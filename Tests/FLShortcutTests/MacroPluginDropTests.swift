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
        XCTAssertEqual(p.y, 239, accuracy: 0.5, "sur le trait sous le dernier son")
        XCTAssertGreaterThan(p.y, 218 + 12)
        let withGap = rack.filter { $0.text != "Snare" }
        XCTAssertEqual(try XCTUnwrap(PluginDrop.channelRackPoint(in: withGap)).y, 239, accuracy: 0.5)
    }

    func testInDoubtThereIsNoDropPoint() {
        XCTAssertNil(PluginDrop.channelRackPoint(in: [item("Kick", 360, 140), item("Snare", 360, 166)]))
        XCTAssertNil(PluginDrop.channelRackPoint(in: [item("Channel rack", 300, 100, w: 90), item("Kick", 360, 140)]))
        XCTAssertNil(PluginDrop.channelRackPoint(in: [
            item("Channel rack", 300, 100, w: 90), item("Kick", 360, 140), item("Snare", 360, 166), item("Hat", 360, 203),
        ]))
    }
}
