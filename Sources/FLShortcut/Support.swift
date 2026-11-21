// Aide de FL Shortcuts : questions fréquentes (dans l'app, sans réseau) et « Écrire à l'équipe ». Le message part par
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

/// 20/11 (maquette « Minimal ») : Un bug, Une idée, Une question, Autre (genre « autre » : supabase/mes-messages.sql).
enum SupportKind: String, CaseIterable, Identifiable {
    case probleme, idee, question, autre

    var id: String { rawValue }

    var label: String {
        switch self {
        case .probleme: return String(localized: "Un bug")
        case .question: return String(localized: "Une question")
        case .idee: return String(localized: "Une idée")
        case .autre: return String(localized: "Autre")
        }
    }

    /// Le genre dans le message lu par l'équipe : en français, quelle que soit la langue du Mac.
    var teamLabel: String {
        switch self {
        case .probleme: return "Un problème"
        case .question: return "Une question"
        case .idee: return "Une idée"
        case .autre: return "Autre"
        }
    }

    var placeholder: String {
        switch self {
        case .probleme: return String(localized: "Ce qui s'est passé")
        case .question: return String(localized: "Ta question")
        case .idee: return String(localized: "Ton idée")
        case .autre: return String(localized: "Ton message")
        }
    }
}

/// Ce que l'utilisateur envoie à l'équipe.
struct SupportMessage: Equatable {
    var kind = SupportKind.probleme
    var text = ""
    /// Pour lui répondre ; facultatif.
    var email = ""
    /// Le message d'erreur signalé (bouton « Signaler ce problème » d'une macro qui échoue), tel que l'app l'a affiché.
    var error: String?
    /// État de l'app, derniers problèmes et journal de la dernière macro (nil : décoché).
    var diagnostic: String?
    /// « FLS-3F9A2C » : retrouver le message dans la boîte de l'équipe, et y répondre.
    var reference = SupportMessage.newReference()
    /// Capture facultative (JPEG en base64, SupportCapture).
    var capture: String?

    static func newReference() -> String {
        "FLS-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)
    }
}

enum SupportRules {
    static let messageRange = 10...4000
    /// Diagnostic joint : état de l'app, derniers problèmes, journal de la dernière macro.
    static let maxDiagnostic = 12_000

    /// Ce qui empêche l'envoi (nil : prêt) ; mêmes règles que le serveur.
    static func problem(_ m: SupportMessage) -> String? {
        let n = m.text.trimmingCharacters(in: .whitespacesAndNewlines).count
        if n < messageRange.lowerBound {
            return String(localized: "Écris au moins quelques mots (\(messageRange.lowerBound) caractères).")
        }
        if n > messageRange.upperBound { return String(localized: "\(messageRange.upperBound) caractères au plus.") }
        let mail = m.email.trimmingCharacters(in: .whitespaces)
        if !mail.isEmpty, let why = CommunityRules.emailProblem(mail) { return why }
        return nil
    }

    /// Le message en texte, pour un mail, le presse-papiers ou un ticket : toujours le même plan, pour lire vite.
    static func plainText(_ m: SupportMessage, appVersion: String) -> String {
        var out = "Référence : \(m.reference)\nGenre : \(m.kind.teamLabel)\nFL Shortcuts \(appVersion)"
        let mail = m.email.trimmingCharacters(in: .whitespaces)
        if !mail.isEmpty { out += "\nPour répondre : \(mail)" }
        out += "\n\n— Message —\n" + m.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let e = m.error, !e.isEmpty { out += "\n\n— Le problème signalé —\n" + e }
        if let d = m.diagnostic, !d.isEmpty { out += "\n\n— État de l'app —\n" + d }
        return out
    }

