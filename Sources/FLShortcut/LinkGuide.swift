// Relier FL Studio, simplement (29/10, demande du propriétaire : « beaucoup plus simple et mieux expliqué pour
// installer, fermer FL… comme dans l'exemple ») : quatre étapes d'une ligne, et la fenêtre MIDI Settings de FL avec
// les quatre cases à régler entourées et numérotées (Resources/MIDISettings.png, redessinée d'après sa capture ;
// source : docs/images/midi-settings.html). Les mêmes partout : accueil, Organiser, installation du lien, README.
import AppKit
import SwiftUI

enum LinkGuide {
    /// Les étapes, dans l'ordre ; la dernière renvoie à l'image.
    static var steps: [String] {
        [String(localized: "Installe le lien"),
         String(localized: "Quitte et rouvre FL"),             // 07/11 : plus « ⌘Q » (tapé dans FL Shortcuts, il le fermait)
         String(localized: "Dans FL : Options › MIDI Settings"),
         String(localized: "Règle les 4 cases entourées")]
    }

    /// Sous l'image : ce qui compte le plus.
    static var samePort: String { String(localized: "Le même numéro de Port en haut et en bas.") }

    static let imageName = "MIDISettings"

    /// L'image de l'app ; nil hors de l'app (essais).
    static let image: NSImage? = Bundle.main.url(forResource: imageName, withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }
}

/// La fenêtre MIDI Settings de FL, cases à régler entourées ; un clic l'agrandit.
struct MIDISettingsImage: View {
    var width: CGFloat = 230
    @State private var large = false

    var body: some View {
        if let image = LinkGuide.image {
            VStack(spacing: 6) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: width)
                    .contentShape(Rectangle())
                    .onTapGesture { large = true }
                    .help("Agrandir")
                    .swissPopover(isPresented: $large, arrowEdge: .trailing) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 520)
                            .padding(8)
                            .onTapGesture { large = false }
                    }
                Text(LinkGuide.samePort)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: width)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Dans MIDI Settings : Port de la sortie, Enable, Controller type FL Shortcuts et Port de l'entrée, le même numéro.")
        } else {
            Text("Options › MIDI Settings")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: width)
        }
    }
}

/// Les 4 cases de MIDI Settings, découpées dans l'image et montrées en grand (01/11, le propriétaire : « l'image,
/// on la verra jamais, c'est trop petit ») : une ligne par case (numéro, ce qu'il faut faire, la case elle-même), puis
/// « Voir toute la fenêtre en grand ».
struct MIDISettingsCrops: View {
    @State private var large = false

    /// Une case : son numéro (le même que dans l'image), la consigne, et sa place dans l'image (pixels sur 1428 de large).
    struct Crop: Identifiable {
        let id: Int
        let text: String
        let rect: CGRect
        /// Montrée sur toute la largeur (Controller type est long).
        var wide = false
    }

    /// Les deux ports d'abord, en 1 et 2 (02/11 : « pour que ça coïncide » ; les pastilles de l'image suivent).
    static var crops: [Crop] {
        [Crop(id: 1, text: String(localized: "Output : un numéro de Port (ex. 7)."),
              rect: CGRect(x: 1086, y: 468, width: 254, height: 122)),
         Crop(id: 2, text: String(localized: "Input : le même numéro de Port. N'importe lequel, du moment que les deux sont pareils."),
              rect: CGRect(x: 1096, y: 948, width: 244, height: 120)),
         Crop(id: 3, text: String(localized: "Input : clique « FL Shortcuts Link », puis allume Enable."),
              rect: CGRect(x: 80, y: 952, width: 200, height: 112)),
         Crop(id: 4, text: String(localized: "Controller type : FL Shortcuts."),
              rect: CGRect(x: 280, y: 924, width: 820, height: 142), wide: true)]
    }

    /// Pure (testée) : la découpe en pixels de l'image réelle (l'image de référence fait 1428 pixels de large).
    static func pixelRect(_ rect: CGRect, imageWidth: Int) -> CGRect {
        let k = CGFloat(imageWidth) / 1428
        return CGRect(x: rect.minX * k, y: rect.minY * k, width: rect.width * k, height: rect.height * k).integral
    }

    private static let cgImage: CGImage? = LinkGuide.image?.cgImage(forProposedRect: nil, context: nil, hints: nil)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Self.crops) { crop in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 12) {
                        Text(verbatim: "\(crop.id)")
                            .font(Swiss.font(12))
                            .foregroundStyle(Swiss.background)
                            .frame(width: 20, height: 20)
                            .background(Rectangle().fill(Swiss.red))
                        Text(crop.text)
                            .font(.system(size: 13, weight: .bold))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if !crop.wide { piece(crop, scale: 0.5) }
                    }
                    if crop.wide { piece(crop, scale: 0.42).padding(.leading, 32) }
                }
                .padding(.vertical, 10)
                .swissRule(Swiss.line, edge: .top)
                .accessibilityElement(children: .combine)
            }
            // 07/11 : l'image entière s'ouvre ici même (plus une bulle à part, fragile dans le panneau de l'Organiser).
            Button {
                large.toggle()
            } label: {
                Label(large ? "Masquer la fenêtre en grand" : "Voir toute la fenêtre en grand",
                      systemImage: large ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .swissLabel(Swiss.text, size: 10.5)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swissRule(Swiss.line, edge: .top)
            if large, let image = LinkGuide.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 560)
                    .overlay(Rectangle().strokeBorder(Swiss.line, lineWidth: 1))
                    .onTapGesture { large = false }
                    .accessibilityLabel(Text("MIDI Settings de FL, les 4 cases à régler entourées"))
            }
        }
    }

    @ViewBuilder private func piece(_ crop: Crop, scale: CGFloat) -> some View {
        if let cg = Self.cgImage,
           let cut = cg.cropping(to: Self.pixelRect(crop.rect, imageWidth: cg.width)) {
            Image(decorative: cut, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: crop.rect.width * scale, height: crop.rect.height * scale)
                .overlay(Rectangle().strokeBorder(Swiss.line, lineWidth: 1))
        }
    }
}
