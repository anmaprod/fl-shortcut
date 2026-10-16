import AppKit
import XCTest
@testable import FLShortcut

/// Faux FL pour la pose de l'icône : F2 ouvre la fenêtre du nom, son bouton de l'icône ouvre la grille, un clic dans
/// une case la referme, Entrée referme la fenêtre du nom, Échap ferme la fenêtre de devant.
private final class FakeIconFL: IconPlacementDriver {
    static let main = WinInfo(number: 1, layer: 0, bounds: CGRect(x: 0, y: 0, width: 1400, height: 900), pid: 7, alpha: 1)
    static let name = WinInfo(number: 2, layer: 0, bounds: CGRect(x: 400, y: 300, width: 360, height: 120), pid: 7, alpha: 1)
    static let grid = WinInfo(number: 3, layer: 0, bounds: CGRect(x: 420, y: 100, width: 617, height: 677), pid: 7, alpha: 1)
    /// Bouton de l'icône : 30 points à gauche du bord droit, 30 sous le haut de la fenêtre du nom.
    static let button = CGPoint(x: 730, y: 330)

    var open: [WinInfo] = [main]
    var events: [String] = []
    var f2Opens = true
    var gridOpens = true
    /// FL referme lui-même la fenêtre du nom quand on choisit une case.
    var nameClosesWithGrid = false
    /// Comme sur le vrai FL : Échap ne ferme pas toujours la fenêtre du nom, et jamais la grille.
    var nameIgnoresEscape = false
    var gridIgnoresEscape = false
    /// Clic montré par l'utilisateur ; nil : il appuie sur Échap.
    var shown: CGPoint? = button
    private var stopped = false

    func windows() -> [WinInfo] { open }

    func press(_ key: KeyCombo) {
        switch key.keyCode {
        case 120:
            events.append("F2")
            if f2Opens { open.insert(Self.name, at: 0) }
        case 36:
            events.append("Entrée")
            // Entrée va à la fenêtre de devant : la grille si elle est restée ouverte.
            if open.first == Self.grid { events.append("case choisie par Entrée") } else { open.removeAll { $0.number == Self.name.number } }
        case 53:
            events.append("Échap")
            if let front = open.first, front != Self.main,
               !(front == Self.name && nameIgnoresEscape), !(front == Self.grid && gridIgnoresEscape) { open.removeFirst() }
        default:
            events.append("touche \(key.keyCode)")
        }
    }

    func click(_ p: CGPoint) -> Bool {
        let g = Self.grid.bounds
        if open.first == Self.grid, g.contains(p) {
            let side = g.width / 14
            let column = Int((p.x - g.minX) / side), row = Int((p.y - g.minY - (g.height - 15 * side)) / side)
            events.append("case \(column)-\(row)")
            open.removeFirst()
            if nameClosesWithGrid { open.removeAll { $0.number == Self.name.number } }
        } else if open.first == Self.name, hypot(p.x - Self.button.x, p.y - Self.button.y) <= 4 {
            events.append("bouton de l'icône")
            if gridOpens { open.insert(Self.grid, at: 0) }
        } else {
            events.append("clic ailleurs")
        }
        return true
    }

    func wait(_ seconds: TimeInterval) -> Bool { !stopped }

    func learnClick(in window: WinInfo, hint: String) -> CGPoint? {
        events.append("montré")
        guard let p = shown else {
            stopped = true
            return nil
        }
        if gridOpens { open.insert(Self.grid, at: 0) }
        return p
    }
}

