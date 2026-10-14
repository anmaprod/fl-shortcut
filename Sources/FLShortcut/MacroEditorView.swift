// Créateur de macros : fenêtre à part (AppKit, MacroCreatorWindowController : créée à la demande, libérée à la
// fermeture avec sa vue et son modèle).
// - À gauche, la palette (barre latérale en verre du système) ; au centre, la liste à plat des étapes avec retrait
//   selon l'imbrication (une phrase en français par ligne, valeurs en pastilles, icône colorée de la catégorie, case
//   « actif », badges) ; à droite, l'inspecteur du bloc choisi.
// - Barre d'outils : macros de la bibliothèque, ▶ Tester (⌘R), Exporter, Enregistrer (⌘S, sinon 0,5 s après la
//   dernière modification). Raccourci dans l'en-tête, avec les avertissements de conflit habituels.
// - Essai : chaque ligne montre son état (bleu en cours, coche verte faite, rouge échouée avec la raison) ; un
//   bandeau flottant donne le résultat (« Échec au bloc 4 (…) : … » et « Montrer le bloc »). Échap arrête.
// Performance : lignes Equatable sans objet observé par ligne, aucun verre par ligne, aucune animation au repos ;
// seules les lignes dont l'état change pendant un essai sont redessinées.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Demande d'ouverture du créateur (fenêtre unique) : quelle macro montrer. Puis
/// `MacroCreatorWindowController.shared.show()`.
final class MacroCreatorLink: ObservableObject {
    static let shared = MacroCreatorLink()

    struct Request: Equatable {
        let serial: Int
        let id: UUID?
        /// Macro d'exemple jamais enregistrée (mesure de l'interface).
        let sample: Bool
    }

    @Published private(set) var request: Request?
    private var serial = 0

    private init() {}

    func open(_ id: UUID?) {
        serial += 1
        request = Request(serial: serial, id: id, sample: false)
    }

    func openSample() {
        serial += 1
        request = Request(serial: serial, id: nil, sample: true)
    }

    /// Fermeture demandée (mesure de l'interface).
    func requestClose() { MacroCreatorWindowController.shared.close() }
}

/// Bandeau du créateur quand la bibliothèque ne peut pas être enregistrée : le brouillon n'est pas gardé.
private struct LibraryProblemBanner: View {
    @ObservedObject var library: MacroLibraryStore

    var body: some View {
        if library.problem != nil {
            MacroLibraryProblemLabel(library: library)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
            Divider()
        }
    }
}

