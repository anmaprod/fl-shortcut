// Fenêtre principale « plus lisible » (maquette du 16/11), à la direction A depuis le 17/11 (« J'aime bien le A ») :
// une barre de gauche en index numéroté (01 Trouver un raccourci, 02 Raccourcis et ses pages, 03 Macros, 04 Communauté,
// 05 Mon compte, 06 Aide), chaque page sous un surtitre (« 02 — Raccourcis ») et un très grand titre ; les raccourcis
// en une seule liste (nom, touche dans son cadre, rouge plein si changée, ↺), rangés sous le nom de leur groupe à
// gauche ; « appuie sur un raccourci » pour en trouver un par ses touches ou son nom. Pièces de EditorView ; rien n'y
// est enregistré.
import SwiftUI

/// Mise en page des pages lisibles (maquette : le titre et la liste partent du même bord, liste de 784 points au plus).
enum ReadableLayout {
    /// Maquette « Minimal » (20/11, vidéo : « la page macro n'est pas la même ») : 48 points du bord de la fenêtre
    /// (8 de la fenêtre + 40), pages sur toute la largeur de la grille de 12 colonnes (1 088 au plus).
    static let inset: CGFloat = 40
    static let maxWidth: CGFloat = 1088
    /// Colonne du nom de groupe (« Outils 09 ») à gauche des lignes d'une page de raccourcis.
    static let groupColumn: CGFloat = 170
    /// Cadre d'une touche (« ⌘S », maquette A : 88 points).
    static let keyWidth: CGFloat = 92
    static let rowHeight: CGFloat = 50
}

// MARK: - Barre de gauche

/// La barre de gauche de la direction A (17/11, « J'aime bien le A ») : « fl shortcuts. », puis un index numéroté
/// (01 Trouver un raccourci, 02 Raccourcis et ses pages, 03 Macros, 04 Communauté, 05 Mon compte, 06 Aide). Le numéro de
/// la partie ouverte est rouge ; un clic sur « Raccourcis » ouvre ou ferme ses pages.
struct ReadableSidebar: View {
    let selected: SidebarItem?
    @Binding var shortcutsOpen: Bool
    /// Nouveautés d'une personne suivie (Communauté) ; ce Mac et le compte ont chacun leurs changements (Mon compte).
    var communityDot = false
    var accountDot = false
    let choose: (SidebarItem) -> Void

    /// Numéro de la partie d'une page (« 02 » pour Playlist), le même que le surtitre de la page.
    static func number(_ item: SidebarItem) -> Int {
        switch item {
        case .find: return 1
        case .section, .custom: return 2
        case .macros: return 3
        case .community: return 4
        case .account: return 5
        case .help: return 6
        }
    }

    private var inShortcuts: Bool {
        switch selected {
        case .section?, .custom?: return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Place des boutons fermer / réduire / agrandir de la fenêtre.
            Color.clear.frame(height: 12)
            brand
                .padding(.top, 26)
                .padding(.bottom, 36)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    top(1, String(localized: "Trouver un raccourci"), on: selected == .find) { choose(.find) }
                    top(2, String(localized: "Raccourcis"), on: inShortcuts) { shortcutsOpen.toggle() }
                        .accessibilityValue(shortcutsOpen ? String(localized: "ouvert") : String(localized: "fermé"))
                    if shortcutsOpen {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(FLSection.allCases) { section in
                                sub(.section(section), section.title)
                            }
                            Rectangle().fill(Swiss.faint).frame(height: 1)
                                .padding(.leading, IndexLayout.textColumn).padding(.trailing, 14)
                                .padding(.vertical, 5)
                            sub(.custom, String(localized: "Mes raccourcis"))
                        }
                        .padding(.bottom, 8)
                    }
                    top(3, String(localized: "Macros"), on: selected == .macros) { choose(.macros) }
                    top(4, String(localized: "Communauté"), on: selected == .community, dot: communityDot) { choose(.community) }
                    top(5, String(localized: "Mon compte"), on: selected == .account, dot: accountDot) { choose(.account) }
                    top(6, String(localized: "Aide"), on: selected == .help) { choose(.help) }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(.leading, 16)
        .frame(width: EditorView.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .trailing) { Rectangle().fill(Swiss.faint).frame(width: 1) }
        .background {
            Rectangle().fill(Swiss.background)
                .padding(.leading, -8)
                .padding(.vertical, -8)
                .allowsHitTesting(false)
        }
        .swissInverted()
    }

