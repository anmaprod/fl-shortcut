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
                                 text: "")
            } else if community.session == nil {
                // Maquette « Minimal » : la phrase et « Se connecter » (la connexion est dans Compte).
                VStack(alignment: .leading, spacing: 24) {
                    Text("Connecte-toi pour voir la Communauté.").font(Swiss.font(24, .regular)).foregroundStyle(Swiss.text)
                    MinimalButton(title: String(localized: "Se connecter")) { AccountLink.shared.pending = true }.fixedSize()
                }
                .frame(maxWidth: 1088, alignment: .leading)
                .padding(.horizontal, ReadableLayout.inset)
                .padding(.top, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        let text = String(localized: "Le partage disparaît pour tout le monde.")
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
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
    @EnvironmentObject var store: Store
    let open: (Share) -> Void
    let report: (Share) -> Void
    let delete: (Share) -> Void

    /// Maquette « plus lisible » du 16/11 : les onglets et la recherche sur une ligne, puis les partages en cases sur
    /// deux colonnes (plus de vitrine à part sur « Pour toi »).
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
                if community.shares.isEmpty {
                    empty
                        .frame(maxWidth: .infinity)
                        .background(MockPlate(cornerRadius: 14)).swissCard()
                } else {
                    // Maquette du 16/11 : deux colonnes de cases qui partagent leurs traits (plus de numéro ni de
                    // sorte en haut : « enlève toutes les fioritures », 16/11).
                    // Maquette « Minimal » (21/11) : deux colonnes à 32 points d'écart, chaque case sur son seul trait du bas.
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 31, alignment: .top),
                                        GridItem(.flexible(), spacing: 0, alignment: .top)], spacing: 0) {
                        ForEach(community.shares) { share in
                            CommunityShareCard(share: share, photo: community.photos[share.authorID],
                                               mine: community.isMine(share),
                                               added: store.library.macros.contains { $0.origin == .community(share.id) },
                                               canDelete: community.canDelete(share),
                                               showAuthor: community.author?.id == share.authorID ? nil : {
                                                   Task { await community.openPerson(of: share) }
                                               },
                                               open: { open(share) }, report: { report(share) }, delete: { delete(share) })
                        }
                    }

                }
            }
            .frame(maxWidth: ReadableLayout.maxWidth, alignment: .leading)
            .padding(.horizontal, ReadableLayout.inset)
            .padding(.top, 10)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                             text: "",
                             button: String(localized: "Les plus ajoutées")) {
                Task { await community.choose(.mostAdded) }
            }
        } else if community.author == nil, community.tab == .mostAdded {
            CommunityMessage(symbol: "star",
                             title: String(localized: "Rien d'ajouté pour l'instant."),
                             text: "")
        } else if let author = community.author {
            CommunityMessage(symbol: "person.crop.circle",
                             title: String(localized: "Aucun partage de @\(author.username.displaySafe(max: 24))"),
                             text: "",
                             button: String(localized: "Voir tout le monde")) {
                Task { await community.showEveryone() }
            }
        } else if community.kind != nil {
            CommunityMessage(symbol: community.kind?.symbol ?? "square.stack",
                             title: String(localized: "Rien de ce genre pour l'instant"),
                             text: "",
                             button: String(localized: "Tout afficher")) {
                community.kind = nil
                Task { await community.reload() }
            }
        } else {
            CommunityMessage(symbol: "sparkles", title: String(localized: "Encore aucun partage"),
                             text: "",
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

    /// Maquette « Minimal » (21/11) : les onglets à gauche, « Chercher » à droite sur un seul trait, puis le trait
    /// d'encre au-dessus des cases.
    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            CommunityTabs(community: community)
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                TextField("Chercher", text: $community.search,
                          prompt: Text("Chercher").foregroundColor(Swiss.faintText))
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
            .font(Swiss.font(15, .regular))
            .frame(width: 233, height: 34)
            .overlay(alignment: .bottom) { Rectangle().fill(Swiss.keyLine).frame(height: 1) }
        }
        .padding(.bottom, 14)
        .overlay(alignment: .bottom) { Rectangle().fill(Swiss.text).frame(height: 1) }
        .disabled(community.busy)
    }
}

/// Un partage en case (maquette « plus lisible » du 16/11) : son numéro et sa sorte en haut, le titre en gras en bas,
/// puis « @pseudo · ★ 4,6 · 312 ajouts » et « AJOUTER » (qui ouvre la fiche : rien ne s'ajoute sans l'avoir lue).
/// Toute la case ouvre la fiche ; clic droit : la page de l'auteur, signaler, supprimer.
private struct CommunityShareCard: View {
    let share: Share
    /// Photo de l'auteur (nil : son initiale de couleur).
    let photo: NSImage?
    let mine: Bool
    /// Déjà dans mes macros (ajoutée depuis la Communauté, 19/11) : « Ajoutée ✓ » à la place d'« Ajouter ».
    var added = false
    let canDelete: Bool
    /// Voir tous les partages de l'auteur (nil : on les regarde déjà).
    let showAuthor: (() -> Void)?
    let open: () -> Void
    let report: () -> Void
    let delete: () -> Void
    @State private var hovering = false

