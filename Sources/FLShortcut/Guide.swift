// Guide de FL Shortcuts, façon Apple : une page « Bienvenue » qui dit tout ce qu'on peut faire, puis une page par
// partie (raccourcis, macros, Communauté, au quotidien), chacune en trois étapes et une astuce. « Passer le guide »
// sur chaque page. Montré une fois, à la première ouverture de la fenêtre principale ; ensuite depuis le menu ⋯ ou
// le menu de la barre des menus (« Guide de FL Shortcuts »). Aucune animation continue.
// Changement de page « morph » (Morphose de PowerPoint) : de « Bienvenue » à une partie, l'icône de la ligne choisie
// glisse et grandit jusqu'en haut de la page ; les textes ne sont jamais étirés d'une taille à l'autre (ils
// sautaient en cours de route) : la page qui part se brouille et s'efface pendant que la nouvelle passe du flou au
// net (titre, phrase, étapes, astuce, l'un après l'autre). Le fond prend la couleur de l'icône de chaque partie.
import SwiftUI

/// Demande d'ouvrir le guide (menu ⋯, barre des menus) : la fenêtre principale l'affiche dès qu'elle est là.
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
    /// Une phrase : sur la page « Bienvenue » et sous le titre de la page.
    let summary: String
    let steps: [String]
    let tip: String
}

enum GuideContent {
    static let pages: [GuidePage] = [
        GuidePage(id: 1, symbol: "keyboard", tint: .blue, title: "Tes raccourcis",
                  summary: "Change les raccourcis de FL Studio, ou ajoute les tiens.",
                  steps: ["À gauche, choisis une page : Général, Playlist, Mixer… Elle montre les raccourcis de FL qui s'y appliquent.",
                          "Clique sur une touche, comme ⌘Z, puis tape la nouvelle : elle remplace celle de FL. « Réinitialiser » remet celle d'origine.",
                          "Le « + » en haut à droite ajoute ton propre raccourci à la page affichée."],
                  tip: "Le menu ⋯ charge un profil tout prêt, ou importe et exporte tes raccourcis."),
        GuidePage(id: 2, symbol: SidebarItem.macros.symbol, tint: SidebarItem.macros.tint, title: "Les macros",
                  summary: "Plusieurs actions de FL enchaînées, sur un seul raccourci.",
                  steps: ["Page Macros, « Enregistrer une macro » : fais ta suite dans FL (clics, flèches, raccourcis), puis « Terminer ». Chaque geste devient un bloc.",
                          "Retouche-la dans le créateur : ajoute des blocs de la palette d'un clic ou en les glissant, range les lignes en les glissant.",
                          "Choisis-lui un raccourci, puis « Tester ». La flèche ← ramène à tes macros."],
                  tip: "« Partir d'un modèle… » propose des macros toutes faites, à adapter."),
        GuidePage(id: 3, symbol: SidebarItem.community.symbol, tint: SidebarItem.community.tint, title: "La Communauté",
                  summary: "Les macros et les raccourcis des autres, et les tiens.",
                  steps: ["Crée un compte : mail, mot de passe et nom d'utilisateur. Seul ton nom est visible des autres.",
                          "Ouvre un partage pour lire son explication et chaque étape, puis « Ajouter à mes macros ».",
                          "Le « + » partage une de tes macros, ou tous tes raccourcis, avec ton explication."],
                  tip: "Une macro ajoutée arrive sans raccourci : rien ne se lance tant que tu ne lui en as pas choisi un."),
        GuidePage(id: 4, symbol: "menubar.rectangle", tint: .orange, title: "Au quotidien",
                  summary: "FL Shortcuts travaille en arrière-plan, depuis la barre des menus.",
                  steps: ["L'icône en haut de l'écran ouvre son menu : modifier les raccourcis, organiser la page ouverte, mettre en pause.",
                          "⌃⌥⌘F met en pause ou reprend, n'importe où. Une pastille le rappelle tant que c'est en pause.",
                          "Un « ! » sur l'icône : le clavier n'est pas autorisé. Ouvre son menu pour savoir quoi faire."],
                  tip: "Tes touches ne sont lues que quand FL Studio est devant. Rien n'est envoyé, sauf ce que tu publies dans la Communauté."),
    ]

    /// « Bienvenue », puis une page par partie.
    static var count: Int { pages.count + 1 }
}

struct GuideView: View {
    /// 0 : « Bienvenue » ; 1… : les parties.
    @Binding var page: Int
    let close: () -> Void
    /// Faux : le fond est dessiné par la fenêtre qui accueille le guide (accueil, même fond que l'écran du clavier).
    var drawsBackdrop = true
    /// Icône de l'app partagée avec l'écran d'avant (accueil) : elle glisse jusqu'en haut de « Bienvenue ».
    var appIconMorph: Namespace.ID? = nil
    /// Élément qui passe d'une page à l'autre : l'icône d'une partie.
    @Namespace private var morph

