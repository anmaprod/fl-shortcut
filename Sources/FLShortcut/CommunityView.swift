// Page Communauté de la fenêtre principale : connexion ou création de compte (mail, mot de passe, nom
// d'utilisateur), puis partages de macros et de raccourcis avec leurs notes. Sans compte, rien n'est visible.
// Tout import passe par les mêmes vérifications qu'un fichier reçu (MacroExchange, ProfileImporter).
import AppKit
import SwiftUI

enum CommunityText {
    static let subtitle = "Les macros et raccourcis partagés par les autres, avec leurs explications."

    /// « 2026-10-16T18:02:11… » → « 16/10/2026 ».
    static func day(_ iso: String) -> String {
        let parts = iso.prefix(10).split(separator: "-")
        return parts.count == 3 ? "\(parts[2])/\(parts[1])/\(parts[0])" : ""
    }
}

struct CommunityPage: View {
    @EnvironmentObject var store: Store
    @ObservedObject var community: CommunityStore
    let toast: (ToastMessage) -> Void
    @State private var publishing = false
    @State private var reporting: Share?

    var body: some View {
        Group {
            if !community.isConfigured {
                message(symbol: "network.slash", title: "Communauté bientôt disponible",
                        text: CommunityError.notConfigured.errorDescription ?? "")
            } else if community.session == nil {
                CommunitySignIn(community: community)
            } else {
                list
            }
        }
        .task { await community.open() }
        .sheet(isPresented: $publishing) {
            CommunityPublishSheet(community: community, library: store.library, profile: { try? store.exportData() })
        }
        .sheet(item: $reporting) { share in
            CommunityReportSheet(community: community, share: share)
        }
    }

