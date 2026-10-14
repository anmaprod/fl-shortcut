// Fenêtre « Raccourcis » › Macros : la bibliothèque des macros en blocs (nom, raccourci, badges « Lien FL »,
// « À apprendre », « Désactivée », « À corriger »), « Nouvelle macro », « Modèles… », « Importer… » ; chaque macro
// s'ouvre dans le créateur (double-clic ou « Modifier… »). Page en cartes comme les autres, aucun verre par ligne.
// Aussi : export / import .flsmacro (fichier relu avant d'être accepté) et le champ « Macro » d'un raccourci relié
// à la bibliothèque.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum MacroPageText {
    static let subtitle = "Enchaîne des touches, des menus et des attentes dans FL Studio sur un seul raccourci. Chaque macro se construit bloc par bloc dans le créateur."
}

/// Problème de la bibliothèque (enregistrement impossible, fichier relu en partie) : page Macros, même vide, et
/// créateur. Rien si tout va bien.
struct MacroLibraryProblemLabel: View {
    @ObservedObject var library: MacroLibraryStore

    var body: some View {
        if let problem = library.problem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .symbolRenderingMode(.multicolor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MacroLibraryPage: View {
    @EnvironmentObject var store: Store
    @ObservedObject var library: MacroLibraryStore
    let open: (UUID) -> Void
    let toast: (ToastMessage) -> Void
    @State private var showTemplates = false

    var body: some View {
        Group {
            if library.macros.isEmpty {
                empty
            } else {
                Form {
                    Section {
                        PageHeader(symbol: SidebarItem.macros.symbol, tint: SidebarItem.macros.tint, title: "Macros",
                                   subtitle: MacroPageText.subtitle,
                                   detail: library.macros.count == 1 ? "1 macro" : "\(library.macros.count) macros")
                        actions
                    }
                    if library.problem != nil {
                        Section {
                            MacroLibraryProblemLabel(library: library)
                        }
                    }
                    Section {
                        ForEach(library.macros) { doc in
                            row(doc)
                        }
                    } header: {
                        Text("Mes macros")
                    }
                }
                .formStyle(.grouped)
                .glassListBackground()
            }
        }
        .sheet(isPresented: $showTemplates) {
            MacroTemplatesSheet(templates: MacroTemplates.gallery(layout: store.layout)) { template in
                use(template)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            SectionIcon(symbol: SidebarItem.macros.symbol, tint: SidebarItem.macros.tint, size: 52)
            Text("Aucune macro").font(.title2.weight(.semibold))
            Text(MacroPageText.subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack(spacing: 10) {
                Button("Nouvelle macro") { newMacro() }
                    .primaryButton()
                    .controlSize(.large)
                Button("Partir d'un modèle…") { showTemplates = true }
                    .secondaryButton()
                    .controlSize(.large)
            }
            Button("Importer un fichier .flsmacro…") { importFile() }
                .buttonStyle(.link)
                .font(.system(size: 12))
            MacroLibraryProblemLabel(library: library)
                .frame(maxWidth: 420)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                newMacro()
            } label: {
                Label("Nouvelle macro", systemImage: "plus")
            }
            Button {
                showTemplates = true
            } label: {
                Label("Modèles…", systemImage: "square.grid.2x2")
            }
            Button {
                importFile()
            } label: {
                Label("Importer…", systemImage: "square.and.arrow.down")
            }
            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
    }

    private func row(_ doc: MacroDoc) -> some View {
        let remap = store.remaps(forMacro: doc.id).first
        let program = store.programs[doc.id]
        let flags = MacroOutline.flags(doc.blocks, learnedInput: MacroSpots.loadPath(.input) != nil)
        var badges: [(String, String, Color, String)] = []
        if flags.usesLink {
            badges.append(("Lien FL", "link", .blue, "Des actions passent par le lien avec FL quand il est installé (sinon leur touche de secours)."))
        }
        if flags.toLearn {
            badges.append(("À apprendre", "hand.point.up.left", .purple, "Un endroit ou l'entrée 1 est à montrer dans FL."))
        } else if let problem = program?.problem {
            badges.append(("À corriger", "exclamationmark.triangle.fill", .red, problem))
        }
        if let remap, !remap.enabled {
            badges.append(("Désactivée", "pause.circle", .secondary, "Le raccourci de cette macro est désactivé."))
        }
        return MacroLibraryRow(doc: doc, trigger: remap?.trigger, badges: badges,
                               onOpen: { open(doc.id) },
                               onDuplicate: { duplicate(doc) },
                               onExport: { export(doc) },
                               onToggle: remap.map { r -> () -> Void in { toggle(r) } },
                               onDelete: { delete(doc) })
    }

    // MARK: Actions

    private func newMacro() {
        let doc = library.add(MacroDoc(name: library.uniqueName("Nouvelle macro"), blocks: []))
        open(doc.id)
    }

    private func use(_ template: MacroTemplate) {
        var doc = template.make(store.layout)
        doc.name = library.uniqueName(doc.name)
        let added = library.add(doc)
        open(added.id)
    }

    private func duplicate(_ doc: MacroDoc) {
        var copy = MacroDoc(name: library.uniqueName(doc.name + " (copie)"), blocks: MacroTemplates.freshIDs(doc.blocks),
                            variables: doc.variables, origin: doc.origin)
        copy.format = doc.format
        library.add(copy)
        toast(ToastMessage(text: "« \(copy.name) » ajoutée, sans raccourci", undo: { library.remove(copy.id) }))
    }

    private func export(_ doc: MacroDoc) {
        if let message = MacroFileActions.export(doc) { toast(ToastMessage(text: message, undo: nil)) }
    }

    private func importFile() {
        guard let doc = MacroFileActions.importMacro(into: library, layout: store.layout) else { return }
        toast(ToastMessage(text: "« \(doc.name) » importée, sans raccourci : relis-la dans le créateur", undo: nil))
        open(doc.id)
    }

    private func toggle(_ remap: Remap) {
        var copy = remap
        copy.enabled.toggle()
        store.upsert(copy)
    }

    /// Supprime la macro et ses raccourcis (annulable depuis la notification).
    private func delete(_ doc: MacroDoc) {
        let shortcuts = store.remaps(forMacro: doc.id)
        guard let removed = library.remove(doc.id) else { return }
        for r in shortcuts { store.delete(r.id) }
        let lib = library
        let model = store
        toast(ToastMessage(text: "« \(doc.name.displaySafe()) » supprimée", undo: {
            lib.add(removed.doc, at: removed.index)
            for r in shortcuts { model.upsert(r) }
        }))
    }
}

/// Une macro de la bibliothèque : icône, nom, résumé, badges, raccourci, « Modifier… ».
private struct MacroLibraryRow: View {
    let doc: MacroDoc
    let trigger: KeyCombo?
    let badges: [(String, String, Color, String)]
    let onOpen: () -> Void
    let onDuplicate: () -> Void
    let onExport: () -> Void
    let onToggle: (() -> Void)?
    let onDelete: () -> Void

    private var caption: String {
        let count = MacroValidation.count(doc.blocks)
        let blocks = count == 1 ? "1 bloc" : "\(count) blocs"
        let first = doc.blocks.lazy.filter { $0.enabled && $0.body.type != .comment }.prefix(3)
            .map { BlockRegistry.label(of: $0.body) }
        return first.isEmpty ? blocks : blocks + " · " + first.joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 10) {
            SectionIcon(symbol: "wand.and.stars", tint: .purple, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(doc.name.displaySafe(max: 60)).lineLimit(1)
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            ForEach(badges.indices, id: \.self) { i in
                Label(badges[i].0, systemImage: badges[i].1)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(badges[i].2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(badges[i].2.opacity(0.13)))
                    .help(badges[i].3)
            }
            KeyLabel(combo: trigger, placeholder: "Sans raccourci")
            Button("Modifier…", action: onOpen)
                .buttonStyle(.borderless)
                .font(.system(size: 12))
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onOpen)
        .contextMenu {
            Button("Modifier…", action: onOpen)
            Button("Dupliquer", action: onDuplicate)
            Button("Exporter…", action: onExport)
            if let onToggle {
                Divider()
                Button(badges.contains { $0.0 == "Désactivée" } ? "Activer le raccourci" : "Désactiver le raccourci",
                       action: onToggle)
            }
            Divider()
            Button("Supprimer", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Modifier", onOpen)
    }
}

// MARK: - Modèles

struct MacroTemplatesSheet: View {
    let templates: [MacroTemplate]
    let choose: (MacroTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SectionIcon(symbol: "square.grid.2x2", tint: .purple, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Modèles de macros").font(.title3.weight(.semibold))
                    Text("Pars d'un modèle, puis modifie-le bloc par bloc dans le créateur.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(templates) { t in
                        HStack(alignment: .top, spacing: 12) {
                            SectionIcon(symbol: t.symbol, tint: .purple, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.title).fontWeight(.semibold)
                                Text(t.summary)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Button("Utiliser") {
                                choose(t)
                                dismiss()
                            }
                            .secondaryButton()
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
                    }
                }
            }
            HStack {
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 540, height: 470)
    }
}

// MARK: - Fichiers .flsmacro

enum MacroFileActions {
    static var fileType: UTType { UTType(filenameExtension: MacroExchange.fileExtension, conformingTo: .json) ?? .json }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// Exporte une macro (positions apprises retirées). Renvoie le message à afficher, nil si annulé.
    static func export(_ doc: MacroDoc) -> String? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [fileType]
        panel.nameFieldStringValue = MacroExchange.suggestedFileName(doc.name)
        panel.message = "Les endroits appris (clics montrés dans FL) ne sont pas exportés : ils se montrent sur chaque Mac."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try MacroExchange.export(doc, appVersion: appVersion).write(to: url, options: .atomic)
            return "Macro exportée"
        } catch {
            Dialogs.inform("Export impossible", error.localizedDescription)
            return nil
        }
    }

    /// Importe un .flsmacro après relecture : la macro arrive sans raccourci (inactive), ids neufs.
    static func importMacro(into library: MacroLibraryStore, layout: KeyboardLayout) -> MacroDoc? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [fileType, .json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            guard size <= MacroExchange.maxBytes else { throw MacroExchange.Failure.tooLarge }
            let preview = try MacroExchange.prepareImport(try Data(contentsOf: url), layout: layout)
            var text = "« \(preview.doc.name) » — " + (preview.lines.count == 1 ? "1 bloc" : "\(preview.lines.count) blocs") + " :\n\n"
            text += preview.lines.prefix(30).joined(separator: "\n")
            if preview.lines.count > 30 { text += "\n… et \(preview.lines.count - 30) autre(s)" }
            if !preview.warnings.isEmpty { text += "\n\nÀ faire :\n• " + preview.warnings.joined(separator: "\n• ") }
            text += "\n\nElle arrive sans raccourci : relis-la dans le créateur, puis choisis-lui un raccourci."
            guard Dialogs.confirm("Importer cette macro ?", text) else { return nil }
            var doc = preview.doc
            doc.name = library.uniqueName(doc.name)
            return library.add(doc)
        } catch {
            Dialogs.inform("Import impossible", error.localizedDescription)
            return nil
        }
    }
}

// MARK: - Fiche d'un raccourci relié à la bibliothèque

struct LibraryMacroFields: View {
    @ObservedObject var library: MacroLibraryStore
    let ref: UUID
    let open: () -> Void

    var body: some View {
        LabeledContent("Macro") {
            VStack(alignment: .leading, spacing: 6) {
                Text(library.doc(ref)?.name.displaySafe(max: 60) ?? "Macro introuvable (supprimée ?)")
                    .fontWeight(.medium)
                Text("Macro en blocs de la bibliothèque (Macros). Ses étapes se modifient dans le créateur.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if library.doc(ref) != nil {
                    Button {
                        open()
                    } label: {
                        Label("Ouvrir dans le créateur…", systemImage: "wand.and.stars")
                    }
                    .secondaryButton()
                }
            }
        }
    }
}

// MARK: - Barre latérale

/// « Macros » dans la barre latérale : le nombre de macros est tenu à jour par la bibliothèque seule (la fenêtre
/// n'est pas redessinée en entier quand une macro change).
struct MacroSidebarRow: View {
    @ObservedObject var library: MacroLibraryStore

    var body: some View {
        Label {
            Text("Macros")
        } icon: {
            SectionIcon(symbol: SidebarItem.macros.symbol, tint: SidebarItem.macros.tint)
        }
        .badge(library.macros.count)
        .help(MacroPageText.subtitle)
    }
}
