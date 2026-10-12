// Exécution des macros (voir Macro.swift). Sans MIDI, sans script, sans réseau.
// Garde-fous (même esprit que EventTap.post) :
//  - la macro ne démarre que si FL est au premier plan, et s'arrête dès qu'il ne l'est plus ;
//  - tout est envoyé au seul PID de FL (postToPid) ; les clics doivent tomber dans une fenêtre de FL ;
//  - les touches sont revérifiées contre la liste noire (⌘Q, ⌘W…) avant l'envoi ;
//  - Échap interrompt la macro à tout moment ; une seule macro à la fois ;
//  - tout tourne sur une file dédiée : jamais d'attente dans le thread du tap clavier (REL-03) ;
//  - aucune frappe n'est lue ni journalisée : seules des durées / étapes sont retenues pour le diagnostic.
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

extension Notification.Name {
    /// userInfo : "ok" (Bool), "text" (String).
    static let macroFinished = Notification.Name("FLShortcutMacroFinished")
}

enum MacroOutcome: Equatable {
    case done
    case doneWithWarning(String)
    case failed(step: Int, reason: String)
    case cancelled(reason: String)

    var text: String {
        switch self {
        case .done: return "Macro terminée"
        case .doneWithWarning(let why): return "Macro terminée, mais \(why)"
        case .failed(let step, let reason): return "Macro arrêtée à l'étape \(step) : \(reason)"
        case .cancelled(let reason): return "Macro annulée : \(reason)"
        }
    }
}

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

// MARK: - Exécution

final class MacroRunner {
    static let shared = MacroRunner()

    enum StartResult: Equatable {
        case started
        /// Une macro tourne déjà : le raccourci est avalé sans rien faire (jamais envoyé à FL tel quel).
        case busy
        /// FL pas au premier plan, macro invalide : le raccourci passe à FL.
        case refused
    }

    /// Le curseur réel est déplacé pendant les clics (certaines interfaces lisent la position réelle de la souris)
    /// puis remis à sa place. À mettre à `false` pour tester l'envoi pur d'événements.
    static var warpCursor = true

    /// Clics envoyés comme de vrais clics (flux du système) : beaucoup d'apps ignorent la souris envoyée à leur
    /// seul PID. Garde-fou : la fenêtre visible tout devant au point visé doit appartenir à FL.
    /// `defaults write app.flshortcut.FLShortcut macroClicksToPid -bool YES` : envoi au seul PID (essai).
    static var clicksToPid: Bool { UserDefaults.standard.bool(forKey: "macroClicksToPid") }

    /// Résultat de la vérification du larsen, lancée en parallèle au début de la macro.
    private var feedbackReport = Locked<FeedbackRisk.Report?>(nil)
    private var feedbackReady = DispatchSemaphore(value: 0)

    /// Point du dernier clic de la macro (repère `lastClick`). File de la macro uniquement.
    private var lastClickPoint: CGPoint?

    private enum StepResult {
        case ok
        case warn(String)        // étape faite, avec un avertissement affiché à la fin
        case fail(String)
        case cancel(String)
    }

    private struct Context {
        let pid: Int32
        let origin: CGPoint
        let frame: CGRect?
        let baseline: Int
        /// Piste visée par les étapes automatiques : dernier clic dans FL, sinon position du curseur.
        let track: CGPoint
        /// Fenêtres visibles au démarrage de la macro (FL + panneaux hors processus).
        let startNumbers: Set<Int>
    }

    private enum MenuStop: Error {
        case cancel(String)
        case fail(String)
    }

    private func result(_ stop: MenuStop) -> StepResult {
        switch stop {
        case .cancel(let why): return .cancel(why)
        case .fail(let why): return .fail(why)
        }
    }

    /// Boîte de dialogue ouverte par le menu (waitDialog → waitDialogClose). File de la macro uniquement.
    private var dialog: WinInfo?
    /// Point du clic droit qui a ouvert le menu de piste (rangée des noms). File de la macro uniquement.
    private var trackTarget: CGPoint?
    /// Position du pointeur de l'utilisateur avant une série de clics automatiques. File de la macro uniquement.
    private var cursorBeforeBurst: CGPoint?
    /// FL a répondu au hit-test AX sur son menu par un rôle de menu : titres utilisables (niveau 0). File de la macro uniquement.
    private var popupAX = false


    private let queue = DispatchQueue(label: "fr.flshortcut.macro", qos: .userInitiated)
    private let busy = Locked(false)
    private let source: CGEventSource? = {
        let s = CGEventSource(stateID: .privateState)
        s?.localEventsSuppressionInterval = 0             // ne pas geler la souris réelle après nos événements
        return s
    }()

    private init() {}

    /// Essai de bout en bout (`--selftest-macro`, FL simulé) : FL reconnu par son PID et le premier plan de
    /// NSWorkspace (pas de tap clavier dans l'essai), piste visée donnée directement. Jamais utilisé dans l'app.
    static var testFLPID: Int32?
    static var testTrackPoint: CGPoint?

    /// Essai : exécute les étapes sur la file appelante (jamais le thread principal) et rend le résultat.
    func runForTest(_ steps: [MacroStep], pid: Int32) -> MacroOutcome {
        busy.withLock { $0 = true }
        defer { busy.withLock { $0 = false } }
        return execute(steps, pid: pid)
    }

    /// Une macro est en cours (ses propres clics ne doivent pas compter comme « dernière piste cliquée »).
    var isRunning: Bool { busy.value }

    /// Appelé depuis le thread du tap : ne bloque jamais, la macro tourne sur sa propre file.
    func start(_ macro: Macro, flPID pid: Int32) -> StartResult {
        let cfg = EventTap.shared.currentConfig
        guard pid != 0, cfg.flPIDs.contains(pid), cfg.frontmostPID == pid else { return .refused }
        guard case .success(let steps) = MacroLibrary.steps(for: macro, forbidden: cfg.forbidden) else { return .refused }
        let acquired = busy.withLock { b -> Bool in
            if b { return false }
            b = true
            return true
        }
        guard acquired else { return .busy }
        queue.async { [self] in
            let outcome = execute(steps, pid: pid)
            busy.withLock { $0 = false }
            DispatchQueue.main.async {
                var ok = false
                switch outcome {
                case .done: ok = true
                case .doneWithWarning: break                       // la fenêtre du larsen suffit
                default: NSSound.beep()
                }
                NotificationCenter.default.post(name: .macroFinished, object: nil,
                                                userInfo: ["ok": ok, "text": outcome.text])
            }
        }
        return .started
    }

