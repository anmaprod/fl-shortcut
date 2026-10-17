// Métadonnées des fenêtres (CoreGraphics : numéro, niveau, cadre, propriétaire, alpha ; jamais de pixels, jamais
// kCGWindowName), attente d'apparition / disparition des fenêtres, hit-test Accessibilité et sonde `--diag-macro --watch`.
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct WinInfo: Equatable, CustomStringConvertible {
    let number: Int
    let layer: Int
    let bounds: CGRect
    let pid: Int32
    let alpha: Double

    var description: String {
        let a = alpha < 0.999 ? String(format: " a%.2f", alpha) : ""
        return "#\(number) L\(layer) \(bounds.logText)\(a)"
    }

    /// Menu contextuel, sous-menu ou liste déroulante plausible.
    var isMenuLike: Bool { bounds.width >= 30 && bounds.width <= 1400 && bounds.height >= 16 && bounds.height <= 4000 }
    /// Boîte de dialogue plausible (panneau d'ouverture, dialogue de FL).
    var isDialogLike: Bool { bounds.width >= 320 && bounds.height >= 200 }
}

/// Une fenêtre de la liste de macOS (à l'écran, sans le bureau), de l'avant vers l'arrière. Seules les entrées qui
/// ont un propriétaire, un niveau et un cadre sont gardées.
struct ScreenWindow {
    let number: Int
    let layer: Int
    let bounds: CGRect
    let owner: Int32
    let ownerName: String?
    let alpha: Double

    /// nil si la liste n'a pas pu être lue.
    static func onScreen() -> [ScreenWindow]? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        return raw.compactMap { w in
            guard let owner = w[kCGWindowOwnerPID as String] as? Int32,
                  let layer = w[kCGWindowLayer as String] as? Int,
                  let dict = w[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary) else { return nil }
            return ScreenWindow(number: (w[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0, layer: layer,
                                bounds: bounds, owner: owner, ownerName: w[kCGWindowOwnerName as String] as? String,
                                alpha: (w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1)
        }
    }
}

/// Fenêtres visibles à l'écran, de l'avant vers l'arrière, à `time` (temps depuis le démarrage : même horloge que
/// NSEvent.timestamp).
struct WinSnapshot {
    let time: TimeInterval
    let fl: [WinInfo]
    /// Panneaux d'ouverture / d'enregistrement hors processus (seulement chez les applis sandboxées ; sans effet sinon).
    let panelService: [WinInfo]

    static let panelServiceOwners: Set<String> = ["Open and Save Panel Service", "com.apple.appkit.xpc.openAndSavePanelService"]

    static func take(pid: Int32) -> WinSnapshot {
        let now = ProcessInfo.processInfo.systemUptime
        guard let raw = ScreenWindow.onScreen() else { return WinSnapshot(time: now, fl: [], panelService: []) }
        var fl: [WinInfo] = [], service: [WinInfo] = []
        // Fenêtres en réserve / qui s'effacent (alpha ≤ 0,05) ou vides : pas « ouvertes ».
        let helpers = FLHelpers.pids(of: pid)
        for w in raw where w.bounds.width >= 1 && w.bounds.height >= 1 && w.alpha > 0.05 {
            let info = WinInfo(number: w.number, layer: w.layer, bounds: w.bounds, pid: w.owner, alpha: w.alpha)
            if w.owner == pid || helpers.contains(w.owner) {     // FL, ou son pont de plugins (Intel)
                fl.append(info)
            } else if let name = w.ownerName, panelServiceOwners.contains(name) {
                service.append(info)
            }
        }
        return WinSnapshot(time: now, fl: fl, panelService: service)
    }

    var numbers: Set<Int> { Set(fl.map(\.number) + panelService.map(\.number)) }
    func window(_ number: Int) -> WinInfo? { fl.first { $0.number == number } }
    /// Fenêtre de FL tout devant sous `p`, tous niveaux : celle où tombe un clic en `p` (parmi les fenêtres de FL).
    func hit(_ p: CGPoint) -> WinInfo? { fl.first { $0.bounds.contains(p) } }
}

/// Processus lancés par FL (pont des plugins Intel sur un Mac Apple) : les fenêtres de ces plugins sont les leurs,
/// elles comptent comme celles de FL. Liste des processus relue au plus une fois par seconde, et seulement pendant une
/// macro ou un enregistrement (rien au repos).
enum FLHelpers {
    private static let cache = Locked<(parent: Int32, time: TimeInterval, pids: Set<Int32>)?>(nil)

    static func pids(of parent: Int32) -> Set<Int32> {
        guard parent > 0 else { return [] }
        let now = ProcessInfo.processInfo.systemUptime
        if let c = cache.value, c.parent == parent, now - c.time < 1 { return c.pids }
        let found = children(of: parent)
        cache.withLock { $0 = (parent: parent, time: now, pids: found) }
        return found
    }

    /// FL ou un processus lancé par FL.
    static func isFLOrHelper(_ pid: Int32, fl: Int32) -> Bool {
        pid == fl || pids(of: fl).contains(pid)
    }

    private static func children(of parent: Int32) -> Set<Int32> {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32)
        size = procs.count * stride
        guard sysctl(&mib, u_int(mib.count), &procs, &size, nil, 0) == 0 else { return [] }
        var out = Set<Int32>()
        for proc in procs.prefix(size / stride) where proc.kp_eproc.e_ppid == parent && proc.kp_proc.p_pid > 0 {
            out.insert(proc.kp_proc.p_pid)
        }
        return out
    }
}

/// Fenêtres de plugins de FL (Serum, Vital…) par l'Accessibilité, déjà accordée pour le clavier : leur titre (le nom
/// de la piste du plugin) les retrouve où qu'elles soient et quelle que soit leur taille. Jamais l'écran ; le titre
/// n'est gardé que dans la macro, jamais journalisé. Délais courts : FL peut être occupé.
enum FLWindowAX {
    static let timeout: Float = 0.15

