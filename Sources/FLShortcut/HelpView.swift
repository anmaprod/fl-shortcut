// Page Aide de la fenêtre principale (maquette « Minimal », 20/11) : deux onglets, Questions (recherche dans les
// questions fréquentes) et Mes messages (ce qu'on a écrit à l'équipe, sa réponse, « Répondre » ; SupportInbox.swift) ;
// « Écrire à l'équipe » (en haut à droite de la page) ouvre sa page : le genre (Un bug, Une idée, Une question,
// Autre), le message (la case grandit avec le texte), une capture si on veut ; l'état de l'appli part tout seul (des
// nombres, jamais de nom de son ni de touche). Un compte est nécessaire pour écrire : la réponse arrive dans Mes
// messages. App compilée sans serveur : copie ou mail (Support.swift).
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Écran de la page Aide.
enum HelpScreen: Equatable {
    case questions, messages, write
    case thread(UUID)
}

/// Demande d'ouvrir la page Aide (menu de la barre des menus, « Signaler ce problème ») : la fenêtre principale la
/// montre dès qu'elle est là, le formulaire prérempli avec l'erreur signalée. Garde aussi l'écran de la page (le
/// bouton « Écrire à l'équipe » de l'en-tête y mène).
final class HelpLink: ObservableObject {
    static let shared = HelpLink()
    @Published var pending = false
    /// Message d'erreur à joindre (macro qui échoue…), repris par le formulaire.
    @Published var reportedError: String?
    @Published var screen = HelpScreen.questions

    func show() { pending = true }

    /// « Signaler ce problème » : la page Aide, le formulaire prêt avec ce message d'erreur.
    func report(_ error: String) {
        reportedError = error
        pending = true
    }
}

