// Communauté du 11/11 (Windows), miroir de CommunitySocial.swift du Mac : onglets, abonnements, « Ajoutée N fois »,
// étoiles, page d'une personne et point rouge (docs/superpowers/specs/2026-11-11-communaute-suivre-design.md ; serveur :
// supabase/communaute-suivre.sql). Requêtes construites ici (testées), envoyées par l'app (CommunityPage.cs). Sans le
// fichier du serveur, tout se replie sur la Communauté d'avant (IsMissingSocial), sans erreur affichée.
using System.Globalization;
using System.Text.Json;

namespace FLShortcut.Core;

/// Onglets de la Communauté (vitrine validée le 11/11).
public enum CommunityTab { ForYou, Following, MostAdded, Mine }

/// Ordre du travail d'une personne (sa page).
public enum PersonSort { MostAdded, Recent }

/// Un créateur (vitrine, page d'une personne) : son pseudo et son nombre d'abonnés, jamais la liste.
public sealed record CommunityCreator(Guid Id, string Username, int FollowerCount);

public static class CommunityTabs
{
    public static string Title(this CommunityTab tab) => tab switch
    {
        CommunityTab.ForYou => Loc.T("Pour toi"),
        CommunityTab.Following => Loc.T("Abonnements"),
        CommunityTab.MostAdded => Loc.T("Les plus ajoutées"),
        _ => Loc.T("Les miens"),
    };

    /// Onglets qui demandent le serveur du 11/11 (cachés sans lui).
    public static bool NeedsSocial(this CommunityTab tab) => tab is CommunityTab.Following or CommunityTab.MostAdded;

    public static string Title(this PersonSort sort) =>
        sort == PersonSort.MostAdded ? Loc.T("Les plus ajoutées") : Loc.T("Les plus récentes");

    /// Ordre demandé au serveur.
    public static string Order(this PersonSort sort) =>
        sort == PersonSort.MostAdded ? "add_count.desc,created_at.desc" : "created_at.desc";
}

/// Textes des nombres de la Communauté (purs, testés ; mêmes que le Mac).
public static class CommunityStats
{
    /// « ★ 4,6 · Ajoutée 312 fois », « Ajoutée une fois », « ★ 5,0 » ; null : rien à dire (jamais « Ajoutée 0 fois »).
    public static string? Line(Share share, CultureInfo? culture = null)
    {
        var parts = new List<string>();
        if (share.Rating is { } value) parts.Add("★ " + Rating(value, culture));
        if (Added(share.AddCount ?? 0) is { } added) parts.Add(added);
        return parts.Count == 0 ? null : string.Join(" · ", parts);
    }

    public static string? Added(int count) => count switch
    {
        < 1 => null,
        1 => Loc.T("Ajoutée une fois"),
        _ => Loc.F("Ajoutée %lld fois", count),
    };

    /// Moyenne à une décimale, à la façon de la langue (« 4,6 » en français, « 4.6 » en anglais).
    public static string Rating(double value, CultureInfo? culture = null) =>
        value.ToString("0.0", culture ?? CultureInfo.CurrentCulture);

    /// « 1 abonné », « 1 284 abonnés ».
    public static string Followers(int count, CultureInfo? culture = null) =>
        count == 1 ? Loc.T("1 abonné") : Loc.F("%@ abonnés", Number(count, culture));

    /// Un nombre à la façon de la langue (« 1 284 », « 1,284 »).
    public static string Number(int count, CultureInfo? culture = null) => count.ToString("N0", culture ?? CultureInfo.CurrentCulture);

    /// Partages arrivés après `since` (point rouge et « N nouvelles »).
    public static int NewCount(IEnumerable<Share> shares, DateTimeOffset since) =>
        shares.Count(s => DateTimeOffset.TryParse(s.CreatedAt, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var d) && d > since);
}

public static class CommunitySocial
{
    /// Pur (testé) : réponse d'un serveur sans communaute-suivre.sql (404 : fonction ou table absente ; 400 : colonne
    /// absente). Même règle que le Mac.
    public static bool IsMissingSocial(int status, string message)
    {
        var m = message.ToLowerInvariant();
        if (status == 404) return true;
        return status == 400 && (m.Contains("does not exist") || m.Contains("could not find"))
               && (m.Contains("add_count") || m.Contains("rating") || m.Contains("follow") || m.Contains("adds"));
    }

    private static string Id(Guid id) => id.ToString("D").ToLowerInvariant();

    private static string Query(params (string Key, string Value)[] items) =>
        string.Join("&", items.Select(i => Uri.EscapeDataString(i.Key) + "=" + Uri.EscapeDataString(i.Value)));

    /// Partages des gens que l'on suit, les plus récents d'abord.
    public static HttpRequestMessage FollowedShares(ServerConfig c, AccountSession s, int limit) =>
        ServerRequests.Make(c, HttpMethod.Post, "rest/v1/rpc/followed_shares?" + Query(("select", CommunityRequests.SocialColumns)),
            s.AccessToken, new Dictionary<string, object?> { ["p_limit"] = limit });

    /// Les plus ajoutés (à égalité, la meilleure note du créateur).
    public static HttpRequestMessage MostAdded(ServerConfig c, AccountSession s, string? kind, int limit) =>
        ServerRequests.Make(c, HttpMethod.Post, "rest/v1/rpc/most_added?" + Query(("select", CommunityRequests.SocialColumns)),
            s.AccessToken, new Dictionary<string, object?> { ["p_kind"] = kind, ["p_limit"] = limit });

