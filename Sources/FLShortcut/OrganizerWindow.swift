// Organiser : la fenêtre (panneau flottant qui laisse FL au premier plan) et son contrôleur. Ouverte par le bloc
// « Organiser le projet » ou par le menu de la barre des menus. Lien avec FL installé à la demande (écran
// d'installation s'il manque), analyse de tout le projet, aperçu par famille (une couleur ou un dégradé chacune, ce
// qu'est chaque son modifiable, ce qui sera fait dans le Channel rack, les patterns, le Mixer et la Playlist), un seul
// « Organiser », puis « Revenir comme avant ». Tout est libéré à la fermeture (session, capture, IA, panneau) :
// rien ne tourne au repos. L'analyse lit le fichier du projet que FL vient d'enregistrer, et la Playlist est rangée
// dans une copie que FL ouvre (OrganizerProjectFile) : aucune lecture de l'écran. Sans fichier (tests), l'ancien
// rangement, qui lisait la fenêtre de FL (OrganizerPlaylistMover, OrganizerClipMover).
import AppKit
import ApplicationServices
import Combine
import SwiftUI

/// État du lien avec FL à l'ouverture de l'Organiser.
enum OrganizerLinkState: Equatable {
    /// Script jamais installé : écran d'installation.
    case notInstalled
    /// `warmUp` : ports MIDI tout juste créés (mode léger), le temps que FL les voie et charge le script.
    case ready(warmUp: TimeInterval)
    /// Script absent de FL Studio, remis à l'instant (même clé) : FL ne le lira qu'à son prochain lancement.
    case restored
}

/// Ce dont l'Organiser a besoin du monde réel (des faux dans les tests).
struct OrganizerEnvironment {
    var link: () -> OrganizerLink
    /// Capture du son de FL, ou la raison de l'impossibilité (macOS trop ancien, FL fermé).
    var audio: () -> Result<AudioSource, OrganizerError>
    var classify: () -> OrganizerSession.Classify
    /// ⌥↑ envoyé à FL : `moveUp(link)(n)` renvoie le nombre de pas faits.
    var moveUp: (OrganizerLink) -> (Int) -> Int
    /// ⌥← envoyé à FL (piste du Mixer décalée à gauche) : `moveLeft(link)(n)` renvoie le nombre de pas faits.
    var moveLeft: (OrganizerLink) -> (Int) -> Int = { _ in { _ in 0 } }
    var timing = OrganizerSession.Timing()
    var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    var escapePressed: () -> Bool = { false }
    var loadStyles: () -> [SoundFamily: FamilyStyle] = { FamilyStyles.load() }
    var saveStyles: ([SoundFamily: FamilyStyle]) -> Void = { FamilyStyles.save($0) }
    /// Icône posée sur l'élément sélectionné par la fenêtre de FL (F2) ; nil si c'est fait.
    var placeIcon: (FLIcon) -> OrganizerError? = { _ in nil }
    /// Fil principal, avant chaque écoute : lien installé ? Ports MIDI créés à la demande.
    var prepareLink: () -> OrganizerLinkState = { .ready(warmUp: 0) }
    /// « Installer le lien » (fil principal) : vrai s'il est installé (faux : annulé, ou impossible, déjà dit).
    var installLink: () -> Bool = { true }
    /// « Autre dossier de FL… » : le lien réinstallé dans le dossier de données de FL choisi (fil principal).
    var installLinkElsewhere: () -> Bool = { true }
    /// En attente de FL (à redémarrer, à ouvrir, page à ouvrir, lecture à arrêter) : nouvel essai, tout seul, à
    /// cet intervalle.
    var waitInterval: TimeInterval = 2
    /// Script dans FL Studio : où il est enregistré, et s'il y est encore (nil : aucun).
    var scriptPlace: () -> (url: URL, present: Bool)? = { nil }
    var reveal: (URL) -> Void = { _ in }
    /// Le script a dit être posé sur une autre entrée MIDI que « FL Shortcuts Link » (PROTOCOL.md §3).
    var wrongInput: () -> Bool = { false }
    var nameDrum: () -> OrganizerSession.NameDrum = { { _, _ in .perc } }
    /// Autorisation « Audio du système » (sans elle, macOS donne du silence à la capture).
    var audioPermission: () -> AudioCapturePermission = { .granted }
    /// Fenêtre de macOS pour la demander ; faux : rien n'a pu être demandé. `done` sur le fil principal.
    var requestAudioPermission: (@escaping (Bool) -> Void) -> Bool = { _ in false }
    var openAudioSettings: () -> Void = {}
    /// En-tête du diagnostic : versions et état du lien (aucun nom).
    var about: () -> String = { "" }
    var copy: (String) -> Void = { _ in }
    /// FL mis devant (le panneau flotte au-dessus) : sa page devant et ses touches en dépendent.
    var focusFL: () -> Void = {}
    /// Avant l'analyse (hors du fil principal), par les menus de FL : clips audio inutilisés retirés, sons sans note
    /// sélectionnés ; vrai si la sélection a été faite.
    var prepareProject: () -> Bool = { false }
    /// « Delete selected » du Channel rack (⌥ + Suppr) envoyé à FL ; faux si rien n'a pu être envoyé.
    var deleteSelected: (OrganizerLink) -> () -> Bool = { _ in { false } }
    /// Piste de la Playlist à cette place remontée de n places par son menu (« Move up ») ; le nombre fait.
    var moveTrack: (OrganizerLink) -> (Int, Int) -> Int = { _ in { _, _ in 0 } }
    /// Clips de la Playlist décalés de n pistes (négatif : vers le haut) : tous ceux de ce pattern (1 = le premier),
    /// ou la sélection en cours (nil) ; le nombre de pas faits.
    var moveClips: (OrganizerLink) -> (Int?, Int) -> Int = { _ in { _, _ in 0 } }
    /// La Playlist lue dans la fenêtre de FL (nil : impossible), et un clip déplacé seul vers une autre piste
    /// (ClipMover) ; `canReadPlaylist` : l'autorisation de lire la fenêtre de FL est là.
    var readClips: (OrganizerLink) -> () -> PlaylistView? = { _ in { nil } }
    var moveClip: (OrganizerLink) -> (ClipMove) -> ClipMoveResult = { _ in { _ in .notDone } }
    var canReadPlaylist: () -> Bool = { false }
    /// Le fichier du projet ouvert dans FL (enregistré par FL, lu, sa copie rangée ouverte) ; nil : l'ancienne
    /// analyse, à l'écoute de FL seulement.
    var projectFiles: () -> ProjectFileAccess? = { nil }

