// Blocs « Ouvrir une page de FL » et « Cliquer sur… » (MacroPages.swift).
import XCTest
@testable import FLShortcut

final class MacroPagesTests: XCTestCase {
    private let layout = FakeLayout.qwerty

    private func program(_ blocks: [Block]) -> MacroProgram {
        MacroProgram(blocks: blocks, name: "essai", source: .blocks(id: UUID(), revision: 0),
                     context: ValidationContext(forbidden: .physical))
    }

    func testEachPageListsOnlyItsOwnOptions() {
        for page in FLPage.allCases {
            let options = PageOptions.options(for: page, layout: layout)
            XCTAssertEqual(Set(options.map(\.id)).count, options.count, "\(page)")
            for o in options {
                XCTAssertEqual(o.page, page)
                XCTAssertEqual(PageOptions.page(of: o.id), page, o.id)
                XCTAssertTrue(PageOptions.isKnown(o.id), o.id)
                XCTAssertEqual(PageOptions.field(of: o.id), o.field, o.id)
                XCTAssertFalse(PageOptions.replaced.contains(o.id), o.id)
            }
        }
        let rack = PageOptions.options(for: .channelRack, layout: layout).map(\.id)
        let mixer = PageOptions.options(for: .mixer, layout: layout).map(\.id)
        XCTAssertEqual(rack.first, "channelRack.addInstrument", "ajouter un instrument d'abord")
        XCTAssertEqual(mixer.first, "mixer.addEffect", "ajouter un effet d'abord")
        XCTAssertTrue(mixer.contains("mixer.armon"))
        XCTAssertFalse(rack.contains("mixer.armon"))
        XCTAssertFalse(mixer.contains("channelRack.addInstrument"))
        XCTAssertFalse(PageOptions.isKnown("mixer.inconnu"))
        XCTAssertNil(PageOptions.page(of: "salon.armon"))
    }

    func testOptionsPlayTheSafestWay() throws {
        let add = try XCTUnwrap(PageOptions.option("channelRack.addInstrument", layout: layout))
        XCTAssertEqual(PageOptions.body(add, name: "  Serum ", layout: layout), .menuBar(titles: ["Add", "Channel", "Serum"]))
        let effect = try XCTUnwrap(PageOptions.option("mixer.addEffect", layout: layout))
        XCTAssertEqual(PageOptions.body(effect, name: "Fruity Limiter", layout: layout),
                       .menuBar(titles: ["Add", "Effect", "Fruity Limiter"]))
        // Armer : le lien, sinon le menu de la piste (n'éteint jamais).
        let arm = try XCTUnwrap(PageOptions.option("mixer.armon", layout: layout))
        XCTAssertEqual(PageOptions.body(arm, name: "", layout: layout), .flAction(key: "armon", fallback: .trackMenuArm))
        // Raccourci d'origine de la page : sa touche de FL.
        let key = try XCTUnwrap(PageOptions.options(for: .mixer, layout: layout).first {
            if case .key = $0.kind { return true }; return false
        })
        guard case .key(let combo) = key.kind else { return XCTFail("touche attendue") }
        XCTAssertEqual(PageOptions.body(key, name: "", layout: layout), .key(KeyRef(combo), times: 1))
        // Ouvrir une page : le lien (jamais refermée), avec sa touche de FL en repli.
        guard case .flAction("mx", _) = FLPage.mixer.openBody(layout: layout) else { return XCTFail("lien attendu") }
    }