    private func execute(_ steps: [MacroStep], pid: Int32) -> MacroOutcome {
        MacroLog.shared.beginRun(steps.map(\.kind.rawValue).joined(separator: " > "), flPID: pid)
        let outcome = runSteps(steps, pid: pid)
        restoreCursor()
        MacroLog.shared.endRun(outcome.text)
        return outcome
    }

    private func runSteps(_ steps: [MacroStep], pid: Int32) -> MacroOutcome {
        let origin = FLWindows.cursor()
        lastClickPoint = nil
        trackTarget = nil
        cursorBeforeBurst = nil
        dialog = nil
        popupAX = false
        let report = Locked<FeedbackRisk.Report?>(nil)
        let ready = DispatchSemaphore(value: 0)
        feedbackReport = report
        feedbackReady = ready
        if steps.contains(where: { $0.kind == .feedbackCheck }) {
            DispatchQueue.global(qos: .utility).async {
                let r = FeedbackRisk.check(flPID: pid)
                report.withLock { $0 = r }
                ready.signal()
            }
        }
        DispatchQueue.main.sync { HintPanel.shared.hide() }       // synchrone : jamais notre bulle sous un clic
        guard CGPreflightPostEventAccess() else {
            return .failed(step: 1, reason: "autorise FL Shortcut dans Réglages Système › Confidentialité et sécurité › Accessibilité")
        }
        let initial = WinSnapshot.take(pid: pid)
        MacroLog.shared.windows("start", initial)
        func frame(_ p: CGPoint) -> CGRect? { initial.fl.first { $0.layer == 0 && $0.bounds.contains(p) }?.bounds }
        var track = origin
        if let p = Self.testTrackPoint {
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
        if steps.first?.kind == .trackMenu, frame(track) == nil {
            return .failed(step: 1, reason: "clique d'abord sur ta piste dans le Mixer de FL, puis refais le raccourci")
        }
        let ctx = Context(pid: pid, origin: origin, frame: frame(origin),
                          baseline: FLWindows.dialogCount(pid: pid), track: track, startNumbers: initial.numbers)
        // Chaque étape qui clique attend elle-même un clavier au repos ; les autres premières étapes attendent ici.
        if steps.first?.kind != .trackMenu, !waitForKeyboardIdle(timeout: 1.5) {
            return .cancelled(reason: "relâche les touches du raccourci")
        }
        var warning: String?
        var index = 0
        while index < steps.count {
            let step = steps[index]
            let number = index + 1
            defer { index += 1 }
            if let stop = shouldStop(pid) { return .cancelled(reason: stop) }
            MacroLog.shared.write("STEP", "\(number)/\(steps.count) \(step.kind.rawValue) …")
            let began = Date()
            let result: StepResult
            if step.kind == .armTrack {
                let withRec = index + 1 < steps.count && steps[index + 1].kind == .recordOn
                let recKey = withRec ? steps[index + 1].combo : nil
                if withRec { index += 1 }
                result = armAndRecord(arm: true, record: withRec, recKey: recKey, ctx: ctx)
            } else {
                result = perform(step, ctx: ctx)
            }
            MacroLog.shared.write("STEP", "\(number) \(step.kind.rawValue) → \(describe(result)) in \(Int(Date().timeIntervalSince(began) * 1000)) ms")
            switch result {
            case .ok: continue
            case .warn(let why): warning = warning.map { "\($0) ; \(why)" } ?? why
            case .fail(let why): return .failed(step: number, reason: why)
            case .cancel(let why): return .cancelled(reason: why)
            }
        }
        return warning.map(MacroOutcome.doneWithWarning) ?? .done
    }

    private func describe(_ r: StepResult) -> String {
        switch r {
        case .ok: return "ok"
        case .warn(let why): return "warn: \(why)"
        case .fail(let why): return "FAIL: \(why)"
        case .cancel(let why): return "cancel: \(why)"
        }
    }

    // MARK: Garde-fous

    /// Raison d'arrêter maintenant, sinon nil.
    private func shouldStop(_ pid: Int32) -> String? {
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
    private func pause(_ ms: Int, pid: Int32) -> StepResult {
        var left = Double(ms) / 1000
        while left > 0 {
            if let stop = shouldStop(pid) { return .cancel(stop) }
            let slice = min(left, 0.05)
            Thread.sleep(forTimeInterval: slice)
            left -= slice
        }
        return .ok
    }

    // MARK: Étapes

    private func perform(_ step: MacroStep, ctx: Context) -> StepResult {
        switch step.kind {
        case .delay:
            return pause(step.ms, pid: ctx.pid)

        case .key:
            guard let combo = step.combo else { return .fail("touche manquante") }
            MacroLog.shared.write("KEY", "touche envoyée (masquée)")
            guard !EventTap.shared.currentConfig.forbidden.isForbidden(combo) else { return .fail("touche interdite") }
            postKey(combo, pid: ctx.pid)
            return .ok

        case .click:
            guard let spot = step.spot else { return .fail("position manquante") }
            return click(spot, right: step.button == .right, ctx: ctx)

        case .menu:
            let found = AXMenus.pressPath(pid: ctx.pid, titles: step.titles, perItemTimeout: 0.9) {
                shouldStop(ctx.pid) != nil
            }
            if found { return .ok }
            if let stop = shouldStop(ctx.pid) { return .cancel(stop) }
            guard !step.fallback.isEmpty else {
                return .fail("menu introuvable : apprends les positions du menu dans la fiche du raccourci")
            }
            for spot in step.fallback {
                let result = click(spot, right: false, ctx: ctx)
                guard case .ok = result else { return result }
                if case .cancel(let why) = pause(250, pid: ctx.pid) { return .cancel(why) }
            }
            return .ok

        case .waitDialog:
            return waitDialogOpen(timeoutMs: step.ms, ctx: ctx)

        case .waitDialogClose:
            return waitDialogClosed(timeoutMs: step.ms, ctx: ctx)

        case .trackMenu:
            return trackMenu(step.titles, ctx: ctx)

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

        case .selectInput:
            return selectInput(ctx: ctx)

        case .armTrack:
            return armAndRecord(arm: true, record: false, recKey: nil, ctx: ctx)

        case .recordOn:
            return armAndRecord(arm: false, record: true, recKey: step.combo, ctx: ctx)

        case .chooseFile:
            guard let path = step.path else { return .fail("chemin manquant") }
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
        }
    }

    // MARK: Étapes automatiques (sans lecture de l'écran)

    /// Actions du script FL (PROTOCOL.md §6) qui n'éteignent jamais ce qui est déjà allumé.
    static let armOnAction = 39
    static let recOnAction = 40

    // MARK: Clavier

    /// Aucun modificateur et (sans insister) aucune touche enfoncés, R du raccourci compris : FL 2026 lit l'état réel
    /// des modificateurs, les clics envoyés en HID reprennent les modificateurs enfoncés, et un menu de FL ouvert réagit
    /// aux touches (relâcher ⌃ peut le fermer). Renvoie false seulement si des modificateurs restent enfoncés.
    private func waitForKeyboardIdle(timeout: TimeInterval) -> Bool {
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

    private static func anyKeyDown() -> Bool {
        for code in CGKeyCode(0)..<CGKeyCode(128) where code != 57 && code != 63 {      // verrouillage majuscules, fn
            if CGEventSource.keyState(.combinedSessionState, key: code) { return true }
        }
        return false
    }

    // MARK: Curseur

    private func restoreCursor() {
        guard let p = cursorBeforeBurst else { return }
        cursorBeforeBurst = nil
        guard Self.warpCursor else { return }
        CGWarpMouseCursorPosition(p)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // MARK: Menu de piste (ancré à la fenêtre du menu)

    /// Clic droit sur la piste, puis File › Open mixer track state AU CLAVIER : les éléments des menus de FL ont une
    /// lettre soulignée (« F » de File, « O » de Open…), comme sous Windows. Aucun clic dans le menu, aucune position
    /// à apprendre : FL peut placer son menu où il veut. Chaque touche n'est envoyée que si un menu de FL est ouvert
    /// (sinon une lettre irait à FL : clavier-piano…).
    private func trackMenu(_ titles: [String], ctx: Context) -> StepResult {
        let letters: [Character] = titles.compactMap { title in
            guard let c = title.split(separator: "|").first?.first else { return nil }
            return Character(c.lowercased())
        }
        guard letters.count >= 2, letters.allSatisfy({ Self.letterKeyCodes[$0] != nil }) else { return .fail("menu de piste mal décrit") }
        guard waitForKeyboardIdle(timeout: 1.5) else { return .cancel("relâche les touches du raccourci") }
        let before = WinSnapshot.take(pid: ctx.pid)
        MacroLog.shared.windows("before right-click", before)
        // Clic droit là où tu as cliqué la piste (comme dans la version validée).
        let r = click(at: ctx.track, right: true, ctx: ctx)
        guard case .ok = r else { return r }
        trackTarget = ctx.track

        // 1. Le menu de la piste s'ouvre (nouvelle fenêtre de FL).
        var opened: Set<Int> = []
        func succeeded() -> StepResult { .ok }
        switch WindowWait.newWindow(pid: ctx.pid, excluding: before.numbers, timeout: 1.5,
                                    accept: { $0.isMenuLike }, stop: { self.shouldStop(ctx.pid) }) {
        case .success(let menu):
            opened.insert(menu.number)
            MacroLog.shared.write("MENU", "track menu \(menu)")
            // FL place souvent son menu sous le curseur : son survol ouvrirait un sous-menu tout seul.
            hoverOutside(menu.bounds, pid: ctx.pid)
        case .failure(.stopped(let why)):
            closePopups(base: before.numbers, ctx: ctx)
            return .cancel(why)
        case .failure(.timeout):
            MacroLog.shared.windows("no menu after the right-click", WinSnapshot.take(pid: ctx.pid))
            return .fail("le menu de la piste ne s'est pas ouvert (clique sur le nom de ta piste dans le Mixer)")
        }

        // 2. Lettres des sous-menus (File) : le sous-menu doit apparaître ; sinon flèche droite.
        for letter in letters.dropLast() {
            guard menusOpen(opened, ctx: ctx) else {
                MacroLog.shared.windows("menu closed before « \(letter) »", WinSnapshot.take(pid: ctx.pid))
                return .fail("le menu de FL s'est fermé tout seul")
            }
            let known = WinSnapshot.take(pid: ctx.pid).numbers
            postLetter(letter, pid: ctx.pid)
            var sub = WindowWait.newWindow(pid: ctx.pid, excluding: known, timeout: 0.6,
                                           accept: { $0.isMenuLike }, stop: { self.shouldStop(ctx.pid) })
            if case .failure(.timeout) = sub {
                MacroLog.shared.write("KEY", "« \(letter) » : no submenu → right arrow")
                postKey(KeyCombo(keyCode: 124), pid: ctx.pid)
                sub = WindowWait.newWindow(pid: ctx.pid, excluding: known, timeout: 0.6,
                                           accept: { $0.isMenuLike }, stop: { self.shouldStop(ctx.pid) })
            }
            switch sub {
            case .success(let w):
                opened.insert(w.number)
                MacroLog.shared.write("MENU", "« \(letter) » → submenu \(w)")
            case .failure(.stopped(let why)):
                closePopups(base: before.numbers, ctx: ctx)
                return .cancel(why)
            case .failure(.timeout):
                MacroLog.shared.windows("« \(letter) » : still no submenu", WinSnapshot.take(pid: ctx.pid),
                                        mark: WinSnapshot.take(pid: ctx.pid).numbers.subtracting(before.numbers))
                closePopups(base: before.numbers, ctx: ctx)
                return .fail("le sous-menu « \(titles[0].split(separator: "|").first ?? "File") » ne s'est pas ouvert")
            }
        }

        // 3. Dernière lettre (Open mixer track state) : tous les menus se ferment ; sinon Entrée (lettre partagée
        //    par plusieurs éléments : FL la surligne seulement).
        guard let last = letters.last else { return .fail("menu de piste mal décrit") }
        guard menusOpen(opened, ctx: ctx) else { return .fail("le menu de FL s'est fermé trop tôt") }
        postLetter(last, pid: ctx.pid)
        // La lettre ouvre l'élément, ou seulement le surligne (plusieurs éléments la partagent) : il faut alors Entrée.
        // Appris au premier passage, puis Entrée part aussitôt (sinon 0,6 s d'attente à chaque fois).
        let needsEnter = UserDefaults.standard.object(forKey: Self.enterAfterLetterKey) as? Bool
        if needsEnter != true {
            switch WindowWait.gone(pid: ctx.pid, numbers: opened, timeout: needsEnter == false ? 0.8 : 0.5,
                                   stop: { self.shouldStop(ctx.pid) }) {
            case .success:
                MacroLog.shared.write("MENU", "« \(last) » → menus closed")
                UserDefaults.standard.set(false, forKey: Self.enterAfterLetterKey)
                return succeeded()
            case .failure(.stopped(let why)):
                return .cancel(why)
            case .failure(.timeout):
                MacroLog.shared.write("KEY", "« \(last) » : menus still open → Enter")
            }
        } else {
            // Courte attente quand même : si la lettre a suffi cette fois, Entrée ne doit pas tomber dans la boîte.
            _ = WindowWait.gone(pid: ctx.pid, numbers: opened, timeout: 0.12, stop: { self.shouldStop(ctx.pid) })
            guard menusOpen(opened, ctx: ctx) else {
                // Cette fois la lettre a suffi (menu changé ?) : plus d'Entrée automatique.
                UserDefaults.standard.set(false, forKey: Self.enterAfterLetterKey)
                MacroLog.shared.write("MENU", "« \(last) » → menus closed (Enter not needed any more)")
                return succeeded()
            }
        }
        postKey(KeyCombo(keyCode: 36), pid: ctx.pid)
        switch WindowWait.gone(pid: ctx.pid, numbers: opened, timeout: 0.8, stop: { self.shouldStop(ctx.pid) }) {
        case .success:
            MacroLog.shared.write("MENU", "Enter → menus closed")
            UserDefaults.standard.set(true, forKey: Self.enterAfterLetterKey)
            return succeeded()
        case .failure(.stopped(let why)):
            return .cancel(why)
        case .failure(.timeout):
            closePopups(base: before.numbers, ctx: ctx)
            UserDefaults.standard.removeObject(forKey: Self.enterAfterLetterKey)
            return .fail("« Open mixer track state » n'a pas répondu")
        }
    }

    /// Entrée nécessaire après la dernière lettre du menu de piste (appris au premier passage).
    static let enterAfterLetterKey = "macroMenuEnterAfterLetter"

    /// Ancienne mémoire de la rangée du Mixer (retirée) : effacée avec le reste.
    static let trackMenuMemoKey = "macroTrackMenuMemo"

    static func forgetTrackMenuMemo(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: trackMenuMemoKey)
        defaults.removeObject(forKey: enterAfterLetterKey)
    }

    /// Pointeur juste à côté du menu (à gauche, sinon à droite) : plus aucun élément survolé.
    private func hoverOutside(_ menu: CGRect, pid: Int32) {
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
    private func menusOpen(_ numbers: Set<Int>, ctx: Context) -> Bool {
        !WinSnapshot.take(pid: ctx.pid).numbers.isDisjoint(with: numbers)
    }

    /// Codes de touche (position ANSI) des lettres. F et O sont au même endroit en AZERTY ; le caractère est aussi
    /// joint à l'événement.
    private static let letterKeyCodes: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
        "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    ]

    /// Lettre sans modificateur (raccourci d'un élément de menu), envoyée au seul processus de FL.
    private func postLetter(_ letter: Character, pid: Int32) {
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

    /// Lien MIDI d'abord : FL confirme, et rien de déjà allumé n'est éteint. Sans lien, au clavier :
    /// - armement : menu de la piste › « Arm selected track(s) » (n'éteint jamais, Disarm est un autre élément) ;
    /// - REC : la touche REC de FL (R), qui inverse l'état sans le lire.
    private func armAndRecord(arm: Bool, record: Bool, recKey: KeyCombo?, ctx: Context) -> StepResult {
        var ids: [Int] = []
        if arm { ids.append(Self.armOnAction) }
        if record { ids.append(Self.recOnAction) }
        guard let why = MIDILink.shared.runBriefly(ids) else {
            MacroLog.shared.write("MIDI", "\(arm ? "arm" : "")\(arm && record ? " + " : "")\(record ? "REC" : "") acknowledged")
            return .ok
        }
        MacroLog.shared.write("MIDI", "unavailable (\(why)) → keyboard")
        var warnings: [String] = []
        if arm {
            let r = armViaKeyboard(ctx: ctx)
            switch r {
            case .cancel: return r
            case .fail(let w), .warn(let w): warnings.append("armement non fait : \(w)")
            case .ok: break
            }
        }
        if record {
            if let stop = shouldStop(ctx.pid) { return .cancel(stop) }
            let key = recKey ?? KeyCombo(keyCode: 15)
            if EventTap.shared.currentConfig.forbidden.isForbidden(key) {
                warnings.append("REC non lancé (touche interdite)")
            } else {
                Thread.sleep(forTimeInterval: 0.03)
                postKey(key, pid: ctx.pid)
                MacroLog.shared.write("KEY", "REC key")
            }
        }
        return warnings.isEmpty ? .ok : .warn(warnings.joined(separator: " ; "))
    }

    /// Éléments entre « Select » et « Arm selected track(s) » dans le menu de piste de FL 2026 : Reset selected
    /// track(s) routing, Unroute tracks…, Solo selected track(s), Alt solo selected track(s), Arm selected track(s).
    static let armDownCount = 5

    /// Menu de la piste au clavier : « S » (Select, lettre soulignée) ouvre son sous-menu, ← le referme en laissant
    /// « Select » surligné, puis ↓ ×5 et Entrée. Chaque touche n'est envoyée que si le menu de piste est encore ouvert.
    private func armViaKeyboard(ctx: Context) -> StepResult {
        guard waitForKeyboardIdle(timeout: 1.0) else { return .cancel("relâche les touches du raccourci") }
        let before = WinSnapshot.take(pid: ctx.pid)
        let r = click(at: trackTarget ?? ctx.track, right: true, ctx: ctx)
        guard case .ok = r else { return r }
        let menu: WinInfo
        switch WindowWait.newWindow(pid: ctx.pid, excluding: before.numbers, timeout: 1.5,
                                    accept: { $0.isMenuLike }, stop: { self.shouldStop(ctx.pid) }) {
        case .success(let w): menu = w
        case .failure(.stopped(let why)):
            closePopups(base: before.numbers, ctx: ctx)
            return .cancel(why)
        case .failure(.timeout):
            return .fail("le menu de la piste ne s'est pas ouvert")
        }
        MacroLog.shared.write("ARM", "track menu \(menu)")
        hoverOutside(menu.bounds, pid: ctx.pid)

        let known = WinSnapshot.take(pid: ctx.pid).numbers
        postLetter("s", pid: ctx.pid)
        guard case .success(let sub) = WindowWait.newWindow(pid: ctx.pid, excluding: known, timeout: 0.45,
                                                            accept: { $0.isMenuLike }, stop: { self.shouldStop(ctx.pid) }) else {
            closePopups(base: before.numbers, ctx: ctx)
            return .fail("sous-menu « Select » non ouvert")
        }
        MacroLog.shared.write("ARM", "« s » → submenu \(sub)")
        postKey(KeyCombo(keyCode: 123), pid: ctx.pid)                       // ←
        guard case .success = WindowWait.gone(pid: ctx.pid, numbers: [sub.number], timeout: 0.4, stop: { self.shouldStop(ctx.pid) }),
              menusOpen([menu.number], ctx: ctx) else {
            closePopups(base: before.numbers, ctx: ctx)
            return .fail("le menu de FL n'a pas suivi les flèches")
        }
        for _ in 0..<Self.armDownCount {
            postKey(KeyCombo(keyCode: 125), pid: ctx.pid)                   // ↓
            Thread.sleep(forTimeInterval: 0.015)
        }
        guard menusOpen([menu.number], ctx: ctx) else { return .fail("le menu de FL s'est fermé") }
        postKey(KeyCombo(keyCode: 36), pid: ctx.pid)                        // Entrée
        switch WindowWait.gone(pid: ctx.pid, numbers: [menu.number], timeout: 0.8, stop: { self.shouldStop(ctx.pid) }) {
        case .success:
            MacroLog.shared.write("ARM", "Enter → menu closed")
            restoreCursor()
            return .ok
        case .failure(.stopped(let why)):
            return .cancel(why)
        case .failure(.timeout):
            closePopups(base: before.numbers, ctx: ctx)
            return .fail("« Arm selected track(s) » n'a pas répondu")
        }
    }

    /// Un menu de la taille apprise apparaît (FL peut le décaler n'importe où : seul son coin haut-gauche compte).
    /// Tout ce qui s'est ouvert d'autre est fermé (Échap, vérifié) et l'étape échoue : jamais de clic à l'aveugle.
    private func awaitPopup(fitting hop: MacroSpots.PopupHop, excluding base: Set<Int>, timeout: TimeInterval,
                            ctx: Context) -> Result<WinInfo, MenuStop> {
        let began = Date()
        switch WindowWait.newWindow(pid: ctx.pid, excluding: base, timeout: timeout,
                                    accept: { $0.isMenuLike && hop.fits($0.bounds) },
                                    stop: { self.shouldStop(ctx.pid) }) {
        case .success(let w):
            // Pas de question à l'Accessibilité ici : FL, dans sa boucle de menu, peut tarder à répondre.
            popupAX = false
            MacroLog.shared.write("MENU", "popup \(w) after \(Int(Date().timeIntervalSince(began) * 1000)) ms "
                + "(learned \(Int(hop.size.width))x\(Int(hop.size.height)))")
            return .success(w)
        case .failure(.stopped(let why)):
            closePopups(base: base, ctx: ctx)
            return .failure(.cancel(why))
        case .failure(.timeout):
            let snap = WinSnapshot.take(pid: ctx.pid)
            MacroLog.shared.windows("no popup of the learned size after \(Int(timeout * 1000)) ms", snap,
                                    mark: snap.numbers.subtracting(base))
            let other = snap.fl.first { !base.contains($0.number) && $0.isMenuLike }
            closePopups(base: base, ctx: ctx)
            if let other {
                return .failure(.fail("FL a ouvert un autre menu (\(Int(other.bounds.width))x\(Int(other.bounds.height))) : "
                                      + "clique sur le nom de ta piste dans le Mixer, ou réapprends les clics"))
            }
            return .failure(.fail("le menu de FL ne s'est pas ouvert"))
        }
    }

    /// Clique chaque saut dans son propre menu ; entre deux sauts, attend le menu suivant (sous-menu) ; après le dernier,
    /// attend que tous les menus se ferment (preuve que l'élément a été pris).
    private func runHops(_ hops: [MacroSpots.PopupHop], titles: [[String]], firstPopup: WinInfo,
                         base: Set<Int>, ctx: Context) -> StepResult {
        var popup = firstPopup
        var opened: Set<Int> = [firstPopup.number]
        for (i, hop) in hops.enumerated() {
            let byTitle = popupAX && i < titles.count ? AXProbe.itemCenter(in: popup, titles: titles[i]) : nil
            let p = byTitle ?? hop.point(in: popup.bounds)
            MacroLog.shared.write("HOP", "\(i + 1)/\(hops.count) in \(popup) → (\(Int(p.x)),\(Int(p.y))) "
                + (byTitle != nil ? "by AX title" : "by learned offset (\(Int(hop.offset.dx)),\(Int(hop.offset.dy)))"))
            let known = WinSnapshot.take(pid: ctx.pid).numbers
            let r = clickInside(p, popup: popup, ctx: ctx)
            guard case .ok = r else {
                closePopups(base: base, ctx: ctx)
                return r
            }
            if i + 1 < hops.count {
                switch awaitPopup(fitting: hops[i + 1], excluding: known.union(opened), timeout: 1.2, ctx: ctx) {
                case .success(let next):
                    popup = next
                    opened.insert(next.number)
                case .failure(let stop):
                    closePopups(base: base, ctx: ctx)
                    return result(stop)
                }
            } else {
                switch WindowWait.gone(pid: ctx.pid, numbers: opened, timeout: 1.0, stop: { self.shouldStop(ctx.pid) }) {
                case .success:
                    MacroLog.shared.write("MENU", "all popups closed after the last click")
                case .failure(.stopped(let why)):
                    return .cancel(why)
                case .failure(.timeout):
                    closePopups(base: base, ctx: ctx)
                    return .fail("le menu de FL est resté ouvert après le clic (élément manqué : réapprends les clics)")
                }
            }
        }
        restoreCursor()
        return .ok
    }

    /// Clic gauche en `p` seulement si `p` est dans `popup`, que le menu est toujours là au même endroit, qu'il est
    /// la fenêtre de FL tout devant en `p` et qu'aucune autre appli ne le couvre (hit-test Accessibilité).
    private func clickInside(_ p: CGPoint, popup: WinInfo, ctx: Context) -> StepResult {
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
    private func closePopups(base: Set<Int>, ctx: Context) {
        for attempt in 1...3 {
            let open = WinSnapshot.take(pid: ctx.pid).fl.filter { !base.contains($0.number) && $0.isMenuLike }
            guard let top = open.first else { return }
            MacroLog.shared.write("ESC", "attempt \(attempt): \(open.map(\.description).joined(separator: ", "))")
            postKey(KeyCombo(keyCode: 53), pid: ctx.pid)
            _ = WindowWait.gone(pid: ctx.pid, numbers: [top.number], timeout: 0.3, stop: { nil })
        }
    }

    /// Ancien format, décalages enchaînés (menus dans la fenêtre de FL seulement). Invérifiable : gardé pour le rejeu exact.
    private func replayChain(_ offsets: [CGVector], from anchor: CGPoint, ctx: Context) -> StepResult {
        for p in MacroSpots.Learned(anchorSize: .zero, offsets: offsets).points(from: anchor) {
            if case .cancel(let why) = pause(220, pid: ctx.pid) { return .cancel(why) }
            let r = click(at: p, right: false, ctx: ctx)
            guard case .ok = r else { return r }
        }
        if case .cancel(let why) = pause(150, pid: ctx.pid) { return .cancel(why) }
        restoreCursor()
        return .ok
    }

    // MARK: Apprentissage (retient la fenêtre où est tombé chaque clic de l'utilisateur)

    /// La bulle s'affiche AVANT le clic droit (aucune fenêtre ne passe devant quand le menu de FL est ouvert), sur
    /// l'autre moitié de l'écran. Les fenêtres de FL sont relevées toutes les 15 ms ; chaque clic de l'utilisateur est
    /// attribué à la fenêtre tout devant sous lui dans le dernier relevé pris avant l'instant du clic.
    private func learnPath(_ kind: MacroSpots.PathKind, clicks n: Int, hint: String, hintAt: CGPoint,
                           rightClick: Bool, ctx: Context) -> StepResult {
        guard waitForKeyboardIdle(timeout: 1.5) else { return .cancel("relâche les touches du raccourci") }
        DispatchQueue.main.sync {
            ClickRecorder.shared.start()
            HintPanel.shared.show(hint, near: hintAt)
        }
        defer { DispatchQueue.main.async { ClickRecorder.shared.stop(); HintPanel.shared.hide() } }
        let before = WinSnapshot.take(pid: ctx.pid)
        MacroLog.shared.windows("learn \(kind.rawValue): before", before)
        var row: MacroSpots.TrackRow?
        if rightClick {
            if let w = before.fl.first(where: { $0.layer == 0 && $0.bounds.contains(ctx.track) }) {
                row = MacroSpots.TrackRow(yFromWindowTop: ctx.track.y - w.bounds.minY, windowSize: w.bounds.size)
            }
            let r = click(at: ctx.track, right: true, ctx: ctx)
            guard case .ok = r else { return r }
            restoreCursor()                                          // l'utilisateur prend la main ici
        }
        var history: [WinSnapshot] = []
        var samples: [ClickSample] = []
        let deadline = Date().addingTimeInterval(60)
        while samples.count < n {
            if let stop = shouldStop(ctx.pid) { return .cancel(stop) }
            guard Date() < deadline else { return .fail("clics non montrés (60 s)") }
            let snap = WinSnapshot.take(pid: ctx.pid)
            if let last = history.last, last.numbers != snap.numbers {
                MacroLog.shared.windows("learn: windows changed", snap, mark: snap.numbers.subtracting(before.numbers))
            }
            history.append(snap)
            if history.count > 200 { history.removeFirst(history.count - 200) }
            samples = ClickRecorder.shared.capturedSamples
            Thread.sleep(forTimeInterval: 0.015)
        }
        let used = Array(samples.prefix(n))
        var path = MacroSpots.resolve(used, history: history, base: before.numbers,
                                      anchor: ctx.track, firstInWindow: !rightClick)
        path.row = row
        for (i, s) in used.enumerated() {
            let hitWindow = (history.last(where: { $0.time <= s.time }) ?? history.first)?.hit(s.point)
            MacroLog.shared.write("LEARN", "click \(i + 1) at (\(Int(s.point.x)),\(Int(s.point.y))) in \(hitWindow?.description ?? "no FL window")")
        }
        MacroLog.shared.write("LEARN", "\(kind.rawValue) = \(MacroSpots.describe(path))")
        guard path.isValid else { return .fail("clics non reconnus : refais le raccourci pour recommencer") }
        MacroSpots.savePath(path, kind)
        return .ok
    }

    private static func displayBounds(containing p: CGPoint) -> CGRect {
        var ids = [CGDirectDisplayID](repeating: 0, count: 4)
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(p, 4, &ids, &count) == .success, count > 0 else { return CGDisplayBounds(CGMainDisplayID()) }
        return CGDisplayBounds(ids[0])
    }

    /// Haut de l'écran, sur la moitié qui ne contient pas `p` (le menu de FL s'ouvre près de `p`).
    private static func hintPoint(awayFrom p: CGPoint) -> CGPoint {
        let d = displayBounds(containing: p)
        return CGPoint(x: p.x > d.midX ? d.minX + d.width * 0.25 : d.minX + d.width * 0.75, y: d.minY + 60)
    }

    // MARK: Entrée « (none) » → 1

    private func selectInput(ctx: Context) -> StepResult {
        let snap = WinSnapshot.take(pid: ctx.pid)
        if let path = MacroSpots.loadPath(.input), let start = path.start,
           let window = Self.inputWindow(in: snap, size: start.windowSize, track: ctx.track) {
            guard waitForKeyboardIdle(timeout: 1.5) else { return .cancel("relâche les touches du raccourci") }
            let p0 = CGPoint(x: window.bounds.maxX + start.fromTopRight.dx, y: window.bounds.minY + start.fromTopRight.dy)
            MacroLog.shared.write("INPUT", "selector (\(Int(p0.x)),\(Int(p0.y))) in \(window)")
            let r = click(at: p0, right: false, ctx: ctx)
            guard case .ok = r else { return r }
            if let first = path.hops.first {
                switch awaitPopup(fitting: first, excluding: snap.numbers, timeout: 1.2, ctx: ctx) {
                case .success(let list): return runHops(path.hops, titles: [], firstPopup: list, base: snap.numbers, ctx: ctx)
                case .failure(let stop): return result(stop)
                }
            }
            if let inline = path.inline { return replayChain(inline.offsets, from: p0, ctx: ctx) }
            return .fail("entrée à réapprendre (fiche du raccourci)")
        }
        // Pas appris, ou la fenêtre de FL a changé de taille : l'utilisateur le montre (une fois).
        guard let main = snap.fl.filter({ $0.layer == 0 })
                .max(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) else {
            return .fail("fenêtre de FL introuvable")
        }
        return learnPath(.input, clicks: 2, hint: "Une seule fois : clique sur « (none) » de la piste, puis sur l'entrée « 1 ».",
                         hintAt: CGPoint(x: main.bounds.maxX - 160, y: main.bounds.minY + 90), rightClick: false, ctx: ctx)
    }

    /// Fenêtre de FL de la taille apprise : d'abord celle qui contient la piste (Mixer détaché), sinon n'importe laquelle.
    private static func inputWindow(in snap: WinSnapshot, size: CGSize, track: CGPoint) -> WinInfo? {
        let fits = snap.fl.filter { $0.layer == 0 && MacroSpots.sameSize($0.bounds.size, size) }
        return fits.first { $0.bounds.contains(track) } ?? fits.first
    }

    // MARK: Boîte de dialogue (suivie par son numéro de fenêtre, pas par un nombre de fenêtres)

    private func waitDialogOpen(timeoutMs: Int, ctx: Context) -> StepResult {
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

    private func waitDialogClosed(timeoutMs: Int, ctx: Context) -> StepResult {
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

    private func wait(timeoutMs: Int, pid: Int32, failure: String, until condition: () -> Bool) -> StepResult {
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

    private func resolve(_ spot: ClickSpot, ctx: Context) -> CGPoint? {
        switch spot.anchor {
        case .cursor:
            return CGPoint(x: ctx.origin.x + spot.dx, y: ctx.origin.y + spot.dy)
        case .window:
            guard let f = ctx.frame else { return nil }
            return CGPoint(x: f.minX + spot.dx, y: f.minY + spot.dy)
        case .cursorXWindowY:
            guard let f = ctx.frame else { return nil }
            return CGPoint(x: ctx.origin.x + spot.dx, y: f.minY + spot.dy)
        case .lastClick:
            guard let last = lastClickPoint else { return nil }
            return CGPoint(x: last.x + spot.dx, y: last.y + spot.dy)
        }
    }

    private func click(_ spot: ClickSpot, right: Bool, ctx: Context) -> StepResult {
        guard spot.isFinite, let p = resolve(spot, ctx: ctx) else { return .fail("position introuvable (fenêtre de FL ?)") }
        return click(at: p, right: right, ctx: ctx)
    }

    // MARK: Événements (tous marqués « FLSH » : le tap ne les retraite jamais)

    private func postKey(_ combo: KeyCombo, pid: Int32) {
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

    private func click(at p: CGPoint, right: Bool, ctx: Context) -> StepResult {
        guard FLWindows.contains(p, pid: ctx.pid) else {
            MacroLog.shared.write("CLICK", "refused (\(Int(p.x)),\(Int(p.y))): outside every FL window")
            return .fail("le point visé est hors de FL")
        }
        if !Self.clicksToPid {
            let ax = AXProbe.hit(p)
            MacroLog.shared.write("AX", "at (\(Int(p.x)),\(Int(p.y))): \(ax)")
            var owner: Int32? = (ax.error == .success && ax.pid != 0) ? ax.pid : nil
            // AX muet : repli sur la fenêtre NORMALE tout devant seulement si aucun menu de FL (niveau supérieur) n'est là.
            if owner == nil, WinSnapshot.take(pid: ctx.pid).hit(p).map({ $0.layer == 0 }) ?? true {
                owner = FLWindows.topNormalWindow(at: p)?.pid
            }
            if let owner, owner != ctx.pid, owner != getpid() {
                let name = NSRunningApplication(processIdentifier: owner)?.localizedName ?? "une autre app"
                return .fail("« \(name) » couvre FL à cet endroit")
            }
        }
        postClick(at: p, right: right, pid: ctx.pid)
        lastClickPoint = p
        return .ok
    }

    private func postClick(at p: CGPoint, right: Bool, pid: Int32, hoverMs: Int = 30) {
        if cursorBeforeBurst == nil { cursorBeforeBurst = FLWindows.cursor() }
        let held = CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        MacroLog.shared.write("CLICK", "\(right ? "right" : "left") (\(Int(p.x)),\(Int(p.y)))"
            + (held.isEmpty ? "" : " WARNING modifiers held 0x\(String(held.rawValue, radix: 16))"))
        if Self.warpCursor {
            CGWarpMouseCursorPosition(p)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        let button: CGMouseButton = right ? .right : .left
        func send(_ type: CGEventType) {
            guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
            e.flags = []
            e.setIntegerValueField(.mouseEventClickState, value: 1)
            e.setIntegerValueField(.eventSourceUserData, value: EventTap.mark)
            if Self.clicksToPid { e.postToPid(pid) } else { e.post(tap: .cghidEventTap) }
            usleep(1_000)
        }
        send(.mouseMoved)
        Thread.sleep(forTimeInterval: Double(hoverMs) / 1000)
        send(right ? .rightMouseDown : .leftMouseDown)
        Thread.sleep(forTimeInterval: 0.05)
        send(right ? .rightMouseUp : .leftMouseUp)
        MacroLog.shared.write("CLICK", "\(right ? "right" : "left") up")
    }
}

// MARK: - Apprentissage des positions (fiche du raccourci)

/// Enregistre les clics que l'utilisateur fait dans FL pour retrouver les positions des boutons.
/// Un moniteur global de souris ne demande pas de permission supplémentaire ; il ne lit que la position du clic.
/// Thread principal uniquement.
final class MacroLearner: ObservableObject {
    static let shared = MacroLearner()

    enum Phase {
        /// clic droit sur la piste, puis File, puis Open mixer track state.
        case menu
        /// clic sur la piste, puis bouton d'armement, sélecteur d'entrée, première entrée.
        case armInput
    }

    @Published private(set) var instruction: String?
    @Published private(set) var message: String?

    private var monitor: Any?
    private var phase: Phase = .menu
    private var pid: Int32 = 0
    private var reference: CGPoint?
    private var referenceFrame: CGRect?
    private var captured: [String: ClickSpot] = [:]
    private var lastPoint: CGPoint?
    private var completion: (([String: ClickSpot]) -> Void)?

    var isActive: Bool { instruction != nil }

    private init() {}

    func begin(_ phase: Phase, completion: @escaping ([String: ClickSpot]) -> Void) {
        cancel()
        guard let flPID = EventTap.shared.currentConfig.flPIDs.first else {
            message = "Ouvre FL Studio, puis recommence."
            return
        }
        pid = flPID
        self.phase = phase
        self.completion = completion
        reference = nil
        referenceFrame = nil
        captured = [:]
        lastPoint = nil
        message = nil
        instruction = prompt()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handle(isRight: event.type == .rightMouseDown)
        }
    }

    func cancel() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        instruction = nil
        completion = nil
    }

    private var order: [String] {
        switch phase {
        case .menu: return [Macro.Spot.menuFile, Macro.Spot.menuOpenState]
        case .armInput: return [Macro.Spot.arm, Macro.Spot.inputMenu, Macro.Spot.firstInput]
        }
    }

    private func prompt() -> String {
        switch phase {
        case .menu:
            if reference == nil { return "Dans FL : clic droit sur une piste du Mixer." }
            return captured.isEmpty ? "Clique sur « File »." : "Clique sur « Open mixer track state… » (Échap pour fermer la boîte)."
        case .armInput:
            if reference == nil { return "Dans FL : clique sur ta piste du Mixer (la souris sera là quand tu utiliseras le raccourci)." }
            switch captured.count {
            case 0: return "Clique sur le bouton d'armement de la piste (enregistrement)."
            case 1: return "Clique sur le sélecteur d'entrée audio (panneau de droite du Mixer)."
            default: return "Clique sur la première entrée de la liste qui s'est ouverte."
            }
        }
    }

    private func handle(isRight: Bool) {
        guard isActive else { return }
        let p = FLWindows.cursor()
        guard FLWindows.contains(p, pid: pid) else {
            message = "Clique dans la fenêtre de FL."
            return
        }
        message = nil
        if reference == nil {
            switch phase {
            case .menu: guard isRight else { message = "Commence par un clic droit."; return }
            case .armInput: guard !isRight else { message = "Fais un clic gauche."; return }
            }
            reference = p
            referenceFrame = FLWindows.frame(containing: p, pid: pid)
            if phase == .armInput, referenceFrame == nil {
                reference = nil
                message = "Clique dans la fenêtre du Mixer."
                return
            }
            instruction = prompt()
            return
        }
        guard !isRight, let ref = reference else { return }
        let names = order
        let name = names[captured.count]
        switch phase {
        case .menu:
            captured[name] = ClickSpot(anchor: .cursor, dx: p.x - ref.x, dy: p.y - ref.y)
        case .armInput:
            guard let frame = referenceFrame else { return }
            switch name {
            case Macro.Spot.arm:            // dans la colonne de la piste visée
                captured[name] = ClickSpot(anchor: .cursorXWindowY, dx: p.x - ref.x, dy: p.y - frame.minY)
            case Macro.Spot.inputMenu:      // panneau de la piste sélectionnée : même place quelle que soit la piste
                captured[name] = ClickSpot(anchor: .window, dx: p.x - frame.minX, dy: p.y - frame.minY)
            default:                        // élément de la liste qui vient de s'ouvrir
                guard let last = lastPoint else { return }
                captured[name] = ClickSpot(anchor: .lastClick, dx: p.x - last.x, dy: p.y - last.y)
            }
        }
        lastPoint = p
        if captured.count == names.count {
            let result = captured
            let done = completion
            cancel()
            done?(result)
        } else {
            instruction = prompt()
        }
    }
}

// MARK: - Diagnostic : `FLShortcut --diag-macro`

/// Affiche ce que voit l'app dans FL (fenêtres, arbre d'accessibilité) pour régler les macros.
/// Mode d'emploi : lancer la commande app quittée, ouvrir dans FL le menu ou la boîte à étudier pendant le compte à rebours.
enum MacroDiagnostics {
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--diag-macro") else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        print("Accessibilité autorisée pour ce programme : \(AXIsProcessTrusted() ? "oui" : "NON (à activer pour le Terminal)")")
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.image-line.flstudio").first else {
            print("FL Studio ne tourne pas.")
            exit(1)
        }
        let pid = app.processIdentifier
        if let i = CommandLine.arguments.firstIndex(of: "--watch") {
            let seconds = min(max(Double(CommandLine.arguments.dropFirst(i + 1).first ?? "") ?? 20, 1), 120)
            print("Observation des fenêtres de FL pendant \(Int(seconds)) s. Dans FL : clic droit sur une piste du Mixer, survole File, ouvre le sous-menu, Échap.")
            MacroLog.shared.beginRun("sonde --watch", flPID: pid)
            MacroProbe.watch(pid: pid, seconds: seconds) { line in
                print(line)
                MacroLog.shared.write("PROBE", line)
            }
            MacroLog.shared.endRun("sonde terminée")
            MacroLog.shared.flush()
            exit(0)
        }
        print("FL Studio : pid \(pid). Ouvre maintenant le menu / la boîte à étudier dans FL : mesure dans 6 s…")
        Thread.sleep(forTimeInterval: 6)
        let windows = FLWindows.list(pid: pid)
        print("\nFenêtres de FL (avant → arrière) : \(windows.count), dont \(FLWindows.dialogCount(pid: pid)) de niveau 0 à 8")
        for w in windows {
            print("  niveau \(w.layer) · \(Int(w.bounds.width))×\(Int(w.bounds.height)) en (\(Int(w.bounds.minX)), \(Int(w.bounds.minY)))")
        }
        print("\nArbre d'accessibilité :")
        for line in AXMenus.dump(pid: pid) { print(line) }
        exit(0)
    }
}
