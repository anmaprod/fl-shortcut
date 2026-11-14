// « Menu de FL » par les menus DANS la fenêtre de FL (FILE, EDIT… en haut de sa fenêtre), cliqués comme à la main,
// avant la barre des menus de macOS. Retour du propriétaire (04/11) : « Export Stems » (File › Export › All playlist
// tracks › Time selection…) ne marche que par le vrai FILE de FL : FL ne remet à jour l'état grisé de ses éléments qu'à
// l'ouverture de SES menus, jamais pour la barre de macOS (même rouverte, MenuBarAX.reopened). « Ma solution est de
// passer directement dans le logiciel » : comme Windows (titre en haut de FL, puis chaque élément retrouvé à son nom).
// Règle du propriétaire : noms lus dans la seule fenêtre de FL (et ses menus), au moment du clic, avec l'autorisation
// « Enregistrement de l'écran » ; rien n'est gardé, aucun nom dans le journal. Sans l'autorisation, titre absent de la
// fenêtre, ou tout autre accroc : menus refermés, puis la barre des menus de macOS, comme avant.
import AppKit
import CoreGraphics

extension MacroEffectsMac {
    enum WindowMenuOutcome: Equatable {
        case done
        case cancelled(String)
        /// Élément grisé dans le menu de FL (lu à son ouverture : l'état est à jour).
        case greyed
        /// Pas par la fenêtre (pas d'autorisation, titre introuvable, menu pas ouvert…) : la barre de macOS.
        case unavailable
    }

    /// Pure (testée) : « Time selection... » → « Time selection » (points de suite et « … » retirés).
    static func plainMenuText(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        while t.hasSuffix("…") || t.hasSuffix(".") { t.removeLast() }
        return t.trimmingCharacters(in: .whitespaces)
    }