    /// « fl shortcuts. » : le nom en gras, son point carré rouge.
    private var brand: some View {
        HStack(alignment: .lastTextBaseline, spacing: 2) {
            Text(verbatim: "fl shortcuts").font(.custom(Swiss.titleFontName, size: 18).weight(.bold)).tracking(-0.6)
                .foregroundStyle(Swiss.text)
            Rectangle().fill(Swiss.red).frame(width: 5, height: 5)
        }
        .padding(.leading, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "FL Shortcuts"))
    }

    private func top(_ number: Int, _ title: String, on: Bool, dot: Bool = false,
                     action: @escaping () -> Void) -> some View {
        IndexTopRow(number: number, title: title, selected: on, dot: dot, action: action)
    }

    private func sub(_ item: SidebarItem, _ title: String) -> some View {
        IndexSubRow(title: title, selected: selected == item) { choose(item) }
    }
}

/// Mesures de l'index de la barre de gauche (maquette A : numéro dans une colonne de 30 points).
enum IndexLayout {
    static let numberColumn: CGFloat = 30
    static var textColumn: CGFloat { numberColumn + 4 }
}

/// Ligne de l'index : « 03 » en petit (rouge si la partie est ouverte), puis le titre en demi-gras.
private struct IndexTopRow: View {
    let number: Int
    let title: String
    let selected: Bool
    var dot = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(String(format: "%02d", number))
                    .font(Swiss.font(11, .medium))
                    .monospacedDigit()
                    .foregroundStyle(selected ? Swiss.red : Swiss.gray)
                    .frame(width: IndexLayout.numberColumn, alignment: .leading)
                    .padding(.leading, 4)
                Text(title)
                    .font(Swiss.font(14, .semibold))
                    .foregroundStyle(Swiss.text)
                    .lineLimit(1)
                if dot {
                    Rectangle().fill(Swiss.red).frame(width: 6, height: 6).padding(.leading, 8)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        .accessibilityLabel(String(localized: "Nouveautés"))
                }
                Spacer(minLength: 0)
            }
            .frame(height: 34)
            .opacity(hovering && !selected ? 0.7 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Page de « Raccourcis » (« Playlist ») : en gris foncé sous le titre ; ouverte, à l'encre, en demi-gras, avec son
/// carré rouge.
private struct IndexSubRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Group {
                    if selected { Rectangle().fill(Swiss.red).frame(width: 5, height: 5) } else { Color.clear }
                }
                .frame(width: IndexLayout.textColumn - 10, alignment: .trailing)
                .padding(.trailing, 10)
                Text(title)
                    .font(Swiss.font(14, selected ? .semibold : .regular))
                    .foregroundStyle(selected || hovering ? Swiss.text : Swiss.soft)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 27)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Colonne de la page (direction A)

