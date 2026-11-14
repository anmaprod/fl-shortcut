// Page Communauté de la fenêtre principale : des macros et des raccourcis prêts à l'emploi, partagés par d'autres
// utilisateurs, avec l'explication de leur auteur. Comme la galerie de Raccourcis d'Apple : on ouvre un partage pour
// lire ce qu'il fait, étape par étape, puis on l'ajoute ; rien ne s'ajoute sans cette fiche, rien ne se lance tout
// seul (une macro ajoutée n'a pas de raccourci). Compte nécessaire (mail, mot de passe, nom d'utilisateur) : sans
// compte, rien n'est visible. Tout ajout passe par les mêmes vérifications qu'un fichier reçu (MacroExchange,
// ProfileImporter).
import AppKit
import SwiftUI

enum CommunityText {
    static let subtitle = String(localized: """
        Des macros et des raccourcis prêts à l'emploi, partagés par d'autres utilisateurs de \
        FL Shortcuts, avec leur explication.
        """)

    /// « 2026-10-16T18:02:11… » → « 16/10/2026 ».
    static func day(_ iso: String) -> String {
        let parts = iso.prefix(10).split(separator: "-")
        return parts.count == 3 ? "\(parts[2])/\(parts[1])/\(parts[0])" : ""
    }

    /// Date du serveur (« 2026-10-16T18:02:11.123456+00:00 », fractions de seconde ou non).
    static func date(_ iso: String) -> Date? {
        // Microsecondes du serveur ramenées aux millisecondes que lit ISO8601DateFormatter.
        var iso = iso
        if let dot = iso.firstIndex(of: "."),
           let end = iso[iso.index(after: dot)...].firstIndex(where: { !$0.isNumber }),
           iso.distance(from: dot, to: end) > 4 {
            iso.removeSubrange(iso.index(dot, offsetBy: 4)..<end)
        }
        return withFraction.date(from: iso) ?? withoutFraction.date(from: iso)
    }

    /// Créés une seule fois (14/11, optimisation : un par carte et par dessin avant). ISO8601DateFormatter lit les
    /// dates sans risque depuis plusieurs fils.
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let withoutFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// « Macro · par @leo.beats · 15/10/2026 ».
    static func byline(_ share: Share) -> String {
        String(localized: "\(share.kind.label) · par @\(share.authorName.displaySafe(max: 24)) · \(day(share.createdAt))")
    }
}

extension ShareKind {
    /// Couleur de l'icône : celle de la page Macros pour une macro, bleu clavier pour des raccourcis.
    var tint: Color { self == .macro ? SidebarItem.macros.tint : .blue }
    /// Bouton principal de la fiche.
    var addLabel: String {
        self == .macro ? String(localized: "Ajouter à mes macros") : String(localized: "Utiliser ces raccourcis")
    }
}

struct CommunityPage: View {
    @EnvironmentObject var store: Store
    @ObservedObject var community: CommunityStore
    let toast: (ToastMessage) -> Void
    /// Fiche ouverte (lecture avant d'ajouter).
    @State private var opened: Share?
    @State private var reporting: Share?

    var body: some View {
        Group {
            if !community.isConfigured {
                CommunityMessage(symbol: "network.slash", title: String(localized: "La Communauté n'est pas encore ouverte"),
                                 text: String(localized: """
                                     Bientôt, tu y trouveras des macros et des raccourcis partagés par d'autres \
                                     utilisateurs, et tu pourras partager les tiens. En attendant, rien ne change \
                                     pour tes raccourcis et tes macros.
                                     """))
            } else if community.session == nil {
                CommunitySignIn(community: community)
            } else {
                CommunityBrowse(community: community, open: { opened = $0 }, report: { reporting = $0 },
                                delete: { share in Task { await delete(share) } })
            }
        }
        .softSwitch(!community.isConfigured ? 0 : community.session == nil ? 1 : 2)
        .task { await community.open() }
        // 10/11 (« sur Mac, quand tu l'ouvres, ça fait un peu du liquid glass… une page au-dessus, mais style
        // suisse ») : la fiche, « Partager » et « Signaler » ne sont plus des feuilles de macOS mais des pages posées
        // au-dessus de la liste (SwissPageAbove), les mêmes que sur Windows.
        .overlay {
            if let share = opened {
                SwissPageAbove {
                    CommunityShareDetail(community: community, store: store, share: share, added: toast,
                                         report: { reportLater(share) }, close: { opened = nil },
                                         rateLater: { opened = share })
                        .id(share.id)
                }
            } else if community.composing {
                SwissPageAbove {
                    CommunityPublishSheet(community: community, library: store.library,
                                          profile: { try? store.exportData() },
                                          close: { community.composing = false })
                }
            } else if let share = reporting {
                SwissPageAbove {
                    CommunityReportSheet(community: community, share: share, close: { reporting = nil })
                        .id(share.id)
                }
            }
        }
        .onReceive(DebugSnapshot.publisher(DebugSnapshot.community)) { note in
            showCapture(note.object as? String ?? "")
        }
    }

    /// « Signaler… » depuis la fiche : la fiche laisse sa place au signalement.
    private func reportLater(_ share: Share) {
        opened = nil
        reporting = share
    }

