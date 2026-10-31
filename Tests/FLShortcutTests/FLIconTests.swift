import AppKit
import XCTest
@testable import FLShortcut

/// Faux FL pour la pose de l'icône : un clic droit ouvre le menu de l'élément, « Change icon… » le referme et ouvre
/// la grille, un clic dans une case la referme, Échap ferme la fenêtre de devant (jamais la grille, comme sur FL).
private final class FakeIconFL: IconPlacementDriver {
    static let main = WinInfo(number: 1, layer: 0, bounds: CGRect(x: 0, y: 0, width: 1400, height: 900), pid: 7, alpha: 1)
    static let menu = WinInfo(number: 2, layer: 101, bounds: CGRect(x: 400, y: 300, width: 220, height: 400), pid: 7, alpha: 1)
    static let grid = WinInfo(number: 3, layer: 101, bounds: CGRect(x: 420, y: 100, width: 617, height: 677), pid: 7, alpha: 1)
    /// « Change icon… » : 30 points du bord gauche, 80 sous le haut du menu.
    static let changeIcon = CGPoint(x: 430, y: 380)
    static let target = CGPoint(x: 350, y: 140)

    var open: [WinInfo] = [main]
    var events: [String] = []
    var menuOpens = true
    var gridOpens = true
    /// Lecture du menu (autorisation « Enregistrement de l'écran ») : trouvé, absent, ou rien de lu.
    var reading = IconPlacement.MenuRead.found(changeIcon)
    var gridIgnoresEscape = true
    /// Comme sur le vrai FL : après le choix d'une case, la grille garde son numéro, réduite à 44 × 44, le temps de
    /// son animation de fermeture (ici, jusqu'à la fin de l'essai).
    var gridShrinksOnClose = false
    static let closingGrid = WinInfo(number: 3, layer: 101, bounds: CGRect(x: 465, y: 117, width: 44, height: 44), pid: 7, alpha: 1)
    /// Clic montré par l'utilisateur ; nil : il appuie sur Échap.
    var shown: CGPoint? = changeIcon
    private var stopped = false

    func windows() -> [WinInfo] { open }

    func press(_ key: KeyCombo) {
        guard key.keyCode == 53 else {
            events.append("touche \(key.keyCode)")
            return
        }
        events.append("Échap")
        if let front = open.first, front != Self.main, !(front == Self.grid && gridIgnoresEscape) { open.removeFirst() }
    }

    func rightClick(_ p: CGPoint) -> Bool {
        events.append("clic droit")
        if menuOpens { open.insert(Self.menu, at: 0) }
        return true
    }

    func readItem(_ label: String, in menu: WinInfo) -> IconPlacement.MenuRead {
        XCTAssertEqual(label, "Change icon")
        return reading
    }

    func click(_ p: CGPoint) -> Bool {
        let g = Self.grid.bounds
        if open.first == Self.grid, g.contains(p) {
            let side = g.width / 14
            let column = Int((p.x - g.minX) / side), row = Int((p.y - g.minY - (g.height - 15 * side)) / side)
            events.append("case \(column)-\(row)")
            open.removeFirst()
            if gridShrinksOnClose { open.insert(Self.closingGrid, at: 0) }
        } else if open.first == Self.menu, hypot(p.x - Self.changeIcon.x, p.y - Self.changeIcon.y) <= 4 {
            chooseChangeIcon()
        } else {
            events.append("clic ailleurs")
        }
        return true
    }

    /// FL referme le menu, puis ouvre la grille.
    private func chooseChangeIcon() {
        events.append("Change icon")
        open.removeAll { $0 == Self.menu }
        if gridOpens { open.insert(Self.grid, at: 0) }
    }

    func wait(_ seconds: TimeInterval) -> Bool { !stopped }

