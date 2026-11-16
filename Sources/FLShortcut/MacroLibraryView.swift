// Fenêtre « Raccourcis » › Macros (maquette « plus lisible » du 16/11) : une ligne par macro (nom, touche dans sa
// case, interrupteur) ; « Importer », « Exporter » et « Nouvelle macro » dans l'en-tête de la page (EditorView), cette
// dernière proposant d'enregistrer une macro, d'en partir d'une vide ou d'un modèle. Sans macro : « Aucune macro. » et
// « Nouvelle macro ». Une macro s'ouvre dans le créateur d'un clic, clic droit pour le reste.
// Aussi : export / import .flsmacro (fichier relu avant d'être accepté) et le champ « Macro » d'un raccourci relié
// à la bibliothèque.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Problème de la bibliothèque (enregistrement impossible, fichier relu en partie) : page Macros, même vide, et
/// créateur. Rien si tout va bien.
struct MacroLibraryProblemLabel: View {
    @ObservedObject var library: MacroLibraryStore

    var body: some View {
        if let problem = library.problem {
            SwissWarning(problem)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct MacroLibraryPage: View {
    @ObservedObject var library: MacroLibraryStore
    let open: (UUID) -> Void
    let toast: (ToastMessage) -> Void
    /// Clic sur la touche d'une macro : la fiche de son raccourci (nouveau si elle n'en a pas).
    var editKey: (Remap, Bool) -> Void = { _, _ in }
    /// Mode capture : des macros d'exemple en mémoire (jamais enregistrées), pour photographier la page remplie.
    @State private var sample: MacroLibrarySample?

    var body: some View {
        MacroLibraryList(library: sample?.library ?? library, sampleRemaps: sample?.remaps ?? [:],
                         open: open, toast: toast, editKey: editKey)
            .onReceive(DebugSnapshot.publisher(DebugSnapshot.macros)) { note in
                sample = (note.object as? String) == "exemples" ? MacroLibrarySample() : nil
            }
    }
}

/// Mode capture : quatre macros des modèles dans une bibliothèque en mémoire, deux avec un raccourci (dont un
/// désactivé). Rien n'est enregistré ni relié au clavier.
private struct MacroLibrarySample {
    let library = MacroLibraryStore(storage: MemoryMacroLibraryStorage())
    var remaps: [UUID: Remap] = [:]

    init() {
        let layout = SystemKeyboardLayout()
        let docs = MacroTemplates.gallery(layout: layout).prefix(4).map { library.add($0.make(layout)) }
        for (i, doc) in docs.prefix(2).enumerated() {
            var remap = Remap()
            remap.kind = .macro
            remap.macroRef = doc.id
            remap.enabled = i == 0
            remap.trigger = KeyCombo(keyCode: i == 0 ? 14 : 1, command: true, option: false, control: false, shift: true)
            remaps[doc.id] = remap
        }
    }
}

/// La page Macros elle-même (bibliothèque de l'app, ou celle des exemples en mode capture).
private struct MacroLibraryList: View {
    @EnvironmentObject var store: Store
    @ObservedObject var library: MacroLibraryStore
    let sampleRemaps: [UUID: Remap]
    let open: (UUID) -> Void
    let toast: (ToastMessage) -> Void
    let editKey: (Remap, Bool) -> Void
    @ObservedObject private var templates = MacroTemplatesLink.shared

    var body: some View {
        Group {
            if library.macros.isEmpty {
                empty
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        MacroLibraryProblemLabel(library: library)
                            .padding(.bottom, 10)
                        ForEach(library.macros, id: \.id) { doc in
                            row(doc)
                        }
                    }
                    .frame(maxWidth: ReadableLayout.maxWidth, alignment: .leading)
                    .padding(.horizontal, ReadableLayout.inset)
                    .padding(.top, 4)
                    .padding(.bottom, 80)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .sheet(isPresented: $templates.showing) {
            MacroTemplatesSheet(templates: MacroTemplates.gallery(layout: store.layout)) { template in
                use(template)
            }
            .swissSheet()
        }
    }

    /// Sans macro (maquette, écran 6) : « Aucune macro. » en grand, puis « Nouvelle macro ».
    private var empty: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text("Aucune macro.").swissTitle(56)
            NewMacroButton(library: library)
            MacroLibraryProblemLabel(library: library)
                .frame(maxWidth: 420, alignment: .leading)
        }
        .padding(.top, 110)
        .frame(maxWidth: ReadableLayout.maxWidth, alignment: .leading)
        .padding(.horizontal, ReadableLayout.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ doc: MacroDoc) -> some View {
        let sample = sampleRemaps[doc.id]
        let remap = sample ?? store.remaps(forMacro: doc.id).first
        let program = store.programs[doc.id]
        let flags = MacroOutline.flags(doc.blocks, learnedInput: MacroSpots.loadPath(.input) != nil)
        var alert: (String, Color, String)?
        if flags.toLearn {
            alert = (String(localized: "À apprendre"), Color.purple, String(localized: "Un endroit ou l'entrée 1 est à montrer dans FL."))
        } else if let problem = program?.problem {
            alert = (String(localized: "À corriger"), Swiss.red, problem)
        }
        return MacroLibraryLine(doc: doc, trigger: remap?.trigger, disabled: remap.map { !$0.enabled } ?? false,
                                alert: alert,
                                onOpen: { open(doc.id) },
                                onKey: {
                                    guard sample == nil else { return }
                                    if let remap { editKey(remap, false) } else { editKey(Remap(trigger: nil, macroRef: doc.id), true) }
                                },
                                onDuplicate: { duplicate(doc) },
                                onExport: { export(doc) },
                                onToggle: remap.map { r -> () -> Void in { if sample == nil { toggle(r) } } },
                                onDelete: { delete(doc) })
    }

    // MARK: Actions

    private func use(_ template: MacroTemplate) {
        var doc = template.make(store.layout)
        doc.name = library.uniqueName(doc.name)
        let added = library.add(doc)
        MacroCreatorLink.shared.open(added.id, isNew: true)
    }

    private func duplicate(_ doc: MacroDoc) {
        var copy = MacroDoc(name: library.uniqueName(doc.name + String(localized: " (copie)")), blocks: MacroTemplates.freshIDs(doc.blocks),
                            variables: doc.variables, origin: doc.origin)
        copy.format = doc.format
        library.add(copy)
        toast(ToastMessage(text: String(localized: "« \(copy.name) » ajoutée, sans raccourci"), undo: { library.remove(copy.id) }))
    }

    private func export(_ doc: MacroDoc) {
        if let message = MacroFileActions.export(doc) { toast(ToastMessage(text: message, undo: nil)) }
    }

    private func toggle(_ remap: Remap) {
        var copy = remap
        copy.enabled.toggle()
        store.upsert(copy)
    }

    /// Supprime la macro et ses raccourcis, après une question (03/11 : « c'est seulement pour supprimer que ça doit
    /// demander ») ; encore annulable depuis la notification.
    private func delete(_ doc: MacroDoc) {
        let shown = doc.name.displaySafe(max: 40)
        guard Dialogs.choose(String(localized: "Supprimer « \(shown) » ?"),
                             "",
                             [String(localized: "Supprimer"), String(localized: "Annuler")], destructive: 0) == 0
        else { return }
        let shortcuts = store.remaps(forMacro: doc.id)
        guard let removed = library.remove(doc.id) else { return }
        for r in shortcuts { store.delete(r.id) }
        let lib = library
        let model = store
        toast(ToastMessage(text: String(localized: "« \(doc.name.displaySafe()) » supprimée"), undo: {
            lib.add(removed.doc, at: removed.index)
            for r in shortcuts { model.upsert(r) }
        }))
    }
}

/// Les façons de commencer une macro et l'import / export, partagés par l'en-tête de la page et la page vide.
enum MacroLibraryActions {
    /// Nouvelle macro vide, ouverte dans le créateur.
    static func newMacro(in library: MacroLibraryStore) {
        let doc = library.add(MacroDoc(name: library.uniqueName(String(localized: "Nouvelle macro")), blocks: []))
        MacroCreatorLink.shared.open(doc.id, isNew: true)       // au retour : l'enregistrer ou la supprimer
    }

    /// « Enregistrer une macro » : nouvelle macro ouverte dans le créateur, et l'enregistrement des clics et des
    /// touches qui démarre aussitôt (FL passe devant).
    static func recordNewMacro(in library: MacroLibraryStore) {
        let doc = library.add(MacroDoc(name: library.uniqueName(String(localized: "Nouvelle macro")), blocks: []))
        MacroCreatorLink.shared.open(doc.id, isNew: true, record: true)
    }

    static func importFile(into library: MacroLibraryStore, layout: KeyboardLayout,
                           toast: (ToastMessage) -> Void, open: (UUID) -> Void) {
        let docs = MacroFileActions.importMacros(into: library, layout: layout)
        if docs.count == 1, let doc = docs.first {
            toast(ToastMessage(text: String(localized: "« \(doc.name) » importée"), undo: nil))
            open(doc.id)
        } else if docs.count > 1 {
            toast(ToastMessage(text: String(localized: "\(docs.count) macros importées, sans raccourci"), undo: nil))
        }
    }

    static func exportAll(_ library: MacroLibraryStore, toast: (ToastMessage) -> Void) {
        if let message = MacroFileActions.exportAll(library.macros) { toast(ToastMessage(text: message, undo: nil)) }
    }
}

/// « Partir d'un modèle… » demandé par « Nouvelle macro » (en-tête ou page vide) : la page Macros montre les modèles.
final class MacroTemplatesLink: ObservableObject {
    static let shared = MacroTemplatesLink()
    @Published var showing = false
}

/// « Nouvelle macro » (maquette du 16/11) : bouton plein ; un clic montre les trois façons de commencer.
struct NewMacroButton: View {
    let library: MacroLibraryStore

    var body: some View {
        Button("Nouvelle macro") {
            SwissContextMenu.shared.show([
                RightClickMenu.Item(title: String(localized: "Enregistrer une macro"),
                                    action: { MacroLibraryActions.recordNewMacro(in: library) }),
                RightClickMenu.Item(title: String(localized: "Macro vide"),
                                    action: { MacroLibraryActions.newMacro(in: library) }),
                RightClickMenu.Item(title: String(localized: "Partir d'un modèle…"),
                                    action: { MacroTemplatesLink.shared.showing = true }),
            ], at: NSEvent.mouseLocation)
        }
        .primaryButton()
        .controlSize(.large)
        .fixedSize()
        .help("Enregistrer une macro, ou partir d'une macro vide ou d'un modèle")
    }
}

/// Une macro (maquette) : son nom (gris si son raccourci est désactivé), « À APPRENDRE » ou « À CORRIGER », sa touche
/// dans sa case, l'interrupteur. Un clic l'ouvre dans le créateur ; la touche ouvre la fiche de son raccourci.
private struct MacroLibraryLine: View {
    let doc: MacroDoc
    let trigger: KeyCombo?
    let disabled: Bool
    let alert: (String, Color, String)?
    let onOpen: () -> Void
    let onKey: () -> Void
    let onDuplicate: () -> Void
    let onExport: () -> Void
    let onToggle: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(doc.name.displaySafe(max: 60))
                .font(Swiss.font(15))
                .foregroundStyle(disabled ? Swiss.gray : Swiss.text)
                .lineLimit(1)
                .layoutPriority(-1)
            if let alert {
                Text(alert.0).swissLabel(alert.1, size: 10).fixedSize().padding(.leading, 12).help(alert.2)
            }
            Spacer(minLength: 12)
            Button(action: onKey) { KeyBox(combo: trigger) }
                .buttonStyle(.plain)
                .opacity(disabled ? 0.55 : 1)
                .help(String(localized: "Changer la touche"))
                .accessibilityLabel(String(localized: "Changer la touche de \(doc.name.displaySafe(max: 40))"))
            Group {
                if let onToggle {
                    SwissSwitch(isOn: Binding(get: { !disabled }, set: { _ in onToggle() }),
                                label: String(localized: "Raccourci de la macro"))
                        .help(disabled ? String(localized: "Activer le raccourci") : String(localized: "Désactiver le raccourci"))
                } else {
                    Color.clear.frame(width: 40, height: 20)
                }
            }
            .padding(.leading, 22)
        }
        .frame(maxWidth: .infinity, minHeight: ReadableLayout.rowHeight, alignment: .leading)
        .swissRule(Swiss.faint)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)                  // un seul clic pour rentrer dans la macro
        .swissContextMenu {
            var items: [RightClickMenu.Item?] = [
                RightClickMenu.Item(title: String(localized: "Modifier…"), action: onOpen),
                RightClickMenu.Item(title: String(localized: "Changer la touche…"), action: onKey),
                RightClickMenu.Item(title: String(localized: "Dupliquer"), action: onDuplicate),
                RightClickMenu.Item(title: String(localized: "Exporter…"), action: onExport),
            ]
            if let onToggle {
                items.append(nil)
                items.append(RightClickMenu.Item(title: disabled ? String(localized: "Activer le raccourci")
                                                 : String(localized: "Désactiver le raccourci"), action: onToggle))
            }
            items.append(nil)
            items.append(RightClickMenu.Item(title: String(localized: "Supprimer"), destructive: true, action: onDelete))
            return items
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Modifier", onOpen)
    }
}

/// La page Macros, demandée hors de la fenêtre principale (menu de l'icône).
final class MacrosLink: ObservableObject {
    static let shared = MacrosLink()
    @Published var pending = false

