// Créateur de macros : affiché DANS la fenêtre principale (comme un dossier dans le Finder), à l'identique de la
// maquette du 28/10 (demande du 29/10) ; vue et modèle libérés au retour (EditorView, CreatorPresence).
// - À gauche, la palette dans une plaque claire (blocs par catégorie) ; au centre, l'en-tête (← rond, nom en gras,
//   touches du raccourci, « Enregistrer » bleu : ⌘S, sinon 0,5 s après la dernière modification), « Enregistrer
//   clics et touches », puis les étapes dans une carte (une phrase par ligne, valeurs en pastilles, icône colorée de
//   la catégorie, interrupteur) et la zone en pointillés où glisser un bloc ; à droite, les réglages du bloc choisi
//   dans une plaque (« Retirer ce bloc » en bas). Plus de barre d'outils, d'Exporter, de Dupliquer, de « Si le bloc
//   échoue » ni de note (29/10 : « le reste ça part »).
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

    var body: some View {
        HStack(spacing: 0) {
            MacroPaletteView(items: model.paletteItems, insert: { [model] item in
                withAnimation(MacroStepsPane.spring) { model.insert(item) }
            })
                .frame(width: EditorView.sidebarWidth)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(MockPlate(cornerRadius: 19, top: 0.10, bottom: 0.04, border: 0.16))
                .overlay(alignment: .trailing) { Rectangle().fill(Swiss.line).frame(width: 1) }
            // Colonne des étapes jamais sous `stepsMinWidth` (03/11, capture « quand on rétrécit trop, ça fait
            // chelou » : à 280 points, le nom de la macro disparaissait et « Commencer l'enregistrement » débordait) ;
            // la fenêtre ne descend pas sous `minWidth` tant que le créateur est affiché.
            VStack(spacing: 0) {
                LibraryProblemBanner(library: store.library)
                MacroStepsPane(model: model, monitor: model.monitor, paletteItems: model.paletteItems, onBack: onBack)
            }
            .frame(minWidth: Self.stepsMinWidth, maxWidth: .infinity, maxHeight: .infinity)
            // Réglages du bloc : largeur fixe, les étapes gardent la place (photo de la CI : lignes coupées).
            // Sous la barre de titre, comme la palette : une liste qui la touche défilait jusqu'en haut de la fenêtre.
            MacroInspectorView(model: model)
                .padding(.top, MainWindowChrome.titleBarHeight - 8 + 4)
                .frame(width: 270)
                .frame(maxHeight: .infinity)
                .background(MockPlate(cornerRadius: 19, top: 0.10, bottom: 0.04, border: 0.16))
                .overlay(alignment: .leading) { Rectangle().fill(Swiss.line).frame(width: 1) }
        }
        .padding(8)
        .frame(minWidth: Self.minWidth, maxWidth: .infinity, maxHeight: .infinity)
        .background(Appearance.windowColor)
        // Sous la barre de titre transparente, comme la page des raccourcis (MainWindowChrome).
        .ignoresSafeArea()
        // Titre de la fenêtre (menu Fenêtre, VoiceOver) ; jamais affiché.
        .navigationTitle(model.draft?.name ?? String(localized: "Créateur de macros"))
        .hiddenWindowChrome()
        // Fenêtre qui l'affiche : retour du focus après « Montrer dans FL… », et devant FL tant qu'il est affiché.
        .background(WindowReader { [model] window in
            model.window = window
            CreatorPresence.attach(window)
            MainWindowChrome.keep(window)
            Self.makeRoom(in: window)
        })
        .onAppear {
            model.undoManager = undoManager
            model.handle(link.request)                  // déjà fait avant l'ouverture : sans effet
        }
        .onChange(of: link.request) { request in model.handle(request) }
    }

    /// Largeur des étapes au plus serré : la ligne du haut (←, nom, touches, « Enregistrer ») et « Commencer
    /// l'enregistrement » y tiennent sans rien couper.
    static let stepsMinWidth: CGFloat = 430
    /// Palette + étapes + réglages + marges.
    static var minWidth: CGFloat { EditorView.sidebarWidth + stepsMinWidth + 270 + 16 }

    /// Fenêtre plus étroite que le créateur à son ouverture : élargie tout de suite (sur l'écran), plutôt que de couper
    /// la colonne des étapes.
    static func makeRoom(in window: NSWindow) {
        DispatchQueue.main.async {
            guard window.frame.width < minWidth else { return }
            var frame = window.frame
            let screen = window.screen?.visibleFrame ?? frame
            frame.size.width = min(minWidth, screen.width)
            if frame.maxX > screen.maxX { frame.origin.x = max(screen.minX, screen.maxX - frame.width) }
            window.setFrame(frame, display: true, animate: false)
        }
    }
}