    /// Mute ou solo d'un canal par son numéro (au lieu des touches 1 à 9), nom de la piste à écrire (au lieu de F2) :
    /// les anciens raccourcis ne sont plus proposés mais restent compris.
    func testChannelNumberAndTrackNameAreAskedFor() throws {
        let rack = PageOptions.options(for: .channelRack, layout: layout).map(\.id)
        XCTAssertTrue(rack.contains("channelRack.chMute") && rack.contains("channelRack.chSolo"))
        XCTAssertFalse(rack.contains("channelRack.fl.channelRack.1"))
        XCTAssertFalse(PageOptions.options(for: .mixer, layout: layout).map(\.id).contains("mixer.fl.mixer.f2"))
        XCTAssertTrue(PageOptions.isKnown("channelRack.fl.channelRack.cmd-0"))
        XCTAssertNotNil(PageOptions.option("mixer.fl.mixer.f2", layout: layout))
        XCTAssertEqual(PageOptions.field(of: "channelRack.chSolo"), .channel)
        XCTAssertEqual(PageOptions.field(of: "mixer.rename"), .name)
        XCTAssertEqual(PageOptions.field(of: "mixer.addEffect"), .plugin)
        XCTAssertNil(PageOptions.field(of: "mixer.armon"))
        XCTAssertTrue(PageOptions.usesLink("channelRack.chMute") && PageOptions.usesLink("mixer.rename"))

        // Numéro : 1 à 999 ; touche de FL jusqu'au canal 10 (0 pour le 10, ⌘ pour le solo).
        XCTAssertEqual(PageOptions.channel(" 12 "), 12)
        XCTAssertNil(PageOptions.channel("0"))
        XCTAssertNil(PageOptions.channel("1000"))
        XCTAssertNil(PageOptions.channel("douze"))
        XCTAssertEqual(PageOptions.channelKey(1, solo: false, layout: layout), KeyCombo(keyCode: 18))
        XCTAssertEqual(PageOptions.channelKey(10, solo: true, layout: layout), KeyCombo(keyCode: 29, command: true))
        XCTAssertNil(PageOptions.channelKey(11, solo: false, layout: layout))
        XCTAssertEqual(OrganizerPayload.toggleChannel(11, solo: true), [13, 1, 0, 11])

        // Jouées par l'effet lui-même (lien, sinon touche ou fenêtre F2), jamais par un bloc de clic.
        let mute = try XCTUnwrap(PageOptions.option("channelRack.chMute", layout: layout))
        XCTAssertNil(PageOptions.body(mute, name: "12", layout: layout))

        // Validation et ligne du bloc.
        func problem(_ id: String, _ value: String) -> String? {
            program([Block(.openPage(PageOptions.page(of: id))), Block(.pageOption(id: id, name: value))]).problem
        }
        XCTAssertNil(problem("channelRack.chMute", "12"))
        XCTAssertNotNil(problem("channelRack.chMute", ""))
        XCTAssertNotNil(problem("channelRack.chSolo", "1000"))
        XCTAssertNil(problem("mixer.rename", "Voix lead"))
        XCTAssertNotNil(problem("mixer.rename", "  "))
        XCTAssertNotNil(problem("mixer.rename", String(repeating: "a", count: 65)))
        XCTAssertNil(problem("mixer.fl.mixer.f2", ""), "ancienne macro : F2 toujours valable")
        let spec = BlockRegistry.spec(.pageOption)
        XCTAssertEqual(spec.resume(.pageOption(id: "channelRack.chSolo", name: "12"), layout), "Solo du canal 12")
        XCTAssertEqual(spec.resume(.pageOption(id: "mixer.rename", name: "Voix"), layout), "Renommer la piste : Voix")
        XCTAssertFalse(BlockRegistry.journal(of: .pageOption(id: "mixer.rename", name: "Secret")).contains("Secret"))
    }

    /// Plugin choisi dans la liste lue dans FL : un sous-menu du menu Add devient un niveau de plus du chemin.
    func testPluginPathsAndGroups() throws {
        let add = try XCTUnwrap(PageOptions.option("mixer.addEffect", layout: layout))
        XCTAssertEqual(PageOptions.body(add, name: "Fruity › Fruity Limiter", layout: layout),
                       .menuBar(titles: ["Add", "Effect", "Fruity", "Fruity Limiter"]))
        XCTAssertNil(PageOptions.valueProblem(.plugin, "Fruity › Fruity Limiter"))
        XCTAssertNotNil(PageOptions.valueProblem(.plugin, "Fruity › "))
        XCTAssertNotNil(PageOptions.valueProblem(.plugin, "a › b › c › d"))
        let groups = FLPluginList.groups(["Serum", "Fruity › Limiter", "Fruity › Delay 3", "Vital"])
        XCTAssertEqual(groups, [FLPluginList.Folder(title: nil, names: ["Serum"]),
                                FLPluginList.Folder(title: "Fruity", names: ["Fruity › Limiter", "Fruity › Delay 3"]),
                                FLPluginList.Folder(title: nil, names: ["Vital"])])
        // Chaque bloc produit par une option de la palette reste valable dans le « Menu de FL ».
        let ctx = ValidationContext(forbidden: .physical)
        XCTAssertNil(BlockRegistry.spec(.menuBar).valider(.menuBar(titles: ["Add", "Effect", "Fruity", "Fruity Limiter"]), ctx))
    }

    func testPageAboveFollowsTheMacroOrderAndLoops() {
        let open = Block(.openPage(.mixer))
        let first = Block(.pageOption(id: "mixer.armon", name: ""))
        let inner = Block(.pageOption(id: "channelRack.chnext", name: ""))
        let innerPage = Block(.openPage(.channelRack))
        let loop = Block(.repeatCount(2, [inner, innerPage]))
        let blocks = [first, open, Block(.key(KeyRef(KeyCombo(keyCode: 1)), times: 1)), loop]
        XCTAssertEqual(PageOptions.pageAbove(first.id, in: blocks), .some(nil), "rien au-dessus")
        XCTAssertEqual(PageOptions.pageAbove(inner.id, in: blocks), .some(.mixer), "page d'avant la boucle")
        XCTAssertEqual(PageOptions.pageAbove(innerPage.id, in: blocks), .some(.mixer))
        XCTAssertNil(PageOptions.pageAbove(UUID(), in: blocks), "bloc absent")
    }

