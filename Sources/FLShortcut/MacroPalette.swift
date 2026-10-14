// Créateur de macros : palette des blocs, à gauche (barre latérale en verre du système sur macOS 26).
// Par catégorie, avec une recherche : taper filtre, ↩ ajoute le premier bloc trouvé sous la sélection. Un clic
// ajoute le bloc. Les blocs pas encore réglables ici (conditions) sont grisés, « bientôt ».
// Statique : aucune animation, aucun survol animé, aucun verre par ligne.
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
    @State private var query = ""

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    private var results: [PaletteItem] { PaletteCatalog.search(items, trimmed) }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            List {
                if trimmed.isEmpty {
                    ForEach(BlockCategory.allCases, id: \.self) { category in
                        section(category)
                    }
                } else if results.isEmpty {
                    Text("Aucun bloc ne correspond à « \(trimmed) ».")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { item in row(item) }
                }
            }
            .listStyle(.sidebar)
        }
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

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Ajouter un bloc…", text: $query)
                .textFieldStyle(.plain)
                .onSubmit(addFirst)
                .accessibilityLabel("Rechercher un bloc à ajouter")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Effacer la recherche")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .help("Tape le nom d'un bloc, puis ↩ pour l'ajouter sous la ligne choisie")
    }

    /// ↩ dans la recherche : le premier bloc disponible est ajouté, la recherche se vide pour le suivant.
    private func addFirst() {
        guard !trimmed.isEmpty, let first = results.first(where: { !$0.soon }) else { return }
        insert(first)
        query = ""
    }

    private func row(_ item: PaletteItem) -> some View {
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
        .buttonStyle(.plain)
        .disabled(item.soon)
        .opacity(item.soon ? 0.5 : 1)
        .help(item.soon ? "Bientôt : " + item.aide : item.aide)
        .accessibilityHint(item.soon ? "Pas encore disponible" : "Ajoute ce bloc sous la ligne choisie")
    }
}
