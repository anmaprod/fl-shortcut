// Choix automatique du preset dans la boîte « Open » native de FL (NSOpenPanel), comme les outils de macro établis
// (Keyboard Maestro, « Insert text by pasting ») : chaque étape attend la fenêtre qu'elle doit produire au lieu
// d'une pause fixe (des touches envoyées avant que la boîte soit prête sont perdues).
//  1. ⌘⇧G (« Aller au dossier ») jusqu'à l'apparition de sa fenêtre (renvoyé si la boîte n'était pas prête) ;
//  2. chemin TAPÉ (caractères Unicode joints aux événements, comme cliclick) : un ⌘V synthétique est ignoré par
//     macOS 26 (protection du presse-papiers), constaté par l'essai de la CI ; le presse-papiers n'est jamais touché ;
//  3. Entrée : la fenêtre « Aller au dossier » se ferme, le fichier est sélectionné ;
//  4. Entrée : la boîte « Open » se ferme sur ce fichier.
// Le contenu de la boîte « Open » est servi par un autre processus du système : des touches adressées au seul
// processus de FL ne lui parviennent pas (constaté sur macOS 26). Quand FL est au premier plan, les touches passent
// donc par le flux clavier du système, comme une vraie frappe ; sinon rien n'est envoyé. Aucune lecture de l'écran.
import AppKit
import CoreGraphics
import Foundation

enum PresetChooser {
    enum Outcome: Equatable {
        case done
        case cancelled(String)
        case failed(String)
    }

    private static let source: CGEventSource? = {
        let s = CGEventSource(stateID: .privateState)
        s?.localEventsSuppressionInterval = 0
        return s
    }()

    /// `dialog` : numéro de fenêtre de la boîte « Open » (déjà ouverte). `stop` : raison d'arrêter, sinon nil.
    static func choose(path: String, pid: Int32, dialog: Int, stop: () -> String?,
                       log: (String) -> Void = { MacroLog.shared.write("FILE", $0) }) -> Outcome {
        func gone(_ numbers: Set<Int>, _ timeout: TimeInterval) -> WindowWait.Failure? {
            if case .failure(let f) = WindowWait.gone(pid: pid, numbers: numbers, timeout: timeout, stop: stop) { return f }
            return nil
        }
        guard WinSnapshot.take(pid: pid).numbers.contains(dialog) else { return .failed("la boîte « Open » s'est fermée") }
        guard MacroRunner.isFrontmost(pid) else { return .failed("la boîte « Open » n'est pas au premier plan") }

        // 1. « Aller au dossier » : nouvelle fenêtre du processus (feuille de la boîte), renvoyé tant qu'elle n'apparaît pas.
        // Fenêtres déjà là avant le premier ⌘⇧G : « Aller au dossier » est la nouvelle (elle s'anime à l'ouverture, d'où
        // une attente généreuse ; ⌘⇧G n'est renvoyé que si elle n'est toujours pas là).
        let base = WinSnapshot.take(pid: pid).numbers
        var goTo: WinInfo?
        for attempt in 1...3 {
            if let why = stop() { return .cancelled(why) }
            post(keyCode: 5, flags: [.maskCommand, .maskShift], pid: pid)                  // ⌘⇧G
            switch WindowWait.newWindow(pid: pid, excluding: base, timeout: 1.5,
                                        accept: { $0.bounds.width >= 120 && $0.bounds.height >= 30 }, stop: stop) {
            case .success(let w):
                goTo = w
                log("go-to-folder \(w) after attempt \(attempt)")
            case .failure(.stopped(let why)):
                return .cancelled(why)
            case .failure(.timeout):
                let snap = WinSnapshot.take(pid: pid)
                log("⌘⇧G attempt \(attempt): no go-to-folder window yet · windows: "
                    + (snap.fl + snap.panelService).map(\.description).joined(separator: " | "))
            }
            if goTo != nil { break }
        }
        guard let sheet = goTo else { return .failed("la boîte « Open » ne répond pas au clavier (⌘⇧G)") }
        Thread.sleep(forTimeInterval: 0.1)                  // fenêtre stable (animation finie) : champ prêt

        // 2. Chemin tapé (remplace le texte proposé : ⌘A d'abord).
        post(keyCode: 0, flags: .maskCommand, pid: pid)                                     // ⌘A
        Thread.sleep(forTimeInterval: 0.02)
        guard type(path, pid: pid, stop: stop) else { return .cancelled(stop() ?? "arrêt") }
        Thread.sleep(forTimeInterval: 0.1)
        log("path typed (\(path.count) characters)")

        // 3. Entrée : « Aller au dossier » se ferme et sélectionne le fichier.
        post(keyCode: 36, flags: [], pid: pid)
        let closed = gone([sheet.number], 2.0)
        switch closed {
        case .stopped(let why)?: return .cancelled(why)
        case .timeout?:
            post(keyCode: 53, flags: [], pid: pid)                                         // Échap : referme la feuille
            return .failed("chemin du preset refusé par la boîte « Open »")
        case nil: break
        }
        log("go-to-folder closed")
        Thread.sleep(forTimeInterval: 0.15)                 // sélection du fichier dans la liste

        // 4. Entrée : ouvrir. Renvoyé une fois si la boîte reste ouverte (sélection encore en cours).
        for attempt in 1...2 {
            post(keyCode: 36, flags: [], pid: pid)
            switch gone([dialog], attempt == 1 ? 1.2 : 2.0) {
            case nil:
                log("open dialog closed (Enter attempt \(attempt))")
                return .done
            case .stopped(let why)?:
                return .cancelled(why)
            case .timeout?:
                log("dialog still open after Enter attempt \(attempt)")
            }
        }
        return .failed("la boîte « Open » ne s'est pas fermée sur le preset")
    }

