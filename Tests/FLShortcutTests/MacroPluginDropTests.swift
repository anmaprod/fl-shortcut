// Plugin ouvert en déposant son .fst de la Plugin database de FL (essais du propriétaire, 04/11) : le bon fichier (.fst,
// format préféré), et le point juste sous le dernier son du Channel rack (jamais sur un son).
import CoreGraphics
import XCTest
@testable import FLShortcut

final class MacroPluginDropTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("fls-plugin-db-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    private func put(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: url)
        return url
    }

    func testTheFstOfThePreferredFormatIsChosen() throws {
        try put("Installed/Generators/VST3/Analog Lab V.nfo")
        try put("Installed/Generators/VST3/Analog Lab V.fst")
        try put("Installed/Generators/VST/Analog Lab V.fst")
        try put("Installed/Effects/AudioUnit/Pro-Q 3.fst")
        try put("Installed/Effects/VST3/Pro-Q 3.fst")
        try put("Installed/Generators/VST3/Keys.nfo")                    // seulement un .nfo : rien
        let instrument = try XCTUnwrap(PluginDrop.presetFile(named: "Analog Lab V", effect: false, root: root))
        XCTAssertEqual(instrument.pathExtension, "fst")
        XCTAssertEqual(instrument.deletingLastPathComponent().lastPathComponent, "VST3")
        let effect = try XCTUnwrap(PluginDrop.presetFile(named: "Pro-Q 3", effect: true, root: root))
        XCTAssertEqual(effect.deletingLastPathComponent().lastPathComponent, "AudioUnit")
        XCTAssertNil(PluginDrop.presetFile(named: "Keys", effect: false, root: root))
        XCTAssertNil(PluginDrop.presetFile(named: "Pro-Q 3", effect: false, root: root), "un effet n'est pas un instrument")
        XCTAssertEqual(PluginDrop.formatKey("AudioUnit"), "au")
        XCTAssertEqual(PluginDrop.formatKey("VST2"), "vst")
    }

    /// 06/11 (« il n'y a que pour Analog Lab que ça fonctionne ») : le .fst trouvé partout dans la base (sous-dossiers,
    /// favoris de FL), même au nom un peu différent (marque, format), jamais un autre numéro.
    func testEveryPluginIsFoundInTheWholeDatabase() throws {
        try put("Installed/Generators/VST3/Arturia/Pigments.fst")                  // un sous-dossier de plus
        try put("Generators/Synth classic/Sytrus.fst")                             // seulement dans les favoris
        try put("Installed/Generators/Fruity/Sytrus.nfo")
        try put("Installed/Effects/VST3/FabFilter Pro-Q 3.fst")                    // la marque devant
        try put("Installed/Generators/VST/Kontakt 7 (VST3).fst")                   // le format derrière
        try put("Installed/Generators/VST3/Serum 2.fst")                           // un autre plugin
        try put("Generators/FL Shortcuts/Vital.fst")                               // ancienne catégorie : ignorée
        XCTAssertEqual(PluginDrop.presetFile(named: "Pigments", effect: false, root: root)?.lastPathComponent, "Pigments.fst")
        XCTAssertEqual(PluginDrop.presetFile(named: "Sytrus", effect: false, root: root)?.lastPathComponent, "Sytrus.fst")
        XCTAssertEqual(PluginDrop.presetFile(named: "Pro-Q 3", effect: true, root: root)?.lastPathComponent, "FabFilter Pro-Q 3.fst")
        XCTAssertEqual(PluginDrop.presetFile(named: "Kontakt 7", effect: false, root: root)?.lastPathComponent, "Kontakt 7 (VST3).fst")
        XCTAssertNil(PluginDrop.presetFile(named: "Serum", effect: false, root: root), "Serum n'ouvre pas Serum 2")
        XCTAssertNil(PluginDrop.presetFile(named: "Vital", effect: false, root: root))
        XCTAssertNil(PluginDrop.presetFile(named: "Pro-Q 4", effect: true, root: root))
    }

    private func item(_ text: String, _ x: CGFloat, _ y: CGFloat, w: CGFloat = 60) -> TextLook.Item {
        TextLook.Item(text: text, box: CGRect(x: x, y: y, width: w, height: 12))
    }

    func testTheDropPointIsJustUnderTheLastChannel() throws {
        let rack = [
            item("Channel rack", 300, 100, w: 90), item("All", 420, 100, w: 20),
            item("Kick", 360, 140), item("Snare", 360, 166), item("Hat", 360, 192), item("Clap", 360, 218),
            item("Track 1", 40, 400), item("Track 2", 40, 430),
        ]
        let p = try XCTUnwrap(PluginDrop.channelRackPoint(in: rack))
        XCTAssertEqual(p.x, 390, accuracy: 0.5)
        XCTAssertEqual(p.y, 237, accuracy: 0.5, "sur le trait sous le dernier son")
        XCTAssertGreaterThan(p.y, 218 + 12)
        let withGap = rack.filter { $0.text != "Snare" }
        XCTAssertEqual(try XCTUnwrap(PluginDrop.channelRackPoint(in: withGap)).y, 237, accuracy: 0.5)
    }

    /// Channel rack coupé (vidéo du 04/11) : juste au-dessus du premier son, dans l'espace sous le titre.
    func testACutChannelRackGetsTheDropAboveTheFirstChannel() throws {
        var rack = [item("Channel rack", 300, 100, w: 90), item("Kick", 360, 140), item("Snare", 360, 166), item("Hat", 360, 192)]
        XCTAssertEqual(try XCTUnwrap(PluginDrop.channelRackPoint(in: rack)).y, 211, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(PluginDrop.channelRackPoint(in: rack, bottom: 225)).y, 133, accuracy: 0.5)
        rack.append(TextLook.Item(text: "Clap", box: CGRect(x: 360, y: 218, width: 60, height: 6)))   // lu à moitié
        XCTAssertEqual(try XCTUnwrap(PluginDrop.channelRackPoint(in: rack)).y, 133, accuracy: 0.5)
    }

    /// 13/11 (vidéo : Diva.fst glissé à la main marche, la macro passait par le menu Add) : le titre est trouvé même avec
    /// l'icône du haut-parleur lue devant, un mot collé derrière ou en deux mots, comme sur Windows ; deux sons suffisent.
    func testTheChannelRackTitleIsFoundWithItsIconOrAnotherWord() throws {
        func rack(_ title: TextLook.Item...) -> [TextLook.Item] {
            title + [item("bass", 360, 140, w: 34), item("kick", 360, 170, w: 30)]
        }
        let alone = try XCTUnwrap(PluginDrop.channelRackPoint(in: rack(item("Channel rack", 300, 100, w: 90))))
        XCTAssertEqual(alone.y, 191, accuracy: 0.5, "sous « kick », jamais dessus")
        XCTAssertEqual(PluginDrop.channelRackPoint(in: rack(item("4) Channel rack", 270, 100, w: 120))), alone)
        XCTAssertEqual(PluginDrop.channelRackPoint(in: rack(item("Channel rack All", 300, 100, w: 130))), alone)
        XCTAssertEqual(PluginDrop.channelRackPoint(in: rack(item("Channel", 300, 100, w: 50), item("rack", 354, 100, w: 30))), alone)
        XCTAssertTrue(PluginDrop.pageShown(effect: false, in: [item("◁ Channel rack", 280, 100, w: 110)]))
        XCTAssertFalse(PluginDrop.pageShown(effect: false, in: [item("Channel racks", 300, 100, w: 90)]))
        XCTAssertFalse(PluginDrop.pageShown(effect: false, in: [item("Open the Channel rack", 300, 100, w: 160)]))
    }

    /// 13/11 : la page que le bloc d'avant vient d'ouvrir est attendue avant d'appuyer sur sa touche (une 2e touche la
    /// refermait) ; la touche une seule fois ; jamais quand la page est là.
    func testTheDropWaitsForThePageBeforePressingItsKey() {
        XCTAssertEqual(DropPageWait.next(waited: 0, sinceKey: nil, seen: false), .read)
        XCTAssertEqual(DropPageWait.next(waited: 1.25, sinceKey: nil, seen: false), .read)
        XCTAssertEqual(DropPageWait.next(waited: 1.5, sinceKey: nil, seen: false), .pressKey)
        XCTAssertEqual(DropPageWait.next(waited: 1.5, sinceKey: nil, seen: true), .giveUp)
        XCTAssertEqual(DropPageWait.next(waited: 3, sinceKey: 2.25, seen: false), .read)
        XCTAssertEqual(DropPageWait.next(waited: 4, sinceKey: 2.5, seen: false), .giveUp)
    }

    func testInDoubtThereIsNoDropPoint() {
        XCTAssertNil(PluginDrop.channelRackPoint(in: [item("Kick", 360, 140), item("Snare", 360, 166)]))
        XCTAssertNil(PluginDrop.channelRackPoint(in: [item("Channel rack", 300, 100, w: 90), item("Kick", 360, 140)]))
        XCTAssertNil(PluginDrop.channelRackPoint(in: [
            item("Channel rack", 300, 100, w: 90), item("Kick", 360, 140), item("Snare", 360, 166), item("Hat", 360, 203),
        ]))
    }

    /// Vidéo du 05/11 (FL 2025) : le titre « Channel rack » est à ~100 points à droite des noms, centrés dans leur
    /// bouton ; « Unsorted » sur la ligne du titre ; le Browser loin à gauche.
    func testTheNamesLeftOfTheTitleAreFound() throws {
        let rack = [
            item("Unsorted", 244, 46, w: 60), item("Channel rack", 369, 46, w: 80),
            item("bass", 270, 94, w: 23), item("kick", 271.5, 124, w: 20),
            item("dash38", 20, 100), item("dryykt", 20, 110), item("dyajp", 20, 120), item("icon", 20, 130),
        ]
        let p = try XCTUnwrap(PluginDrop.channelRackPoint(in: rack))
        XCTAssertEqual(p.x, 281.5, accuracy: 1)
        XCTAssertEqual(p.y, 145, accuracy: 0.5, "dans l'espace sous « kick »")
        // Noms de longueurs différentes, centrés : une seule colonne.
        let mixed = [item("Channel rack", 369, 46, w: 80), item("Kick", 271, 94, w: 20), item("ZENOLOGY Lead", 241, 124, w: 80),
                     item("Hat", 273, 154, w: 16)]
        XCTAssertEqual(try XCTUnwrap(PluginDrop.channelRackPoint(in: mixed)).y, 175, accuracy: 0.5)
    }

    /// 06/11 : l'effet va dans la première case libre de la piste choisie du Mixer (« Slot 3 » avant « Slot 7 »),
    /// même lue de travers (« Slot l ») ; rien si aucune case libre n'est lue.
    func testTheEffectGoesToTheFirstFreeSlotOfTheSelectedTrack() throws {
        let mixer = [item("Insert 1", 200, 400), item("Fruity Limiter", 900, 120, w: 90), item("Slot 7", 900, 300),
                     item("Slot 3", 900, 180), item("Master", 60, 400)]
        let p = try XCTUnwrap(PluginDrop.mixerSlotPoint(in: mixer))
        XCTAssertEqual(p.y, 186, accuracy: 0.5)
        XCTAssertEqual(try XCTUnwrap(PluginDrop.mixerSlotPoint(in: [item("Slot l", 900, 140)])).y, 146, accuracy: 0.5)
        XCTAssertNil(PluginDrop.mixerSlotPoint(in: [item("Slot machine", 900, 140), item("Insert 2", 300, 400)]))
        // 07/11 (vidéo : l'effet allait sur une autre piste) : la flèche devant la case, ou les mots collés.
        XCTAssertEqual(PluginDrop.slotNumber("▶ Slot 3"), 3)
        XCTAssertEqual(PluginDrop.slotNumber("> Slot 2"), 2)
        XCTAssertEqual(PluginDrop.slotNumber("Slot10"), 10)
        XCTAssertEqual(PluginDrop.slotNumber("SIot 1"), 1)
        XCTAssertNil(PluginDrop.slotNumber("Auto-Tune Pro"))
        XCTAssertTrue(PluginDrop.pageShown(effect: true, in: [item("Mixer - Insert 11", 900, 40, w: 120)]))
        XCTAssertTrue(PluginDrop.pageShown(effect: false, in: [item("Channel rack", 300, 100, w: 90)]))
        XCTAssertFalse(PluginDrop.pageShown(effect: false, in: [item("Playlist - Arrangement", 300, 100, w: 160)]))
    }
}
