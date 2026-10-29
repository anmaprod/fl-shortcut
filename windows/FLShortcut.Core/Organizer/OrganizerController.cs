// Organiser : le contrôleur de sa fenêtre (sans la fenêtre). Lien avec FL installé à la demande (écran d'installation
// s'il manque), attente de FL (à redémarrer, à ouvrir, lecture à arrêter) avec nouvel essai tout seul, analyse de tout
// le projet sur son fichier, aperçu par famille (couleur ou dégradé, ce qu'est chaque son, son nom écrit, sa piste du
// Mixer, le départ de chaque famille, l'ordre des familles), un seul « Organiser », puis « Revenir comme avant » et
// « Pas content ? ». Miroir de OrganizerController (Sources/FLShortcut/OrganizerWindow.swift).
using System.Text.Json;

namespace FLShortcut.Core.Organizer;

/// État du lien avec FL à l'ouverture de l'Organiser.
public abstract record OrganizerLinkState
{
    /// Script jamais installé : écran d'installation.
    public sealed record NotInstalled : OrganizerLinkState;
    /// `WarmUp` : secondes à attendre que FL voie les ports et charge le script.
    public sealed record Ready(double WarmUp) : OrganizerLinkState;
    /// Script absent de FL Studio, remis à l'instant : FL ne le lira qu'à son prochain lancement.
    public sealed record Restored : OrganizerLinkState;
}

/// Ce que l'Organiser attend de FL : il réessaie tout seul et continue dès que c'est bon.
public enum OrganizerWait { RestartFl, NoResponse, WrongInput, OpenFl, StopPlayback }

public abstract record OrganizerPhase
{
    public sealed record Starting : OrganizerPhase;
    public sealed record Setup : OrganizerPhase;
    public sealed record Waiting(OrganizerWait Reason) : OrganizerPhase;
    public sealed record Listening(int Done, int Total) : OrganizerPhase;
    public sealed record Preview : OrganizerPhase;
    public sealed record Applying : OrganizerPhase;
    public sealed record Applied(OrganizerError? Error) : OrganizerPhase;
    public sealed record Undoing : OrganizerPhase;
    public sealed record Undone(OrganizerError? Error) : OrganizerPhase;
    public sealed record Failed(string Message) : OrganizerPhase;
}

/// Ce dont l'Organiser a besoin du monde réel (des faux dans les essais).
public sealed class OrganizerEnvironment
{
    public required Func<IOrganizerLink> Link { get; init; }
    /// La capture du son de FL, ou la raison de l'impossibilité (FL fermé…).
    public required Func<(IAudioSource? Source, OrganizerError? Error)> Audio { get; init; }
    public required Func<OrganizerSession.Classify> Classify { get; init; }
    /// Alt+↑ envoyé à FL : `MoveUp(link)(n)` renvoie le nombre de pas faits ; Alt+← dans le Mixer.
    public required Func<IOrganizerLink, Func<int, int>> MoveUp { get; init; }
    public Func<IOrganizerLink, Func<int, int>> MoveLeft { get; init; } = _ => _ => 0;
    /// Le fichier du projet ouvert dans FL (enregistré par FL, lu, sa copie rangée ouverte).
    public required Func<ProjectFileAccess> ProjectFiles { get; init; }
    public OrganizerSession.Timing Timing { get; init; } = new();
    public Action<double> Sleep { get; init; } = s => Thread.Sleep(TimeSpan.FromSeconds(s));
    public Func<bool> EscapePressed { get; init; } = () => false;
    public Func<Dictionary<SoundFamily, FamilyStyle>> LoadStyles { get; init; } = () => FamilyStyles.Initial.ToDictionary(kv => kv.Key, kv => kv.Value);
    public Action<IReadOnlyDictionary<SoundFamily, FamilyStyle>> SaveStyles { get; init; } = _ => { };
    /// Ordre des familles glissées dans l'aperçu, gardé d'un projet à l'autre.
    public Func<IReadOnlyList<SoundFamily>> LoadFamilyOrder { get; init; } = () => SoundFamilies.Order;
    public Action<IReadOnlyList<SoundFamily>> SaveFamilyOrder { get; init; } = _ => { };
    /// Icône posée sur l'élément sélectionné par la fenêtre de FL ; null si c'est fait.
    public Func<FlIcon, OrganizerError?> PlaceIcon { get; init; } = _ => null;
    /// Avant chaque analyse : lien installé ? Ports MIDI prêts ?
    public Func<OrganizerLinkState> PrepareLink { get; init; } = () => new OrganizerLinkState.Ready(0);
    /// « Installer le lien » : vrai s'il est installé ; « Autre dossier de FL… ».
    public Func<bool> InstallLink { get; init; } = () => true;
    public Func<bool> InstallLinkElsewhere { get; init; } = () => true;
    /// En attente de FL : nouvel essai, tout seul, à cet intervalle (secondes).
    public double WaitInterval { get; init; } = 2;
    /// Script dans FL Studio : où il est, et s'il y est encore (null : aucun) ; le montrer dans l'Explorateur.
    public Func<(string Path, bool Present)?> ScriptPlace { get; init; } = () => null;
    public Action<string> Reveal { get; init; } = _ => { };
    /// Le script a dit être posé sur une autre entrée MIDI que « FL Shortcuts ».
    public Func<bool> WrongInput { get; init; } = () => false;
    public Func<OrganizerSession.NameDrum?> NameDrum { get; init; } = () => (_, _) => SoundKind.Perc;
    public Func<OrganizerSession.NameMelody?> NameMelody { get; init; } = () => null;
    public Func<OrganizerSession.NameKind?> NameKind { get; init; } = () => null;
    public Func<OrganizerSession.Fingerprint?> Fingerprint { get; init; } = () => null;
    /// Les corrections gardées sur ce PC (et l'accord pour les partager) ; null : rien n'est appris.
    public Func<CorrectionsIA?> Corrections { get; init; } = () => null;
    /// Une correction partagée (accord donné, JSON) envoyée au serveur, en tâche de fond.
    public Action<string> ShareCorrection { get; init; } = _ => { };
    /// « Pas content ? » : le message pour l'équipe et le diagnostic (nombres), envoyés en tâche de fond.
    public Action<string, string> SendFeedback { get; init; } = (_, _) => { };
    public Func<OrganizerSession.SoundFile?> SoundFile { get; init; } = () => null;
    /// En-tête du diagnostic : versions et état du lien (aucun nom).
    public Func<string> About { get; init; } = () => "";
    public Action<string> Copy { get; init; } = _ => { };
    /// FL mis devant (ses touches et sa page devant en dépendent).
    public Action FocusFl { get; init; } = () => { };
    /// Alt+Suppr envoyé à FL (Channel rack devant) ; faux si rien n'a pu être envoyé.
    public Func<IOrganizerLink, Func<bool>> DeleteSelected { get; init; } = _ => () => false;
    /// « Choisir le fichier… » : l'utilisateur montre le projet ouvert dans FL ; faux : annulé.
    public Func<bool> ChooseProject { get; init; } = () => false;
    /// Une copie rangée faite et ouverte dans FL (original, copie), à valider à la réouverture de FL Shortcuts ; puis
    /// « Revenir comme avant » réussi sur cette copie.
    public Action<string, string> CopyMade { get; init; } = (_, _) => { };
    public Action<string> CopyUndone { get; init; } = _ => { };
    public string AppVersion { get; init; } = "?";
    /// Fil de l'interface (les essais : tout de suite).
    public Action<Action> Post { get; init; } = a => a();
    /// Travail long, hors du fil de l'interface, un à la fois (les essais : tout de suite).
    public Action<Action> Background { get; init; } = a => a();
    /// `After(secondes, action)` : sur le fil de l'interface, plus tard.
    public Action<double, Action> After { get; init; } = (_, _) => { };
}

