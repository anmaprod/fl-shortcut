// Aide (Windows), miroir de Sources/FLShortcut/Support.swift : questions fréquentes (dans l'app, sans réseau), message à
// l'équipe (règles, texte lu par l'équipe, sujet, ticket public sans le mail) et diagnostic joint (état de l'app,
// jamais de touches, de noms de pistes ni de fichiers). Les réponses propres au Mac (autorisations de macOS,
// enregistrement des clics) ont leur version Windows ; les autres gardent mot pour mot le texte du Mac (même anglais).
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace FLShortcut.Core;

public enum SupportKind { Probleme, Question, Idee }

public static class SupportKinds
{
    /// Valeur envoyée au serveur (`support_requests.kind`).
    public static string Raw(this SupportKind k) => k switch
    {
        SupportKind.Question => "question",
        SupportKind.Idee => "idee",
        _ => "probleme",
    };

    /// Le genre dans le message lu par l'équipe : en français, quelle que soit la langue de l'app.
    public static string TeamLabel(this SupportKind k) => k switch
    {
        SupportKind.Question => "Une question",
        SupportKind.Idee => "Une idée",
        _ => "Un problème",
    };

    public static string Label(this SupportKind k) => Loc.T(k.TeamLabel());

    public static string Placeholder(this SupportKind k) => k switch
    {
        SupportKind.Question => Loc.T("Ta question, le plus précisément possible."),
        SupportKind.Idee => Loc.T("Ce qui te ferait gagner du temps dans FL Studio."),
        _ => Loc.T("Ce que tu faisais et ce qui s'est passé."),
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
                               string? LastMacro, IReadOnlyList<string> Screens);

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
            "Mode : " + (f.Light ? "léger (sans lien MIDI)" : "lien avec FL : " + f.Link),
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

    /// Les questions fréquentes de Windows (numéros du Mac ; 2, 4 et 12 n'existent que sur Mac, 13 et 14 que sur
    /// Windows).
    public static IReadOnlyList<HelpEntry> Faq => _faq ??= new List<HelpEntry>
    {
        new(1, Loc.T("Mes raccourcis ne font rien dans FL"),
            Loc.T("Vérifie : 1. FL Studio est devant. 2. FL Shortcuts n'est pas en pause. 3. FL n'est pas lancé en administrateur."),
            "marche pas fonctionne touche inactif rien administrateur"),
        new(14, Loc.T("« FL Studio n'est pas reconnu »"),
            Loc.T("Relance FL Studio, puis FL Shortcuts."),
            "reconnu signature ouvert ferme detecte crack"),
        new(15, Loc.T("Mon antivirus bloque FL Shortcuts"),
            Loc.T("Il n'y a aucun virus. Autorise FL Shortcuts dans ton antivirus : Avast › Menu › Paramètres › Exceptions."),
            "antivirus avast virus bloque defender smartscreen exception menace"),
        new(13, Loc.T("À quoi sert loopMIDI ?"),
            Loc.T("Installe loopMIDI, puis ferme-le : rien à faire dedans. L'app crée elle-même les ports qui la relient à FL."),
            "loopmidi midi port lien organiser actions installer windows 11 25h2 services"),
        new(3, Loc.T("Comment créer une macro ?"),
            Loc.T("Page Macros : « Macro vide » ou « Modèles »."),
            "creer nouvelle blocs createur modele"),
        new(5, Loc.T("Une macro est « À apprendre »"),
            Loc.T("Remontre le clic du bloc marqué : « Montrer dans FL… »."),
            "apprendre position endroit montrer"),
        new(6, Loc.T("Une macro s'arrête ou clique au mauvais endroit"),
            Loc.T("Le message dit le bloc. Remontre son endroit ou ajoute « Attendre »."),
            "erreur echec arrete bloque mauvais clic bouge bouton"),
        new(7, Loc.T("Mettre en pause ou reprendre"),
            Loc.T("Ctrl+Alt+Maj+F. « Reprendre » dans le menu de l'icône."),
            "pause reprendre arreter desactiver"),
        new(8, Loc.T("Je n'ai pas reçu le code par mail"),
            Loc.T("Regarde tes spams, sinon « Renvoyer le code »."),
            "compte inscription confirmation code mail spam connexion mot de passe oublie"),
        new(9, Loc.T("Mes données sont-elles envoyées quelque part ?"),
            Loc.T("Tes touches ne sont lues que dans FL. Rien n'est gardé ni envoyé."),
            "vie privee donnees confidentialite securite internet"),
        new(11, Loc.T("Signaler un problème"),
            Loc.T("En bas : « Écrire à l'équipe »."),
            "bug erreur contact equipe support aide ecrire"),
        new(10, Loc.T("Désinstaller FL Shortcuts"),
            Loc.T("Menu de l'icône › « Désinstaller FL Shortcuts… »."),
            "supprimer enlever desinstallation"),
    };
}