    static func live() -> OrganizerEnvironment {
        OrganizerEnvironment(
            link: { RequestOrganizerLink.live() },
            audio: {
                guard #available(macOS 14.2, *) else {
                    return .failure(.failed(String(localized: "L'Organiser écoute FL avec macOS 14.2 ou plus récent : mets macOS à jour.")))
                }
                guard let pid = OrganizerEnvironment.flPID() else { return .failure(.flClosed) }
                return .success(FLAudioTap(pid: pid))
            },
            classify: { OrganizerSession.liveClassifier() },
            moveUp: { link in { count in OrganizerEnvironment.liveMove(count, key: 126, page: .channelRack, link: link) } },
            moveLeft: { link in { count in OrganizerEnvironment.liveMove(count, key: 123, page: .mixer, link: link) } },
            escapePressed: { CGEventSource.keyState(.combinedSessionState, key: 53) },
            placeIcon: { OrganizerEnvironment.livePlaceIcon($0) },
            prepareLink: { OrganizerEnvironment.livePrepareLink() },
            installLink: { FLScriptInstaller.installWithAlert(quiet: true) },
            installLinkElsewhere: { FLScriptInstaller.installWithAlert(chooseFolder: true, quiet: true) },
            scriptPlace: { FLScriptInstaller.installedScript() },
            reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
            wrongInput: { MIDILink.shared.core.snapshot.wrongInput },
            nameDrum: { OrganizerSession.liveDrumNamer() },
            audioPermission: { AudioCapturePermission.status },
            requestAudioPermission: { done in
                NSApp.activate(ignoringOtherApps: true)        // la fenêtre de macOS devant FL, pas derrière
                return AudioCapturePermission.request(done)
            },
            openAudioSettings: { ScreenLook.openSettings() },
            about: {
                let app = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
                let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
                let os = ProcessInfo.processInfo.operatingSystemVersion
                let snap = MIDILink.shared.core.snapshot
                let api = snap.hello.map { "\($0.apiVersion)" } ?? "?"
                let fl = FLDetector.installedVersion().map { "\($0)" } ?? "?"
                return "app \(app) (\(build)) · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · FL \(fl) "
                    + "· API \(api) · lien \(snap.hello == nil ? "muet" : "ok") · audio=\(AudioCapturePermission.status) "
                    + "· écran=\(ScreenLook.allowed ? "oui" : "non") · AX=\(AXIsProcessTrusted() ? "oui" : "non")"
            },
            copy: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            focusFL: {
                guard let pid = OrganizerEnvironment.flPID() else { return }
                if EventTap.shared.currentConfig.frontmostPID != pid {
                    _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [])
                }
                // Sa fenêtre principale de nouveau active (un champ de texte du panneau a pu prendre le clavier).
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.3)
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &value) == .success,
                   let value, CFGetTypeID(value) == AXUIElementGetTypeID() {
                    AXUIElementPerformAction(value as! AXUIElement, kAXRaiseAction as CFString)
                }
            },
            prepareProject: { OrganizerEnvironment.livePrepareProject() },
            deleteSelected: { link in { OrganizerEnvironment.liveDeleteSelected(link: link) } },
            moveTrack: { link in { place, count in OrganizerEnvironment.liveMoveTrack(place, count, link: link) } },
            moveClips: { link in { pattern, rows in OrganizerEnvironment.liveMoveClips(pattern, rows, link: link) } },
            readClips: { link in { OrganizerEnvironment.liveReadClips(link: link) } },
            moveClip: { link in { move in OrganizerEnvironment.liveMoveClip(move, link: link) } },
            canReadPlaylist: { ScreenLook.allowed },
            projectFiles: { ProjectFileLive.access() })
    }

    /// La Playlist devant (FL au premier plan), lue dans sa fenêtre.
    static func liveReadClips(link: OrganizerLink) -> PlaylistView? {
        guard let pid = playlistInFront(link: link) else { return nil }
        return ClipMover.read(link: link, pid: pid)?.view
    }

    /// Un clip déplacé seul vers une autre piste, Playlist devant ; le panneau de l'Organiser laisse passer le clic.
    static func liveMoveClip(_ move: ClipMove, link: OrganizerLink) -> ClipMoveResult {
        guard let pid = playlistInFront(link: link) else { return .notDone }
        OrganizerWindow.clickThrough(true)
        defer { OrganizerWindow.clickThrough(false) }
        return ClipMover.move(move, link: link, pid: pid)
    }

    /// FL au premier plan et sa Playlist devant ; son processus, ou nil.
    private static func playlistInFront(link: OrganizerLink) -> Int32? {
        guard let pid = flPID(), (try? link.show(.playlist)) != nil else { return nil }
        if EventTap.shared.currentConfig.frontmostPID != pid {
            _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            Thread.sleep(forTimeInterval: 0.3)
        }
        guard link.window == .playlist, EventTap.shared.currentConfig.frontmostPID == pid else { return nil }
        return pid
    }

    /// Par les menus de FL dans la barre de macOS (comme le modèle « Supprimer les clips audio inutilisés ») : Tools ›
    /// Purge unused audio clips, puis Tools › Select unused channels (les sons sans aucune note, laissés de côté par
    /// l'Organiser) ; vrai si la sélection a été faite. Un menu absent (FL plus ancien) : rien.
    static func livePrepareProject() -> Bool {
        guard let pid = flPID() else { return false }
        _ = MenuBarAX.press(pid: pid, titles: ["Tools", "Macros", "Purge unused audio clips"], stop: { nil })
        Thread.sleep(forTimeInterval: 0.5)
        guard MenuBarAX.press(pid: pid, titles: ["Tools", "Macros", "Select unused channels"], stop: { nil }) == .done
        else { return false }
        Thread.sleep(forTimeInterval: 0.3)
        return true
    }

    /// « Delete selected » du Channel rack comme le ferait l'utilisateur : ⌥ + Suppr (fn + ⌫) envoyé à FL seul, le
    /// Channel rack devant. Une fenêtre de FL ouverte par la touche (une confirmation) est validée par Entrée.
    static func liveDeleteSelected(link: OrganizerLink) -> Bool {
        guard let pid = flPID() else { return false }
        if EventTap.shared.currentConfig.frontmostPID != pid {
            _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            Thread.sleep(forTimeInterval: 0.3)
        }
        guard link.window == .channelRack, EventTap.shared.currentConfig.frontmostPID == pid else { return false }
        let before = WinSnapshot.take(pid: pid).numbers
        let effects = MacroEffectsMac(pid: pid)
        effects.postKey(KeyCombo(keyCode: 117, option: true), pid: pid)
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.1)
            let opened = WinSnapshot.take(pid: pid).fl.filter {
                !before.contains($0.number) && $0.bounds.width >= 150 && $0.bounds.height >= 80
            }
            if !opened.isEmpty {
                MacroLog.shared.write("ORGANIZE", "delete: FL asked for a confirmation, Return")
                effects.postKey(KeyCombo(keyCode: 36), pid: pid)
                _ = WindowWait.gone(pid: pid, numbers: Set(opened.map(\.number)), timeout: 1, stop: { nil })
                break
            }
        }
        Thread.sleep(forTimeInterval: 0.2)
        return true
    }

    /// Piste de la Playlist remontée par son menu (OrganizerPlaylistMover), FL au premier plan et la Playlist devant ;
    /// le panneau de l'Organiser laisse passer les clics le temps du rangement.
    static func liveMoveTrack(_ place: Int, _ count: Int, link: OrganizerLink) -> Int {
        guard let pid = flPID() else { return 0 }
        if EventTap.shared.currentConfig.frontmostPID != pid {
            _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            Thread.sleep(forTimeInterval: 0.3)
        }
        guard link.window == .playlist else { return 0 }
        OrganizerWindow.clickThrough(true)
        defer { OrganizerWindow.clickThrough(false) }
        return PlaylistMover.moveUp(place, count, link: link, pid: pid)
    }

    /// Clips de la Playlist décalés de `rows` pistes (négatif : vers le haut), FL au premier plan, la Playlist devant,
    /// comme le ferait l'utilisateur : avec un pattern, d'abord tous ses clips sélectionnés (le script l'ouvre, puis ⌘D
    /// et ⇧C de FL : « Select by selected source ») ; sans, la sélection en cours. ⇧↓ ou ⇧↑ envoyés à FL seul ;
    /// renvoie le nombre de pas faits.
    static func liveMoveClips(_ pattern: Int?, _ rows: Int, link: OrganizerLink) -> Int {
        guard rows != 0, let pid = flPID() else { return 0 }
        if let pattern {
            guard (try? link.pickPattern(pattern)) == pattern else { return 0 }
        }
        guard (try? link.show(.playlist)) != nil else { return 0 }
        if EventTap.shared.currentConfig.frontmostPID != pid {
            _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            Thread.sleep(forTimeInterval: 0.3)
        }
        guard link.window == .playlist, EventTap.shared.currentConfig.frontmostPID == pid else { return 0 }
        let effects = MacroEffectsMac(pid: pid)
        if pattern != nil {
            let layout = SystemKeyboardLayout()
            let d = KeyNames.commandKeyCode(for: "d", layout: layout) ?? 2
            let c = KeyNames.keyCode(for: "c", layout: layout) ?? 8
            effects.postKey(KeyCombo(keyCode: d, command: true), pid: pid)      // rien de sélectionné
            Thread.sleep(forTimeInterval: 0.08)
            effects.postKey(KeyCombo(keyCode: c, shift: true), pid: pid)        // tous les clips du pattern ouvert
            Thread.sleep(forTimeInterval: 0.15)
        }
        let arrow = KeyCombo(keyCode: rows > 0 ? 125 : 126, shift: true)
        var done = 0
        while done < abs(rows) {
            guard EventTap.shared.currentConfig.frontmostPID == pid else { break }
            effects.postKey(arrow, pid: pid)
            done += 1
            Thread.sleep(forTimeInterval: 0.03)
        }
        Thread.sleep(forTimeInterval: 0.1)
        return done
    }

    /// Lien installé : script remis dans FL s'il en a disparu, ports « FL Shortcuts Link » créés s'ils ne sont pas là
    /// (mode léger, sans trafic), comme pour une macro qui en a besoin.
    static func livePrepareLink() -> OrganizerLinkState {
        let midi = MIDILink.shared
        guard midi.snapshot.hasKey else { return .notInstalled }
        // Remis maintenant, ou mis à jour au lancement de l'appli pendant que FL tournait : FL doit le relire.
        let restored = FLScriptInstaller.repairIfNeeded() != nil || AppStatus.shared.scriptNeedsFLRestart
        let fresh = AppMode.light && !midi.onDemand
        midi.setOnDemand(true)
        return restored ? .restored : .ready(warmUp: fresh && midi.onDemand ? 2 : 0)
    }

    /// Mêmes étapes et garde-fous que le bloc « Nom et couleur » (FL au premier plan, Échap).
    static func livePlaceIcon(_ icon: FLIcon) -> OrganizerError? {
        guard let pid = flPID() else { return .failed(String(localized: "FL Studio n'est pas ouvert.")) }
        if EventTap.shared.currentConfig.frontmostPID != pid {
            _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            Thread.sleep(forTimeInterval: 0.3)
        }
        switch MacroEffectsMac(pid: pid).placeIcon(icon, alsoColored: false) {
        case .ok, .warn: return nil
        case .fail(let why), .cancel(let why):
            return .failed(why.prefix(1).uppercased() + String(why.dropFirst()) + String(localized: ". Les couleurs sont posées."))
        }
    }

    /// FL au premier plan d'abord, sinon le premier FL ouvert.
    static func flPID() -> Int32? {
        let cfg = EventTap.shared.currentConfig
        if cfg.flPIDs.contains(cfg.frontmostPID) { return cfg.frontmostPID }
        return cfg.flPIDs.min()
    }

    /// ⌥ + flèche (`key` : 126 ↑ dans le Channel rack, 123 ← dans le Mixer) envoyé à FL seul, 15 ms entre deux ;
    /// s'arrête dès que FL n'est plus au premier plan ou que la page n'est plus devant dans FL.
    static func liveMove(_ count: Int, key: UInt16, page: FLWindow, link: OrganizerLink) -> Int {
        guard count > 0, let pid = flPID() else { return 0 }
        if EventTap.shared.currentConfig.frontmostPID != pid {
            _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            Thread.sleep(forTimeInterval: 0.3)
        }
        let effects = MacroEffectsMac(pid: pid)
        let up = KeyCombo(keyCode: key, option: true)
        guard link.window == page else { return 0 }          // demandé à FL (une requête), pas à chaque touche
        var done = 0
        while done < count {
            guard EventTap.shared.currentConfig.frontmostPID == pid else { break }
            effects.postKey(up, pid: pid)
            done += 1
            Thread.sleep(forTimeInterval: 0.015)
        }
        return done
    }
}

