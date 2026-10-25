import CoreGraphics
import XCTest
@testable import FLShortcut

/// « Enregistrer des clics » : chaque clic devient un bloc, d'après les fenêtres de FL retenues juste avant lui.
final class MacroClickSequenceTests: XCTestCase {
    private func win(_ n: Int, _ layer: Int, _ r: CGRect) -> WinInfo {
        WinInfo(number: n, layer: layer, bounds: r, pid: 42, alpha: 1)
    }

    private func click(_ x: CGFloat, _ y: CGFloat, _ windows: [WinInfo], right: Bool = false,
                       menu: MenuBarAX.Hit? = nil) -> RecordedClick {
        RecordedClick(point: CGPoint(x: x, y: y), right: right, windows: windows, menu: menu)
    }

    /// OPTIONS dans la fenêtre de FL, « Audio settings » dans son menu, boutons de la fenêtre des réglages (niveau 8),
    /// puis le même menu par la barre des menus de macOS ; un clic hors de FL est ignoré.
    func testRecordedClicksBecomeBlocks() {
        let main = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let menu = CGRect(x: 120, y: 60, width: 200, height: 120)
        let settings = CGRect(x: 400, y: 200, width: 520, height: 428)
        let alone = [win(1, 0, main)]
        let withMenu = [win(7, 101, menu), win(1, 0, main)]
        let withSettings = [win(9, 8, settings), win(1, 0, main)]
        let r = ClickSequenceCompiler.compile([
            click(150, 40, alone),
            click(140, 100, withMenu),
            click(430, 260, withSettings),
            click(900, 600, withSettings, right: true),
            click(60, 10, alone, menu: .bar("Options")),
            click(80, 60, alone, menu: .item(["Options", "Audio settings"])),
            click(2000, 10, alone),
        ])
        XCTAssertEqual(r.blocks, [
            .click(.flWindow(corner: .topLeft, dx: 150, dy: 15, size: main.size), button: .left),
            .click(.openMenu(MacroSpots.PopupHop(offset: CGVector(dx: 20, dy: 40), size: menu.size)), button: .left),
            .click(.flWindow(corner: .topLeft, dx: 30, dy: 60, size: settings.size), button: .left),
            .click(.flWindow(corner: .bottomRight, dx: -20, dy: -28, size: settings.size), button: .right),
            .menuBar(titles: ["Options", "Audio settings"]),
        ])
        XCTAssertEqual(r.ignored, 1)
    }

    private func named(_ c: RecordedClick, _ label: String?) -> RecordedClick {
        var c = c
        c.named = label.map { NamedHit(label: $0, dx: 0, dy: 0) }
        return c
    }

    /// Clics « intelligents » (demande du propriétaire, 25/10) : FILE dans la fenêtre de FL puis Export › « Wave
    /// file… » dans son menu → son raccourci ; OPTIONS puis « Project general settings » → « Menu de FL » ; le bouton
    /// Arrangement puis « Clone » → l'option de la Playlist, avec la page juste au-dessus.
    func testNamedClicksBecomeTheMostPreciseBlock() {
        let main = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let menu = CGRect(x: 120, y: 60, width: 200, height: 300)
        let sub = CGRect(x: 320, y: 120, width: 200, height: 200)
        let alone = [win(1, 0, main)]
        let withMenu = [win(7, 101, menu), win(1, 0, main)]
        let withSub = [win(8, 101, sub), win(7, 101, menu), win(1, 0, main)]
        let entries: [String: [[String]]] = [
            "File": [["New"], ["Export", "Wave file..."], ["Export", "MP3 file..."],
                     ["Export", "All playlist tracks", "Time selection..."]],
            "Options": [["Project general settings"], ["Audio settings"]],
        ]
        let r = ClickSequenceCompiler.compile([
            named(click(30, 40, alone), "FILE"),
            named(click(140, 200, withMenu), "Export"),
            named(click(340, 150, withSub), "Wave file..."),
            named(click(200, 40, alone), "OPTIONS"),
            named(click(140, 100, withMenu), "Project general settings"),
            named(click(500, 300, alone), "Arrangement"),
            named(click(140, 100, withMenu), "Clone"),
            named(click(500, 300, alone), "Arrangement 2"),
            named(click(140, 120, withMenu), "Arrangement 3"),
        ], layout: FakeLayout.qwerty, menuEntries: { entries[$0] ?? [] })
        XCTAssertEqual(r.blocks, [
            .key(KeyRef(KeyCombo(keyCode: 15, command: true)), times: 1),           // File › Export › Wave file : ⌘R
            .menuBar(titles: ["Options", "Project general settings"]),
            .openPage(.playlist),
            .pageOption(id: "playlist.arrangementClone", name: ""),
            .pageOption(id: "playlist.arrangementGo", name: "Arrangement 3"),       // page déjà au-dessus
        ])
        XCTAssertEqual(r.ignored, 0)
        let ctx = ValidationContext(forbidden: .physical)
        XCTAssertNil(MacroValidation.problem(in: r.blocks.map { Block($0) }, context: ctx))
    }

