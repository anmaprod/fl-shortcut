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
                VStack(spacing: 0) {
                    CommunityMessage(symbol: "person.crop.circle.badge.xmark", tint: SidebarItem.account.tint,
                                     title: String(localized: "Les comptes ne sont pas encore ouverts"),
                                     text: String(localized: "Tes raccourcis et tes macros restent sur ce Mac en attendant."))
                    themeBelow
                }
            } else if let session = community.session {
                signedIn(session)
            } else {
                VStack(spacing: 0) {
                    CommunitySignIn(community: community, page: .account)
                    themeBelow
                }
            }
        }
        // Connexion, déconnexion : la page passe de l'une à l'autre en fondu.
        .softSwitch(!community.isConfigured ? 0 : community.session == nil ? 1 : 2)
        .task { await backup.refreshIfStale() }
        .onReceive(DebugSnapshot.publisher(DebugSnapshot.account)) { note in
            backup.showDemo(note.object as? String ?? "")
        }
    }

    /// Maquette du 05/11 (« la page Mon compte, elle est plutôt cool… la page de thème, elle est très bien ») : à
    /// gauche le profil puis le thème ; à droite la sauvegarde en ligne (et le choix quand ce Mac et le compte ont
    /// chacun leurs changements) ; en bas « Se déconnecter » et « Supprimer mon compte » souligné.
    private func signedIn(_ session: CommunitySession) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 20, alignment: .top)],
                          alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 20) {
                        AccountProfileCard(community: community, session: session)
                        AccountThemeCard()
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        AccountBackupStatus(status: backup.status, here: backup.hereSummary, online: backup.onlineSummary,
                                            notice: backup.notice) { Task { await backup.saveNow() } }
                        if let conflict = backup.conflict {
                            AccountConflictCard(conflict: conflict) { keepAccount in
                                Task { await backup.resolve(keepAccount: keepAccount) }
                            }
                        }
                    }
                }
                HStack(spacing: 20) {
                    Button("Se déconnecter") { Task { await AccountActions.signOut(backup) } }
                        .secondaryButton()
                        .controlSize(.large)
                        .help("Tes raccourcis et tes macros quittent ce Mac et restent dans ton compte.")
                    Button("Supprimer mon compte") {
                        Task { deleteError = await AccountActions.deleteAccount(backup) }
                    }
                    .buttonStyle(SwissLinkButtonStyle())
                    .font(.system(size: 13))
                    .help("Efface ton compte, ta sauvegarde en ligne et tes partages. Tes raccourcis et tes macros restent sur ce Mac.")
                }
                if let deleteError {
                    Label(deleteError, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Swiss.red)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .sheet(isPresented: $community.editingProfile) {
            EditProfileSheet(community: community)
                .swissSheet()
        }
    }

    /// Sans compte (ou comptes pas encore ouverts) : le choix du thème reste là, sous la page.
    private var themeBelow: some View {
        AccountThemeCard()
            .padding(.horizontal, 26)
            .padding(.bottom, 20)
    }
}

/// Choix du thème (demande du 04/11, maquette validée) : trois aperçus, Noir, Papier, Orange ; le choisi entouré et
/// soulevé sur son ombre rouge ; un clic le prend tout de suite, pour toute l'app (AppTheme.choose).
struct AccountThemeCard: View {
    @State private var chosen = AppTheme.current

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Thème").swissLabel()
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 12) {
                ForEach(AppTheme.allCases) { theme in
                    ThemeTile(theme: theme, selected: theme == chosen) {
                        chosen = theme
                        AppTheme.choose(theme)
                    }
                }
            }
            .padding(.trailing, 4)
        }
        .swissPanel()
    }
}

