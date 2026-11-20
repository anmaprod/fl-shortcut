// Pages de la maquette « Minimal » (20/11, « fais exactement tout ce qu'on a fait pour la maquette ») :
// docs/maquettes/fl-shortcuts-minimal.html. Raccourcis : groupe en capitales sur un trait d'encre, lignes nom | touche |
// Remettre, la ligne survolée pleine d'encre, un clic = « Appuie sur une touche » dans la ligne ; Trouver : la grande
// case de 200 points, la touche en très grand, ce qu'elle fait à droite, le changement dans la page (Nouvelle touche,
// C'est changé.). La touche se change sans fiche à part (KeyChange : mêmes règles que la fiche d'avant).
import AppKit
import SwiftUI

// MARK: - Changer une touche

/// Changer la touche d'un raccourci de FL depuis la page (ligne ou « Trouver ») : mêmes règles que la fiche d'avant
/// (touche refusée, une touche ne fait qu'une seule chose : petite page avant → après, « Changer aussi dans … ? »).
enum KeyChange {
    enum Outcome {
        /// Changée : l'ancienne et la nouvelle touche, et les raccourcis d'avant pour « Annuler le changement ».
        case done(old: KeyCombo?, new: KeyCombo?, before: [Remap])
        case cancelled
        case refused(String)
    }

    static func apply(_ row: CatalogRow, to combo: KeyCombo?, store: Store) -> Outcome {
        let before = store.remaps
        let old = row.current
        if combo == old { return .cancelled }
        var native: KeyCombo?
        var isAction = false
        switch row.entry.kind {
        case .native(let c): native = c
        case .action: isAction = true
        default: break
        }
        if combo == nil && !isAction { return .refused(String(localized: "Ce raccourci de FL garde une touche.")) }
        if let combo {
            guard combo.isValidTrigger else { return .refused(String(localized: "Cette touche ne peut pas servir de raccourci.")) }
            if combo != native {
                let issues = store.draftIssues(store.draft(for: row, trigger: combo)).filter {
                    if case .noTrigger = $0 { return false }
                    if case .noTarget = $0 { return false }
                    return true
                }
                if let blocking = issues.first(where: \.isBlocking) { return .refused(blocking.message) }
            }
        }
        let clashes = combo.map { store.clashes(for: $0, editing: row) } ?? []
        if !clashes.isEmpty {
            var lines = [KeyChangeLine.text(row.entry.title, row.entry.section.title, from: old, to: combo)]
            lines += KeyChangeLine.grouped(clashes).map { KeyChangeLine.text($0.title, $0.places, from: combo, to: old) }
            let swapping = old != nil
            let answer = SwissDialog.run(swapping ? String(localized: "Échanger les touches ?") : String(localized: "Remplacer la touche ?"),
                                         "", buttons: [swapping ? String(localized: "Échanger") : String(localized: "Remplacer"),
                                                       String(localized: "Annuler")], list: lines)
            guard answer == 0 else { return .cancelled }
            _ = store.swap(clashes, to: old)
        }
        store.setTrigger(combo, for: row)
        // « Changer aussi dans Piano Roll ? » (19/11) : la même action des autres pages.
        let twins = store.twins(of: row, old: old, new: combo)
        if !twins.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                let place = twins.count == 1 ? twins[0].entry.section.title : String(localized: "les autres pages")
                let lines = twins.map { KeyChangeLine.text($0.entry.title, $0.entry.section.title, from: old, to: combo) }
                let answer = SwissDialog.run(String(localized: "Changer aussi dans \(place) ?"), "",
                                             buttons: [String(localized: "Changer aussi"), String(localized: "Seulement ici")],
                                             list: lines)
                if answer == 0 { for twin in twins { store.setTrigger(combo, for: twin) } }
            }
        }
        return .done(old: old, new: combo, before: before)
    }
}

/// « C'est changé. » de « Trouver » : ce qui a changé, et les raccourcis d'avant pour « Annuler le changement ».
struct FindDone {
    let section: String
    let title: String
    let old: KeyCombo?
    let new: KeyCombo?
    let before: [Remap]
}

// MARK: - Lignes de « Raccourcis »

/// Nom d'un groupe (« PROJET ») : petites capitales sur un trait d'encre de 2 points, comme la maquette.
struct MinimalGroupHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(Swiss.font(12, .semibold)).tracking(0.96)
            .foregroundStyle(Swiss.text)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Swiss.text).frame(height: 2) }
            .padding(.top, 32)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Une ligne : le nom (la page dessous dans « Mes raccourcis »), la touche en texte (rouge si changée), puis
/// « Remettre » ; survolée ou en écoute, pleine d'encre. En écoute : « Appuie sur une touche » en rouge et « Annuler ».
struct MinimalKeyRow: View {
    let title: String
    var page: String? = nil
    let key: String?
    var changed = false
    var dimmed = false
    var capturing = false
    var error: String? = nil
    let onTap: () -> Void
    var trailingTitle: String? = nil
    var onTrailing: (() -> Void)? = nil
    var onCancel: (() -> Void)? = nil
    @State private var hovering = false

