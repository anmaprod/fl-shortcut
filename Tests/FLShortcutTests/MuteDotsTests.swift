import XCTest
@testable import FLShortcut

/// Mute / solo sans le lien (08/11) : le rond de la piste cliquée retrouvé tout seul, sur des fenêtres de FL dessinées
/// comme les vraies (Mixer, Channel rack, Playlist ; rond rose ou vert ; piste coupée : rond éteint). Fenêtres lues deux
/// fois plus fines que l'écran, comme dans l'app.
final class MuteDotsTests: XCTestCase {
    private struct Canvas {
        let width: Int, height: Int
        var pixels: [UInt8]

        init(_ width: Int, _ height: Int, _ c: (Int, Int, Int) = (52, 54, 58)) {
            self.width = width
            self.height = height
            pixels = [UInt8](repeating: 255, count: width * height * 4)
            rect(0, 0, width, height, c)
        }

        mutating func set(_ x: Int, _ y: Int, _ c: (Int, Int, Int)) {
            guard x >= 0, y >= 0, x < width, y < height else { return }
            let i = (y * width + x) * 4
            pixels[i] = UInt8(c.0); pixels[i + 1] = UInt8(c.1); pixels[i + 2] = UInt8(c.2)
        }

        mutating func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: (Int, Int, Int)) {
            for yy in y..<(y + h) { for xx in x..<(x + w) { set(xx, yy, c) } }
        }

        mutating func disk(_ cx: Int, _ cy: Int, _ r: Double, _ c: (Int, Int, Int)) {
            let reach = Int(r.rounded(.up))
            for dy in -reach...reach {
                for dx in -reach...reach where Double(dx * dx + dy * dy) <= r * r { set(cx + dx, cy + dy, c) }
            }
        }

        mutating func ring(_ cx: Int, _ cy: Int, _ r: Double, _ c: (Int, Int, Int)) {
            let reach = Int(r.rounded(.up)) + 1
            for dy in -reach...reach {
                for dx in -reach...reach {
                    let d = Double(dx * dx + dy * dy).squareRoot()
                    if abs(d - r) <= 1.2 { set(cx + dx, cy + dy, c) }
                }
            }
        }