final class OrganizerController: ObservableObject {
    /// Ce qu'Organiser attend de FL : il réessaie tout seul (`waitInterval`) et continue dès que c'est bon.
    enum Wait: Equatable {
        /// Lien tout juste installé ou remis, ou ancienne version chargée : FL le lit en démarrant.
        case restartFL
        /// FL ne répond pas (lien pas encore chargé dans FL).
        case noResponse
        /// Le script est chargé, mais sur une autre entrée MIDI (carte son, clavier) : il ne reçoit rien.
        case wrongInput
        case openFL
        case stopPlayback
        /// « Audio du système » refusée, ou sa fenêtre de macOS ouverte : l'écoute n'entendrait que du silence.
        case audioPermission
    }

    enum Phase: Equatable {
        case starting
        /// Lien avec FL pas installé : écran d'installation.
        case setup
        /// En attente de FL : nouvel essai tout seul, toutes les `waitInterval` secondes.
        case waiting(Wait)
        case listening(done: Int, total: Int)
        case preview
        case applying
        case applied(OrganizerError?)
        case undoing
        case undone(OrganizerError?)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .starting
    /// Famille de chaque son du Channel rack (index du canal), modifiable dans l'aperçu.
    @Published var families: [Int: SoundFamily] = [:]
    /// Ce qu'est chaque son (Kick, 808, Open Hat…), modifiable dans l'aperçu ; oublié s'il ne va plus avec sa
    /// famille.
    @Published var kinds: [Int: SoundKind] = [:]
    @Published var styles: [SoundFamily: FamilyStyle]
    @Published private(set) var result: OrganizerResult?
    /// Ce que « Organiser » fait : les pages de FL touchées, et les noms.
    @Published var options = OrganizerOptions()
    /// Ce que la dernière application a fait de plus (sons supprimés, Playlist rangée ou non).
    @Published private(set) var lastApply: ApplyOutcome?
    /// Où en est l'application (« FL ouvre la copie rangée… 12 s ») ; nil : le texte général.
    @Published private(set) var applyStep: String?
    /// En attente de FL : l'aide détaillée (réglages de FL, dossier du script) dépliée.
    @Published var showLinkHelp = false

    /// Appelé une fois, à la fermeture (la fenêtre se ferme et lâche le contrôleur).
    var onClose: (() -> Void)?

    private let env: OrganizerEnvironment
    private let queue = DispatchQueue(label: "app.flshortcut.organizer", qos: .userInitiated)
    private var link: OrganizerLink?
    private var session: OrganizerSession?
    private var snapshot: OrganizerSnapshot?
    private var closed = false
    /// La fenêtre de macOS pour « Audio du système » est montrée une fois par Organiser ouvert.
    private var askedAudio = false
    /// Écoute en cours : la fin d'une écoute remplacée (nouvel essai) est ignorée (audit : deux écoutes à la fois).
    private var runToken = 0
    /// Ce que la dernière écoute a fait, en nombres (« Copier le diagnostic »).
    @Published private(set) var diagnostics: OrganizerDiagnostics?
    /// « Copié » montré un instant après « Copier le diagnostic ».
    @Published private(set) var copied = false

    init(env: OrganizerEnvironment) {
        self.env = env
        styles = env.loadStyles()
    }

    var title: String { String(localized: "Organiser le projet") }

    /// Écoute de chaque son, hors du fil principal.
    func start() {
        guard phase == .starting else { return }
        begin(quiet: false)
    }

    /// `quiet` : nouvel essai pendant une attente ; l'écran d'attente reste jusqu'au premier son écouté (pas
    /// d'aller-retour entre « En attente » et « Préparation… » toutes les 2 secondes).
    private func begin(quiet: Bool) {
        guard !closed else { return }
        let warmUp: TimeInterval
        switch env.prepareLink() {
        case .notInstalled:
            phase = .setup
            return
        case .restored:
            wait(.restartFL)
            return
        case .ready(let delay):
            warmUp = delay
        }
        // « Audio du système » : sans elle, macOS donne du silence (chaque son finissait « À vérifier »). Pas encore
        // demandée : la fenêtre de macOS, une fois, avant l'écoute ; refusée : Organiser attend qu'elle soit donnée.
        switch env.audioPermission() {
        case .denied:
            wait(.audioPermission)
            return
        case .unknown where !askedAudio:
            askedAudio = true
            if env.requestAudioPermission({ [weak self] _ in self?.afterAudioPermission() }) {
                waitSerial += 1                               // pas d'essai tout seul pendant la fenêtre de macOS
                phase = .waiting(.audioPermission)
                return
            }
        default:
            break
        }
        let audio: AudioSource
        switch env.audio() {
        case .success(let source):
            audio = source
        case .failure(let error):
            if let reason = Self.waitReason(for: error, wrongInput: env.wrongInput()) { wait(reason) } else { phase = .failed(error.message) }
            return
        }
        if !quiet { env.focusFL() }
        self.session?.cancel()                                // l'ancienne écoute s'arrête (FL remis comme avant)
        runToken += 1
        let token = runToken
        let link = env.link()
        let session = OrganizerSession(
            link: link, audio: audio, classify: env.classify(), nameDrum: env.nameDrum(), timing: env.timing,
            sleep: env.sleep, escape: env.escapePressed, prepare: env.prepareProject, files: env.projectFiles(),
            progress: { [weak self] done, total in
                DispatchQueue.main.async {
                    guard self?.runToken == token else { return }
                    self?.listening(done, total)
                }
            })
        self.link = link
        self.session = session
        if !quiet { phase = .listening(done: 0, total: 0) }
        let sleep = env.sleep
        queue.async { [weak self] in                           // file en série : jamais deux écoutes en même temps
            if warmUp > 0 { sleep(warmUp) }
            let outcome = session.run()
            let diagnostics = session.diagnostics
            DispatchQueue.main.async {
                guard self?.runToken == token else { return }
                self?.diagnostics = diagnostics
                self?.finishListening(outcome)
            }
        }
    }

    /// Ce qui se règle dans FL (redémarrer, ouvrir une page, arrêter la lecture…) : Organiser attend et continue
    /// tout seul. nil : un vrai échec, dit tel quel.
    static func waitReason(for error: OrganizerError, wrongInput: Bool = false) -> Wait? {
        switch error {
        case .noResponse: return wrongInput ? .wrongInput : .noResponse
        case .outdatedScript: return .restartFL
        case .flClosed: return .openFL
        case .refused(4): return .stopPlayback
        default: return nil
        }
    }

    /// Nouvelle attente : un essai part tout seul après `waitInterval`, tant que la fenêtre attend toujours la même
    /// chose (un essai manuel, une installation ou la fermeture l'annulent).
    private var waitSerial = 0

    private func wait(_ reason: Wait) {
        phase = .waiting(reason)
        waitSerial += 1
        let serial = waitSerial
        DispatchQueue.main.asyncAfter(deadline: .now() + env.waitInterval) { [weak self] in
            guard let self, !self.closed, self.waitSerial == serial, case .waiting = self.phase else { return }
            self.begin(quiet: true)
        }
    }

    /// Réponse à la fenêtre de macOS : l'écoute part (ou attend l'autorisation, refusée).
    private func afterAudioPermission() {
        guard !closed, phase == .waiting(.audioPermission) else { return }
        retry()
    }

    func openAudioSettings() { env.openAudioSettings() }

    /// Texte à m'envoyer quand ça ne marche pas : versions, autorisations, état, et ce que l'écoute a fait — des
    /// nombres seulement, jamais le nom d'un son ou d'une piste.
    var diagnosticText: String {
        var lines = ["FL Shortcuts · diagnostic de l'Organiser", env.about(), "étape=\(Self.phaseCode(phase))"]
        if let diagnostics { lines.append(diagnostics.text) }
        if let trace = lastApply?.trace, !trace.isEmpty { lines.append("application=" + trace.joined(separator: " ; ")) }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    func copyDiagnostic() {
        env.copy(diagnosticText)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.copied = false }
    }

