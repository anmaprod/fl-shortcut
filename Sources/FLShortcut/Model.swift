// Audit : REL-01 (décodage tolérant champ par champ et élément par élément, actions inconnues conservées et
//         désactivées, migration du format v1, ids dédoublonnés), REL-11 / REL-12 / audit 05 §6 (profils
//         Recommandé / Ableton dans FL / Logic Pro dans FL / Vide, aucune touche seule ni ⌃←/⌃→ dans le profil
//         par défaut),
//         REL-17 (Fn / pavé numérique / Verr. Maj ne font pas partie de la combinaison), REL-20 (une seule
//         analyse sert à l'index ET à l'interface ; clé d'unicité (déclencheur, contexte)), SEC-05 (validation
//         stricte : bornes des keyCodes, touches modificatrices refusées, liste noire, détection de boucles,
//         import validé avec récapitulatif), PROTOCOL.md §6 (ids d'action du protocole).
import AppKit
import CoreGraphics
import Foundation

// MARK: - Combinaison de touches

/// Une combinaison de touches (touche physique + ⌘ ⌥ ⌃ ⇧). Fn, pavé numérique et Verr. Maj sont ignorés.
struct KeyCombo: Codable, Hashable {
    var keyCode: UInt16
    var command = false
    var option = false
    var control = false
    var shift = false

    /// Touches modificatrices elles-mêmes (⌘ ⇧ ⇪ ⌥ ⌃ droite/gauche, Fn) : jamais un déclencheur ni une cible.
    static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    init(keyCode: UInt16, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false) {
        self.keyCode = keyCode
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

    /// Seuls ⌘ ⌥ ⌃ ⇧ comptent : les drapeaux parasites (Fn, pavé numérique, Verr. Maj) sont masqués.
    init(keyCode: UInt16, flags: CGEventFlags) {
        self.init(keyCode: keyCode,
                  command: flags.contains(.maskCommand),
                  option: flags.contains(.maskAlternate),
                  control: flags.contains(.maskControl),
                  shift: flags.contains(.maskShift))
    }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.init(keyCode: keyCode,
                  command: modifiers.contains(.command),
                  option: modifiers.contains(.option),
                  control: modifiers.contains(.control),
                  shift: modifiers.contains(.shift))
    }

    private enum CodingKeys: String, CodingKey { case keyCode, command, option, control, shift }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try c.decode(UInt16.self, forKey: .keyCode)
        command = (try? c.decodeIfPresent(Bool.self, forKey: .command)) ?? false
        option = (try? c.decodeIfPresent(Bool.self, forKey: .option)) ?? false
        control = (try? c.decodeIfPresent(Bool.self, forKey: .control)) ?? false
        shift = (try? c.decodeIfPresent(Bool.self, forKey: .shift)) ?? false
    }

    var hasModifiers: Bool { command || option || control || shift }

    /// Touche qui sert aussi à taper dans FL (texte, lettres d'un menu, clavier-piano) : sans ⌘ ⌃ ⌥ (⇧ compris :
    /// majuscules), hors touches de fonction. Un raccourci de ce genre laisse la touche à FL quand elle y sert.
    var isTypingKey: Bool { !command && !control && !option && !KeyNames.functionKeys.contains(keyCode) }

    /// keyCode virtuel borné (0…127) et pas une touche modificatrice.
    var isValidKey: Bool { keyCode < 128 && !Self.modifierKeyCodes.contains(keyCode) }

    var cgFlags: CGEventFlags {
        var f = CGEventFlags()
        if command { f.insert(.maskCommand) }
        if option { f.insert(.maskAlternate) }
        if control { f.insert(.maskControl) }
        if shift { f.insert(.maskShift) }
        return f
    }

    var modifierSymbols: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        return s
    }

    func displayName(layout: KeyboardLayout) -> String { modifierSymbols + KeyNames.name(for: keyCode, layout: layout) }

    /// Libellé selon la disposition active (thread principal).
    var display: String { displayName(layout: SystemKeyboardLayout()) }
}

// MARK: - Contexte (fenêtre FL)

