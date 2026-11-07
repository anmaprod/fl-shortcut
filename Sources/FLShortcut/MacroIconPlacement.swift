// Pose d'une icône de FL sur un élément (son du Channel rack, piste du Mixer, piste de la Playlist), par la fenêtre de
// FL (l'API de FL ne lit ni ne pose les icônes) : clic droit sur l'élément → « Change icon… » dans son menu → grille
// des icônes → clic au centre de la case. Relevé sur le FL du propriétaire (vidéos du 30/10 14 h et du 31/10 2 h) :
// le bouton à gauche du nom dans « Rename, color and icon » (F2) propose des NOMS tout faits (Drums, Kick…), pas la
// grille ; « Change icon… » est dans le menu du clic droit du Channel rack, du Mixer et de la Playlist, et ouvre la
// grille. « Change icon… » est retrouvé à son nom dans le menu (lecture de la seule fenêtre du menu de FL, avec
// l'autorisation « Enregistrement de l'écran ») ; un menu lu sans lui est refermé (le clic droit n'était pas sur un
// son ni une piste). Sans l'autorisation : place retenue pour un menu de cette taille, sinon montrée une fois par
// l'utilisateur. Relevé du 16/10 : la grille ne se ferme PAS avec Échap ; seul le choix d'une case la ferme à coup
// sûr. Une grille restée ouverte est donc signalée, jamais refermée en cliquant à l'aveugle.
import AppKit
import CoreGraphics
import Foundation

/// Ce dont la pose a besoin : le vrai FL (FLIconDriver), ou un faux dans les tests.
protocol IconPlacementDriver {
    /// Fenêtres de FL, de l'avant vers l'arrière.
    func windows() -> [WinInfo]
    func press(_ key: KeyCombo)
    /// Clic gauche ; false s'il est refusé (hors de FL, FL couvert, Échap).
    func click(_ point: CGPoint) -> Bool
    /// Clic droit ; false s'il est refusé.
    func rightClick(_ point: CGPoint) -> Bool
    /// Pause ; false après Échap ou quand FL n'est plus au premier plan.
    func wait(_ seconds: TimeInterval) -> Bool
    /// L'élément de menu `label` lu dans la fenêtre `menu`.
    func readItem(_ label: String, in menu: WinInfo) -> IconPlacement.MenuRead
    /// Clic de l'utilisateur dans `window`, guidé par une bulle ; nil s'il ne vient pas.
    func learnClick(in window: WinInfo, hint: String) -> CGPoint?
    /// Journal de diagnostic (fenêtres vues, points cliqués) ; jamais un nom de piste.
    func note(_ text: String)
}

extension IconPlacementDriver {
    func note(_ text: String) {}
    func readItem(_ label: String, in menu: WinInfo) -> IconPlacement.MenuRead { .unreadable }
}

enum IconPlacement {
    enum Failure: Error, Equatable {
        case stopped, noMenu, notInMenu, notShown, clickRefused, noGrid, gridStayed

        var message: String {
            switch self {
            case .stopped: return String(localized: "arrêtée (Échap, ou FL n'est plus devant)")
            case .noMenu:
                return String(localized: "le menu du clic droit de FL ne s'est pas ouvert : clique d'abord sur le nom d'un son, d'une piste du Mixer ou de la Playlist, puis relance")
            case .notInMenu:
                return String(localized: "« Change icon… » n'est pas dans ce menu de FL : clique d'abord sur le nom d'un son, d'une piste du Mixer ou de la Playlist, puis relance")
            case .notShown: return String(localized: "« Change icon… » non montré")
            case .clickRefused: return String(localized: "clic refusé (FL fermé ou couvert)")
            case .noGrid:
                return String(localized: "la grille des icônes ne s'est pas ouverte : relance pour montrer de nouveau « Change icon… »")
            case .gridStayed:
                return String(localized: "la grille des icônes de FL est restée ouverte : choisis une case ou clique à côté")
            }
        }
    }

    /// Lecture d'un menu de FL : l'élément cherché, son absence (menu lu sans lui), ou rien de lu (autorisation
    /// « Enregistrement de l'écran » absente, fenêtre non capturée).
    enum MenuRead: Equatable {
        case found(CGPoint)
        case absent
        case unreadable
    }

    /// « Change icon… » dans un menu de FL, par rapport au coin haut-gauche du menu (taille du menu retenue : le
    /// menu du Channel rack, du Mixer et de la Playlist n'ont pas la même).
    struct Spot: Codable, Equatable {
        var fromTopLeft: CGVector
        var menuSize: CGSize

