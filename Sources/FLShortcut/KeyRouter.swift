// Audit : REL-03 (configuration immuable lue sous verrou depuis le thread du tap), REL-04 / SEC-11 (propriété
//         d'un appui décidée au keyDown initial, répétitions et keyUp suivent cette décision, état purgé et borné),
//         REL-05 (destinataire réel de la frappe : PID cible), REL-06 (une touche « Action dans FL » n'est
//         avalée que si le lien est « Relié », la clé présente et l'action disponible), REL-15 (bascule une seule
//         fois malgré l'auto-répétition), REL-19 (enregistrement en cours : tout passe), REL-20 (index construit
//         par la même analyse que l'interface), SEC-05 (liste noire revérifiée), filtrage par fenêtre FL active.
// Logique pure (aucune dépendance à CoreGraphics / AppKit) : testée par FLShortcutTests.
import Foundation

/// Index immuable des raccourcis actifs : (déclencheur, contexte) → action.
struct ShortcutIndex: Equatable {
    enum RoutedAction: Equatable {
        case flAction(Int)
        case keystroke(KeyCombo)
        case macro(Macro)
    }

    struct Entry: Equatable {
        let remapID: UUID
        let action: RoutedAction
    }

    private(set) var table: [KeyCombo: [ShortcutContext: Entry]] = [:]

    init() {}

    /// Les remaps doivent avoir été analysés : `blocked` contient les ids écartés (doublon, cible interdite…).
    init(remaps: [Remap], blocked: Set<UUID>) {
        for r in remaps where r.enabled && !blocked.contains(r.id) {
            guard let trigger = r.trigger, let action = r.routedAction else { continue }
            if table[trigger]?[r.context] != nil { continue }      // le premier gagne (même règle que l'analyse)
            table[trigger, default: [:]][r.context] = Entry(remapID: r.id, action: action)
        }
    }

    var count: Int { table.values.reduce(0) { $0 + $1.count } }

    /// Fenêtre précise d'abord, puis « Partout ». Fenêtre inconnue : seulement « Partout », sauf `anyContext`
    /// (mode léger : FL applique lui-même la touche envoyée à sa fenêtre active), où une entrée de n'importe
    /// quelle fenêtre convient, dans un ordre fixe.
    func lookup(_ combo: KeyCombo, window: FLWindow?, anyContext: Bool = false) -> Entry? {
        guard let byContext = table[combo] else { return nil }
        if let window, let ctx = ShortcutContext(window: window), let e = byContext[ctx] { return e }
        if let e = byContext[.everywhere] { return e }
        guard anyContext else { return nil }
        for ctx in ShortcutContext.allCases { if let e = byContext[ctx] { return e } }
        return nil
    }
}

/// Configuration poussée par le thread principal, remplacée en bloc.
struct TapConfig: Equatable {
    var enabled = true
    var index = ShortcutIndex()
    var toggle = KeyCombo(keyCode: 3, command: true, option: true, control: true)
    var forbidden = ForbiddenTargets.physical
    var recording = false
    var flPIDs: Set<Int32> = []
    var frontmostPID: Int32 = 0
    /// Mode léger : action → touche d'origine de FL (vide sinon) ; contexte de fenêtre ignoré.
    var actionNatives: [Int: KeyCombo] = [:]
    var anyContext = false
}

/// Événement clavier réduit à ce qui sert à la décision (aucun caractère tapé n'est conservé : SEC-07).
struct RouterInput: Equatable {
    enum Kind: Equatable { case down, up, tapDisabled }
    var kind: Kind
    var combo: KeyCombo
    var isRepeat = false
    var isOwn = false
    var targetIsFL = false
}

enum RouterEffect: Equatable {
    case sendAction(Int)
    case post(KeyCombo)
    case runMacro(Macro)
    case toggleEnabled
}

struct RouterDecision: Equatable {
    var swallow: Bool
    var effects: [RouterEffect]

    static let pass = RouterDecision(swallow: false, effects: [])
    static let swallowOnly = RouterDecision(swallow: true, effects: [])
}

struct KeyRouter {
    enum Owner: Equatable {
        case toggle
        case action(Int)
        case keystroke(KeyCombo)
        case macro
    }

    /// keyCode → propriétaire de l'appui en cours. Au plus 128 entrées (codes de touche bornés).
    private(set) var owned: [UInt16: Owner] = [:]

    mutating func purge() { owned.removeAll() }

    /// L'effet décidé n'a pas pu être produit (trame non émise, injection refusée) : l'appui est rendu,
    /// ses répétitions et son keyUp passeront tels quels (REL-06 : ne jamais avaler sans effet).
    mutating func release(_ keyCode: UInt16) { owned.removeValue(forKey: keyCode) }

    mutating func route(_ e: RouterInput, config: TapConfig, link: LinkRoutingView) -> RouterDecision {
        if e.kind == .tapDisabled {
            purge()                                   // des keyUp ont pu être perdus
            return .pass
        }
        if e.isOwn { return .pass }                   // nos propres événements : jamais retraités (anti-boucle)
        let code = e.combo.keyCode
        guard code < 128 else { return .pass }

        if e.kind == .up {
            return owned.removeValue(forKey: code) != nil ? .swallowOnly : .pass
        }

        if e.isRepeat {
            guard let owner = owned[code] else { return .pass }    // appui qui ne nous appartient pas
            switch owner {
            case .keystroke(let target):
                guard e.targetIsFL, config.enabled, !config.forbidden.isForbidden(target) else { return .swallowOnly }
                return RouterDecision(swallow: true, effects: [.post(target)])
            case .toggle, .action, .macro:
                return .swallowOnly                   // jamais de bascule, d'action ni de macro répétées
            }
        }

        owned.removeValue(forKey: code)               // keyDown neuf : un keyUp manqué n'empoisonne plus la touche
        if config.recording { return .pass }

        if e.combo == config.toggle {
            owned[code] = .toggle
            return RouterDecision(swallow: true, effects: [.toggleEnabled])
        }

        guard config.enabled, e.targetIsFL,
              let entry = config.index.lookup(e.combo, window: link.knownWindow, anyContext: config.anyContext)
        else { return .pass }

        switch entry.action {
        case .flAction(let id):
            if let native = config.actionNatives[id] {          // mode léger : la touche de FL équivalente
                guard !config.forbidden.isForbidden(native) else { return .pass }
                owned[code] = .keystroke(native)
                return RouterDecision(swallow: true, effects: [.post(native)])
            }
            guard link.canRun(id) else { return .pass }        // lien inactif : la touche va à FL telle quelle
            owned[code] = .action(id)
            return RouterDecision(swallow: true, effects: [.sendAction(id)])
        case .keystroke(let target):
            guard !config.forbidden.isForbidden(target) else { return .pass }
            owned[code] = .keystroke(target)
            return RouterDecision(swallow: true, effects: [.post(target)])
        case .macro(let macro):
            owned[code] = .macro
            return RouterDecision(swallow: true, effects: [.runMacro(macro)])
        }
    }
}
