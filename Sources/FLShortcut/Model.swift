import AppKit
import CoreGraphics

/// Une combinaison de touches (touche physique + modificateurs).
struct KeyCombo: Codable, Hashable {
    var keyCode: UInt16
    var command = false
    var option = false
    var control = false
    var shift = false

    init(keyCode: UInt16, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false) {
        self.keyCode = keyCode
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

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

    var cgFlags: CGEventFlags {
        var f = CGEventFlags()
        if command { f.insert(.maskCommand) }
        if option { f.insert(.maskAlternate) }
        if control { f.insert(.maskControl) }
        if shift { f.insert(.maskShift) }
        return f
    }

    var display: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        return s + KeyNames.name(for: keyCode)
    }
}

/// Actions exécutées par le script Python dans FL Studio (numéro de CC MIDI).
/// Doit rester synchronisé avec Resources/device_FLShortcut.py.
enum FLAction: String, Codable, CaseIterable, Identifiable {
    case playPause, stop, record, undo, redo
    case showPlaylist, showMixer, showChannelRack, showPianoRoll, showBrowser
    case togglePlaylistMixer, muteSelected, soloSelected
    case metronome, loopMode, nextPattern, prevPattern, nextWindow

    var id: String { rawValue }

    var cc: UInt8 {
        switch self {
        case .playPause: return 20
        case .stop: return 21
        case .record: return 22
        case .undo: return 23
        case .redo: return 24
        case .showPlaylist: return 25
        case .showMixer: return 26
        case .showChannelRack: return 27
        case .showPianoRoll: return 28
        case .showBrowser: return 29
        case .togglePlaylistMixer: return 30
        case .muteSelected: return 31
        case .soloSelected: return 32
        case .metronome: return 33
        case .loopMode: return 34
        case .nextPattern: return 35
        case .prevPattern: return 36
        case .nextWindow: return 37
        }
    }

    var label: String {
        switch self {
        case .playPause: return "Lecture / Pause"
        case .stop: return "Stop"
        case .record: return "Enregistrer"
        case .undo: return "Annuler"
        case .redo: return "Rétablir"
        case .showPlaylist: return "Afficher la Playlist"
        case .showMixer: return "Afficher le Mixer"
        case .showChannelRack: return "Afficher le Channel Rack"
        case .showPianoRoll: return "Afficher le Piano Roll"
        case .showBrowser: return "Afficher le Browser"
        case .togglePlaylistMixer: return "Basculer Playlist ↔ Mixer"
        case .muteSelected: return "Mute (piste / canal sélectionné)"
        case .soloSelected: return "Solo (piste / canal sélectionné)"
        case .metronome: return "Métronome on/off"
        case .loopMode: return "Mode Pattern ↔ Song"
        case .nextPattern: return "Pattern suivant"
        case .prevPattern: return "Pattern précédent"
        case .nextWindow: return "Fenêtre suivante"
        }
    }
}

/// Un raccourci personnalisé : déclencheur → action FL ou autre raccourci.
struct Remap: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case flAction, keystroke }

    var id = UUID()
    var enabled = true
    var trigger: KeyCombo?
    var kind: Kind = .flAction
    var action: FLAction = .playPause
    var target: KeyCombo?

    init(trigger: KeyCombo? = nil, action: FLAction = .playPause) {
        self.trigger = trigger
        self.action = action
    }

    init(trigger: KeyCombo?, sends target: KeyCombo) {
        self.trigger = trigger
        self.kind = .keystroke
        self.target = target
    }
}

/// Stocke le profil de l'utilisateur et l'index utilisé par l'interception clavier.
final class Store: ObservableObject {
    static let shared = Store()

    @Published var remaps: [Remap] {
        didSet { rebuildIndex(); save() }
    }
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "enabled") }
    }

    private(set) var index: [KeyCombo: Remap] = [:]
    let toggleCombo = KeyCombo(keyCode: KeyNames.keyCode(for: "f") ?? 3, command: true, option: true, control: true)

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FL Shortcut", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profile.json")
    }

    private init() {
        enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
        if let data = try? Data(contentsOf: Store.fileURL),
           let saved = try? JSONDecoder().decode([Remap].self, from: data) {
            remaps = saved
        } else {
            remaps = Store.defaults()
        }
        rebuildIndex()
    }

    func isDuplicate(_ remap: Remap) -> Bool {
        guard remap.enabled, let t = remap.trigger else { return false }
        return remaps.filter { $0.enabled && $0.trigger == t }.count > 1
    }

    func resetToDefaults() { remaps = Store.defaults() }

    private func rebuildIndex() {
        var idx: [KeyCombo: Remap] = [:]
        for r in remaps where r.enabled {
            guard let t = r.trigger, idx[t] == nil else { continue }
            if r.kind == .keystroke && r.target == nil { continue }
            idx[t] = r
        }
        index = idx
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted]
        if let data = try? enc.encode(remaps) { try? data.write(to: Store.fileURL) }
    }

    /// Profil de départ "style Ableton". Les touches sont résolues selon la disposition
    /// du clavier (AZERTY, QWERTY...) au premier lancement.
    static func defaults() -> [Remap] {
        func key(_ ch: String, _ fallback: UInt16) -> UInt16 { KeyNames.keyCode(for: ch) ?? fallback }
        return [
            Remap(trigger: KeyCombo(keyCode: key("z", 6), command: true, shift: true), action: .redo),
            Remap(trigger: KeyCombo(keyCode: 48), action: .togglePlaylistMixer),          // Tab
            Remap(trigger: KeyCombo(keyCode: 29), action: .muteSelected),                 // 0
            Remap(trigger: KeyCombo(keyCode: 18, control: true), action: .showPlaylist),  // ⌃1
            Remap(trigger: KeyCombo(keyCode: 19, control: true), action: .showChannelRack),
            Remap(trigger: KeyCombo(keyCode: 20, control: true), action: .showPianoRoll),
            Remap(trigger: KeyCombo(keyCode: 21, control: true), action: .showMixer),
            Remap(trigger: KeyCombo(keyCode: 23, control: true), action: .showBrowser),
            Remap(trigger: KeyCombo(keyCode: key("m", 46), control: true), action: .metronome),
            Remap(trigger: KeyCombo(keyCode: key("l", 37), control: true), action: .loopMode),
            Remap(trigger: KeyCombo(keyCode: 124, control: true), action: .nextPattern),  // ⌃→
            Remap(trigger: KeyCombo(keyCode: 123, control: true), action: .prevPattern),  // ⌃←
        ]
    }
}
