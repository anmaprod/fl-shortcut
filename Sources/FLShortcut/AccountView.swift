// Page Mon compte de la fenêtre principale : connexion ou création du compte (le même que pour la Communauté), puis
// la sauvegarde en ligne des raccourcis et des macros (AccountBackup) : où elle en est, le choix quand ce Mac et le
// compte ont chacun leurs changements, la déconnexion (ils quittent ce Mac, restent dans le compte) et la suppression
// du compte.
import SwiftUI

enum AccountText {
    static let subtitle = String(localized: """
        Sauvegarde tes raccourcis et tes macros en ligne, et retrouve-les sur n'importe quel Mac.
        """)
    /// « aujourd'hui à 21:07 », « hier à 9:12 », « 14 oct. 2026 à 18:00 » ; dans la langue de l'app (« today at
    /// 9:07 PM » sur un Mac en anglais).
    static func when(_ date: Date) -> String {
        let f = DateFormatter()
        let language = Bundle.main.preferredLocalizations.first ?? "fr"
        f.locale = Locale(identifier: Locale.current.region.map { "\(language)_\($0.identifier)" } ?? language)
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f.string(from: date)
    }
}

/// Déconnexion et suppression du compte, avec leurs confirmations (page Mon compte, menu de la Communauté).
@MainActor
enum AccountActions {
    /// `backup` nil : le compte de l'app (lu ici, sur le fil principal, et pas en valeur par défaut : Swift 6).
    static func signOut(_ backup: AccountBackup? = nil) async {
        let backup = backup ?? .shared
        guard Dialogs.choose(String(localized: "Se déconnecter ?"),
                             String(localized: """
                                 Tes raccourcis et tes macros seront retirés de ce Mac. Ils restent dans ton compte : \
                                 reconnecte-toi, ici ou sur un autre Mac, pour les retrouver.
                                 """),
                             [String(localized: "Se déconnecter"), String(localized: "Annuler")]) == 0 else { return }
        var outcome = await backup.signOut()
        while case .notSaved(let why) = outcome {
            switch Dialogs.choose(String(localized: "Tes derniers changements ne sont pas en ligne"),
                                  String(localized: "\(why) Si tu te déconnectes maintenant, ils seront perdus."),
                                  [String(localized: "Réessayer"), String(localized: "Se déconnecter quand même"),
                                   String(localized: "Annuler")], destructive: 1) {
            case 0: outcome = await backup.signOut()
            case 1: outcome = await backup.signOut(evenIfNotSaved: true)
            default: return
            }
        }
    }

    /// nil : supprimé, ou rien fait (annulé) ; sinon, ce qui s'est passé.
    static func deleteAccount(_ backup: AccountBackup? = nil) async -> String? {
        let backup = backup ?? .shared
        guard Dialogs.choose(String(localized: "Supprimer ton compte ?"),
                             String(localized: """
                                 Ton compte, ta sauvegarde en ligne et tes partages dans la Communauté seront effacés \
                                 pour toujours. Tes raccourcis et tes macros restent sur ce Mac.
                                 """),
                             [String(localized: "Supprimer définitivement"), String(localized: "Annuler")],
                             destructive: 0) == 0 else { return nil }
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
                                 title: String(localized: "Les comptes ne sont pas encore ouverts"),
                                 text: String(localized: "Tes raccourcis et tes macros restent sur ce Mac en attendant."))
            } else if let session = community.session {
                signedIn(session)
            } else {
                CommunitySignIn(community: community, page: .account)
            }
        }
        // Connexion, déconnexion : la page passe de l'une à l'autre en fondu.
        .softSwitch(!community.isConfigured ? 0 : community.session == nil ? 1 : 2)
        .task { await backup.refreshIfStale() }
        .onReceive(DebugSnapshot.publisher(DebugSnapshot.account)) { note in
            backup.showDemo(note.object as? String ?? "")
        }
    }

    /// Maquettes validées le 30/10 : une carte du profil (photo, pseudo, mail, « Modifier le profil », « Se
    /// déconnecter »), la sauvegarde en carte (son état, ce Mac, en ligne) et, quand ce Mac et le compte ont chacun
    /// leurs changements, la carte orange du choix ; « Supprimer mon compte » discret, en bas.
    private func signedIn(_ session: CommunitySession) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                AccountProfileCard(community: community, session: session) {
                    Task { await AccountActions.signOut(backup) }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12, alignment: .top)], spacing: 12) {
                    AccountBackupStatus(status: backup.status, here: backup.hereSummary, online: backup.onlineSummary,
                                        notice: backup.notice) { Task { await backup.saveNow() } }
                    if let conflict = backup.conflict {
                        AccountConflictCard(conflict: conflict) { keepAccount in
                            Task { await backup.resolve(keepAccount: keepAccount) }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "trash").foregroundStyle(Color.red)
                        Text("Supprimer mon compte").font(.system(size: 13))
                        Spacer(minLength: 12)
                        Button("Supprimer…", role: .destructive) {
                            Task { deleteError = await AccountActions.deleteAccount(backup) }
                        }
                        .secondaryButton()
                        .help("Efface ton compte, ta sauvegarde en ligne et tes partages. Tes raccourcis et tes macros restent sur ce Mac.")
                    }
                    if let deleteError {
                        Label(deleteError, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(MockPlate(cornerRadius: 14))
                .padding(.top, 10)
            }
            .padding(.horizontal, 26)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $community.editingProfile) {
            EditProfileSheet(community: community)
        }
    }
}

