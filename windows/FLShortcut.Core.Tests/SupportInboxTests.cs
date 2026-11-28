using FLShortcut.Core;
using Xunit;

namespace FLShortcut.Core.Tests;

/// Aide › Mes messages (20/11, comme SupportInboxTests du Mac).
public class SupportInboxTests
{
    private static readonly ServerConfig Server = new(new Uri("https://exemple.supabase.co/"), "cle-publique");
    private static readonly AccountSession Session = new("jeton", "renouveler", DateTimeOffset.UtcNow.AddHours(1),
        Guid.Parse("6f1d2c1e-0000-4000-8000-000000000001"), "flshortcuts@exemple.fr", "flshortcuts");

    [Fact]
    public void ThreadsAreReadWithTheirRepliesInOrder()
    {
        var threads = SupportInbox.Decode("""
            [{"id":"6f1d2c1e-0000-4000-8000-0000000000a1","kind":"autre","reference":"FLS-3F9A2C",
              "message":"Export Stems s'arrête.\nAu menu Export.","created_at":"2026-11-17T10:00:00+00:00",
              "support_replies":[
                {"id":"6f1d2c1e-0000-4000-8000-0000000000b2","team":false,"message":"Merci","created_at":"2026-11-18T10:00:00+00:00"},
                {"id":"6f1d2c1e-0000-4000-8000-0000000000b1","team":true,"message":"Corrigé","created_at":"2026-11-18T09:00:00+00:00"}]}]
            """);
        var t = Assert.Single(threads);
        Assert.Equal("Export Stems s'arrête.", t.FirstLine);
        Assert.Equal(new[] { "Corrigé", "Merci" }, t.Replies.Select(r => r.Message));
        Assert.Equal(SupportKind.Autre, t.Kind);
        Assert.Equal("/9j/abc", SupportInbox.DecodeCapture("""[{"capture":"/9j/abc"}]"""));
        Assert.Null(SupportInbox.DecodeCapture("""[{"capture":null}]"""));
    }

    [Fact]
    public void StateFollowsTheTeamsLastReply()
    {
        var answer = new SupportReply(Guid.NewGuid(), true, "Oui", "2026-11-19T10:00:00+00:00");
        var sent = new SupportThread(Guid.NewGuid(), SupportKind.Idee, "FLS-1", "Un thème bleu", "2026-11-18T10:00:00+00:00", new List<SupportReply>());
        var answered = sent with { Replies = new[] { answer, new SupportReply(Guid.NewGuid(), false, "Merci", "2026-11-19T11:00:00+00:00") } };
        Assert.Equal(SupportState.Sent, SupportInbox.State(sent, new HashSet<Guid>()));
        Assert.Equal(SupportState.NewAnswer, SupportInbox.State(answered, new HashSet<Guid>()));
        Assert.Equal(SupportState.Answered, SupportInbox.State(answered, new HashSet<Guid> { answer.Id }));
        Assert.Equal(1, SupportInbox.Unread(new[] { sent, answered }, new HashSet<Guid>()));
    }

    [Fact]
    public void OldServerIsRecognised()
    {
        Assert.True(SupportInbox.IsMissing(404, ""));
        Assert.True(SupportInbox.IsMissing(400, "Could not find a relationship between 'support_requests' and 'support_replies'"));
        Assert.False(SupportInbox.IsMissing(401, "JWT expired"));
        Assert.True(SupportInbox.NeedsOldForm(400, "new row violates check constraint \"support_requests_kind_check\""));
        Assert.False(SupportInbox.NeedsOldForm(429, "Trop de messages en ce moment"));
    }

    [Fact]
    public void RequestsCarryTheCaptureAndTheAccount()
    {
        var message = new SupportMessage { Kind = SupportKind.Autre, Text = "Une remarque sur les couleurs.", Capture = "/9j/abc" };
        var body = Body(ServerRequests.Support(Server, message, "0.3.0", "jeton"));
        Assert.Contains("\"kind\":\"autre\"", body);
        Assert.Contains("\"capture\":\"/9j/abc\"", body);
        var old = Body(ServerRequests.Support(Server, message, "0.3.0", "jeton", oldForm: true));
        Assert.Contains("\"kind\":\"question\"", old);
        Assert.DoesNotContain("capture", old);

        var list = ServerRequests.MyMessages(Server, Session);
        Assert.Contains("support_replies(id,team,message,created_at)", Uri.UnescapeDataString(list.RequestUri!.Query));
        Assert.Contains("user_id=eq.6f1d2c1e-0000-4000-8000-000000000001", list.RequestUri!.Query);
        var reply = ServerRequests.ReplySupport(Server, Session, Guid.Parse("6f1d2c1e-0000-4000-8000-0000000000a1"), "  Merci  ");
        Assert.Equal("/rest/v1/support_replies", reply.RequestUri!.AbsolutePath);
        Assert.Contains("\"message\":\"Merci\"", Body(reply));
        Assert.Throws<ArgumentException>(() => ServerRequests.ReplySupport(Server, Session, Guid.NewGuid(), "   "));
    }

    [Fact]
    public void TipsComeFromTheWordsOfTheMessage()
    {
        var faq = new[] { new HelpEntry(1, "FL ne répond pas au lien", "Relance FL.", "midi"), new HelpEntry(2, "Exporter mes macros", "Macros.") };
        Assert.Equal(new[] { 1 }, SupportInbox.Tips("Le lien MIDI ne marche plus", SupportKind.Probleme, faq).Select(e => e.Id));
        Assert.Empty(SupportInbox.Tips("Le lien MIDI", SupportKind.Idee, faq));
        Assert.Empty(SupportInbox.Tips("a b c", SupportKind.Question, faq));
    }

    [Fact]
    public void DateLabelSaysHowLongAgo()
    {
        var now = DateTimeOffset.Parse("2026-11-20T10:00:00+00:00", System.Globalization.CultureInfo.InvariantCulture);
        Assert.Equal(Loc.F("il y a %lld j", 3), SupportInbox.DateLabel("2026-11-17T09:00:00+00:00", now));
        Assert.Equal(Loc.F("il y a %lld h", 2), SupportInbox.DateLabel("2026-11-20T07:59:00.123456+00:00", now));
        Assert.Equal("", SupportInbox.DateLabel("pas une date", now));
    }

    private static string Body(HttpRequestMessage r) => r.Content!.ReadAsStringAsync().Result;
}
