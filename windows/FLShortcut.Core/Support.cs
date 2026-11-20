// Aide (Windows), miroir de Sources/FLShortcut/Support.swift : questions fréquentes (dans l'app, sans réseau), message à
// l'équipe (règles, texte lu par l'équipe, sujet, ticket public sans le mail) et diagnostic joint (état de l'app,
// jamais de touches, de noms de pistes ni de fichiers). Les réponses propres au Mac (autorisations de macOS,
// enregistrement des clics) ont leur version Windows ; les autres gardent mot pour mot le texte du Mac (même anglais).
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace FLShortcut.Core;

/// 20/11 (maquette « Minimal », comme le Mac) : Un bug, Une idée, Une question, Autre (« autre » :
/// supabase/mes-messages.sql).
public enum SupportKind { Probleme, Idee, Question, Autre }

public static class SupportKinds
{
    /// Valeur envoyée au serveur (`support_requests.kind`).
    public static string Raw(this SupportKind k) => k switch
    {
        SupportKind.Question => "question",
        SupportKind.Idee => "idee",
        SupportKind.Autre => "autre",
        _ => "probleme",
    };

    public static SupportKind FromRaw(string? raw) => raw switch
    {
        "question" => SupportKind.Question,
        "idee" => SupportKind.Idee,
        "autre" => SupportKind.Autre,
        "probleme" => SupportKind.Probleme,
        _ => SupportKind.Question,
    };

    /// Le genre dans le message lu par l'équipe : en français, quelle que soit la langue de l'app.
    public static string TeamLabel(this SupportKind k) => k switch
    {
        SupportKind.Question => "Une question",
        SupportKind.Idee => "Une idée",
        SupportKind.Autre => "Autre",
        _ => "Un problème",
    };

    public static string Label(this SupportKind k) => k switch
    {
        SupportKind.Question => Loc.T("Une question"),
        SupportKind.Idee => Loc.T("Une idée"),
        SupportKind.Autre => Loc.T("Autre"),
        _ => Loc.T("Un bug"),
    };

    public static string Placeholder(this SupportKind k) => k switch
    {
        SupportKind.Question => Loc.T("Ta question"),
        SupportKind.Idee => Loc.T("Ton idée"),
        SupportKind.Autre => Loc.T("Ton message"),
        _ => Loc.T("Ce qui s'est passé"),
    };
}

/// Ce que l'utilisateur envoie à l'équipe.
public sealed class SupportMessage
{
    public SupportKind Kind { get; set; } = SupportKind.Probleme;
    public string Text { get; set; } = "";
    /// Pour lui répondre ; facultatif.
    public string Email { get; set; } = "";
    /// Le message d'erreur signalé (« Signaler ce problème… » après une macro ratée), tel que l'app l'a affiché.
    public string? Error { get; set; }
    /// État de l'app et derniers problèmes (null : décoché).
    public string? Diagnostic { get; set; }
    /// « FLS-3F9A2C » : retrouver le message dans la boîte de l'équipe, et y répondre.
    public string Reference { get; set; } = NewReference();
    /// Capture facultative (JPEG en base64, 1 Mo au plus : supabase/mes-messages.sql).
    public string? Capture { get; set; }

    public static string NewReference() => "FLS-" + Guid.NewGuid().ToString("N")[..6].ToUpperInvariant();
}

public static class SupportRules
{
    public const int MinMessage = 10, MaxMessage = 4000;
    /// Diagnostic joint : état de l'app et derniers problèmes.
    public const int MaxDiagnostic = 12_000;
    public const string IssuesUrl = "https://github.com/anmaprod/fl-shortcut/issues/new";

    /// Même règle que CommunityRules.emailProblem du Mac (et que le serveur).
    public static string? EmailProblem(string s)
    {
        var parts = s.Split('@');
        if (parts.Length != 2 || parts[0].Length == 0 || !parts[1].Contains('.') || s.Contains(' ') || s.Length > 254)
            return Loc.T("Adresse mail invalide.");
        return null;
    }

    /// Ce qui empêche l'envoi (null : prêt) ; mêmes règles que le serveur.
    public static string? Problem(SupportMessage m)
    {
        var n = m.Text.Trim().Length;
        if (n < MinMessage) return Loc.F("Écris au moins %lld caractères.", MinMessage);
        if (n > MaxMessage) return Loc.F("%lld caractères au plus.", MaxMessage);
        var mail = m.Email.Trim();
        return mail.Length > 0 ? EmailProblem(mail) : null;
    }