    /// Sans nom lu dans le menu (lecture trop lente, pas d'autorisation), ou sans chemin unique : les clics restent
    /// des clics (le bouton retenu à son nom, l'élément du menu à sa place).
    func testSmartClicksFallBackToClicks() {
        let main = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let menu = CGRect(x: 120, y: 60, width: 200, height: 300)
        let alone = [win(1, 0, main)]
        let withMenu = [win(7, 101, menu), win(1, 0, main)]
        let entries = ["File": [["Export", "Wave file..."], ["Render", "Wave file..."]]]
        for item in [nil, "Wave file...", "Inconnu"] {
            let r = ClickSequenceCompiler.compile([
                named(click(30, 40, alone), "FILE"),
                named(click(140, 100, withMenu), item),
            ], layout: FakeLayout.qwerty, menuEntries: { entries[$0] ?? [] })
            XCTAssertEqual(r.blocks.count, 2, item ?? "sans nom")
            guard case .click(.named(let spot), .left)? = r.blocks.first else { return XCTFail("bouton FILE attendu") }
            XCTAssertEqual(spot.label, "FILE")
            guard case .click(.openMenu, .left)? = r.blocks.last else { return XCTFail("clic dans le menu attendu") }
        }
        // Un sous-menu cliqué départage deux éléments du même nom ; « FILE » lu « FlLE » est reconnu.
        XCTAssertEqual(SmartClicks.menuPath(top: "File", clicked: ["Render", "Wave file"], entries: entries["File"]!),
                       ["File", "Render", "Wave file..."])
        XCTAssertNil(SmartClicks.menuPath(top: "File", clicked: ["Wave file"], entries: entries["File"]!))
        XCTAssertEqual(SmartClicks.menuTitle("FlLE"), "File")
        XCTAssertNil(SmartClicks.menuTitle("Insert 1"))
        XCTAssertNil(SmartClicks.arrangementOption("Merge with"))
        // Add › Channel › … et Add › Effect › … : les options « Ajouter un instrument / un effet », plugin compris.
        XCTAssertEqual(SmartClicks.pageOption(forMenu: ["Add", "Channel", "Fruity", "Fruity DX10"]),
                       .pageOption(id: "channelRack.addInstrument", name: "Fruity › Fruity DX10"))
        XCTAssertEqual(SmartClicks.pageOption(forMenu: ["Add", "Effect", "Fruity Limiter"]),
                       .pageOption(id: "mixer.addEffect", name: "Fruity Limiter"))
        XCTAssertNil(SmartClicks.pageOption(forMenu: ["Add", "Channel"]))
        XCTAssertNil(SmartClicks.pageOption(forMenu: ["Tools", "Channel", "X"]))
        let main = CGRect(x: 0, y: 25, width: 800, height: 600)
        let r = ClickSequenceCompiler.compile([
            click(60, 10, [win(1, 0, main)], menu: .bar("Add")),
            click(80, 60, [win(1, 0, main)], menu: .item(["Add", "Channel", "Serum"])),
        ], layout: FakeLayout.qwerty)
        XCTAssertEqual(r.blocks, [.openPage(.channelRack), .pageOption(id: "channelRack.addInstrument", name: "Serum")])
        // Rejoué comme avant : le même chemin dans les menus de FL.
        let option = PageOptions.option("channelRack.addInstrument", layout: FakeLayout.qwerty)!
        XCTAssertEqual(PageOptions.body(option, name: "Fruity › Fruity DX10", layout: FakeLayout.qwerty),
                       .menuBar(titles: ["Add", "Channel", "Fruity", "Fruity DX10"]))
    }

