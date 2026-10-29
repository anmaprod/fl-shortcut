// Tuto en images de l'Organiser (29/10, demande du propriétaire : « la première fois qu'on ouvre organiser on a un
// tuto en gros avec aide image ») : quatre pages d'une image et d'une phrase, montrées à la première ouverture, avant
// l'écoute (rien n'est envoyé à FL tant qu'il est là) ; « Revoir le tuto » (Options de l'aperçu) le remontre. Images :
// Resources/{fr,en}.lproj/OrganiserTuto1…4.png, dessinées dans le style de l'app (source :
// docs/images/organiser-tuto.html, rendu par docs/images/rendre-organiser-tuto.js).
import AppKit
import SwiftUI

enum OrganizerTutorial {
    struct Page: Identifiable, Equatable {
        let id: Int
        let title: String
        let text: String

        var imageName: String { "OrganiserTuto\(id)" }
    }

    static var pages: [Page] {
        [Page(id: 1, title: String(localized: "Ouvre ton projet dans FL"),
              text: String(localized: "Puis menu de l'icône › Organiser…")),
         Page(id: 2, title: String(localized: "Il écoute chaque son"),
              text: String(localized: "Ne touche pas à FL pendant l'écoute.")),
         Page(id: 3, title: String(localized: "Vérifie le rangement"),
              text: String(localized: "Change une famille, un nom ou une piste si tu veux.")),
         Page(id: 4, title: String(localized: "Une copie rangée"),
              text: String(localized: "Ton projet ne bouge pas : tu valides la copie, ou tu reviens en arrière."))]
    }

    /// Vu une fois : plus montré tout seul. Rien de sensible (un autre programme peut l'écrire : le tuto revient, ou
    /// non, c'est tout).
    static let seenKey = "organizerTutorialSeen"

    static func shouldShow(defaults: UserDefaults = .standard) -> Bool { !defaults.bool(forKey: seenKey) }

    static func markSeen(defaults: UserDefaults = .standard) { defaults.set(true, forKey: seenKey) }

    /// L'image de la page, dans la langue du Mac ; nil hors de l'app (essais).
    static func image(_ page: Page) -> NSImage? {
        Bundle.main.url(forResource: page.imageName, withExtension: "png").flatMap { NSImage(contentsOf: $0) }
    }
}

/// Les pages du tuto, une à la fois : l'image en grand, son titre et sa phrase, les points de page, « Passer » et
/// « Suivant » (« C'est parti » sur la dernière).
struct OrganizerTutorialView: View {
    let done: () -> Void
    @State private var index = 0

    private var pages: [OrganizerTutorial.Page] { OrganizerTutorial.pages }

    private var page: OrganizerTutorial.Page { pages[min(index, pages.count - 1)] }
    private var isLast: Bool { index >= pages.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            picture
            VStack(alignment: .leading, spacing: 4) {
                Text(page.title).font(.system(size: 17, weight: .bold))
                Text(page.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 10) {
                dots
                Spacer()
                if !isLast {
                    Button("Passer", action: done).secondaryButton()
                }
                Button(isLast ? String(localized: "C'est parti") : String(localized: "Suivant")) {
                    if isLast { done() } else { index += 1 }
                }
                .buttonStyle(AlwaysBlueButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder private var picture: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Group {
            if let image = OrganizerTutorial.image(page) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(16 / 9, contentMode: .fit)
            } else {
                shape.fill(Color.white.opacity(0.06))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay(Image(systemName: "photo").font(.system(size: 28)).foregroundStyle(.tertiary))
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(pages.indices, id: \.self) { i in
                Circle()
                    .fill(i == index ? Color.accentColor : Color.white.opacity(0.25))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page \(index + 1) sur \(pages.count)"))
    }
}