    func show() { pending = true }
}

// MARK: - Modèles

struct MacroTemplatesSheet: View {
    let templates: [MacroTemplate]
    let choose: (MacroTemplate) -> Void
    @Environment(\.dismiss) private var dismiss

    /// 05/11 (« reprendre l'idée de base… mais refais-la un peu mieux… tout sur une page, sans scroll ») : le titre et
    /// son point carré, puis les modèles en cartes sur deux colonnes (numéro, nom, phrase) ; un clic sur une carte la
    /// prend. Tout tient sans défiler.
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SwissPageTitle(text: String(localized: "Modèles"), size: 38)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .swissRule()
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                      alignment: .leading, spacing: 16) {
                ForEach(Array(templates.enumerated()), id: \.element.id) { index, t in
                    TemplateCard(number: String(format: "%02d", index + 1), title: t.title, summary: t.summary) {
                        choose(t)
                        dismiss()
                    }
                }
            }
            HStack(spacing: 0) {
                Spacer()
                Button("Fermer") { dismiss() }
                    .secondaryButton()
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 4)
        }
        .padding(26)
        .frame(width: 680)
        .fixedSize(horizontal: false, vertical: true)
        .background(Swiss.background)
    }
}

/// Un modèle (05/11) : son numéro, son nom en gras, sa phrase, « UTILISER » ; toute la carte le prend, pleine d'encre au
/// survol.
private struct TemplateCard: View {
    let number: String
    let title: String
    let summary: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                Text(verbatim: number).font(Swiss.font(14)).foregroundStyle(hovering ? Swiss.red : Swiss.gray)
                    .frame(width: 24, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Swiss.font(16)).tracking(-0.3).lineLimit(1).minimumScaleFactor(0.8)
                    Text(summary).font(.system(size: 12)).opacity(0.7).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                Text("Utiliser").font(Swiss.font(10.5)).tracking(1.1).textCase(.uppercase)
                    .padding(.horizontal, 10).frame(height: 30)
                    .overlay(Rectangle().strokeBorder(hovering ? Swiss.background : Swiss.text, lineWidth: 2))
            }
            .foregroundStyle(hovering ? Swiss.background : Swiss.text)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .background(Rectangle().fill(hovering ? Swiss.text : Swiss.background))
            .overlay(Rectangle().strokeBorder(Swiss.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityHint(summary)
    }
}

