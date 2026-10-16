// Aide de FL Shortcut : questions fréquentes (dans l'app, sans réseau) et « Écrire à l'équipe ». Le message part par
// le serveur de la Communauté quand il est branché (table support_requests, avec ou sans compte : supabase/schema.sql) ;
// sinon, ou s'il échoue, par mail à l'adresse de l'équipe (build.sh : FLS_SUPPORT_EMAIL), ou en copie / ticket GitHub.
// Le diagnostic joint (si l'utilisateur le laisse coché) dit l'état de l'app, jamais ses touches, ses noms de pistes ni
// ses fichiers ; il est affiché tel quel avant l'envoi.
import AppKit
import Foundation

/// Adresse de l'équipe et ticket public, pour envoyer sans le serveur.
enum SupportConfig {
    /// build.sh : FLS_SUPPORT_EMAIL (Info.plist FLSSupportEmail) ; essai : `defaults write … supportEmail`.
    static var email: String? {
        let raw = UserDefaults.standard.string(forKey: "supportEmail")
            ?? Bundle.main.object(forInfoDictionaryKey: "FLSSupportEmail") as? String ?? ""
        let mail = raw.trimmingCharacters(in: .whitespaces)
        return !mail.isEmpty && CommunityRules.emailProblem(mail) == nil ? mail : nil
    }

    static let issuesURL = URL(string: "https://github.com/anmaprod/fl-shortcut/issues/new")!
}

enum SupportKind: String, CaseIterable, Identifiable {
    case probleme, question, idee

    var id: String { rawValue }

    var label: String {
        switch self {
        case .probleme: return "Un problème"
        case .question: return "Une question"
        case .idee: return "Une idée"
        }
    }

    var placeholder: String {
        switch self {
        case .probleme:
            return "Ce que tu faisais, ce qui devait se passer, ce qui s'est passé. Ex. : « ma macro s'arrête au 3e bloc "
                + "dans le Mixer »."
        case .question: return "Ta question, le plus précisément possible."
        case .idee: return "Ce qui te ferait gagner du temps dans FL Studio."
        }
    }
}

/// Ce que l'utilisateur envoie à l'équipe.
struct SupportMessage: Equatable {
    var kind = SupportKind.probleme
    var text = ""
    /// Pour lui répondre ; facultatif.
    var email = ""
    /// État de l'app joint (nil : décoché).
    var diagnostic: String?
}

enum SupportRules {
    static let messageRange = 10...4000

    /// Ce qui empêche l'envoi (nil : prêt) ; mêmes règles que le serveur.
    static func problem(_ m: SupportMessage) -> String? {
        let n = m.text.trimmingCharacters(in: .whitespacesAndNewlines).count
        if n < messageRange.lowerBound { return "Écris au moins quelques mots (\(messageRange.lowerBound) caractères)." }
        if n > messageRange.upperBound { return "\(messageRange.upperBound) caractères au plus." }
        let mail = m.email.trimmingCharacters(in: .whitespaces)
        if !mail.isEmpty, let why = CommunityRules.emailProblem(mail) { return why }
        return nil
    }

    /// Le message en texte, pour un mail, le presse-papiers ou un ticket.
    static func plainText(_ m: SupportMessage, appVersion: String) -> String {
        var out = "\(m.kind.label) — FL Shortcut \(appVersion)\n\n" + m.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let mail = m.email.trimmingCharacters(in: .whitespaces)
        if !mail.isEmpty { out += "\n\nPour me répondre : \(mail)" }
        if let d = m.diagnostic, !d.isEmpty { out += "\n\n— État de l'app —\n" + d }
        return out
    }

    static func subject(_ m: SupportMessage) -> String {
        let first = m.text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first.map(String.init) ?? ""
        return "FL Shortcut · \(m.kind.label) : \(first.prefix(60))"
    }

