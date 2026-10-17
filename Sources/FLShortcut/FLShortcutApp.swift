// Audit : REL-07 (instance unique, vérifiée avant toute création de tap, de port MIDI ou de profil),
//         REL-08 (surveillance permanente de la permission Accessibilité : tap arrêté / recréé / redémarré,
//         permission périmée signalée), REL-09 (Saisie sécurisée détectée et affichée), SEC-10 (tap coupé trop
//         souvent : recréé et signalé), REL-04 (purge sur veille, réveil, changement de session),
//         REL-21 (profil écrit à la fermeture), REL-23 (accueil marqué « vu » après le choix ; permission
//         demandée depuis l'accueil, pas en même temps), audit 05 §4.4 (état « en pause » visible en permanence :
//         icône dédiée + panneau flottant non activant), audit 04 §8.2 (disponibilité des actions : masque du
//         script, sinon version lue dans le bundle de FL), PROTOCOL.md §5 (statut du lien affiché).
import AppKit
import ApplicationServices
import Carbon
import Combine
import SwiftUI

@main
struct FLShortcutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store: Store
    @StateObject private var status: AppStatus
    // Simples références : leurs publications (lien, présence de FL) ne réévaluent pas toute la scène.
    private let link = MIDILink.shared
    private let fl = FLMonitor.shared

    init() {
        Bench.runIfRequested()                   // `--mesure` : temps de réponse de FL, puis quitte
        MacroDiagnostics.runIfRequested()        // `--diag-macro` : fenêtres et menus de FL vus par l'app, puis quitte
        MacroDiagnostics.runIconIfRequested()    // `--diag-icon 7-4` : pose une icône dans le vrai FL, puis quitte
        PresetSelfTest.runIfRequested()          // `--selftest-preset` : essai du choix automatique du preset, puis quitte
        FakeFL.runIfRequested()                  // `--fake-fl` : FL Studio simulé pour l'essai de bout en bout (CI)
        MacroSelfTest.runIfRequested()           // `--selftest-macro` : la macro complète contre le FL simulé, puis quitte
        Uninstaller.runCheckIfRequested()        // `--essai-desinstallation` (CI) : tout supprimer, vérifier, quitter
        SingleInstance.enforce()                 // avant de créer quoi que ce soit (REL-07)
        _store = StateObject(wrappedValue: Store.shared)
        _status = StateObject(wrappedValue: AppStatus.shared)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(store)
                .environmentObject(status)
                .environmentObject(link)
                .environmentObject(fl)
        } label: {
            MenuBarLabel(symbol: status.menuBarSymbol(enabled: store.enabled))
        }
        .menuBarExtraStyle(.window)

        Window("FL Shortcuts – Raccourcis", id: "editor") {
            EditorView()
                .environmentObject(store)
                .environmentObject(status)
                .environmentObject(link)
                .environmentObject(fl)
                .frame(minWidth: 820, minHeight: 480)
        }
        .windowResizability(.contentMinSize)

        // Pas de scène pour le créateur de macros : il s'affiche dans cette fenêtre (EditorView, comme un dossier dans
        // le Finder), son modèle n'existe que pendant qu'il est affiché.
    }
}

/// Couleur de l'état de l'app (pastille du menu de la barre, état de la fenêtre principale) : grise en pause,
/// orange sans autorisation clavier, puis selon FL (mode léger) ou le lien.
enum AppStatusColor {
    static func color(enabled: Bool, accessibilityOK: Bool, flRunning: Bool, link: LinkStatus) -> Color {
        if !enabled { return .gray }
        if !accessibilityOK { return .orange }
        if AppMode.light { return flRunning ? .green : .gray }
        switch link {
        case .linked: return .green
        case .inactive: return .orange
        case .flClosed: return .gray
        }
    }
}

