// Choix d'une icône de FL (Organiser, bloc « Nom et couleur ») dans une grille disposée comme celle de FL : mêmes
// titres, mêmes cases vides, symboles de macOS. Ouverte à la demande seulement ; rien ne tourne au repos.
import AppKit
import SwiftUI

extension FLIconGrid.Cell {
    /// Symbole d'un macOS plus récent (macOS 13 : 7 cases, Trumpet, Harp…) : un symbole présent partout le remplace,
    /// la case reste reconnaissable par sa place et sa bulle.
    static let fallbackSymbol = "square.dashed"

    var shownSymbol: String {
        Self.available(symbol) ? symbol : Self.fallbackSymbol
    }

    private static let cache = Locked<[String: Bool]>([:])

    static func available(_ name: String) -> Bool {
        if let known = cache.value[name] { return known }
        let found = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
        cache.withLock { $0[name] = found }
        return found
    }
}

struct FLIconPicker: View {
    let selected: FLIcon?
    let pick: (FLIcon?) -> Void

    private static let side: CGFloat = 26
    private static let gap: CGFloat = 2
    private static let shownColumns = Array(0..<FLIconGrid.channelColumn)

    /// Un titre de la barre du haut et le nombre de colonnes qu'il couvre (Channel n'est pas proposée).
    struct Header: Identifiable, Equatable {
        let column: Int
        let title: String
        let span: Int
        var id: Int { column }
    }

    static var headers: [Header] {
        let shown = FLIconGrid.titles.filter { $0.column < FLIconGrid.channelColumn }
        var out: [Header] = []
        for (i, t) in shown.enumerated() {
            let next = i + 1 < shown.count ? shown[i + 1].column : FLIconGrid.channelColumn
            out.append(Header(column: t.column, title: t.title, span: next - t.column))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Icône de FL").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Aucune") { pick(nil) }
                    .controlSize(.small)
                    .help("Ne pas toucher à l'icône dans FL")
            }
            HStack(spacing: Self.gap) {
                ForEach(Self.headers) { header in
                    Text(header.title)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: CGFloat(header.span) * Self.side + CGFloat(header.span - 1) * Self.gap)
                }
            }
            HStack(alignment: .top, spacing: Self.gap) {
                ForEach(Self.shownColumns, id: \.self) { column in
                    VStack(spacing: Self.gap) {
                        ForEach(0..<FLIconGrid.rows, id: \.self) { row in
                            cell(column: column, row: row)
                        }
                    }
                }
            }
            Text("Même place que dans la grille « Change icon… » de FL. Reset retire l'icône dans FL.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
    }

    @ViewBuilder private func cell(column: Int, row: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        if let icon = FLIcon(column: column, row: row), let found = FLIconGrid.cell(icon) {
            let isSelected = icon == selected
            Button { pick(icon) } label: {
                Image(systemName: found.shownSymbol)
                    .font(.system(size: 12))
                    .frame(width: Self.side, height: Self.side)
                    .background(shape.fill(isSelected ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.06)))
                    .overlay(shape.strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5))
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .help(found.name)
        } else {
            // Case vide dans FL (ou pas encore relevée) : rien à choisir.
            shape.fill(Color.primary.opacity(0.02)).frame(width: Self.side, height: Self.side)
        }
    }
}

/// Réglage « Icône » : l'icône choisie (ou « Aucune ») et « Choisir… », qui ouvre la grille.
struct FLIconField: View {
    let icon: FLIcon?
    let set: (FLIcon?) -> Void
    @State private var picking = false

    var body: some View {
        HStack(spacing: 8) {
            Button { picking = true } label: { FLIconBadge(icon: icon, size: 22) }
                .buttonStyle(.plain)
                .help("Choisir dans la grille des icônes de FL")
            Text(icon.map { FLIconGrid.cell($0)?.name ?? $0.code } ?? String(localized: "Aucune"))
                .foregroundStyle(icon == nil ? Color.secondary : Color.primary)
            Spacer()
            Button("Choisir…") { picking = true }
                .controlSize(.small)
                .popover(isPresented: $picking, arrowEdge: .leading) {
                    FLIconPicker(selected: icon) { picked in
                        set(picked)
                        picking = false
                    }
                }
        }
    }
}

/// Pastille d'une icône (case pointillée : aucune icône).
struct FLIconBadge: View {
    let icon: FLIcon?
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Group {
            if let icon, let cell = FLIconGrid.cell(icon) {
                Image(systemName: cell.shownSymbol).font(.system(size: size * 0.55))
            } else {
                Image(systemName: "square.dashed").font(.system(size: size * 0.55)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .background(shape.fill(Color.primary.opacity(0.06)))
        .overlay(shape.strokeBorder(Color.primary.opacity(0.15)))
    }
}
