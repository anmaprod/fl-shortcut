// Fenêtre « Raccourcis » › Macros (maquette du 30/10) : trois grandes cartes pour commencer une macro (Enregistrer,
// Macro vide, Modèles), puis la bibliothèque en cartes (nom, interrupteur du raccourci, touches, badges « À apprendre »
// et « À corriger ») ; chaque macro s'ouvre dans le créateur d'un clic, clic droit pour le reste. Importer / Exporter.
// Aussi : export / import .flsmacro (fichier relu avant d'être accepté) et le champ « Macro » d'un raccourci relié
// à la bibliothèque.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum MacroPageText {
    static let subtitle = String(localized: "Enchaîne des clics, des touches et des menus de FL Studio sur un seul raccourci. Le plus simple : enregistre ce que tu fais dans FL, chaque geste devient un bloc.")
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
    @ObservedObject var library: MacroLibraryStore
    let open: (UUID) -> Void
    let toast: (ToastMessage) -> Void
    /// Mode capture : des macros d'exemple en mémoire (jamais enregistrées), pour photographier la page remplie.
    @State private var sample: MacroLibrarySample?

    var body: some View {
        MacroLibraryList(library: sample?.library ?? library, sampleRemaps: sample?.remaps ?? [:],
                         open: open, toast: toast)
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
    @State private var showTemplates = false

    var body: some View {
        Group {
            if library.macros.isEmpty {
                empty
            } else {
                // Maquette validée le 30/10 (« pas du tout agréable à regarder ») : trois grandes cartes pour
                // commencer une macro, puis tes macros en cartes sur deux colonnes (nom, interrupteur, touches).
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 18) {
                        actionCards
                        MacroLibraryProblemLabel(library: library)
                        HStack(spacing: 8) {
                            Text("Mes macros").font(.system(size: 15, weight: .bold))
                            Text(verbatim: "\(library.macros.count)").font(.system(size: 12)).foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            smallButton(String(localized: "Importer"), symbol: "square.and.arrow.down") { importFile() }
                                .help("Ajouter des macros reçues (.flsmacro) ; la boîte s'ouvre dans Documents › FL Shortcuts › Macros")
                            smallButton(String(localized: "Exporter"), symbol: "square.and.arrow.up") { exportAll() }
                                .help("Toutes les macros, un fichier chacune, pour les partager (par défaut dans Documents › FL Shortcuts › Macros)")
                        }
                        .padding(.top, 4)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                            ForEach(library.macros, id: \.id) { doc in
                                row(doc)
                            }
                        }
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
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
            // Plus de phrases d'explication (maquette du 28/10) : le résumé reste dans la bulle d'aide.
            // Le plus simple d'abord : enregistrer ce qu'on fait dans FL.
            Button {
                Self.recordNewMacro(in: library)
            } label: {
                Label("Enregistrer une macro", systemImage: "record.circle").frame(minWidth: 240)
            }
            .primaryButton()
            .tint(.red)
            .controlSize(.large)
            .help("Une nouvelle macro s'ouvre et FL passe devant : clique et tape ta suite (menus, flèches, raccourcis…), puis « Terminer ». Chaque geste devient un bloc.")
            HStack(spacing: 10) {
                Button("Macro vide") { newMacro() }
                    .secondaryButton()
                Button("Partir d'un modèle…") { showTemplates = true }
                    .secondaryButton()
            }
            .padding(.top, 4)
            Button("Importer un fichier .flsmacro…") { importFile() }
                .buttonStyle(.link)
                .font(.system(size: 12))
            MacroLibraryProblemLabel(library: library)
                .frame(maxWidth: 420)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Les trois façons de commencer une macro, en grandes cartes (la première en rouge : la plus simple).
    private var actionCards: some View {
        HStack(spacing: 12) {
            MacroActionCard(title: String(localized: "Enregistrer une macro"), symbol: "record.circle", tint: .red,
                            prominent: true) { Self.recordNewMacro(in: library) }
                .help("Une nouvelle macro s'ouvre et FL passe devant : clique et tape ta suite, puis « Terminer »")
            MacroActionCard(title: String(localized: "Macro vide"), symbol: "plus", tint: .blue) { newMacro() }
            MacroActionCard(title: String(localized: "Modèles"), symbol: "square.grid.2x2", tint: .purple) {
                showTemplates = true
            }
        }
    }

    /// Petit bouton en capsule (« Importer », « Exporter »).
    private func smallButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .menuHover(tint: .gray, cornerRadius: 14)
    }

    private func row(_ doc: MacroDoc) -> some View {
        let sample = sampleRemaps[doc.id]
        let remap = sample ?? store.remaps(forMacro: doc.id).first
        let program = store.programs[doc.id]
        let flags = MacroOutline.flags(doc.blocks, learnedInput: MacroSpots.loadPath(.input) != nil)
        var badges: [(String, String, Color, String)] = []
        if flags.toLearn {
            badges.append((String(localized: "À apprendre"), "hand.point.up.left", .purple,
                            String(localized: "Un endroit ou l'entrée 1 est à montrer dans FL.")))
        } else if let problem = program?.problem {
            badges.append((String(localized: "À corriger"), "exclamationmark.triangle.fill", .red, problem))
        }
        if let remap, !remap.enabled {
            badges.append((String(localized: "Désactivée"), "pause.circle", .secondary,
                            String(localized: "Le raccourci de cette macro est désactivé.")))
        }
        return MacroLibraryCard(doc: doc, trigger: remap?.trigger, badges: badges,
                               onOpen: { open(doc.id) },
                               onDuplicate: { duplicate(doc) },
                               onExport: { export(doc) },
                               onToggle: remap.map { r -> () -> Void in { if sample == nil { toggle(r) } } },
                               onDelete: { delete(doc) })
    }

    // MARK: Actions

    private func newMacro() { Self.newMacro(in: library) }

    /// Nouvelle macro vide, ouverte dans le créateur (carte « Macro vide », ou bouton de la page vide).
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

    private func importFile() {
        let docs = MacroFileActions.importMacros(into: library, layout: store.layout)
        if docs.count == 1, let doc = docs.first {
            toast(ToastMessage(text: String(localized: "« \(doc.name) » importée, sans raccourci : relis-la dans le créateur"), undo: nil))
            open(doc.id)
        } else if docs.count > 1 {
            toast(ToastMessage(text: String(localized: "\(docs.count) macros importées, sans raccourci"), undo: nil))
        }
    }

    private func exportAll() {
        if let message = MacroFileActions.exportAll(library.macros) { toast(ToastMessage(text: message, undo: nil)) }
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
        toast(ToastMessage(text: String(localized: "« \(doc.name.displaySafe()) » supprimée"), undo: {
            lib.add(removed.doc, at: removed.index)
            for r in shortcuts { model.upsert(r) }
        }))
    }
}

/// Grande carte d'action de la page Macros : icône de couleur, nom en gras ; au survol, pleine de sa couleur.
private struct MacroActionCard: View {
    let title: String
    let symbol: String
    let tint: Color
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                SectionIcon(symbol: symbol, tint: tint, size: 40)
                Text(title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background {
                if prominent {
                    let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
                    shape.fill(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.10)],
                                              startPoint: .top, endPoint: .bottom))
                        .overlay(shape.strokeBorder(tint.opacity(0.45), lineWidth: 1))
                } else {
                    MockPlate(cornerRadius: 14)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .menuHover(tint: tint, cornerRadius: 14)
        .accessibilityLabel(title)
    }
}