    /// Titre de la fenêtre sous `p` si c'est une fenêtre de plugin de FL (ni la fenêtre principale, ni sans titre).
    static func pluginTitle(at p: CGPoint, fl pid: Int32) -> String? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &found) == .success, let el = found
        else { return nil }
        var owner: pid_t = 0
        guard AXUIElementGetPid(el, &owner) == .success, FLHelpers.isFLOrHelper(owner, fl: pid) else { return nil }
        let window: AXUIElement
        if string(el, kAXRoleAttribute) == (kAXWindowRole as String) {
            window = el
        } else {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, kAXWindowAttribute as CFString, &value) == .success, let v = value,
                  CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
            window = v as! AXUIElement               // type vérifié juste au-dessus
        }
        return pluginTitle(of: window)
    }

    /// Titre de la fenêtre de plugin sous un clic, d'après les fenêtres de FL juste avant lui : jamais pour la fenêtre
    /// principale (la plus grande au niveau 0), ni hors des fenêtres de FL.
    static func pluginTitle(at p: CGPoint, before: WinSnapshot, fl pid: Int32) -> String? {
        guard let hit = before.hit(p) else { return nil }
        let main = before.fl.filter { $0.layer == 0 }.max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
        guard hit.number != main?.number else { return nil }
        return pluginTitle(at: p, fl: pid)
    }

    /// Cadres (coordonnées de l'écran, origine en haut à gauche) des fenêtres de FL et de son pont qui portent ce titre.
    static func frames(titled title: String, fl pid: Int32) -> [CGRect] {
        var out: [CGRect] = []
        for owner in [pid] + FLHelpers.pids(of: pid).sorted() {
            let app = AXUIElementCreateApplication(owner)
            AXUIElementSetMessagingTimeout(app, timeout)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
                  let windows = value as? [AXUIElement] else { continue }
            for w in windows where pluginTitle(of: w) == title {
                if let f = frame(of: w) { out.append(f) }
            }
        }
        return out
    }

    /// Titre retenu pour une fenêtre : pas la fenêtre principale de FL (son titre porte le nom du projet), pas vide,
    /// court.
    static func pluginTitle(of window: AXUIElement) -> String? {
        guard let title = string(window, kAXTitleAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines),
              isPluginTitle(title) else { return nil }
        return title
    }

    /// Pure (testée).
    static func isPluginTitle(_ title: String) -> Bool {
        !title.isEmpty && title.count <= ClickTarget.maxTitle && !title.localizedCaseInsensitiveContains("FL Studio")
    }

    private static func string(_ el: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
              let p = pos, let s = size, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero, extent = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &extent),
              extent.width >= 1, extent.height >= 1 else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}

