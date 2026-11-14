// Communauté (Windows), miroir de CommunityClient.swift et CommunityView.swift du Mac : les partages (macros, et les
// raccourcis d'un Mac, qui restent sur Mac : leurs touches n'ont pas les codes de Windows), leurs requêtes (liste,
// fichier, publication, suppression, signalement), leurs règles et leur lecture. Compte nécessaire : sans session,
// rien n'est lu. Les requêtes sont construites ici (testées), envoyées par l'app.
using System.Text;
using System.Text.Json;

namespace FLShortcut.Core;

/// Un partage tel que listé (sans le fichier, chargé seulement pour l'ajout). Communauté du 11/11
/// (communaute-suivre.sql) : nombre d'ajouts, somme et nombre des notes (null : serveur d'avant).
public sealed record Share(Guid Id, Guid AuthorId, string Kind, string Title, string Notes, string AppVersion,
                           string CreatedAt, string AuthorName, int? AddCount = null, int? RatingSum = null,
                           int? RatingCount = null)
{
    public bool IsMacro => Kind == CommunityRules.MacroKind;

    /// Moyenne des notes (null : aucune note).
    public double? Rating => RatingSum is { } sum && RatingCount is > 0 and var count ? (double)sum / count : null;

    /// « 2026-10-16T18:02:11… » → « 16/10/2026 ».
    public string Day
    {
        get
        {
            var parts = (CreatedAt.Length >= 10 ? CreatedAt[..10] : CreatedAt).Split('-');
            return parts.Length == 3 ? $"{parts[2]}/{parts[1]}/{parts[0]}" : "";
        }
    }

    /// « Macro · par @flshortcuts · 15/10/2026 » (comme CommunityText.byline du Mac).
    public string Byline => Loc.F("%@ · par @%@ · %@", IsMacro ? Loc.T("Macro") : Loc.T("Raccourcis"),
                                  DisplayText.Safe(AuthorName, 24), Day);
}

public static class CommunityRules
{
    public const string MacroKind = "macro";
    public const string ProfileKind = "profile";
    public const int MinTitle = 3, MaxTitle = 80;
    public const int MaxNotes = 4000;
    public const int MaxPayload = 262_144;

    /// Comme CommunityRules.shareProblem du Mac (et le serveur).
    public static string? ShareProblem(string title, string notes, int payloadBytes)
    {
        var t = title.Trim().Length;
        if (t < MinTitle || t > MaxTitle) return Loc.F("Titre : %lld à %lld caractères.", MinTitle, MaxTitle);
        if (notes.Length > MaxNotes) return Loc.F("Notes : %lld caractères au plus.", MaxNotes);
        if (payloadBytes > MaxPayload) return Loc.T("Fichier trop volumineux pour être partagé.");
        return null;
    }

    /// Mots de la recherche gardés pour le serveur : lettres, chiffres, espace, « - » et « ' », 60 au plus (rien qui
    /// change le sens de la requête).
    public static string SearchPattern(string s)
    {
        var kept = new string(s.Where(c => char.IsLetterOrDigit(c) || c is ' ' or '-' or '\'').ToArray()).Trim();
        return kept.Length > 60 ? kept[..60] : kept;
    }
}

public static class CommunityRequests
{
    public const string ListColumns = "id,author_id,kind,title,notes,app_version,created_at,author:profiles(username)";

    /// Colonnes d'un partage avec ses nombres (communaute-suivre.sql).
    public const string SocialColumns = ListColumns + ",add_count,rating_sum,rating_count";

    /// Les 50 partages les plus récents : d'une sorte (null : toutes), d'un auteur, ou dont le titre ou l'explication
    /// contient la recherche. `social` : avec les ajouts et les notes ; `order` : ordre du serveur.
    public static HttpRequestMessage Shares(ServerConfig c, AccountSession s, string? kind, string search, Guid? authorId = null,
                                            bool social = false, string order = "created_at.desc")
    {
        var query = new List<(string, string)> { ("select", social ? SocialColumns : ListColumns), ("order", order), ("limit", "50") };
        if (kind is not null) query.Add(("kind", "eq." + kind));
        if (authorId is { } author) query.Add(("author_id", "eq." + Id(author)));
        var words = CommunityRules.SearchPattern(search);
        if (words.Length > 0) query.Add(("or", $"(title.ilike.*{words}*,notes.ilike.*{words}*)"));
        return ServerRequests.Make(c, HttpMethod.Get, "rest/v1/shares?" + Query(query), s.AccessToken);
    }

