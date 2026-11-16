// Fenêtre principale « plus lisible » (maquette du 16/11, « FL Shortcuts — plus lisible », 8 écrans) : une barre de
// gauche en parties qui se déplient (Trouver un raccourci ; Raccourcis : les pages de FL et Mes raccourcis ; Macros ;
// Plus : Communauté, Mon compte, Aide), la page choisie marquée d'un carré rouge ; les raccourcis en une seule liste
// (nom, touche dans une case, ↺), rangés sous le nom de leur groupe à gauche ; « appuie sur un raccourci » pour en
// trouver un par ses touches ou son nom. Pièces de EditorView ; rien n'y est enregistré.
import SwiftUI

/// Mise en page des pages lisibles (maquette : le titre et la liste partent du même bord, liste de 784 points au plus).
enum ReadableLayout {
    static let inset: CGFloat = 56
    static let maxWidth: CGFloat = 800
    /// Colonne du nom de groupe (« OUTILS ») à gauche des lignes d'une page de raccourcis.
    static let groupColumn: CGFloat = 166
    /// Case d'une touche (« ⌘S »).
    static let keyWidth: CGFloat = 100
    static let rowHeight: CGFloat = 51
}

// MARK: - Barre de gauche

/// La barre de gauche de la maquette : « fl shortcuts. », puis les parties. Un clic sur « Raccourcis » ou « Plus » les
/// ouvre ou les ferme ; la page ouverte a son carré rouge.
struct ReadableSidebar: View {
    let selected: SidebarItem?
    @Binding var shortcutsOpen: Bool
    @Binding var moreOpen: Bool
    /// Nouveautés d'une personne suivie (Communauté) ; ce Mac et le compte ont chacun leurs changements (Mon compte).
    var communityDot = false
    var accountDot = false
    let choose: (SidebarItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Place des boutons fermer / réduire / agrandir de la fenêtre.
            Color.clear.frame(height: 12)
            brand
                .padding(.top, 22)
                .padding(.bottom, 30)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    top(.find, String(localized: "Trouver un raccourci"))
                    part(String(localized: "Raccourcis"), open: $shortcutsOpen) {
                        ForEach(FLSection.allCases) { section in
                            sub(.section(section), section.title)
                        }
                        Rectangle().fill(Swiss.line).frame(height: 1)
                            .padding(.leading, 34).padding(.trailing, 12)
                            .padding(.vertical, 6)
                        sub(.custom, String(localized: "Mes raccourcis"))
                    }
                    top(.macros, String(localized: "Macros"))
                    part(String(localized: "Plus"), open: $moreOpen, dot: communityDot || accountDot) {
                        sub(.community, String(localized: "Communauté"), dot: communityDot)
                        sub(.account, String(localized: "Mon compte"), dot: accountDot)
                        sub(.help, String(localized: "Aide"))
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(.leading, 12)
        .frame(width: EditorView.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .trailing) { Rectangle().fill(Swiss.line).frame(width: 1) }
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
            Text(verbatim: "fl shortcuts").font(Swiss.font(15)).tracking(-0.4).foregroundStyle(Swiss.text)
            Rectangle().fill(Swiss.brandRed).frame(width: 4, height: 4)
        }
        .padding(.leading, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "FL Shortcuts"))
    }

    /// Ligne du haut (« Trouver un raccourci », « Macros ») : carré rouge quand elle est ouverte.
    private func top(_ item: SidebarItem, _ title: String) -> some View {
        let isOn = selected == item
        return SidebarTopRow(title: title, mark: isOn ? .square : .blank, selected: isOn) { choose(item) }
    }

    /// Partie qui se déplie (« Raccourcis », « Plus ») : son triangle, puis ses pages dessous quand elle est ouverte.
    private func part<Content: View>(_ title: String, open: Binding<Bool>, dot: Bool = false,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarTopRow(title: title, mark: open.wrappedValue ? .open : .closed, selected: false,
                          dot: dot && !open.wrappedValue) { open.wrappedValue.toggle() }
                .accessibilityValue(open.wrappedValue ? String(localized: "ouvert") : String(localized: "fermé"))
            if open.wrappedValue {
                VStack(alignment: .leading, spacing: 0) { content() }
                    .padding(.bottom, 8)
            }
        }
    }

    private func sub(_ item: SidebarItem, _ title: String, dot: Bool = false) -> some View {
        SidebarSubRow(title: title, selected: selected == item, dot: dot) { choose(item) }
    }
}