    /// Créateurs à suivre : ni soi ni ceux qu'on suit déjà.
    public static HttpRequestMessage CreatorsToFollow(ServerConfig c, AccountSession s, int limit) =>
        ServerRequests.Make(c, HttpMethod.Post, "rest/v1/rpc/creators_to_follow", s.AccessToken,
            new Dictionary<string, object?> { ["p_limit"] = limit });

    /// Une personne : son pseudo et son nombre d'abonnés.
    public static HttpRequestMessage Person(ServerConfig c, AccountSession s, Guid id) =>
        ServerRequests.Make(c, HttpMethod.Get, "rest/v1/profiles?" + Query(("select", "id,username,follower_count"), ("id", "eq." + Id(id))),
            s.AccessToken);

    /// Les gens que l'on suit (le serveur ne rend que les siens).
    public static HttpRequestMessage Following(ServerConfig c, AccountSession s) =>
        ServerRequests.Make(c, HttpMethod.Get, "rest/v1/follows?" + Query(("select", "followee_id")), s.AccessToken);

    public static HttpRequestMessage Follow(ServerConfig c, AccountSession s, Guid id) =>
        ServerRequests.Make(c, HttpMethod.Post, "rest/v1/follows", s.AccessToken, new Dictionary<string, string> { ["followee_id"] = Id(id) });

    public static HttpRequestMessage Unfollow(ServerConfig c, AccountSession s, Guid id) =>
        ServerRequests.Make(c, HttpMethod.Delete, "rest/v1/follows?" + Query(("followee_id", "eq." + Id(id))), s.AccessToken);

    /// « Ajouter » compté sur le serveur (une fois par personne, jamais le sien).
    public static HttpRequestMessage RecordAdd(ServerConfig c, AccountSession s, Guid share) =>
        ServerRequests.Make(c, HttpMethod.Post, "rest/v1/rpc/record_add", s.AccessToken, new Dictionary<string, string> { ["p_share"] = Id(share) });

    /// Ce partage a-t-il été ajouté par moi (une ligne : oui).
    public static HttpRequestMessage MyAdd(ServerConfig c, AccountSession s, Guid share) =>
        ServerRequests.Make(c, HttpMethod.Get, "rest/v1/adds?" + Query(("select", "share_id"), ("share_id", "eq." + Id(share))), s.AccessToken);

    /// Ma note de ce partage (aucune ligne : pas notée).
    public static HttpRequestMessage MyRating(ServerConfig c, AccountSession s, Guid share) =>
        ServerRequests.Make(c, HttpMethod.Get, "rest/v1/ratings?" + Query(("select", "stars"), ("share_id", "eq." + Id(share))), s.AccessToken);

    /// Ma note (1 à 5).
    public static HttpRequestMessage Rate(ServerConfig c, AccountSession s, Guid share, int stars)
    {
        if (stars is < 1 or > 5) throw new ArgumentOutOfRangeException(nameof(stars));
        return ServerRequests.Make(c, HttpMethod.Post, "rest/v1/rpc/rate_share", s.AccessToken,
            new Dictionary<string, object?> { ["p_share"] = Id(share), ["p_stars"] = stars });
    }

    // ---------- Lecture des réponses ----------

    public static List<CommunityCreator> DecodeCreators(string json)
    {
        var output = new List<CommunityCreator>();
        try
        {
            foreach (var row in JsonDocument.Parse(json).RootElement.EnumerateArray())
            {
                if (!row.TryGetProperty("id", out var id) || !id.TryGetGuid(out var guid)) continue;
                if (!row.TryGetProperty("username", out var u) || u.ValueKind != JsonValueKind.String) continue;
                var followers = row.TryGetProperty("follower_count", out var f) && f.TryGetInt32(out var n) ? n : 0;
                output.Add(new CommunityCreator(guid, u.GetString()!, followers));
            }
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException) { }
        return output;
    }

    public static HashSet<Guid> DecodeFollowing(string json)
    {
        var output = new HashSet<Guid>();
        try
        {
            foreach (var row in JsonDocument.Parse(json).RootElement.EnumerateArray())
                if (row.TryGetProperty("followee_id", out var id) && id.TryGetGuid(out var guid)) output.Add(guid);
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException) { }
        return output;
    }

    /// Le nombre d'ajouts rendu par record_add ; null : réponse illisible.
    public static int? DecodeCount(string json) => int.TryParse(json.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var n) ? n : null;

    /// Une ligne rendue (mes ajouts) : oui ou non.
    public static bool DecodeAny(string json)
    {
        try { return JsonDocument.Parse(json).RootElement is { ValueKind: JsonValueKind.Array } a && a.GetArrayLength() > 0; }
        catch (JsonException) { return false; }
    }

    /// Ma note (null : pas notée).
    public static int? DecodeStars(string json)
    {
        try
        {
            var rows = JsonDocument.Parse(json).RootElement;
            return rows.ValueKind == JsonValueKind.Array && rows.GetArrayLength() > 0
                   && rows[0].TryGetProperty("stars", out var s) && s.TryGetInt32(out var n) ? n : null;
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException) { return null; }
    }

    /// Somme et nombre de notes rendus par rate_share.
    public static (int Sum, int Count)? DecodeRated(string json)
    {
        try
        {
            var rows = JsonDocument.Parse(json).RootElement;
            if (rows.ValueKind != JsonValueKind.Array || rows.GetArrayLength() == 0) return null;
            return rows[0].TryGetProperty("rating_sum", out var s) && s.TryGetInt32(out var sum)
                   && rows[0].TryGetProperty("rating_count", out var c) && c.TryGetInt32(out var count) ? (sum, count) : null;
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException) { return null; }
    }
}