enum WindowWait {
    enum Failure: Error, Equatable { case timeout, stopped(String) }

    /// Fenêtre de FL tout devant, absente de `excluding` et acceptée par `accept`, lue deux fois de suite avec le même
    /// cadre et le même alpha (FL a fini de la placer : c'est là qu'il la décale pour qu'elle tienne à l'écran).
    static func newWindow(pid: Int32, excluding: Set<Int>, timeout: TimeInterval,
                          accept: (WinInfo) -> Bool = { $0.isMenuLike },
                          stop: () -> String?) -> Result<WinInfo, Failure> {
        let deadline = Date().addingTimeInterval(timeout)
        var candidate: WinInfo?
        repeat {
            if let why = stop() { return .failure(.stopped(why)) }
            let fresh = WinSnapshot.take(pid: pid).fl.first { !excluding.contains($0.number) && accept($0) }
            if let fresh, let previous = candidate, previous == fresh { return .success(fresh) }
            candidate = fresh
            Thread.sleep(forTimeInterval: 0.012)
        } while Date() < deadline
        return .failure(.timeout)
    }

    /// Toutes les fenêtres `numbers` fermées (ou invisibles).
    static func gone(pid: Int32, numbers: Set<Int>, timeout: TimeInterval, interval: TimeInterval = 0.015,
                     stop: () -> String?) -> Result<Void, Failure> {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let why = stop() { return .failure(.stopped(why)) }
            if WinSnapshot.take(pid: pid).numbers.isDisjoint(with: numbers) { return .success(()) }
            Thread.sleep(forTimeInterval: interval)
        } while Date() < deadline
        return .failure(.timeout)
    }
}

// MARK: - Hit-test via l'Accessibilité (permission déjà donnée pour le tap clavier)

enum AXProbe {
    struct Hit: CustomStringConvertible {
        var pid: Int32 = 0
        var role = "-"
        var subrole = ""
        var title: String?
        var frame: CGRect?
        var error: AXError = .success
        var ms = 0.0
        var element: AXUIElement?

        var description: String {
            let time = String(format: "%.0f ms", ms)
            guard error == .success else { return "AX error \(error.rawValue) (\(time))" }
            var s = "AX pid \(pid) \(role)" + (subrole.isEmpty ? "" : "/\(subrole)")
            if let title { s += " \"\(title)\"" }
            if let f = frame { s += " \(f.logText)" }
            return s + " (\(time))"
        }
    }

