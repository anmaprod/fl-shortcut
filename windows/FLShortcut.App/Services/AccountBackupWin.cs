// Sauvegarde en ligne du compte sur Windows, comme AccountBackup.swift du Mac et dans la MÊME sauvegarde : connecté, les
// raccourcis (écrits comme sur le Mac, traduits par MacProfile) et les macros partent en ligne quelques secondes après
// chaque changement ; à la connexion, sur ce PC, un autre PC ou un Mac, la sauvegarde du compte revient (traduite pour
// le clavier d'ici) ; à la déconnexion, ils quittent ce PC (qui revient au premier lancement) et restent dans le
// compte. Jamais rien sans compte. Un ordinateur n'écrase jamais une sauvegarde plus récente faite ailleurs sans le
// demander (révision du serveur), et rien n'est remplacé ici sans copie datée (« avant-compte »), sauf à la
// déconnexion, où tout vient d'être mis en ligne. Le journal ne dit que des états (jamais un raccourci ni un nom).
using FLShortcut.Core;
using FLShortcut.Core.Macros;

namespace FLShortcut.App.Services;

internal sealed class AccountBackupWin
{
    public abstract record State
    {
        public sealed record Off : State;
        public sealed record Checking : State;
        public sealed record UpToDate(string? When) : State;
        public sealed record Pending : State;
        public sealed record Saving : State;
        public sealed record Waiting(string Why) : State;
        public sealed record Choice : State;
        public sealed record Blocked(string Why) : State;
    }

    /// Cet ordinateur et le compte ont chacun leurs changements : l'utilisateur choisit.
    public sealed record Conflict(RemoteBackup Remote, string Here, string Account);

    public abstract record SignOutOutcome
    {
        public sealed record Done : SignOutOutcome;
        public sealed record NotSaved(string Why) : SignOutOutcome;
    }

    private enum Result { Saved, Conflict, Failed }

    private const string CopyLabel = "avant-compte";
    private static readonly TimeSpan Delay = TimeSpan.FromSeconds(4);
    private static readonly TimeSpan FirstRetry = TimeSpan.FromSeconds(30);

    private readonly AppController _app;
    private readonly AccountPage _account;
    private TimeSpan _retry = FirstRetry;
    /// Changements faits ici depuis le lancement : un changement pendant un envoi reste à envoyer.
    private int _changes;
    private bool _syncing;
    private CancellationTokenSource? _scheduled;
    private DateTimeOffset _lastCheck = DateTimeOffset.MinValue;
    private Guid? _user;

    public State Status { get; private set; } = new State.Off();
    public Conflict? Choice { get; private set; }
    /// Information d'une action (sauvegarde reprise…), affichée par la page Mon compte.
    public string? Notice { get; set; }
    /// « 12 raccourcis · 3 macros » : ce qu'il y a dans le compte, d'après la dernière sauvegarde lue ou écrite.
    public string? OnlineSummary { get; private set; }

    public event Action? Changed;

    public AccountBackupWin(AppController app, AccountPage account)
    {
        _app = app;
        _account = account;
        _app.DataChanged += LocalChanged;
        _user = _account.Session?.UserId;
        // Connexion, déconnexion (pas la photo ni le pseudo) : la sauvegarde suit.
        _account.Changed += () =>
        {
            var user = _account.Session?.UserId;
            if (user == _user) return;
            _user = user;
            SessionChanged(user);
        };
        if (_user is not null) _ = Sync();
    }

    // ---------- État ----------

    private AppSettings Settings => _app.Settings;

    private bool Dirty
    {
        get => Settings.BackupDirty;
        set
        {
            Settings.BackupDirty = value;
            Settings.Save();
        }
    }

    /// Dernière révision de ce compte lue ou écrite par ce PC.
    private long? SyncedRevision(Guid account) => Settings.BackupAccount == account.ToString() ? Settings.BackupRevision : null;

    public string HereSummary => _app.HereSummary;

    private void Set(State state)
    {
        Status = state;
        Changed?.Invoke();
    }

