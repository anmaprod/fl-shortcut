import CoreAudio
import XCTest
@testable import FLShortcut

/// Macros en blocs : codage JSON (identifiants stables, décodage tolérant, blocs inconnus conservés et bloquants)
/// et registre des blocs (textes en français, valeurs par défaut valides, besoins, journal sans donnée sensible).
final class MacroModelTests: XCTestCase {
    private func roundTrip(_ blocks: [Block]) throws -> [Block] {
        try JSONDecoder().decode([Block].self, from: JSONEncoder().encode(blocks))
    }

    private func program(_ blocks: [Block], variables: [VariableDecl] = []) -> MacroProgram {
        MacroProgram(blocks: blocks, name: "essai", source: .blocks(id: UUID(), revision: 0), variables: variables,
                     context: ValidationContext(forbidden: .physical))
    }

    // MARK: Codage

    /// Chaque type, avec la valeur par défaut du registre : aller-retour identique et `type` stable dans le JSON.
    func testEveryBlockTypeRoundTrips() throws {
        for t in BlockType.allCases {
            let b = Block(BlockRegistry.spec(t).parDefaut())
            XCTAssertEqual(try roundTrip([b]), [b], "\(t)")
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(b)) as? [String: Any]
            XCTAssertEqual(object?["type"] as? String, t.rawValue)
            XCTAssertEqual(object?["id"] as? String, b.id.uuidString)
        }
    }

    func testRichValuesRoundTrip() throws {
        let hop = MacroSpots.PopupHop(offset: CGVector(dx: 115, dy: 54), size: CGSize(width: 230, height: 88))
        let blocks: [Block] = [
            Block(.key(KeyRef(KeyCombo(keyCode: 1, command: true, shift: true), char: "s"), times: 2),
                  enabled: false, onFailure: .keepGoing, note: "enregistrer"),
            Block(.click(.flWindow(corner: .bottomRight, dx: -12.5, dy: -40, size: CGSize(width: 940, height: 652)), button: .right)),
            Block(.click(.openMenu(hop), button: .left)),
            Block(.click(.track(dx: 0, dy: 300), button: .left)),
            Block(.click(.lastClick(dx: 3, dy: 4), button: .left)),
            Block(.click(.startCursor(dx: -1, dy: 2), button: .left)),
            Block(.click(.cursorXWindowY(dx: 12, dy: 640), button: .left)),
            Block(.menuLetters(["s", "a"], finalEnter: .always)),
            Block(.menuKey(.left, times: 1)),
            Block(.waitWindow(.menu, timeoutMs: 1_500)),
            Block(.waitWindowClose(.menu, timeoutMs: 800)),
            Block(.flAction(key: "recon", fallback: .key(KeyRef(KeyCombo(keyCode: 15))))),
            Block(.flAction(key: "play", fallback: .none)),
            Block(.flActionValue(key: "trnext", value: .variable("n"))),
            Block(.menuAX(titles: ["File", "Open mixer track state"], fallback: [.startCursor(dx: 4, dy: 5)])),
            Block(.ifElse(.all([.windowOpen(.dialog), .not(.lastBlockFailed), .any([.variable("n", .lt, 3),
                                                                                     .flState(query: "isrec", .eq, 0)])]),
                          then: [Block(.delay(ms: 100))],
                          otherwise: [Block(.repeatCount(3, [Block(.menuKey(.down, times: 5))]))])),
            Block(.repeatWhile(.windowOpen(.menu), maxIterations: 7, [Block(.comment("tour"))])),
            Block(.waitUntil(.not(.windowOpen(.dialog)), timeoutMs: 2_000)),
            Block(.setVariable("n", .flState("track"))),
            Block(.stop(message: "fini")),
        ]
        XCTAssertEqual(try roundTrip(blocks), blocks)
    }

    func testMacroDocRoundTripAndTolerance() throws {
        let doc = MacroDoc(name: "Armer et enregistrer", blocks: MacroTemplates.enregistrementRapide(Macro()),
                           variables: [VariableDecl(name: "n", initial: 2)], origin: .template("autoRecord"), revision: 4)
        XCTAssertEqual(try JSONDecoder().decode(MacroDoc.self, from: JSONEncoder().encode(doc)), doc)
        // Champs manquants : valeurs par défaut, jamais d'échec.
        let sparse = try JSONDecoder().decode(MacroDoc.self, from: Data(#"{"blocks":[{"type":"delay","ms":50}]}"#.utf8))
        XCTAssertEqual(sparse.format, 2)
        XCTAssertEqual(sparse.name, "Macro")
        XCTAssertEqual(sparse.blocks.map(\.body), [.delay(ms: 50)])
        XCTAssertEqual(sparse.blocks.first?.enabled, true)
        XCTAssertEqual(sparse.blocks.first?.onFailure, .stop)
    }

    /// Un bloc d'une version plus récente est conservé tel quel (réécrit à l'identique) et bloque la macro.
    func testUnknownBlockIsKeptAsIsAndBlocksTheMacro() throws {
        let json = """
        [{"type":"teleport","id":"F15C0009-0000-4000-8000-000000000042","destination":{"x":1,"y":[2,3]},"enabled":false},
         {"type":"delay","id":"F15C0009-0000-4000-8000-000000000043","ms":100}]
        """
        let blocks = try JSONDecoder().decode([Block].self, from: Data(json.utf8))
        XCTAssertEqual(blocks.count, 2)
        guard case .unknown(let type, let raw) = blocks[0].body else { return XCTFail("bloc inconnu attendu") }
        XCTAssertEqual(type, "teleport")
        XCTAssertEqual(raw["destination"]?["x"]?.int, 1)
        XCTAssertEqual(blocks[0].id.uuidString, "F15C0009-0000-4000-8000-000000000042")
        XCTAssertFalse(blocks[0].enabled)
        XCTAssertEqual(blocks[1].body, .delay(ms: 100))
        XCTAssertEqual(try roundTrip(blocks), blocks)
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(blocks)) as? [[String: Any]]
        XCTAssertEqual(written?.first?["type"] as? String, "teleport")
        XCTAssertNotNil(written?.first?["destination"])
        // Même inactif, il bloque : il pourrait être réactivé, et il n'est jamais exécuté sans être compris.
        let p = program(blocks)
        XCTAssertFalse(p.isRunnable)
        XCTAssertTrue(p.problem?.contains("teleport") == true)
        XCTAssertTrue(p.problem?.hasPrefix("Étape 1 :") == true)
    }

    /// Un bloc connu mais illisible (paramètre manquant ou du mauvais type) devient inconnu : jamais deviné.
    func testMalformedKnownBlockIsKeptAndBlocks() throws {
        let json = #"[{"type":"delay","ms":"beaucoup"},{"type":"if","condition":{"type":"windowOpen","window":"dialog"},"then":[{"type":"key"}]}]"#
        let blocks = try JSONDecoder().decode([Block].self, from: Data(json.utf8))
        guard case .unknown("delay", _) = blocks[0].body else { return XCTFail("delay illisible : inconnu") }
        guard case .ifElse(_, let then, let otherwise) = blocks[1].body, case .unknown("key", _)? = then.first?.body else {
            return XCTFail("touche sans combinaison : inconnue")
        }
        XCTAssertEqual(otherwise, [])
        XCTAssertEqual(MacroValidation.firstUnknown(blocks), "1")
        XCTAssertEqual(MacroValidation.firstUnknown([blocks[1]]), "1.1")
        XCTAssertFalse(program(blocks).isRunnable)
    }

    func testDecodingNeverFailsOnGarbage() throws {
        let blocks = try JSONDecoder().decode([Block].self, from: Data(#"[1, "x", null, {"type": 3}, {"type":"comment"}]"#.utf8))
        XCTAssertEqual(blocks.count, 5)
        XCTAssertEqual(blocks.prefix(4).filter { if case .unknown = $0.body { return true } else { return false } }.count, 4)
        XCTAssertEqual(blocks[4].body, .comment(""))
        // Échec inconnu : arrêt ; id illisible : un nouveau.
        let b = try JSONDecoder().decode(Block.self, from: Data(#"{"type":"delay","ms":5,"id":"nope","onFailure":"retry"}"#.utf8))
        XCTAssertEqual(b.onFailure, .stop)
        XCTAssertEqual(b.body, .delay(ms: 5))
        let c = try JSONDecoder().decode(Block.self, from: Data(#"{"type":"delay","ms":5,"onFailure":"continue"}"#.utf8))
        XCTAssertEqual(c.onFailure, .keepGoing)
    }

    /// Imbrication démesurée (fichier piégé) : le fond n'est pas interprété, la macro est bloquée.
    func testDeepNestingIsBounded() throws {
        var json = #"{"type":"delay","ms":1}"#
        for _ in 0..<40 { json = #"{"type":"repeat","count":1,"blocks":[\#(json)]}"# }
        let block = try JSONDecoder().decode(Block.self, from: Data(json.utf8))
        XCTAssertNotNil(MacroValidation.firstUnknown([block]))
        XCTAssertFalse(program([block]).isRunnable)
    }

    func testLegacyClickSpotsKeepTheirAnchor() {
        XCTAssertEqual(ClickTarget(ClickSpot(anchor: .cursor, dx: 1, dy: 2)), .startCursor(dx: 1, dy: 2))
        XCTAssertEqual(ClickTarget(ClickSpot(anchor: .window, dx: 1, dy: 2)), .flWindow(corner: .topLeft, dx: 1, dy: 2, size: nil))
        XCTAssertEqual(ClickTarget(ClickSpot(anchor: .cursorXWindowY, dx: 1, dy: 2)), .cursorXWindowY(dx: 1, dy: 2))
        XCTAssertEqual(ClickTarget(ClickSpot(anchor: .lastClick, dx: 1, dy: 2)), .lastClick(dx: 1, dy: 2))
        XCTAssertFalse(ClickTarget.track(dx: .infinity, dy: 0).isFinite)
        XCTAssertFalse(ClickTarget.startCursor(dx: 5001, dy: 0).isFinite)
    }

    // MARK: Registre

    func testEveryTypeHasFrenchTextsAndASymbol() {
        for t in BlockType.allCases {
            let s = BlockRegistry.spec(t)
            XCTAssertEqual(s.type, t)
            XCTAssertFalse(s.label.isEmpty, "\(t)")
            XCTAssertNotEqual(s.label, t.rawValue, "\(t) : libellé en français, pas l'identifiant")
            XCTAssertGreaterThan(s.aide.count, 20, "\(t)")
            XCTAssertFalse(s.symbol.isEmpty, "\(t)")
            XCTAssertTrue(s.plateformes.contains(.mac))
        }
    }

    /// Valeur par défaut de chaque type : valide seule (variable « n » déclarée). « Cliquer sur… » demande sa page
    /// au-dessus : valide sous « Ouvrir une page de FL » par défaut. « Menu de FL » : vide, à choisir dans les menus
    /// de FL (MacroClickSequenceTests).
    func testDefaultsAreValid() {
        for t in BlockType.allCases where t != .pageOption && t != .menuBar {
            let p = program([Block(BlockRegistry.spec(t).parDefaut())], variables: [VariableDecl(name: "n")])
            XCTAssertNil(p.problem, "\(t)")
        }
        let page = Block(BlockRegistry.spec(.openPage).parDefaut())
        XCTAssertNil(program([page, Block(BlockRegistry.spec(.pageOption).parDefaut())]).problem)
        XCTAssertNotNil(program([Block(BlockRegistry.spec(.pageOption).parDefaut())]).problem, "sans page au-dessus")
    }

    func testPaletteHidesLegacyAndUnfinishedBlocks() {
        let shown = BlockRegistry.palette.flatMap { cat, specs -> [BlockType] in
            XCTAssertTrue(specs.allSatisfy { $0.category == cat })
            return specs.map(\.type)
        }
        XCTAssertFalse(shown.contains(.menuAX))
        XCTAssertTrue(shown.contains(.trackMenu))
        XCTAssertTrue(shown.contains(.menuBar))
        XCTAssertEqual(Set(shown).count, shown.count)
    }

    /// Le journal garde les noms des anciennes étapes (comparaison des journaux d'une version à l'autre).
    func testJournalKeepsTheOldStepNames() {
        XCTAssertEqual(BlockRegistry.journal(of: .waitWindow(.dialog, timeoutMs: 4_000)), "waitDialog")
        XCTAssertEqual(BlockRegistry.journal(of: .waitWindowClose(.dialog, timeoutMs: 8_000)), "waitDialogClose")
        XCTAssertEqual(BlockRegistry.journal(of: .flAction(key: "armon", fallback: .trackMenuArm)), "armTrack")
        XCTAssertEqual(BlockRegistry.journal(of: .flAction(key: "recon", fallback: .none)), "recordOn")
        XCTAssertEqual(BlockRegistry.journal(of: .menuAX(titles: ["File"], fallback: [])), "menu")
        XCTAssertEqual(BlockRegistry.journal(of: .unknown(type: "x", raw: .null)), "unknown")
    }

    /// Jamais une touche, un chemin, un nom de piste ou un texte de l'utilisateur dans le journal.
    func testJournalNeverContainsPrivateData() {
        let bodies: [BlockBody] = [
            .chooseFile(path: "/Users/secret/Presets/Voix lead.fst"),
            .key(KeyRef(KeyCombo(keyCode: 1, command: true), char: "s"), times: 1),
            .trackMenu(letters: ["f", "o"], labels: ["Piste secrète", "Voix"], target: .lastClicked, finalEnter: .ifNeeded),
            .comment("secret"), .stop(message: "secret"), .setVariable("secret", .constant(1)),
            .flAction(key: "secret", fallback: .none), .menuAX(titles: ["Secret"], fallback: []),
        ]
        for body in bodies {
            let line = BlockRegistry.journal(of: body).lowercased()
            for word in ["secret", "voix", "users", "fst", "piste", "⌘"] { XCTAssertFalse(line.contains(word), line) }
        }
    }

    func testSummaryLines() {
        XCTAssertEqual(BlockRegistry.spec(.key).resume(.key(KeyRef(KeyCombo(keyCode: 1, command: true)), times: 2), FakeLayout.qwerty),
                       "⌘S × 2")
        XCTAssertEqual(BlockRegistry.spec(.trackMenu).resume(MacroTemplates.openStateMenu, FakeLayout.qwerty),
                       "File › Open mixer track state")
        XCTAssertEqual(BlockRegistry.spec(.delay).resume(.delay(ms: 1_500), FakeLayout.qwerty), "1,5 s")
        XCTAssertEqual(BlockRegistry.spec(.chooseFile).resume(.chooseFile(path: "/Users/a/Voix.fst"), FakeLayout.qwerty), "Voix.fst")
    }

    func testNeedsAreAggregatedOverTheWholeTree() {
        var m = Macro()
        m.recKey = KeyCombo(keyCode: 15)
        let full = MacroProgram.compile(m, forbidden: .physical).needs
        XCTAssertTrue(full.isSuperset(of: [.pisteVisee, .pisteRequise, .lienMIDI, .larsenEnAvance, .cliqueHID, .attenteClavierInterne]))
        m.armAndInput = false
        m.startRecording = false
        let menuOnly = MacroProgram.compile(m, forbidden: .physical).needs
        XCTAssertFalse(menuOnly.contains(.lienMIDI))
        XCTAssertFalse(menuOnly.contains(.larsenEnAvance))
        // Au fond d'un « si », un bloc actif compte ; inactif, non.
        let nested = Block(.ifElse(.windowOpen(.dialog), then: [Block(.feedbackCheck)],
                                   otherwise: [Block(.flAction(key: "recon", fallback: .none), enabled: false)]))
        let needs = MacroValidation.needs(of: [nested])
        XCTAssertTrue(needs.contains(.larsenEnAvance))
        XCTAssertFalse(needs.contains(.lienMIDI))
        XCTAssertTrue(MacroValidation.needs(of: [Block(.flActionValue(key: "trnext", value: .constant(1)))]).contains(.extensionsMIDI))
    }

    // MARK: Nom et couleur

    func testNameColorJSONRoundTrip() throws {
        let red = try XCTUnwrap(RGBColor(hex: "E0453A"))
        let blocks = [Block(.nameColor(name: "Kick", color: red)), Block(.nameColor(name: nil, color: red)),
                      Block(.nameColor(name: "Voix", color: nil))]
        XCTAssertEqual(try roundTrip(blocks), blocks)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(blocks[0])) as? [String: Any]
        XCTAssertEqual(object?["name"] as? String, "Kick")
        XCTAssertEqual(object?["color"] as? String, "E0453A")
        let colorOnly = try JSONSerialization.jsonObject(with: JSONEncoder().encode(blocks[1])) as? [String: Any]
        XCTAssertNil(colorOnly?["name"])
        // Couleur hors format, nom qui n'est pas un texte : bloc illisible, conservé et bloquant.
        for raw in [#"{"type":"nameColor","color":"ZZZ"}"#, #"{"type":"nameColor","name":12}"#] {
            let b = try JSONDecoder().decode(Block.self, from: Data(raw.utf8))
            guard case .unknown(let type, _) = b.body else { return XCTFail(raw) }
            XCTAssertEqual(type, "nameColor")
        }
        let lower = try JSONDecoder().decode(Block.self, from: Data(##"{"type":"nameColor","color":"#e0453a"}"##.utf8))
        XCTAssertEqual(lower.body, .nameColor(name: nil, color: red))
    }

    /// Dégradé (« fade ») et icône : clés JSON facultatives ; une valeur illisible rend le bloc illisible (bloquant).
    func testNameColorFadeJSONRoundTrip() throws {
        let first = try XCTUnwrap(RGBColor(hex: "F2A0D8"))
        let last = try XCTUnwrap(RGBColor(hex: "C02890"))
        let icon = try XCTUnwrap(FLIcon(code: "3-7"))
        let blocks = [Block(.nameColor(name: nil, color: first, fade: last)),
                      Block(.nameColor(name: "Kick", color: first, icon: icon))]
        XCTAssertEqual(try roundTrip(blocks), blocks)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(blocks[0])) as? [String: Any]
        XCTAssertEqual(object?["fade"] as? String, "C02890")
        XCTAssertNil(object?["icon"])
        let withIcon = try JSONSerialization.jsonObject(with: JSONEncoder().encode(blocks[1])) as? [String: Any]
        XCTAssertEqual(withIcon?["icon"] as? String, "3-7")
        for raw in [#"{"type":"nameColor","color":"F2A0D8","fade":"nope"}"#,
                    #"{"type":"nameColor","color":"F2A0D8","icon":"14-0"}"#,
                    #"{"type":"nameColor","color":"F2A0D8","icon":7}"#] {
            let b = try JSONDecoder().decode(Block.self, from: Data(raw.utf8))
            guard case .unknown(let type, _) = b.body else { return XCTFail(raw) }
            XCTAssertEqual(type, "nameColor")
        }
        XCTAssertEqual(NameColorPayload.summary(name: nil, color: first, fade: last), "dégradé #F2A0D8 → #C02890")
    }

    /// Même arrondi que le script et que « Gradient color… » de FL : E0453A → 3FA7E0, milieu 90768D.
    func testLerpMatchesScript() throws {
        let a = try XCTUnwrap(RGBColor(hex: "E0453A"))
        let b = try XCTUnwrap(RGBColor(hex: "3FA7E0"))
        XCTAssertEqual(a.lerp(b, 0.5).hex, "90768D")
        XCTAssertEqual(a.lerp(b, 0), a)
        XCTAssertEqual(a.lerp(b, 1), b)
        XCTAssertEqual(a.lerp(b, 2), b)                                     // borné
        XCTAssertEqual(GradientField.defaultLast(for: RGBColor(r: 200, g: 100, b: 0)), RGBColor(r: 110, g: 55, b: 0))
    }

    func testIconCodeRoundTrip() {
        XCTAssertEqual(FLIcon(code: "3-7")?.code, "3-7")
        XCTAssertEqual(FLIcon(code: "0-0")?.isReset, true)
        for bad in ["14-0", "0-15", "-1-2", "a-b", "3", "3-7-1", "03-7", " 3-7"] {
            XCTAssertNil(FLIcon(code: bad), bad)
        }
    }

    func testNameColorTexts() {
        let red = NameColorPayload.defaultColor
        XCTAssertEqual(NameColorPayload.summary(name: "Kick", color: red), "Kick · #E0453A")
        XCTAssertEqual(NameColorPayload.summary(name: " Kick ", color: nil), "Kick")
        XCTAssertEqual(NameColorPayload.summary(name: nil, color: red), "couleur #E0453A")
        XCTAssertEqual(NameColorPayload.message(forReason: 1), "Ouvre le Mixer, le Channel rack ou la Playlist.")
        XCTAssertEqual(NameColorPayload.message(forReason: 2), "Sélectionne une piste ou un canal.")
        XCTAssertEqual(NameColorPayload.message(forReason: 3), "Sélectionne une seule piste ou un seul canal.")
        XCTAssertEqual(NameColorPayload.message(forReason: 4), "Arrête la lecture d'abord.")
        XCTAssertEqual(NameColorPayload.message(forReason: 5), "FL a refusé le nom ou la couleur.")
        XCTAssertEqual(NameColorPayload.message(forReason: 6), "Ta version de FL ne le permet pas sur cette page : mets FL à jour.")
    }


    /// Fenêtre de couleur de FL : échelle de FL (relevé : RVB 88, 110, 124 → 203, 40, 100), roue à 16 secteurs.
    func testFLColorScaleAndWheel() {
        let v = RGBColor(r: 88, g: 110, b: 124).flHSL
        XCTAssertEqual(v.hue, 203)
        XCTAssertTrue((40...41).contains(v.saturation), "\(v.saturation)")
        XCTAssertEqual(v.luminance, 100)
        // Aller-retour HSL ↔ RVB à un pas d'arrondi près.
        for c in [RGBColor(r: 254, g: 105, b: 110), RGBColor(r: 46, g: 253, b: 197), RGBColor(r: 12, g: 12, b: 12)] {
            let back = RGBColor(flHSL: c.flHSL)
            XCTAssertLessThanOrEqual(abs(Int(back.r) - Int(c.r)) + abs(Int(back.g) - Int(c.g)) + abs(Int(back.b) - Int(c.b)), 9, c.hex)
        }
        XCTAssertEqual(FLColorWheel.pale.count, 16)
        XCTAssertEqual(FLColorWheel.medium.count, 16)
        XCTAssertEqual(FLColorWheel.vivid.count, 16)
        // Rouge vif en haut, centre gris, à droite le 5e secteur (90°), rien hors de la roue.
        XCTAssertEqual(FLColorWheel.hit(dx: 0, dy: 0)?.ring, 0)
        let top = FLColorWheel.hit(dx: 0, dy: -0.6)
        XCTAssertEqual(top?.ring, 3)
        XCTAssertEqual(top?.sector, 0)
        XCTAssertEqual(FLColorWheel.color(ring: 3, sector: 0), RGBColor(r: 254, g: 105, b: 110))
        let right = FLColorWheel.hit(dx: 0.9, dy: 0)
        XCTAssertEqual(right?.ring, 5)
        XCTAssertEqual(right?.sector, 4)
        XCTAssertEqual(FLColorWheel.hit(dx: 0.3, dy: -0.95)?.sector, 1)        // un peu à droite du haut
        XCTAssertNil(FLColorWheel.hit(dx: 1.05, dy: 0))
        // Anneaux sombres : même teinte que le vif, plus foncés.
        let dark = FLColorWheel.color(ring: 5, sector: 0).flHSL
        XCTAssertLessThan(dark.luminance, FLColorWheel.color(ring: 4, sector: 0).flHSL.luminance)
        let d = abs(dark.hue - FLColorWheel.vivid[0].flHSL.hue)
        XCTAssertLessThan(min(d, 360 - d), 3)                                 // le rouge est près de 360°
    }


    /// Carte son : une carte externe avec sortie (de préférence avec entrée), celle de la dernière fois d'abord ;
    /// jamais les haut-parleurs du Mac, l'HDMI ni le Bluetooth.
    func testSoundCardChoice() {
        func dev(_ id: UInt32, _ name: String, _ transport: UInt32, inputs: Int, outputs: Int) -> AudioDeviceInfo {
            AudioDeviceInfo(id: id, uid: "uid-\(id)", name: name, transport: transport, inputs: inputs, outputs: outputs)
        }
        let speakers = dev(1, "Haut-parleurs MacBook Pro", kAudioDeviceTransportTypeBuiltIn, inputs: 0, outputs: 1)
        let mic = dev(2, "Micro MacBook Pro", kAudioDeviceTransportTypeBuiltIn, inputs: 1, outputs: 0)
        let hdmi = dev(3, "HDMI", kAudioDeviceTransportTypeHDMI, inputs: 0, outputs: 1)
        let ssl = dev(4, "SSL 2+", kAudioDeviceTransportTypeUSB, inputs: 1, outputs: 1)
        let dac = dev(5, "DAC USB", kAudioDeviceTransportTypeUSB, inputs: 0, outputs: 1)
        let bt = dev(6, "AirPods", kAudioDeviceTransportTypeBluetooth, inputs: 1, outputs: 1)
        XCTAssertNil(SoundCard.choose([speakers, mic, hdmi, bt], preferredUID: nil))
        XCTAssertEqual(SoundCard.choose([speakers, mic, hdmi, ssl, bt], preferredUID: nil), ssl)
        XCTAssertEqual(SoundCard.choose([dac, ssl], preferredUID: nil), ssl)           // avec entrée d'abord
        XCTAssertEqual(SoundCard.choose([speakers, dac], preferredUID: nil), dac)      // sinon sortie seule
        let ssl2 = dev(7, "Scarlett 2i2", kAudioDeviceTransportTypeUSB, inputs: 1, outputs: 1)
        XCTAssertEqual(SoundCard.choose([ssl, ssl2], preferredUID: "uid-7"), ssl2)     // celle de la dernière fois
        XCTAssertEqual(SoundCard.choose([ssl, ssl2], preferredUID: "uid-99"), ssl)
        // Choisie dans la fiche du bloc : toujours elle si elle est branchée, même hors des cartes « externes ».
        let display = dev(8, "Studio Display", kAudioDeviceTransportTypeUSB, inputs: 1, outputs: 1)
        XCTAssertEqual(SoundCard.choose([display, ssl], preferredUID: nil, chosenUID: "uid-4"), ssl)
        XCTAssertEqual(SoundCard.choose([display, ssl], preferredUID: "uid-8", chosenUID: "uid-4"), ssl)
        XCTAssertEqual(SoundCard.choose([speakers, ssl], preferredUID: nil, chosenUID: "uid-1"), speakers)
        XCTAssertEqual(SoundCard.choose([display, ssl], preferredUID: nil, chosenUID: "uid-99"), display, "pas branchée")
        let aggregate = dev(9, "Agrégé", kAudioDeviceTransportTypeAggregate, inputs: 1, outputs: 1)
        XCTAssertEqual(SoundCard.selectable([speakers, mic, aggregate, ssl]).map(\.id), [1, 4])
        XCTAssertEqual(SoundCard.fourCC(kAudioDeviceTransportTypeUSB), "usb ")
    }

}