// MARK: - Fichiers .flsmacro

/// Dossiers d'échange, rangés comme les projets de FL : ~/Documents/FL Shortcuts/Macros et …/Raccourcis. Dans
/// Macros (06/11, « un dossier Importer et un dossier Exporter ») : Importer, où l'on pose les macros reçues (la boîte
/// d'import s'y ouvre), et Exporter, où arrivent les macros exportées. Créés au premier import ou export (jamais au
/// lancement), les deux ensemble. Un dossier « Documents/FL Shortcut » (ancien nom de l'app) prend alors le nouveau
/// nom, avec ses fichiers.
enum ExchangeFolder {
    case macros, shortcuts, macrosImport, macrosExport

    var url: URL {
        let documents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        let root = AppPaths.renamed(documents.appendingPathComponent(AppPaths.oldName, isDirectory: true),
                                    to: documents.appendingPathComponent("FL Shortcuts", isDirectory: true))
        switch self {
        case .macros: return root.appendingPathComponent("Macros", isDirectory: true)
        case .shortcuts: return root.appendingPathComponent("Raccourcis", isDirectory: true)
        case .macrosImport: return Self.macros.url.appendingPathComponent("Importer", isDirectory: true)
        case .macrosExport: return Self.macros.url.appendingPathComponent("Exporter", isDirectory: true)
        }
    }

