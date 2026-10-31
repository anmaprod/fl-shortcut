import AppKit
import XCTest
@testable import FLShortcut

/// Organiser : où faire le clic droit qui pose une icône (le nom de l'élément, lu dans la fenêtre de FL).
final class OrganizerIconTargetsTests: XCTestCase {
    private func item(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 40, height: CGFloat = 12) -> TextLook.Item {
        TextLook.Item(text: text, box: CGRect(x: x, y: y, width: width, height: height))
    }

    /// Channel rack (vidéo du 31/10) : noms centrés dans leurs boutons, en colonne. Un nom coupé par FL
    /// (« Serum..ad ») prend sa place entre ses voisins ; rien au-delà du dernier nom lu.
    func testChannelColumn() throws {
        let names = ["Kick", "Snare", "Serum 2 Lead", "808", "Vox"]
        let items = [item("Kick", x: 340, y: 100, width: 20), item("Snare", x: 337, y: 120, width: 26),
                     item("Serum..ad", x: 330, y: 140, width: 40), item("808", x: 342, y: 160, width: 16),
                     // Navigateur à gauche : mêmes noms, pas dans l'ordre.
                     item("808", x: 20, y: 90), item("Kick", x: 20, y: 300)]
        let points = try XCTUnwrap(IconTargets.line(names: names, items: items))
        XCTAssertEqual(points[0], CGPoint(x: 350, y: 106))
        XCTAssertEqual(points[1], CGPoint(x: 350, y: 126))
        XCTAssertEqual(try XCTUnwrap(points[2]).y, 146, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(points[2]).x, 350, accuracy: 0.01)
        XCTAssertEqual(points[3], CGPoint(x: 350, y: 166))
        XCTAssertNil(points[4], "jamais deviné au-delà du dernier nom lu")
    }

    /// Les pistes de la Playlist portent les mêmes noms dans le même ordre : à égalité, la colonne la plus proche du
    /// titre « Channel rack » ; sans titre, aucune (doute).
    func testTieGoesToTheChannelRackTitle() throws {
        let names = ["Kick", "Snare", "808"]
        let rack = [item("Kick", x: 400, y: 100), item("Snare", x: 400, y: 120), item("808", x: 400, y: 140)]
        let playlist = [item("Kick", x: 10, y: 200), item("Snare", x: 10, y: 260), item("808", x: 10, y: 320)]
        XCTAssertNil(IconTargets.line(names: names, items: rack + playlist))
        let points = try XCTUnwrap(IconTargets.line(names: names, items: playlist + rack, near: CGPoint(x: 440, y: 70)))
        XCTAssertEqual(points[1], CGPoint(x: 420, y: 126))
        // Plus de noms lus dans une colonne : elle l'emporte, titre ou non.
        let more = try XCTUnwrap(IconTargets.line(names: names, items: rack + Array(playlist.prefix(2))))
        XCTAssertEqual(more[2], CGPoint(x: 420, y: 146))
        XCTAssertNil(IconTargets.line(names: names, items: [item("Kick", x: 400, y: 100)]), "un seul nom : rien")
    }

    /// Mixer : noms écrits à la verticale, alignés en bas, lus de gauche à droite (Master, puis les pistes).
    func testMixerRow() throws {
        let names = ["Master", "Insert 1", "Drums", "Insert 3", "Insert 4"]
        let items = [item("Master", x: 20, y: 200, width: 12, height: 44),
                     item("Insert 1", x: 60, y: 196, width: 12, height: 48),
                     item("Insert 3", x: 140, y: 196, width: 12, height: 48),
                     item("Insert 4", x: 180, y: 196, width: 12, height: 48)]
        let points = try XCTUnwrap(IconTargets.line(names: names, items: items, across: true))
        XCTAssertEqual(points[0], CGPoint(x: 26, y: 222))
        XCTAssertEqual(points[1], CGPoint(x: 66, y: 220))
        XCTAssertEqual(try XCTUnwrap(points[2]).x, 106, accuracy: 0.01, "« Drums » non lu : entre ses voisins")
        XCTAssertEqual(points[4], CGPoint(x: 186, y: 220))
    }

