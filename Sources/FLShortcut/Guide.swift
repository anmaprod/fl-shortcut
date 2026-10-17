// Guide de FL Shortcuts, façon Apple : une page « Bienvenue » qui dit tout ce qu'on peut faire, puis une page par
// partie (raccourcis, macros, Communauté, au quotidien), chacune en trois étapes et une astuce. « Passer le guide »
// sur chaque page. Montré une fois, à la première ouverture de la fenêtre principale ; ensuite depuis le menu ⋯ ou
// le menu de la barre des menus (« Guide de FL Shortcuts »). Aucune animation continue.
// Changement de page « morph » (Morphose de PowerPoint) : de « Bienvenue » à une partie, l'icône, le titre et la
// phrase de la ligne choisie glissent et grandissent jusqu'en haut de la page ; d'une partie à l'autre, l'en-tête
// reste en place et change, les étapes arrivent l'une après l'autre.
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
    @AppStorage(Appearance.glassKey) private var glassEnabled = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Éléments qui passent d'une page à l'autre (icône, titre et phrase d'une partie).
    @Namespace private var morph

    private var showGlass: Bool { Appearance.glassAvailable && glassEnabled && !reduceTransparency }
    private var last: Bool { page >= GuideContent.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if page == 0 {
                    welcome
                        .transition(Motion.pageMorph)
                } else {
                    let part = GuideContent.pages[min(page, GuideContent.pages.count) - 1]
                    GuidePageView(page: part, morph: morph)
                        .id(part.id)
                        .transition(Motion.pageMorph)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 48)
            .padding(.top, 36)
            footer
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
        }
        .frame(width: 640, height: 540)
        .background { if showGlass { BrandGlow() } }
        .motion(Motion.morph, value: page)
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            AppIcon().frame(width: 72, height: 72)
            Text("Bienvenue dans FL Shortcuts")
                .font(.largeTitle.weight(.bold))
                .padding(.top, 10)
            Text("Tout ce que tu peux faire, en une minute.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(GuideContent.pages) { p in
                    Button {
                        page = p.id
                    } label: {
                        HStack(spacing: 14) {
                            SectionIcon(symbol: p.symbol, tint: p.tint, size: 36)
                                .matchedGeometryEffect(id: "icon\(p.id)", in: morph)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.title).font(.system(size: 14, weight: .semibold))
                                    .matchedGeometryEffect(id: "title\(p.id)", in: morph)
                                Text(p.summary).font(.system(size: 12)).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .matchedGeometryEffect(id: "summary\(p.id)", in: morph)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverLift()
                    .help("Voir « \(p.title) »")
                }
            }
            .frame(maxWidth: 440)
            .padding(.top, 26)
        }
    }

    private var footer: some View {
        ZStack {
            GuideDots(count: GuideContent.count, page: $page)
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

/// Une partie : grande icône, titre, phrase, trois étapes numérotées, une astuce. L'en-tête vient de la ligne de
/// « Bienvenue » (`morph`) ; les étapes et l'astuce arrivent l'une après l'autre.
private struct GuidePageView: View {
    let page: GuidePage
    let morph: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                SectionIcon(symbol: page.symbol, tint: page.tint, size: 56)
                    .matchedGeometryEffect(id: "icon\(page.id)", in: morph)
                VStack(alignment: .leading, spacing: 3) {
                    Text(page.title).font(.largeTitle.weight(.bold))
                        .matchedGeometryEffect(id: "title\(page.id)", in: morph)
                    Text(page.summary).font(.system(size: 14)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .matchedGeometryEffect(id: "summary\(page.id)", in: morph)
                }
            }
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(page.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        StepBadge(number: index + 1)
                        Text(step).font(.system(size: 14)).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .morphIn(index)
                }
            }
            .padding(.top, 28)
            Label {
                Text(page.tip).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lightbulb").foregroundStyle(.yellow)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
            .padding(.top, 26)
            .morphIn(page.steps.count)
        }
        .frame(maxWidth: 520, alignment: .leading)
    }
}

/// Points de pagination, cliquables.
private struct GuideDots: View {
    let count: Int
    @Binding var page: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<count, id: \.self) { i in
                Button {
                    page = i
                } label: {
                    Circle()
                        .fill(i == page ? Color.primary.opacity(0.8) : Color.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page \(i + 1) sur \(count)")
            }
        }
    }
}
