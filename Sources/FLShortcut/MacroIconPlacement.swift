// Pose d'une icône de FL sur l'élément sélectionné, par la fenêtre de FL (l'API de FL ne lit ni ne pose les
// icônes) : F2 → fenêtre « Rename, color and icon » → clic sur son bouton de l'icône (montré une fois par
// l'utilisateur, gardé par rapport au coin haut-droit de cette fenêtre : préférence macroSpots.v2.iconButton) →
// grille des icônes → clic au centre de la case → Entrée referme la fenêtre du nom sans le changer.
// Aucune lecture de l'écran : seulement la liste des fenêtres de FL (numéro, cadre). Échap seulement tant qu'une
// fenêtre ouverte par la pose est encore là.
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
    /// Pause ; false après Échap ou quand FL n'est plus au premier plan.
    func wait(_ seconds: TimeInterval) -> Bool
    /// Clic de l'utilisateur dans `window`, guidé par une bulle ; nil s'il ne vient pas.
    func learnClick(in window: WinInfo, hint: String) -> CGPoint?
}

enum IconPlacement {
    enum Failure: Error, Equatable {
        case stopped, noNameWindow, notShown, clickRefused, noGrid, gridStayed, nameStayed

        var message: String {
            switch self {
            case .stopped: return "arrêtée (Échap, ou FL n'est plus devant)"
            case .noNameWindow: return "la fenêtre du nom de FL (F2) ne s'est pas ouverte : sélectionne une seule piste ou un seul canal"
            case .notShown: return "clic sur l'icône de la fenêtre du nom non montré"
            case .clickRefused: return "clic refusé (FL fermé ou couvert)"
            case .noGrid: return "la grille des icônes ne s'est pas ouverte : relance pour montrer de nouveau le bouton de l'icône"
            case .gridStayed: return "la grille des icônes est restée ouverte (case vide ?)"
            case .nameStayed: return "la fenêtre du nom de FL est restée ouverte"
            }
        }
    }

    /// Bouton de l'icône dans la fenêtre du nom, relatif au coin haut-droit de cette fenêtre (taille retenue).
    struct Spot: Codable, Equatable {
        var fromTopRight: CGVector
        var windowSize: CGSize

        var isValid: Bool {
            func ok(_ v: CGFloat) -> Bool { v.isFinite && abs(v) <= 2000 }
            return ok(fromTopRight.dx) && ok(fromTopRight.dy) && fromTopRight.dx <= 0 && fromTopRight.dy >= 0
                && windowSize.width > 0 && windowSize.height > 0
                && -fromTopRight.dx <= windowSize.width && fromTopRight.dy <= windowSize.height
        }

        func point(in w: CGRect) -> CGPoint { CGPoint(x: w.maxX + fromTopRight.dx, y: w.minY + fromTopRight.dy) }
    }

    static let spotKey = "macroSpots.v2.iconButton"

    static func loadSpot(defaults: UserDefaults = .standard) -> Spot? {
        guard let data = defaults.data(forKey: spotKey),
              let spot = try? JSONDecoder().decode(Spot.self, from: data), spot.isValid else { return nil }
        return spot
    }

    static func saveSpot(_ spot: Spot, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(spot) { defaults.set(data, forKey: spotKey) }
    }

    static func forgetSpot(defaults: UserDefaults = .standard) { defaults.removeObject(forKey: spotKey) }

    static let f2 = KeyCombo(keyCode: 120)
    static let enter = KeyCombo(keyCode: 36)
    static let escape = KeyCombo(keyCode: 53)
    static let hint = "Une seule fois : clique sur l'icône à droite du nom."

    /// Fenêtre du nom plausible : petite fenêtre de FL, plus haute qu'une ligne de menu.
    static func isNameWindow(_ w: WinInfo) -> Bool {
        w.bounds.width >= 120 && w.bounds.height >= 40 && w.bounds.width <= 1400 && w.bounds.height <= 1000
    }

    /// Grille plausible : 15 rangées de cases carrées de L / 14 sous une barre de titres de 0 à 80 points.
    static func isGrid(_ w: WinInfo) -> Bool {
        let side = w.bounds.width / CGFloat(FLIconGrid.columns)
        let header = w.bounds.height - CGFloat(FLIconGrid.rows) * side
        return side >= 10 && header >= 0 && header <= 80
    }

