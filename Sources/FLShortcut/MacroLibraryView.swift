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
                // Style suisse (01/11) : les trois départs numérotés, puis « MES MACROS » en lignes séparées d'un trait.
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        actionCards
                        MacroLibraryProblemLabel(library: library)
                            .padding(.top, 10)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("Mes macros").swissLabel(Swiss.text)
                            Text(verbatim: "\(library.macros.count)").swissLabel()
                            Spacer(minLength: 8)
                            smallButton(String(localized: "Importer"), symbol: "square.and.arrow.down") { importFile() }
                                .help("Ajouter des macros reçues (.flsmacro) ; la boîte s'ouvre dans Documents › FL Shortcuts › Macros")
                            smallButton(String(localized: "Exporter"), symbol: "square.and.arrow.up") { exportAll() }
                                .help("Toutes les macros, un fichier chacune, pour les partager (par défaut dans Documents › FL Shortcuts › Macros)")
                        }
                        .padding(.top, 26)
                        .padding(.bottom, 6)
                        .swissRule()
                        // Maquette du 05/11 : tes macros en cartes (nom, interrupteur, touches), sur trois colonnes.
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 20, alignment: .top)],
                                  alignment: .leading, spacing: 20) {
                            ForEach(library.macros, id: \.id) { doc in
                                row(doc)
                            }
                        }
                        .padding(.top, 14)
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 0)
                    .padding(.bottom, 24)
                }
            }
        }
        .sheet(isPresented: $showTemplates) {
            MacroTemplatesSheet(templates: MacroTemplates.gallery(layout: store.layout)) { template in
                use(template)
            }
            .swissSheet()
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Text("Aucune macro").swissTitle(34)
            // Plus de phrases d'explication (maquette du 28/10) : le résumé reste dans la bulle d'aide.
            // Le plus simple d'abord : enregistrer ce qu'on fait dans FL.
            Button {
                Self.recordNewMacro(in: library)
            } label: {
                Label("Enregistrer une macro", systemImage: "record.circle").frame(minWidth: 240)
            }
            .primaryButton()
            .controlSize(.large)
            .help("Une nouvelle macro s'ouvre et FL passe devant : clique et tape ta suite (menus, flèches, raccourcis…), puis « Terminer ». Chaque geste devient un bloc.")
            HStack(spacing: 10) {
                Button("Macro vide") { newMacro() }
                    .secondaryButton()
                Button("Partir d'un modèle…") { showTemplates = true }
                    .secondaryButton()
            }
            .padding(.top, 4)
            Button { importFile() } label: {
                Text("Importer un fichier .flsmacro…").swissLabel(size: 10.5).underline()
            }
            .buttonStyle(.plain)
            MacroLibraryProblemLabel(library: library)
                .frame(maxWidth: 420)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Les trois façons de commencer une macro (maquette du 05/11) : trois grandes cartes numérotées, le titre en grand
    /// en bas ; la première est la carte principale (pleine, sur son ombre nette).
    private var actionCards: some View {
        HStack(alignment: .top, spacing: 20) {
            MacroActionCard(number: "01", title: String(localized: "Enregistrer une macro"),
                            subtitle: String(localized: "Fais-le dans FL, l'app le retient."), primary: true) {
                Self.recordNewMacro(in: library)
            }
            .help("Une nouvelle macro s'ouvre et FL passe devant : clique et tape ta suite, puis « Terminer »")
            MacroActionCard(number: "02", title: String(localized: "Macro vide"),
                            subtitle: String(localized: "Pose les blocs un par un.")) { newMacro() }
            MacroActionCard(number: "03", title: String(localized: "Modèles"),
                            subtitle: String(localized: "Pars d'une macro toute prête.")) { showTemplates = true }
        }
        .padding(.top, 10)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Petit bouton en texte (« IMPORTER », « EXPORTER ») : petites capitales grises, blanc plein au survol.
    private func smallButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .swissLabel(size: 10.5)
                .padding(.horizontal, 6)
                .frame(height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuHover(tint: Swiss.text, cornerRadius: 0)
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

    /// Supprime la macro et ses raccourcis, après une question (03/11 : « c'est seulement pour supprimer que ça doit
    /// demander ») ; encore annulable depuis la notification.
    private func delete(_ doc: MacroDoc) {
        let shown = doc.name.displaySafe(max: 40)
        guard Dialogs.choose(String(localized: "Supprimer « \(shown) » ?"),
                             String(localized: "La macro et son raccourci sont supprimés."),
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

/// Départ d'une macro (maquette du 05/11) : son numéro en haut, le titre en grand (minuscules) en bas, une phrase
/// dessous. La principale : pleine sur son ombre nette ; les autres : cartes bordées, pleines d'encre au survol.
private struct MacroActionCard: View {
    let number: String
    let title: String
    let subtitle: String
    var primary = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let lit = hovering
        let fill: Color = primary ? (lit ? Swiss.background : Swiss.primaryFill) : (lit ? Swiss.text : Swiss.background)
        let ink: Color = primary ? (lit ? Swiss.text : Swiss.primaryInk) : (lit ? Swiss.background : Swiss.text)
        let numberColor: Color = lit || (primary && AppTheme.current == .papier) ? Swiss.red
            : (primary ? Swiss.primaryInk : Swiss.gray)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: number).font(Swiss.font(15)).foregroundStyle(numberColor)
                Spacer(minLength: 28)
                Text(title.lowercased(with: Locale.current))
                    .font(Swiss.title(30)).tracking(-1.5)
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.system(size: 13)).opacity(0.75).lineLimit(2)
            }
            .foregroundStyle(ink)
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
            .background(Rectangle().fill(fill))
            .overlay(Rectangle().strokeBorder(primary ? Swiss.text : Swiss.line, lineWidth: primary ? 2 : 1))
            .background(Rectangle().fill(primary && !lit ? Swiss.primaryShadow : Color.clear).offset(x: 6, y: 6))
            .contentShape(Rectangle())
            .swissCard(if: !primary)                     // noire sous Orange, comme la maquette
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
    @State private var hovering = false

    private var count: String {
        let count = MacroValidation.count(doc.blocks)
        return count == 1 ? String(localized: "1 bloc") : String(localized: "\(count) blocs")
    }

    private var disabled: Bool { badges.contains { $0.0 == String(localized: "Désactivée") } }

    /// Les badges qui demandent d'agir (« Désactivée » se voit à l'interrupteur).
    private var alerts: [(String, String, Color, String)] { badges.filter { $0.0 != String(localized: "Désactivée") } }

    var body: some View {
        // Maquette du 05/11 : une carte par macro, le nom en gras et l'interrupteur en haut, les alertes, puis ses
        // touches ; survolée, elle se soulève sur une encoche rouge.
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                Text(doc.name.displaySafe(max: 60))
                    .font(Swiss.font(17)).tracking(-0.3)
                    .lineLimit(2)
                    .help(count)
                Spacer(minLength: 8)
                if let onToggle {
                    SwissSwitch(isOn: Binding(get: { !disabled }, set: { _ in onToggle() }),
                                label: String(localized: "Raccourci de la macro"))
                        .help(disabled ? String(localized: "Activer le raccourci") : String(localized: "Désactiver le raccourci"))
                }
            }
            if !alerts.isEmpty {
                HStack(spacing: 10) {
                    ForEach(alerts.indices, id: \.self) { i in
                        Text(alerts[i].0)
                            .swissLabel(alerts[i].2, size: 10)
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
                    .underline()
                    .lineLimit(1)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .swissCard()
        .background(Rectangle().fill(Swiss.background))
        .overlay(Rectangle().strokeBorder(hovering ? Swiss.text : Swiss.line, lineWidth: hovering ? 2 : 1))
        .offset(x: hovering ? -3 : 0, y: hovering ? -3 : 0)
        .background(Rectangle().fill(hovering ? Swiss.brandRed : Color.clear))
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovering = inside } }
        .contentShape(Rectangle())
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
        // Au style suisse (02/11) : tous les blocs dans une liste qui défile, sous le texte.
        return SwissDialog.run(String(localized: "Importer cette macro ?"), text,
                               buttons: [String(localized: "Importer"), String(localized: "Annuler")],
                               list: preview.lines) == 0
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
        SidebarLabel(title: Text("Macros"), symbol: SidebarItem.macros.symbol, tint: SidebarItem.macros.tint,
                     selected: selected)
            .sidebarRow(SidebarItem.macros.tint, selected: selected, choose: choose)
            .help(MacroPageText.subtitle)
    }
}
