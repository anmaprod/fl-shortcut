// Désinstallation en 3 étapes, à la façon d'Apple :
// 1. « Désinstaller FL Shortcuts ? » ; si les raccourcis et les macros ne sont sauvegardés nulle part (pas connecté
//    au compte, ou derniers changements pas encore en ligne), une ligne le dit, avec de quoi les sauvegarder d'abord ;
// 2. Touch ID ou le mot de passe du Mac, une seule fois, avant toute suppression (l'app installée par le .pkg
//    appartient au système ; sinon, simple confirmation de l'identité). Refusé : rien n'est supprimé ;
// 3. le bilan vérifié (Uninstaller.removeEverything) : coche verte qui apparaît en grandissant, « Quitter » en bas à
//    droite ; s'il reste quelque chose, « Glisse FL Shortcuts dans la Corbeille » et « Afficher dans le Finder ».
// Couleurs et mise en page des alertes de macOS ; textes courts (les gens lisent ce qui est court).
import AppKit
import LocalAuthentication
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

    /// Étape 2, puis 3.
    func start() {
        guard !demo else { return }
        cancelled = nil
        step = .authenticating
        let work = Uninstaller.privilegedWork()
        if !work.isEmpty {
            // La fenêtre de macOS (Touch ID ou mot de passe) s'affiche ; l'étape « Confirme… » est dessinée avant.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                switch Uninstaller.runPrivileged(work) {
                case .cancelled: self.back("Rien n'a été supprimé.")
                case .done, .failed: self.finish()   // ce qui a résisté est dans le bilan
                }
            }
            return
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            finish()                                // Mac sans mot de passe : rien à demander
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "désinstaller l'app et tout ce qu'elle a créé sur ce Mac") { ok, _ in
            DispatchQueue.main.async {
                if ok { self.finish() } else { self.back("Rien n'a été supprimé.") }
            }
        }
    }

    private func back(_ why: String) {
        cancelled = why
        step = .confirm
    }

    private func finish() {
        step = .working
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let report = Uninstaller.removeEverything(interactive: true, removeExports: self.removeExports)
            self.step = .done(report)
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

    /// Mode capture : un écran d'exemple ; « fermer » ferme la fenêtre (sans quitter).
    func showDemo(_ screen: String) {
        if screen == "fermer" {
            window?.close()
            return
        }
        show(demo: screen)
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
        w.title = "Désinstaller FL Shortcuts"
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

/// Mise en page des alertes de macOS : icône, titre en gras, une phrase, boutons en bas ; couleurs du système
/// (bouton principal à la couleur d'accent, triangle d'avertissement jaune, coche verte). Textes courts : une idée
/// par ligne.
struct UninstallView: View {
    @ObservedObject var flow: UninstallFlow
    let close: () -> Void

    var body: some View {
        Group {
            switch flow.step {
            case .confirm: confirm
            case .authenticating: waiting(symbol: "touchid", title: "Confirme avec Touch ID ou ton mot de passe")
            case .working: waiting(symbol: "trash", title: "Suppression…")
            case .done(let report): done(report)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 18)
        .frame(width: 340)
    }

    // MARK: 1. Confirmation

    private var confirm: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            Text("Désinstaller FL Shortcuts ?")
                .font(.system(size: 13, weight: .bold))
            Text("L'app et tous ses réglages seront supprimés de ce Mac.")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            risk
            if flow.hasExports {
                Toggle("Supprimer aussi mes fichiers exportés", isOn: $flow.removeExports)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
            }
            if let cancelled = flow.cancelled {
                Text(cancelled).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button(action: close) { Text("Annuler").frame(maxWidth: .infinity) }
                    .keyboardShortcut(.cancelAction)
                Button { flow.start() } label: { Text("Désinstaller").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var risk: some View {
        switch flow.risk {
        case .nothing:
            EmptyView()
        case .saved:
            Text("Tes raccourcis et tes macros restent dans ton compte.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .notSignedIn:
            warning("Tes raccourcis et tes macros ne sont pas sauvegardés : ils seront perdus.",
                    link: "Les sauvegarder d'abord")
        case .notSaved:
            warning("Tes derniers changements ne sont pas encore sauvegardés.", link: "Ouvrir Mon compte")
        }
    }

    private func warning(_ text: String, link: String) -> some View {
        VStack(spacing: 4) {
            Label {
                Text(text).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
            .font(.system(size: 11, weight: .medium))
            .multilineTextAlignment(.leading)
            Button(link) {
                close()
                AccountLink.shared.show()
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
        }
        .padding(.top, 2)
    }

    // MARK: 2. Touch ID, suppression

    private func waiting(symbol: String, title: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.system(size: 13, weight: .bold)).multilineTextAlignment(.center)
            ProgressView().controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: 3. Bilan

    private func done(_ report: Uninstaller.Report) -> some View {
        VStack(spacing: 10) {
            if report.remaining.isEmpty {
                SuccessMark()
                Text("FL Shortcuts est désinstallé")
                    .font(.system(size: 13, weight: .bold))
                Text("Plus rien ne reste sur ce Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                Text("Encore une étape")
                    .font(.system(size: 13, weight: .bold))
                Text("Glisse FL Shortcuts dans la Corbeille.")
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if !report.remaining.isEmpty {
                    Button("Afficher dans le Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(report.remaining.map(\.url))
                    }
                }
                Button("Quitter", action: close)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, 10)
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
