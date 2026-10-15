// Effets macOS des macros : touches, lettres, clics, pointeur, attentes de fenêtres, fermeture des menus ouverts par
// la macro, choix du preset. Code DÉPLACÉ tel quel de l'ancien MacroRunner.swift (durées, journal, garde-fous
// identiques) ; les blocs propres à FL (menu de piste, armement, entrée 1) sont dans MacroFLBlocks.swift.
// Garde-fous (même esprit que EventTap.post) :
//  - la macro s'arrête dès que FL n'est plus au premier plan ; Échap l'interrompt à tout moment ;
//  - tout est envoyé au seul PID de FL (postToPid) ; les clics doivent tomber dans une fenêtre de FL ;
//  - les touches sont revérifiées contre la liste noire (⌘Q, ⌘W…) avant l'envoi ;
//  - aucune frappe n'est lue ni journalisée : seules des durées / étapes sont retenues pour le diagnostic.
// Un objet neuf par passage : l'état partagé entre les blocs (boîte suivie, piste visée, pointeur à remettre…) ne
// survit jamais à un passage.
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Fenêtres de FL (CoreGraphics : PID, niveau et cadre seulement, aucune permission d'écran)

enum FLWindows {
    struct Info {
        let layer: Int
        let bounds: CGRect
        var number: Int = 0
    }

    /// Fenêtres visibles du processus, de l'avant vers l'arrière.
    static func list(pid: Int32) -> [Info] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var out: [Info] = []
        for w in raw {
            guard let owner = w[kCGWindowOwnerPID as String] as? Int32, owner == pid,
                  let layer = w[kCGWindowLayer as String] as? Int,
                  let dict = w[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }
            out.append(Info(layer: layer, bounds: bounds, number: w[kCGWindowNumber as String] as? Int ?? 0))
        }
        return out
    }

    /// Fenêtres « normales » et boîtes de dialogue (niveaux 0 à 8 ; les menus contextuels sont plus haut).
    static func dialogCount(pid: Int32) -> Int {
        list(pid: pid).filter { (0...8).contains($0.layer) && $0.bounds.width > 50 && $0.bounds.height > 50 }.count
    }

    /// Fenêtre de FL (niveau 0) sous le point, la plus à l'avant.
    static func frame(containing p: CGPoint, pid: Int32) -> CGRect? {
        list(pid: pid).first { $0.layer == 0 && $0.bounds.contains(p) }?.bounds
    }

    /// Le point est dans une fenêtre de FL (menus contextuels compris).
    static func contains(_ p: CGPoint, pid: Int32) -> Bool {
        list(pid: pid).contains { $0.bounds.insetBy(dx: -2, dy: -2).contains(p) }
    }

    /// Appli qui recevrait VRAIMENT un clic à ce point, d'après le système (Accessibilité, permission déjà donnée) :
    /// les fenêtres transparentes qui laissent passer la souris (enregistreurs d'écran, utilitaires, Dock, nos
    /// bulles) ne comptent pas. Repli : fenêtre normale (niveau 0) tout devant.
    static func receiverPID(at p: CGPoint) -> Int32? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.3)
        var element: AXUIElement?
        if AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &element) == .success, let element {
            var pid: pid_t = 0
            if AXUIElementGetPid(element, &pid) == .success, pid != 0 { return pid }
        }
        return topNormalWindow(at: p)?.pid
    }

    /// Fenêtre normale (niveau 0) tout devant à ce point, sans les nôtres : (processus, nom de l'appli).
    static func topNormalWindow(at p: CGPoint) -> (pid: Int32, name: String)? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        let me = getpid()
        for w in raw {                                            // de l'avant vers l'arrière
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  let owner = w[kCGWindowOwnerPID as String] as? Int32, owner != me,
                  let dict = w[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary), bounds.contains(p) else { continue }
            return (owner, w[kCGWindowOwnerName as String] as? String ?? "une autre app")
        }
        return nil
    }

    /// Position actuelle du curseur, en coordonnées CoreGraphics (origine en haut à gauche).
    static func cursor() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }
}

// MARK: - Menus via l'Accessibilité (la permission est déjà celle du tap clavier)

enum AXMenus {
    /// Appuie successivement sur chaque titre. Le menu de la barre des menus de FL est ignoré :
    /// on cherche le menu contextuel ouvert, pas « File » de la barre du haut.
    static func pressPath(pid: Int32, titles: [String], perItemTimeout: TimeInterval,
                          shouldStop: () -> Bool) -> Bool {
        pressPath(pid: pid, variants: titles.map { [$0] }, perItemTimeout: perItemTimeout, shouldStop: shouldStop)
    }

    /// Chaque niveau du menu accepte plusieurs libellés (« File » ou « Fichier »…).
    static func pressPath(pid: Int32, variants: [[String]], perItemTimeout: TimeInterval,
                          shouldStop: () -> Bool) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        for titles in variants {
            let deadline = Date().addingTimeInterval(perItemTimeout)
            var pressed = false
            while Date() < deadline, !shouldStop() {
                var item: AXUIElement?
                for title in titles where item == nil {
                    item = findItem(in: app, title: title, deadline: deadline, shouldStop: shouldStop)
                }
                if let item, AXUIElementPerformAction(item, kAXPressAction as CFString) == .success {
                    pressed = true
                    break
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
            guard pressed else { return false }
            Thread.sleep(forTimeInterval: 0.15)
        }
        return true
    }

    private static func normalized(_ s: String) -> String {
        var t = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasSuffix("…") || t.hasSuffix(".") { t.removeLast() }
        return t
    }

    private static func matches(_ have: String, _ want: String) -> Bool {
        let h = normalized(have), w = normalized(want)
        return w.count <= 6 ? h == w : h.hasPrefix(w)
    }

    private static func attribute(_ el: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &value) == .success,
              let list = value as? [AXUIElement] else { return [] }
        return list
    }

