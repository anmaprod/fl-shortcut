// Macros en blocs (format 2) : données pures, testables, sans AppKit.
// - Les identifiants JSON sont stables, en ASCII, jamais traduits : c'est un contrat (comme « armon » ou « trackMenu »).
// - Codage écrit à la main, piloté par le champ `type` : {"type":"if","id":…,"condition":…,"then":[…],"else":[…]}.
// - Décodage tolérant : un bloc de type inconnu (version plus récente) ou illisible est conservé TEL QUEL
//   (`.unknown(type:raw:)`) et la macro qui le contient est bloquée : jamais exécutée sans lui (REL-01).
// L'exécution est dans MacroInterpreter.swift (contrôle) et MacroEffectsMac.swift / MacroFLBlocks.swift (effets).
import CoreGraphics
import Foundation

// MARK: - Valeur JSON brute (blocs inconnus conservés tels quels)

enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "valeur JSON illisible")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n):
            if let i = Int(exactly: n) { try c.encode(i) } else { try c.encode(n) }
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    var string: String? { if case .string(let s) = self { return s }; return nil }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var double: Double? { if case .number(let n) = self { return n }; return nil }
    /// Entier exact seulement (1.5 ou 1e300 : nil).
    var int: Int? { double.flatMap { Int(exactly: $0) } }
    var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }

    static func num(_ i: Int) -> JSONValue { .number(Double(i)) }
}

// MARK: - Macro de la bibliothèque

/// Une macro en blocs (bibliothèque `macros.json` à partir de l'incrément 2 ; ici : modèle développé et essais).
struct MacroDoc: Codable, Identifiable, Equatable {
    var id: UUID
    var format = 2
    var name: String                      // ≤ 60, affiché avec displaySafe()
    var blocks: [Block]
    var variables: [VariableDecl] = []    // ≤ 8 entiers (incrément 4)
    var origin: Origin?
    var revision = 0                      // +1 à chaque enregistrement : clé du cache de validation

    init(id: UUID = UUID(), name: String, blocks: [Block], variables: [VariableDecl] = [], origin: Origin? = nil,
         revision: Int = 0) {
        self.id = id
        self.name = name
        self.blocks = blocks
        self.variables = variables
        self.origin = origin
        self.revision = revision
    }

    private enum CodingKeys: String, CodingKey { case id, format, name, blocks, variables, origin, revision }

    /// Tolérant : chaque champ manquant prend sa valeur par défaut ; les blocs ne font jamais échouer le décodage.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        format = (try? c.decodeIfPresent(Int.self, forKey: .format)) ?? 2
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Macro"
        blocks = (try? c.decodeIfPresent([Block].self, forKey: .blocks)) ?? []
        let lossy = (try? c.decodeIfPresent([Lossy<VariableDecl>].self, forKey: .variables)) ?? []
        variables = lossy.compactMap { $0.value }
        origin = try? c.decodeIfPresent(Origin.self, forKey: .origin)
        revision = (try? c.decodeIfPresent(Int.self, forKey: .revision)) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(format, forKey: .format)
        try c.encode(name, forKey: .name)
        try c.encode(blocks, forKey: .blocks)
        if !variables.isEmpty { try c.encode(variables, forKey: .variables) }
        try c.encodeIfPresent(origin, forKey: .origin)
        try c.encode(revision, forKey: .revision)
    }
}

/// Variable entière d'une macro (jamais de texte).
struct VariableDecl: Codable, Equatable {
    var name: String
    var initial = 0
}

/// D'où vient une macro : modèle développé, import, enregistrement, ancienne macro reprise.
enum Origin: Codable, Equatable {
    case template(String)
    case imported
    case recorded
    case legacy

