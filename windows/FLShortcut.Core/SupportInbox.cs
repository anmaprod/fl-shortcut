// Aide › Mes messages (20/11, maquette « Minimal »), miroir de Sources/FLShortcut/SupportInbox.swift : les messages
// envoyés à l'équipe avec son compte, la réponse de l'équipe (supabase/mes-messages.sql), l'état de chacun (envoyé,
// réponse vue, nouvelle réponse) et « Ça t'aide peut-être ». Ce qui a été lu reste sur ce PC : rien de sensible.
using System.Globalization;
using System.Text.Json;

namespace FLShortcut.Core;

public sealed record SupportReply(Guid Id, bool Team, string Message, string CreatedAt);

public sealed record SupportThread(Guid Id, SupportKind Kind, string Reference, string Message, string CreatedAt,
                                   IReadOnlyList<SupportReply> Replies)
{
    /// La première ligne du message (titre de la ligne dans « Mes messages »).
    public string FirstLine => Message.Split('\n', '\r').FirstOrDefault(l => l.Trim().Length > 0)?.Trim() ?? "";
}

public enum SupportState { Sent, Answered, NewAnswer }

public static class SupportInbox
{
    /// La réponse du serveur (support_requests avec support_replies) ; réponses dans l'ordre.
    public static List<SupportThread> Decode(string json)
    {
        var list = new List<SupportThread>();
        using var doc = JsonDocument.Parse(json);
        if (doc.RootElement.ValueKind != JsonValueKind.Array) return list;
        foreach (var row in doc.RootElement.EnumerateArray())
        {
            if (!Guid.TryParse(Str(row, "id"), out var id)) continue;
            var replies = new List<SupportReply>();
            if (row.TryGetProperty("support_replies", out var rs) && rs.ValueKind == JsonValueKind.Array)
                foreach (var r in rs.EnumerateArray())
                    if (Guid.TryParse(Str(r, "id"), out var rid))
                        replies.Add(new SupportReply(rid, r.TryGetProperty("team", out var t) && t.ValueKind == JsonValueKind.True,
                                                     Str(r, "message"), Str(r, "created_at")));
            replies.Sort((a, b) => string.CompareOrdinal(a.CreatedAt, b.CreatedAt));
            list.Add(new SupportThread(id, SupportKinds.FromRaw(Str(row, "kind")), Str(row, "reference"), Str(row, "message"),
                                       Str(row, "created_at"), replies));
        }
        return list;
    }

    /// La capture lue (null : sans).
    public static string? DecodeCapture(string json)
    {
        using var doc = JsonDocument.Parse(json);
        if (doc.RootElement.ValueKind != JsonValueKind.Array || doc.RootElement.GetArrayLength() == 0) return null;
        var c = Str(doc.RootElement[0], "capture");
        return c.Length > 0 ? c : null;
    }

    private static string Str(JsonElement e, string name) =>
        e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() ?? "" : "";

    /// Envoyé (pas de réponse de l'équipe), réponse vue, nouvelle réponse.
    public static SupportState State(SupportThread thread, ISet<Guid> seen)
    {
        var last = thread.Replies.LastOrDefault(r => r.Team);
        if (last is null) return SupportState.Sent;
        return seen.Contains(last.Id) ? SupportState.Answered : SupportState.NewAnswer;
    }

    public static int Unread(IEnumerable<SupportThread> threads, ISet<Guid> seen) =>
        threads.Count(t => State(t, seen) == SupportState.NewAnswer);

    /// Serveur sans mes-messages.sql : table des réponses absente.
    public static bool IsMissing(int status, string message)
    {
        var m = message.ToLowerInvariant();
        if (status == 404) return true;
        return status == 400 && (m.Contains("support_replies") || m.Contains("relationship")
            || (m.Contains("capture") && (m.Contains("does not exist") || m.Contains("could not find"))));
    }

    /// Envoi refusé par un serveur d'avant (genre « autre » ou capture inconnus) : à renvoyer sans eux.
    public static bool NeedsOldForm(int status, string message)
    {
        var m = message.ToLowerInvariant();
        return status == 400 && (m.Contains("capture") || m.Contains("support_requests_kind_check"));
    }

    /// « il y a 3 j » ; vide si la date ne se lit pas.
    public static string DateLabel(string iso, DateTimeOffset? now = null)
    {
        if (!DateTimeOffset.TryParse(iso, CultureInfo.InvariantCulture, DateTimeStyles.AssumeUniversal, out var date)) return "";
        var span = (now ?? DateTimeOffset.UtcNow) - date;
        if (span.TotalMinutes < 1) return Loc.T("à l'instant");
        if (span.TotalHours < 1) return Loc.F("il y a %lld min", (int)span.TotalMinutes);
        if (span.TotalDays < 1) return Loc.F("il y a %lld h", (int)span.TotalHours);
        return Loc.F("il y a %lld j", (int)span.TotalDays);
    }

    /// « Ça t'aide peut-être » : les questions qui parlent des mots d'au moins 4 lettres du message, 3 au plus ; rien
    /// pour une idée.
    public static List<HelpEntry> Tips(string text, SupportKind? kind, IEnumerable<HelpEntry> faq)
    {
        if (kind == SupportKind.Idee) return new();
        var words = HelpEntry.Fold(text).SplitWhere(c => !char.IsLetterOrDigit(c)).Where(w => w.Length >= 4).ToList();
        if (words.Count == 0) return new();
        return faq.Where(e => words.Any(w => HelpEntry.Fold(e.Question + " " + e.Keywords).Contains(w))).Take(3).ToList();
    }
}

file static class SplitExtensions
{
    public static string[] SplitWhere(this string s, Func<char, bool> separator)
    {
        var parts = new List<string>();
        var start = 0;
        for (var i = 0; i <= s.Length; i++)
        {
            if (i < s.Length && !separator(s[i])) continue;
            if (i > start) parts.Add(s[start..i]);
            start = i + 1;
        }
        return parts.ToArray();
    }
}