    /// Parcours en largeur, borné (300 nœuds et l'échéance de l'étape), sans la barre des menus.
    private static func findItem(in root: AXUIElement, title: String, deadline: Date = .distantFuture,
                                 shouldStop: () -> Bool = { false }) -> AXUIElement? {
        var queue: [AXUIElement] = [root]
        var visited = 0
        while !queue.isEmpty, visited < 300, Date() < deadline, !shouldStop() {
            let el = queue.removeFirst()
            visited += 1
            let role = attribute(el, kAXRoleAttribute as String)
            if role == (kAXMenuBarRole as String) { continue }
            if role == (kAXMenuItemRole as String), let t = attribute(el, kAXTitleAttribute as String), matches(t, title) {
                return el
            }
            queue.append(contentsOf: children(el))
        }
        return nil
    }

    /// Arbre d'accessibilité de FL (diagnostic `--diag-macro`).
    static func dump(pid: Int32, maxDepth: Int = 6, maxNodes: Int = 800) -> [String] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var lines: [String] = []
        var count = 0
        func walk(_ el: AXUIElement, depth: Int) {
            guard depth <= maxDepth, count < maxNodes else { return }
            count += 1
            let role = attribute(el, kAXRoleAttribute as String) ?? "?"
            let sub = attribute(el, kAXSubroleAttribute as String).map { "/" + $0 } ?? ""
            let title = attribute(el, kAXTitleAttribute as String).map { " « \($0) »" } ?? ""
            lines.append(String(repeating: "  ", count: depth) + role + sub + title)
            for child in children(el) { walk(child, depth: depth + 1) }
        }
        walk(app, depth: 0)
        return lines
    }
}

// MARK: - Effets d'un passage

final class MacroEffectsMac: MacroEffects {
    struct Context {
        let pid: Int32
        let origin: CGPoint
        let frame: CGRect?
        let baseline: Int
        /// Piste visée par les étapes automatiques : dernier clic dans FL, sinon position du curseur.
        let track: CGPoint
        /// Fenêtres visibles au démarrage de la macro (FL + panneaux hors processus).
        let startNumbers: Set<Int>
    }

    enum MenuStop: Error {
        case cancel(String)
        case fail(String)
    }

    func result(_ stop: MenuStop) -> StepResult {
        switch stop {
        case .cancel(let why): return .cancel(why)
        case .fail(let why): return .fail(why)
        }
    }

    let pid: Int32
    /// Relevés du départ, posés par `begin`.
    var ctx: Context
    private var initial = WinSnapshot(time: 0, fl: [], panelService: [])

    /// Résultat de la vérification du larsen, lancée en parallèle au début de la macro.
    let feedbackReport = Locked<FeedbackRisk.Report?>(nil)
    let feedbackReady = DispatchSemaphore(value: 0)

    /// Point du dernier clic de la macro (repère `lastClick`).
    var lastClickPoint: CGPoint?
    /// Boîte de dialogue ouverte par le menu (waitDialog → waitDialogClose).
    var dialog: WinInfo?
    /// Point du clic droit qui a ouvert le menu de piste (rangée des noms).
    var trackTarget: CGPoint?
    /// Position du pointeur de l'utilisateur avant une série de clics automatiques.
    var cursorBeforeBurst: CGPoint?
    /// FL a répondu au hit-test AX sur son menu par un rôle de menu : titres utilisables (niveau 0).
    var popupAX = false
    /// Dernier menu attendu par « Attendre une fenêtre (menu) » : repère des clics « menu ouvert ».
    var lastMenu: WinInfo?
    /// Fenêtres de FL juste avant le dernier clic appris (ou menu de la barre) : ce qui n'y est pas vient d'être ouvert.
    var numbersBeforeLastClick: Set<Int>?

    /// Source privée partagée par tous les passages (comme avant : une seule pour l'app).
    static let sharedSource: CGEventSource? = {
        let s = CGEventSource(stateID: .privateState)
        s?.localEventsSuppressionInterval = 0             // ne pas geler la souris réelle après nos événements
        return s
    }()
    var source: CGEventSource? { Self.sharedSource }

    static var warpCursor: Bool { MacroRunner.warpCursor }
    static var clicksToPid: Bool { MacroRunner.clicksToPid }
    static var testFLPID: Int32? { MacroRunner.testFLPID }
    static var armDownCount: Int { MacroRunner.armDownCount }

    init(pid: Int32) {
        self.pid = pid
        ctx = Context(pid: pid, origin: .zero, frame: nil, baseline: 0, track: .zero, startNumbers: [])
    }

    // MARK: Protocole MacroEffects

    func log(_ tag: String, _ text: String) { MacroLog.shared.write(tag, text) }

    func begin(startFeedbackEarly: Bool) -> String? {
        let origin = FLWindows.cursor()
        lastClickPoint = nil
        trackTarget = nil
        cursorBeforeBurst = nil
        dialog = nil
        popupAX = false
        numbersBeforeLastClick = nil
        if startFeedbackEarly {
            let report = feedbackReport, ready = feedbackReady, pid = self.pid
            DispatchQueue.global(qos: .utility).async {
                let r = FeedbackRisk.check(flPID: pid)
                report.withLock { $0 = r }
                ready.signal()
            }
        }
        DispatchQueue.main.sync {                                  // synchrone : jamais notre bulle sous un clic,
            HintPanel.shared.hide()                                // ni le créateur de macros devant FL
            CreatorPresence.stepAside()
        }
        guard CGPreflightPostEventAccess() else {
            return "autorise FL Shortcut dans Réglages Système › Confidentialité et sécurité › Accessibilité"
        }
        let initial = WinSnapshot.take(pid: pid)
        MacroLog.shared.windows("start", initial)
        func frame(_ p: CGPoint) -> CGRect? { initial.fl.first { $0.layer == 0 && $0.bounds.contains(p) }?.bounds }
        var track = origin
        if let p = MacroRunner.testTrackPoint {
            track = p
            MacroLog.shared.write("TRACK", "test track (\(Int(p.x)),\(Int(p.y)))")
        } else if let remembered = TrackMemory.shared.lastClickInfo() {
            let same = initial.window(remembered.window).map { MacroSpots.sameSize($0.bounds.size, remembered.windowSize) } ?? false
            MacroLog.shared.write("TRACK", "remembered (\(Int(remembered.point.x)),\(Int(remembered.point.y))) "
                + "\(Int(-remembered.date.timeIntervalSinceNow)) s ago in #\(remembered.window): \(same ? "window unchanged" : "window gone/resized → ignored")")
            if same { track = remembered.point }
        } else {
            MacroLog.shared.write("TRACK", "no remembered click → cursor (\(Int(origin.x)),\(Int(origin.y)))")
        }
        self.initial = initial
        ctx = Context(pid: pid, origin: origin, frame: frame(origin),
                      baseline: FLWindows.dialogCount(pid: pid), track: track, startNumbers: initial.numbers)
        return nil
    }