    private func message(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 12) {
            SectionIcon(symbol: symbol, tint: SidebarItem.community.tint, size: 52)
            Text(title).font(.title2.weight(.semibold))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        Form {
            Section {
                PageHeader(symbol: SidebarItem.community.symbol, tint: SidebarItem.community.tint, title: "Communauté",
                           subtitle: CommunityText.subtitle,
                           detail: community.session.map { "Connecté : \($0.username.isEmpty ? $0.email : $0.username)" })
                actions
                CommunityStatus(community: community)
            }
            Section {
                if community.shares.isEmpty {
                    Text(community.busy ? "Chargement…" : "Aucun partage pour l'instant.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(community.shares) { share in
                        CommunityShareRow(share: share, mine: community.isMine(share), canDelete: community.canDelete(share),
                                          importShare: { Task { await importShare(share) } },
                                          delete: { Task { await delete(share) } },
                                          report: { reporting = share })
                    }
                }
            } header: {
                Text("Partages récents")
            }
        }
        .formStyle(.grouped)
        .glassListBackground()
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                publishing = true
            } label: {
                Label("Partager…", systemImage: "square.and.arrow.up")
            }
            Picker("", selection: $community.kind) {
                Text("Tout").tag(ShareKind?.none)
                ForEach(ShareKind.allCases) { kind in Text(kind.label).tag(ShareKind?.some(kind)) }
            }
            .labelsHidden()
            .fixedSize()
            .onChange(of: community.kind) { _ in Task { await community.reload() } }
            TextField("Rechercher", text: $community.search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
                .onSubmit { Task { await community.reload() } }
            Button {
                Task { await community.reload() }
            } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
            Spacer(minLength: 0)
            Button("Se déconnecter") { Task { await community.signOut() } }
        }
        .buttonStyle(.borderless)
        .disabled(community.busy)
    }

    /// Import après relecture : mêmes contrôles et même confirmation qu'un fichier reçu.
    private func importShare(_ share: Share) async {
        guard let data = await community.payload(of: share) else { return }
        do {
            switch share.kind {
            case .macro:
                let preview = try MacroExchange.prepareImport(data, layout: store.layout)
                guard MacroFileActions.confirmImport(preview) else { return }
                var doc = preview.doc
                doc.name = store.library.uniqueName(doc.name)
                _ = store.library.add(doc)
                toast(ToastMessage(text: "Macro « \(doc.name.displaySafe(max: 40)) » ajoutée à tes macros", undo: nil))
            case .profile:
                let preview = try store.prepareImport(data)
                var text = preview.summary.joined(separator: "\n")
                if !preview.rejected.isEmpty {
                    text += "\n\nRefusé(s) par sécurité :\n• " + preview.rejected.joined(separator: "\n• ")
                }
                text += "\n\nTes raccourcis actuels seront remplacés (annulable)."
                guard Dialogs.confirm("Importer les raccourcis de \(share.authorName.displaySafe(max: 24)) ?", text) else { return }
                store.applyImport(preview)
                toast(ToastMessage(text: "Raccourcis importés", undo: { store.undoReplace() }))
            }
        } catch {
            Dialogs.inform("Import impossible", error.localizedDescription)
        }
    }

    private func delete(_ share: Share) async {
        guard Dialogs.confirm("Supprimer « \(share.title.displaySafe(max: 40)) » ?",
                              "Le partage disparaît pour tout le monde. Tes macros et raccourcis ne changent pas.") else { return }
        await community.delete(share)
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

// MARK: - Connexion et création de compte

private struct CommunitySignIn: View {
    @ObservedObject var community: CommunityStore
    @State private var creating = false
    @State private var email = ""
    @State private var password = ""
    @State private var username = ""

    var body: some View {
        Form {
            Section {
                PageHeader(symbol: SidebarItem.community.symbol, tint: SidebarItem.community.tint, title: "Communauté",
                           subtitle: CommunityText.subtitle + " Un compte est nécessaire pour y accéder.")
                Picker("", selection: $creating) {
                    Text("Se connecter").tag(false)
                    Text("Créer un compte").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Section {
                if creating {
                    TextField("Nom d'utilisateur", text: $username)
                        .textContentType(.username)
                }
                TextField("Mail", text: $email)
                SecureField("Mot de passe", text: $password)
                    .textContentType(.password)
                if creating {
                    Text("Ton nom d'utilisateur est visible par les autres membres ; ton mail ne l'est jamais.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button(creating ? "Créer mon compte" : "Se connecter") { submit() }
                        .primaryButton()
                        .keyboardShortcut(.defaultAction)
                    if !creating {
                        Button("Mot de passe oublié ?") { Task { await community.resetPassword(email: email) } }
                            .buttonStyle(.link)
                            .font(.system(size: 12))
                    }
                    Spacer(minLength: 0)
                    if community.busy { ProgressView().controlSize(.small) }
                }
                .disabled(community.busy)
                CommunityStatus(community: community)
            }
        }
        .formStyle(.grouped)
        .glassListBackground()
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

// MARK: - Ligne d'un partage

private struct CommunityShareRow: View {
    let share: Share
    let mine: Bool
    let canDelete: Bool
    let importShare: () -> Void
    let delete: () -> Void
    let report: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: share.kind.symbol)
                    .foregroundStyle(SidebarItem.community.tint)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(share.title.displaySafe(max: 80)).fontWeight(.medium)
                    Text("\(share.kind.label) · \(share.authorName.displaySafe(max: 24)) · \(CommunityText.day(share.createdAt))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Importer…", action: importShare)
                Menu {
                    if canDelete {
                        Button(mine ? "Supprimer mon partage…" : "Supprimer (administrateur)…", role: .destructive,
                               action: delete)
                    }
                    if !mine {
                        Button("Signaler…", action: report)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            if !share.notes.isEmpty {
                Text(share.notes)
                    .font(.system(size: 12))
                    .lineLimit(expanded ? nil : 2)
                    .textSelection(.enabled)
                    .onTapGesture { expanded.toggle() }
                    .help(expanded ? "" : "Cliquer pour tout lire")
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Publier

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
        VStack(alignment: .leading, spacing: 14) {
            Text("Partager avec la Communauté").font(.title3.weight(.semibold))
            Picker("Quoi", selection: $kind) {
                Text("Une macro").tag(ShareKind.macro)
                Text("Tous mes raccourcis").tag(ShareKind.profile)
            }
            .pickerStyle(.segmented)
            if kind == .macro {
                Picker("Macro", selection: $macroID) {
                    Text("Choisir…").tag(UUID?.none)
                    ForEach(library.macros) { doc in Text(doc.name.displaySafe(max: 50)).tag(UUID?.some(doc.id)) }
                }
            }
            TextField("Titre", text: $title)
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes : à quoi ça sert, comment l'utiliser").font(.system(size: 12)).foregroundStyle(.secondary)
                TextEditor(text: $notes)
                    .font(.system(size: 12))
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            }
            Text("Les positions apprises et les chemins de tes fichiers ne sont jamais partagés.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.system(size: 12))
            }
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                Button("Publier") { Task { await publish() } }
                    .primaryButton()
                    .keyboardShortcut(.defaultAction)
                    .disabled(community.busy)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onChange(of: macroID) { id in
            if title.isEmpty, let doc = id.flatMap(library.doc) { title = String(doc.name.prefix(80)) }
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
    @State private var reason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Signaler « \(share.title.displaySafe(max: 40)) »").font(.title3.weight(.semibold))
            TextField("Pourquoi ? (contenu dangereux, trompeur, offensant…)", text: $reason)
            HStack {
                Spacer()
                Button("Annuler") { dismiss() }
                Button("Signaler") {
                    Task {
                        await community.report(share, reason: reason)
                        if community.error == nil { dismiss() }
                    }
                }
                .primaryButton()
                .disabled(community.busy)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