struct MacroCreatorView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var link = MacroCreatorLink.shared
    /// Possédé par MacroCreatorWindowController (libéré avec la fenêtre).
    @ObservedObject var model: MacroEditorModel
    @Environment(\.undoManager) private var undoManager
    @AppStorage(Appearance.glassKey) private var glassEnabled = true
    @State private var paletteItems: [PaletteItem] = []

    var body: some View {
        NavigationSplitView {
            MacroPaletteView(items: paletteItems, insert: { [model] item in
                withAnimation(MacroStepsPane.spring) { model.insert(item) }
            })
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            VStack(spacing: 0) {
                if #available(macOS 14.0, *) {
                    EmptyView()
                } else {
                    legacyBar
                }
                LibraryProblemBanner(library: store.library)
                HStack(spacing: 0) {
                    MacroStepsPane(model: model, monitor: model.monitor, paletteItems: paletteItems)
                        .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    MacroInspectorView(model: model)
                        .frame(width: 300)
                }
            }
        }
        .navigationTitle(model.draft?.name ?? "Créateur de macros")
        .toolbar { toolbarContent }
        .windowGlass(glassEnabled)
        .onAppear {
            model.undoManager = undoManager
            if paletteItems.isEmpty { paletteItems = PaletteCatalog.items(layout: store.layout) }
            handle(link.request)
        }
        .onChange(of: link.request) { request in handle(request) }
    }

    private func handle(_ request: MacroCreatorLink.Request?) {
        guard let request else {
            if model.draft == nil { model.load(nil) }
            return
        }
        // onAppear puis onChange peuvent livrer la même demande : la rejouer rechargerait le brouillon.
        guard model.handledRequestSerial != request.serial else { return }
        model.handledRequestSerial = request.serial
        if request.sample {
            let doc = MacroTemplates.sampleForCapture(layout: store.layout)
            model.loadSample(doc)
            // Capture : essai en cours sur l'exemple (couleurs des lignes), bloc 4 choisi (inspecteur).
            let ids = doc.blocks.map(\.id)
            if ids.count > 7 {
                model.monitor.showSample(done: Array(ids[1...6]), running: ids[7])
                model.selection = MacroStepRow.blockRowID(ids[3])
            }
        } else {
            model.load(request.id)
        }
    }

    // MARK: Barre d'outils

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) { switcher }
        ToolbarItem(placement: .primaryAction) { TestButton(model: model, monitor: model.monitor) }
        ToolbarItem(placement: .primaryAction) { exportButton }
        ToolbarItem(placement: .primaryAction) { saveButton }
    }

    /// macOS 13 : NSHostingController n'y relaie pas la barre d'outils SwiftUI (sceneBridgingOptions : macOS 14) ;
    /// mêmes commandes dans une barre en tête.
    private var legacyBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                switcher
                Spacer(minLength: 8)
                TestButton(model: model, monitor: model.monitor)
                exportButton
                saveButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
        }
    }

    private var switcher: some View {
        MacroSwitcher(library: store.library, current: model.draft?.id) { id in
            model.load(id)
        } onNew: {
            model.newMacro()
        }
    }

    private var exportButton: some View {
        Button {
            exportDraft()
        } label: {
            Label("Exporter…", systemImage: "square.and.arrow.up")
        }
        .disabled(model.draft == nil || model.ephemeral)
        .help("Enregistre la macro dans un fichier .flsmacro à partager (positions apprises retirées)")
    }

    private var saveButton: some View {
        Button {
            model.saveNow()
        } label: {
            Label(model.dirty ? "Enregistrer" : "Enregistrée",
                  systemImage: model.dirty ? "square.and.arrow.down" : "checkmark.circle")
        }
        .keyboardShortcut("s", modifiers: .command)
        .disabled(!model.dirty)
        .help(model.dirty ? "Enregistrer maintenant (⌘S) : sinon c'est fait tout seul dans un instant"
                          : "Tout est enregistré")
    }

    private func exportDraft() {
        model.saveNow()
        guard let doc = model.draft else { return }
        if let message = MacroFileActions.export(doc) { model.notice = message }
    }
}

/// ▶ Tester : observe seul le suivi de l'essai (le reste de la fenêtre n'est pas redessiné à chaque bloc).
private struct TestButton: View {
    @ObservedObject var model: MacroEditorModel
    @ObservedObject var monitor: MacroRunMonitor

    var body: some View {
        Button {
            model.test()
        } label: {
            Label("Tester", systemImage: "play.fill")
        }
        .keyboardShortcut("r", modifiers: .command)
        .disabled(model.draft == nil || monitor.running || model.preparingTest)
        .help("FL passe devant et la macro tourne comme avec son raccourci (⌘R). Échap l'arrête.")
    }
}

// MARK: - Liste des étapes

private struct MacroStepsPane: View {
    @ObservedObject var model: MacroEditorModel
    @ObservedObject var monitor: MacroRunMonitor
    let paletteItems: [PaletteItem]