    private func delete(_ share: Share) async {
        let title = String(localized: "Supprimer « \(share.title.displaySafe(max: 40)) » ?")
        let text = String(localized: "Le partage disparaît pour tout le monde. Tes macros et raccourcis ne changent pas.")
        guard Dialogs.confirm(title, text) else { return }
        await community.delete(share)
    }

    /// Mode capture (mesure de la CI) : chaque écran de la page, avec des exemples et sans réseau.
    private func showCapture(_ screen: String) {
        opened = nil
        reporting = nil
        community.composing = false
        switch screen {
        case "connexion", "inscription":
            community.showDemo(signedIn: false)
            community.creatingAccount = screen == "inscription"
        case "vide":
            community.showDemo(signedIn: true, empty: true)
        case "detail":
            community.showDemo(signedIn: true)
            opened = community.shares.first
        case "partager":
            community.showDemo(signedIn: true)
            community.composing = true
        case "signaler":
            community.showDemo(signedIn: true)
            reporting = community.shares.first
        case "membres":
            community.showDemoMemberSearch("le")
        case "auteur", "personne":
            community.showDemo(signedIn: true)
            // prod.nina : une personne avec une photo, 1 284 abonnés (page du 11/11).
            if let share = community.shares.first(where: { $0.authorName == "prod.nina" }) ?? community.shares.first {
                Task { await community.openPerson(of: share) }
            }
        case "abonnements":
            community.showDemo(signedIn: true)
            Task { await community.choose(.following) }
        case "plus-ajoutees":
            community.showDemo(signedIn: true)
            Task { await community.choose(.mostAdded) }
        case "note":
            // Fiche d'un partage ajouté : « Ta note » et ses étoiles.
            community.showDemo(signedIn: true)
            opened = community.shares.first
        default:
            community.showDemo(signedIn: true)
        }
    }
}

/// Page sans contenu : ce qui se passe, en une phrase, et quoi faire (s'il y a quelque chose à faire).
struct CommunityMessage: View {
    let symbol: String
    var tint: Color = SidebarItem.community.tint
    let title: String
    let text: String
    var button: String? = nil
    var action: () -> Void = {}