// MARK: - Liste des étapes

private struct MacroStepsPane: View {
    @ObservedObject var model: MacroEditorModel
    @ObservedObject var monitor: MacroRunMonitor
    let paletteItems: [PaletteItem]
    /// ← : retour aux raccourcis (avec la question « Enregistrer ou supprimer » si besoin).
    let onBack: () -> Void
    /// Pendant un glisser (bloc de la liste ou de la palette) : la place où il tombera, dessinée en trait rouge.
    @State private var dropLine: StepDropLine?
    /// Largeur d'une ligne : l'image qui suit la souris a la taille du bloc entier.
    @State private var rowWidth: CGFloat = 420
    /// Bloc de la palette ou de la liste au-dessus de la zone en pointillés.
    @State private var zoneTargeted = false

    var body: some View {
        Group {
            if model.draft != nil {
                VStack(alignment: .leading, spacing: 12) {
                    MacroHeader(model: model, onBack: onBack)
                        .padding(.horizontal, 22)
                    list
                }
                // Sous la barre de titre : elle ne laisse passer aucun clic.
                .padding(.top, MainWindowChrome.contentTop)
            } else {
                VStack(spacing: 10) {
                    SectionIcon(symbol: "wand.and.stars", tint: .purple, size: 44)
                    Text("Aucune macro ouverte").font(Swiss.title(22)).tracking(Swiss.titleTracking(22))
                    Text("Crée une macro, ou ouvre-en une depuis la fenêtre Raccourcis › Macros.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button("Nouvelle macro") { model.newMacro() }
                        .primaryButton()
                        .controlSize(.large)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) {
                    CreatorBackButton(action: onBack)
                        .padding(.leading, 22)
                        .padding(.top, MainWindowChrome.contentTop)
                }
            }
        }
        .floatingBar(.bottom) {
            MacroResultBanner(model: model, monitor: monitor)
        }
    }

    /// Ressort court et sans rebond visible, façon Apple : les lignes s'écartent pour le bloc ajouté, glissent quand
    /// on les range, se resserrent quand on en supprime. Seulement au moment du changement : rien ne tourne au repos.
    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.86)