    /// Menu de la barre refermé sans choix : par un clic ailleurs (macOS avale ce clic, FL ne le reçoit pas) ou en
    /// recliquant son titre. Passer d'un menu de la barre à un autre ne garde que le dernier.
    func testMenuBarClosedWithoutChoiceIsIgnored() {
        let main = CGRect(x: 0, y: 25, width: 800, height: 600)
        let alone = [win(1, 0, main)]
        let r = ClickSequenceCompiler.compile([
            click(60, 10, alone, menu: .bar("Options")),
            click(300, 300, alone),                                     // referme le menu : avalé
            click(310, 300, alone),
            click(60, 10, alone, menu: .bar("Tools")),
            click(60, 10, alone, menu: .bar("Tools")),                  // même titre : refermé
            click(320, 300, alone),
            click(60, 10, alone, menu: .bar("File")),
            click(110, 10, alone, menu: .bar("Options")),               // autre menu de la barre
            click(130, 50, [], menu: .item(["Options", "Audio settings"])),
        ])
        XCTAssertEqual(r.blocks, [
            .click(.flWindow(corner: .topLeft, dx: 310, dy: 275, size: main.size), button: .left),
            .click(.flWindow(corner: .topLeft, dx: 320, dy: 275, size: main.size), button: .left),
            .menuBar(titles: ["Options", "Audio settings"]),
        ])
        XCTAssertEqual(r.ignored, 5)
    }

    /// Glisser-déposer enregistré : l'appui et l'endroit où il est lâché (un vrai bloc « Glisser-déposer », plus un
    /// simple clic). Choix d'un menu de FL qui a son raccourci : le raccourci, sans ouvrir de menu.
    func testDragAndMenuShortcutsAreRecordedAsSuch() {
        let main = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let alone = [win(1, 0, main)]
        var drag = click(100, 200, alone)
        drag.release = RecordedRelease(point: CGPoint(x: 700, y: 400), windows: alone)
        let r = ClickSequenceCompiler.compile([
            drag,
            click(60, 10, alone, menu: .bar("View")),
            click(80, 60, alone, menu: .item(["View", "Mixer"])),
            click(60, 10, alone, menu: .bar("File")),
            click(80, 60, alone, menu: .item(["File", "Export", "Wave file..."])),
            click(80, 60, alone, menu: .item(["Options", "Audio settings"])),
        ], layout: FakeLayout.qwerty)
        XCTAssertEqual(r.blocks, [
            .drag(from: .flWindow(corner: .topLeft, dx: 100, dy: 175, size: main.size),
                  to: .flWindow(corner: .topLeft, dx: 700, dy: 375, size: main.size)),
            .key(KeyRef(KeyCombo(keyCode: 101)), times: 1),                              // F9
            .key(KeyRef(KeyCombo(keyCode: 15, command: true)), times: 1),                // ⌘R
            .menuBar(titles: ["Options", "Audio settings"]),                             // pas de raccourci : le menu
        ])
        XCTAssertNil(MenuShortcuts.key(for: ["View", "Inconnu"], layout: FakeLayout.qwerty))
        XCTAssertEqual(MenuShortcuts.key(for: ["view", "Browser"], layout: FakeLayout.qwerty),
                       KeyCombo(keyCode: 100, option: true))
    }

