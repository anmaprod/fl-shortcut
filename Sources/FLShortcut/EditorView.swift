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
    /// « Trouver un raccourci » (16/11, maquette « plus lisible ») : appuie sur ses touches, ou tape son nom.
    case find
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
        case .find: return "keyboard"
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
        case .find: return .red
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
        case .find: return "find"
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
        case "find": self = .find
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


extension View {
    /// Ligne de la barre latérale (maquette validée le 28/10) : la page choisie dans une pastille de sa couleur (30/10,
    /// « ça prenne sa couleur et ça ne reste pas en bleu »), titre blanc en gras ; les autres s'allument de leur
    /// couleur au survol, comme une ligne du menu de la barre des menus. Un
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
            .hoverTint(Color.primary)
            // Choisie : pleine de sa couleur comme au survol (texte blanc, icône en blanc translucide).
            .transformEnvironment(\.hoverFilled) { filled in
                if selected { filled = true }
            }
            .fontWeight(selected ? .bold : nil)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .background {
                // Style suisse (01/11) : la page choisie en blanc plein, texte noir, coins carrés.
                if selected { Rectangle().fill(Swiss.text) }
            }
            .contentShape(Rectangle())
            .menuHover(tint: Swiss.text, cornerRadius: 0, enabled: !selected)
            .onTapGesture(perform: choose)
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { choose() }
    }
}

/// Largeur de la page, lue sans rien redessiner tant qu'elle ne change pas.
struct WidthReader: View {
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