    private enum CodingKeys: String, CodingKey { case kind, name }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "template": self = .template((try? c.decode(String.self, forKey: .name)) ?? "?")
        case "imported": self = .imported
        case "recorded": self = .recorded
        case "legacy": self = .legacy
        default: throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "origine inconnue")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .template(let name):
            try c.encode("template", forKey: .kind)
            try c.encode(name, forKey: .name)
        case .imported: try c.encode("imported", forKey: .kind)
        case .recorded: try c.encode("recorded", forKey: .kind)
        case .legacy: try c.encode("legacy", forKey: .kind)
        }
    }
}

// MARK: - Bloc

enum FailurePolicy: String, Codable {
    case stop
    /// Le bloc qui échoue est sauté (« dernier bloc échoué » devient vrai) ; la macro continue.
    case keepGoing = "continue"
}

struct Block: Codable, Identifiable, Equatable {
    var id: UUID                          // stable : surlignage, rapport par bloc, positions apprises
    var enabled = true                    // case à cocher (comme Pulover)
    var onFailure: FailurePolicy = .stop
    var note: String?                     // commentaire ≤ 120
    var body: BlockBody

    init(id: UUID = UUID(), _ body: BlockBody, enabled: Bool = true, onFailure: FailurePolicy = .stop,
         note: String? = nil) {
        self.id = id
        self.body = body
        self.enabled = enabled
        self.onFailure = onFailure
        self.note = note
    }

    /// Jamais d'échec : tout ce qui n'est pas compris devient `.unknown` (conservé, macro bloquée).
    init(from decoder: Decoder) throws {
        self.init(json: try JSONValue(from: decoder))
    }

    func encode(to encoder: Encoder) throws {
        try json.encode(to: encoder)
    }

    /// Imbrication au-delà de laquelle plus rien n'est interprété (fichier piégé) : bloc conservé tel quel.
    static let maxParseDepth = 16

    init(json: JSONValue, depth: Int = 0) {
        let typeName = json["type"]?.string ?? "?"
        id = json["id"]?.string.flatMap { UUID(uuidString: $0) } ?? UUID()
        enabled = json["enabled"]?.bool ?? true
        onFailure = json["onFailure"]?.string.flatMap { FailurePolicy(rawValue: $0) } ?? .stop
        note = json["note"]?.string
        if depth < Self.maxParseDepth, let type = BlockType(rawValue: typeName),
           let body = BlockBody.parse(type, json, depth: depth) {
            self.body = body
        } else if case .object(var o) = json {
            // Paramètres gardés tels quels ; les champs communs (id, case à cocher…) sont rendus à l'écriture.
            for key in Self.commonKeys { o.removeValue(forKey: key) }
            body = .unknown(type: typeName, raw: .object(o))
        } else {
            body = .unknown(type: typeName, raw: json)
        }
    }

    /// Champs communs à tous les blocs (hors paramètres).
    static let commonKeys = ["type", "id", "enabled", "onFailure", "note"]

    var json: JSONValue {
        var o: [String: JSONValue]
        if case .unknown(let type, let raw) = body {
            guard case .object(let r) = raw else { return raw }
            o = r
            o["type"] = .string(type)
        } else {
            o = body.params
            if let type = body.type { o["type"] = .string(type.rawValue) }
        }
        o["id"] = .string(id.uuidString)
        o["enabled"] = .bool(enabled)
        o["onFailure"] = .string(onFailure.rawValue)
        o["note"] = note.map { .string($0) }
        return .object(o)
    }
}

// MARK: - Corps d'un bloc