    /// Pure (testée) : reste d'une ligne de menu après son nom : un raccourci affiché (« Ctrl+S », « ⇧⌘S », « F5 »).
    static func isShortcutText(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return true }
        guard t.count <= 16 else { return false }
        if t.contains(where: { "⌘⇧⌥⌃+".contains($0) }) { return true }
        return t.range(of: #"^F\d{1,2}$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Pure (testée) : l'élément voulu parmi les textes lus dans un menu de FL (même nom à la forme de comparaison
    /// près, ou ce nom suivi de son raccourci affiché) ; le plus haut s'il y est plusieurs fois.
    static func menuEntry(_ wanted: String, in items: [TextLook.Item]) -> TextLook.Item? {
        let w = TextLook.normalized(plainMenuText(wanted))
        guard !w.isEmpty else { return nil }
        let exact = items.filter { TextLook.normalized(plainMenuText($0.text)) == w }
        if let top = exact.min(by: { $0.box.minY < $1.box.minY }) { return top }
        // Le nom (autant de mots que lui) puis le raccourci affiché, pris dans le texte lu tel quel (la forme de
        // comparaison change « F10 » en « flo »).
        let count = w.split(separator: " ").count
        let prefixed = items.filter { item in
            let words = item.text.split(whereSeparator: \.isWhitespace)
            guard words.count > count,
                  TextLook.normalized(plainMenuText(words.prefix(count).joined(separator: " "))) == w else { return false }
            return isShortcutText(words.dropFirst(count).joined(separator: " "))
        }
        return prefixed.min(by: { $0.box.minY < $1.box.minY })
    }

    /// Pure (testée) : le titre de menu de FL (« FILE » pour « File ») parmi les textes du haut de sa fenêtre, le plus
    /// à gauche.
    static func menuTitle(_ wanted: String, in items: [TextLook.Item]) -> TextLook.Item? {
        let w = TextLook.normalized(plainMenuText(wanted))
        return items.filter { TextLook.normalized($0.text) == w }.min(by: { $0.box.minX < $1.box.minX })
    }

    /// Pure (testée) : un texte de menu grisé est sombre : moins de `limit` (sur 255) pour ses pixels les plus clairs.
    static func looksGreyed(brightest: UInt8, limit: UInt8 = 170) -> Bool { brightest < limit }

    /// Les pixels les plus clairs (95e centile) du cadre `box` (points) d'une image de fenêtre de `size` points.
    static func brightest(in image: CGImage, size: CGSize, box: CGRect) -> UInt8? {
        let sx = CGFloat(image.width) / size.width, sy = CGFloat(image.height) / size.height
        let r = CGRect(x: box.minX * sx, y: box.minY * sy, width: box.width * sx, height: box.height * sy).integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !r.isNull, r.width >= 2, r.height >= 2, let crop = image.cropping(to: r) else { return nil }
        let w = Int(r.width), h = Int(r.height)
        var pixels = [UInt8](repeating: 0, count: w * h)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        let sorted = pixels.sorted()
        return sorted[min(sorted.count - 1, sorted.count * 95 / 100)]
    }

    /// Fenêtre principale de FL : celle du cadre de départ de la macro, sinon la plus grande au niveau des fenêtres.
    static func mainWindow(_ snap: WinSnapshot, frame: CGRect?) -> WinInfo? {
        if let frame, let w = snap.fl.first(where: { $0.layer == 0 && $0.bounds == frame }) { return w }
        return snap.fl.filter { $0.layer == 0 }.max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }

    /// Menu de FL ouvert après `before` (fenêtres d'avant), attendu jusqu'à `timeoutMs` ; nil : rien d'ouvert.
    func newMenu(after before: Set<Int>, ctx: Context, timeoutMs: Int) -> WinInfo? {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000)
        repeat {
            if let menu = WinSnapshot.take(pid: ctx.pid).fl.first(where: { !before.contains($0.number) && $0.isMenuLike && $0.layer > 8 }) {
                Thread.sleep(forTimeInterval: 0.12)                    // le menu se dessine
                return menu
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline && stopReason() == nil
        return nil
    }

    /// Referme les menus de FL ouverts par ce chemin (Échap, quatre fois au plus).
    func closeWindowMenus(opened before: Set<Int>, ctx: Context) {
        for _ in 0..<4 {
            let open = WinSnapshot.take(pid: ctx.pid).fl.contains { !before.contains($0.number) && $0.isMenuLike && $0.layer > 8 }
            if !open { return }
            postKey(KeyCombo(keyCode: 53), pid: ctx.pid)
            Thread.sleep(forTimeInterval: 0.15)
        }
    }

    /// Le chemin `titles` par les menus dans la fenêtre de FL : le titre (FILE…) puis chaque élément, cliqués comme à
    /// la main, retrouvés à leur nom au moment du clic. Journal : les étapes, jamais un nom.
    func windowMenu(titles: [String], ctx: Context) -> WindowMenuOutcome {
        guard titles.count >= 2, Self.canRead else { return .unavailable }
        let start = WinSnapshot.take(pid: ctx.pid)
        guard let main = Self.mainWindow(start, frame: ctx.frame), main.number > 0,
              let image = ScreenLook.captureImage(windowNumber: main.number, size: main.bounds.size, scale: 2) else {
            MacroLog.shared.write("MENU", "window menu: FL window unreadable, menu bar used")
            return .unavailable
        }
        let f = main.bounds
        let strip = CGRect(x: 0, y: 0, width: min(f.width, 760), height: min(f.height, 96))
        guard let title = Self.menuTitle(titles[0], in: TextLook.read(image, size: f.size, region: strip)) else {
            MacroLog.shared.write("MENU", "window menu: title not found in FL window, menu bar used")
            return .unavailable
        }
        let initial = start.numbers
        var before = initial
        postClick(at: CGPoint(x: f.minX + title.center.x, y: f.minY + title.center.y), right: false, pid: ctx.pid, hoverMs: 60)
        for (step, wanted) in titles.dropFirst().enumerated() {
            if let why = stopReason() {
                closeWindowMenus(opened: initial, ctx: ctx)
                return .cancelled(why)
            }
            guard let menu = newMenu(after: before, ctx: ctx, timeoutMs: 1500) else {
                MacroLog.shared.write("MENU", "window menu: level \(step + 1) not opened, menu bar used")
                closeWindowMenus(opened: initial, ctx: ctx)
                return .unavailable
            }
            // Un menu de FL peut se remplir juste après son ouverture : lu jusqu'à trois fois.
            var found: (item: TextLook.Item, shot: CGImage)?
            for attempt in 0..<3 where found == nil {
                if attempt > 0 { Thread.sleep(forTimeInterval: 0.25) }
                guard let shot = ScreenLook.captureImage(windowNumber: menu.number, size: menu.bounds.size, scale: 2) else { continue }
                if let item = Self.menuEntry(wanted, in: TextLook.read(shot, size: menu.bounds.size)) { found = (item, shot) }
            }
            guard let hit = found else {
                MacroLog.shared.write("MENU", "window menu: item of level \(step + 1) not found, menu bar used")
                closeWindowMenus(opened: initial, ctx: ctx)
                return .unavailable
            }
            if let light = Self.brightest(in: hit.shot, size: menu.bounds.size, box: hit.item.box), Self.looksGreyed(brightest: light) {
                MacroLog.shared.write("MENU", "window menu: item of level \(step + 1) greyed (\(light))")
                closeWindowMenus(opened: initial, ctx: ctx)
                return .greyed
            }
            before = WinSnapshot.take(pid: ctx.pid).numbers
            let p = CGPoint(x: menu.bounds.minX + hit.item.center.x, y: menu.bounds.minY + hit.item.center.y)
            postClick(at: p, right: false, pid: ctx.pid, hoverMs: 80)
        }
        MacroLog.shared.write("MENU", "window menu: \(titles.count) levels clicked in FL window")
        return .done
    }
}