public sealed class OrganizerController
{
    private readonly OrganizerEnvironment _env;
    private IOrganizerLink? _link;
    private OrganizerSession? _session;
    private OrganizerSnapshot? _snapshot;
    private bool _closed;
    private int _runToken;
    private int _waitSerial;

    /// Chaque changement à montrer (sur le fil de l'interface).
    public event Action? Changed;
    /// Appelé une fois, à la fermeture.
    public Action? OnClose { get; set; }

    public OrganizerPhase Phase { get; private set; } = new OrganizerPhase.Starting();
    /// Famille et sorte de chaque son du Channel rack (index du canal), modifiables dans l'aperçu.
    public Dictionary<int, SoundFamily> Families { get; private set; } = new();
    public Dictionary<int, SoundKind> Kinds { get; private set; } = new();
    public Dictionary<SoundFamily, FamilyStyle> Styles { get; private set; }
    public OrganizerResult? Result { get; private set; }
    public OrganizerOptions Options { get; private set; }
    /// Noms écrits dans l'aperçu (« Écrire… ») ; pistes du Mixer choisies (la case de FL), par index du canal.
    public Dictionary<int, string> Names { get; } = new();
    public Dictionary<int, int> Slots { get; } = new();
    public ApplyOutcome? LastApply { get; private set; }
    /// Où en est l'application (« FL ouvre la copie rangée… 12 s ») ; null : le texte général.
    public string? ApplyStep { get; private set; }
    public bool ShowLinkHelp { get; set; }
    public OrganizerDiagnostics? Diagnostics { get; private set; }
    public bool Copied { get; private set; }
    /// Le fichier du projet reste introuvable : « Choisir le fichier… » le fait montrer.
    public bool ProjectMissing { get; private set; }
    /// Sons corrigés que l'IA a retenus (aperçu et « Pas content ? »).
    public int Learned { get; private set; }
    public bool FeedbackSent { get; private set; }

    public OrganizerController(OrganizerEnvironment env)
    {
        _env = env;
        Styles = env.LoadStyles();
        Options = new OrganizerOptions { FamilyOrder = OrganizerOptions.CompleteOrder(env.LoadFamilyOrder()) };
    }

    /// Le titre seul, comme le Mac (maquette du 28/10).
    public string Title => Loc.T("Organiser");