    var body: some View {
        // 06/11 (« le petit logo d'étoile… ça rentre pas du tout dans le thème ») : plus d'icône de couleur, le titre
        // et le texte seuls ; `symbol` et `tint` restent pour les appels existants.
        VStack(spacing: 10) {
            Text(title).font(Swiss.title(22)).tracking(Swiss.titleTracking(22)).multilineTextAlignment(.center)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .fixedSize(horizontal: false, vertical: true)
            if let button {
                Button(button, action: action).primaryButton().padding(.top, 4)
            }
        }
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Erreur ou information de la dernière action.
private struct CommunityStatus: View {
    @ObservedObject var community: CommunityStore

    var body: some View {
        // Sans icône (06/11 : rien qui détonne dans le style suisse) : l'erreur en rouge, l'information en gris.
        if let error = community.error {
            Text(error)
                .foregroundStyle(Swiss.red)
                .font(.system(size: 12))
        } else if let notice = community.notice {
            Text(notice)
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
        }
    }
}

// MARK: - Les partages

private struct CommunityBrowse: View {
    @ObservedObject var community: CommunityStore
    let open: (Share) -> Void
    let report: (Share) -> Void
    let delete: (Share) -> Void

    /// Maquette validée le 30/10 : la recherche et les filtres sur une ligne, puis les partages en cartes sur deux
    /// colonnes. Plus de « Comment ça marche » ni de « Connecté en tant que » (le compte est dans l'en-tête).
    /// Vitrine du 11/11 (« Pour toi ») : seulement sans recherche, sur tout le monde, avec le serveur du 11/11.
    private var showcase: Bool {
        community.social && community.tab == .forYou && community.author == nil
            && community.search.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                if let author = community.author, community.isPersonPage {
                    // Page d'une personne (11/11) : elle prend la place de la liste ; son pseudo est le titre, ← devant.
                    CommunityPersonHeader(community: community, author: author)
                    CommunityStatus(community: community)
                } else {
                    CommunityFilters(community: community)
                    CommunityStatus(community: community)
                }
                if community.isPersonPage {
                    EmptyView()
                } else if !community.members.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Membres")
                            .swissLabel(Swiss.text)
                            .padding(.bottom, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .swissRule()
                        VStack(spacing: 0) {
                            ForEach(community.members) { member in
                                CommunityMemberRow(member: member, photo: community.photos[member.id]) {
                                    Task { await community.openPerson(member) }
                                }
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 6)
                                    .swissRule(Swiss.faint)
                                    .menuHover(tint: Swiss.text, cornerRadius: 0)
                            }
                        }
                        .padding(2)
                        .background(MockPlate(cornerRadius: 14)).swissCard()
                    }
                }
                if showcase {
                    CommunityShowcase(community: community, open: open)
                    if !community.shares.isEmpty,
                       !(community.followedPreview.isEmpty && community.creators.isEmpty && community.topPreview.isEmpty) {
                        Text("Nouveautés")
                            .swissLabel(Swiss.text)
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .swissRule(Swiss.line)
                            .padding(.top, 14)
                    }
                }
                if community.shares.isEmpty {
                    empty
                        .frame(maxWidth: .infinity)
                        .background(MockPlate(cornerRadius: 14)).swissCard()
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 20, alignment: .top)], spacing: 20) {
                        ForEach(community.shares) { share in
                            CommunityShareCard(share: share, photo: community.photos[share.authorID],
                                               mine: community.isMine(share),
                                               canDelete: community.canDelete(share),
                                               showAuthor: community.author?.id == share.authorID ? nil : {
                                                   Task { await community.openPerson(of: share) }
                                               },
                                               open: { open(share) }, report: { report(share) }, delete: { delete(share) })
                        }
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
    }

    private var trimmedSearch: String { community.search.trimmingCharacters(in: .whitespaces) }

    @ViewBuilder private var empty: some View {
        if community.busy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Chargement des partages…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else if !trimmedSearch.isEmpty {
            CommunityMessage(symbol: "magnifyingglass",
                             title: String(localized: "Aucun partage pour « \(trimmedSearch.displaySafe(max: 30)) »"),
                             text: community.members.isEmpty
                                 ? String(localized: """
                                     Essaie un autre mot : un titre, une fenêtre de FL (Mixer, Playlist…), une action ou \
                                     le nom d'un membre.
                                     """)
                                 : String(localized: """
                                     Aucun titre ni aucune explication ne contient ce mot : choisis un membre plus haut \
                                     pour voir ses partages.
                                     """),
                             button: String(localized: "Effacer la recherche")) {
                community.search = ""
                Task { await community.reload() }
            }
        } else if community.author == nil, community.tab == .following {
            // Onglet « Abonnements » (11/11) : personne de suivi, ou rien de neuf.
            CommunityMessage(symbol: "person.2",
                             title: community.following.isEmpty ? String(localized: "Tu ne suis personne.")
                                 : String(localized: "Rien de nouveau."),
                             text: String(localized: "Suis un créateur : ses partages arrivent ici."),
                             button: String(localized: "Pour toi")) {
                Task { await community.choose(.forYou) }
            }
        } else if community.author == nil, community.tab == .mostAdded {
            CommunityMessage(symbol: "star",
                             title: String(localized: "Rien d'ajouté pour l'instant."),
                             text: String(localized: "Les partages ajoutés par les membres arrivent ici."),
                             button: String(localized: "Pour toi")) {
                Task { await community.choose(.forYou) }
            }
        } else if let author = community.author {
            CommunityMessage(symbol: "person.crop.circle",
                             title: String(localized: "Aucun partage de @\(author.username.displaySafe(max: 24))"),
                             text: community.kind == nil ? String(localized: "Ce membre n'a rien publié pour l'instant.")
                                 : String(localized: "Ce membre n'a rien publié pour l'instant de ce genre."),
                             button: String(localized: "Voir tout le monde")) {
                Task { await community.showEveryone() }
            }
        } else if community.kind != nil {
            CommunityMessage(symbol: community.kind?.symbol ?? "square.stack",
                             title: String(localized: "Rien de ce genre pour l'instant"),
                             text: community.kind == .macro ? String(localized: "Personne n'a encore partagé de macro.")
                                 : String(localized: "Personne n'a encore partagé de raccourcis."),
                             button: String(localized: "Tout afficher")) {
                community.kind = nil
                Task { await community.reload() }
            }
        } else {
            CommunityMessage(symbol: "sparkles", title: String(localized: "Encore aucun partage"),
                             text: String(localized: """
                                 Sois le premier : partage une macro qui te fait gagner du temps, avec une petite \
                                 explication pour les autres.
                                 """),
                             button: String(localized: "Partager une macro…")) { community.composing = true }
        }
    }
}

/// Un membre trouvé par son nom : toute la ligne ouvre ses partages.
private struct CommunityMemberRow: View {
    let member: CommunityMember
    let photo: NSImage?
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(photo: photo, username: member.username, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(member.username.displaySafe(max: 24))").fontWeight(.semibold).lineLimit(1)
                Text(member.shareCount == 1 ? String(localized: "1 partage")
                     : String(localized: "\(member.shareCount) partages"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .help("Voir tout ce que @\(member.username.displaySafe(max: 24)) a publié")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
    }
}

/// Recherche (au fil de la frappe) dans une capsule, puis les onglets du 11/11, et actualiser.
private struct CommunityFilters: View {
    @ObservedObject var community: CommunityStore
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Swiss.text)
                // Texte d'aide à l'encre (05/11 : « sous Orange… que ce soit écrit en noir »).
                TextField("Rechercher", text: $community.search,
                          prompt: Text("Chercher une macro, des raccourcis").foregroundColor(Swiss.text.opacity(0.75)))
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await community.reload() } }
                    .onChange(of: community.search) { _ in
                        searchTask?.cancel()
                        searchTask = Task {
                            try? await Task.sleep(nanoseconds: 450_000_000)
                            guard !Task.isCancelled else { return }
                            await community.reload()
                        }
                    }
            }
            // Maquette du 05/11 : recherche bordée de 2 points, pleine du fond ; filtres en cases collées, le choisi
            // plein d'encre.
            .font(.system(size: 14))
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(Rectangle().fill(Swiss.background))
            .overlay(Rectangle().strokeBorder(Swiss.text, lineWidth: 2))
            // Onglets du 11/11 (Pour toi, Abonnements, Les plus ajoutées, Les miens) à la place de Tout / Macros /
            // Raccourcis / Les miens.
            CommunityTabs(community: community)
            Button {
                Task { await community.reload() }
            } label: {
                Image(systemName: "arrow.clockwise").frame(width: 30, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .menuHover(tint: Swiss.text, cornerRadius: 0)
            .help("Actualiser : voir les derniers partages")
            .accessibilityLabel("Actualiser")
        }
        .disabled(community.busy)
    }
}