    private void MarkSynced(Guid account, long revision, string? when, int changesBefore)
    {
        Settings.BackupAccount = account.ToString();
        Settings.BackupRevision = revision;
        _retry = FirstRetry;
        if (_changes != changesBefore)                       // changé pendant l'envoi : à renvoyer
        {
            Dirty = true;
            Set(new State.Pending());
            Schedule(Delay, Push);
        }
        else
        {
            Dirty = false;
            Set(new State.UpToDate(when ?? DateTimeOffset.Now.ToString("o")));
        }
    }

    public void ForgetSync()
    {
        OnlineSummary = null;
        Settings.BackupAccount = null;
        Settings.BackupRevision = null;
        Settings.BackupDirty = false;
        Settings.Save();
        _scheduled?.Cancel();
        Choice = null;
        _retry = FirstRetry;
        Set(new State.Off());
    }

    // ---------- Événements ----------

    private void SessionChanged(Guid? user)
    {
        if (user is null)
        {
            _scheduled?.Cancel();
            Choice = null;
            Set(new State.Off());                            // session finie : tout reste sur ce PC
        }
        else
        {
            _ = Sync();
        }
    }

    private void LocalChanged()
    {
        _changes++;
        // Données de ce PC rattachées à un compte : changement à envoyer, même hors connexion.
        if (Settings.BackupAccount is null) return;
        Dirty = true;
        if (_account.Session is null || Choice is not null || Status is State.Blocked) return;
        Set(new State.Pending());
        Schedule(Delay, Push);
    }

    private void Schedule(TimeSpan after, Func<Task> work)
    {
        _scheduled?.Cancel();
        var cts = _scheduled = new CancellationTokenSource();
        _ = Later();

        async Task Later()
        {
            try { await Task.Delay(after, cts.Token); }
            catch (TaskCanceledException) { return; }
            await work();
        }
    }

    /// Page Mon compte ouverte : relit le compte s'il n'a pas été vu depuis 2 minutes (changé ailleurs ?).
    public async Task RefreshIfStale()
    {
        if (_account.Session is null || DateTimeOffset.Now - _lastCheck < TimeSpan.FromMinutes(2)) return;
        await Sync();
    }

    // ---------- Synchronisation ----------

    /// Retrouve ce PC et le compte : envoie, reprend ou demande (BackupRules), puis met l'état à jour.
    public async Task Sync()
    {
        if (_account.Session is null || _syncing || Choice is not null || HelpPage.Server is null) return;
        _syncing = true;
        try
        {
            _lastCheck = DateTimeOffset.Now;
            if (await SyncOnce() == Result.Conflict) await SyncOnce();   // changé ailleurs pendant l'envoi : relu une fois
        }
        finally { _syncing = false; }
    }

    private static async Task<string> Body(HttpRequestMessage request)
    {
        var (status, body) = await AccountPage.Send(request);
        if (status is < 200 or >= 300) throw new AccountPage.ServerError(AccountRequests.ServerMessage(body, status), status);
        return body;
    }

    private async Task<AccountSession> SessionOrFail() =>
        await _account.FreshSession() ?? throw new AccountPage.ServerError(Loc.T("Session expirée : reconnecte-toi."), 401);

