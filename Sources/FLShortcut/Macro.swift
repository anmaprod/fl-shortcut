// Macros : enchaînement d'étapes exécuté dans FL Studio SANS MIDI et SANS script.
// Même principe sûr que le mode léger : des événements clavier / souris envoyés au seul processus FL
// (CGEvent.postToPid), uniquement quand FL est au premier plan, jamais rien d'écrit dans FL.
// Ce fichier ne contient que des données et de la logique pure (testable) ; l'exécution est dans MacroRunner.swift.
import CoreGraphics
import Foundation

/// Un point de l'écran, retrouvé à chaque exécution à partir d'un repère (appris par l'utilisateur).
struct ClickSpot: Codable, Equatable, Hashable {
    enum Anchor: String, Codable {
        /// Position du curseur au moment où la macro démarre.
        case cursor
        /// Coin haut-gauche de la fenêtre FL qui est sous le curseur au démarrage.
        case window
        /// x depuis le curseur, y depuis le haut de la fenêtre FL (colonne d'une piste du Mixer).
        case cursorXWindowY
        /// Depuis le point du clic précédent de la macro (élément d'une liste qui vient de s'ouvrir).
        case lastClick
    }

    var anchor: Anchor
    var dx: Double
    var dy: Double

    var isFinite: Bool { dx.isFinite && dy.isFinite && abs(dx) <= 5000 && abs(dy) <= 5000 }
}

struct MacroStep: Codable, Equatable, Hashable {
    enum Kind: String, Codable {
        case key              // une touche (combinaison) envoyée à FL
        case delay            // pause (ms)
        case click            // clic gauche / droit à un point appris
        case menu             // choix dans un menu par ses titres (Accessibilité), sinon clics de secours
        case waitDialog       // attend l'ouverture d'une boîte de dialogue de FL
        case waitDialogClose  // attend sa fermeture (l'utilisateur choisit son preset)
        case chooseFile       // dans la boîte « Ouvrir » : ⌘⇧G, chemin, Entrée, Entrée
    }

    enum Button: String, Codable { case left, right }

    var kind: Kind
    var combo: KeyCombo?
    var ms = 0
    var spot: ClickSpot?
    var button: Button = .left
    var titles: [String] = []
    var fallback: [ClickSpot] = []
    var path: String?

    private enum CodingKeys: String, CodingKey { case kind, combo, ms, spot, button, titles, fallback, path }

    init(kind: Kind) { self.kind = kind }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(Kind.self, forKey: .kind)
        combo = try? c.decodeIfPresent(KeyCombo.self, forKey: .combo)
        ms = (try? c.decodeIfPresent(Int.self, forKey: .ms)) ?? 0
        spot = try? c.decodeIfPresent(ClickSpot.self, forKey: .spot)
        button = (try? c.decodeIfPresent(Button.self, forKey: .button)) ?? .left
        titles = (try? c.decodeIfPresent([String].self, forKey: .titles)) ?? []
        fallback = (try? c.decodeIfPresent([ClickSpot].self, forKey: .fallback)) ?? []
        path = try? c.decodeIfPresent(String.self, forKey: .path)
    }

    static func key(_ combo: KeyCombo) -> MacroStep { var s = MacroStep(kind: .key); s.combo = combo; return s }
    static func delay(_ ms: Int) -> MacroStep { var s = MacroStep(kind: .delay); s.ms = ms; return s }
    static func click(_ spot: ClickSpot, button: Button = .left) -> MacroStep {
        var s = MacroStep(kind: .click); s.spot = spot; s.button = button; return s
    }
    static func menu(_ titles: [String], fallback: [ClickSpot] = []) -> MacroStep {
        var s = MacroStep(kind: .menu); s.titles = titles; s.fallback = fallback; return s
    }
    static func waitDialog(_ ms: Int) -> MacroStep { var s = MacroStep(kind: .waitDialog); s.ms = ms; return s }
    static func waitDialogClose(_ ms: Int) -> MacroStep { var s = MacroStep(kind: .waitDialogClose); s.ms = ms; return s }
    static func chooseFile(_ path: String) -> MacroStep { var s = MacroStep(kind: .chooseFile); s.path = path; return s }
}