    func testMenuBarPathIsValidatedAndNeverLogged() {
        let ctx = ValidationContext(forbidden: .physical)
        let spec = BlockRegistry.spec(.menuBar)
        XCTAssertNil(spec.valider(.menuBar(titles: ["Options", "Audio settings"]), ctx))
        XCTAssertNotNil(spec.valider(.menuBar(titles: ["Options"]), ctx))
        XCTAssertNotNil(spec.valider(.menuBar(titles: ["Options", " "]), ctx))
        XCTAssertNotNil(spec.valider(.menuBar(titles: Array(repeating: "Niveau", count: MenuBarAX.maxDepth + 1)), ctx))
        XCTAssertEqual(BlockRegistry.journal(of: .menuBar(titles: ["Secret", "Voix"])), "menuBar")
        XCTAssertTrue(spec.dansLaPalette)
        // Ajouté depuis la palette : vide, à choisir dans les menus de FL.
        XCTAssertEqual(spec.parDefaut(), .menuBar(titles: []))
        XCTAssertEqual(spec.valider(.menuBar(titles: []), ctx)?.contains("menus de FL"), true)
        XCTAssertEqual(spec.resume(.menuBar(titles: []), FakeLayout.qwerty), "à choisir")
    }

    /// Menus de FL parcourus comme dans FL : un menu de la barre, puis ses sous-menus, jusqu'à l'élément choisi.
    func testMenuNavigation() {
        let file = MenuBarAX.Entry(title: "File", submenu: true)
        let export = MenuBarAX.Entry(title: "Export", submenu: true)
        let stems = MenuBarAX.Entry(title: "All playlist tracks", submenu: false)
        XCTAssertEqual(FLMenuNav.step(path: [], entry: file), .open(["File"]))
        XCTAssertEqual(FLMenuNav.step(path: ["File"], entry: export), .open(["File", "Export"]))
        XCTAssertEqual(FLMenuNav.step(path: ["File", "Export"], entry: stems), .choose(["File", "Export", "All playlist tracks"]))
        // Grisé dans FL en ce moment : se choisit quand même (il peut être actif quand la macro tourne).
        let paste = MenuBarAX.Entry(title: "Paste", submenu: false, enabled: false)
        XCTAssertEqual(FLMenuNav.step(path: ["Edit"], entry: paste), .choose(["Edit", "Paste"]))
        // Un sous-menu dont les éléments dépasseraient ce que le bloc rejoue ne s'ouvre pas ; un titre de la barre
        // seul n'est pas un choix.
        let deep = Array(repeating: "Niveau", count: MenuBarAX.maxDepth - 1)
        XCTAssertEqual(FLMenuNav.step(path: deep, entry: export), .none)
        XCTAssertEqual(FLMenuNav.step(path: [], entry: MenuBarAX.Entry(title: "Help", submenu: false)), .none)
        // Chaque chemin choisi est valable pour le bloc.
        let ctx = ValidationContext(forbidden: .physical)
        if case .choose(let path) = FLMenuNav.step(path: Array(deep.dropLast()), entry: stems) {
            XCTAssertNil(BlockRegistry.spec(.menuBar).valider(.menuBar(titles: path), ctx))
        } else {
            XCTFail("élément au dernier niveau rejouable")
        }
        XCTAssertEqual(FLMenuNav.start(for: ["File", "Export", "Wave file"]), ["File", "Export"])
        XCTAssertEqual(FLMenuNav.start(for: []), [])
    }