        var isValid: Bool {
            func ok(_ v: CGFloat) -> Bool { v.isFinite && v >= 0 && v <= 4000 }
            return ok(fromTopLeft.dx) && ok(fromTopLeft.dy) && menuSize.width > 0 && menuSize.height > 0
                && fromTopLeft.dx <= menuSize.width && fromTopLeft.dy <= menuSize.height
        }

        func point(in w: CGRect) -> CGPoint { CGPoint(x: w.minX + fromTopLeft.dx, y: w.minY + fromTopLeft.dy) }
    }

    static let spotKey = "macroSpots.v3.changeIcon"
    /// Ancienne place (bouton de la fenêtre F2) : ne sert plus, effacée avec les autres places apprises.
    static let oldSpotKey = "macroSpots.v2.iconButton"
    /// Texte de l'élément dans le menu de FL (sans les points de suspension).
    static let itemLabel = "Change icon"

    /// Pur (testé) : l'élément `label` parmi les textes lus dans un menu : une ligne qui commence par lui (« Change
    /// icon… », « Change icon... »), pas plus longue que lui et ses points de suspension.
    static func menuItem(_ label: String, in items: [TextLook.Item]) -> TextLook.Item? {
        let wanted = TextLook.normalized(label)
        return items.filter {
            let text = TextLook.normalized($0.text).trimmingCharacters(in: CharacterSet(charactersIn: ".…: "))
            return text == wanted
        }.min { $0.box.minY < $1.box.minY }
    }

    /// Places retenues, une par taille de menu.
    static func loadSpots(defaults: UserDefaults = .standard) -> [Spot] {
        guard let data = defaults.data(forKey: spotKey),
              let spots = try? JSONDecoder().decode([Spot].self, from: data) else { return [] }
        return spots.filter(\.isValid)
    }

    static func loadSpot(forMenu size: CGSize, defaults: UserDefaults = .standard) -> Spot? {
        loadSpots(defaults: defaults).first { MacroSpots.sameSize($0.menuSize, size) }
    }

    static func saveSpot(_ spot: Spot, defaults: UserDefaults = .standard) {
        guard spot.isValid else { return }
        var spots = loadSpots(defaults: defaults).filter { !MacroSpots.sameSize($0.menuSize, spot.menuSize) }
        spots.append(spot)
        if let data = try? JSONEncoder().encode(Array(spots.suffix(8))) { defaults.set(data, forKey: spotKey) }
    }

    static func forgetSpot(forMenu size: CGSize, defaults: UserDefaults = .standard) {
        let spots = loadSpots(defaults: defaults).filter { !MacroSpots.sameSize($0.menuSize, size) }
        if let data = try? JSONEncoder().encode(spots) { defaults.set(data, forKey: spotKey) }
    }