/// Un partage en carte (maquette du 30/10) : l'auteur et la date, le genre, le titre, deux lignes de l'explication,
/// « Voir » et le bouton bleu (tous deux ouvrent la fiche : rien ne s'ajoute sans l'avoir lue). Clic droit : les
/// partages de l'auteur, signaler, supprimer.
private struct CommunityShareCard: View {
    let share: Share
    /// Photo de l'auteur (nil : son initiale de couleur).
    let photo: NSImage?
    let mine: Bool
    let canDelete: Bool
    /// Voir tous les partages de l'auteur (nil : on les regarde déjà).
    let showAuthor: (() -> Void)?
    let open: () -> Void
    let report: () -> Void
    let delete: () -> Void

    /// Style suisse (01/11) : pas de carte, l'auteur et la date en petites capitales grises, la sorte à droite dans
    /// sa couleur, le titre en gras, deux lignes grises, « VOIR » et l'action côte à côte ; un trait fin dessous.
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AvatarView(photo: photo, username: share.authorName, size: 18)
                Button {
                    showAuthor?()
                } label: {
                    Text(verbatim: "@" + share.authorName.displaySafe(max: 24))
                        .swissLabel(size: 11)
                        .textCase(nil)
                        .lineLimit(1)                     // colonne étroite : le nom se raccourcit, rien ne passe à la ligne
                }
                .buttonStyle(.plain)
                .disabled(showAuthor == nil)
                .help("Voir tout ce que @\(share.authorName.displaySafe(max: 24)) a publié")
                Text(verbatim: "· " + CommunityText.day(share.createdAt))
                    .swissLabel(size: 11)
                    .fixedSize()
                Spacer(minLength: 8)
                Text(share.kind.label)
                    .swissLabel(Swiss.gray, size: 11)
                    .fixedSize()
            }
            Text(share.title.displaySafe(max: 80))
                .font(Swiss.title(24)).tracking(-1)
                .lineLimit(2)
            Text(share.notes.isEmpty ? " " : share.notes)
                .font(.system(size: 12.5))
                .foregroundStyle(Swiss.soft)
                .lineLimit(2, reservesSpace: true)
            // 11/11 : « ★ 4,6 · Ajoutée 312 fois » sur sa ligne (rien sans ajout ni note ; à côté des boutons, il était coupé).
            if let stats = CommunityStats.line(share) {
                Text(stats).swissLabel(Swiss.text, size: 10.5).lineLimit(1)
            }
            HStack(spacing: 0) {
                Button("Voir", action: open)
                    .secondaryButton()
                    .controlSize(.small)
                    .help("Lire l'explication et voir ce que fait ce partage, avant de l'ajouter")
                if mine {
                    Text("Partagé par toi").swissLabel(size: 10.5).padding(.leading, 12)
                } else {
                    Button(share.kind.addLabel, action: open)
                        .primaryButton()
                        .controlSize(.small)
                        .help("Lire la fiche, puis l'ajouter")
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
        // Maquette du 05/11 : une carte par partage (pleine du fond, trait fin ; noire sous Orange).
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Rectangle().fill(Swiss.background))
        .overlay(Rectangle().strokeBorder(Swiss.line, lineWidth: 1))
        .swissCard()
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .swissContextMenu {
            var items: [RightClickMenu.Item?] = []
            if let showAuthor {
                items.append(RightClickMenu.Item(title: String(localized: "Voir la page de @\(share.authorName.displaySafe(max: 24))"),
                                                 action: showAuthor))
            }
            if !mine { items.append(RightClickMenu.Item(title: String(localized: "Signaler…"), action: report)) }
            if canDelete {
                items.append(RightClickMenu.Item(title: mine ? String(localized: "Supprimer mon partage…")
                                                 : String(localized: "Supprimer (administrateur)…"),
                                                 destructive: true, action: delete))
            }
            return items
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Fiche d'un partage

/// Lire avant d'ajouter : explication de l'auteur, chaque étape (ou chaque raccourci), ce qu'il faut savoir.
private struct CommunityShareDetail: View {
    @ObservedObject var community: CommunityStore
    let store: Store
    let share: Share
    let added: (ToastMessage) -> Void
    let report: () -> Void
    /// Ferme la page posée au-dessus (10/11 : plus de feuille de macOS).
    let close: () -> Void
    /// Rouvre la fiche (« Noter » du message qui suit l'ajout, 11/11).
    var rateLater: () -> Void = {}
    @State private var content = Content.loading
    /// Étoiles (11/11) : seulement si je l'ai ajouté et que ce n'est pas le mien ; ma note (nil : pas notée).
    @State private var canRate = false
    @State private var stars: Int?

    enum Content {
        case loading
        case macro(MacroExchange.Preview)
        case profile(ImportPreview)
        case failed(String)
    }

    private var mine: Bool { community.isMine(share) }

    private var ready: Bool {
        switch content {
        case .macro, .profile: return true
        case .loading, .failed: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(share.title.displaySafe(max: 80)).font(Swiss.title(22)).tracking(Swiss.titleTracking(22))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(CommunityText.byline(share)).font(.system(size: 12)).foregroundStyle(.secondary)
                    if let stats = CommunityStats.line(share) {
                        Text(stats).swissLabel(Swiss.text, size: 10.5).padding(.top, 2)
                    }
                    if community.author?.id != share.authorID {
                        Button("Voir la page de @\(share.authorName.displaySafe(max: 24))") {
                            close()
                            Task { await community.openPerson(of: share) }
                        }
                        .buttonStyle(SwissLinkButtonStyle())
                        .font(.system(size: 12))
                    }
                }
            }
            .padding(20)
            Rectangle().fill(Swiss.line).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    part(String(localized: "L'explication de @\(share.authorName.displaySafe(max: 24))")) {
                        Text(share.notes.isEmpty ? String(localized: "L'auteur n'a pas écrit d'explication.") : share.notes)
                            .font(.system(size: 13))
                            .foregroundStyle(share.notes.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    part(share.kind == .macro ? String(localized: "Ce que fait la macro, étape par étape")
                         : String(localized: "Les raccourcis qu'il contient")) {
                        steps
                    }
                    if !notes.isEmpty {
                        part(String(localized: "Bon à savoir")) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(notes, id: \.self) { line in
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Rectangle().fill(Swiss.text).frame(width: 5, height: 5)
                                            .alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 3 }
                                        Text(line)
                                            .font(.system(size: 12))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(Swiss.line).frame(height: 1)
            // 11/11 : « Ta note », seulement après l'avoir ajouté (jamais le sien).
            if canRate {
                CommunityStarsRow(stars: stars) { n in
                    let before = stars
                    stars = n
                    Task {
                        let sent = await community.rate(share, stars: n)
                        if !sent { stars = before }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                Rectangle().fill(Swiss.line).frame(height: 1)
            }
            HStack {
                if !mine {
                    Button("Signaler…", action: report)
                        .secondaryButton()
                        .help("Prévenir les administrateurs : partage dangereux, trompeur ou offensant")
                }
                Spacer()
                Button("Fermer") { close() }
                    .secondaryButton()
                    .keyboardShortcut(.cancelAction)
                Button(share.kind.addLabel) { add() }
                    .primaryButton()
                    .keyboardShortcut(.defaultAction)
                    .disabled(!ready)
            }
            .padding(16)
        }
        .frame(width: 540)
        .frame(maxHeight: 580)
        .task {
            await load()
            if let rating = await community.myRating(of: share) {
                canRate = rating.added
                stars = rating.stars
            }
        }
    }

    /// Une partie de la fiche : son titre en petites capitales souligné d'un trait fin (comme Windows), puis le texte.
    private func part<C: View>(_ title: String, @ViewBuilder _ body: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).swissLabel(Swiss.text)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .swissRule(Swiss.line)
            body()
        }
    }

    @ViewBuilder private var steps: some View {
        switch content {
        case .loading:
            Text("Lecture du partage…").font(.system(size: 12)).foregroundStyle(Swiss.gray)
        case .failed(let why):
            SwissWarning(String(localized: "Ce partage ne peut pas être ajouté : \(why)"))
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
        case .macro(let preview):
            listed(preview.lines)
        case .profile(let preview):
            listed(preview.summary)
        }
    }

    /// Lignes de l'aperçu d'import, telles quelles (celles d'une macro sont déjà numérotées : « 12.1. … »).
    private func listed(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Rectangle().fill(Color.primary.opacity(0.05)))
    }

    /// Ce qu'il faut savoir avant de s'en servir.
    private var notes: [String] {
        switch content {
        case .macro(let preview):
            var out = preview.warnings
            if preview.sensitiveCount > 0 {
                out.append(preview.sensitiveCount == 1
                           ? String(localized: "1 étape tape des touches, clique ou ouvre un fichier : relis-la dans le créateur.")
                           : String(localized: """
                             \(preview.sensitiveCount) étapes tapent des touches, cliquent ou ouvrent des fichiers : \
                             relis-les dans le créateur.
                             """))
            }
            out.append(String(localized: "Elle arrive sans raccourci : rien ne se lance tant que tu ne lui en as pas choisi un."))
            return out
        case .profile(let preview):
            var out = [String(localized: """
                Tes raccourcis actuels sont remplacés par ceux-ci. Tu peux annuler juste après, depuis la \
                notification en bas de la fenêtre.
                """)]
            if !preview.rejected.isEmpty {
                out.append(String(localized: "Refusés par sécurité : \(preview.rejected.joined(separator: " ; "))"))
            }
            return out
        case .loading, .failed:
            return []
        }
    }

    private func load() async {
        guard let data = await community.payload(of: share) else {
            content = .failed(community.error ?? String(localized: "téléchargement impossible."))
            return
        }
        do {
            switch share.kind {
            case .macro: content = .macro(try MacroExchange.prepareImport(data, layout: store.layout))
            case .profile: content = .profile(try store.prepareImport(data))
            }
        } catch {
            content = .failed(error.localizedDescription)
        }
    }

    private func add() {
        guard !community.demo else {                      // mode capture : rien n'est ajouté
            close()
            return
        }
        // 11/11 : l'ajout compte une fois sur le serveur, et le message propose « Noter » (rouvre la fiche, étoiles).
        let rate: (title: String, run: () -> Void)? = community.social && !mine
            ? (String(localized: "Noter"), rateLater) : nil
        switch content {
        case .macro(let preview):
            var doc = preview.doc
            doc.name = store.library.uniqueName(doc.name)
            _ = store.library.add(doc)
            added(ToastMessage(text: String(localized: """
                « \(doc.name.displaySafe(max: 40)) » ajoutée à tes macros : choisis-lui un raccourci \
                dans la page Macros
                """), undo: nil, action: rate))
        case .profile(let preview):
            let model = store
            model.applyImport(preview)
            added(ToastMessage(text: String(localized: "Raccourcis de @\(share.authorName.displaySafe(max: 24)) en place"),
                               undo: { model.undoReplace() }, action: rate))
        case .loading, .failed:
            return
        }
        let counted = share
        Task { await community.recordAdd(counted) }
        close()
    }
}

// MARK: - Connexion et création de compte

/// Connexion, création du compte ou code reçu par mail : une carte au centre (maquette du 30/10). Un seul compte pour
/// la Communauté et la sauvegarde en ligne (page Mon compte).
struct CommunitySignIn: View {
    @ObservedObject var community: CommunityStore
    /// Page qui montre la carte (Mon compte ou Communauté).
    var page: SidebarItem = .community
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var code = ""
    @State private var newPassword = ""
    @State private var nameCheck: CommunityStore.NameCheck = .empty

    private var creating: Bool { community.creatingAccount }

    var body: some View {
        // Sans barre de défilement visible (elle apparaissait en changeant d'onglet).
        ScrollView(.vertical, showsIndicators: false) {
            Group {
                if let pending = community.pendingCode {
                    codeCard(pending)
                } else {
                    signInCard
                }
            }
            .softSwitch(community.pendingCode == nil ? 0 : 1, quick: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 26)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .glassListBackground()
        .onChange(of: community.pendingCode) { _ in
            code = ""
            newPassword = ""
        }
    }

    // MARK: Se connecter / Créer un compte

    /// 05/11 (« faut que tu me fasses la page de avant mon compte… un truc très beau ») : à gauche, ce que donne un
    /// compte en trois lignes numérotées ; à droite, le formulaire (onglets, champs, bouton principal). L'un sous
    /// l'autre si la fenêtre est étroite.
    private var signInCard: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 44) {
                AuthPitch().frame(minWidth: 280, maxWidth: 400, alignment: .leading)
                signInForm
            }
            VStack(alignment: .leading, spacing: 30) {
                AuthPitch()
                signInForm
            }
        }
    }

    private var signInForm: some View {
        AuthCard {
            AuthTabs(creating: $community.creatingAccount)
            VStack(alignment: .leading, spacing: 18) {
                if creating {
                    AuthField(title: String(localized: "Pseudo"), text: $username, prompt: String(localized: "ton.pseudo"),
                              prefix: "@") {
                        UsernameStatus(check: nameCheck)
                    }
                    .modifier(UsernameChecker(community: community, name: username, check: $nameCheck))
                    if case .invalid(let why) = nameCheck { hint(why) }
                }
                AuthField(title: String(localized: "E-mail"), text: $email, prompt: String(localized: "toi@exemple.com"))
                AuthField(title: String(localized: "Mot de passe"), text: $password,
                          prompt: creating ? String(localized: "8 caractères au moins") : String(localized: "Ton mot de passe"),
                          secure: true, link: creating ? nil : forgotLink)
                if creating { PasswordRules(password: password) }
            }
            Button(creating ? String(localized: "Créer mon compte") : String(localized: "Se connecter")) { submit() }
                .buttonStyle(AuthPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || community.busy)
                .overlay(alignment: .trailing) {
                    if community.busy { ProgressView().controlSize(.small).padding(.trailing, 18) }
                }
            CommunityStatus(community: community)
            if creating {
                Text("Les autres voient ton pseudo et ta photo, jamais ton e-mail.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Swiss.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var forgotLink: (title: String, action: () -> Void) {
        (String(localized: "Mot de passe oublié ?"), { Task { await community.resetPassword(email: email) } })
    }

    // MARK: Code reçu par mail

    /// Code reçu par mail : confirmer l'inscription, ou choisir un nouveau mot de passe.
    private func codeCard(_ pending: CommunityStore.PendingCode) -> some View {
        let recovery = pending.kind == .recovery
        return AuthCard {
            VStack(alignment: .leading, spacing: 8) {
                SwissPageTitle(text: recovery ? String(localized: "Nouveau mot de passe") : String(localized: "Vérifie tes mails"),
                               size: 28)
                Text("Code envoyé à \(Text(pending.email.displaySafe(max: 60)).fontWeight(.semibold))")
                    .font(.system(size: 13))
                    .foregroundStyle(Swiss.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CodeBoxes(code: $code)
            if recovery {
                VStack(alignment: .leading, spacing: 10) {
                    AuthField(title: String(localized: "Nouveau mot de passe"), text: $newPassword, secure: true)
                    PasswordRules(password: newPassword)
                }
            }
            Button(recovery ? String(localized: "Changer le mot de passe") : String(localized: "Valider")) {
                let typed = code, chosen = newPassword
                Task {
                    if recovery {
                        await community.finishReset(code: typed, newPassword: chosen)
                    } else {
                        await community.confirmSignup(code: typed)
                    }
                }
            }
            .buttonStyle(AuthPrimaryButtonStyle())
            .keyboardShortcut(.defaultAction)
            .disabled(CommunityRules.code(code) == nil || (recovery && CommunityRules.passwordProblem(newPassword) != nil)
                      || community.busy)
            .overlay(alignment: .trailing) {
                if community.busy { ProgressView().controlSize(.small).padding(.trailing, 18) }
            }
            HStack(spacing: 18) {
                AuthLinkButton(title: String(localized: "Renvoyer le code")) { Task { await community.resendCode() } }
                AuthLinkButton(title: String(localized: "Changer d'adresse")) {
                    email = pending.email
                    community.cancelCode()
                }
            }
            CommunityStatus(community: community)
            VStack(spacing: 6) {
                Text("Rien reçu ? Regarde dans les spams.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                if !recovery {
                    // Mail avec un lien au lieu d'un code : le lien confirme l'adresse (la page affichée après peut ne
                    // pas s'ouvrir), il ne reste qu'à se connecter.
                    HStack(spacing: 4) {
                        Text("Reçu un lien au lieu d'un code ?").foregroundStyle(.secondary)
                        Button("J'ai cliqué sur le lien") {
                            email = pending.email
                            community.confirmedByLink()
                        }
                        .buttonStyle(SwissLinkButtonStyle())
                    }
                    .font(.system(size: 11))
                }
            }
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
    }

    private var canSubmit: Bool {
        let mail = email.trimmingCharacters(in: .whitespaces)
        guard creating else { return !mail.isEmpty && !password.isEmpty }
        return CommunityRules.usernameProblem(username.trimmingCharacters(in: .whitespaces)) == nil && nameCheck != .taken
            && CommunityRules.emailProblem(mail) == nil && CommunityRules.passwordProblem(password) == nil
    }

    private func submit() {
        let mail = email.trimmingCharacters(in: .whitespaces)
        let name = username.trimmingCharacters(in: .whitespaces)
        let pass = password
        Task {
            if creating {
                await community.signUp(email: mail, password: pass, username: name)
            } else {
                await community.signIn(email: mail, password: pass)
            }
            if community.session != nil { password = "" }
        }
    }
}

// MARK: - Partager

private struct CommunityPublishSheet: View {
    @ObservedObject var community: CommunityStore
    @ObservedObject var library: MacroLibraryStore
    let profile: () -> Data?
    /// Ferme la page posée au-dessus (10/11 : plus de feuille de macOS).
    let close: () -> Void
    @State private var kind = ShareKind.macro
    @State private var macroID: UUID?
    @State private var title = ""
    @State private var notes = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Partager avec la Communauté").font(Swiss.title(22)).tracking(Swiss.titleTracking(22))
                Text("Les autres pourront lire ton explication, voir chaque étape, puis l'ajouter chez eux.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            field(String(localized: "Quoi")) {
                SwissSegmented(selection: $kind, options: [
                    (value: ShareKind.macro, label: String(localized: "Une macro")),
                    (value: ShareKind.profile, label: String(localized: "Tous mes raccourcis")),
                ])
                Text(kind == .macro
                     ? String(localized: "La macro choisie, avec ses étapes.")
                     : String(localized: "Ton jeu de raccourcis complet : les autres pourront le mettre à la place du leur."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if kind == .macro {
                field(String(localized: "Macro")) {
                    if library.macros.isEmpty {
                        Text("Tu n'as pas encore de macro : crée-en une dans la page Macros.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        SwissPicker(selection: $macroID,
                                    current: library.macros.first { $0.id == macroID }?.name.displaySafe(max: 50)
                                        ?? String(localized: "Choisir…"),
                                    entries: [SwissPickerEntry<UUID?>.option(nil, String(localized: "Choisir…"))]
                                        + library.macros.map { SwissPickerEntry<UUID?>.option($0.id, $0.name.displaySafe(max: 50)) })
                        .labelsHidden()
                    }
                }
            }
            field(String(localized: "Titre"), count: "\(trimmedTitle.count)/\(CommunityRules.titleRange.upperBound)") {
                TextField("Titre", text: $title, prompt: Text("ex. Armer la piste et lancer l'enregistrement"))
                    .labelsHidden()
                    .swissField()
            }
            field(String(localized: "Explication"), count: "\(notes.count)/\(CommunityRules.maxNotes)") {
                TextEditor(text: $notes)
                    .font(.system(size: 12))
                    .frame(minHeight: 110)
                    .overlay(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text(String(localized: """
                                À quoi elle sert, où l'utiliser dans FL (Mixer, Playlist…), ce qu'il faut faire avant \
                                de la lancer.
                                """))
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .swissTextArea()
            }
            VStack(alignment: .leading, spacing: 4) {
                Label(kind == .macro
                      ? String(localized: "Partagé : la macro, le titre, ton explication, ton nom d'utilisateur.")
                      : String(localized: "Partagé : tes raccourcis, le titre, ton explication, ton nom d'utilisateur."),
                      systemImage: "eye")
                Label("Jamais partagé : ton mail, tes positions apprises, les chemins de tes fichiers.",
                      systemImage: "lock")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            if let problem = problem ?? limitProblem {
                SwissWarning(problem)
                    .font(.system(size: 12))
            }
            HStack {
                Spacer()
                Button("Annuler") { close() }
                    .secondaryButton()
                    .keyboardShortcut(.cancelAction)
                Button("Publier") { Task { await publish() } }
                    .primaryButton()
                    .keyboardShortcut(.defaultAction)
                    .disabled(community.busy || !canPublish)
                    .help(canPublish ? String(localized: "Publier pour tous les membres de la Communauté")
                          : kind == .macro && macroID == nil ? String(localized: "Choisis d'abord la macro à partager")
                          : String(localized: "Écris un titre (\(CommunityRules.titleRange.lowerBound) caractères au moins)"))
            }
        }
        .padding(20)
        .frame(width: 480)
        .onChange(of: macroID) { id in
            if title.isEmpty, let doc = id.flatMap(library.doc) { title = String(doc.name.prefix(80)) }
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Tout est rempli : le bouton « Publier » s'active.
    private var canPublish: Bool {
        (kind == .profile || macroID != nil) && CommunityRules.titleRange.contains(trimmedTitle.count)
            && notes.count <= CommunityRules.maxNotes
    }

    /// Saisie hors des limites (rien tant que le champ est vide : ce qui reste à remplir n'est pas une erreur).
    private var limitProblem: String? {
        if !trimmedTitle.isEmpty, !CommunityRules.titleRange.contains(trimmedTitle.count) {
            return String(localized: """
                Titre : \(CommunityRules.titleRange.lowerBound) à \(CommunityRules.titleRange.upperBound) caractères.
                """)
        }
        if notes.count > CommunityRules.maxNotes {
            return String(localized: "Explication : \(CommunityRules.maxNotes) caractères au plus.")
        }
        return nil
    }

    private func field<C: View>(_ label: String, count: String? = nil, @ViewBuilder _ body: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.system(size: 12, weight: .semibold))
                Spacer()
                if let count { Text(count).font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary) }
            }
            body()
        }
    }

    private func publish() async {
        let payload: Data?
        switch kind {
        case .macro:
            guard let doc = macroID.flatMap(library.doc) else {
                problem = String(localized: "Choisis la macro à partager.")
                return
            }
            payload = try? MacroExchange.export(doc, appVersion: MacroFileActions.appVersion)
        case .profile:
            payload = profile()
        }
        guard let payload else {
            problem = String(localized: "Export impossible.")
            return
        }
        if await community.publish(kind: kind, title: title, notes: notes, payload: payload) {
            close()
        } else {
            problem = community.error
        }
    }
}

// MARK: - Signaler

private struct CommunityReportSheet: View {
    @ObservedObject var community: CommunityStore
    let share: Share
    /// Ferme la page posée au-dessus (10/11 : plus de feuille de macOS).
    let close: () -> Void
    @State private var reason = Reason.danger
    @State private var details = ""

    enum Reason: String, CaseIterable, Identifiable {
        case danger = "Dangereux : supprime, écrase ou envoie des choses sans prévenir"
        case misleading = "Ne fait pas ce que dit son explication"
        case offensive = "Contenu offensant"
        case spam = "Publicité ou spam"
        case other = "Autre"

        var id: String { rawValue }

        /// Raison affichée ; le rawValue, en français, part tel quel au serveur.
        var label: String {
            switch self {
            case .danger: return String(localized: "Dangereux : supprime, écrase ou envoie des choses sans prévenir")
            case .misleading: return String(localized: "Ne fait pas ce que dit son explication")
            case .offensive: return String(localized: "Contenu offensant")
            case .spam: return String(localized: "Publicité ou spam")
            case .other: return String(localized: "Autre")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Signaler « \(share.title.displaySafe(max: 40)) »").font(Swiss.title(22)).tracking(Swiss.titleTracking(22))
                Text("Les administrateurs le relisent et le retirent s'il le faut. L'auteur ne sait pas qui l'a signalé.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SwissRadioGroup(selection: $reason, options: Reason.allCases.map { (value: $0, label: $0.label) })
            TextField("Détails", text: $details, prompt: Text("Précisions (facultatif)"))
                .swissField()
            HStack {
                Spacer()
                Button("Annuler") { close() }
                    .secondaryButton()
                    .keyboardShortcut(.cancelAction)
                Button("Signaler") {
                    Task {
                        await community.report(share, reason: text)
                        if community.error == nil { close() }
                    }
                }
                .primaryButton()
                .disabled(community.busy)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    /// Raison envoyée (3 à 500 caractères, comme le veut le serveur).
    private var text: String {
        let extra = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((extra.isEmpty ? reason.rawValue : reason.rawValue + " : " + extra).prefix(500))
    }
}
