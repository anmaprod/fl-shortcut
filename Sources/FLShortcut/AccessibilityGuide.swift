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

/// Contenu du panneau : titre gras aligné à gauche avec l'icône de l'app (typographie de macOS 26), étapes
/// numérotées en pastilles, et un aperçu de la ligne à activer. Panneau standard du système (aucun verre ajouté).
private struct AccessibilityGuideView: View {
    @ObservedObject var guide: AccessibilityGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if guide.granted {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(Color.green)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Clavier autorisé").font(.headline)
                        Text("Tes raccourcis marchent dès que FL Studio est au premier plan.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                HStack(spacing: 10) {
                    AppIcon().frame(width: 36, height: 36)
                    Text("Dans la fenêtre Accessibilité qui vient de s'ouvrir :")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                step(1, "Active l'interrupteur à côté de FL Shortcut.")
                SwitchPreview()
                    .padding(.leading, 28)
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
        .frame(width: 360, alignment: .leading)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            StepBadge(number: n)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Étape \(n) : \(text)")
    }
}

/// Aperçu de la ligne de Réglages Système › Accessibilité, interrupteur activé (dessin, rien de cliquable).
private struct SwitchPreview: View {
    var body: some View {
        HStack(spacing: 8) {
            AppIcon().frame(width: 20, height: 20)
            Text("FL Shortcut").font(.system(size: 12))
            Spacer(minLength: 8)
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 30, height: 17)
                .overlay(Circle().fill(Color.white).padding(2).shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5),
                         alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exemple : FL Shortcut, interrupteur activé")
    }
}