    private var last: Bool { page >= GuideContent.count - 1 }
    private var part: GuidePage? { page > 0 ? GuideContent.pages[min(page, GuideContent.pages.count) - 1] : nil }
    /// Couleur de la page : celle de son icône (boutons, points de pagination, fond).
    private var tint: Color { GuideBackdrop.tint(page) }

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
            .padding(.horizontal, 48)
            .padding(.top, 34)
            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .frame(width: 640, height: 540)
        .background { if drawsBackdrop { GuideBackdrop(page: page) } }
        .tint(tint)
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
            AppIcon()
                .morphing("appIcon", in: appIconMorph)
                .frame(width: 76, height: 76)
                .shadow(color: Appearance.brand[1].opacity(0.35), radius: 22, y: 10)
            Text("Bienvenue dans FL Shortcuts")
                .font(.system(size: 30, weight: .bold))
                .padding(.top, 14)
                .morphIn(0)
            Text("Tout ce que tu peux faire, en une minute.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .morphIn(1)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(GuideContent.pages.enumerated()), id: \.element.id) { index, p in
                    Button {
                        page = p.id
                    } label: {
                        HStack(spacing: 14) {
                            MorphIcon(page: p, size: 36, morph: morph)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.title).font(.system(size: 14, weight: .semibold))
                                Text(p.summary).font(.system(size: 12)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(GuideCard(tint: p.tint))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverLift(cornerRadius: 14)
                    .help("Voir « \(p.title) »")
                    .morphIn(index + 2)
                }
            }
            .frame(maxWidth: 460)
            .padding(.top, 24)
        }
    }

    private var footer: some View {
        ZStack {
            GuideDots(count: GuideContent.count, page: $page, tint: tint)
            HStack(spacing: 8) {
                if !last {
                    Button("Passer le guide", action: close)
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                        .keyboardShortcut(.cancelAction)
                        .help("Fermer le guide : tu le retrouves dans le menu ⋯ ou le menu de la barre des menus")
                }
                Spacer()
                if page > 0 {
                    Button("Précédent") { page -= 1 }
                }
                Button(page == 0 ? "Découvrir" : last ? "C'est parti" : "Suivant") {
                    if last { close() } else { page += 1 }
                }
                .primaryButton()
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Une partie : grande icône, titre, phrase, trois étapes en cartes, une astuce. L'icône vient de la ligne de
/// « Bienvenue » (`morph`) ; le titre et la phrase, les étapes puis l'astuce arrivent l'un après l'autre, du flou au
/// net.
private struct GuidePageView: View {
    let page: GuidePage
    let morph: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                MorphIcon(page: page, size: 60, morph: morph)
                    .shadow(color: page.tint.opacity(0.45), radius: 18, y: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(page.title).font(.system(size: 30, weight: .bold))
                    Text(page.summary).font(.system(size: 14)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .morphIn(0)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(page.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        GuideNumber(number: index + 1, tint: page.tint)
                        Text(step).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(GuideCard(tint: page.tint))
                    .accessibilityElement(children: .combine)
                    .morphIn(index + 1)
                }
            }
            .padding(.top, 24)
            Label {
                Text(page.tip).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lightbulb.fill").foregroundStyle(page.tint)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(page.tint.opacity(0.1)))
            .padding(.top, 16)
            .morphIn(page.steps.count + 1)
        }
        .frame(maxWidth: 530, alignment: .leading)
    }
}

/// Carte d'une ligne du guide : voile clair, liseré de la couleur de la page.
private struct GuideCard: View {
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.primary.opacity(0.045))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 1))
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
            .frame(width: 22, height: 22)
            .background(Circle().fill(tint.gradient))
            .accessibilityHidden(true)
    }
}

/// Icône d'une partie redessinée à la taille qu'on lui donne : pendant le morph, elle grandit en douceur de la ligne
/// de « Bienvenue » (36 points) jusqu'à l'en-tête de la page (60 points), au lieu de sauter d'une taille à l'autre.
private struct MorphIcon: View {
    let page: GuidePage
    let size: CGFloat
    let morph: Namespace.ID

    var body: some View {
        GeometryReader { g in
            SectionIcon(symbol: page.symbol, tint: page.tint, size: max(1, min(g.size.width, g.size.height)))
        }
        .matchedGeometryEffect(id: "icon\(page.id)", in: morph)
        .frame(width: size, height: size)
    }
}

/// Fond du guide : les couleurs de l'app sur « Bienvenue », puis la couleur de l'icône de chaque partie. D'une page à
/// l'autre, les couleurs se fondent l'une dans l'autre, jamais de changement sec.
struct GuideBackdrop: View {
    let page: Int

    /// Couleur de la page : celle de son icône ; « Bienvenue » : celle du milieu de l'icône de l'app.
    static func tint(_ page: Int) -> Color {
        page > 0 && page <= GuideContent.pages.count ? GuideContent.pages[page - 1].tint : Appearance.brand[1]
    }

    var body: some View {
        ZStack {
            Group {
                if page > 0 && page <= GuideContent.pages.count {
                    TintGlow(tint: Self.tint(page))
                } else {
                    BrandGlow()
                }
            }
            .id(page)
            .transition(.opacity.animation(.easeInOut(duration: 0.9 * DebugSnapshot.slowMotion)))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Lueur d'une seule couleur (celle de l'icône de la page) : halo en haut à gauche, reflet en haut à droite, une
/// touche en bas. Dégradés statiques, aucune animation continue.
struct TintGlow: View {
    let tint: Color
    @Environment(\.colorScheme) private var scheme

    private var k: Double { scheme == .dark ? 0.5 : 0.34 }

    var body: some View {
        ZStack {
            RadialGradient(colors: [tint.opacity(k), .clear], center: .topLeading, startRadius: 0, endRadius: 460)
            RadialGradient(colors: [tint.opacity(k * 0.7), .clear], center: UnitPoint(x: 0.85, y: -0.05),
                           startRadius: 0, endRadius: 380)
            RadialGradient(colors: [tint.opacity(k * 0.3), .clear], center: .bottom, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}

/// Points de pagination, cliquables : celui de la page ouverte s'allonge, dans la couleur de la page.
private struct GuideDots: View {
    let count: Int
    @Binding var page: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Button {
                    page = i
                } label: {
                    Capsule()
                        .fill(i == page ? tint : Color.secondary.opacity(0.35))
                        .frame(width: i == page ? 20 : 7, height: 7)
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page \(i + 1) sur \(count)")
            }
        }
    }
}