    /// Étape en un mot (diagnostic) : jamais le texte d'un message qui pourrait citer un nom.
    static func phaseCode(_ phase: Phase) -> String {
        switch phase {
        case .starting: return "début"
        case .setup: return "installation"
        case .waiting(let wait): return "attente-\(wait)"
        case .listening(let done, let total): return "écoute-\(done)/\(total)"
        case .preview: return "aperçu"
        case .applying: return "application"
        case .applied(let error): return "appliqué" + (error.map { "-\($0)" } ?? "")
        case .undoing: return "retour"
        case .undone(let error): return "revenu" + (error.map { "-\($0)" } ?? "")
        case .failed: return "échec"
        }
    }

    /// « Réessayer » : après un échec, ou tout de suite pendant une attente.
    var canRetry: Bool {
        switch phase {
        case .setup, .failed, .waiting: return snapshot == nil
        default: return false
        }
    }

    func retry() {
        guard canRetry, !closed else { return }
        waitSerial += 1
        result = nil
        families = [:]
        kinds = [:]
        phase = .starting
        start()
    }

    /// Lien installé en un clic : FL doit redémarrer pour le lire, Organiser attend et continue tout seul.
    func installLink() {
        guard env.installLink(), !closed else { return }
        wait(.restartFL)
    }

    var scriptPlace: (url: URL, present: Bool)? { env.scriptPlace() }

    func revealScript() {
        if let place = env.scriptPlace(), place.present { env.reveal(place.url) }
    }

    func installLinkElsewhere() {
        guard env.installLinkElsewhere(), !closed else { return }
        wait(.restartFL)
    }

    private func listening(_ done: Int, _ total: Int) {
        switch phase {
        case .listening, .waiting: phase = .listening(done: done, total: total)   // l'attente finit au premier son
        default: return
        }
    }

    private func finishListening(_ outcome: Result<OrganizerResult, OrganizerError>) {
        session = nil
        guard !closed else { return }
        switch outcome {
        case .success(let result):
            self.result = result
            families = OrganizerApplier.families(of: result)
            kinds = OrganizerApplier.kinds(of: result)
            if !families.isEmpty || !plan.isEmpty {
                phase = .preview
            } else {
                phase = .failed(String(localized: "Aucun son à organiser dans ce projet."))
            }
        case .failure(let error):
            if let reason = Self.waitReason(for: error, wrongInput: env.wrongInput()) { wait(reason) } else { phase = .failed(error.message) }
        }
    }

    /// Ce que « Organiser » fera, d'après ce qu'est chaque son (modifiable) et les options.
    var plan: OrganizerPlan {
        guard let result else { return OrganizerPlan() }
        return OrganizerPlan.make(result, families: families, kinds: kinds, styles: styles, options: options)
    }

    /// Familles présentes, dans l'ordre Voix, Mélodies, Basse, Drums, FX, À vérifier (les familles absentes sont
    /// sautées).
    var presentFamilies: [SoundFamily] {
        let used = Set(families.values)
        return SoundFamily.order.filter { used.contains($0) }
    }

    struct Member: Identifiable, Equatable {
        let id: Int
        let name: String
        let testNotes: Bool
        /// Classé d'après son nom (rien n'a été écouté).
        var byName = false
        /// Nom qu'il prendra (nil : il garde le sien).
        var newName: String? = nil
        /// Ce qu'est le son (Kick, 808…), s'il va avec sa famille.
        var kind: SoundKind? = nil
    }

    /// Sons d'une famille, dans l'ordre où ils finiront dans le Channel rack (les Kick ensemble, puis les Snare…).
    func members(of family: SoundFamily) -> [Member] {
        guard let result else { return [] }
        let channels = result.channels.sorted { $0.index < $1.index }
        let order = OrganizerApplier.rackPlan(channels, families: families, kinds: kinds).final
        var byIndex: [Int: OrganizerItem] = [:]
        for item in result.items { byIndex[item.index] = item }
        let names = plan.rack.names
        return order.compactMap { index in
            guard families[index] == family, let item = byIndex[index] else { return nil }
            return Member(id: index, name: item.name, testNotes: item.testNotes, byName: item.byName,
                          newName: names[index].flatMap { $0 == item.name ? nil : $0 }, kind: kind(of: index))
        }
    }

    /// Ce qu'est le son, s'il va avec sa famille.
    func kind(of index: Int) -> SoundKind? {
        OrganizerApplier.kind(index, families: families, kinds: kinds)
    }

    /// Changé dans l'aperçu : une famille seule (ce qu'était le son est oublié), ou ce qu'est le son (sa famille suit).
    func setFamily(_ index: Int, _ family: SoundFamily) {
        families[index] = family
        kinds[index] = nil
    }

    func setKind(_ index: Int, _ kind: SoundKind) {
        families[index] = kind.family
        kinds[index] = kind
    }

    /// Couleur prévue de chaque son du Channel rack (dégradés répartis dans l'ordre final), même si le Channel rack
    /// n'est pas touché : la couleur de sa famille dans l'aperçu.
    var plannedColors: [Int: RGBColor] {
        guard let result else { return [:] }
        let channels = result.channels.sorted { $0.index < $1.index }
        let order = OrganizerApplier.rackPlan(channels, families: families, kinds: kinds).final
        return OrganizerApplier.plannedColors(families: families, styles: styles, order: order)
    }

    /// Analyse sur le fichier : tout se fait dans une copie rangée du projet (OrganizerProjectFile), Channel rack sur
    /// « All » ; sa Playlist n'est rangée que si « Playlist » est cochée.
    var organizesCopy: Bool { result?.project != nil }

    /// Une ligne par page de FL touchée, pour l'aperçu : combien d'éléments seront rangés, colorés, renommés.
    var summary: [(symbol: String, text: String)] {
        let plan = self.plan
        var out: [(symbol: String, text: String)] = []
        if !plan.deleted.isEmpty {
            out.append(("trash", organizesCopy
                ? String(localized: "\(plan.deleted.count) sons sans aucune note supprimés du Channel rack de la copie rangée")
                : String(localized: "\(plan.deleted.count) sons sans aucune note supprimés du Channel rack (on ne peut pas les remettre avec « Revenir comme avant »)")))
        }
        if options.rack, !plan.rack.isEmpty {
            out.append(("square.stack.3d.up", String(localized: "Channel rack : \(plan.rack.colors.count) sons regroupés et colorés, \(plan.rack.names.count) renommés")))
        }
        if options.patterns, !plan.patterns.isEmpty {
            out.append(("square.stack", String(localized: "Patterns : \(plan.patterns.colors.count) colorés, \(plan.patterns.names.count) renommés")))
        }
        if options.mixer, !plan.mixer.isEmpty {
            let buses = plan.mixer.buses.count
            let tracks = plan.mixer.verdicts.count - buses
            out.append(("slider.vertical.3", buses > 0
                ? String(localized: "Mixer : \(tracks) pistes dans l'ordre du Channel rack, \(buses) bus (un par famille), \(plan.mixer.names.count) renommées")
                : String(localized: "Mixer : \(tracks) pistes dans l'ordre du Channel rack, \(plan.mixer.names.count) renommées")))
            if !plan.mixer.links.isEmpty {
                out.append(("arrow.triangle.branch", String(localized: "\(plan.mixer.links.count) sons envoyés au Master reliés chacun à une piste libre du Mixer")))
            }
            if !plan.mixer.resets.isEmpty {
                out.append(("eraser", String(localized: "\(plan.mixer.resets.count) pistes du Mixer sans son remises comme neuves (nom et couleur de FL)")))
            }
        }
        if plan.deleted.isEmpty, let unused = result?.unused.count, unused > 0 {
            out.append(("moon.zzz", String(localized: "\(unused) sons sans aucune note laissés de côté (ni rangés, ni colorés, ni renommés)")))
        }
        if options.playlist, !plan.playlist.isEmpty {
            out.append(("rectangle.split.3x1", plan.playlist.moves.isEmpty
                ? String(localized: "Playlist : \(plan.playlist.colors.count) pistes colorées, \(plan.playlist.names.count) renommées")
                : String(localized: "Playlist : \(plan.playlist.colors.count) pistes colorées, \(plan.playlist.names.count) renommées, rangées comme le Channel rack")))
        }
        if options.playlist, let layout = plan.layout {
            out.append(("square.split.1x2", String(localized: "Playlist rangée dans une copie de ton projet : chaque son sur sa piste, tous les clips des mêmes sons réunis (\(layout.count) pistes). Ton projet d'origine ne bouge pas.")))
            if let silent = result?.project?.silentPatterns, silent > 0 {
                out.append(("moon.zzz", String(localized: "\(silent) patterns sans aucune note (rien n'y joue) : chacun sur sa piste, en bas de la Playlist")))
            }
        } else if organizesCopy, options.playlist {
            out.append(("exclamationmark.triangle", String(localized: "Playlist : il faudrait plus de pistes que FL n'en a pour mettre chaque son sur la sienne ; décoche « Playlist » pour ranger le reste.")))
        } else if options.playlist, options.splitTracks, env.canReadPlaylist() {
            out.append(("square.split.1x2", String(localized: "Playlist : un son par piste, et les clips d'un même son réunis sur sa piste (FL Shortcuts lit la fenêtre de FL au moment de les déplacer)")))
        } else if options.playlist, !plan.splits.isEmpty {
            out.append(("square.split.1x2", String(localized: "Playlist : \(plan.splits.count) sons qui partagent une piste avec un autre auront chacun la leur")))
        }
        return out
    }

