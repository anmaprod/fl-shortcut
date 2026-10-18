// Page Communauté de la fenêtre principale : des macros et des raccourcis prêts à l'emploi, partagés par d'autres
// utilisateurs, avec l'explication de leur auteur. Comme la galerie de Raccourcis d'Apple : on ouvre un partage pour
// lire ce qu'il fait, étape par étape, puis on l'ajoute ; rien ne s'ajoute sans cette fiche, rien ne se lance tout
// seul (une macro ajoutée n'a pas de raccourci). Compte nécessaire (mail, mot de passe, nom d'utilisateur) : sans
// compte, rien n'est visible. Tout ajout passe par les mêmes vérifications qu'un fichier reçu (MacroExchange,
// ProfileImporter).
import AppKit
import SwiftUI

enum CommunityText {
    static let subtitle = "Des macros et des raccourcis prêts à l'emploi, partagés par d'autres utilisateurs de "
        + "FL Shortcuts, avec leur explication."

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
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    /// « Macro · par @leo.beats · 15/10/2026 ».
    static func byline(_ share: Share) -> String {
        "\(share.kind.label) · par @\(share.authorName.displaySafe(max: 24)) · \(day(share.createdAt))"
    }
}

extension ShareKind {
    /// Couleur de l'icône : celle de la page Macros pour une macro, bleu clavier pour des raccourcis.
    var tint: Color { self == .macro ? SidebarItem.macros.tint : .blue }
    /// Bouton principal de la fiche.
    var addLabel: String { self == .macro ? "Ajouter à mes macros" : "Utiliser ces raccourcis" }
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
                CommunityMessage(symbol: "network.slash", title: "La Communauté n'est pas encore ouverte",
                                 text: "Bientôt, tu y trouveras des macros et des raccourcis partagés par d'autres "
                                     + "utilisateurs, et tu pourras partager les tiens. En attendant, rien ne change "
                                     + "pour tes raccourcis et tes macros.")
            } else if community.session == nil {
                CommunitySignIn(community: community)
            } else {
                CommunityBrowse(community: community, open: { opened = $0 }, report: { reporting = $0 },
                                delete: { share in Task { await delete(share) } })
            }
        }
        .softSwitch(!community.isConfigured ? 0 : community.session == nil ? 1 : 2)
        .task { await community.open() }
        .sheet(item: $opened) { share in
            CommunityShareDetail(community: community, store: store, share: share, added: toast,
                                 report: { reportLater(share) })
        }
        .background {
            // Feuilles posées sur des vues différentes : une seule par vue, comme le veut SwiftUI.
            Color.clear
                .sheet(isPresented: $community.composing) {
                    CommunityPublishSheet(community: community, library: store.library,
                                          profile: { try? store.exportData() })
                }
                .sheet(item: $reporting) { share in
                    CommunityReportSheet(community: community, share: share)
                }
        }
        .onReceive(DebugSnapshot.publisher(DebugSnapshot.community)) { note in
            showCapture(note.object as? String ?? "")
        }
    }

    /// « Signaler… » depuis la fiche : la fiche se ferme, puis la feuille du signalement s'ouvre.
    private func reportLater(_ share: Share) {
        opened = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { reporting = share }
    }

    private func delete(_ share: Share) async {
        guard Dialogs.confirm("Supprimer « \(share.title.displaySafe(max: 40)) » ?",
                              "Le partage disparaît pour tout le monde. Tes macros et raccourcis ne changent pas.") else { return }
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
        case "auteur":
            community.showDemo(signedIn: true)
            if let first = community.shares.first { Task { await community.showAuthor(of: first) } }
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
        VStack(spacing: 10) {
            SectionIcon(symbol: symbol, tint: tint, size: 44)
            Text(title).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
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
        if let error = community.error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))
        } else if let notice = community.notice {
            Label(notice, systemImage: "info.circle.fill")
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
    /// « Comment ça marche » rangé une fois compris.
    @AppStorage("communityHowToSeen") private var howToSeen = false

    var body: some View {
        PageContainer {
            Section {
                PageHeader(symbol: SidebarItem.community.symbol, tint: SidebarItem.community.tint, title: "Communauté",
                           subtitle: CommunityText.subtitle,
                           detail: community.session.map { "Connecté en tant que @\($0.username.isEmpty ? $0.email : $0.username)" })
                    .cardRow(.single)
            }
            if !howToSeen {
                Section {
                    CommunityHowTo { withAnimation(Motion.smooth) { howToSeen = true } }
                        .cardRow(.single)
                }
            }
            Section {
                CommunityFilters(community: community)
                    .cardRow(community.error == nil && community.notice == nil ? .single : .first)
                if community.error != nil || community.notice != nil {
                    CommunityStatus(community: community).cardRow(.last)
                }
            }
            if let author = community.author {
                Section {
                    CommunityAuthorHeader(author: author, count: community.shares.count, busy: community.busy) {
                        Task { await community.showEveryone() }
                    }
                    .cardRow(.single)
                }
            } else if !community.members.isEmpty {
                Section {
                    ForEach(Array(community.members.enumerated()), id: \.element.id) { index, member in
                        CommunityMemberRow(member: member) { Task { await community.showAuthor(member) } }
                            .cardRow(.position(index: index, count: community.members.count), hover: true)
                    }
                } header: {
                    Text("Membres")
                }
            }
            Section {
                if community.shares.isEmpty {
                    empty.cardRow(.single)
                } else {
                    ForEach(Array(community.shares.enumerated()), id: \.element.id) { index, share in
                        CommunityShareRow(share: share, mine: community.isMine(share),
                                          canDelete: community.canDelete(share),
                                          showAuthor: community.author?.id == share.authorID ? nil : {
                                              Task { await community.showAuthor(of: share) }
                                          },
                                          open: { open(share) }, report: { report(share) }, delete: { delete(share) })
                            .cardRow(.position(index: index, count: community.shares.count), hover: true)
                    }
                }
            } header: {
                Text(listTitle)
            }
        }
        .glassListBackground()
    }

    private var trimmedSearch: String { community.search.trimmingCharacters(in: .whitespaces) }

    private var listTitle: String {
        let n = community.shares.count
        if let author = community.author {
            let name = "@\(author.username.displaySafe(max: 24))"
            if !trimmedSearch.isEmpty { return n == 1 ? "1 résultat chez \(name)" : "\(n) résultats chez \(name)" }
            return "Partages de \(name)"
        }
        if !trimmedSearch.isEmpty {
            return n == 1 ? "1 partage trouvé" : "\(n) partages trouvés"
        }
        switch community.kind {
        case .macro?: return "Macros partagées"
        case .profile?: return "Raccourcis partagés"
        case nil: return "Derniers partages"
        }
    }

    @ViewBuilder private var empty: some View {
        if community.busy {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Chargement des partages…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else if !trimmedSearch.isEmpty {
            CommunityMessage(symbol: "magnifyingglass", title: "Aucun partage pour « \(trimmedSearch.displaySafe(max: 30)) »",
                             text: community.members.isEmpty
                                 ? "Essaie un autre mot : un titre, une fenêtre de FL (Mixer, Playlist…), une action ou "
                                     + "le nom d'un membre."
                                 : "Aucun titre ni aucune explication ne contient ce mot : choisis un membre plus haut "
                                     + "pour voir ses partages.",
                             button: "Effacer la recherche") {
                community.search = ""
                Task { await community.reload() }
            }
        } else if let author = community.author {
            CommunityMessage(symbol: "person.crop.circle", title: "Aucun partage de @\(author.username.displaySafe(max: 24))",
                             text: "Ce membre n'a rien publié pour l'instant\(community.kind == nil ? "" : " de ce genre").",
                             button: "Voir tout le monde") {
                Task { await community.showEveryone() }
            }
        } else if community.kind != nil {
            CommunityMessage(symbol: community.kind?.symbol ?? "square.stack", title: "Rien de ce genre pour l'instant",
                             text: "Personne n'a encore partagé de \(community.kind == .macro ? "macro" : "raccourcis").",
                             button: "Tout afficher") {
                community.kind = nil
                Task { await community.reload() }
            }
        } else {
            CommunityMessage(symbol: "sparkles", title: "Encore aucun partage",
                             text: "Sois le premier : partage une macro qui te fait gagner du temps, avec une petite "
                                 + "explication pour les autres.",
                             button: "Partager une macro…") { community.composing = true }
        }
    }
}

/// Trois étapes, en contexte, rangées par « J'ai compris ».
private struct CommunityHowTo: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Comment ça marche").font(.headline)
                Spacer()
                Button("J'ai compris", action: dismiss).buttonStyle(.borderless)
            }
            step(1, "Clique sur un partage : tu lis l'explication de son auteur et ce qu'il fait, étape par étape.")
            step(2, "« Ajouter à mes macros » la range avec les tiennes, sans raccourci : rien ne se lance tant que "
                 + "tu ne lui en as pas choisi un.")
            step(3, "Le « + » en haut à droite partage une de tes macros, ou tous tes raccourcis, avec ton explication.")
        }
        .padding(.vertical, 4)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            StepBadge(number: number)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Un membre trouvé par son nom : toute la ligne ouvre ses partages.