enum SingleInstance {
    static func enforce() {
        let me = NSRunningApplication.current
        let id = Bundle.main.bundleIdentifier ?? "app.flshortcut.FLShortcut"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != me.processIdentifier && !$0.isTerminated }
        if let first = others.first {
            first.activate(options: [])
            exit(0)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !AppMode.light { MIDILink.shared.start() }  // mode léger : aucun port MIDI, rien dans FL
        FLMonitor.shared.start()
        AppStatus.shared.start()
        PauseIndicator.shared.bind()
        DebugSnapshot.start()
        // Sauvegarde en ligne : seulement avec un compte connecté (session au Trousseau), sinon aucune requête.
        MainActor.assumeIsolated { AccountBackup.shared.start() }

        if !UserDefaults.standard.bool(forKey: "didOnboard") {
            DispatchQueue.main.async { AppDelegate.onboard() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Store.shared.saveNow()
        Store.shared.library.saveNow()
        EventTap.shared.stop()
        MIDILink.shared.stop()
    }

    private static func onboard() {
        OnboardingWindow.shared.show()          // accueil en 2 étapes (marqué « vu » après un choix, REL-23)
    }
}

/// État global affiché par le menu et l'éditeur ; superviseur du tap.
final class AppStatus: ObservableObject {
    static let shared = AppStatus()

    @Published private(set) var accessibilityOK = false {
        didSet { if oldValue, !accessibilityOK { ProblemLog.shared.add("Clavier : autorisation Accessibilité perdue") } }
    }
    @Published private(set) var secureInput = false
    @Published private(set) var tapRunning = false
    @Published private(set) var staleTCC = false {
        didSet { if staleTCC, !oldValue { ProblemLog.shared.add("Clavier : autorisation périmée (FL Shortcuts à retirer puis rajouter dans Accessibilité)") } }
    }
    @Published private(set) var tapUnstable = false {
        didSet { if tapUnstable, !oldValue { ProblemLog.shared.add("Clavier : macOS a coupé l'interception, elle a été relancée") } }
    }
    @Published private(set) var scriptState: ScriptIntegrity.State = .notInstalled
    @Published private(set) var capabilities: CapabilityMask? = nil
    @Published private(set) var flVersion: FLVersion? = nil
    /// Résultat de la dernière macro (« Macro terminée », « Macro arrêtée à l'étape 3 : … »), nil avant la première.
    @Published private(set) var lastMacro: (ok: Bool, text: String)? = nil

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var lastStartAttempt = Date.distantPast

    private init() {}

    func start() {
        Store.shared.availability = { [weak self] id in self?.availability(id) ?? .unverified }

        MIDILink.shared.$snapshot
            .map { $0.hello?.capabilities }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] caps in
                self?.capabilities = caps
                Store.shared.recompute()
            }
            .store(in: &cancellables)

        FLMonitor.shared.$running
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in if !AppMode.light { self?.refreshScriptState() } }
            .store(in: &cancellables)

        FLMonitor.shared.$version
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] v in
                self?.flVersion = v
                Store.shared.recompute()
            }
            .store(in: &cancellables)

        observers.append(NotificationCenter.default.addObserver(forName: .macroFinished, object: nil, queue: .main) { [weak self] note in
            let ok = note.userInfo?["ok"] as? Bool ?? false
            let text = note.userInfo?["text"] as? String ?? ""
            self?.lastMacro = (ok, text)
            // Dire pourquoi, pas seulement un bip (le larsen a déjà sa fenêtre).
            if !ok, !(text.hasPrefix("Macro terminée, mais risque de larsen") && !text.contains(" ; ")) {
                HintPanel.shared.flash(text)
            }
        })

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                EventTap.shared.purge()
            })
        }

        FLScriptInstaller.updateInstalledIfNeeded()     // script déjà installé : nouvelle version, même clé
        if !AppMode.light { refreshScriptState() }
        supervise()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.supervise() }
        t.tolerance = 0.5                            // laisse macOS regrouper les réveils
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Le masque du script fait foi ; avant le handshake, la version lue dans le bundle de FL.
    func availability(_ id: Int) -> ActionAvailability {
        if AppMode.light {
            return AppMode.nativeEquivalent(of: id, layout: Store.shared.layout) != nil
                ? .available
                : .unavailable(reason: "Demande le script MIDI dans FL (désactivé en mode léger)")
        }
        return AvailabilityResolver.availability(of: id, caps: capabilities, flVersion: flVersion)
    }

    func refreshScriptState() {
        let s = ScriptIntegrity.check()
        if s != scriptState { scriptState = s }
    }

    /// Guide : ouvre Accessibilité et le Finder sur l'app, puis détecte l'autorisation tout seul.
    func requestAccessibility() { AccessibilityGuide.start() }

    func openAccessibilitySettings() { AccessibilityGuide.start() }

    /// Revérifie tout de suite (autorisation accordée pendant le guide).
    func recheck() {
        lastStartAttempt = .distantPast
        supervise()
    }

    func menuBarSymbol(enabled: Bool) -> String {
        if !enabled { return "pause.circle.fill" }
        if !accessibilityOK || secureInput || staleTCC { return "exclamationmark.triangle.fill" }
        return "keyboard.fill"
    }

    /// Toutes les 2 s (REL-08, REL-09, SEC-10).
    private func supervise() {
        let trusted = AXIsProcessTrusted()
        let secure = IsSecureEventInputEnabled()
        if secure != secureInput {
            secureInput = secure
            EventTap.shared.purge()                 // les keyUp ont pu être perdus (REL-04 a)
        }
        if trusted != accessibilityOK { accessibilityOK = trusted }

        let tap = EventTap.shared
        var running = false
        var stale = false
        if !trusted {
            if tap.isRunning { tap.stop() }
        } else if tap.consumeRestartRequest() {
            if !tapUnstable { tapUnstable = true }
            running = tap.restart()
            stale = !running
        } else if !tap.isRunning {
            // Permission cochée mais refusée (TCC périmé) : nouvel essai toutes les 10 s, pas toutes les 2 s.
            if Date().timeIntervalSince(lastStartAttempt) >= 10 {
                lastStartAttempt = Date()
                running = tap.start()
                stale = !running
            } else {
                stale = staleTCC
            }
        } else if !tap.isHealthy {
            // Recréation au plus toutes les 10 s : chaque recréation réenregistre le tap auprès du système.
            if Date().timeIntervalSince(lastStartAttempt) >= 10 {
                lastStartAttempt = Date()
                running = tap.restart()
            } else {
                running = tap.isRunning
            }
        } else {
            running = true
        }
        if running != tapRunning { tapRunning = running }
        if stale != staleTCC { staleTCC = stale }
        // Empreinte du script : vérifiée au lancement, quand FL démarre ou s'arrête (c'est là qu'il charge le
        // script) et après une installation ; plus de lecture disque périodique.
    }
}