    func style(of family: SoundFamily) -> FamilyStyle {
        styles[family] ?? FamilyStyles.initial[family] ?? FamilyStyle(color: NameColorPayload.defaultColor)
    }

    func updateStyle(_ family: SoundFamily, _ change: (inout FamilyStyle) -> Void) {
        var updated = self.style(of: family)
        change(&updated)
        styles[family] = updated
    }

    var doneText: String {
        var lines = [String(localized: "C'est fait : le projet est rangé, coloré et renommé. « Revenir comme avant » défait tout, sauf les sons supprimés.")]
        if let copy = lastApply?.copy {
            // Rangé dans une copie : son nom à l'écran (jamais dans le journal).
            lines = [String(localized: "C'est fait : ton projet est rangé, coloré et renommé dans une copie, « \(copy.lastPathComponent) », à côté de l'original. L'original n'a pas bougé : « Revenir comme avant » le rouvre.")]
            if lastApply?.copyNotSaved == true {
                lines.append(String(localized: "FL n'a pas enregistré la copie rangée : enregistre-la dans FL (⌘S)."))
            }
        }
        if let outcome = lastApply {
            if outcome.deleted > 0 {
                lines.append(String(localized: "\(outcome.deleted) sons sans aucune note supprimés."))
            }
            if outcome.notDeleted > 0 {
                lines.append(String(localized: "FL n'a pas supprimé les \(outcome.notDeleted) sons sans aucune note : ils sont sélectionnés dans le Channel rack, supprime-les avec clic droit › Delete."))
            }
            if outcome.split > 0 {
                lines.append(String(localized: "Playlist : \(outcome.split) sons qui partageaient une piste ont chacun la leur."))
            }
            if outcome.reunited > 0 {
                lines.append(String(localized: "Playlist : \(outcome.reunited) clips déplacés sur la piste de leur son (un son par piste)."))
            }
            if outcome.clipsLeft > 0 {
                lines.append(String(localized: "Playlist : \(outcome.clipsLeft) clips n'ont pas pu rejoindre la piste de leur son (leur nom n'a pas été lu dans la fenêtre de FL, ou FL ne l'a pas laissé faire) : ils sont restés à leur place."))
            }
            if outcome.playlistMixed {
                lines.append(String(localized: "Playlist : des pistes gardent deux sons, FL n'a pas laissé descendre leurs clips sur une piste à eux (dans FL, « Typing keyboard to piano keyboard » doit être éteint)."))
            }
            if outcome.playlistUnordered {
                lines.append(ScreenLook.allowed
                    ? String(localized: "Playlist pas rangée : FL n'a pas montré le menu de ses pistes (la Playlist doit être visible, ses noms de piste à l'écran). Noms et couleurs sont posés.")
                    : String(localized: "Playlist pas rangée : pour remonter ses pistes, FL Shortcuts doit voir la fenêtre de FL (Réglages Système › Confidentialité et sécurité › Enregistrement de l'écran). Noms et couleurs sont posés."))
            }
        }
        return lines.joined(separator: "\n")
    }

    func apply() {
        guard phase == .preview, let result, let link else { return }
        env.saveStyles(styles)
        env.focusFL()                                         // ⌥↑, ⌥← et F2 vont à FL
        phase = .applying
        applyStep = nil
        let applier = OrganizerApplier(link: link, moveUp: env.moveUp(link), moveLeft: env.moveLeft(link),
                                       placeIcon: env.placeIcon, deleteSelected: env.deleteSelected(link),
                                       moveTrack: env.moveTrack(link), moveClips: env.moveClips(link),
                                       readClips: env.readClips(link), moveClip: env.moveClip(link),
                                       wait: env.sleep, listen: env.timing.trackListen, files: env.projectFiles(),
                                       report: { [weak self] text in
                                           DispatchQueue.main.async { self?.applyStep = text }
                                       })
        let plan = self.plan, styles = self.styles
        queue.async { [weak self] in
            let outcome = applier.apply(plan, result: result, styles: styles)
            DispatchQueue.main.async {
                self?.snapshot = outcome.snapshot
                self?.lastApply = outcome
                self?.phase = .applied(outcome.error)
            }
        }
    }

    /// « Revenir comme avant » : après l'application, ou pour finir un retour interrompu.
    var canUndo: Bool {
        guard let snapshot, !snapshot.isEmpty else { return false }
        switch phase {
        case .applied: return true
        case .undone(let error): return error != nil
        default: return false
        }
    }

    func undo() {
        guard canUndo, let snapshot, let link else { return }
        env.focusFL()
        phase = .undoing
        let applier = OrganizerApplier(link: link, moveUp: env.moveUp(link), moveLeft: env.moveLeft(link),
                                       moveTrack: env.moveTrack(link), moveClips: env.moveClips(link),
                                       readClips: env.readClips(link), moveClip: env.moveClip(link),
                                       wait: env.sleep, listen: env.timing.trackListen, files: env.projectFiles())
        queue.async { [weak self] in
            let outcome = applier.undo(snapshot)
            DispatchQueue.main.async {
                self?.snapshot = outcome.snapshot
                self?.phase = .undone(outcome.error)
            }
        }
    }

    /// Mode capture (mesure de la CI) : un écran donné, avec des sons d'exemple ; rien n'est envoyé à FL.
    func showDemo(_ screen: String) {
        waitSerial += 1
        showLinkHelp = screen == "aide"
        switch screen {
        case "installer": phase = .setup
        case "attente": phase = .waiting(.restartFL)
        case "aide": phase = .waiting(.noResponse)
        case "ecoute": phase = .listening(done: 3, total: 8)
        case "apercu", "fini":
            let result = Self.demoResult
            self.result = result
            families = OrganizerApplier.families(of: result)
            kinds = OrganizerApplier.kinds(of: result)
            phase = screen == "fini" ? .applied(nil) : .preview
        default: break
        }
    }

    /// Un petit projet d'exemple : des sons nommés comme dans les packs, leurs patterns, leurs pistes du Mixer et
    /// de la Playlist.
    static var demoResult: OrganizerResult {
        let names = ["BEAM KICK", "Serum Lead", "ZEBRA 808", "@MEH CLAP", "ALTER OPEN HAT", "Vocal Chop", "Riser FX",
                     "Pluck"]
        let gray = RGBColor(r: 92, g: 101, b: 107)
        let channels = names.enumerated().map {
            ChannelInfo(index: $0.offset, type: 2, mixerTrack: $0.offset + 1, color: gray, name: $0.element)
        }
        let items = names.enumerated().compactMap { entry -> OrganizerItem? in
            guard let kind = SoundNames.kind(of: entry.element) else { return nil }
            return OrganizerItem(index: entry.offset, name: entry.element, family: kind.family, confidence: 0.9,
                                 testNotes: false, mixerTrack: entry.offset + 1, color: gray, kind: kind, byName: true)
        }
        let patterns = (0..<4).map { PatternInfo(index: $0, color: gray, name: "Pattern \($0 + 1)") }
        let mixer = (0...10).map { MixerTrackInfo(index: $0, color: gray, name: $0 == 0 ? "Master" : "Insert \($0)") }
        let playlist = (0..<4).map { PlaylistTrackInfo(index: $0, selected: false, color: gray, name: "Track \($0 + 1)") }
        return OrganizerResult(channels: channels, items: items, patterns: patterns,
                               patternSounds: [0: [0, 3, 4], 1: [2], 2: [1, 7], 3: [5]], mixer: mixer, routes: [:],
                               playlist: playlist, trackSounds: [0: [0], 1: [3, 4], 2: [2], 3: [1, 7]])
    }

    /// Arrête l'écoute (la session remet FL comme avant) et ferme la fenêtre.
    func close() {
        guard !closed else { return }
        closed = true
        session?.cancel()
        session = nil
        let done = onClose
        onClose = nil
        done?()
    }
}

/// Le panneau de l'Organiser : un seul à la fois, détruit à la fermeture. Sans barre de titre visible (contenu sous
/// les boutons de fenêtre, déplaçable par le fond) ; sa hauteur suit son contenu (un message court : un petit
/// panneau), l'aperçu garde une hauteur fixe qui défile.
enum OrganizerWindow {
    private static var panel: NSPanel?
    /// Le contrôleur affiché (nil quand la fenêtre est fermée).
    private(set) static var controller: OrganizerController?
    private static let delegate = Delegate()
    /// Taille ajustée à chaque étape.
    private static var sizing: AnyCancellable?