indirect enum BlockBody: Equatable {
    // Clavier
    case key(KeyRef, times: Int)                            // « Touche »
    case menuLetters([Character], finalEnter: EnterPolicy)  // « Lettres d'un menu de FL » (seulement si un menu est ouvert)
    case menuKey(MenuKey, times: Int)                       // ↑ ↓ ← → Entrée Échap, seulement dans un menu ouvert
    // Souris
    case click(ClickTarget, button: MouseButton)
    // Fenêtres et attentes
    case delay(ms: Int)
    case waitWindow(WindowKind, timeoutMs: Int)             // .dialog | .menu
    case waitWindowClose(WindowKind, timeoutMs: Int)
    // FL (haut niveau : le code validé d'aujourd'hui). `labels` : libellés du menu, pour les messages seulement.
    case trackMenu(letters: [Character], labels: [String], target: TrackTarget, finalEnter: EnterPolicy)
    case chooseFile(path: String)
    case flAction(key: String, fallback: ActionFallback)    // clé stable du protocole ; repli : touche / chemin clavier
    case flActionValue(key: String, value: IntSource)       // incrément 4 (paramètre signé)
    case selectInput(LearnedRef)
    case feedbackCheck
    /// Ancienne étape `menu` (titres d'accessibilité, clics de secours) : reprise des anciennes macros, hors palette.
    case menuAX(titles: [String], fallback: [ClickTarget])
    // Contrôle
    case ifElse(Condition, then: [Block], otherwise: [Block])
    case repeatCount(Int, [Block])
    case repeatWhile(Condition, maxIterations: Int, [Block])
    case waitUntil(Condition, timeoutMs: Int)
    case setVariable(String, IntSource)
    case stop(message: String?)
    case comment(String)
    // Format plus récent ou bloc illisible : conservé tel quel, macro BLOQUÉE (jamais exécutée sans lui).
    case unknown(type: String, raw: JSONValue)

    /// nil pour un bloc inconnu.
    var type: BlockType? {
        switch self {
        case .key: return .key
        case .menuLetters: return .menuLetters
        case .menuKey: return .menuKey
        case .click: return .click
        case .delay: return .delay
        case .waitWindow: return .waitWindow
        case .waitWindowClose: return .waitWindowClose
        case .trackMenu: return .trackMenu
        case .chooseFile: return .chooseFile
        case .flAction: return .flAction
        case .flActionValue: return .flActionValue
        case .selectInput: return .selectInput
        case .feedbackCheck: return .feedbackCheck
        case .menuAX: return .menuAX
        case .ifElse: return .ifElse
        case .repeatCount: return .repeatCount
        case .repeatWhile: return .repeatWhile
        case .waitUntil: return .waitUntil
        case .setVariable: return .setVariable
        case .stop: return .stop
        case .comment: return .comment
        case .unknown: return nil
        }
    }

    /// Listes de blocs imbriquées (alors puis sinon, corps d'une boucle).
    var children: [[Block]] {
        switch self {
        case .ifElse(_, let then, let otherwise): return [then, otherwise]
        case .repeatCount(_, let body), .repeatWhile(_, _, let body): return [body]
        default: return []
        }
    }

    /// Condition portée par le bloc (si, tant que, attendre que).
    var condition: Condition? {
        switch self {
        case .ifElse(let c, _, _), .repeatWhile(let c, _, _), .waitUntil(let c, _): return c
        default: return nil
        }
    }

    // MARK: Codage des paramètres (identifiants JSON stables)

    var params: [String: JSONValue] {
        switch self {
        case .key(let k, let times):
            return ["key": k.json, "times": .num(times)]
        case .menuLetters(let letters, let enter):
            return ["letters": .string(String(letters)), "finalEnter": enter.json]
        case .menuKey(let key, let times):
            return ["menuKey": .string(key.rawValue), "times": .num(times)]
        case .click(let target, let button):
            return ["target": target.json, "button": .string(button.rawValue)]
        case .delay(let ms):
            return ["ms": .num(ms)]
        case .waitWindow(let kind, let timeout), .waitWindowClose(let kind, let timeout):
            return ["window": .string(kind.rawValue), "timeoutMs": .num(timeout)]
        case .trackMenu(let letters, let labels, let target, let enter):
            return ["letters": .string(String(letters)), "labels": .array(labels.map { .string($0) }),
                    "target": .string(target.rawValue), "finalEnter": enter.json]
        case .chooseFile(let path):
            return ["path": .string(path)]
        case .flAction(let key, let fallback):
            return ["action": .string(key), "fallback": fallback.json]
        case .flActionValue(let key, let value):
            return ["action": .string(key), "value": value.json]
        case .selectInput(let ref):
            return ["learned": ref.json]
        case .feedbackCheck:
            return [:]
        case .menuAX(let titles, let fallback):
            return ["titles": .array(titles.map { .string($0) }), "fallback": .array(fallback.map(\.json))]
        case .ifElse(let c, let then, let otherwise):
            return ["condition": c.json, "then": .array(then.map(\.json)), "else": .array(otherwise.map(\.json))]
        case .repeatCount(let n, let body):
            return ["count": .num(n), "blocks": .array(body.map(\.json))]
        case .repeatWhile(let c, let max, let body):
            return ["condition": c.json, "maxIterations": .num(max), "blocks": .array(body.map(\.json))]
        case .waitUntil(let c, let timeout):
            return ["condition": c.json, "timeoutMs": .num(timeout)]
        case .setVariable(let name, let value):
            return ["variable": .string(name), "value": value.json]
        case .stop(let message):
            return message.map { ["message": .string($0)] } ?? [:]
        case .comment(let text):
            return ["text": .string(text)]
        case .unknown(_, let raw):
            if case .object(let o) = raw { return o }
            return [:]
        }
    }

    /// nil = paramètres illisibles (le bloc devient `.unknown`, conservé et bloquant).
    static func parse(_ type: BlockType, _ j: JSONValue, depth: Int) -> BlockBody? {
        func blocks(_ key: String) -> [Block]? {
            guard let list = j[key]?.array else { return nil }
            return list.map { Block(json: $0, depth: depth + 1) }
        }
        func letters(_ key: String) -> [Character]? { j[key]?.string.map { Array($0) } }
        switch type {
        case .key:
            guard let k = KeyRef(json: j["key"]) else { return nil }
            return .key(k, times: j["times"]?.int ?? 1)
        case .menuLetters:
            guard let l = letters("letters"), let e = EnterPolicy(json: j["finalEnter"]) else { return nil }
            return .menuLetters(l, finalEnter: e)
        case .menuKey:
            guard let k = j["menuKey"]?.string.flatMap({ MenuKey(rawValue: $0) }) else { return nil }
            return .menuKey(k, times: j["times"]?.int ?? 1)
        case .click:
            guard let t = ClickTarget(json: j["target"]),
                  let button = MouseButton(rawValue: j["button"]?.string ?? "left") else { return nil }
            return .click(t, button: button)
        case .delay:
            guard let ms = j["ms"]?.int else { return nil }
            return .delay(ms: ms)
        case .waitWindow, .waitWindowClose:
            guard let kind = j["window"]?.string.flatMap({ WindowKind(rawValue: $0) }),
                  let timeout = j["timeoutMs"]?.int else { return nil }
            return type == .waitWindow ? .waitWindow(kind, timeoutMs: timeout) : .waitWindowClose(kind, timeoutMs: timeout)
        case .trackMenu:
            guard let l = letters("letters"), let e = EnterPolicy(json: j["finalEnter"]),
                  let target = j["target"]?.string.flatMap({ TrackTarget(rawValue: $0) }) else { return nil }
            let labels = j["labels"]?.array?.compactMap(\.string) ?? []
            return .trackMenu(letters: l, labels: labels, target: target, finalEnter: e)
        case .chooseFile:
            guard let path = j["path"]?.string else { return nil }
            return .chooseFile(path: path)
        case .flAction:
            guard let key = j["action"]?.string, let fallback = ActionFallback(json: j["fallback"]) else { return nil }
            return .flAction(key: key, fallback: fallback)
        case .flActionValue:
            guard let key = j["action"]?.string, let value = IntSource(json: j["value"]) else { return nil }
            return .flActionValue(key: key, value: value)
        case .selectInput:
            guard let ref = LearnedRef(json: j["learned"]) else { return nil }
            return .selectInput(ref)
        case .feedbackCheck:
            return .feedbackCheck
        case .menuAX:
            guard let titles = j["titles"]?.array?.compactMap(\.string) else { return nil }
            var fallback: [ClickTarget] = []
            for v in j["fallback"]?.array ?? [] {
                guard let t = ClickTarget(json: v) else { return nil }
                fallback.append(t)
            }
            return .menuAX(titles: titles, fallback: fallback)
        case .ifElse:
            guard let c = Condition(json: j["condition"]), let then = blocks("then") else { return nil }
            return .ifElse(c, then: then, otherwise: blocks("else") ?? [])
        case .repeatCount:
            guard let n = j["count"]?.int, let body = blocks("blocks") else { return nil }
            return .repeatCount(n, body)
        case .repeatWhile:
            guard let c = Condition(json: j["condition"]), let max = j["maxIterations"]?.int,
                  let body = blocks("blocks") else { return nil }
            return .repeatWhile(c, maxIterations: max, body)
        case .waitUntil:
            guard let c = Condition(json: j["condition"]), let timeout = j["timeoutMs"]?.int else { return nil }
            return .waitUntil(c, timeoutMs: timeout)
        case .setVariable:
            guard let name = j["variable"]?.string, let value = IntSource(json: j["value"]) else { return nil }
            return .setVariable(name, value)
        case .stop:
            return .stop(message: j["message"]?.string)
        case .comment:
            return .comment(j["text"]?.string ?? "")
        }
    }
}