    /// Délai court : FL peut être dans sa boucle de menu (thread principal) ; une réponse lente ne doit pas bloquer la macro.
    static func hit(_ p: CGPoint, timeout: Float = 0.15) -> Hit {
        let t0 = DispatchTime.now().uptimeNanoseconds
        var out = Hit()
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, timeout)
        var element: AXUIElement?
        out.error = AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &element)
        if out.error == .success, let element {
            out.element = element
            var pid: pid_t = 0
            if AXUIElementGetPid(element, &pid) == .success { out.pid = pid }
            out.role = string(element, kAXRoleAttribute) ?? "?"
            out.subrole = string(element, kAXSubroleAttribute) ?? ""
            // Titres seulement pour les rôles de menu (libellés de FL), tronqués : jamais de contenu de document ou de projet.
            if out.role.hasPrefix("AXMenu") { out.title = string(element, kAXTitleAttribute).map { String($0.prefix(48)) } }
            out.frame = frame(element)
        }
        out.ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        return out
    }

    /// Niveau 0 : si FL expose ce menu à l'Accessibilité, centre de l'élément dont le titre correspond (sinon nil).
    static func itemCenter(in popup: WinInfo, titles: [String]) -> CGPoint? {
        guard !titles.isEmpty else { return nil }
        let probe = hit(CGPoint(x: popup.bounds.midX, y: popup.bounds.minY + min(30, popup.bounds.height / 2)))
        guard var el = probe.element, probe.pid == popup.pid else { return nil }
        var climbs = 0
        while string(el, kAXRoleAttribute) != (kAXMenuRole as String) {
            var parent: CFTypeRef?
            guard climbs < 4, AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
            el = parent as! AXUIElement
            climbs += 1
        }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &kids) == .success,
              let items = kids as? [AXUIElement] else { return nil }
        let wanted = titles.map(normalized)
        for item in items.prefix(80) {
            guard let t = string(item, kAXTitleAttribute).map(normalized),
                  wanted.contains(where: { $0.count <= 6 ? t == $0 : t.hasPrefix($0) }),
                  let f = frame(item) else { continue }
            let c = CGPoint(x: f.midX, y: f.midY)
            if popup.bounds.insetBy(dx: 1, dy: 1).contains(c) { return c }
        }
        return nil
    }

    static func string(_ el: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func frame(_ el: AXUIElement) -> CGRect? {
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &size) == .success,
              let pos, let size,
              CFGetTypeID(pos) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(pos as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    private static func normalized(_ s: String) -> String {
        var t = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasSuffix("…") || t.hasSuffix(".") { t.removeLast() }
        return t
    }
}

// MARK: - Sonde : `FLShortcut --diag-macro --watch 20`

/// Affiche chaque fenêtre de FL qui apparaît (+), change (~) ou disparaît (-), à 50 ms près, ainsi que les boutons
/// de la souris et le hit-test AX sous le curseur quand ils changent. La lancer, puis dans FL : clic droit sur une piste
/// du mixer, survol de File, ouverture du sous-menu, Échap. Répond à : les menus de FL sont-ils des fenêtres à part,
/// à quel niveau, décalés où, FL les expose-t-il à l'Accessibilité, le menu s'ouvre-t-il à l'appui ou au relâchement ?
enum MacroProbe {
    static func watch(pid: Int32, seconds: Double, emit: (String) -> Void) {
        var previous: [Int: WinInfo] = [:]
        var lastPointer = ""
        var lastAX = Date.distantPast
        let start = Date()
        while Date().timeIntervalSince(start) < seconds {
            let t = String(format: "%7.3f", Date().timeIntervalSince(start))
            let snap = WinSnapshot.take(pid: pid)
            var now: [Int: WinInfo] = [:]
            for w in snap.fl { now[w.number] = w }
            for w in snap.fl where previous[w.number] == nil { emit("\(t) + \(w)") }
            for w in snap.fl where previous[w.number].map({ $0 != w }) ?? false { emit("\(t) ~ \(w)") }
            for (n, w) in previous where now[n] == nil { emit("\(t) - \(w)") }
            previous = now
            let c = FLWindows.cursor()
            let left = CGEventSource.buttonState(.combinedSessionState, button: .left)
            let right = CGEventSource.buttonState(.combinedSessionState, button: .right)
            var pointer = "buttons L\(left ? 1 : 0) R\(right ? 1 : 0) over FL #\(snap.hit(c)?.number ?? 0)"
            if Date().timeIntervalSince(lastAX) > 0.25 {
                lastAX = Date()
                let ax = AXProbe.hit(c)
                pointer += " | \(ax.pid) \(ax.role)/\(ax.subrole) \(ax.title ?? "")"
            } else if let range = lastPointer.range(of: " | ") {
                pointer += lastPointer[range.lowerBound...]
            }
            if pointer != lastPointer { emit("\(t)   cursor \(c.logText) \(pointer)") }
            lastPointer = pointer
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}