extension View {
    /// La colonne des pages (direction A, 17/11) : du même bord que le titre et son trait, 800 points au plus.
    func readableColumn() -> some View {
        frame(maxWidth: ReadableLayout.maxWidth, alignment: .leading)
            .padding(.horizontal, ReadableLayout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Titre de page (direction A)

/// En-tête d'une page de la direction A : le surtitre (« 02 — RACCOURCIS »), puis le très grand titre en Inter Display
/// gras, serré (« Playlist », « Appuie sur / un raccourci. ») ; il rétrécit plutôt que de se couper.
struct IndexTitle: View {
    let eyebrow: String
    let text: String
    var size: CGFloat = 72
    var lines = 1
    /// Flèche ← devant le titre seulement (page d'une personne) : le surtitre reste au bord de la page.
    var back: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(eyebrow).swissLabel(size: 11)
            HStack(alignment: .center, spacing: 14) {
                if let back {
                    Button(action: back) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Swiss.text)
                            .frame(width: 30, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Revenir à la Communauté"))
                    .accessibilityLabel(String(localized: "Revenir"))
                }
                Text(text)
                    .font(Swiss.title(size))
                    .tracking(-size * 0.05)
                    .foregroundStyle(Swiss.text)
                    .lineLimit(lines)
                    .minimumScaleFactor(0.4)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
        }
    }
}

// MARK: - Touche et lignes

/// Mise en page des listes de la direction A (maquette : N° en tête de ligne, colonne de la page).
enum IndexTable {
    static let numberColumn: CGFloat = 46
    static let pageColumn: CGFloat = 200
}

/// La touche d'un raccourci dans son cadre à l'encre (« ⌘S » en Inter Display) ; changée : rouge plein, texte blanc.
struct KeyBox: View {
    let combo: KeyCombo?
    var changed = false
    var placeholder = "—"
    @State private var hovering = false

    var body: some View {
        let onRed = AppTheme.current == .orange ? Swiss.background : Color.white
        return Text(combo?.display ?? placeholder)
            .font(.custom(Swiss.titleFontName, size: 15).weight(.semibold))
            .foregroundStyle(changed ? onRed : (combo == nil ? Swiss.gray : Swiss.text))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6)
            .frame(width: ReadableLayout.keyWidth, height: 32)
            .background(Rectangle().fill(changed ? Swiss.red : (hovering ? Swiss.faint : Color.clear)))
            .overlay(Rectangle().strokeBorder(changed ? Swiss.red : (hovering ? Swiss.text : Swiss.keyLine), lineWidth: 1))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(combo?.spoken ?? String(localized: "aucune"))
    }
}

/// En-tête d'une liste numérotée (maquette A) : « N° », le nom de la colonne, « PAGE », « TOUCHE », sur un trait
/// d'encre.
struct IndexTableHeader: View {
    let title: String
    var page: String? = nil
    var key = String(localized: "Touche")
    /// Dernière colonne (« ACTIVE » des macros) et sa largeur.
    var last: String? = nil
    var lastWidth: CGFloat = 50

    var body: some View {
        HStack(spacing: 0) {
            Text(verbatim: "N°").swissLabel(size: 11).frame(width: IndexTable.numberColumn, alignment: .leading)
            Text(title).swissLabel(size: 11)
            Spacer(minLength: 12)
            if let page {
                Text(page).swissLabel(size: 11).frame(width: IndexTable.pageColumn, alignment: .leading)
                    .padding(.trailing, 12)
            }
            Text(key).swissLabel(size: 11).frame(width: ReadableLayout.keyWidth, alignment: .leading)
            Text(last ?? "").swissLabel(size: 11).frame(width: lastWidth, alignment: .trailing)
        }
        .padding(.bottom, 10)
        .swissRule(Swiss.text)
        .accessibilityHidden(true)
    }
}

/// Une ligne des pages lisibles : son numéro (listes de résultats), le nom, sa page en petites capitales, la touche
/// dans son cadre, puis ↺ (ou un autre bouton) ; un trait fin dessous. Toute la ligne ouvre la fiche de la touche.
struct ReadableRow<Trailing: View>: View {
    let title: String
    var bold = false
    var number: Int? = nil
    var detail: String? = nil
    var dimmed = false
    var warning: String? = nil
    let combo: KeyCombo?
    var changed = false
    let onKey: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            if let number {
                Text(String(format: "%02d", number))
                    .font(Swiss.font(12, .regular)).monospacedDigit()
                    .foregroundStyle(Swiss.gray)
                    .frame(width: IndexTable.numberColumn, alignment: .leading)
            }
            Text(title)
                .font(Swiss.font(15, bold ? .medium : .regular))
                .foregroundStyle(dimmed ? Swiss.gray : Swiss.text)
                .lineLimit(1)
                .layoutPriority(-1)
            if let warning {
                SwissWarningMark(size: 7).padding(.leading, 8).help(warning)
                    .accessibilityLabel(String(localized: "Attention : ") + warning)
            }
            Spacer(minLength: 12)
            if let detail {
                Text(detail).swissLabel(size: 10.5).lineLimit(1)
                    .frame(width: IndexTable.pageColumn, alignment: .leading)
                    .padding(.trailing, 12)
            }
            Button(action: onKey) { KeyBox(combo: combo, changed: changed) }
                .buttonStyle(.plain)
                .help(String(localized: "Changer la touche"))
                .accessibilityLabel(String(localized: "Changer la touche de \(title)"))
            trailing()
                .frame(width: 50, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, minHeight: number == nil ? ReadableLayout.rowHeight : 62, alignment: .leading)
        .swissRule(Swiss.faint)
        .contentShape(Rectangle())
        .onTapGesture(perform: onKey)
    }
}

