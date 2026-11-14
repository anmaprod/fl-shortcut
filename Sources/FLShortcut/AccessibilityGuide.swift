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
    /// Le son de FL se donne dans les Réglages (« Enregistrement de l'écran et audio du système ») : on attend qu'il
    /// soit coché, tant que les Réglages sont ouverts, au lieu de conclure « refusé » à la première seconde.
    @Published private(set) var audioInSettings = false
    private var settingsGoneSince: Date?
    /// Réglages déjà vus ouverts pour le son (la fenêtre de macOS y mène quand on clique son bouton), et depuis quand
    /// on attend : sans Réglages ouverts en 2 minutes, on arrête d'attendre.
    private var settingsSeen = false
    private var settingsAskedAt: Date?
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
        AppResume.shared.noteAsking(askingKey)              // retrouvée même si macOS ferme l'app de force
        if panel { showPanel() }
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Son de FL autorisé (Audio du système) ; vrai là où l'Organiser ne peut pas écouter (macOS avant 14.2).
    /// Retour du 02/11 (« le bouton Son de FL ne se met pas en Autorisé quand j'appuie sur Autoriser ») : TCC répondait
    /// encore « pas demandé » après « Autoriser », ou la case cochée était celle du haut de la page (« Enregistrement de
    /// l'écran et de l'audio du système »). Compte aussi : « Autoriser » choisi à la question de macOS (retenu), et la
    /// case du haut (l'écran et l'audio du système).
    /// Son de FL : « Enregistrement de l'écran et audio du système » (la liste du haut des Réglages, 03/11).
    static var audioAllowed: Bool {
        guard #available(macOS 14.2, *) else { return true }
        return AudioCapturePermission.screenAndAudioStatus == .granted
    }

    /// Son de FL demandable sur ce Mac et pas encore autorisé.
    static var audioMissing: Bool { !audioAllowed }

    /// Son de FL (03/11 : « tu as mis Enregistrement audio du système uniquement, alors qu'il faut l'écran et l'audio
    /// du système ») : la liste du haut, « Enregistrement de l'écran et audio du système ». macOS ne la donne que dans
    /// les Réglages : sa fenêtre (la première fois) y mène par son bouton, sinon les Réglages s'ouvrent ; FL Shortcuts
    /// s'y coche, puis « Quitter et rouvrir » (l'app relancée attend cachée, `PermissionRelaunchWait`).
    private func askAudio() {
        stage = .audio
        AppResume.shared.noteAsking("son")
        guard #available(macOS 14.2, *) else { return }
        if Self.audioAllowed {
            audioGranted = true
            return
        }
        // 12/11 (« la petite page qui demande d'ouvrir… s'ouvre en même temps… on peut juste ouvrir cette page-là, elle
        // se met devant FL Shortcuts ») : déjà dans la liste (TCC répond « refusé » : présent, décoché), rien n'est
        // demandé à macOS (sur macOS 27, sa demande montrait sa petite fenêtre ET les Réglages) : la page seule, devant.
        // Pas encore dans la liste (tout premier lancement sur ce Mac) : seule la demande de macOS l'y ajoute.
        if AudioCapturePermission.screenAndAudioStatus == .denied {
            MacroLog.shared.write("AUDIO", "already listed: settings only " + AudioCapturePermission.rawSummary)
            SingleInstance.watchForRelaunch()               // « Quitter et rouvrir » : l'app revient
            openAudioSettings()
            return
        }
        NSApp.activate(ignoringOtherApps: true)             // la fenêtre de macOS devant
        let window = ScreenLook.requestOnce()
        MacroLog.shared.write("AUDIO", "screen+audio asked (\(window ? "macOS window" : "settings")) "
                              + AudioCapturePermission.rawSummary)
        if window {
            audioInSettings = true                          // sa fenêtre mène aux Réglages : on attend
            settingsGoneSince = nil
            settingsSeen = false
            settingsAskedAt = Date()
            SingleInstance.watchForRelaunch()               // « Quitter et rouvrir » : l'app revient
        } else {
            openAudioSettings()
        }
    }

    /// La page « Enregistrement de l'écran et audio du système » des Réglages, où FL Shortcuts se coche dans la liste
    /// du haut ; l'accueil (dit sur sa ligne) attend qu'il le soit, tant que les Réglages restent ouverts. Relancée
    /// par « Quitter et rouvrir », l'app attend cachée (`PermissionRelaunchWait`, autorisation notée).
    private func openAudioSettings() {
        audioInSettings = true
        settingsGoneSince = nil
        settingsSeen = false
        settingsAskedAt = Date()
        AppResume.shared.noteAsking("son")
        MacroLog.shared.write("AUDIO", "settings opened")
        ScreenLook.openSettings()
        // Devant FL Shortcuts (12/11) : la page s'ouvre parfois derrière l'accueil.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences") {
                app.activate(options: [])
            }
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
        if !audioGranted, Self.audioAllowed {
            audioGranted = true
            MacroLog.shared.write("AUDIO", "given (seen) " + AudioCapturePermission.rawSummary)
        }
    }

    /// « À autoriser » du son de FL cliqué sur l'accueil : seulement le son (le clavier peut attendre).
    func startAudio() {
        showsPanel = false
        audioGranted = Self.audioAllowed
        guard !audioGranted else { return }
        askAudio()
        asking = true
        AppResume.shared.noteAsking("son")
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
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
            if audioGranted || Self.audioAllowed {
                audioGranted = true
                MacroLog.shared.write("AUDIO", "given\(audioInSettings ? " in settings" : "")")
                // Réglages ouverts pour ça : refermés, comme pour le clavier (12/11, « ça ferme pas la page de
                // réglage, ce qui est pas très intuitif »).
                if audioInSettings { PermissionRelaunchWait.closeSystemSettings(why: "son") }
                audioInSettings = false
                timer?.invalidate()                         // la coche se voit, puis tout est rangé
                timer = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in self?.close() }
                return
            }
            if audioInSettings {
                // Dans les Réglages : on attend qu'il soit coché ; Réglages fermés depuis 3 s (après les avoir vus
                // ouverts), ou jamais ouverts en 2 minutes (fenêtre de macOS refusée), on arrête d'attendre.
                let open = !NSRunningApplication.runningApplications(
                    withBundleIdentifier: "com.apple.systempreferences").isEmpty
                if open { settingsSeen = true }
                if open || !settingsSeen { settingsGoneSince = nil } else if settingsGoneSince == nil { settingsGoneSince = Date() }
                let neverOpened = !settingsSeen && (settingsAskedAt.map { Date().timeIntervalSince($0) >= 120 } ?? true)
                if neverOpened || settingsGoneSince.map({ Date().timeIntervalSince($0) >= 3 }) == true {
                    MacroLog.shared.write("AUDIO", "settings closed, not given")
                    close()
                }
                return
            }
        }
    }

    /// Panneau affiché (noté pour la reprise après « Quitter et rouvrir »).
    var isShowing: Bool { panel != nil }

    func close() {
        asking = false
        audioInSettings = false
        AppResume.shared.noteAsking(nil)
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func showPanel() {
        if let panel { panel.orderFrontRegardless(); return }
        let host = NSHostingView(rootView: AccessibilityGuideView(guide: self).background(ArrowCursorKeeper()))
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
            Rectangle()
                .fill(Swiss.red)
                .frame(width: 30, height: 17)
                .overlay(Circle().fill(Color.white).padding(2).shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5),
                         alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Rectangle().fill(Color.primary.opacity(0.05)))
        .overlay(Rectangle()
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
    /// L'autorisation attendue (notée à la fermeture : relancée encore une fois, la copie suivante attend aussi).
    private(set) var waitingKey: String?

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

    /// Réglages Système refermés (ouverts par l'app pour une autorisation, maintenant donnée).
    static func closeSystemSettings(why key: String) {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
        guard !apps.isEmpty else { return }
        for app in apps { app.terminate() }
        MacroLog.shared.write("ACCUEIL", "\(key) given: settings closed")
    }

    /// 12/11 (« ça quitte et FL Shortcuts se rouvre… mais ça ferme pas la page de réglage ») : rouverte par « Quitter
    /// et rouvrir » avec l'autorisation qu'elle demandait maintenant donnée, l'app referme les Réglages Système
    /// ouverts pour ça et revient devant. Rien si l'autorisation manque encore (l'attente garde les Réglages).
    static func closeSettingsIfGiven(_ key: String?) {
        guard let key, !missingNow(key) else { return }
        closeSystemSettings(why: key)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// `then` aussitôt si l'autorisation est déjà là ; sinon une fois l'attente finie.
    func start(asking key: String, then show: @escaping () -> Void) {
        guard Self.missingNow(key) else { show(); return }
        MacroLog.shared.write("ACCUEIL", "relaunched before \(key) was given: welcome waits")
        waitingKey = key
        AppResume.shared.noteAsking(key)                    // fermée de force pendant l'attente : la suivante attend
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
        if !missing { Self.closeSettingsIfGiven(key) }
        finishNow()
    }

    /// L'accueil revient maintenant (attente finie, ou app rouverte à la main) ; rien si l'app n'attendait pas.
    func finishNow() {
        timer?.invalidate()
        timer = nil
        if waitingKey != nil { AppResume.shared.noteAsking(nil) }
        waitingKey = nil
        let show = then
        then = nil
        show?()
    }
}