/// Une macro de la bibliothèque, en carte (maquette du 30/10) : icône, nom, nombre de blocs, interrupteur du
/// raccourci, puis ses touches. Un clic l'ouvre dans le créateur ; clic droit : Dupliquer, Exporter, Supprimer.
private struct MacroLibraryCard: View {
    let doc: MacroDoc
    let trigger: KeyCombo?
    let badges: [(String, String, Color, String)]
    let onOpen: () -> Void
    let onDuplicate: () -> Void
    let onExport: () -> Void
    let onToggle: (() -> Void)?
    let onDelete: () -> Void

    private var count: String {
        let count = MacroValidation.count(doc.blocks)
        return count == 1 ? String(localized: "1 bloc") : String(localized: "\(count) blocs")
    }

    private var disabled: Bool { badges.contains { $0.0 == String(localized: "Désactivée") } }

    /// Les badges qui demandent d'agir (« Désactivée » se voit à l'interrupteur).
    private var alerts: [(String, String, Color, String)] { badges.filter { $0.0 != String(localized: "Désactivée") } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SectionIcon(symbol: SidebarItem.macros.symbol, tint: SidebarItem.macros.tint, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.name.displaySafe(max: 60))
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    Text(count).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                .layoutPriority(-1)                      // carte étroite : le nom se raccourcit, pas l'interrupteur
                Spacer(minLength: 8)
                if let onToggle {
                    Toggle("", isOn: Binding(get: { !disabled }, set: { _ in onToggle() }))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .help(disabled ? String(localized: "Activer le raccourci") : String(localized: "Désactiver le raccourci"))
                }
            }
            if !alerts.isEmpty {
                HStack(spacing: 6) {
                    ForEach(alerts.indices, id: \.self) { i in
                        Label(alerts[i].0, systemImage: alerts[i].1)
                            .font(.system(size: 10.5, weight: .semibold))
                            .hoverTint(alerts[i].2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(alerts[i].2.opacity(0.15)))
                            .fixedSize()
                            .help(alerts[i].3)
                    }
                }
            }
            if let trigger {
                KeyLabel(combo: trigger, placeholder: String(localized: "Sans raccourci"))
            } else {
                Text("Choisir un raccourci…")
                    .font(.system(size: 12, weight: .medium))
                    .hoverTint(Appearance.link)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MockPlate(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .menuHover(tint: SidebarItem.macros.tint, cornerRadius: 14)
        .onTapGesture(perform: onOpen)                  // un seul clic pour rentrer dans la macro
        .contextMenu {
            Button("Modifier…", action: onOpen)
            Button("Dupliquer", action: onDuplicate)
            Button("Exporter…", action: onExport)
            if let onToggle {
                Divider()
                Button(disabled ? String(localized: "Activer le raccourci") : String(localized: "Désactiver le raccourci"), action: onToggle)
            }
            Divider()
            Button("Supprimer", role: .destructive, action: onDelete)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SectionIcon(symbol: "square.grid.2x2", tint: .purple, size: 34)
                Text("Modèles de macros").font(.title3.weight(.semibold))
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
                        .menuHover(tint: .purple, cornerRadius: 12)
                    }
                }
                .padding(6)                              // place pour le survol, qui grandit un peu
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

/// Dossiers d'échange, rangés comme les projets de FL : ~/Documents/FL Shortcuts/Macros et …/Raccourcis. Les boîtes
/// d'export et d'import s'y ouvrent ; créés à la première ouverture d'une de ces boîtes (jamais au lancement).
/// Un dossier « Documents/FL Shortcut » (ancien nom de l'app) prend alors le nouveau nom, avec ses fichiers.
enum ExchangeFolder {
    case macros, shortcuts

    var url: URL {
        let documents = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        return AppPaths.renamed(documents.appendingPathComponent(AppPaths.oldName, isDirectory: true),
                                to: documents.appendingPathComponent("FL Shortcuts", isDirectory: true))
            .appendingPathComponent(self == .macros ? "Macros" : "Raccourcis", isDirectory: true)
    }

    /// Le dossier, créé s'il manque ; nil si impossible (la boîte s'ouvre alors là où macOS le décide).
    func prepared() -> URL? {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue ? url : nil
    }
}

enum MacroFileActions {
    static var fileType: UTType { UTType(filenameExtension: MacroExchange.fileExtension, conformingTo: .json) ?? .json }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    /// Exporte une macro (positions apprises retirées). Renvoie le message à afficher, nil si annulé.
    static func export(_ doc: MacroDoc) -> String? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [fileType]
        panel.directoryURL = ExchangeFolder.macros.prepared()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = MacroExchange.suggestedFileName(doc.name)
        panel.message = String(localized: "Les endroits appris (clics montrés dans FL) ne sont pas exportés : ils se montrent sur chaque Mac.")
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try MacroExchange.export(doc, appVersion: appVersion).write(to: url, options: .atomic)
            return String(localized: "Macro exportée")
        } catch {
            Dialogs.inform(String(localized: "Export impossible"), error.localizedDescription)
            return nil
        }
    }

