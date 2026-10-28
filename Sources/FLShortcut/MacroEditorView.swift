// Créateur de macros : affiché DANS la fenêtre principale (comme un dossier dans le Finder), flèche ← en haut à gauche
// pour revenir aux raccourcis (EditorView, CreatorPresence) ; vue et modèle libérés au retour.
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

/// Demande d'ouverture du créateur : quelle macro montrer. La fenêtre principale (EditorView) l'affiche alors en son
/// sein ; déjà affiché, le créateur passe à cette macro.
final class MacroCreatorLink: ObservableObject {
    static let shared = MacroCreatorLink()

    struct Request: Equatable {
        let serial: Int
        let id: UUID?
        /// Macro d'exemple jamais enregistrée (mesure de l'interface).
        let sample: Bool
        /// Macro créée à l'instant (nouvelle, modèle) : au retour, l'enregistrer ou la supprimer.
        var isNew = false
        /// « Enregistrer une macro » : l'enregistrement des clics et des touches démarre dès l'ouverture.
        var record = false
    }

    @Published private(set) var request: Request?
    /// Retour aux raccourcis demandé sans question (mesure de l'interface).
    @Published private(set) var closeSerial = 0
    /// Dernière macro quittée par ← : la flèche → des raccourcis y ramène, comme dans le Finder.
    @Published var lastClosedID: UUID?
    private var serial = 0

    private init() {}

    func open(_ id: UUID?, isNew: Bool = false, record: Bool = false) {
        serial += 1
        request = Request(serial: serial, id: id, sample: false, isNew: isNew, record: record)
    }

    func openSample() {
        serial += 1
        request = Request(serial: serial, id: nil, sample: true)
    }

    /// Fermeture demandée (mesure de l'interface).
    func requestClose() { closeSerial += 1 }
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
    /// Possédé par la fenêtre principale tant que le créateur y est affiché (libéré au retour).
    @ObservedObject var model: MacroEditorModel
    /// Flèche ← : retour aux raccourcis (avec la question « Enregistrer ou supprimer » si besoin).
    let onBack: () -> Void
    @Environment(\.undoManager) private var undoManager
    @AppStorage(Appearance.glassKey) private var glassEnabled = true