// MARK: - Paramètres

/// Touche portable : code Mac + caractère (base d'un futur portage Windows ; la touche envoyée est `combo`).
struct KeyRef: Equatable {
    var combo: KeyCombo
    var char: String?

    init(_ combo: KeyCombo, char: String? = nil) {
        self.combo = combo
        self.char = char
    }

    init?(json: JSONValue?) {
        guard let json, let combo = KeyCombo(json: json["combo"]) else { return nil }
        self.combo = combo
        char = json["char"]?.string
    }

    var json: JSONValue {
        var o: [String: JSONValue] = ["combo": combo.json]
        if let char { o["char"] = .string(char) }
        return .object(o)
    }
}

extension KeyCombo {
    init?(json: JSONValue?) {
        guard let json, let code = json["keyCode"]?.int, let keyCode = UInt16(exactly: code) else { return nil }
        self.init(keyCode: keyCode, command: json["command"]?.bool ?? false, option: json["option"]?.bool ?? false,
                  control: json["control"]?.bool ?? false, shift: json["shift"]?.bool ?? false)
    }

    var json: JSONValue {
        var o: [String: JSONValue] = ["keyCode": .num(Int(keyCode))]
        if command { o["command"] = .bool(true) }
        if option { o["option"] = .bool(true) }
        if control { o["control"] = .bool(true) }
        if shift { o["shift"] = .bool(true) }
        return .object(o)
    }
}