/// Panneau flottant non activant visible tant que FL Shortcuts est en pause (audit 05 §4.4).
final class PauseIndicator {
    static let shared = PauseIndicator()
    private var panel: NSPanel?
    private var cancellable: AnyCancellable?
    /// Dernier état demandé : décide, à la fin d'un fondu de sortie, s'il faut vraiment cacher le panneau.
    private var wantsVisible = false

    private init() {}

    func bind() {
        cancellable = Store.shared.$enabled
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.update(paused: !enabled) }
    }

    /// Fondu d'entrée / de sortie (instantané si « Réduire les animations » est activé).
    private func update(paused: Bool) {
        let duration = Motion.reduce ? 0 : 0.22
        wantsVisible = paused
        guard paused else {
            guard let p = panel, p.isVisible else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                p.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                // Ne cacher que si on n'a pas été remis en pause pendant le fondu (état local, pas Store :
                // indépendant de l'ordre de publication de @Published).
                guard let self, !self.wantsVisible else { return }
                self.panel?.orderOut(nil)
            })
            return
        }
        let p = panel ?? makePanel()
        panel = p
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = p.frame.size
            p.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 16, y: frame.maxY - size.height - 12))
        }
        if !p.isVisible { p.alphaValue = 0 }
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }
    }

    private func makePanel() -> NSPanel {
        let host = NSHostingView(rootView: PauseBadge())
        let size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = host
        return p
    }
}

/// Petite étiquette opaque en haut à droite de l'écran, en capsule comme les pastilles de macOS 26. Jamais de verre :
/// elle reste affichée au-dessus de FL qui se redessine sans cesse (curseur de lecture, vumètres) ; un verre
/// recalculé à chaque image coûterait pendant tout le temps de la pause. Liseré clair statique en guise de reflet.
struct PauseBadge: View {
    private var shape: Capsule { Capsule() }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.orange)
            Text("FL Shortcuts en pause").font(.system(size: 12, weight: .semibold))
            Text("⌃⌥⌘F").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(shape.fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color(nsColor: .separatorColor)],
                                                   startPoint: .top, endPoint: .bottom),
                                    lineWidth: 0.75))
        .accessibilityElement(children: .combine)
    }
}

