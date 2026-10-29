// Autorisations, demandées en une seule fois (demandé par l'utilisateur : plus de demandes éparpillées) : le clavier
// (Accessibilité, indispensable), puis le son de FL (Audio du système, pour l'Organiser). Seule la page de réglages
// utile s'ouvre (retour du propriétaire, 24/10 : ni fenêtre du Finder, ni demande « Enregistrement de l'écran », qui
// n'est faite que dans le créateur de macros, au moment où un bloc en a besoin). On détecte tout seul quand c'est
// autorisé ; depuis l'accueil, qui explique déjà tout, sans le petit panneau.
// Le panneau ne vérifie qu'une fois par seconde, et seulement tant qu'il est affiché (ou que l'accueil attend).
import AppKit
import ApplicationServices
import SwiftUI

final class AccessibilityGuide: ObservableObject {
    static let shared = AccessibilityGuide()

    enum Stage { case keyboard, audio }

    @Published private(set) var granted = AXIsProcessTrusted()
    @Published private(set) var audioGranted = AccessibilityGuide.audioAllowed
    @Published private(set) var stage = Stage.keyboard
    private var panel: NSPanel?
    private var timer: Timer?
    /// Montrer le petit panneau (faux depuis l'accueil, qui explique déjà quoi faire).
    private var showsPanel = true

    /// `panel` : faux depuis l'accueil (seule la page de réglages s'ouvre).
    static func start(panel: Bool = true) { shared.start(panel: panel) }

    /// Tout ce qui manque, à la suite : le clavier, puis le son de FL.
    func start(panel: Bool = true) {
        showsPanel = panel
        granted = AXIsProcessTrusted()
        audioGranted = Self.audioAllowed
        if !granted {
            stage = .keyboard
            // Inscrit FL Shortcuts dans la liste (décoché) : il ne reste qu'à l'activer.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            SingleInstance.watchForRelaunch()           // « Quitter et rouvrir » : l'app revient
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } else if Self.audioMissing {
            askAudio()
        } else {
            return
        }
        if panel { showPanel() }
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Son de FL autorisé (Audio du système) ; vrai là où l'Organiser ne peut pas écouter (macOS avant 14.2).
    static var audioAllowed: Bool {
        guard #available(macOS 14.2, *) else { return true }
        return AudioCapturePermission.status == .granted
    }

    /// Son de FL demandable sur ce Mac et pas encore autorisé.
    static var audioMissing: Bool { !audioAllowed }

    /// La fenêtre de macOS pour le son, la première fois ; déjà refusé : la page de réglages où l'activer.
    private func askAudio() {
        stage = .audio
        guard #available(macOS 14.2, *) else { return }
        switch AudioCapturePermission.status {
        case .unknown:
            NSApp.activate(ignoringOtherApps: true)         // la fenêtre de macOS devant, pas derrière les réglages
            if !AudioCapturePermission.request({ [weak self] ok in if ok { self?.audioGranted = true } }) {
                ScreenLook.openSettings()
            }
        case .denied:
            ScreenLook.openSettings()
        case .granted:
            audioGranted = true
        }
    }

    private func check() {
        switch stage {
        case .keyboard:
            guard AXIsProcessTrusted() else { return }
            granted = true
            AppStatus.shared.recheck()
            // Laisse voir la coche, puis le son (même panneau), ou tout est rangé.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                if Self.audioMissing { withAnimation(Motion.quickMorph) { self.askAudio() } } else { self.close() }
            }
        case .audio:
            if #available(macOS 14.2, *), !showsPanel, AudioCapturePermission.status == .denied {
                close()                                     // refusé depuis l'accueil : redemandé à l'Organiser
                return
            }
            guard Self.audioAllowed else { return }
            audioGranted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in self?.close() }
        }
    }

    /// Panneau affiché (noté pour la reprise après « Quitter et rouvrir »).
    var isShowing: Bool { panel != nil }

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

/// Contenu du panneau (maquette validée le 28/10) : un titre court, puis une carte en verre avec le clavier et le son
/// de FL, chacun coché une fois autorisé ; tant que le clavier attend, l'interrupteur à activer en exemple.
private struct AccessibilityGuideView: View {
    @ObservedObject var guide: AccessibilityGuide

    private var title: String {
        switch guide.stage {
        case .keyboard:
            return guide.granted ? String(localized: "Clavier autorisé") : String(localized: "Active FL Shortcuts")
        case .audio:
            return guide.audioGranted ? String(localized: "Tout est prêt") : String(localized: "Autorise le son de FL")
        }
    }

    private var marks: [Mark] {
        var list = [Mark(id: "clavier", title: String(localized: "Clavier"), done: guide.granted,
                         current: guide.stage == .keyboard)]
        if #available(macOS 14.2, *) {
            list.append(Mark(id: "son", title: String(localized: "Son de FL"), done: guide.audioGranted,
                             current: guide.stage == .audio))
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .contentTransition(.opacity)
            PlateRows(data: marks) { mark in
                HStack(spacing: 10) {
                    Group {
                        if mark.done {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.green)
                        } else if mark.current {
                            WaitingRing(size: 16)
                        } else {
                            Image(systemName: "circle").foregroundStyle(.tertiary)
                        }
                    }
                    .font(.system(size: 16))
                    .frame(width: 18)
                    Text(mark.title)
                        .foregroundStyle(mark.done || mark.current ? Color.primary : Color.secondary)
                    Spacer(minLength: 8)
                    if mark.current && !mark.done {
                        Text("En attente…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .frame(height: 40)
                .accessibilityElement(children: .combine)
            }
            if guide.stage == .keyboard && !guide.granted {
                SwitchPreview()
            }
            if guide.stage == .audio && !guide.audioGranted {
                HStack {
                    Spacer()
                    Button("Plus tard") { guide.close() }
                        .secondaryButton()
                    Button("Ouvrir les réglages") { ScreenLook.openSettings() }
                        .primaryButton()
                }
            }
        }
        .padding(18)
        .frame(width: 300, alignment: .leading)
        .animation(Motion.quickMorph, value: guide.stage)
    }

    private struct Mark: Identifiable {
        let id: String
        let title: String
        let done: Bool
        let current: Bool
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