    /// Mail tout prêt pour l'app de mail.
    static func mailURL(_ m: SupportMessage, to address: String, appVersion: String) -> URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = address
        c.queryItems = [URLQueryItem(name: "subject", value: subject(m)),
                        URLQueryItem(name: "body", value: plainText(m, appVersion: appVersion))]
        return c.url
    }

    /// Ticket public sur GitHub, prérempli (sans le mail : la page est publique).
    static func issueURL(_ m: SupportMessage, appVersion: String) -> URL? {
        var publicMessage = m
        publicMessage.email = ""
        var c = URLComponents(url: SupportConfig.issuesURL, resolvingAgainstBaseURL: false)
        c?.queryItems = [URLQueryItem(name: "title", value: subject(m)),
                         URLQueryItem(name: "body", value: String(plainText(publicMessage, appVersion: appVersion).prefix(5000)))]
        return c?.url
    }
}

/// État de l'app joint au message : de quoi comprendre un problème sans rien de personnel.
enum SupportDiagnostic {
    struct Facts: Equatable {
        var appVersion: String
        var macOS: String
        var flRunning: Bool
        var flVersion: String?
        var accessibility: Bool
        var staleTCC: Bool
        var secureInput: Bool
        var paused: Bool
        var light: Bool
        var link: String
        var shortcuts: Int
        var macros: Int
        var macrosToLearn: Int
        var lastMacro: String?
        var screens: [String]
    }

    static func text(_ f: Facts) -> String {
        func yes(_ b: Bool) -> String { b ? "oui" : "non" }
        var lines = ["FL Shortcut \(f.appVersion) · \(f.macOS)"]
        lines.append("FL Studio : " + (f.flRunning ? "ouvert" + (f.flVersion.map { " (\($0))" } ?? "") : "fermé"))
        lines.append("Clavier autorisé : \(yes(f.accessibility))" + (f.staleTCC ? " (autorisation périmée)" : "")
                     + " · En pause : \(yes(f.paused)) · Saisie sécurisée : \(yes(f.secureInput))")
        lines.append("Mode : " + (f.light ? "léger (sans lien MIDI)" : "lien avec FL : \(f.link)"))
        lines.append("Raccourcis modifiés ou ajoutés : \(f.shortcuts) · Macros : \(f.macros)"
                     + (f.macrosToLearn > 0 ? " (\(f.macrosToLearn) à apprendre)" : ""))
        if let last = f.lastMacro { lines.append("Dernière macro : \(last)") }
        lines.append("Écrans : " + (f.screens.isEmpty ? "?" : f.screens.joined(separator: ", ")))
        return lines.joined(separator: "\n")
    }

    static func current(store: Store, status: AppStatus, fl: FLMonitor, link: MIDILink) -> Facts {
        let learned = MacroSpots.loadPath(.input) != nil
        let toLearn = store.library.macros.filter { MacroOutline.flags($0.blocks, learnedInput: learned).toLearn }.count
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return Facts(appVersion: MacroFileActions.appVersion,
                     macOS: "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                     flRunning: fl.running, flVersion: fl.version?.description,
                     accessibility: status.accessibilityOK, staleTCC: status.staleTCC, secureInput: status.secureInput,
                     paused: !store.enabled, light: AppMode.light, link: link.status.label,
                     shortcuts: store.remaps.count, macros: store.library.macros.count, macrosToLearn: toLearn,
                     lastMacro: status.lastMacro.map { ($0.ok ? "réussie" : "échec") + " — " + $0.text },
                     screens: NSScreen.screens.map { "\(Int($0.frame.width))×\(Int($0.frame.height))" })
    }
}

// MARK: - Questions fréquentes

struct HelpEntry: Identifiable {
    let id: Int
    let question: String
    let answer: String
    /// Mots en plus pour la recherche (synonymes).
    var keywords = ""

    /// Tous les mots de la recherche se trouvent dans la question, la réponse ou les mots en plus (sans accents ni
    /// majuscules).
    func matches(_ query: String) -> Bool {
        let words = HelpEntry.fold(query).split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
        guard !words.isEmpty else { return true }
        let haystack = HelpEntry.fold(question + " " + answer + " " + keywords)
        return words.allSatisfy { haystack.contains($0) }
    }

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
    }
}

