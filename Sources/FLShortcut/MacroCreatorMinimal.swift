// Créateur de macro de la maquette « Minimal » (20/11, vidéo du propriétaire : « fais exactement tout ce qu'on a fait
// pour la maquette ») : une seule colonne. En haut « ← Macros » et « Terminé » ; le nom en grand, souligné, et
// « Touche » ; les étapes en phrases numérotées (« 01 Choisir File › Export dans le menu »), la valeur soulignée qui
// ouvre les réglages du bloc juste sous sa ligne ; au survol « Monter », « Descendre », « Retirer ». À droite, la boîte
// « Ajouter une étape » (Clavier, FL Studio, Souris, Temps) ; en bas « Supprimer la macro », demandé dans la page.
// Les réglages de chaque bloc restent ceux de l'inspecteur (MacroInspectorView) : rien n'est perdu.
import SwiftUI
import UniformTypeIdentifiers

/// Les mots d'une étape autour de sa valeur (maquette : « Choisir [File › Save] dans le menu »).
enum StepSentence {
    struct Parts {
        let pre: String
        let post: String
        /// Ce qui s'affiche, en rouge pointillé, tant que rien n'est choisi.
        let placeholder: String
    }

    static func parts(_ type: BlockType?, verb: String) -> Parts {
        switch type {
        case .key?:
            return Parts(pre: String(localized: "Appuyer sur"), post: "", placeholder: String(localized: "une touche"))
        case .menuKey?:
            return Parts(pre: String(localized: "Appuyer dans le menu sur"), post: "", placeholder: String(localized: "une touche"))
        case .menuLetters?:
            return Parts(pre: String(localized: "Taper dans le menu"), post: "", placeholder: String(localized: "des lettres"))
        case .menuBar?, .menuAX?:
            return Parts(pre: String(localized: "Choisir"), post: String(localized: "dans le menu"),
                         placeholder: String(localized: "un élément"))
        case .trackMenu?:
            return Parts(pre: String(localized: "Choisir dans le menu de la piste"), post: "",
                         placeholder: String(localized: "un élément"))
        case .openPage?:
            return Parts(pre: String(localized: "Ouvrir"), post: "", placeholder: String(localized: "une fenêtre"))
        case .pageOption?:
            return Parts(pre: String(localized: "Cliquer sur"), post: "", placeholder: String(localized: "un bouton"))
        case .flAction?, .flActionValue?:
            return Parts(pre: "", post: "", placeholder: String(localized: "une action de FL"))
        case .dropFile?, .chooseFile?:
            return Parts(pre: String(localized: "Ouvrir le preset"), post: "", placeholder: String(localized: "un fichier"))
        case .nameColor?:
            return Parts(pre: String(localized: "Renommer la piste en"), post: "", placeholder: String(localized: "un nom"))
        case .mouseClick?:
            return Parts(pre: String(localized: "Faire un clic"), post: "", placeholder: String(localized: "gauche ou droit"))
        case .click?:
            return Parts(pre: String(localized: "Cliquer"), post: "", placeholder: String(localized: "un endroit"))
        case .drag?:
            return Parts(pre: String(localized: "Glisser"), post: "", placeholder: String(localized: "un endroit"))
        case .delay?, .waitWindow?, .waitWindowClose?, .waitUntil?:
            return Parts(pre: String(localized: "Attendre"), post: "", placeholder: String(localized: "une durée"))
        case .organize?:
            return Parts(pre: String(localized: "Organiser le projet"), post: "", placeholder: "")
        default:
            return Parts(pre: verb, post: "", placeholder: "…")
        }
    }

