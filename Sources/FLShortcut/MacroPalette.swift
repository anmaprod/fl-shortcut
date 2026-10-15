// Créateur de macros : palette des blocs, à gauche (barre latérale en verre du système sur macOS 26).
// Par catégorie. Un clic ajoute le bloc ; on peut aussi le prendre et le glisser à sa place dans la liste. Les blocs
// pas encore réglables ici (conditions) sont grisés, « bientôt ». Survol : le bloc se soulève un peu ; appuyé, il
// flotte ; pendant le glisser, une pastille qui flotte suit la souris. Aucun verre par ligne.
import AppKit
import SwiftUI

extension BlockCategory {
    /// Couleur de la catégorie (icônes des lignes et de la palette) : bleu les touches, orange la souris, vert les
    /// attentes, violet FL et ses menus, gris le contrôle.
    var tint: Color {
        switch self {
        case .clavier: return .blue
        case .souris: return .orange
        case .fenetres: return .green
        case .fl: return .purple
        case .controle: return .gray
        }
    }
}

struct MacroPaletteView: View {
    /// Liste calculée une fois par le créateur ; aucun modèle observé : la palette ne se redessine pas à chaque
    /// modification de la macro.
    let items: [PaletteItem]
    let insert: (PaletteItem) -> Void

    /// La liste est la vue de la colonne elle-même, comme la barre latérale des raccourcis : macOS lui donne la marge
    /// du haut (sous les boutons fermer / réduire / agrandir). Dans une pile, elle montait jusque sous ces boutons.
    var body: some View {
        List {
            ForEach(BlockCategory.allCases, id: \.self) { category in
                section(category)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder private func section(_ category: BlockCategory) -> some View {
        let group = items.filter { $0.category == category }
        if !group.isEmpty {
            Section {
                ForEach(group) { item in row(item) }
            } header: {
                Text(category.rawValue)
            }
        }
    }

    /// Un clic ajoute le bloc sous la sélection ; on peut aussi le glisser à la place voulue dans la liste.
    @ViewBuilder private func row(_ item: PaletteItem) -> some View {
        if item.soon {
            button(item)
        } else {
            button(item)
                .onDrag { PaletteDrag.provider(item) } preview: { PaletteDragPreview(item: item) }
        }
    }

    private func button(_ item: PaletteItem) -> some View {
        Button {
            insert(item)
        } label: {
            HStack(spacing: 8) {
                SectionIcon(symbol: item.symbol, tint: item.category.tint, size: 22)
                Text(item.label).lineLimit(1)
                Spacer(minLength: 4)
                if item.soon {
                    Text("bientôt")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LiftButtonStyle())
        .hoverLift()
        .disabled(item.soon)
        .opacity(item.soon ? 0.5 : 1)
        .help(item.soon ? "Bientôt : " + item.aide : item.aide + " Clique pour l'ajouter, ou glisse-le à sa place dans la liste.")
        .accessibilityHint(item.soon ? "Pas encore disponible" : "Ajoute ce bloc sous la ligne choisie")
    }
}

/// Glisser un bloc de la palette vers la liste : un texte « flshortcut-block:<id> », que seule la liste du créateur
/// comprend (lâché ailleurs, c'est un texte sans effet).
enum PaletteDrag {
    static let prefix = "flshortcut-block:"

    static func provider(_ item: PaletteItem) -> NSItemProvider {
        NSItemProvider(object: (prefix + item.id) as NSString)
    }

    /// Entrée de palette portée par le glisser, rendue sur le fil principal ; rien pour un autre texte.
    static func load(_ providers: [NSItemProvider], _ done: @escaping (String) -> Void) {
        guard let p = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return }
        _ = p.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? NSString, text.hasPrefix(prefix) else { return }
            let id = String((text as String).dropFirst(prefix.count))
            DispatchQueue.main.async { done(id) }
        }
    }
}

/// Ce qui suit la souris pendant le glisser : le bloc soulevé, qui flotte (un peu plus grand, légèrement penché,
/// grande ombre douce), comme une carte qu'on vient de prendre.
private struct PaletteDragPreview: View {
    let item: PaletteItem

    var body: some View {
        HStack(spacing: 8) {
            SectionIcon(symbol: item.symbol, tint: item.category.tint, size: 22)
            Text(item.label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.97)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.28), radius: 16, y: 9)
        .scaleEffect(1.06)
        .rotationEffect(.degrees(Motion.reduce ? 0 : -2))
        .padding(22)                          // place pour l'ombre
    }
}
