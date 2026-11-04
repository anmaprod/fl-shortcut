// Sauvegarde en ligne du compte sur Windows : la MÊME que celle du Mac (supabase/sauvegarde.sql, AccountBackup.swift).
// Les raccourcis partent écrits comme sur le Mac (MacProfile : un Mac les relit tels quels, un PC les traduit pour son
// clavier) et les macros au même format que le Mac ; un raccourci venu du Mac et pas changé ici repart à l'identique.
// Règles de décision recopiées du Mac (BackupRules) : un ordinateur n'écrase jamais une sauvegarde plus récente faite
// ailleurs sans le demander (révision du serveur), et rien n'est remplacé ici sans copie datée. Requêtes construites
// ici (testées), envoyées par l'app.
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using FLShortcut.Core.Macros;

namespace FLShortcut.Core;

/// Ce qui est sauvegardé : le profil (format du Mac) et la bibliothèque des macros, en texte.
public sealed record BackupContent(string Profile, string Macros);

/// La sauvegarde du compte telle que lue sur le serveur.
public sealed record RemoteBackup(BackupContent Content, long Revision, string? UpdatedAt);

/// Que faire quand cet ordinateur et la sauvegarde du compte se retrouvent (connexion, lancement, nouvel essai).
public enum BackupDecision
{
    /// Cet ordinateur envoie ce qu'il a : pas encore de sauvegarde, ou le compte n'a pas bougé depuis.
    Upload,
    /// La sauvegarde du compte remplace cet ordinateur, qui n'a rien à perdre.
    Restore,
    InSync,
    /// Chacun a ses changements : l'utilisateur choisit.
    Ask,
}

public sealed class BackupFailure : Exception
{
    private BackupFailure(string message) : base(message) { }
    public static BackupFailure Unreadable => new(Loc.T("La sauvegarde de ton compte est illisible : rien n'a été changé sur ce PC."));
    public static BackupFailure NewerVersion => new(Loc.T("Ta sauvegarde vient d'une version plus récente de FL Shortcuts : mets l'app à jour."));
    public static BackupFailure CopyFailed => new(Loc.T("Impossible de garder une copie de ce PC avant de reprendre ta sauvegarde : rien n'a été remplacé."));
    public static BackupFailure Custom(string message) => new(message);
}

public static class BackupRules
{
    /// Comme BackupRules.decide du Mac :
    /// - `remoteRevision` : révision de la sauvegarde du compte (null : pas encore de sauvegarde) ;
    /// - `sameContent` : cet ordinateur et le compte ont les mêmes raccourcis et macros ;
    /// - `untouched` : rien de personnel ici (premier lancement, ou juste après une déconnexion) ;
    /// - `syncedRevision` : la dernière révision de CE compte lue ou écrite ici (null : jamais, ou un autre compte) ;
    ///   `dirty` : changements faits ici depuis.
    public static BackupDecision Decide(long? remoteRevision, bool sameContent, bool untouched, long? syncedRevision, bool dirty)
    {
        if (remoteRevision is not { } remote) return BackupDecision.Upload;
        if (sameContent) return BackupDecision.InSync;
        if (syncedRevision is { } synced)
        {
            if (synced == remote) return BackupDecision.Upload;      // le compte n'a pas bougé : ce PC a des changements
            if (!dirty) return BackupDecision.Restore;               // changé ailleurs, rien à perdre ici
        }
        return untouched ? BackupDecision.Restore : BackupDecision.Ask;
    }

    /// « 12 raccourcis · 3 macros ».
    public static string Summary(int shortcuts, int macros) =>
        Loc.F("%lld raccourci%@ · %lld macro%@", shortcuts, shortcuts > 1 ? "s" : "", macros, macros > 1 ? "s" : "");
}

public static class BackupCodec
{
    /// Profil de la sauvegarde : version lue par le Mac (ProfileCodec.currentVersion).
    public const int ProfileVersion = 2;

    public static BackupContent Of(IEnumerable<Shortcut> shortcuts, IEnumerable<MacroDoc> macros, IKeyLayout layout) =>
        new(MacProfile.ToMac(shortcuts, layout), Encoding.UTF8.GetString(MacroLibraryCodec.Encode(macros, pretty: false)));

    /// Raccourcis (traduits pour ce PC) et macros relus ; refusé s'ils viennent d'une version plus récente de l'app
    /// (rien ne serait perdu ici, mais les renvoyer depuis cette version en perdrait une partie).
    public static (List<Shortcut> Shortcuts, List<MacroDoc> Macros) Decode(BackupContent content, IKeyLayout layout)
    {
        MacProfile.Translated profile;
        MacroLibraryCodec.Decoded library;
        int profileVersion;
        try
        {
            profileVersion = JsonNode.Parse(content.Profile) is JsonObject o && o["version"] is JsonValue v && v.TryGetValue<int>(out var n) ? n : 1;
            profile = MacProfile.FromMac(content.Profile, layout);
            library = MacroLibraryCodec.Decode(Encoding.UTF8.GetBytes(content.Macros));
        }
        catch (Exception e) when (e is FormatException or JsonException or MacroLibraryCodec.Failure)
        {
            throw BackupFailure.Unreadable;
        }
        if (profileVersion > ProfileVersion || library.Version > MacroLibraryCodec.CurrentVersion) throw BackupFailure.NewerVersion;
        return (profile.Shortcuts, library.Macros);
    }

