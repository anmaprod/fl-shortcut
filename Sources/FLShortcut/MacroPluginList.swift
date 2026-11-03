// « Cliquer sur… › Ajouter un instrument / un effet » avec un plugin hors des favoris de FL (demande du 28/10 : tous
// les plugins, mais RIEN ajouté aux listes de FL) : Add › Channel (ou Effect) › More plugins... ouvre la liste de tous
// les plugins de FL (fenêtre « Select plugin ») ; le plugin y est retrouvé à son nom, lu dans la seule fenêtre de FL au
// moment du clic (autorisation « Enregistrement de l'écran », règle du propriétaire), puis double-cliqué : FL l'ouvre
// (manuel de FL : « Double-click the instrument name »). Jamais la case devant le nom : elle en ferait un favori. La
// liste défile si besoin. Le nom n'est jamais journalisé.
import CoreGraphics
import Foundation

enum PluginListPick {
    /// Pure (testée) : le nom du plugin parmi les textes lus de la liste, le plus haut s'il y est plusieurs fois. Même
    /// texte à la forme de comparaison près, sans ce qui le précède (l'étoile des favoris, lue « ☆ » ou « * ») ; aussi
    /// le début d'une ligne lue d'un seul tenant avec ses colonnes (« Analog Lab V VST3 Apple + Intel »). Vidéo du
    /// 03/11 : « Analog Lab V » était en haut de la liste, jamais reconnu, toute la liste a défilé.
    static func find(_ name: String, in items: [TextLook.Item]) -> TextLook.Item? {
        let wanted = TextLook.normalized(name)
        guard !wanted.isEmpty else { return nil }
        return items.filter { matches(TextLook.normalized($0.text), wanted) }.min { $0.box.minY < $1.box.minY }
    }

    static func matches(_ read: String, _ wanted: String) -> Bool {
        let text = String(read.drop { !$0.isLetter && !$0.isNumber })
        if text == wanted { return true }
        // Ligne lue d'un seul tenant : le nom, puis la colonne du format (jamais « Serum 2 » pour « Serum », ni
        // « Serum 2 FX » pour « Serum 2 »).
        guard text.hasPrefix(wanted + " ") else { return false }
        let next = text.dropFirst(wanted.count + 1).split(separator: " ").first.map(String.init) ?? ""
        return formats.contains(next)
    }

    /// Pure (testée) : parmi les lignes au nom du plugin, celle du format préféré (`prefer`, à la forme de
    /// comparaison ; 03/11 : un instrument en VST3, sinon VST ; un effet du Mixer en AU), la plus haute à égalité. Le
    /// format est lu à droite du nom sur la même ligne (colonne « Format »), ou juste après lui dans une ligne lue d'un
    /// seul tenant.
    static func best(_ name: String, prefer: [String], in items: [TextLook.Item]) -> TextLook.Item? {
        let wanted = TextLook.normalized(name)
        guard !wanted.isEmpty else { return nil }
        let hits = items.filter { matches(TextLook.normalized($0.text), wanted) }
        func format(of hit: TextLook.Item) -> String? {
            let text = String(TextLook.normalized(hit.text).drop { !$0.isLetter && !$0.isNumber })
            if text.count > wanted.count {
                return text.dropFirst(wanted.count + 1).split(separator: " ").first.map(String.init)
            }
            let tolerance = max(hit.box.height, 8) * 0.6
            return items.filter { $0.box.minX > hit.box.maxX && abs($0.box.midY - hit.box.midY) < tolerance }
                .sorted { $0.box.minX < $1.box.minX }
                .map { TextLook.normalized($0.text) }
                .first { formats.contains($0) }
        }
        func rank(_ hit: TextLook.Item) -> Int {
            format(of: hit).flatMap { prefer.firstIndex(of: $0) } ?? prefer.count
        }
        return hits.min { (rank($0), $0.box.minY) < (rank($1), $1.box.minY) }
    }

    /// Ordre des formats : instrument (Channel rack) VST3 puis VST ; effet (Mixer) AU d'abord (demande du 03/11).
    static func preferredFormats(item: String) -> [String] {
        (item == "Effect" ? ["au", "vst3", "vst", "clap", "fl"] : ["vst3", "vst", "au", "clap", "fl"]).map(TextLook.normalized)
    }

