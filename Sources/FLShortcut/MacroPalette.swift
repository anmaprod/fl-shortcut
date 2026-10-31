// Créateur de macros : palette des blocs, à gauche, dans la plaque claire de la maquette du 28/10 (comme la barre de
// gauche des raccourcis). Par catégorie, sous son titre gris. Un clic ajoute le bloc ; on peut aussi le prendre et le
// glisser à sa place dans la liste. Les blocs pas encore réglables ici (conditions) sont grisés, « bientôt ». Survol :
// le bloc plein de la couleur de sa catégorie ; pendant le glisser, une pastille qui flotte suit la souris.
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

    /// La plaque (maquette) : les boutons fermer / réduire / agrandir en haut, puis les catégories, chacune sous son
    /// titre gris ; elle défile si la fenêtre est basse.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Place des boutons fermer / réduire / agrandir de la fenêtre.
            Color.clear.frame(height: 12)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(BlockCategory.paletteOrder, id: \.self) { category in
                        section(category)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    @ViewBuilder private func section(_ category: BlockCategory) -> some View {
        let group = items.filter { $0.category == category }
        if !group.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text(category.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                ForEach(group) { item in row(item) }
            }
        }
    }

    /// Un clic ajoute le bloc sous la sélection ; on peut aussi le glisser à la place voulue dans la liste.
    /// Ligne simple, pas un bouton : sur macOS, un bouton garde l'appui de la souris pour lui et le glisser ne
    /// démarrait jamais (vrai glisser à la souris de la mesure de la CI : liste inchangée).
    @ViewBuilder private func row(_ item: PaletteItem) -> some View {
        if item.soon {
            label(item)
                .opacity(0.5)
                .help(String(localized: "Bientôt : \(item.aide)"))
                .accessibilityElement(children: .combine)
                .accessibilityHint("Pas encore disponible")
        } else {
            label(item)
                .menuHover(tint: item.category.tint, cornerRadius: 8)
                .onTapGesture { insert(item) }
                .onDrag { PaletteDrag.provider(item) } preview: { PaletteDragPreview(item: item) }
                .help(item.aide)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { insert(item) }
                .accessibilityHint("Ajoute ce bloc sous la ligne choisie")
        }
    }

    /// Ligne de 30 points (maquette) : icône de la catégorie (20 points), puis le nom.
    private func label(_ item: PaletteItem) -> some View {
        HStack(spacing: 9) {
            SectionIcon(symbol: item.symbol, tint: item.category.tint, size: 20)
            Text(item.label).font(.system(size: 13)).lineLimit(1)
            Spacer(minLength: 4)
            if item.soon {
                Text("bientôt")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .contentShape(Rectangle())
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
