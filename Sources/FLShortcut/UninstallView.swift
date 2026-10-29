// Désinstallation en 3 étapes, à la façon d'Apple :
// 1. « Désinstaller FL Shortcuts ? » ; si les raccourcis et les macros ne sont sauvegardés nulle part (pas connecté
//    au compte, ou derniers changements pas encore en ligne), une ligne le dit, avec de quoi les sauvegarder d'abord ;
// 2. rien à confirmer de plus, sauf pour une app installée par un ancien .pkg (au système) : le mot de passe du Mac,
//    une seule fois, avant toute suppression. Refusé : rien n'est supprimé ;
// 3. le bilan vérifié (Uninstaller.removeEverything) : coche verte qui apparaît en grandissant, « Quitter » en bas à
//    droite ; s'il reste quelque chose, « Glisse FL Shortcuts dans la Corbeille » et « Afficher dans le Finder ».
// Aspect de l'app (29/10, « refaire la désinstallation dans le nouveau style, sans toucher à sa fonctionnalité ») :
// fond noir plein, titre en gras, ce qu'il faut savoir dans des plaques claires (icône de couleur), boutons en capsule
// (bleu pour l'action) ; textes courts (les gens lisent ce qui est court).
import AppKit
import SwiftUI

/// Un lien vers la page Mon compte, depuis l'extérieur de la fenêtre principale (fenêtre de désinstallation).
final class AccountLink: ObservableObject {
    static let shared = AccountLink()
    @Published var pending = false

    /// Ouvre la fenêtre principale sur la page Mon compte.
    func show() {
        pending = true
        NotificationCenter.default.post(name: Self.openEditor, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Reçu par l'icône de la barre des menus (MenuBarLabel), qui sait ouvrir la fenêtre principale.
    static let openEditor = Notification.Name("app.flshortcut.openEditor")
}

@MainActor
final class UninstallFlow: ObservableObject {
    enum Step: Equatable {
        case confirm
        case authenticating
        case working
        case done(Uninstaller.Report)
    }

    /// Ce que la désinstallation fait perdre, selon le compte.
    enum Risk: Equatable {
        /// Rien de personnel sur ce Mac.
        case nothing
        /// Pas connecté : tout serait perdu.
        case notSignedIn
        /// Connecté, mais les derniers changements ne sont pas en ligne.
        case notSaved
        /// Tout est dans le compte.
        case saved
    }

    @Published var step: Step = .confirm
    @Published var removeExports = false
    /// Désinstallation refusée à l'étape 2 : rien n'a été supprimé.
    @Published var cancelled: String?
    let risk: Risk
    let hasExports: Bool
    /// Mode capture (mesure de la CI) : écrans seulement, rien n'est demandé ni supprimé.
    let demo: Bool

    init(risk: Risk, hasExports: Bool, demo: Bool = false) {
        self.risk = risk
        self.hasExports = hasExports
        self.demo = demo
    }

    static func currentRisk() -> Risk {
        let store = Store.shared
        if store.isUntouched { return .nothing }
        let backup = AccountBackup.shared
        guard backup.community.session != nil else { return .notSignedIn }
        if case .upToDate = backup.status, !backup.hasUnsavedChanges { return .saved }
        return .notSaved
    }

    /// Étape 2, puis 3. Rien à confirmer de plus : le bouton « Désinstaller » suffit. Le mot de passe du Mac n'est
    /// demandé que pour une app installée par un ancien .pkg (elle appartient au système).
    func start() {
        guard !demo else { return }
        cancelled = nil
        let work = Uninstaller.privilegedWork()
        guard !work.isEmpty else {
            finish()
            return
        }
        step = .authenticating
        // La fenêtre de macOS (mot de passe) s'affiche ; l'étape « Ton mot de passe… » est dessinée avant.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch Uninstaller.runPrivileged(work) {
            case .cancelled: self.back(String(localized: "Rien n'a été supprimé."))
            case .done, .failed: self.finish()   // ce qui a résisté est dans le bilan
            }
        }
    }

    private func back(_ why: String) {
        cancelled = why
        step = .confirm
    }

    /// Tout est parti : l'app se ferme d'elle-même après un court instant (le bilan reste lisible), plus rien ne
    /// tourne. S'il reste quelque chose à glisser à la Corbeille, la fenêtre attend.
    static let autoQuitDelay: TimeInterval = 2.5

