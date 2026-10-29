import CoreGraphics
import Foundation
import XCTest
@testable import FLShortcut

/// Créateur de macros : liste à plat, opérations sur l'arbre, palette, clic montré dans FL.
final class MacroEditingTests: XCTestCase {
    private let ctx = ValidationContext(forbidden: .physical, strictFiles: true)

    private func tree() -> (blocks: [Block], a: Block, loop: Block, inner: Block, c: Block) {
        let a = Block(.key(KeyRef(KeyCombo(keyCode: 1, command: true)), times: 1))
        let inner = Block(.menuKey(.down, times: 5))
        let loop = Block(.repeatCount(3, [inner]))
        let c = Block(.delay(ms: 200))
        return ([a, loop, c], a, loop, inner, c)
    }

    private func rows(_ blocks: [Block], learned: Bool = true) -> [MacroStepRow] {
        MacroOutline.rows(blocks, layout: FakeLayout.qwerty, context: ctx, learnedInput: learned)
    }

    func testFlatListWithIndentationAndEndRows() {
        let t = tree()
        let r = rows(t.blocks)
        XCTAssertEqual(r.map(\.number), ["1", "2", "2.1", "", "3"])
        XCTAssertEqual(r.map(\.depth), [0, 0, 1, 0, 0])
        XCTAssertEqual(r[3].kind, .end(slot: 0))
        XCTAssertEqual(r[3].verb, "Fin de la boucle")
        XCTAssertEqual(r[0].verb, "Appuyer sur")
        XCTAssertEqual(r[0].value, "⌘S")
        XCTAssertEqual(r[2].value, "↓ × 5")
        XCTAssertEqual(r[1].value, "3 fois")
        XCTAssertTrue(r[4].badges.contains(.pauseFixe))
        XCTAssertTrue(r[1].isContainer)
    }

    func testDisabledParentDimsItsChildren() {
        var t = tree()
        MacroOutline.update(&t.blocks, id: t.loop.id) { $0.enabled = false }
        let r = rows(t.blocks)
        XCTAssertFalse(r[2].enabled)
        XCTAssertTrue(r[2].ownEnabled)
    }

    func testBadgesForLinkLearningAndProblems() {
        let blocks = [
            Block(.flAction(key: "bypass", fallback: .none)),
            Block(.selectInput(.legacy(key: "macroSpots.v2.input"))),
            Block(.click(.toLearn, button: .left)),
            Block(.chooseFile(path: "")),
            Block(.key(KeyRef(KeyCombo(keyCode: 12, command: true)), times: 1), onFailure: .keepGoing),
        ]
        let r = rows(blocks, learned: false)
        XCTAssertTrue(r[0].badges.isEmpty, "plus de « Lien FL »")
        XCTAssertTrue(r[1].badges.contains { if case .aApprendre = $0 { return true }; return false })
        XCTAssertEqual(r[2].badges.count, 1)
        XCTAssertTrue(r[2].badges.contains { if case .aApprendre = $0 { return true }; return false })
        XCTAssertTrue(r[3].badges.contains { if case .probleme = $0 { return true }; return false })
        XCTAssertEqual(r[3].value, "à choisir")
        // ⌘Q : refusé, message sans « Étape n : ».
        guard case .probleme(let why)? = r[4].badges.first else { return XCTFail("problème attendu") }
        XCTAssertTrue(why.hasPrefix("Touche interdite"), why)
        XCTAssertTrue(r[4].badges.contains(.continueSiEchec))
        // Entrée déjà apprise : plus de badge.
        XCTAssertTrue(rows(blocks, learned: true)[1].badges.isEmpty)
        // Mute et solo marchent sans le script : jamais « lien FL » ; le mute attend son bouton, montré une fois.
        MuteSwitch.forget()
        let mixer = rows([Block(.flAction(key: "mute", fallback: .none)), Block(.flAction(key: "solo", fallback: .none))],
                         learned: true)
        XCTAssertEqual(mixer[0].badges, [.aApprendre(MuteSwitch.toLearn)])
        XCTAssertTrue(mixer[1].badges.isEmpty)
    }

    func testInsertBelowSelectionOrInsideALoop() {
        var t = tree()
        let r = rows(t.blocks)
        // Sous le bloc 1 : même niveau.
        let p1 = MacroOutline.insertionPoint(after: r[0], in: t.blocks)
        XCTAssertEqual(p1, InsertionPoint(container: [], slot: 0, index: 1))
        // Ligne « Fin de la boucle » : à la fin de la boucle.
        let p2 = MacroOutline.insertionPoint(after: r[3], in: t.blocks)
        XCTAssertEqual(p2.container.count, 1)
        XCTAssertEqual(p2.index, 1)
        let new = Block(.comment("ici"))
        XCTAssertTrue(MacroOutline.insert(new, into: &t.blocks, at: p2))
        XCTAssertEqual(rows(t.blocks).map(\.number), ["1", "2", "2.1", "2.2", "", "3"])
        // Rien de choisi : tout en bas.
        XCTAssertEqual(MacroOutline.insertionPoint(after: nil, in: t.blocks).index, 3)
    }