    var body: some View {
        Group {
            if model.draft != nil {
                VStack(spacing: 0) {
                    MacroHeader(model: model)
                    Divider()
                    list
                    Divider()
                    actionBar
                }
            } else {
                VStack(spacing: 10) {
                    SectionIcon(symbol: "wand.and.stars", tint: .purple, size: 44)
                    Text("Aucune macro ouverte").font(.title3.weight(.semibold))
                    Text("Crée une macro, ou ouvre-en une depuis la fenêtre Raccourcis › Macros.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Nouvelle macro") { model.newMacro() }
                        .primaryButton()
                        .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .floatingBar(.bottom) {
            MacroResultBanner(model: model, monitor: monitor)
        }
    }

    /// Ressort court et sans rebond visible, façon Apple : les lignes s'écartent pour le bloc ajouté, glissent quand
    /// on les range, se resserrent quand on en supprime. Seulement au moment du changement : rien ne tourne au repos.
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.86)

    private var list: some View {
        List(selection: $model.selection) {
            ForEach(model.rows) { row in
                MacroStepRowView(row: row, status: status(row), current: monitor.current == row.blockID && row.kind == .block,
                                 onToggle: { on in model.setEnabled(row.blockID, on) })
                    .equatable()
                    .tag(row.id)
                    .moveDisabled(row.kind != .block)          // les lignes de fin suivent leur boucle
                    .contextMenu { contextMenu(row) }
            }
            .onMove { offsets, to in
                withAnimation(Self.spring) { model.move(fromOffsets: offsets, toOffset: to) }
            }
            // Bloc glissé depuis la palette : lâché entre deux lignes, il prend cette place (3e, 4e…).
            .onInsert(of: [.plainText]) { index, providers in
                dropFromPalette(providers, beforeRow: index)
            }
        }
        .listStyle(.inset)
        .glassListBackground()
        .onDeleteCommand { withAnimation(Self.spring) { model.deleteSelection() } }
        .overlay {
            if model.rows.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.down.right")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("Aucun bloc pour l'instant").font(.headline)
                    Text("Glisse un bloc de la palette ici, clique-le, ou tape son nom dans « Ajouter un bloc… » puis ↩.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onDrop(of: [.plainText], isTargeted: nil) { providers in
                    dropFromPalette(providers, beforeRow: 0)
                    return true
                }
            }
        }
    }

    private func dropFromPalette(_ providers: [NSItemProvider], beforeRow row: Int) {
        let items = paletteItems
        PaletteDrag.load(providers) { [model] id in
            guard let item = items.first(where: { $0.id == id }) else { return }
            withAnimation(Self.spring) { model.insert(item, beforeRow: row) }
        }
    }

    private func status(_ row: MacroStepRow) -> MacroRunMonitor.Status? {
        guard row.kind == .block else { return nil }
        return monitor.statuses[row.blockID]
    }

    @ViewBuilder private func contextMenu(_ row: MacroStepRow) -> some View {
        if row.kind == .block {
            Button(row.ownEnabled ? "Désactiver" : "Activer") { model.setEnabled(row.blockID, !row.ownEnabled) }
            Button("Dupliquer") {
                model.selection = row.id
                withAnimation(Self.spring) { model.duplicateSelection() }
            }
            Divider()
            Button("Supprimer", role: .destructive) {
                model.selection = row.id
                withAnimation(Self.spring) { model.deleteSelection() }
            }
        }
    }

    /// Sous la liste : ajouter (sous la sélection), dupliquer (⌘D), supprimer (⌫), avec l'aide du moment.
    private var actionBar: some View {
        HStack(spacing: 10) {
            AddBlockMenu(items: paletteItems, insert: { [model] item in withAnimation(Self.spring) { model.insert(item) } })
            RecordClicksButton(model: model)
            Button {
                withAnimation(Self.spring) { model.duplicateSelection() }
            } label: {
                Label("Dupliquer", systemImage: "plus.square.on.square")
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(model.selectedBlock == nil)
            .help("Dupliquer le bloc choisi (⌘D)")
            Button {
                withAnimation(Self.spring) { model.deleteSelection() }
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
            .disabled(model.selectedBlock == nil)
            .help("Supprimer le bloc choisi (⌫)")
            Spacer(minLength: 8)
            Text("Glisse les lignes pour les ranger")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .frame(height: 34)
    }
}

/// « Enregistrer des clics » : FL passe devant, chaque clic devient un bloc (panneau « Terminer » en haut à droite).
/// Observe seul l'enregistreur : le reste de la barre n'est pas redessiné.
private struct RecordClicksButton: View {
    let model: MacroEditorModel
    @ObservedObject private var recorder = ClickSequenceRecorder.shared

    var body: some View {
        Button {
            model.recordClicks()
        } label: {
            Label(recorder.active ? "Enregistrement…" : "Enregistrer des clics",
                  systemImage: recorder.active ? "record.circle.fill" : "record.circle")
        }
        .disabled(recorder.active)
        .help("FL passe devant : clique dans l'ordre (menus, Options › Audio, boutons de ses fenêtres…), puis « Terminer ». Chaque clic devient un bloc.")
    }
}

/// « + Ajouter » : les blocs de la palette, par catégorie, ajoutés sous la ligne choisie.
private struct AddBlockMenu: View {
    /// Mêmes blocs que la palette (calculés une fois par le créateur), sans modèle observé.
    let items: [PaletteItem]
    let insert: (PaletteItem) -> Void

    var body: some View {
        Menu {
            ForEach(BlockCategory.allCases, id: \.self) { category in
                Section(category.rawValue) {
                    ForEach(items.filter { $0.category == category && !$0.soon }) { item in
                        Button(item.label) { insert(item) }
                    }
                }
            }
        } label: {
            Label("Ajouter", systemImage: "plus")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Ajouter un bloc sous la ligne choisie (ou dans la boucle si sa ligne de fin est choisie)")
    }
}

/// Une ligne : case « actif », numéro, icône de la catégorie, phrase avec sa valeur en pastille, badges, état.
private struct MacroStepRowView: View, Equatable {
    let row: MacroStepRow
    let status: MacroRunMonitor.Status?
    let current: Bool
    let onToggle: (Bool) -> Void

    static func == (a: MacroStepRowView, b: MacroStepRowView) -> Bool {
        a.row == b.row && a.status == b.status && a.current == b.current
    }

    private var indent: CGFloat { CGFloat(row.depth) * 22 }

    var body: some View {
        switch row.kind {
        case .block: blockRow
        case .end: endRow
        }
    }

    private var tint: Color { row.category?.tint ?? .gray }

    private var blockRow: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(get: { row.ownEnabled }, set: onToggle))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(row.ownEnabled ? "Bloc actif : décoche pour le sauter sans le supprimer" : "Bloc sauté : coche pour le réactiver")
            Text(row.number)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 24, alignment: .trailing)
            SectionIcon(symbol: row.symbol, tint: tint, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                sentence
                if let note = row.note {
                    Text(note).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                if let reason = failure {
                    Text(reason).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            ForEach(row.badges, id: \.self) { badge in
                BadgeCapsule(badge: badge)
            }
            stateIcon
        }
        .padding(.leading, indent)
        .padding(.vertical, 3)
        .opacity(row.enabled ? 1 : 0.45)
        .background(stateBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var sentence: some View {
        if row.type == .comment {
            Text(row.verb).italic().foregroundStyle(.secondary).lineLimit(2)
        } else {
            HStack(spacing: 6) {
                Text(row.verb).lineLimit(1)
                if let value = row.value {
                    Text(value)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(tint.opacity(0.15)))
                }
            }
        }
    }

    private var failure: String? {
        if case .failed(let reason)? = status { return reason }
        if case .warned(let reason)? = status { return reason }
        return nil
    }

    @ViewBuilder private var stateIcon: some View {
        if current {
            Image(systemName: "play.circle.fill").foregroundStyle(.blue).help("En cours")
        } else {
            switch status {
            case .done?:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Fait")
            case .warned?:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange).help("Fait, avec un avertissement")
            case .failed?:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red).help("Échec")
            case .cancelled?:
                Image(systemName: "stop.circle.fill").foregroundStyle(.orange).help("Arrêté")
            case .running?:
                Image(systemName: "play.circle.fill").foregroundStyle(.blue).help("En cours")
            case nil:
                EmptyView()
            }
        }
    }

    @ViewBuilder private var stateBackground: some View {
        if current {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.blue.opacity(0.13))
        } else if case .failed? = status {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.red.opacity(0.10))
        }
    }

    private var endRow: some View {
        HStack(spacing: 6) {
            Image(systemName: row.symbol).foregroundStyle(.secondary)
            Text(row.verb).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .padding(.leading, indent + 62)
        .padding(.vertical, 1)
        .opacity(row.enabled ? 1 : 0.45)
        .help("Choisis cette ligne pour ajouter des blocs à la fin de la liste, ou glisses-en une ici")
    }

    private var accessibilityText: String {
        var parts = ["Bloc \(row.number)", row.verb]
        if let value = row.value { parts.append(value) }
        if !row.ownEnabled { parts.append("désactivé") }
        parts += row.badges.map(\.title)
        if current { parts.append("en cours") }
        if let failure { parts.append("échec : " + failure) }
        return parts.joined(separator: ", ")
    }
}

/// Badge d'une ligne : petite capsule colorée, l'explication en bulle d'aide.
private struct BadgeCapsule: View {
    let badge: MacroBadge

    var body: some View {
        Label(badge.title, systemImage: badge.symbol)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(badge.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(badge.tint.opacity(0.13)))
            .help(badge.help)
    }
}

// MARK: - En-tête : nom, état, raccourci

private struct MacroHeader: View {
    @ObservedObject var model: MacroEditorModel

    private var nameBinding: Binding<String> {
        let editor = model
        return Binding(get: { editor.draft?.name ?? "" }, set: { editor.rename($0) })
    }

    private var triggerBinding: Binding<KeyCombo?> {
        let editor = model
        return Binding(get: { editor.trigger }, set: { editor.setTrigger($0) })
    }

    /// Nom et état sur toute la largeur, raccourci sur sa propre ligne : la colonne des étapes est étroite (400 pt
    /// au moins), un champ à côté du nom le coupait et repliait l'état sur quatre lignes.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                SectionIcon(symbol: "wand.and.stars", tint: .purple, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Nom de la macro", text: nameBinding)
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                        .accessibilityLabel("Nom de la macro")
                    statusLine
                }
            }
            HStack(spacing: 10) {
                Text("Raccourci").font(.system(size: 12)).foregroundStyle(.secondary)
                CaptureField(id: "macro-trigger-\(model.draft?.id.uuidString ?? "")", role: .trigger, combo: triggerBinding)
                    .disabled(model.ephemeral)               // exemple de la mesure : jamais enregistré
                    .frame(width: 230)
                Spacer(minLength: 0)
            }
            if !model.triggerIssues.isEmpty {
                IssuesView(issues: model.triggerIssues)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusLine: some View {
        let count = MacroValidation.count(model.draft?.blocks ?? [])
        let blocks = count == 1 ? "1 bloc" : "\(count) blocs"
        let duration = model.estimateMs > 0 ? " · \(MacroOutline.seconds(max(100, model.estimateMs / 100 * 100))) au plus" : ""
        return HStack(spacing: 6) {
            if let problem = model.problem {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(problem)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Prête · \(blocks)\(duration)").lineLimit(1)
            }
            if model.needs.contains(.lienMIDI) {
                Label("Lien FL", systemImage: "link")
                    .fixedSize()
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.blue)
                    .help("Des actions de FL passent par le lien avec FL quand il est installé (sinon leur touche de secours).")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
}

// MARK: - Bandeau du résultat de l'essai

private struct MacroResultBanner: View {
    @ObservedObject var model: MacroEditorModel
    @ObservedObject var monitor: MacroRunMonitor

    var body: some View {
        Group {
            if model.preparingTest {
                banner(symbol: "arrow.up.forward.app", tint: .blue, text: "FL Studio passe devant…")
            } else if monitor.running {
                banner(symbol: "play.circle.fill", tint: .blue, text: "Essai en cours dans FL… Échap pour l'arrêter.")
            } else if let outcome = monitor.outcome {
                outcomeBanner(outcome)
            } else if let notice = model.notice {
                banner(symbol: "info.circle.fill", tint: nil, text: notice, close: { model.notice = nil })
            } else if let refusal = monitor.refusal {
                banner(symbol: "exclamationmark.triangle.fill", tint: .orange, text: "Essai non lancé : \(refusal)",
                       close: { monitor.clear() })
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    @ViewBuilder private func outcomeBanner(_ outcome: MacroOutcome) -> some View {
        switch outcome {
        case .done, .stopped:
            banner(symbol: "checkmark.circle.fill", tint: .green, text: model.outcomeText(outcome), close: { monitor.clear() })
        case .doneWithWarning:
            banner(symbol: "exclamationmark.circle.fill", tint: .orange, text: model.outcomeText(outcome), close: { monitor.clear() })
        case .cancelled:
            banner(symbol: "stop.circle.fill", tint: .orange, text: model.outcomeText(outcome), close: { monitor.clear() })
        case .failed, .failedInBlock:
            let editor = model
            let show: (String, () -> Void)? = monitor.failedBlock == nil ? nil : ("Montrer le bloc", { editor.showFailedBlock() })
            banner(symbol: "xmark.octagon.fill", tint: .red, text: model.outcomeText(outcome), action: show,
                   close: { monitor.clear() })
        }
    }

    private func banner(symbol: String, tint: Color?, text: String, action: (String, () -> Void)? = nil,
                        close: (() -> Void)? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint ?? .secondary)
            Text(text)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let action {
                Button(action.0, action: action.1).controlSize(.small).onGlassButton()
            }
            if let close {
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Fermer")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassSurface(RoundedRectangle(cornerRadius: 16, style: .continuous), tint: tint)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Choix de la macro

/// Menu de la barre d'outils : les macros de la bibliothèque, et « Nouvelle macro ».
private struct MacroSwitcher: View {
    @ObservedObject var library: MacroLibraryStore
    let current: UUID?
    let onSelect: (UUID) -> Void
    let onNew: () -> Void

    var body: some View {
        Menu {
            ForEach(library.macros) { doc in
                Button {
                    onSelect(doc.id)
                } label: {
                    if doc.id == current {
                        Label(doc.name.displaySafe(max: 50), systemImage: "checkmark")
                    } else {
                        Text(doc.name.displaySafe(max: 50))
                    }
                }
            }
            if !library.macros.isEmpty { Divider() }
            Button {
                onNew()
            } label: {
                Label("Nouvelle macro", systemImage: "plus")
            }
        } label: {
            Label("Macros", systemImage: "list.bullet")
        }
        .help("Ouvrir une autre macro de la bibliothèque")
    }
}