    /// Playlist trop grande pour être rangée dans la copie (comme le Mac) : l'aperçu propose de décocher « Playlist ».
    public bool PlaylistTooBig => OrganizesCopy && Options.Playlist && Plan.Layout is null;

    /// Pur (testé, comme OrganizerView.familyColumns du Mac) : les familles en `count` colonnes, dans l'ordre (la
    /// première colonne de haut en bas, puis la suivante), coupées là où les colonnes ont la hauteur la plus proche
    /// (`size` : nombre de sons d'une famille ; l'en-tête compte pour deux lignes).
    public static List<List<T>> FamilyColumns<T>(IReadOnlyList<T> families, int count, Func<T, int> size)
    {
        if (count < 2 || families.Count < 2) return new List<List<T>> { families.ToList() };
        var heights = families.Select(f => size(f) + 2).ToList();
        var total = heights.Sum();
        var best = 1;
        var bestGap = int.MaxValue;
        var running = 0;
        for (var cut = 1; cut < families.Count; cut++)
        {
            running += heights[cut - 1];
            var gap = Math.Abs(total - 2 * running);
            if (gap < bestGap)
            {
                best = cut;
                bestGap = gap;
            }
        }
        return new List<List<T>> { families.Take(best).ToList(), families.Skip(best).ToList() };
    }

    private void Raise() => Changed?.Invoke();

    private void SetPhase(OrganizerPhase phase)
    {
        Phase = phase;
        Raise();
    }

    public void Start()
    {
        if (Phase is not OrganizerPhase.Starting) return;
        Begin(false);
    }

    /// `quiet` : nouvel essai pendant une attente ; l'écran d'attente reste jusqu'au premier son écouté.
    private void Begin(bool quiet)
    {
        if (_closed) return;
        double warmUp;
        switch (_env.PrepareLink())
        {
            case OrganizerLinkState.NotInstalled:
                SetPhase(new OrganizerPhase.Setup());
                return;
            case OrganizerLinkState.Restored:
                Wait(OrganizerWait.RestartFl);
                return;
            case OrganizerLinkState.Ready r:
                warmUp = r.WarmUp;
                break;
            default:
                return;
        }
        var (audio, audioError) = _env.Audio();
        if (audio is null)
        {
            var error = audioError ?? OrganizerError.FlClosed;
            if (WaitReason(error, _env.WrongInput()) is { } reason) Wait(reason);
            else SetPhase(new OrganizerPhase.Failed(error.UserMessage));
            return;
        }
        if (!quiet) _env.FocusFl();
        _session?.Cancel();
        var token = ++_runToken;
        var link = _env.Link();
        var session = new OrganizerSession(link, audio, _env.Classify(), _env.ProjectFiles(), _env.NameDrum(), _env.NameMelody(),
            _env.NameKind(), _env.Fingerprint(), _env.Timing, _env.Sleep, _env.EscapePressed, _env.SoundFile(),
            (done, total) => _env.Post(() =>
            {
                if (_runToken == token) Listening(done, total);
            }));
        _link = link;
        _session = session;
        if (!quiet) SetPhase(new OrganizerPhase.Listening(0, 0));
        var sleep = _env.Sleep;
        _env.Background(() =>
        {
            if (warmUp > 0) sleep(warmUp);
            var outcome = session.Run();
            var diagnostics = session.Diagnostics;
            _env.Post(() =>
            {
                if (_runToken != token) return;
                Diagnostics = diagnostics;
                FinishListening(outcome.Result, outcome.Error);
            });
        });
    }

    /// Ce qui se règle dans FL : l'Organiser attend et continue tout seul. null : un vrai échec, dit tel quel.
    public static OrganizerWait? WaitReason(OrganizerError error, bool wrongInput = false) => error.Kind switch
    {
        OrganizerError.Kinds.NoResponse => wrongInput ? OrganizerWait.WrongInput : OrganizerWait.NoResponse,
        OrganizerError.Kinds.OutdatedScript => OrganizerWait.RestartFl,
        OrganizerError.Kinds.FlClosed => OrganizerWait.OpenFl,
        OrganizerError.Kinds.Refused when error.Reason == 4 => OrganizerWait.StopPlayback,
        _ => null,
    };

    private void Wait(OrganizerWait reason)
    {
        SetPhase(new OrganizerPhase.Waiting(reason));
        var serial = ++_waitSerial;
        _env.After(_env.WaitInterval, () =>
        {
            if (_closed || _waitSerial != serial || Phase is not OrganizerPhase.Waiting) return;
            Begin(true);
        });
    }

    /// Texte à envoyer quand ça ne marche pas : versions, état, et ce que l'écoute a fait — des nombres seulement.
    public string DiagnosticText
    {
        get
        {
            var lines = new List<string> { "FL Shortcuts · diagnostic de l'Organiser (Windows)", _env.About(), $"étape={PhaseCode(Phase)}" };
            if (Diagnostics is { } d) lines.Add(d.Text);
            if (LastApply is { Trace.Count: > 0 } a) lines.Add("application=" + string.Join(" ; ", a.Trace));
            return string.Join("\n", lines.Where(l => l.Length > 0));
        }
    }