    /// Toutes les macros, un fichier .flsmacro chacune, dans le dossier choisi (par défaut FL Shortcuts › Macros) :
    /// prêtes à envoyer à un collègue. Un fichier du même nom n'est jamais écrasé (« (2) », « (3) »…).
    static func exportAll(_ docs: [MacroDoc]) -> String? {
        guard !docs.isEmpty else { return nil }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = ExchangeFolder.macros.prepared()
        panel.prompt = String(localized: "Exporter ici")
        panel.message = String(localized: "Chaque macro devient un fichier .flsmacro. Les endroits appris (clics montrés dans FL) ne sont pas exportés.")
        guard panel.runModal() == .OK, let folder = panel.url else { return nil }
        var written = 0
        for doc in docs {
            let base = (MacroExchange.suggestedFileName(doc.name) as NSString).deletingPathExtension
            var url = folder.appendingPathComponent(base).appendingPathExtension(MacroExchange.fileExtension)
            var n = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = folder.appendingPathComponent("\(base) (\(n))").appendingPathExtension(MacroExchange.fileExtension)
                n += 1
            }
            do {
                try MacroExchange.export(doc, appVersion: appVersion).write(to: url, options: .withoutOverwriting)
                written += 1
            } catch {
                Dialogs.inform(String(localized: "Export impossible"),
                               String(localized: "« \(doc.name.displaySafe(max: 40)) » : \(error.localizedDescription)"))
                break
            }
        }
        guard written > 0 else { return nil }
        let what = written == 1 ? String(localized: "1 macro exportée") : String(localized: "\(written) macros exportées")
        return what + String(localized: " dans « \(folder.lastPathComponent) »")
    }

    /// Relecture d'un import : décompte en tête, TOUS les blocs dans une liste qui défile, ce qu'il faudra faire.
    static func confirmImport(_ preview: MacroExchange.Preview) -> Bool {
        let count = preview.lines.count == 1 ? String(localized: "1 bloc") : String(localized: "\(preview.lines.count) blocs")
        let review = preview.sensitiveCount == 0 ? "" : preview.sensitiveCount == 1
            ? String(localized: ", dont 1 à relire") : String(localized: ", dont \(preview.sensitiveCount) à relire")
        var text = String(localized: "« \(preview.doc.name) » — \(count)\(review).")
        if !preview.warnings.isEmpty { text += String(localized: "\n\nÀ faire :\n• ") + preview.warnings.joined(separator: "\n• ") }
        text += String(localized: "\n\nElle arrive sans raccourci : relis-la dans le créateur, puis choisis-lui un raccourci.")
        let alert = NSAlert()
        alert.messageText = String(localized: "Importer cette macro ?")
        alert.informativeText = text
        alert.addButton(withTitle: String(localized: "Importer"))
        alert.addButton(withTitle: String(localized: "Annuler"))
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 460, height: 220))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let list = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        list.isEditable = false
        list.isVerticallyResizable = true
        list.autoresizingMask = [.width]
        list.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        list.textContainer?.widthTracksTextView = true
        list.font = .systemFont(ofSize: 11)
        list.string = preview.lines.joined(separator: "\n")
        scroll.documentView = list
        alert.accessoryView = scroll
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Importe un ou plusieurs .flsmacro (reçus d'un collègue), chacun relu avant d'être accepté : chaque macro
    /// arrive sans raccourci (inactive), ids neufs. La boîte s'ouvre dans FL Shortcuts › Macros.
    static func importMacros(into library: MacroLibraryStore, layout: KeyboardLayout) -> [MacroDoc] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [fileType, .json]
        panel.allowsMultipleSelection = true
        panel.directoryURL = ExchangeFolder.macros.prepared()
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

struct LibraryMacroFields: View {
    @ObservedObject var library: MacroLibraryStore
    let ref: UUID
    let open: () -> Void

    var body: some View {
        LabeledContent("Macro") {
            VStack(alignment: .leading, spacing: 6) {
                Text(library.doc(ref)?.name.displaySafe(max: 60) ?? String(localized: "Macro introuvable (supprimée ?)"))
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
    var selected = false
    let choose: () -> Void

    var body: some View {
        SidebarLabel(title: Text("Macros"), symbol: SidebarItem.macros.symbol, tint: SidebarItem.macros.tint)
            .sidebarRow(SidebarItem.macros.tint, selected: selected, choose: choose)
            .help(MacroPageText.subtitle)
    }
}