    /// Le message en texte (mail, presse-papiers, ticket) : toujours le même plan, pour lire vite.
    public static string PlainText(SupportMessage m, string appVersion)
    {
        var sb = new StringBuilder($"Référence : {m.Reference}\nGenre : {m.Kind.TeamLabel()}\nFL Shortcuts {appVersion}");
        var mail = m.Email.Trim();
        if (mail.Length > 0) sb.Append("\nPour répondre : ").Append(mail);
        sb.Append("\n\n— Message —\n").Append(m.Text.Trim());
        if (!string.IsNullOrEmpty(m.Error)) sb.Append("\n\n— Le problème signalé —\n").Append(m.Error);
        if (!string.IsNullOrEmpty(m.Diagnostic)) sb.Append("\n\n— État de l'app —\n").Append(m.Diagnostic);
        return sb.ToString();
    }

    /// « [FL Shortcuts] Problème · FLS-3F9A2C · Ma macro s'arrête… » : un filtre sur « [FL Shortcuts] » range tout.
    public static string Subject(SupportMessage m)
    {
        var first = m.Text.Trim().Split('\n')[0];
        var word = m.Kind.TeamLabel().Split(' ')[^1];
        var kind = char.ToUpper(word[0], CultureInfo.GetCultureInfo("fr-FR")) + word[1..];
        return $"[FL Shortcuts] {kind} · {m.Reference} · {(first.Length > 60 ? first[..60] : first)}";
    }

    /// Ticket public sur GitHub, prérempli (sans le mail : la page est publique).
    public static Uri IssueUri(SupportMessage m, string appVersion)
    {
        var copy = new SupportMessage { Kind = m.Kind, Text = m.Text, Error = m.Error, Diagnostic = m.Diagnostic, Reference = m.Reference };
        var body = PlainText(copy, appVersion);
        if (body.Length > 5000) body = body[..5000];
        return new Uri($"{IssuesUrl}?title={Uri.EscapeDataString(Subject(m))}&body={Uri.EscapeDataString(body)}");
    }
}

/// État de l'app joint au message (Windows) : de quoi comprendre un problème sans rien de personnel.
public static class SupportDiagnostic
{
    public sealed record Facts(string AppVersion, string Windows, bool FlRunning, string? FlVersion, bool FlUnrecognized,
                               bool FlElevated, bool Paused, bool Light, string Link, int Shortcuts, int Macros,
                               string? LastMacro, IReadOnlyList<string> Screens, bool ScriptInstalled = false);

    public static string Text(Facts f)
    {
        static string Yes(bool b) => b ? "oui" : "non";
        var fl = f.FlRunning ? "ouvert" + (f.FlVersion is { } v ? $" ({v})" : "") : "fermé";
        if (f.FlUnrecognized) fl += " · pas reconnu (signature)";
        if (f.FlElevated) fl += " · lancé en administrateur";
        var lines = new List<string>
        {
            $"FL Shortcuts {f.AppVersion} · {f.Windows}",
            "FL Studio : " + fl,
            "En pause : " + Yes(f.Paused),
            // 09/11 (« il n'y a plus de mode léger, on est avec MIDI ») : le lien MIDI s'ouvre le temps d'une action.
            "Lien MIDI avec FL : " + (f.Light
                ? "ouvert le temps d'une action · script " + (f.ScriptInstalled ? "installé" : "pas installé")
                : "toujours ouvert · " + f.Link),
            $"Raccourcis modifiés ou ajoutés : {f.Shortcuts} · Macros : {f.Macros}",
        };
        if (f.LastMacro is { } last) lines.Add("Dernière macro : " + last);
        lines.Add("Écrans : " + (f.Screens.Count == 0 ? "?" : string.Join(", ", f.Screens)));
        return string.Join("\n", lines);
    }

    /// Tout ce qui est joint : l'état, puis les derniers problèmes s'il y en a.
    public static string Report(Facts f, string? problems)
    {
        var text = Text(f);
        if (problems is not null) text += "\n\n— Derniers problèmes —\n" + problems;
        return text.Length > SupportRules.MaxDiagnostic ? text[..SupportRules.MaxDiagnostic] : text;
    }
}

