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
         String(localized: "Quitte FL (⌘Q), puis rouvre-le"),
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
                    .popover(isPresented: $large, arrowEdge: .trailing) {
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