private struct CommunityMemberRow: View {
    let member: CommunityMember
    let open: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SectionIcon(symbol: "person.fill", tint: SidebarItem.community.tint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(member.username.displaySafe(max: 24))").fontWeight(.semibold).lineLimit(1)
                Text(member.shareCount == 1 ? "1 partage" : "\(member.shareCount) partages")
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

/// Partages d'un seul membre : son nom, combien, et le retour à tout le monde.
private struct CommunityAuthorHeader: View {
    let author: CommunityMember
    let count: Int
    let busy: Bool
    let everyone: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SectionIcon(symbol: "person.fill", tint: SidebarItem.community.tint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(author.username.displaySafe(max: 24))").font(.headline).lineLimit(1)
                Text(busy ? "Chargement…" : count == 1 ? "1 partage" : count >= 50 ? "50 partages les plus récents"
                                                                                 : "\(count) partages")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Voir tout le monde", action: everyone)
                .help("Revenir aux partages de tous les membres")
        }
        .padding(.vertical, 2)
    }
}

/// Genre, recherche (au fil de la frappe), actualiser, compte.
private struct CommunityFilters: View {
    @ObservedObject var community: CommunityStore
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 10) {
            Picker("Afficher", selection: $community.kind) {
                Text("Tout").tag(ShareKind?.none)
                Text("Macros").tag(ShareKind?.some(.macro))
                Text("Raccourcis").tag(ShareKind?.some(.profile))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Afficher tous les partages, seulement les macros, ou seulement les jeux de raccourcis")
            .onChange(of: community.kind) { _ in Task { await community.reload() } }
            TextField("Rechercher", text: $community.search, prompt: Text("Rechercher un partage ou un membre"))
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await community.reload() } }
                .onChange(of: community.search) { _ in
                    searchTask?.cancel()
                    searchTask = Task {
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        guard !Task.isCancelled else { return }
                        await community.reload()
                    }
                }
            Button {
                Task { await community.reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Actualiser : voir les derniers partages")
            .accessibilityLabel("Actualiser")
            Menu {
                if let session = community.session {
                    Text("Connecté en tant que @\(session.username)")
                }
                Divider()
                Button("Se déconnecter…") { Task { await AccountActions.signOut() } }
            } label: {
                Image(systemName: "person.crop.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Ton compte")
            .accessibilityLabel("Ton compte")
        }
        .disabled(community.busy)
    }
}

/// Un partage : genre, titre, auteur et date, début de l'explication. Toute la ligne ouvre la fiche.
private struct CommunityShareRow: View {
    let share: Share
    let mine: Bool
    let canDelete: Bool
    /// Voir tous les partages de l'auteur (nil : on les regarde déjà).
    let showAuthor: (() -> Void)?
    let open: () -> Void
    let report: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Clic sur le partage (icône, titre, explication) : sa fiche. Les boutons à droite gardent leurs clics.
            HStack(alignment: .top, spacing: 12) {
                SectionIcon(symbol: share.kind.symbol, tint: share.kind.tint, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(share.title.displaySafe(max: 80)).fontWeight(.semibold).lineLimit(1)
                        if mine {
                            Text("Ton partage")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                        }
                    }
                    Text(CommunityText.byline(share)).font(.system(size: 11)).foregroundStyle(.secondary)
                    if !share.notes.isEmpty {
                        Text(share.notes).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: open)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { open() }
            Button("Voir", action: open)
                .help("Lire l'explication et voir ce que fait ce partage, avant de l'ajouter")
            Menu {
                if let showAuthor {
                    Button("Tous les partages de @\(share.authorName.displaySafe(max: 24))", action: showAuthor)
                }
                if !mine {
                    Button("Signaler…", action: report)
                }
                if canDelete {
                    Button(mine ? "Supprimer mon partage…" : "Supprimer (administrateur)…", role: .destructive,
                           action: delete)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Plus d'actions")
        }
        .padding(.vertical, 2)
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
    @Environment(\.dismiss) private var dismiss
    @State private var content = Content.loading

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
                SectionIcon(symbol: share.kind.symbol, tint: share.kind.tint, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(share.title.displaySafe(max: 80)).font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(CommunityText.byline(share)).font(.system(size: 12)).foregroundStyle(.secondary)
                    if community.author?.id != share.authorID {
                        Button("Tous les partages de @\(share.authorName.displaySafe(max: 24))") {
                            dismiss()
                            Task { await community.showAuthor(of: share) }
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                    }
                }
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    part("L'explication de @\(share.authorName.displaySafe(max: 24))") {
                        Text(share.notes.isEmpty ? "L'auteur n'a pas écrit d'explication." : share.notes)
                            .font(.system(size: 13))
                            .foregroundStyle(share.notes.isEmpty ? .secondary : .primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    part(share.kind == .macro ? "Ce que fait la macro, étape par étape" : "Les raccourcis qu'il contient") {
                        steps
                    }
                    if !notes.isEmpty {
                        part("Bon à savoir") {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(notes, id: \.self) { line in
                                    Label(line, systemImage: "info.circle")
                                        .font(.system(size: 12))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if !mine {
                    Button("Signaler…", action: report)
                        .help("Prévenir les administrateurs : partage dangereux, trompeur ou offensant")
                }
                Spacer()
                Button("Fermer") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(share.kind.addLabel) { add() }
                    .primaryButton()
                    .keyboardShortcut(.defaultAction)
                    .disabled(!ready)
            }
            .padding(16)
        }
        .frame(width: 540, height: 580)
        .task { await load() }
    }

    private func part<C: View>(_ title: String, @ViewBuilder _ body: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            body()
        }
    }

    @ViewBuilder private var steps: some View {
        switch content {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Lecture du partage…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        case .failed(let why):
            Label("Ce partage ne peut pas être ajouté : \(why)", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
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
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    /// Ce qu'il faut savoir avant de s'en servir.
    private var notes: [String] {
        switch content {
        case .macro(let preview):
            var out = preview.warnings
            if preview.sensitiveCount > 0 {
                out.append(preview.sensitiveCount == 1
                           ? "1 étape tape des touches, clique ou ouvre un fichier : relis-la dans le créateur."
                           : "\(preview.sensitiveCount) étapes tapent des touches, cliquent ou ouvrent des fichiers : "
                             + "relis-les dans le créateur.")
            }
            out.append("Elle arrive sans raccourci : rien ne se lance tant que tu ne lui en as pas choisi un.")
            return out
        case .profile(let preview):
            var out = ["Tes raccourcis actuels sont remplacés par ceux-ci. Tu peux annuler juste après, depuis la "
                       + "notification en bas de la fenêtre."]
            if !preview.rejected.isEmpty {
                out.append("Refusés par sécurité : " + preview.rejected.joined(separator: " ; "))
            }
            return out
        case .loading, .failed:
            return []
        }
    }

    private func load() async {
        guard let data = await community.payload(of: share) else {
            content = .failed(community.error ?? "téléchargement impossible.")
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
            dismiss()
            return
        }
        switch content {
        case .macro(let preview):
            var doc = preview.doc
            doc.name = store.library.uniqueName(doc.name)
            _ = store.library.add(doc)
            added(ToastMessage(text: "« \(doc.name.displaySafe(max: 40)) » ajoutée à tes macros : choisis-lui un raccourci "
                               + "dans la page Macros", undo: nil))
        case .profile(let preview):
            let model = store
            model.applyImport(preview)
            added(ToastMessage(text: "Raccourcis de @\(share.authorName.displaySafe(max: 24)) en place",
                               undo: { model.undoReplace() }))
        case .loading, .failed:
            return
        }
        dismiss()
    }
}

// MARK: - Connexion et création de compte

/// Connexion ou création du compte : un seul compte pour la Communauté et la sauvegarde en ligne (page Mon compte).
struct CommunitySignIn: View {
    @ObservedObject var community: CommunityStore
    var page: SidebarItem = .community
    var title = "Communauté"
    var subtitle = CommunityText.subtitle
    var benefits: [(symbol: String, text: String)] = [
        ("square.and.arrow.down", "Ajoute des macros toutes faites, après avoir lu ce qu'elles font."),
        ("square.and.arrow.up", "Partage les tiennes, avec une explication pour les autres."),
        ("lock.shield", "Ton mail reste privé : les autres ne voient que ton nom d'utilisateur."),
    ]
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var code = ""
    @State private var newPassword = ""

    private var creating: Bool { community.creatingAccount }

    var body: some View {
        Form {
            Section {
                PageHeader(symbol: page.symbol, tint: page.tint, title: title, subtitle: subtitle)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(benefits.indices, id: \.self) { i in benefit(benefits[i].symbol, benefits[i].text) }
                }
                .padding(.vertical, 2)
            }
            if let pending = community.pendingCode {
                codeSection(pending)
            } else {
                signInSection
            }
        }
        .formStyle(.grouped)
        .glassListBackground()
        // Code reçu, création du compte : les champs changent en douceur.
        .motion(Motion.morph, value: community.pendingCode)
        .motion(Motion.morph, value: creating)
        .onChange(of: community.pendingCode) { _ in
            code = ""
            newPassword = ""
        }
    }

    /// Code reçu par mail : confirmer l'inscription, ou choisir un nouveau mot de passe.
    private func codeSection(_ pending: CommunityStore.PendingCode) -> some View {
        let recovery = pending.kind == .recovery
        return Section {
            Text("Code envoyé à \(pending.email.displaySafe(max: 60))")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Code", text: $code, prompt: Text("123456"))
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .textContentType(.oneTimeCode)
            if recovery {
                SecureField("Nouveau mot de passe", text: $newPassword, prompt: Text("8 caractères, majuscule, chiffre, symbole"))
                    .textContentType(.password)
                let missing = CommunityRules.passwordMissing(newPassword)
                if !newPassword.isEmpty, !missing.isEmpty {
                    hint("Il faut encore : " + missing.joined(separator: ", ") + ".")
                }
            }
            HStack {
                Button(recovery ? "Changer le mot de passe" : "Confirmer") {
                    let typed = code, chosen = newPassword
                    Task {
                        if recovery {
                            await community.finishReset(code: typed, newPassword: chosen)
                        } else {
                            await community.confirmSignup(code: typed)
                        }
                    }
                }
                .primaryButton()
                .keyboardShortcut(.defaultAction)
                .disabled(CommunityRules.code(code) == nil || (recovery && CommunityRules.passwordProblem(newPassword) != nil))
                Button("Renvoyer le code") { Task { await community.resendCode() } }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                Spacer(minLength: 0)
                if community.busy { ProgressView().controlSize(.small) }
                Button("Retour") { community.cancelCode() }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
            .disabled(community.busy)
            CommunityStatus(community: community)
        } header: {
            Text(recovery ? "Mot de passe oublié" : "Confirme ton adresse")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pas de mail ? Regarde dans les courriers indésirables, ou renvoie le code.")
                    .foregroundStyle(.secondary)
                if !recovery {
                    // Mail avec un lien au lieu d'un code : le lien confirme l'adresse (la page affichée après peut
                    // ne pas s'ouvrir), il ne reste qu'à se connecter.
                    HStack(spacing: 4) {
                        Text("Reçu un lien au lieu d'un code ?").foregroundStyle(.secondary)
                        Button("J'ai cliqué sur le lien") {
                            email = pending.email
                            community.confirmedByLink()
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            .font(.system(size: 11))
        }
    }

    private var signInSection: some View {
            Section {
                Picker("", selection: $community.creatingAccount) {
                    Text("J'ai déjà un compte").tag(false)
                    Text("Créer un compte").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if creating {
                    TextField("Nom d'utilisateur", text: $username, prompt: Text("ex. malo.beats"))
                        .textContentType(.username)
                    if let problem = usernameHint { hint(problem) }
                }
                TextField("Mail", text: $email, prompt: Text("toi@exemple.fr"))
                if creating {
                    SecureField("Mot de passe", text: $password, prompt: Text("8 caractères, majuscule, chiffre, symbole"))
                        .textContentType(.password)
                    let missing = CommunityRules.passwordMissing(password)
                    if !password.isEmpty, !missing.isEmpty {
                        hint("Il faut encore : " + missing.joined(separator: ", ") + ".")
                    }
                } else {
                    SecureField("Mot de passe", text: $password)
                        .textContentType(.password)
                }
                HStack {
                    Button(creating ? "Créer mon compte" : "Se connecter") { submit() }
                        .primaryButton()
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSubmit)
                    if !creating {
                        Button("Mot de passe oublié ?") { Task { await community.resetPassword(email: email) } }
                            .buttonStyle(.link)
                            .font(.system(size: 12))
                            .help("Reçois par mail un code pour choisir un nouveau mot de passe")
                    }
                    Spacer(minLength: 0)
                    if community.busy { ProgressView().controlSize(.small) }
                }
                .disabled(community.busy)
                CommunityStatus(community: community)
            } header: {
                Text(creating ? "Nouveau compte" : "Connexion")
            } footer: {
                if creating {
                    Text("Visible par les autres : ton nom d'utilisateur et ce que tu partages. Jamais : ton mail.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
    }

    private func benefit(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(page.tint)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
    }

    private var usernameHint: String? {
        let name = username.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : CommunityRules.usernameProblem(name)
    }

    private var canSubmit: Bool {
        let mail = email.trimmingCharacters(in: .whitespaces)
        guard creating else { return !mail.isEmpty && !password.isEmpty }
        return CommunityRules.usernameProblem(username.trimmingCharacters(in: .whitespaces)) == nil
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
    @Environment(\.dismiss) private var dismiss
    @State private var kind = ShareKind.macro
    @State private var macroID: UUID?
    @State private var title = ""
    @State private var notes = ""
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Partager avec la Communauté").font(.title3.weight(.semibold))
                Text("Les autres pourront lire ton explication, voir chaque étape, puis l'ajouter chez eux.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            field("Quoi") {
                Picker("Quoi", selection: $kind) {
                    Text("Une macro").tag(ShareKind.macro)
                    Text("Tous mes raccourcis").tag(ShareKind.profile)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(kind == .macro
                     ? "La macro choisie, avec ses étapes."
                     : "Ton jeu de raccourcis complet : les autres pourront le mettre à la place du leur.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if kind == .macro {
                field("Macro") {
                    if library.macros.isEmpty {
                        Text("Tu n'as pas encore de macro : crée-en une dans la page Macros.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Macro", selection: $macroID) {
                            Text("Choisir…").tag(UUID?.none)
                            ForEach(library.macros) { doc in Text(doc.name.displaySafe(max: 50)).tag(UUID?.some(doc.id)) }
                        }
                        .labelsHidden()
                    }
                }
            }
            field("Titre", count: "\(trimmedTitle.count)/\(CommunityRules.titleRange.upperBound)") {
                TextField("Titre", text: $title, prompt: Text("ex. Armer la piste et lancer l'enregistrement"))
                    .labelsHidden()
            }
            field("Explication", count: "\(notes.count)/\(CommunityRules.maxNotes)") {
                TextEditor(text: $notes)
                    .font(.system(size: 12))
                    .frame(minHeight: 110)
                    .overlay(alignment: .topLeading) {
                        if notes.isEmpty {
                            Text("À quoi elle sert, où l'utiliser dans FL (Mixer, Playlist…), ce qu'il faut faire avant "
                                 + "de la lancer.")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
            VStack(alignment: .leading, spacing: 4) {
                Label("Partagé : \(kind == .macro ? "la macro" : "tes raccourcis"), le titre, ton explication, "
                      + "ton nom d'utilisateur.", systemImage: "eye")
                Label("Jamais partagé : ton mail, tes positions apprises, les chemins de tes fichiers.",
                      systemImage: "lock")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            if let problem = problem ?? limitProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 12))
            }
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Publier") { Task { await publish() } }
                    .primaryButton()
                    .keyboardShortcut(.defaultAction)
                    .disabled(community.busy || !canPublish)
                    .help(canPublish ? "Publier pour tous les membres de la Communauté"
                          : kind == .macro && macroID == nil ? "Choisis d'abord la macro à partager"
                          : "Écris un titre (\(CommunityRules.titleRange.lowerBound) caractères au moins)")
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
            return "Titre : \(CommunityRules.titleRange.lowerBound) à \(CommunityRules.titleRange.upperBound) caractères."
        }
        if notes.count > CommunityRules.maxNotes { return "Explication : \(CommunityRules.maxNotes) caractères au plus." }
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
                problem = "Choisis la macro à partager."
                return
            }
            payload = try? MacroExchange.export(doc, appVersion: MacroFileActions.appVersion)
        case .profile:
            payload = profile()
        }
        guard let payload else {
            problem = "Export impossible."
            return
        }
        if await community.publish(kind: kind, title: title, notes: notes, payload: payload) {
            dismiss()
        } else {
            problem = community.error
        }
    }
}

// MARK: - Signaler

private struct CommunityReportSheet: View {
    @ObservedObject var community: CommunityStore
    let share: Share
    @Environment(\.dismiss) private var dismiss
    @State private var reason = Reason.danger
    @State private var details = ""

    enum Reason: String, CaseIterable, Identifiable {
        case danger = "Dangereux : supprime, écrase ou envoie des choses sans prévenir"
        case misleading = "Ne fait pas ce que dit son explication"
        case offensive = "Contenu offensant"
        case spam = "Publicité ou spam"
        case other = "Autre"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Signaler « \(share.title.displaySafe(max: 40)) »").font(.title3.weight(.semibold))
                Text("Les administrateurs le relisent et le retirent s'il le faut. L'auteur ne sait pas qui l'a signalé.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Raison", selection: $reason) {
                ForEach(Reason.allCases) { r in Text(r.rawValue).tag(r) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            TextField("Détails", text: $details, prompt: Text("Précisions (facultatif)"))
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Signaler") {
                    Task {
                        await community.report(share, reason: text)
                        if community.error == nil { dismiss() }
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