    /// 16/11 (maquette « plus lisible ») : la fenêtre s'ouvre sur « Trouver un raccourci ».
    @State private var selection: SidebarItem? = .find
    /// Parties de la barre de gauche ouvertes (Raccourcis, Plus) ; une page choisie ouvre sa partie.
    @State private var shortcutsOpen = true
    @State private var moreOpen = false
    /// « ou tape son nom » : la grande case de « Trouver un raccourci » cherche par le nom.
    @State private var findTyping = false
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
    /// Plus petite fenêtre (06/11) : barre de gauche + deux colonnes de raccourcis, et le créateur de macros entier.
    static var minWindowWidth: CGFloat { max(980, MacroCreatorView.minWidth) }
    static let minWindowHeight: CGFloat = 620

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
            MainWindowChrome.keep(window)
        })
        .onChange(of: selection) { AppResume.shared.page = $0 }
        .sheet(isPresented: $showGuide, onDismiss: { guideSeen = true }) {
            GuideSheet(initialPage: guidePage) { showGuide = false }
                .swissSheet()
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

    /// Flèche ← ou « Enregistrer » : retour direct, sans question (03/11 : « pour enregistrer et ré-enregistrer il n'y
    /// a pas besoin de demande, c'est seulement pour supprimer que ça doit demander ») ; une macro neuve restée vide
    /// est retirée.
    private func leaveCreator(_ editor: MacroEditorModel) {
        if editor.leaveCheck() == .discardEmpty { editor.discardNew() }
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
            sidebar
            VStack(alignment: .leading, spacing: 6) {
                pageHeader
                detail(data)
            }
            // Sous la barre de titre : elle ne laisse passer aucun clic.
            .padding(.top, MainWindowChrome.contentTop)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Thème Papier : la grille de douze colonnes derrière la page (maquette).
            .background(SwissPaperGrid())
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Appearance.windowColor)
        // Sous la barre de titre transparente : la plaque de gauche monte jusqu'en haut, les boutons fermer /
        // réduire / agrandir y sont posés (MainWindowChrome).
        .ignoresSafeArea()
        // ⌘F : la recherche prend la main (la garde la lui laisse jusqu'au premier clic ailleurs).
        .background {
            Button("Rechercher") { showFind(typing: true) }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        // Titre de la fenêtre (menu Fenêtre, VoiceOver) ; jamais affiché dans la barre de titre.
        .navigationTitle(title)
        .hiddenWindowChrome()
        // Active seulement après un clic dedans (ou ⌘F) : taper ailleurs n'y écrit plus rien ; un clic ailleurs, dans
        // l'app ou dehors, la lui reprend.
        .background(SearchFocusGuard())
        // Une page est toujours choisie ; elle ouvre sa partie de la barre de gauche.
        .onChange(of: selection) { newValue in
            if newValue == nil { selection = .find }
            // On quitte « Trouver un raccourci » : la case n'attend plus de touches.
            if newValue != .find, recorder.activeID == Self.keySearchID { recorder.stop() }
            openPart(for: newValue)
        }
        .onReceive(DebugSnapshot.publisher(DebugSnapshot.select)) { note in
            // « mixer lent » : le changement de page au ralenti (10 fois), photographié en route.
            let words = (note.object as? String ?? "").split(separator: " ")
            DebugSnapshot.slowMotion = words.contains("lent") ? 10 : 1
            let name = words.first.map(String.init) ?? ""
            selection = FLSection(rawValue: name).map(SidebarItem.section)
                ?? (name == "custom" ? .custom : name == "macros" ? .macros : name == "community" ? .community
                    : name == "aide" ? .help : name == "compte" ? .account : name == "trouver" ? .find : selection)
        }
        .onReceive(DebugSnapshot.publisher(DebugSnapshot.search)) { note in
            // Mode capture : « Trouver un raccourci » en mode « tape son nom », avec ce texte.
            selection = .find
            findTyping = true
            query = note.object as? String ?? ""
        }
        .sheet(item: $editing) { remap in
            EditSheet(original: remap, isNew: editingIsNew, openCreator: { id in openCreator(id) }) { message in show(message) }
                .environmentObject(store)
                .environmentObject(status)
                .environmentObject(link)
                .swissSheet()
        }
    }

    /// En-tête de la page (maquette « plus lisible » du 16/11) : le grand titre en minuscules et son point carré, puis
    /// un trait (pas sur « appuie sur un raccourci »). Plus de « CLIQUE SUR UNE TOUCHE POUR LA CHANGER » dessous (16/11,
    /// « tu peux enlever, toutes fioritures »). À droite : « Partager » (Communauté), « Importer », « Exporter »,
    /// « Nouvelle macro » (Macros). Plus de cadre du compte en haut (il est sous « Plus ›  Mon compte »).
    private var pageHeader: some View {
        let current = selection ?? .find
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 14) {
                    if personPageShown {
                        // 11/11 (« j'aime pas le carré à côté du nom ») : une flèche seule, sans cadre, pour revenir.
                        Button {
                            Task { await community.leavePerson() }
                        } label: {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(Swiss.text)
                                .frame(width: 30, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Revenir à la Communauté"))
                        .accessibilityLabel(String(localized: "Revenir"))
                    }
                    SwissPageTitle(text: title)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            Spacer(minLength: 8)
            if current == .macros {
                macrosHeaderButtons
            }
            if showsShareButton {
                Button {
                    community.composing = true
                } label: {
                    Text("Partager")
                }
                .primaryButton()
                .controlSize(.large)
                .help("Partager une macro ou tes raccourcis")
            }
        }
        .padding(.top, 30)
        .padding(.bottom, current == .find ? 4 : 20)
        .overlay(alignment: .bottom) {
            if current != .find { Rectangle().fill(Swiss.line).frame(height: 1) }
        }
        .frame(maxWidth: ReadableLayout.maxWidth, alignment: .leading)
        .padding(.horizontal, ReadableLayout.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Macros (maquette) : « Importer », « Exporter » bordés, « Nouvelle macro » plein ; sans macro, « Importer » seul
    /// (« Nouvelle macro » est au milieu de la page vide).
    private var macrosHeaderButtons: some View {
        HStack(spacing: 12) {
            Button("Importer") {
                MacroLibraryActions.importFile(into: store.library, layout: store.layout, toast: { show($0) }, open: { openCreator($0) })
            }
            .secondaryButton()
            .controlSize(.large)
            .help("Ajouter des macros reçues (.flsmacro) ; la boîte s'ouvre dans Documents › FL Shortcuts › Macros › Importer")
            if !store.library.macros.isEmpty {
                Button("Exporter") { MacroLibraryActions.exportAll(store.library, toast: { show($0) }) }
                    .secondaryButton()
                    .controlSize(.large)
                    .help("Toutes les macros, un fichier chacune, dans Documents › FL Shortcuts › Macros › Exporter")
                NewMacroButton(library: store.library)
            }
        }
        .fixedSize()
    }

    private var title: String {
        switch selection ?? .find {
        case .find: return String(localized: "Appuie sur un raccourci")
        case .section(let s): return s.title
        case .custom: return String(localized: "Mes raccourcis")
        case .macros: return String(localized: "Macros")
        // 11/11 : sur la page d'une personne, son pseudo à la place de « communauté. ».
        case .community: return community.personName ?? String(localized: "Communauté")
        case .help: return String(localized: "Aide")
        case .account: return String(localized: "Mon compte")
        }
    }

    // MARK: Barre latérale

    /// Fin de la recherche (texte vidé, attente d'un raccourci arrêtée) : la page choisie revient.
    private func endSearch() {
        if recorder.activeID == Self.keySearchID { recorder.stop() }
        keySearch = nil
        query = ""
    }

    /// Page choisie dans la barre de gauche.
    private func isShown(_ item: SidebarItem) -> Bool { selection == item }

    /// Clic sur une ligne de la barre de gauche.
    private func choose(_ item: SidebarItem) {
        // Déjà sur la page d'une personne : « Communauté » ramène à la liste.
        if item == .community, personPageShown {
            Task { await community.leavePerson() }
            return
        }
        selection = item
    }

    /// Une page choisie ouvre sa partie de la barre de gauche (Raccourcis, Plus).
    private func openPart(for item: SidebarItem?) {
        switch item {
        case .section?, .custom?: shortcutsOpen = true
        case .community?, .account?, .help?: moreOpen = true
        default: break
        }
    }

    /// La page d'une personne est à l'écran.
    private var personPageShown: Bool { isShown(.community) && community.personName != nil }

    /// Barre de gauche (maquette « plus lisible » du 16/11) : ReadableSidebar.
    private var sidebar: some View {
        ReadableSidebar(selected: selection, shortcutsOpen: $shortcutsOpen, moreOpen: $moreOpen,
                        communityDot: community.newFromFollowed > 0, accountDot: backup.conflict != nil) { item in
            choose(item)
        }
    }

    // MARK: Détail

    private func detail(_ data: CatalogData) -> some View {
        Group {
            switch selection ?? .find {
            case .find: findPage(data)
            case .section(let s): sectionList(s, rows: data.rows, mine: data.others.filter { $0.belongs(to: s) })
            case .custom: customList(data)
            case .macros: MacroLibraryPage(library: store.library, open: { id in openCreator(id) }, toast: { show($0) },
                                           editKey: { remap, isNew in editingIsNew = isNew; editing = remap })
            case .community: CommunityPage(community: CommunityStore.shared, toast: { show($0) })
            case .help: HelpPage(community: CommunityStore.shared, showGuide: { GuideLink.shared.show() })
            case .account: AccountPage(community: CommunityStore.shared, backup: AccountBackup.shared)
            }
        }
        // Le titre de la page est dans l'en-tête de la fenêtre : les pages ne le répètent pas (PageHeader).
        .environment(\.pageTitleShown, false)
        // Nouvelle liste (et retour en haut) à chaque section, affichée d'un coup (aucune animation).
        .pageSwitch(selection)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .swissSheet()
        }
    }

    /// Une page lisible (maquette du 16/11) : une colonne de 800 points au plus, du même bord que le titre ; elle
    /// défile sous l'en-tête, la dernière ligne au-dessus de la barre d'état.
    private func readablePage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) { content() }
                .frame(maxWidth: ReadableLayout.maxWidth, alignment: .leading)
                .padding(.horizontal, ReadableLayout.inset)
                .padding(.top, 14)
                .padding(.bottom, 80)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Une page de raccourcis (maquette) : chaque groupe de FL (Outils, Clips…) avec son nom à gauche et ses lignes à
    /// droite, puis les actions en plus et tes raccourcis ajoutés sur cette page.
    private func sectionList(_ section: FLSection, rows: [CatalogRow], mine custom: [Remap]) -> some View {
        let mine = rows.filter { $0.entry.section == section }
        let groups = CatalogGroups.cards(for: section, rows: mine.filter { $0.entry.isNative }, entry: \.entry)
        let extras = mine.filter { !$0.entry.isNative }
        return readablePage {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                ReadableGroup(title: group.title) {
                    ForEach(group.rows) { catalogLine($0) }
                }
            }
            if !extras.isEmpty {
                ReadableGroup(title: String(localized: "Actions en plus")) {
                    ForEach(extras) { catalogLine($0) }
                }
            }
            if !custom.isEmpty {
                ReadableGroup(title: String(localized: "Tes raccourcis sur cette page")) {
                    ForEach(custom) { customLine($0) }
                }
            }
        }
        .padding(.top, 10)
        .id(section)                                 // nouvelle section : la page repart du haut
    }

    /// « appuie sur un raccourci » (maquette, écrans 1 à 3) : la grande case attend les touches (ou le nom, « ou tape
    /// son nom »), puis ce qu'elles font, dans toutes les pages : nom, page (« GÉNÉRAL · AVANT ⌘S » si changée), touche.
    private func findPage(_ data: CatalogData) -> some View {
        let listening = recorder.activeID == Self.keySearchID
        let combo = findTyping ? nil : keySearch
        let q = findTyping ? trimmedQuery : ""
        let active = combo != nil || !q.isEmpty
        let rows: [CatalogRow] = !active ? [] : data.rows.filter { row in
            if let combo { return KeySearch.matches(row, combo) }
            return [row.entry.title, row.entry.detail, row.current?.display ?? "", row.entry.section.title]
                .joined(separator: " ").localizedCaseInsensitiveContains(q)
        }
        let others: [Remap] = !active ? [] : data.others.filter { r in
            if let combo { return KeySearch.matches(r, combo) }
            return [r.title, r.subtitle, r.trigger?.display ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(q)
        }
        return readablePage {
            FindShortcutField(combo: combo, listening: listening, typing: findTyping, query: $query,
                              focusSerial: searchFocusSerial,
                              startListening: { startKeySearch() },
                              clear: {
                                  if findTyping { query = "" } else { keySearch = nil }
                              })
            ReadableLink(title: findTyping ? String(localized: "ou appuie sur le raccourci") : String(localized: "ou tape son nom")) {
                if recorder.activeID == Self.keySearchID { recorder.stop() }
                findTyping.toggle()
                if findTyping { searchFocusSerial += 1 }
            }
            .padding(.top, 12)
            if recorder.hintID == Self.keySearchID, let hint = recorder.hint {
                SwissWarning(hint).font(.system(size: 13)).padding(.top, 16)
            }
            if active {
                if rows.isEmpty && others.isEmpty {
                    Text(combo.map { String(localized: "Rien n'utilise \($0.display) : ces touches sont libres.") }
                         ?? String(localized: "Aucun raccourci ne correspond à « \(q) »."))
                        .font(.system(size: 15))
                        .foregroundStyle(Swiss.gray)
                        .padding(.top, 44)
                } else {
                    Color.clear.frame(height: 1)
                        .padding(.top, 44)
                        .swissRule(Swiss.faint)
                    ForEach(rows) { row in catalogLine(row, detail: findDetail(row), bold: true) }
                    ForEach(others) { remap in customLine(remap, detail: String(localized: "Mes raccourcis"), bold: true) }
                }
            }
        }
        .padding(.top, 18)
    }

    /// « GÉNÉRAL » : la page seule (16/11, plus de « · AVANT ⌘S » : « enlève toutes les fioritures »).
    private func findDetail(_ row: CatalogRow) -> String { row.entry.section.title }

    /// « Mes raccourcis » (05/11, « juste action, page, puis raccourci, avec le bouton réinitialiser derrière ») : une
    /// ligne par raccourci de FL changé, puis par raccourci créé ou importé. Jamais les macros (page Macros).
    private func customList(_ data: CatalogData) -> some View {
        let changed = MyShortcuts.changed(data.rows)
        let created = MyShortcuts.created(data.others, starters: store.freshRemaps())
        return Group {
            if changed.isEmpty && created.isEmpty {
                EmptyState(symbol: SidebarItem.custom.symbol, title: String(localized: "Aucun raccourci changé"),
                           text: PageSummary.custom)
            } else {
                readablePage {
                    ForEach(changed) { row in catalogLine(row, detail: findDetail(row), bold: true) }
                    ForEach(created) { remap in customLine(remap, bold: true) }
                }
                .padding(.top, 10)
            }
        }
    }

    /// Ligne d'un raccourci de FL : nom, touche (rouge si changée), ↺ ; clic droit : changer, réinitialiser.
    private func catalogLine(_ row: CatalogRow, detail: String? = nil, bold: Bool = false) -> some View {
        let issues = row.remap.map { store.issues(for: $0.id) } ?? []
        let warning: String? = row.takenBy.map {
            String(localized: "Touche aussi utilisée par « \($0) ». Clique sur la touche pour en choisir une autre.")
        } ?? (issues.isEmpty ? nil : issues.map(\.message).joined(separator: "\n"))
        let edit = { editNotice = nil; editingRow = row }
        return ReadableRow(title: row.entry.title, bold: bold, detail: detail, warning: warning,
                           combo: row.current, changed: !row.isDefault, onKey: edit) {
            if !row.isDefault {
                ReadableResetButton(help: String(localized: "Revenir à : ")
                                    + (row.entry.defaultTrigger?.display ?? String(localized: "aucune touche"))) { reset(row) }
            }
        }
        .help(row.entry.isNative ? String(localized: "Raccourci d'origine de FL Studio") : row.entry.detail)
        .swissContextMenu {
            var items: [RightClickMenu.Item?] = [RightClickMenu.Item(title: String(localized: "Changer la touche…"), action: edit)]
            if !row.isDefault { items.append(RightClickMenu.Item(title: String(localized: "Réinitialiser"), action: { reset(row) })) }
            return items
        }
    }

    /// Ligne d'un raccourci que tu as créé : nom (gris s'il est désactivé), touche, Supprimer.
    private func customLine(_ remap: Remap, detail: String? = nil, bold: Bool = false) -> some View {
        let issues = store.issues(for: remap.id)
        let open = { editingIsNew = false; editing = remap }
        return ReadableRow(title: remap.title, bold: bold, detail: detail, dimmed: !remap.enabled,
                           warning: issues.isEmpty ? nil : issues.map(\.message).joined(separator: "\n"),
                           combo: remap.trigger, onKey: open) {
            Button { delete(remap) } label: {
                Image(systemName: "trash").font(.system(size: 12, weight: .medium)).foregroundStyle(Swiss.gray)
                    .frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Supprimer")
            .accessibilityLabel(String(localized: "Supprimer"))
        }
        .swissContextMenu {
            [RightClickMenu.Item(title: String(localized: "Modifier…"), action: open),
             RightClickMenu.Item(title: remap.enabled ? String(localized: "Désactiver") : String(localized: "Activer"), action: {
                 var copy = remap
                 copy.enabled.toggle()
                 store.upsert(copy)
             }),
             nil,
             RightClickMenu.Item(title: String(localized: "Supprimer"), destructive: true, action: { delete(remap) })]
        }
    }

    // MARK: Avertissements (seulement quand il faut agir)

    private var notices: [NoticeItem] {
        var out: [NoticeItem] = []
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

    /// Page affichée.
    private var page: SidebarItem { selection ?? .find }

    /// La grande case de « Trouver un raccourci » attend les touches : appuyées, elle montre ce qu'elles font (pour qui
    /// connaît ses touches mais pas le nom du raccourci). Échap annule.
    private func startKeySearch() {
        findTyping = false
        recorder.start(Self.keySearchID) { combo in
            if !combo.hasModifiers && combo.keyCode == 53 { return }          // Échap : annuler
            guard combo.isValidTrigger else { return }
            keySearch = combo
        }
    }

    /// ⌘F : « Trouver un raccourci », la case prête (au nom si `typing`).
    private func showFind(typing: Bool) {
        if macroEditor != nil { closeCreator() }
        selection = .find
        findTyping = typing
        if typing { searchFocusSerial += 1 }
    }

    /// « Partager » sur la page Communauté une fois connecté (le « + » d'avant, 30/10).
    private var showsShareButton: Bool {
        page == .community && community.session != nil
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
                            StatusSymbol(name: item.symbol, size: 14, tint: item.tint)
                            Text(item.text).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            if let title = item.button, let action = item.action {
                                Button(title, action: action).controlSize(.small).onGlassButton()
                            }
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassSurface(Rectangle(),
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
                StatusSymbol(name: symbol, size: 13, tint: color)
                    .accessibilityHidden(true)
                Text(text).lineLimit(1)
                if let action {
                    Button(action.label, action: action.run)
                        .buttonStyle(SwissLinkButtonStyle())
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .frame(height: 34)
            .glassSurface(Rectangle())
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
        // Clavier non autorisé : l'avertissement du haut le dit déjà, avec son bouton (16/11, pas de doublon en bas).
        if !status.accessibilityOK { return nil }
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
            Text(title).font(Swiss.title(22)).tracking(Swiss.titleTracking(22)).foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action).secondaryButton().padding(.top, 6)
            }
        }
        .frame(maxWidth: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

private extension View {
    /// Titre d'une page dans les résultats de la recherche, posé comme une ligne : fond transparent, sans trait.
    func headerRow() -> some View {
        font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Swiss.gray)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .listRowInsets(EdgeInsets(top: 0, leading: CardRowBackground.inset + 6, bottom: 0, trailing: CardRowBackground.inset))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
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

    /// Titre de la fiche : le nom de la macro, de l'action ou du raccourci ; « nouveau raccourci » pour un nouveau.
    private var headerTitle: String {
        if isNew { return String(localized: "Nouveau raccourci") }
        if draft.kind == .macro, let ref = draft.macroRef, let doc = store.library.doc(ref) {
            return doc.name.displaySafe(max: 40)
        }
        if draft.kind == .flAction, let id = draft.actionID, let info = FLActions.info(id) { return info.label }
        return draft.title
    }

    /// Rubrique au-dessus du titre : la sorte de raccourci (ou la page d'un nouveau).
    private var headerLabel: String {
        if isNew { return draft.page?.title ?? String(localized: "Modifier le raccourci") }
        switch draft.kind {
        case .flAction: return String(localized: "Action dans FL")
        case .keystroke: return String(localized: "Touche de FL")
        case .macro: return String(localized: "Macro")
        }
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
            SheetHeader(symbol: kindSymbol, tint: SidebarItem.custom.tint, title: headerTitle, subtitle: headerLabel)

            // 05/11 (« on s'y perd… juste le bouton raccourci et puis c'est fini ») : une fiche ouverte sur un raccourci
            // qui existe ne montre que sa touche (et le créateur pour une macro) ; le choix du type, seulement pour un
            // nouveau raccourci.
            SheetRow(String(localized: "Raccourci")) {
                CaptureField(id: "\(draft.id)-trigger", role: .trigger, combo: $draft.trigger)
                if !issues.isEmpty && recorder.activeID == nil {
                    IssuesView(issues: issues)
                }
            }
            if isNew {
                Form {
                    SwissSegmented(selection: $draft.kind, options: [
                        (value: Remap.Kind.flAction, label: String(localized: "Action dans FL")),
                        (value: Remap.Kind.keystroke, label: String(localized: "Touche de FL")),
                        (value: Remap.Kind.macro, label: String(localized: "Macro")),
                    ], title: String(localized: "Type"))
                    switch draft.kind {
                    case .flAction: actionFields
                    case .keystroke: keystrokeFields
                    case .macro: MacroFields(macro: macroBinding, customize: { customizeTemplate() })
                    }
                }
                .formStyle(.columns)
            } else {
                switch draft.kind {
                case .flAction:
                    EmptyView()
                case .keystroke:
                    SheetRow(String(localized: "Touche de FL")) {
                        CaptureField(id: "\(draft.id)-target", role: .target, combo: $draft.target)
                    }
                case .macro:
                    if let ref = draft.macroRef {
                        if let doc = store.library.doc(ref) {
                            OpenCreatorRow(name: doc.name.displaySafe(max: 60)) {
                                dismiss()
                                openCreator(ref)
                            }
                        } else {
                            Text("Macro introuvable (supprimée ?)").font(.system(size: 12)).foregroundStyle(Swiss.gray)
                        }
                    } else {
                        Form { MacroFields(macro: macroBinding, customize: { customizeTemplate() }) }
                            .formStyle(.columns)
                    }
                }
            }

            HStack(spacing: 8) {
                if !isNew {
                    Button("Supprimer", role: .destructive) {
                        let removed = draft
                        store.delete(draft.id)
                        onDone(ToastMessage(text: String(localized: "Raccourci supprimé"), undo: { store.upsert(removed) }))
                        dismiss()
                    }
                    .buttonStyle(CapsuleButtonStyle(prominent: false, danger: true))
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
        .padding(24)
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
                        .swissField()
                    if !AppMode.light {
                        Button("Tester") {
                            if let id = draft.actionID { link.test(action: id) }
                        }
                        .secondaryButton()
                        .disabled(draft.actionID == nil || link.status != .linked)
                        .help("Envoie l'action à FL Studio")
                    }
                }
                SwissSegmented(selection: categoryBinding,
                               options: FLActionInfo.Category.allCases.map { (value: $0, label: $0.label) })

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
        SwissPicker(String(localized: "Où"), selection: $draft.context, current: draft.context.label,
                    entries: ShortcutContext.allCases.map { SwissPickerEntry.option($0, $0.label) })
    }

    private var actions: [FLActionInfo] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return FLActions.offered.filter { info in
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

/// En-tête des fiches (05/11, « pas avec ce logo-là… le carré ») : la rubrique en petites capitales grises, puis le
/// titre en minuscules suivi de son point carré. Plus d'icône de couleur. `symbol` et `tint` : gardés pour les appels.
private struct SheetHeader: View {
    let symbol: String
    let tint: Color
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let subtitle {
                Text(subtitle).swissLabel()
            }
            SwissPageTitle(text: title, size: 30)
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .swissRule()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Ligne d'une fiche (style suisse) : le nom en petites capitales à gauche, le champ à droite, un trait fin dessous.
private struct SheetRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).swissLabel().frame(width: 110, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 14)
        .swissRule(Swiss.faint)
    }
}

/// « Ouvrir dans le créateur » (05/11, « faire un truc plus beau ») : une grande ligne bordée, le carré creux, le nom
/// de la macro, la flèche ; au survol, pleine d'encre.
private struct OpenCreatorRow: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { OpenCreatorLabel(name: name) }
            .buttonStyle(.plain)
            .menuHover(tint: Swiss.text, cornerRadius: 0)
            .accessibilityLabel(String(localized: "Ouvrir dans le créateur"))
    }
}

private struct OpenCreatorLabel: View {
    let name: String
    @Environment(\.hoverFilled) private var filled

    var body: some View {
        HStack(spacing: 12) {
            PageSquare()
            VStack(alignment: .leading, spacing: 2) {
                Text("Ouvrir dans le créateur").font(Swiss.font(13)).tracking(1.2).textCase(.uppercase)
                Text(name).font(.system(size: 12)).foregroundStyle(filled ? Swiss.background : Swiss.gray).lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .overlay(Rectangle().strokeBorder(Swiss.text, lineWidth: 1.5))
        .contentShape(Rectangle())
    }
}

struct IssuesView: View {
    let issues: [ShortcutIssue]

    var body: some View {
        let blocking = issues.contains(where: \.isBlocking)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            SwissWarningMark(size: blocking ? 8 : 7).alignmentGuide(.firstTextBaseline) { d in d[.bottom] }
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
    private var handler: ((KeyCombo) -> Void)?
    private var timeout: DispatchWorkItem?
    private var resignObserver: NSObjectProtocol?

    private init() {}

    /// Touches, ou bouton de souris du milieu ou du côté (05/11) : le champ reçoit une combinaison, la touche codée
    /// comme un bouton de souris le cas échéant (KeyCombo.mouseBase).
    func start(_ id: String, handler: @escaping (KeyCombo) -> Void) {
        stop()
        hint = nil
        hintID = nil
        activeID = id
        self.handler = handler
        Store.shared.recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .otherMouseDown]) { [weak self] event in
            guard let self, let h = self.handler else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let combo: KeyCombo
            if event.type == .otherMouseDown {
                guard let pressed = KeyCombo(mouseButton: event.buttonNumber, modifiers: mods) else { return event }
                combo = pressed
            } else {
                combo = KeyCombo(keyCode: event.keyCode, modifiers: mods)
            }
            self.stop()
            DispatchQueue.main.async { h(combo) }
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
    private var shape: Rectangle { Rectangle() }

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
                    Text("Appuie sur les touches…").foregroundStyle(Swiss.red)
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
                    Text("Appuie sur les touches…").foregroundStyle(Swiss.red)
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
        .background(shape.fill(Swiss.red.opacity(recording ? 0.08 : 0)))
        .background(shape.fill(Color(nsColor: .textBackgroundColor)))
        .overlay(shape.strokeBorder(recording ? Swiss.red : Color(nsColor: .separatorColor),
                                    lineWidth: recording ? 2 : 1))
        .accessibilityLabel(role == .trigger ? String(localized: "Raccourci déclencheur")
                                             : String(localized: "Touche envoyée à FL"))
        .accessibilityValue(recording ? String(localized: "Enregistrement en cours")
                                      : (combo?.spoken ?? String(localized: "aucun")))
    }

    private func accept(_ candidate: KeyCombo) {
        if !candidate.hasModifiers && candidate.keyCode == 53 { return }            // Échap : annuler
        if !candidate.hasModifiers && candidate.keyCode == 51 { combo = nil; return } // ⌫ : effacer
        // Un bouton de souris lance un raccourci, mais n'est jamais envoyé à FL.
        guard role == .trigger ? candidate.isValidTrigger : candidate.isValidKey else { return }

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
    /// Un bouton de plus (« Noter » après un ajout de la Communauté, 11/11) ; nil : aucun.
    var action: (title: String, run: () -> Void)? = nil

    static func == (a: ToastMessage, b: ToastMessage) -> Bool { a.id == b.id }
}

/// Petite notification (verre sur macOS 26, matériau ou opaque sinon) au-dessus du statut, dont elle naît, avec
/// « Annuler » quand c'est possible (simple remplissage sur le verre, jamais de verre sur du verre).
private struct ToastView: View {
    let message: ToastMessage
    let onClose: () -> Void

    private var shape: Rectangle { Rectangle() }

    var body: some View {
        HStack(spacing: 10) {
            Text(message.text).font(.system(size: 12, weight: .medium))
            if let undo = message.undo {
                Button("Annuler") { undo(); onClose() }
                    .controlSize(.small)
                    .onGlassButton()
            }
            if let action = message.action {
                Button(action.title) { action.run(); onClose() }
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

/// Les questions et messages de l'app, au style suisse (`SwissDialog`, 02/11) à la place des alertes de macOS.
enum Dialogs {
    static func confirm(_ title: String, _ text: String) -> Bool {
        SwissDialog.run(title, text, buttons: [String(localized: "Continuer"), String(localized: "Annuler")]) == 0
    }

    static func inform(_ title: String, _ text: String) {
        _ = SwissDialog.run(title, text, buttons: [String(localized: "OK")])
    }

    /// Plusieurs boutons (le premier par défaut, Échap sur le dernier) : rend l'indice du bouton choisi.
    static func choose(_ title: String, _ text: String, _ buttons: [String], destructive: Int? = nil) -> Int {
        SwissDialog.run(title, text, buttons: buttons, destructive: destructive)
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
                SwissWarning(notice)
                    .fixedSize(horizontal: false, vertical: true)
                .font(.system(size: 12))
            }

            SheetRow(String(localized: "Touche")) {
                CaptureField(id: "catalog-\(row.id)", role: .trigger, combo: $combo)
                if !clashes.isEmpty && recorder.activeID == nil {
                    clashList
                }
                if !issues.isEmpty && recorder.activeID == nil {
                    IssuesView(issues: issues)
                }
            }
            SheetRow(String(localized: "D'origine")) {
                Text(row.entry.defaultTrigger?.display ?? String(localized: "Aucune")).font(Swiss.font(13))
            }

            HStack(spacing: 8) {
                Button {
                    combo = row.entry.defaultTrigger
                } label: {
                    Label("Réinitialiser", systemImage: "arrow.counterclockwise")
                }
                .secondaryButton()
                .disabled(combo == row.entry.defaultTrigger)

                if let id = actionID {
                    Button("Aucune touche") { combo = nil }
                        .secondaryButton()
                        .disabled(combo == nil)
                    if !AppMode.light {
                        Button("Tester") { link.test(action: id) }
                            .secondaryButton()
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
                        // La question au style suisse (02/11), après le clic (le bouton se relâche d'abord).
                        DispatchQueue.main.async { askReplace(found) }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .primaryButton()
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onDisappear { recorder.stop() }
    }

    /// Une touche ne sert qu'une fois : on annonce ce qui l'utilise avant de la reprendre.
    private func askReplace(_ found: [KeyClash]) {
        let title = String(localized: "\(combo?.display ?? String(localized: "Cette touche")) est déjà utilisée")
        let text = found.prefix(4).map(\.line).joined(separator: "\n")
            + String(localized: "\n\nUn raccourci ne peut servir qu'une fois. Si tu remplaces, tu pourras choisir tout de suite ")
            + String(localized: "une autre touche pour « \(found.first?.title ?? String(localized: "l'autre raccourci")) ».")
        let answer = SwissDialog.run(title, text, buttons: [String(localized: "Remplacer"), String(localized: "Annuler")],
                                     destructive: 0)
        if answer == 0 { apply(releasing: found) } else { pendingClashes = [] }
    }

    /// Liste courte sous le champ : qui utilise déjà cette touche.
    private var clashList: some View {
        VStack(alignment: .leading, spacing: 2) {
            SwissWarning(String(localized: "Déjà utilisée par :"))
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