/// Carte du profil (maquette du 30/10) : la photo (clic : la changer), le pseudo, le mail, « Modifier le profil » et
/// « Se déconnecter ».
private struct AccountProfileCard: View {
    @ObservedObject var community: CommunityStore
    let session: CommunitySession
    let signOut: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Button { community.editingProfile = true } label: {
                AvatarView(photo: community.myPhoto, username: session.username, size: 76)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(white: 0.96))
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Color(white: 0.17)))                // #2c2c2e
                            .overlay(Circle().strokeBorder(Color(white: 0.14), lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
            }
            .buttonStyle(.plain)
            .help("Changer ta photo")
            .accessibilityLabel("Changer ta photo")
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "@" + session.username.displaySafe(max: 24))
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(1)
                Text(verbatim: session.email.displaySafe(max: 60))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 12)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons }
                VStack(alignment: .trailing, spacing: 8) { buttons }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(MockPlate(cornerRadius: 14))
    }

    @ViewBuilder private var buttons: some View {
        Button { community.editingProfile = true } label: {
            Label("Modifier le profil", systemImage: "pencil")
        }
        .secondaryButton()
        Button(action: signOut) {
            Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
        }
        .secondaryButton()
        .help("Tes raccourcis et tes macros quittent ce Mac et restent dans ton compte.")
    }
}

/// La sauvegarde en carte : son état (icône de couleur, titre, détail), « Sauvegarder », puis ce qu'il y a sur ce Mac
/// et en ligne.
private struct AccountBackupStatus: View {
    let status: AccountBackup.Status
    let here: String
    let online: String?
    let notice: String?
    let saveNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                SectionIcon(symbol: look.symbol, tint: look.color == .secondary ? .gray : look.color, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(look.title).font(.system(size: 15, weight: .bold))
                    Text(look.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                if look.busy {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Sauvegarder", action: saveNow)
                        .secondaryButton()
                        .disabled(status == .choice)
                        .help("Sauvegarder maintenant")
                }
            }
            HStack(spacing: 10) {
                tile(String(localized: "Sur ce Mac"), symbol: "laptopcomputer", here)
                tile(String(localized: "En ligne"), symbol: "icloud", online ?? "—")
            }
            if let notice {
                Label(notice, systemImage: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MockPlate(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private func tile(_ title: String, symbol: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black.opacity(0.22)))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }

    private var look: (symbol: String, color: Color, title: String, detail: String, busy: Bool) {
        switch status {
        case .off, .checking:
            return ("arrow.triangle.2.circlepath.icloud", .secondary, String(localized: "Vérification de ta sauvegarde…"),
                    String(localized: "Ce Mac et ton compte se comparent."), true)
        case .upToDate(let date):
            return ("checkmark.icloud.fill", .green, String(localized: "Sauvegarde à jour"),
                    date.map { AccountText.when($0).capitalizedFirst } ?? String(localized: "Tout est en ligne."), false)
        case .pending:
            return ("icloud.and.arrow.up", .blue, String(localized: "Changements à envoyer"),
                    String(localized: "Ils partent dans quelques secondes."), false)
        case .saving:
            return ("icloud.and.arrow.up.fill", .blue, String(localized: "Enregistrement en ligne…"),
                    String(localized: "Ne quitte pas l'app tout de suite."), true)
        case .waiting(let why):
            return ("exclamationmark.icloud.fill", .orange, String(localized: "Pas encore en ligne"), why, false)
        case .choice:
            return ("exclamationmark.icloud.fill", .orange, String(localized: "À toi de choisir"),
                    String(localized: "Ce Mac et ton compte ont chacun des changements : choisis la version à garder ci-dessus."),
                    false)
        case .blocked(let why):
            return ("xmark.icloud.fill", .red, String(localized: "Sauvegarde arrêtée"), why, false)
        }
    }
}

/// Ce Mac et le compte ont chacun leurs changements : carte orange, les deux versions côte à côte et le choix.
private struct AccountConflictCard: View {
    let conflict: AccountBackup.Conflict
    let choose: (_ keepAccount: Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SectionIcon(symbol: "arrow.triangle.2.circlepath", tint: .orange, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deux versions différentes").font(.system(size: 15, weight: .bold))
                    Text("Laquelle garder ?").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                side(title: String(localized: "Ce Mac"), summary: conflict.here,
                     effect: String(localized: "La sauvegarde de ton compte est remplacée par ce qu'il y a ici."),
                     button: String(localized: "Garder ce Mac"), prominent: true) { choose(false) }
                side(title: String(localized: "Mon compte"), summary: conflict.account
                        + (conflict.remote.updatedAt.map { " · \(AccountText.when($0))" } ?? ""),
                     effect: String(localized: """
                         Ce Mac reprend ta sauvegarde. Ce qu'il y avait ici est copié dans Application Support › \
                         FL Shortcuts.
                         """),
                     button: String(localized: "Garder mon compte"), prominent: false) { choose(true) }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            shape.fill(LinearGradient(colors: [Color.orange.opacity(0.16), Color.orange.opacity(0.06)],
                                      startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(Color.orange.opacity(0.45), lineWidth: 1))
        }
    }

    private func side(title: String, summary: String, effect: String, button: String, prominent: Bool,
                      action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
            Text(summary).font(.system(size: 13.5, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if prominent {
                Button(button, action: action).primaryButton().help(effect)
            } else {
                Button(button, action: action).secondaryButton().help(effect)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.black.opacity(0.25)))
    }
}

private extension String {
    /// « aujourd'hui à 18:54 » → « Aujourd'hui à 18:54 ».
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