    var body: some View {
        // 19/11 (maquette « Minimal ») : qui, le nom, puis la note et les ajouts en grand ; plus de détail ni de date.
        VStack(alignment: .leading, spacing: 12) {
            if showAuthor != nil || !mine {
                Button {
                    showAuthor?()
                } label: {
                    HStack(spacing: 8) {
                        AvatarView(photo: photo, username: share.authorName, size: 20, ink: true)
                        Text(verbatim: share.authorName.displaySafe(max: 24))
                            .font(Swiss.font(13, .semibold))
                            .foregroundStyle(Swiss.text)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(showAuthor == nil)
                .help("Voir tout ce que @\(share.authorName.displaySafe(max: 24)) a publié")
            }
            Text(share.title.displaySafe(max: 80))
                .font(Swiss.font(19, .medium)).tracking(-0.2)
                .foregroundStyle(Swiss.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            HStack(alignment: .center, spacing: 12) {
                CommunityBigStats(share: share)
                Spacer(minLength: 8)
                if added {
                    Text("Ajoutée ✓").font(Swiss.font(13, .semibold)).foregroundStyle(Swiss.text).fixedSize()
                } else if !mine {
                    // Maquette « Minimal » : le mot tel quel (pas en capitales), bordé d'encre ; plein au survol.
                    Button(share.kind == .macro ? String(localized: "Ajouter") : String(localized: "Utiliser"), action: open)
                        .buttonStyle(MinimalOutlineButtonStyle())
                        .fixedSize()
                        .help("Lire la fiche, puis l'ajouter")
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
        .background(Rectangle().fill(hovering ? Swiss.faint : Color.clear))
        .overlay(alignment: .bottom) { Rectangle().fill(Swiss.keyLine).frame(height: 1).allowsHitTesting(false) }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
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
    /// Ma note en demi-étoiles (1 à 10, 19/11).
    @State private var half: Int?
    /// Redessine la fiche après « Supprimer de mes macros ».
    @State private var libraryChanged = 0

    /// La macro de ce partage déjà dans mes macros (ajoutée depuis la Communauté, 19/11).
    private var ownedDoc: MacroDoc? {
        _ = libraryChanged
        guard share.kind == .macro else { return nil }
        return store.library.macros.first { $0.origin == .community(share.id) }
    }

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
                    part(share.kind == .macro ? String(localized: "Étapes") : String(localized: "Raccourcis")) {
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
                CommunityStarsRow(half: half) { n in
                    let before = half
                    half = n
                    Task {
                        let sent = await community.rate(share, half: n)
                        if !sent { half = before }
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
                if let doc = ownedDoc {
                    // 19/11 : ajoutée depuis la Communauté, elle se retire d'ici (avec une question, comme toute suppression).
                    Text("Dans tes macros ✓").font(.system(size: 14, weight: .semibold)).foregroundStyle(Swiss.text)
                    Button("Supprimer de mes macros") { removeFromMacros(doc) }
                        .secondaryButton()
                } else {
                    Button(share.kind.addLabel) { add() }
                        .primaryButton()
                        .keyboardShortcut(.defaultAction)
                        .disabled(!ready)
                }
            }
            .padding(16)
        }
        .frame(width: 540)
        .frame(maxHeight: 580)
        .task {
            await load()
            if let rating = await community.myRating(of: share) {
                canRate = rating.added
                half = rating.half
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
                           ? String(localized: "1 étape à relire dans le créateur.")
                           : String(localized: "\(preview.sensitiveCount) étapes à relire dans le créateur."))
            }
            return out
        case .profile(let preview):
            var out = [String(localized: "Tes raccourcis actuels sont remplacés par ceux-ci.")]
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
            case .macro: content = .macro(try MacroExchange.prepareImport(data, layout: store.layout,
                                                                         installed: MacroExchange.installedPluginNames))
            case .profile: content = .profile(try store.prepareImport(data))
            }
        } catch {
            content = .failed(error.localizedDescription)
        }
    }

    /// « Supprimer de mes macros » (19/11) : la macro ajoutée depuis ce partage et ses raccourcis, après une question.
    private func removeFromMacros(_ doc: MacroDoc) {
        let shown = doc.name.displaySafe(max: 40)
        guard Dialogs.choose(String(localized: "Supprimer « \(shown) » de tes macros ?"), "",
                             [String(localized: "Supprimer"), String(localized: "Annuler")], destructive: 0) == 0
        else { return }
        let shortcuts = store.remaps(forMacro: doc.id)
        guard store.library.remove(doc.id) != nil else { return }
        for r in shortcuts { store.delete(r.id) }
        libraryChanged += 1
        added(ToastMessage(text: String(localized: "« \(shown) » supprimée de tes macros"), undo: nil))
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
            // Presets joints au partage : rangés dans Documents › FL Shortcuts › Presets (jamais par-dessus un autre).
            if let why = MacroExchange.writeAttached(preview.files) { Dialogs.inform(String(localized: "Preset"), why) }
            doc.name = store.library.uniqueName(doc.name)
            doc.origin = .community(share.id)          // 19/11 : pour « Supprimer de mes macros »
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
            .frame(maxWidth: 1088, alignment: .leading)
            .padding(.horizontal, ReadableLayout.inset)
            .padding(.top, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 32)
        }
        .glassListBackground()
        .onChange(of: community.pendingCode) { _ in
            code = ""
            newPassword = ""
        }
    }

    // MARK: Se connecter / Créer un compte (maquette « Minimal »)

    /// « Mot de passe oublié » : l'adresse, puis le code reçu par mail.
    @State private var forgot = false

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(forgot ? String(localized: "Mot de passe oublié") : creating ? String(localized: "Créer un compte") : String(localized: "Connexion"))
                .font(Swiss.font(48, .semibold)).tracking(-1.4).foregroundStyle(Swiss.text)
            MinimalField(title: String(localized: "Adresse mail"), text: $email)
            if creating && !forgot {
                MinimalField(title: String(localized: "Pseudo"), text: $username)
                    .modifier(UsernameChecker(community: community, name: username, check: $nameCheck))
                if case .invalid(let why) = nameCheck { hint(why) }
                if nameCheck == .taken { hint(String(localized: "Ce pseudo est déjà pris.")) }
            }
            if !forgot {
                MinimalField(title: String(localized: "Mot de passe"), text: $password, secure: true)
                if creating, let why = password.isEmpty ? nil : CommunityRules.passwordProblem(password) { hint(why) }
            }
            HStack(spacing: 16) {
                MinimalButton(title: forgot || creating ? String(localized: "Recevoir le code") : String(localized: "Se connecter")) { submit() }
                    .fixedSize()
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit || community.busy)
                    .opacity(!canSubmit || community.busy ? 0.4 : 1)
                if community.busy { ProgressView().controlSize(.small) }
            }
            .padding(.top, 32)
            CommunityStatus(community: community).padding(.top, 12)
            HStack(spacing: 20) {
                if creating || forgot {
                    MinimalLink(title: String(localized: "J'ai déjà un compte")) { community.creatingAccount = false; forgot = false }
                } else {
                    MinimalLink(title: String(localized: "Créer un compte")) { community.creatingAccount = true }
                    MinimalLink(title: String(localized: "Mot de passe oublié ?"), color: Swiss.gray) { forgot = true }
                }
            }
            .padding(.top, 24)
        }
        .frame(maxWidth: 480, alignment: .leading)
    }

    // MARK: Code reçu par mail

    /// Code reçu par mail : confirmer l'inscription, ou choisir un nouveau mot de passe (maquette « Minimal »).
    private func codeCard(_ pending: CommunityStore.PendingCode) -> some View {
        let recovery = pending.kind == .recovery
        return VStack(alignment: .leading, spacing: 0) {
            Text(recovery ? String(localized: "Mot de passe oublié") : String(localized: "Créer un compte"))
                .font(Swiss.font(48, .semibold)).tracking(-1.4).foregroundStyle(Swiss.text)
            Text("Code envoyé à \(pending.email.displaySafe(max: 60)).")
                .font(Swiss.font(14, .regular)).foregroundStyle(Swiss.text).padding(.top, 16)
            CodeBoxes(code: $code).padding(.top, 24)
            if recovery {
                MinimalField(title: String(localized: "Nouveau mot de passe"), text: $newPassword, secure: true)
                if !newPassword.isEmpty, let why = CommunityRules.passwordProblem(newPassword) { hint(why) }
            }
            HStack(spacing: 16) {
                MinimalButton(title: String(localized: "Valider")) {
                    let typed = code, chosen = newPassword
                    Task {
                        if recovery {
                            await community.finishReset(code: typed, newPassword: chosen)
                        } else {
                            await community.confirmSignup(code: typed)
                        }
                    }
                }
                .fixedSize()
                .keyboardShortcut(.defaultAction)
                .disabled(CommunityRules.code(code) == nil || (recovery && CommunityRules.passwordProblem(newPassword) != nil)
                          || community.busy)
                MinimalLink(title: String(localized: "Renvoyer le code")) { Task { await community.resendCode() } }
                if community.busy { ProgressView().controlSize(.small) }
            }
            .padding(.top, 32)
            CommunityStatus(community: community).padding(.top, 12)
            MinimalLink(title: String(localized: "J'ai déjà un compte")) {
                email = pending.email
                forgot = false
                community.creatingAccount = false
                community.cancelCode()
            }
            .padding(.top, 24)
        }
        .frame(maxWidth: 480, alignment: .leading)
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
    }

    private var canSubmit: Bool {
        let mail = email.trimmingCharacters(in: .whitespaces)
        if forgot { return CommunityRules.emailProblem(mail) == nil }
        guard creating else { return !mail.isEmpty && !password.isEmpty }
        return CommunityRules.usernameProblem(username.trimmingCharacters(in: .whitespaces)) == nil && nameCheck != .taken
            && CommunityRules.emailProblem(mail) == nil && CommunityRules.passwordProblem(password) == nil
    }

    private func submit() {
        let mail = email.trimmingCharacters(in: .whitespaces)
        let name = username.trimmingCharacters(in: .whitespaces)
        let pass = password
        Task {
            if forgot {
                await community.resetPassword(email: mail)
            } else if creating {
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
            Text("Partager avec la Communauté").font(Swiss.title(22)).tracking(Swiss.titleTracking(22))
            field(String(localized: "Quoi")) {
                SwissSegmented(selection: $kind, options: [
                    (value: ShareKind.macro, label: String(localized: "Une macro")),
                    (value: ShareKind.profile, label: String(localized: "Tous mes raccourcis")),
                ])
            }
            if kind == .macro {
                field(String(localized: "Macro")) {
                    if library.macros.isEmpty {
                        Text("Aucune macro.")
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
                // 20/11 : la case grandit avec le texte, jamais redimensionnable à la main.
                GrowingTextArea(text: $notes, placeholder: String(localized: "À quoi elle sert"), minLines: 5)
            }
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
    /// 19/11 (maquette « Minimal ») : une case par raison, plusieurs possibles ; « Autre » ouvre « Pourquoi ? ».
    @State private var picked: Set<Reason> = []
    @State private var other = false
    @State private var details = ""

    enum Reason: String, CaseIterable, Identifiable {
        case danger = "Dangereux pour mon projet"
        case broken = "Ne marche pas"
        case misleading = "Ne fait pas ce que dit le titre"
        case offensive = "Titre ou photo choquant"
        case spam = "Pub ou spam"
        case copy = "Copie du travail de quelqu'un"

        var id: String { rawValue }

        /// Raison affichée ; le rawValue, en français, part tel quel au serveur.
        var label: String {
            switch self {
            case .danger: return String(localized: "Dangereux pour mon projet")
            case .broken: return String(localized: "Ne marche pas")
            case .misleading: return String(localized: "Ne fait pas ce que dit le titre")
            case .offensive: return String(localized: "Titre ou photo choquant")
            case .spam: return String(localized: "Pub ou spam")
            case .copy: return String(localized: "Copie du travail de quelqu'un")
            }
        }
    }

    private var ready: Bool {
        !picked.isEmpty || (other && !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Signaler").font(Swiss.title(22)).tracking(Swiss.titleTracking(22))
                Text(verbatim: share.title.displaySafe(max: 50) + " · " + share.authorName.displaySafe(max: 24))
                    .font(.system(size: 13)).foregroundStyle(Swiss.gray)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Reason.allCases) { reason in
                    Toggle(reason.label, isOn: Binding(get: { picked.contains(reason) },
                                                       set: { on in if on { picked.insert(reason) } else { picked.remove(reason) } }))
                        .toggleStyle(SwissCheckboxStyle())
                }
                Toggle("Autre", isOn: $other).toggleStyle(SwissCheckboxStyle())
            }
            if other {
                // Grandit avec le texte, jamais tiré à la main (19/11).
                TextField("Pourquoi ?", text: $details, prompt: Text("Pourquoi ?"), axis: .vertical)
                    .lineLimit(2...8)
                    .swissField()
            }
            HStack {
                Spacer()
                Button("Annuler") { close() }
                    .secondaryButton()
                    .keyboardShortcut(.cancelAction)
                Button("Envoyer") {
                    Task {
                        await community.report(share, reason: text)
                        if community.error == nil { close() }
                    }
                }
                .primaryButton()
                .disabled(community.busy || !ready)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    /// Raisons envoyées, en français, à la suite (3 à 500 caractères, comme le veut le serveur).
    private var text: String {
        var parts = Reason.allCases.filter { picked.contains($0) }.map(\.rawValue)
        let extra = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if other { parts.append(extra.isEmpty ? "Autre" : "Autre : " + extra) }
        return String(parts.joined(separator: " ; ").prefix(500))
    }
}
