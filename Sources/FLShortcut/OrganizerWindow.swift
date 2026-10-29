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
import UniformTypeIdentifiers

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
    /// Ordre des familles glissées dans l'aperçu, gardé d'un projet à l'autre.
    var loadFamilyOrder: () -> [SoundFamily] = { FamilyStyles.loadOrder() }
    var saveFamilyOrder: ([SoundFamily]) -> Void = { FamilyStyles.saveOrder($0) }
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
    var nameMelody: () -> OrganizerSession.NameMelody = { { _, _ in nil } }
    /// Sorte d'un son par l'IA intégrée (nil : aucune, les deux précédentes servent).
    var nameKind: () -> OrganizerSession.NameKind? = { nil }
    /// Ce que l'IA intégrée retient d'un son écouté (nil : aucune correction ne pourra en apprendre).
    var fingerprint: () -> OrganizerSession.Fingerprint? = { nil }
    /// Les corrections gardées sur le Mac (et l'accord pour les partager) ; nil : rien n'est appris.
    var corrections: () -> CorrectionsIA? = { nil }
    /// Une correction partagée (accord donné, JSON de CorrectionsIA.envoi) envoyée au serveur, en tâche de fond.
    var shareCorrection: (Data) -> Void = { _ in }
    /// « Pas content ? » : le message pour l'équipe et le diagnostic (nombres), envoyés en tâche de fond.
    var sendFeedback: (_ message: String, _ diagnostic: String) -> Void = { _, _ in }
    /// Fichier de son d'un clip audio lu directement (analyse sur le fichier) ; nil : joué dans FL.
    var soundFile: () -> OrganizerSession.SoundFile? = { nil }
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
    /// « Choisir le fichier… » : l'utilisateur montre le projet ouvert dans FL (fil principal) ; faux : annulé.
    var chooseProject: () -> Bool = { false }
    /// Une copie rangée faite et ouverte dans FL (original, copie) : à valider à la réouverture de FL Shortcuts ; puis
    /// « Revenir comme avant » réussi sur cette copie : elle part à la Corbeille (plus rien à demander). Fil principal.
    var copyMade: (_ original: URL, _ copy: URL) -> Void = { _, _ in }
    var copyUndone: (_ copy: URL) -> Void = { _ in }

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
            nameMelody: { OrganizerSession.liveMelodyNamer() },
            nameKind: { OrganizerSession.liveKindNamer() },
            fingerprint: { OrganizerSession.liveFingerprint() },
            corrections: { CorrectionsIA.shared },
            shareCorrection: { json in Task { @MainActor in await CommunityStore.shared.shareCorrection(json) } },
            sendFeedback: { message, diagnostic in
                Task { @MainActor in
                    _ = await CommunityStore.shared.sendSupport(
                        SupportMessage(kind: .probleme, text: message, diagnostic: diagnostic))
                }
            },
            soundFile: { SampleFiles.liveReader() },
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
            projectFiles: { ProjectFileLive.access() },
            chooseProject: {
                let panel = NSOpenPanel()
                panel.message = String(localized: "Choisis le fichier du projet ouvert dans FL Studio (.flp).")
                panel.allowedContentTypes = [UTType(filenameExtension: "flp") ?? .data]
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                NSApp.activate(ignoringOtherApps: true)
                guard panel.runModal() == .OK, let url = panel.url else { return false }
                ProjectFileLive.chosen = url
                return true
            },
            copyMade: { CopyApproval.shared.record(original: $0, copy: $1) },
            copyUndone: { CopyApproval.shared.discard(copy: $0) })
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
    /// Ce que « Organiser » fait : les pages de FL touchées, les noms, l'ordre des familles.
    @Published var options = OrganizerOptions()
    /// Noms écrits dans l'aperçu (« Écrire… », demande du propriétaire du 25/10), par index du canal.
    @Published var names: [Int: String] = [:]
    /// Piste du Mixer choisie pour un son dans l'aperçu (la case de FL), par index du canal ; absent : automatique.
    @Published var slots: [Int: Int] = [:]
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
    /// Le fichier du projet reste introuvable : « Choisir le fichier… » le fait montrer.
    @Published private(set) var projectMissing = false
    /// Sons corrigés que l'IA a retenus (aperçu et « Pas content ? »), dit à la fin.
    @Published private(set) var learned = 0
    /// « Pas content ? » ouvert, puis envoyé.
    @Published var feedbackShown = false
    @Published private(set) var feedbackSent = false

    init(env: OrganizerEnvironment) {
        self.env = env
        styles = env.loadStyles()
        options.familyOrder = OrganizerOptions.completeOrder(env.loadFamilyOrder())
    }

    /// Le nom du bouton, comme la maquette du 28/10.
    var title: String { String(localized: "Organiser") }

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
            link: link, audio: audio, classify: env.classify(), nameDrum: env.nameDrum(), nameMelody: env.nameMelody(),
            nameKind: env.nameKind(), fingerprint: env.fingerprint(), timing: env.timing,
            sleep: env.sleep, escape: env.escapePressed, prepare: env.prepareProject, files: env.projectFiles(),
            soundFile: env.soundFile(),
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
        projectMissing = false
        learned = 0
        feedbackSent = false
        result = nil
        families = [:]
        kinds = [:]
        names = [:]
        slots = [:]
        phase = .starting
        start()
    }

    /// « Choisir le fichier… » : le projet montré, l'analyse repart dessus.
    func chooseProject() {
        guard projectMissing, env.chooseProject() else { return }
        retry()
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
            projectMissing = error == .projectNotFound
            if let reason = Self.waitReason(for: error, wrongInput: env.wrongInput()) { wait(reason) } else { phase = .failed(error.message) }
        }
    }

    /// Ce que « Organiser » fera, d'après ce qu'est chaque son (modifiable) et les options.
    var plan: OrganizerPlan {
        guard let result else { return OrganizerPlan() }
        return OrganizerPlan.make(result, families: families, kinds: kinds, styles: styles, options: options,
                                  names: names, slots: slots)
    }

    /// Familles présentes, dans l'ordre choisi (au départ Voix, Mélodies, Basse, Drums, FX, À vérifier ; les familles
    /// absentes sont sautées).
    var presentFamilies: [SoundFamily] {
        let used = Set(families.values)
        return options.familyOrder.filter { used.contains($0) }
    }

    /// Une famille glissée sur une autre (comme un dossier) : elle prend sa place, l'autre se décale vers là d'où elle
    /// vient (glissée vers le bas : juste après elle ; vers le haut : juste avant). Tout le projet suit ce nouvel ordre.
    func moveFamily(_ family: SoundFamily, onto target: SoundFamily) {
        options.familyOrder = Self.moving(family, onto: target, in: options.familyOrder)
    }

    /// « Monter / Descendre la famille » : d'une famille présente vers le haut (-1) ou le bas (+1).
    func shiftFamily(_ family: SoundFamily, by step: Int) {
        let present = presentFamilies
        guard let at = present.firstIndex(of: family), present.indices.contains(at + step) else { return }
        moveFamily(family, onto: present[at + step])
    }

    /// Pur (testé) : l'ordre des familles après en avoir glissé une sur une autre.
    static func moving(_ family: SoundFamily, onto target: SoundFamily, in order: [SoundFamily]) -> [SoundFamily] {
        guard family != target, let from = order.firstIndex(of: family), let to = order.firstIndex(of: target) else {
            return order
        }
        var out = order
        out.remove(at: from)
        let place = out.firstIndex(of: target) ?? out.count
        out.insert(family, at: from < to ? place + 1 : place)
        return out
    }

    // MARK: Places dans le Mixer (demande du propriétaire du 25/10)

    /// Dernière piste du Mixer de ce projet (la toute dernière est « Current »).
    var mixerLast: Int { max(1, min((result?.mixer.count ?? 2) - 2, FamilyStyle.maxMixerTrack)) }

    /// La piste du Mixer où finira ce son (ce que montre sa case, comme dans le Channel rack de FL) ; nil : aucune
    /// (envoyé au Master sans piste libre).
    func mixerSlot(of index: Int, in plan: OrganizerPlan? = nil) -> Int? {
        guard let channel = result?.channels.first(where: { $0.index == index }) else { return nil }
        let mixer = (plan ?? self.plan).mixer
        let track = mixer.links[index] ?? channel.mixerTrack
        guard track >= 1 else { return nil }
        if let place = mixer.final.firstIndex(of: track) { return place + 1 }
        return track
    }

    /// Les pistes du Mixer où finira la famille (son bus compris ; la 808 avec les drums).
    func mixerRange(of family: SoundFamily, in plan: OrganizerPlan? = nil) -> ClosedRange<Int>? {
        let mixer = (plan ?? self.plan).mixer
        let places = mixer.final.enumerated().compactMap { place, track in
            mixer.verdicts[track]?.busFamily == family ? place + 1 : nil
        }
        guard let first = places.min(), let last = places.max() else { return nil }
        return first...last
    }

    func setSlot(_ index: Int, _ slot: Int?) {
        slots[index] = slot.map { min(max($0, 1), mixerLast) }
    }

    func setMixerStart(_ family: SoundFamily, _ start: Int?) {
        updateStyle(family) { $0.mixerStart = start.map { min(max($0, 1), self.mixerLast) } }
    }

    /// Le Mixer rangé tout seul de nouveau : plus aucune place choisie (sons et familles).
    func autoArrange() {
        slots = [:]
        for family in SoundFamily.order where style(of: family).mixerStart != nil {
            updateStyle(family) { $0.mixerStart = nil }
        }
    }

    var placesChosen: Bool {
        !slots.isEmpty || SoundFamily.order.contains { style(of: $0).mixerStart != nil }
    }

    /// « Écrire… » : le nom que la personne donne à ce son ; vide : le nom automatique.
    func setName(_ index: Int, _ name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespaces) ?? ""
        names[index] = trimmed.isEmpty ? nil : String(trimmed.prefix(64))
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
        /// La piste du Mixer où il finira (sa case) ; choisie à la main ; son nom écrit dans l'aperçu.
        var slot: Int? = nil
        var pinned = false
        var written = false
    }

    /// Sons d'une famille, dans l'ordre où ils finiront dans le Channel rack (les Kick ensemble, puis les Snare…).
    func members(of family: SoundFamily) -> [Member] {
        guard let result else { return [] }
        let channels = result.channels.sorted { $0.index < $1.index }
        let order = OrganizerApplier.rackPlan(channels, families: families, kinds: kinds, options: options).final
        var byIndex: [Int: OrganizerItem] = [:]
        for item in result.items { byIndex[item.index] = item }
        let plan = self.plan
        let planned = plan.rack.names
        return order.compactMap { index in
            guard families[index] == family, let item = byIndex[index] else { return nil }
            return Member(id: index, name: item.name, testNotes: item.testNotes, byName: item.byName,
                          newName: (names[index] ?? planned[index]).flatMap { $0 == item.name ? nil : $0 },
                          kind: kind(of: index), slot: mixerSlot(of: index, in: plan), pinned: slots[index] != nil,
                          written: names[index] != nil)
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
        let order = OrganizerApplier.rackPlan(channels, families: families, kinds: kinds, options: options).final
        return OrganizerApplier.plannedColors(families: families, styles: styles, order: order)
    }

    /// Analyse sur le fichier : tout se fait dans une copie rangée du projet (OrganizerProjectFile), Channel rack sur
    /// « All » ; sa Playlist n'est rangée que si « Playlist » est cochée.
    var organizesCopy: Bool { result?.project != nil }

    /// La Playlist rangée demanderait plus de pistes que FL n'en a : seul avertissement de l'aperçu (le résumé ligne
    /// par ligne et ses phrases sont retirés le 28/10 : « ça j'aime pas non plus »).
    var playlistTooBig: Bool { organizesCopy && options.playlist && plan.layout == nil }

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
            lines = [String(localized: "C'est fait : ton projet est rangé, coloré et renommé dans une copie, « \(copy.lastPathComponent) », à côté de l'original. L'original n'a pas bougé : « Revenir comme avant » le rouvre et met la copie à la Corbeille.")]
            if lastApply?.copyNotSaved == true {
                lines.append(String(localized: "FL n'a pas enregistré la copie rangée : enregistre-la dans FL (⌘S)."))
            }
            lines.append(String(localized: "Une fois l'Organiser fermé, FL Shortcuts te demandera si tu valides cette version : « Valider » met ton projet d'origine à la Corbeille et lui donne son nom, « Retourner en arrière » la supprime et rouvre ton projet d'avant."))
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
        if learned > 0 {
            lines.append(String(localized: """
                L'IA retient \(learned) sons corrigés sur ce Mac : la prochaine fois, ils seront rangés comme tu l'as dit.
                """))
        }
        if feedbackSent {
            lines.append(String(localized: """
                Merci ! Pour ranger ce projet avec tes corrections : « Revenir comme avant », puis relance Organiser.
                """))
        }
        return lines.joined(separator: "\n")
    }

    func apply() {
        guard phase == .preview, let result, let link else { return }
        env.saveStyles(styles)
        env.saveFamilyOrder(options.familyOrder)
        // Les sons changés dans l'aperçu : l'IA s'en souvient (demande du propriétaire), sans rien demander.
        learned = learn(OrganizerFeedback.previewFixes(result.items, families: families, kinds: kinds),
                        reasons: ["apercu"])
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
                if let made = OrganizerController.madeCopy(outcome) { self?.env.copyMade(made.original, made.copy) }
            }
        }
    }

    /// La copie rangée faite et ouverte dans FL, avec son original (même si la suite s'est arrêtée en route : la
    /// Playlist y est rangée, l'utilisateur dira s'il la garde).
    static func madeCopy(_ outcome: ApplyOutcome) -> (original: URL, copy: URL)? {
        guard let copy = outcome.copy, let original = outcome.snapshot.original else { return nil }
        return (original, copy)
    }

    // MARK: L'IA apprend de ses erreurs

    /// Sons écoutés que l'on peut corriger (ceux classés d'après leur nom n'ont pas été écoutés).
    var correctable: [OrganizerItem] { (result?.items ?? []).filter { $0.soundPrint != nil } }

    /// « Pas content ? » : après l'application, une fois.
    var canGiveFeedback: Bool {
        guard case .applied = phase, result != nil else { return false }
        return !feedbackSent
    }

    /// L'accord déjà donné pour aider l'IA de tout le monde.
    var sharingCorrections: Bool { env.corrections()?.partage == true }

    /// Chaque son corrigé retenu sur le Mac et, avec l'accord, partagé (des nombres seulement) ; le nombre retenu.
    private func learn(_ fixes: [Int: OrganizerFeedback.Fix], reasons: [String]) -> Int {
        guard !fixes.isEmpty, let store = env.corrections(), let result else { return 0 }
        var count = 0
        for item in result.items {
            guard let fix = fixes[item.index], fix.family != .unsure, let heard = item.soundPrint else { continue }
            store.ajoute(CorrectionIA(empreinte: heard.empreinte, famille: fix.family, sorte: fix.kind, date: Date()))
            count += 1
            if store.partage == true,
               let corps = CorrectionsIA.envoi(heard, avant: (item.family, item.kind), apres: (fix.family, fix.kind),
                                               raisons: reasons, appVersion: MacroFileActions.appVersion),
               let json = try? JSONSerialization.data(withJSONObject: corps) {
                env.shareCorrection(json)
            }
        }
        return count
    }

    /// « Envoyer » : les sons corrigés retenus (et partagés si la case est cochée), le reste dit à l'équipe.
    func submitFeedback(_ feedback: OrganizerFeedback) {
        if !feedback.fixes.isEmpty { env.corrections()?.partage = feedback.share }
        learned += learn(feedback.fixes, reasons: feedback.reasons.map(\.rawValue).sorted())
        if let message = feedback.teamMessage() { env.sendFeedback(message, diagnosticText) }
        feedbackSent = true
        feedbackShown = false
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
                if outcome.error == nil, snapshot.original != nil, let copy = self?.lastApply?.copy {
                    self?.env.copyUndone(copy)
                }
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
/// les boutons de fenêtre, déplaçable par le fond) ; redimensionnable (retour du propriétaire). Sa hauteur suit son
/// contenu, mesuré à chaque changement (un message court : un petit panneau, même juste après l'aperçu) ; l'aperçu
/// prend la hauteur que l'utilisateur lui a donnée (600 la première fois), sa liste défile. Retour du 25/10 (« quand
/// on la rétrécit et l'agrandit ») : hors aperçu, seule la largeur se tire (la hauteur est celle du contenu : rien de
/// coupé en bas, aucun vide) ; l'aperçu se tire aussi en hauteur, jamais sous `previewMinHeight` ; la largeur reste
/// entre `OrganizerView.width` et `maxWidth` (au-delà, les cartes s'étiraient sans fin).
enum OrganizerWindow {
    private static var panel: NSPanel?
    /// Le contrôleur affiché (nil quand la fenêtre est fermée).
    private(set) static var controller: OrganizerController?
    private static let delegate = Delegate()
    /// Hauteur de l'aperçu, gardée quand l'utilisateur tire la fenêtre (pour la session de l'app).
    private static var previewHeight = OrganizerView.height
    /// L'aperçu est affiché (sa hauteur ne suit pas le contenu).
    private static var showingPreview = false
    /// Hauteur mesurée avant que le panneau existe.
    private static var pending: (height: CGFloat, preview: Bool)?
    /// Bornes de la fenêtre : la plus petite hauteur d'une étape, celle de l'aperçu (texte, liste, boutons sans se
    /// chevaucher), la plus grande largeur.
    static let minHeight: CGFloat = 160
    static let previewMinHeight: CGFloat = 420
    static let maxWidth: CGFloat = 760
    /// Largeur donnée à l'aperçu à son arrivée : les familles sur deux colonnes (maquette du 28/10).
    static let previewWidth: CGFloat = 720

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
                        styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.contentMinSize = NSSize(width: OrganizerView.width, height: minHeight)
        p.contentMaxSize = NSSize(width: maxWidth, height: .greatestFiniteMagnitude)
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
        showingPreview = false
        panel = p
        self.controller = controller
        host.layoutSubtreeIfNeeded()
        if let first = pending {
            pending = nil
            adapt(height: first.height, preview: first.preview)
        }
        p.center()
        p.orderFrontRegardless()
        if start { controller.start() }
    }

    /// Hauteur demandée par le contenu (`OrganizerView`, à chaque changement : nouvelle étape, fondu fini, aide
    /// dépliée, texte de l'application), le haut du panneau restant à sa place et la largeur choisie gardée. Pendant
    /// l'aperçu, la fenêtre garde la hauteur que l'utilisateur lui donne ; elle est reprise au prochain aperçu.
    static func adapt(height: CGFloat, preview: Bool) {
        guard height > 0 else { return }
        guard let panel else {
            pending = (height, preview)
            return
        }
        let content = panel.contentRect(forFrameRect: panel.frame)
        if showingPreview && !preview { previewHeight = content.height }
        let entering = preview && !showingPreview
        showingPreview = preview
        let screen = (panel.screen ?? NSScreen.main)?.visibleFrame
        let tallest = screen.map { $0.height - 40 } ?? .greatestFiniteMagnitude
        if preview {
            // L'aperçu se tire en hauteur, sans descendre sous ce qu'il lui faut.
            panel.contentMinSize = NSSize(width: OrganizerView.width, height: min(previewMinHeight, tallest))
            panel.contentMaxSize = NSSize(width: maxWidth, height: .greatestFiniteMagnitude)
            if !entering { return }
        }
        var target = preview ? max(previewHeight, previewMinHeight) : height
        target = max(min(target, tallest), minHeight)
        // L'aperçu arrive assez large pour deux colonnes de familles (sans dépasser l'écran) ; la largeur choisie
        // ensuite par l'utilisateur est gardée.
        let widest = screen.map { $0.width - 40 } ?? maxWidth
        let width = entering ? min(max(content.width, previewWidth), widest) : content.width
        if !preview {
            // Les autres étapes : la hauteur de leur contenu, fixe ; seule la largeur se tire.
            panel.contentMinSize = NSSize(width: OrganizerView.width, height: min(target, content.height))
            panel.contentMaxSize = NSSize(width: maxWidth, height: max(target, content.height))
        }
        guard abs(target - content.height) > 0.5 || abs(width - content.width) > 0.5 else {
            if !preview { pin(panel, height: target) }
            return
        }
        var frame = panel.frameRect(forContentRect: NSRect(x: 0, y: 0, width: width, height: target))
        frame.origin = NSPoint(x: panel.frame.minX, y: panel.frame.maxY - frame.height)
        if let screen {                                              // jamais sous le bas de l'écran
            frame.origin.y = max(frame.origin.y, screen.minY)
            if frame.maxY > screen.maxY { frame.origin.y = screen.maxY - frame.height }
        }
        panel.setFrame(frame, display: true, animate: panel.isVisible && !Motion.reduce)
        if !preview { pin(panel, height: target) }
    }

    /// Hauteur d'une étape fixée (après le changement de taille, qui doit pouvoir passer d'une hauteur à l'autre).
    private static func pin(_ panel: NSPanel, height: CGFloat) {
        panel.contentMinSize = NSSize(width: OrganizerView.width, height: height)
        panel.contentMaxSize = NSSize(width: maxWidth, height: height)
    }

    /// Depuis la vue : après sa mise à jour (la fenêtre ne change pas de taille au milieu d'un dessin de SwiftUI).
    static func contentChanged(height: CGFloat, preview: Bool) {
        DispatchQueue.main.async { adapt(height: height, preview: preview) }
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
        showingPreview = false
        pending = nil
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

    /// Pendant l'application : l'étape en cours (« FL ouvre la copie rangée… 12 s »), sinon le texte général.
    private var applyingText: String {
        let hands = String(localized: "Ne touche pas à FL.")
        if let step = controller.applyStep { return step + " " + hands }
        if controller.organizesCopy {
            return String(localized: "FL ouvre la copie rangée de ton projet, puis tout s'y range… Ne touche pas à FL.")
        }
        return String(localized: "Application dans FL… Ne touche pas à FL.")
    }

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
        // La largeur de la fenêtre (que l'utilisateur peut tirer) ; l'aperçu remplit sa hauteur, les autres étapes
        // demandent la leur.
        .frame(minWidth: Self.width, maxWidth: .infinity, alignment: .top)
        .frame(maxHeight: isPreview ? .infinity : nil, alignment: .top)
        .fixedSize(horizontal: false, vertical: !isPreview)
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { OrganizerWindow.contentChanged(height: geo.size.height, preview: isPreview) }
                .onChange(of: geo.size.height) { OrganizerWindow.contentChanged(height: $0, preview: isPreview) }
                .onChange(of: isPreview) { OrganizerWindow.contentChanged(height: geo.size.height, preview: $0) }
        })
        // Collé en haut, et le fond remplit toute la fenêtre : pendant qu'elle change de taille (Réessayer, étape
        // suivante), plus de bandes noires en haut et en bas (vidéo de l'utilisateur : le contenu se centrait).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Plus de lueur de couleur dans le fond (28/10, « pas de fond »).
        .motion(Motion.morph, value: stepKey)
        .sheet(isPresented: $controller.feedbackShown) { OrganizerFeedbackView(controller: controller) }
    }

    /// Le titre seul (maquette validée le 28/10 : ni grande icône, ni phrase dessous).
    private var header: some View {
        HStack(spacing: 10) {
            Text(controller.title).font(.system(size: 20, weight: .bold))
            Spacer()
            if isPreview {
                // Maquette du 28/10 : « Rangement automatique » à droite du titre ; les choix et le diagnostic sont
                // rangés dans « Options ».
                if controller.options.mixer {
                    Button("Rangement automatique") { withAnimation(Motion.quickMorph) { controller.autoArrange() } }
                        .secondaryButton()
                        .disabled(!controller.placesChosen)
                        .help("Oublie les places choisies : chaque famille à la suite, dans l'ordre du Channel rack")
                }
                OrganizerOptionsMenu(controller: controller)
            }
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
                // Plus d'explication (28/10, « ça j'aime pas ») : la consigne seule.
                Text(String(localized: "Ne touche pas à FL."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
            working(applyingText)
        case .undoing:
            working(String(localized: "Retour comme avant…"))
        case .applied(let error):
            ending(error?.message ?? controller.doneText, ok: error == nil, linkHelp: error == .noResponse)
        case .undone(let error):
            ending(error?.message ?? (controller.lastApply?.copy != nil
                    ? String(localized: "Ton projet d'origine se rouvre dans FL, tel qu'il était. La copie rangée part à la Corbeille dès que FL l'a quittée.")
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
                linkHelpSteps
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
            if controller.canGiveFeedback {
                Button("Pas content ?") { controller.feedbackShown = true }
                    .help("Dis ce qui n'allait pas : l'IA apprend de ses erreurs")
            }
            Spacer()
            if controller.canRetry && controller.projectMissing {
                Button("Fermer") { controller.close() }.keyboardShortcut(.cancelAction)
                Button("Réessayer") { controller.retry() }
                Button("Choisir le fichier…") { controller.chooseProject() }
                    .primaryButton()
                    .keyboardShortcut(.defaultAction)
            } else if controller.canRetry {
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
                Text("Un petit lien avec FL, une seule fois").font(.system(size: 14, weight: .semibold))
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

    /// Relier FL (29/10, « beaucoup plus simple et mieux expliqué ») : les quatre étapes de `LinkGuide` et la fenêtre
    /// MIDI Settings entourée ; dessous, les trois pièges déjà vus, une ligne chacun, puis où est le script.
    private var linkHelpSteps: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(LinkGuide.steps.enumerated()), id: \.offset) { index, text in
                        OrganizerStep(n: index + 1, text: text)
                    }
                }
                MIDISettingsImage(width: 170)
                    .morphIn(2)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Toujours rien ?").font(.system(size: 12, weight: .semibold))
                Text("Ta carte son : un autre numéro de Port.")
                Text("Pas de « FL Shortcuts » dans Controller type : vérifie le dossier ci-dessous.")
                Text("Réglages Système › Fichiers et dossiers › FL Studio : coche « Dossier Documents ».")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .morphIn(6)
            scriptCard
                .morphIn(6)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Maquette du 28/10 : les familles sur deux colonnes dès que la fenêtre est assez large ; chacune, son
            // en-tête (poignée, couleur, nom, départ dans le Mixer), puis ses sons dans une carte de verre.
            GeometryReader { geo in
                ScrollView {
                    let colors = controller.plannedColors
                    let families = controller.presentFamilies
                    let columns = OrganizerView.familyColumns(families, count: geo.size.width >= 600 ? 2 : 1) {
                        controller.members(of: $0).count
                    }
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(column, id: \.self) { family in
                                    FamilySection(controller: controller, family: family, colors: colors)
                                        .morphIn((families.firstIndex(of: family) ?? 0) + 1)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(minHeight: 120)                       // fenêtre rétrécie : la liste défile, jamais écrasée
            if controller.playlistTooBig {
                Label(String(localized: "Playlist trop grande pour FL : décoche « Playlist »."),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Spacer()
                Button("Annuler") { controller.close() }
                    .secondaryButton()
                    .keyboardShortcut(.cancelAction)
                Button("Organiser") { controller.apply() }
                    .buttonStyle(AlwaysBlueButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
        }
    }

    /// Pur (testé) : les familles en `count` colonnes, dans l'ordre (la première colonne de haut en bas, puis la
    /// suivante), coupées là où les colonnes ont la hauteur la plus proche (`size` : nombre de sons d'une famille).
    static func familyColumns<F>(_ families: [F], count: Int, size: (F) -> Int) -> [[F]] {
        guard count >= 2, families.count >= 2 else { return [families] }
        let heights = families.map { size($0) + 2 }                  // l'en-tête compte pour deux lignes
        let total = heights.reduce(0, +)
        var best = 1
        var bestGap = Int.max
        var running = 0
        for cut in 1..<families.count {
            running += heights[cut - 1]
            let gap = abs(total - 2 * running)
            if gap < bestGap { best = cut; bestGap = gap }
        }
        return [Array(families[..<best]), Array(families[best...])]
    }
}

/// Bouton principal de l'Organiser, toujours bleu : le panneau ne devient jamais la fenêtre active (FL reste devant),
/// et le bouton du système y paraissait gris, comme désactivé (vidéo du 29/10).
private struct AlwaysBlueButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 20)
            .frame(height: 34)
            .background(Capsule().fill(Color.accentColor))
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .contentShape(Capsule())
    }
}

/// « Options » de l'aperçu (maquette du 28/10 : rien autour des familles) : les pages de FL à ranger, les noms, les
/// bus, les sons sans note, et le diagnostic à copier.
private struct OrganizerOptionsMenu: View {
    @ObservedObject var controller: OrganizerController

    var body: some View {
        Menu {
            Toggle("Channel rack", isOn: $controller.options.rack)
            Toggle("Patterns", isOn: $controller.options.patterns)
            Toggle("Mixer", isOn: $controller.options.mixer)
            Toggle("Playlist", isOn: $controller.options.playlist)
            Divider()
            Toggle("Renommer", isOn: $controller.options.rename)
            Toggle("Un bus par famille", isOn: $controller.options.buses)
                .disabled(!controller.options.mixer)
            Toggle(isOn: $controller.options.deleteUnused) {
                Text(controller.organizesCopy
                    ? String(localized: "Supprimer les sons sans note")
                    : String(localized: "Supprimer les sons sans note (définitif)"))
            }
            Divider()
            Button(controller.copied ? String(localized: "Copié") : String(localized: "Copier le diagnostic")) {
                controller.copyDiagnostic()
            }
        } label: {
            Text("Options")
        }
        .menuStyle(.button)
        .secondaryButton()
        .fixedSize()
        .help("Ce que l'Organiser range, et le diagnostic à copier pour l'équipe")
    }
}

/// Carte de l'Organiser : plaque de verre (28/10, « le verre seulement devant ») ; sans l'effet, le voile clair et le
/// liseré de sa couleur. Pas de survol : une carte n'est pas une option (29/10, le survol remplit l'option de sa
/// couleur).
private struct OrganizerCard: View {
    var tint: Color = OrganizerView.tint
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Appearance.glassKey) private var glassEnabled = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if GlassPlate.on(glass: glassEnabled, reduceTransparency: reduceTransparency,
                         increasedContrast: contrast == .increased) {
            shape.fill(GlassPlate.fill(scheme))
                .overlay(shape.strokeBorder(GlassPlate.rim(scheme), lineWidth: 1))
        } else {
            shape.fill(Color.primary.opacity(0.045))
                .overlay(shape.strokeBorder(tint.opacity(0.24), lineWidth: 1))
        }
    }
}

private extension View {
    func organizerCard(_ tint: Color = OrganizerView.tint) -> some View { background(OrganizerCard(tint: tint)) }
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

/// Une famille de l'aperçu : son réglage (une couleur ou un dégradé, son départ dans le Mixer) et ses sons. Elle se
/// glisse au-dessus ou en dessous d'une autre par sa poignée, comme un dossier (demande du propriétaire du 25/10).
private struct FamilySection: View {
    @ObservedObject var controller: OrganizerController
    let family: SoundFamily
    let colors: [Int: RGBColor]
    @State private var pickingFirst = false
    @State private var pickingLast = false
    @State private var pickingIcon = false
    @State private var dropTarget = false

    /// Ce qui est glissé : une famille de l'aperçu (jamais pris pour autre chose).
    static let dragPrefix = "organiser-famille:"

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
            // En-tête au-dessus de la carte (maquette du 28/10) : poignée, couleur, nom, départ dans le Mixer, icône.
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 24)
                    .contentShape(Rectangle())
                    .onDrag { NSItemProvider(object: (Self.dragPrefix + family.rawValue) as NSString) }
                    .help("Glisse la famille au-dessus ou en dessous d'une autre : le Channel rack, le Mixer et la Playlist suivent cet ordre")
                // Sa couleur (et la fin de son dégradé) : un rond qu'on clique ; « Une couleur / Dégradé » est dans
                // la fenêtre du premier rond (maquette du 28/10 : tout ce qui se change, sans rien autour).
                swatch(style.color, picking: $pickingFirst, withFade: true) { picked in
                    controller.updateStyle(family) { $0.color = picked }
                }
                if let fade = style.fade {
                    swatch(fade, picking: $pickingLast) { picked in
                        controller.updateStyle(family) { $0.fade = picked }
                    }
                }
                // Jamais coupé en deux lignes (capture du 25/10 : « Melodie / s »).
                Text(family.label).font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                if controller.options.mixer, let range = controller.mixerRange(of: family) {
                    Text("Mixer").font(.system(size: 12)).foregroundStyle(.secondary)
                    MixerSlotBox(value: style.mixerStart ?? range.lowerBound, chosen: style.mixerStart != nil,
                                 last: controller.mixerLast, tint: swiftColor(style.color)) {
                        controller.setMixerStart(family, $0)
                    }
                    .help("Première piste du Mixer de la famille (son bus compris ; la 808 avec les drums) : tire vers le haut ou le bas comme dans FL, ou clique pour l'écrire")
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
            .padding(.horizontal, 4)
            .frame(minHeight: 32)
            // Ses sons, dans une carte de verre, séparés par un trait fin.
            VStack(spacing: 0) {
                ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                    if index > 0 { Divider() }
                    FamilyMemberRow(controller: controller, family: family, member: member,
                                    color: colors[member.id] ?? style.color)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .organizerCard(swiftColor(style.color))
        }
        .overlay(alignment: .top) {
            if dropTarget {
                Capsule().fill(OrganizerView.tint).frame(height: 3).padding(.horizontal, 10).offset(y: -6)
            }
        }
        .onDrop(of: [.plainText], isTargeted: $dropTarget) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let text = (object as? NSString).map({ $0 as String }), text.hasPrefix(Self.dragPrefix),
                      let dragged = SoundFamily(rawValue: String(text.dropFirst(Self.dragPrefix.count))) else { return }
                DispatchQueue.main.async {
                    withAnimation(Motion.quickMorph) { controller.moveFamily(dragged, onto: family) }
                }
            }
            return true
        }
        .contextMenu {
            Button("Monter la famille") { withAnimation(Motion.quickMorph) { controller.shiftFamily(family, by: -1) } }
            Button("Descendre la famille") { withAnimation(Motion.quickMorph) { controller.shiftFamily(family, by: 1) } }
        }
    }

    /// Un rond de couleur : la roue des couleurs de FL s'ouvre au clic. `withFade` : au-dessus de la roue, le choix
    /// « Une couleur / Dégradé » de la famille.
    private func swatch(_ color: RGBColor, picking: Binding<Bool>, withFade: Bool = false,
                        set: @escaping (RGBColor) -> Void) -> some View {
        Button { picking.wrappedValue = true } label: {
            Circle()
                .fill(swiftColor(color))
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .help(String(localized: "#\(color.hex) : choisir dans la roue des couleurs de FL"))
        .popover(isPresented: picking, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                if withFade {
                    Picker("", selection: fadeOn) {
                        Text("Une couleur").tag(false)
                        Text("Dégradé").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .padding([.horizontal, .top], 12)
                }
                FLColorSelector(initial: color) { picked in
                    set(picked)
                    picking.wrappedValue = false
                }
            }
        }
    }
}

/// Un son de l'aperçu : sa couleur, son nom (et celui qu'il prendra), sa piste du Mixer (la case de FL) et ce qu'il est
/// (« Écrire… » : son nom tapé à la main, à la place de « À vérifier », demande du propriétaire du 25/10).
private struct FamilyMemberRow: View {
    @ObservedObject var controller: OrganizerController
    let family: SoundFamily
    let member: OrganizerController.Member
    let color: RGBColor
    @State private var writing = false
    @State private var draft = ""

    var body: some View {
        HStack(spacing: 8) {
            // Son nom d'origine → le nom qu'il prendra (28/10 : « le nom qui passe d'un nom à un autre ») ; le nouveau
            // nom dans sa case, qui s'ouvre sur ce qu'est le son et « Écrire… » (maquette du 28/10).
            Text(member.name.isEmpty ? String(localized: "(sans nom)") : member.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 150, alignment: .leading)
            if member.testNotes {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
                    .help("Muet dans ses patterns : classé avec deux notes d'essai. Vérifie sa famille.")
            }
            Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            Menu {
                ForEach(SoundFamily.order.filter { !$0.kinds.isEmpty }, id: \.self) { choice in
                    Menu(choice.label) {
                        ForEach(choice.kinds, id: \.self) { kind in
                            Button(kind.name) { controller.setKind(member.id, kind) }
                        }
                    }
                }
                Divider()
                Button("Écrire…") {
                    draft = controller.names[member.id] ?? ""
                    writing = true
                }
                if member.written {
                    Button("Nom automatique") { controller.setName(member.id, nil) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(member.newName ?? member.kind?.name ?? family.label)
                        .lineLimit(1)
                        .foregroundStyle(Color.primary)
                    Spacer(minLength: 2)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help("Changer ce qu'est ce son (Kick, 808, Lead…), ou écrire son nom")
            .popover(isPresented: $writing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nom du son").font(.system(size: 12, weight: .semibold))
                    TextField(String(localized: "Écris le nom que tu veux"), text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onSubmit(save)
                    HStack {
                        Spacer()
                        Button("Annuler") { writing = false }.keyboardShortcut(.cancelAction)
                        Button("OK", action: save).keyboardShortcut(.defaultAction)
                    }
                }
                .padding(14)
            }
            // La case du Mixer tout à droite, alignée d'un son à l'autre.
            if controller.options.mixer, member.slot != nil || member.pinned {
                MixerSlotBox(value: member.slot, chosen: member.pinned, last: controller.mixerLast,
                             tint: swiftColor(color)) {
                    controller.setSlot(member.id, $0)
                }
                .help("Piste du Mixer de ce son : tire vers le haut ou le bas comme dans FL, ou clique pour l'écrire")
            }
        }
        .font(.system(size: 13))
        .frame(minHeight: 38)
    }

    private func save() {
        controller.setName(member.id, draft)
        writing = false
    }
}

/// La case du numéro de piste du Mixer, comme celle du Channel rack de FL (vidéo du propriétaire) : on la tire vers le
/// haut ou le bas pour changer le numéro, ou on clique pour l'écrire ; ⌥ + clic : automatique. Un numéro choisi est
/// clair, un numéro automatique est gris ; « --- » : aucune piste.
struct MixerSlotBox: View {
    let value: Int?
    /// Choisi à la main (sinon : la place automatique).
    let chosen: Bool
    let last: Int
    /// Couleur du bord d'un numéro choisi (celle de la famille).
    var tint: Color = OrganizerView.tint
    /// nil : automatique.
    let set: (Int?) -> Void
    @State private var dragStart: Int?
    @State private var typing = false
    @State private var draft = ""
    @State private var hovered = false
    /// Pendant qu'on tire, comme la case de FL (vidéo du 29/10 : la flèche restait sur le chiffre) : la flèche est
    /// cachée et garée à droite de la case, le chiffre reste visible ; au lâcher, elle revient où elle était.
    @State private var hiddenDrag: HiddenDrag?

    /// Points de souris par numéro, comme la case de FL (tirer vers le haut : plus grand).
    static let step: CGFloat = 6
    static let width: CGFloat = 40

    var body: some View {
        // Un peu plus grande qu'avant (28/10) : c'est ce qu'on change le plus dans l'aperçu.
        Text(verbatim: value.map { String($0) } ?? "---")
            .font(.system(size: 12, weight: chosen ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(chosen ? Color.primary : Color.secondary)
            .frame(width: Self.width, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.28)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(chosen ? tint : Color.primary.opacity(hovered ? 0.35 : 0.12), lineWidth: 1))
            .contentShape(Rectangle())
            .onHover { inside in
                hovered = inside
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { drag in
                    guard dragStart == nil else { return }       // la suite arrive par `HiddenDrag` (souris garée)
                    let from = value ?? 1
                    dragStart = from
                    set(Self.dragged(from: from, dy: drag.translation.height, last: last))
                    hiddenDrag = HiddenDrag(localX: drag.startLocation.x, width: Self.width,
                                            already: drag.translation.height) { dy in
                        set(Self.dragged(from: from, dy: dy, last: last))
                    }
                }
                .onEnded { _ in
                    hiddenDrag?.finish()
                    hiddenDrag = nil
                    dragStart = nil
                })
            .onDisappear {
                hiddenDrag?.finish()
                hiddenDrag = nil
            }
            .onTapGesture {
                if NSEvent.modifierFlags.contains(.option) {
                    set(nil)
                } else {
                    draft = value.map { "\($0)" } ?? ""
                    typing = true
                }
            }
            .popover(isPresented: $typing, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Piste du Mixer").font(.system(size: 12, weight: .semibold))
                    TextField(String("1…\(last)"), text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .onSubmit(save)
                    HStack {
                        Button("Automatique") {
                            set(nil)
                            typing = false
                        }
                        Spacer()
                        Button("OK", action: save).keyboardShortcut(.defaultAction)
                    }
                }
                .padding(14)
            }
    }

    private func save() {
        if let n = Int(draft.trimmingCharacters(in: .whitespaces)) { set(min(max(n, 1), last)) }
        typing = false
    }

    /// Pur (testé) : le numéro après avoir tiré la case de `dy` points (vers le haut : négatif, plus grand).
    static func dragged(from: Int, dy: CGFloat, last: Int) -> Int {
        min(max(from + Int((-dy / step).rounded(.towardZero)), 1), max(last, 1))
    }
}

/// Glisser d'une case comme dans FL : la flèche disparaît, garée à droite de la case (elle ne couvre plus le chiffre
/// même si macOS la laisse visible, FL étant devant) ; la souris continue de compter (mouvements reçus tels quels) ;
/// au lâcher, la flèche revient exactement où elle était. Aucune autorisation : la flèche de la souris seulement.
final class HiddenDrag {
    private let origin: CGPoint
    private var monitor: Any?
    private var dy: CGFloat
    private let change: (CGFloat) -> Void
    private var finished = false

    /// `localX` : où la case a été prise (depuis son bord gauche) ; `already` : ce qui a déjà été tiré.
    init(localX: CGFloat, width: CGFloat, already: CGFloat, change: @escaping (CGFloat) -> Void) {
        let mouse = NSEvent.mouseLocation
        origin = mouse
        dy = already
        self.change = change
        let primary = NSScreen.screens.first?.frame.height ?? 0
        NSCursor.hide()
        CGWarpMouseCursorPosition(Self.displayPoint(Self.parked(mouse: mouse, localX: localX, width: width),
                                                    primaryHeight: primary))
        CGAssociateMouseAndMouseCursorPosition(0)                   // la flèche reste garée, les mouvements comptent
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            guard let self else { return event }
            self.dy += event.deltaY                                 // vers le bas : positif, comme `translation`
            self.change(self.dy)
            return event
        }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        let primary = NSScreen.screens.first?.frame.height ?? 0
        CGWarpMouseCursorPosition(Self.displayPoint(origin, primaryHeight: primary))
        CGAssociateMouseAndMouseCursorPosition(1)
        NSCursor.unhide()
    }

    deinit { finish() }

    /// Pur (testé) : la flèche garée 12 points à droite de la case, à la même hauteur (coordonnées d'AppKit).
    static func parked(mouse: CGPoint, localX: CGFloat, width: CGFloat) -> CGPoint {
        CGPoint(x: mouse.x + max(0, width - localX) + 12, y: mouse.y)
    }

    /// Pur (testé) : un point d'AppKit (origine en bas à gauche de l'écran principal) en point de l'écran pour
    /// CoreGraphics (origine en haut à gauche).
    static func displayPoint(_ p: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}