    /// La piste visée est dans une fenêtre normale de FL (relevé du départ).
    func targetTrackIsInFL() -> Bool {
        initial.fl.first { $0.layer == 0 && $0.bounds.contains(ctx.track) } != nil
    }

    func stopReason() -> String? { shouldStop(pid) }

    func pause(ms: Int) -> StepResult { pause(ms, pid: pid) }

    func cleanup(state: inout RunState) {
        restoreCursor()
        DispatchQueue.main.async { CreatorPresence.comeBack() }
    }

    // MARK: Blocs simples

    func perform(_ body: BlockBody, state: inout RunState) -> StepResult {
        switch body {
        case .delay(let ms):
            return pause(ms, pid: ctx.pid)

        case .key(let ref, let times):
            for i in 0..<max(times, 1) {
                if i > 0 { Thread.sleep(forTimeInterval: 0.015) }
                MacroLog.shared.write("KEY", "touche envoyée (masquée)")
                guard !EventTap.shared.currentConfig.forbidden.isForbidden(ref.combo) else { return .fail("touche interdite") }
                postKey(ref.combo, pid: ctx.pid)
            }
            return .ok

        case .click(let target, let button):
            return click(target, right: button == .right, ctx: ctx)

        case .menuAX(let titles, let fallback):
            let found = AXMenus.pressPath(pid: ctx.pid, titles: titles, perItemTimeout: 0.9) {
                shouldStop(ctx.pid) != nil
            }
            if found { return .ok }
            if let stop = shouldStop(ctx.pid) { return .cancel(stop) }
            guard !fallback.isEmpty else {
                return .fail("menu introuvable : apprends les positions du menu dans la fiche du raccourci")
            }
            for target in fallback {
                let result = click(target, right: false, ctx: ctx)
                guard case .ok = result else { return result }
                if case .cancel(let why) = pause(250, pid: ctx.pid) { return .cancel(why) }
            }
            return .ok

        case .menuBar(let titles):
            numbersBeforeLastClick = WinSnapshot.take(pid: ctx.pid).numbers
            switch MenuBarAX.press(pid: ctx.pid, titles: titles, stop: { self.shouldStop(ctx.pid) }) {
            case .done: return .ok
            case .cancelled(let why): return .cancel(why)
            case .failed(let why): return .fail(why)
            }

        case .waitWindow(.dialog, let ms):
            return waitDialogOpen(timeoutMs: ms, ctx: ctx)

        case .waitWindow(.menu, let ms):
            return waitMenuOpen(timeoutMs: ms, ctx: ctx)

        case .waitWindowClose(.dialog, let ms):
            return waitDialogClosed(timeoutMs: ms, ctx: ctx)

        case .waitWindowClose(.menu, let ms):
            return waitMenuClosed(timeoutMs: ms, ctx: ctx)

        case .trackMenu(let letters, let labels, let target, let enter):
            return trackMenu(letters: letters, labels: labels, at: target == .cursor ? ctx.origin : ctx.track,
                             enter: EnterMemory(policy: enter), ctx: ctx)

        case .feedbackCheck:
            // Vérification lancée dès le début de la macro (Core Audio peut mettre plusieurs secondes à répondre
            // la première fois) : ici, le résultat est en général déjà prêt.
            // Jamais d'attente : résultat pas encore prêt → la fenêtre s'affichera dès qu'il l'est.
            let report = feedbackReport, ready = feedbackReady
            if ready.wait(timeout: .now() + 0.05) == .success {
                guard let r = report.value, r.risky else { return .ok }
                DispatchQueue.main.async { FeedbackAlert.show(r) }
                return .warn("risque de larsen : change d'entrée ou de sortie (casque, carte son)")
            }
            DispatchQueue.global(qos: .utility).async {
                _ = ready.wait(timeout: .now() + 10)
                if let r = report.value, r.risky { DispatchQueue.main.async { FeedbackAlert.show(r) } }
            }
            return .ok

        case .selectInput(.legacy(let key)):
            guard key == MacroSpots.PathKind.input.rawValue else { return .fail("positions apprises inconnues") }
            return selectInput(ctx: ctx)

        case .chooseFile(let path):
            MacroLog.shared.write("FILE", "chemin du preset saisi (\(path.count) caractères)")
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
                return .fail("preset introuvable (\(URL(fileURLWithPath: path).lastPathComponent))")
            }
            guard let d = dialog ?? WinSnapshot.take(pid: ctx.pid).fl.first(where: {
                !ctx.startNumbers.contains($0.number) && $0.isDialogLike && $0.layer < 20 }) else {
                return .fail("boîte « Open » introuvable")
            }
            restoreCursor()
            switch PresetChooser.choose(path: path, pid: ctx.pid, dialog: d.number, stop: { self.shouldStop(ctx.pid) }) {
            case .done: return .ok
            case .cancelled(let why): return .cancel(why)
            case .failed(let why): return .fail(why)
            }

        case .dropFile(let path):
            MacroLog.shared.write("FILE", "preset déposé sur la piste (\(path.count) caractères)")
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
                return .fail("preset introuvable (\(URL(fileURLWithPath: path).lastPathComponent))")
            }
            return dropFile(path, at: ctx.track, ctx: ctx)

        case .menuLetters(let letters, let enter):
            return menuLetters(letters, enter: EnterMemory(policy: enter), ctx: ctx)

        case .menuKey(let key, let times):
            return menuKey(key, times: times, ctx: ctx)

        case .flAction(let key, let fallback):
            return flActions([FLActionCall(key: key, fallback: fallback)], state: &state)

        case .flActionValue:
            return .fail("action avec valeur : demande l'extension du lien avec FL")

