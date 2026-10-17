// Page Mon compte de la fenêtre principale : connexion ou création du compte (le même que pour la Communauté), puis
// la sauvegarde en ligne des raccourcis et des macros (AccountBackup) : où elle en est, le choix quand ce Mac et le
// compte ont chacun leurs changements, la déconnexion (ils quittent ce Mac, restent dans le compte) et la suppression
// du compte.
import SwiftUI

enum AccountText {
    static let subtitle = "Sauvegarde tes raccourcis et tes macros en ligne, et retrouve-les sur n'importe quel Mac."
    static let benefits: [(symbol: String, text: String)] = [
        ("icloud.and.arrow.up", "Tes raccourcis et tes macros sont sauvegardés en ligne, tout seuls, à chaque changement."),
        ("laptopcomputer.and.arrow.down", "Connecte-toi sur un autre Mac : tout revient. À la déconnexion, ils quittent ce Mac et restent dans ton compte."),
        ("person.2", "Le même compte sert à la Communauté : ajoute des macros toutes faites, partage les tiennes."),
        ("lock.shield", "Personne d'autre ne peut lire ta sauvegarde. Ton mail reste privé."),
    ]

    /// « aujourd'hui à 21:07 », « hier à 9:12 », « 14 oct. 2026 à 18:00 ».
    static func when(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f.string(from: date)
    }
}

/// Déconnexion et suppression du compte, avec leurs confirmations (page Mon compte, menu de la Communauté).
@MainActor
enum AccountActions {
    static func signOut(_ backup: AccountBackup = .shared) async {
        guard Dialogs.choose("Se déconnecter ?",
                             "Tes raccourcis et tes macros seront retirés de ce Mac. Ils restent dans ton compte : "
                                 + "reconnecte-toi, ici ou sur un autre Mac, pour les retrouver.",
                             ["Se déconnecter", "Annuler"]) == 0 else { return }
        var outcome = await backup.signOut()
        while case .notSaved(let why) = outcome {
            switch Dialogs.choose("Tes derniers changements ne sont pas en ligne",
                                  why + " Si tu te déconnectes maintenant, ils seront perdus.",
                                  ["Réessayer", "Se déconnecter quand même", "Annuler"], destructive: 1) {
            case 0: outcome = await backup.signOut()
            case 1: outcome = await backup.signOut(evenIfNotSaved: true)
            default: return
            }
        }
    }

    /// nil : supprimé, ou rien fait (annulé) ; sinon, ce qui s'est passé.
    static func deleteAccount(_ backup: AccountBackup = .shared) async -> String? {
        guard Dialogs.choose("Supprimer ton compte ?",
                             "Ton compte, ta sauvegarde en ligne et tes partages dans la Communauté seront effacés "
                                 + "pour toujours. Tes raccourcis et tes macros restent sur ce Mac.",
                             ["Supprimer définitivement", "Annuler"], destructive: 0) == 0 else { return nil }
        return await backup.deleteAccount()
    }
}

struct AccountPage: View {
    @ObservedObject var community: CommunityStore
    @ObservedObject var backup: AccountBackup
    @State private var deleteError: String?

    var body: some View {
        Group {
            if !community.isConfigured {
                CommunityMessage(symbol: "person.crop.circle.badge.xmark", tint: SidebarItem.account.tint,
                                 title: "Les comptes ne sont pas encore ouverts",
                                 text: "Tes raccourcis et tes macros restent sur ce Mac en attendant.")
            } else if let session = community.session {
                signedIn(session)
            } else {
                CommunitySignIn(community: community, page: .account, title: "Mon compte",
                                subtitle: AccountText.subtitle, benefits: AccountText.benefits)
            }
        }
        .task { await backup.refreshIfStale() }
        .onReceive(DebugSnapshot.publisher(DebugSnapshot.account)) { note in
            backup.showDemo(note.object as? String ?? "")
        }
    }

