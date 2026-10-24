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

/// Contenu du panneau : titre gras aligné à gauche avec l'icône de l'app (typographie de macOS 26), étapes
/// numérotées en pastilles, et un aperçu de la ligne à activer. Panneau standard du système (aucun verre ajouté).
private struct AccessibilityGuideView: View {
    @ObservedObject var guide: AccessibilityGuide

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            progress
            if guide.stage == .audio {
                audioSteps
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
                    Retire-le avec « – », puis ajoute-le avec « + » (dossier Applications).
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
            if #available(macOS 14.2, *) {
                mark(String(localized: "Son de FL"), done: guide.audioGranted, current: guide.stage == .audio)
            }
        }
        .font(.system(size: 11, weight: .medium))
    }

    private func mark(_ title: String, done: Bool, current: Bool) -> some View {
        Label(title, systemImage: done ? "checkmark.circle.fill" : current ? "circle.dotted" : "circle")
            .foregroundStyle(done ? Color.green : current ? Color.primary : Color.secondary)
    }

    @ViewBuilder private var audioSteps: some View {
        if guide.audioGranted {
            Label("Son de FL autorisé : tout est prêt.", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(Color.green)
        } else {
            HStack(spacing: 10) {
                AppIcon().frame(width: 36, height: 36)
                Text("Autorise le son de FL :")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            step(1, String(localized: "Dans la fenêtre de macOS, clique « Autoriser »."))
            step(2, String(localized: """
                Pas de fenêtre ? Dans les réglages qui s'ouvrent, active l'interrupteur à côté de FL Shortcuts, dans \
                la partie audio.
                """))
            Text(String(localized: """
                Sert à l'Organiser : il écoute chaque son de FL pour le ranger. Rien n'est enregistré ni envoyé.
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