    /// Les étapes dans une carte (maquette : une plaque claire, un trait fin entre deux lignes), puis la zone en
    /// pointillés où lâcher un bloc. Toujours une liste : sélection, ⌫, rangement et dépôt entre deux lignes.
    private var list: some View {
        let rows = model.rows
        return List(selection: $model.selection) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                MacroStepRowView(row: row, status: status(row), current: monitor.current == row.blockID && row.kind == .block,
                                 selected: model.selection == row.id,
                                 onToggle: { on in model.setEnabled(row.blockID, on) })
                    .equatable()
                    // Survol : toute la ligne de la couleur de son bloc (pas la ligne choisie, ni une fin de boucle).
                    .cardRow(.position(index: index, count: rows.count),
                             hover: row.kind == .block ? Swiss.text : nil,
                             selected: model.selection == row.id,
                             stamp: row.kind == .block ? Swiss.brandRed : nil)   // l'encoche orange, pour tous (05/11)
                    .tag(row.id)
                    // Pas de sélection bleue de macOS : la ligne choisie est blanche, sur son encoche (02/11).
                    .background(NoSystemSelection().frame(width: 0, height: 0))
                    // Clic droit : Désactiver, Supprimer, sans le contour bleu de macOS (04/11).
                    .overlay(RightClickMenu(items: { menuItems(row) }))
                    // Glisser-déposer à nous (07/11 au soir, « quand je joue avec un bloc du milieu ça fait crash ») :
                    // plus le rangement de la liste de macOS (onMove), qui faisait tomber l'app ; le bloc entier suit
                    // la souris, un trait rouge montre où il tombera (moitié haute : au-dessus, moitié basse : dessous).
                    .modifier(StepDragDrop(row: row, index: index, count: rows.count, width: rowWidth, line: $dropLine,
                                           select: { [model] in
                                               model.selection = row.id
                                               NoSystemSelection.focusList()      // ⌫ et les flèches pour la liste
                                           },
                                           drop: { providers, before in drop(providers, before: before) }))
            }
            if !rows.isEmpty {
                dropZone
                    .listRowInsets(EdgeInsets(top: 12, leading: CardRowBackground.inset, bottom: 8,
                                              trailing: CardRowBackground.inset))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.inset)
        .glassListBackground()
        // Largeur d'une ligne (sans les marges de la carte) : celle de l'image du bloc glissé.
        .background(GeometryReader { g in
            Color.clear
                .onAppear { rowWidth = max(200, g.size.width - 2 * CardRowBackground.inset - 16) }
                .onChange(of: g.size.width) { w in rowWidth = max(200, w - 2 * CardRowBackground.inset - 16) }
        })
        .onDeleteCommand { withAnimation(Self.spring) { model.deleteSelection() } }
        .overlay {
            if model.rows.isEmpty {
                // Le plus simple d'abord : enregistrer ce qu'on fait dans FL ; les blocs de la palette ensuite.
                VStack(spacing: 10) {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text("Enregistre ce que tu fais dans FL").font(Swiss.title(22)).tracking(Swiss.titleTracking(22))
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

    /// Bloc lâché avant la ligne `before` : une ligne de la liste y est rangée (avec ce qu'elle contient), un bloc de
    /// la palette y est ajouté.
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

    /// Menu du clic droit d'un bloc (rien pour une ligne de fin de boucle).
    private func menuItems(_ row: MacroStepRow) -> [RightClickMenu.Item?] {
        guard row.kind == .block else { return [] }
        let model = model
        return [
            RightClickMenu.Item(title: row.ownEnabled ? String(localized: "Désactiver") : String(localized: "Activer")) {
                model.setEnabled(row.blockID, !row.ownEnabled)
            },
            nil,
            RightClickMenu.Item(title: String(localized: "Supprimer"), destructive: true) {
                model.selection = row.id
                withAnimation(Self.spring) { model.deleteSelection() }
            },
        ]
    }

    /// Zone en pointillés sous les étapes (maquette) : un bloc de la palette, ou de la liste, lâché ici va à la fin.
    private var dropZone: some View {
        Text("Glisse un bloc ici, ou clique-le dans la liste à gauche")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 52)
            .overlay(Rectangle()
                .strokeBorder(zoneTargeted ? Swiss.brandRed : Swiss.keyLine,
                              style: StrokeStyle(lineWidth: zoneTargeted ? 2 : 1, dash: [5, 4])))
            .contentShape(Rectangle())
            .onDrop(of: [.plainText], isTargeted: $zoneTargeted) { providers in
                drop(providers, before: model.rows.count)
                return true
            }
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
                    .hoverTint(.red)
                VStack(alignment: .leading, spacing: 1) {
                    Text(recorder.active ? String(localized: "Enregistrement en cours…")
                                         : String(localized: "Enregistrer clics et touches"))
                        .font(.system(size: 13, weight: .semibold))
                    // Une phrase seulement pendant l'enregistrement : comment le finir.
                    if recorder.active {
                        Text("Clique et tape dans FL, puis « Terminer » en haut à droite.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Text("⇧⌘R").font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Rectangle().fill(Color.red.opacity(0.09)))
            .overlay(Rectangle().strokeBorder(Color.red.opacity(0.3)))
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

/// Une ligne : case « actif », numéro, icône de la catégorie, phrase avec sa valeur en pastille, badges, état.
/// Glisser une ligne de la liste : un texte « flshortcut-step:<ligne> » (numéro de ligne interne, jamais un nom),
/// que seule la liste du créateur comprend.
enum StepDrag {
    static let prefix = "flshortcut-step:"

    enum Payload: Equatable {
        case step(String)
        case palette(String)
    }

    static func provider(_ row: MacroStepRow) -> NSItemProvider {
        NSItemProvider(object: (prefix + row.id) as NSString)
    }

    /// Ce que porte un texte glissé : une ligne de la liste, un bloc de la palette, ou rien.
    static func payload(_ text: String) -> Payload? {
        if text.hasPrefix(prefix) { return .step(String(text.dropFirst(prefix.count))) }
        if text.hasPrefix(PaletteDrag.prefix) { return .palette(String(text.dropFirst(PaletteDrag.prefix.count))) }
        return nil
    }

    /// Lu sur le fil principal ; rien pour un autre texte.
    static func load(_ providers: [NSItemProvider], _ done: @escaping (Payload) -> Void) {
        guard let p = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return }
        _ = p.loadObject(ofClass: NSString.self) { object, _ in
            guard let text = object as? NSString, let payload = payload(text as String) else { return }
            DispatchQueue.main.async { done(payload) }
        }
    }
}

/// Place d'un dépôt en cours : avant la ligne `before` ; `owner` = la ligne survolée (elle seule l'efface en sortant).
struct StepDropLine: Equatable {
    let before: Int
    let owner: Int
}

/// Une ligne qui se glisse (bloc entier) et qui reçoit un dépôt (trait rouge au-dessus ou au-dessous).
private struct StepDragDrop: ViewModifier {
    let row: MacroStepRow
    let index: Int
    let count: Int
    let width: CGFloat
    @Binding var line: StepDropLine?
    /// Clic sur la ligne : elle est choisie. Le glisser à nous prend l'appui de la souris, la liste de macOS ne voyait
    /// plus le clic (essai à vrais clics de la CI du 07/11 au soir : la ligne cliquée n'était pas choisie).
    let select: () -> Void
    let drop: ([NSItemProvider], Int) -> Void
    @State private var height: CGFloat = 40

    /// Écart ouvert entre les deux blocs voisins de l'endroit où le bloc tombera (08/11, « il n'y a pas d'animation…
    /// refais une animation avec le bloc… pour que les gens comprennent qu'ils peuvent glisser ») : les deux lignes
    /// s'écartent en douceur et un trait orange, avec son carré, se déroule entre elles. Seul le dessin bouge : la
    /// zone de dépôt de chaque ligne reste en place (jamais d'aller-retour sous la souris).
    static let gap: CGFloat = 7

    private var shift: CGFloat {
        guard let before = line?.before else { return 0 }
        if before == index { return Self.gap }                      // l'écart s'ouvre au-dessus de cette ligne
        if before == index + 1 { return -Self.gap }                 // … ou en dessous
        return 0
    }

    func body(content: Content) -> some View {
        dragged(content)
            .offset(y: shift)
            .animation(Motion.reduce ? nil : .spring(response: 0.26, dampingFraction: 0.82), value: line?.before)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { height = g.size.height }
                    .onChange(of: g.size.height) { h in height = h }
            })
            .onDrop(of: [.plainText], delegate: StepDropDelegate(index: index, height: height, line: $line, drop: drop))
            .overlay(alignment: .top) { if line?.before == index { mark.offset(y: -1.5) } }
            .overlay(alignment: .bottom) { if index == count - 1, line?.before == count { mark.offset(y: 1.5) } }
            .animation(Motion.reduce ? nil : .easeOut(duration: 0.16), value: line?.before)
    }

    @ViewBuilder private func dragged(_ content: Content) -> some View {
        if row.kind == .block {
            content
                .onTapGesture(perform: select)
                .onDrag { StepDrag.provider(row) } preview: { StepDragPreview(row: row, width: width) }
        } else {
            content.onTapGesture(perform: select)
        }
    }

    /// Là où le bloc tombera : un carré et un trait orange (style suisse), qui se déroule de gauche à droite.
    private var mark: some View {
        HStack(spacing: 0) {
            Rectangle().fill(Swiss.brandRed).frame(width: 9, height: 9)
            Rectangle().fill(Swiss.brandRed).frame(height: 3)
        }
        .allowsHitTesting(false)
        .transition(.scale(scale: 0.05, anchor: .leading).combined(with: .opacity))
    }
}

private struct StepDropDelegate: DropDelegate {
    let index: Int
    let height: CGFloat
    @Binding var line: StepDropLine?
    let drop: ([NSItemProvider], Int) -> Void

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.plainText]) }
    func dropEntered(info: DropInfo) { update(info) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)          // jamais le « + » vert de macOS
    }