    /// Le dossier, créé s'il manque (avec son voisin pour Importer / Exporter) ; nil si impossible (la boîte s'ouvre
    /// alors là où macOS le décide).
    func prepared() -> URL? {
        if self == .macrosImport || self == .macrosExport {
            for folder in [Self.macrosImport, Self.macrosExport] {
                try? FileManager.default.createDirectory(at: folder.url, withIntermediateDirectories: true)
            }
        } else {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue ? url : nil
    }

    /// Fichier libre dans ce dossier : « Nom.flsmacro », sinon « Nom (2).flsmacro »… (jamais d'écrasement).
    static func freeFile(in folder: URL, base: String, extension ext: String) -> URL {
        var url = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) (\(n))").appendingPathExtension(ext)
            n += 1
        }
        return url
    }
}

enum MacroFileActions {
    static var fileType: UTType { UTType(filenameExtension: MacroExchange.fileExtension, conformingTo: .json) ?? .json }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// Exporte une macro (positions apprises retirées) tout droit dans Documents › FL Shortcuts › Macros › Exporter
    /// (06/11), sans boîte ; le Finder montre le fichier, prêt à envoyer. Renvoie le message à afficher.
    static func export(_ doc: MacroDoc) -> String? {
        write([doc])
    }

    /// Toutes les macros, un fichier .flsmacro chacune, dans Macros › Exporter : prêtes à envoyer à un collègue. Un
    /// fichier du même nom n'est jamais écrasé (« (2) », « (3) »…).
    static func exportAll(_ docs: [MacroDoc]) -> String? {
        write(docs)
    }

