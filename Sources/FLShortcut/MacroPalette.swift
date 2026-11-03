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
    /// Vidéo du 03/11 (« les mots se superposent avec les 3 options en haut à gauche pour fermer l'app ») : la liste
    /// commençait dans la barre de titre (46 points sous le haut, barre de 52) ; une liste qui touche la barre de titre
    /// défile jusqu'en haut de la fenêtre, sous les boutons. Elle commence maintenant sous la barre et ne dessine rien
    /// au-dessus d'elle (`clipped`).
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(BlockCategory.paletteOrder, id: \.self) { category in
                    section(category)
                }
            }
            .padding(.bottom, 4)
        }
        .clipped()
        .padding(.horizontal, 10)
        // Sous la barre de titre (la plaque est à 8 points du haut de la fenêtre), avec 4 points d'air.
        .padding(.top, MainWindowChrome.titleBarHeight - 8 + 4)
        .padding(.bottom, 16)
    }

    @ViewBuilder private func section(_ category: BlockCategory) -> some View {
        let group = items.filter { $0.category == category }
        if !group.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                Text(category.label)
                    .swissLabel()
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
                .menuHover(tint: Swiss.text, cornerRadius: 0)
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
        // Style suisse (01/11) : un petit carré de la couleur de la catégorie, puis le nom.
        HStack(spacing: 10) {
            Rectangle().fill(item.category.tint).frame(width: 8, height: 8).accessibilityHidden(true)
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
        HStack(spacing: 10) {
            Rectangle().fill(item.category.tint).frame(width: 8, height: 8)
            Text(item.label).font(.system(size: 13, weight: .bold)).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Rectangle().fill(Swiss.background))
        .overlay(Rectangle().strokeBorder(Swiss.text, lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 16, y: 9)
        .scaleEffect(1.06)
        .rotationEffect(.degrees(Motion.reduce ? 0 : -2))
        .padding(22)                          // place pour l'ombre
    }
}