/// Entrée après la dernière lettre d'un menu de FL.
enum EnterPolicy: Equatable {
    /// Apprise au premier passage, retenue sous une clé UserDefaults historique (liste blanche : MacroValidation).
    case learned(legacyKey: String)
    /// Toujours (après une courte attente, seulement si les menus restent ouverts).
    case always
    /// Seulement si les menus restent ouverts après la lettre (rien n'est retenu).
    case ifNeeded
    /// Jamais (les lettres ne font que naviguer).
    case never

    init?(json: JSONValue?) {
        switch json?["mode"]?.string {
        case "learned":
            guard let key = json?["key"]?.string else { return nil }
            self = .learned(legacyKey: key)
        case "always": self = .always
        case "ifNeeded": self = .ifNeeded
        case "never": self = .never
        default: return nil
        }
    }

    var json: JSONValue {
        switch self {
        case .learned(let key): return .object(["mode": .string("learned"), "key": .string(key)])
        case .always: return .object(["mode": .string("always")])
        case .ifNeeded: return .object(["mode": .string("ifNeeded")])
        case .never: return .object(["mode": .string("never")])
        }
    }
}

enum MenuKey: String, CaseIterable {
    case up, down, left, right, enter, escape

    var keyCode: UInt16 {
        switch self {
        case .up: return 126
        case .down: return 125
        case .left: return 123
        case .right: return 124
        case .enter: return 36
        case .escape: return 53
        }
    }

