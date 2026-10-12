// Choix automatique du preset dans la boîte « Open » native de FL (NSOpenPanel), comme les outils de macro établis
// (Keyboard Maestro, « Insert text by pasting ») : chaque étape attend la fenêtre qu'elle doit produire au lieu
// d'une pause fixe (des touches envoyées avant que la boîte soit prête sont perdues).
//  1. ⌘⇧G (« Aller au dossier ») jusqu'à l'apparition de sa fenêtre (renvoyé si la boîte n'était pas prête) ;
//  2. chemin COLLÉ d'un coup (⌘A puis ⌘V), presse-papiers de l'utilisateur rendu ensuite tel quel ;
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
        let front = NSWorkspace.shared.frontmostApplication
        log("frontmost \(front?.localizedName ?? "?") (\(front?.processIdentifier ?? 0)), target \(pid)")
        guard front?.processIdentifier == pid else { return .failed("la boîte « Open » n'est pas au premier plan") }

        // 1. « Aller au dossier » : nouvelle fenêtre du processus (feuille de la boîte), renvoyé tant qu'elle n'apparaît pas.
        var goTo: WinInfo?
        for attempt in 1...4 {
            if let why = stop() { return .cancelled(why) }
            let known = WinSnapshot.take(pid: pid).numbers
            post(keyCode: 5, flags: [.maskCommand, .maskShift], pid: pid)                  // ⌘⇧G
            switch WindowWait.newWindow(pid: pid, excluding: known, timeout: 0.6,
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
        Thread.sleep(forTimeInterval: 0.08)                 // champ prêt à recevoir le texte

        // 2. Chemin collé (presse-papiers rendu ensuite).
        let saved = Clipboard.save()
        Clipboard.setString(path)
        post(keyCode: 0, flags: .maskCommand, pid: pid)                                     // ⌘A (remplace le texte proposé)
        Thread.sleep(forTimeInterval: 0.03)
        post(keyCode: 9, flags: .maskCommand, pid: pid)                                     // ⌘V
        Thread.sleep(forTimeInterval: 0.12)
        log("path pasted (\(path.count) characters)")

        // 3. Entrée : « Aller au dossier » se ferme et sélectionne le fichier.
        post(keyCode: 36, flags: [], pid: pid)
        let closed = gone([sheet.number], 2.0)
        Clipboard.restore(saved, after: 0.3)
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

    /// Une touche (avec ses modificateurs) frappée comme au clavier, seulement si `pid` est au premier plan (elle va
    /// donc à sa fenêtre active : la boîte « Open »). Marquée pour que notre tap l'ignore.
    static func post(keyCode: CGKeyCode, flags: CGEventFlags, pid: Int32) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
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

/// Presse-papiers général : copie complète (tous les types de chaque élément), puis remise en l'état.
enum Clipboard {
    typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    static func save() -> Snapshot {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var out: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let d = item.data(forType: t) { out[t] = d } }
            return out
        }
    }

    static func setString(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    /// Après `after` secondes (le temps que l'app cible ait lu le collage).
    static func restore(_ snapshot: Snapshot, after: TimeInterval) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + after) {
            let pb = NSPasteboard.general
            pb.clearContents()
            guard !snapshot.isEmpty else { return }
            let items: [NSPasteboardItem] = snapshot.map { dict in
                let item = NSPasteboardItem()
                for (t, d) in dict { item.setData(d, forType: t) }
                return item
            }
            pb.writeObjects(items)
        }
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
