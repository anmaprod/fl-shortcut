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
    /// Une demande est en cours (de « Tout autoriser… » jusqu'à la fin) : l'accueil montre « En attente… ».
    @Published private(set) var asking = false
    private var panel: NSPanel?
    /// Réglages Système ouverts par nous pour le clavier : refermés une fois le clavier autorisé.
    private var openedSettings = false
    /// La fenêtre d'accueil est cachée pendant la question du son de macOS.
    private var accueilCache = false
    /// La question du son de macOS est affichée (jusqu'à la réponse) : rien n'est conclu de TCC pendant ce temps.
    private var audioQuestionOpen = false
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
                openedSettings = NSWorkspace.shared.open(url)
            }
        } else if Self.audioMissing {
            askAudio()
        } else {
            return
        }
        asking = true
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
            // Vidéo du 30/10 : la fenêtre d'accueil se retire pendant la question de macOS et ne revient qu'une fois
            // la réponse donnée (au plus tard au bout de 2 minutes, si la question disparaît sans réponse).
            hideWelcome()
            NSApp.activate(ignoringOtherApps: true)         // la fenêtre de macOS devant, pas derrière les réglages
            audioQuestionOpen = true
            let asked = AudioCapturePermission.request { [weak self] ok in
                guard let self else { return }
                self.audioQuestionOpen = false
                MacroLog.shared.write("AUDIO", "question answered: \(ok ? "allowed" : "not allowed"), "
                                      + "TCC \(AudioCapturePermission.status)")
                if ok || Self.audioAllowed { self.audioGranted = true }
                // Vidéo du 31/10 : l'accueil revenait pendant que la question de macOS se refermait (fondu) ; il
                // attend qu'elle ait disparu.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.showWelcome() }
                self.recheckAudioSoon()
            }
            if !asked {
                audioQuestionOpen = false
                showWelcome()
                ScreenLook.openSettings()
            }
        case .denied:
            ScreenLook.openSettings()
        case .granted:
            audioGranted = true
        }
    }

    /// Vidéo du 31/10 (« Autorisé » jamais affiché) : TCC peut ne noter la réponse qu'un instant après la question ;
    /// relu encore quelques fois.
    private func recheckAudioSoon() {
        for delay in [0.5, 1.5, 3, 6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refresh() }
        }
    }

    /// Relit les deux autorisations (accueil affiché : chaque seconde ; app réactivée). Le clavier autorisé est aussi
    /// dit tout de suite à `AppStatus` (l'accueil, la barre des menus et l'interception suivent ensemble).
    func refresh() {
        let trusted = AXIsProcessTrusted()
        if trusted != granted {
            granted = trusted
            AppStatus.shared.recheck()
        }
        if !audioGranted, Self.audioAllowed { audioGranted = true }
    }

    /// Autorisation en cours (« clavier », « son »), notée à la fermeture : une copie relancée avant qu'elle soit
    /// donnée attend qu'elle le soit (`PermissionRelaunchWait`).
    var askingKey: String? {
        guard asking else { return nil }
        return stage == .keyboard ? "clavier" : "son"
    }

    /// Accueil revenu après la relance : le clavier donné entre-temps, la suite (le son de FL) reprend comme dans
    /// l'ancienne copie ; sinon rien (« Tout autoriser… » reste là, l'état est relu chaque seconde).
    func continueAfterRelaunch(asking key: String) {
        refresh()
        guard key == "clavier", granted, Self.audioMissing else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, !self.asking, Self.audioMissing else { return }
            self.start(panel: false)
        }
    }

    private func hideWelcome() {
        guard OnboardingWindow.shared.isOpen else { return }
        accueilCache = true
        OnboardingWindow.shared.stepAside()
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in self?.showWelcome() }
    }

    private func showWelcome() {
        guard accueilCache else { return }
        accueilCache = false
        OnboardingWindow.shared.bringToFront()
    }

    /// Réglages Système ouverts par « Tout autoriser… » : refermés une fois le clavier autorisé (vidéo du 30/10).
    /// macOS ne donne l'autorisation qu'après le code ou Touch ID : cocher la case seule ne suffit pas.
    private func closeSettings() {
        guard openedSettings else { return }
        openedSettings = false
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences") {
            app.terminate()
        }
    }

    private func check() {
        switch stage {
        case .keyboard:
            guard AXIsProcessTrusted() else { return }
            granted = true
            closeSettings()
            AppStatus.shared.recheck()
            // Laisse voir la coche, puis le son (même panneau), ou tout est rangé.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                if Self.audioMissing { withAnimation(Motion.quickMorph) { self.askAudio() } } else { self.close() }
            }
        case .audio:
            // Pendant la question de macOS, TCC ne dit encore rien de sûr : on attend la réponse (vidéo du 31/10 : la
            // vérification s'arrêtait là, et « Son de FL » restait « À autoriser » une fois autorisé).
            guard !audioQuestionOpen else { return }
            if #available(macOS 14.2, *), !showsPanel, AudioCapturePermission.status == .denied, !audioGranted {
                close()                                     // refusé depuis l'accueil : redemandé à l'Organiser
                return
            }
            guard audioGranted || Self.audioAllowed else { return }
            audioGranted = true
            showWelcome()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in self?.close() }
        }
    }

    /// Panneau affiché (noté pour la reprise après « Quitter et rouvrir »).
    var isShowing: Bool { panel != nil }

    func close() {
        asking = false
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
                .fill(Swiss.red)
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

/// Relancée pendant une autorisation (retour du propriétaire, 01/11 : « qu'il attende de se rouvrir que
/// l'autorisation soit faite ») : l'accueil reste caché tant que l'autorisation demandée n'est pas donnée, puis revient
/// avec « Autorisé ». Il revient aussi si les Réglages Système sont fermés (2 s), au bout de 3 minutes, ou si l'app est
/// rouverte à la main. Relu deux fois par seconde, seulement pendant cette attente.
final class PermissionRelaunchWait {
    static let shared = PermissionRelaunchWait()

    private var timer: Timer?
    private var then: (() -> Void)?
    private var started = Date()
    private var settingsGoneSince: Date?

    /// Pur (testé) : l'autorisation demandée avant la relance manque encore.
    static func missing(_ asking: String, keyboardOK: Bool, audioOK: Bool) -> Bool {
        switch asking {
        case "clavier": return !keyboardOK
        case "son": return !audioOK
        default: return false
        }
    }

    /// Pur (testé) : l'attente s'arrête (autorisation donnée, Réglages fermés depuis 2 s, ou 3 minutes passées).
    static func ends(missing: Bool, settingsGoneFor: TimeInterval?, elapsed: TimeInterval) -> Bool {
        !missing || (settingsGoneFor ?? 0) >= 2 || elapsed >= 180
    }

    private static var missingNow: (String) -> Bool = { key in
        missing(key, keyboardOK: AXIsProcessTrusted(), audioOK: AccessibilityGuide.audioAllowed)
    }

    /// `then` aussitôt si l'autorisation est déjà là ; sinon une fois l'attente finie.
    func start(asking key: String, then show: @escaping () -> Void) {
        guard Self.missingNow(key) else { show(); return }
        MacroLog.shared.write("ACCUEIL", "relaunched before \(key) was given: welcome waits")
        then = show
        started = Date()
        settingsGoneSince = nil
        timer?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick(key) }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick(_ key: String) {
        let settingsOpen = !NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.systempreferences").isEmpty
        if settingsOpen { settingsGoneSince = nil } else if settingsGoneSince == nil { settingsGoneSince = Date() }
        let missing = Self.missingNow(key)
        guard Self.ends(missing: missing, settingsGoneFor: settingsGoneSince.map { Date().timeIntervalSince($0) },
                        elapsed: Date().timeIntervalSince(started)) else { return }
        MacroLog.shared.write("ACCUEIL", "welcome back after \(Int(Date().timeIntervalSince(started))) s, "
                              + "\(key) \(missing ? "still missing" : "given")")
        finishNow()
    }

    /// L'accueil revient maintenant (attente finie, ou app rouverte à la main) ; rien si l'app n'attendait pas.
    func finishNow() {
        timer?.invalidate()
        timer = nil
        let show = then
        then = nil
        show?()
    }
}