    static func forgetSpot(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: spotKey)
        defaults.removeObject(forKey: oldSpotKey)
    }

    static let escape = KeyCombo(keyCode: 53)
    static let hint = String(localized: "Une seule fois : clique sur « Change icon… » dans ce menu.")

    /// Menu de FL plausible : une fenêtre devant (niveau des menus), de la taille d'un menu, pas la grille.
    static func isMenu(_ w: WinInfo) -> Bool { w.layer > 8 && w.isMenuLike && !isGrid(w) }

    /// Grille plausible : 15 rangées de cases carrées de L / 14 sous une barre de titres de 0 à 80 points.
    static func isGrid(_ w: WinInfo) -> Bool {
        let side = w.bounds.width / CGFloat(FLIconGrid.columns)
        let header = w.bounds.height - CGFloat(FLIconGrid.rows) * side
        return side >= 10 && header >= 0 && header <= 80
    }

    /// Pose `icon` sur l'élément sous `target` (son nom dans FL) ; nil si c'est fait.
    static func place(_ icon: FLIcon, at target: CGPoint, driver: IconPlacementDriver,
                      defaults: UserDefaults = .standard) -> Failure? {
        let base = Set(driver.windows().map(\.number))
        guard driver.rightClick(target) else { return .clickRefused }
        let menu: WinInfo
        switch awaitWindow(excluding: base, missing: .noMenu, driver: driver, accept: isMenu) {
        case .success(let w): menu = w
        case .failure(let failure):
            driver.note("no menu after the right-click at \(target.logText); new windows: \(fresh(base, driver))")
            return failure
        }
        driver.note("menu \(menu)")
        func spot(_ p: CGPoint) -> Spot {
            Spot(fromTopLeft: CGVector(dx: p.x - menu.bounds.minX, dy: p.y - menu.bounds.minY), menuSize: menu.bounds.size)
        }
        switch driver.readItem(itemLabel, in: menu) {
        case .found(let p):
            driver.note("Change icon (read) at \(p.logText)")
            guard driver.click(p) else { return close([menu], driver: driver, .clickRefused) }
            saveSpot(spot(p), defaults: defaults)
        case .absent:
            driver.note("no Change icon in this menu")
            return close([menu], driver: driver, .notInMenu)
        case .unreadable:
            if let learned = loadSpot(forMenu: menu.bounds.size, defaults: defaults) {
                let p = learned.point(in: menu.bounds)
                driver.note("Change icon (learned) at \(p.logText)")
                guard driver.click(p) else { return close([menu], driver: driver, .clickRefused) }
            } else {
                // Le clic de l'utilisateur ouvre lui-même la grille : rien à recliquer.
                guard let p = driver.learnClick(in: menu, hint: hint) else {
                    return close([menu], driver: driver, driver.wait(0.01) ? .notShown : .stopped)
                }
                driver.note("Change icon shown at \(p.logText)\(spot(p).isValid ? "" : " — not kept")")
                saveSpot(spot(p), defaults: defaults)
            }
        }
        let grid: WinInfo
        switch awaitWindow(excluding: base.union([menu.number]), missing: .noGrid, driver: driver, accept: isGrid) {
        case .success(let w): grid = w
        case .failure(let failure):
            driver.note("no icon grid; new windows: \(fresh(base, driver))")
            if failure == .noGrid { forgetSpot(forMenu: menu.bounds.size, defaults: defaults) }   // à montrer de nouveau
            return close([menu], driver: driver, failure)
        }
        let cell = FLIconGrid.center(of: icon, in: grid.bounds)
        driver.note("icon grid \(grid) → cell \(icon.code) at \(cell.logText)")
        guard driver.click(cell) else { return close([grid, menu], driver: driver, .clickRefused) }
        // Relevé sur le FL de l'utilisateur (16/10) : la grille garde son numéro le temps de son animation de
        // fermeture (44 × 44 points juste après le choix) ; elle compte comme fermée dès qu'elle n'en a plus la forme.
        guard awaitGone(grid.number, driver: driver, still: isGrid) else {
            return close([grid, menu], driver: driver, .stopped)
        }
        if isOpen(grid.number, driver, still: isGrid) { return close([grid], driver: driver, .gridStayed) }
        driver.note("icon \(icon.code) placed")
        return nil
    }

    /// La fenêtre `number` est là et répond encore à `still` (sa forme : une grille qui se referme n'en est plus une).
    static func isOpen(_ number: Int, _ driver: IconPlacementDriver,
                       still: (WinInfo) -> Bool = { _ in true }) -> Bool {
        driver.windows().contains { $0.number == number && still($0) }
    }

    /// Fenêtres de FL absentes de `base` (journal).
    static func fresh(_ base: Set<Int>, _ driver: IconPlacementDriver) -> String {
        let windows = driver.windows().filter { !base.contains($0.number) }
        return windows.isEmpty ? "none" : windows.map(\.description).joined(separator: ", ")
    }

    /// Ferme, de l'avant vers l'arrière, les fenêtres ouvertes par la pose qui sont encore là (Échap seulement, jamais
    /// de clic ni d'Entrée : une Entrée irait à la grille et pourrait y choisir une case), puis renvoie `failure`.
    static func close(_ opened: [WinInfo], driver: IconPlacementDriver, _ failure: Failure) -> Failure {
        for w in opened {
            // Une grille qui se referme (même numéro, plus sa forme) est déjà fermée.
            let still: (WinInfo) -> Bool = isGrid(w) ? isGrid : { _ in true }
            guard isOpen(w.number, driver, still: still) else { continue }
            driver.press(escape)
            _ = awaitGone(w.number, driver: driver, timeout: 0.5, still: still)
            if isOpen(w.number, driver, still: still) { driver.note("still open: \(w)") }
        }
        return failure
    }

    /// Nouvelle fenêtre de FL acceptée, la plus à l'avant, lue deux fois de suite au même endroit (FL a fini de la
    /// placer) ; `missing` au bout de `timeout`.
    static func awaitWindow(excluding known: Set<Int>, missing: Failure, timeout: TimeInterval = 1.5,
                            driver: IconPlacementDriver, accept: (WinInfo) -> Bool) -> Result<WinInfo, Failure> {
        var waited: TimeInterval = 0
        var candidate: WinInfo?
        while true {
            let best = driver.windows().first { !known.contains($0.number) && accept($0) }
            if let best, best == candidate {
                return .success(best)
            }
            candidate = best
            guard waited < timeout else { return .failure(missing) }
            guard driver.wait(0.03) else { return .failure(.stopped) }
            waited += 0.03
        }
    }

    /// La fenêtre `number` a disparu ou ne répond plus à `still` (1 s au plus) ; false seulement après Échap.
    static func awaitGone(_ number: Int, driver: IconPlacementDriver, timeout: TimeInterval = 1,
                          still: (WinInfo) -> Bool = { _ in true }) -> Bool {
        var waited: TimeInterval = 0
        while isOpen(number, driver, still: still) && waited < timeout {
            guard driver.wait(0.03) else { return false }
            waited += 0.03
        }
        return true
    }
}