    /// Le fichier partagé, pour l'ajout.
    public static HttpRequestMessage Payload(ServerConfig c, AccountSession s, Guid id) =>
        ServerRequests.Make(c, HttpMethod.Get, "rest/v1/shares?" + Query(new() { ("select", "payload"), ("id", "eq." + Id(id)) }), s.AccessToken);

    public static HttpRequestMessage Publish(ServerConfig c, AccountSession s, string kind, string title, string notes,
                                             byte[] payload, string appVersion)
    {
        title = title.Trim();
        if (CommunityRules.ShareProblem(title, notes, payload.Length) is { } why) throw new ArgumentException(why);
        string text;
        try { text = new UTF8Encoding(false, true).GetString(payload); }
        catch (DecoderFallbackException) { throw new ArgumentException(Loc.T("Fichier illisible.")); }
        return ServerRequests.Make(c, HttpMethod.Post, "rest/v1/shares", s.AccessToken, new Dictionary<string, string>
        {
            ["kind"] = kind,
            ["title"] = title,
            ["notes"] = notes,
            ["payload"] = text,
            ["app_version"] = appVersion.Length > 20 ? appVersion[..20] : appVersion,
        });
    }

    public static HttpRequestMessage Delete(ServerConfig c, AccountSession s, Guid id) =>
        ServerRequests.Make(c, HttpMethod.Delete, "rest/v1/shares?" + Query(new() { ("id", "eq." + Id(id)) }), s.AccessToken);

    public static HttpRequestMessage Report(ServerConfig c, AccountSession s, Guid id, string reason)
    {
        reason = reason.Trim();
        if (reason.Length is < 3 or > 500) throw new ArgumentException(Loc.T("Raison : 3 à 500 caractères."));
        return ServerRequests.Make(c, HttpMethod.Post, "rest/v1/reports", s.AccessToken,
            new Dictionary<string, string> { ["share_id"] = Id(id), ["reason"] = reason });
    }

    /// La liste du serveur ; une ligne illisible est sautée.
    public static List<Share> DecodeShares(string json)
    {
        var shares = new List<Share>();
        try
        {
            foreach (var row in JsonDocument.Parse(json).RootElement.EnumerateArray())
            {
                if (!row.TryGetProperty("id", out var id) || !id.TryGetGuid(out var shareId)) continue;
                if (!row.TryGetProperty("author_id", out var a) || !a.TryGetGuid(out var authorId)) continue;
                string Text(string key) => row.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString()! : "";
                var author = row.TryGetProperty("author", out var au) && au.ValueKind == JsonValueKind.Object
                             && au.TryGetProperty("username", out var u) && u.ValueKind == JsonValueKind.String ? u.GetString()! : "?";
                var kind = Text("kind");
                if (kind is not (CommunityRules.MacroKind or CommunityRules.ProfileKind) || Text("title").Length == 0) continue;
                int? Number(string key) => row.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.Number
                                           && v.TryGetInt32(out var n) ? n : null;
                shares.Add(new Share(shareId, authorId, kind, Text("title"), Text("notes"), Text("app_version"),
                                     Text("created_at"), author, Number("add_count"), Number("rating_sum"), Number("rating_count")));
            }
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException) { }
        return shares;
    }

    /// Le fichier d'un partage ; null s'il manque ou dépasse la taille permise.
    public static byte[]? DecodePayload(string json)
    {
        try
        {
            var rows = JsonDocument.Parse(json).RootElement;
            if (rows.ValueKind != JsonValueKind.Array || rows.GetArrayLength() == 0) return null;
            if (!rows[0].TryGetProperty("payload", out var p) || p.ValueKind != JsonValueKind.String) return null;
            var bytes = Encoding.UTF8.GetBytes(p.GetString()!);
            return bytes.Length <= CommunityRules.MaxPayload ? bytes : null;
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException) { return null; }
    }

    private static string Id(Guid id) => id.ToString("D").ToLowerInvariant();

    private static string Query(List<(string Key, string Value)> items) =>
        string.Join("&", items.Select(i => Uri.EscapeDataString(i.Key) + "=" + Uri.EscapeDataString(i.Value)));
}