    private var on: Bool { hovering || capturing }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Swiss.font(16, .regular))
                        .foregroundStyle(on ? Swiss.background : (dimmed ? Swiss.gray : Swiss.text))
                        .lineLimit(2)
                    if let page {
                        Text(page).font(Swiss.font(13, .regular)).foregroundStyle(Swiss.faintText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                keyCell.frame(width: 160, alignment: .leading)
                trailing.frame(width: 96, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(Rectangle().fill(on ? Swiss.text : Color.clear))
            .overlay(alignment: .bottom) { Rectangle().fill(on ? Swiss.text : Swiss.line).frame(height: 1) }
            .contentShape(Rectangle())
            .onTapGesture { if !capturing { onTap() } }
            .onHover { hovering = $0 }
            if let error {
                Text(error)
                    .font(Swiss.font(13, .regular))
                    .foregroundStyle(Swiss.red)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Changer la touche de \(title)"))
    }

    @ViewBuilder private var keyCell: some View {
        if capturing {
            HStack(spacing: 8) {
                Rectangle().fill(Swiss.red).frame(width: 2, height: 18)
                Text("Appuie sur une touche").font(Swiss.font(15, .regular)).foregroundStyle(Swiss.red)
            }
        } else {
            Text(verbatim: key ?? "—")
                .font(Swiss.font(20, .semibold))
                .foregroundStyle(key == nil ? (on ? Swiss.background.opacity(0.6) : Swiss.gray)
                                 : changed ? Swiss.red : (on ? Swiss.background : Swiss.text))
                .lineLimit(1)
        }
    }

    @ViewBuilder private var trailing: some View {
        if capturing, let onCancel {
            linkButton(String(localized: "Annuler"), action: onCancel)
        } else if let trailingTitle, let onTrailing {
            linkButton(trailingTitle, action: onTrailing)
        }
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Swiss.font(13, .regular)).underline()
                .foregroundStyle(on ? Swiss.background : Swiss.gray)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Trouver

/// La grande case de « Trouver » (maquette) : 200 points de haut, un trait d'encre de 2 points dessous ; son contenu
/// posé en bas.
struct MinimalBigField<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .bottom, spacing: 24) { content; Spacer(minLength: 0) }
            .frame(height: 200, alignment: .bottomLeading)
            .padding(.bottom, 16)
            .overlay(alignment: .bottom) { Rectangle().fill(Swiss.text).frame(height: 2) }
    }
}

/// « Appuie sur une touche » / « Nouvelle touche » : la barre rouge qui attend, puis le mot en très grand gris.
struct MinimalWaitingKey: View {
    let placeholder: String

    var body: some View {
        HStack(alignment: .bottom, spacing: 24) {
            Rectangle().fill(Swiss.red).frame(width: 20, height: 168)
            Text(placeholder)
                .font(Swiss.font(48, .regular))
                .tracking(-0.5)
                .foregroundStyle(Swiss.faintText)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.bottom, 2)
        }
    }
}

/// La touche en très grand (taille d'après sa longueur, comme la maquette).
struct MinimalKeyImage: View {
    let text: String
    var red = false

    var body: some View {
        let n = text.count
        let size: CGFloat = n <= 3 ? 200 : n <= 5 ? 150 : n <= 8 ? 96 : 64
        Text(verbatim: text)
            .font(Swiss.font(size, .semibold))
            .tracking(-size * 0.05)
            .foregroundStyle(red ? Swiss.red : Swiss.text)
            .lineLimit(1)
            .minimumScaleFactor(0.3)
    }
}

/// Une ligne de résultat (maquette) : « Playlist · ⌘S » en gris et « Changer » à droite, puis le nom en 24.
struct MinimalResultRow: View {
    let section: String
    let key: String?
    let title: String
    var changed = false
    let change: () -> Void
    var reset: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 4) {
                    Text(section).foregroundStyle(Swiss.gray)
                    if let key {
                        Text(verbatim: "·").foregroundStyle(Swiss.gray)
                        Text(verbatim: key).fontWeight(.semibold).foregroundStyle(changed ? Swiss.red : Swiss.text)
                    }
                }
                .font(Swiss.font(13, .regular))
                Spacer(minLength: 8)
                HStack(spacing: 16) {
                    Button(action: change) { Text("Changer").underline() }
                    if let reset { Button(action: reset) { Text("Remettre").underline() } }
                }
                .buttonStyle(.plain)
                .font(Swiss.font(13, .regular))
                .foregroundStyle(Swiss.gray)
            }
            Button(action: change) {
                Text(title).font(Swiss.font(24, .regular)).foregroundStyle(Swiss.text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 32)
    }
}