    private final class Delegate: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) { OrganizerWindow.close() }
    }

    /// Mode capture : l'Organiser sur un écran d'exemple (sans écoute ni lien) ; « fermer » le ferme.
    static func showDemo(_ screen: String) {
        guard screen != "fermer" else {
            controller?.close()
            return
        }
        if panel == nil { open(start: false) }
        controller?.showDemo(screen)
    }

    /// Ouvre l'Organiser (ou le ramène devant). Fil principal.
    static func open(env: OrganizerEnvironment = .live(), start: Bool = true) {
        if let panel {
            panel.orderFrontRegardless()
            return
        }
        let controller = OrganizerController(env: env)
        controller.onClose = { OrganizerWindow.close() }
        let host = NSHostingView(rootView: OrganizerView(controller: controller))
        host.sizingOptions = []                                       // taille posée ici, à chaque étape
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: OrganizerView.width, height: 220),
                        styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.title = String(localized: "Organiser")
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        // Jamais la fenêtre active à la place de FL (audit : avec makeKey, FL perdait sa fenêtre active, ne disait plus
        // quelle page était devant, et ⌥↑ / F2 partaient dans le vide) ; un champ de texte la rend active au clic.
        p.becomesKeyOnlyIfNeeded = true
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.fullScreenAuxiliary]
        p.contentView = host
        p.delegate = delegate
        fit(p, host, animate: false)
        p.center()
        panel = p
        self.controller = controller
        // Nouvelle étape, ou aide dépliée / repliée : le panneau suit la hauteur du contenu.
        sizing = controller.$phase.map { _ in () }.merge(with: controller.$showLinkHelp.map { _ in () }).sink { _ in
            // Après le dessin de la nouvelle étape, puis une fois le fondu fini : pendant le fondu, l'ancienne étape
            // compte encore dans la hauteur (la fenêtre restait trop grande).
            for delay in [0.05, 0.85 * DebugSnapshot.slowMotion] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    guard let panel = OrganizerWindow.panel, panel === p else { return }
                    fit(p, host, animate: true)
                }
            }
        }
        p.orderFrontRegardless()
        if start { controller.start() }
    }

    /// Hauteur du contenu, le haut du panneau restant à sa place.
    private static func fit(_ panel: NSPanel, _ host: NSView, animate: Bool) {
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        var frame = panel.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        let old = panel.frame
        frame.origin = NSPoint(x: old.minX, y: old.maxY - frame.height)
        guard abs(frame.height - old.height) > 0.5 || abs(frame.width - old.width) > 0.5 else { return }
        panel.setFrame(frame, display: true, animate: animate && panel.isVisible && !Motion.reduce)
    }

    /// Pendant que l'Organiser clique dans FL (Playlist) : les clics traversent le panneau, qui flotte au-dessus de FL.
    static func clickThrough(_ on: Bool) {
        let set: () -> Void = { panel?.ignoresMouseEvents = on }
        if Thread.isMainThread { set() } else { DispatchQueue.main.sync(execute: set) }
    }

    /// Ferme et lâche tout ; l'écoute en cours s'arrête et FL est remis comme avant.
    static func close() {
        guard let p = panel else { return }
        let c = controller
        panel = nil
        controller = nil
        sizing = nil
        c?.close()
        p.delegate = nil
        p.orderOut(nil)
        p.contentView = nil
        CreatorPresence.releaseMemory()
    }
}

struct OrganizerView: View {
    static let width: CGFloat = 440
    /// Hauteur de l'aperçu (la liste des familles y défile).
    static let height: CGFloat = 600
    /// Couleur de l'Organiser (icône, fond, numéros des étapes).
    static let tint = Color.indigo

    @ObservedObject var controller: OrganizerController

    private var isPreview: Bool { controller.phase == .preview }