    private async Task<Result> SyncOnce()
    {
        Set(new State.Checking());
        try
        {
            var server = HelpPage.Server!;
            var session = await SessionOrFail();
            var account = session.UserId;
            var synced = SyncedRevision(account);
            // Fichiers de ce PC illisibles au lancement (leur copie est déjà gardée) : la sauvegarde du compte les
            // remplace ; rien n'est envoyé à leur place.
            if (_app.LocalUnreliable && BackupRequests.DecodeBackup(await Body(BackupRequests.Get(server, session))) is { } kept)
            {
                Restore(kept, account, keepCopy: false);
                return Result.Saved;
            }
            // Vérification rapide : le compte n'a pas bougé depuis ce PC.
            if (synced is { } s && BackupRequests.DecodeRevision(await Body(BackupRequests.Revision(server, session))) is { } quick
                && quick.Revision == s)
            {
                if (Dirty) return await Save(s, force: false);
                OnlineSummary ??= HereSummary;               // même révision : le même contenu
                Set(new State.UpToDate(quick.UpdatedAt));
                return Result.Saved;
            }
            var remote = BackupRequests.DecodeBackup(await Body(BackupRequests.Get(server, session)));
            var before = _changes;
            var decision = BackupRules.Decide(remote?.Revision, remote is not null && _app.SameAs(remote.Content),
                                              _app.Untouched, synced, Dirty);
            AppLog.Write("BACKUP", $"décision {decision}");
            switch (decision)
            {
                case BackupDecision.Upload:
                    return await Save(remote?.Revision ?? 0, force: false);
                case BackupDecision.InSync when remote is not null:
                    OnlineSummary = BackupCodec.Summary(remote.Content, _app.KeyLayout);
                    MarkSynced(account, remote.Revision, remote.UpdatedAt, before);
                    break;
                case BackupDecision.Restore when remote is not null:
                    Restore(remote, account, keepCopy: !_app.Untouched);
                    break;
                case BackupDecision.Ask when remote is not null:
                    OnlineSummary = BackupCodec.Summary(remote.Content, _app.KeyLayout);
                    Choice = new Conflict(remote, HereSummary, OnlineSummary);
                    Set(new State.Choice());
                    break;
            }
            return Result.Saved;
        }
        catch (Exception e) when (IsHandled(e))
        {
            Handle(e);
            return Result.Failed;
        }
    }

    private static bool IsHandled(Exception e) =>
        e is AccountPage.ServerError or BackupFailure or FormatException or System.Text.Json.JsonException
            or KeyNotFoundException or InvalidOperationException;

    /// Envoie ce qu'il y a sur ce PC si le compte est toujours à la révision `base` (ou quoi qu'il y ait : `force`).
    private async Task<Result> Save(long @base, bool force)
    {
        Set(new State.Saving());
        var before = _changes;
        try
        {
            var session = await SessionOrFail();
            var content = _app.BackupContent();
            var (status, body) = await AccountPage.Send(BackupRequests.Save(HelpPage.Server!, session, content, @base, force, HelpPage.AppVersion));
            if (status is < 200 or >= 300)
            {
                if (BackupRequests.IsConflict(body)) return Result.Conflict;
                throw new AccountPage.ServerError(AccountRequests.ServerMessage(body, status), status);
            }
            OnlineSummary = HereSummary;
            MarkSynced(session.UserId, BackupRequests.DecodeSaved(body), DateTimeOffset.Now.ToString("o"), before);
            AppLog.Write("BACKUP", "envoyée");
            return Result.Saved;
        }
        catch (Exception e) when (IsHandled(e))
        {
            Handle(e);
            return Result.Failed;
        }
    }

    /// Envoi après un changement (quelques secondes après le dernier).
    private async Task Push()
    {
        if (!Dirty || _account.Session?.UserId is not { } user || _syncing || Choice is not null) return;
        if (_app.LocalUnreliable || SyncedRevision(user) is not { } synced)
        {
            await Sync();                                    // relu et décidé par Sync
            return;
        }
        _syncing = true;
        Result result;
        try { result = await Save(synced, force: false); }
        finally { _syncing = false; }
        if (result == Result.Conflict) await Sync();
    }

    /// La sauvegarde du compte remplace ce PC (copie datée de ce qu'il y avait, s'il y avait quelque chose à soi).
    private void Restore(RemoteBackup remote, Guid account, bool keepCopy)
    {
        var (shortcuts, macros) = BackupCodec.Decode(remote.Content, _app.KeyLayout);
        if (_app.MacrosWritesDisabled) throw BackupFailure.Custom(MacroLibraryStore.WritesDisabledMessage);
        if (keepCopy && !_app.KeepCopies(CopyLabel)) throw BackupFailure.CopyFailed;
        _app.ReplaceAllData(shortcuts, macros);
        // Les couleurs récentes du compte reviennent (aucune en ligne : celles de ce PC restent).
        var colors = BackupCodec.Colors(remote.Content.Profile);
        if (colors.Count > 0) _app.ReplaceRecentColors(colors);
        OnlineSummary = BackupRules.Summary(shortcuts.Count, macros.Count);
        MarkSynced(account, remote.Revision, remote.UpdatedAt, _changes);
        Notice = Loc.F("Ta sauvegarde est revenue : %@.", OnlineSummary);
        AppLog.Write("BACKUP", "reprise du compte");
    }