/// Une macro d'un raccourci. `quickRecord` est le modèle livré ; `custom` porte ses propres étapes
/// (écrites à la main dans le profil, jamais acceptées à l'import).
struct Macro: Codable, Equatable, Hashable {
    enum Template: String, Codable { case quickRecord, custom }

    /// Noms des positions apprises (modèle quickRecord).
    enum Spot {
        static let menuFile = "menuFile"
        static let menuOpenState = "menuOpenState"
        static let arm = "arm"
        static let inputMenu = "inputMenu"
        static let firstInput = "firstInput"
    }

    var template: Template = .quickRecord
    var name = "Enregistrement rapide"
    /// Fichier d'état de piste (.fst) à charger directement. `nil` = ouvrir la liste de FL et attendre le choix.
    var presetPath: String?
    /// Armer la piste et choisir la première entrée (clics appris).
    var armAndInput = true
    /// Allumer REC à la fin.
    var startRecording = true
    /// Touche REC de FL selon le clavier de l'utilisateur (repli : position physique de R).
    var recKey: KeyCombo?
    var spots: [String: ClickSpot] = [:]
    var steps: [MacroStep] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case template, name, presetPath, armAndInput, startRecording, recKey, spots, steps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        template = try c.decode(Template.self, forKey: .template)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Macro"
        presetPath = try? c.decodeIfPresent(String.self, forKey: .presetPath)
        armAndInput = (try? c.decodeIfPresent(Bool.self, forKey: .armAndInput)) ?? true
        startRecording = (try? c.decodeIfPresent(Bool.self, forKey: .startRecording)) ?? true
        recKey = try? c.decodeIfPresent(KeyCombo.self, forKey: .recKey)
        let lossySpots = try? c.decodeIfPresent([String: Lossy<ClickSpot>].self, forKey: .spots)
        spots = lossySpots?.compactMapValues { $0.value } ?? [:]
        let lossySteps = try? c.decodeIfPresent([Lossy<MacroStep>].self, forKey: .steps)
        steps = lossySteps?.compactMap { $0.value } ?? []
    }
}

enum MacroLibrary {
    static let maxSteps = 40
    static let maxDelayMs = 5_000
    static let maxWaitMs = 120_000
    static let maxTotalMs = 180_000
    static let requiredSpots = [Macro.Spot.arm, Macro.Spot.inputMenu, Macro.Spot.firstInput]
    /// Touche R (position physique QWERTY) si la disposition n'a pas pu être lue.
    static let fallbackRecKeyCode: UInt16 = 15

    enum BuildError: Error, Equatable {
        case missing([String])
        case invalid(String)

        var message: String {
            switch self {
            case .missing(let names):
                let labels = names.map { Self.label(for: $0) }.joined(separator: ", ")
                return "Position(s) à apprendre : \(labels)."
            case .invalid(let why):
                return why
            }
        }

        private static func label(for spot: String) -> String {
            switch spot {
            case Macro.Spot.arm: return "bouton d'armement"
            case Macro.Spot.inputMenu: return "sélecteur d'entrée"
            case Macro.Spot.firstInput: return "première entrée"
            default: return spot
            }
        }
    }

    /// Raison pour laquelle la macro ne peut pas tourner, ou `nil` si elle est prête.
    static func problem(in macro: Macro, forbidden: ForbiddenTargets) -> String? {
        if case .failure(let e) = steps(for: macro, forbidden: forbidden) { return e.message }
        return nil
    }

