import AppKit
import SwiftUI
import XCTest
@testable import FLShortcut

/// Thèmes (04/11) : Noir, Papier, Orange ; les couleurs du style suisse suivent le thème et la partie (claire ou
/// sombre) au moment du dessin.
final class AppThemeTests: XCTestCase {
    override func tearDown() {
        AppTheme.use(.noir)
        super.tearDown()
    }

    private func srgb(_ color: NSColor, in name: NSAppearance.Name) throws -> NSColor {
        var resolved: NSColor?
        try XCTUnwrap(NSAppearance(named: name)).performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        return try XCTUnwrap(resolved)
    }

    private func hex(_ color: NSColor) -> UInt32 {
        let r = UInt32((color.redComponent * 255).rounded()), g = UInt32((color.greenComponent * 255).rounded())
        let b = UInt32((color.blueComponent * 255).rounded())
        return r << 16 | g << 8 | b
    }

    func testPalettesOfTheMockups() {
        XCTAssertEqual(SwissPalette.of(.noir, dark: true), .noir)
        XCTAssertEqual(SwissPalette.noir.background, 0x000000)
        XCTAssertEqual(SwissPalette.noir.text, 0xFFFFFF)
        // Direction A (17/11) : papier clair, encre presque noire, rouge plus profond.
        XCTAssertEqual(SwissPalette.of(.papier, dark: false).background, 0xF3F2EE)
        XCTAssertEqual(SwissPalette.of(.papier, dark: false).text, 0x111111)
        XCTAssertEqual(SwissPalette.of(.papier, dark: false).red, 0xFF3B1F)
        XCTAssertEqual(SwissPalette.of(.orange, dark: false).background, SwissPalette.brandRed)
        XCTAssertEqual(SwissPalette.of(.orange, dark: false).text, 0x000000)
        // Sous Orange, ce qui compte est blanc (le rouge ne se verrait pas sur le fond rouge) ; rouge dans les cartes.
        XCTAssertEqual(SwissPalette.of(.orange, dark: false).red, 0xFFFFFF)
        XCTAssertEqual(SwissPalette.of(.orange, dark: true).background, 0x000000)
        XCTAssertEqual(SwissPalette.of(.orange, dark: true).red, SwissPalette.brandRed)
        XCTAssertEqual(AppTheme.noir.appearanceName, .darkAqua)
        XCTAssertEqual(AppTheme.papier.appearanceName, .aqua)
        XCTAssertEqual(AppTheme.orange.appearanceName, .aqua)
    }

    /// Demande du 07/11 : les thèmes seulement avec un compte connecté ; sans compte, Papier (direction A du 17/11, pour
    /// tout le monde), et le choix revient à la connexion.
    @MainActor func testThemesOnlyWithAnAccount() {
        let defaults = UserDefaults.standard
        let theme = defaults.object(forKey: AppTheme.key), account = defaults.object(forKey: AppTheme.accountKey)
        defer {
            defaults.set(theme, forKey: AppTheme.key)
            defaults.set(account, forKey: AppTheme.accountKey)
        }
        AppTheme.use(nil)
        AppTheme.choose(.noir)
        AppTheme.accountChanged(signedIn: false)
        XCTAssertFalse(AppTheme.unlocked)
        XCTAssertEqual(AppTheme.current, .papier)
        XCTAssertEqual(AppTheme.chosen, .noir, "choix gardé pour la prochaine connexion")
        AppTheme.accountChanged(signedIn: true)
        XCTAssertEqual(AppTheme.current, .noir)
        XCTAssertTrue(defaults.bool(forKey: AppTheme.accountKey), "état gardé pour le lancement")
        AppTheme.accountChanged(signedIn: false)
        XCTAssertEqual(AppTheme.current, .papier)
        // Photos de la CI : un thème montré passe avant le compte.
        AppTheme.use(.orange)
        XCTAssertEqual(AppTheme.current, .orange)
        AppTheme.choose(.noir)
    }

    func testUnknownStoredValueIsNotATheme() {
        XCTAssertNil(AppTheme(rawValue: "violet"))
        XCTAssertEqual(AppTheme.allCases.map(\.rawValue), ["noir", "papier", "orange"])
    }

    func testAppKitColorsFollowTheThemeAndTheAppearance() throws {
        AppTheme.use(.papier)
        XCTAssertEqual(hex(try srgb(Swiss.NS.background, in: .aqua)), 0xF3F2EE)
        XCTAssertEqual(hex(try srgb(Swiss.NS.text, in: .aqua)), 0x111111)
        AppTheme.use(.orange)
        XCTAssertEqual(hex(try srgb(Swiss.NS.background, in: .aqua)), SwissPalette.brandRed)
        XCTAssertEqual(hex(try srgb(Swiss.NS.background, in: .darkAqua)), 0x000000)
        AppTheme.use(.noir)
        XCTAssertEqual(hex(try srgb(Swiss.NS.background, in: .darkAqua)), 0x000000)
        XCTAssertEqual(hex(try srgb(Swiss.NS.text, in: .darkAqua)), 0xFFFFFF)
    }

    /// Une partie sombre sous Orange (barre de gauche, carte) est dessinée par SwiftUI avec `colorScheme` sombre : les
    /// couleurs suisses doivent y prendre le noir, et l'orange ailleurs.
    @MainActor func testSwiftUIColorsFollowTheSchemeOfTheSurface() throws {
        AppTheme.use(.orange)
        func pixel(_ scheme: ColorScheme) throws -> NSColor {
            let view = Rectangle().fill(Swiss.background).frame(width: 8, height: 8).environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            let image = try XCTUnwrap(renderer.cgImage)
            let rep = NSBitmapImageRep(cgImage: image)
            return try XCTUnwrap(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh / 2)?.usingColorSpace(.sRGB))
        }
        let light = try pixel(.light), dark = try pixel(.dark)
        XCTAssertGreaterThan(light.redComponent, 0.9, "fond orange")
        XCTAssertLessThan(light.greenComponent, 0.4, "fond orange")
        XCTAssertLessThan(dark.redComponent + dark.greenComponent + dark.blueComponent, 0.2, "partie noire")
    }

    /// 22/11 (« trait blanc pour noir et orange alors que ça doit être que dans le blanc ») : la grille du Papier lit
    /// le thème suivi, qui change avec le thème montré (Papier → Noir, et Papier → Orange, même apparence de macOS).
    @MainActor func testPaperGridFollowsTheThemeShown() async throws {
        let watch = ThemeWatch.shared
        AppTheme.use(.noir)
        AppTheme.choose(.papier, save: false)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(watch.theme, .papier)
        AppTheme.choose(.noir, save: false)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(watch.theme, .noir, "plus de grille sous Noir")
        AppTheme.choose(.papier, save: false)
        try await Task.sleep(nanoseconds: 400_000_000)
        AppTheme.choose(.orange, save: false)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(watch.theme, .orange, "plus de grille sous Orange")
    }
}