    private static func write(_ docs: [MacroDoc]) -> String? {
        guard !docs.isEmpty else { return nil }
        guard let folder = ExchangeFolder.macrosExport.prepared() else {
            Dialogs.inform(String(localized: "Export impossible"),
                           String(localized: "Le dossier Documents › FL Shortcuts › Macros › Exporter n'a pas pu être créé."))
            return nil
        }
        var written: [URL] = []
        for doc in docs {
            let base = (MacroExchange.suggestedFileName(doc.name) as NSString).deletingPathExtension
            let url = ExchangeFolder.freeFile(in: folder, base: base, extension: MacroExchange.fileExtension)
            do {
                try MacroExchange.export(doc, appVersion: appVersion).write(to: url, options: .withoutOverwriting)
                written.append(url)
            } catch {
                Dialogs.inform(String(localized: "Export impossible"),
                               String(localized: "« \(doc.name.displaySafe(max: 40)) » : \(error.localizedDescription)"))
                break
            }
        }
        guard !written.isEmpty else { return nil }
        NSWorkspace.shared.activateFileViewerSelecting(written)
        return written.count == 1 ? String(localized: "Macro exportée dans Macros › Exporter")
            : String(localized: "\(written.count) macros exportées dans Macros › Exporter")
    }

    /// Relecture d'un import : décompte en tête, TOUS les blocs dans une liste qui défile, ce qu'il faudra faire.
    static func confirmImport(_ preview: MacroExchange.Preview) -> Bool {
        let count = preview.lines.count == 1 ? String(localized: "1 bloc") : String(localized: "\(preview.lines.count) blocs")
        let review = preview.sensitiveCount == 0 ? "" : preview.sensitiveCount == 1
            ? String(localized: ", dont 1 à relire") : String(localized: ", dont \(preview.sensitiveCount) à relire")
        var text = String(localized: "« \(preview.doc.name) » — \(count)\(review).")
        if !preview.warnings.isEmpty { text += String(localized: "\n\nÀ faire :\n• ") + preview.warnings.joined(separator: "\n• ") }
        // Au style suisse (02/11) : tous les blocs dans une liste qui défile, sous le texte.
        return SwissDialog.run(String(localized: "Importer cette macro ?"), text,
                               buttons: [String(localized: "Importer"), String(localized: "Annuler")],
                               list: preview.lines) == 0
    }

