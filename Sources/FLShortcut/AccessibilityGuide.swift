// Autorisations, demandées en une seule fois (demandé par l'utilisateur : plus de demandes éparpillées) : le clavier
// (Accessibilité, indispensable), puis la lecture de la fenêtre de FL (Enregistrement de l'écran, pour retrouver les
// boutons par leur nom ; facultative). On ouvre nous-mêmes Réglages Système sur la bonne liste (et le Finder sur l'app
// pour le clavier), un petit panneau dit quoi faire, et on détecte tout seul quand c'est autorisé. Le son de FL
// (Organiser) n'a pas de réglage à ouvrir : macOS le demande lui-même, une fois, à la première écoute.
// Le panneau ne vérifie qu'une fois par seconde, et seulement tant qu'il est affiché.
import AppKit
import ApplicationServices
import SwiftUI

final class AccessibilityGuide: ObservableObject {
    static let shared = AccessibilityGuide()

    enum Stage { case keyboard, screen }

    @Published private(set) var granted = AXIsProcessTrusted()
    @Published private(set) var screenGranted = ScreenLook.allowed
    @Published private(set) var stage = Stage.keyboard
    private var panel: NSPanel?
    private var timer: Timer?

    static func start() { shared.start() }

    /// Tout ce qui manque, à la suite : le clavier, puis la fenêtre de FL.
    func start() {
        granted = AXIsProcessTrusted()
        screenGranted = ScreenLook.allowed
        if !granted {
            stage = .keyboard
            // Inscrit FL Shortcuts dans la liste (décoché) : il ne reste qu'à l'activer.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
        } else if Self.screenMissing {
            askScreen()
        } else {
            return
        }
        showPanel()
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Lecture de la fenêtre de FL possible sur ce Mac et pas encore autorisée.
    static var screenMissing: Bool { ScreenLook.available && !ScreenLook.allowed }

    /// Inscrit FL Shortcuts dans la liste « Enregistrement de l'écran » (fenêtre de macOS la première fois) et l'ouvre.
    private func askScreen() {
        stage = .screen
        // Première fois : la fenêtre de macOS, avec son bouton « Ouvrir Réglages Système… » (ouvrir les réglages en
        // même temps la cachait derrière eux). Déjà demandée : directement la bonne liste des réglages.
        if !ScreenLook.requestOnce() { ScreenLook.openSettings() }
    }

    private func check() {
        switch stage {
        case .keyboard:
            guard AXIsProcessTrusted() else { return }
            granted = true
            AppStatus.shared.recheck()
            // Laisse voir la coche, puis la fenêtre de FL (même panneau), ou tout est rangé.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                if Self.screenMissing { withAnimation(Motion.quickMorph) { self.askScreen() } } else { self.close() }
            }
        case .screen:
            // macOS ne le dit souvent qu'après « Quitter et rouvrir » : le panneau reste jusque-là, ou « Plus tard ».
            guard ScreenLook.allowed else { return }
            screenGranted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in self?.close() }
        }
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
        p.title = String(localized: "Autoriser FL Shortcuts")
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
            progress
            if guide.stage == .screen {
                screenSteps
            } else if guide.granted {
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
                step(1, String(localized: "Active l'interrupteur à côté de FL Shortcuts."))
                SwitchPreview()
                    .padding(.leading, 28)
                step(2, String(localized: """
                    Il n'est pas dans la liste, ou il est déjà activé mais rien ne marche ? \
                    Retire-le avec « – », puis glisse FL Shortcuts depuis la fenêtre du Finder dans la liste.
                    """))
                HStack(spacing: 6) {
                    Image(systemName: "hourglass").foregroundStyle(.secondary)   // fixe : aucune animation
                    Text("En attente… FL Shortcuts le détecte tout seul.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(18)
        .frame(width: 360, alignment: .leading)
        .animation(Motion.quickMorph, value: guide.stage)
    }

    /// Les deux autorisations demandées ensemble, cochées une à une.
    private var progress: some View {
        HStack(spacing: 14) {
            mark(String(localized: "Clavier"), done: guide.granted, current: guide.stage == .keyboard)
            if ScreenLook.available {
                mark(String(localized: "Fenêtre de FL"), done: guide.screenGranted, current: guide.stage == .screen)
            }
        }
        .font(.system(size: 11, weight: .medium))
    }

    private func mark(_ title: String, done: Bool, current: Bool) -> some View {
        Label(title, systemImage: done ? "checkmark.circle.fill" : current ? "circle.dotted" : "circle")
            .foregroundStyle(done ? Color.green : current ? Color.primary : Color.secondary)
    }

    @ViewBuilder private var screenSteps: some View {
        if guide.screenGranted {
            Label("Fenêtre de FL autorisée : tout est prêt.", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Color.green)
        } else {
            HStack(spacing: 10) {
                AppIcon().frame(width: 36, height: 36)
                Text("Autorise « Enregistrement de l'écran » :")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            step(1, String(localized: """
                Dans la fenêtre de macOS, clique « Ouvrir Réglages Système… » (pas de fenêtre ? « Ouvrir les \
                réglages » ci-dessous).
                """))
            step(2, String(localized: "Active l'interrupteur à côté de FL Shortcuts."))
            SwitchPreview()
                .padding(.leading, 28)
            step(3, String(localized: "macOS propose « Quitter et rouvrir » : accepte, FL Shortcuts revient tout seul."))
            Text(String(localized: """
                Facultatif : sert seulement à retrouver les boutons de FL par leur nom. Seule la fenêtre de FL est lue, \
                au moment du clic, jamais enregistrée.
                """))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Plus tard") { guide.close() }
                Button("Ouvrir les réglages") { ScreenLook.openSettings() }
            }
        }
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
            Text("FL Shortcuts").font(.system(size: 12))
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
        .accessibilityLabel("Exemple : FL Shortcuts, interrupteur activé")
    }
}