    /// FL met certains sous-menus à plat dans la barre de macOS : au rejeu, l'élément est aussi cherché sans le titre
    /// de son sous-menu (Tools › Macros › Purge… → Tools › Purge…).
    func testMenuPathFlattened() {
        XCTAssertEqual(MenuBarAX.flattened(["Tools", "Macros", "Purge unused audio clips"]),
                       ["Tools", "Purge unused audio clips"])
        XCTAssertEqual(MenuBarAX.flattened(["File", "Export", "Stems", "All"]), ["File", "Export", "All"])
        XCTAssertNil(MenuBarAX.flattened(["Tools", "Purge unused audio clips"]))
    }

    private func key(_ code: UInt16, _ char: String?, menu: Bool = false, command: Bool = false,
                     shift: Bool = false) -> RecordedInput {
        .key(RecordedKey(combo: KeyCombo(keyCode: code, command: command, shift: shift), char: char, menuOpen: menu))
    }

    /// Touches tapées dans FL : flèches, Entrée et lettres dans un menu ouvert ; raccourcis et touches ailleurs ;
    /// la même touche d'affilée devient « × n » ; une touche pendant un menu de la barre de macOS est ignorée.
    func testRecordedKeysBecomeBlocks() {
        let main = CGRect(x: 0, y: 25, width: 800, height: 600)
        let alone = [win(1, 0, main)]
        let r = ClickSequenceCompiler.compile(inputs: [
            .click(click(100, 100, alone, right: true)),
            key(125, nil, menu: true), key(125, nil, menu: true), key(125, nil, menu: true),
            key(3, "f", menu: true), key(31, "o", menu: true),
            key(36, "\r", menu: true),
            key(49, " "), key(49, " "),
            key(1, "s", command: true),
            key(126, nil),                                           // ↑ hors menu : touche
            .click(click(60, 10, alone, menu: .bar("Options"))),
            key(125, nil),                                           // dans un menu de la barre : ignorée
            .click(click(80, 60, alone, menu: .item(["Options", "Audio settings"]))),
        ])
        XCTAssertEqual(r.blocks, [
            .click(.flWindow(corner: .topLeft, dx: 100, dy: 75, size: main.size), button: .right),
            .menuKey(.down, times: 3),
            .menuLetters(["f", "o"], finalEnter: .never),
            .menuKey(.enter, times: 1),
            .key(KeyRef(KeyCombo(keyCode: 49), char: " "), times: 2),
            .key(KeyRef(KeyCombo(keyCode: 1, command: true), char: "s"), times: 1),
            .key(KeyRef(KeyCombo(keyCode: 126), char: nil), times: 1),
            .menuBar(titles: ["Options", "Audio settings"]),
        ])
        XCTAssertEqual(r.ignored, 1)
    }

    /// Répétitions plafonnées comme la validation (20 fois, 8 lettres) : au-delà, un nouveau bloc ; tous valides.
    func testKeyRepeatsStayValid() {
        let downs = Array(repeating: key(125, nil, menu: true), count: 25)
        let letters = (0..<10).map { _ in key(0, "a", menu: true) }
        let r = ClickSequenceCompiler.compile(inputs: downs + letters)
        XCTAssertEqual(r.blocks, [.menuKey(.down, times: 20), .menuKey(.down, times: 5),
                                  .menuLetters(Array(repeating: "a", count: 8), finalEnter: .never),
                                  .menuLetters(["a", "a"], finalEnter: .never)])
        let ctx = ValidationContext(forbidden: .physical)
        for b in r.blocks {
            XCTAssertNil(BlockRegistry.spec(b.type!).valider(b, ctx), "\(b)")
        }
    }

    /// Point visé dans une fenêtre, depuis le coin retenu.
    func testPointFromCorner() {
        let f = CGRect(x: 400, y: 200, width: 520, height: 428)
        XCTAssertEqual(MacroEffectsMac.point(in: f, corner: .topLeft, dx: 30, dy: 60), CGPoint(x: 430, y: 260))
        XCTAssertEqual(MacroEffectsMac.point(in: f, corner: .bottomRight, dx: -20, dy: -28), CGPoint(x: 900, y: 600))
    }
}