    func dropExited(info: DropInfo) {
        if line?.owner == index { line = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        let before = place(info)
        line = nil
        drop(info.itemProviders(for: [.plainText]), before)
        return true
    }

    /// Moitié haute de la ligne : au-dessus ; moitié basse : dessous.
    private func place(_ info: DropInfo) -> Int { info.location.y > height / 2 ? index + 1 : index }

    private func update(_ info: DropInfo) {
        let next = StepDropLine(before: place(info), owner: index)
        if line != next { line = next }
    }
}

/// Ce qui suit la souris : le bloc entier, comme la ligne choisie (blanche sur son encoche rouge), à sa vraie largeur.
private struct StepDragPreview: View {
    let row: MacroStepRow
    let width: CGFloat

    var body: some View {
        MacroStepRowView(row: row, status: nil, current: false, selected: true, onToggle: { _ in })
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(width: width, alignment: .leading)
            .hoverFilled(true)
            .background(Rectangle().fill(Swiss.text))
            .background(Rectangle().fill(Swiss.brandRed).offset(x: 4, y: 4))
            .shadow(color: .black.opacity(0.28), radius: 14, y: 8)
            .padding(24)                          // place pour l'encoche et l'ombre
    }
}

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
        // Style suisse (maquette du 01/11) : numéro, petit carré de la couleur du bloc, verbe en gras et valeur en gris,
        // interrupteur carré ; la ligne choisie est blanche (texte noir).
        HStack(spacing: 10) {
            Text(row.number)
                .font(Swiss.font(12).monospacedDigit())
                .hoverTint(Swiss.gray)
                .frame(minWidth: 24, alignment: .trailing)
            BlockSquare()
            VStack(alignment: .leading, spacing: 2) {
                sentence
                if let note = row.note {
                    Text(note).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                if let reason = failure {
                    Text(reason).font(.system(size: 11)).hoverTint(.red).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            ForEach(row.badges, id: \.self) { badge in
                BadgeCapsule(badge: badge)
            }
            stateIcon
            // Interrupteur carré à droite (style suisse).
            SwissSwitch(isOn: Binding(get: { row.ownEnabled }, set: onToggle), label: String(localized: "Bloc actif"))
                .scaleEffect(0.8)
                .help(row.ownEnabled ? String(localized: "Bloc actif : coupe-le pour le sauter sans le supprimer")
                                     : String(localized: "Bloc sauté : rallume-le pour le réactiver"))
        }
        .padding(.leading, indent)
        .frame(minHeight: 32)
        .opacity(row.enabled ? 1 : 0.45)
        .background(stateBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var sentence: some View {
        if row.type == .comment {
            Text(row.verb).italic().foregroundStyle(.secondary).lineLimit(2)
        } else {
            HStack(spacing: 7) {
                Text(row.verb).font(.system(size: 13.5, weight: .bold)).lineLimit(1).layoutPriority(1)
                if let value = row.value {
                    Text(value)
                        .font(.system(size: 13.5))
                        .hoverTint(Swiss.gray)
                        .lineLimit(1)
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
            Image(systemName: "play.fill").foregroundStyle(Swiss.red).help("En cours")
        } else {
            switch status {
            case .done?:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Fait")
            case .warned?:
                SwissWarningMark(size: 8).help("Fait, avec un avertissement")
            case .failed?:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red).help("Échec")
            case .cancelled?:
                Image(systemName: "stop.circle.fill").foregroundStyle(.orange).help("Arrêté")
            case .running?:
                Image(systemName: "play.fill").foregroundStyle(Swiss.red).help("En cours")
            case nil:
                EmptyView()
            }
        }
    }

    @ViewBuilder private var stateBackground: some View {
        if current {
            Rectangle().fill(Swiss.red.opacity(0.16))
        } else if case .failed? = status {
            Rectangle().fill(Color.red.opacity(0.10))
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
        HStack(spacing: 4) {
            StatusSymbol(name: badge.symbol, size: 10, tint: badge.tint)
            Text(badge.title)
        }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(badge.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Rectangle().fill(badge.tint.opacity(0.13)))
            .lineLimit(1)
            .fixedSize()                                 // jamais replié lettre par lettre
            .help(badge.help)
    }
}

// MARK: - En-tête : nom, état, raccourci

private struct MacroHeader: View {
    @ObservedObject var model: MacroEditorModel
    let onBack: () -> Void

    private var nameBinding: Binding<String> {
        let editor = model
        return Binding(get: { editor.draft?.name ?? "" }, set: { editor.rename($0) })
    }

    private var triggerBinding: Binding<KeyCombo?> {
        let editor = model
        return Binding(get: { editor.trigger }, set: { editor.setTrigger($0) })
    }

    /// Maquette : ← rond, le nom en grand (champ), les touches du raccourci (clic : en taper d'autres), « Enregistrer »
    /// en bleu. Dessous, seulement ce qui demande d'agir (problème, conflit), puis « Enregistrer clics et touches ».
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CreatorBackButton(action: onBack)
                // 06/11 : le nom comme le titre des pages de raccourcis (minuscules + point carré) ; un clic le renomme.
                MacroNameTitle(name: nameBinding)
                    .layoutPriority(1)                         // le nom garde la place, le reste se serre
                CaptureField(id: "macro-trigger-\(model.draft?.id.uuidString ?? "")", role: .trigger, combo: triggerBinding,
                             compact: true)
                    .disabled(model.ephemeral)               // exemple de la mesure : jamais enregistré
                    .fixedSize()
                saveButton
            }
            .frame(minHeight: 52)
            // 06/11 (« tous ces messages-là, tu peux les enlever… les gens verront bien ») : plus de message au-dessus
            // d'« Enregistrer clics et touches » ; ce qui cloche est dit à l'enregistrement (`saveButton`).
            if !model.rows.isEmpty {
                RecordHero(model: model)
            }
        }
    }

    /// Toujours actif (30/10, « le bouton enregistrer ne fonctionne plus ») : chaque changement s'enregistre seul
    /// une demi-seconde après, le bouton restait donc grisé sur « Enregistrée ». Il enregistre ce qui reste et
    /// revient à la liste des macros.
    private var saveButton: some View {
        Button {
            // Un raccourci posé sur une macro pas prête : on prévient avant de revenir (06/11, « un message de
            // prévention »). Sinon, enregistrée sans question (03/11).
            if model.trigger != nil, let warning = model.saveWarning {
                let answer = SwissDialog.run(String(localized: "Ce raccourci ne marchera pas encore"), warning,
                                             buttons: [String(localized: "Enregistrer quand même"),
                                                       String(localized: "Corriger")])
                guard answer == 0 else { return }
            }
            model.commit()
            onBack()
        } label: {
            // Une coche devant (01/11 : « un rectangle blanc, pas très compréhensible ») ; 02/11 : le nom de la macro
            // prenait la place et le mot était écrasé (un carré blanc en hauteur, la coche seule) : le bouton garde sa
            // largeur, en paysage, le mot écrit en entier.
            // 02/11, encore : « un truc horizontal où il y a juste écrit Enregistrer, comme tous les boutons » : le mot
            // seul, en capitales, sans icône.
            Text("Enregistrer")
                .lineLimit(1)
                .fixedSize()
        }
        // 05/11 : blanc sous Papier, comme sous Orange ; sous Noir, accordé aux touches juste à gauche.
        .buttonStyle(KeyLikeButtonStyle())
        .fixedSize()
        .layoutPriority(2)
        .keyboardShortcut("s", modifiers: .command)
        .help("Enregistrer et revenir aux macros (⌘S)")
    }
}

/// Nom de la macro en titre (07/11, vidéo : « le texte se décale… ce n'est pas la même police… le point orange tout le
/// temps, même quand la personne écrit ») : un seul champ, le même au repos et pendant la frappe (Helvetica Neue gras
/// resserré, en minuscules comme les titres des pages), suivi de son point carré à la couleur du thème ; un clic
/// dedans le renomme, rien ne bouge. Entrée ou Échap rendent la main.
private struct MacroNameTitle: View {
    @Binding var name: String

    var body: some View {
        MacroTitleField(name: $name, size: 34, placeholder: String(localized: "Nom de la macro"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: MacroTitleFieldView.height(size: 34))
            .accessibilityLabel(Text("Nom de la macro"))
    }
}

struct MacroTitleField: NSViewRepresentable {
    @Binding var name: String
    let size: CGFloat
    let placeholder: String

    func makeCoordinator() -> Coordinator { Coordinator(name: $name) }

    func makeNSView(context: Context) -> MacroTitleFieldView {
        let view = MacroTitleFieldView(size: size, placeholder: placeholder)
        view.field.delegate = context.coordinator
        view.show(name)
        context.coordinator.view = view
        return view
    }

    func updateNSView(_ view: MacroTitleFieldView, context: Context) {
        context.coordinator.name = $name
        // Pendant la frappe, le champ fait foi ; au repos, il suit le nom (macro ouverte, renommée ailleurs).
        if view.field.currentEditor() == nil { view.show(name) }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var name: Binding<String>
        weak var view: MacroTitleFieldView?

        init(name: Binding<String>) { self.name = name }

        func controlTextDidChange(_ note: Notification) {
            guard let view else { return }
            view.normalizeEditor()
            name.wrappedValue = view.field.stringValue
            view.needsLayout = true
        }

        func controlTextDidEndEditing(_ note: Notification) {
            guard let view else { return }
            view.show(view.field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) || selector == #selector(NSResponder.cancelOperation(_:))
            else { return false }
            control.window?.makeFirstResponder(nil)
            return true
        }
    }
}

/// Le champ du titre et son point carré, posés à la main : le point suit la fin du texte, sur sa ligne de base.
final class MacroTitleFieldView: NSView {
    let field = TitleTextField()
    private let dot = TitleDot()
    private let size: CGFloat
    private let placeholder: String

    /// Hauteur d'une ligne du titre (champ sans cadre).
    static func height(size: CGFloat) -> CGFloat {
        let font = titleFont(size)
        return ceil(font.ascender - font.descender + font.leading) + 4
    }

    static func titleFont(_ size: CGFloat) -> NSFont {
        NSFontManager.shared.font(withFamily: Swiss.fontName, traits: .boldFontMask, weight: 9, size: size)
            ?? NSFont(name: "HelveticaNeue-Bold", size: size) ?? .boldSystemFont(ofSize: size)
    }

    private var font: NSFont { Self.titleFont(size) }
    private var dotSize: CGFloat { (size * 0.19).rounded() }
    private var gap: CGFloat { size * 0.09 }

    func attributes(_ color: NSColor = Swiss.NS.text) -> [NSAttributedString.Key: Any] {
        [.font: font, .kern: Swiss.titleTracking(size), .foregroundColor: color]
    }

    init(size: CGFloat, placeholder: String) {
        self.size = size
        self.placeholder = placeholder.lowercased(with: .current)
        super.init(frame: .zero)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.font = font
        field.textColor = Swiss.NS.text
        field.lineBreakMode = .byClipping
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.allowsEditingTextAttributes = false
        field.toolTip = String(localized: "Clique pour renommer la macro")
        field.placeholderAttributedString = NSAttributedString(string: self.placeholder,
                                                               attributes: attributes(SwissPalette.adaptive(.gray)))
        field.titleAttributes = { [weak self] in self?.attributes() ?? [:] }
        addSubview(field)
        addSubview(dot)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    /// Nom montré au repos : en minuscules, comme les titres.
    func show(_ name: String) {
        let shown = name.lowercased(with: .current)
        let current = field.attributedStringValue
        let styled = current.length == 0 || current.attribute(.kern, at: 0, effectiveRange: nil) != nil
        if field.stringValue != shown || !styled {
            field.attributedStringValue = NSAttributedString(string: shown, attributes: attributes())
        }
        needsLayout = true
    }

    /// Pendant la frappe : en minuscules, même police, même resserrement (le texte ne bouge pas, le curseur non plus).
    func normalizeEditor() {
        guard let editor = field.currentEditor() as? NSTextView, let storage = editor.textStorage else { return }
        let all = NSRange(location: 0, length: storage.length)
        if !editor.hasMarkedText() {
            let lowered = storage.string.lowercased(with: .current)
            if lowered != storage.string, (lowered as NSString).length == storage.length {
                let selection = editor.selectedRanges
                storage.replaceCharacters(in: all, with: lowered)
                editor.selectedRanges = selection
            }
            storage.setAttributes(attributes(), range: NSRange(location: 0, length: storage.length))
        }
        editor.typingAttributes = attributes()
    }

    private var textWidth: CGFloat {
        let text = field.stringValue.isEmpty ? placeholder : field.stringValue
        return ceil(NSAttributedString(string: text, attributes: attributes()).size().width)
    }

    override func layout() {
        super.layout()
        let height = Self.height(size: size)
        // Le champ sans cadre écrit à 2 points de son bord : décalé d'autant, le texte part du même bord que les titres.
        let room = max(0, bounds.width - dotSize - gap)
        let width = min(room, textWidth + 6)
        field.frame = NSRect(x: -2, y: (bounds.height - height) / 2, width: width + 4, height: height)
        let baseline = field.frame.minY + field.firstBaselineOffsetFromTop
        let end = min(textWidth, room - 2)
        dot.frame = NSRect(x: end + gap, y: (baseline - dotSize).rounded(), width: dotSize, height: dotSize)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        dot.needsDisplay = true
    }
}

/// Champ du titre : il prend la main au clic ; le curseur et la police du titre dès qu'il l'a.
final class TitleTextField: NSTextField {
    var titleAttributes: () -> [NSAttributedString.Key: Any] = { [:] }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, let editor = currentEditor() as? NSTextView {
            SwissCaret.style(editor)
            editor.typingAttributes = titleAttributes()
            if let storage = editor.textStorage {
                storage.setAttributes(titleAttributes(), range: NSRange(location: 0, length: storage.length))
            }
            // Le curseur à la fin du nom (pas tout sélectionné) : on écrit à la suite, comme dans un titre.
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
        }
        return accepted
    }
}

/// Point carré du titre, à la couleur du thème (rouge ; blanc sous Orange).
final class TitleDot: NSView {
    override func draw(_ dirtyRect: NSRect) {
        SwissPalette.adaptive(.red).setFill()
        bounds.fill()
    }
}

/// ← carré (style suisse) : retour aux raccourcis et aux macros (⌘[).
private struct CreatorBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Carré du début à la fin (01/11 : le passage du rond au carré au survol était bizarre) ; au survol, blanc
            // plein et flèche noire, comme les autres boutons.
            Image(systemName: "chevron.backward")
                .font(.system(size: 14, weight: .bold))
                .frame(width: 34, height: 34)
                .overlay(Rectangle().strokeBorder(Swiss.text, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuHover(tint: Swiss.text, cornerRadius: 0)
        .keyboardShortcut("[", modifiers: .command)
        .help("Revenir aux raccourcis et aux macros (⌘[)")
        .accessibilityLabel("Retour")
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
            StatusSymbol(name: symbol, size: 14, tint: tint ?? .secondary)
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
        .glassSurface(Rectangle(), tint: tint)
        .accessibilityElement(children: .contain)
    }
}