enum ShortcutContext: String, Codable, CaseIterable, Identifiable {
    case everywhere, pianoRoll, playlist, mixer, channelRack, browser

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everywhere: return "Partout"
        case .pianoRoll: return "Piano Roll"
        case .playlist: return "Playlist"
        case .mixer: return "Mixer"
        case .channelRack: return "Channel Rack"
        case .browser: return "Browser"
        }
    }

    /// Contexte d'un raccourci ajouté depuis une page : la fenêtre de FL de cette page, sinon « Partout ».
    init(page: FLSection) {
        switch page {
        case .playlist: self = .playlist
        case .pianoRoll: self = .pianoRoll
        case .channelRack: self = .channelRack
        case .mixer: self = .mixer
        case .browser: self = .browser
        case .general, .transport, .patterns: self = .everywhere
        }
    }

    /// Contexte correspondant à la fenêtre FL active (CC 117), s'il y en a un.
    init?(window: FLWindow) {
        switch window {
        case .pianoRoll: self = .pianoRoll
        case .playlist: self = .playlist
        case .mixer: self = .mixer
        case .channelRack: self = .channelRack
        case .browser: self = .browser
        default: return nil
        }
    }
}

// MARK: - Raccourci

/// Un raccourci : déclencheur (+ contexte) → action du script FL ou touche envoyée à FL.
struct Remap: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case flAction      // « Action dans FL » (trame authentifiée)
        case keystroke     // « Touche de FL » (frappe envoyée au seul processus FL)
        case macro         // « Macro » : enchaînement de clics / touches dans FL, sans MIDI (Macro.swift)
    }

    var id = UUID()
    var enabled = true
    var trigger: KeyCombo?
    var context: ShortcutContext = .everywhere
    var kind: Kind = .flAction
    /// Id du protocole (PROTOCOL.md §6). `nil` si l'action est inconnue de cette version.
    var actionID: Int? = 1
    /// Action illisible conservée telle quelle (profil plus récent relu par une version plus ancienne).
    var unknownAction: String?
    var target: KeyCombo?
    var macro: Macro?
    /// Macro en blocs de la bibliothèque (macros.json) lancée par ce raccourci. Doublée à l'écriture d'un lien caché
    /// `unknownAction = "macroRef:<uuid>"` : une ancienne version de l'app le conserve (sans connaître `macroRef`),
    /// et cette version s'en sert pour retrouver la macro si la clé `macroRef` a disparu.
    var macroRef: UUID?
    /// Page de FL Shortcuts où le raccourci a été ajouté (« + » de la page Mixer…) : il y est listé. nil : ajouté
    /// depuis « Mes raccourcis », ou par une version qui ne connaissait pas les pages.
    var page: FLSection?

    /// Préfixe du lien caché vers la bibliothèque.
    static let macroRefPrefix = "macroRef:"

    init(trigger: KeyCombo?, action: Int, context: ShortcutContext = .everywhere) {
        self.trigger = trigger
        self.actionID = action
        self.context = context
    }

    init(trigger: KeyCombo?, sends target: KeyCombo, context: ShortcutContext = .everywhere) {
        self.trigger = trigger
        self.kind = .keystroke
        self.actionID = nil
        self.target = target
        self.context = context
    }

    init(trigger: KeyCombo?, macro: Macro, context: ShortcutContext = .everywhere) {
        self.trigger = trigger
        self.kind = .macro
        self.actionID = nil
        self.macro = macro
        self.context = context
    }

    /// Raccourci d'une macro de la bibliothèque.
    init(trigger: KeyCombo?, macroRef: UUID, context: ShortcutContext = .everywhere) {
        self.trigger = trigger
        self.kind = .macro
        self.actionID = nil
        self.macroRef = macroRef
        self.context = context
    }

    init() {}

    var routedAction: ShortcutIndex.RoutedAction? { indexedAction(forbidden: .physical) }

    /// Programme de la macro du raccourci : bibliothèque (déjà compilée par le Store), sinon modèle ou ancienne
    /// macro portés par le profil (compilés, en cache). nil : aucune macro.
    func macroProgram(forbidden: ForbiddenTargets, programs: [UUID: MacroProgram]) -> MacroProgram? {
        if let ref = macroRef { return programs[ref] }
        return macro.map { MacroProgram.compile($0, forbidden: forbidden) }
    }

    /// Macro : programme compilé (en cache) avec la liste noire donnée ; jamais d'action pour une macro qui ne
    /// peut pas tourner.
    func indexedAction(forbidden: ForbiddenTargets, programs: [UUID: MacroProgram] = [:]) -> ShortcutIndex.RoutedAction? {
        switch kind {
        case .flAction: return actionID.map { .flAction($0) }
        case .keystroke: return target.map { .keystroke($0) }
        case .macro:
            guard let program = macroProgram(forbidden: forbidden, programs: programs) else { return nil }
            return program.isRunnable ? .macro(program) : nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, enabled, trigger, context, kind, action, actionID, unknownAction, target, macro, macroRef, page
    }

    /// Décodage tolérant : chaque champ manquant prend sa valeur par défaut ; une action, un type ou un
    /// contexte inconnu désactive la ligne sans la perdre (REL-01).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        trigger = try? c.decodeIfPresent(KeyCombo.self, forKey: .trigger)
        target = try? c.decodeIfPresent(KeyCombo.self, forKey: .target)
        unknownAction = try? c.decodeIfPresent(String.self, forKey: .unknownAction)
        macro = try? c.decodeIfPresent(Macro.self, forKey: .macro)
        macroRef = try? c.decodeIfPresent(UUID.self, forKey: .macroRef)
        page = (try? c.decodeIfPresent(String.self, forKey: .page)).flatMap { FLSection(rawValue: $0) }

        if let raw = try? c.decodeIfPresent(String.self, forKey: .context) {
            if let ctx = ShortcutContext(rawValue: raw) {
                context = ctx
            } else {
                context = .everywhere
                enabled = false
            }
        }

        let rawKind = try? c.decodeIfPresent(String.self, forKey: .kind)
        if rawKind == nil || rawKind == Kind.flAction.rawValue {
            kind = .flAction
        } else if rawKind == Kind.keystroke.rawValue {
            kind = .keystroke
        } else if rawKind == Kind.macro.rawValue {
            kind = .macro
        } else {
            kind = .flAction
            actionID = nil
            unknownAction = "type:" + (rawKind ?? "?")
            enabled = false
            return
        }

        switch kind {
        case .keystroke:
            actionID = nil
        case .macro:
            actionID = nil
            // Profil réécrit par une ancienne version (clé `macroRef` perdue) : le lien caché la retrouve. Une
            // macro mise à la place entre-temps garde la priorité.
            if macroRef == nil, macro == nil, let link = unknownAction, link.hasPrefix(Self.macroRefPrefix) {
                macroRef = UUID(uuidString: String(link.dropFirst(Self.macroRefPrefix.count)))
            }
            if macroRef != nil, unknownAction?.hasPrefix(Self.macroRefPrefix) == true { unknownAction = nil }
        case .flAction:
            let rawID = try? c.decodeIfPresent(Int.self, forKey: .actionID)
            let rawName = try? c.decodeIfPresent(String.self, forKey: .action)
            if let id = rawID, FLActions.isKnown(id) {
                actionID = id
            } else if let name = rawName, let id = FLActions.id(forKey: name) ?? FLActions.v1Names[name] {
                actionID = id
            } else {
                actionID = nil
                unknownAction = rawName ?? rawID.map { "id:\($0)" } ?? unknownAction ?? "?"
                enabled = false                      // jamais exécuter une action « devinée »
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(enabled, forKey: .enabled)
        try c.encodeIfPresent(trigger, forKey: .trigger)
        try c.encode(context, forKey: .context)
        try c.encode(kind, forKey: .kind)
        if kind == .flAction, let actionID, let info = FLActions.info(actionID) {
            try c.encode(info.key, forKey: .action)
            try c.encode(actionID, forKey: .actionID)
        }
        if kind == .macro, let ref = macroRef {
            try c.encode(ref, forKey: .macroRef)
            try c.encode(Self.macroRefPrefix + ref.uuidString, forKey: .unknownAction)
        } else if unknownAction?.hasPrefix(Self.macroRefPrefix) != true {
            try c.encodeIfPresent(unknownAction, forKey: .unknownAction)
        }
        try c.encodeIfPresent(target, forKey: .target)
        if kind == .macro, macroRef == nil { try c.encodeIfPresent(macro, forKey: .macro) }
        try c.encodeIfPresent(page?.rawValue, forKey: .page)
    }

    /// Raccourci personnel listé sur cette page : ajouté depuis elle, ou (ajouté sans page) visant sa fenêtre de FL.
    func belongs(to section: FLSection) -> Bool {
        if let page { return page == section }
        let ctx = ShortcutContext(page: section)
        return ctx != .everywhere && context == ctx
    }
}

// MARK: - Fichier de profil

/// Décode un élément sans faire échouer le tableau entier.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

enum ProfileCodec {
    static let currentVersion = 2

    struct Decoded {
        var remaps: [Remap]
        /// 1 = tableau nu de la v1 ; 2 = fichier versionné.
        var sourceVersion: Int
        /// Éléments illisibles ignorés.
        var dropped: Int
    }

    enum Failure: Error, LocalizedError {
        case unreadable
        var errorDescription: String? { "Format de profil illisible." }
    }

    private struct Versioned: Decodable {
        let version: Int?
        let remaps: [Lossy<Remap>]
    }

    private struct FileOut: Encodable {
        let version: Int
        let remaps: [Remap]
    }

    static func decode(_ data: Data) throws -> Decoded {
        let decoder = JSONDecoder()
        let items: [Lossy<Remap>]
        let version: Int
        if let file = try? decoder.decode(Versioned.self, from: data) {
            items = file.remaps
            version = file.version ?? currentVersion
        } else if let legacy = try? decoder.decode([Lossy<Remap>].self, from: data) {
            items = legacy
            version = 1
        } else {
            throw Failure.unreadable
        }
        var seen = Set<UUID>()
        var remaps: [Remap] = []
        for item in items {
            guard var r = item.value else { continue }
            if !seen.insert(r.id).inserted { r.id = UUID() }      // ids en double : ForEach indéfini
            remaps.append(r)
        }
        return Decoded(remaps: remaps, sourceVersion: version, dropped: items.count - remaps.count)
    }

    static func encode(_ remaps: [Remap]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(FileOut(version: currentVersion, remaps: remaps))
    }
}

// MARK: - Texte importé affiché

extension String {
    /// Texte venu d'un profil importé, affiché dans l'interface (relecture 11) : sans caractères de contrôle ni de
    /// mise en forme invisibles (inversion bidi U+202E, largeur nulle…) qui pourraient maquiller un libellé, et
    /// raccourci. Text n'interprète que le Markdown des littéraux : une variable String est affichée telle quelle.
    func displaySafe(max: Int = 40) -> String {
        var view = String.UnicodeScalarView()
        for scalar in unicodeScalars
        where scalar.properties.generalCategory != .control && scalar.properties.generalCategory != .format {
            view.append(scalar)
        }
        let cleaned = String(view)
        return cleaned.count > max ? String(cleaned.prefix(max)) + "…" : cleaned
    }
}

// MARK: - Analyse (une seule fonction pour l'index et l'interface)

enum ShortcutIssue: Hashable {
    case noTrigger
    case noTarget
    case invalidKey
    case unknownAction(String)
    case forbiddenTarget(String)
    case reservedToggle
    case duplicate
    case bareKey
    case macOSConflict(String)
    case flConflict(String)
    case loop
    case unavailable(String)
    case macroInvalid(String)
    /// Créateur : macro pas encore prête, raccourci gardé mais inactif tant que le bloc n'est pas réglé (le Store,
    /// lui, l'écarte avec `macroInvalid`).
    case macroWaiting(String)

    /// Bloquant : la ligne n'entre pas dans l'index.
    var isBlocking: Bool {
        switch self {
        case .noTrigger, .noTarget, .invalidKey, .unknownAction, .forbiddenTarget, .reservedToggle, .duplicate, .macroInvalid:
            return true
        case .bareKey, .macOSConflict, .flConflict, .loop, .unavailable, .macroWaiting:
            return false
        }
    }

    var message: String {
        switch self {
        case .noTrigger: return "Aucun raccourci défini."
        case .noTarget: return "Aucune touche de FL choisie."
        case .invalidKey: return "Touche non prise en charge."
        case .unknownAction(let raw): return "Action inconnue (« \(raw.displaySafe()) ») : mets à jour FL Shortcuts."
        case .forbiddenTarget(let why): return "Cible interdite : \(why)."
        case .reservedToggle: return "Réservé à ⌃⌥⌘F (mettre FL Shortcuts en pause)."
        case .duplicate: return "Déjà utilisé dans ce contexte : seul le premier compte."
        case .bareKey: return "Touche seule : laissée à FL quand tu tapes du texte, qu'un menu de FL est ouvert ou que le clavier-piano est actif."
        case .macOSConflict(let what): return "Conflit : \(what)."
        case .flConflict(let what): return "Remplace un raccourci natif — \(what)."
        case .loop: return "La touche envoyée est aussi un déclencheur : elle sera envoyée telle quelle, sans enchaînement."
        case .unavailable(let why): return why
        case .macroInvalid(let why): return why
        case .macroWaiting(let why): return why
        }
    }
}

struct AnalysisContext {
    var toggle: KeyCombo
    var forbidden: ForbiddenTargets
    var conflicts: ConflictTable
    var availability: (Int) -> ActionAvailability
    /// Programmes de la bibliothèque (Store.recompute), par id de macro.
    var programs: [UUID: MacroProgram] = [:]
}

enum ShortcutAnalyzer {
    static func analyze(_ remaps: [Remap], context: AnalysisContext) -> [UUID: [ShortcutIssue]] {
        var out: [UUID: [ShortcutIssue]] = [:]
        var seen: [KeyCombo: Set<ShortcutContext>] = [:]
        var activeTriggers = Set<KeyCombo>()

        for r in remaps {
            var list: [ShortcutIssue] = []
            switch r.kind {
            case .flAction:
                if let id = r.actionID {
                    if case .unavailable(let why) = context.availability(id) { list.append(.unavailable(why)) }
                } else {
                    list.append(.unknownAction(r.unknownAction ?? "?"))
                }
            case .keystroke:
                if let t = r.target {
                    if !t.isValidKey { list.append(.invalidKey) }
                    else if let why = context.forbidden.reason(for: t) { list.append(.forbiddenTarget(why)) }
                } else {
                    list.append(.noTarget)
                }
            case .macro:
                if let ref = r.macroRef {
                    if let program = context.programs[ref] {
                        if let why = program.problem { list.append(.macroInvalid(why)) }
                    } else {
                        list.append(.macroInvalid("Macro introuvable dans la bibliothèque (supprimée ?)."))
                    }
                } else if let m = r.macro {
                    if let why = MacroLibrary.problem(in: m, forbidden: context.forbidden) { list.append(.macroInvalid(why)) }
                } else {
                    list.append(.macroInvalid("Aucune macro configurée."))
                }
            }

            if let t = r.trigger {
                if !t.isValidKey { list.append(.invalidKey) }
                if t == context.toggle { list.append(.reservedToggle) }
                if !t.hasModifiers && !KeyNames.functionKeys.contains(t.keyCode) { list.append(.bareKey) }
                if let m = context.conflicts.macOSConflict(t) { list.append(.macOSConflict(m)) }
                if let f = context.conflicts.flConflict(t) { list.append(.flConflict(f)) }
                if r.enabled && !list.contains(where: \.isBlocking) {
                    if seen[t]?.contains(r.context) == true {
                        list.append(.duplicate)
                    } else {
                        seen[t, default: []].insert(r.context)
                        activeTriggers.insert(t)
                    }
                }
            } else {
                list.append(.noTrigger)
            }
            out[r.id] = list
        }

        // Boucles : une touche envoyée qui est aussi un déclencheur actif (les frappes injectées sont marquées
        // et ne sont jamais retraitées, mais l'utilisateur doit le savoir).
        for r in remaps where r.enabled && r.kind == .keystroke {
            guard let t = r.target, activeTriggers.contains(t), out[r.id]?.contains(where: \.isBlocking) == false else { continue }
            out[r.id, default: []].append(.loop)
        }
        return out
    }

    static func blocked(_ issues: [UUID: [ShortcutIssue]]) -> Set<UUID> {
        Set(issues.compactMap { $0.value.contains(where: \.isBlocking) ? $0.key : nil })
    }
}

// MARK: - Profils livrés

enum ProfilePreset: String, CaseIterable, Identifiable {
    case recommended, ableton, logic, empty

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recommended: return "Recommandé"
        case .ableton: return "Ableton dans FL"
        case .logic: return "Logic Pro dans FL"
        case .empty: return "Vide"
        }
    }

    var summary: String {
        switch self {
        case .recommended: return "⌃1…⌃5 pour les fenêtres, ⌃D/⌃F patterns, ⌃T/⌃S mute/solo, ⌃M métronome, ⌘⇧Z rétablir, ⌃R enregistrement rapide (macro). Rien n'écrase FL."
        case .ableton: return "Les raccourcis d'Ableton Live font la même chose dans FL : F9 enregistre, ⌘D duplique, ⌘E découpe, "
            + "⌘J consolide, ⌘U quantize, ⌘R renomme, 0 coupe le son de la sélection, B dessine, O métronome, ⌘4 "
            + "magnétisme, ⌘+/⌘− et Z zooment, ⌘⌥B Browser, ⌘⌥M Mixer, ⇧⇥ Piano Roll, ⌘Z annule pas à pas. "
            + "Remplace certaines touches de FL (F9, B, O, Z…)."
        case .logic: return "Les raccourcis de Logic Pro font la même chose dans FL : Retour revient au début, K métronome, "
            + "X Mixer, P Piano Roll, F Browser, Y instruments et effets, T outils, Q quantize, ⌘T découpe, ⌘R répète, "
            + "⌘J joint, ⌃M coupe le son des clips, ⌘←/⌘→ et Z zooment, « , » et « . » changent de mesure, ⌘K clavier "
            + "musical, ⌘B exporte. Remplace certaines touches de FL (P, F, T, Z…)."
        case .empty: return "Aucun raccourci."
        }
    }

    /// Macro livrée en exemple : « Enregistrement rapide » sur ⌃R (positions à apprendre dans sa fiche).
    static func exampleMacro(layout: KeyboardLayout) -> Remap {
        var macro = Macro()
        macro.recKey = AppMode.nativeEquivalent(of: 3, layout: layout)
        let r = KeyNames.keyCode(for: "r", layout: layout) ?? 15
        return Remap(trigger: KeyCombo(keyCode: r, control: true), macro: macro)
    }

    /// Lettres résolues selon la disposition (repli QWERTY), chiffres par position physique.
    func remaps(layout: KeyboardLayout) -> [Remap] {
        func key(_ ch: String, _ fallback: UInt16) -> UInt16 { KeyNames.keyCode(for: ch, layout: layout) ?? fallback }
        func cmdKey(_ ch: String, _ fallback: UInt16) -> UInt16 { KeyNames.commandKeyCode(for: ch, layout: layout) ?? fallback }
        let digits: [UInt16] = [18, 19, 20, 21, 23]          // 1…5 de la rangée des chiffres
        let windows = [30, 31, 32, 33, 34]                    // Playlist, Channel Rack, Piano Roll, Mixer, Browser
        let redo = Remap(trigger: KeyCombo(keyCode: cmdKey("z", 6), command: true, shift: true), action: 37)
        /// Caractère résolu selon la disposition (avec ⌘ : la touche qui le produit avec ⌘), repli QWERTY.
        func ch(_ c: String, _ fallback: UInt16, cmd: Bool = false, opt: Bool = false, ctrl: Bool = false,
                shift: Bool = false) -> KeyCombo {
            KeyCombo(keyCode: cmd ? cmdKey(c, fallback) : key(c, fallback), command: cmd, option: opt, control: ctrl,
                     shift: shift)
        }
        /// Touche physique (F1…F12, flèches, pavé numérique, chiffres de la rangée).
        func kc(_ code: UInt16, cmd: Bool = false, opt: Bool = false, shift: Bool = false) -> KeyCombo {
            KeyCombo(keyCode: code, command: cmd, option: opt, control: false, shift: shift)
        }
        /// Ta touche → la touche de FL, dans la fenêtre de sa page (FL Shortcuts la montre sur cette ligne).
        func sends(_ trigger: KeyCombo, _ target: KeyCombo, _ context: ShortcutContext = .everywhere) -> Remap {
            Remap(trigger: trigger, sends: target, context: context)
        }
        let undo = sends(ch("z", 6, cmd: true), ch("z", 6, cmd: true, opt: true))   // ⌘Z : annuler pas à pas (⌘⌥Z)

        switch self {
        case .recommended:
            var list = zip(digits, windows).map { Remap(trigger: KeyCombo(keyCode: $0, control: true), action: $1) }
            list += [
                Remap(trigger: KeyCombo(keyCode: key("d", 2), control: true), action: 14),   // pattern précédent
                Remap(trigger: KeyCombo(keyCode: key("f", 3), control: true), action: 13),   // pattern suivant
                Remap(trigger: KeyCombo(keyCode: key("t", 17), control: true), action: 21),  // mute
                Remap(trigger: KeyCombo(keyCode: key("s", 1), control: true), action: 22),   // solo
                Remap(trigger: KeyCombo(keyCode: key("m", 46), control: true), action: 4),   // métronome
                redo,
                Self.exampleMacro(layout: layout),
            ]
            return list
        case .ableton:
            // Raccourcis par défaut d'Ableton Live 12 (manuel d'Ableton, « Live Keyboard Shortcuts »), chacun envoyé
            // comme la touche de FL qui fait la même chose : rien ne demande le script, sauf ⌘⇧Z (rétablir).
            return [
                sends(kc(101), ch("r", 15)),                                            // F9 : enregistrer (R)
                sends(kc(48, shift: true), kc(98)),                                     // ⇧⇥ : vue du clip → Piano Roll (F7)
                sends(ch("b", 11, cmd: true, opt: true), kc(100, opt: true)),           // ⌘⌥B : Browser (⌥F8)
                sends(ch("m", 46, cmd: true, opt: true), kc(101)),                      // ⌘⌥M : Mixer (F9)
                sends(ch("d", 2, cmd: true), ch("b", 11, cmd: true), .playlist),        // ⌘D : dupliquer (⌘B)
                sends(ch("e", 14, cmd: true), ch("c", 8), .playlist),                   // ⌘E : découper (outil C)
                sends(ch("j", 38, cmd: true), ch("c", 8, cmd: true, opt: true), .playlist),  // ⌘J : consolider (⌘⌥C)
                // ⌘U : quantize. Le Quantize rapide de FL (⌘⌥Q) n'est jamais envoyé (⌘ + Q quitterait FL au
                // moindre ⌥ perdu) : l'outil Quantize du Piano Roll (⌥Q), le Quantize rapide des clips (⇧Q).
                sends(ch("u", 32, cmd: true), ch("q", 12, opt: true), .pianoRoll),
                sends(ch("u", 32, cmd: true), ch("q", 12, shift: true), .playlist),
                sends(ch("r", 15, cmd: true), kc(120)),                                 // ⌘R : renommer (F2)
                sends(ch("r", 15, cmd: true, shift: true), ch("r", 15, cmd: true)),     // ⌘⇧R : exporter (⌘R)
                sends(kc(29), ch("m", 46, opt: true), .playlist),                       // 0 : désactiver → mute (⌥M)
                sends(ch("b", 11), ch("p", 35), .playlist),                             // B : dessiner (crayon P)
                sends(ch("b", 11), ch("p", 35), .pianoRoll),
                sends(ch("o", 31), ch("m", 46, cmd: true)),                             // O : métronome (⌘M)
                sends(kc(21, cmd: true), kc(51)),                                       // ⌘4 : magnétisme (⌫)
                sends(ch("=", 24, cmd: true), kc(116), .playlist),                      // ⌘+ : zoom avant (Pg↑)
                sends(ch("-", 27, cmd: true), kc(121), .playlist),                      // ⌘− : zoom arrière (Pg↓)
                sends(ch("z", 6), kc(23), .playlist),                                   // Z : zoomer sur la sélection (5)
                sends(ch("m", 46, cmd: true, shift: true), kc(118, cmd: true)),         // ⌘⇧M : clip MIDI → pattern vide (⌘F4)
                sends(ch(",", 43, cmd: true), kc(109)),                                 // ⌘, : réglages (F10)
                undo,
                redo,
            ]
        case .logic:
            // Raccourcis par défaut de Logic Pro (jeu américain), chacun envoyé comme la touche de FL qui fait la même
            // chose : rien ne demande le script, sauf ⌘⇧Z (rétablir).
            return [
                sends(kc(36), kc(115), .playlist),                                      // Retour : au début (Origine)
                sends(ch("k", 40), ch("m", 46, cmd: true)),                             // K : métronome (⌘M)
                sends(ch("x", 7), kc(101)),                                             // X : Mixer (F9)
                sends(ch("p", 35), kc(98)),                                             // P : Piano Roll (F7)
                sends(ch("f", 3), kc(100, opt: true)),                                  // F : navigateurs → Browser (⌥F8)
                sends(ch("y", 16), kc(100)),                                            // Y : bibliothèque → Plugin Picker (F8)
                sends(ch("t", 17), kc(99)),                                             // T : outils (F3)
                sends(ch("q", 12), ch("q", 12, opt: true), .pianoRoll),                 // Q : quantize (outil ⌥Q)
                sends(ch("q", 12), ch("q", 12, shift: true), .playlist),                 // (clips : ⇧Q)
                sends(ch("t", 17, cmd: true), ch("c", 8), .playlist),                   // ⌘T : couper (outil C)
                sends(ch("r", 15, cmd: true), ch("b", 11, cmd: true), .playlist),       // ⌘R : répéter (⌘B)
                sends(ch("j", 38, cmd: true), ch("c", 8, cmd: true, opt: true), .playlist),  // ⌘J : joindre (⌘⌥C)
                sends(ch("m", 46, ctrl: true), ch("m", 46, opt: true), .playlist),      // ⌃M : mute des régions (⌥M)
                sends(kc(124, cmd: true), kc(116), .playlist),                          // ⌘→ : zoom avant (Pg↑)
                sends(kc(123, cmd: true), kc(121), .playlist),                          // ⌘← : zoom arrière (Pg↓)
                sends(ch("z", 6), kc(23), .playlist),                                   // Z : zoomer sur la sélection (5)
                sends(ch(",", 43), kc(75)),                                             // , : mesure précédente (/ du pavé)
                sends(ch(".", 47), kc(67)),                                             // . : mesure suivante (* du pavé)
                sends(ch("k", 40, cmd: true), ch("t", 17, cmd: true)),                  // ⌘K : clavier musical (⌘T)
                sends(ch("b", 11, cmd: true), ch("r", 15, cmd: true)),                  // ⌘B : bounce → exporter (⌘R)
                sends(ch(",", 43, cmd: true), kc(109)),                                 // ⌘, : réglages (F10)
                undo,
                redo,
            ]
        case .empty:
            return []
        }
    }
}

