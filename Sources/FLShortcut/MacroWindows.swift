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
        return "#\(number) L\(layer) (\(Int(bounds.minX)),\(Int(bounds.minY))) \(Int(bounds.width))x\(Int(bounds.height))\(a)"
    }

    /// Menu contextuel, sous-menu ou liste déroulante plausible.
    var isMenuLike: Bool { bounds.width >= 30 && bounds.width <= 1400 && bounds.height >= 16 && bounds.height <= 4000 }
    /// Boîte de dialogue plausible (panneau d'ouverture, dialogue de FL).
    var isDialogLike: Bool { bounds.width >= 320 && bounds.height >= 200 }
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
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return WinSnapshot(time: now, fl: [], panelService: [])
        }
        var fl: [WinInfo] = [], service: [WinInfo] = []
        for w in raw {
            guard let owner = w[kCGWindowOwnerPID as String] as? Int32,
                  let layer = w[kCGWindowLayer as String] as? Int,
                  let dict = w[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  bounds.width >= 1, bounds.height >= 1 else { continue }
            let alpha = (w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard alpha > 0.05 else { continue }      // fenêtres en réserve / qui s'effacent : pas « ouvertes »
            let info = WinInfo(number: (w[kCGWindowNumber as String] as? NSNumber)?.intValue ?? 0,
                               layer: layer, bounds: bounds, pid: owner, alpha: alpha)
            if owner == pid {
                fl.append(info)
            } else if let name = w[kCGWindowOwnerName as String] as? String, panelServiceOwners.contains(name) {
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
            if let f = frame { s += " (\(Int(f.minX)),\(Int(f.minY))) \(Int(f.width))x\(Int(f.height))" }
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
            if pointer != lastPointer { emit("\(t)   cursor (\(Int(c.x)),\(Int(c.y))) \(pointer)") }
            lastPointer = pointer
            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}
