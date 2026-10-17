// Désinstallation en 3 étapes, à la façon d'Apple :
// 1. « Tu veux vraiment désinstaller FL Shortcuts ? » ; si les raccourcis et les macros ne sont sauvegardés nulle part
//    (pas connecté au compte, ou derniers changements pas encore en ligne), un avertissement le dit, avec de quoi les
//    sauvegarder d'abord ;
// 2. Touch ID ou le mot de passe du Mac, une seule fois, avant toute suppression (l'app installée par le .pkg
//    appartient au système ; sinon, simple confirmation de l'identité). Refusé : rien n'est supprimé ;
// 3. le bilan vérifié (Uninstaller.removeEverything) : coche verte qui apparaît en grandissant, « Quitter » en bleu ;
//    s'il reste quelque chose, ce qui reste et « Afficher dans le Finder ».
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
        /// Pas connecté : tout serait perdu (« 12 raccourcis · 3 macros »).
        case notSignedIn(String)
        /// Connecté, mais les derniers changements ne sont pas en ligne.
        case notSaved(String)
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
        guard backup.community.session != nil else { return .notSignedIn(backup.hereSummary) }
        if case .upToDate = backup.status, !backup.hasUnsavedChanges { return .saved }
        return .notSaved(backup.hereSummary)
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
                case .cancelled: self.back("Désinstallation annulée : rien n'a été supprimé.")
                case .done, .failed: self.finish(privilegedDone: true)   // ce qui a résisté est dans le bilan
                }
            }
            return
        }
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            finish(privilegedDone: true)                                // Mac sans mot de passe : rien à demander
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "désinstaller l'app et tout ce qu'elle a créé sur ce Mac") { ok, _ in
            DispatchQueue.main.async {
                if ok { self.finish(privilegedDone: true) } else { self.back("Désinstallation annulée : rien n'a été supprimé.") }
            }
        }
    }

    private func back(_ why: String) {
        cancelled = why
        step = .confirm
    }

    private func finish(privilegedDone: Bool) {
        step = .working
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let report = Uninstaller.removeEverything(interactive: true, removeExports: self.removeExports,
                                                      privilegedDone: privilegedDone)
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
        let home = FileManager.default.homeDirectoryForCurrentUser
        let hasExports = Uninstaller.exportFolders(home: home).contains { url in
            ((try? FileManager.default.contentsOfDirectory(atPath: url.appendingPathComponent("Macros").path)) ?? [])
                .contains { !$0.hasPrefix(".") }
        }
        let risk: UninstallFlow.Risk = demo == "compte" ? .saved
            : demo != nil ? .notSignedIn("12 raccourcis · 3 macros") : UninstallFlow.currentRisk()
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

struct UninstallView: View {
    @ObservedObject var flow: UninstallFlow
    let close: () -> Void

    var body: some View {
        Group {
            switch flow.step {
            case .confirm: confirm
            case .authenticating: waiting(symbol: "touchid", title: "Confirme avec Touch ID ou ton mot de passe",
                                          text: "macOS te le demande une seule fois, pour tout supprimer.")
            case .working: waiting(symbol: "trash", title: "Suppression en cours…", text: "Ça ne prend qu'un instant.")
            case .done(let report): done(report)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 34)
        .padding(.bottom, 20)
        .frame(width: 460)
    }

    // MARK: 1. Confirmation

    private var confirm: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tu veux vraiment désinstaller FL Shortcuts ?")
                        .font(.system(size: 15, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("L'app, ses réglages, ses autorisations et le lien avec FL Studio seront supprimés de ce Mac. "
                         + "FL Studio garde ses raccourcis d'origine.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            riskBox
            if flow.hasExports {
                Toggle("Supprimer aussi mes macros exportées (Documents › FL Shortcuts)", isOn: $flow.removeExports)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }
            if let cancelled = flow.cancelled {
                Label(cancelled, systemImage: "info.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Label("Touch ID ou ton mot de passe te sera demandé.", systemImage: "touchid")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Annuler", action: close)
                    .keyboardShortcut(.cancelAction)
                Button("Désinstaller") { flow.start() }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var riskBox: some View {
        switch flow.risk {
        case .nothing:
            EmptyView()
        case .saved:
            box(symbol: "checkmark.icloud.fill", color: .green,
                text: "Tes raccourcis et tes macros sont sauvegardés dans ton compte : tu les retrouveras en te reconnectant.")
        case .notSignedIn(let summary):
            box(symbol: "exclamationmark.triangle.fill", color: .red,
                text: "Tes raccourcis et tes macros (\(summary)) ne sont sauvegardés nulle part : tu n'es pas connecté "
                    + "à ton compte. Si tu désinstalles maintenant, tu les perdras pour toujours.",
                button: "Me connecter pour les sauvegarder d'abord")
        case .notSaved(let summary):
            box(symbol: "exclamationmark.icloud.fill", color: .orange,
                text: "Tes derniers changements (\(summary)) ne sont pas encore en ligne : si tu désinstalles "
                    + "maintenant, ils seront perdus.",
                button: "Ouvrir Mon compte")
        }
    }

    private func box(symbol: String, color: Color, text: String, button: String? = nil) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                if let button {
                    Button(button) {
                        close()
                        AccountLink.shared.show()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 12, weight: .medium))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color.opacity(0.3)))
    }

    // MARK: 2. Touch ID, suppression

    private func waiting(symbol: String, title: String, text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.center)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            ProgressView().controlSize(.small).padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    // MARK: 3. Bilan

    private func done(_ report: Uninstaller.Report) -> some View {
        VStack(spacing: 14) {
            if report.remaining.isEmpty {
                SuccessMark()
                Text("FL Shortcuts est désinstallé")
                    .font(.system(size: 17, weight: .semibold))
                Text("Plus rien ne reste sur ce Mac. Merci de l'avoir utilisé !")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Il reste une dernière étape")
                    .font(.system(size: 17, weight: .semibold))
                Text("macOS n'a pas laissé supprimer : "
                     + report.remaining.map { $0.url.lastPathComponent }.joined(separator: ", ")
                     + ". Glisse-le dans la Corbeille : le Finder te demandera ton mot de passe si besoin.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                if !report.remaining.isEmpty {
                    Button("Afficher dans le Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting(report.remaining.map(\.url))
                    }
                }
                Button("Quitter", action: close)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
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
                .fill(Color.green.gradient)
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