/// ↺ au bout d'une ligne : remet la touche d'origine de FL.
struct ReadableResetButton: View {
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Swiss.text)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(String(localized: "Réinitialiser"))
    }
}

/// Une partie d'une page de raccourcis (maquette A) : le nom du groupe en demi-gras et son nombre en gris à gauche
/// (« Outils 09 »), ses lignes à droite.
struct ReadableGroup<Content: View>: View {
    let title: String
    var count: Int? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(Swiss.font(13, .semibold)).foregroundStyle(Swiss.text)
                    .lineLimit(2)
                if let count {
                    Text(String(format: "%02d", count)).font(Swiss.font(11, .medium)).monospacedDigit()
                        .foregroundStyle(Swiss.gray)
                }
            }
            .frame(width: ReadableLayout.groupColumn, alignment: .leading)
            .padding(.top, 17)
            .padding(.trailing, 10)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content() }
        }
        .padding(.bottom, 36)
    }
}

// MARK: - Trouver un raccourci

/// « Appuie sur un raccourci » (maquette A) : « TOUCHES », puis la grande ligne soulignée de rouge. Un clic attend les
/// touches ; appuyées, elles s'y écrivent en très grand, avec × pour recommencer. En mode « ou tape son nom », la ligne
/// devient une recherche par le nom.
struct FindShortcutField: View {
    let combo: KeyCombo?
    let listening: Bool
    let typing: Bool
    @Binding var query: String
    let focusSerial: Int
    let startListening: () -> Void
    let clear: () -> Void

    private var lit: Bool { (combo != nil && !typing) || listening || typing }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(typing ? String(localized: "Nom") : String(localized: "Touches")).swissLabel(size: 11)
            HStack(spacing: 12) {
                if typing {
                    SidebarSearchField(text: $query, prompt: String(localized: "Tape son nom"), focusSerial: focusSerial)
                        .frame(maxWidth: .infinity)
                } else if let combo {
                    Text(combo.display).font(.custom(Swiss.titleFontName, size: 56).weight(.semibold))
                        .tracking(-1.6).foregroundStyle(Swiss.text).lineLimit(1).minimumScaleFactor(0.5)
                    Spacer(minLength: 0)
                } else {
                    Text(listening ? String(localized: "Appuie sur les touches…") : String(localized: "Clique ici"))
                        .font(Swiss.font(26, .regular))
                        .foregroundStyle(listening ? Swiss.text : Swiss.gray)
                    Spacer(minLength: 0)
                }
                if (typing && !query.isEmpty) || (!typing && combo != nil) {
                    Button(action: clear) {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .medium)).foregroundStyle(Swiss.text)
                            .frame(width: 44, height: 44)
                            .overlay(Rectangle().strokeBorder(Swiss.text, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "Effacer"))
                    .accessibilityLabel(String(localized: "Effacer"))
                }
            }
            .frame(height: 80)
            .overlay(alignment: .bottom) {
                Rectangle().fill(lit ? Swiss.red : Swiss.text).frame(height: 2)
            }
            .contentShape(Rectangle())
            .onTapGesture { if !typing { startListening() } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(typing ? String(localized: "Tape son nom") : String(localized: "Appuie sur un raccourci"))
        }
    }
}