struct HelpPage: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var status: AppStatus
    @EnvironmentObject var link: MIDILink
    @ObservedObject var community: CommunityStore
    let showGuide: () -> Void
    @ObservedObject private var helpLink = HelpLink.shared
    @ObservedObject private var inbox = SupportInbox.shared

    @State private var query = ""
    @State private var opened: Set<Int> = []
    @State private var message = SupportMessage()
    /// Le genre, choisi par la personne (rien d'office, comme la maquette ; « Signaler ce problème » : Un bug).
    @State private var kind: SupportKind?
    @State private var captureImage: NSImage?
    @State private var dropping = false
    @State private var sending = false
    @State private var failure: String?
    /// Envoyé sans « Mes messages » (serveur d'avant, ou sans serveur) : la référence seule.
    @State private var sentReference: String?
    @State private var reply = ""
    @State private var replying = false
    @State private var replySent = false
    @State private var tipsOpened: Set<Int> = []
    @State private var wide = true

    private var entries: [HelpEntry] { HelpContent.faq.filter { $0.matches(query) } }
    private var signedIn: Bool { community.session != nil || community.demo }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                switch helpLink.screen {
                case .write: writePage
                case .thread(let id): threadPage(id)
                case .questions, .messages:
                    tabs
                    if helpLink.screen == .messages { messagesPage } else { questionsPage }
                }
            }
            .readableColumn()
            .padding(.top, 6)
            .padding(.bottom, 32)
            .background(WidthReader { width in
                let fits = min(width - 2 * ReadableLayout.inset, ReadableLayout.maxWidth) >= 640
                if fits != wide { wide = fits }
            })
        }
        .onAppear {
            takeReportedError()
            Task { await inbox.load(community) }
        }
        .onChange(of: helpLink.reportedError) { _ in takeReportedError() }
        .onChange(of: community.session?.userID) { _ in
            inbox.forget()
            Task { await inbox.load(community) }
        }
        .onChange(of: helpLink.screen) { screen in
            if screen == .messages { Task { await inbox.load(community) } }
        }
        .onReceive(DebugSnapshot.publisher(DebugSnapshot.help)) { note in
            showCapture(note.object as? String ?? "")
        }
    }

    // MARK: Onglets

    /// Questions / Mes messages (comme les onglets de la Communauté) ; un point rouge : une nouvelle réponse.
    private var tabs: some View {
        HStack(spacing: 28) {
            tab(String(localized: "Questions"), .questions, dot: false)
            tab(String(localized: "Mes messages"), .messages, dot: signedIn && inbox.unread > 0)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Swiss.line).frame(height: 1) }
    }

    private func tab(_ title: String, _ screen: HelpScreen, dot: Bool) -> some View {
        let on = helpLink.screen == screen
        return Button {
            helpLink.screen = screen
        } label: {
            HStack(spacing: 7) {
                Text(title)
                    .font(Swiss.font(11.5)).tracking(1.3).textCase(.uppercase)
                    .foregroundStyle(on ? Swiss.text : Swiss.gray)
                if dot {
                    Rectangle().fill(Swiss.red).frame(width: 6, height: 6)
                        .accessibilityLabel(String(localized: "Nouvelle réponse"))
                }
            }
            .frame(height: 44)
            .overlay(alignment: .bottom) {
                if on { Rectangle().fill(Swiss.text).frame(height: 2) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Questions

    private var questionsPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            searchField.frame(maxWidth: 480)
            if entries.isEmpty {
                Text("Aucune réponse.").font(.system(size: 15)).foregroundStyle(Swiss.gray)
            } else {
                faqList(entries, opened: $opened)
            }
            Button("Revoir le guide") { showGuide() }
                .buttonStyle(SwissLinkButtonStyle())
                .font(.system(size: 13))
        }
        .padding(.top, 24)
    }

    /// Recherche dans l'aide : une case bordée, la loupe devant.
    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundStyle(Swiss.text)
            TextField("Rechercher dans l'aide", text: $query, prompt: Text("Rechercher dans l'aide").foregroundColor(Swiss.gray))
                .textFieldStyle(.plain)
                .font(Swiss.font(15, .regular))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Swiss.text)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Rectangle().fill(Swiss.background))
        .overlay(Rectangle().strokeBorder(Swiss.text, lineWidth: 2))
        .background(ReleaseOnOutsideClick())
    }

    /// Les questions en liste (▸ / ▾), un trait d'encre au-dessus, un trait fin entre elles.
    private func faqList(_ list: [HelpEntry], opened: Binding<Set<Int>>) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(list, id: \.id) { entry in
                HelpEntryRow(entry: entry, open: opened.wrappedValue.contains(entry.id)) {
                    if opened.wrappedValue.contains(entry.id) { opened.wrappedValue.remove(entry.id) } else { opened.wrappedValue.insert(entry.id) }
                }
                .padding(.vertical, 14)
                .overlay(alignment: .bottom) { Rectangle().fill(Swiss.line).frame(height: 1) }
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Swiss.text).frame(height: 2) }
    }

    // MARK: Mes messages

    @ViewBuilder private var messagesPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !signedIn {
                signInAsk(String(localized: "Connecte-toi pour retrouver tes messages."))
            } else if inbox.ready == false {
                Text("Mes messages n'est pas encore ouvert.").font(.system(size: 15)).foregroundStyle(Swiss.gray)
            } else if inbox.threads.isEmpty {
                Text(inbox.loading || inbox.ready == nil ? String(localized: "Chargement…") : String(localized: "Aucun message."))
                    .font(.system(size: 15)).foregroundStyle(Swiss.gray)
                if let error = inbox.error { SwissWarning(error).font(.system(size: 12)) }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(inbox.threads) { thread in messageRow(thread) }
                }
                .overlay(alignment: .top) { Rectangle().fill(Swiss.text).frame(height: 2) }
            }
        }
        .padding(.top, 24)
    }

    /// Une ligne : la 1re ligne du message en gras et son genre, la date, puis Envoyé / Réponse ✓ / Réponse ●.
    private func messageRow(_ thread: SupportThread) -> some View {
        let state = SupportInboxRules.state(thread, seen: inbox.seen)
        return Button {
            helpLink.screen = .thread(thread.id)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(thread.firstLine.displaySafe(max: 80))
                        .font(Swiss.font(15)).foregroundStyle(Swiss.text).lineLimit(1)
                    Text(thread.kindLabel).font(.system(size: 12)).foregroundStyle(Swiss.gray)
                }
                Spacer(minLength: 8)
                Text(SupportInboxRules.dateLabel(thread.createdAt)).font(.system(size: 12)).foregroundStyle(Swiss.gray)
                    .fixedSize()
                Group {
                    switch state {
                    case .sent: Text("Envoyé").foregroundStyle(Swiss.gray)
                    case .answered: Text("Réponse ✓").foregroundStyle(Swiss.text)
                    case .newAnswer:
                        HStack(spacing: 6) {
                            Text("Réponse").foregroundStyle(Swiss.red)
                            Rectangle().fill(Swiss.red).frame(width: 6, height: 6)
                        }
                    }
                }
                .font(Swiss.font(13))
                .frame(width: 96, alignment: .trailing)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(Swiss.line).frame(height: 1) }
    }

    // MARK: Un message

    @ViewBuilder private func threadPage(_ id: UUID) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            backLink(String(localized: "Mes messages"), to: .messages)
            if let thread = inbox.threads.first(where: { $0.id == id }) {
                Text(thread.kindLabel)
                    .font(Swiss.title(34)).tracking(Swiss.titleTracking(34)).foregroundStyle(Swiss.text)
                VStack(alignment: .leading, spacing: 0) {
                    bubble(team: false, text: thread.message, date: thread.createdAt, image: inbox.captures[thread.id])
                    ForEach(thread.replies) { r in bubble(team: r.team, text: r.message, date: r.createdAt, image: nil) }
                }
                .overlay(alignment: .top) { Rectangle().fill(Swiss.text).frame(height: 2) }
                if replySent { Text("Envoyé ✓").font(Swiss.font(15)).foregroundStyle(Swiss.text) }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Répondre").swissLabel(Swiss.text)
                    GrowingTextArea(text: $reply, placeholder: "", minLines: 3)
                    if let failure { SwissWarning(failure).font(.system(size: 12)) }
                    HStack {
                        Button("Envoyer") { Task { await sendReply(thread) } }
                            .primaryButton()
                            .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || replying)
                        if replying { ProgressView().controlSize(.small) }
                    }
                }
                .padding(.top, 12)
                .task(id: thread.id) {
                    replySent = false
                    failure = nil
                    await inbox.open(thread, community)
                }
            }
        }
        .padding(.top, 8)
    }

    private func bubble(team: Bool, text: String, date: String, image: NSImage?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: (team ? String(localized: "L'équipe") : String(localized: "Toi")) + " · "
                 + SupportInboxRules.dateLabel(date))
                .swissLabel(team ? Swiss.red : Swiss.gray)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Swiss.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let image {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 420, maxHeight: 280, alignment: .leading)
                    .overlay(Rectangle().strokeBorder(Swiss.line, lineWidth: 1))
                    .accessibilityLabel(String(localized: "Ta capture"))
            }
        }
        .padding(.vertical, 14)
        .padding(.leading, team ? 16 : 0)
        .overlay(alignment: .leading) { if team { Rectangle().fill(Swiss.red).frame(width: 2) } }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Swiss.line).frame(height: 1) }
    }

    private func sendReply(_ thread: SupportThread) async {
        replying = true
        failure = nil
        defer { replying = false }
        if let why = await inbox.reply(thread, text: reply, community) {
            failure = why
        } else {
            reply = ""
            replySent = true
        }
    }

    // MARK: Écrire à l'équipe

    @ViewBuilder private var writePage: some View {
        VStack(alignment: .leading, spacing: 20) {
            backLink(String(localized: "Aide"), to: .questions)
            Text("Écrire à l'équipe")
                .font(Swiss.title(34)).tracking(Swiss.titleTracking(34)).foregroundStyle(Swiss.text)
            if community.isConfigured && !signedIn {
                signInAsk(String(localized: "Connecte-toi pour écrire à l'équipe."))
            } else if let reference = sentReference {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Envoyé ✓").font(Swiss.font(17)).foregroundStyle(Swiss.text)
                    Text("Référence : \(reference)").font(.system(size: 12).monospacedDigit()).foregroundStyle(Swiss.gray)
                        .textSelection(.enabled)
                    Button("Écrire un autre message") { startWriting() }
                        .buttonStyle(SwissLinkButtonStyle())
                        .font(.system(size: 13))
                }
            } else if wide {
                HStack(alignment: .top, spacing: 40) {
                    form.frame(maxWidth: 560)
                    tipsColumn.frame(width: 260)
                }
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    form
                    tipsColumn
                }
            }
        }
        .padding(.top, 8)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let error = message.error {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        SwissWarning(String(localized: "Le problème signalé")).font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Button("Retirer") { message.error = nil }
                            .buttonStyle(SwissLinkButtonStyle())
                            .font(.system(size: 11))
                    }
                    Text(error).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("C'est à propos de").swissLabel(Swiss.text)
                HStack(spacing: -1) {
                    ForEach(SupportKind.allCases) { k in
                        Button(k.label) {
                            kind = k
                            message.kind = k
                        }
                        .buttonStyle(SwissChoiceStyle(chosen: kind == k, uppercase: false))
                        .accessibilityAddTraits(kind == k ? .isSelected : [])
                    }
                }
                .fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Message").swissLabel(Swiss.text)
                GrowingTextArea(text: $message.text, placeholder: (kind ?? .autre).placeholder, minLines: 6)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("Capture").swissLabel(Swiss.text)
                    Text("facultatif").font(.system(size: 12)).foregroundStyle(Swiss.gray)
                }
                captureZone
                if captureImage != nil {
                    Button("Retirer la capture") {
                        captureImage = nil
                        message.capture = nil
                    }
                    .buttonStyle(SwissLinkButtonStyle())
                    .font(.system(size: 12))
                }
            }
            if let failure {
                SwissWarning(failure).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 18) {
                if community.isConfigured {
                    Button("Envoyer") { Task { await send() } }
                        .primaryButton()
                        .keyboardShortcut(.defaultAction)
                        .disabled(!ready || sending)
                } else if let mail = SupportConfig.email {
                    Button("Envoyer par mail") { openMail(mail) }
                        .primaryButton()
                        .disabled(!ready)
                }
                if !community.isConfigured || failure != nil {
                    Button("Copier") { copy() }.secondaryButton().disabled(!ready)
                }
                Button("Annuler") { helpLink.screen = .questions }
                    .buttonStyle(SwissLinkButtonStyle())
                    .font(.system(size: 13))
                if sending { ProgressView().controlSize(.small) }
            }
        }
    }

    /// « Ajouter une capture » : un clic choisit une image ; on peut aussi la déposer ici.
    private var captureZone: some View {
        Button {
            chooseCapture()
        } label: {
            Group {
                if let captureImage {
                    HStack(spacing: 14) {
                        Image(nsImage: captureImage).resizable().scaledToFit().frame(maxWidth: 160, maxHeight: 100)
                        Text("Changer").font(Swiss.font(13)).foregroundStyle(Swiss.text).underline()
                    }
                    .padding(12)
                } else {
                    Text("Ajouter une capture").font(Swiss.font(13)).foregroundStyle(Swiss.text)
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Rectangle().fill(dropping ? Swiss.faint : Swiss.background))
            .overlay(Rectangle().strokeBorder(Swiss.text, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { useCapture(url) }
            }
            return true
        }
    }

    /// « Ça t'aide peut-être » : les questions qui parlent des mots du message.
    @ViewBuilder private var tipsColumn: some View {
        let tips = SupportInboxRules.tips(for: message.text, kind: kind, in: HelpContent.faq)
        if !tips.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ça t'aide peut-être").swissLabel(Swiss.text)
                faqList(tips, opened: $tipsOpened)
            }
        }
    }

    private func backLink(_ title: String, to screen: HelpScreen) -> some View {
        Button {
            helpLink.screen = screen
        } label: {
            Text(verbatim: "← " + title).font(.system(size: 13)).foregroundStyle(Swiss.gray)
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
    }

    private func signInAsk(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text).font(.system(size: 15)).foregroundStyle(Swiss.text)
            Button("Se connecter") { AccountLink.shared.pending = true }
                .primaryButton()
        }
    }

    private var ready: Bool { kind != nil && SupportRules.problem(message) == nil }

    private var outgoing: SupportMessage {
        var m = message
        m.kind = kind ?? .autre
        m.email = community.session?.email ?? ""
        m.diagnostic = SupportDiagnostic.report(
            SupportDiagnostic.current(store: store, status: status, fl: FLMonitor.shared, link: link),
            problems: ProblemLog.shared.text, journal: MacroLog.lastRunExcerpt())
        return m
    }

    private func startWriting() {
        message = SupportMessage()
        kind = nil
        captureImage = nil
        failure = nil
        sentReference = nil
        helpLink.screen = .write
    }

    /// « Signaler ce problème » : la page « Écrire à l'équipe », Un bug, l'erreur jointe.
    private func takeReportedError() {
        guard let error = helpLink.reportedError else { return }
        helpLink.reportedError = nil
        startWriting()
        kind = .probleme
        message.kind = .probleme
        message.error = error
    }

    private func chooseCapture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        useCapture(url)
    }

    private func useCapture(_ url: URL) {
        guard let text = SupportCapture.base64(fromFile: url), let image = SupportCapture.image(text) else {
            failure = String(localized: "Image illisible ou trop lourde.")
            return
        }
        failure = nil
        message.capture = text
        captureImage = image
    }

    /// Envoyé : le message dans « Mes messages » (serveur avec mes-messages.sql), sinon « Envoyé ✓ » et sa référence.
    private func send() async {
        sending = true
        failure = nil
        defer { sending = false }
        let sent = outgoing
        if let why = await community.sendSupport(sent) {
            failure = why
            return
        }
        await inbox.load(community)
        if inbox.ready == true, let thread = inbox.threads.first(where: { $0.reference == sent.reference }) {
            message = SupportMessage()
            kind = nil
            captureImage = nil
            helpLink.screen = .thread(thread.id)
            replySent = true
        } else {
            sentReference = sent.reference
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SupportRules.plainText(outgoing, appVersion: MacroFileActions.appVersion), forType: .string)
    }

    private func openMail(_ address: String) {
        if let url = SupportRules.mailURL(outgoing, to: address, appVersion: MacroFileActions.appVersion),
           !NSWorkspace.shared.open(url) {
            failure = String(localized: "Aucune app de mail : écris à \(address).")
        }
    }

    /// Mode capture (mesure de la CI) : « aide », « recherche », « ecrire », « envoye », « messages » ou « fil ».
    private func showCapture(_ screen: String) {
        query = screen == "recherche" ? "macro" : ""
        opened = screen == "aide" ? [1] : []
        failure = nil
        sentReference = nil
        if ["ecrire", "envoye", "messages", "fil"].contains(screen) {
            community.showDemo(signedIn: true)                // compte d'exemple, rien n'est envoyé
            Task { await inbox.load(community) }
        }
        switch screen {
        case "ecrire", "envoye":
            message = SupportMessage(kind: .probleme, text: "Je lançais ma macro « Armer la piste » depuis le Mixer.",
                                     error: "Macro : échec au bloc 3 (Attendre un menu) : aucun menu de FL ne s'est ouvert en 1,5 s.")
            kind = .probleme
            helpLink.screen = .write
            if screen == "envoye" { sentReference = "FLS-3F9A2C" }
        case "messages":
            helpLink.screen = .messages
        case "fil":
            helpLink.screen = .thread(SupportInbox.demoThreads[0].id)
        default:
            helpLink.screen = .questions
        }
    }
}