    /// Pose `icon` sur l'élément sélectionné dans la page de FL devant ; nil si c'est fait.
    static func place(_ icon: FLIcon, driver: IconPlacementDriver, defaults: UserDefaults = .standard) -> Failure? {
        let base = Set(driver.windows().map(\.number))
        driver.press(f2)
        let name: WinInfo
        switch awaitWindow(excluding: base, missing: .noNameWindow, driver: driver, accept: isNameWindow) {
        case .success(let w): name = w
        case .failure(let failure): return failure
        }
        if let spot = loadSpot(defaults: defaults), MacroSpots.sameSize(name.bounds.size, spot.windowSize) {
            guard driver.click(spot.point(in: name.bounds)) else { return close([name], driver: driver, .clickRefused) }
        } else {
            // Le clic de l'utilisateur ouvre lui-même la grille : rien à recliquer.
            guard let p = driver.learnClick(in: name, hint: hint) else {
                return close([name], driver: driver, driver.wait(0.01) ? .notShown : .stopped)
            }
            let spot = Spot(fromTopRight: CGVector(dx: p.x - name.bounds.maxX, dy: p.y - name.bounds.minY),
                            windowSize: name.bounds.size)
            if spot.isValid { saveSpot(spot, defaults: defaults) }
        }
        let grid: WinInfo
        switch awaitWindow(excluding: base.union([name.number]), missing: .noGrid, driver: driver, accept: isGrid) {
        case .success(let w): grid = w
        case .failure(let failure):
            if failure == .noGrid { forgetSpot(defaults: defaults) }        // à montrer de nouveau
            return close([name], driver: driver, failure)
        }
        guard driver.click(FLIconGrid.center(of: icon, in: grid.bounds)) else {
            return close([grid, name], driver: driver, .clickRefused)
        }
        guard awaitGone(grid.number, driver: driver) else { return close([grid, name], driver: driver, .stopped) }
        if isOpen(grid.number, driver) { return close([grid, name], driver: driver, .gridStayed) }
        driver.press(enter)
        guard awaitGone(name.number, driver: driver) else { return close([name], driver: driver, .stopped) }
        if isOpen(name.number, driver) { return close([name], driver: driver, .nameStayed) }
        return nil
    }

    static func isOpen(_ number: Int, _ driver: IconPlacementDriver) -> Bool {
        driver.windows().contains { $0.number == number }
    }

    /// Ferme, de l'avant vers l'arrière, les fenêtres ouvertes par la pose qui sont encore là (Échap, une fois
    /// chacune), puis renvoie `failure`.
    static func close(_ opened: [WinInfo], driver: IconPlacementDriver, _ failure: Failure) -> Failure {
        for w in opened where isOpen(w.number, driver) {
            driver.press(escape)
            _ = awaitGone(w.number, driver: driver, timeout: 0.5)
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

    /// La fenêtre `number` a disparu (1 s au plus) ; false seulement après Échap.
    static func awaitGone(_ number: Int, driver: IconPlacementDriver, timeout: TimeInterval = 1) -> Bool {
        var waited: TimeInterval = 0
        while driver.windows().contains(where: { $0.number == number }) && waited < timeout {
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
    func wait(_ seconds: TimeInterval) -> Bool { fx.pause(Int(seconds * 1000), pid: fx.pid) == .ok }

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
    /// Icône de FL sur l'élément sélectionné (bloc « Nom et couleur », Organiser). `alsoColored` : le nom ou la
    /// couleur est déjà posé, une icône manquée n'est alors qu'un avertissement.
    func placeIcon(_ icon: FLIcon, alsoColored: Bool) -> StepResult {
        guard waitForKeyboardIdle(timeout: 1.5) else { return .cancel("relâche les touches du raccourci") }
        MacroLog.shared.write("FL", "icon \(icon.code)")
        defer { restoreCursor() }
        guard let failure = IconPlacement.place(icon, driver: FLIconDriver(fx: self)) else { return .ok }
        MacroLog.shared.write("FL", "icon not placed: \(failure)")
        if failure == .stopped { return .cancel(failure.message) }
        return alsoColored ? .warn("icône non posée : " + failure.message) : .fail("icône non posée : " + failure.message)
    }
}