/// Bouton plein d'encre de la maquette (« Chercher un autre raccourci ») et bouton bordé (« Aucune touche »).
struct MinimalButton: View {
    let title: String
    var outlined = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Swiss.font(14, .semibold))
                .foregroundStyle(outlined ? Swiss.text : Swiss.background)
                .padding(.horizontal, 20)
                .frame(height: 44)
                .background(Rectangle().fill(outlined ? Color.clear : (hovering ? Swiss.red : Swiss.text)))
                .overlay(Rectangle().strokeBorder(Swiss.text, lineWidth: outlined ? 2 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Lien souligné de la maquette (« Annuler », « Annuler le changement »).
struct MinimalLink: View {
    let title: String
    var color: Color = Swiss.text
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(Swiss.font(13, .regular)).underline().foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }
}

extension Swiss {
    /// Gris pâle de la maquette (« --faint », #A8A59E en Papier) : texte d'attente, page sous un nom.
    static var faintText: Color { Swiss.gray.opacity(0.65) }
}

// MARK: - Macros

/// Interrupteur de la maquette : un rectangle plein d'encre et son carré clair à droite (Active), ou bordé et son carré
/// d'encre à gauche (Éteinte), puis le mot.
struct MinimalSwitch: View {
    let isOn: Bool
    var inverted = false
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Rectangle().fill(isOn ? ink : Color.clear)
                        .overlay(Rectangle().strokeBorder(ink, lineWidth: 2))
                        .frame(width: 40, height: 22)
                    Rectangle().fill(isOn ? paper : ink).frame(width: 12, height: 12).padding(.horizontal, 5)
                }
                Text(isOn ? String(localized: "Active") : String(localized: "Éteinte"))
                    .font(Swiss.font(14, .regular)).foregroundStyle(ink)
                    .frame(width: 52, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    private var ink: Color { inverted ? Swiss.background : Swiss.text }
    private var paper: Color { inverted ? Swiss.text : Swiss.background }
}

/// Une macro (maquette) : son nom en demi-gras et ses étapes en une ligne grise, sa touche, l'interrupteur et
/// « Supprimer » ; survolée, pleine d'encre ; un clic l'ouvre. « Supprimer » demande dans la ligne même.
struct MinimalMacroRow: View {
    let name: String
    let summary: String
    var alert: String? = nil
    let key: String?
    let active: Bool?
    var confirming = false
    let onOpen: () -> Void
    let onKey: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void
    let onConfirmDelete: () -> Void
    let onCancelDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(Swiss.font(16, .semibold)).foregroundStyle(fg).lineLimit(1)
                    HStack(spacing: 6) {
                        if let alert { Text(alert).foregroundStyle(Swiss.red) }
                        Text(summary).foregroundStyle(hovering ? Swiss.background.opacity(0.7) : Swiss.gray).lineLimit(1)
                    }
                    .font(Swiss.font(13, .regular))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onKey) {
                    Text(verbatim: key ?? "—")
                        .font(Swiss.font(20, .semibold))
                        .foregroundStyle(key == nil ? (hovering ? Swiss.background.opacity(0.6) : Swiss.gray) : fg)
                        .frame(width: 120, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Changer la touche"))
                HStack(spacing: 24) {
                    if let active {
                        MinimalSwitch(isOn: active, inverted: hovering, toggle: onToggle)
                    } else {
                        Color.clear.frame(width: 102, height: 22)
                    }
                    Button(action: onDelete) {
                        Text("Supprimer").font(Swiss.font(13, .regular)).underline()
                            .foregroundStyle(hovering ? Swiss.background : Swiss.gray)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 58)
            .background(Rectangle().fill(hovering ? Swiss.text : Color.clear))
            .overlay(alignment: .bottom) { Rectangle().fill(hovering ? Swiss.text : Swiss.line).frame(height: 1) }
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .onHover { hovering = $0 }
            if confirming {
                HStack(spacing: 16) {
                    Text("Supprimer « \(name) » ?").font(Swiss.font(14, .regular)).foregroundStyle(Swiss.text)
                    MinimalButton(title: String(localized: "Supprimer"), action: onConfirmDelete)
                    MinimalLink(title: String(localized: "Annuler"), action: onCancelDelete)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(Swiss.line).frame(height: 1) }
            }
        }
    }

    private var fg: Color { hovering ? Swiss.background : Swiss.text }
}

// MARK: - Compte

/// Champ de la maquette : son nom en gris au-dessus, la case bordée d'encre (2 points), 48 de haut.
struct MinimalField: View {
    let title: String
    @Binding var text: String
    var secure = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Swiss.font(13, .regular)).foregroundStyle(Swiss.gray)
            Group {
                if secure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(Swiss.font(16, .regular))
            .padding(.horizontal, 12)
            .frame(height: 48)
            .overlay(Rectangle().strokeBorder(Swiss.text, lineWidth: 2))
            .accessibilityLabel(title)
        }
        .padding(.top, 24)
    }
}