    /// Étape affichée : une nouvelle étape remplace l'ancienne en fondu (la progression de l'écoute, non).
    private var stepKey: String {
        switch controller.phase {
        case .starting: return "starting"
        case .setup: return "setup"
        case .waiting(let reason): return "waiting:\(reason)"
        case .listening: return "listening"
        case .preview: return "preview"
        case .applying: return "applying"
        case .applied: return "applied"
        case .undoing: return "undoing"
        case .undone: return "undone"
        case .failed(let message): return "failed:" + message
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            ZStack(alignment: .topLeading) {
                content
                    .id(stepKey)
                    .transition(Motion.pageMorph)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 22)
        .padding(.top, 34)                           // sous les boutons de la fenêtre
        .padding(.bottom, 20)
        .frame(width: Self.width, alignment: .top)
        .frame(height: isPreview ? Self.height : nil, alignment: .top)
        .fixedSize(horizontal: false, vertical: !isPreview)
        // Collé en haut, et le fond remplit toute la fenêtre : pendant qu'elle change de taille (Réessayer, étape
        // suivante), plus de bandes noires en haut et en bas (vidéo de l'utilisateur : le contenu se centrait).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { TintGlow(tint: Self.tint) }
        .motion(Motion.morph, value: stepKey)
    }

    private var header: some View {
        HStack(spacing: 14) {
            SectionIcon(symbol: "square.stack.3d.up", tint: Self.tint, size: 42)
                .shadow(color: Self.tint.opacity(0.35), radius: 12, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.title).font(.system(size: 18, weight: .bold))
                Text("Range, colore et renomme tout le projet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .morphIn(0)
    }

    private static func listeningText(_ done: Int, _ total: Int) -> String {
        total == 0 ? String(localized: "Préparation de l'analyse…") : String(localized: "Analyse du projet : \(min(done + 1, total)) sur \(total)")
    }

    @ViewBuilder private var content: some View {
        switch controller.phase {
        case .starting:
            working(String(localized: "Préparation…"))
        case .setup:
            setup
        case .waiting(let reason):
            waiting(reason)
        case .listening(let done, let total):
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    OrganizerBadge(symbol: "waveform", tint: Self.tint, live: true)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(Self.listeningText(done, total)).font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if total > 0 {
                                Text("\(Int((Double(done) / Double(max(total, 1)) * 100).rounded())) %")
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ProgressView(value: Double(done), total: Double(max(total, 1)))
                            .tint(Self.tint)
                            .motion(Motion.smooth, value: done)
                    }
                }
                .padding(14)
                .organizerCard()
                .morphIn(1)
                Text(String(localized: """
                    FL enregistre ton projet, puis FL Shortcuts lit son fichier : ce que joue chaque pattern et où est \
                    chaque clip, exactement (rien n'est deviné). Un son dont le nom dit ce qu'il est (Kick, 808, Hat…) \
                    est classé tout de suite ; les autres jouent seuls, à ton tempo, sans que tu les entendes. Ne \
                    touche pas à FL ; Échap arrête.
                    """))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .morphIn(2)
                HStack {
                    Spacer()
                    Button("Arrêter") { controller.close() }.keyboardShortcut(.cancelAction)
                }
                .morphIn(3)
            }
        case .preview:
            preview
        case .applying:
            working(controller.applyStep.map { $0 + " " + String(localized: "Ne touche pas à FL.") }
                ?? (controller.organizesCopy
                ? String(localized: "FL ouvre la copie rangée de ton projet, puis tout s'y range… Ne touche pas à FL.")
                : String(localized: "Application dans FL… Ne touche pas à FL.")))
        case .undoing:
            working(String(localized: "Retour comme avant…"))
        case .applied(let error):
            ending(error?.message ?? controller.doneText, ok: error == nil, linkHelp: error == .noResponse)
        case .undone(let error):
            ending(error?.message ?? (controller.lastApply?.copy != nil
                    ? String(localized: "Ton projet d'origine se rouvre dans FL, tel qu'il était. La copie rangée reste à côté, si tu la veux.")
                    : String(localized: "FL est revenu comme avant.")),
                   ok: error == nil, linkHelp: error == .noResponse)
        case .failed(let message):
            ending(message, ok: false, linkHelp: false)
        }
    }

    private func working(_ text: String) -> some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(text).font(.system(size: 13))
            Spacer(minLength: 0)
        }
        .padding(14)
        .organizerCard()
        .morphIn(1)
    }

    /// Fin d'une étape : le message dans une carte (coche verte ou triangle orange) ; FL muet : les réglages de FL
    /// à vérifier, étape par étape.
    private func ending(_ text: String, ok: Bool, linkHelp: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                OrganizerBadge(symbol: ok ? "checkmark" : "exclamationmark", tint: ok ? .green : .orange)
                Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .organizerCard(ok ? .green : .orange)
            .morphIn(1)
            if linkHelp {
                VStack(alignment: .leading, spacing: 8) {
                    OrganizerStep(n: 1, text: String(localized: """
                        Quitte et rouvre FL Studio : il trouve « FL Shortcuts Link » en démarrant \
                        et le relie tout seul. Puis « Réessayer ».
                        """))
                    OrganizerStep(n: 2, text: String(localized: """
                        Toujours rien : Options › MIDI Settings, entrée « FL Shortcuts Link », \
                        Controller type « FL Shortcuts » (pas « generic controller »), Enable, et le même \
                        numéro de Port à l'entrée et à la sortie. Dans Output, « FL Shortcuts Link » seul \
                        sur ce numéro : « FL Shortcuts » doit s'afficher à côté de lui, pas de ta carte son.
                        """))
                    OrganizerStep(n: 3, text: String(localized: """
                        « FL Shortcuts » absent des Controller types : FL ne lit pas le dossier du \
                        script ci-dessous. Compare-le avec Options › File settings › User data folder dans \
                        FL (pas sur iCloud) ; s'il diffère, « Autre dossier de FL… » et choisis celui-là.
                        """))
                    OrganizerStep(n: 4, text: String(localized: """
                        Réglages Système › Confidentialité et sécurité › Fichiers et dossiers › \
                        FL Studio : « Dossier Documents » doit être coché.
                        """))
                }
                scriptCard
                    .morphIn(6)
            }
            buttons
                .morphIn(linkHelp ? 7 : 2)
        }
    }

    /// Où est le script du lien, avec « Afficher dans le Finder » et « Autre dossier de FL… ».
    private var scriptCard: some View {
        let place = controller.scriptPlace
        let present = place?.present == true
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: present ? "doc.text.fill" : "questionmark.folder.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(present ? Self.tint : Color.orange)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(present ? String(localized: "Script du lien") : String(localized: "Script introuvable dans FL Studio"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(place.map { FLScriptInstaller.displayFolder(of: $0.url) } ?? String(localized: "Aucun dossier enregistré."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            HStack {
                if present {
                    Button("Afficher dans le Finder") { controller.revealScript() }
                }
                Button("Autre dossier de FL…") { controller.installLinkElsewhere() }
                Spacer(minLength: 0)
            }
            .controlSize(.small)
        }
        .padding(12)
        .organizerCard(present ? Self.tint : .orange)
    }

    /// « Copier le diagnostic » : un texte court à m'envoyer (aucun nom de son ni de piste).
    private var diagnosticButton: some View {
        Button(controller.copied ? String(localized: "Copié") : String(localized: "Copier le diagnostic")) {
            controller.copyDiagnostic()
        }
        .help(String(localized: """
            Copie un court texte technique (versions, autorisations, ce que l'écoute a reçu), sans aucun nom de \
            son ni de piste : colle-le dans ton message pour qu'on trouve ce qui bloque.
            """))
    }

    @ViewBuilder private var buttons: some View {
        HStack {
            if controller.canUndo {
                Button("Revenir comme avant") { controller.undo() }
            } else if case .failed = controller.phase {
                diagnosticButton
            } else if case .applied(let error) = controller.phase, error != nil {
                diagnosticButton
            }
            Spacer()
            if controller.canRetry {
                Button("Fermer") { controller.close() }.keyboardShortcut(.cancelAction)
                Button("Réessayer") { controller.retry() }
                    .primaryButton()
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Fermer") { controller.close() }
                    .primaryButton()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.top, 2)
    }

    /// Lien avec FL pas encore installé : un seul bouton, la suite se fait toute seule.
    private var setup: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                OrganizerBadge(symbol: "link", tint: Self.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Un petit lien avec FL, une seule fois").font(.system(size: 14, weight: .semibold))
                    Text(String(localized: """
                        Organiser parle à FL par un script que FL Shortcuts installe dans FL Studio. Ensuite, tout se \
                        fait seul.
                        """))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .organizerCard()
            .morphIn(1)
            HStack {
                Spacer()
                Button("Fermer") { controller.close() }.keyboardShortcut(.cancelAction)
                Button("Installer le lien") { controller.installLink() }
                    .primaryButton()
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
            .morphIn(2)
        }
    }

    /// En attente de FL : ce qu'il faut faire, en une phrase ; Organiser vérifie tout seul et continue dès que
    /// c'est bon (aucun bouton à toucher). FL muet : l'aide détaillée, repliée.
    private func waiting(_ reason: OrganizerController.Wait) -> some View {
        let text = Self.waitText(reason)
        let tint: Color = reason == .stopPlayback ? .orange : Self.tint
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                WaitingPulse(symbol: text.symbol, tint: tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(text.title).font(.system(size: 14, weight: .semibold))
                    Text(text.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .organizerCard(tint)
            .morphIn(1)
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini)
                Text("Organiser continue tout seul dès que FL est prêt.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .morphIn(2)
            if reason == .audioPermission {
                Button("Ouvrir les réglages") { controller.openAudioSettings() }
                    .controlSize(.large)
                    .morphIn(3)
            }
            if reason == .noResponse || reason == .restartFL || reason == .wrongInput {
                linkHelpToggle.morphIn(3)
                if controller.showLinkHelp {
                    linkHelpSteps
                        .transition(Motion.quickSwap)
                }
            }
            HStack {
                diagnosticButton
                Spacer()
                Button("Fermer") { controller.close() }.keyboardShortcut(.cancelAction)
                Button("Réessayer maintenant") { controller.retry() }
            }
            .padding(.top, 2)
            .morphIn(4)
        }
    }

    static func waitText(_ reason: OrganizerController.Wait) -> (symbol: String, title: String, detail: String) {
        switch reason {
        case .restartFL:
            return ("arrow.clockwise", String(localized: "Quitte et rouvre FL Studio"),
                    String(localized: "Le lien est prêt : FL le lit en démarrant et relie « FL Shortcuts Link » tout seul."))
        case .noResponse:
            return ("antenna.radiowaves.left.and.right", String(localized: "En attente de FL Studio"),
                    String(localized: """
                        FL ne répond pas encore. Dans FL › MIDI Settings › Output, « FL Shortcuts » doit s'afficher à côté \
                        de « FL Shortcuts Link », seul sur son Port. Sinon : « Ça ne marche toujours pas ? » ci-dessous.
                        """))
        case .wrongInput:
            return ("cable.connector", String(localized: "Le lien est sur la mauvaise entrée"),
                    String(localized: """
                        Dans FL : Options › MIDI Settings › Input, ta carte son (ou ton clavier) a le Controller type « FL \
                        Shortcuts ». Remets-la sur « (generic controller) », puis clique la ligne « FL Shortcuts Link » \
                        et choisis « FL Shortcuts ».
                        """))
        case .openFL:
            return ("macwindow", String(localized: "Ouvre FL Studio"),
                    String(localized: "Organiser commence dès que FL est ouvert, avec ton projet."))
        case .stopPlayback:
            return ("stop.fill", String(localized: "Arrête la lecture dans FL"),
                    String(localized: "Organiser écoute chaque son seul : FL doit être à l'arrêt."))
        case .audioPermission:
            return ("speaker.wave.2.fill", String(localized: "Autorise « Audio du système »"),
                    String(localized: """
                        Organiser écoute seulement le son de FL, sans l'enregistrer. Réglages Système › Confidentialité et \
                        sécurité › Enregistrement de l'écran et de l'audio du système : active FL Shortcuts dans « Audio \
                        du système uniquement ».
                        """))
        }
    }

    /// « Ça ne marche toujours pas ? » : les réglages de FL à vérifier, repliés tant qu'on ne les demande pas.
    private var linkHelpToggle: some View {
        Button {
            withAnimation(Motion.quickMorph) { controller.showLinkHelp.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(controller.showLinkHelp ? 90 : 0))
                Text("Ça ne marche toujours pas ?").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Self.tint)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var linkHelpSteps: some View {
        VStack(alignment: .leading, spacing: 8) {
            OrganizerStep(n: 1, text: String(localized: """
                Dans FL : Options › MIDI Settings › Input, clique d'abord la ligne « FL Shortcuts \
                Link » (le Controller type, en bas, change la ligne choisie), puis Controller type « FL \
                Shortcuts », Enable, Port 7. Ta carte son ou ton clavier MIDI restent sur « (generic \
                controller) ».
                """))
            OrganizerStep(n: 2, text: String(localized: """
                Dans Output : « FL Shortcuts Link » sur ce même Port 7, et SEUL sur ce numéro. \
                Clique ta carte son (SSL 2+…) et donne-lui un autre Port (8…) : FL répond à la première \
                sortie du numéro. C'est bon quand « FL Shortcuts » s'affiche à côté de « FL Shortcuts \
                Link » dans Output (pas à côté de ta carte son). Puis quitte et rouvre FL.
                """))
            OrganizerStep(n: 3, text: String(localized: """
                « FL Shortcuts » absent des Controller types : FL ne lit pas le dossier du \
                script ci-dessous. Compare-le avec Options › File settings › User data folder (pas sur \
                iCloud) ; s'il diffère, « Autre dossier de FL… » et choisis celui-là.
                """))
            OrganizerStep(n: 4, text: String(localized: """
                Réglages Système › Confidentialité et sécurité › Fichiers et dossiers › \
                FL Studio : « Dossier Documents » doit être coché.
                """))
            scriptCard
        }
    }

    private var hint: String {
        String(localized: """
            Chaque son est rangé d'après son nom (« BEAM KICK » : Kick), sinon d'après son écoute. Clique sur Kick, \
            808… pour le changer : tout le projet suit (Channel rack, patterns, Mixer, Playlist).
            """)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .morphIn(1)
            // Les familles (couleur ou dégradé de chacune), puis le résumé et les choix, dans la même zone qui défile :
            // le résumé, devenu long, écrasait les familles à une hauteur nulle (retour du propriétaire : les
            // couleurs n'étaient plus proposées). Seuls les boutons restent en bas.
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let colors = controller.plannedColors
                    ForEach(Array(controller.presentFamilies.enumerated()), id: \.element) { index, family in
                        FamilySection(controller: controller, family: family, colors: colors)
                            .morphIn(index + 2)
                    }
                    ProjectSummary(controller: controller)
                }
                // Place pour la carte survolée qui grandit et son ombre.
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            .padding(.horizontal, -4)
            HStack {
                Button("Annuler") { controller.close() }.keyboardShortcut(.cancelAction)
                diagnosticButton
                Spacer()
                Button("Organiser") { controller.apply() }
                    .primaryButton()
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Carte de l'Organiser, comme celles du guide : voile clair et liseré de sa couleur, qui s'épaissit au survol.
private struct OrganizerCard: View {
    var tint: Color = OrganizerView.tint
    var hovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.primary.opacity(hovered ? 0.085 : 0.045))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(hovered ? 0.6 : 0.24), lineWidth: hovered ? 1.5 : 1))
    }
}