    func testOptionOutsideItsPageIsReportedOnItsStep() {
        let mixer = Block(.openPage(.mixer))
        let arm = Block(.pageOption(id: "mixer.armon", name: ""))
        XCTAssertNil(PageOptions.misplaced(in: [mixer, arm]))
        XCTAssertNil(program([mixer, arm]).problem)

        let rack = Block(.pageOption(id: "channelRack.chnext", name: ""))
        let wrong = PageOptions.misplaced(in: [mixer, arm, rack])
        XCTAssertEqual(wrong?.path, "3")
        XCTAssertEqual(wrong?.page, .mixer)
        XCTAssertEqual(program([mixer, arm, rack]).problem,
                       "Étape 3 : cette option n'est pas dans Mixer, la page ouverte au-dessus : choisis-en une de cette page.")
        // Sans page au-dessus, et numérotation du « sinon » qui suit celle du « alors ».
        XCTAssertEqual(PageOptions.misplaced(in: [arm])?.path, "1")
        XCTAssertNil(PageOptions.misplaced(in: [arm])?.page)
        let branch = Block(.ifElse(.windowOpen(.dialog), then: [Block(.key(KeyRef(KeyCombo(keyCode: 1)), times: 1))],
                                   otherwise: [arm]))
        XCTAssertEqual(PageOptions.misplaced(in: [branch])?.path, "1.2")
        XCTAssertNil(PageOptions.misplaced(in: [mixer, branch]), "page ouverte avant le « Si »")
        // Signalé aussi sur la ligne du bloc dans l'éditeur.
        let rows = MacroOutline.rows([mixer, arm, rack], layout: layout, context: ValidationContext(forbidden: .physical),
                                     learnedInput: false)
        XCTAssertTrue(rows[2].badges.contains { if case .probleme = $0 { return true }; return false })
        XCTAssertFalse(rows[1].badges.contains { if case .probleme = $0 { return true }; return false })
    }

    func testPagesAndOptionsToChooseBlockTheMacro() {
        XCTAssertNotNil(program([Block(.openPage(nil))]).problem)
        XCTAssertNotNil(program([Block(.openPage(.mixer)), Block(.pageOption(id: nil, name: ""))]).problem)
        XCTAssertNotNil(program([Block(.openPage(.mixer)), Block(.pageOption(id: "mixer.addEffect", name: " "))]).problem,
                        "nom du plugin à écrire")
        XCTAssertNil(program([Block(.openPage(.mixer)), Block(.pageOption(id: "mixer.addEffect", name: "Pro-Q 3"))]).problem)
        XCTAssertNotNil(program([Block(.openPage(.mixer)), Block(.pageOption(id: "mixer.zzz", name: ""))]).problem)
    }

    func testClickOnAddsThePageJustAboveWhenMissing() throws {
        let option = Block(.pageOption(id: nil, name: ""))
        var blocks = [Block(.key(KeyRef(KeyCombo(keyCode: 1)), times: 1))]
        let end = InsertionPoint.rootEnd(blocks)
        XCTAssertTrue(MacroOutline.needsPage(option, at: end, in: blocks))
        let page = Block(.openPage(nil))
        XCTAssertTrue(MacroOutline.insertWithPage(option, page: page, into: &blocks, at: end))
        XCTAssertEqual(blocks.map(\.id).suffix(2), [page.id, option.id], "page juste au-dessus")

        // Sous une page ou une autre option : rien de plus.
        let second = Block(.pageOption(id: nil, name: ""))
        XCTAssertFalse(MacroOutline.needsPage(second, at: .rootEnd(blocks), in: blocks))
        XCTAssertTrue(MacroOutline.insertWithPage(second, into: &blocks, at: .rootEnd(blocks)))
        XCTAssertEqual(blocks.count, 4)
        // Un autre bloc n'emmène jamais de page.
        let key = Block(.key(KeyRef(KeyCombo(keyCode: 2)), times: 1))
        XCTAssertFalse(MacroOutline.needsPage(key, at: InsertionPoint(container: [], slot: 0, index: 0), in: blocks))

        // Dans une boucle vide : la page entre dans la boucle, avec l'option.
        let loop = Block(.repeatCount(2, []))
        var nested = [loop]
        let inside = InsertionPoint(container: [BlockStep(slot: 0, index: 0)], slot: 0, index: 0)
        XCTAssertTrue(MacroOutline.insertWithPage(Block(.pageOption(id: nil, name: "")), into: &nested, at: inside))
        guard case .repeatCount(_, let body) = nested[0].body else { return XCTFail("boucle") }
        XCTAssertEqual(body.map(\.body.type), [.openPage, .pageOption])
    }

    func testBlocksRoundTripAndNeverLogThePluginName() throws {
        let blocks = [Block(.openPage(.pianoRoll)), Block(.openPage(nil)),
                      Block(.pageOption(id: "channelRack.addInstrument", name: "Serum")), Block(.pageOption(id: nil, name: ""))]
        let back = try JSONDecoder().decode([Block].self, from: JSONEncoder().encode(blocks))
        XCTAssertEqual(back, blocks)
        let journal = BlockRegistry.journal(of: .pageOption(id: "channelRack.addInstrument", name: "Serum"))
        XCTAssertFalse(journal.contains("Serum"))
        XCTAssertEqual(BlockRegistry.journal(of: .openPage(.mixer)), "openPage mixer")
    }
}