    /// « [FL Shortcuts] Problème · FLS-3F9A2C · Ma macro s'arrête… » : un filtre sur « [FL Shortcuts] » range tout.
    static func subject(_ m: SupportMessage) -> String {
        let first = m.text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").first.map(String.init) ?? ""
        let kind = m.kind.teamLabel.split(separator: " ").last.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? ""
        return "[FL Shortcuts] \(kind) · \(m.reference) · \(first.prefix(60))"
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
        /// Script de FL Shortcuts installé dans FL (le lien MIDI s'ouvre avec lui le temps d'une action).
        var scriptInstalled = false
    }

    /// Tout ce qui est joint : l'état, puis les derniers problèmes et le journal de la dernière macro s'il y en a.
    static func report(_ f: Facts, problems: String?, journal: String?) -> String {
        var out = text(f)
        if let problems { out += "\n\n— Derniers problèmes —\n" + problems }
        if let journal { out += "\n\n— Journal de la dernière macro —\n" + journal }
        return String(out.prefix(SupportRules.maxDiagnostic))
    }

    static func text(_ f: Facts) -> String {
        func yes(_ b: Bool) -> String { b ? "oui" : "non" }
        var lines = ["FL Shortcuts \(f.appVersion) · \(f.macOS)"]
        lines.append("FL Studio : " + (f.flRunning ? "ouvert" + (f.flVersion.map { " (\($0))" } ?? "") : "fermé"))
        lines.append("Clavier autorisé : \(yes(f.accessibility))" + (f.staleTCC ? " (autorisation périmée)" : "")
                     + " · En pause : \(yes(f.paused)) · Saisie sécurisée : \(yes(f.secureInput))")
        // 09/11 (« il n'y a plus de mode léger, on est avec MIDI ») : le lien MIDI s'ouvre le temps d'une action.
        lines.append("Lien MIDI avec FL : " + (f.light
            ? "ouvert le temps d'une action · script \(f.scriptInstalled ? "installé" : "pas installé")"
            : "toujours ouvert · \(f.link)"))
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
                     screens: NSScreen.screens.map { "\(Int($0.frame.width))×\(Int($0.frame.height))" },
                     scriptInstalled: FLScriptInstaller.installedScript()?.present ?? false)
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
    /// 5 questions (21/11 : « je veux juste qu'on n'ait pas à scroller… c'est les gens qui vont nous poser des
    /// questions ») : le carré rouge de l'icône et « Revenir à la touche d'origine » (le lien « Remettre ») retirés.
    static let faq: [HelpEntry] = [
        HelpEntry(id: 1, question: String(localized: "Mes raccourcis ne font rien dans FL"),
                  answer: String(localized: """
                      Vérifie trois choses. 1. Mets FL Studio devant. 2. Vérifie que FL Shortcuts n'est pas en pause : \
                      ⌃⌥⌘F. 3. Autorise le clavier : Réglages Système › Confidentialité et sécurité › Accessibilité.
                      """),
                  keywords: "marche pas fonctionne touche inactif rien"),
        HelpEntry(id: 3, question: String(localized: "Comment créer une macro ?"),
                  answer: String(localized: """
                      1. Macros › Nouvelle macro. 2. Clique sa touche, puis appuie sur celle que tu veux. 3. Ajoute ses \
                      étapes une par une.
                      """),
                  keywords: "creer nouvelle enregistrer etapes createur"),
        HelpEntry(id: 13, question: String(localized: "Comment changer la touche d'un raccourci ?"),
                  answer: String(localized: """
                      1. Raccourcis, puis la page de FL à gauche. 2. Clique la touche, puis appuie sur la nouvelle.
                      """),
                  keywords: "changer modifier touche raccourci"),
        HelpEntry(id: 7, question: String(localized: "Mettre en pause ou reprendre"),
                  answer: String(localized: "⌃⌥⌘F, n'importe où."),
                  keywords: "pause reprendre arreter desactiver"),
        HelpEntry(id: 8, question: String(localized: "Je n'ai pas reçu le code par mail"),
                  answer: String(localized: "Regarde dans les courriers indésirables. Sinon, « Renvoyer le code »."),
                  keywords: "compte inscription confirmation code mail spam connexion mot de passe oublie"),
    ]
}