        var image: RGBAImage { RGBAImage(width: width, height: height, pixels: pixels) }
    }

    private let pink = (225, 143, 184)
    private let green = (110, 220, 90)
    private let unlit = (92, 92, 96)

    /// Mixer : 12 pistes de 58 pixels, nom au-dessus, rond rose dessous, bouton et fader plus bas ; à droite, la colonne
    /// des voyants des effets (« Slot 1 » à 10), de la même couleur.
    private func mixer(muted: Set<Int> = []) -> Canvas {
        var c = Canvas(1400, 900)
        for t in 0..<12 {
            let x = 100 + t * 58
            c.rect(x - 20, 300, 40, 120, (60, 62, 66))                    // le nom (vertical)
            c.disk(x, 440, 5.5, muted.contains(t) ? unlit : pink)
            c.ring(x, 480, 12, (110, 110, 112))                           // bouton de panoramique
            c.rect(x - 4, 520, 8, 260, (40, 40, 42))                      // fader
        }
        for slot in 0..<10 { c.disk(1360, 200 + slot * 40, 5, pink) }     // voyants des effets
        return c
    }

    func testMixerTrackUnderTheClickedName() throws {
        let image = mixer().image
        let onName = try XCTUnwrap(MuteDots.target(in: image, click: (x: 274, y: 360)))   // piste 4 (x = 274)
        XCTAssertEqual(onName.page, .mixer)
        XCTAssertEqual(onName.x, 274, accuracy: 1)
        XCTAssertEqual(onName.y, 440, accuracy: 1)
        XCTAssertFalse(onName.inferred)
        // Clic sur le fader de la piste 7 : même piste.
        let onFader = try XCTUnwrap(MuteDots.target(in: image, click: (x: 450, y: 700)))
        XCTAssertEqual(onFader.x, 448, accuracy: 1)
    }

    func testMutedMixerTrackIsFoundBetweenItsNeighbours() throws {
        let t = try XCTUnwrap(MuteDots.target(in: mixer(muted: [4]).image, click: (x: 332, y: 360)))
        XCTAssertEqual(t.x, 332, accuracy: 1.5)
        XCTAssertEqual(t.y, 440, accuracy: 1)
        XCTAssertTrue(t.inferred)
    }

    func testEffectSlotsNextToTheMixerAreNeverClicked() {
        // Dernier clic dans la colonne des effets : ce n'est pas une piste, rien n'est cliqué.
        XCTAssertNil(MuteDots.target(in: mixer().image, click: (x: 1300, y: 320)))
    }

    /// Channel rack : 6 sons de 52 pixels ; rond, deux boutons, case du numéro, puis le nom ; pas à droite.
    private func channelRack(dot: (Int, Int, Int), muted: Set<Int> = []) -> Canvas {
        var c = Canvas(1200, 600, (46, 48, 52))
        for row in 0..<6 {
            let y = 80 + row * 52
            c.disk(60, y, 5.5, muted.contains(row) ? unlit : dot)
            c.ring(100, y, 10, (120, 120, 124))
            c.ring(140, y, 10, (120, 120, 124))
            c.rect(166, y - 12, 30, 24, (30, 30, 32))                    // numéro de la piste du Mixer
            c.rect(210, y - 18, 200, 36, (84, 86, 92))                   // le nom
            for step in 0..<16 where (step + row) % 3 == 0 {
                c.rect(430 + step * 34, y - 20, 26, 40, (200, 90, 60))   // pas allumés : pas des ronds
            }
        }
        return c
    }

    func testChannelRackDotLeftOfTheClickedName() throws {
        for dot in [pink, green] {
            let t = try XCTUnwrap(MuteDots.target(in: channelRack(dot: dot).image, click: (x: 300, y: 184)))  // 3e son
            XCTAssertEqual(t.page, .channelRack)
            XCTAssertEqual(t.x, 60, accuracy: 1)
            XCTAssertEqual(t.y, 184, accuracy: 1)
        }
        let muted = try XCTUnwrap(MuteDots.target(in: channelRack(dot: pink, muted: [2]).image, click: (x: 300, y: 186)))
        XCTAssertEqual(muted.y, 184, accuracy: 1.5)
        XCTAssertTrue(muted.inferred)
    }

    /// Playlist : en-têtes de 90 pixels, nom en haut à gauche, rond en bas à droite ; à droite, les clips.
    private func playlist() -> Canvas {
        var c = Canvas(1300, 800, (40, 42, 46))
        for track in 0..<7 {
            let top = 40 + track * 90
            c.rect(20, top + 2, 340, 86, (62, 64, 70))                    // l'en-tête
            c.rect(40, top + 14, 160, 22, (90, 92, 98))                   // « Track 1 »
            c.disk(338, top + 70, 5.5, pink)                             // en bas à droite
            if track % 2 == 0 { c.rect(400 + track * 40, top + 6, 300, 78, (120, 70, 200)) }   // un clip
        }
        return c
    }

    func testPlaylistDotAtTheBottomRightOfTheClickedHeader() throws {
        let image = playlist().image
        // 3e piste : en-tête de y = 220 à 310, rond à 290 ; clic en haut, sur le nom, tout en bas ; 1re piste : rond à 110.
        for (clickY, expected) in [(228.0, 290.0), (245.0, 290.0), (305.0, 290.0), (60.0, 110.0)] {
            let t = try XCTUnwrap(MuteDots.target(in: image, click: (x: 110, y: clickY)))
            XCTAssertEqual(t.page, .playlist)
            XCTAssertEqual(t.x, 338, accuracy: 1)
            XCTAssertEqual(t.y, expected, accuracy: 1, "clic à y = \(clickY)")
        }
    }

    func testNothingAroundTheClickGivesNothing() {
        XCTAssertNil(MuteDots.target(in: Canvas(400, 300).image, click: (x: 200, y: 150)))
        // Clic loin de toute piste (au milieu des clips de la Playlist) : rien.
        XCTAssertNil(MuteDots.target(in: playlist().image, click: (x: 1250, y: 300)))
    }
}