    public void CopyDiagnostic()
    {
        _env.Copy(DiagnosticText);
        Copied = true;
        Raise();
        _env.After(2, () =>
        {
            Copied = false;
            Raise();
        });
    }

    /// Étape en un mot (diagnostic) : jamais le texte d'un message qui pourrait citer un nom.
    public static string PhaseCode(OrganizerPhase phase) => phase switch
    {
        OrganizerPhase.Starting => "début",
        OrganizerPhase.Setup => "installation",
        OrganizerPhase.Waiting w => "attente-" + SoundFamilies.Lower(w.Reason.ToString()),
        OrganizerPhase.Listening l => $"écoute-{l.Done}/{l.Total}",
        OrganizerPhase.Preview => "aperçu",
        OrganizerPhase.Applying => "application",
        OrganizerPhase.Applied a => "appliqué" + (a.Error is { } e ? "-" + e.Code : ""),
        OrganizerPhase.Undoing => "retour",
        OrganizerPhase.Undone u => "revenu" + (u.Error is { } e2 ? "-" + e2.Code : ""),
        _ => "échec",
    };

    /// « Réessayer » : après un échec, ou tout de suite pendant une attente.
    public bool CanRetry => Phase is OrganizerPhase.Setup or OrganizerPhase.Failed or OrganizerPhase.Waiting && _snapshot is null;

    public void Retry()
    {
        if (!CanRetry || _closed) return;
        _waitSerial++;
        ProjectMissing = false;
        Learned = 0;
        FeedbackSent = false;
        Result = null;
        Families = new Dictionary<int, SoundFamily>();
        Kinds = new Dictionary<int, SoundKind>();
        Names.Clear();
        Slots.Clear();
        Phase = new OrganizerPhase.Starting();
        Start();
    }

    /// « Choisir le fichier… » : le projet montré, l'analyse repart dessus.
    public void ChooseProject()
    {
        if (!ProjectMissing || !_env.ChooseProject()) return;
        Retry();
    }

    /// Lien installé en un clic : FL doit redémarrer pour le lire, l'Organiser attend et continue tout seul.
    public void InstallLink()
    {
        if (!_env.InstallLink() || _closed) return;
        Wait(OrganizerWait.RestartFl);
    }

    public (string Path, bool Present)? ScriptPlace => _env.ScriptPlace();

    public void RevealScript()
    {
        if (_env.ScriptPlace() is { Present: true } place) _env.Reveal(place.Path);
    }

    public void InstallLinkElsewhere()
    {
        if (!_env.InstallLinkElsewhere() || _closed) return;
        Wait(OrganizerWait.RestartFl);
    }

    private void Listening(int done, int total)
    {
        if (Phase is OrganizerPhase.Listening or OrganizerPhase.Waiting) SetPhase(new OrganizerPhase.Listening(done, total));
    }

    private void FinishListening(OrganizerResult? result, OrganizerError? error)
    {
        _session = null;
        if (_closed) return;
        if (result is not null)
        {
            Result = result;
            Families = Organize.FamiliesOf(result);
            Kinds = Organize.KindsOf(result);
            if (Families.Count > 0 || !Plan.IsEmpty) SetPhase(new OrganizerPhase.Preview());
            else SetPhase(new OrganizerPhase.Failed(Loc.T("Aucun son à organiser dans ce projet.")));
            return;
        }
        var e = error ?? OrganizerError.Failed("?");
        ProjectMissing = e.Is(OrganizerError.Kinds.ProjectNotFound);
        if (WaitReason(e, _env.WrongInput()) is { } reason) Wait(reason);
        else SetPhase(new OrganizerPhase.Failed(e.UserMessage));
    }

    /// Ce que « Organiser » fera, d'après ce qu'est chaque son (modifiable), les noms écrits, les places et les options.
    public OrganizerPlan Plan => Result is { } result
        ? OrganizerPlan.Make(result, Families, Kinds, Styles, Options, Names, Slots)
        : new OrganizerPlan();

    /// Familles présentes, dans l'ordre choisi (les familles absentes sont sautées).
    public List<SoundFamily> PresentFamilies
    {
        get
        {
            var used = Families.Values.ToHashSet();
            return Options.FamilyOrder.Where(used.Contains).ToList();
        }
    }

    public void SetOptions(OrganizerOptions options)
    {
        Options = options;
        Raise();
    }

    /// Une famille glissée sur une autre (comme un dossier) : elle prend sa place, l'autre se décale vers là d'où elle
    /// vient. Tout le projet suit ce nouvel ordre.
    public void MoveFamily(SoundFamily family, SoundFamily onto) =>
        SetOptions(Options with { FamilyOrder = Moving(family, onto, Options.FamilyOrder) });

    /// « Monter / Descendre la famille » : d'une famille présente vers le haut (-1) ou le bas (+1).
    public void ShiftFamily(SoundFamily family, int step)
    {
        var present = PresentFamilies;
        var at = present.IndexOf(family);
        if (at < 0 || at + step < 0 || at + step >= present.Count) return;
        MoveFamily(family, present[at + step]);
    }

