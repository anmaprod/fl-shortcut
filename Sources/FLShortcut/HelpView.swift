// Page Aide de la fenêtre principale (barre de gauche, sous Communauté ; aussi le menu de la barre des menus) :
// recherche dans les questions fréquentes, puis « Écrire à l'équipe » (problème, question ou idée), avec l'état de
// l'app joint si on le laisse coché, affiché tel quel. Envoi par le serveur s'il est branché ; sinon, ou
// s'il échoue, par mail, en copie ou en ticket GitHub (Support.swift).
import AppKit
import SwiftUI

/// Demande d'ouvrir la page Aide (menu de la barre des menus, « Signaler ce problème ») : la fenêtre principale la
/// montre dès qu'elle est là, le formulaire prérempli avec l'erreur signalée.
final class HelpLink: ObservableObject {
    static let shared = HelpLink()
    @Published var pending = false
    /// Message d'erreur à joindre (macro qui échoue…), repris par le formulaire.
    @Published var reportedError: String?

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

    @State private var query = ""
    @State private var opened: Set<Int> = []
    @State private var message = SupportMessage()
    @State private var includeDiagnostic = true
    @State private var showDiagnostic = false
    @State private var sending = false
    @State private var sent = false
    @State private var failure: String?
    /// L'app de mail s'est ouverte avec le message : reste à l'envoyer.
    @State private var mailOpened = false
    /// Ce qui est joint (état, derniers problèmes, journal de la dernière macro), relu à l'ouverture et à l'envoi.
    @State private var attached = ""
    @State private var scrollToForm = 0
    /// « Écrire… » choisi (ou un problème signalé) : le formulaire s'ouvre sous les questions.
    @State private var writing = false
    /// Assez large pour les questions et, à droite, « Écrire à l'équipe » et le guide.
    @State private var wide = true

    private var entries: [HelpEntry] { HelpContent.faq.filter { $0.matches(query) } }