// MARK: - Import validé

struct ImportPreview {
    var remaps: [Remap]
    /// Lignes refusées, avec la raison.
    var rejected: [String]
    /// Récapitulatif affiché avant confirmation.
    var summary: [String]
}

enum ProfileImporter {
    static let maxBytes = 1 << 20
    static let maxRemaps = 500

    enum Failure: Error, LocalizedError {
        case tooLarge, tooMany
        var errorDescription: String? {
            switch self {
            case .tooLarge: return "Fichier trop volumineux pour un profil."
            case .tooMany: return "Trop de raccourcis dans ce profil (\(ProfileImporter.maxRemaps) au maximum)."
            }
        }
    }

    /// Validation stricte : touches bornées, touches modificatrices et cibles interdites refusées, nouveaux ids.
    static func prepare(_ data: Data, forbidden: ForbiddenTargets, layout: KeyboardLayout) throws -> ImportPreview {
        guard data.count <= maxBytes else { throw Failure.tooLarge }
        let decoded = try ProfileCodec.decode(data)
        guard decoded.remaps.count <= maxRemaps else { throw Failure.tooMany }
        var kept: [Remap] = []
        var rejected: [String] = []
        var summary: [String] = []
        if decoded.dropped > 0 { rejected.append("\(decoded.dropped) ligne(s) illisible(s)") }

        for var r in decoded.remaps {
            r.id = UUID()
            let trigger = r.trigger.map { $0.displayName(layout: layout) } ?? "(sans raccourci)"
            if let t = r.trigger, !t.isValidKey {
                rejected.append("\(trigger) : touche non prise en charge")
                continue
            }
            if r.kind == .macro, r.macroRef != nil {
                // Macro de la bibliothèque : elle voyage seule, en .flsmacro, relue avant d'être acceptée.
                rejected.append("\(trigger) : macro non importée (importe-la en .flsmacro pour la relire)")
                continue
            }
            if r.kind == .macro, r.macro == nil || r.macro?.template == .custom {
                // Une macro personnalisée (étapes libres) n'est jamais acceptée depuis un fichier importé.
                rejected.append("\(trigger) : macro non importée (seul le modèle « Enregistrement rapide » l'est)")
                continue
            }
            if r.kind == .keystroke, let target = r.target {
                if !target.isValidKey {
                    rejected.append("\(trigger) : touche envoyée non prise en charge")
                    continue
                }
                if let why = forbidden.reason(for: target) {
                    rejected.append("\(trigger) → \(target.displayName(layout: layout)) : interdit (\(why))")
                    continue
                }
            }
            let what: String
            switch r.kind {
            case .flAction:
                what = r.actionID.flatMap(FLActions.info).map(\.label) ?? "action inconnue (désactivée)"
            case .keystroke:
                what = "touche " + (r.target.map { $0.displayName(layout: layout) } ?? "(aucune)")
            case .macro:
                what = "macro " + (r.macro?.name.displaySafe() ?? "(aucune)")
            }
            let ctx = r.context == .everywhere ? "" : " [\(r.context.label)]"
            summary.append("\(trigger)\(ctx) → \(what)\(r.enabled ? "" : " (désactivé)")")
            kept.append(r)
        }
        return ImportPreview(remaps: kept, rejected: rejected, summary: summary)
    }
}
