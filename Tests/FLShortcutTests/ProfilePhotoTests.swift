import CoreGraphics
import ImageIO
import XCTest
@testable import FLShortcut

/// Photo de profil préparée sur le Mac : carré choisi (zoom, position), 256 × 256, JPEG assez petit pour le serveur ;
/// sans photo, l'initiale sur une couleur tirée du pseudo.
final class ProfilePhotoTests: XCTestCase {
    /// Image d'essai : moitié gauche rouge, moitié droite bleue.
    private func picture(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return ctx.makeImage()!
    }

    func testCropRectFollowsZoomAndPosition() {
        // Paysage 800 × 600 : le plus grand carré centré, puis plus petit avec le zoom, puis poussé au bord.
        XCTAssertEqual(ProfilePhoto.cropRect(width: 800, height: 600, zoom: 1, offset: .zero), CGRect(x: 100, y: 0, width: 600, height: 600))
        XCTAssertEqual(ProfilePhoto.cropRect(width: 800, height: 600, zoom: 2, offset: .zero), CGRect(x: 250, y: 150, width: 300, height: 300))
        XCTAssertEqual(ProfilePhoto.cropRect(width: 800, height: 600, zoom: 2, offset: CGPoint(x: -1, y: 1)),
                       CGRect(x: 0, y: 300, width: 300, height: 300))
        // Bornes : zoom sous 1 ramené à 1, décalage au-delà de ±1 ramené au bord.
        XCTAssertEqual(ProfilePhoto.cropRect(width: 600, height: 900, zoom: 0.2, offset: CGPoint(x: 5, y: -5)),
                       CGRect(x: 0, y: 0, width: 600, height: 600))
    }

    func testJpegIsSmallSquareAndReadable() throws {
        let data = try XCTUnwrap(ProfilePhoto.jpeg(from: picture(width: 1600, height: 1200)))
        XCTAssertTrue(ProfilePhoto.isAcceptable(data), "\(data.count) octets")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, ProfilePhoto.side)
        XCTAssertEqual(image.height, ProfilePhoto.side)
        // Poussé tout à gauche avec le zoom : il ne reste que du rouge.
        let left = try XCTUnwrap(ProfilePhoto.jpeg(from: picture(width: 1600, height: 1200), zoom: 3, offset: CGPoint(x: -1, y: 0)))
        let pixel = try XCTUnwrap(centerPixel(left))
        XCTAssertGreaterThan(pixel.red, 200)
        XCTAssertLessThan(pixel.blue, 60)
    }

    private func centerPixel(_ jpeg: Data) -> (red: Int, blue: Int)? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        var buffer = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &buffer, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        ctx?.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
                                    width: CGFloat(image.width), height: CGFloat(image.height)))
        return (Int(buffer[0]), Int(buffer[2]))
    }

    func testAcceptableJpegOnly() {
        XCTAssertFalse(ProfilePhoto.isAcceptable(Data()))
        XCTAssertFalse(ProfilePhoto.isAcceptable(Data("<svg/>".utf8)))
        XCTAssertFalse(ProfilePhoto.isAcceptable(Data([0x89, 0x50, 0x4E, 0x47, 0x0D])), "PNG refusé : l'app envoie du JPEG")
        XCTAssertTrue(ProfilePhoto.isAcceptable(Data([0xFF, 0xD8, 0xFF, 0xE0, 0])))
        XCTAssertFalse(ProfilePhoto.isAcceptable(Data([0xFF, 0xD8, 0xFF]) + Data(count: ProfilePhoto.maxBytes)))
    }

    /// Sans photo : la même couleur et la même lettre pour un pseudo, sur tous les Mac, majuscules comprises.
    func testInitialAndColorComeFromTheUsername() {
        XCTAssertEqual(ProfilePhoto.initial("malo.beats"), "M")
        XCTAssertEqual(ProfilePhoto.initial("_2pac"), "2")
        XCTAssertEqual(ProfilePhoto.initial(""), "?")
        XCTAssertEqual(ProfilePhoto.colorIndex("Malo"), ProfilePhoto.colorIndex("malo"))
        XCTAssertTrue((0..<ProfilePhoto.initialColors.count).contains(ProfilePhoto.colorIndex("prod.nina")))
        let spread = Set(["malo", "leo.beats", "sarah.mix", "prod.nina", "nina", "zoe", "max", "lea"].map(ProfilePhoto.colorIndex))
        XCTAssertGreaterThan(spread.count, 3, "les couleurs varient d'un membre à l'autre")
    }
}