    func learnClick(in window: WinInfo, hint: String) -> CGPoint? {
        events.append("montré")
        guard let p = shown else {
            stopped = true
            return nil
        }
        open.removeAll { $0 == Self.menu }
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
        // « Reset » n'est pas une icône (retour du 31/10 : il retire l'icône dans FL) : « Aucune ».
        XCTAssertFalse(FLIconGrid.isPickable(try XCTUnwrap(FLIcon(code: "0-0"))))
        XCTAssertTrue(FLIconGrid.isPickable(try XCTUnwrap(FLIcon(code: "1-0"))))
        XCTAssertFalse(FLIconGrid.pickable.contains { $0.column == FLIconGrid.channelColumn || $0.isReset })
        XCTAssertEqual(FLIconGrid.pickable.count, FLIconGrid.table.map(\.count).reduce(0, +) - 1)
        XCTAssertTrue(FLIconGrid.table.allSatisfy { $0.count <= FLIconGrid.rows })
        XCTAssertEqual(FLIconGrid.table.count, FLIconGrid.channelColumn)
        // Les titres couvrent les 12 colonnes proposées (ni Reset ni Channel), chacun au moins une.
        XCTAssertEqual(FLIconPicker.headers.map(\.span).reduce(0, +), FLIconGrid.channelColumn - 1)
        XCTAssertFalse(FLIconPicker.headers.contains { $0.title == "Reset" })
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

    /// Clic droit sur l'élément, « Change icon… » lu dans le menu (sa place retenue pour ce menu), puis la case.
    func testIconByChangeIconInTheMenu() throws {
        let microphone = try XCTUnwrap(FLIcon(code: "7-4"))
        let fl = FakeIconFL()
        XCTAssertNil(IconPlacement.place(microphone, at: FakeIconFL.target, driver: fl, defaults: defaults))
        XCTAssertEqual(fl.events, ["clic droit", "Change icon", "case 7-4"])
        XCTAssertEqual(fl.open, [FakeIconFL.main])
        let spot = try XCTUnwrap(IconPlacement.loadSpot(forMenu: FakeIconFL.menu.bounds.size, defaults: defaults))
        XCTAssertEqual(spot.fromTopLeft, CGVector(dx: 30, dy: 80))
    }

    /// Sans « Enregistrement de l'écran » : la première fois, l'utilisateur montre « Change icon… » (retenu pour un
    /// menu de cette taille) ; ensuite il est cliqué seul.
    func testIconWithoutScreenReading() throws {
        let microphone = try XCTUnwrap(FLIcon(code: "7-4"))
        let first = FakeIconFL()
        first.reading = .unreadable
        XCTAssertNil(IconPlacement.place(microphone, at: FakeIconFL.target, driver: first, defaults: defaults))
        XCTAssertEqual(first.events, ["clic droit", "montré", "case 7-4"])
        XCTAssertEqual(first.open, [FakeIconFL.main])

        let again = FakeIconFL()
        again.reading = .unreadable
        XCTAssertNil(IconPlacement.place(microphone, at: FakeIconFL.target, driver: again, defaults: defaults))
        XCTAssertEqual(again.events, ["clic droit", "Change icon", "case 7-4"])
        XCTAssertEqual(again.open, [FakeIconFL.main])
    }

    /// Menu lu sans « Change icon… » (clic droit ailleurs que sur un nom) : refermé, rien cliqué à l'aveugle, même
    /// avec une place retenue pour un menu de cette taille.
    func testMenuWithoutChangeIconIsClosed() throws {
        IconPlacement.saveSpot(IconPlacement.Spot(fromTopLeft: CGVector(dx: 30, dy: 80),
                                                  menuSize: FakeIconFL.menu.bounds.size), defaults: defaults)
        let fl = FakeIconFL()
        fl.reading = .absent
        XCTAssertEqual(IconPlacement.place(try XCTUnwrap(FLIcon(code: "7-4")), at: FakeIconFL.target, driver: fl,
                                           defaults: defaults), .notInMenu)
        XCTAssertEqual(fl.events, ["clic droit", "Échap"])
        XCTAssertEqual(fl.open, [FakeIconFL.main])
    }

    /// Aucun menu après le clic droit : rien d'autre n'est envoyé (jamais d'Échap à l'aveugle).
    func testNoMenu() throws {
        let fl = FakeIconFL()
        fl.menuOpens = false
        XCTAssertEqual(IconPlacement.place(try XCTUnwrap(FLIcon(code: "7-4")), at: FakeIconFL.target, driver: fl,
                                           defaults: defaults), .noMenu)
        XCTAssertEqual(fl.events, ["clic droit"])
    }

    /// La grille se referme en gardant son numéro (44 × 44, animation) : la pose réussit, sans Échap ni « grille
    /// restée ouverte ».
    func testClosingGridAnimationCountsAsClosed() throws {
        let fl = FakeIconFL()
        fl.gridShrinksOnClose = true
        XCTAssertNil(IconPlacement.place(try XCTUnwrap(FLIcon(code: "7-4")), at: FakeIconFL.target, driver: fl,
                                         defaults: defaults))
        XCTAssertEqual(fl.events, ["clic droit", "Change icon", "case 7-4"])
        XCTAssertEqual(fl.open, [FakeIconFL.closingGrid, FakeIconFL.main])
    }

    /// Grille restée ouverte devant (elle ignore Échap) : rien n'est choisi ni fermé à l'aveugle.
    func testGridThatStaysOpenIsLeftAlone() throws {
        let fl = FakeIconFL()
        fl.open = [FakeIconFL.grid, FakeIconFL.main]
        XCTAssertEqual(IconPlacement.close([FakeIconFL.grid], driver: fl, .gridStayed), .gridStayed)
        XCTAssertEqual(fl.events, ["Échap"])
        XCTAssertEqual(fl.open, [FakeIconFL.grid, FakeIconFL.main])
    }

    /// La grille ne s'ouvre pas avec la place retenue : elle est à montrer de nouveau pour ce menu seulement.
    func testGridMissingForgetsSpot() throws {
        let other = CGSize(width: 300, height: 500)
        IconPlacement.saveSpot(IconPlacement.Spot(fromTopLeft: CGVector(dx: 30, dy: 80),
                                                  menuSize: FakeIconFL.menu.bounds.size), defaults: defaults)
        IconPlacement.saveSpot(IconPlacement.Spot(fromTopLeft: CGVector(dx: 40, dy: 90), menuSize: other),
                               defaults: defaults)
        let fl = FakeIconFL()
        fl.reading = .unreadable
        fl.gridOpens = false
        XCTAssertEqual(IconPlacement.place(try XCTUnwrap(FLIcon(code: "7-4")), at: FakeIconFL.target, driver: fl,
                                           defaults: defaults), .noGrid)
        XCTAssertEqual(fl.events, ["clic droit", "Change icon"], "menu déjà refermé par FL : pas d'Échap")
        XCTAssertNil(IconPlacement.loadSpot(forMenu: FakeIconFL.menu.bounds.size, defaults: defaults))
        XCTAssertNotNil(IconPlacement.loadSpot(forMenu: other, defaults: defaults))
    }

    /// Échap au lieu de montrer « Change icon… » : le menu est refermé, rien n'est retenu.
    func testStopWhileShowing() throws {
        let fl = FakeIconFL()
        fl.reading = .unreadable
        fl.shown = nil
        XCTAssertEqual(IconPlacement.place(try XCTUnwrap(FLIcon(code: "7-4")), at: FakeIconFL.target, driver: fl,
                                           defaults: defaults), .stopped)
        XCTAssertEqual(fl.events, ["clic droit", "montré", "Échap"])
        XCTAssertEqual(fl.open, [FakeIconFL.main])
        XCTAssertTrue(IconPlacement.loadSpots(defaults: defaults).isEmpty)
    }

    /// « Change icon… » parmi les lignes lues du menu de FL (vidéo du 31/10) : pas « Change color… », ni les mots
    /// seuls d'une ligne.
    func testChangeIconReadInMenu() throws {
        func item(_ text: String, y: CGFloat) -> TextLook.Item {
            TextLook.Item(text: text, box: CGRect(x: 8, y: y, width: 90, height: 12))
        }
        let items = [item("Rename, color and icon...", y: 10), item("Change color...", y: 26), item("Random color", y: 42),
                     item("Change", y: 58), item("icon...", y: 58), item("Change icon...", y: 58),
                     item("Cut itself", y: 74)]
        XCTAssertEqual(IconPlacement.menuItem("Change icon", in: items)?.box.minY, 58)
        XCTAssertEqual(IconPlacement.menuItem("Change icon", in: [item("Change icon…", y: 30)])?.box.minY, 30)
        XCTAssertNil(IconPlacement.menuItem("Change icon", in: [item("Change color...", y: 26), item("Change", y: 58)]))
    }

    /// Une place par taille de menu (Channel rack, Mixer, Playlist) ; tout s'oublie avec les autres places apprises.
    func testSpotsPerMenuSize() throws {
        let rack = IconPlacement.Spot(fromTopLeft: CGVector(dx: 30, dy: 80), menuSize: CGSize(width: 290, height: 250))
        let mixer = IconPlacement.Spot(fromTopLeft: CGVector(dx: 25, dy: 60), menuSize: CGSize(width: 200, height: 620))
        XCTAssertTrue(rack.isValid)
        XCTAssertFalse(IconPlacement.Spot(fromTopLeft: CGVector(dx: 300, dy: 80), menuSize: rack.menuSize).isValid)
        XCTAssertEqual(rack.point(in: CGRect(x: 100, y: 200, width: 290, height: 250)), CGPoint(x: 130, y: 280))
        IconPlacement.saveSpot(rack, defaults: defaults)
        IconPlacement.saveSpot(mixer, defaults: defaults)
        XCTAssertEqual(IconPlacement.loadSpot(forMenu: CGSize(width: 290, height: 250), defaults: defaults), rack)
        XCTAssertEqual(IconPlacement.loadSpot(forMenu: CGSize(width: 200, height: 620), defaults: defaults), mixer)
        defaults.set(Data([1]), forKey: IconPlacement.oldSpotKey)
        IconPlacement.forgetSpot(defaults: defaults)
        XCTAssertTrue(IconPlacement.loadSpots(defaults: defaults).isEmpty)
        XCTAssertNil(defaults.object(forKey: IconPlacement.oldSpotKey))
    }
}