    /// Texte frappé caractère par caractère (Unicode joint à chaque événement : indépendant de la disposition du
    /// clavier, AZERTY compris). Faux si arrêté en route.
    static func type(_ text: String, pid: Int32, stop: () -> String?) -> Bool {
        // Par paquets de 12 caractères (un événement peut en porter jusqu'à 20) : 19 ms par caractère mesurés sur la
        // CI en les tapant un par un, soit 1,7 s pour un chemin ; le premier plan n'est vérifié qu'une fois par paquet.
        let units = Array(text.utf16)
        var start = 0
        while start < units.count {
            if stop() != nil { return false }
            guard MacroRunner.isFrontmost(pid) else { return false }
            var end = min(start + 12, units.count)
            if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }   // jamais un caractère coupé
            let chunk = Array(units[start..<end])
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                e.flags = []
                e.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                e.setIntegerValueField(.eventSourceUserData, value: EventTap.mark)
                e.post(tap: .cghidEventTap)
                usleep(2_000)
            }
            start = end
        }
        return true
    }

    /// Une touche (avec ses modificateurs) frappée comme au clavier, seulement si `pid` est au premier plan (elle va
    /// donc à sa fenêtre active : la boîte « Open »). Marquée pour que notre tap l'ignore.
    static func post(keyCode: CGKeyCode, flags: CGEventFlags, pid: Int32) {
        guard MacroRunner.isFrontmost(pid) else { return }
        func send(_ e: CGEvent) { e.post(tap: .cghidEventTap) }
        func flagsEvent(_ f: CGEventFlags) {
            guard let e = CGEvent(source: source) else { return }
            e.type = .flagsChanged
            e.flags = f
            e.setIntegerValueField(.eventSourceUserData, value: EventTap.mark)
            send(e)
        }
        if !flags.isEmpty { flagsEvent(flags) }
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: EventTap.mark)
            send(e)
            usleep(8_000)
        }
        if !flags.isEmpty { flagsEvent([]) }
    }
}

// MARK: - Essai automatique : `FLShortcut --selftest-preset` (CI macOS)

/// L'app ouvre elle-même une boîte « Open », y choisit un fichier temporaire avec `PresetChooser`, et vérifie que
/// c'est bien ce fichier qui est ouvert. Sortie : PASS / FAIL / SKIP (pas d'autorisation d'envoi d'événements).
enum PresetSelfTest {
    static func runIfRequested() {
        guard let flag = CommandLine.arguments.firstIndex(of: "--selftest-preset") else { return }
        // Lancé par `open` (seul moyen d'être au premier plan comme FL) : la sortie va dans le fichier donné.
        if let out = CommandLine.arguments.dropFirst(flag + 1).first, !out.hasPrefix("-") { freopen(out, "w", stdout) }
        setvbuf(stdout, nil, _IOLBF, 0)
        guard CGPreflightPostEventAccess() else {
            print("SKIP: pas d'autorisation d'envoi d'événements pour ce programme")
            exit(0)
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fls-selftest-\(getpid())", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for name in ["Autre preset.fst", "Voix lead (test).fst", "Zz dernier.fst"] {
            FileManager.default.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data("FLS".utf8))
        }
        let wanted = dir.appendingPathComponent("Voix lead (test).fst").resolvingSymlinksInPath()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)
        print("au premier plan : \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")

        let pid = getpid()
        let started = Date()
        DispatchQueue.global(qos: .userInitiated).async {
            // La boîte « Open » : nouvelle fenêtre assez grande.
            let base = WinSnapshot.take(pid: pid).numbers
            guard case .success(let dialog) = WindowWait.newWindow(pid: pid, excluding: base, timeout: 10,
                                                                   accept: { $0.isDialogLike }, stop: { nil }) else {
                print("FAIL: la boîte « Open » n'est pas apparue")
                exit(1)
            }
            print("boîte « Open » : \(dialog)")
            MacroRunner.testFLPID = pid
            // Lancé depuis un terminal, l'app n'est pas au premier plan : un clic dans une zone vide du bas de la
            // boîte (à gauche de « Cancel ») la fait passer devant, comme FL quand la macro tourne.
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid {
                let p = CGPoint(x: dialog.bounds.minX + dialog.bounds.width * 0.4, y: dialog.bounds.maxY - 22)
                for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
                        .post(tap: .cghidEventTap)
                    usleep(40_000)
                }
                let deadline = Date().addingTimeInterval(2)
                while NSWorkspace.shared.frontmostApplication?.processIdentifier != pid, Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                print("au premier plan après le clic : \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
            }
            let outcome = PresetChooser.choose(path: wanted.path, pid: pid, dialog: dialog.number, stop: { nil },
                                               log: { print("  \($0)") })
            print("PresetChooser : \(outcome) en \(Int(Date().timeIntervalSince(started) * 1000)) ms")
            if outcome != .done {
                DispatchQueue.main.async { NSApp.abortModal() }
            }
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = dir
        let response = panel.runModal()
        let chosen = panel.url?.resolvingSymlinksInPath()
        try? FileManager.default.removeItem(at: dir)
        if response == .OK, chosen == wanted {
            print("PASS: preset choisi (\(wanted.lastPathComponent))")
            exit(0)
        }
        print("FAIL: réponse \(response.rawValue), fichier \(chosen?.lastPathComponent ?? "aucun")")
        exit(1)
    }
}
