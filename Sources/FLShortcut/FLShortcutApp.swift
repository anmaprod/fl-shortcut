import SwiftUI
import AppKit
import ApplicationServices

@main
struct FLShortcutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store.shared
    @StateObject private var status = AppStatus.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(store)
                .environmentObject(status)
        } label: {
            Image(systemName: store.enabled ? "keyboard.fill" : "keyboard")
        }

        Window("FL Shortcut – Raccourcis", id: "editor") {
            EditorView()
                .environmentObject(store)
                .environmentObject(status)
                .frame(minWidth: 680, minHeight: 440)
        }
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = MIDIOut.shared
        AppStatus.shared.checkPermissionsAndStart()

        if !UserDefaults.standard.bool(forKey: "didOnboard") {
            UserDefaults.standard.set(true, forKey: "didOnboard")
            NSApp.activate(ignoringOtherApps: true)
            let a = NSAlert()
            a.messageText = "Bienvenue dans FL Shortcut 🎹"
            a.informativeText = """
            FL Shortcut vit dans la barre des menus (icône clavier en haut à droite).

            Pour démarrer :
            1. Autorise FL Shortcut dans Réglages Système › Confidentialité et sécurité › Accessibilité.
            2. Installe le script dans FL Studio (bouton ci-dessous).
            3. Personnalise tes raccourcis depuis le menu.

            ⌃⌥⌘F active ou désactive les raccourcis à tout moment.
            """
            a.addButton(withTitle: "Installer le script FL Studio")
            a.addButton(withTitle: "Plus tard")
            if a.runModal() == .alertFirstButtonReturn {
                FLScriptInstaller.installWithAlert()
            }
        }
    }
}

/// Suit l'autorisation d'accessibilité et démarre l'interception dès qu'elle est accordée.
final class AppStatus: ObservableObject {
    static let shared = AppStatus()
    @Published var accessibilityOK = false
    @Published var tapRunning = false
    private var timer: Timer?

    func checkPermissionsAndStart() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        accessibilityOK = AXIsProcessTrustedWithOptions(options)
        if accessibilityOK {
            tapRunning = EventTap.shared.start()
            return
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard let self, AXIsProcessTrusted() else { return }
            t.invalidate()
            self.accessibilityOK = true
            self.tapRunning = EventTap.shared.start()
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

struct MenuContent: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var status: AppStatus
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("Raccourcis actifs (⌃⌥⌘F)", isOn: $store.enabled)
        if !status.accessibilityOK {
            Button("⚠️ Autoriser l'accessibilité…") { status.openAccessibilitySettings() }
        }
        Divider()
        Button("Modifier les raccourcis…") {
            openWindow(id: "editor")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Installer le script dans FL Studio…") { FLScriptInstaller.installWithAlert() }
        Divider()
        Button("Quitter FL Shortcut") { NSApp.terminate(nil) }
    }
}
