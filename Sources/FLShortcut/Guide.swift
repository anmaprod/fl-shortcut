// Guide de FL Shortcuts (maquette validée le 28/10) : « Bienvenue », une ligne par partie, puis une page par partie
// (raccourcis, macros, Communauté, au quotidien), chacune en trois étapes d'une ligne dans une seule carte en verre.
// « Passer » sur chaque page sauf la dernière. Montré une fois, à la première ouverture de la fenêtre principale ;
// ensuite depuis la page Aide ou le menu de la barre des menus (« Guide de FL Shortcuts »). Fond plein, sans lueur de
// couleur ; aucune animation continue.
// Changement de page : de « Bienvenue » à une partie, l'icône de la ligne choisie glisse et grandit jusqu'en haut de
// la page ; la page qui part se brouille et s'efface pendant que la nouvelle passe du flou au net. En revenant en
// arrière, pas de vol d'icône : les deux pages se fondent l'une dans l'autre.
import SwiftUI

/// Demande d'ouvrir le guide (page Aide, barre des menus) : la fenêtre principale l'affiche dès qu'elle est là.
final class GuideLink: ObservableObject {
    static let shared = GuideLink()
    @Published var pending = false

    func show() { pending = true }
}

struct GuidePage: Identifiable {
    let id: Int
    let symbol: String
    let tint: Color
    let title: String
    /// Trois étapes, d'une ligne chacune.
    let steps: [String]
}

enum GuideContent {
    static let pages: [GuidePage] = [
        GuidePage(id: 1, symbol: "keyboard", tint: .blue, title: String(localized: "Tes raccourcis"),
                  steps: [String(localized: "Choisis une page à gauche."),
                          String(localized: "Clique une touche, puis tape la nouvelle."),
                          String(localized: "↺ remet la touche de FL.")]),
        GuidePage(id: 2, symbol: SidebarItem.macros.symbol, tint: SidebarItem.macros.tint, title: String(localized: "Les macros"),
                  steps: [String(localized: "« Enregistrer une macro », puis fais ta suite dans FL."),
                          String(localized: "Retouche les blocs dans le créateur."),
                          String(localized: "Donne-lui un raccourci.")]),
        GuidePage(id: 3, symbol: SidebarItem.community.symbol, tint: SidebarItem.community.tint, title: String(localized: "La Communauté"),
                  steps: [String(localized: "Crée ton compte."),
                          String(localized: "Ajoute les macros des autres."),
                          String(localized: "« + » partage les tiennes.")]),
        GuidePage(id: 4, symbol: "menubar.rectangle", tint: .orange, title: String(localized: "Au quotidien"),
                  steps: [String(localized: "L'icône en haut de l'écran ouvre le menu."),
                          String(localized: "⌃⌥⌘F met en pause ou reprend."),
                          String(localized: "Un « ! » sur l'icône : autorise le clavier.")]),
    ]

    /// « Bienvenue », puis une page par partie.
    static var count: Int { pages.count + 1 }
}

struct GuideView: View {
    /// 0 : « Bienvenue » ; 1… : les parties.
    @Binding var page: Int
    let close: () -> Void
    /// Élément qui passe d'une page à l'autre : l'icône d'une partie.
    @Namespace private var morph
    /// Sens du dernier changement de page : en avant, l'icône d'une ligne vole jusqu'en haut de sa partie ; en
    /// arrière, simple fondu.
    @State private var forward = true