    /// Importe un ou plusieurs .flsmacro (reçus d'un collègue), chacun relu avant d'être accepté : chaque macro
    /// arrive sans raccourci (inactive), ids neufs. La boîte s'ouvre dans FL Shortcuts › Macros › Importer (06/11 :
    /// c'est là qu'on pose les macros reçues).
    static func importMacros(into library: MacroLibraryStore, layout: KeyboardLayout) -> [MacroDoc] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [fileType, .json]
        panel.allowsMultipleSelection = true
        panel.directoryURL = ExchangeFolder.macrosImport.prepared()
        guard panel.runModal() == .OK else { return [] }
        var added: [MacroDoc] = []
        for url in panel.urls.prefix(50) {
            do {
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                guard size <= MacroExchange.maxBytes else { throw MacroExchange.Failure.tooLarge }
                let preview = try MacroExchange.prepareImport(try Data(contentsOf: url), layout: layout)
                guard confirmImport(preview) else { continue }
                var doc = preview.doc
                doc.name = library.uniqueName(doc.name)
                added.append(library.add(doc))
            } catch {
                Dialogs.inform(String(localized: "Import impossible"), String(localized: "\(url.lastPathComponent) : \(error.localizedDescription)"))
            }
        }
        return added
    }
}

// MARK: - Fiche d'un raccourci relié à la bibliothèque

// MARK: - Barre latérale

/// « Macros » dans la barre latérale : le nombre de macros est tenu à jour par la bibliothèque seule (la fenêtre
/// n'est pas redessinée en entier quand une macro change).
struct MacroSidebarRow: View {
    var selected = false
    let choose: () -> Void

    var body: some View {
        SidebarLabel(title: Text("Macros"), symbol: SidebarItem.macros.symbol, tint: SidebarItem.macros.tint,
                     selected: selected)
            .sidebarRow(SidebarItem.macros.tint, selected: selected, choose: choose)
    }
}