    /// Maquette validée le 30/10 : la recherche en grand, les questions dans une carte (réponse en étapes numérotées
    /// quand elle en a), à droite « Écrire à l'équipe » et « Revoir le guide » ; le formulaire s'ouvre dessous.
    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    searchField
                    if wide {
                        HStack(alignment: .top, spacing: 12) {
                            faqCard
                            sideCards.frame(width: 250)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            faqCard
                            sideCards
                        }
                    }
                    if writing || sent {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Écrire à l'équipe").font(.system(size: 15, weight: .bold))
                            Group {
                                if sent { sentCard } else { form }
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(MockPlate(cornerRadius: 14))
                        }
                        .id("form")
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 10)
                .padding(.bottom, 24)
                .background(WidthReader { width in
                    let fits = width >= 640
                    if fits != wide { wide = fits }
                })
            }
            .onAppear {
                if message.email.isEmpty { message.email = community.session?.email ?? "" }
                refreshAttached()
                takeReportedError()
            }
            .onChange(of: helpLink.reportedError) { _ in takeReportedError() }
            .onChange(of: scrollToForm) { _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { reader.scrollTo("form", anchor: .top) }
            }
            .onReceive(DebugSnapshot.publisher(DebugSnapshot.help)) { note in
                showCapture(note.object as? String ?? "")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(.secondary)
            TextField("Rechercher", text: $query, prompt: Text("Cherche dans l'aide : raccourcis, macro, pause…"))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Effacer la recherche")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    /// Les questions, dans une carte ; un trait fin entre deux.
    private var faqCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if entries.isEmpty {
                Text("Aucune réponse pour « \(query.displaySafe(max: 30)) » : écris-nous juste en dessous, on te répond.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(16)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    HelpEntryRow(entry: entry, open: opened.contains(entry.id)) {
                        withAnimation(Motion.smooth) {
                            if opened.contains(entry.id) { opened.remove(entry.id) } else { opened.insert(entry.id) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) {
                        if index > 0 { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MockPlate(cornerRadius: 14))
    }

    /// À droite des questions : écrire à l'équipe, revoir le guide.
    private var sideCards: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                SectionIcon(symbol: "bubble.left", tint: SidebarItem.help.tint, size: 40)
                Text("Écrire à l'équipe").font(.system(size: 15, weight: .bold))
                Button("Écrire un message…") {
                    writing = true
                    sent = false
                    scrollToForm += 1
                }
                .primaryButton()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MockPlate(cornerRadius: 14))
            Button {
                showGuide()
            } label: {
                HStack(spacing: 12) {
                    SectionIcon(symbol: "play", tint: .green, size: 32)
                    Text("Revoir le guide").font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MockPlate(cornerRadius: 14))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .menuHover(tint: .green, cornerRadius: 14)
            .help("Revoir le guide de FL Shortcuts")
        }
    }

    // MARK: Écrire à l'équipe

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = message.error {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label("Le problème signalé", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Retirer") { message.error = nil }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                    }
                    Text(error)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Dis en quelques mots ce que tu faisais juste avant : ça nous aide beaucoup.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.orange.opacity(0.08)))
            }
            Picker("Genre", selection: $message.kind) {
                ForEach(SupportKind.allCases) { kind in Text(kind.label).tag(kind) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            VStack(alignment: .trailing, spacing: 3) {
                TextEditor(text: $message.text)
                    .font(.system(size: 12))
                    .frame(minHeight: 110)
                    .overlay(alignment: .topLeading) {
                        if message.text.isEmpty {
                            Text(message.kind.placeholder)
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                Text("\(message.text.count)/\(SupportRules.messageRange.upperBound)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            TextField("Ton mail", text: $message.email, prompt: Text("Ton mail, pour qu'on te réponde (facultatif)"))
                .textFieldStyle(.roundedBorder)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Toggle("Joindre l'état de l'appli (recommandé)", isOn: $includeDiagnostic)
                        .toggleStyle(.checkbox)
                    Spacer()
                    Button(showDiagnostic ? String(localized: "Masquer") : String(localized: "Voir ce qui est joint")) {
                        refreshAttached()
                        withAnimation(Motion.smooth) { showDiagnostic.toggle() }
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                }
                if showDiagnostic {
                    ScrollView {
                        Text(attached)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                }
                Label("Jamais envoyé : tes touches, tes noms de pistes, tes fichiers.", systemImage: "lock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if mailOpened {
                Label("Ton app de mail s'est ouverte avec le message tout prêt : vérifie-le, puis envoie-le.",
                      systemImage: "envelope")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
        .padding(.vertical, 4)
    }

    private var outgoing: SupportMessage {
        var m = message
        m.diagnostic = includeDiagnostic ? attached : nil
        return m
    }

    private func refreshAttached() {
        attached = SupportDiagnostic.report(
            SupportDiagnostic.current(store: store, status: status, fl: FLMonitor.shared, link: link),
            problems: ProblemLog.shared.text, journal: MacroLog.lastRunExcerpt())
    }

    /// « Signaler ce problème » : formulaire prêt avec l'erreur, page déroulée jusqu'à lui.
    private func takeReportedError() {
        guard let error = helpLink.reportedError else { return }
        helpLink.reportedError = nil
        message.kind = .probleme
        message.error = error
        writing = true
        sent = false
        failure = nil
        mailOpened = false
        refreshAttached()
        scrollToForm += 1
    }

    private var ready: Bool { SupportRules.problem(message) == nil }

    /// Le serveur d'abord ; le mail de l'équipe s'il n'y a pas de serveur (ou après un échec) ; sinon copie et ticket.
    @ViewBuilder private var buttons: some View {
        let mail = SupportConfig.email
        HStack(spacing: 8) {
            if !ready, !message.text.isEmpty, let why = SupportRules.problem(message) {
                Text(why).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if sending { ProgressView().controlSize(.small) }
            if !community.isConfigured || failure != nil {
                Button("Copier") { copy() }
                    .disabled(!ready)
                    .help("Copier le message, pour le coller où tu veux")
                if mail == nil {
                    Button("Ouvrir un ticket sur GitHub") { openIssue() }
                        .disabled(!ready)
                        .help("Page publique : ton mail n'y est pas recopié")
                }
            }
            if community.isConfigured && failure == nil {
                Button("Envoyer") { Task { await send() } }
                    .primaryButton()
                    .keyboardShortcut(.defaultAction)
                    .disabled(!ready || sending)
            } else if let mail {
                Button("Envoyer par mail") { openMail(mail) }
                    .primaryButton()
                    .keyboardShortcut(.defaultAction)
                    .disabled(!ready)
                    .help("Ouvre ton app de mail avec le message tout prêt, pour \(mail)")
            }
        }
    }

    private var sentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Merci, c'est envoyé !", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            let mail = message.email.trimmingCharacters(in: .whitespaces)
            Text(mail.isEmpty
                 ? String(localized: """
                     On lira ton message. Sans mail, on ne peut pas te répondre : écris-en un la prochaine fois si tu veux une réponse.
                     """)
                 : String(localized: "On te répond à \(mail) dès que possible."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Référence : \(message.reference)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Button("Écrire un autre message") {
                message.text = ""
                message.error = nil
                message.reference = SupportMessage.newReference()
                sent = false
                writing = true
            }
            .buttonStyle(.link)
            .font(.system(size: 12))
        }
        .padding(.vertical, 4)
    }

    private func send() async {
        sending = true
        failure = nil
        defer { sending = false }
        refreshAttached()
        if let why = await community.sendSupport(outgoing) {
            failure = SupportConfig.email == nil
                ? String(localized: "Envoi impossible : \(why) Tu peux le copier ou ouvrir un ticket.")
                : String(localized: "Envoi impossible : \(why) Tu peux l'envoyer par mail.")
        } else {
            sent = true
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(SupportRules.plainText(outgoing, appVersion: MacroFileActions.appVersion), forType: .string)
    }

    private func openMail(_ address: String) {
        refreshAttached()
        if let url = SupportRules.mailURL(outgoing, to: address, appVersion: MacroFileActions.appVersion) {
            mailOpened = NSWorkspace.shared.open(url)
            if !mailOpened {
                failure = String(localized: "Aucune app de mail ne s'est ouverte : copie le message et envoie-le à \(address).")
            }
        }
    }

    private func openIssue() {
        if let url = SupportRules.issueURL(outgoing, appVersion: MacroFileActions.appVersion) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Mode capture (mesure de la CI) : « aide », « recherche », « ecrire » ou « envoye ».
    private func showCapture(_ screen: String) {
        query = screen == "recherche" ? "macro" : ""
        opened = screen == "aide" ? [1] : []
        sent = screen == "envoye"
        writing = screen == "ecrire" || screen == "envoye"
        failure = nil
        if screen == "ecrire" || screen == "envoye" {
            message = SupportMessage(kind: .probleme, text: "Je lançais ma macro « Armer la piste » depuis le Mixer.",
                                     email: "malo@exemple.fr",
                                     error: "Macro : échec au bloc 3 (Attendre un menu) : aucun menu de FL ne s'est ouvert en 1,5 s.")
            showDiagnostic = false
            refreshAttached()
            scrollToForm += 1
        }
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
                        .font(.system(size: 13, weight: open ? .bold : .medium))
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
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
                                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                                    .foregroundStyle(Color.white)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(SidebarItem.help.tint))
                                answerText(step).padding(.top, 3)
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
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension HelpEntry {
    /// Pur (testé) : une réponse « Vérifie trois choses. 1. … 2. … 3. … » coupée en son début et ses étapes
    /// (numérotées 1, 2, 3… à la suite) ; nil si elle n'en a pas au moins deux.
    static func steps(_ answer: String) -> (intro: String, steps: [String])? {
        guard let regex = try? NSRegularExpression(pattern: "(?:^|\\s)(\\d)\\.\\s") else { return nil }
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