    /// Même contenu ici et dans le compte (une fois relu de part et d'autre).
    public static bool Same(BackupContent remote, IReadOnlyList<Shortcut> shortcuts, IReadOnlyList<MacroDoc> macros, IKeyLayout layout)
    {
        try
        {
            var (theirShortcuts, theirMacros) = Decode(remote, layout);
            var theirs = JsonNode.Parse(MacProfile.ToMac(theirShortcuts, layout))!["remaps"];
            var ours = JsonNode.Parse(MacProfile.ToMac(shortcuts, layout))!["remaps"];
            if (!JsonNode.DeepEquals(theirs, ours)) return false;
            return theirMacros.Count == macros.Count
                   && theirMacros.Zip(macros).All(p => p.First.Id == p.Second.Id && MacroLibraryStore.SameContent(p.First, p.Second));
        }
        catch (BackupFailure) { return false; }
    }

    /// « 12 raccourcis · 3 macros » d'une sauvegarde ; « illisible » si elle ne se lit pas.
    public static string Summary(BackupContent content, IKeyLayout layout)
    {
        try
        {
            var (shortcuts, macros) = Decode(content, layout);
            return BackupRules.Summary(shortcuts.Count, macros.Count);
        }
        catch (BackupFailure) { return Loc.T("illisible"); }
    }

    private static readonly Regex Uuid = new("[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}", RegexOptions.CultureInvariant);

    /// Rien de personnel sur ce PC : raccourcis du premier lancement et aucune macro (identifiants mis à part, ils
    /// changent à chaque création), comme Store.isUntouched du Mac.
    public static bool Untouched(IEnumerable<Shortcut> shortcuts, int macroCount) =>
        macroCount == 0 && WithoutIds(shortcuts) == WithoutIds(ProfilePreset.Recommended.Shortcuts());

    private static string WithoutIds(IEnumerable<Shortcut> shortcuts) => Uuid.Replace(ProfileCodec.Encode(shortcuts), "-");
}

public static class BackupRequests
{
    /// Révision et date de la sauvegarde, sans son contenu (vérification rapide).
    public static HttpRequestMessage Revision(ServerConfig c, AccountSession s) =>
        ServerRequests.Make(c, HttpMethod.Get, "rest/v1/backups?select=revision,updated_at", s.AccessToken);

    public static HttpRequestMessage Get(ServerConfig c, AccountSession s) =>
        ServerRequests.Make(c, HttpMethod.Get, "rest/v1/backups?select=profile,macros,revision,updated_at", s.AccessToken);

    /// Enregistre si la sauvegarde est toujours à la révision `base` (sinon le serveur répond « Sauvegarde plus
    /// récente… », IsConflict), ou quoi qu'il y ait si `force`. Réponse : la nouvelle révision.
    public static HttpRequestMessage Save(ServerConfig c, AccountSession s, BackupContent content, long @base, bool force, string appVersion) =>
        ServerRequests.Make(c, HttpMethod.Post, "rest/v1/rpc/save_backup", s.AccessToken, new Dictionary<string, object>
        {
            ["p_profile"] = content.Profile,
            ["p_macros"] = content.Macros,
            ["p_base"] = @base,
            ["p_force"] = force,
            ["p_app_version"] = appVersion.Length > 20 ? appVersion[..20] : appVersion,
        });

    /// (révision, date) ; null : pas encore de sauvegarde ; exception : réponse illisible.
    public static (long Revision, string? UpdatedAt)? DecodeRevision(string json)
    {
        var rows = JsonDocument.Parse(json).RootElement;
        if (rows.ValueKind != JsonValueKind.Array) throw new FormatException();
        if (rows.GetArrayLength() == 0) return null;
        var row = rows[0];
        return (row.GetProperty("revision").GetInt64(), Text(row, "updated_at"));
    }

    public static RemoteBackup? DecodeBackup(string json)
    {
        var rows = JsonDocument.Parse(json).RootElement;
        if (rows.ValueKind != JsonValueKind.Array) throw new FormatException();
        if (rows.GetArrayLength() == 0) return null;
        var row = rows[0];
        return new RemoteBackup(new BackupContent(row.GetProperty("profile").GetString() ?? throw new FormatException(),
                                                  row.GetProperty("macros").GetString() ?? throw new FormatException()),
                                row.GetProperty("revision").GetInt64(), Text(row, "updated_at"));
    }

    public static long DecodeSaved(string json) => JsonDocument.Parse(json).RootElement.GetInt64();

    /// Refus du serveur : la sauvegarde a changé depuis un autre ordinateur (relire avant d'envoyer).
    public static bool IsConflict(string json)
    {
        try
        {
            var root = JsonDocument.Parse(json).RootElement;
            return root.ValueKind == JsonValueKind.Object && root.TryGetProperty("message", out var m)
                   && m.ValueKind == JsonValueKind.String
                   && m.GetString()!.StartsWith("Sauvegarde plus récente", StringComparison.OrdinalIgnoreCase);
        }
        catch (JsonException) { return false; }
    }

    private static string? Text(JsonElement row, string key) =>
        row.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
}