    private void Handle(Exception error)
    {
        AppLog.Write("BACKUP", "échec : " + error.GetType().Name);
        if (error is BackupFailure failure)
        {
            Set(new State.Blocked(failure.Message));
            return;
        }
        if (_account.Session is null)
        {
            Set(new State.Off());
            return;
        }
        // Refus définitif du serveur (trop grande, compte supprimé ailleurs…) : pas de nouvel essai sans fin.
        if (error is AccountPage.ServerError { Status: >= 400 and < 500 } refused && refused.Status is not (401 or 408 or 429))
        {
            Set(new State.Blocked(Loc.F("Sauvegarde refusée par le serveur : %@", refused.Message)));
            return;
        }
        var why = error is AccountPage.ServerError { Status: 0 }
            ? Loc.T("Pas de connexion : la sauvegarde partira dès que possible.")
            : Loc.F("Sauvegarde impossible pour l'instant : %@", error.Message);
        Set(new State.Waiting(why));
        var wait = _retry;
        _retry = TimeSpan.FromSeconds(Math.Min(_retry.TotalSeconds * 2, 900));
        Schedule(wait, Sync);
    }

    // ---------- Choix, déconnexion ----------

    /// Choix de l'utilisateur quand ce PC et le compte ont chacun leurs changements.
    public async Task Resolve(bool keepAccount)
    {
        if (Choice is not { } choice || _account.Session?.UserId is not { } account) return;
        Choice = null;
        if (keepAccount)
        {
            try { Restore(choice.Remote, account, keepCopy: true); }
            catch (BackupFailure e) { Handle(e); }
        }
        else
        {
            _syncing = true;
            Result result;
            try { result = await Save(choice.Remote.Revision, force: true); }
            finally { _syncing = false; }
            if (result == Result.Conflict) await Sync();
        }
        Changed?.Invoke();
    }

    /// Envoi tout de suite (bouton « Sauvegarder »).
    public async Task SaveNow()
    {
        _scheduled?.Cancel();
        await Sync();
    }

    /// Déconnexion : d'abord tout en ligne, puis raccourcis et macros retirés de ce PC (ils restent dans le compte).
    /// `evenIfNotSaved` : l'utilisateur accepte de perdre ce qui n'a pas pu partir.
    public async Task<SignOutOutcome> SignOut(bool evenIfNotSaved)
    {
        _scheduled?.Cancel();
        while (_syncing) await Task.Delay(50);              // un envoi en cours se termine d'abord
        var session = _account.Session;
        if (!evenIfNotSaved && session is null && (Dirty || Settings.BackupAccount is null))
            return new SignOutOutcome.NotSaved(Loc.T("Ta session a expiré : reconnecte-toi pour mettre en ligne tes derniers changements."));
        if (!evenIfNotSaved && session is not null)
        {
            if (Choice is null && (Dirty || SyncedRevision(session.UserId) is null)) await Sync();
            if (Choice is not null)
                return new SignOutOutcome.NotSaved(Loc.T("Choisis d'abord quelle version garder : celle de ce PC ou celle de ton compte."));
            if (Dirty || SyncedRevision(session.UserId) is null)
            {
                return Status switch
                {
                    State.Waiting w => new SignOutOutcome.NotSaved(w.Why),
                    State.Blocked b => new SignOutOutcome.NotSaved(b.Why),
                    _ => new SignOutOutcome.NotSaved(Loc.T("Tes derniers changements ne sont pas encore en ligne.")),
                };
            }
        }
        await _account.SignOutNow();
        _app.ReplaceAllData(ProfilePreset.Recommended.Shortcuts(), new List<MacroDoc>());
        _app.ReplaceRecentColors(Array.Empty<string>());   // elles restent dans le compte, comme le reste
        ForgetSync();
        Notice = null;
        AppLog.Write("BACKUP", "déconnecté : ce PC revient au premier lancement");
        return new SignOutOutcome.Done();
    }
}
