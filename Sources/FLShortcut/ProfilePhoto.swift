// Photo de profil (Mon compte › Modifier le profil) : préparée sur le Mac avant l'envoi. L'image choisie est lue à
// l'endroit (orientation de l'appareil photo appliquée), réduite, recadrée en carré (zoom et position choisis dans la
// feuille), puis réduite à 256 × 256 et compressée en JPEG : 20 à 40 Ko, jamais plus de 72 Ko (le serveur en accepte 96
// en base64 : supabase/profil.sql). Sans photo : l'initiale du pseudo sur une couleur tirée du pseudo.
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum ProfilePhoto {
    /// Côté de la photo envoyée.
    static let side = 256
    /// Taille maximale du JPEG envoyé (≈ 96 Ko en base64 : la limite du serveur).
    static let maxBytes = 72_000
    /// Image choisie trop lourde pour être lue (une photo d'appareil fait 2 à 15 Mo).
    static let maxFileBytes = 40 << 20

    /// JPEG acceptable : assez petit, et vraiment un JPEG (commence par FF D8 FF).
    static func isAcceptable(_ data: Data) -> Bool {
        data.count <= maxBytes && data.count > 3 && data.starts(with: [0xFF, 0xD8, 0xFF])
    }

    /// L'image d'un fichier, à l'endroit et réduite (2048 points de côté au plus) ; nil : illisible ou trop lourde.
    static func load(_ url: URL) -> CGImage? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxFileBytes, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Pure (testée) : le carré visible de l'image, en pixels (origine en haut à gauche, comme `CGImage.cropping`).
    /// `zoom` ≥ 1 (1 : le plus grand carré centré) ; `offset` de -1 à 1 sur chaque axe : déplacement dans la marge.
    static func cropRect(width: Int, height: Int, zoom: Double, offset: CGPoint) -> CGRect {
        let w = Double(width), h = Double(height)
        let visible = min(w, h) / min(max(zoom, 1), 8)
        let dx = min(max(Double(offset.x), -1), 1), dy = min(max(Double(offset.y), -1), 1)
        let x = (w - visible) / 2 * (1 + dx), y = (h - visible) / 2 * (1 + dy)
        return CGRect(x: x.rounded(), y: y.rounded(), width: visible.rounded(), height: visible.rounded())
    }

    /// La photo à envoyer : le carré visible réduit à 256 × 256, en JPEG (qualité baissée tant qu'elle est trop
    /// lourde) ; nil si l'image ne se lit pas.
    static func jpeg(from image: CGImage, zoom: Double = 1, offset: CGPoint = .zero) -> Data? {
        let rect = cropRect(width: image.width, height: image.height, zoom: zoom, offset: offset)
        guard let cropped = image.cropping(to: rect),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.setFillColor(CGColor(gray: 1, alpha: 1))                // transparence d'un PNG : fond blanc
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let square = context.makeImage() else { return nil }
        for quality in [0.82, 0.7, 0.55, 0.4, 0.25] {
            guard let data = encode(square, quality: quality) else { return nil }
            if data.count <= maxBytes { return data }
        }
        return nil
    }

    private static func encode(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    // MARK: Sans photo : l'initiale de couleur

    /// Couleurs des initiales (choisies par le pseudo : la même pour un membre sur tous les Mac).
    static let initialColors: [Color] = [.teal, .blue, .indigo, .purple, .pink, .orange, .green, .red]

    /// Pure (testée) : la couleur d'un pseudo, sans tenir compte des majuscules.
    static func colorIndex(_ username: String) -> Int {
        let sum = username.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF }
        return sum % initialColors.count
    }

    /// Pure (testée) : la lettre affichée (« malo.beats » → « M » ; vide → « ? »).
    static func initial(_ username: String) -> String {
        username.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
    }

    // MARK: Mode capture

    /// Photo d'exemple des captures de la CI (jamais envoyée) : un dégradé et une silhouette, comme dans la maquette.
    static func sample(_ colors: (NSColor, NSColor)) -> NSImage {
        let size = NSSize(width: CGFloat(side), height: CGFloat(side))
        return NSImage(size: size, flipped: false) { rect in
            NSGradient(starting: colors.0, ending: colors.1)?.draw(in: rect, angle: -60)
            NSColor.white.withAlphaComponent(0.72).setFill()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - 40, y: rect.midY + 6, width: 80, height: 80)).fill()
            NSBezierPath(ovalIn: NSRect(x: rect.midX - 82, y: -70, width: 164, height: 150)).fill()
            return true
        }
    }
}

/// Photo d'un membre dans un rond ; sans photo, l'initiale de son pseudo sur sa couleur.
struct AvatarView: View {
    let photo: NSImage?
    let username: String
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            if let photo {
                Image(nsImage: photo)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Circle().fill(ProfilePhoto.initialColors[ProfilePhoto.colorIndex(username)].gradient)
                Text(ProfilePhoto.initial(username))
                    .font(.system(size: size * 0.44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: max(0.5, size / 64)))
        .accessibilityHidden(true)
    }
}