    func testRemoveAndUpdateNestedBlocks() {
        var t = tree()
        XCTAssertTrue(MacroOutline.update(&t.blocks, id: t.inner.id) { $0.body = .menuKey(.up, times: 2) })
        XCTAssertEqual(MacroOutline.block(t.inner.id, in: t.blocks)?.body, .menuKey(.up, times: 2))
        let removed = MacroOutline.remove(&t.blocks, id: t.inner.id)
        XCTAssertEqual(removed?.block.id, t.inner.id)
        XCTAssertEqual(removed?.at.index, 0)
        XCTAssertEqual(MacroValidation.count(t.blocks), 3)
        // Annulation : remis à sa place.
        if let removed { MacroOutline.insert(removed.block, into: &t.blocks, at: removed.at) }
        XCTAssertEqual(rows(t.blocks).map(\.number), ["1", "2", "2.1", "", "3"])
    }

    func testMoveInAndOutOfLoopsButNeverIntoItself() {
        var t = tree()
        // Bloc 3 dans la boucle (déposé sur sa ligne de fin).
        XCTAssertTrue(MacroOutline.move(&t.blocks, id: t.c.id, to: .end(container: t.loop.id, slot: 0)))
        XCTAssertEqual(MacroOutline.path(of: t.c.id, in: t.blocks)?.count, 2)
        // Puis avant le bloc 1.
        XCTAssertTrue(MacroOutline.move(&t.blocks, id: t.c.id, to: .before(t.a.id)))
        XCTAssertEqual(t.blocks.first?.id, t.c.id)
        // La boucle dans elle-même : refusé, rien ne change.
        let before = t.blocks
        XCTAssertFalse(MacroOutline.move(&t.blocks, id: t.loop.id, to: .before(t.inner.id)))
        XCTAssertFalse(MacroOutline.move(&t.blocks, id: t.loop.id, to: .end(container: t.loop.id, slot: 0)))
        XCTAssertEqual(t.blocks, before)
        // En bas.
        XCTAssertTrue(MacroOutline.move(&t.blocks, id: t.c.id, to: .rootEnd))
        XCTAssertEqual(t.blocks.last?.id, t.c.id)
    }

    func testMoveRefusesTooDeepNesting() {
        var deepest = Block(.comment("fond"))
        for _ in 0..<MacroValidation.maxDepth { deepest = Block(.repeatCount(2, [deepest])) }
        let loop = Block(.repeatCount(2, []))
        var blocks = [deepest, loop]
        // La pile de boucles dans une boucle de plus : trop profond.
        XCTAssertFalse(MacroOutline.move(&blocks, id: deepest.id, to: .end(container: loop.id, slot: 0)))
        XCTAssertEqual(blocks.first?.id, deepest.id)
    }

    func testIfElseRowsKeepTheErrorNumbering() {
        let blocks = [Block(.ifElse(.windowOpen(.dialog), then: [Block(.delay(ms: 1))],
                                    otherwise: [Block(.delay(ms: 2)), Block(.delay(ms: 3))]))]
        let r = rows(blocks)
        XCTAssertEqual(r.map(\.number), ["1", "1.1", "", "1.2", "1.3", ""])
        XCTAssertEqual(r[2].verb, "Sinon")
        XCTAssertEqual(r[5].verb, "Fin du « Si »")
        // Même numérotation que la validation : « 1.3 » est le dernier bloc du sinon.
        XCTAssertEqual(MacroValidation.block(at: "1.3", in: blocks)?.body, .delay(ms: 3))
    }

    func testFreshIDsForDuplicates() {
        let t = tree()
        let copy = MacroTemplates.freshIDs([t.loop])[0]
        XCTAssertNotEqual(copy.id, t.loop.id)
        XCTAssertNotEqual(copy.body.children[0][0].id, t.inner.id)
        XCTAssertEqual(copy.body.children[0][0].body, t.inner.body)
    }

    // MARK: Palette

