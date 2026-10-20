// Organiser : la fenêtre (panneau flottant qui laisse FL au premier plan) et son contrôleur. Ouverte par le bloc
// « Organiser la page ouverte » ou par le menu de la barre des menus. Lien avec FL installé à la demande (écran
// d'installation s'il manque), écoute, aperçu par famille (une couleur ou un dégradé chacune, famille de chaque son
// modifiable, nouveaux noms des pistes de la Playlist), application, puis « Revenir comme avant ». Tout est libéré à
// la fermeture (session, capture, IA, panneau) : rien ne tourne au repos. Aucune lecture de l'écran.
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

extension OrganizerPage: Hashable {
    var flPage: FLPage {
        switch self {
        case .channelRack: return .channelRack
        case .mixer: return .mixer
        case .playlist: return .playlist
        }
    }

    var title: String { flPage.title }

    var symbol: String {
        switch self {
        case .channelRack: return "square.stack.3d.up"
        case .mixer: return "slider.vertical.3"
        case .playlist: return "rectangle.split.3x1"
        }
    }
}

/// Ce dont l'Organiser a besoin du monde réel (des faux dans les tests).
struct OrganizerEnvironment {
    var link: () -> OrganizerLink
    /// Capture du son de FL, ou la raison de l'impossibilité (macOS trop ancien, FL fermé).
    var audio: () -> Result<AudioSource, OrganizerError>
    var classify: () -> OrganizerSession.Classify
    /// ⌥↑ envoyé à FL : `moveUp(link)(n)` renvoie le nombre de pas faits.
    var moveUp: (OrganizerLink) -> (Int) -> Int
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
    /// Met la page devant dans FL (hors du fil principal : réveil du lien).
    var showPage: (OrganizerPage) -> Void = { _ in }
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
            moveUp: { link in { count in OrganizerEnvironment.liveMoveUp(count, link: link) } },
            escapePressed: { CGEventSource.keyState(.combinedSessionState, key: 53) },
            placeIcon: { OrganizerEnvironment.livePlaceIcon($0) },
            prepareLink: { OrganizerEnvironment.livePrepareLink() },
            installLink: { FLScriptInstaller.installWithAlert(quiet: true) },
            installLinkElsewhere: { FLScriptInstaller.installWithAlert(chooseFolder: true, quiet: true) },
            scriptPlace: { FLScriptInstaller.installedScript() },
            reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
            wrongInput: { MIDILink.shared.core.snapshot.wrongInput },
            showPage: { page in
                guard let id = FLActions.id(forKey: page.flPage.actionKey) else { return }
                _ = MIDILink.shared.runBriefly([id])
            },
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
            })
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

    /// ⌥↑ envoyé à FL seul, 15 ms entre deux ; s'arrête dès que FL n'est plus au premier plan ou que le Channel rack
    /// n'est plus devant dans FL.
    static func liveMoveUp(_ count: Int, link: OrganizerLink) -> Int {
        guard count > 0, let pid = flPID() else { return 0 }
        if EventTap.shared.currentConfig.frontmostPID != pid {
            _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            Thread.sleep(forTimeInterval: 0.3)
        }
        let effects = MacroEffectsMac(pid: pid)
        let up = KeyCombo(keyCode: 126, option: true)
        guard link.window == .channelRack else { return 0 }  // demandé à FL (une requête), pas à chaque touche
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
        /// Aucune page à organiser devant dans FL.
        case openPage
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
    /// Famille de chaque élément (canal, piste du Mixer ou de la Playlist), modifiable dans l'aperçu.
    @Published var families: [Int: SoundFamily] = [:]
    /// Ce qu'est chaque élément (Kick, 808, Open Hat…), modifiable dans l'aperçu ; oublié s'il ne va plus avec sa
    /// famille.
    @Published var kinds: [Int: SoundKind] = [:]
    @Published var styles: [SoundFamily: FamilyStyle]
    @Published private(set) var result: OrganizerResult?
    /// Playlist : renommer les pistes qui ont encore le nom de FL.
    @Published var renameTracks = true
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
    /// Page choisie avec les boutons de l'Organiser : organisée telle quelle, sans redemander à FL quelle page est
    /// devant (FL ne disait pas toujours le Mixer ou la Playlist « focused »).
    private(set) var chosenPage: OrganizerPage?
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

    var title: String {
        switch result?.page {
        case .mixer?: return String(localized: "Organiser le Mixer")
        case .channelRack?: return String(localized: "Organiser le Channel rack")
        case .playlist?: return String(localized: "Organiser la Playlist")
        case nil: return String(localized: "Organiser")
        }
    }

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
            sleep: env.sleep, escape: env.escapePressed,
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
        let chosen = chosenPage
        queue.async { [weak self] in                           // file en série : jamais deux écoutes en même temps
            if warmUp > 0 { sleep(warmUp) }
            let outcome = session.run(on: chosen)
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
        case .refused(1): return .openPage
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

    /// La page mise devant dans FL (lien avec FL, comme « Ouvrir une page de FL »), puis un nouvel essai sur cette
    /// page, sans redemander à FL laquelle est devant.
    func open(_ page: OrganizerPage) {
        guard !closed else { return }
        chosenPage = page
        waitSerial += 1                                       // pas d'essai tout seul pendant que la page s'ouvre
        let show = env.showPage
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            show(page)
            DispatchQueue.main.async { self?.retry() }
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
            if !families.isEmpty {
                phase = .preview
            } else if result.page == .mixer {
                phase = .failed(String(localized: "Aucune piste du Mixer n'est reliée à un son du Channel rack."))
            } else if result.page == .playlist {
                phase = .failed(String(localized: """
                    Aucune piste de la Playlist ne joue de son. Sélectionne les pistes à organiser \
                    (clic sur leur nom), puis clique sur « Réessayer ».
                    """))
            } else {
                phase = .failed(String(localized: "Aucun son à écouter dans le Channel rack."))
            }
        case .failure(let error):
            if let reason = Self.waitReason(for: error, wrongInput: env.wrongInput()) { wait(reason) } else { phase = .failed(error.message) }
        }
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
        /// Playlist : nom qu'elle prendra.
        var newName: String? = nil
        /// Ce qu'est le son (Kick, 808…), s'il va avec sa famille.
        var kind: SoundKind? = nil
    }

    /// Éléments d'une famille, dans l'ordre de FL ; Channel rack : dans l'ordre où ils finiront (les Kick
    /// ensemble, puis les Snare…).
    func members(of family: SoundFamily) -> [Member] {
        guard let result else { return [] }
        var out: [Member] = []
        switch result.page {
        case .channelRack:
            for item in result.items where families[item.index] == family {
                out.append(Member(id: item.index, name: item.name, testNotes: item.testNotes, byName: item.byName,
                                  kind: kind(of: item.index)))
            }
            let rank = { (m: Member) in m.kind?.rank ?? SoundKind.allCases.count }
            out = out.enumerated().sorted { a, b in
                rank(a.element) != rank(b.element) ? rank(a.element) < rank(b.element) : a.offset < b.offset
            }.map { $0.element }
        case .mixer:
            for track in result.mixer where families[track.index] == family {
                out.append(Member(id: track.index, name: track.name.isEmpty ? String(localized: "Piste \(track.index)") : track.name,
                                  testNotes: false, kind: kind(of: track.index)))
            }
        case .playlist:
            let names = plannedNames
            for item in result.items where families[item.index] == family {
                out.append(Member(id: item.index, name: item.name.isEmpty ? "Track \(item.index + 1)" : item.name,
                                  testNotes: false, byName: item.byName, newName: names[item.index],
                                  kind: kind(of: item.index)))
            }
        }
        return out
    }

    /// Ce qu'est l'élément, s'il va avec sa famille.
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

    /// Playlist : nouveaux noms (vide si « Renommer les pistes » est décoché).
    var plannedNames: [Int: String] {
        guard renameTracks, let result, result.page == .playlist else { return [:] }
        return OrganizerApplier.plannedNames(result: result, families: families, kinds: kinds)
    }

    /// Couleur prévue de chaque élément (dégradés répartis dans l'ordre final).
    var plannedColors: [Int: RGBColor] {
        guard let result else { return [:] }
        let order: [Int]
        switch result.page {
        case .channelRack:
            let channels = result.channels.sorted { $0.index < $1.index }
            order = OrganizerApplier.rackPlan(channels, families: families, kinds: kinds).final
        case .mixer:
            order = result.mixer.map(\.index)
        case .playlist:
            order = result.playlist.map(\.index)
        }
        return OrganizerApplier.plannedColors(families: families, styles: styles, order: order)
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
        switch result?.page {
        case .mixer?: return String(localized: "C'est fait : les pistes du Mixer sont colorées.")
        case .playlist?:
            return plannedNames.isEmpty ? String(localized: "C'est fait : les pistes de la Playlist sont colorées par famille.")
                                        : String(localized: "C'est fait : les pistes de la Playlist sont colorées et renommées.")
        default: return String(localized: "C'est fait : les sons sont colorés par famille et rangés par sorte (Kick, Snare, 808…).")
        }
    }

    func apply() {
        guard phase == .preview, let result, let link else { return }
        env.saveStyles(styles)
        env.focusFL()                                         // ⌥↑ et F2 vont à FL
        phase = .applying
        let applier = OrganizerApplier(link: link, moveUp: env.moveUp(link), placeIcon: env.placeIcon)
        let families = self.families, styles = self.styles, names = plannedNames, kinds = self.kinds
        queue.async { [weak self] in
            let outcome = applier.apply(result: result, families: families, styles: styles, names: names, kinds: kinds)
            DispatchQueue.main.async {
                self?.snapshot = outcome.snapshot
                self?.phase = .applied(outcome.error)
            }
        }
    }

    /// « Revenir comme avant » : après l'application, ou pour finir un retour interrompu.
    var canUndo: Bool {
        guard snapshot != nil else { return false }
        switch phase {
        case .applied: return true
        case .undone(let error): return error != nil
        default: return false
        }
    }

    func undo() {
        guard canUndo, let snapshot, let link else { return }
        phase = .undoing
        let applier = OrganizerApplier(link: link, moveUp: env.moveUp(link))
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
        case "page": phase = .waiting(.openPage)
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

    static var demoResult: OrganizerResult {
        let sounds: [(String, SoundFamily)] = [("Voix lead", .vocals), ("Piano", .melody), ("Pluck", .melody),
                                               ("808", .bass), ("Kick", .drums), ("Snare", .drums),
                                               ("Hi-hat", .drums), ("Riser", .fx)]
        let gray = RGBColor(r: 92, g: 101, b: 107)
        let channels = sounds.enumerated().map {
            ChannelInfo(index: $0.offset, type: 2, mixerTrack: $0.offset + 1, color: gray, name: $0.element.0)
        }
        let items = sounds.enumerated().map {
            OrganizerItem(index: $0.offset, name: $0.element.0, family: $0.element.1, confidence: 0.9, testNotes: false,
                          mixerTrack: $0.offset + 1, color: gray, kind: SoundNames.kind(of: $0.element.0))
        }
        return OrganizerResult(page: .channelRack, channels: channels, items: items, mixer: [], mixerFamilies: [:])
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
    static let height: CGFloat = 560
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
                Text("Écoute, classe et colore tes sons")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .morphIn(0)
    }

    private static func listeningText(_ done: Int, _ total: Int) -> String {
        total == 0 ? String(localized: "Préparation de l'écoute…") : String(localized: "Écoute \(min(done + 1, total)) sur \(total)")
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
                    Un son dont le nom dit la famille (Kick, 808, Hat…) est classé tout de suite ; les autres jouent \
                    seuls, dans un pattern où ils jouent, sans que tu les entendes. Dans la Playlist, la chanson est \
                    parcourue : FL dit quels sons jouent sur chaque piste. Ne touche pas à FL ; Échap arrête.
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
            working(String(localized: "Application dans FL… Ne touche pas à FL."))
        case .undoing:
            working(String(localized: "Retour comme avant…"))
        case .applied(let error):
            ending(error?.message ?? controller.doneText, ok: error == nil, linkHelp: error == .noResponse)
        case .undone(let error):
            ending(error?.message ?? String(localized: "FL est revenu comme avant."), ok: error == nil,
                   linkHelp: error == .noResponse)
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
            if reason == .openPage {
                // La page mise devant dans FL par le lien, puis l'écoute tout de suite (plus besoin d'aller cliquer
                // dans FL : signalé, l'Organiser semblait bloqué ici).
                HStack(spacing: 8) {
                    ForEach([OrganizerPage.channelRack, .mixer, .playlist], id: \.self) { page in
                        Button { controller.open(page) } label: {
                            Label(page.title, systemImage: page.symbol).frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                    }
                }
                .morphIn(3)
            }
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
        case .openPage:
            return ("square.stack.3d.up", String(localized: "Choisis la page à organiser"),
                    String(localized: """
                        Elle s'ouvre dans FL et l'écoute commence. Ou clique toi-même dans le Channel rack, le Mixer \
                        ou la Playlist de FL.
                        """))
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
        switch controller.result?.page {
        case .mixer?:
            return String(localized: "Chaque piste prend la famille des sons qui y sont reliés. Clique sur une famille pour la changer.")
        case .playlist?:
            return String(localized: "Chaque piste prend ce que jouent ses sons (Kick, 808…, sinon leur famille), d'après leur nom ou leur écoute. Clique dessus pour le changer. Appliquer colore les pistes par famille.")
        default:
            return String(localized: "Chaque son est rangé d'après son nom (« BEAM KICK » : Kick), sinon d'après son écoute. Clique sur Kick, 808… pour le changer. Appliquer colore les sons par famille et met ensemble ceux de même sorte.")
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .morphIn(1)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    let colors = controller.plannedColors
                    ForEach(Array(controller.presentFamilies.enumerated()), id: \.element) { index, family in
                        FamilySection(controller: controller, family: family, colors: colors)
                            .morphIn(index + 2)
                    }
                }
                // Place pour la carte survolée qui grandit et son ombre.
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
            .padding(.horizontal, -4)
            if controller.result?.page == .playlist {
                Toggle("Renommer les pistes qui ont encore le nom de FL (Kick, Snare, Voix…)",
                       isOn: $controller.renameTracks)
                    .font(.system(size: 12))
                Text(String(localized: """
                    FL ne laisse pas un script déplacer les pistes de la Playlist ni changer leur icône : leur ordre \
                    et leurs icônes restent comme ils sont.
                    """))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Annuler") { controller.close() }.keyboardShortcut(.cancelAction)
                diagnosticButton
                Spacer()
                Button("Appliquer") { controller.apply() }
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
                if controller.result?.page != .playlist {
                    Button { pickingIcon = true } label: { FLIconBadge(icon: style.icon, size: 18) }
                        .buttonStyle(.plain)
                        .help("Icône de FL de la famille (posée par la fenêtre de FL, F2 ; « Revenir comme avant » ne la retire pas)")
                        .popover(isPresented: $pickingIcon, arrowEdge: .bottom) {
                            FLIconPicker(selected: style.icon) { picked in
                                controller.updateStyle(family) { $0.icon = picked }
                                pickingIcon = false
                            }
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
