// Organiser : la fenêtre (panneau flottant qui laisse FL au premier plan) et son contrôleur. Ouverte par le bloc
// « Organiser la page ouverte » ou par le menu de la barre des menus. Lien avec FL installé à la demande (écran
// d'installation s'il manque), écoute, aperçu par famille (une couleur ou un dégradé chacune, famille de chaque son
// modifiable, nouveaux noms des pistes de la Playlist), application, puis « Revenir comme avant ». Tout est libéré à
// la fermeture (session, capture, IA, panneau) : rien ne tourne au repos. Aucune lecture de l'écran.
import AppKit
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
    var timing = OrganizerSession.Timing()
    var sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    var escapePressed: () -> Bool = { false }
    var loadStyles: () -> [SoundFamily: FamilyStyle] = { FamilyStyles.load() }
    var saveStyles: ([SoundFamily: FamilyStyle]) -> Void = { FamilyStyles.save($0) }
    /// Icône posée sur l'élément sélectionné par la fenêtre de FL (F2) ; nil si c'est fait.
    var placeIcon: (FLIcon) -> OrganizerError? = { _ in nil }
    /// Fil principal, avant chaque écoute : lien installé ? Ports MIDI créés à la demande.
    var prepareLink: () -> OrganizerLinkState = { .ready(warmUp: 0) }
    /// « Installer le lien avec FL » (fil principal).
    var installLink: () -> Void = {}
    /// « Autre dossier de FL… » : le lien réinstallé dans le dossier de données de FL choisi (fil principal).
    var installLinkElsewhere: () -> Void = {}
    /// Script dans FL Studio : où il est enregistré, et s'il y est encore (nil : aucun).
    var scriptPlace: () -> (url: URL, present: Bool)? = { nil }
    var reveal: (URL) -> Void = { _ in }
    var nameDrum: () -> OrganizerSession.NameDrum = { { _, _ in .perc } }

    static func live() -> OrganizerEnvironment {
        OrganizerEnvironment(
            link: { RequestOrganizerLink.live() },
            audio: {
                guard #available(macOS 14.2, *) else {
                    return .failure(.failed("L'Organiser écoute FL avec macOS 14.2 ou plus récent : mets macOS à jour."))
                }
                guard let pid = OrganizerEnvironment.flPID() else { return .failure(.failed("FL Studio n'est pas ouvert.")) }
                return .success(FLAudioTap(pid: pid))
            },
            classify: { OrganizerSession.liveClassifier() },
            moveUp: { link in { count in OrganizerEnvironment.liveMoveUp(count, link: link) } },
            escapePressed: { CGEventSource.keyState(.combinedSessionState, key: 53) },
            placeIcon: { OrganizerEnvironment.livePlaceIcon($0) },
            prepareLink: { OrganizerEnvironment.livePrepareLink() },
            installLink: { FLScriptInstaller.installWithAlert() },
            installLinkElsewhere: { FLScriptInstaller.installWithAlert(chooseFolder: true) },
            scriptPlace: { FLScriptInstaller.installedScript() },
            reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) },
            nameDrum: { OrganizerSession.liveDrumNamer() })
    }

    /// Lien installé : script remis dans FL s'il en a disparu, ports « FL Shortcuts Link » créés s'ils ne sont pas là
    /// (mode léger, sans trafic), comme pour une macro qui en a besoin.
    static func livePrepareLink() -> OrganizerLinkState {
        let midi = MIDILink.shared
        guard midi.snapshot.hasKey else { return .notInstalled }
        let restored = FLScriptInstaller.repairIfNeeded() != nil
        let fresh = AppMode.light && !midi.onDemand
        midi.setOnDemand(true)
        return restored ? .restored : .ready(warmUp: fresh && midi.onDemand ? 2 : 0)
    }

    /// Mêmes étapes et garde-fous que le bloc « Nom et couleur » (FL au premier plan, Échap).
    static func livePlaceIcon(_ icon: FLIcon) -> OrganizerError? {
        guard let pid = flPID() else { return .failed("FL Studio n'est pas ouvert.") }
        if EventTap.shared.currentConfig.frontmostPID != pid {
            _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            Thread.sleep(forTimeInterval: 0.3)
        }
        switch MacroEffectsMac(pid: pid).placeIcon(icon, alsoColored: false) {
        case .ok, .warn: return nil
        case .fail(let why), .cancel(let why):
            return .failed(why.prefix(1).uppercased() + String(why.dropFirst()) + ". Les couleurs sont posées.")
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
        var done = 0
        while done < count {
            guard EventTap.shared.currentConfig.frontmostPID == pid, link.window == .channelRack else { break }
            effects.postKey(up, pid: pid)
            done += 1
            Thread.sleep(forTimeInterval: 0.015)
        }
        return done
    }
}