    var symbol: String {
        switch self {
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        case .enter: return "Entrée"
        case .escape: return "Échap"
        }
    }
}

enum MouseButton: String { case left, right }

enum WindowKind: String { case dialog, menu }

enum TrackTarget: String {
    /// Dernière piste cliquée dans FL (TrackMemory), sinon le curseur au démarrage.
    case lastClicked
    /// Curseur au démarrage de la macro.
    case cursor
}

/// Sans lien avec FL : ce que fait le bloc « Action de FL ».
enum ActionFallback: Equatable {
    /// Rien : le bloc échoue (« ce bloc a besoin du lien avec FL »).
    case none
    /// Une touche de FL (REC : R).
    case key(KeyRef)
    /// Menu de la piste › S › ← › ↓×5 › Entrée = « Arm selected track(s) » (n'éteint jamais).
    case trackMenuArm

    init?(json: JSONValue?) {
        switch json?["kind"]?.string {
        case "none": self = .none
        case "trackMenuArm": self = .trackMenuArm
        case "key":
            guard let k = KeyRef(json: json?["key"]) else { return nil }
            self = .key(k)
        default: return nil
        }
    }

    var json: JSONValue {
        switch self {
        case .none: return .object(["kind": .string("none")])
        case .trackMenuArm: return .object(["kind": .string("trackMenuArm")])
        case .key(let k): return .object(["kind": .string("key"), "key": k.json])
        }
    }
}

/// Valeur entière : constante, variable, ou état de FL lu par le lien (incrément 4).
enum IntSource: Equatable {
    case constant(Int)
    case variable(String)
    case flState(String)

    init?(json: JSONValue?) {
        switch json?["kind"]?.string {
        case "const":
            guard let v = json?["value"]?.int else { return nil }
            self = .constant(v)
        case "variable":
            guard let name = json?["name"]?.string else { return nil }
            self = .variable(name)
        case "flState":
            guard let query = json?["query"]?.string else { return nil }
            self = .flState(query)
        default: return nil
        }
    }

    var json: JSONValue {
        switch self {
        case .constant(let v): return .object(["kind": .string("const"), "value": .num(v)])
        case .variable(let name): return .object(["kind": .string("variable"), "name": .string(name)])
        case .flState(let query): return .object(["kind": .string("flState"), "query": .string(query)])
        }
    }
}

/// Positions apprises d'un bloc. `.legacy` pointe vers les clés UserDefaults actuelles : rien à réapprendre.
enum LearnedRef: Equatable {
    case legacy(key: String)

    init?(json: JSONValue?) {
        guard json?["kind"]?.string == "legacy", let key = json?["key"]?.string else { return nil }
        self = .legacy(key: key)
    }

    var json: JSONValue {
        switch self {
        case .legacy(let key): return .object(["kind": .string("legacy"), "key": .string(key)])
        }
    }
}

enum CompareOp: String, CaseIterable {
    case eq, ne, lt, le, gt, ge

    func holds(_ a: Int, _ b: Int) -> Bool {
        switch self {
        case .eq: return a == b
        case .ne: return a != b
        case .lt: return a < b
        case .le: return a <= b
        case .gt: return a > b
        case .ge: return a >= b
        }
    }

    var symbol: String {
        switch self {
        case .eq: return "="
        case .ne: return "≠"
        case .lt: return "<"
        case .le: return "≤"
        case .gt: return ">"
        case .ge: return "≥"
        }
    }
}