/// Petit lien souligné sous la grande case (« ou tape son nom »).
struct ReadableLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(Swiss.font(13, .regular)).foregroundStyle(Swiss.soft).underline()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Fenêtre « Minimal » (20/11)

/// Menus en haut de la fenêtre (maquette « Minimal », validée le 19/11 : « vasi go met la maquette dans le vrai
/// logiciel ») à la place de la barre de gauche : Trouver, Raccourcis, Macros, Communauté, Compte, Aide. Des mots en
/// gris ; la partie ouverte à l'encre, en demi-gras ; un point rouge : des nouveautés (Communauté), une réponse de
/// l'équipe (Aide), un choix à faire (Compte).
struct MinimalNavBar: View {
    let selected: SidebarItem?
    var communityDot = false
    var accountDot = false
    var helpDot = false
    let choose: (SidebarItem) -> Void

    private var part: Int { ReadableSidebar.number(selected ?? .find) }

    var body: some View {
        HStack(spacing: 24) {
            item(1, String(localized: "Trouver"), .find)
            item(2, String(localized: "Raccourcis"), nil)
            item(3, String(localized: "Macros"), .macros)
            item(4, String(localized: "Communauté"), .community, dot: communityDot)
            item(5, String(localized: "Compte"), .account, dot: accountDot)
            item(6, String(localized: "Aide"), .help, dot: helpDot)
            Spacer(minLength: 0)
        }
        // Dans la barre de titre (20/11) : à droite des boutons de la fenêtre, au bord de la colonne des pages (maquette).
        .frame(height: MainWindowChrome.titleBarHeight - 8)
        .padding(.leading, MinimalNavBar.leadingGap)
    }

    /// Écart entre les boutons de la fenêtre et « Trouver » (maquette : « Trouver » vers 214 points du bord).
    static let leadingGap: CGFloat = 120

    /// `target` nil : « Raccourcis », qui rouvre la dernière page de raccourcis (EditorView.choose).
    private func item(_ number: Int, _ title: String, _ target: SidebarItem?, dot: Bool = false) -> some View {
        MinimalNavItem(title: title, selected: part == number, dot: dot) {
            choose(target ?? .section(FLSection.allCases[0]))
        }
    }
}

private struct MinimalNavItem: View {
    let title: String
    let selected: Bool
    let dot: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(Swiss.font(13, selected ? .semibold : .regular))
                    .foregroundStyle(selected || hovering ? Swiss.text : Swiss.gray)
                    .lineLimit(1)
                if dot {
                    Rectangle().fill(Swiss.red).frame(width: 6, height: 6)
                        .accessibilityLabel(String(localized: "Nouveautés"))
                }
            }
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Pages de FL à gauche de « Raccourcis » (maquette « Minimal ») : les 8 pages puis « Mes raccourcis », en gris ; la
/// page ouverte à l'encre avec son carré rouge.
struct ShortcutsSubnav: View {
    let selected: SidebarItem?
    let choose: (SidebarItem) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(FLSection.allCases) { section in
                    row(.section(section), section.title)
                }
                row(.custom, String(localized: "Mes raccourcis"))
            }
            .padding(.top, 40)
            .padding(.bottom, 24)
        }
        // Colonnes 1 à 3 de la grille de la maquette : la page commence à la 4e.
        .frame(width: 254, alignment: .leading)
        .padding(.leading, ReadableLayout.inset)
        .padding(.trailing, 24 - ReadableLayout.inset)
    }

    private func row(_ item: SidebarItem, _ title: String) -> some View {
        SubnavRow(title: title, selected: selected == item) { choose(item) }
    }
}

