// Fenêtre « Raccourcis », sur le modèle de Xcode › Key Bindings et de Réglages Système › Clavier : barre
// latérale standard (une rubrique par fenêtre de FL, puis « Mes raccourcis »), liste native à droite, une ligne
// par raccourci avec sa touche (cliquable) et « Réinitialiser ». Recherche, profil et pause dans la barre
// d'outils ; statut discret en bas ; une seule ligne d'avertissement en haut quand il faut agir.
// Performance : listes paresseuses (NSTableView), aucun survol animé, aucune animation infinie, aucun flou.
// Audit : REL-06 / PROTOCOL.md §5 (statut du lien), audit 04 §8.2 (actions grisées, « Disponible à partir de
//         FL X »), audit 05 §4.2-4.4 (conflits, touche seule confirmée, pause visible, noms de touches en clair,
//         VoiceOver), REL-19 (un seul enregistreur, ⌫ efface, Échap annule, ⌃⌥⌘F refusé, délai 5 s, arrêt à la
//         perte du focus, tap suspendu), REL-20 (avertissements issus de l'analyse de l'index), REL-21
//         (remplacement de profil confirmé et annulable), SEC-05 (cibles interdites refusées, import validé).
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Fenêtre principale

/// Élément de la barre latérale.
enum SidebarItem: Hashable {
    case section(FLSection)
    case custom
}

typealias CatalogData = (rows: [CatalogRow], others: [Remap])