final class OrganizerController: ObservableObject {
    enum Phase: Equatable {
        case starting
        /// Lien avec FL pas installé : écran d'installation.
        case setup
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
    @Published var styles: [SoundFamily: FamilyStyle]
    @Published private(set) var result: OrganizerResult?
    /// Playlist : renommer les pistes qui ont encore le nom de FL.
    @Published var renameTracks = true

    /// Appelé une fois, à la fermeture (la fenêtre se ferme et lâche le contrôleur).
    var onClose: (() -> Void)?

    private let env: OrganizerEnvironment
    private let queue = DispatchQueue(label: "app.flshortcut.organizer", qos: .userInitiated)
    private var link: OrganizerLink?
    private var session: OrganizerSession?
    private var snapshot: OrganizerSnapshot?
    private var closed = false

    init(env: OrganizerEnvironment) {
        self.env = env
        styles = env.loadStyles()
    }

    var title: String {
        switch result?.page {
        case .mixer?: return "Organiser le Mixer"
        case .channelRack?: return "Organiser le Channel rack"
        case .playlist?: return "Organiser la Playlist"
        case nil: return "Organiser"
        }
    }

    /// Écoute de chaque son, hors du fil principal.
    func start() {
        guard phase == .starting, !closed else { return }
        let warmUp: TimeInterval
        switch env.prepareLink() {
        case .notInstalled:
            phase = .setup
            return
        case .restored:
            phase = .failed(Self.restoredMessage)
            return
        case .ready(let delay):
            warmUp = delay
        }
        let audio: AudioSource
        switch env.audio() {
        case .success(let source):
            audio = source
        case .failure(let error):
            phase = .failed(error.message)
            return
        }
        let link = env.link()
        let session = OrganizerSession(
            link: link, audio: audio, classify: env.classify(), nameDrum: env.nameDrum(), timing: env.timing,
            sleep: env.sleep, escape: env.escapePressed,
            progress: { [weak self] done, total in
                DispatchQueue.main.async { self?.listening(done, total) }
            })
        self.link = link
        self.session = session
        phase = .listening(done: 0, total: 0)
        let sleep = env.sleep
        queue.async { [weak self] in
            if warmUp > 0 { sleep(warmUp) }
            let outcome = session.run()
            DispatchQueue.main.async { self?.finishListening(outcome) }
        }
    }

    /// « Réessayer » : après l'écran d'installation ou un échec (FL qui jouait, page à ouvrir, FL à redémarrer…).
    var canRetry: Bool {
        switch phase {
        case .setup, .failed: return snapshot == nil
        default: return false
        }
    }

    func retry() {
        guard canRetry, !closed else { return }
        result = nil
        families = [:]
        phase = .starting
        start()
    }

    func installLink() {
        env.installLink()
    }

    static let restoredMessage = "Le script du lien manquait dans FL Studio : il vient d'être remis. Quitte et rouvre "
        + "FL Studio (il ne lit ses scripts qu'en démarrant), puis clique sur « Réessayer »."

    /// FL muet : réglages de FL à vérifier et emplacement du script.
    func needsLinkHelp(_ message: String) -> Bool {
        message == OrganizerError.noResponse.message || message == Self.restoredMessage
    }

    var scriptPlace: (url: URL, present: Bool)? { env.scriptPlace() }

    func revealScript() {
        if let place = env.scriptPlace(), place.present { env.reveal(place.url) }
    }

    func installLinkElsewhere() {
        env.installLinkElsewhere()
    }

    private func listening(_ done: Int, _ total: Int) {
        guard case .listening = phase else { return }
        phase = .listening(done: done, total: total)
    }