    func testPaletteCoversTheRunnableBlocksAndMarksTheOthers() {
        let items = PaletteCatalog.items(layout: FakeLayout.qwerty)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)
        let ready = Set(items.filter { !$0.soon }.map(\.type))
        for t: BlockType in [.key, .click, .drag, .menuKey, .waitWindow, .dropFile, .flAction,
                             .openPage, .pageOption, .menuBar] {
            XCTAssertTrue(ready.contains(t), "\(t)")
        }
        // Contrôle retiré de la palette le 28/10 (Répéter, Si… sinon) : toujours compris dans les anciennes macros.
        XCTAssertFalse(items.contains { $0.type == .repeatCount || $0.type == .ifElse })
        XCTAssertFalse(items.contains { $0.category == .controle })
        // Un seul « Attendre », avec l'horloge.
        XCTAssertEqual(items.filter { $0.category == .fenetres }.map(\.id), ["wait"])
        XCTAssertEqual(items.first { $0.id == "wait" }?.symbol, "clock")
        // Triés avec l'utilisateur : plus proposés (toujours compris dans les anciennes macros). Les attentes sont un
        // seul « Attendre ».
        // « Ouvrir un preset (boîte Open) » aussi : « Ouvrir un preset » (le fichier déposé) fait la même chose, plus
        // vite. « Menu de la piste » : outil technique, remplacé par « Cliquer sur… » et l'enregistrement des clics.
        for t: BlockType in [.menuLetters, .stop, .comment, .repeatWhile, .waitUntil, .delay, .waitWindowClose,
                             .selectInput, .feedbackCheck, .chooseFile, .trackMenu] {
            XCTAssertFalse(items.contains { $0.type == t }, "\(t)")
        }
        // Armer la piste et allumer le REC : plus proposés non plus (l'enregistrement rapide sera refait).
        let keys = items.compactMap { item -> String? in
            if case .flAction(let key, _) = item.make() { return key }
            return nil
        }
        XCTAssertFalse(keys.contains("armon") || keys.contains("recon"), "\(keys)")
        // Mute et solo de la piste retirés le 29/10 (demande du propriétaire).
        XCTAssertFalse(keys.contains("mute") || keys.contains("solo"), "\(keys)")
        XCTAssertFalse(items.contains { $0.type == .menuAX || $0.type == .setVariable || $0.type == .flActionValue })
        // Chaque entrée prête produit un bloc valide, sauf ce qui reste à choisir ou à montrer dans FL.
        let toChoose: Set<String> = ["chooseFile", "dropFile", "clickLearned", "drag", "openPage", "pageOption",
                                     "menuBar"]
        for item in items where !item.soon && !toChoose.contains(item.id) {
            let p = MacroProgram(blocks: [Block(item.make())], name: "x", source: .blocks(id: UUID(), revision: 0), context: ctx)
            XCTAssertNil(p.problem, item.id)
        }
    }

    func testPaletteSearchIgnoresCaseAndAccents() {
        let items = PaletteCatalog.items(layout: FakeLayout.qwerty)
        XCTAssertEqual(PaletteCatalog.search(items, "PAUSE").first?.id, "wait")
        XCTAssertTrue(PaletteCatalog.search(items, "boite").contains { $0.id == "wait" })
        XCTAssertEqual(PaletteCatalog.search(items, "MENU DE").first?.id, "menuBar")
        XCTAssertTrue(PaletteCatalog.search(items, "zzz introuvable").isEmpty)
        XCTAssertEqual(PaletteCatalog.search(items, "  ").count, items.count)
    }

    // MARK: Clic montré dans FL

    func testLearnedTargetInMenuOrWindow() {
        let mixer = CGRect(x: 100, y: 100, width: 900, height: 600)
        let menu = CGRect(x: 300, y: 50, width: 260, height: 400)
        let windows: [(layer: Int, bounds: CGRect)] = [(101, menu), (0, mixer)]
        // Dans le menu : relatif au menu.
        guard case .openMenu(let hop)? = MacroOutline.learnedTarget(at: CGPoint(x: 320, y: 90), windows: windows) else {
            return XCTFail("menu attendu")
        }
        XCTAssertEqual(hop.offset.dx, 20)
        XCTAssertEqual(hop.offset.dy, 40)
        XCTAssertEqual(hop.size, menu.size)
        // Dans le Mixer, près du coin bas-droit : relatif à ce coin, taille retenue.
        let t = MacroOutline.learnedTarget(at: CGPoint(x: 980, y: 690), windows: windows)
        XCTAssertEqual(t, .flWindow(corner: .bottomRight, dx: -20, dy: -10, size: mixer.size))
        // Hors de FL : rien.
        XCTAssertNil(MacroOutline.learnedTarget(at: CGPoint(x: 5, y: 5), windows: windows))
        // Fenêtre de réglages (Options › Audio) ou boîte de dialogue, devant le Mixer : relative à SON coin, sa
        // taille retenue (c'est elle qu'on retrouve au rejeu), qu'elle soit flottante (3) ou de dialogue (8).
        let settings = CGRect(x: 200, y: 150, width: 400, height: 300)
        for layer in [3, 8] {
            let front: [(layer: Int, bounds: CGRect)] = [(layer, settings), (0, mixer)]
            XCTAssertEqual(MacroOutline.learnedTarget(at: CGPoint(x: 230, y: 170), windows: front),
                           .flWindow(corner: .topLeft, dx: 30, dy: 20, size: settings.size))
        }
        // Niveau négatif (bureau, fenêtres d'arrière-plan) : jamais une fenêtre de FL à viser.
        XCTAssertNil(MacroOutline.learnedTarget(at: CGPoint(x: 10, y: 10), windows: [(-20, CGRect(x: 0, y: 0, width: 400, height: 300))]))
    }

    func testPluginWindowIsLearnedWithItsTitleEvenOnTop() {
        let serum = CGRect(x: 300, y: 50, width: 1012, height: 768)
        let main = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        // Fenêtre de plugin restée devant (niveau des menus) : avec son titre, une fenêtre, pas un menu.
        let windows: [(layer: Int, bounds: CGRect)] = [(101, serum), (0, main)]
        XCTAssertEqual(MacroOutline.learnedTarget(at: CGPoint(x: 340, y: 90), windows: windows, title: "Serum"),
                       .flWindow(corner: .topLeft, dx: 40, dy: 40, size: serum.size, title: "Serum"))
        guard case .openMenu? = MacroOutline.learnedTarget(at: CGPoint(x: 340, y: 90), windows: windows) else {
            return XCTFail("sans titre : un menu, comme avant")
        }
        // Le titre est gardé dans la macro, relu tel quel.
        let target = ClickTarget.flWindow(corner: .bottomRight, dx: -20, dy: -10, size: serum.size, title: "Serum #2")
        XCTAssertEqual(ClickTarget(json: target.json), target)
        XCTAssertTrue(target.isFinite)
        XCTAssertFalse(ClickTarget.flWindow(corner: .topLeft, dx: 1, dy: 1, size: serum.size, title: "").isFinite)
        XCTAssertFalse(ClickTarget.flWindow(corner: .topLeft, dx: 1, dy: 1, size: nil, title: "Serum").isFinite)
        // La fenêtre principale (nom du projet) n'est jamais retenue par son titre.
        XCTAssertTrue(FLWindowAX.isPluginTitle("Serum"))
        XCTAssertFalse(FLWindowAX.isPluginTitle("Mon morceau - FL Studio 2025"))
        XCTAssertFalse(FLWindowAX.isPluginTitle(""))
    }

    func testPaletteHasNameColor() {
        let items = PaletteCatalog.items(layout: FakeLayout.qwerty)
        let item = items.first { $0.id == "nameColor" }
        XCTAssertEqual(item?.type, .nameColor)
        XCTAssertEqual(item?.soon, false)
        XCTAssertTrue(PaletteCatalog.search(items, "couleur").contains { $0.id == "nameColor" })
        XCTAssertTrue(PaletteCatalog.search(items, "renommer").contains { $0.id == "nameColor" } ||
                      PaletteCatalog.search(items, "nom").contains { $0.id == "nameColor" })
    }

    func testRecentColors() throws {
        let suite = "flshortcut.tests.recentColors.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(RecentColors.list(defaults: defaults), [])
        let colors = (0..<12).map { RGBColor(r: UInt8($0 * 20), g: 0x10, b: 0x20) }
        for c in colors { RecentColors.remember(c, defaults: defaults) }
        let list = RecentColors.list(defaults: defaults)
        XCTAssertEqual(list.count, 10)
        XCTAssertEqual(list.first, colors[11])
        // Une couleur déjà présente remonte en tête, sans doublon.
        RecentColors.remember(colors[5], defaults: defaults)
        XCTAssertEqual(RecentColors.list(defaults: defaults).first, colors[5])
        XCTAssertEqual(Set(RecentColors.list(defaults: defaults)).count, 10)
        // Valeurs illisibles dans les préférences : ignorées.
        defaults.set(["E0453A", "zz", 3, "E0453A"], forKey: RecentColors.key)
        XCTAssertEqual(RecentColors.list(defaults: defaults), [RGBColor(r: 0xE0, g: 0x45, b: 0x3A)])
    }

    /// « Choisir… » du preset : la boîte s'ouvre directement dans Mixer presets de FL, sinon au plus proche.
    func testPresetChooserOpensInMixerPresets() {
        let home = URL(fileURLWithPath: "/Users/moi")
        let all = PresetPanel.startFolder(home: home) { _ in true }
        XCTAssertEqual(all?.path, "/Users/moi/Documents/Image-Line/FL Studio/Presets/Mixer presets")
        let noMixer = PresetPanel.startFolder(home: home) { !$0.path.hasSuffix("Mixer presets") }
        XCTAssertEqual(noMixer?.path, "/Users/moi/Documents/Image-Line/FL Studio/Presets")
        XCTAssertNil(PresetPanel.startFolder(home: home) { _ in false })
    }
}