    /// Pur (testé) : l'ordre des familles après en avoir glissé une sur une autre.
    public static List<SoundFamily> Moving(SoundFamily family, SoundFamily onto, IReadOnlyList<SoundFamily> order)
    {
        var out_ = order.ToList();
        var from = out_.IndexOf(family);
        var to = out_.IndexOf(onto);
        if (family == onto || from < 0 || to < 0) return out_;
        out_.RemoveAt(from);
        var place = out_.IndexOf(onto);
        out_.Insert(from < to ? place + 1 : place, family);
        return out_;
    }

    // ---------- Places dans le Mixer (demande du propriétaire du 25/10) ----------

    /// Dernière piste du Mixer de ce projet (la toute dernière est « Current »).
    public int MixerLast => Math.Max(1, Math.Min((Result?.Mixer.Count ?? 2) - 2, FamilyStyles.MaxMixerTrack));

    /// La piste du Mixer où finira ce son (ce que montre sa case) ; null : aucune.
    public int? MixerSlot(int index, OrganizerPlan? plan = null)
    {
        if (Result?.Channels.FirstOrDefault(c => c.Index == index) is not { } channel) return null;
        var mixer = (plan ?? Plan).Mixer;
        var track = mixer.Links.TryGetValue(index, out var l) ? l : channel.MixerTrack;
        if (track < 1) return null;
        var place = mixer.Final.IndexOf(track);
        return place >= 0 ? place + 1 : track;
    }

    /// Les pistes du Mixer où finira la famille (son bus compris ; la 808 avec les drums).
    public (int First, int Last)? MixerRange(SoundFamily family, OrganizerPlan? plan = null)
    {
        var mixer = (plan ?? Plan).Mixer;
        var places = mixer.Final.Select((track, place) => (track, place))
            .Where(x => mixer.Verdicts.TryGetValue(x.track, out var v) && v.BusFamily == family).Select(x => x.place + 1).ToList();
        return places.Count == 0 ? null : (places.Min(), places.Max());
    }

    /// Points de souris par numéro, comme la case de FL (tirer vers le haut : plus grand).
    public const double SlotStep = 6;

    /// Pur (testé) : le numéro après avoir tiré la case de `dy` points (vers le haut : négatif, plus grand).
    public static int DraggedSlot(int from, double dy, int last) =>
        Math.Clamp(from + (int)Math.Truncate(-dy / SlotStep), 1, Math.Max(last, 1));

    public void SetSlot(int index, int? slot)
    {
        if (slot is { } n) Slots[index] = Math.Clamp(n, 1, MixerLast);
        else Slots.Remove(index);
        Raise();
    }

    public void SetMixerStart(SoundFamily family, int? start) =>
        UpdateStyle(family, s => s with { MixerStart = start is { } n ? Math.Clamp(n, 1, MixerLast) : null });

    /// Le Mixer rangé tout seul de nouveau : plus aucune place choisie (sons et familles).
    public void AutoArrange()
    {
        Slots.Clear();
        foreach (var family in SoundFamilies.Order.Where(f => StyleOf(f).MixerStart is not null).ToList())
            Styles[family] = StyleOf(family) with { MixerStart = null };
        Raise();
    }

    public bool PlacesChosen => Slots.Count > 0 || SoundFamilies.Order.Any(f => StyleOf(f).MixerStart is not null);

    /// « Écrire… » : le nom que la personne donne à ce son ; vide : le nom automatique.
    public void SetName(int index, string? name)
    {
        var trimmed = (name ?? "").Trim();
        if (trimmed.Length == 0) Names.Remove(index);
        else Names[index] = trimmed.Length > 64 ? trimmed[..64] : trimmed;
        Raise();
    }

    public sealed record Member(int Id, string Name, bool TestNotes, bool ByName, string? NewName, SoundKind? Kind, int? Slot,
        bool Pinned, bool Written);

    /// Sons d'une famille, dans l'ordre où ils finiront dans le Channel rack.
    public List<Member> Members(SoundFamily family)
    {
        if (Result is not { } result) return new List<Member>();
        var channels = result.Channels.OrderBy(c => c.Index).ToList();
        var order = Organize.RackPlan(channels, Families, Kinds, Options).Final;
        var byIndex = result.Items.ToDictionary(i => i.Index);
        var plan = Plan;
        var planned = plan.Rack.Names;
        var out_ = new List<Member>();
        foreach (var index in order)
        {
            if (!Families.TryGetValue(index, out var f) || f != family || !byIndex.TryGetValue(index, out var item)) continue;
            var newName = Names.TryGetValue(index, out var w) ? w : planned.TryGetValue(index, out var p) ? p : null;
            out_.Add(new Member(index, item.Name, item.TestNotes, item.ByName, newName == item.Name ? null : newName, KindOf(index),
                MixerSlot(index, plan), Slots.ContainsKey(index), Names.ContainsKey(index)));
        }
        return out_;
    }

    public SoundKind? KindOf(int index) => Organize.KindOf(index, Families, Kinds);

    /// Changé dans l'aperçu : une famille seule (ce qu'était le son est oublié), ou ce qu'est le son (sa famille suit).
    public void SetFamily(int index, SoundFamily family)
    {
        Families[index] = family;
        Kinds.Remove(index);
        Raise();
    }

