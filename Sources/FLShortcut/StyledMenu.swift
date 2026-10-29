// Menus de l'app au style du menu de l'icône (demandé par l'utilisateur) : ⋯ de la page principale, options d'une
// macro, « + Ajouter » du créateur. Chaque option a son icône de couleur à gauche ; au survol, la carte du guide (voile
// clair, liseré de sa couleur, ombre douce) ; à l'ouverture, les options arrivent l'une après l'autre (flou → net, de
// haut en bas, ressort) et leur icône éclot. Une liste à déplier (« Charger un profil ») s'ouvre sur place en poussant
// les options du dessous, au lieu d'un sous-menu. Une bulle de macOS (popover) les porte, sans lueur de couleur
// (28/10). Rien ne tourne au repos.
import SwiftUI

/// Une ligne d'un menu.
struct StyledMenuEntry {
    enum Kind {
        case action(() -> Void)
        /// Interrupteur : la ligne le bascule, le menu reste ouvert.
        case toggle(Binding<Bool>)
        /// Liste à déplier sur place.
        case group([StyledMenuEntry])
        /// Titre d'un groupe de lignes (petites capitales grises).
        case header
        case separator
    }

    var title = ""
    var symbol = ""
    var tint: Color = .gray
    var shortcut: String?
    var help: String?
    let kind: Kind

    static func item(_ title: String, symbol: String, tint: Color, shortcut: String? = nil, help: String? = nil,
                     action: @escaping () -> Void) -> StyledMenuEntry {
        StyledMenuEntry(title: title, symbol: symbol, tint: tint, shortcut: shortcut, help: help, kind: .action(action))
    }

    static func toggle(_ title: String, symbol: String, tint: Color, isOn: Binding<Bool>) -> StyledMenuEntry {
        StyledMenuEntry(title: title, symbol: symbol, tint: tint, kind: .toggle(isOn))
    }

    static func group(_ title: String, symbol: String, tint: Color, _ entries: [StyledMenuEntry]) -> StyledMenuEntry {
        StyledMenuEntry(title: title, symbol: symbol, tint: tint, kind: .group(entries))
    }

    static func header(_ title: String) -> StyledMenuEntry { StyledMenuEntry(title: title, kind: .header) }

    static let separator = StyledMenuEntry(kind: .separator)
}

/// Bouton qui ouvre un menu de ce style. `entries` est lu à l'ouverture (état du moment).
struct StyledMenuButton<Content: View>: View {
    let help: String
    let arrowEdge: Edge
    let width: CGFloat
    let entries: () -> [StyledMenuEntry]
    let label: () -> Content
    @State private var shown = false

    init(help: String, arrowEdge: Edge = .bottom, width: CGFloat = 270,
         entries: @escaping () -> [StyledMenuEntry], @ViewBuilder label: @escaping () -> Content) {
        self.help = help
        self.arrowEdge = arrowEdge
        self.width = width
        self.entries = entries
        self.label = label
    }

    var body: some View {
        Button { shown.toggle() } label: { label() }
            .help(help)
            .popover(isPresented: $shown, arrowEdge: arrowEdge) {
                StyledMenuList(entries: entries(), width: width) { shown = false }
            }
    }
}

/// Contenu du menu : les lignes, qui arrivent l'une après l'autre.
struct StyledMenuList: View {
    let entries: [StyledMenuEntry]
    var width: CGFloat = 270
    let close: () -> Void
    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StyledMenuRows(entries: entries, revealed: revealed, firstOrder: 0, close: close)
        }
        .padding(8)
        .frame(width: width)
        .onAppear {
            // Un tour plus tard : l'état replié est d'abord affiché, puis les lignes arrivent.
            DispatchQueue.main.async { revealed = true }
        }
    }
}

/// Lignes d'un menu (ou d'une liste dépliée), numérotées pour arriver chacune à son tour.
private struct StyledMenuRows: View {
    let entries: [StyledMenuEntry]
    let revealed: Bool
    let firstOrder: Int
    let close: () -> Void
    @State private var unfolded: Set<Int> = []

    var body: some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { i, entry in
            switch entry.kind {
            case .separator:
                Divider().padding(.horizontal, 8).padding(.vertical, 4)
                    .menuRevealRow(revealed, index: firstOrder + i)
            case .header:
                Text(entry.title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, i == 0 ? 2 : 8)
                    .padding(.bottom, 2)
                    .menuRevealRow(revealed, index: firstOrder + i)
            case .group(let children):
                let open = unfolded.contains(i)
                StyledMenuRow(entry: entry, order: firstOrder + i, revealed: revealed, chevron: open ? .open : .closed) {
                    withAnimation(Motion.quickMorph) {
                        if open { unfolded.remove(i) } else { unfolded.insert(i) }
                    }
                }
                if open {
                    VStack(alignment: .leading, spacing: 0) {
                        StyledMenuRows(entries: children, revealed: true, firstOrder: 0, close: close)
                    }
                    .padding(.leading, 18)
                    .transition(Motion.transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity)))
                }
            case .toggle(let isOn):
                StyledMenuRow(entry: entry, order: firstOrder + i, revealed: revealed, toggle: isOn) {
                    isOn.wrappedValue.toggle()
                }
            case .action(let action):
                StyledMenuRow(entry: entry, order: firstOrder + i, revealed: revealed) {
                    // Le menu se ferme d'abord : une boîte (ouvrir un fichier, confirmer) ne s'ouvre pas sous la bulle.
                    close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: action)
                }
            }
        }
    }
}

/// Une option : icône de couleur, titre, raccourci ou interrupteur ; au survol, la carte du guide.
private struct StyledMenuRow: View {
    enum Chevron { case closed, open }

    let entry: StyledMenuEntry
    let order: Int
    let revealed: Bool
    var chevron: Chevron?
    var toggle: Binding<Bool>?
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SectionIcon(symbol: entry.symbol, tint: entry.tint, size: 22)
                    .scaleEffect(revealed || reduceMotion ? 1 : 0.35)
                    .rotationEffect(.degrees(revealed || reduceMotion ? 0 : -25))
                    .animation(revealed
                               ? .spring(response: 0.5, dampingFraction: 0.58).delay(0.12 + Double(order) * 0.04)
                               : .easeIn(duration: 0.12), value: revealed)
                Text(entry.title)
                    .lineLimit(1)
                Spacer(minLength: 12)
                if let shortcut = entry.shortcut {
                    Text(shortcut).foregroundStyle(.secondary)
                }
                if let toggle {
                    Toggle("", isOn: toggle)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
                if let chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(chevron == .open ? 90 : 0))
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 32)
            .contentShape(shape)
            .background {
                shape.fill(Color.primary.opacity(hovering ? 0.085 : 0))
                    .overlay(shape.strokeBorder(entry.tint.opacity(hovering ? 0.6 : 0), lineWidth: hovering ? 1.5 : 1))
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering && !reduceMotion ? 1.03 : 1)
        .shadow(color: entry.tint.opacity(hovering ? 0.3 : 0), radius: hovering ? 10 : 0, y: hovering ? 4 : 0)
        .help(entry.help ?? "")
        .onHover { inside in
            withAnimation(reduceMotion ? Motion.reduced : Motion.lift) { hovering = inside }
        }
        .menuRevealRow(revealed, index: order)
    }
}
