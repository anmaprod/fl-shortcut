// Guide d'autorisation du clavier : on ouvre nous-mêmes Réglages Système › Accessibilité et une fenêtre du
// Finder sur l'app, un petit panneau dit quoi faire, et on détecte tout seul quand c'est autorisé.
// Le panneau ne vérifie qu'une fois par seconde, et seulement tant qu'il est affiché.
import AppKit
import ApplicationServices
import SwiftUI

final class AccessibilityGuide: ObservableObject {
    static let shared = AccessibilityGuide()

    @Published private(set) var granted = AXIsProcessTrusted()
    private var panel: NSPanel?
    private var timer: Timer?

    static func start() { shared.start() }

    func start() {
        granted = AXIsProcessTrusted()
        guard !granted else { return }
        // Inscrit FL Shortcut dans la liste (décoché) : il ne reste qu'à l'activer.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        showPanel()
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func check() {
        guard AXIsProcessTrusted() else { return }
        granted = true
        timer?.invalidate()
        timer = nil
        AppStatus.shared.recheck()
        // Laisse voir la coche une seconde, puis range tout.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in self?.close() }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func showPanel() {
        if let panel { panel.orderFrontRegardless(); return }
        let host = NSHostingView(rootView: AccessibilityGuideView(guide: self))
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                        styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
                        backing: .buffered, defer: false)
        p.title = "Autoriser le clavier"
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.contentView = host
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.maxX - p.frame.width - 24, y: f.minY + 24))
        }
        p.orderFrontRegardless()
        panel = p
    }
}

private struct AccessibilityGuideView: View {
    @ObservedObject var guide: AccessibilityGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if guide.granted {
                Label("Clavier autorisé", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Text("Tes raccourcis marchent dès que FL Studio est au premier plan.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Dans la fenêtre Accessibilité qui vient de s'ouvrir :")
                    .font(.headline)
                step(1, "Active l'interrupteur à côté de FL Shortcut.")
                step(2, "Il n'est pas dans la liste, ou il est déjà activé mais rien ne marche ? "
                     + "Retire-le avec « – », puis glisse FL Shortcut depuis la fenêtre du Finder dans la liste.")
                HStack(spacing: 6) {
                    Image(systemName: "hourglass").foregroundStyle(.secondary)   // fixe : aucune animation
                    Text("En attente… FL Shortcut le détecte tout seul.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(18)
        .frame(width: 340, alignment: .leading)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.callout.monospacedDigit().weight(.semibold)).foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