/// Un thème : son petit aperçu (barre de gauche, titre, texte, rond de la marque) et son nom.
private struct ThemeTile: View {
    let theme: AppTheme
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 8) {
                ThemePreview(theme: theme).frame(height: 62)
                HStack(spacing: 4) {
                    Text(verbatim: theme.title).font(Swiss.font(14))
                    Spacer(minLength: 4)
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).accessibilityHidden(true)
                    }
                }
                .foregroundStyle(Swiss.text)
                .padding(.horizontal, 2)
            }
            .padding(6)
            .background(Rectangle().fill(Swiss.background))
            .overlay(Rectangle().strokeBorder(selected ? Swiss.text : Swiss.line, lineWidth: selected ? 2 : 1))
            .background(Rectangle().fill(Swiss.brandRed).offset(x: 4, y: 4).opacity(selected ? 1 : 0))
            .offset(x: selected ? -3 : 0, y: selected ? -3 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .help(theme.title)
        .accessibilityLabel(theme.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Aperçu d'un thème, dans ses propres couleurs (pas celles du thème en cours).
struct ThemePreview: View {
    let theme: AppTheme

    private struct Colors {
        let page, side, sideLine, sideInk, ink, frame: UInt32
    }

    private var colors: Colors {
        switch theme {
        case .noir:
            return Colors(page: 0x000000, side: 0x000000, sideLine: 0x333333, sideInk: 0xFFFFFF, ink: 0xFFFFFF,
                          frame: 0x333333)
        case .papier:
            return Colors(page: 0xFFFFFF, side: 0xFFFFFF, sideLine: 0xCFCFCF, sideInk: 0x000000, ink: 0x000000,
                          frame: 0xCFCFCF)
        case .orange:
            return Colors(page: SwissPalette.brandRed, side: 0x000000, sideLine: 0x000000, sideInk: 0xFFFFFF,
                          ink: 0x000000, frame: 0x000000)
        }
    }

    var body: some View {
        let c = colors
        func color(_ rgb: UInt32, _ alpha: Double = 1) -> Color { Color(nsColor: SwissPalette.nsColor(rgb)).opacity(alpha) }
        return Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color(c.page)))
            let side = (size.width * 0.32).rounded()
            context.fill(Path(CGRect(x: 0, y: 0, width: side, height: size.height)), with: .color(color(c.side)))
            context.fill(Path(CGRect(x: side - 1, y: 0, width: 1, height: size.height)), with: .color(color(c.sideLine)))
            for (i, bar) in [(0.8, 1.0), (0.6, 0.45), (0.7, 0.45)].enumerated() {
                context.fill(Path(CGRect(x: 5, y: 8 + CGFloat(i) * 9, width: (side - 10) * bar.0, height: 4)),
                             with: .color(color(c.sideInk, bar.1)))
            }
            let x = side + 8, width = max(0, size.width - side - 16)
            context.fill(Path(CGRect(x: x, y: 8, width: width * 0.64, height: 9)), with: .color(color(c.ink)))
            context.fill(Path(CGRect(x: x, y: 23, width: width * 0.9, height: 4)), with: .color(color(c.ink, 0.4)))
            context.fill(Path(ellipseIn: CGRect(x: x, y: 33, width: 11, height: 11)), with: .color(Swiss.brandRed))
        }
        .overlay(Rectangle().strokeBorder(color(c.frame), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Carte du profil (maquette du 05/11) : « PROFIL », la photo ronde (clic : la changer), le pseudo, le mail, puis
/// « Modifier le profil ».
private struct AccountProfileCard: View {
    @ObservedObject var community: CommunityStore
    let session: CommunitySession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Profil").swissLabel().accessibilityAddTraits(.isHeader)
            HStack(spacing: 16) {
                Button { community.editingProfile = true } label: {
                    AvatarView(photo: community.myPhoto, username: session.username, size: 72)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Swiss.background)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Swiss.text))
                                .offset(x: 2, y: 2)
                        }
                }
                .buttonStyle(.plain)
                .help("Changer ta photo")
                .accessibilityLabel("Changer ta photo")
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: session.username.displaySafe(max: 24))
                        .font(Swiss.title(24)).tracking(-0.8)
                        .lineLimit(1)
                    Text(verbatim: session.email.displaySafe(max: 60))
                        .font(.system(size: 14))
                        .foregroundStyle(Swiss.gray)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Button("Modifier le profil") { community.editingProfile = true }
                .secondaryButton()
        }
        .swissPanel()
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

    /// Maquette du 05/11 : « SAUVEGARDE EN LIGNE » et le bouton à droite, l'état en grand (« À jour. »), son détail,
    /// puis ce Mac et le compte en lignes séparées d'un trait.
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Sauvegarde en ligne").swissLabel()
                Spacer(minLength: 12)
                if look.busy {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Sauvegarder", action: saveNow)
                        .secondaryButton()
                        .controlSize(.small)
                        .disabled(status == .choice)
                        .help("Sauvegarder maintenant")
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(look.title).font(Swiss.title(22)).tracking(-0.7)
                    .foregroundStyle(look.color == .red || look.color == .orange ? Swiss.red : Swiss.text)
                Text(look.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Swiss.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                row(String(localized: "Sur ce Mac"), here)
                row(String(localized: "En ligne"), online ?? "—")
            }
            .padding(.top, 4)
            if let notice {
                Text(notice).font(.system(size: 12)).foregroundStyle(Swiss.gray)
            }
        }
        .swissPanel()
        .accessibilityElement(children: .contain)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title).swissLabel()
            Spacer(minLength: 8)
            Text(value).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(minHeight: 44)
        .overlay(alignment: .top) { Rectangle().fill(Swiss.faint).frame(height: 1) }
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
            let shape = Rectangle()
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
        .background(Rectangle().fill(Swiss.background))
    }
}

private extension String {
    /// « aujourd'hui à 18:54 » → « Aujourd'hui à 18:54 ».
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
