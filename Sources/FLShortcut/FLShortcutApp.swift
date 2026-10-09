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
        Bench.runIfRequested()                   // `--mesure` : temps de réponse de FL, puis quitte
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
        .menuBarExtraStyle(.window)

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
        OnboardingWindow.shared.show()          // accueil en 2 étapes (marqué « vu » après un choix, REL-23)
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
    private var ticks = 0
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
        t.tolerance = 0.5                            // laisse macOS regrouper les réveils
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
        lastStartAttempt = .distantPast
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
            // Permission cochée mais refusée (TCC périmé) : nouvel essai toutes les 10 s, pas toutes les 2 s.
            if Date().timeIntervalSince(lastStartAttempt) >= 10 {
                lastStartAttempt = Date()
                running = tap.start()
                stale = !running
            } else {
                stale = staleTCC
            }
        } else if !tap.isHealthy {
            running = tap.restart()
        } else {
            running = true
        }
        if running != tapRunning { tapRunning = running }
        if stale != staleTCC { staleTCC = stale }
        // Empreinte du script : toutes les 10 s suffisent (lecture disque évitée le reste du temps).
        ticks &+= 1
        if ticks % 5 == 1 { refreshScriptState() }
    }
}

/// Panneau flottant non activant visible tant que FL Shortcut est en pause (audit 05 §4.4).
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

struct PauseBadge: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
            Text("FL Shortcut en pause · ⌃⌥⌘F pour reprendre")
                .font(.callout.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassCapsule()
        .padding(6)                                   // marge pour l'ombre du verre
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AppIcon().frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("FL Shortcut").font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 6) {
                        Circle().fill(dotColor).frame(width: 6, height: 6)
                        Text(statusLine).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                            .contentTransition(.interpolate)
                    }
                    .motion(Motion.smooth, value: statusLine)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $store.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel("Raccourcis actifs (⌃⌥⌘F)")
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 12)

            ForEach(alerts, id: \.self) { text in
                Label(text, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .transition(Motion.transition(.opacity.combined(with: .move(edge: .top))))
            }
            if !status.accessibilityOK {
                PanelItem(title: "Autoriser le clavier…", shortcut: nil) { status.openAccessibilitySettings() }
            }

            Divider().padding(.horizontal, 8).padding(.bottom, 6)

            PanelItem(title: "Modifier les raccourcis…", shortcut: "⌘,") {
                openWindow(id: "editor")
                NSApp.activate(ignoringOtherApps: true)
            }
            PanelItem(title: store.enabled ? "Mettre en pause" : "Reprendre", shortcut: "⌃⌥⌘F") { store.enabled.toggle() }
            PanelItem(title: "Installer le lien avec FL Studio…", shortcut: nil) { FLScriptInstaller.installWithAlert() }

            Divider().padding(.horizontal, 8).padding(.vertical, 6)

            PanelItem(title: "Quitter FL Shortcut", shortcut: "⌘Q") { NSApp.terminate(nil) }
        }
        .padding(8)
        .frame(width: 300)
        .motion(Motion.smooth, value: alerts)
        .motion(Motion.smooth, value: status.accessibilityOK)
    }

    private var dotColor: Color {
        guard store.enabled else { return .gray }
        switch link.status {
        case .linked: return .green
        case .inactive: return .orange
        case .flClosed: return .gray
        }
    }

    /// Chaîne calculée à part : pas de fermeture imbriquée dans une interpolation de LocalizedStringKey.
    private var statusLine: String {
        guard store.enabled else { return "En pause" }
        let version = fl.version.map { " \($0)" } ?? ""
        switch link.status {
        case .linked: return "Relié à FL Studio" + version
        case .inactive: return "Lien inactif"
        case .flClosed: return "FL Studio fermé"
        }
    }

    private var alerts: [String] {
        var out: [String] = []
        if status.staleTCC { out.append("Permission périmée : retire FL Shortcut de la liste Accessibilité puis ajoute-le.") }
        if status.secureInput { out.append("Saisie sécurisée activée par une autre appli : raccourcis muets.") }
        if status.tapUnstable { out.append("macOS a coupé l'interception plusieurs fois : elle a été relancée.") }
        if status.scriptState == .modified { out.append("Le script FL a été modifié : réinstalle le lien.") }
        if link.uniqueIDConflict { out.append("Conflit de port MIDI : une autre copie de FL Shortcut tourne peut-être.") }
        if let warning = store.loadWarning { out.append(warning) }
        if let error = store.saveError { out.append(error) }
        return out
    }
}

/// Ligne du panneau : surbrillance au survol, comme un menu macOS.
private struct PanelItem: View {
    let title: String
    let shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                if let shortcut {
                    Text(shortcut).font(.system(size: 12)).foregroundStyle(hovering ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .foregroundStyle(hovering ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Color.accentColor : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableRowStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.08), value: hovering)   // surbrillance quasi immédiate, comme un vrai menu
    }
}
