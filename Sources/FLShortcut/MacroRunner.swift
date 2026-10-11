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
    case failed(step: Int, reason: String)
    case cancelled(reason: String)

    var text: String {
        switch self {
        case .done: return "Macro terminée"
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
            out.append(Info(layer: layer, bounds: bounds))
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

    /// Processus propriétaire de la fenêtre visible tout devant à ce point (menus contextuels compris).
    static func ownerOfTopWindow(at p: CGPoint) -> Int32? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for w in raw {                                            // de l'avant vers l'arrière
            guard let layer = w[kCGWindowLayer as String] as? Int, layer >= 0, layer < 1000,
                  let alpha = w[kCGWindowAlpha as String] as? Double, alpha > 0.01,
                  let dict = w[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary), bounds.contains(p) else { continue }
            return w[kCGWindowOwnerPID as String] as? Int32
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
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        for title in titles {
            let deadline = Date().addingTimeInterval(perItemTimeout)
            var pressed = false
            while Date() < deadline, !shouldStop() {
                if let item = findItem(in: app, title: title),
                   AXUIElementPerformAction(item, kAXPressAction as CFString) == .success {
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

    /// Parcours en largeur, borné (600 nœuds), sans la barre des menus.
    private static func findItem(in root: AXUIElement, title: String) -> AXUIElement? {
        var queue: [AXUIElement] = [root]
        var visited = 0
        while !queue.isEmpty, visited < 600 {
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

    /// Point du dernier clic de la macro (repère `lastClick`). File de la macro uniquement.
    private var lastClickPoint: CGPoint?

    private enum StepResult {
        case ok
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
        /// Fenêtre de FL qui contient la piste (Mixer détaché, ou fenêtre principale).
        let trackFrame: CGRect?
    }

    /// Colonne de la piste capturée avant le choix de l'entrée : le bouton d'armement est ce qui y change.
    private var columnBefore: ScreenShot?

    private let queue = DispatchQueue(label: "fr.flshortcut.macro", qos: .userInitiated)
    private let busy = Locked(false)
    private let source = CGEventSource(stateID: .privateState)

    private init() {}

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
                if case .done = outcome { ok = true } else { NSSound.beep() }
                NotificationCenter.default.post(name: .macroFinished, object: nil,
                                                userInfo: ["ok": ok, "text": outcome.text])
            }
        }
        return .started
    }

    private func execute(_ steps: [MacroStep], pid: Int32) -> MacroOutcome {
        let origin = FLWindows.cursor()
        lastClickPoint = nil
        columnBefore = nil
        var track = origin
        if let remembered = TrackMemory.shared.lastClick(), FLWindows.frame(containing: remembered, pid: pid) != nil {
            track = remembered
        }
        let ctx = Context(pid: pid, origin: origin,
                          frame: FLWindows.frame(containing: origin, pid: pid),
                          baseline: FLWindows.dialogCount(pid: pid),
                          track: track,
                          trackFrame: FLWindows.frame(containing: track, pid: pid))
        if steps.contains(where: { [.trackMenu, .selectInput, .armTrack, .recordOn].contains($0.kind) }),
           !ScreenAccess.granted {
            DispatchQueue.main.async { ScreenAccess.request() }
            return .failed(step: 1, reason: "autorise « Enregistrement de l'écran » pour FL Shortcut (Réglages Système), puis réessaie")
        }
        defer { if Self.warpCursor { CGWarpMouseCursorPosition(origin) } }
        // Les modificateurs du raccourci (⌃⌥⌘⇧) sont encore enfoncés : un clic avec ⌃ serait un clic droit.
        guard waitForModifiersReleased(timeout: 1.5) else { return .cancelled(reason: "relâche les touches du raccourci") }
        for (index, step) in steps.enumerated() {
            if let stop = shouldStop(pid) { return .cancelled(reason: stop) }
            switch perform(step, ctx: ctx) {
            case .ok: continue
            case .fail(let why): return .failed(step: index + 1, reason: why)
            case .cancel(let why): return .cancelled(reason: why)
            }
        }
        return .done
    }

    // MARK: Garde-fous

    /// Raison d'arrêter maintenant, sinon nil.
    private func shouldStop(_ pid: Int32) -> String? {
        let cfg = EventTap.shared.currentConfig
        guard cfg.flPIDs.contains(pid), cfg.frontmostPID == pid else { return "FL n'est plus au premier plan" }
        if CGEventSource.keyState(.combinedSessionState, key: 53) { return "Échap" }
        return nil
    }

    private func waitForModifiersReleased(timeout: TimeInterval) -> Bool {
        let mask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if CGEventSource.flagsState(.combinedSessionState).intersection(mask).isEmpty { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return false
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
            return wait(timeoutMs: step.ms, pid: ctx.pid, failure: "boîte de dialogue introuvable") {
                FLWindows.dialogCount(pid: ctx.pid) > ctx.baseline
            }

        case .waitDialogClose:
            return wait(timeoutMs: step.ms, pid: ctx.pid, failure: "la boîte de dialogue ne se ferme pas") {
                FLWindows.dialogCount(pid: ctx.pid) <= ctx.baseline
            }

        case .trackMenu:
            return trackMenu(step.titles, ctx: ctx)

        case .feedbackCheck:
            let report = FeedbackRisk.check(flPID: ctx.pid)
            guard report.risky else { return .ok }
            DispatchQueue.main.async { FeedbackAlert.show(report) }
            return .fail("risque de larsen (micro et haut-parleurs de l'ordinateur)")

        case .selectInput:
            return selectInput(ctx: ctx)

        case .armTrack:
            return armTrack(ctx: ctx)

        case .recordOn:
            guard let combo = step.combo else { return .fail("touche REC manquante") }
            guard !EventTap.shared.currentConfig.forbidden.isForbidden(combo) else { return .fail("touche interdite") }
            return recordOn(combo, ctx: ctx)

        case .chooseFile:
            guard let path = step.path else { return .fail("chemin manquant") }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
                return .fail("preset introuvable (\(URL(fileURLWithPath: path).lastPathComponent))")
            }
            // ⌘⇧G = « Aller au dossier » ; un chemin complet sélectionne le fichier ; Entrée l'ouvre.
            postKey(KeyCombo(keyCode: 5, command: true, shift: true), pid: ctx.pid)
            if case .cancel(let why) = pause(450, pid: ctx.pid) { return .cancel(why) }
            typeText(path, pid: ctx.pid)
            if case .cancel(let why) = pause(350, pid: ctx.pid) { return .cancel(why) }
            postKey(KeyCombo(keyCode: 36), pid: ctx.pid)
            if case .cancel(let why) = pause(450, pid: ctx.pid) { return .cancel(why) }
            postKey(KeyCombo(keyCode: 36), pid: ctx.pid)
            return .ok
        }
    }

    // MARK: Étapes automatiques (lecture de l'écran)

    /// Zone de l'écran où chercher un menu qui s'ouvre au point `p` (vers la droite et le bas, un peu autour).
    private func menuArea(around p: CGPoint) -> CGRect {
        CGRect(x: p.x - 80, y: p.y - 500, width: 760, height: 1100)
    }

    /// Cherche l'un des libellés à l'écran (fenêtres de FL seulement) pendant `timeout` secondes.
    private func waitForText(_ variants: [String], in area: CGRect, pid: Int32, timeout: TimeInterval) -> Result<ScreenText, StepResultError> {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let stop = shouldStop(pid) { return .failure(.cancel(stop)) }
            if let shot = ScreenReader.capture(pid: pid, rect: area), let hit = ScreenReader.find(variants, in: shot) {
                return .success(hit)
            }
            Thread.sleep(forTimeInterval: 0.12)
        } while Date() < deadline
        return .failure(.notFound)
    }

    private enum StepResultError: Error {
        case cancel(String)
        case notFound
    }

    /// Clic droit sur la piste, puis chaque titre lu dans le menu qui s'ouvre (File › Open mixer track state).
    private func trackMenu(_ titles: [String], ctx: Context) -> StepResult {
        let first = click(at: ctx.track, right: true, ctx: ctx)
        guard case .ok = first else { return first }
        var anchor = ctx.track
        for (i, title) in titles.enumerated() {
            let variants = title.split(separator: "|").map(String.init)
            switch waitForText(variants, in: menuArea(around: anchor), pid: ctx.pid, timeout: i == 0 ? 1.5 : 1.2) {
            case .success(let hit):
                // Survol puis clic : FL ouvre ses sous-menus au survol.
                let result = click(at: hit.center, right: false, ctx: ctx)
                guard case .ok = result else { return result }
                anchor = hit.center
                if case .cancel(let why) = pause(220, pid: ctx.pid) { return .cancel(why) }
            case .failure(.cancel(let why)):
                return .cancel(why)
            case .failure(.notFound):
                postKey(KeyCombo(keyCode: 53), pid: ctx.pid)            // Échap : referme le menu à moitié ouvert
                return .fail(i == 0
                    ? "menu de la piste introuvable : clique sur le nom de la piste dans le Mixer, puis réessaie"
                    : "« \(variants.first ?? title) » introuvable dans le menu de la piste")
            }
        }
        return .ok
    }

    /// Colonne de la piste dans sa fenêtre (largeur d'une tranche du Mixer).
    private func trackColumn(_ ctx: Context) -> CGRect? {
        guard let f = ctx.trackFrame else { return nil }
        return CGRect(x: ctx.track.x - 40, y: f.minY, width: 80, height: f.height).intersection(f)
    }

    /// « (none) » → première entrée de la liste. Déjà une entrée choisie : rien à faire.
    private func selectInput(ctx: Context) -> StepResult {
        guard let frame = ctx.trackFrame else { return .fail("fenêtre du Mixer introuvable") }
        if let column = trackColumn(ctx) { columnBefore = ScreenReader.capture(pid: ctx.pid, rect: column) }
        guard let shot = ScreenReader.capture(pid: ctx.pid, rect: frame) else { return .fail("capture de FL impossible") }
        let texts = ScreenReader.texts(in: shot)
        // Le sélecteur d'entrée est le premier « (none) » en partant du haut (la sortie est en dessous).
        let selectors = texts.filter { ScreenReader.normalized($0.text).contains("none") }.sorted { $0.rect.minY < $1.rect.minY }
        guard let selector = selectors.first else { return .ok }               // une entrée est déjà choisie
        let opened = click(at: selector.center, right: false, ctx: ctx)
        guard case .ok = opened else { return opened }
        // Première entrée : « In 1 », « Input 1 », « 1 », ou « … 1 » (nom de l'appareil suivi du numéro).
        let deadline = Date().addingTimeInterval(1.5)
        repeat {
            if let stop = shouldStop(ctx.pid) { return .cancel(stop) }
            let area = CGRect(x: selector.center.x - 200, y: selector.center.y - 60, width: 700, height: 900)
            if let list = ScreenReader.capture(pid: ctx.pid, rect: area) {
                let items = ScreenReader.texts(in: list)
                    .filter { $0.rect.minY > selector.rect.minY - 4 && !ScreenReader.normalized($0.text).contains("none") }
                    .sorted { $0.rect.minY < $1.rect.minY }
                if let one = items.first(where: { Self.isFirstInput($0.text) }) ?? items.first(where: { $0.rect.minY > selector.rect.maxY }) {
                    return click(at: one.center, right: false, ctx: ctx)
                }
            }
            Thread.sleep(forTimeInterval: 0.12)
        } while Date() < deadline
        postKey(KeyCombo(keyCode: 53), pid: ctx.pid)
        return .fail("liste des entrées introuvable")
    }

    static func isFirstInput(_ text: String) -> Bool {
        let t = ScreenReader.normalized(text)
        return t.range(of: #"^(in|input|entrée|entree)?\s*1(\b|$)"#, options: .regularExpression) != nil
            || t.range(of: #"\s1$"#, options: .regularExpression) != nil
    }

    /// Bouton d'armement de la piste : ce qui est apparu ou a changé dans sa colonne avec l'entrée, ou le voyant
    /// déjà allumé en bas de la colonne. Allumé : rien à faire (ne jamais désarmer).
    private func armTrack(ctx: Context) -> StepResult {
        guard let column = trackColumn(ctx) else { return .fail("fenêtre du Mixer introuvable") }
        if case .cancel(let why) = pause(250, pid: ctx.pid) { return .cancel(why) }
        guard let now = ScreenReader.capture(pid: ctx.pid, rect: column), let after = ScreenReader.Pixels(now.image) else {
            return .fail("capture de FL impossible")
        }
        let lowerHalf = CGRect(x: 0, y: CGFloat(after.height) * 0.45, width: CGFloat(after.width), height: CGFloat(after.height) * 0.55)
        var candidate: CGRect?
        if let before = columnBefore.flatMap({ ScreenReader.Pixels($0.image) }) {
            candidate = ScreenReader.changedBoxes(before, after)
                .filter { $0.intersects(lowerHalf) && $0.width <= 40 * now.scale && $0.height <= 40 * now.scale }
                .max { $0.width * $0.height < $1.width * $1.height }
        }
        // Voyant déjà allumé en bas de la colonne : armée.
        if ScreenReader.litFraction(after, in: candidate ?? lowerHalf) > (candidate == nil ? 0.004 : 0.15) { return .ok }
        guard let box = candidate else {
            return .fail("bouton d'armement non reconnu : envoie une capture (fiche du raccourci › Capturer FL)")
        }
        let point = CGPoint(x: now.rect.minX + box.midX / now.scale, y: now.rect.minY + box.midY / now.scale)
        let result = click(at: point, right: false, ctx: ctx)
        guard case .ok = result else { return result }
        if case .cancel(let why) = pause(300, pid: ctx.pid) { return .cancel(why) }
        if let check = ScreenReader.capture(pid: ctx.pid, rect: column), let px = ScreenReader.Pixels(check.image),
           ScreenReader.litFraction(px, in: box) > 0.15 {
            return .ok
        }
        return .fail("armement non confirmé : envoie une capture (fiche du raccourci › Capturer FL)")
    }

    /// REC : la touche de FL, puis comparaison du haut de la fenêtre avant / après. S'il s'est éteint, il était
    /// déjà allumé : on le rallume (ne jamais couper un REC déjà prêt).
    private func recordOn(_ combo: KeyCombo, ctx: Context) -> StepResult {
        let main = FLWindows.list(pid: ctx.pid).filter { $0.layer == 0 }.max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
        guard let window = main?.bounds else { return .fail("fenêtre de FL introuvable") }
        let band = CGRect(x: window.minX, y: window.minY, width: window.width, height: min(110, window.height))
        guard let before = ScreenReader.capture(pid: ctx.pid, rect: band), let a = ScreenReader.Pixels(before.image) else {
            return .fail("capture de FL impossible")
        }
        postKey(combo, pid: ctx.pid)
        if case .cancel(let why) = pause(350, pid: ctx.pid) { return .cancel(why) }
        guard let after = ScreenReader.capture(pid: ctx.pid, rect: band), let b = ScreenReader.Pixels(after.image) else {
            return .fail("capture de FL impossible")
        }
        let changed = ScreenReader.changedBoxes(a, b).filter { $0.width <= 120 * before.scale && $0.height <= 80 * before.scale }
        guard let button = changed.max(by: { ScreenReader.litFraction(b, in: $0) + ScreenReader.litFraction(a, in: $0)
                                             < ScreenReader.litFraction(b, in: $1) + ScreenReader.litFraction(a, in: $1) }) else {
            return .fail("le bouton REC n'a pas réagi")
        }
        if ScreenReader.litFraction(b, in: button) >= ScreenReader.litFraction(a, in: button) { return .ok }
        postKey(combo, pid: ctx.pid)                                       // il était déjà allumé : on le rallume
        return .ok
    }

    private func wait(timeoutMs: Int, pid: Int32, failure: String, until condition: () -> Bool) -> StepResult {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        while Date() < deadline {
            if let stop = shouldStop(pid) { return .cancel(stop) }
            if condition() { return .ok }
            Thread.sleep(forTimeInterval: 0.05)
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

    private func click(at p: CGPoint, right: Bool, ctx: Context) -> StepResult {
        guard FLWindows.contains(p, pid: ctx.pid) else { return .fail("le point visé est hors de FL") }
        if !Self.clicksToPid, FLWindows.ownerOfTopWindow(at: p) != ctx.pid {
            return .fail("une autre fenêtre couvre FL à cet endroit")
        }
        postClick(at: p, right: right, pid: ctx.pid)
        lastClickPoint = p
        return .ok
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

    /// Saisie d'un texte (chemin de fichier) caractère par caractère.
    private func typeText(_ text: String, pid: Int32) {
        for character in text {
            let units = Array(String(character).utf16)
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                e.flags = []
                e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                e.setIntegerValueField(.eventSourceUserData, value: EventTap.mark)
                e.postToPid(pid)
            }
            Thread.sleep(forTimeInterval: 0.012)
        }
    }

    private func postClick(at p: CGPoint, right: Bool, pid: Int32) {
        if Self.warpCursor { CGWarpMouseCursorPosition(p) }
        let button: CGMouseButton = right ? .right : .left
        func send(_ type: CGEventType) {
            guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
            e.flags = []
            e.setIntegerValueField(.mouseEventClickState, value: 1)
            e.setIntegerValueField(.eventSourceUserData, value: EventTap.mark)
            if Self.clicksToPid { e.postToPid(pid) } else { e.post(tap: .cghidEventTap) }
        }
        send(.mouseMoved)
        Thread.sleep(forTimeInterval: 0.03)
        send(right ? .rightMouseDown : .leftMouseDown)
        Thread.sleep(forTimeInterval: 0.04)
        send(right ? .rightMouseUp : .leftMouseUp)
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