    /// La ligne de « Ajouter une étape » (maquette : des verbes, « Appuyer sur une touche »).
    static func addLabel(_ item: PaletteItem) -> String {
        switch item.id {
        case "key": return String(localized: "Appuyer sur une touche")
        case "menuKey": return String(localized: "Appuyer dans un menu ouvert")
        case "menuBar": return String(localized: "Choisir dans un menu de FL")
        case "openPage": return String(localized: "Ouvrir une fenêtre de FL")
        case "pageOption": return String(localized: "Cliquer sur un bouton de FL")
        case "flAction": return String(localized: "Faire une action de FL")
        case "dropFile": return String(localized: "Ouvrir un preset")
        case "nameColor": return String(localized: "Renommer la piste")
        case "organize": return String(localized: "Organiser le projet")
        case "mouseClick": return String(localized: "Faire un clic de souris")
        case "clickLearned": return String(localized: "Cliquer à un endroit appris")
        case "drag": return String(localized: "Glisser-déposer")
        case "wait": return String(localized: "Attendre")
        default: return item.label
        }
    }

    /// Ordre de la maquette : Clavier, FL Studio (menu, fenêtre, bouton, action, preset, nom), Souris, Temps.
    static let order = ["key", "menuKey", "menuBar", "openPage", "pageOption", "flAction", "dropFile", "nameColor",
                        "organize", "mouseClick", "clickLearned", "drag", "wait"]

    struct StepGroup: Identifiable {
        let title: String
        let items: [PaletteItem]
        var id: String { title }
    }

    static func groups(_ items: [PaletteItem]) -> [StepGroup] {
        let sorted = items.filter { !$0.soon }.sorted {
            (order.firstIndex(of: $0.id) ?? order.count) < (order.firstIndex(of: $1.id) ?? order.count)
        }
        let categories: [(BlockCategory, String)] = [
            (.clavier, String(localized: "Clavier")), (.fl, String(localized: "FL Studio")),
            (.souris, String(localized: "Souris")), (.fenetres, String(localized: "Temps")),
            (.controle, String(localized: "Contrôle")),
        ]
        return categories.compactMap { category, title in
            let inside = sorted.filter { $0.category == category }
            return inside.isEmpty ? nil : StepGroup(title: title, items: inside)
        }
    }
}