/// Le vrai FL : mêmes clics, touches et garde-fous que les macros (événements au seul FL, Échap, FL devant).
final class FLIconDriver: IconPlacementDriver {
    private let fx: MacroEffectsMac

    init(fx: MacroEffectsMac) { self.fx = fx }

    func windows() -> [WinInfo] { WinSnapshot.take(pid: fx.pid).fl }
    func press(_ key: KeyCombo) { fx.postKey(key, pid: fx.pid) }
    func click(_ point: CGPoint) -> Bool { fx.click(at: point, right: false, ctx: fx.ctx) == .ok }
    func rightClick(_ point: CGPoint) -> Bool { fx.click(at: point, right: true, ctx: fx.ctx) == .ok }
    func wait(_ seconds: TimeInterval) -> Bool { fx.pause(Int(seconds * 1000), pid: fx.pid) == .ok }
    func note(_ text: String) { MacroLog.shared.write("ICON", text) }

    /// Lecture de la seule fenêtre du menu, une fois FL fini de le dessiner (deux essais).
    func readItem(_ label: String, in menu: WinInfo) -> IconPlacement.MenuRead {
        guard ScreenLook.allowed else { return .unreadable }
        var read = false
        for attempt in 0..<2 {
            if attempt > 0 { guard wait(0.12) else { return .unreadable } }
            guard let image = ScreenLook.captureImage(windowNumber: menu.number, size: menu.bounds.size, scale: 2)
            else { continue }
            let items = TextLook.read(image, size: menu.bounds.size)
            read = read || !items.isEmpty
            if let item = IconPlacement.menuItem(label, in: items) {
                return .found(CGPoint(x: menu.bounds.minX + item.center.x, y: menu.bounds.minY + item.center.y))
            }
        }
        return read ? .absent : .unreadable
    }

    /// Hors du fil principal seulement (comme l'apprentissage des menus).
    func learnClick(in window: WinInfo, hint: String) -> CGPoint? {
        DispatchQueue.main.sync {
            ClickRecorder.shared.start()
            HintPanel.shared.show(hint, near: CGPoint(x: window.bounds.midX, y: window.bounds.maxY + 60))
        }
        defer { DispatchQueue.main.async { ClickRecorder.shared.stop(); HintPanel.shared.hide() } }
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if fx.shouldStop(fx.pid) != nil { return nil }
            if let sample = ClickRecorder.shared.capturedSamples.first(where: { window.bounds.contains($0.point) }) {
                return sample.point
            }
            Thread.sleep(forTimeInterval: 0.015)
        }
        return nil
    }
}

extension MacroEffectsMac {
    /// Icône de FL sur l'élément sous `target` (son nom dans FL) : dernier clic dans FL (bloc « Nom et couleur »), nom
    /// retrouvé dans la fenêtre de FL (Organiser). `alsoColored` : le nom ou la couleur est déjà posé, une icône
    /// manquée n'est alors qu'un avertissement.
    func placeIcon(_ icon: FLIcon, at target: CGPoint, alsoColored: Bool) -> StepResult {
        guard waitForKeyboardIdle(timeout: 1.5) else { return .cancel(String(localized: "relâche les touches du raccourci")) }
        MacroLog.shared.write("FL", "icon \(icon.code) at \(target.logText)")
        defer { restoreCursor() }
        guard let failure = IconPlacement.place(icon, at: target, driver: FLIconDriver(fx: self)) else { return .ok }
        MacroLog.shared.write("FL", "icon not placed: \(failure)")
        if failure == .stopped { return .cancel(failure.message) }
        return alsoColored ? .warn(String(localized: "icône non posée : ") + failure.message)
                           : .fail(String(localized: "icône non posée : ") + failure.message)
    }
}