    /// Étapes à exécuter, ou ce qui manque. Pure : aucun accès au système de fichiers ni à l'écran.
    static func steps(for macro: Macro, forbidden: ForbiddenTargets) -> Result<[MacroStep], BuildError> {
        let built: [MacroStep]
        switch macro.template {
        case .custom:
            built = macro.steps
        case .quickRecord:
            switch quickRecordSteps(macro) {
            case .success(let s): built = s
            case .failure(let e): return .failure(e)
            }
        }
        if let why = validate(built, forbidden: forbidden) { return .failure(.invalid(why)) }
        return .success(built)
    }

    private static func quickRecordSteps(_ macro: Macro) -> Result<[MacroStep], BuildError> {
        var out: [MacroStep] = []
        // 1. Clic droit sur la piste (sous le curseur) puis File > Open mixer track state.
        out.append(.click(ClickSpot(anchor: .cursor, dx: 0, dy: 0), button: .right))
        out.append(.delay(200))
        let fallback = [macro.spots[Macro.Spot.menuFile], macro.spots[Macro.Spot.menuOpenState]].compactMap { $0 }
        out.append(.menu(["File", "Open mixer track state"], fallback: fallback.count == 2 ? fallback : []))
        out.append(.waitDialog(3_000))
        // 2. Preset : choisi à l'avance, ou liste de FL et attente du choix de l'utilisateur.
        if let path = macro.presetPath, !path.isEmpty {
            out.append(.chooseFile(path))
            out.append(.waitDialogClose(8_000))
        } else {
            out.append(.waitDialogClose(MacroLibrary.maxWaitMs))
        }
        // 3. Armer la piste, première entrée.
        if macro.armAndInput {
            let missing = requiredSpots.filter { macro.spots[$0] == nil }
            if !missing.isEmpty { return .failure(.missing(missing)) }
            out.append(.delay(250))
            out.append(.click(macro.spots[Macro.Spot.arm]!))
            out.append(.delay(150))
            out.append(.click(macro.spots[Macro.Spot.inputMenu]!))
            out.append(.delay(200))
            out.append(.click(macro.spots[Macro.Spot.firstInput]!))
            out.append(.delay(150))
        }
        // 4. REC.
        if macro.startRecording {
            out.append(.key(macro.recKey ?? KeyCombo(keyCode: fallbackRecKeyCode)))
        }
        return .success(out)
    }

    /// Bornes strictes (SEC-05) : nombre d'étapes, durées, cibles interdites, chemins sans caractères de contrôle.
    static func validate(_ steps: [MacroStep], forbidden: ForbiddenTargets) -> String? {
        guard !steps.isEmpty else { return "La macro est vide." }
        guard steps.count <= maxSteps else { return "Macro trop longue (\(maxSteps) étapes au plus)." }
        var total = 0
        for (i, s) in steps.enumerated() {
            let n = i + 1
            switch s.kind {
            case .key:
                guard let combo = s.combo, combo.isValidKey else { return "Étape \(n) : touche non prise en charge." }
                if let why = forbidden.reason(for: combo) { return "Étape \(n) : touche interdite (\(why))." }
            case .delay:
                guard (0...maxDelayMs).contains(s.ms) else { return "Étape \(n) : pause hors limites." }
                total += s.ms
            case .click:
                guard let spot = s.spot, spot.isFinite else { return "Étape \(n) : position invalide." }
            case .menu:
                guard (1...3).contains(s.titles.count), s.titles.allSatisfy({ !$0.isEmpty && $0.count <= 80 }) else {
                    return "Étape \(n) : titres de menu invalides."
                }
                guard s.fallback.count <= 3, s.fallback.allSatisfy(\.isFinite) else { return "Étape \(n) : positions de secours invalides." }
                total += 2_000
            case .waitDialog, .waitDialogClose:
                guard (100...maxWaitMs).contains(s.ms) else { return "Étape \(n) : attente hors limites." }
                total += s.ms
            case .chooseFile:
                guard let p = s.path, !p.isEmpty, p.count <= 1024,
                      !p.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                    return "Étape \(n) : chemin de fichier invalide."
                }
                total += 3_000
            }
        }
        guard total <= maxTotalMs else { return "Macro trop longue (durée totale)." }
        return nil
    }
}