    public void SetKind(int index, SoundKind kind)
    {
        Families[index] = kind.Family();
        Kinds[index] = kind;
        Raise();
    }

    /// Couleur prévue de chaque son du Channel rack (dégradés répartis dans l'ordre final).
    public Dictionary<int, RgbColor> PlannedColors
    {
        get
        {
            if (Result is not { } result) return new Dictionary<int, RgbColor>();
            var channels = result.Channels.OrderBy(c => c.Index).ToList();
            var order = Organize.RackPlan(channels, Families, Kinds, Options).Final;
            return Organize.PlannedColors(Families, Styles, order);
        }
    }

    /// Analyse sur le fichier : tout se fait dans une copie rangée du projet.
    public bool OrganizesCopy => Result?.Project is not null;

    public FamilyStyle StyleOf(SoundFamily family) =>
        Styles.TryGetValue(family, out var s) ? s : FamilyStyles.Initial.TryGetValue(family, out var i) ? i : new FamilyStyle(new RgbColor(0x8A, 0x8F, 0x98));

    public void UpdateStyle(SoundFamily family, Func<FamilyStyle, FamilyStyle> change)
    {
        Styles[family] = change(StyleOf(family));
        Raise();
    }

    /// Une ligne par page de FL touchée, pour l'aperçu : combien d'éléments seront rangés, colorés, renommés.
    public List<string> Summary
    {
        get
        {
            var plan = Plan;
            var out_ = new List<string>();
            if (plan.Deleted.Count > 0)
                out_.Add(OrganizesCopy
                    ? Loc.F("%lld sons sans aucune note supprimés du Channel rack de la copie rangée", plan.Deleted.Count)
                    : Loc.F("%lld sons sans aucune note supprimés du Channel rack (on ne peut pas les remettre avec « Revenir comme avant »)", plan.Deleted.Count));
            if (Options.Rack && !plan.Rack.IsEmpty)
                out_.Add(Loc.F("Channel rack : %lld sons regroupés et colorés, %lld renommés", plan.Rack.Colors.Count, plan.Rack.Names.Count));
            if (Options.Patterns && !plan.Patterns.IsEmpty)
                out_.Add(Loc.F("Patterns : %lld colorés, %lld renommés", plan.Patterns.Colors.Count, plan.Patterns.Names.Count));
            if (Options.Mixer && !plan.Mixer.IsEmpty)
            {
                var buses = plan.Mixer.Buses.Count;
                var tracks = plan.Mixer.Verdicts.Count - buses;
                out_.Add(buses > 0
                    ? Loc.F("Mixer : %lld pistes dans l'ordre du Channel rack, %lld bus (un par famille), %lld renommées", tracks, buses, plan.Mixer.Names.Count)
                    : Loc.F("Mixer : %lld pistes dans l'ordre du Channel rack, %lld renommées", tracks, plan.Mixer.Names.Count));
                if (plan.Mixer.Links.Count > 0)
                    out_.Add(Loc.F("%lld sons envoyés au Master reliés chacun à une piste libre du Mixer", plan.Mixer.Links.Count));
                if (plan.Mixer.Resets.Count > 0)
                    out_.Add(Loc.F("%lld pistes du Mixer sans son remises comme neuves (nom et couleur de FL)", plan.Mixer.Resets.Count));
            }
            if (plan.Deleted.Count == 0 && Result?.Unused.Count is > 0 and var unused)
                out_.Add(Loc.F("%lld sons sans aucune note laissés de côté (ni rangés, ni colorés, ni renommés)", unused));
            if (Options.Playlist && !plan.Playlist.IsEmpty)
                out_.Add(plan.Playlist.Moves.Count == 0
                    ? Loc.F("Playlist : %lld pistes colorées, %lld renommées", plan.Playlist.Colors.Count, plan.Playlist.Names.Count)
                    : Loc.F("Playlist : %lld pistes colorées, %lld renommées, rangées comme le Channel rack", plan.Playlist.Colors.Count, plan.Playlist.Names.Count));
            if (Result?.Project?.SplitPatterns is > 0 and var split)
                out_.Add(Loc.F("%lld sons sortis des patterns qui en avaient plusieurs : chacun dans son pattern (comme « Split by channel » de FL)", split));
            if (Options.Playlist && plan.Layout is { } layout)
            {
                out_.Add(Loc.F("Playlist rangée dans une copie de ton projet : chaque son sur sa piste, tous les clips des mêmes sons réunis (%lld pistes). Ton projet d'origine ne bouge pas.", layout.Count));
                if (Result?.Project?.SilentPatterns is > 0 and var silent)
                    out_.Add(Loc.F("%lld patterns sans aucune note (rien n'y joue) : chacun sur sa piste, en bas de la Playlist", silent));
            }
            else if (OrganizesCopy && Options.Playlist)
            {
                out_.Add(Loc.T("Playlist : il faudrait plus de pistes que FL n'en a pour mettre chaque son sur la sienne ; décoche « Playlist » pour ranger le reste."));
            }
            return out_;
        }
    }