/// Panneau de la barre des menus, façon menus de macOS 26 : en-tête avec l'icône de l'app et le statut, puis des
/// lignes de menu avec leur symbole à gauche (WWDC25 310 / 356). Le fond est le matériau du système (verre des
/// menus) : rien n'y est ajouté, jamais de verre sur du verre.
struct MenuContent: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var library = MacroLibraryStore.shared
    @EnvironmentObject var status: AppStatus
    @EnvironmentObject var link: MIDILink
    @EnvironmentObject var fl: FLMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AppIcon().frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("FL Shortcuts").font(.system(size: 13, weight: .semibold))
                    if let line = statusLine {
                        HStack(spacing: 5) {
                            Circle().fill(dotColor).frame(width: 7, height: 7)
                            Text(line).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .font(.system(size: 11))
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .accessibilityElement(children: .combine)

            if let macro = status.lastMacro {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: macro.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(macro.ok ? Color.green : Color.orange)
                    Text(macro.text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                if !macro.ok {
                    // La page Aide, le formulaire prêt avec ce message d'erreur et le journal de la macro.
                    PanelItem(symbol: "exclamationmark.bubble", title: "Signaler ce problème…") {
                        HelpLink.shared.report("Macro : " + macro.text)
                        openWindow(id: "editor")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
            }

            ForEach(alerts, id: \.self) { text in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }

            MenuSeparator()

            if !status.accessibilityOK {
                PanelItem(symbol: "lock.open", title: "Autoriser le clavier…") { AccessibilityGuide.start() }
            }
            PanelItem(symbol: "keyboard", title: "Modifier les raccourcis…") {
                openWindow(id: "editor")
                NSApp.activate(ignoringOtherApps: true)
            }
            PanelItem(symbol: "square.stack.3d.up", title: "Organiser la page ouverte…") { OrganizerWindow.open() }
            PanelItem(symbol: "questionmark.circle", title: "Aide et contact…") {
                HelpLink.shared.show()
                openWindow(id: "editor")
                NSApp.activate(ignoringOtherApps: true)
            }
            PanelItem(symbol: "book", title: "Guide de FL Shortcuts") {
                GuideLink.shared.show()
                openWindow(id: "editor")
                NSApp.activate(ignoringOtherApps: true)
            }
            PanelItem(symbol: store.enabled ? "pause" : "play", title: store.enabled ? "Mettre en pause" : "Reprendre",
                      shortcut: "⌃⌥⌘F") { store.enabled.toggle() }
            if !AppMode.light {
                PanelItem(symbol: "link", title: "Installer le lien avec FL Studio…") { FLScriptInstaller.installWithAlert() }
            }

            MenuSeparator()

            PanelItem(symbol: "trash", title: "Désinstaller FL Shortcuts…") { Uninstaller.confirmAndRun() }
            PanelItem(symbol: "power", title: "Quitter FL Shortcuts", shortcut: "⌘Q", key: "q") { NSApp.terminate(nil) }
        }
        .padding(6)
        .frame(width: 280)
    }

    private var dotColor: Color {
        AppStatusColor.color(enabled: store.enabled, accessibilityOK: status.accessibilityOK, flRunning: fl.running,
                             link: link.status)
    }

    /// Chaîne calculée à part : pas de fermeture imbriquée dans une interpolation de LocalizedStringKey. nil quand
    /// tout va bien : ni « Actif », ni la version de FL (demandé par l'utilisateur), seulement ce qui cloche.
    private var statusLine: String? {
        guard store.enabled else { return "En pause" }
        if !status.accessibilityOK { return "Clavier non autorisé" }
        if AppMode.light { return fl.running ? nil : "FL Studio n'est pas ouvert" }
        switch link.status {
        case .linked: return nil
        case .inactive: return "Lien inactif"
        case .flClosed: return "FL Studio n'est pas ouvert"
        }
    }

    private var alerts: [String] {
        var out: [String] = []
        if status.staleTCC { out.append("Autorisation périmée : retire FL Shortcuts de la liste Accessibilité puis ajoute-le.") }
        if status.secureInput { out.append("Saisie sécurisée active dans une autre app : raccourcis muets.") }
        if status.tapUnstable { out.append("macOS a coupé l'interception plusieurs fois : elle a été relancée.") }
        if !AppMode.light, status.scriptState == .modified { out.append("Le script FL a été modifié : réinstalle le lien.") }
        if !AppMode.light, link.uniqueIDConflict { out.append("Conflit de port MIDI : une autre copie de FL Shortcuts tourne peut-être.") }
        if let warning = store.loadWarning { out.append(warning) }
        if let error = store.saveError { out.append(error) }
        if let problem = library.problem { out.append(problem) }
        return out
    }
}

/// Filet entre deux groupes de lignes, comme dans un menu.
private struct MenuSeparator: View {
    var body: some View {
        Divider().padding(.horizontal, 8).padding(.vertical, 4)
    }
}

/// Ligne du panneau : symbole à gauche (une colonne facile à parcourir), surlignage discret au survol, immédiat
/// (aucune animation). Coins concentriques avec le panneau (rayon du panneau moins sa marge).
private struct PanelItem: View {
    let symbol: String
    let title: String
    var shortcut: String? = nil
    /// Raccourci réellement actif dans le panneau (avec ⌘).
    var key: KeyEquivalent? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title)
                Spacer(minLength: 12)
                if let shortcut {
                    Text(shortcut).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.1) : Color.clear))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(key.map { KeyboardShortcut($0, modifiers: .command) })
        .onHover { hovering = $0 }
    }
}