enum HelpContent {
    static let faq: [HelpEntry] = [
        HelpEntry(id: 1, question: "Mes raccourcis ne font rien dans FL",
                  answer: "Vérifie trois choses. 1. FL Studio est la fenêtre au premier plan : tes raccourcis ne marchent "
                      + "que là. 2. FL Shortcut n'est pas en pause (⌃⌥⌘F, ou le menu de l'icône en haut de l'écran). "
                      + "3. Le clavier est autorisé : Réglages Système › Confidentialité et sécurité › Accessibilité, "
                      + "FL Shortcut coché. Quand une autre app attend un mot de passe (saisie sécurisée), les raccourcis "
                      + "se taisent le temps qu'elle le fasse.",
                  keywords: "marche pas fonctionne touche inactif rien"),
        HelpEntry(id: 2, question: "Un « ! » apparaît sur l'icône en haut de l'écran",
                  answer: "Le clavier n'est pas, ou plus, autorisé. Ouvre Réglages Système › Confidentialité et sécurité "
                      + "› Accessibilité, retire FL Shortcut avec « − », puis ajoute-le de nouveau avec « + » (dans "
                      + "Applications). Après une mise à jour de l'app, macOS demande parfois de refaire ce geste.",
                  keywords: "point exclamation alerte avertissement autorisation accessibilite barre des menus"),
        HelpEntry(id: 3, question: "Comment créer une macro ?",
                  answer: "Page Macros › « Enregistrer une macro » : FL passe devant, fais ta suite (clics, flèches, "
                      + "raccourcis), puis « Terminer » en haut à droite. Chaque geste devient un bloc : retouche-les dans "
                      + "le créateur, choisis un raccourci, puis « Tester ». Tu peux aussi partir d'un modèle.",
                  keywords: "creer nouvelle enregistrer blocs createur"),
        HelpEntry(id: 4, question: "« Enregistrer clics et touches » n'a rien enregistré",
                  answer: "FL Studio doit être ouvert et au premier plan pendant l'enregistrement : les clics et les "
                      + "touches faits ailleurs sont ignorés. Clique et tape dans les fenêtres et les menus de FL, puis "
                      + "« Terminer » dans le petit panneau en haut à droite (« Annuler » n'ajoute rien).",
                  keywords: "enregistrement clic clavier vide rien ajoute"),
        HelpEntry(id: 5, question: "Une macro est « À apprendre »",
                  answer: "Un de ses blocs clique à un endroit qu'il faut montrer une fois sur ton Mac (les positions ne "
                      + "sont jamais partagées). Ouvre la macro, choisis le bloc marqué, puis « Montrer dans FL… » et "
                      + "clique à l'endroit voulu.",
                  keywords: "apprendre position endroit montrer"),
        HelpEntry(id: 6, question: "Une macro s'arrête ou clique au mauvais endroit",
                  answer: "Le bandeau en bas du créateur dit à quel bloc elle s'est arrêtée (« Montrer le bloc »). Si FL "
                      + "a changé de taille ou d'écran, remontre l'endroit de ce bloc. Si une fenêtre de FL met du temps à "
                      + "s'ouvrir, ajoute un bloc « Attendre » juste avant.",
                  keywords: "erreur echec arrete bloque mauvais clic"),
        HelpEntry(id: 7, question: "Mettre en pause ou reprendre",
                  answer: "⌃⌥⌘F, n'importe où, ou « Mettre en pause » dans le menu de l'icône en haut de l'écran. Une "
                      + "pastille rappelle que c'est en pause.",
                  keywords: "pause reprendre arreter desactiver"),
        HelpEntry(id: 8, question: "La Communauté dit « pas encore ouverte »",
                  answer: "Le serveur de la Communauté n'est pas encore branché dans cette version. Tes raccourcis et tes "
                      + "macros marchent normalement en attendant.",
                  keywords: "communaute partage compte serveur connexion"),
        HelpEntry(id: 9, question: "Mes données sont-elles envoyées quelque part ?",
                  answer: "Non. Tes touches ne sont lues que quand FL Studio est devant, et rien n'est enregistré ni "
                      + "envoyé. Seul ce que tu publies dans la Communauté, et ce que tu écris à l'équipe depuis cette "
                      + "page, part sur internet.",
                  keywords: "vie privee donnees confidentialite securite internet"),
        HelpEntry(id: 10, question: "Désinstaller FL Shortcut",
                  answer: "Menu ⋯ en haut à droite de la fenêtre, ou menu de l'icône en haut de l'écran › « Désinstaller "
                      + "FL Shortcut… » : l'app, ses réglages et le lien avec FL sont retirés.",
                  keywords: "supprimer enlever desinstallation"),
    ]
}