/// Carte qui grandit un peu au survol avec son liseré, ombre douce de sa couleur (comme sur l'accueil du guide).
private struct OrganizerHoverCard: ViewModifier {
    let tint: Color
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(OrganizerCard(tint: tint, hovered: hovered))
            .scaleEffect(hovered && !reduceMotion ? 1.015 : 1)
            .shadow(color: tint.opacity(hovered ? 0.25 : 0), radius: hovered ? 12 : 0, y: hovered ? 4 : 0)
            .onHover { inside in
                withAnimation(reduceMotion ? Motion.reduced : Motion.lift) { hovered = inside }
            }
    }
}

private extension View {
    func organizerCard(_ tint: Color = OrganizerView.tint) -> some View { modifier(OrganizerHoverCard(tint: tint)) }
}

/// Attente de FL : la pastille de couleur et deux ondes qui s'en éloignent sans fin, comme un appel (rien ne tourne
/// une fois la fenêtre fermée). Mouvement réduit demandé : la pastille seule.
private struct WaitingPulse: View {
    let symbol: String
    let tint: Color
    @State private var going = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(0..<2, id: \.self) { i in
                    Circle()
                        .stroke(tint.opacity(0.45), lineWidth: 1.5)
                        .frame(width: 34, height: 34)
                        .scaleEffect(going ? 1.9 : 1)
                        .opacity(going ? 0 : 0.9)
                        .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(Double(i) * 0.8),
                                   value: going)
                }
            }
            OrganizerBadge(symbol: symbol, tint: tint)
        }
        .frame(width: 56, height: 56)
        .onAppear { going = true }
    }
}

/// Pastille ronde de couleur avec son symbole (résultat, écoute en cours : l'onde s'anime).
private struct OrganizerBadge: View {
    let symbol: String
    let tint: Color
    var live = false

    var body: some View {
        icon
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(width: 34, height: 34)
            .background(Circle().fill(tint.gradient))
            .shadow(color: tint.opacity(0.35), radius: 8, y: 3)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var icon: some View {
        if live {
            if #available(macOS 14.0, *) {
                Image(systemName: symbol).symbolEffect(.variableColor.iterative, options: .repeating)
            } else {
                Image(systemName: symbol)
            }
        } else {
            Image(systemName: symbol)
        }
    }
}

/// Une étape numérotée, dans une carte (comme les étapes du guide), qui apparaît à son tour.
private struct OrganizerStep: View {
    let n: Int
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(OrganizerView.tint.gradient))
                .accessibilityHidden(true)
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .organizerCard()
        .morphIn(n + 1)
    }
}

/// Ce que « Organiser » fera dans chaque page de FL, avec une case par page et une pour les noms.
private struct ProjectSummary: View {
    @ObservedObject var controller: OrganizerController

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(controller.summary.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: line.symbol)
                        .font(.system(size: 11))
                        .foregroundStyle(OrganizerView.tint)
                        .frame(width: 16)
                    Text(line.text)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 12) {
                Toggle("Channel rack", isOn: $controller.options.rack)
                Toggle("Patterns", isOn: $controller.options.patterns)
                Toggle("Mixer", isOn: $controller.options.mixer)
                Toggle("Playlist", isOn: $controller.options.playlist)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
            Toggle("Renommer simplement (Kick, Kick 2, 808…)", isOn: $controller.options.rename)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            Toggle("Un bus par famille dans le Mixer (les 808 avec les drums), chaque son envoyé seulement à son bus",
                   isOn: $controller.options.buses)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .disabled(!controller.options.mixer)
            Toggle(isOn: $controller.options.deleteUnused) {
                Text(controller.organizesCopy
                    ? String(localized: "Supprimer les sons sans aucune note de la copie rangée")
                    : String(localized: "Supprimer les sons sans aucune note (on ne peut pas les remettre)"))
            }
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            Text(controller.organizesCopy
                ? String(localized: """
                    Tout se range dans une nouvelle version de ton projet (« _2 », comme « Save new version » de FL), \
                    à côté de l'original : ton projet d'origine ne bouge pas, « Revenir comme avant » le rouvre. \
                    Aucune lecture de l'écran.
                    """)
                : String(localized: """
                    Les pistes de la Playlist sont remontées par leur menu (« Move up ») : FL Shortcuts lit alors la \
                    fenêtre de FL (autorisation « Enregistrement de l'écran »). Les patterns restent à leur place.
                    """))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .organizerCard()
    }
}

/// Une famille de l'aperçu : son réglage (une couleur ou un dégradé) et ses sons.
private struct FamilySection: View {
    @ObservedObject var controller: OrganizerController
    let family: SoundFamily
    let colors: [Int: RGBColor]
    @State private var pickingFirst = false
    @State private var pickingLast = false
    @State private var pickingIcon = false

    private var fadeOn: Binding<Bool> {
        Binding(get: { controller.style(of: family).fade != nil }, set: { on in
            controller.updateStyle(family) { style in
                style.fade = on ? GradientField.defaultLast(for: style.color) : nil
            }
        })
    }

    var body: some View {
        let style = controller.style(of: family)
        let members = controller.members(of: family)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: family.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(swiftColor(style.color).gradient))
                    .accessibilityHidden(true)
                Text(family.label).font(.system(size: 13, weight: .semibold))
                Text("\(members.count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.07)))
                Spacer()
                Picker("", selection: fadeOn) {
                    Text("Une couleur").tag(false)
                    Text("Dégradé").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
                swatch(style.color, picking: $pickingFirst) { picked in
                    controller.updateStyle(family) { $0.color = picked }
                }
                if let fade = style.fade {
                    swatch(fade, picking: $pickingLast) { picked in
                        controller.updateStyle(family) { $0.fade = picked }
                    }
                }
                Button { pickingIcon = true } label: { FLIconBadge(icon: style.icon, size: 18) }
                    .buttonStyle(.plain)
                    .help("Icône de FL de la famille, sur ses sons et ses pistes du Mixer (posée par la fenêtre de FL, F2 ; « Revenir comme avant » ne la retire pas)")
                    .popover(isPresented: $pickingIcon, arrowEdge: .bottom) {
                        FLIconPicker(selected: style.icon) { picked in
                            controller.updateStyle(family) { $0.icon = picked }
                            pickingIcon = false
                        }
                    }
            }
            ForEach(members) { member in
                row(member, color: colors[member.id] ?? style.color)
            }
        }
        .padding(12)
        .organizerCard(swiftColor(style.color))
    }

    private func row(_ member: OrganizerController.Member, color: RGBColor) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(swiftColor(color))
                .frame(width: 12, height: 12)
            Text(member.name.isEmpty ? String(localized: "(sans nom)") : member.name).lineLimit(1)
            if let newName = member.newName {
                Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(.secondary)
                Text(newName).lineLimit(1).foregroundStyle(.secondary)
            }
            if member.testNotes {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
                    .help("Muet dans ses patterns : classé avec deux notes d'essai. Vérifie sa famille.")
            }
            if member.byName {
                Image(systemName: "textformat")
                    .foregroundStyle(.secondary)
                    .help("Classé d'après son nom, sans l'écouter.")
            }
            Spacer()
            // Ce qu'est le son (« BEAM KICK » : Kick), sinon sa famille ; chaque famille propose ses sortes.
            Menu {
                ForEach(SoundFamily.order, id: \.self) { choice in
                    if choice.kinds.isEmpty {
                        Button(choice.label) { controller.setFamily(member.id, choice) }
                    } else {
                        Menu(choice.label) {
                            ForEach(choice.kinds, id: \.self) { kind in
                                Button(kind.name) { controller.setKind(member.id, kind) }
                            }
                        }
                    }
                }
            } label: {
                Text(member.kind?.name ?? family.label).font(.system(size: 11))
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .help("Changer ce qu'est ce son (Kick, 808, Lead…) ou sa famille")
        }
        .font(.system(size: 12))
    }

    private func swatch(_ color: RGBColor, picking: Binding<Bool>, set: @escaping (RGBColor) -> Void) -> some View {
        Button { picking.wrappedValue = true } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(swiftColor(color))
                .frame(width: 22, height: 16)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .help(String(localized: "#\(color.hex) : choisir dans la roue des couleurs de FL"))
        .popover(isPresented: picking, arrowEdge: .bottom) {
            FLColorSelector(initial: color) { picked in
                set(picked)
                picking.wrappedValue = false
            }
        }
    }
}
