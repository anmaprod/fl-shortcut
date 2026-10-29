// Fenêtre « Raccourcis », à l'identique de la maquette du 28/10 (demande du 29/10) : fond noir, barre de gauche dans
// une plaque claire (boutons de la fenêtre en haut, recherche, groupes de pages aux icônes colorées), en-tête de la
// page (titre, capsule du compte), raccourcis en cartes titrées par groupe (Outils, Sélection, Zoom…) sur deux
// colonnes, une ligne par raccourci avec ↺ puis sa touche (cliquable). Plus de barre d'outils, de menu ⋯ ni de « + »
// sur les pages de raccourcis (29/10 : « le reste ça part ») ; la recherche par une touche reste. Statut et
// avertissements flottants seulement quand il faut agir. Aucune animation infinie, aucun flou dans les listes.
// Audit : REL-06 / PROTOCOL.md §5 (statut du lien), audit 04 §8.2 (actions grisées, « Disponible à partir de
//         FL X »), audit 05 §4.2-4.4 (conflits, touche seule laissée à FL pendant une saisie, pause visible, noms de touches en clair,
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
    /// Bibliothèque des macros en blocs (MacroLibraryView.swift).
    case macros
    /// Partages des membres, avec un compte (CommunityView.swift).
    case community
    /// Questions fréquentes et « Écrire à l'équipe » (HelpView.swift).
    case help
    /// Compte et sauvegarde en ligne des raccourcis et des macros (AccountView.swift).
    case account

    var symbol: String {
        switch self {
        case .section(let s): return s.symbol
        case .custom: return "star"
        case .macros: return "wand.and.stars"
        case .community: return "person.2"
        case .help: return "questionmark.circle"
        case .account: return "person.crop.circle"
        }
    }

    var tint: Color {
        switch self {
        case .section(let s): return s.tint
        case .custom: return .pink
        case .macros: return .purple
        // Communauté : une couleur à elle (ambre, prise par aucune autre rubrique) ; Mon compte et Aide, groupés,
        // partagent la leur.
        case .community: return Color(red: 0.96, green: 0.68, blue: 0.0)
        case .help, .account: return .teal
        }
    }
}

extension FLSection {
    /// Couleur de la rubrique (icône, lavis de la page) : couche de contenu, jamais sur le verre.
    var tint: Color {
        switch self {
        case .general: return .gray
        case .transport: return .red
        case .patterns: return .orange
        case .playlist: return .green
        case .pianoRoll: return .purple
        case .channelRack: return .teal
        case .mixer: return .blue
        case .browser: return .indigo
        }
    }
}

extension SidebarItem {
    /// Nom de la page noté pour la reprise après « Quitter et rouvrir » (AppResume) : « section:mixer », « macros »…
    var resumeKey: String {
        switch self {
        case .section(let s): return "section:" + s.rawValue
        case .custom: return "custom"
        case .macros: return "macros"
        case .community: return "community"
        case .help: return "help"
        case .account: return "account"
        }
    }

    init?(resumeKey key: String) {
        let prefix = "section:"
        if key.hasPrefix(prefix) {
            guard let s = FLSection(rawValue: String(key.dropFirst(prefix.count))) else { return nil }
            self = .section(s)
            return
        }
        switch key {
        case "custom": self = .custom
        case "macros": self = .macros
        case "community": self = .community
        case "help": self = .help
        case "account": self = .account
        default: return nil
        }
    }
}

/// Les raccourcis, demandés hors de la fenêtre principale (« Modifier les raccourcis… » du menu de l'icône).
final class ShortcutsLink: ObservableObject {
    static let shared = ShortcutsLink()
    @Published var pending = false

    func show() { pending = true }

    /// Pure (testée) : la page de raccourcis à montrer : celle déjà ouverte si c'en est une, sinon Général.
    static func page(from shown: SidebarItem?) -> SidebarItem {
        switch shown {
        case .section?, .custom?: return shown ?? .section(.general)
        default: return .section(.general)
        }
    }
}

/// Textes de l'en-tête de page.
enum PageSummary {
    /// Résumé des raccourcis de « Mes raccourcis ».
    static let custom = String(localized: "Chaque raccourci que tu changes arrive ici, avec ceux que tu crées. Les macros ont leur page.")

    /// « 34 raccourcis · 3 modifiés ».
    static func count(_ count: Int, modified: Int) -> String {
        let total = count == 1 ? String(localized: "1 raccourci") : String(localized: "\(count) raccourcis")
        guard modified > 0 else { return total }
        return total + " · " + (modified == 1 ? String(localized: "1 modifié") : String(localized: "\(modified) modifiés"))
    }
}

private extension View {
    /// Page en sections arrondies (cartes), comme Réglages Système ; posées sur le fond translucide en verre.
    func cardList() -> some View {
        glassListBackground()
    }
}

/// Contenu d'une page : List paresseuse (seules les lignes visibles sont construites), sections en cartes par
/// `cardRow`. Le Form groupé construisait toutes les lignes : 228 Mo pour la recherche « e », 58 Mo en List.
struct PageContainer<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        List { content }.listStyle(.inset)
    }
}

extension View {
    /// Ligne de la barre latérale (maquette validée le 28/10) : la page choisie dans une pastille bleue, titre blanc
    /// en gras ; les autres s'allument de leur couleur au survol, comme une ligne du menu de la barre des menus. Un
    /// clic la choisit : plus de sélection de la liste, que macOS dessinait en gris tant que la liste n'avait pas le
    /// clavier (vidéo du 29/10).
    func sidebarRow(_ tint: Color, selected: Bool, choose: @escaping () -> Void) -> some View {
        modifier(SidebarRowModifier(tint: tint, selected: selected, choose: choose))
    }
}

private struct SidebarRowModifier: ViewModifier {
    let tint: Color
    let selected: Bool
    let choose: () -> Void

    func body(content: Content) -> some View {
        content
            .hoverTint(selected ? Color.white : Color.primary)
            .fontWeight(selected ? .semibold : nil)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .menuHover(tint: tint, cornerRadius: 9, enabled: !selected)
            .onTapGesture(perform: choose)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { choose() }
    }
}

/// Lignes d'une carte, chacune à sa place (première, intérieure, dernière). `trailing` : lignes posées après
/// (bouton « Nouveau… »), comptées pour arrondir la bonne. Au survol, chaque ligne s'allume de la couleur de sa
/// page (`tint`), comme une ligne du menu de la barre des menus.
private struct CardRows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let tint: Color
    var trailing = 0
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            row(item).cardRow(.position(index: index, count: items.count + trailing), hover: tint)
        }
    }
}

/// Largeur de la page, lue sans rien redessiner tant qu'elle ne change pas.
private struct WidthReader: View {
    let report: (CGFloat) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { report(proxy.size.width) }
                .onChange(of: proxy.size.width) { width in report(width) }
        }
    }
}

typealias CatalogData = (rows: [CatalogRow], others: [Remap])