/// La page du créateur (maquette « Minimal »).
struct MinimalCreatorPage: View {
    @ObservedObject var model: MacroEditorModel
    @ObservedObject var monitor: MacroRunMonitor
    let paletteItems: [PaletteItem]
    let onBack: () -> Void
    /// Bloc dont les réglages sont ouverts sous sa ligne.
    @State private var openRow: String?
    @State private var confirmingDelete = false
    @State private var dropLine: StepDropLine?
    @State private var zoneTargeted = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    MinimalLink(title: "← " + String(localized: "Macros"), color: Swiss.gray) { finish() }
                    Spacer(minLength: 16)
                    MinimalButton(title: String(localized: "Terminé")) { finish() }
                        .fixedSize()
                        .keyboardShortcut("s", modifiers: .command)
                        .help("Enregistrer et revenir aux macros (⌘S)")
                }
                .padding(.top, 24)
                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 0) {
                        head
                        if let warning = triggerWarning {
                            Text(verbatim: warning).font(Swiss.font(13, .regular)).foregroundStyle(Swiss.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 8)
                        }
                        steps.padding(.top, 32)
                        if let notice = model.notice {
                            Text(verbatim: notice).font(Swiss.font(13, .regular)).foregroundStyle(Swiss.gray).padding(.top, 16)
                        }
                        deleteArea.padding(.top, 48)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    AddStepBox(items: paletteItems, recording: { model.recordClicks() }) { item in
                        withAnimation(Self.spring) { model.insert(item) }
                        if let id = model.selection { openRow = id }
                    }
                    .frame(width: 300)
                    .padding(.top, 60)
                }
            }
            .frame(maxWidth: 1088, alignment: .leading)
            .padding(.horizontal, ReadableLayout.inset)
            .padding(.top, MainWindowChrome.contentTop - 8)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .floatingBar(.bottom) {
            MacroResultBanner(model: model, monitor: monitor)
        }
        .onAppear { if let id = model.selection { openRow = id } }
    }

    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.86)

    /// « Terminé » / « ← Macros » : un raccourci posé sur une macro pas prête est dit d'abord (06/11), puis retour.
    private func finish() {
        if model.trigger != nil, let warning = model.saveWarning {
            let answer = SwissDialog.run(String(localized: "Ce raccourci ne marchera pas encore"), warning,
                                         buttons: [String(localized: "Enregistrer quand même"), String(localized: "Corriger")])
            guard answer == 0 else { return }
        }
        model.commit()
        onBack()
    }

    private var triggerWarning: String? {
        guard model.trigger != nil else { return nil }
        return model.triggerIssues.first?.message
    }

    // MARK: Nom et touche

    private var nameBinding: Binding<String> {
        let editor = model
        return Binding(get: { editor.draft?.name ?? "" }, set: { editor.rename(String($0.prefix(MacroValidation.maxNameLength))) })
    }

    private var triggerBinding: Binding<KeyCombo?> {
        let editor = model
        return Binding(get: { editor.trigger }, set: { editor.setTrigger($0) })
    }

    private var head: some View {
        HStack(alignment: .bottom, spacing: 32) {
            MinimalNameField(text: nameBinding)
                .frame(maxWidth: .infinity)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Touche").font(Swiss.font(15, .regular)).foregroundStyle(Swiss.gray)
                CaptureField(id: "macro-trigger-\(model.draft?.id.uuidString ?? "")", role: .trigger, combo: triggerBinding,
                             minimal: true)
                    .disabled(model.ephemeral)
                    .fixedSize()
            }
            .padding(.bottom, 6)
            .frame(width: 280, alignment: .leading)
        }
        .padding(.top, 16)
    }

    // MARK: Étapes

    private var steps: some View {
        let rows = model.rows
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Swiss.text).frame(height: 2)
            if rows.isEmpty {
                Text("Choisis une étape à droite.")
                    .font(Swiss.font(16, .regular)).foregroundStyle(Swiss.gray)
                    .padding(.horizontal, 12).padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onDrop(of: [.plainText], isTargeted: $zoneTargeted) { providers in
                        drop(providers, before: 0)
                        return true
                    }
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    VStack(alignment: .leading, spacing: 0) {
                        MinimalStepRow(row: row, index: index, count: rows.count,
                                       status: status(row), current: monitor.current == row.blockID && row.kind == .block,
                                       open: openRow == row.id,
                                       onValue: { toggle(row) },
                                       onUp: { move(index, by: -1) },
                                       onDown: { move(index, by: 1) },
                                       onRemove: { remove(row) })
                            .modifier(StepDragDrop(row: row, index: index, count: rows.count, width: 640, line: $dropLine,
                                                   select: { toggle(row) },
                                                   drop: { providers, before in drop(providers, before: before) }))
                            .overlay(RightClickMenu(items: { menuItems(row) }))
                        if openRow == row.id, row.kind == .block, model.selection == row.id {
                            MacroInspectorView(model: model)
                                .frame(height: 380)
                                .overlay(Rectangle().strokeBorder(Swiss.text, lineWidth: 2))
                                .padding(.vertical, 8)
                                .padding(.leading, 60)
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ row: MacroStepRow) {
        guard row.kind == .block else { return }
        if openRow == row.id {
            openRow = nil
        } else {
            model.selection = row.id
            openRow = row.id
        }
    }

    private func move(_ index: Int, by step: Int) {
        let rows = model.rows
        let target = step < 0 ? index - 1 : index + 2
        guard rows.indices.contains(index), target >= 0, target <= rows.count else { return }
        withAnimation(Self.spring) { model.move(fromOffsets: IndexSet(integer: index), toOffset: target) }
    }

    private func remove(_ row: MacroStepRow) {
        guard row.kind == .block else { return }
        if openRow == row.id { openRow = nil }
        model.selection = row.id
        withAnimation(Self.spring) { model.deleteSelection() }
    }

    private func drop(_ providers: [NSItemProvider], before: Int) {
        let items = paletteItems
        StepDrag.load(providers) { [model] payload in
            switch payload {
            case .step(let id):
                guard let from = model.rows.firstIndex(where: { $0.id == id }) else { return }
                withAnimation(Self.spring) { model.move(fromOffsets: IndexSet(integer: from), toOffset: before) }
            case .palette(let id):
                guard let item = items.first(where: { $0.id == id }) else { return }
                withAnimation(Self.spring) { model.insert(item, beforeRow: before) }
            }
        }
    }

    private func status(_ row: MacroStepRow) -> MacroRunMonitor.Status? {
        guard row.kind == .block else { return nil }
        return monitor.statuses[row.blockID]
    }

    private func menuItems(_ row: MacroStepRow) -> [RightClickMenu.Item?] {
        guard row.kind == .block else { return [] }
        let model = model
        return [
            RightClickMenu.Item(title: row.ownEnabled ? String(localized: "Désactiver") : String(localized: "Activer")) {
                model.setEnabled(row.blockID, !row.ownEnabled)
            },
            nil,
            RightClickMenu.Item(title: String(localized: "Retirer"), destructive: true) { remove(row) },
        ]
    }

    // MARK: Supprimer la macro

    @ViewBuilder private var deleteArea: some View {
        if model.ephemeral {
            EmptyView()
        } else if confirmingDelete {
            VStack(alignment: .leading, spacing: 8) {
                Text("Supprimer cette macro ?").font(Swiss.font(14, .regular)).foregroundStyle(Swiss.text)
                HStack(spacing: 16) {
                    MinimalButton(title: String(localized: "Supprimer")) {
                        confirmingDelete = false
                        model.deleteMacro()
                        onBack()
                    }
                    .fixedSize()
                    MinimalLink(title: String(localized: "Annuler")) { confirmingDelete = false }
                }
            }
        } else {
            MinimalLink(title: String(localized: "Supprimer la macro"), color: Swiss.red) { confirmingDelete = true }
        }
    }
}

/// Nom de la macro (maquette) : 32 demi-gras, souligné d'un trait gris clair, gris au survol, à l'encre pendant la
/// frappe.
private struct MinimalNameField: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    @State private var hovering = false

    var body: some View {
        TextField("", text: $text, prompt: Text("Nouvelle macro").foregroundColor(Swiss.gray))
            .textFieldStyle(.plain)
            .font(Swiss.font(32, .semibold))
            .tracking(-0.6)
            .foregroundStyle(Swiss.text)
            .focused($focused)
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) {
                Rectangle().fill(focused ? Swiss.text : hovering ? Swiss.gray : Swiss.faint).frame(height: 2)
            }
            .onHover { hovering = $0 }
            .onSubmit { focused = false }
            .accessibilityLabel(Text("Nom de la macro"))
    }
}