/// Ligne du haut de la barre de gauche : sa marque (carré rouge, triangle), puis le titre en gras.
private struct SidebarTopRow: View {
    enum Mark { case blank, square, open, closed }
    let title: String
    let mark: Mark
    let selected: Bool
    var dot = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Group {
                    switch mark {
                    case .blank: Color.clear
                    case .square: Rectangle().fill(Swiss.brandRed).frame(width: 6, height: 6)
                    case .open: Image(systemName: "arrowtriangle.down.fill").font(.system(size: 7)).foregroundStyle(Swiss.gray)
                    case .closed: Image(systemName: "arrowtriangle.right.fill").font(.system(size: 7)).foregroundStyle(Swiss.gray)
                    }
                }
                .frame(width: 20, alignment: .leading)
                .padding(.leading, 8)
                Text(title).font(Swiss.font(15)).foregroundStyle(Swiss.text).lineLimit(1)
                if dot {
                    Rectangle().fill(Swiss.red).frame(width: 6, height: 6).padding(.leading, 8)
                        .accessibilityLabel(String(localized: "Nouveautés"))
                }
                Spacer(minLength: 0)
            }
            .frame(height: 46)
            .opacity(hovering && !selected ? 0.75 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Page d'une partie (« Playlist », « Communauté ») : en gris, blanche quand elle est ouverte, avec son carré rouge.
private struct SidebarSubRow: View {
    let title: String
    let selected: Bool
    var dot = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Group {
                    if selected { Rectangle().fill(Swiss.brandRed).frame(width: 6, height: 6) } else { Color.clear }
                }
                .frame(width: 14, alignment: .leading)
                .padding(.leading, 28)
                Text(title)
                    .font(selected ? Swiss.font(14.5) : .system(size: 14.5))
                    .foregroundStyle(selected || hovering ? Swiss.text : Swiss.soft)
                    .lineLimit(1)
                if dot {
                    Rectangle().fill(Swiss.red).frame(width: 6, height: 6).padding(.leading, 8)
                        .accessibilityLabel(String(localized: "Nouveautés"))
                }
                Spacer(minLength: 0)
            }
            .frame(height: 29)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Touche et lignes

/// La touche d'un raccourci dans sa case (maquette : « ⌘S » en gras, cadre gris) ; changée : en rouge.
struct KeyBox: View {
    let combo: KeyCombo?
    var changed = false
    var placeholder = "—"
    @State private var hovering = false

    var body: some View {
        Text(combo?.display ?? placeholder)
            .font(Swiss.font(14))
            .foregroundStyle(changed ? Swiss.red : (combo == nil ? Swiss.gray : Swiss.text))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6)
            .frame(width: ReadableLayout.keyWidth, height: 32)
            .background(Rectangle().fill(hovering ? Swiss.faint : Swiss.background))
            .overlay(Rectangle().strokeBorder(hovering ? Swiss.text : Swiss.keyLine, lineWidth: 1))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(combo?.spoken ?? String(localized: "aucune"))
    }
}

/// Une ligne des pages lisibles : le nom, un libellé en petites capitales (sa page, « avant ⌘S »), la touche dans sa
/// case, puis ↺ (ou un autre bouton) ; un trait fin dessous. Toute la ligne ouvre la fiche de la touche.
struct ReadableRow<Trailing: View>: View {
    let title: String
    var bold = false
    var detail: String? = nil
    var dimmed = false
    var warning: String? = nil
    let combo: KeyCombo?
    var changed = false
    let onKey: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(bold ? Swiss.font(15) : .system(size: 15))
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
                    .frame(maxWidth: 220, alignment: .leading)
                    .padding(.trailing, 12)
            }
            Button(action: onKey) { KeyBox(combo: combo, changed: changed) }
                .buttonStyle(.plain)
                .help(String(localized: "Changer la touche"))
                .accessibilityLabel(String(localized: "Changer la touche de \(title)"))
            trailing()
                .frame(width: 50)
        }
        .frame(maxWidth: .infinity, minHeight: ReadableLayout.rowHeight, alignment: .leading)
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Swiss.gray)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(String(localized: "Réinitialiser"))
    }
}

/// Une partie d'une page de raccourcis : le nom du groupe à gauche (« OUTILS »), ses lignes à droite.
struct ReadableGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(title).swissLabel(size: 10.5)
                .lineLimit(2)
                .frame(width: ReadableLayout.groupColumn, alignment: .leading)
                .padding(.top, 19)
                .padding(.trailing, 10)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content() }
        }
        .padding(.bottom, 34)
    }
}

// MARK: - Trouver un raccourci

/// « appuie sur un raccourci » : la grande case. Un clic attend les touches ; appuyées, elles s'y écrivent en gras,
/// cadre rouge, avec × pour recommencer. En mode « ou tape son nom », la case devient une recherche par le nom.
struct FindShortcutField: View {
    let combo: KeyCombo?
    let listening: Bool
    let typing: Bool
    @Binding var query: String
    let focusSerial: Int
    let startListening: () -> Void
    let clear: () -> Void

    private var lit: Bool { (combo != nil && !typing) || listening }

    var body: some View {
        HStack(spacing: 14) {
            if typing {
                SidebarSearchField(text: $query, prompt: String(localized: "Tape son nom"), focusSerial: focusSerial)
                    .frame(maxWidth: .infinity)
            } else if let combo {
                Text(combo.display).font(Swiss.font(19)).foregroundStyle(Swiss.text)
                Spacer(minLength: 0)
            } else {
                Text(listening ? String(localized: "Appuie sur les touches…") : String(localized: "Clique ici"))
                    .font(.system(size: 18))
                    .foregroundStyle(listening ? Swiss.text : Swiss.gray)
                Spacer(minLength: 0)
            }
            if (typing && !query.isEmpty) || (!typing && combo != nil) {
                Button(action: clear) {
                    Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(Swiss.gray)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Effacer"))
                .accessibilityLabel(String(localized: "Effacer"))
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 66)
        .background(Rectangle().fill(Swiss.background))
        .overlay(Rectangle().strokeBorder(lit ? Swiss.red : Swiss.text, lineWidth: lit ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { if !typing { startListening() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(typing ? String(localized: "Tape son nom") : String(localized: "Appuie sur un raccourci"))
    }
}

/// Petit lien souligné sous la grande case (« ou tape son nom »).
struct ReadableLink: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 12.5)).foregroundStyle(Swiss.gray).underline()
        }
        .buttonStyle(.plain)
    }
}