    public string DoneText
    {
        get
        {
            var lines = new List<string> { Loc.T("C'est fait : le projet est rangé, coloré et renommé. « Revenir comme avant » défait tout, sauf les sons supprimés.") };
            if (LastApply?.Copy is { } copy)
            {
                // Rangé dans une copie : son nom à l'écran (jamais dans le journal).
                lines = new List<string> { Loc.F("C'est fait : ton projet est rangé, coloré et renommé dans une copie, « %@ », à côté de l'original. L'original n'a pas bougé : « Revenir comme avant » le rouvre et met la copie à la Corbeille.", Path.GetFileName(copy)) };
                if (LastApply.CopyNotSaved) lines.Add(Loc.T("FL n'a pas enregistré la copie rangée : enregistre-la dans FL (Ctrl+S)."));
                lines.Add(Loc.T("Une fois l'Organiser fermé, FL Shortcuts te demandera si tu valides cette version : « Valider » met ton projet d'origine à la Corbeille et lui donne son nom, « Retourner en arrière » la supprime et rouvre ton projet d'avant."));
            }
            if (LastApply is { } outcome)
            {
                if (outcome.Deleted > 0) lines.Add(Loc.F("%lld sons sans aucune note supprimés.", outcome.Deleted));
                if (outcome.NotDeleted > 0)
                    lines.Add(Loc.F("FL n'a pas supprimé les %lld sons sans aucune note : ils sont sélectionnés dans le Channel rack, supprime-les avec clic droit › Delete.", outcome.NotDeleted));
                if (outcome.Split > 0) lines.Add(Loc.F("Playlist : %lld sons qui partageaient une piste ont chacun la leur.", outcome.Split));
            }
            if (Learned > 0)
                lines.Add(Loc.F("L'IA retient %lld sons corrigés sur ce PC : la prochaine fois, ils seront rangés comme tu l'as dit.", Learned));
            if (FeedbackSent)
                lines.Add(Loc.T("Merci ! Pour ranger ce projet avec tes corrections : « Revenir comme avant », puis relance Organiser."));
            return string.Join("\n", lines);
        }
    }

    public void Apply()
    {
        if (Phase is not OrganizerPhase.Preview || Result is not { } result || _link is not { } link) return;
        _env.SaveStyles(Styles);
        _env.SaveFamilyOrder(Options.FamilyOrder);
        // Les sons changés dans l'aperçu : l'IA s'en souvient, sans rien demander.
        Learned = Learn(OrganizerFeedback.PreviewFixes(result.Items, Families, Kinds), new[] { "apercu" });
        _env.FocusFl();
        ApplyStep = null;
        SetPhase(new OrganizerPhase.Applying());
        var applier = new OrganizerApplier(link, _env.MoveUp(link), _env.MoveLeft(link), _env.PlaceIcon, _env.DeleteSelected(link),
            wait: _env.Sleep, listen: _env.Timing.TrackListen, files: _env.ProjectFiles(),
            report: text => _env.Post(() =>
            {
                ApplyStep = text;
                Raise();
            }));
        var plan = Plan;
        var styles = Styles.ToDictionary(kv => kv.Key, kv => kv.Value);
        _env.Background(() =>
        {
            var outcome = applier.Apply(plan, result, styles);
            _env.Post(() =>
            {
                _snapshot = outcome.Snapshot;
                LastApply = outcome;
                SetPhase(new OrganizerPhase.Applied(outcome.Error));
                if (MadeCopy(outcome) is { } made) _env.CopyMade(made.Original, made.Copy);
            });
        });
    }

    /// La copie rangée faite et ouverte dans FL, avec son original (même si la suite s'est arrêtée en route).
    public static (string Original, string Copy)? MadeCopy(ApplyOutcome outcome) =>
        outcome.Copy is { } copy && outcome.Snapshot.Original is { } original ? (original, copy) : null;

    // ---------- L'IA apprend de ses erreurs ----------

    /// Sons écoutés que l'on peut corriger (ceux classés d'après leur nom n'ont pas été écoutés).
    public List<OrganizerItem> Correctable => (Result?.Items ?? new List<OrganizerItem>()).Where(i => i.SoundPrint is not null).ToList();

    /// « Pas content ? » : après l'application, une fois.
    public bool CanGiveFeedback => Phase is OrganizerPhase.Applied && Result is not null && !FeedbackSent;

    public bool SharingCorrections => _env.Corrections()?.Partage == true;

    private int Learn(IReadOnlyDictionary<int, OrganizerFeedback.Fix> fixes, IReadOnlyList<string> reasons)
    {
        if (fixes.Count == 0 || _env.Corrections() is not { } store || Result is not { } result) return 0;
        var count = 0;
        foreach (var item in result.Items)
        {
            if (!fixes.TryGetValue(item.Index, out var fix) || fix.Family == SoundFamily.Unsure || item.SoundPrint is not { } heard) continue;
            store.Ajoute(new CorrectionIA(heard.Empreinte, fix.Family, fix.Kind, DateTimeOffset.UtcNow));
            count++;
            if (store.Partage == true
                && CorrectionsIA.Envoi(heard, (item.Family, item.Kind), (fix.Family, fix.Kind), reasons, _env.AppVersion) is { } body)
                _env.ShareCorrection(body.ToJsonString());
        }
        return count;
    }