    func testNamesInFLOrder() {
        let mixer = [MixerTrackInfo(index: 0, color: RGBColor(r: 0, g: 0, b: 0), name: ""),
                     MixerTrackInfo(index: 2, color: RGBColor(r: 0, g: 0, b: 0), name: "Drums"),
                     MixerTrackInfo(index: 3, color: RGBColor(r: 0, g: 0, b: 0), name: " ")]
        XCTAssertEqual(IconTarget.mixerNames(mixer), ["Master", "Insert 1", "Drums", "Insert 3"])
        let channels = [ChannelInfo(index: 1, type: 2, mixerTrack: 0, color: RGBColor(r: 0, g: 0, b: 0), name: "Snare"),
                        ChannelInfo(index: 0, type: 2, mixerTrack: 0, color: RGBColor(r: 0, g: 0, b: 0), name: "Kick")]
        XCTAssertEqual(IconTarget.channelNames(channels), ["Kick", "Snare"])
        XCTAssertEqual(IconTarget.mixerNames([]), [])
    }

    // MARK: Image tournée d'un quart de tour

    /// Image RGBA de `width` × `height` pixels, noire, un pixel rouge en (`x`, `y`) (origine en haut à gauche).
    private func image(width: Int, height: Int, red x: Int, _ y: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        pixels[(y * width + x) * 4] = 255
        return try XCTUnwrap(context.makeImage())
    }

    /// Le pixel rouge de `image` (origine en haut à gauche).
    private func red(in image: CGImage) throws -> (x: Int, y: Int)? {
        let width = image.width, height = image.height
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4] > 128 { return (x, y) }
        }
        return nil
    }

    /// Un cadre lu dans l'image tournée revient à sa place dans la fenêtre, dans les deux sens.
    func testTurnedImageMapsBack() throws {
        let original = try image(width: 40, height: 20, red: 5, 3)
        for clockwise in [true, false] {
            let turned = try XCTUnwrap(IconTargets.turned(original, clockwise: clockwise))
            XCTAssertEqual(turned.width, 20)
            XCTAssertEqual(turned.height, 40)
            let spot = try XCTUnwrap(try red(in: turned), "sens \(clockwise)")
            let back = IconTargets.unturned(CGRect(x: spot.x, y: spot.y, width: 1, height: 1), clockwise: clockwise,
                                            size: CGSize(width: 40, height: 20))
            XCTAssertEqual(back, CGRect(x: 5, y: 3, width: 1, height: 1), "sens \(clockwise)")
        }
    }

    /// Texte de `size` points à 2 pixels par point, écrit en blanc sur noir ; `vertical` : de bas en haut, comme les
    /// noms du Mixer de FL, sa ligne de base sur x = 100, son début 60 points au-dessus du bas.
    private func render(_ text: String, size: CGSize, vertical: Bool) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(size.width * 2), height: Int(size.height * 2),
                                              bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size.width * 2, height: size.height * 2))
        context.scaleBy(x: 2, y: 2)
        if vertical {
            context.translateBy(x: 100, y: 60)
            context.rotate(by: .pi / 2)
        } else {
            context.translateBy(x: 20, y: 60)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 18),
                                                      .foregroundColor: NSColor.white]).draw(at: .zero)
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(context.makeImage())
    }

    /// Lecture sur le Mac (Vision) d'un nom écrit à la verticale : retrouvé, à sa place dans la fenêtre.
    func testReadsVerticalNames() throws {
        let size = CGSize(width: 200, height: 300)
        let flat = TextLook.read(try render("Insert 12", size: size, vertical: false), size: size)
        guard flat.contains(where: { TextLook.normalized($0.text) == TextLook.normalized("Insert 12") }) else {
            throw XCTSkip("lecture de texte (Vision) indisponible ici")
        }
        let items = IconTargets.readVertical(try render("Insert 12", size: size, vertical: true), size: size)
        let found = try XCTUnwrap(items.first { TextLook.normalized($0.text) == TextLook.normalized("Insert 12") })
        // Repère de la fenêtre (origine en haut à gauche) : à gauche de x = 100, de y = 240 vers le haut.
        XCTAssertEqual(found.box.midX, 92, accuracy: 10)
        XCTAssertEqual(found.box.maxY, 240, accuracy: 8)
        XCTAssertGreaterThan(found.box.height, 50)
        XCTAssertLessThan(found.box.width, 30)
    }
}