private struct SubnavRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Rectangle().fill(selected ? Swiss.red : Color.clear).frame(width: 8, height: 8)
                Text(title)
                    .font(Swiss.font(15, selected ? .semibold : .regular))
                    .foregroundStyle(selected || hovering ? Swiss.text : Swiss.gray)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Titre d'une page (maquette « Minimal ») : 32 points, demi-gras, serré ; la flèche ← devant sur la page d'une personne.
struct MinimalTitle: View {
    let text: String
    var back: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let back {
                Button(action: back) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Swiss.text)
                        .frame(width: 24, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Revenir à la Communauté"))
                .accessibilityLabel(String(localized: "Revenir"))
            }
            Text(text)
                .font(Swiss.font(32, .semibold))
                .tracking(-0.64)
                .foregroundStyle(Swiss.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// Étapes de « Trouver » (maquette « Minimal ») : 1 Touche, 2 Action, 3 Nouvelle touche ; l'étape en cours à l'encre en
/// demi-gras, les étapes passées en gris, les suivantes plus pâles.
struct FindSteps: View {
    let now: Int

    var body: some View {
        HStack(spacing: 24) {
            step(1, String(localized: "Touche"))
            step(2, String(localized: "Action"))
            step(3, String(localized: "Nouvelle touche"))
        }
        .accessibilityElement(children: .combine)
    }

    /// Maquette : l'étape en cours, son numéro en rouge et son nom à l'encre en demi-gras ; les passées en gris ; les
    /// suivantes pâles. `now` 4 : tout est fait (« C'est changé. »), les trois en gris.
    private func step(_ n: Int, _ title: String) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: "\(n)").foregroundStyle(n == now ? Swiss.red : n < now ? Swiss.gray : Swiss.faintText)
            Text(title).foregroundStyle(n == now ? Swiss.text : n < now ? Swiss.gray : Swiss.faintText)
        }
        .font(Swiss.font(13, n == now ? .semibold : .regular))
    }
}

// MARK: - Grille du papier

/// Thème Papier (maquette « Minimal », 20/11 : « papier n'a pas les traits ») : la grille suisse visible, un trait fin
/// au bord de chaque colonne (12 colonnes, gouttières de 24, 48 points du bord de la fenêtre), couleur #E2DFD8.
/// Rien dans les thèmes Noir et Orange.
struct PaperGrid: View {
    static let color = Color(red: 0xE2 / 255, green: 0xDF / 255, blue: 0xD8 / 255)

    var body: some View {
        if AppTheme.current == .papier {
            GeometryReader { proxy in
                Path { path in
                    for x in PaperGrid.lines(width: proxy.size.width) {
                        path.addRect(CGRect(x: x, y: 0, width: 1, height: proxy.size.height))
                    }
                }
                .fill(PaperGrid.color)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Pur : abscisses des traits pour une fenêtre de `width` points (bords gauche et droit de chaque colonne).
    static func lines(width: CGFloat, margin: CGFloat = 48, gutter: CGFloat = 24, columns: Int = 12) -> [CGFloat] {
        let content = min(width - 2 * margin, ReadableLayout.maxWidth)
        let column = (content - CGFloat(columns - 1) * gutter) / CGFloat(columns)
        guard column > 0 else { return [] }
        return (0..<columns).flatMap { k -> [CGFloat] in
            let x = margin + CGFloat(k) * (column + gutter)
            return [x, x + column]
        }
    }
}

/// Clignote comme le curseur de la maquette (1,1 s : allumé puis éteint), seulement à l'écran.
struct Blinking: ViewModifier {
    func body(content: Content) -> some View {
        TimelineView(.periodic(from: .now, by: 0.55)) { context in
            content.opacity(Int(context.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0 ? 1 : 0)
        }
    }
}

extension View {
    func blinking() -> some View { modifier(Blinking()) }
}