struct EditorView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var status: AppStatus
    private var link: MIDILink { MIDILink.shared }

    @State private var selection: SidebarItem? = .section(.general)
    @State private var query = ""
    @State private var editing: Remap? = nil
    @State private var editingIsNew = false
    @State private var toast: ToastMessage? = nil
    @State private var editingRow: CatalogRow? = nil
    /// Annonce affichée en tête de la fiche quand on doit choisir une nouvelle touche pour un autre raccourci.
    @State private var editNotice: String? = nil
    @AppStorage(Appearance.glassKey) private var glassEnabled = true

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        let data = store.catalogRows()
        NavigationSplitView {
            sidebar(data)
                .navigationSplitViewColumnWidth(min: 220, ideal: 245, max: 300)
        } detail: {
            detail(data)
        }
        .navigationTitle(title)
        .searchable(text: $query, placement: .toolbar, prompt: "Rechercher")
        .toolbar { toolbarContent }
        // Un clic dans le vide de la barre latérale ne laisse jamais la fenêtre sans section.
        .onChange(of: selection) { newValue in
            if newValue == nil { selection = .section(.general) }
        }
        .onReceive(DebugSnapshot.publisher(DebugSnapshot.select)) { note in
            let name = note.object as? String ?? ""
            selection = FLSection(rawValue: name).map(SidebarItem.section) ?? (name == "custom" ? .custom : selection)
        }
        .sheet(item: $editing) { remap in
            EditSheet(original: remap, isNew: editingIsNew) { message in show(message) }
                .environmentObject(store)
                .environmentObject(status)
                .environmentObject(link)
        }
    }

    private var title: String {
        if !trimmedQuery.isEmpty { return "Recherche" }
        switch selection ?? .section(.general) {
        case .section(let s): return s.title
        case .custom: return "Mes raccourcis"
        }
    }

    // MARK: Barre latérale

    private func sidebar(_ data: CatalogData) -> some View {
        var modified: [FLSection: Int] = [:]
        for row in data.rows where !row.isDefault { modified[row.entry.section, default: 0] += 1 }
        return List(selection: $selection) {
            Section {
                // Sélection par étiquette (.tag) : un NavigationLink sans destination ne sélectionne rien sur
                // macOS 26+ (clic capté, section inchangée).
                ForEach(FLSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .badge(modified[section] ?? 0)
                        .help(section.subtitle)
                        .tag(SidebarItem.section(section))
                }
            } header: {
                Text("FL Studio")
            }
            Section {
                Label("Mes raccourcis", systemImage: "star")
                    .badge(data.others.count)
                    .tag(SidebarItem.custom)
            } header: {
                Text("Personnalisés")
            }
        }
    }

    // MARK: Détail

    private func detail(_ data: CatalogData) -> some View {
        Group {
            if !trimmedQuery.isEmpty {
                searchResults(data)
            } else {
                switch selection ?? .section(.general) {
                case .section(let s): sectionList(s, rows: data.rows)
                case .custom: customList(data.others)
                }
            }
        }
        .id(trimmedQuery.isEmpty ? selection : nil)          // nouvelle liste (et retour en haut) à chaque section
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Façon macOS 26 : la liste défile SOUS des éléments en verre qui flottent (avertissements en haut,
        // notification et statut en bas). Peu de surfaces, regroupées : le système les dessine ensemble.
        .safeAreaInset(edge: .top, spacing: 0) {
            NoticeStack(items: notices)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GlassGroup(spacing: 8) {
                VStack(spacing: 8) {
                    if let toast {
                        ToastView(message: toast) { self.toast = nil }
                            .transition(Motion.rise)
                            .id(toast.id)                   // une nouvelle notification remplace l'ancienne
                    }
                    StatusBar(store: store, status: status, link: link, fl: FLMonitor.shared)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            .motion(Motion.smooth, value: toast)
        }
        .sheet(item: $editingRow) { row in
            CatalogEditSheet(row: row, notice: editNotice) { message, followUp in
                show(message)
                // La touche a été reprise à un autre raccourci : on propose aussitôt de lui en choisir une autre.
                if let followUp {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        guard let next = store.catalogRows().rows.first(where: { $0.id == followUp }) else { return }
                        editNotice = "« \(row.entry.title) » utilise maintenant cette touche. "
                            + "Choisis une nouvelle touche pour « \(next.entry.title) »."
                        editingRow = next
                    }
                }
            }
            .environmentObject(store)
            .environmentObject(link)
        }
    }

    /// Une section : raccourcis d'origine de FL, puis actions en plus.
    private func sectionList(_ section: FLSection, rows: [CatalogRow]) -> some View {
        let mine = rows.filter { $0.entry.section == section }
        let natives = mine.filter { $0.entry.isNative }
        let extras = mine.filter { !$0.entry.isNative }
        return List {
            if !natives.isEmpty {
                Section {
                    ForEach(natives) { catalogRow($0) }
                } header: {
                    Text("Raccourcis de FL Studio")
                }
            }
            if !extras.isEmpty {
                Section {
                    ForEach(extras) { catalogRow($0) }
                } header: {
                    Text("Actions en plus")
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .id(section)                                     // nouvelle section : la liste repart du haut
    }

    /// Recherche : toutes les sections, regroupées par section.
    private func searchResults(_ data: CatalogData) -> some View {
        let q = trimmedQuery
        let rows = data.rows.filter { row in
            [row.entry.title, row.entry.detail, row.current?.display ?? "", row.entry.section.title]
                .joined(separator: " ").localizedCaseInsensitiveContains(q)
        }
        let others = data.others.filter { r in
            [r.title, r.subtitle, r.trigger?.display ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(q)
        }
        let sections = FLSection.allCases.filter { s in rows.contains { $0.entry.section == s } }
        return Group {
            if rows.isEmpty && others.isEmpty {
                EmptyState(title: "Aucun résultat", text: "Aucun raccourci ne correspond à « \(q) ».")
            } else {
                List {
                    ForEach(sections) { s in
                        Section {
                            ForEach(rows.filter { $0.entry.section == s }) { catalogRow($0) }
                        } header: {
                            Text(s.title)
                        }
                    }
                    if !others.isEmpty {
                        Section {
                            ForEach(others) { customRow($0) }
                        } header: {
                            Text("Mes raccourcis")
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    /// Raccourcis du profil hors catalogue (créés ou importés).
    private func customList(_ others: [Remap]) -> some View {
        Group {
            if others.isEmpty {
                EmptyState(title: "Aucun raccourci personnalisé",
                           text: "Un raccourci personnalisé lance une action ou envoie une touche de FL Studio.",
                           actionTitle: "Nouveau raccourci…",
                           action: { newCustom() })
            } else {
                List {
                    Section {
                        ForEach(others) { customRow($0) }
                    }
                    Button {
                        newCustom()
                    } label: {
                        Label("Nouveau raccourci…", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private func catalogRow(_ row: CatalogRow) -> some View {
        CatalogRowView(row: row,
                       issues: row.remap.map { store.issues(for: $0.id) } ?? [],
                       onEdit: { editNotice = nil; editingRow = row },
                       onReset: { reset(row) })
    }

    private func customRow(_ remap: Remap) -> some View {
        ShortcutRow(remap: remap, issues: store.issues(for: remap.id),
                    onOpen: { editingIsNew = false; editing = remap },
                    onToggle: {
                        var copy = remap
                        copy.enabled.toggle()
                        store.upsert(copy)
                    },
                    onDelete: { delete(remap) })
    }

    // MARK: Avertissements (seulement quand il faut agir)

    private var notices: [NoticeItem] {
        var out: [NoticeItem] = []
        if !status.accessibilityOK {
            out.append(NoticeItem(id: "ax", symbol: "exclamationmark.triangle.fill", tint: .orange,
                                  text: "FL Shortcut n'a pas accès au clavier : tes raccourcis sont inactifs.",
                                  button: "Autoriser…", action: { AccessibilityGuide.start() }))
        } else if status.staleTCC {
            out.append(NoticeItem(id: "stale", symbol: "exclamationmark.triangle.fill", tint: .orange,
                                  text: "Autorisation périmée : retire FL Shortcut de la liste Accessibilité, puis ajoute-le.",
                                  button: "Ouvrir…", action: { AccessibilityGuide.start() }))
        }
        if status.secureInput {
            out.append(NoticeItem(id: "secure", symbol: "lock.fill", tint: .orange,
                                  text: "Saisie sécurisée active dans une autre app : macOS ne transmet plus les touches."))
        }
        if !AppMode.light, status.scriptState == .modified {
            out.append(NoticeItem(id: "script", symbol: "exclamationmark.shield.fill", tint: .red,
                                  text: "Le script FL a été modifié depuis son installation.",
                                  button: "Réinstaller", action: { FLScriptInstaller.installWithAlert() }))
        }
        if let error = store.saveError {
            out.append(NoticeItem(id: "save", symbol: "xmark.octagon.fill", tint: .red, text: error))
        }
        if let warning = store.loadWarning {
            let model = store
            out.append(NoticeItem(id: "load", symbol: "info.circle.fill", tint: .secondary, text: warning,
                                  button: "OK", action: { model.loadWarning = nil }))
        }
        return out
    }

    // MARK: Barre d'outils

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: pausedBinding) {
                Label("Pause", systemImage: "pause.circle")
            }
            .help(store.enabled ? "Mettre en pause (⌃⌥⌘F)" : "Reprendre (⌃⌥⌘F)")
        }
        ToolbarItem(placement: .primaryAction) {
            profileMenu
        }
    }

    private var pausedBinding: Binding<Bool> {
        let model = store
        return Binding(get: { !model.enabled }, set: { model.enabled = !$0 })
    }

    private var profileMenu: some View {
        Menu {
            Menu("Charger un profil") {
                ForEach(ProfilePreset.allCases) { preset in
                    Button(preset.label) { load(preset) }
                }
            }
            Button("Importer…") { importProfile() }
            Button("Exporter…") { exportProfile() }
            Divider()
            Button("Nouveau raccourci personnalisé…") { newCustom() }
            Divider()
            if store.undoSnapshot != nil {
                Button("Annuler le dernier remplacement") { store.undoReplace() }
            }
            Button("Tout réinitialiser…") { resetAll() }
            if Appearance.glassAvailable {
                Divider()
                Toggle("Effet Liquid Glass", isOn: $glassEnabled)
            }
            Divider()
            Button("Désinstaller FL Shortcut…") { Uninstaller.confirmAndRun() }
        } label: {
            Label("Profil", systemImage: "ellipsis.circle")
        }
        .help("Profil, import et export")
    }

    // MARK: Actions

    private func newCustom() {
        editingIsNew = true
        editing = Remap().with { $0.actionID = nil }
    }

    private func load(_ preset: ProfilePreset) {
        guard Dialogs.confirm("Charger le profil « \(preset.label) » ?",
                              preset.summary + "\n\nTes raccourcis actuels seront remplacés (annulable).")
        else { return }
        store.apply(preset: preset)
        show(ToastMessage(text: "Profil « \(preset.label) » chargé", undo: { store.undoReplace() }))
    }

    private func reset(_ row: CatalogRow) {
        let before = store.remaps
        store.reset(row)
        show(ToastMessage(text: "« \(row.entry.title) » réinitialisé", undo: { store.remaps = before }))
    }

    private func resetAll() {
        guard Dialogs.confirm("Tout réinitialiser ?",
                              "Tous les raccourcis reviennent à leur touche d'origine (profil Recommandé). C'est annulable.")
        else { return }
        store.resetAll()
        show(ToastMessage(text: "Tous les raccourcis sont réinitialisés", undo: { store.undoReplace() }))
    }

    private func delete(_ remap: Remap) {
        store.delete(remap.id)
        show(ToastMessage(text: "Raccourci supprimé", undo: { store.upsert(remap) }))
    }

    private func show(_ message: ToastMessage) {
        toast = message
        let id = message.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            if toast?.id == id { toast = nil }
        }
    }

    private func show(_ text: String) { show(ToastMessage(text: text, undo: nil)) }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            guard size <= ProfileImporter.maxBytes else { throw ProfileImporter.Failure.tooLarge }
            let preview = try store.prepareImport(try Data(contentsOf: url))
            var text = preview.summary.joined(separator: "\n")
            if !preview.rejected.isEmpty { text += "\n\nRefusé(s) par sécurité :\n• " + preview.rejected.joined(separator: "\n• ") }
            text += "\n\nTes raccourcis actuels seront remplacés (annulable)."
            guard Dialogs.confirm("Importer ce profil ?", text) else { return }
            store.applyImport(preview)
            show(ToastMessage(text: "Profil importé", undo: { store.undoReplace() }))
        } catch {
            Dialogs.inform("Import impossible", error.localizedDescription)
        }
    }

    private func exportProfile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "FL Shortcut – profil.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData().write(to: url, options: .atomic)
            show("Profil exporté")
        } catch {
            Dialogs.inform("Export impossible", error.localizedDescription)
        }
    }
}

// MARK: - Avertissements en tête du détail

private struct NoticeItem: Identifiable {
    let id: String
    let symbol: String
    let tint: Color
    let text: String
    var button: String? = nil
    var action: (() -> Void)? = nil
}

/// Lignes compactes sous la barre d'outils, séparées par un filet (vide la plupart du temps).
private struct NoticeStack: View {
    let items: [NoticeItem]

    var body: some View {
        if !items.isEmpty {
            GlassGroup(spacing: 6) {
                VStack(spacing: 6) {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.symbol).foregroundStyle(item.tint)
                            Text(item.text).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            if let title = item.button, let action = item.action {
                                Button(title, action: action).controlSize(.small).secondaryButton()
                            }
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .glassSurface(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        }
    }
}

// MARK: - Statut (barre du bas, comme celle du Finder)

private struct StatusBar: View {
    @ObservedObject var store: Store
    @ObservedObject var status: AppStatus
    @ObservedObject var link: MIDILink
    @ObservedObject var fl: FLMonitor

    /// Pastille de verre flottante en bas à gauche (comme les barres flottantes de macOS 26).
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(text).foregroundStyle(.secondary).lineLimit(1)
                if let action {
                    Button(action.label, action: action.run)
                        .buttonStyle(.link)
                }
            }
            .font(.system(size: 11.5))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .glassSurface(Capsule())
            .accessibilityElement(children: .contain)
            Spacer(minLength: 0)
        }
    }

    private var color: Color {
        if !store.enabled { return .gray }
        if !status.accessibilityOK { return .orange }
        if AppMode.light { return fl.running ? .green : .gray }
        switch link.status {
        case .linked: return .green
        case .inactive: return .orange
        case .flClosed: return .gray
        }
    }

    static func format(_ ms: Double) -> String {
        ms < 10 ? String(format: "%.1f ms", ms).replacingOccurrences(of: ".", with: ",") : "\(Int(ms.rounded())) ms"
    }

    private var text: String {
        if !store.enabled { return "En pause : FL Studio utilise ses raccourcis d'origine" }
        if !status.accessibilityOK { return "Clavier non autorisé" }
        let version = fl.version.map { " \($0)" } ?? ""
        if AppMode.light {
            return fl.running ? "Actif dans FL Studio" + version : "FL Studio n'est pas ouvert"
        }
        switch link.status {
        case .linked:
            if let ms = link.snapshot.responseMs { return "Relié à FL Studio\(version), réponse en \(Self.format(ms))" }
            return "Relié à FL Studio" + version
        case .flClosed: return "FL Studio n'est pas ouvert"
        case .inactive:
            if !link.snapshot.hasKey { return "Lien avec FL Studio non installé" }
            if link.snapshot.incompatibleProtocol != nil { return "Script FL d'une autre version" }
            return "Lien inactif : active « FL Shortcut » dans Options › MIDI Settings"
        }
    }

    /// L'autorisation du clavier a son bouton dans l'avertissement en haut : pas de doublon ici.
    private var action: (label: String, run: () -> Void)? {
        let model = store
        let midi = link
        guard model.enabled else { return ("Reprendre", { model.enabled = true }) }
        guard status.accessibilityOK, !AppMode.light, midi.status == .inactive else { return nil }
        if !midi.snapshot.hasKey || midi.snapshot.incompatibleProtocol != nil {
            return ("Installer…", { FLScriptInstaller.installWithAlert() })
        }
        return ("Tester", { midi.testLink() })
    }
}

// MARK: - Lignes

/// Symbole d'avertissement d'une ligne (bulle d'aide : le détail).
private struct IssueIcon: View {
    let issues: [ShortcutIssue]

    var body: some View {
        let blocking = issues.contains(where: \.isBlocking)
        let text = issues.map(\.message).joined(separator: "\n")
        Image(systemName: blocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
            .font(.system(size: 12))
            .foregroundStyle(blocking ? Color.red : Color.orange)
            .help(text)
            .accessibilityLabel("Attention : " + text)
    }
}

/// « Réinitialiser » : présent sur chaque ligne, grisé quand la touche est déjà celle d'origine.
private struct ResetButton: View {
    let enabled: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Réinitialiser", systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .disabled(!enabled)
        .help(help)
    }
}

/// Une ligne du catalogue : ce que fait le raccourci, sa touche (cliquable), et « Réinitialiser ».
private struct CatalogRowView: View {
    let row: CatalogRow
    let issues: [ShortcutIssue]
    let onEdit: () -> Void
    let onReset: () -> Void

    /// Légende seulement quand la touche a changé.
    private var caption: String? {
        guard !row.isDefault else { return nil }
        return "D'origine : " + (row.entry.defaultTrigger?.display ?? "aucune")
    }

    private var titleHelp: String {
        row.entry.isNative ? "Raccourci d'origine de FL Studio" : row.entry.detail
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.entry.title).lineLimit(1)
                if let caption {
                    Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .help(titleHelp)
            Spacer(minLength: 12)
            if let takenBy = row.takenBy {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .help("Touche aussi utilisée par « \(takenBy) ». Clique sur la touche pour en choisir une autre.")
                    .accessibilityLabel("Touche utilisée par \(takenBy)")
            }
            if !issues.isEmpty {
                IssueIcon(issues: issues)
            }
            Button(action: onEdit) {
                KeyLabel(combo: row.current, accent: !row.isDefault)
            }
            .buttonStyle(.plain)
            .help("Changer la touche")
            .accessibilityLabel("Changer la touche de \(row.entry.title)")
            .accessibilityValue(row.current?.spoken ?? "aucune")

            ResetButton(enabled: !row.isDefault,
                        help: "Revenir à : " + (row.entry.defaultTrigger?.display ?? "aucune touche"),
                        action: onReset)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Changer la touche…", action: onEdit)
            Button("Réinitialiser", action: onReset).disabled(row.isDefault)
        }
    }
}

/// Un raccourci personnalisé : titre, touche (ouvre la fiche), « Supprimer ».
private struct ShortcutRow: View {
    let remap: Remap
    let issues: [ShortcutIssue]
    let onOpen: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    private var caption: String? {
        var parts: [String] = []
        if remap.context != .everywhere { parts.append(remap.context.label) }
        if !remap.enabled { parts.append("désactivé") }
        guard !parts.isEmpty else { return nil }
        let text = parts.joined(separator: ", ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(remap.title).lineLimit(1)
                if let caption {
                    Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .help(remap.subtitle)
            Spacer(minLength: 12)
            if !issues.isEmpty {
                IssueIcon(issues: issues)
            }
            Button(action: onOpen) {
                KeyLabel(combo: remap.trigger)
            }
            .buttonStyle(.plain)
            .help("Modifier le raccourci")
            .accessibilityLabel("Modifier : \(remap.title)")
            .accessibilityValue(remap.trigger?.spoken ?? "aucun raccourci")

            Button(action: onDelete) {
                Label("Supprimer", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .opacity(remap.enabled ? 1 : 0.55)
        .contextMenu {
            Button("Modifier…", action: onOpen)
            Button(remap.enabled ? "Désactiver" : "Activer", action: onToggle)
            Divider()
            Button("Supprimer", role: .destructive, action: onDelete)
        }
    }
}

/// État vide centré (aucun résultat, aucun raccourci personnalisé).
private struct EmptyState: View {
    let title: String
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.title3).foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).padding(.top, 6)
            }
        }
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Fiche d'un raccourci personnalisé

struct EditSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var status: AppStatus
    @EnvironmentObject var link: MIDILink
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var recorder = Recorder.shared

    let isNew: Bool
    let onDone: (ToastMessage) -> Void
    @State private var draft: Remap
    @State private var category: FLActionInfo.Category
    @State private var query = ""

    init(original: Remap, isNew: Bool, onDone: @escaping (ToastMessage) -> Void) {
        self.isNew = isNew
        self.onDone = onDone
        _draft = State(initialValue: original)
        let cat = original.actionID.flatMap(FLActions.info)?.category ?? .composition
        _category = State(initialValue: cat)
    }

    private var issues: [ShortcutIssue] {
        guard draft.trigger != nil || draft.target != nil else { return [] }
        return store.draftIssues(draft).filter {
            if case .noTrigger = $0 { return false }
            if case .noTarget = $0 { return false }
            return true
        }
    }

    private var canSave: Bool {
        guard recorder.activeID == nil, draft.trigger != nil else { return false }
        switch draft.kind {
        case .flAction: guard draft.actionID != nil else { return false }
        case .keystroke: guard draft.target != nil else { return false }
        case .macro: guard draft.macro != nil else { return false }
        }
        return !store.draftIssues(draft).contains(where: \.isBlocking)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Nouveau raccourci" : "Modifier le raccourci").font(.headline)

            Form {
                LabeledContent("Raccourci") {
                    VStack(alignment: .leading, spacing: 6) {
                        CaptureField(id: "\(draft.id)-trigger", role: .trigger, combo: $draft.trigger)
                        if !issues.isEmpty && recorder.activeID == nil {
                            IssuesView(issues: issues)
                        }
                    }
                }
                Picker("Type", selection: $draft.kind) {
                    Text("Action dans FL").tag(Remap.Kind.flAction)
                    Text("Touche de FL").tag(Remap.Kind.keystroke)
                    Text("Macro").tag(Remap.Kind.macro)
                }
                .pickerStyle(.segmented)

                switch draft.kind {
                case .flAction: actionFields
                case .keystroke: keystrokeFields
                case .macro: MacroFields(macro: macroBinding)
                }
            }
            .formStyle(.columns)

            HStack(spacing: 8) {
                if !isNew {
                    Button("Supprimer", role: .destructive) {
                        let removed = draft
                        store.delete(draft.id)
                        onDone(ToastMessage(text: "Raccourci supprimé", undo: { store.upsert(removed) }))
                        dismiss()
                    }
                }
                Spacer()
                Button("Annuler") { recorder.stop(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .secondaryButton()
                Button("Valider") {
                    recorder.stop()
                    var final = draft
                    final.enabled = true
                    if final.kind != .keystroke { final.target = nil }
                    if final.kind != .flAction { final.actionID = nil }
                    if final.kind != .macro { final.macro = nil }
                    store.upsert(final)
                    onDone(ToastMessage(text: isNew ? "Raccourci ajouté" : "Raccourci modifié", undo: nil))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .primaryButton()
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onDisappear { recorder.stop() }
    }

    /// Macro du brouillon (le modèle « Enregistrement rapide » tant que rien n'est modifié).
    private var macroBinding: Binding<Macro> {
        Binding(get: { draft.macro ?? Macro() }, set: { draft.macro = $0 })
    }

    private var categoryBinding: Binding<FLActionInfo.Category> {
        Binding(get: { category }, set: { category = $0; query = "" })
    }

    /// Sélection dans la liste : les actions indisponibles ne se sélectionnent pas.
    private var actionSelection: Binding<Int?> {
        let appStatus = status
        return Binding(get: { draft.actionID }, set: { id in
            guard let id, appStatus.availability(id).isUsable else { return }
            draft.actionID = id
            draft.unknownAction = nil
        })
    }

    @ViewBuilder private var actionFields: some View {
        LabeledContent("Action") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Rechercher une action", text: $query)
                        .textFieldStyle(.roundedBorder)
                    if !AppMode.light {
                        Button("Tester") {
                            if let id = draft.actionID { link.test(action: id) }
                        }
                        .disabled(draft.actionID == nil || link.status != .linked)
                        .help("Envoie l'action à FL Studio")
                    }
                }
                Picker("Catégorie", selection: categoryBinding) {
                    ForEach(FLActionInfo.Category.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                List(actions, selection: actionSelection) { info in
                    actionRow(info)
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .frame(height: 170)
                .overlay {
                    if actions.isEmpty {
                        Text("Aucune action trouvée").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        Picker("Où", selection: $draft.context) {
            ForEach(ShortcutContext.allCases) { Text($0.label).tag($0) }
        }
    }

    private var actions: [FLActionInfo] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return FLActions.all.filter { info in
            q.isEmpty ? info.category == category
                      : (info.label + " " + info.detail).localizedCaseInsensitiveContains(q)
        }
    }

    private func actionRow(_ info: FLActionInfo) -> some View {
        let availability = status.availability(info.id)
        return VStack(alignment: .leading, spacing: 1) {
            Text(info.label)
            if case .unavailable(let reason) = availability {
                Text(reason).font(.system(size: 11))
            }
        }
        .foregroundStyle(availability.isUsable ? Color.primary : Color.secondary)
        .help(info.detail)
    }

    @ViewBuilder private var keystrokeFields: some View {
        LabeledContent("Touche de FL") {
            VStack(alignment: .leading, spacing: 6) {
                CaptureField(id: "\(draft.id)-target", role: .target, combo: $draft.target)
                if let t = draft.target, let name = store.conflicts.flConflict(t) {
                    Text("Dans FL Studio : \(name.replacingOccurrences(of: "FL : ", with: ""))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("Le raccourci de FL Studio à déplacer sur ta touche.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct IssuesView: View {
    let issues: [ShortcutIssue]

    var body: some View {
        let blocking = issues.contains(where: \.isBlocking)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: blocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(blocking ? Color.red : Color.orange)
            Text(issues.map(\.message).joined(separator: " "))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11))
    }
}

// MARK: - Champ d'enregistrement d'un raccourci

/// Un seul enregistrement de raccourci à la fois (REL-19) ; le tap laisse tout passer pendant ce temps.
final class Recorder: ObservableObject {
    static let shared = Recorder()

    @Published private(set) var activeID: String? = nil
    @Published private(set) var hint: String? = nil
    /// Champ concerné par `hint` (le message reste visible après l'arrêt de l'enregistrement).
    @Published private(set) var hintID: String? = nil

    private var monitor: Any?
    private var handler: ((NSEvent) -> Void)?
    private var timeout: DispatchWorkItem?
    private var resignObserver: NSObjectProtocol?

    private init() {}

    func start(_ id: String, handler: @escaping (NSEvent) -> Void) {
        stop()
        hint = nil
        hintID = nil
        activeID = id
        self.handler = handler
        Store.shared.recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let h = self.handler else { return event }
            self.stop()
            DispatchQueue.main.async { h(event) }
            return nil
        }
        let work = DispatchWorkItem { [weak self] in
            self?.stop()
            self?.hint = "Aucune touche reçue : macOS utilise peut-être ce raccourci."
            self?.hintID = id
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.stop()
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        timeout?.cancel()
        timeout = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        handler = nil
        if activeID != nil { activeID = nil }
        if Store.shared.recording { Store.shared.recording = false }
    }
}

/// Champ façon champ de texte : clique, puis appuie sur tes touches. Échap annule, ⌫ seul efface.
/// Pendant l'enregistrement : contour accentué fixe (aucune animation).
struct CaptureField: View {
    enum Role { case trigger, target }

    let id: String
    let role: Role
    @Binding var combo: KeyCombo?
    @ObservedObject private var recorder = Recorder.shared

    private var recording: Bool { recorder.activeID == id }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 6, style: .continuous) }

    private var footnote: (text: String, warning: Bool)? {
        if recording { return ("Échap pour annuler, ⌫ pour effacer.", false) }
        if recorder.hintID == id, let hint = recorder.hint { return (hint, true) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                recording ? recorder.stop() : recorder.start(id, handler: accept)
            } label: {
                Group {
                    if recording {
                        Text("Appuie sur les touches…").foregroundStyle(Color.accentColor)
                    } else if let combo {
                        KeyCaps(combo: combo, large: true)
                    } else {
                        Text(role == .trigger ? "Cliquer pour enregistrer" : "Cliquer, puis taper la touche de FL")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(shape.fill(Color(nsColor: .textBackgroundColor)))
            .overlay(shape.strokeBorder(recording ? Color.accentColor : Color(nsColor: .separatorColor),
                                        lineWidth: recording ? 2 : 1))
            .accessibilityLabel(role == .trigger ? "Raccourci déclencheur" : "Touche envoyée à FL")
            .accessibilityValue(recording ? "Enregistrement en cours" : (combo?.spoken ?? "aucun"))

            if let footnote {
                Text(footnote.text)
                    .font(.system(size: 11))
                    .foregroundStyle(footnote.warning ? Color.orange : Color.secondary)
            }
        }
        .onDisappear { if recording { recorder.stop() } }
    }

    private func accept(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let candidate = KeyCombo(keyCode: event.keyCode, modifiers: mods)
        if !candidate.hasModifiers && event.keyCode == 53 { return }            // Échap : annuler
        if !candidate.hasModifiers && event.keyCode == 51 { combo = nil; return } // ⌫ : effacer
        guard candidate.isValidKey else { return }

        switch role {
        case .target:
            if let why = Store.shared.forbiddenReason(candidate) {
                Dialogs.inform("Touche interdite", "\(candidate.display) ne peut pas être envoyée à FL : \(why).")
                return
            }
        case .trigger:
            if candidate == Store.shared.toggleCombo {
                Dialogs.inform("Raccourci réservé", "⌃⌥⌘F sert à mettre FL Shortcut en pause.")
                return
            }
            if !candidate.hasModifiers && !KeyNames.functionKeys.contains(candidate.keyCode) {
                guard Dialogs.confirm("Touche seule : « \(candidate.display) »",
                                      "Elle ne pourra plus servir à taper du texte dans FL (noms, recherche, tempo) "
                                      + "ni au clavier-piano. Ajoute plutôt ⌃, ou limite-la à une fenêtre. Garder quand même ?")
                else { return }
            }
        }
        combo = candidate
    }
}

// MARK: - Éléments communs

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let undo: (() -> Void)?

    static func == (a: ToastMessage, b: ToastMessage) -> Bool { a.id == b.id }
}

/// Petite notification (verre sur macOS 26, opaque sinon) au-dessus du statut, avec « Annuler » quand c'est possible.
private struct ToastView: View {
    let message: ToastMessage
    let onClose: () -> Void

    private var shape: Capsule { Capsule() }

    var body: some View {
        HStack(spacing: 10) {
            Text(message.text).font(.system(size: 12))
            if let undo = message.undo {
                Button("Annuler") { undo(); onClose() }
                    .controlSize(.small)
                    .secondaryButton()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassSurface(shape)
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .accessibilityElement(children: .contain)
    }
}

enum Dialogs {
    static func confirm(_ title: String, _ text: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: "Continuer")
        a.addButton(withTitle: "Annuler")
        return a.runModal() == .alertFirstButtonReturn
    }

    static func inform(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}

// MARK: - Aides de présentation

extension Remap {
    /// Copie modifiée (création d'un brouillon).
    func with(_ change: (inout Remap) -> Void) -> Remap {
        var copy = self
        change(&copy)
        return copy
    }

    var title: String {
        switch kind {
        case .keystroke: return target.map { "Envoie \($0.display)" } ?? "Touche de FL à choisir"
        case .macro: return macro.map { "Macro : \($0.name.displaySafe())" } ?? "Macro à configurer"
        case .flAction:
            if let id = actionID, let info = FLActions.info(id) { return info.label }
            return unknownAction.map { "Action inconnue (\($0.displaySafe()))" } ?? "Action à choisir"
        }
    }

    var subtitle: String {
        switch kind {
        case .keystroke: return "Raccourci de FL Studio"
        case .macro: return "Enchaîne des clics et des touches dans FL, sans MIDI"
        case .flAction:
            guard let id = actionID, let info = FLActions.info(id) else { return "Mets FL Shortcut à jour pour l'utiliser" }
            if case .unavailable(let reason) = AppStatus.shared.availability(id) { return reason }
            return info.detail
        }
    }
}

// MARK: - Fiche d'une entrée du catalogue

/// Fiche simple d'une entrée du catalogue : on appuie sur la nouvelle touche, c'est tout.
/// Une touche ne sert qu'une fois : ce qui l'utilise déjà est listé sous le champ, puis confirmé.
struct CatalogEditSheet: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var link: MIDILink
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var recorder = Recorder.shared

    let row: CatalogRow
    let notice: String?
    /// Message, et l'entrée à qui proposer ensuite une nouvelle touche (touche reprise).
    let onDone: (ToastMessage, String?) -> Void
    @State private var combo: KeyCombo?
    @State private var pendingClashes: [KeyClash] = []
    @State private var showClashAlert = false

    init(row: CatalogRow, notice: String? = nil, onDone: @escaping (ToastMessage, String?) -> Void) {
        self.row = row
        self.notice = notice
        self.onDone = onDone
        _combo = State(initialValue: row.current)
    }

    /// Ce qui utilise déjà la touche choisie (affiché tout de suite, confirmé à la validation).
    private var clashes: [KeyClash] {
        guard let combo, combo != row.current else { return [] }
        return store.clashes(for: combo, editing: row)
    }

    private func apply(releasing toRelease: [KeyClash]) {
        recorder.stop()
        let followUp = toRelease.isEmpty ? nil : store.release(toRelease)
        store.setTrigger(combo, for: row)
        onDone(ToastMessage(text: "« \(row.entry.title) » : " + (combo?.display ?? "aucune touche"), undo: nil), followUp)
        dismiss()
    }

    private var nativeKey: KeyCombo? {
        if case .native(let c) = row.entry.kind { return c }
        return nil
    }

    private var actionID: Int? {
        if case .action(let id) = row.entry.kind { return id }
        return nil
    }

    private var issues: [ShortcutIssue] {
        guard let combo, combo != nativeKey else { return [] }
        return store.draftIssues(store.draft(for: row, trigger: combo)).filter {
            if case .noTrigger = $0 { return false }
            if case .noTarget = $0 { return false }
            return true
        }
    }

    private var canSave: Bool {
        recorder.activeID == nil && combo != row.current && !issues.contains(where: \.isBlocking)
            && (combo != nil || actionID != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.entry.title).font(.headline)
                Text(row.entry.section.title).font(.system(size: 11)).foregroundStyle(.secondary)
            }

            if let notice {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(notice).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12))
            }

            Form {
                LabeledContent("Touche") {
                    VStack(alignment: .leading, spacing: 6) {
                        CaptureField(id: "catalog-\(row.id)", role: .trigger, combo: $combo)
                        if !clashes.isEmpty && recorder.activeID == nil {
                            clashList
                        }
                        if !issues.isEmpty && recorder.activeID == nil {
                            IssuesView(issues: issues)
                        }
                    }
                }
                LabeledContent("D'origine") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.entry.defaultTrigger?.display ?? "Aucune")
                        if nativeKey != nil {
                            Text("Elle continue de marcher dans FL : ta touche s'ajoute.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.columns)

            HStack(spacing: 8) {
                Button {
                    combo = row.entry.defaultTrigger
                } label: {
                    Label("Réinitialiser", systemImage: "arrow.counterclockwise")
                }
                .disabled(combo == row.entry.defaultTrigger)

                if let id = actionID {
                    Button("Aucune touche") { combo = nil }
                        .disabled(combo == nil)
                    if !AppMode.light {
                        Button("Tester") { link.test(action: id) }
                            .disabled(link.status != .linked)
                            .help("Envoie l'action à FL Studio")
                    }
                }
                Spacer()
                Button("Annuler") { recorder.stop(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .secondaryButton()
                Button("Valider") {
                    recorder.stop()
                    let found = clashes
                    if found.isEmpty {
                        apply(releasing: [])
                    } else {
                        pendingClashes = found
                        showClashAlert = true
                    }
                }
                .keyboardShortcut(.defaultAction)
                .primaryButton()
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onDisappear { recorder.stop() }
        // Une touche ne sert qu'une fois : on annonce ce qui l'utilise avant de la reprendre.
        .alert("\(combo?.display ?? "Cette touche") est déjà utilisée", isPresented: $showClashAlert) {
            Button("Remplacer", role: .destructive) { apply(releasing: pendingClashes) }
            Button("Annuler", role: .cancel) { pendingClashes = [] }
        } message: {
            Text(pendingClashes.prefix(4).map(\.line).joined(separator: "\n")
                 + "\n\nUn raccourci ne peut servir qu'une fois. Si tu remplaces, tu pourras choisir tout de suite "
                 + "une autre touche pour « \(pendingClashes.first?.title ?? "l'autre raccourci") ».")
        }
    }

    /// Liste courte sous le champ : qui utilise déjà cette touche.
    private var clashList: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Déjà utilisée par :")
            }
            ForEach(clashes.prefix(4)) { c in
                Text(c.line).foregroundStyle(.secondary)
            }
            if clashes.count > 4 {
                Text("et \(clashes.count - 4) autre(s)").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11))
        .accessibilityElement(children: .combine)
    }
}
