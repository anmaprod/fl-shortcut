// Communauté du 11/11 sur Windows : mêmes règles que le Mac (CommunityTests.swift) : nombres des partages, textes,
// requêtes du serveur, repli sans le fichier du serveur, point rouge.
using System.Globalization;
using FLShortcut.Core;
using Xunit;

namespace FLShortcut.Core.Tests;

public sealed class CommunitySocialTests
{
    private static readonly ServerConfig Server = new(new Uri("https://exemple.supabase.co"), "cle-anon");
    private static readonly AccountSession Session =
        new("jeton", "suite", DateTimeOffset.UnixEpoch.AddHours(1), Guid.Empty, "flshortcuts@exemple.fr", "flshortcuts");

    private static Share Share(string created = "2026-11-11T10:00:00+00:00", int? adds = null, int? sum = null, int? count = null) =>
        new(Guid.NewGuid(), Guid.NewGuid(), CommunityRules.MacroKind, "Armer", "", "", created, "leo.beats", adds, sum, count);

    private static Dictionary<string, string> QueryOf(HttpRequestMessage r) =>
        (r.RequestUri!.Query.TrimStart('?')).Split('&', StringSplitOptions.RemoveEmptyEntries)
            .Select(p => p.Split('=', 2)).ToDictionary(p => Uri.UnescapeDataString(p[0]), p => Uri.UnescapeDataString(p[1]));

    private static string BodyOf(HttpRequestMessage r) => r.Content!.ReadAsStringAsync().Result;

    /// « ★ 4,6 · Ajoutée 312 fois » : jamais « Ajoutée 0 fois », pas d'étoile sans note, moyenne à une décimale.
    [Fact]
    public void StatsLine()
    {
        var fr = CultureInfo.GetCultureInfo("fr-FR");
        var en = CultureInfo.GetCultureInfo("en-US");
        Assert.Null(CommunityStats.Line(Share(), fr));                              // serveur d'avant : rien
        Assert.Null(CommunityStats.Line(Share(adds: 0, sum: 0, count: 0), fr));    // jamais « Ajoutée 0 fois »
        Assert.Equal("4,6", CommunityStats.Rating(1435.0 / 312, fr));
        Assert.Equal("4.6", CommunityStats.Rating(1435.0 / 312, en));
        Assert.Equal("★ 4,6 · " + CommunityStats.Added(312), CommunityStats.Line(Share(adds: 312, sum: 1435, count: 312), fr));
        Assert.Null(CommunityStats.Added(0));
        Assert.NotEqual(CommunityStats.Added(1), CommunityStats.Added(2));
        Assert.Equal("1,284", CommunityStats.Number(1284, en));
        Assert.Equal(1435.0 / 312, Share(sum: 1435, count: 312).Rating!.Value, 3);
        Assert.Null(Share(sum: 0, count: 0).Rating);
    }

    /// Les nombres sont lus avec le partage ; un serveur d'avant n'en donne pas.
    [Fact]
    public void SharesCarryTheirNumbers()
    {
        var id = Guid.NewGuid();
        var json = $$$"""
            [{"id":"{{{id}}}","author_id":"{{{Guid.NewGuid()}}}","kind":"macro","title":"Armer vite","notes":"","app_version":"0.1.0",
              "created_at":"2026-11-11T10:00:00+00:00","author":{"username":"leo.beats"},"add_count":312,"rating_sum":1435,"rating_count":312},
             {"id":"{{{Guid.NewGuid()}}}","author_id":"{{{Guid.NewGuid()}}}","kind":"macro","title":"Ancien","notes":"","app_version":"",
              "created_at":"2026-10-01T10:00:00+00:00","author":{"username":"sarah.mix"}}]
            """;
        var list = CommunityRequests.DecodeShares(json);
        Assert.Equal(312, list[0].AddCount);
        Assert.Equal(312, list[0].RatingCount);
        Assert.Null(list[1].AddCount);
        Assert.Equal(CommunityRequests.SocialColumns, QueryOf(CommunityRequests.Shares(Server, Session, null, "", social: true))["select"]);
        Assert.Equal(CommunityRequests.ListColumns, QueryOf(CommunityRequests.Shares(Server, Session, null, ""))["select"]);
        Assert.Equal("add_count.desc,created_at.desc",
            QueryOf(CommunityRequests.Shares(Server, Session, null, "", Guid.NewGuid(), true, PersonSort.MostAdded.Order()))["order"]);
    }