    var body: some View {
        NavigationSplitView {
            MacroPaletteView(items: model.paletteItems, insert: { [model] item in
                withAnimation(MacroStepsPane.spring) { model.insert(item) }
            })
                .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 300)
        } detail: {
            // Colonnes souples : quand la fenêtre se resserre, la liste puis l'inspecteur rétrécissent (jamais rien
            // de coupé ; la fenêtre ne descend pas sous 820 points, et 190 + 280 + 240 y tiennent).
            VStack(spacing: 0) {
                LibraryProblemBanner(library: store.library)
                HStack(spacing: 0) {
                    MacroStepsPane(model: model, monitor: model.monitor, paletteItems: model.paletteItems)
                        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    MacroInspectorView(model: model)
                        .frame(minWidth: 240, idealWidth: 300, maxWidth: 300)
                }
            }
        }
        // Titre de la fenêtre (menu Fenêtre, VoiceOver) ; pas dans la barre d'outils : le nom est déjà au centre.
        .navigationTitle(model.draft?.name ?? String(localized: "Créateur de macros"))
        .toolbarTitleHidden()
        .toolbar { toolbarContent }
        // Plus de fondu de couleur dans le fond (28/10 : « garder que le Liquid Glass, pas de fond »).
        .windowGlass(glassEnabled)
        // Fenêtre qui l'affiche : retour du focus après « Montrer dans FL… », et devant FL tant qu'il est affiché.
        .background(WindowReader { [model] window in
            model.window = window
            CreatorPresence.attach(window)
        })
        .onAppear {
            model.undoManager = undoManager
            model.handle(link.request)                  // déjà fait avant l'ouverture : sans effet
        }
        .onChange(of: link.request) { request in model.handle(request) }
    }

    // MARK: Barre d'outils

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        // Comme dans le Finder : on est entré dans la macro, ← ramène aux raccourcis et aux macros.
        ToolbarItem(placement: .navigation) { FinderArrows(back: onBack, forward: nil) }
        ToolbarItem(placement: .primaryAction) { exportButton }
        ToolbarItem(placement: .primaryAction) { saveButton }
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
            Label(model.dirty ? String(localized: "Enregistrer") : String(localized: "Enregistrée"),
                  systemImage: model.dirty ? "square.and.arrow.down" : "checkmark.circle")
        }
        .keyboardShortcut("s", modifiers: .command)
        .disabled(!model.dirty)
        .help(model.dirty ? String(localized: "Enregistrer maintenant (⌘S) : sinon c'est fait tout seul dans un instant")
                          : String(localized: "Tout est enregistré"))
    }

    private func exportDraft() {
        model.saveNow()
        guard let doc = model.draft else { return }
        if let message = MacroFileActions.export(doc) { model.notice = message }
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
                                 selected: model.selection == row.id,
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
                // Le plus simple d'abord : enregistrer ce qu'on fait dans FL ; les blocs de la palette ensuite.
                VStack(spacing: 10) {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text("Enregistre ce que tu fais dans FL").font(.title3.weight(.semibold))
                    Text(String(localized: "Clique, utilise les flèches, tes raccourcis… : chaque geste devient un bloc, que tu peux ")
                         + String(localized: "ensuite modifier, ranger ou supprimer."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                        .fixedSize(horizontal: false, vertical: true)
                    RecordStartButton(model: model)
                    Text("ou glisse des blocs de la palette, à gauche")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .padding(20)
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
            Button(row.ownEnabled ? String(localized: "Désactiver") : String(localized: "Activer")) {
                model.setEnabled(row.blockID, !row.ownEnabled)
            }
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
        // Fenêtre étroite : d'abord sans l'astuce, puis les icônes seules (leur bulle d'aide reste) ; jamais un
        // libellé coupé sur deux lignes.
        ViewThatFits(in: .horizontal) {
            actionButtons(hint: true)
            actionButtons(hint: false)
            actionButtons(hint: false).labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .frame(height: 34)
    }

    private func actionButtons(hint: Bool) -> some View {
        HStack(spacing: 10) {
            AddBlockMenu(items: paletteItems, insert: { [model] item in withAnimation(Self.spring) { model.insert(item) } })
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
            if hint {
                Text("Glisse les lignes pour les ranger")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
    }
}

/// « Enregistrer clics et touches », le cœur des macros : FL passe devant, chaque clic, flèche ou raccourci devient
/// un bloc (panneau « Terminer » en haut à droite). En grand dans l'en-tête du créateur (⇧⌘R) ; seul l'enregistreur
/// est observé : le reste de l'en-tête n'est pas redessiné.
private struct RecordHero: View {
    let model: MacroEditorModel
    @ObservedObject private var recorder = ClickSequenceRecorder.shared

    var body: some View {
        Button {
            model.recordClicks()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: recorder.active ? "record.circle.fill" : "record.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 1) {
                    Text(recorder.active ? String(localized: "Enregistrement en cours…")
                                         : String(localized: "Enregistrer clics et touches"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(recorder.active ? String(localized: "Clique et tape dans FL, puis « Terminer » en haut à droite.")
                         : String(localized: "Fais ta suite dans FL : chaque clic, flèche ou raccourci devient un bloc."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text("⇧⌘R").font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.red.opacity(0.09)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.red.opacity(0.3)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuHover(tint: .red)
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(recorder.active)
        .help("FL passe devant : clique et tape dans l'ordre (menus, Options › Audio, boutons de ses fenêtres, flèches, raccourcis…), puis « Terminer ». Chaque clic et chaque touche devient un bloc, ajouté sous la ligne choisie.")
        .accessibilityLabel("Enregistrer clics et touches")
    }
}

/// Grand bouton rouge de la macro vide : « Commencer l'enregistrement ».
private struct RecordStartButton: View {
    let model: MacroEditorModel
    @ObservedObject private var recorder = ClickSequenceRecorder.shared

    var body: some View {
        Button {
            model.recordClicks()
        } label: {
            Label(recorder.active ? String(localized: "Enregistrement en cours…") : String(localized: "Commencer l'enregistrement"),
                  systemImage: "record.circle")
                .frame(minWidth: 220)
        }
        .primaryButton()
        .tint(.red)
        .controlSize(.large)
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .disabled(recorder.active)
        .help("FL passe devant : clique et tape dans l'ordre, puis « Terminer » en haut à droite (⇧⌘R).")
    }
}

/// « + Ajouter » : les blocs de la palette, par catégorie, ajoutés sous la ligne choisie.
private struct AddBlockMenu: View {
    /// Mêmes blocs que la palette (calculés une fois par le créateur), sans modèle observé.
    let items: [PaletteItem]
    let insert: (PaletteItem) -> Void

    var body: some View {
        // Au style du menu de l'icône : chaque bloc avec son icône et la couleur de sa catégorie.
        StyledMenuButton(help: String(localized: "Ajouter un bloc sous la ligne choisie (ou dans la boucle si sa ligne de fin est choisie)"),
                         arrowEdge: .top, width: 280) {
            BlockCategory.allCases.flatMap { category -> [StyledMenuEntry] in
                let inCategory = items.filter { $0.category == category && !$0.soon }
                guard !inCategory.isEmpty else { return [] }
                return [StyledMenuEntry.header(category.label)] + inCategory.map { item -> StyledMenuEntry in
                    .item(item.label, symbol: item.symbol, tint: category.tint, help: item.aide) { insert(item) }
                }
            }
        } label: {
            Label("Ajouter", systemImage: "plus")
        }
        .fixedSize()
    }
}

/// Une ligne : case « actif », numéro, icône de la catégorie, phrase avec sa valeur en pastille, badges, état.
private struct MacroStepRowView: View, Equatable {
    let row: MacroStepRow
    let status: MacroRunMonitor.Status?
    let current: Bool
    /// Bloc choisi : il ne s'allume pas au survol (le fond de la sélection, plus grand, dépassait du contour).
    let selected: Bool
    let onToggle: (Bool) -> Void

    static func == (a: MacroStepRowView, b: MacroStepRowView) -> Bool {
        a.row == b.row && a.status == b.status && a.current == b.current && a.selected == b.selected
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
                .help(row.ownEnabled ? String(localized: "Bloc actif : décoche pour le sauter sans le supprimer")
                                     : String(localized: "Bloc sauté : coche pour le réactiver"))
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
        .menuHover(tint: tint, cornerRadius: 8, enabled: !selected)
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
        var parts = [String(localized: "Bloc \(row.number)"), row.verb]
        if let value = row.value { parts.append(value) }
        if !row.ownEnabled { parts.append(String(localized: "désactivé")) }
        parts += row.badges.map(\.title)
        if current { parts.append(String(localized: "en cours")) }
        if let failure { parts.append(String(localized: "échec : ") + failure) }
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
            // Fenêtre au plus étroit : le champ rétrécit, le mot « Raccourci » reste sur une ligne (le champ de largeur
            // fixe l'écrasait en une lettre par ligne).
            HStack(spacing: 10) {
                Text("Raccourci").font(.system(size: 12)).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                CaptureField(id: "macro-trigger-\(model.draft?.id.uuidString ?? "")", role: .trigger, combo: triggerBinding)
                    .disabled(model.ephemeral)               // exemple de la mesure : jamais enregistré
                    .frame(minWidth: 120, maxWidth: 230)
                Spacer(minLength: 0)
            }
            if !model.triggerIssues.isEmpty {
                IssuesView(issues: model.triggerIssues)
            }
            if !model.rows.isEmpty {
                RecordHero(model: model)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusLine: some View {
        let count = MacroValidation.count(model.draft?.blocks ?? [])
        let blocks = count == 1 ? String(localized: "1 bloc") : String(localized: "\(count) blocs")
        let duration = model.estimateMs > 0
            ? String(localized: " · \(MacroOutline.seconds(max(100, model.estimateMs / 100 * 100))) au plus") : ""
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
                banner(symbol: "arrow.up.forward.app", tint: .blue, text: String(localized: "FL Studio passe devant…"))
            } else if monitor.running {
                banner(symbol: "play.circle.fill", tint: .blue, text: String(localized: "Essai en cours dans FL… Échap pour l'arrêter."))
            } else if let outcome = monitor.outcome {
                outcomeBanner(outcome)
            } else if let notice = model.notice {
                banner(symbol: "info.circle.fill", tint: nil, text: notice, close: { model.notice = nil })
            } else if let refusal = monitor.refusal {
                banner(symbol: "exclamationmark.triangle.fill", tint: .orange, text: String(localized: "Essai non lancé : \(refusal)"),
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
            let text = model.outcomeText(outcome)
            let show: (String, () -> Void)? = monitor.failedBlock == nil ? nil
                : (String(localized: "Montrer le bloc"), { editor.showFailedBlock() })
            // « Signaler » : la page Aide, le formulaire prêt avec ce message d'erreur et le journal de l'essai.
            banner(symbol: "xmark.octagon.fill", tint: .red, text: text, action: show,
                   report: { HelpLink.shared.report("Macro « \(editor.draft?.name ?? "?") » : \(text)") },
                   close: { monitor.clear() })
        }
    }

    private func banner(symbol: String, tint: Color?, text: String, action: (String, () -> Void)? = nil,
                        report: (() -> Void)? = nil, close: (() -> Void)? = nil) -> some View {
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
            if let report {
                Button("Signaler", action: report)
                    .controlSize(.small)
                    .onGlassButton()
                    .help("Écrire à l'équipe : le message d'erreur et le journal de cet essai sont joints, tu les vois avant l'envoi")
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

/// ← → comme dans le Finder : ← revient aux raccourcis depuis une macro (⌘[), → rentre dans la dernière macro
/// quittée (⌘]). Une flèche sans destination reste grisée.
struct FinderArrows: View {
    let back: (() -> Void)?
    let forward: (() -> Void)?

    var body: some View {
        ControlGroup {
            Button {
                back?()
            } label: {
                Label("Retour", systemImage: "chevron.backward")
            }
            .disabled(back == nil)
            .keyboardShortcut("[", modifiers: .command)
            .help("Revenir aux raccourcis et aux macros (⌘[)")
            Button {
                forward?()
            } label: {
                Label("Avancer", systemImage: "chevron.forward")
            }
            .disabled(forward == nil)
            .keyboardShortcut("]", modifiers: .command)
            .help(forward == nil ? String(localized: "Rien où retourner pour l'instant")
                                 : String(localized: "Revenir dans la dernière macro quittée (⌘])"))
        }
    }
}

extension View {
    /// Titre de la fenêtre gardé (menu Fenêtre, VoiceOver), retiré de la barre d'outils (macOS 15 et plus récent).
    @ViewBuilder func toolbarTitleHidden(_ hidden: Bool = true) -> some View {
        if #available(macOS 15.0, *) {
            toolbar(removing: hidden ? .title : nil)
        } else {
            self
        }
    }
}