    /// « Envoyer » : les sons corrigés retenus (et partagés si la case est cochée), le reste dit à l'équipe.
    public void SubmitFeedback(OrganizerFeedback feedback)
    {
        if (feedback.Fixes.Count > 0 && _env.Corrections() is { } store) store.Partage = feedback.Share;
        Learned += Learn(feedback.Fixes, feedback.Reasons.Select(OrganizerFeedback.Raw).OrderBy(r => r, StringComparer.Ordinal).ToList());
        if (feedback.TeamMessage() is { } message) _env.SendFeedback(message, DiagnosticText);
        FeedbackSent = true;
        Raise();
    }

    /// « Revenir comme avant » : après l'application, ou pour finir un retour interrompu.
    public bool CanUndo => _snapshot is { IsEmpty: false } && Phase switch
    {
        OrganizerPhase.Applied => true,
        OrganizerPhase.Undone u => u.Error is not null,
        _ => false,
    };

    public void Undo()
    {
        if (!CanUndo || _snapshot is not { } snapshot || _link is not { } link) return;
        _env.FocusFl();
        SetPhase(new OrganizerPhase.Undoing());
        var applier = new OrganizerApplier(link, _env.MoveUp(link), _env.MoveLeft(link), wait: _env.Sleep,
            listen: _env.Timing.TrackListen, files: _env.ProjectFiles());
        _env.Background(() =>
        {
            var outcome = applier.Undo(snapshot);
            _env.Post(() =>
            {
                _snapshot = outcome.Snapshot;
                SetPhase(new OrganizerPhase.Undone(outcome.Error));
                if (outcome.Error is null && snapshot.Original is not null && LastApply?.Copy is { } copy) _env.CopyUndone(copy);
            });
        });
    }

    /// Mode capture (photos de la CI) : un écran donné, avec des sons d'exemple ; rien n'est envoyé à FL.
    public void ShowDemo(string screen)
    {
        _waitSerial++;
        ShowLinkHelp = screen == "aide";
        switch (screen)
        {
            case "installer": SetPhase(new OrganizerPhase.Setup()); break;
            case "attente": SetPhase(new OrganizerPhase.Waiting(OrganizerWait.RestartFl)); break;
            case "aide": SetPhase(new OrganizerPhase.Waiting(OrganizerWait.NoResponse)); break;
            case "ecoute": SetPhase(new OrganizerPhase.Listening(3, 8)); break;
            case "apercu":
            case "fini":
                Result = DemoResult;
                Families = Organize.FamiliesOf(Result);
                Kinds = Organize.KindsOf(Result);
                SetPhase(screen == "fini" ? new OrganizerPhase.Applied(null) : new OrganizerPhase.Preview());
                break;
        }
    }

    /// Un petit projet d'exemple : des sons nommés comme dans les packs, leurs patterns, leurs pistes du Mixer.
    public static OrganizerResult DemoResult
    {
        get
        {
            var names = new[] { "BEAM KICK", "Serum Lead", "ZEBRA 808", "@MEH CLAP", "ALTER OPEN HAT", "Vocal Chop", "Riser FX", "Pluck" };
            var gray = new RgbColor(92, 101, 107);
            var channels = names.Select((n, i) => new ChannelInfo(i, 2, i + 1, gray, n)).ToList();
            var items = names.Select((n, i) => (n, i)).Where(x => SoundNames.KindOf(x.n) is not null).Select(x =>
            {
                var kind = SoundNames.KindOf(x.n)!.Value;
                return new OrganizerItem
                {
                    Index = x.i, Name = x.n, Family = kind.Family(), Confidence = 0.9, MixerTrack = x.i + 1, Color = gray, Kind = kind, ByName = true,
                };
            }).ToList();
            return new OrganizerResult
            {
                Channels = channels,
                Items = items,
                Patterns = Enumerable.Range(0, 4).Select(i => new PatternInfo(i, gray, $"Pattern {i + 1}")).ToList(),
                PatternSounds = new Dictionary<int, HashSet<int>> { [0] = new() { 0, 3, 4 }, [1] = new() { 2 }, [2] = new() { 1, 7 }, [3] = new() { 5 } },
                Mixer = Enumerable.Range(0, 12).Select(i => new MixerTrackInfo(i, gray, i == 0 ? "Master" : $"Insert {i}")).ToList(),
                Playlist = Enumerable.Range(0, 4).Select(i => new PlaylistTrackInfo(i, false, gray, $"Track {i + 1}")).ToList(),
                TrackSounds = new Dictionary<int, HashSet<int>> { [0] = new() { 0 }, [1] = new() { 3, 4 }, [2] = new() { 2 }, [3] = new() { 1, 7 } },
            };
        }
    }

    /// Arrête l'écoute (la session remet FL comme avant) et ferme.
    public void Close()
    {
        if (_closed) return;
        _closed = true;
        _session?.Cancel();
        _session = null;
        var done = OnClose;
        OnClose = null;
        done?.Invoke();
    }
}