indirect enum Condition: Equatable {
    case windowOpen(WindowKind)               // local, sans MIDI
    case flState(query: String, CompareOp, Int) // lien MIDI (incrément 4)
    case variable(String, CompareOp, Int)
    case lastBlockFailed                      // utile avec onFailure = .keepGoing
    case not(Condition)
    case all([Condition])
    case any([Condition])

    static let maxParseDepth = 8

    init?(json: JSONValue?, depth: Int = 0) {
        guard let json, depth < Self.maxParseDepth else { return nil }
        func list() -> [Condition]? {
            guard let a = json["conditions"]?.array else { return nil }
            var out: [Condition] = []
            for v in a {
                guard let c = Condition(json: v, depth: depth + 1) else { return nil }
                out.append(c)
            }
            return out
        }
        switch json["type"]?.string {
        case "windowOpen":
            guard let kind = json["window"]?.string.flatMap({ WindowKind(rawValue: $0) }) else { return nil }
            self = .windowOpen(kind)
        case "flState":
            guard let q = json["query"]?.string, let op = json["op"]?.string.flatMap({ CompareOp(rawValue: $0) }),
                  let v = json["value"]?.int else { return nil }
            self = .flState(query: q, op, v)
        case "variable":
            guard let name = json["name"]?.string, let op = json["op"]?.string.flatMap({ CompareOp(rawValue: $0) }),
                  let v = json["value"]?.int else { return nil }
            self = .variable(name, op, v)
        case "lastBlockFailed":
            self = .lastBlockFailed
        case "not":
            guard let inner = Condition(json: json["condition"], depth: depth + 1) else { return nil }
            self = .not(inner)
        case "all":
            guard let l = list() else { return nil }
            self = .all(l)
        case "any":
            guard let l = list() else { return nil }
            self = .any(l)
        default:
            return nil
        }
    }

    var json: JSONValue {
        switch self {
        case .windowOpen(let kind):
            return .object(["type": .string("windowOpen"), "window": .string(kind.rawValue)])
        case .flState(let q, let op, let v):
            return .object(["type": .string("flState"), "query": .string(q), "op": .string(op.rawValue), "value": .num(v)])
        case .variable(let name, let op, let v):
            return .object(["type": .string("variable"), "name": .string(name), "op": .string(op.rawValue), "value": .num(v)])
        case .lastBlockFailed:
            return .object(["type": .string("lastBlockFailed")])
        case .not(let inner):
            return .object(["type": .string("not"), "condition": inner.json])
        case .all(let list):
            return .object(["type": .string("all"), "conditions": .array(list.map(\.json))])
        case .any(let list):
            return .object(["type": .string("any"), "conditions": .array(list.map(\.json))])
        }
    }
}

enum Corner: String, CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

/// Où cliquer, retrouvé à chaque exécution (jamais un point absolu de l'écran).
enum ClickTarget: Equatable {
    /// Coin d'une fenêtre de FL. Taille retenue : la fenêtre de cette taille (refus si aucune) ; sans taille : celle
    /// qui est sous le curseur au démarrage (ancien repère `window`).
    case flWindow(corner: Corner, dx: Double, dy: Double, size: CGSize?)
    /// Relatif au dernier menu de FL ouvert (résiste au décalage du menu).
    case openMenu(MacroSpots.PopupHop)
    /// Depuis la piste visée (TrackMemory).
    case track(dx: Double, dy: Double)
    case lastClick(dx: Double, dy: Double)
    case startCursor(dx: Double, dy: Double)
    /// x depuis le curseur, y depuis le haut de la fenêtre de FL (reprise d'un ancien ClickSpot).
    case cursorXWindowY(dx: Double, dy: Double)