struct EditorView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var status: AppStatus
    private var link: MIDILink { MIDILink.shared }

    @State private var selection: SidebarItem? = .section(.general)
    @State private var query = ""
    /// Augmenté par ⌘F : la recherche prend la main.
    @State private var searchFocusSerial = 0
    @State private var editing: Remap? = nil
    @State private var editingIsNew = false
    @State private var toast: ToastMessage? = nil
    @State private var editingRow: CatalogRow? = nil
    /// Annonce affichée en tête de la fiche quand on doit choisir une nouvelle touche pour un autre raccourci.
    @State private var editNotice: String? = nil
    @Namespace private var glassNS
    /// Page assez large pour deux colonnes de raccourcis (changé seulement quand on passe le seuil).
    @State private var twoColumns = false
    /// Largeur de page à partir de laquelle les cartes passent sur deux colonnes (cartes d'au moins 300 points).
    static let twoColumnWidth: CGFloat = 660

    private var columnCount: Int { twoColumns ? 2 : 1 }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    /// Créateur de macros affiché dans la fenêtre, comme un dossier ouvert dans le Finder (nil : les raccourcis).
    /// Le modèle n'existe que pendant qu'il est affiché.
    @State private var macroEditor: MacroEditorModel?
    @ObservedObject private var creatorLink = MacroCreatorLink.shared
    /// Page Communauté : le « + » (partager) n'apparaît qu'une fois connecté.
    @ObservedObject private var community = CommunityStore.shared
    @ObservedObject private var backup = AccountBackup.shared
    /// Guide : montré une fois à la première ouverture, puis à la demande (page Aide, barre des menus).
    @AppStorage("guideSeen") private var guideSeen = false
    @ObservedObject private var guideLink = GuideLink.shared
    @ObservedObject private var helpLink = HelpLink.shared
    @ObservedObject private var macrosLink = MacrosLink.shared
    @ObservedObject private var shortcutsLink = ShortcutsLink.shared
    @ObservedObject private var accountLink = AccountLink.shared
    @State private var showGuide = false
    @State private var guidePage = 0
    /// Recherche avec un raccourci : la touche appuyée (la recherche affiche son nom, « ⌥⇧A »).
    @State private var keySearch: KeyCombo?
    @ObservedObject private var recorder = Recorder.shared
    private static let keySearchID = "recherche-raccourci"

    /// Entre dans le créateur sur cette macro (la fenêtre reste la même ; la flèche ← y ramène).
    private func openCreator(_ id: UUID?) {
        MacroCreatorLink.shared.open(id)
    }

    var body: some View {
        // Bascule sans animation (la page qui part s'en va tout de suite), puis celle qui arrive apparaît en fondu.
        ZStack {
            if let editor = macroEditor {
                MacroCreatorView(model: editor, onBack: { leaveCreator(editor) })
                    .environmentObject(store)
                    .windowReveal()
                    .zIndex(1)
            } else {
                shortcuts
                    .windowReveal()
                    .zIndex(0)
            }
        }
        .onChange(of: creatorLink.request) { request in
            guard request != nil, macroEditor == nil else { return }    // déjà affiché : il passe à cette macro
            enterCreator()
        }
        .onChange(of: creatorLink.closeSerial) { _ in closeCreator() }
        // Fenêtre fermée pendant le créateur : brouillon enregistré, modèle lâché (rien ne reste en mémoire).
        .onDisappear { closeCreator() }
        // Reprise après « Quitter et rouvrir » : la fenêtre, sa page et la macro ouverte sont notées à la fermeture.
        .background(WindowReader { window in
            AppResume.shared.editorWindow = window
            MainWindowChrome.apply(to: window)
        })
        .onChange(of: selection) { AppResume.shared.page = $0 }
        .sheet(isPresented: $showGuide, onDismiss: { guideSeen = true }) {
            GuideSheet(initialPage: guidePage) { showGuide = false }
        }
        .onAppear {
            resumeIfAsked()
            AppResume.shared.page = selection
            showGuideIfNeeded()
            showHelpIfAsked()
            showMacrosIfAsked()
            showShortcutsIfAsked()
            showAccountIfAsked()
            Task { await backup.refreshIfStale() }       // changé depuis un autre Mac ?
        }
        // Ce Mac et le compte ont chacun leurs changements : la page Mon compte montre le choix.
        .onChange(of: backup.conflict?.id) { id in
            guard id != nil, macroEditor == nil else { return }
            query = ""
            selection = .account
        }
        .onChange(of: guideLink.pending) { _ in showGuideIfNeeded() }
        .onChange(of: helpLink.pending) { _ in showHelpIfAsked() }
        .onChange(of: macrosLink.pending) { _ in showMacrosIfAsked() }
        .onChange(of: shortcutsLink.pending) { _ in showShortcutsIfAsked() }
        .onChange(of: accountLink.pending) { _ in showAccountIfAsked() }
        .onReceive(DebugSnapshot.publisher(DebugSnapshot.guide)) { note in
            // Mode capture : « 0 » à « 4 », la page du guide ; autre chose, le ferme. « 1 lent » (guide ouvert) :
            // changée par le guide lui-même, au ralenti (GuideView).
            let words = (note.object as? String ?? "").split(separator: " ")
            if words.contains("lent"), showGuide { return }
            if let n = words.first.flatMap({ Int($0) }) {
                DebugSnapshot.slowMotion = 1
                guidePage = max(0, min(n, GuideContent.count - 1))
                showGuide = true
            } else {
                showGuide = false
            }
        }
    }

    /// Relancée par « Quitter et rouvrir » (ou juste après avoir quitté) : la page et la macro d'avant reviennent.
    private func resumeIfAsked() {
        guard let resume = AppResume.shared.takeEditor() else { return }
        if let page = resume.page { selection = page }
        if let id = resume.macro, store.library.doc(id) != nil {
            MacroCreatorLink.shared.open(id, isNew: resume.isNew)
            if macroEditor == nil { enterCreator() }
        }
    }

    /// Une page demandée hors de la fenêtre (menu de l'icône, désinstallation…) : elle s'affiche toujours, même si la
    /// fenêtre était ouverte ailleurs (retour de l'utilisateur, 25/10 : « Modifier les raccourcis… » laissait la
    /// page Macros, et « c'est tous les menus dans l'icône ») : créateur refermé (brouillon gardé), recherche finie,
    /// fiche d'un raccourci fermée.
    private func go(to page: SidebarItem) {
        if macroEditor != nil { closeCreator() }
        endSearch()
        editing = nil
        editingRow = nil
        selection = page
    }

    /// Page Mon compte demandée hors de la fenêtre (désinstallation : « Me connecter pour les sauvegarder d'abord »).
    private func showAccountIfAsked() {
        guard accountLink.pending else { return }
        accountLink.pending = false
        go(to: .account)
    }

    /// Page Macros demandée depuis le menu de l'icône.
    private func showMacrosIfAsked() {
        guard macrosLink.pending else { return }
        macrosLink.pending = false
        go(to: .macros)
    }

    /// « Modifier les raccourcis… » du menu de l'icône : une page de raccourcis (celle déjà ouverte si c'en est une).
    private func showShortcutsIfAsked() {
        guard shortcutsLink.pending else { return }
        shortcutsLink.pending = false
        go(to: ShortcutsLink.page(from: macroEditor == nil ? selection : nil))
    }

    /// Page Aide demandée depuis le menu de l'icône (« Signaler ce problème… ») ou la barre des menus.
    private func showHelpIfAsked() {
        guard helpLink.pending else { return }
        helpLink.pending = false
        go(to: .help)
    }

    /// Guide demandé (page Aide, barre des menus), ou jamais vu : première ouverture (sauf en mode capture, où la
    /// mesure de la CI l'ouvre elle-même).
    private func showGuideIfNeeded() {
        let asked = guideLink.pending
        guard asked || (!guideSeen && !DebugSnapshot.enabled) else { return }
        guideLink.pending = false
        guidePage = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showGuide = true }
    }

    private func enterCreator() {
        editing = nil
        editingRow = nil
        let editor = MacroEditorModel(store: store)
        // Macro chargée et palette prête avant l'animation : le créateur arrive rempli, rien n'apparaît en route.
        editor.handle(creatorLink.request)
        _ = editor.paletteItems
        macroEditor = editor
        AppResume.shared.creator = editor
    }

    /// Flèche ← : macro neuve → l'enregistrer ou la supprimer ; macro modifiée → enregistrer ou annuler les
    /// modifications ; sinon retour direct. « Annuler » / « Rester » : on reste dans le créateur.
    private func leaveCreator(_ editor: MacroEditorModel) {
        switch editor.leaveCheck() {
        case .close:
            break
        case .discardEmpty:
            editor.discardNew()
        case .askNew(let name):
            let shown = name.displaySafe(max: 40)
            switch Dialogs.choose(String(localized: "Enregistrer « \(shown) » ?"),
                                  String(localized: "Si tu ne l'enregistres pas, cette nouvelle macro est supprimée."),
                                  [String(localized: "Enregistrer"), String(localized: "Supprimer"), String(localized: "Annuler")],
                                  destructive: 1) {
            case 0:
                editor.saveNow()
            case 1:
                editor.discardNew()
                show(String(localized: "« \(shown) » supprimée"))
            default:
                return
            }
        case .askChanges(let name):
            switch Dialogs.choose(String(localized: "Enregistrer les modifications de « \(name.displaySafe(max: 40)) » ?"),
                                  String(localized: "Sinon, la macro revient telle qu'elle était quand tu l'as ouverte."),
                                  [String(localized: "Enregistrer"), String(localized: "Annuler les modifications"),
                                   String(localized: "Rester")], destructive: 1) {
            case 0: editor.saveNow()
            case 1: editor.revertChanges()
            default: return
            }
        }
        closeCreator()
    }

    private func closeCreator() {
        guard let editor = macroEditor else { return }
        let id = editor.draft?.id
        editor.close()
        // → des raccourcis : retour dans cette macro, si elle existe toujours (pas supprimée au retour).
        MacroCreatorLink.shared.lastClosedID = id.flatMap { id in store.library.macros.contains { $0.id == id } ? id : nil }
        CreatorPresence.detach()
        macroEditor = nil
        AppResume.shared.creator = nil
        selection = .macros
        CreatorPresence.releaseMemory()
    }

    /// Largeur de la barre de gauche (maquette : 252 points).
    static let sidebarWidth: CGFloat = 252

    /// Les raccourcis (maquette du 28/10, « à l'identique » le 29/10) : la barre de gauche dans sa plaque claire, puis
    /// la page choisie (en-tête : titre et capsule du compte ; dessous, ses cartes), sur le fond noir de la fenêtre.
    private var shortcuts: some View {
        let data = store.catalogRows()
        return HStack(spacing: 0) {
            sidebar(data)
            VStack(alignment: .leading, spacing: 6) {
                pageHeader
                detail(data)
            }
            .padding(.top, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Appearance.windowColor)
        // Sous la barre de titre transparente : la plaque de gauche monte jusqu'en haut, les boutons fermer /
        // réduire / agrandir y sont posés (MainWindowChrome).
        .ignoresSafeArea()
        // ⌘F : la recherche prend la main (la garde la lui laisse jusqu'au premier clic ailleurs).
        .background {
            Button("Rechercher") { searchFocusSerial += 1 }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        // Titre de la fenêtre (menu Fenêtre, VoiceOver) ; jamais affiché dans la barre de titre.
        .navigationTitle(title)
        // Active seulement après un clic dedans (ou ⌘F) : taper ailleurs n'y écrit plus rien ; un clic ailleurs, dans
        // l'app ou dehors, la lui reprend.
        .background(SearchFocusGuard())
        // Le texte de la recherche n'est plus le nom du raccourci appuyé : recherche ordinaire.
        .onChange(of: query) { newValue in
            if let combo = keySearch, newValue.trimmingCharacters(in: .whitespaces) != combo.display { keySearch = nil }
        }
        // Une page est toujours choisie.
        .onChange(of: selection) { newValue in
            if newValue == nil { selection = .section(.general) }
        }
        .onReceive(DebugSnapshot.publisher(DebugSnapshot.select)) { note in
            // « mixer lent » : le changement de page au ralenti (10 fois), photographié en route.
            let words = (note.object as? String ?? "").split(separator: " ")
            DebugSnapshot.slowMotion = words.contains("lent") ? 10 : 1
            let name = words.first.map(String.init) ?? ""
            selection = FLSection(rawValue: name).map(SidebarItem.section)
                ?? (name == "custom" ? .custom : name == "macros" ? .macros : name == "community" ? .community
                    : name == "aide" ? .help : name == "compte" ? .account : selection)
        }
        .onReceive(DebugSnapshot.publisher(DebugSnapshot.search)) { note in
            query = note.object as? String ?? ""
        }
        .sheet(item: $editing) { remap in
            EditSheet(original: remap, isNew: editingIsNew, openCreator: { id in openCreator(id) }) { message in show(message) }
                .environmentObject(store)
                .environmentObject(status)
                .environmentObject(link)
        }
    }

    /// En-tête de la page (maquette) : le titre en gras à gauche ; à droite, la capsule : → sur la page Macros (retour
    /// dans la dernière macro quittée), « + » sur les pages Macros et Communauté, puis Mon compte.
    private var pageHeader: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            HeaderCapsule {
                if onMacrosPage, let last = creatorLink.lastClosedID {
                    HeaderIconButton(symbol: "chevron.forward",
                                     help: String(localized: "Revenir dans la dernière macro quittée (⌘])")) {
                        openCreator(last)
                    }
                    .keyboardShortcut("]", modifiers: .command)
                }
                if showsNewButton { newButton }
                HeaderIconButton(symbol: "person.crop.circle", help: String(localized: "Mon compte")) { choose(.account) }
            }
        }
        .frame(minHeight: 52)
        .padding(.horizontal, 26)
    }

    private var title: String {
        if !trimmedQuery.isEmpty { return String(localized: "Recherche") }
        switch selection ?? .section(.general) {
        case .section(let s): return s.title
        case .custom: return String(localized: "Mes raccourcis")
        case .macros: return String(localized: "Macros")
        case .community: return String(localized: "Communauté")
        case .help: return String(localized: "Aide")
        case .account: return String(localized: "Mon compte")
        }
    }

    // MARK: Barre latérale

    /// Pendant une recherche, aucune page n'est choisie dans la barre latérale (la recherche les couvre toutes) : un
    /// clic sur une page, même celle d'avant, quitte la recherche et l'ouvre (retour de l'utilisateur, vidéo : Mixer
    /// cliqué pendant une recherche, rien ne changeait).
    private var sidebarSelection: Binding<SidebarItem?> {
        Binding(get: { trimmedQuery.isEmpty ? selection : nil },
                set: { newValue in
                    guard let newValue else {
                        if trimmedQuery.isEmpty { selection = nil }
                        return
                    }
                    if !trimmedQuery.isEmpty { endSearch() }
                    selection = newValue
                })
    }

    /// Fin de la recherche (texte vidé, attente d'un raccourci arrêtée) : la page choisie revient.
    private func endSearch() {
        if recorder.activeID == Self.keySearchID { recorder.stop() }
        keySearch = nil
        query = ""
    }

    /// Page choisie dans la barre latérale (aucune pendant une recherche).
    private func isShown(_ item: SidebarItem) -> Bool { trimmedQuery.isEmpty && selection == item }

    /// Clic sur une ligne de la barre latérale : comme une sélection de la liste (quitte la recherche s'il y en a une).
    private func choose(_ item: SidebarItem) {
        sidebarSelection.wrappedValue = item
    }

    /// Barre de gauche (maquette) : plaque claire arrondie, les boutons de la fenêtre en haut, la recherche, puis les
    /// groupes de pages, chacun sous son titre gris. Plus de compteurs (« rien d'inutile ») ; la page choisie est une
    /// pastille bleue (sidebarRow).
    private func sidebar(_ data: CatalogData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Place des boutons fermer / réduire / agrandir de la fenêtre.
            Color.clear.frame(height: 12)
            searchBar
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    SidebarGroup(Text("FL Studio")) {
                        ForEach(FLSection.allCases) { section in
                            SidebarLabel(title: Text(section.title), symbol: section.symbol, tint: section.tint)
                                .sidebarRow(section.tint, selected: isShown(.section(section))) { choose(.section(section)) }
                                .help(section.subtitle)
                        }
                    }
                    SidebarGroup(Text("Automatiser")) {
                        MacroSidebarRow(selected: isShown(.macros)) { choose(.macros) }
                    }
                    SidebarGroup(Text("Personnalisé")) {
                        sidebarItem(.custom, Text("Mes raccourcis"))
                    }
                    SidebarGroup(Text("Partager")) {
                        sidebarItem(.community, Text("Communauté"))
                            .help(CommunityText.subtitle)
                    }
                    SidebarGroup(Text("Compte et aide")) {
                        sidebarItem(.account, Text("Mon compte"))
                            .overlay(alignment: .trailing) {
                                // Ce Mac et le compte ont chacun leurs changements : la page Mon compte montre le choix.
                                if backup.conflict != nil {
                                    Text(verbatim: "!")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.white)
                                        .frame(width: 18, height: 18)
                                        .background(Circle().fill(Color.orange))
                                        .padding(.trailing, 8)
                                        .allowsHitTesting(false)
                                }
                            }
                            .help(AccountText.subtitle)
                        sidebarItem(.help, Text("Aide"))
                            .help("Questions fréquentes, et écrire à l'équipe")
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(width: Self.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MockPlate(cornerRadius: 19, top: 0.10, bottom: 0.04, border: 0.16))
    }

    private func sidebarItem(_ item: SidebarItem, _ title: Text) -> some View {
        SidebarLabel(title: title, symbol: item.symbol, tint: item.tint)
            .sidebarRow(item.tint, selected: isShown(item)) { choose(item) }
    }

    /// Recherche (maquette : capsule claire en haut de la barre de gauche) ; à droite, chercher avec le raccourci qu'on
    /// connaît plutôt que son nom.
    private var searchBar: some View {
        HStack(spacing: 4) {
            SidebarSearchField(text: $query, prompt: String(localized: "Rechercher"), focusSerial: searchFocusSerial)
                .frame(maxWidth: .infinity)
            keySearchButton
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(height: 34)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: Détail

    private func detail(_ data: CatalogData) -> some View {
        Group {
            if !trimmedQuery.isEmpty {
                searchResults(data)
            } else {
                switch selection ?? .section(.general) {
                case .section(let s): sectionList(s, rows: data.rows, mine: data.others.filter { $0.belongs(to: s) })
                case .custom: customList(data)
                case .macros: MacroLibraryPage(library: store.library, open: { id in openCreator(id) }, toast: { show($0) })
                case .community: CommunityPage(community: CommunityStore.shared, toast: { show($0) })
                case .help: HelpPage(community: CommunityStore.shared, showGuide: { GuideLink.shared.show() })
                case .account: AccountPage(community: CommunityStore.shared, backup: AccountBackup.shared)
                }
            }
        }
        // Le titre de la page est dans l'en-tête de la fenêtre : les pages ne le répètent pas (PageHeader).
        .environment(\.pageTitleShown, false)
        // Nouvelle liste (et retour en haut) à chaque section, affichée d'un coup (aucune animation).
        .pageSwitch(trimmedQuery.isEmpty ? selection : nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WidthReader { width in
            let wide = width >= Self.twoColumnWidth
            if wide != twoColumns { twoColumns = wide }
        })
        // Façon macOS 26 : la liste défile SOUS des éléments en verre qui flottent (avertissements en haut,
        // notification et statut en bas). Peu de surfaces, regroupées : le système les dessine ensemble.
        // macOS 26 : barres flottantes (safeAreaBar) : la liste défile dessous avec l'effet de bord, et sa dernière
        // ligne n'est jamais cachée par la pastille.
        .floatingBar(.top) { NoticeStack(items: notices) }
        .floatingBar(.bottom) {
            GlassGroup(spacing: 8) {
                VStack(spacing: 8) {
                    if let toast {
                        ToastView(message: toast) { self.toast = nil }
                            .glassID("toast", in: glassNS)         // la notification naît de la pastille
                            .transition(Motion.transition(.opacity))
                            .id(toast.id)
                    }
                    StatusBar(store: store, status: status, link: link, fl: FLMonitor.shared)
                        .glassID("status", in: glassNS)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            .motion(Motion.smooth, value: toast)
        }
        // La page ne réclame jamais plus de hauteur que la fenêtre. Sans ce cadre, sa hauteur minimale était prise à
        // sa largeur minimale, où le texte des avertissements se replie presque mot par mot (994 points sur la page
        // Général) : les deux colonnes devenaient plus hautes que la fenêtre, centrées, et le haut de la barre
        // latérale (recherche, « FL Studio ») passait sous la barre de titre. Largeur minimale réaliste en plus.
        .frame(minWidth: 480, minHeight: 0, maxHeight: .infinity)
        // Plus de lavis de couleur sous le verre (28/10, « garder que le Liquid Glass, pas de fond »).
        .sheet(item: $editingRow) { row in
            CatalogEditSheet(row: row, notice: editNotice) { message, followUp in
                show(message)
                // La touche a été reprise à un autre raccourci : on propose aussitôt de lui en choisir une autre.
                if let followUp {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        guard let next = store.catalogRows().rows.first(where: { $0.id == followUp }) else { return }
                        editNotice = String(localized: "« \(row.entry.title) » utilise maintenant cette touche. ")
                            + String(localized: "Choisis une nouvelle touche pour « \(next.entry.title) ».")
                        editingRow = next
                    }
                }
            }
            .environmentObject(store)
            .environmentObject(link)
        }
    }

    /// Une carte de page : un groupe de raccourcis de FL, les actions en plus, ou tes raccourcis.
    private struct PageCard: Identifiable {
        enum Lines {
            case catalog([CatalogRow])
            case custom([Remap])
        }

        let id: String
        let title: String
        let lines: Lines

        var count: Int {
            switch lines {
            case .catalog(let rows): return rows.count
            case .custom(let remaps): return remaps.count
            }
        }
    }

    /// Une section (maquette) : une carte par groupe de raccourcis de FL (Outils, Sélection, Zoom…), les actions en
    /// plus, puis tes raccourcis ajoutés sur cette page.
    private func sectionList(_ section: FLSection, rows: [CatalogRow], mine custom: [Remap]) -> some View {
        let mine = rows.filter { $0.entry.section == section }
        var cards = CatalogGroups.cards(for: section, rows: mine.filter { $0.entry.isNative }, entry: \.entry)
            .map { PageCard(id: "groupe-" + $0.title, title: $0.title, lines: .catalog($0.rows)) }
        let extras = mine.filter { !$0.entry.isNative }
        if !extras.isEmpty {
            cards.append(PageCard(id: "actions", title: String(localized: "Actions en plus"), lines: .catalog(extras)))
        }
        if !custom.isEmpty {
            cards.append(PageCard(id: "tes-raccourcis", title: String(localized: "Tes raccourcis sur cette page"),
                                  lines: .custom(custom)))
        }
        return cardPage(cards, tint: section.tint)
            .id(section)                                 // nouvelle section : la page repart du haut
    }

    /// Page en cartes titrées (maquette), sur deux colonnes quand elle est large ; elle défile sous l'en-tête.
    private func cardPage(_ cards: [PageCard], tint: Color) -> some View {
        ScrollView(.vertical) {
            CardMasonry(cards: cards, columns: columnCount, size: \.count) { card in
                pageCard(card, tint: tint)
            }
            .padding(.horizontal, 26)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
    }

    @ViewBuilder private func pageCard(_ card: PageCard, tint: Color) -> some View {
        switch card.lines {
        case .catalog(let rows):
            TitledCard(title: card.title, items: rows, tint: tint) { catalogRow($0) }
        case .custom(let remaps):
            TitledCard(title: card.title, items: remaps, tint: tint) { customRow($0) }
        }
    }

    /// Recherche : toutes les sections, regroupées par section. Avec un raccourci appuyé (bouton clavier) : ce qui se
    /// lance sur ces touches, ou les portait dans FL.
    private func searchResults(_ data: CatalogData) -> some View {
        let q = trimmedQuery
        let combo = keySearch.flatMap { $0.display == q ? $0 : nil }
        let rows = data.rows.filter { row in
            if let combo { return KeySearch.matches(row, combo) }
            return [row.entry.title, row.entry.detail, row.current?.display ?? "", row.entry.section.title]
                .joined(separator: " ").localizedCaseInsensitiveContains(q)
        }
        let others = data.others.filter { r in
            if let combo { return KeySearch.matches(r, combo) }
            return [r.title, r.subtitle, r.trigger?.display ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(q)
        }
        let sections = FLSection.allCases.filter { s in rows.contains { $0.entry.section == s } }
        return Group {
            if rows.isEmpty && others.isEmpty {
                if let combo {
                    EmptyState(symbol: "keyboard", title: String(localized: "Aucun raccourci"),
                               text: String(localized: "Rien n'utilise \(combo.display) : ces touches sont libres."))
                } else {
                    EmptyState(symbol: "magnifyingglass", title: String(localized: "Aucun résultat"),
                               text: String(localized: "Aucun raccourci ne correspond à « \(q) »."))
                }
            } else {
                PageContainer {
                    ForEach(sections) { s in
                        Section {
                            CardRows(items: rows.filter { $0.entry.section == s }, tint: s.tint) { catalogRow($0) }
                        } header: {
                            SectionHeader(symbol: s.symbol, tint: s.tint, title: s.title)
                        }
                    }
                    if !others.isEmpty {
                        Section {
                            CardRows(items: others, tint: SidebarItem.custom.tint) { customRow($0) }
                        } header: {
                            SectionHeader(symbol: SidebarItem.custom.symbol, tint: SidebarItem.custom.tint,
                                          title: String(localized: "Mes raccourcis"))
                        }
                    }
                }
                .cardList()
            }
        }
    }

    /// « Mes raccourcis » : les raccourcis de FL que tu as changés (une carte par page), puis ceux que tu as créés ou
    /// importés. Jamais les macros (page Macros) ni les touches de départ.
    private func customList(_ data: CatalogData) -> some View {
        let changed = MyShortcuts.changed(data.rows)
        let created = MyShortcuts.created(data.others, starters: store.freshRemaps())
        var cards = FLSection.allCases.compactMap { s -> PageCard? in
            let mine = changed.filter { $0.entry.section == s }
            return mine.isEmpty ? nil : PageCard(id: "page-" + s.rawValue, title: s.title, lines: .catalog(mine))
        }
        if !created.isEmpty {
            cards.append(PageCard(id: "crees", title: String(localized: "Créés par toi"), lines: .custom(created)))
        }
        return Group {
            if cards.isEmpty {
                EmptyState(symbol: SidebarItem.custom.symbol, title: String(localized: "Aucun raccourci changé"),
                           text: PageSummary.custom)
            } else {
                cardPage(cards, tint: SidebarItem.custom.tint)
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
        if recorder.activeID == Self.keySearchID {
            out.append(NoticeItem(id: "keysearch", symbol: "keyboard", tint: .accentColor,
                                  text: String(localized: "Appuie sur le raccourci que tu connais : la recherche montre ce qu'il fait."),
                                  button: String(localized: "Annuler"), action: { Recorder.shared.stop() }))
        } else if recorder.hintID == Self.keySearchID, let hint = recorder.hint {
            out.append(NoticeItem(id: "keysearch-hint", symbol: "keyboard", tint: .orange, text: hint,
                                  button: String(localized: "Réessayer"), action: { startKeySearch() }))
        }
        if !status.accessibilityOK {
            out.append(NoticeItem(id: "ax", symbol: "exclamationmark.triangle.fill", tint: .orange,
                                  text: String(localized: "FL Shortcuts n'a pas accès au clavier : tes raccourcis sont inactifs."),
                                  button: String(localized: "Autoriser…"), action: { AccessibilityGuide.start() }))
        } else if status.staleTCC {
            out.append(NoticeItem(id: "stale", symbol: "exclamationmark.triangle.fill", tint: .orange,
                                  text: String(localized: "Autorisation périmée : retire FL Shortcuts de la liste Accessibilité, puis ajoute-le."),
                                  button: String(localized: "Ouvrir…"), action: { AccessibilityGuide.start() }))
        }
        if status.secureInput {
            out.append(NoticeItem(id: "secure", symbol: "lock.fill", tint: .orange,
                                  text: String(localized: "Saisie sécurisée active dans une autre app : macOS ne transmet plus les touches.")))
        }
        if !AppMode.light, status.scriptState == .modified {
            out.append(NoticeItem(id: "script", symbol: "exclamationmark.shield.fill", tint: .red,
                                  text: String(localized: "Le script FL a été modifié depuis son installation."),
                                  button: String(localized: "Réinstaller"), action: { FLScriptInstaller.installWithAlert() }))
        }
        if let error = store.saveError {
            out.append(NoticeItem(id: "save", symbol: "xmark.octagon.fill", tint: .red, text: error))
        }
        if let warning = store.loadWarning {
            let model = store
            out.append(NoticeItem(id: "load", symbol: "info.circle.fill", tint: .secondary, text: warning,
                                  button: String(localized: "OK"), action: { model.loadWarning = nil }))
        }
        return out
    }

    // MARK: En-tête

    /// Page affichée (pendant une recherche : aucune des pages de la capsule).
    private var page: SidebarItem { trimmedQuery.isEmpty ? (selection ?? .section(.general)) : .custom }
    private var onMacrosPage: Bool { page == .macros }

    /// Bouton clavier dans la recherche : appuie sur un raccourci, la recherche montre ce qu'il fait (pour qui
    /// connaît ses touches mais pas le nom du raccourci). Échap annule.
    private var keySearchButton: some View {
        let listening = recorder.activeID == Self.keySearchID
        return Button {
            if listening { recorder.stop() } else { startKeySearch() }
        } label: {
            Image(systemName: listening ? "keyboard.fill" : "keyboard")
                .font(.system(size: 13))
                .foregroundStyle(listening ? Color.accentColor : Color.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Rechercher avec un raccourci : appuie sur les touches que tu connais")
        .accessibilityLabel("Rechercher avec un raccourci")
        .accessibilityValue(listening ? String(localized: "En attente des touches") : "")
    }

    private func startKeySearch() {
        recorder.start(Self.keySearchID) { event in
            let combo = KeyCombo(keyCode: event.keyCode,
                                 modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
            if !combo.hasModifiers && event.keyCode == 53 { return }          // Échap : annuler
            guard combo.isValidKey else { return }
            keySearch = combo
            query = combo.display
        }
    }

    /// « + » sur la page Macros (nouvelle macro) et sur la page Communauté une fois connecté (partager) ; plus sur les
    /// pages de raccourcis (29/10 : « le reste ça part »).
    private var showsNewButton: Bool {
        page == .macros || (page == .community && community.session != nil)
    }

    private var newButton: some View {
        let current = page
        let help = current == .macros ? String(localized: "Nouvelle macro")
                                      : String(localized: "Partager une macro ou tes raccourcis")
        return HeaderIconButton(symbol: "plus", help: help) {
            switch current {
            case .macros: MacroLibraryPage.newMacro(in: store.library)
            case .community: community.composing = true
            default: break
            }
        }
    }

    // MARK: Actions

    private func reset(_ row: CatalogRow) {
        let before = store.remaps
        store.reset(row)
        show(ToastMessage(text: String(localized: "« \(row.entry.title) » réinitialisé"), undo: { store.remaps = before }))
    }

    private func delete(_ remap: Remap) {
        store.delete(remap.id)
        show(ToastMessage(text: String(localized: "Raccourci supprimé"), undo: { store.upsert(remap) }))
    }

    private func show(_ message: ToastMessage) {
        toast = message
        let id = message.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            if toast?.id == id { toast = nil }
        }
    }

    private func show(_ text: String) { show(ToastMessage(text: text, undo: nil)) }
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

/// Avertissements flottants sous la barre d'outils (vides la plupart du temps), sur un même conteneur de verre.
/// Le verre est teinté de la couleur de l'alerte : la teinte porte un sens (WWDC25 219). Le bouton posé dessus
/// est un simple remplissage (jamais de verre sur du verre).
private struct NoticeStack: View {
    let items: [NoticeItem]

    var body: some View {
        if !items.isEmpty {
            GlassGroup(spacing: 6) {
                VStack(spacing: 6) {
                    ForEach(items) { item in
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(item.tint)
                            Text(item.text).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            if let title = item.button, let action = item.action {
                                Button(title, action: action).controlSize(.small).onGlassButton()
                            }
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassSurface(RoundedRectangle(cornerRadius: 18, style: .continuous),
                                      tint: item.tint == Color.secondary ? nil : item.tint)
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

    /// Pastille de verre flottante en bas à gauche (comme les barres flottantes de macOS 26). Une capsule : elle
    /// reste concentrique avec le coin arrondi de la fenêtre. Symbole + couleur : l'état ne repose pas que sur la
    /// couleur.
    /// Rien quand tout va bien (ni « Actif », ni la version de FL : demandé par l'utilisateur) ; seulement ce qui
    /// demande une action ou explique un silence des raccourcis.
    var body: some View {
        if let text {
            pill(text)
        }
    }

    private func pill(_ text: String) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                Text(text).lineLimit(1)
                if let action {
                    Button(action.label, action: action.run)
                        .buttonStyle(.link)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .glassSurface(Capsule())
            .accessibilityElement(children: .contain)
            Spacer(minLength: 0)
        }
    }

    private var color: Color {
        AppStatusColor.color(enabled: store.enabled, accessibilityOK: status.accessibilityOK, flRunning: fl.running,
                             link: link.status)
    }

    private var symbol: String {
        if !store.enabled { return "pause.circle.fill" }
        if !status.accessibilityOK { return "exclamationmark.triangle.fill" }
        if AppMode.light { return fl.running ? "checkmark.circle.fill" : "minus.circle.fill" }
        switch link.status {
        case .linked: return "checkmark.circle.fill"
        case .inactive: return "exclamationmark.circle.fill"
        case .flClosed: return "minus.circle.fill"
        }
    }

    static func format(_ ms: Double) -> String {
        ms < 10 ? String(format: "%.1f ms", ms).replacingOccurrences(of: ".", with: ",") : "\(Int(ms.rounded())) ms"
    }

    /// FL fermé : rien non plus (29/10, « le bouton FL n'est pas ouvert, tu peux l'enlever »).
    private var text: String? {
        if !store.enabled { return String(localized: "En pause : FL Studio utilise ses raccourcis d'origine") }
        if !status.accessibilityOK { return String(localized: "Clavier non autorisé") }
        if AppMode.light { return nil }
        switch link.status {
        case .linked, .flClosed: return nil
        case .inactive:
            if !link.snapshot.hasKey { return String(localized: "Lien avec FL Studio non installé") }
            if link.snapshot.incompatibleProtocol != nil { return String(localized: "Script FL d'une autre version") }
            return String(localized: "Lien inactif : quitte et rouvre FL (il relie « FL Shortcuts Link » tout seul)")
        }
    }

    /// L'autorisation du clavier a son bouton dans l'avertissement en haut : pas de doublon ici.
    private var action: (label: String, run: () -> Void)? {
        let model = store
        let midi = link
        guard model.enabled else { return (String(localized: "Reprendre"), { model.enabled = true }) }
        guard status.accessibilityOK, !AppMode.light, midi.status == .inactive else { return nil }
        if !midi.snapshot.hasKey || midi.snapshot.incompatibleProtocol != nil {
            return (String(localized: "Installer…"), { FLScriptInstaller.installWithAlert() })
        }
        return (String(localized: "Tester"), { midi.testLink() })
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
            .accessibilityLabel(String(localized: "Attention : ") + text)
    }
}

/// ↺ : remet la touche d'origine de FL. Seulement sur une touche changée (maquette du 28/10 : rien d'inutile sur les
/// autres lignes) ; son nom reste lu par VoiceOver et sa bulle dit la touche d'origine.
private struct ResetButton: View {
    let enabled: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .accessibilityLabel(String(localized: "Réinitialiser"))
        .buttonStyle(RowActionStyle())
        .fixedSize()
        .disabled(!enabled)
        .help(help)
    }
}

/// Petits boutons au bout des lignes (« Réinitialiser », « Supprimer ») : la même couleur au repos et au survol de
/// la ligne. Le gris « secondaire » de macOS se peint autrement sous l'ombre du survol : il s'éteignait ligne après
/// ligne quand la souris passait vite (retour de l'utilisateur, vidéo : « une sorte de vague »). Couleur simple ici.
private struct RowActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let ink: Color = colorScheme == .dark ? .white : .black
        let strength: Double = colorScheme == .dark ? 0.7 : 0.55
        configuration.label
            .font(.system(size: 11))
            .foregroundStyle(ink.opacity(isEnabled ? (configuration.isPressed ? strength * 0.6 : strength) : strength * 0.5))
            .contentShape(Rectangle())
    }
}

/// Une ligne du catalogue : ce que fait le raccourci, sa touche (cliquable), et « Réinitialiser ».
private struct CatalogRowView: View {
    let row: CatalogRow
    let issues: [ShortcutIssue]
    let onEdit: () -> Void
    let onReset: () -> Void

    private var titleHelp: String {
        row.entry.isNative ? String(localized: "Raccourci d'origine de FL Studio") : row.entry.detail
    }

    var body: some View {
        HStack(spacing: 10) {
            // Une seule ligne : le nom du raccourci (la touche d'origine est dans la bulle de ↺).
            Text(row.entry.title)
                .lineLimit(1)
                .help(titleHelp)
                .layoutPriority(-1)                      // fenêtre étroite : le titre se raccourcit, pas la touche
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
            // ↺ juste avant la touche changée (maquette du 28/10).
            if !row.isDefault {
                ResetButton(enabled: true,
                            help: String(localized: "Revenir à : ") + (row.entry.defaultTrigger?.display ?? String(localized: "aucune touche")),
                            action: onReset)
            }
            Button(action: onEdit) {
                KeyLabel(combo: row.current, accent: !row.isDefault)
            }
            .buttonStyle(.plain)
            .help("Changer la touche")
            .accessibilityLabel("Changer la touche de \(row.entry.title)")
            .accessibilityValue(row.current?.spoken ?? String(localized: "aucune"))
        }
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
        if !remap.enabled { parts.append(String(localized: "désactivé")) }
        guard !parts.isEmpty else { return nil }
        let text = parts.joined(separator: ", ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(remap.title).lineLimit(1)
                if let caption {
                    Text(caption).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .help(remap.subtitle)
            .layoutPriority(-1)
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
            .accessibilityValue(remap.trigger?.spoken ?? String(localized: "aucun raccourci"))

            Button(action: onDelete) {
                Label("Supprimer", systemImage: "trash")
            }
            .buttonStyle(RowActionStyle())
            .fixedSize()
        }
        .padding(.vertical, 4)
        .opacity(remap.enabled ? 1 : 0.55)
        .contextMenu {
            Button("Modifier…", action: onOpen)
            Button(remap.enabled ? String(localized: "Désactiver") : String(localized: "Activer"), action: onToggle)
            Divider()
            Button("Supprimer", role: .destructive, action: onDelete)
        }
    }
}

/// État vide centré (aucun résultat, aucun raccourci personnalisé). Sa seule action est l'action principale :
/// bouton en verre teinté, grand.
private struct EmptyState: View {
    let symbol: String
    let title: String
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        if #available(macOS 14.0, *) {
            ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                Text(text)
            } actions: {
                if let actionTitle, let action {
                    Button(actionTitle, action: action).primaryButton().controlSize(.large)
                }
            }
        } else {
            legacy
        }
    }

    private var legacy: some View {
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

/// En-tête de page (maquette validée le 28/10 : « trop de détails inutiles ») : le titre en gras, seul ; `detail`
/// seulement quand il dit qui est connecté (Compte, Communauté). Le résumé de la page reste dans sa bulle d'aide.
/// `symbol` et `tint` : gardés pour les appels, plus dessinés.
/// Dans la fenêtre principale, le titre est déjà dans l'en-tête de la fenêtre (maquette) : seul `detail` reste.
struct PageHeader: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    var detail: String? = nil
    @Environment(\.pageTitleShown) private var titleShown

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if titleShown {
                Text(title).font(.system(size: 22, weight: .bold))
            }
            if let detail {
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .help(subtitle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct PageTitleShownKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Faux dans la fenêtre principale : l'en-tête de la fenêtre porte le titre de la page.
    var pageTitleShown: Bool {
        get { self[PageTitleShownKey.self] }
        set { self[PageTitleShownKey.self] = newValue }
    }
}

/// Titre de section des résultats de recherche : petite icône de la rubrique, puis son nom.
private struct SectionHeader: View {
    let symbol: String
    let tint: Color
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            SectionIcon(symbol: symbol, tint: tint, size: 16)
            Text(title)
        }
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
    /// Ouvre une macro de la bibliothèque dans le créateur.
    let openCreator: (UUID) -> Void
    @State private var draft: Remap
    @State private var category: FLActionInfo.Category
    @State private var query = ""

    init(original: Remap, isNew: Bool, openCreator: @escaping (UUID) -> Void = { _ in },
         onDone: @escaping (ToastMessage) -> Void) {
        self.isNew = isNew
        self.onDone = onDone
        self.openCreator = openCreator
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
        case .macro: guard draft.macro != nil || draft.macroRef != nil else { return false }
        }
        return !store.draftIssues(draft).contains(where: \.isBlocking)
    }

    private var kindSymbol: String {
        switch draft.kind {
        case .flAction: return "bolt"
        case .keystroke: return "keyboard"
        case .macro: return "wand.and.stars"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: kindSymbol, tint: SidebarItem.custom.tint,
                        title: isNew ? String(localized: "Nouveau raccourci") + (draft.page.map { " · " + $0.title } ?? "")
                                     : String(localized: "Modifier le raccourci"))

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
                case .macro:
                    if let ref = draft.macroRef {
                        LibraryMacroFields(library: store.library, ref: ref) {
                            dismiss()
                            openCreator(ref)
                        }
                    } else {
                        MacroFields(macro: macroBinding, customize: { customizeTemplate() })
                    }
                }
            }
            .formStyle(.columns)

            HStack(spacing: 8) {
                if !isNew {
                    Button("Supprimer", role: .destructive) {
                        let removed = draft
                        store.delete(draft.id)
                        onDone(ToastMessage(text: String(localized: "Raccourci supprimé"), undo: { store.upsert(removed) }))
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
                    if final.kind != .macro {
                        final.macro = nil
                        final.macroRef = nil
                    }
                    store.upsert(final)
                    onDone(ToastMessage(text: isNew ? String(localized: "Raccourci ajouté") : String(localized: "Raccourci modifié"), undo: nil))
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

    /// « Personnaliser » : le modèle, avec ses réglages, devient une macro en blocs de la bibliothèque que ce
    /// raccourci lance désormais ; elle s'ouvre dans le créateur (comme « Convertir » dans Raccourcis d'Apple).
    private func customizeTemplate() {
        let template = draft.macro ?? Macro()
        guard Dialogs.confirm(String(localized: "Personnaliser « Enregistrement rapide » ?"),
                              String(localized: "Le modèle devient une macro en blocs que tu modifies étape par étape dans le créateur. ")
                              + String(localized: "Ce raccourci lancera ta version ; le modèle d'origine reste dans Macros › Modèles."))
        else { return }
        let copy = MacroTemplates.customizedCopy(of: template,
                                                 name: store.library.uniqueName(String(localized: "Enregistrement rapide (personnalisé)")),
                                                 forbidden: store.forbidden)
        if let problem = copy.problem {
            Dialogs.inform(String(localized: "Personnalisation impossible"),
                           String(localized: "Le raccourci garde le modèle, qui continue de marcher. \(problem)"))
            return
        }
        let doc = store.library.add(copy.doc)
        var final = draft
        final.kind = .macro
        final.macro = nil
        final.macroRef = doc.id
        final.actionID = nil
        final.target = nil
        recorder.stop()
        if final.trigger != nil { store.upsert(final) }
        onDone(ToastMessage(text: String(localized: "« \(doc.name) » est dans Macros : modifie-la bloc par bloc"), undo: nil))
        dismiss()
        openCreator(doc.id)
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
                        Text(c.label).tag(c)
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
                    Text("Dans FL Studio : \(name.replacingOccurrences(of: String(localized: "FL : "), with: ""))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("Le raccourci de FL Studio à déplacer sur ta touche.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// En-tête des fiches : icône colorée et titre gras aligné à gauche (typographie de macOS 26, WWDC25 356).
private struct SheetHeader: View {
    let symbol: String
    let tint: Color
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            SectionIcon(symbol: symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct IssuesView: View {
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
            self?.hint = String(localized: "Aucune touche reçue : macOS utilise peut-être ce raccourci.")
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
/// Pendant l'enregistrement : contour et fond accentués fixes (aucune animation). Coins plus ronds, comme les
/// champs de macOS 26.
struct CaptureField: View {
    enum Role { case trigger, target }

    let id: String
    let role: Role
    @Binding var combo: KeyCombo?
    /// En-tête du créateur (maquette) : les touches seules, sans cadre ; un clic, puis taper le nouveau raccourci.
    var compact = false
    @ObservedObject private var recorder = Recorder.shared

    private var recording: Bool { recorder.activeID == id }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    private var footnote: (text: String, warning: Bool)? {
        if recording { return (String(localized: "Échap pour annuler, ⌫ pour effacer."), false) }
        if recorder.hintID == id, let hint = recorder.hint { return (hint, true) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if compact {
                compactButton
            } else {
                fullButton
            }
            if let footnote {
                Text(footnote.text)
                    .font(.system(size: 11))
                    .foregroundStyle(footnote.warning ? Color.orange : Color.secondary)
            }
        }
        .onDisappear { if recording { recorder.stop() } }
    }

    private var compactButton: some View {
        Button {
            recording ? recorder.stop() : recorder.start(id, handler: accept)
        } label: {
            Group {
                if recording {
                    Text("Appuie sur les touches…").foregroundStyle(Color.accentColor)
                } else {
                    KeyLabel(combo: combo, placeholder: String(localized: "Raccourci"))
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 4)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Changer le raccourci de la macro")
        .accessibilityLabel(String(localized: "Raccourci déclencheur"))
        .accessibilityValue(recording ? String(localized: "Enregistrement en cours")
                                      : (combo?.spoken ?? String(localized: "aucun")))
    }

    private var fullButton: some View {
        Button {
            recording ? recorder.stop() : recorder.start(id, handler: accept)
        } label: {
            Group {
                if recording {
                    Text("Appuie sur les touches…").foregroundStyle(Color.accentColor)
                } else if let combo {
                    KeyCaps(combo: combo, large: true)
                } else {
                    Text(role == .trigger ? String(localized: "Cliquer pour enregistrer")
                                          : String(localized: "Cliquer, puis taper la touche de FL"))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13))
            .multilineTextAlignment(.center)                // champ étroit : texte sur deux lignes, centré
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(shape.fill(Color.accentColor.opacity(recording ? 0.08 : 0)))
        .background(shape.fill(Color(nsColor: .textBackgroundColor)))
        .overlay(shape.strokeBorder(recording ? Color.accentColor : Color(nsColor: .separatorColor),
                                    lineWidth: recording ? 2 : 1))
        .accessibilityLabel(role == .trigger ? String(localized: "Raccourci déclencheur")
                                             : String(localized: "Touche envoyée à FL"))
        .accessibilityValue(recording ? String(localized: "Enregistrement en cours")
                                      : (combo?.spoken ?? String(localized: "aucun")))
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
                Dialogs.inform(String(localized: "Touche interdite"),
                               String(localized: "\(candidate.display) ne peut pas être envoyée à FL : \(why)."))
                return
            }
        case .trigger:
            if candidate == Store.shared.toggleCombo {
                Dialogs.inform(String(localized: "Raccourci réservé"), String(localized: "⌃⌥⌘F sert à mettre FL Shortcuts en pause."))
                return
            }
            // Touche seule : plus de question. Elle reste à FL quand elle y sert (texte en cours de saisie, menu
            // de FL ouvert, clavier-piano actif : TypingGuard), sinon elle lance le raccourci.
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

/// Petite notification (verre sur macOS 26, matériau ou opaque sinon) au-dessus du statut, dont elle naît, avec
/// « Annuler » quand c'est possible (simple remplissage sur le verre, jamais de verre sur du verre).
private struct ToastView: View {
    let message: ToastMessage
    let onClose: () -> Void

    private var shape: Capsule { Capsule() }

    var body: some View {
        HStack(spacing: 10) {
            Text(message.text).font(.system(size: 12, weight: .medium))
            if let undo = message.undo {
                Button("Annuler") { undo(); onClose() }
                    .controlSize(.small)
                    .onGlassButton()
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 36)
        .glassSurface(shape)
        .accessibilityElement(children: .contain)
    }
}

enum Dialogs {
    static func confirm(_ title: String, _ text: String) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.addButton(withTitle: String(localized: "Continuer"))
        a.addButton(withTitle: String(localized: "Annuler"))
        return a.runModal() == .alertFirstButtonReturn
    }

    static func inform(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }

    /// Alerte à plusieurs boutons (le premier par défaut, Échap sur le dernier) : rend l'indice du bouton choisi.
    static func choose(_ title: String, _ text: String, _ buttons: [String], destructive: Int? = nil) -> Int {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        for (i, label) in buttons.enumerated() {
            let button = a.addButton(withTitle: label)
            if i == destructive { button.hasDestructiveAction = true }
            if i == buttons.count - 1, buttons.count > 1 { button.keyEquivalent = "\u{1b}" }
        }
        return a.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
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
        case .keystroke: return target.map { String(localized: "Envoie \($0.display)") } ?? String(localized: "Touche de FL à choisir")
        case .macro:
            if let ref = macroRef {
                return String(localized: "Macro : ")
                    + (MacroLibraryStore.shared.doc(ref)?.name.displaySafe() ?? String(localized: "introuvable"))
            }
            return macro.map { String(localized: "Macro : \($0.name.displaySafe())") } ?? String(localized: "Macro à configurer")
        case .flAction:
            if let id = actionID, let info = FLActions.info(id) { return info.label }
            return unknownAction.map { String(localized: "Action inconnue (\($0.displaySafe()))") }
                ?? String(localized: "Action à choisir")
        }
    }

    var subtitle: String {
        switch kind {
        case .keystroke: return String(localized: "Raccourci de FL Studio")
        case .macro:
            return macroRef != nil ? String(localized: "Macro en blocs de la bibliothèque")
                                   : String(localized: "Enchaîne des clics et des touches dans FL, sans MIDI")
        case .flAction:
            guard let id = actionID, let info = FLActions.info(id) else {
                return String(localized: "Mets FL Shortcuts à jour pour l'utiliser")
            }
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
        onDone(ToastMessage(text: String(localized: "« \(row.entry.title) » : ")
                                + (combo?.display ?? String(localized: "aucune touche")), undo: nil), followUp)
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
            SheetHeader(symbol: row.entry.section.symbol, tint: row.entry.section.tint,
                        title: row.entry.title, subtitle: row.entry.section.title)

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
                        Text(row.entry.defaultTrigger?.display ?? String(localized: "Aucune"))
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
        .alert("\(combo?.display ?? String(localized: "Cette touche")) est déjà utilisée", isPresented: $showClashAlert) {
            Button("Remplacer", role: .destructive) { apply(releasing: pendingClashes) }
            Button("Annuler", role: .cancel) { pendingClashes = [] }
        } message: {
            Text(pendingClashes.prefix(4).map(\.line).joined(separator: "\n")
                 + String(localized: "\n\nUn raccourci ne peut servir qu'une fois. Si tu remplaces, tu pourras choisir tout de suite ")
                 + String(localized: "une autre touche pour « \(pendingClashes.first?.title ?? String(localized: "l'autre raccourci")) »."))
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