/// Une étape (maquette) : son numéro, sa phrase avec la valeur soulignée (▾ : elle ouvre les réglages du bloc) ; au
/// survol, le fond se teinte et « Monter », « Descendre », « Retirer » apparaissent.
private struct MinimalStepRow: View {
    let row: MacroStepRow
    let index: Int
    let count: Int
    let status: MacroRunMonitor.Status?
    let current: Bool
    let open: Bool
    let onValue: () -> Void
    let onUp: () -> Void
    let onDown: () -> Void
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        switch row.kind {
        case .block: blockRow
        case .end: endRow
        }
    }

    private var parts: StepSentence.Parts { StepSentence.parts(row.type, verb: row.verb) }
    private var value: String? {
        guard let v = row.value?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return nil }
        return v
    }

    private var blockRow: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(String(format: "%02d", index + 1))
                .font(Swiss.font(13, .regular).monospacedDigit())
                .foregroundStyle(current ? Swiss.red : Swiss.gray)
                .frame(width: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                sentence
                if let reason = failure {
                    Text(verbatim: reason).font(Swiss.font(13, .regular)).foregroundStyle(Swiss.red).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 16) {
                tool(String(localized: "Monter"), action: onUp).opacity(index > 0 ? 1 : 0).disabled(index == 0)
                tool(String(localized: "Descendre"), action: onDown).opacity(index < count - 1 ? 1 : 0).disabled(index >= count - 1)
                tool(String(localized: "Retirer"), red: true, action: onRemove)
            }
            .opacity(hovering || open ? 1 : 0)
        }
        .padding(.leading, CGFloat(row.depth) * 24)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .opacity(row.enabled ? 1 : 0.45)
        .background(Rectangle().fill(hovering || open ? Swiss.text.opacity(0.06) : Color.clear))
        .overlay(alignment: .bottom) { Rectangle().fill(Swiss.faint).frame(height: 1) }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }

    private var sentence: some View {
        FlowRow(spacing: 8, lineSpacing: 4) {
            if !parts.pre.isEmpty {
                Text(verbatim: parts.pre).font(Swiss.font(17, .regular)).foregroundStyle(Swiss.text)
            }
            if value != nil || !parts.placeholder.isEmpty {
                Button(action: onValue) {
                    HStack(spacing: 4) {
                        Text(verbatim: value ?? parts.placeholder)
                            .font(Swiss.font(17, value == nil ? .regular : .semibold))
                            .lineLimit(1)
                        Text(verbatim: "▾").font(Swiss.font(13, .regular))
                    }
                    .foregroundStyle(value == nil ? Swiss.red : Swiss.text)
                    .padding(.bottom, 2)
                    .overlay(alignment: .bottom) {
                        if value == nil {
                            DottedLine().stroke(Swiss.red, style: StrokeStyle(lineWidth: 2, dash: [2, 3])).frame(height: 2)
                        } else {
                            Rectangle().fill(Swiss.text).frame(height: 2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Réglages de cette étape")
            }
            if !parts.post.isEmpty {
                Text(verbatim: parts.post).font(Swiss.font(17, .regular)).foregroundStyle(Swiss.text)
            }
            if !row.ownEnabled {
                Text("désactivée").font(Swiss.font(13, .regular)).foregroundStyle(Swiss.gray)
            }
        }
    }

    private var failure: String? {
        if case .failed(let reason)? = status { return reason }
        if case .warned(let reason)? = status { return reason }
        return nil
    }

    private func tool(_ title: String, red: Bool = false, action: @escaping () -> Void) -> some View {
        StepTool(title: title, red: red, action: action)
    }

    private var endRow: some View {
        Text(verbatim: row.verb)
            .font(Swiss.font(13, .regular))
            .foregroundStyle(Swiss.gray)
            .padding(.leading, CGFloat(row.depth) * 24 + 60)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Swiss.faint).frame(height: 1) }
    }
}

/// « Monter », « Descendre », « Retirer » : gris, soulignés à l'encre au survol (« Retirer » en rouge).
private struct StepTool: View {
    let title: String
    let red: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(Swiss.font(13, .regular))
                .foregroundStyle(hovering ? (red ? Swiss.red : Swiss.text) : Swiss.gray)
                .underline(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Trait pointillé (valeur pas encore choisie, « Choisir »).
struct DottedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

/// « Ajouter une étape » (maquette) : une boîte bordée d'encre, les blocs par catégorie ; un clic ajoute le bloc sous
/// l'étape choisie, on peut aussi le glisser à sa place. En tête, « Enregistrer clics et touches » (⇧⌘R).
private struct AddStepBox: View {
    let items: [PaletteItem]
    let recording: () -> Void
    let add: (PaletteItem) -> Void
    @ObservedObject private var recorder = ClickSequenceRecorder.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ajouter une étape").swissLabel()
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            AddStepLine(title: recorder.active ? String(localized: "Enregistrement en cours…")
                                               : String(localized: "Enregistrer clics et touches"),
                        red: true, action: recording)
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(recorder.active)
            ForEach(StepSentence.groups(items)) { group in
                Text(verbatim: group.title)
                    .font(Swiss.font(12, .regular)).foregroundStyle(Swiss.gray)
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 2)
                ForEach(group.items) { item in
                    AddStepLine(title: StepSentence.addLabel(item), action: { add(item) })
                        .onDrag { PaletteDrag.provider(item) }
                        .help(item.aide)
                }
            }
            Color.clear.frame(height: 8)
        }
        .overlay(Rectangle().strokeBorder(Swiss.text, lineWidth: 2))
    }
}

/// Une ligne de la boîte : pleine d'encre au survol, texte de la couleur du fond.
private struct AddStepLine: View {
    let title: String
    var red = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(Swiss.font(16, .regular))
                .foregroundStyle(hovering ? Swiss.background : red ? Swiss.red : Swiss.text)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Rectangle().fill(hovering ? Swiss.text : Color.clear))
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
