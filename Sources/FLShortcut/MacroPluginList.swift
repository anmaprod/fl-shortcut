// « Cliquer sur… › Ajouter un instrument / un effet » avec un plugin hors des favoris de FL (demande du 28/10 : tous
// les plugins, mais RIEN ajouté aux listes de FL) : Add › Channel (ou Effect) › More plugins... ouvre la liste de tous
// les plugins de FL (fenêtre « Select plugin ») ; le plugin y est retrouvé à son nom, lu dans la seule fenêtre de FL au
// moment du clic (autorisation « Enregistrement de l'écran », règle du propriétaire), puis double-cliqué : FL l'ouvre
// (manuel de FL : « Double-click the instrument name »). Jamais la case devant le nom : elle en ferait un favori. La
// liste défile si besoin. Le nom n'est jamais journalisé.
import CoreGraphics
import Foundation

enum PluginListPick {
    /// Pure (testée) : le nom du plugin parmi les textes lus de la liste (même texte, à la forme de comparaison près),
    /// le plus haut s'il y est plusieurs fois.
    static func find(_ name: String, in items: [TextLook.Item]) -> TextLook.Item? {
        let wanted = TextLook.normalized(name)
        guard !wanted.isEmpty else { return nil }
        return items.filter { TextLook.normalized($0.text) == wanted }.min { $0.box.minY < $1.box.minY }
    }
}

extension MacroEffectsMac {
    /// Pages de la liste lues au plus (une page : ce qu'on voit, puis la molette).
    static let pluginListPages = 15

    func addFromPluginList(_ plugin: String, item: String, ctx: Context) -> StepResult {
        guard ScreenLook.available, ScreenLook.allowed else {
            return .fail(String(localized: "lecture de l'écran pas autorisée (Réglages Système › Confidentialité et sécurité › Enregistrement de l'écran) : le plugin ne peut pas être cherché dans « More plugins… » de FL"))
        }
        let pid = ctx.pid
        let before = WinSnapshot.take(pid: pid).numbers
        numbersBeforeLastClick = before
        switch MenuBarAX.press(pid: pid, titles: ["Add", item, FLPluginDatabase.morePlugins], stop: stopReason,
                               click: { [self] p in postClick(at: p, right: false, pid: pid, hoverMs: 60) }) {
        case .done: break
        case .cancelled(let why): return .cancel(why)
        case .failed(let why): return .fail(why)
        }
        let list: WinInfo
        switch WindowWait.newWindow(pid: pid, excluding: before, timeout: 3,
                                    accept: { Self.clickWindowLayers.contains($0.layer) && $0.isDialogLike }, stop: stopReason) {
        case .success(let w): list = w
        case .failure(.stopped(let why)): return .cancel(why)
        case .failure(.timeout): return .fail(String(localized: "la liste « More plugins… » de FL ne s'est pas ouverte"))
        }
        MacroLog.shared.write("PLUGIN", "plugin list \(Int(list.bounds.width))x\(Int(list.bounds.height))")
        var previous: [String]?
        for page in 0..<Self.pluginListPages {
            if let why = stopReason() {
                closePluginList(list, pid: pid)
                return .cancel(why)
            }
            guard let image = ScreenLook.captureImage(windowNumber: list.number, size: list.bounds.size, scale: 2) else {
                closePluginList(list, pid: pid)
                return .fail(String(localized: "liste « More plugins… » de FL illisible"))
            }
            let items = TextLook.read(image, size: list.bounds.size)
            if let hit = PluginListPick.find(plugin, in: items) {
                let p = CGPoint(x: list.bounds.minX + hit.center.x, y: list.bounds.minY + hit.center.y)
                MacroLog.shared.write("PLUGIN", "found on page \(page + 1)")
                postDoubleClick(at: p, pid: pid)
                lastClickPoint = p
                // La liste se ferme d'elle-même, ou reste ouverte : refermée (le plugin est ouvert).
                if case .failure = WindowWait.gone(pid: pid, numbers: [list.number], timeout: 1.5, stop: { nil }) {
                    closePluginList(list, pid: pid)
                }
                return .ok
            }
            let texts = items.map(\.text)
            if texts == previous { break }                       // bas de la liste : plus rien ne défile
            previous = texts
            scrollWheel(in: list.bounds, lines: -8, pid: pid)
            Thread.sleep(forTimeInterval: 0.2)
        }
        closePluginList(list, pid: pid)
        MacroLog.shared.write("PLUGIN", "not found in the list")
        return .fail(String(localized: "plugin introuvable dans « More plugins… » de FL : vérifie son nom, ou choisis-le de nouveau dans « Cliquer sur… »"))
    }

    /// Échap tant que la liste est encore là (jamais d'Échap à l'aveugle) : elle se referme.
    func closePluginList(_ list: WinInfo, pid: Int32) {
        for _ in 0..<2 where WinSnapshot.take(pid: pid).window(list.number) != nil {
            postKey(KeyCombo(keyCode: 53), pid: pid)
            _ = WindowWait.gone(pid: pid, numbers: [list.number], timeout: 0.5, stop: { nil })
        }
    }

    /// Double-clic gauche en `p` (deux appuis, le second compté comme double).
    func postDoubleClick(at p: CGPoint, pid: Int32) {
        if cursorBeforeBurst == nil { cursorBeforeBurst = FLWindows.cursor() }
        if Self.warpCursor {
            CGWarpMouseCursorPosition(p)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        func send(_ type: CGEventType, _ count: Int64) {
            guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: p, mouseButton: .left) else { return }
            e.flags = []
            e.setIntegerValueField(.mouseEventClickState, value: count)
            e.setIntegerValueField(.eventSourceUserData, value: EventTap.mark)
            if Self.clicksToPid { e.postToPid(pid) } else { e.post(tap: .cghidEventTap) }
        }
        send(.mouseMoved, 0)
        usleep(40_000)
        send(.leftMouseDown, 1)
        usleep(30_000)
        send(.leftMouseUp, 1)
        usleep(60_000)
        send(.leftMouseDown, 2)
        usleep(30_000)
        send(.leftMouseUp, 2)
        MacroLog.shared.write("CLICK", "double \(p.logText)")
    }

    /// Molette au milieu de `frame` (lignes négatives : vers le bas).
    func scrollWheel(in frame: CGRect, lines: Int32, pid: Int32) {
        let p = CGPoint(x: frame.midX, y: frame.midY)
        if cursorBeforeBurst == nil { cursorBeforeBurst = FLWindows.cursor() }
        if Self.warpCursor {
            CGWarpMouseCursorPosition(p)
            CGAssociateMouseAndMouseCursorPosition(1)
        }
        guard let e = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0) else { return }
        e.location = p
        e.setIntegerValueField(.eventSourceUserData, value: EventTap.mark)
        if Self.clicksToPid { e.postToPid(pid) } else { e.post(tap: .cghidEventTap) }
    }
}