    /// Pure (testée) : le bouton « Find » en bas de la liste de FL (lu dans la fenêtre), s'il y est.
    static func findButton(in items: [TextLook.Item], height: CGFloat) -> TextLook.Item? {
        let wanted = TextLook.normalized("Find")
        return items.first { TextLook.normalized($0.text) == wanted && $0.box.minY > height - 80 }
    }

    /// Colonne « Format » de la liste de FL, à la forme de comparaison (1 lu « l »).
    static let formats: Set<String> = ["vst", "vst2", "vst3", "au", "fl", "clap", "aax"].map(TextLook.normalized)
        .reduce(into: []) { $0.insert($1) }
}

extension MacroEffectsMac {
    /// Pages de la liste lues au plus (une page : ce qu'on voit, puis la molette).
    static let pluginListPages = 15

    func addFromPluginList(_ plugin: String, item: String, ctx: Context) -> StepResult {
        // D'abord le menu Add de FL lui-même (03/11, « il faut trouver une autre solution ») : un plugin qui y est
        // (favori de FL, comme Analog Lab V dans la vidéo) est pris là, comme à la main, sans lire l'écran ni
        // parcourir la liste. Rien n'est ajouté aux listes de FL.
        let pid = ctx.pid
        switch MenuBarAX.press(pid: pid, titles: ["Add", item, plugin], stop: stopReason,
                               click: { [self] p in postClick(at: p, right: false, pid: pid, hoverMs: 60) }) {
        case .done:
            MacroLog.shared.write("PLUGIN", "taken from the Add menu")
            return .ok
        case .cancelled(let why): return .cancel(why)
        case .failed: break                                        // pas dans le menu : « More plugins… »
        }
        guard ScreenLook.available, ScreenLook.allowed else {
            return .fail(String(localized: "lecture de l'écran pas autorisée (Réglages Système › Confidentialité et sécurité › Enregistrement de l'écran) : le plugin ne peut pas être cherché dans « More plugins… » de FL"))
        }
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
        let prefer = PluginListPick.preferredFormats(item: item)
        // Le nom tapé dans la recherche de la liste (« Find », demande du 03/11) plutôt que de la faire défiler : la
        // ligne arrive tout de suite. Sans « Find » lisible, la liste défile comme avant.
        if let why = searchPluginList(list, plugin: plugin, pid: pid) { closePluginList(list, pid: pid); return .cancel(why) }
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
            if let hit = PluginListPick.best(plugin, prefer: prefer, in: items) {
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

    /// « Find » de la liste cliqué, puis le nom du plugin tapé : dans la petite fenêtre que FL ouvre alors (validée par
    /// Entrée), ou dans la liste elle-même. Rien si « Find » n'est pas lu. nil, ou la raison d'un arrêt (Échap).
    func searchPluginList(_ list: WinInfo, plugin: String, pid: Int32) -> String? {
        guard let image = ScreenLook.captureImage(windowNumber: list.number, size: list.bounds.size, scale: 2),
              let find = PluginListPick.findButton(in: TextLook.read(image, size: list.bounds.size),
                                                   height: list.bounds.height) else {
            MacroLog.shared.write("PLUGIN", "no Find button read: the list scrolls")
            return nil
        }
        if let why = stopReason() { return why }
        let before = WinSnapshot.take(pid: pid).numbers
        postClick(at: CGPoint(x: list.bounds.minX + find.center.x, y: list.bounds.minY + find.center.y), right: false,
                  pid: pid, hoverMs: 60)
        let prompt: WinInfo?
        switch WindowWait.newWindow(pid: pid, excluding: before, timeout: 0.8, accept: { _ in true }, stop: stopReason) {
        case .success(let w): prompt = w
        case .failure(.stopped(let why)): return why
        case .failure(.timeout): prompt = nil
        }
        Thread.sleep(forTimeInterval: 0.2)
        guard PresetChooser.type(plugin, pid: pid, stop: stopReason) else { return stopReason() }
        if let prompt {
            postKey(KeyCombo(keyCode: 36), pid: pid)                 // Entrée : la recherche est lancée
            _ = WindowWait.gone(pid: pid, numbers: [prompt.number], timeout: 1.5, stop: { nil })
        }
        MacroLog.shared.write("PLUGIN", "name typed in Find (\(prompt == nil ? "in the list" : "in its window"))")
        Thread.sleep(forTimeInterval: 0.4)
        return nil
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