    /// Un serveur sans communaute-suivre.sql (colonne, table ou fonction absente) : la Communauté d'avant, sans erreur.
    [Fact]
    public void ServerWithoutTheSocialFileIsRecognized()
    {
        Assert.True(CommunitySocial.IsMissingSocial(400, "Erreur du serveur : column shares.add_count does not exist"));
        Assert.True(CommunitySocial.IsMissingSocial(404, "Could not find the function public.record_add"));
        Assert.False(CommunitySocial.IsMissingSocial(400, "Ajoute-le d'abord, puis note-le."));
        Assert.False(CommunitySocial.IsMissingSocial(500, "column add_count does not exist"));
    }

    /// Ajout compté, note envoyée, abonnements : les bonnes adresses du serveur, les bons nombres dans le corps.
    [Fact]
    public void SocialRequests()
    {
        var share = Guid.NewGuid();
        var author = Guid.NewGuid();
        var followed = CommunitySocial.FollowedShares(Server, Session, 3);
        Assert.Equal("/rest/v1/rpc/followed_shares", followed.RequestUri!.AbsolutePath);
        Assert.Equal(CommunityRequests.SocialColumns, QueryOf(followed)["select"]);
        Assert.Contains("\"p_limit\":3", BodyOf(followed));
        Assert.Contains("\"p_kind\":null", BodyOf(CommunitySocial.MostAdded(Server, Session, null, 50)));
        var rate = CommunitySocial.Rate(Server, Session, share, 5);
        Assert.Contains("\"p_stars\":5", BodyOf(rate));
        Assert.Contains(share.ToString("D"), BodyOf(rate));
        Assert.Throws<ArgumentOutOfRangeException>(() => CommunitySocial.Rate(Server, Session, share, 6));
        Assert.Equal("/rest/v1/rpc/record_add", CommunitySocial.RecordAdd(Server, Session, share).RequestUri!.AbsolutePath);
        var follow = CommunitySocial.Follow(Server, Session, author);
        Assert.Equal(HttpMethod.Post, follow.Method);
        Assert.Contains(author.ToString("D"), BodyOf(follow));
        var unfollow = CommunitySocial.Unfollow(Server, Session, author);
        Assert.Equal(HttpMethod.Delete, unfollow.Method);
        Assert.Equal("eq." + author.ToString("D"), QueryOf(unfollow)["followee_id"]);
        Assert.Equal("Bearer jeton", follow.Headers.Authorization!.ToString());

        Assert.Equal(313, CommunitySocial.DecodeCount("313"));
        Assert.Equal((1440, 313), CommunitySocial.DecodeRated("""[{"rating_sum":1440,"rating_count":313}]"""));
        Assert.Equal(4, CommunitySocial.DecodeStars("""[{"stars":4}]"""));
        Assert.Null(CommunitySocial.DecodeStars("[]"));
        Assert.True(CommunitySocial.DecodeAny($$"""[{"share_id":"{{share}}"}]"""));
        Assert.False(CommunitySocial.DecodeAny("[]"));
        Assert.Equal(new[] { author }, CommunitySocial.DecodeFollowing($$"""[{"followee_id":"{{author}}"}]"""));
        var creator = Assert.Single(CommunitySocial.DecodeCreators($$"""[{"id":"{{author}}","username":"leo.beats","follower_count":1284,"score":3.9,"adds":12}]"""));
        Assert.Equal(1284, creator.FollowerCount);
    }

    /// Point rouge : seuls les partages plus récents que la dernière ouverture d'« Abonnements » comptent.
    [Fact]
    public void NewFromFollowedCount()
    {
        var seen = DateTimeOffset.Parse("2026-11-10T12:00:00+00:00", CultureInfo.InvariantCulture);
        Assert.Equal(2, CommunityStats.NewCount(new[] { Share("2026-11-11T10:00:00+00:00"), Share("2026-11-09T10:00:00+00:00"),
                                                         Share("2026-11-12T10:00:00+00:00") }, seen));
        Assert.Equal(0, CommunityStats.NewCount(Array.Empty<Share>(), seen));
    }

    /// Tout texte de la nouvelle Communauté a son anglais (un Windows en anglais ne voit aucun mot français).
    [Fact]
    public void EveryTextHasItsEnglish()
    {
        foreach (var tab in Enum.GetValues<CommunityTab>()) Assert.True(Loc.Has(tab.Title()), tab.Title());
        foreach (var sort in Enum.GetValues<PersonSort>()) Assert.True(Loc.Has(sort.Title()), sort.Title());
        foreach (var text in new[] { "Ajoutée une fois", "Ajoutée %lld fois", "1 abonné", "%@ abonnés" })
            Assert.True(Loc.Has(text), text);
    }
}