    private func finish() {
        step = .working
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let report = Uninstaller.removeEverything(interactive: true, removeExports: self.removeExports)
            self.step = .done(report)
            if report.remaining.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoQuitDelay) { Uninstaller.quitAfterUninstall() }
            }
        }
    }

    /// Mode capture : un écran donné, avec des exemples.
    func showDemo(_ screen: String) {
        cancelled = nil
        switch screen {
        case "fini":
            step = .done(Uninstaller.Report(removed: ["l'app (/Applications)", "tes raccourcis et tes macros", "les réglages"]))
        case "reste":
            step = .done(Uninstaller.Report(removed: ["tes raccourcis et tes macros"],
                                            remaining: [Uninstaller.Trace(url: URL(fileURLWithPath: "/Applications/FL Shortcuts.app"),
                                                                          label: "l'app (/Applications)")]))
        default:
            step = .confirm
        }
    }
}

/// Fenêtre de la désinstallation (une seule à la fois). La fermer après la suppression quitte l'app.
@MainActor
final class UninstallWindow: NSObject, NSWindowDelegate {
    static let shared = UninstallWindow()
    private var window: NSWindow?
    private var flow: UninstallFlow?

    /// Mode capture : un écran d'exemple ; « fermer » ferme la fenêtre (sans quitter). « reel » : la vraie
    /// désinstallation, comme si on cliquait « Désinstaller » (essai de la fenêtre sur la CI, machine jetable).
    func showDemo(_ screen: String) {
        switch screen {
        case "fermer":
            window?.close()
        case "reel":
            guard ProcessInfo.processInfo.environment["FLS_ESSAI_DESINSTALLATION"] == "1" else { return }
            show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.flow?.removeExports = true
                self?.flow?.start()
            }
        default:
            show(demo: screen)
        }
    }

    func show(demo: String? = nil) {
        if let window, demo == nil {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hasExports = Uninstaller.hasExports(home: FileManager.default.homeDirectoryForCurrentUser)
        let risk: UninstallFlow.Risk = demo == "compte" ? .saved : demo != nil ? .notSignedIn : UninstallFlow.currentRisk()
        let flow = UninstallFlow(risk: risk, hasExports: hasExports, demo: demo != nil)
        if let demo { flow.showDemo(demo) }
        self.flow = flow
        let host = NSHostingController(rootView: UninstallView(flow: flow, close: { [weak self] in self?.close() }))
        let w = self.window ?? NSWindow(contentViewController: host)
        w.contentViewController = host
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.title = String(localized: "Désinstaller FL Shortcuts")
        w.delegate = self
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func close() { window?.close() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        flow?.step == .authenticating || flow?.step == .working ? false : true
    }

    func windowWillClose(_ notification: Notification) {
        if case .done = flow?.step, flow?.demo == false { Uninstaller.quitAfterUninstall() }
        window = nil
        flow = nil
    }
}

/// Comme les autres fenêtres de l'app (maquettes du 28/10) : fond noir plein, l'icône, le titre en gras, une phrase ;
/// ce qu'il faut savoir dans des plaques claires (icône de couleur), boutons en capsule en bas (bleu pour l'action).
/// Textes courts : une idée par ligne.
struct UninstallView: View {
    @ObservedObject var flow: UninstallFlow
    let close: () -> Void

    var body: some View {
        Group {
            switch flow.step {
            case .confirm: confirm
            case .authenticating:
                waiting(symbol: "lock", tint: .orange,
                        title: String(localized: "Ton mot de passe du Mac, une seule fois (ancienne installation)"))
            case .working: waiting(symbol: "trash", tint: .red, title: String(localized: "Suppression…"))
            case .done(let report): done(report)
            }
        }
        .softSwitch(stepKey)
        .padding(.horizontal, 26)
        .padding(.top, 34)
        .padding(.bottom, 22)
        // Même taille à chaque étape : la fenêtre ne saute plus quand le contenu change (confirmation haute, attente
        // courte, bilan) ; chaque étape est centrée dedans.
        .frame(width: 380, height: 420)
        // Fond noir plein, jusque sous la barre de titre (comme la fenêtre principale).
        .background(Appearance.windowColor.ignoresSafeArea())
    }

    /// Étape affichée : chacune arrive en fondu flou, comme dans le guide.
    private var stepKey: Int {
        switch flow.step {
        case .confirm: return 0
        case .authenticating: return 1
        case .working: return 2
        case .done: return 3
        }
    }

    /// Deux boutons de même largeur, en capsule (le second en bleu).
    private func buttons<A: View, B: View>(@ViewBuilder first: () -> A, @ViewBuilder second: () -> B) -> some View {
        HStack(spacing: 10) {
            first()
            second()
        }
        .controlSize(.large)
    }

    // MARK: 1. Confirmation

    private var confirm: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("Désinstaller FL Shortcuts ?")
                .font(.system(size: 18, weight: .bold))
                .padding(.top, 12)
            Text("L'app et tous ses réglages seront supprimés de ce Mac.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            VStack(spacing: 8) {
                risk
                if flow.hasExports {
                    HStack(spacing: 10) {
                        SectionIcon(symbol: "square.and.arrow.up", tint: .gray, size: 24)
                        Text("Supprimer aussi mes fichiers exportés")
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 6)
                        Toggle("", isOn: $flow.removeExports)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(GlassPlateBackground())
                    .accessibilityElement(children: .combine)
                }
                if let cancelled = flow.cancelled {
                    Text(cancelled).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 16)
            Spacer(minLength: 12)
            buttons {
                Button(action: close) { Text("Annuler").frame(maxWidth: .infinity) }
                    .secondaryButton()
                    .keyboardShortcut(.cancelAction)
            } second: {
                Button { flow.start() } label: { Text("Désinstaller").frame(maxWidth: .infinity) }
                    .primaryButton()
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    @ViewBuilder
    private var risk: some View {
        switch flow.risk {
        case .nothing:
            EmptyView()
        case .saved:
            HStack(spacing: 10) {
                SectionIcon(symbol: "checkmark", tint: .green, size: 24)
                Text("Tes raccourcis et tes macros restent dans ton compte.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(GlassPlateBackground())
        case .notSignedIn:
            warning(String(localized: "Tes raccourcis et tes macros ne sont pas sauvegardés : ils seront perdus."),
                    link: String(localized: "Les sauvegarder d'abord"))
        case .notSaved:
            warning(String(localized: "Tes derniers changements ne sont pas encore sauvegardés."),
                    link: String(localized: "Ouvrir Mon compte"))
        }
    }

    /// Ce qui serait perdu : une plaque bordée d'orange, l'icône, la phrase, et le lien pour sauvegarder d'abord.
    private func warning(_ text: String, link: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            SectionIcon(symbol: "exclamationmark.triangle", tint: .orange, size: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Button(link) {
                    close()
                    AccountLink.shared.show()
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
        )
    }

    // MARK: 2. Mot de passe (ancienne installation), suppression

    private func waiting(symbol: String, tint: Color, title: String) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            SectionIcon(symbol: symbol, tint: tint, size: 56)
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView().controlSize(.small)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 3. Bilan

    private func done(_ report: Uninstaller.Report) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if report.remaining.isEmpty {
                SuccessMark()
                Text("FL Shortcuts est désinstallé")
                    .font(.system(size: 18, weight: .bold))
                    .padding(.top, 14)
                Text(flow.demo ? String(localized: "Plus rien ne reste sur ce Mac.")
                     : String(localized: "Plus rien ne reste sur ce Mac. L'app se ferme…"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                SectionIcon(symbol: "exclamationmark.triangle", tint: .orange, size: 68)
                Text("Encore une étape")
                    .font(.system(size: 18, weight: .bold))
                    .padding(.top, 14)
                Text("Glisse FL Shortcuts dans la Corbeille.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            Spacer(minLength: 12)
            if report.remaining.isEmpty {
                Button(action: close) { Text("Quitter").frame(maxWidth: .infinity) }
                    .primaryButton()
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            } else {
                buttons {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting(report.remaining.map(\.url))
                    } label: { Text("Afficher dans le Finder").frame(maxWidth: .infinity) }
                        .secondaryButton()
                } second: {
                    Button(action: close) { Text("Quitter").frame(maxWidth: .infinity) }
                        .primaryButton()
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Coche de réussite à la façon d'Apple : le rond vert apparaît en grandissant (fondu), puis la coche blanche, fine,
/// se trace. Mouvement réduit demandé : tout apparaît d'un coup.
struct SuccessMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    @State private var drawn = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.green)
                .scaleEffect(grown ? 1 : 0.4)
                .opacity(grown ? 1 : 0)
            CheckShape()
                .trim(from: 0, to: drawn ? 1 : 0)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: 30, height: 30)
        }
        .frame(width: 68, height: 68)
        .accessibilityElement()
        .accessibilityLabel("Réussi")
        .onAppear {
            if reduceMotion {
                grown = true
                drawn = true
                return
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) { grown = true }
            withAnimation(.easeOut(duration: 0.32).delay(0.28)) { drawn = true }
        }
    }
}

/// Coche : trait court vers le bas, puis long vers le haut à droite.
struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.minY + rect.height * 0.55))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.minY + rect.height * 0.84))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.94, y: rect.minY + rect.height * 0.18))
        return p
    }
}