/// Zone de texte qui grandit avec le texte (20/11, « que ça grandisse si on écrit trop mais pas qu'on puisse jouer
/// avec ») : jamais redimensionnable à la main, `minLines` lignes au moins, 16 au plus (puis elle défile).
struct GrowingTextArea: View {
    @Binding var text: String
    let placeholder: String
    var minLines = 3

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundColor(Swiss.gray), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .lineLimit(minLines...16)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Rectangle().fill(Swiss.background))
            .overlay(Rectangle().strokeBorder(Swiss.text, lineWidth: 1))
    }
}

/// Une question : clic pour la réponse (en étapes numérotées quand elle en a : « 1. … 2. … »).
private struct HelpEntryRow: View {
    let entry: HelpEntry
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack {
                    Text(entry.question)
                        .font(Swiss.font(17)).tracking(-0.3)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? String(localized: "ouverte") : String(localized: "fermée"))
            if open {
                if let parsed = HelpEntry.steps(entry.answer) {
                    VStack(alignment: .leading, spacing: 8) {
                        if !parsed.intro.isEmpty { answerText(parsed.intro) }
                        ForEach(Array(parsed.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text(verbatim: "\(index + 1)")
                                    .font(Swiss.font(14).monospacedDigit())
                                    .foregroundStyle(Swiss.text)
                                    .frame(width: 16, alignment: .leading)
                                answerText(step)
                            }
                        }
                    }
                } else {
                    answerText(entry.answer)
                }
            }
        }
    }

    private func answerText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(Swiss.soft)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension HelpEntry {
    /// Numéro d'étape « 1. », compilé une seule fois (14/11, optimisation : une fois par question affichée avant).
    private static let stepNumber = try? NSRegularExpression(pattern: "(?:^|\\s)(\\d)\\.\\s")

    /// Pur (testé) : une réponse « Vérifie trois choses. 1. … 2. … 3. … » coupée en son début et ses étapes
    /// (numérotées 1, 2, 3… à la suite) ; nil si elle n'en a pas au moins deux.
    static func steps(_ answer: String) -> (intro: String, steps: [String])? {
        guard let regex = stepNumber else { return nil }
        let text = answer as NSString
        var cuts: [NSRange] = []
        for match in regex.matches(in: answer, range: NSRange(location: 0, length: text.length)) {
            guard Int(text.substring(with: match.range(at: 1))) == cuts.count + 1 else { continue }
            cuts.append(match.range)
        }
        guard cuts.count >= 2 else { return nil }
        let intro = text.substring(to: cuts[0].location).trimmingCharacters(in: .whitespacesAndNewlines)
        let steps = cuts.indices.map { i -> String in
            let start = cuts[i].location + cuts[i].length
            let end = i + 1 < cuts.count ? cuts[i + 1].location : text.length
            return text.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (intro, steps)
    }
}