    private var last: Bool { page >= GuideContent.count - 1 }
    private var part: GuidePage? { page > 0 ? GuideContent.pages[min(page, GuideContent.pages.count) - 1] : nil }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if let part {
                    GuidePageView(page: part, morph: morph)
                        .id(part.id)
                        .transition(Motion.pageMorph)
                } else {
                    welcome
                        .transition(Motion.pageMorph)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 48)
            footer
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 56)
        .frame(width: 640, height: 540)
        .motion(Motion.morph, value: page)
        .onReceive(DebugSnapshot.publisher(DebugSnapshot.guide)) { note in
            // Mode capture : « 1 lent », la page changée ici comme par « Suivant », 10 fois plus lentement.
            let words = (note.object as? String ?? "").split(separator: " ")
            guard words.contains("lent"), let n = words.first.flatMap({ Int($0) }) else { return }
            DebugSnapshot.slowMotion = 10
            page = max(0, min(n, GuideContent.count - 1))
        }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Text("Bienvenue")
                .font(.system(size: 30, weight: .bold))
                .morphIn(0)
            PlateRows(data: GuideContent.pages) { p in
                GuideWelcomeRow(page: p, morph: morph, flies: forward) { go(to: p.id) }
            }
            .padding(.top, 26)
            .morphIn(1)
        }
    }

    /// Change de page en notant le sens (même mise à jour : l'icône sait si elle doit voler).
    private func go(to new: Int) {
        let target = max(0, min(new, GuideContent.count - 1))
        guard target != page else { return }
        forward = target > page
        page = target
    }

    private var footer: some View {
        ZStack {
            GuideDots(count: GuideContent.count, page: page) { go(to: $0) }
            HStack(spacing: 10) {
                if !last {
                    Button("Passer", action: close)
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(.cancelAction)
                        .help("Fermer le guide : tu le retrouves dans la page Aide ou le menu de la barre des menus")
                }
                Spacer()
                if page > 0 {
                    Button("Précédent") { go(to: page - 1) }
                        .secondaryButton()
                }
                Button(page == 0 ? String(localized: "Découvrir") : last ? String(localized: "C'est parti")
                       : String(localized: "Suivant")) {
                    if last { close() } else { go(to: page + 1) }
                }
                .primaryButton()
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
    }
}

/// Une partie : icône et titre, puis ses trois étapes numérotées dans une seule carte. L'icône vient de la ligne de
/// « Bienvenue » (`morph`) ; le titre puis les étapes arrivent l'un après l'autre, du flou au net.
private struct GuidePageView: View {
    let page: GuidePage
    let morph: Namespace.ID

    private struct Step: Identifiable {
        let id: Int
        let text: String
    }

    private var steps: [Step] { page.steps.enumerated().map { Step(id: $0.offset + 1, text: $0.element) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                MorphIcon(page: page, size: 44, morph: morph, id: MorphIcon.id(page))
                Text(page.title)
                    .font(.system(size: 28, weight: .bold))
                    .morphIn(0)
            }
            PlateRows(data: steps) { step in
                HStack(spacing: 12) {
                    GuideNumber(number: step.id, tint: page.tint)
                    Text(step.text).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(minHeight: 52)
                .accessibilityElement(children: .combine)
            }
            .padding(.top, 26)
            .morphIn(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Ligne d'une partie sur « Bienvenue » : icône, titre, chevron ; au survol, contour et halo de sa couleur.
private struct GuideWelcomeRow: View {
    let page: GuidePage
    let morph: Namespace.ID
    /// En avant : son icône vole jusqu'en haut de la partie.
    let flies: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                MorphIcon(page: page, size: 28, morph: morph, id: flies ? MorphIcon.id(page) : "ligne\(page.id)")
                Text(page.title).font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuHover(tint: page.tint)
        .help("Voir « \(page.title) »")
    }
}

/// Numéro d'une étape, dans la couleur de la page.
private struct GuideNumber: View {
    let number: Int
    let tint: Color

    var body: some View {
        Text("\(number)")
            .font(.system(size: 12, weight: .bold).monospacedDigit())
            .foregroundStyle(Color.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(tint.gradient))
            .accessibilityHidden(true)
    }
}

/// Icône d'une partie redessinée à la taille qu'on lui donne : pendant le changement de page, elle grandit en douceur
/// de la ligne de « Bienvenue » (28 points) jusqu'à l'en-tête de la page (44 points), au lieu de sauter d'une taille
/// à l'autre.
private struct MorphIcon: View {
    let page: GuidePage
    let size: CGFloat
    let morph: Namespace.ID
    /// Même identifiant sur les deux pages : l'icône vole de l'une à l'autre ; différent : chacune reste à sa place.
    let id: String

    static func id(_ page: GuidePage) -> String { "icon\(page.id)" }

    var body: some View {
        GeometryReader { g in
            SectionIcon(symbol: page.symbol, tint: page.tint, size: max(1, min(g.size.width, g.size.height)))
        }
        .matchedGeometryEffect(id: id, in: morph)
        .frame(width: size, height: size)
    }
}

/// Points de pagination, cliquables : celui de la page ouverte s'allonge, en bleu.
private struct GuideDots: View {
    let count: Int
    let page: Int
    let select: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Button {
                    select(i)
                } label: {
                    Capsule()
                        .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: i == page ? 18 : 6, height: 6)
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page \(i + 1) sur \(count)")
            }
        }
    }
}

/// Guide ouvert dans la fenêtre principale (page Aide, barre des menus) : sa page vit dans la feuille elle-même.
/// Gardée par la fenêtre, chaque changement de page redessinait la feuille de l'extérieur, sans aucune animation.
struct GuideSheet: View {
    /// Page demandée à l'ouverture (et par le mode capture, guide ouvert).
    let initialPage: Int
    let close: () -> Void
    @State private var page: Int

    init(initialPage: Int, close: @escaping () -> Void) {
        self.initialPage = initialPage
        self.close = close
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        GuideView(page: $page, close: close)
            .onChange(of: initialPage) { page = $0 }
    }
}