    private func signedIn(_ session: CommunitySession) -> some View {
        Form {
            Section {
                PageHeader(symbol: SidebarItem.account.symbol, tint: SidebarItem.account.tint, title: "Mon compte",
                           subtitle: AccountText.subtitle,
                           detail: "@\(session.username.displaySafe(max: 24)) · \(session.email.displaySafe(max: 60))")
            }
            if let conflict = backup.conflict {
                Section {
                    AccountConflictCard(conflict: conflict) { keepAccount in
                        Task { await backup.resolve(keepAccount: keepAccount) }
                    }
                }
            }
            Section {
                AccountBackupStatus(status: backup.status) { Task { await backup.saveNow() } }
                LabeledContent("Sur ce Mac", value: backup.hereSummary)
                if let notice = backup.notice {
                    Label(notice, systemImage: "info.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Sauvegarde en ligne")
            } footer: {
                Text("Tes raccourcis et tes macros partent en ligne quelques secondes après chaque changement. Personne "
                     + "d'autre ne peut les lire. Les réglages de ce Mac (pause, autorisations, endroits appris dans FL) "
                     + "restent ici.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Se déconnecter")
                        Text("Tes raccourcis et tes macros quittent ce Mac et restent dans ton compte.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button("Se déconnecter…") { Task { await AccountActions.signOut(backup) } }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Supprimer mon compte")
                        Text("Efface ton compte, ta sauvegarde en ligne et tes partages. Tes raccourcis et tes macros "
                             + "restent sur ce Mac.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button("Supprimer…", role: .destructive) {
                        Task { deleteError = await AccountActions.deleteAccount(backup) }
                    }
                }
                if let deleteError {
                    Label(deleteError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Compte")
            }
        }
        .formStyle(.grouped)
        .glassListBackground()
    }
}

/// Où en est la sauvegarde, en une ligne, avec « Sauvegarder maintenant ».
private struct AccountBackupStatus: View {
    let status: AccountBackup.Status
    let saveNow: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: look.symbol)
                .font(.system(size: 18))
                .foregroundStyle(look.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(look.title).font(.system(size: 13, weight: .semibold))
                Text(look.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if look.busy {
                ProgressView().controlSize(.small)
            } else {
                Button("Sauvegarder maintenant", action: saveNow)
                    .disabled(status == .choice)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var look: (symbol: String, color: Color, title: String, detail: String, busy: Bool) {
        switch status {
        case .off, .checking:
            return ("arrow.triangle.2.circlepath.icloud", .secondary, "Vérification de ta sauvegarde…",
                    "Ce Mac et ton compte se comparent.", true)
        case .upToDate(let date):
            return ("checkmark.icloud.fill", .green, "À jour",
                    date.map { "Dernière sauvegarde : \(AccountText.when($0))." } ?? "Tout est en ligne.", false)
        case .pending:
            return ("icloud.and.arrow.up", .blue, "Changements à envoyer", "Ils partent dans quelques secondes.", false)
        case .saving:
            return ("icloud.and.arrow.up.fill", .blue, "Enregistrement en ligne…", "Ne quitte pas l'app tout de suite.", true)
        case .waiting(let why):
            return ("exclamationmark.icloud.fill", .orange, "Pas encore en ligne", why, false)
        case .choice:
            return ("exclamationmark.icloud.fill", .orange, "À toi de choisir",
                    "Ce Mac et ton compte ont chacun des changements : choisis la version à garder ci-dessus.", false)
        case .blocked(let why):
            return ("xmark.icloud.fill", .red, "Sauvegarde arrêtée", why, false)
        }
    }
}

/// Ce Mac et le compte ont chacun leurs changements : les deux versions, résumées, et le choix.
private struct AccountConflictCard: View {
    let conflict: AccountBackup.Conflict
    let choose: (_ keepAccount: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ce Mac et ton compte ont chacun des changements", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
            Text("Choisis la version à garder. Rien n'est envoyé ni remplacé avant ton choix.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                side(title: "Ce Mac", symbol: "laptopcomputer", summary: conflict.here,
                     effect: "La sauvegarde de ton compte est remplacée par ce qu'il y a ici.",
                     button: "Garder ce Mac") { choose(false) }
                side(title: "Ton compte", symbol: "icloud", summary: conflict.account
                        + (conflict.remote.updatedAt.map { " · \(AccountText.when($0))" } ?? ""),
                     effect: "Ce Mac reprend ta sauvegarde. Ce qu'il y avait ici est copié dans Application Support › "
                         + "FL Shortcuts.",
                     button: "Garder mon compte") { choose(true) }
            }
        }
        .padding(.vertical, 4)
    }

    private func side(title: String, symbol: String, summary: String, effect: String, button: String,
                      action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold))
            Text(summary).font(.system(size: 12))
            Text(effect)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(button, action: action)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}