    private func finishListening(_ outcome: Result<OrganizerResult, OrganizerError>) {
        session = nil
        guard !closed else { return }
        switch outcome {
        case .success(let result):
            self.result = result
            families = OrganizerApplier.families(of: result)
            if !families.isEmpty {
                phase = .preview
            } else if result.page == .mixer {
                phase = .failed("Aucune piste du Mixer n'est reliée à un son du Channel rack.")
            } else if result.page == .playlist {
                phase = .failed("Aucune piste de la Playlist ne joue de son. Sélectionne les pistes à organiser "
                                + "(clic sur leur nom), puis clique sur « Réessayer ».")
            } else {
                phase = .failed("Aucun son à écouter dans le Channel rack.")
            }
        case .failure(let error):
            phase = .failed(error.message)
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
        /// Playlist : nom qu'elle prendra.
        var newName: String? = nil
    }

    /// Éléments d'une famille, dans l'ordre de FL.
    func members(of family: SoundFamily) -> [Member] {
        guard let result else { return [] }
        var out: [Member] = []
        switch result.page {
        case .channelRack:
            for item in result.items where families[item.index] == family {
                out.append(Member(id: item.index, name: item.name, testNotes: item.testNotes))
            }
        case .mixer:
            for track in result.mixer where families[track.index] == family {
                out.append(Member(id: track.index, name: track.name.isEmpty ? "Piste \(track.index)" : track.name,
                                  testNotes: false))
            }
        case .playlist:
            let names = plannedNames
            for item in result.items where families[item.index] == family {
                out.append(Member(id: item.index, name: item.name.isEmpty ? "Track \(item.index + 1)" : item.name,
                                  testNotes: false, newName: names[item.index]))
            }
        }
        return out
    }

    /// Playlist : nouveaux noms (vide si « Renommer les pistes » est décoché).
    var plannedNames: [Int: String] {
        guard renameTracks, let result, result.page == .playlist else { return [:] }
        return OrganizerApplier.plannedNames(result: result, families: families)
    }

    /// Couleur prévue de chaque élément (dégradés répartis dans l'ordre final).
    var plannedColors: [Int: RGBColor] {
        guard let result else { return [:] }
        let order: [Int]
        switch result.page {
        case .channelRack:
            let channels = result.channels.sorted { $0.index < $1.index }
            order = RegroupPlan.make(order: channels.map { families[$0.index] }).final
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
        case .mixer?: return "C'est fait : les pistes du Mixer sont colorées."
        case .playlist?:
            return plannedNames.isEmpty ? "C'est fait : les pistes de la Playlist sont colorées par famille."
                                        : "C'est fait : les pistes de la Playlist sont colorées et renommées."
        default: return "C'est fait : les sons sont colorés et regroupés par famille."
        }
    }

    func apply() {
        guard phase == .preview, let result, let link else { return }
        env.saveStyles(styles)
        phase = .applying
        let applier = OrganizerApplier(link: link, moveUp: env.moveUp(link), placeIcon: env.placeIcon)
        let families = self.families, styles = self.styles, names = plannedNames
        queue.async { [weak self] in
            let outcome = applier.apply(result: result, families: families, styles: styles, names: names)
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

    /// Ouvre l'Organiser (ou le ramène devant). Fil principal.
    static func open(env: OrganizerEnvironment = .live()) {
        if let panel {
            panel.orderFrontRegardless()
            panel.makeKey()
            return
        }
        let controller = OrganizerController(env: env)
        controller.onClose = { OrganizerWindow.close() }
        let host = NSHostingView(rootView: OrganizerView(controller: controller))
        host.sizingOptions = []                                       // taille posée ici, à chaque étape
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: OrganizerView.width, height: 220),
                        styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.title = "Organiser"
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
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
        sizing = controller.$phase.sink { _ in
            // Après le dessin de la nouvelle étape.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard let panel = OrganizerWindow.panel, panel === p else { return }
                fit(p, host, animate: true)
            }
        }
        p.orderFrontRegardless()
        p.makeKey()
        controller.start()
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
        total == 0 ? "Préparation de l'écoute…" : "Écoute \(min(done + 1, total)) sur \(total)"
    }

    @ViewBuilder private var content: some View {
        switch controller.phase {
        case .starting:
            working("Préparation…")
        case .setup:
            setup
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
                Text("Chaque son joue seul, sans que tu l'entendes (dans la Playlist, la chanson est parcourue jusqu'à "
                     + "ce que la piste sonne). Ne touche pas à FL ; Échap arrête.")
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
            working("Application dans FL… Ne touche pas à FL.")
        case .undoing:
            working("Retour comme avant…")
        case .applied(let error):
            ending(error?.message ?? controller.doneText, ok: error == nil, linkHelp: error == .noResponse)
        case .undone(let error):
            ending(error?.message ?? "FL est revenu comme avant.", ok: error == nil, linkHelp: error == .noResponse)
        case .failed(let message):
            ending(message, ok: false, linkHelp: controller.needsLinkHelp(message))
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
                    OrganizerStep(n: 1, text: "Quitte et rouvre FL Studio : il trouve « FL Shortcuts Link » en démarrant "
                                  + "et le relie tout seul. Puis « Réessayer ».")
                    OrganizerStep(n: 2, text: "Toujours rien : Options › MIDI Settings, entrée « FL Shortcuts Link », "
                                  + "Controller type « FL Shortcuts » (pas « generic controller »), Enable, et le même "
                                  + "numéro de Port à l'entrée et à la sortie.")
                    OrganizerStep(n: 3, text: "« FL Shortcuts » absent des Controller types : FL ne lit pas le dossier du "
                                  + "script ci-dessous. Compare-le avec Options › File settings › User data folder dans "
                                  + "FL (pas sur iCloud) ; s'il diffère, « Autre dossier de FL… » et choisis celui-là.")
                    OrganizerStep(n: 4, text: "Réglages Système › Confidentialité et sécurité › Fichiers et dossiers › "
                                  + "FL Studio : « Dossier Documents » doit être coché.")
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
                    Text(present ? "Script du lien" : "Script introuvable dans FL Studio")
                        .font(.system(size: 12, weight: .semibold))
                    Text(place.map { FLScriptInstaller.displayFolder(of: $0.url) } ?? "Aucun dossier enregistré.")
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

    @ViewBuilder private var buttons: some View {
        HStack {
            if controller.canUndo {
                Button("Revenir comme avant") { controller.undo() }
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

    /// Lien avec FL pas encore installé : installé ici, à la demande.
    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Organiser parle à FL par un petit script que FL Shortcuts installe dans FL Studio, une seule fois.")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .morphIn(1)
            VStack(alignment: .leading, spacing: 8) {
                OrganizerStep(n: 1, text: "Clique sur « Installer le lien avec FL ».")
                OrganizerStep(n: 2, text: "Quitte et rouvre FL Studio : il trouve « FL Shortcuts Link » en démarrant et "
                              + "le relie tout seul.")
                OrganizerStep(n: 3, text: "Ouvre la page à organiser (Channel rack, Mixer ou Playlist), puis "
                              + "« Réessayer ».")
            }
            HStack {
                Button("Installer le lien avec FL") { controller.installLink() }
                Spacer()
                Button("Fermer") { controller.close() }.keyboardShortcut(.cancelAction)
                Button("Réessayer") { controller.retry() }
                    .primaryButton()
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 2)
            .morphIn(5)
        }
    }

    private var hint: String {
        switch controller.result?.page {
        case .mixer?:
            return "Chaque piste prend la famille des sons qui y sont reliés. Clique sur une famille pour la changer."
        case .playlist?:
            return "Chaque piste a été écoutée seule. Clique sur sa famille pour la changer. Appliquer colore les pistes par famille."
        default:
            return "Vérifie chaque son et clique sur sa famille pour la changer. Appliquer colore et regroupe les sons par famille."
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
                Text("FL ne laisse pas un script déplacer les pistes de la Playlist ni changer leur icône : leur ordre "
                     + "et leurs icônes restent comme ils sont.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Annuler") { controller.close() }.keyboardShortcut(.cancelAction)
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
            Text(member.name.isEmpty ? "(sans nom)" : member.name).lineLimit(1)
            if let newName = member.newName {
                Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(.secondary)
                Text(newName).lineLimit(1).foregroundStyle(.secondary)
            }
            if member.testNotes {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
                    .help("Muet dans le pattern : classé avec deux notes d'essai. Vérifie sa famille.")
            }
            Spacer()
            Menu {
                ForEach(SoundFamily.order, id: \.self) { choice in
                    Button(choice.label) { controller.families[member.id] = choice }
                }
            } label: {
                Text(family.label).font(.system(size: 11))
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .help("Changer la famille de ce son")
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
        .help("#" + color.hex + " : choisir dans la roue des couleurs de FL")
        .popover(isPresented: picking, arrowEdge: .bottom) {
            FLColorSelector(initial: color) { picked in
                set(picked)
                picking.wrappedValue = false
            }
        }
    }
}