/// Icônes de FL : géométrie de la grille (clic au centre de la case, sans lire l'écran), table des cases, pose par
/// la fenêtre de FL et ligne du bloc.
final class FLIconTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suite = "FLIconTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    /// Grille de FL de 617 × 677 : cases de 617 / 14 de côté sous une barre de titres de 677 − 15 × 617 / 14.
    func testCellCenters() throws {
        let window = CGRect(x: 100, y: 200, width: 617, height: 677)
        let first = FLIconGrid.center(of: try XCTUnwrap(FLIcon(column: 1, row: 0)), in: window)
        XCTAssertEqual(first.x - window.minX, 66.1, accuracy: 0.05)
        XCTAssertEqual(first.y - window.minY, 38.0, accuracy: 0.05)
        let last = FLIconGrid.center(of: try XCTUnwrap(FLIcon(column: 13, row: 14)), in: window)
        XCTAssertEqual(last.x, window.maxX - 617.0 / 28, accuracy: 0.05)
        XCTAssertEqual(last.y, window.maxY - 617.0 / 28, accuracy: 0.05)
        for column in 0..<FLIconGrid.columns {
            for row in 0..<FLIconGrid.rows {
                let icon = try XCTUnwrap(FLIcon(column: column, row: row))
                XCTAssertTrue(window.contains(FLIconGrid.center(of: icon, in: window)), icon.code)
            }
        }
    }

    func testPickerSkipsChannelColumn() throws {
        XCTAssertFalse(FLIconGrid.isPickable(try XCTUnwrap(FLIcon(column: 13, row: 2))))
        XCTAssertTrue(FLIconGrid.isPickable(try XCTUnwrap(FLIcon(column: 12, row: 2))))
        XCTAssertTrue(FLIconGrid.isPickable(try XCTUnwrap(FLIcon(code: "0-0"))))
        XCTAssertFalse(FLIconGrid.pickable.contains { $0.column == FLIconGrid.channelColumn })
        XCTAssertEqual(FLIconGrid.pickable.count, FLIconGrid.table.map(\.count).reduce(0, +))
        XCTAssertTrue(FLIconGrid.table.allSatisfy { $0.count <= FLIconGrid.rows })
        XCTAssertEqual(FLIconGrid.table.count, FLIconGrid.channelColumn)
        // Les titres couvrent les 13 colonnes proposées, chacun au moins une.
        XCTAssertEqual(FLIconPicker.headers.map(\.span).reduce(0, +), FLIconGrid.channelColumn)
        XCTAssertTrue(FLIconPicker.headers.allSatisfy { $0.span >= 1 })
    }

    /// Chaque case est dessinée par un symbole de macOS qui existe.
    func testAllSymbolsExist() throws {
        for icon in FLIconGrid.pickable {
            let cell = try XCTUnwrap(FLIconGrid.cell(icon))
            XCTAssertNotNil(NSImage(systemSymbolName: cell.symbol, accessibilityDescription: nil), "\(icon.code) \(cell.symbol)")
        }
        XCTAssertNotNil(NSImage(systemSymbolName: "square.dashed", accessibilityDescription: nil))
        // Repli pour les symboles d'un macOS plus récent (cible : macOS 13) : présent depuis macOS 11.
        XCTAssertTrue(FLIconGrid.Cell.available(FLIconGrid.Cell.fallbackSymbol))
        XCTAssertEqual(FLIconGrid.Cell(symbol: "pas.un.symbole", name: "x").shownSymbol, FLIconGrid.Cell.fallbackSymbol)
        XCTAssertEqual(FLIconGrid.Cell(symbol: "mic.fill", name: "Microphone").shownSymbol, "mic.fill")
    }

    func testSummaryShowsIcon() throws {
        let red = NameColorPayload.defaultColor
        let icon = try XCTUnwrap(FLIcon(code: "7-4"))
        XCTAssertEqual(NameColorPayload.summary(name: "Kick", color: red, icon: icon), "Kick · #E0453A · icône Microphone")
        XCTAssertEqual(NameColorPayload.summary(name: nil, color: nil, icon: icon), "icône Microphone")
        XCTAssertEqual(NameColorPayload.summary(name: nil, color: nil), "nom et couleur à choisir")
        let body = BlockBody.nameColor(name: nil, color: red, icon: icon)
        XCTAssertEqual(BlockRegistry.spec(.nameColor).resume(body, FakeLayout.qwerty), "couleur #E0453A · icône Microphone")
        let unknown = try XCTUnwrap(FLIcon(code: "3-14"))
        XCTAssertEqual(NameColorPayload.summary(name: nil, color: nil, icon: unknown), "icône 3-14")
    }

    /// Première fois : l'utilisateur montre le bouton de l'icône (retenu par rapport au coin haut-droit de la
    /// fenêtre du nom), puis la case et Entrée ; ensuite le bouton est cliqué seul.
    func testIconStepOrder() throws {
        let microphone = try XCTUnwrap(FLIcon(code: "7-4"))
        let first = FakeIconFL()
        XCTAssertNil(IconPlacement.place(microphone, driver: first, defaults: defaults))
        XCTAssertEqual(first.events, ["F2", "montré", "case 7-4", "Entrée"])
        XCTAssertEqual(first.open, [FakeIconFL.main])
        let spot = try XCTUnwrap(IconPlacement.loadSpot(defaults: defaults))
        XCTAssertEqual(spot.fromTopRight, CGVector(dx: -30, dy: 30))
        XCTAssertEqual(spot.windowSize, FakeIconFL.name.bounds.size)

        let again = FakeIconFL()
        XCTAssertNil(IconPlacement.place(microphone, driver: again, defaults: defaults))
        XCTAssertEqual(again.events, ["F2", "bouton de l'icône", "case 7-4", "Entrée"])
        XCTAssertEqual(again.open, [FakeIconFL.main])
    }

    /// FL referme la fenêtre du nom avec la grille : aucune Entrée envoyée sans elle (elle irait à la page devant).
    func testNoEnterWhenFLClosesTheNameWindow() throws {
        IconPlacement.saveSpot(IconPlacement.Spot(fromTopRight: CGVector(dx: -30, dy: 30),
                                                  windowSize: FakeIconFL.name.bounds.size), defaults: defaults)
        let fl = FakeIconFL()
        fl.nameClosesWithGrid = true
        XCTAssertNil(IconPlacement.place(try XCTUnwrap(FLIcon(code: "7-4")), driver: fl, defaults: defaults))
        XCTAssertEqual(fl.events, ["F2", "bouton de l'icône", "case 7-4"])
        XCTAssertEqual(fl.open, [FakeIconFL.main])
    }

    /// Échap ne ferme pas la fenêtre du nom : Entrée (le nom ne change pas, rien n'a été tapé).
    func testEnterClosesTheNameWindowWhenEscapeDoesNot() throws {
        IconPlacement.saveSpot(IconPlacement.Spot(fromTopRight: CGVector(dx: -30, dy: 30),
                                                  windowSize: FakeIconFL.name.bounds.size), defaults: defaults)
        let fl = FakeIconFL()
        fl.gridOpens = false
        fl.nameIgnoresEscape = true
        XCTAssertEqual(IconPlacement.place(try XCTUnwrap(FLIcon(code: "7-4")), driver: fl, defaults: defaults), .noGrid)
        XCTAssertEqual(fl.events, ["F2", "bouton de l'icône", "Échap", "Entrée"])
        XCTAssertEqual(fl.open, [FakeIconFL.main])
    }

    /// Grille restée ouverte devant (elle ignore Échap) : jamais d'Entrée, qui irait à la grille.
    func testNoEnterWhileTheGridStaysOpen() throws {
        let fl = FakeIconFL()
        fl.open = [FakeIconFL.grid, FakeIconFL.name, FakeIconFL.main]
        fl.gridIgnoresEscape = true
        fl.nameIgnoresEscape = true
        XCTAssertEqual(IconPlacement.close([FakeIconFL.grid, FakeIconFL.name], driver: fl, .gridStayed), .gridStayed)
        XCTAssertEqual(fl.events, ["Échap", "Échap"])
        XCTAssertEqual(fl.open, [FakeIconFL.grid, FakeIconFL.name, FakeIconFL.main], "rien n'est choisi ni fermé à l'aveugle")
    }

    /// Le bouton relevé sur le FL de l'utilisateur : à 9 points du bord gauche d'une fenêtre du nom de 260 × 52.
    func testRealNameWindowSpot() {
        let spot = IconPlacement.Spot(fromTopRight: CGVector(dx: -250, dy: 17), windowSize: CGSize(width: 260, height: 52))
        XCTAssertTrue(spot.isValid)
        XCTAssertEqual(spot.point(in: CGRect(x: 243, y: 421, width: 260, height: 52)), CGPoint(x: 253, y: 438))
    }

    /// La grille ne s'ouvre pas avec le clic retenu : la fenêtre du nom est refermée (Échap) et le clic est à
    /// montrer de nouveau.
    func testGridMissingForgetsSpot() throws {
        IconPlacement.saveSpot(IconPlacement.Spot(fromTopRight: CGVector(dx: -30, dy: 30),
                                                  windowSize: FakeIconFL.name.bounds.size), defaults: defaults)
        let fl = FakeIconFL()
        fl.gridOpens = false
        XCTAssertEqual(IconPlacement.place(try XCTUnwrap(FLIcon(code: "7-4")), driver: fl, defaults: defaults), .noGrid)
        XCTAssertEqual(fl.events, ["F2", "bouton de l'icône", "Échap"])
        XCTAssertEqual(fl.open, [FakeIconFL.main])
        XCTAssertNil(IconPlacement.loadSpot(defaults: defaults))
    }

    func testNoNameWindowAndStop() throws {
        let icon = try XCTUnwrap(FLIcon(code: "7-4"))
        let silent = FakeIconFL()
        silent.f2Opens = false
        XCTAssertEqual(IconPlacement.place(icon, driver: silent, defaults: defaults), .noNameWindow)
        XCTAssertEqual(silent.events, ["F2"], "jamais d'Échap à l'aveugle")

        let escaped = FakeIconFL()
        escaped.shown = nil
        XCTAssertEqual(IconPlacement.place(icon, driver: escaped, defaults: defaults), .stopped)
        XCTAssertEqual(escaped.events, ["F2", "montré", "Échap"])
        XCTAssertEqual(escaped.open, [FakeIconFL.main])
        XCTAssertNil(IconPlacement.loadSpot(defaults: defaults))
    }
}