    /// Reprise d'une ancienne position apprise, repère par repère (même point à l'exécution).
    init(_ spot: ClickSpot) {
        switch spot.anchor {
        case .cursor: self = .startCursor(dx: spot.dx, dy: spot.dy)
        case .window: self = .flWindow(corner: .topLeft, dx: spot.dx, dy: spot.dy, size: nil)
        case .cursorXWindowY: self = .cursorXWindowY(dx: spot.dx, dy: spot.dy)
        case .lastClick: self = .lastClick(dx: spot.dx, dy: spot.dy)
        }
    }

    /// Décalages finis et bornés (±5000), taille plausible.
    var isFinite: Bool {
        func ok(_ v: Double) -> Bool { v.isFinite && abs(v) <= 5000 }
        switch self {
        case .flWindow(_, let dx, let dy, let size):
            let sizeOK = size.map { $0.width.isFinite && $0.height.isFinite && $0.width > 0 && $0.height > 0
                && $0.width <= 10_000 && $0.height <= 10_000 } ?? true
            return ok(dx) && ok(dy) && sizeOK
        case .openMenu(let hop):
            return ok(Double(hop.offset.dx)) && ok(Double(hop.offset.dy)) && hop.size.width.isFinite && hop.size.height.isFinite
                && (16...2000).contains(hop.size.width) && (16...4000).contains(hop.size.height)
        case .track(let dx, let dy), .lastClick(let dx, let dy), .startCursor(let dx, let dy), .cursorXWindowY(let dx, let dy):
            return ok(dx) && ok(dy)
        }
    }

    init?(json: JSONValue?) {
        guard let json else { return nil }
        let dx = json["dx"]?.double ?? 0, dy = json["dy"]?.double ?? 0
        func size(_ v: JSONValue?) -> CGSize? {
            guard let a = v?.array, a.count == 2, let w = a[0].double, let h = a[1].double else { return nil }
            return CGSize(width: w, height: h)
        }
        switch json["anchor"]?.string {
        case "flWindow":
            guard let corner = json["corner"]?.string.flatMap({ Corner(rawValue: $0) }) else { return nil }
            let parsed = size(json["size"])
            if let s = json["size"], s != .null, parsed == nil { return nil }
            self = .flWindow(corner: corner, dx: dx, dy: dy, size: parsed)
        case "openMenu":
            guard let offset = size(json["offset"]), let s = size(json["size"]) else { return nil }
            self = .openMenu(MacroSpots.PopupHop(offset: CGVector(dx: offset.width, dy: offset.height), size: s))
        case "track": self = .track(dx: dx, dy: dy)
        case "lastClick": self = .lastClick(dx: dx, dy: dy)
        case "startCursor": self = .startCursor(dx: dx, dy: dy)
        case "cursorXWindowY": self = .cursorXWindowY(dx: dx, dy: dy)
        default: return nil
        }
    }

    var json: JSONValue {
        func pair(_ a: CGFloat, _ b: CGFloat) -> JSONValue { .array([.number(Double(a)), .number(Double(b))]) }
        func offset(_ anchor: String, _ dx: Double, _ dy: Double) -> JSONValue {
            .object(["anchor": .string(anchor), "dx": .number(dx), "dy": .number(dy)])
        }
        switch self {
        case .flWindow(let corner, let dx, let dy, let size):
            var o: [String: JSONValue] = ["anchor": .string("flWindow"), "corner": .string(corner.rawValue),
                                          "dx": .number(dx), "dy": .number(dy)]
            if let size { o["size"] = pair(size.width, size.height) }
            return .object(o)
        case .openMenu(let hop):
            return .object(["anchor": .string("openMenu"), "offset": pair(hop.offset.dx, hop.offset.dy),
                            "size": pair(hop.size.width, hop.size.height)])
        case .track(let dx, let dy): return offset("track", dx, dy)
        case .lastClick(let dx, let dy): return offset("lastClick", dx, dy)
        case .startCursor(let dx, let dy): return offset("startCursor", dx, dy)
        case .cursorXWindowY(let dx, let dy): return offset("cursorXWindowY", dx, dy)
        }
    }
}
