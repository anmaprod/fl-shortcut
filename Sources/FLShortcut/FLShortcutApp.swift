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
    @StateObject private var link: MIDILink
    @StateObject private var fl: FLMonitor

    init() {
        SingleInstance.enforce()                 // avant de créer quoi que ce soit (REL-07)
        _store = StateObject(wrappedValue: Store.shared)
        _status = StateObject(wrappedValue: AppStatus.shared)
        _link = StateObject(wrappedValue: MIDILink.shared)
        _fl = StateObject(wrappedValue: FLMonitor.shared)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(store)
                .environmentObject(status)
                .environmentObject(link)
                .environmentObject(fl)
        } label: {
            Image(systemName: status.menuBarSymbol(enabled: store.enabled))
        }

        Window("FL Shortcut – Raccourcis", id: "editor") {
            EditorView()
                .environmentObject(store)
                .environmentObject(status)
                .environmentObject(link)
                .environmentObject(fl)
                .frame(minWidth: 820, minHeight: 480)
        }
        .windowResizability(.contentMinSize)
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
        MIDILink.shared.start()
        FLMonitor.shared.start()
        AppStatus.shared.start()
        PauseIndicator.shared.bind()

        if !UserDefaults.standard.bool(forKey: "didOnboard") {
            DispatchQueue.main.async { AppDelegate.onboard() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Store.shared.saveNow()
        EventTap.shared.stop()
        MIDILink.shared.stop()
    }

    private static func onboard() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Bienvenue dans FL Shortcut"
        a.informativeText = """
        FL Shortcut vit dans la barre des menus (icône clavier).

        1. Autorise le clavier : Réglages Système › Confidentialité et sécurité › Accessibilité.
        2. Installe le script dans FL Studio pour les « Actions dans FL ».
        3. Personnalise tes raccourcis depuis le menu (profil Recommandé chargé).

        ⌃⌥⌘F met FL Shortcut en pause à tout moment. FL Shortcut ne lit les touches que pour reconnaître
        tes raccourcis : rien n'est enregistré ni transmis.
        """
        a.addButton(withTitle: "Autoriser le clavier et installer le script")
        a.addButton(withTitle: "Autoriser le clavier seulement")
        a.addButton(withTitle: "Plus tard")
        let choice = a.runModal()
        UserDefaults.standard.set(true, forKey: "didOnboard")      // après le choix (REL-23)
        switch choice {
        case .alertFirstButtonReturn:
            FLScriptInstaller.installWithAlert()
            AppStatus.shared.requestAccessibility()
        case .alertSecondButtonReturn:
            AppStatus.shared.requestAccessibility()
        default:
            break
        }
    }
}

/// État global affiché par le menu et l'éditeur ; superviseur du tap.
final class AppStatus: ObservableObject {
    static let shared = AppStatus()

    @Published private(set) var accessibilityOK = false
    @Published private(set) var secureInput = false
    @Published private(set) var tapRunning = false
    @Published private(set) var staleTCC = false
    @Published private(set) var tapUnstable = false
    @Published private(set) var scriptState: ScriptIntegrity.State = .notInstalled
    @Published private(set) var capabilities: CapabilityMask? = nil
    @Published private(set) var flVersion: FLVersion? = nil

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []

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

        FLMonitor.shared.$version
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] v in
                self?.flVersion = v
                Store.shared.recompute()
            }
            .store(in: &cancellables)

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                EventTap.shared.purge()
            })
        }

        refreshScriptState()
        supervise()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.supervise() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Le masque du script fait foi ; avant le handshake, la version lue dans le bundle de FL.
    func availability(_ id: Int) -> ActionAvailability {
        AvailabilityResolver.availability(of: id, caps: capabilities, flVersion: flVersion)
    }

    func refreshScriptState() {
        let s = ScriptIntegrity.check()
        if s != scriptState { scriptState = s }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        supervise()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
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
            running = tap.start()
            stale = !running                        // permission cochée mais refusée : TCC périmé
        } else if !tap.isEnabled {
            running = tap.restart()
        } else {
            running = true
        }
        if running != tapRunning { tapRunning = running }
        if stale != staleTCC { staleTCC = stale }
        refreshScriptState()
    }
}

/// Panneau flottant non activant visible tant que FL Shortcut est en pause (audit 05 §4.4).
final class PauseIndicator {
    static let shared = PauseIndicator()
    private var panel: NSPanel?
    private var cancellable: AnyCancellable?

    private init() {}

    func bind() {
        cancellable = Store.shared.$enabled
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.update(paused: !enabled) }
    }

    private func update(paused: Bool) {
        guard paused else {
            panel?.orderOut(nil)
            return
        }
        let p = panel ?? makePanel()
        panel = p
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = p.frame.size
            p.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 16, y: frame.maxY - size.height - 12))
        }
        p.orderFrontRegardless()
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

struct PauseBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
            Text("FL Shortcut en pause · ⌃⌥⌘F pour reprendre")
                .font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct MenuContent: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var status: AppStatus
    @EnvironmentObject var link: MIDILink
    @EnvironmentObject var fl: FLMonitor
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle(store.enabled ? "Raccourcis actifs (⌃⌥⌘F)" : "En pause – réactiver (⌃⌥⌘F)", isOn: $store.enabled)
        Text("FL Studio : \(link.status.label)\(fl.version.map { " · FL \($0)" } ?? "")")
        if !status.accessibilityOK {
            Button("Autoriser le clavier (Accessibilité)…") { status.openAccessibilitySettings() }
        }
        if status.staleTCC {
            Text("Permission périmée : retire FL Shortcut de la liste Accessibilité puis ajoute-le.")
        }
        if status.secureInput {
            Text("Saisie sécurisée activée par une autre appli (ex. Terminal) : raccourcis muets.")
        }
        if status.tapUnstable {
            Text("macOS a coupé l'interception plusieurs fois : elle a été relancée.")
        }
        if status.scriptState == .modified {
            Text("Le script FL a été modifié depuis l'installation : réinstalle-le.")
        }
        if link.uniqueIDConflict {
            Text("Conflit de port MIDI : une autre copie de FL Shortcut tourne peut-être.")
        }
        if let warning = store.loadWarning { Text(warning) }
        if let error = store.saveError { Text(error) }
        Divider()
        Button("Modifier les raccourcis…") {
            openWindow(id: "editor")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Tester le lien avec FL") { link.testLink() }
        Button("Installer le script dans FL Studio…") { FLScriptInstaller.installWithAlert() }
        Divider()
        Button("Quitter FL Shortcut") { NSApp.terminate(nil) }
    }
}