        case .ifElse, .repeatCount, .repeatWhile, .waitUntil, .setVariable, .stop, .comment, .unknown:
            return .fail("bloc de contrôle hors de l'interpréteur")
        }
    }

    // MARK: Conditions qui regardent FL

    func evaluate(_ c: Condition, state: inout RunState) -> Result<Bool, StepFailure> {
        switch c {
        case .windowOpen(.dialog):
            let snap = WinSnapshot.take(pid: ctx.pid)
            let open = snap.fl.contains { !ctx.startNumbers.contains($0.number) && $0.isDialogLike && $0.layer < 20 }
                || snap.panelService.contains { !ctx.startNumbers.contains($0.number) && $0.isDialogLike }
            return .success(open)
        case .windowOpen(.menu):
            return .success(!menusOpenedByMacro(ctx: ctx).isEmpty)
        case .flState:
            return .failure(.fail("condition sur l'état de FL : demande l'extension du lien avec FL"))
        case .variable, .lastBlockFailed, .not, .all, .any:
            return .failure(.fail("condition évaluée par l'interpréteur"))
        }
    }

    // MARK: Garde-fous

    /// Raison d'arrêter maintenant, sinon nil.
    func shouldStop(_ pid: Int32) -> String? {
        if let test = Self.testFLPID {
            guard test == pid, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                return "FL n'est plus au premier plan"
            }
        } else {
            let cfg = EventTap.shared.currentConfig
            guard cfg.flPIDs.contains(pid), cfg.frontmostPID == pid else { return "FL n'est plus au premier plan" }
        }
        if CGEventSource.keyState(.combinedSessionState, key: 53) { return "Échap" }
        return nil
    }

    /// Pause interrompue par Échap ou la perte du premier plan de FL.
    func pause(_ ms: Int, pid: Int32) -> StepResult {
        var left = Double(ms) / 1000
        while left > 0 {
            if let stop = shouldStop(pid) { return .cancel(stop) }
            let slice = min(left, 0.05)
            Thread.sleep(forTimeInterval: slice)
            left -= slice
        }
        return .ok
    }

    // MARK: Clavier

    /// Aucun modificateur et (sans insister) aucune touche enfoncés, R du raccourci compris : FL 2026 lit l'état réel
    /// des modificateurs, les clics envoyés en HID reprennent les modificateurs enfoncés, et un menu de FL ouvert réagit
    /// aux touches (relâcher ⌃ peut le fermer). Renvoie false seulement si des modificateurs restent enfoncés.
    func waitForKeyboardIdle(timeout: TimeInterval) -> Bool {
        let start = Date()
        let mask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        var modsUp = false
        var modsUpAt: Date?
        while Date().timeIntervalSince(start) < timeout {
            modsUp = CGEventSource.flagsState(.combinedSessionState).intersection(mask).isEmpty
            if modsUp {
                if !Self.anyKeyDown() {
                    MacroLog.shared.write("KEYS", "keyboard idle after \(Int(Date().timeIntervalSince(start) * 1000)) ms")
                    return true
                }
                // Modificateurs relâchés : une autre touche tenue (ou signalée à tort) ne retarde pas plus de 0,3 s.
                if let t = modsUpAt, Date().timeIntervalSince(t) > 0.3 { break }
                if modsUpAt == nil { modsUpAt = Date() }
            } else {
                modsUpAt = nil
            }
            Thread.sleep(forTimeInterval: 0.008)
        }
        MacroLog.shared.write("KEYS", modsUp ? "a key is still down after \(Int(Date().timeIntervalSince(start) * 1000)) ms → going on" : "modifiers still held")
        return modsUp
    }

    static func anyKeyDown() -> Bool {
        for code in CGKeyCode(0)..<CGKeyCode(128) where code != 57 && code != 63 {      // verrouillage majuscules, fn
            if CGEventSource.keyState(.combinedSessionState, key: code) { return true }
        }
        return false
    }

    // MARK: Curseur

    func restoreCursor() {
        guard let p = cursorBeforeBurst else { return }
        cursorBeforeBurst = nil
        guard Self.warpCursor else { return }
        CGWarpMouseCursorPosition(p)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    /// Pointeur juste à côté du menu (à gauche, sinon à droite) : plus aucun élément survolé.
    func hoverOutside(_ menu: CGRect, pid: Int32) {
        let screen = Self.displayBounds(containing: CGPoint(x: menu.midX, y: menu.midY))
        let x = menu.minX - 24 >= screen.minX ? menu.minX - 24 : min(menu.maxX + 24, screen.maxX - 2)
        let p = CGPoint(x: x, y: min(max(menu.minY + 12, screen.minY + 2), screen.maxY - 2))
        if cursorBeforeBurst == nil { cursorBeforeBurst = FLWindows.cursor() }
        if Self.warpCursor {
            CGWarpMouseCursorPosition(p)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        if let e = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left) {
            e.flags = []
            e.setIntegerValueField(.eventSourceUserData, value: EventTap.mark)
            if Self.clicksToPid { e.postToPid(pid) } else { e.post(tap: .cghidEventTap) }
        }
        MacroLog.shared.write("MOVE", "pointer beside the menu (\(Int(p.x)),\(Int(p.y)))")
        Thread.sleep(forTimeInterval: 0.04)
    }

    /// Au moins un des menus ouverts par la macro est encore à l'écran.
    func menusOpen(_ numbers: Set<Int>, ctx: Context) -> Bool {
        !WinSnapshot.take(pid: ctx.pid).numbers.isDisjoint(with: numbers)
    }

    /// Codes de touche (position ANSI) des lettres. F et O sont au même endroit en AZERTY ; le caractère est aussi
    /// joint à l'événement.
    static let letterKeyCodes: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    ]

    /// Lettre sans modificateur (raccourci d'un élément de menu), envoyée au seul processus de FL.
    func postLetter(_ letter: Character, pid: Int32) {
        guard let code = Self.letterKeyCodes[letter] else { return }
        MacroLog.shared.write("KEY", "menu letter « \(letter) »")
        let units = Array(String(letter).utf16)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { continue }
            e.flags = []
            e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            e.setIntegerValueField(.eventSourceUserData, value: EventTap.mark)
            e.postToPid(pid)
            usleep(15_000)
        }
    }

    /// Clic gauche en `p` seulement si `p` est dans `popup`, que le menu est toujours là au même endroit, qu'il est
    /// la fenêtre de FL tout devant en `p` et qu'aucune autre appli ne le couvre (hit-test Accessibilité).
    func clickInside(_ p: CGPoint, popup: WinInfo, ctx: Context) -> StepResult {
        if let stop = shouldStop(ctx.pid) { return .cancel(stop) }
        let snap = WinSnapshot.take(pid: ctx.pid)
        guard let now = snap.window(popup.number), now.bounds == popup.bounds else {
            MacroLog.shared.windows("popup moved or closed before the click", snap)
            return .fail("le menu de FL s'est fermé avant le clic")
        }
        guard popup.bounds.insetBy(dx: 2, dy: 2).contains(p) else { return .fail("point hors du menu : réapprends les clics") }
        guard snap.hit(p)?.number == popup.number else {
            MacroLog.shared.windows("another FL window above the item", snap)
            return .fail("une autre fenêtre de FL couvre le menu")
        }
        let ax = AXProbe.hit(p, timeout: 0.05)
        MacroLog.shared.write("AX", "at (\(Int(p.x)),\(Int(p.y))): \(ax)")
        if ax.error == .success, ax.pid != 0, ax.pid != ctx.pid, ax.pid != getpid() {
            let name = NSRunningApplication(processIdentifier: ax.pid)?.localizedName ?? "une autre app"
            return .fail("« \(name) » couvre le menu de FL")
        }
        postClick(at: p, right: false, pid: ctx.pid, hoverMs: 35)       // survol d'abord : les menus maison suivent le pointeur
        lastClickPoint = p
        return .ok
    }

    /// Échap seulement tant qu'un menu ouvert par NOUS (absent de `base`) est encore à l'écran : jamais d'Échap à
    /// l'aveugle, que FL pourrait appliquer à sa fenêtre / son panneau actif.
    func closePopups(base: Set<Int>, ctx: Context) {
        for attempt in 1...3 {
            let open = WinSnapshot.take(pid: ctx.pid).fl.filter { !base.contains($0.number) && $0.isMenuLike }
            guard let top = open.first else { return }
            MacroLog.shared.write("ESC", "attempt \(attempt): \(open.map(\.description).joined(separator: ", "))")
            postKey(KeyCombo(keyCode: 53), pid: ctx.pid)
            _ = WindowWait.gone(pid: ctx.pid, numbers: [top.number], timeout: 0.3, stop: { nil })
        }
    }

    static func displayBounds(containing p: CGPoint) -> CGRect {
        var ids = [CGDirectDisplayID](repeating: 0, count: 4)
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(p, 4, &ids, &count) == .success, count > 0 else { return CGDisplayBounds(CGMainDisplayID()) }
        return CGDisplayBounds(ids[0])
    }

    /// Haut de l'écran, sur la moitié qui ne contient pas `p` (le menu de FL s'ouvre près de `p`).
    static func hintPoint(awayFrom p: CGPoint) -> CGPoint {
        let d = displayBounds(containing: p)
        return CGPoint(x: p.x > d.midX ? d.minX + d.width * 0.25 : d.minX + d.width * 0.75, y: d.minY + 60)
    }

    // MARK: Boîte de dialogue (suivie par son numéro de fenêtre, pas par un nombre de fenêtres)

    func waitDialogOpen(timeoutMs: Int, ctx: Context) -> StepResult {
        restoreCursor()
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        while Date() < deadline {
            if let stop = shouldStop(ctx.pid) { return .cancel(stop) }
            let snap = WinSnapshot.take(pid: ctx.pid)
            let fresh = snap.fl.first { !ctx.startNumbers.contains($0.number) && $0.isDialogLike && $0.layer < 20 }
                ?? snap.panelService.first { !ctx.startNumbers.contains($0.number) && $0.isDialogLike }
            if let fresh {
                dialog = fresh
                MacroLog.shared.windows("dialog \(fresh) opened", snap, mark: [fresh.number])
                return .ok
            }
            Thread.sleep(forTimeInterval: 0.03)
        }
        MacroLog.shared.windows("no dialog after \(timeoutMs) ms", WinSnapshot.take(pid: ctx.pid))
        return .fail("boîte de dialogue introuvable")
    }

    func waitDialogClosed(timeoutMs: Int, ctx: Context) -> StepResult {
        restoreCursor()
        guard let d = dialog else {
            return wait(timeoutMs: timeoutMs, pid: ctx.pid, failure: "la boîte de dialogue ne se ferme pas") {
                FLWindows.dialogCount(pid: ctx.pid) <= ctx.baseline
            }
        }
        switch WindowWait.gone(pid: ctx.pid, numbers: [d.number], timeout: Double(timeoutMs) / 1000,
                               interval: timeoutMs > 10_000 ? 0.05 : 0.03, stop: { self.shouldStop(ctx.pid) }) {
        case .success:
            MacroLog.shared.write("DIALOG", "#\(d.number) closed")
            return .ok
        case .failure(.stopped(let why)):
            return .cancel(why)
        case .failure(.timeout):
            return .fail("la boîte de dialogue ne se ferme pas")
        }
    }

    func wait(timeoutMs: Int, pid: Int32, failure: String, until condition: () -> Bool) -> StepResult {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        // Longue attente (choix du preset) : 4 vérifications par seconde suffisent, Échap reste immédiat.
        let interval = timeoutMs > 10_000 ? 0.1 : 0.03
        var nextCheck = Date.distantPast
        while Date() < deadline {
            if let stop = shouldStop(pid) { return .cancel(stop) }
            if Date() >= nextCheck {
                if condition() { return .ok }
                nextCheck = Date().addingTimeInterval(interval)
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return .fail(failure)
    }

    // MARK: Menus et fenêtres ouverts par la macro (blocs génériques)

    /// Menus de FL (au-dessus des boîtes de dialogue) absents au démarrage de la macro.
    func menusOpenedByMacro(ctx: Context) -> Set<Int> {
        Set(WinSnapshot.take(pid: ctx.pid).fl.filter { !ctx.startNumbers.contains($0.number) && $0.isMenuLike && $0.layer > 8 }
            .map(\.number))
    }

    func waitMenuOpen(timeoutMs: Int, ctx: Context) -> StepResult {
        switch WindowWait.newWindow(pid: ctx.pid, excluding: ctx.startNumbers, timeout: Double(timeoutMs) / 1000,
                                    accept: { $0.isMenuLike && $0.layer > 8 }, stop: { self.shouldStop(ctx.pid) }) {
        case .success(let w):
            lastMenu = w
            MacroLog.shared.write("MENU", "menu \(w) open")
            // Comme le menu de la piste : FL ouvre souvent son menu sous le pointeur, dont le survol ouvrirait un
            // sous-menu tout seul ; le pointeur est mis juste à côté (remis à sa place à la fin de la macro).
            hoverOutside(w.bounds, pid: ctx.pid)
            return .ok
        case .failure(.stopped(let why)):
            return .cancel(why)
        case .failure(.timeout):
            return .fail("aucun menu de FL ne s'est ouvert")
        }
    }

    func waitMenuClosed(timeoutMs: Int, ctx: Context) -> StepResult {
        let open = menusOpenedByMacro(ctx: ctx)
        guard !open.isEmpty else { return .ok }
        switch WindowWait.gone(pid: ctx.pid, numbers: open, timeout: Double(timeoutMs) / 1000, stop: { self.shouldStop(ctx.pid) }) {
        case .success:
            MacroLog.shared.write("MENU", "menus closed")
            return .ok
        case .failure(.stopped(let why)):
            return .cancel(why)
        case .failure(.timeout):
            return .fail("le menu de FL est resté ouvert")
        }
    }

    /// Lettres soulignées dans un menu ouvert par la macro (chaque lettre seulement si un de ces menus est encore là).
    func menuLetters(_ letters: [Character], enter: EnterMemory, ctx: Context) -> StepResult {
        var opened = menusOpenedByMacro(ctx: ctx)
        guard !opened.isEmpty else { return .fail("aucun menu de FL ouvert par la macro") }
        guard letters.allSatisfy({ Self.letterKeyCodes[$0] != nil }) else { return .fail("lettre de menu non prise en charge") }
        for (i, letter) in letters.enumerated() {
            guard menusOpen(opened, ctx: ctx) else { return .fail("le menu de FL s'est fermé tout seul") }
            let known = WinSnapshot.take(pid: ctx.pid).numbers
            postLetter(letter, pid: ctx.pid)
            guard i + 1 < letters.count else { break }
            switch WindowWait.newWindow(pid: ctx.pid, excluding: known, timeout: 0.6,
                                        accept: { $0.isMenuLike }, stop: { self.shouldStop(ctx.pid) }) {
            case .success(let w): opened.insert(w.number)
            case .failure(.stopped(let why)): return .cancel(why)
            case .failure(.timeout): break                 // la lettre a seulement surligné son élément
            }
        }
        guard enter.policy != .never else { return .ok }
        let needsEnter = enter.read()
        if needsEnter != true {
            switch WindowWait.gone(pid: ctx.pid, numbers: opened, timeout: needsEnter == false ? 0.8 : 0.5,
                                   stop: { self.shouldStop(ctx.pid) }) {
            case .success:
                enter.write(false)
                return .ok
            case .failure(.stopped(let why)):
                return .cancel(why)
            case .failure(.timeout):
                break
            }
        } else {
            _ = WindowWait.gone(pid: ctx.pid, numbers: opened, timeout: 0.12, stop: { self.shouldStop(ctx.pid) })
            guard menusOpen(opened, ctx: ctx) else {
                enter.write(false)
                return .ok
            }
        }
        postKey(KeyCombo(keyCode: 36), pid: ctx.pid)
        switch WindowWait.gone(pid: ctx.pid, numbers: opened, timeout: 0.8, stop: { self.shouldStop(ctx.pid) }) {
        case .success:
            enter.write(true)
            return .ok
        case .failure(.stopped(let why)):
            return .cancel(why)
        case .failure(.timeout):
            closePopups(base: ctx.startNumbers, ctx: ctx)
            enter.write(nil)
            return .fail("le menu de FL n'a pas répondu")
        }
    }

    /// Flèche, Entrée ou Échap, seulement tant qu'un menu ouvert par la macro est là.
    func menuKey(_ key: MenuKey, times: Int, ctx: Context) -> StepResult {
        let opened = menusOpenedByMacro(ctx: ctx)
        guard !opened.isEmpty else { return .fail("aucun menu de FL ouvert par la macro") }
        for i in 0..<max(times, 1) {
            guard menusOpen(opened, ctx: ctx) else {
                return i > 0 && (key == .enter || key == .escape) ? .ok : .fail("le menu de FL s'est fermé")
            }
            postKey(KeyCombo(keyCode: key.keyCode), pid: ctx.pid)
            MacroLog.shared.write("KEY", "menu key \(key.rawValue)")
            Thread.sleep(forTimeInterval: 0.015)
        }
        return .ok
    }

    // MARK: Cibles de clic

    /// Niveaux des fenêtres de FL qu'un clic appris peut viser : fenêtre principale (0), fenêtres détachées ou
    /// flottantes, réglages (Options › Audio…), boîtes de dialogue (8). Au-dessus : les menus.
    static let clickWindowLayers = 0...8
    /// Délai pour qu'apparaisse la fenêtre ou le menu visé quand le clic précédent vient de l'ouvrir (la fenêtre des
    /// réglages de FL peut mettre un moment à s'ouvrir la première fois). Rien n'est attendu s'il est déjà là.
    static let windowAppearTimeout: TimeInterval = 3
    static let menuAppearTimeout: TimeInterval = 1.5

    /// Fenêtre de FL de cette taille (à 2 points près) visée par un clic appris : celle qui contient la piste visée,
    /// sinon la plus à l'avant.
    static func clickWindow(in snap: WinSnapshot, size: CGSize, track: CGPoint) -> WinInfo? {
        let fits = snap.fl.filter { clickWindowLayers.contains($0.layer) && MacroSpots.sameSize($0.bounds.size, size) }
        return fits.first { $0.bounds.contains(track) } ?? fits.first
    }

    /// Point visé, et le menu dans lequel il doit tomber (cible « menu ouvert »).
    func resolve(_ target: ClickTarget, ctx: Context) -> (point: CGPoint, popup: WinInfo?)? {
        switch target {
        case .startCursor(let dx, let dy):
            return (CGPoint(x: ctx.origin.x + dx, y: ctx.origin.y + dy), nil)
        case .flWindow(let corner, let dx, let dy, let size):
            let frame: CGRect?
            if let size {
                frame = Self.clickWindow(in: WinSnapshot.take(pid: ctx.pid), size: size, track: ctx.track)?.bounds
            } else {
                frame = ctx.frame
            }
            guard let f = frame else { return nil }
            let x: CGFloat = corner == .topLeft || corner == .bottomLeft ? f.minX : f.maxX
            let y: CGFloat = corner == .topLeft || corner == .topRight ? f.minY : f.maxY
            return (CGPoint(x: x + dx, y: y + dy), nil)
        case .cursorXWindowY(let dx, let dy):
            guard let f = ctx.frame else { return nil }
            return (CGPoint(x: ctx.origin.x + dx, y: f.minY + dy), nil)
        case .lastClick(let dx, let dy):
            guard let last = lastClickPoint else { return nil }
            return (CGPoint(x: last.x + dx, y: last.y + dy), nil)
        case .track(let dx, let dy):
            return (CGPoint(x: ctx.track.x + dx, y: ctx.track.y + dy), nil)
        case .openMenu(let hop):
            let snap = WinSnapshot.take(pid: ctx.pid)
            let remembered = lastMenu.flatMap { m in snap.window(m.number).flatMap { $0.bounds == m.bounds ? $0 : nil } }
            // Le menu attendu par « Attendre un menu », sinon le menu ouvert par la macro qui a la forme apprise (le
            // plus à l'avant : un sous-menu passe devant le menu qui l'a ouvert).
            let opened = snap.fl.filter { !ctx.startNumbers.contains($0.number) && $0.isMenuLike && $0.layer > 8 }
            guard let menu = remembered.flatMap({ hop.fits($0.bounds) ? $0 : nil })
                    ?? opened.first(where: { hop.fits($0.bounds) }) else { return nil }
            return (hop.point(in: menu.bounds), menu)
        case .toLearn:
            return nil                                  // refusé par la validation : jamais de clic à l'aveugle
        }
    }

    /// Fenêtre (taille retenue) ou menu de FL : attendu s'il n'est pas encore là. Autres cibles : jamais attendues.
    static func appearTimeout(of target: ClickTarget) -> TimeInterval? {
        switch target {
        case .flWindow(_, _, _, .some): return windowAppearTimeout
        case .openMenu: return menuAppearTimeout
        default: return nil
        }
    }

    /// Cible d'un clic appris, et si sa fenêtre ou son menu vient d'être ouvert (absent juste avant le clic précédent
    /// de la macro, ou au démarrage). Un menu tout juste ouvert passe avant un menu plus ancien de même forme (un
    /// sous-menu et le menu qui l'a ouvert).
    func locate(_ target: ClickTarget, ctx: Context) -> (point: CGPoint, popup: WinInfo?, fresh: Bool)? {
        let baseline = numbersBeforeLastClick ?? ctx.startNumbers
        switch target {
        case .flWindow(let corner, let dx, let dy, let size?):
            guard let w = Self.clickWindow(in: WinSnapshot.take(pid: ctx.pid), size: size, track: ctx.track) else { return nil }
            return (point: Self.point(in: w.bounds, corner: corner, dx: dx, dy: dy), popup: nil, fresh: !baseline.contains(w.number))
        case .openMenu(let hop):
            let snap = WinSnapshot.take(pid: ctx.pid)
            let fitting = snap.fl.filter {
                !ctx.startNumbers.contains($0.number) && $0.isMenuLike && $0.layer > 8 && hop.fits($0.bounds)
            }
            guard let menu = fitting.first(where: { !baseline.contains($0.number) }) ?? fitting.first else { return nil }
            return (point: hop.point(in: menu.bounds), popup: menu, fresh: !baseline.contains(menu.number))
        default:
            return resolve(target, ctx: ctx).map { (point: $0.point, popup: $0.popup, fresh: false) }
        }
    }

    static func point(in f: CGRect, corner: Corner, dx: Double, dy: Double) -> CGPoint {
        let x: CGFloat = corner == .topLeft || corner == .bottomLeft ? f.minX : f.maxX
        let y: CGFloat = corner == .topLeft || corner == .topRight ? f.minY : f.maxY
        return CGPoint(x: x + dx, y: y + dy)
    }

    func click(_ target: ClickTarget, right: Bool, ctx: Context) -> StepResult {
        guard target.isFinite else { return .fail("position introuvable (fenêtre de FL ?)") }
        var found = locate(target, ctx: ctx)
        if let timeout = Self.appearTimeout(of: target), found?.fresh != false || found?.popup != nil {
            // Fenêtre ou menu que le clic précédent ouvre : attendu s'il n'est pas encore là, puis lu deux fois de suite
            // au même endroit (FL a fini de le placer). Seul un menu plus ancien de la forme apprise : un sous-menu
            // tout juste ouvert peut encore passer devant (0,3 s). Échap et la perte du premier plan l'interrompent.
            let t0 = Date()
            var previous: CGPoint?
            while true {
                let elapsed = Date().timeIntervalSince(t0)
                if let f = found {
                    if f.fresh {
                        if f.point == previous { break }
                        previous = f.point
                    } else if elapsed >= 0.3 {
                        break
                    }
                } else {
                    previous = nil
                }
                if elapsed >= timeout { break }
                if let stop = shouldStop(ctx.pid) { return .cancel(stop) }
                Thread.sleep(forTimeInterval: 0.015)
                found = locate(target, ctx: ctx)
            }
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            if ms >= 30 || found == nil {
                MacroLog.shared.write("CLICK", found == nil ? "target still missing after \(ms) ms" : "target ready after \(ms) ms")
            }
            // Fenêtre qui vient de s'ouvrir : un court instant pour qu'elle passe au premier plan de FL.
            if let f = found, f.fresh, f.popup == nil, case .cancel(let why) = pause(80, pid: ctx.pid) { return .cancel(why) }
        }
        guard let r = found else {
            switch target {
            case .flWindow(_, _, _, let size?):
                return .fail("fenêtre de FL de \(Int(size.width)) × \(Int(size.height)) introuvable "
                             + "(pas ouverte, ou changée de taille : montre de nouveau le clic)")
            case .openMenu:
                return .fail("le menu de FL attendu ne s'est pas ouvert")
            default:
                return .fail("position introuvable (fenêtre de FL ?)")
            }
        }
        numbersBeforeLastClick = WinSnapshot.take(pid: ctx.pid).numbers
        if let popup = r.popup { return clickInside(r.point, popup: popup, ctx: ctx) }
        return click(at: r.point, right: right, ctx: ctx)
    }

    // MARK: Événements (tous marqués « FLSH » : le tap ne les retraite jamais)

    func postKey(_ combo: KeyCombo, pid: Int32) {
        func flags(_ f: CGEventFlags) {
            guard let e = CGEvent(source: source) else { return }
            e.type = .flagsChanged
            e.flags = f
            e.setIntegerValueField(.eventSourceUserData, value: EventTap.mark)
            e.postToPid(pid)
        }
        flags(combo.cgFlags)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: combo.keyCode, keyDown: down) else { continue }
            e.flags = combo.cgFlags
            e.setIntegerValueField(.eventSourceUserData, value: EventTap.mark)
            e.postToPid(pid)
        }
        flags([])
    }

    func click(at p: CGPoint, right: Bool, ctx: Context) -> StepResult {
        guard FLWindows.contains(p, pid: ctx.pid) else {
            MacroLog.shared.write("CLICK", "refused (\(Int(p.x)),\(Int(p.y))): outside every FL window")
            return .fail("le point visé est hors de FL")
        }
        if !Self.clicksToPid, let name = coveringApp(at: p, ctx: ctx) {
            return .fail("« \(name) » couvre FL à cet endroit")
        }
        postClick(at: p, right: right, pid: ctx.pid)
        lastClickPoint = p
        return .ok
    }

    /// Nom de l'app dont une fenêtre couvre FL au point visé ; nil : c'est bien FL (ou notre app) dessous.
    func coveringApp(at p: CGPoint, ctx: Context) -> String? {
        let ax = AXProbe.hit(p)
        MacroLog.shared.write("AX", "at (\(Int(p.x)),\(Int(p.y))): \(ax)")
        var owner: Int32? = (ax.error == .success && ax.pid != 0) ? ax.pid : nil
        // AX muet : repli sur la fenêtre NORMALE tout devant seulement si aucun menu de FL (niveau supérieur) n'est là.
        if owner == nil, WinSnapshot.take(pid: ctx.pid).hit(p).map({ $0.layer == 0 }) ?? true {
            owner = FLWindows.topNormalWindow(at: p)?.pid
        }
        guard let owner, owner != ctx.pid, owner != getpid() else { return nil }
        return NSRunningApplication(processIdentifier: owner)?.localizedName ?? "une autre app"
    }

    /// Preset glissé sur la piste (PresetDrop) : mêmes garde-fous qu'un clic (dans FL, rien ne la couvre), toujours
    /// par le flux du système (un glisser ne peut pas être adressé à un seul processus).
    func dropFile(_ path: String, at p: CGPoint, ctx: Context) -> StepResult {
        guard FLWindows.contains(p, pid: ctx.pid) else {
            MacroLog.shared.write("DROP", "refused (\(Int(p.x)),\(Int(p.y))): outside every FL window")
            return .fail("la piste visée est hors de FL : clique d'abord sur ta piste dans le Mixer")
        }
        if let name = coveringApp(at: p, ctx: ctx) { return .fail("« \(name) » couvre FL à cet endroit") }
        if let stop = shouldStop(ctx.pid) { return .cancel(stop) }
        if cursorBeforeBurst == nil { cursorBeforeBurst = FLWindows.cursor() }
        switch PresetDrop.drop(path: path, at: p, source: source) {
        case .done:
            lastClickPoint = p
            return .ok
        case .failed(let why):
            return .fail(why)
        }
    }

    func postClick(at p: CGPoint, right: Bool, pid: Int32, hoverMs: Int = 30) {
        if cursorBeforeBurst == nil { cursorBeforeBurst = FLWindows.cursor() }
        let held = CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        MacroLog.shared.write("CLICK", "\(right ? "right" : "left") (\(Int(p.x)),\(Int(p.y)))"
            + (held.isEmpty ? "" : " WARNING modifiers held 0x\(String(held.rawValue, radix: 16))"))
        func ms(since t: UInt64) -> Int { Int((DispatchTime.now().uptimeNanoseconds &- t) / 1_000_000) }
        let t0 = DispatchTime.now().uptimeNanoseconds
        if Self.warpCursor {
            CGWarpMouseCursorPosition(p)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        let warpMs = ms(since: t0)
        let button: CGMouseButton = right ? .right : .left
        var postMs = 0
        func send(_ type: CGEventType) {
            guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
            e.flags = []
            e.setIntegerValueField(.mouseEventClickState, value: 1)
            e.setIntegerValueField(.eventSourceUserData, value: EventTap.mark)
            let t = DispatchTime.now().uptimeNanoseconds
            if Self.clicksToPid { e.postToPid(pid) } else { e.post(tap: .cghidEventTap) }
            postMs += ms(since: t)
            usleep(1_000)
        }
        send(.mouseMoved)
        Thread.sleep(forTimeInterval: Double(hoverMs) / 1000)
        send(right ? .rightMouseDown : .leftMouseDown)
        Thread.sleep(forTimeInterval: 0.05)
        send(right ? .rightMouseUp : .leftMouseUp)
        MacroLog.shared.write("CLICK", "\(right ? "right" : "left") up · \(ms(since: t0)) ms (warp \(warpMs) ms, posts \(postMs) ms)")
    }
}