public sealed record HelpEntry(int Id, string Question, string Answer, string Keywords = "")
{
    /// Tous les mots de la recherche se trouvent dans la question, la réponse ou les mots en plus (sans accents ni
    /// majuscules).
    public bool Matches(string query)
    {
        var words = Regex.Split(Fold(query), @"[\s\p{P}]+").Where(w => w.Length > 0).ToArray();
        if (words.Length == 0) return true;
        var haystack = Fold(Question + " " + Answer + " " + Keywords);
        return words.All(haystack.Contains);
    }

    public static string Fold(string s)
    {
        var sb = new StringBuilder();
        foreach (var c in s.Normalize(NormalizationForm.FormD))
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
        return sb.ToString().Normalize(NormalizationForm.FormC).ToLowerInvariant();
    }

    /// Une réponse « Vérifie trois choses. 1. … 2. … 3. … » coupée en son début et ses étapes (numérotées 1, 2, 3… à
    /// la suite) ; null si elle n'en a pas au moins deux (HelpEntry.steps du Mac).
    public static (string Intro, List<string> Steps)? Steps(string answer)
    {
        var cuts = new List<Match>();
        foreach (Match m in Regex.Matches(answer, @"(?:^|\s)(\d)\.\s"))
            if (int.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture) == cuts.Count + 1) cuts.Add(m);
        if (cuts.Count < 2) return null;
        var intro = answer[..cuts[0].Index].Trim();
        var steps = new List<string>();
        for (var i = 0; i < cuts.Count; i++)
        {
            var start = cuts[i].Index + cuts[i].Length;
            var end = i + 1 < cuts.Count ? cuts[i + 1].Index : answer.Length;
            steps.Add(answer[start..end].Trim());
        }
        return (intro, steps);
    }
}

public static class HelpContent
{
    private static IReadOnlyList<HelpEntry>? _faq;

    /// Les 7 questions de la maquette « Minimal » (vidéo du 20/11 : « je ne veux pas qu'on ait à scroller, quitte à
    /// enlever les questions les plus débiles »), comme le Mac ; sur Windows, « FL ne répond pas au lien » (16) à la
    /// place du carré rouge de l'icône (2, Mac seulement).
    public static IReadOnlyList<HelpEntry> Faq => _faq ??= new List<HelpEntry>
    {
        new(1, Loc.T("Mes raccourcis ne font rien dans FL"),
            Loc.T("Vérifie trois choses. 1. Mets FL Studio devant. 2. Vérifie que FL Shortcuts n'est pas en pause : Ctrl+Alt+Maj+F. 3. FL ne doit pas être lancé en administrateur."),
            "marche pas fonctionne touche inactif rien administrateur"),
        new(16, Loc.T("FL ne répond pas au lien"),
            Loc.T("Quitte et rouvre FL : il voit le lien seulement à son ouverture. Puis MIDI Settings : Controller type « FL Shortcuts », même Port pour la sortie « FL Shortcuts »."),
            "lien muet repond attente organiser midi settings port controller relancer rouvrir loopmidi"),
        new(3, Loc.T("Comment créer une macro ?"),
            Loc.T("1. Macros › Nouvelle macro. 2. Clique sa touche, puis appuie sur celle que tu veux. 3. Ajoute ses étapes une par une."),
            "creer nouvelle enregistrer etapes createur"),
        new(13, Loc.T("Comment changer la touche d'un raccourci ?"),
            Loc.T("1. Raccourcis, puis la page de FL à gauche. 2. Clique la touche, puis appuie sur la nouvelle."),
            "changer modifier touche raccourci"),
        new(14, Loc.T("Revenir à la touche d'origine"),
            Loc.T("Clique « Remettre » à côté de la touche changée."),
            "reinitialiser origine remettre defaut"),
        new(7, Loc.T("Mettre en pause ou reprendre"),
            Loc.T("Ctrl+Alt+Maj+F, n'importe où."),
            "pause reprendre arreter desactiver"),
        new(8, Loc.T("Je n'ai pas reçu le code par mail"),
            Loc.T("Regarde dans les courriers indésirables. Sinon, « Renvoyer le code »."),
            "compte inscription confirmation code mail spam connexion mot de passe oublie"),
    };
}
