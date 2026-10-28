// Audit : REL-07 (instance unique, vérifiée avant toute création de tap, de port MIDI ou de profil),
//         REL-08 (surveillance permanente de la permission Accessibilité : tap arrêté / recréé / redémarré,
//         permission périmée signalée), REL-09 (Saisie sécurisée détectée et affichée), SEC-10 (tap coupé trop
//         souvent : recréé et signalé), REL-04 (purge sur veille, réveil, changement de session),
//         REL-21 (profil écrit à la fermeture), REL-23 (accueil marqué « vu » après le choix ; permission
//         demandée depuis l'accueil, pas en même temps), audit 05 §4.4 (état « en pause » visible en permanence :
//         icône dédiée + panneau flottant non activant), audit 04 §8.2 (disponibilité des actions : masque du
//         script, sinon version lue dans le bundle de FL), PROTOCOL.md §5 (statut du lien affiché).
import AppKit
import ApplicationServices
import Carbon
import Combine
import SwiftUI

@main
struct FLShortcutApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store: Store
    @StateObject private var status: AppStatus
    // Simples références : leurs publications (lien, présence de FL) ne réévaluent pas toute la scène.
    private let link = MIDILink.shared
    private let fl = FLMonitor.shared

    init() {
        Bench.runIfRequested()                   // `--mesure` : temps de réponse de FL, puis quitte
        MacroDiagnostics.runIfRequested()        // `--diag-macro` : fenêtres et menus de FL vus par l'app, puis quitte
        MacroDiagnostics.runIconIfRequested()    // `--diag-icon 7-4` : pose une icône dans le vrai FL, puis quitte
        PresetSelfTest.runIfRequested()          // `--selftest-preset` : essai du choix automatique du preset, puis quitte
        FakeFL.runIfRequested()                  // `--fake-fl` : FL Studio simulé pour l'essai de bout en bout (CI)
        MacroSelfTest.runIfRequested()           // `--selftest-macro` : la macro complète contre le FL simulé, puis quitte
        Uninstaller.runCheckIfRequested()        // `--essai-desinstallation` (CI) : tout supprimer, vérifier, quitter
        SingleInstance.started = Date()
        SingleInstance.enforce()                 // avant de créer quoi que ce soit (REL-07)
        _store = StateObject(wrappedValue: Store.shared)
        _status = StateObject(wrappedValue: AppStatus.shared)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(store)
                .environmentObject(status)
                .environmentObject(link)
                .environmentObject(fl)
        } label: {
            MenuBarLabel(symbol: status.menuBarSymbol(enabled: store.enabled))
        }
        .menuBarExtraStyle(.window)

        Window("FL Shortcuts – Raccourcis", id: "editor") {
            EditorView()
                .environmentObject(store)
                .environmentObject(status)
                .environmentObject(link)
                .environmentObject(fl)
                .frame(minWidth: 820, minHeight: 480)
        }
        .windowResizability(.contentMinSize)

        // Pas de scène pour le créateur de macros : il s'affiche dans cette fenêtre (EditorView, comme un dossier dans
        // le Finder), son modèle n'existe que pendant qu'il est affiché.
    }
}

/// Couleur de l'état de l'app (pastille du menu de la barre, état de la fenêtre principale) : grise en pause,
/// orange sans autorisation clavier, puis selon FL (mode léger) ou le lien.
enum AppStatusColor {
    static func color(enabled: Bool, accessibilityOK: Bool, flRunning: Bool, link: LinkStatus) -> Color {
        if !enabled { return .gray }
        if !accessibilityOK { return .orange }
        if AppMode.light { return flRunning ? .green : .gray }
        switch link {
        case .linked: return .green
        case .inactive: return .orange
        case .flClosed: return .gray
        }
    }
}

enum SingleInstance {
    /// Noté par une copie qui se ferme. « Quitter et rouvrir » de macOS relance l'app pendant que l'ancienne copie
    /// finit de se fermer : la nouvelle la voyait encore et partait aussitôt, rien ne se rouvrait (retour du
    /// propriétaire). Elle attend maintenant que l'ancienne soit partie, aussi longtemps qu'il le faut (une limite de
    /// 5 s la faisait de nouveau partir : l'ancienne mettait plus longtemps à se fermer). La note est un fichier (lu
    /// tout de suite par l'autre copie, relu à chaque tour : la relance peut arriver avant qu'elle ne soit écrite).
    static let quittingKey = "quittingPID"
    static var quittingFile: URL { URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("FLShortcuts.quitting") }
    /// Une copie qui se ferme est attendue jusque-là ; bloquée au-delà, elle est arrêtée (elle a demandé à partir).
    static let quittingTimeout: TimeInterval = 30
    /// Lancement (journal : combien de temps la réouverture a pris, en millisecondes).
    static var started = Date()
    static var waitedMs = 0

    /// Fermeture de cette copie notée (avant tout le reste de la fermeture).
    static func markQuitting() {
        UserDefaults.standard.set(Int(getpid()), forKey: quittingKey)
        try? Data("\(getpid())".utf8).write(to: quittingFile, options: .atomic)
    }

    /// Cette copie (`pid`) a-t-elle noté qu'elle se ferme ?
    static func isQuitting(_ pid: pid_t) -> Bool {
        if let text = try? String(contentsOf: quittingFile, encoding: .utf8), Int(text) == Int(pid) { return true }
        return UserDefaults.standard.integer(forKey: quittingKey) == Int(pid)
    }

    static func enforce() {
        let me = NSRunningApplication.current
        let id = Bundle.main.bundleIdentifier ?? "app.flshortcut.FLShortcut"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != me.processIdentifier && !$0.isTerminated }
        guard let first = others.first else { return }
        let pid = first.processIdentifier
        let waitStart = Date()
        defer { waitedMs = Int(Date().timeIntervalSince(waitStart) * 1000) }
        // Copie qui se ferme : attendue jusqu'à ce qu'elle soit partie ; sinon un court instant.
        if waitForExit(pid, timeout: 1.5, longer: { isQuitting(pid) }, longTimeout: quittingTimeout) { return }
        if isQuitting(pid) {
            // Elle a demandé à se fermer mais reste bloquée : arrêtée, pour que l'app se rouvre quand même.
            kill(pid, SIGKILL)
            if waitForExit(pid, timeout: 2) {
                MacroLog.shared.write("LAUNCH", "old copy stuck while quitting, stopped")
                return
            }
        }
        MacroLog.shared.write("LAUNCH", "another copy is running (\(Int(Date().timeIntervalSince(waitStart) * 1000)) ms), this one leaves")
        MacroLog.shared.flush()
        first.activate(options: [])
        exit(0)
    }

    /// Qui demande la fermeture, quand c'est une autre app ou un processus du système (événement « quit » de macOS) :
    /// son identifiant d'app s'il en a un, le chemin de son programme, et si c'est la fin de la session (raison donnée).
    struct QuitSender: Equatable {
        var bundle: String?
        var path: String?
        var sessionEnd = false

        /// Pour le journal : l'identifiant, sinon le nom du programme (rien de l'utilisateur).
        var label: String { bundle ?? path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "inconnu" }
    }

    /// nil : l'utilisateur a quitté lui-même (⌘Q, menu : aucun événement « quit »).
    static func quitSender() -> QuitSender? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == 0x6165_7674, event.eventID == 0x7175_6974,      // 'aevt' 'quit'
              let sender = event.attributeDescriptor(forKeyword: 0x7370_6964)  // 'spid' : qui l'envoie
        else { return nil }
        let pid = pid_t(sender.int32Value)
        guard pid > 0, pid != getpid() else { return nil }
        let why: AEKeyword = 0x7768_7921                                       // 'why?' : fin de session…
        let reason = event.attributeDescriptor(forKeyword: why) ?? event.paramDescriptor(forKeyword: why)
        return QuitSender(bundle: NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                          path: processPath(pid), sessionEnd: reason != nil)
    }

    /// Chemin du programme du processus `pid` (nil s'il est déjà parti).
    static func processPath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    }

    /// L'app Réglages Système, ou une de ses pages (« com.apple.settings.PrivacySecurity.extension »).
    static func isSettings(_ bundle: String?) -> Bool {
        guard let bundle else { return false }
        return bundle.hasPrefix("com.apple.systempreferences") || bundle.hasPrefix("com.apple.settings")
            || bundle == "com.apple.Settings"
    }

    /// Pur (testé) : rouvrir l'app après cette fermeture ? Oui quand Réglages Système la demande (« Quitter et
    /// rouvrir », après une autorisation) : l'app des Réglages, une de ses pages, ou un processus du système sans nom
    /// d'app (la page « Confidentialité et sécurité » est une extension à part depuis macOS 13 : elle n'était pas
    /// reconnue et l'app quittait sans revenir, retour du propriétaire, trois fois), ou un envoyeur déjà parti. Non
    /// pour ⌘Q (nil), la fin de session, ni une autre app (Dock, Moniteur d'activité…).
    static func relaunches(_ sender: QuitSender?) -> Bool {
        guard let sender, !sender.sessionEnd else { return false }
        if isSettings(sender.bundle) { return true }
        let path = (sender.path ?? "").lowercased()
        if ["settings", "preference", "privacy", "/tcc"].contains(where: { path.contains($0) }) { return true }
        guard sender.bundle == nil else { return false }
        guard let full = sender.path else { return true }
        return full.hasPrefix("/System/") || full.hasPrefix("/usr/")
    }

    /// Note laissée par une copie que l'utilisateur a quittée lui-même : le surveillant ne la rouvre pas.
    static var noRelaunchFile: URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("FLShortcuts.norelaunch")
    }
    private static var watching = false

    /// Surveillant posé quand l'app ouvre les Réglages pour une autorisation (une fois par lancement) : dès que cette
    /// copie est partie, même fermée de force par macOS, il la rouvre (`open` : la lance, ou la met devant si macOS
    /// l'a déjà relancée) ; pas si l'utilisateur l'a quittée (note `noRelaunchFile`), ni après 30 minutes.
    static func watchForRelaunch() {
        guard !watching, !DebugSnapshot.enabled else { return }
        watching = true
        try? FileManager.default.removeItem(at: noRelaunchFile)
        let me = getpid()
        relaunch(after: me, limit: 9_000, skipIfNoted: true)
    }

    /// Rouvre l'app une fois cette copie partie (60 s au plus).
    static func relaunchAfterQuit() {
        relaunch(after: getpid(), limit: 300, skipIfNoted: false)
    }

    /// Attend que `pid` soit parti (`limit` tours de 0,2 s au plus), puis `open` sur l'app ; avec `skipIfNoted`, rien
    /// si la note dit que l'utilisateur l'a quittée.
    private static func relaunch(after pid: pid_t, limit: Int, skipIfNoted: Bool) {
        // Seulement l'app elle-même (jamais les tests, ni un autre programme qui contiendrait ce code).
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.bundleIdentifier?.hasPrefix("app.flshortcut") == true else { return }
        var script = "i=0; while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; i=$((i+1)); "
        script += "[ $i -gt \(limit) ] && exit 0; done; "
        if skipIfNoted { script += "[ \"$(/bin/cat \"$1\" 2>/dev/null)\" = \"\(pid)\" ] && exit 0; " }
        script += "/bin/sleep 0.5; /usr/bin/open \"$0\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", script, Bundle.main.bundleURL.path, noRelaunchFile.path]
        try? task.run()
    }

    /// Fermeture voulue par l'utilisateur (ou la fin de session) : le surveillant ne rouvre pas l'app.
    static func noteNoRelaunch() {
        try? Data("\(getpid())".utf8).write(to: noRelaunchFile, options: .atomic)
    }

    /// Vrai dès que le processus `pid` n'existe plus ; faux s'il est toujours là au bout de `timeout` secondes
    /// (`longTimeout` si `longer` devient vrai : relu tous les 5 tours, et toujours une dernière fois avant
    /// d'abandonner, car sur un Mac chargé le délai court pouvait passer avant la deuxième lecture — CI, 0,38 s).
    static func waitForExit(_ pid: pid_t, timeout: TimeInterval, longer: () -> Bool = { false },
                            longTimeout: TimeInterval = 0) -> Bool {
        let start = Date()
        var checks = 0
        var long = false
        while true {
            if kill(pid, 0) != 0 && errno == ESRCH { return true }
            let elapsed = Date().timeIntervalSince(start)
            if !long, checks % 5 == 0 || elapsed >= timeout { long = longer() }
            if elapsed >= (long ? max(timeout, longTimeout) : timeout) { return false }
            usleep(30_000)                           // repart dès que l'ancienne copie est partie
            checks += 1
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // La note de l'ancienne copie ne sert plus (elle est partie) : jamais prise pour celle d'une autre plus tard.
        try? FileManager.default.removeItem(at: SingleInstance.quittingFile)
        UserDefaults.standard.removeObject(forKey: SingleInstance.quittingKey)
        if !AppMode.light { MIDILink.shared.start() }  // mode léger : aucun port MIDI, rien dans FL
        FLMonitor.shared.start()
        AppStatus.shared.start()
        PauseIndicator.shared.bind()
        DebugSnapshot.start()
        // Plus jamais rien dans les listes de plugins de FL (demande du 28/10) : ce que d'anciennes versions y avaient
        // ajouté (catégorie « FL Shortcuts » de Add › Channel et des effets) part à la Corbeille. Jamais en mode capture.
        if !DebugSnapshot.enabled {
            DispatchQueue.global(qos: .utility).async {
                let removed = FLPluginDatabase.removeAddedFavorites()
                if removed > 0 { MacroLog.shared.write("LAUNCH", "\(removed) added favorites folder(s) moved to the Trash") }
            }
        }
        // Sauvegarde en ligne : seulement avec un compte connecté (session au Trousseau), sinon aucune requête.
        MainActor.assumeIsolated { AccountBackup.shared.start() }

        // Accueil (autorisations, puis le guide) : au premier lancement, et de nouveau quand le clavier n'est plus
        // autorisé. Une nouvelle version de l'app est une autre app pour macOS, ses autorisations sont à redonner
        // (retour de l'utilisateur : ni page d'accès ni guide après une mise à jour). Jamais en mode capture (CI).
        // Relancée par « Quitter et rouvrir » (ou juste après avoir quitté) : ce qui était ouvert revient (AppResume).
        let resume = DebugSnapshot.enabled ? nil : AppResume.shared.load()
        let onboarding = !UserDefaults.standard.bool(forKey: "didOnboard") || (!AXIsProcessTrusted() && !DebugSnapshot.enabled)
        if onboarding || resume?.onboarding != nil {
            DispatchQueue.main.async { AppDelegate.onboard() }
        }
        if let resume {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { AppDelegate.reopen(resume, onboarding: onboarding) }
        }
        // Une version organisée attend (Organiser fermé avant de quitter) : la question, une fois l'app lancée.
        if !onboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { CopyApproval.shared.askIfNeeded() }
        }
        // Durées seulement : l'attente de l'ancienne copie, puis le lancement jusqu'ici.
        let readyMs = Int(Date().timeIntervalSince(SingleInstance.started) * 1000)
        MacroLog.shared.write("LAUNCH", "waited \(SingleInstance.waitedMs) ms, ready in \(readyMs) ms, resume \(resume != nil)")
    }

    /// Rouvre ce qui l'était avant de quitter. Pendant l'accueil, la fenêtre principale attend sa fin (elle s'ouvre
    /// alors, sur la page et la macro d'avant).
    private static func reopen(_ resume: ResumeState, onboarding: Bool) {
        if resume.permissions { AccessibilityGuide.start() }
        if resume.editor && !onboarding && resume.onboarding == nil {
            NotificationCenter.default.post(name: AccountLink.openEditor, object: nil)
        }
        if resume.organizer { OrganizerWindow.open() }
    }

    /// FL Shortcuts rouvert (double-clic dans le Finder, le Dock, Spotlight) : une version organisée attend peut-être.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        CopyApproval.shared.askIfNeeded()
        return true
    }

    /// Après la désinstallation, quitter (⌘Q, fermeture de session…) ne doit rien réécrire : sortie directe.
    /// Début de la fermeture (journal : combien de temps elle prend).
    private var quitAsked: Date?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Uninstaller.didUninstall {
            SingleInstance.noteNoRelaunch()
            Uninstaller.quitAfterUninstall()
        }
        // Une copie relancée (« Quitter et rouvrir ») attend celle-ci au lieu de partir (SingleInstance).
        SingleInstance.markQuitting()
        quitAsked = Date()
        // « Quitter et rouvrir » de macOS : l'app quittait sans revenir (retour du propriétaire, trois fois) ; elle
        // se relance elle-même une fois partie (si macOS l'a déjà fait, ça ne fait que la mettre devant). Quittée
        // par l'utilisateur : le surveillant posé avec les Réglages ne la rouvre pas.
        let quit = SingleInstance.quitSender()
        let relaunch = SingleInstance.relaunches(quit)
        if relaunch {
            SingleInstance.relaunchAfterQuit()
        } else {
            SingleInstance.noteNoRelaunch()
        }
        MacroLog.shared.write("QUIT", "asked by \(quit?.label ?? "user")\(relaunch ? ", relaunch" : "")")
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Durée de chaque étape (millisecondes seulement) : où la fermeture passe son temps.
        var steps: [String] = []
        var mark = Date()
        func step(_ name: String) {
            steps.append("\(name) \(Int(Date().timeIntervalSince(mark) * 1000))")
            mark = Date()
        }
        // Ce qui est ouvert (et la macro en cours, enregistrée), pour reprendre là si l'app est rouverte aussitôt.
        if !DebugSnapshot.enabled {
            AppResume.shared.saveOnQuit(permissions: AccessibilityGuide.shared.isShowing,
                                        organizer: OrganizerWindow.controller != nil)
        }
        step("reprise")
        Store.shared.saveNow()
        Store.shared.library.saveNow()
        step("sauvegarde")
        EventTap.shared.stop()
        step("clavier")
        MIDILink.shared.stop()
        step("midi")
        let total = quitAsked.map { Int(Date().timeIntervalSince($0) * 1000) } ?? -1
        MacroLog.shared.write("QUIT", "\(total) ms since asked (" + steps.joined(separator: ", ") + ")")
        MacroLog.shared.flush()
    }

    private static func onboard() {
        OnboardingWindow.shared.show()          // accueil en 2 étapes (marqué « vu » après un choix, REL-23)
    }
}

/// État global affiché par le menu et l'éditeur ; superviseur du tap.
final class AppStatus: ObservableObject {
    static let shared = AppStatus()

    @Published private(set) var accessibilityOK = false {
        didSet { if oldValue, !accessibilityOK { ProblemLog.shared.add("Clavier : autorisation Accessibilité perdue") } }
    }
    @Published private(set) var secureInput = false
    @Published private(set) var tapRunning = false
    @Published private(set) var staleTCC = false {
        didSet { if staleTCC, !oldValue { ProblemLog.shared.add("Clavier : autorisation périmée (FL Shortcuts à retirer puis rajouter dans Accessibilité)") } }
    }
    @Published private(set) var tapUnstable = false {
        didSet { if tapUnstable, !oldValue { ProblemLog.shared.add("Clavier : macOS a coupé l'interception, elle a été relancée") } }
    }
    @Published private(set) var scriptState: ScriptIntegrity.State = .notInstalled
    @Published private(set) var capabilities: CapabilityMask? = nil
    @Published private(set) var flVersion: FLVersion? = nil
    /// Résultat de la dernière macro (« Macro terminée », « Macro arrêtée à l'étape 3 : … »), nil avant la première.
    @Published private(set) var lastMacro: (ok: Bool, text: String)? = nil
    /// Script de FL réécrit (nouvelle version, ou remis) pendant que FL tournait : FL ne relit ses scripts qu'en
    /// démarrant (« FL Shortcuts » absent de Controller type, ou ancienne version chargée). Effacé quand FL se ferme.
    @Published private(set) var scriptNeedsFLRestart = false

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var lastStartAttempt = Date.distantPast

    private init() {}

    func start() {
        // Disposition du clavier copiée sur le fil principal, pour les macros (leur file ne doit jamais la lire).
        KeyboardLayoutCopy.shared.start()
        Store.shared.availability = { [weak self] id in self?.availability(id) ?? .unverified }

        MIDILink.shared.$snapshot
            .map { $0.hello?.capabilities }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] caps in
                self?.capabilities = caps
                Store.shared.recompute()
            }
            .store(in: &cancellables)

        FLMonitor.shared.$running
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in if !AppMode.light { self?.refreshScriptState() } }
            .store(in: &cancellables)

        FLMonitor.shared.$running
            .dropFirst()                                 // valeur de départ : pas une fermeture de FL
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] running in if !running { self?.scriptNeedsFLRestart = false } }
            .store(in: &cancellables)

        FLMonitor.shared.$version
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] v in
                self?.flVersion = v
                Store.shared.recompute()
            }
            .store(in: &cancellables)

        observers.append(NotificationCenter.default.addObserver(forName: .macroFinished, object: nil, queue: .main) { [weak self] note in
            let ok = note.userInfo?["ok"] as? Bool ?? false
            let text = note.userInfo?["text"] as? String ?? ""
            let feedbackOnly = note.userInfo?["feedbackOnly"] as? Bool ?? false
            self?.lastMacro = (ok, text)
            // Dire pourquoi, pas seulement un bip (le larsen a déjà sa fenêtre).
            if !ok, !feedbackOnly {
                HintPanel.shared.flash(text)
            }
        })

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                EventTap.shared.purge()
            })
        }

        let updated = FLScriptInstaller.updateInstalledIfNeeded()   // script déjà installé : nouvelle version, même clé
        let repaired = FLScriptInstaller.repairIfNeeded() != nil    // clé là mais script disparu de FL : remis, même clé
        let flOpen = NSWorkspace.shared.runningApplications.contains { FLMatcher.isFL(bundleID: $0.bundleIdentifier) }
        if updated || repaired, flOpen { scriptNeedsFLRestart = true }
        if !AppMode.light { refreshScriptState() }
        supervise()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.supervise() }
        t.tolerance = 0.5                            // laisse macOS regrouper les réveils
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Le masque du script fait foi ; avant le handshake, la version lue dans le bundle de FL.
    func availability(_ id: Int) -> ActionAvailability {
        if AppMode.light {
            return AppMode.nativeEquivalent(of: id, layout: Store.shared.layout) != nil
                ? .available
                : .unavailable(reason: String(localized: "Demande le script MIDI dans FL (désactivé en mode léger)"))
        }
        return AvailabilityResolver.availability(of: id, caps: capabilities, flVersion: flVersion)
    }

    func refreshScriptState() {
        let s = ScriptIntegrity.check()
        if s != scriptState { scriptState = s }
    }

    /// Guide : ouvre Accessibilité et le Finder sur l'app, puis détecte l'autorisation tout seul.
    func requestAccessibility() { AccessibilityGuide.start() }

    func openAccessibilitySettings() { AccessibilityGuide.start() }

    /// Revérifie tout de suite (autorisation accordée pendant le guide).
    func recheck() {
        lastStartAttempt = .distantPast
        supervise()
    }

    func menuBarSymbol(enabled: Bool) -> String {
        if !enabled { return "pause.circle.fill" }
        if !accessibilityOK || secureInput || staleTCC { return "exclamationmark.triangle.fill" }
        return "keyboard.fill"
    }

    /// Toutes les 2 s (REL-08, REL-09, SEC-10).
    private func supervise() {
        let trusted = AXIsProcessTrusted()
        let secure = IsSecureEventInputEnabled()
        if secure != secureInput {
            secureInput = secure
            EventTap.shared.purge()                 // les keyUp ont pu être perdus (REL-04 a)
        }
        if trusted != accessibilityOK { accessibilityOK = trusted }

        let tap = EventTap.shared
        var running = false
        var stale = false
        if !trusted {
            if tap.isRunning { tap.stop() }
        } else if tap.consumeRestartRequest() {
            if !tapUnstable { tapUnstable = true }
            running = tap.restart()
            stale = !running
        } else if !tap.isRunning {
            // Permission cochée mais refusée (TCC périmé) : nouvel essai toutes les 10 s, pas toutes les 2 s.
            if Date().timeIntervalSince(lastStartAttempt) >= 10 {
                lastStartAttempt = Date()
                running = tap.start()
                stale = !running
            } else {
                stale = staleTCC
            }
        } else if !tap.isHealthy {
            // Recréation au plus toutes les 10 s : chaque recréation réenregistre le tap auprès du système.
            if Date().timeIntervalSince(lastStartAttempt) >= 10 {
                lastStartAttempt = Date()
                running = tap.restart()
            } else {
                running = tap.isRunning
            }
        } else {
            running = true
        }
        if running != tapRunning { tapRunning = running }
        if stale != staleTCC { staleTCC = stale }
        // Empreinte du script : vérifiée au lancement, quand FL démarre ou s'arrête (c'est là qu'il charge le
        // script) et après une installation ; plus de lecture disque périodique.
    }
}

/// Panneau flottant non activant visible tant que FL Shortcuts est en pause (audit 05 §4.4).
final class PauseIndicator {
    static let shared = PauseIndicator()
    private var panel: NSPanel?
    private var cancellable: AnyCancellable?
    /// Dernier état demandé : décide, à la fin d'un fondu de sortie, s'il faut vraiment cacher le panneau.
    private var wantsVisible = false

    private init() {}

    func bind() {
        cancellable = Store.shared.$enabled
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.update(paused: !enabled) }
    }

    /// Fondu d'entrée / de sortie (instantané si « Réduire les animations » est activé).
    private func update(paused: Bool) {
        let duration = Motion.reduce ? 0 : 0.22
        wantsVisible = paused
        guard paused else {
            guard let p = panel, p.isVisible else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = duration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                p.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                // Ne cacher que si on n'a pas été remis en pause pendant le fondu (état local, pas Store :
                // indépendant de l'ordre de publication de @Published).
                guard let self, !self.wantsVisible else { return }
                self.panel?.orderOut(nil)
            })
            return
        }
        let p = panel ?? makePanel()
        panel = p
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = p.frame.size
            p.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 16, y: frame.maxY - size.height - 12))
        }
        if !p.isVisible { p.alphaValue = 0 }
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }
    }

    private func makePanel() -> NSPanel {
        let host = NSHostingView(rootView: PauseBadge())
        let size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = host
        return p
    }
}

/// Petite étiquette opaque en haut à droite de l'écran, en capsule comme les pastilles de macOS 26. Jamais de verre :
/// elle reste affichée au-dessus de FL qui se redessine sans cesse (curseur de lecture, vumètres) ; un verre
/// recalculé à chaque image coûterait pendant tout le temps de la pause. Liseré clair statique en guise de reflet.
struct PauseBadge: View {
    private var shape: Capsule { Capsule() }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.orange)
            Text("FL Shortcuts en pause").font(.system(size: 12, weight: .semibold))
            Text("⌃⌥⌘F").font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(shape.fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color(nsColor: .separatorColor)],
                                                   startPoint: .top, endPoint: .bottom),
                                    lineWidth: 0.75))
        .accessibilityElement(children: .combine)
    }
}

/// Fenêtre principale demandée depuis le menu de l'icône : devant, même réduite dans le Dock ou derrière une autre.
enum MainWindow {
    static func bringForward() {
        NSApp.activate(ignoringOtherApps: true)
        // Après `openWindow` (la fenêtre peut venir d'être créée).
        DispatchQueue.main.async {
            guard let window = AppResume.shared.editorWindow else { return }
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
    }
}

/// Panneau de la barre des menus : en-tête avec l'icône de l'app et le statut, puis les options, chacune avec son
/// icône de couleur et, au survol, la carte du guide (elle grossit avec son liseré de couleur). Sur le verre des
/// menus, la lueur des couleurs de l'app (jamais de verre sur du verre).
struct MenuContent: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var library = MacroLibraryStore.shared
    @EnvironmentObject var status: AppStatus
    @EnvironmentObject var link: MIDILink
    @EnvironmentObject var fl: FLMonitor
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var panel = MenuPanel.shared
    @ObservedObject private var approval = CopyApproval.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Plus de logo ni de titre en haut (28/10, « enlève prêt, FL Shortcuts, le logo ») : seulement ce qui
            // cloche (en pause, clavier non autorisé, FL fermé…), rien quand tout va bien.
            if let line = statusLine {
                HStack(spacing: 5) {
                    Circle().fill(dotColor).frame(width: 7, height: 7)
                    Text(line).foregroundStyle(.secondary).lineLimit(1)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .padding(.bottom, 6)
                .accessibilityElement(children: .combine)
            }

            // Seulement un échec (« Macro terminée » retiré à la demande de l'utilisateur : rien à dire quand tout va bien).
            if let macro = status.lastMacro, !macro.ok {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.orange)
                    Text(macro.text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                // La page Aide, le formulaire prêt avec ce message d'erreur et le journal de la macro.
                PanelItem(symbol: "exclamationmark.bubble", title: String(localized: "Signaler ce problème…"), tint: .orange, order: 1) {
                    HelpLink.shared.report("Macro : " + macro.text)
                    openWindow(id: "editor")
                    MainWindow.bringForward()
                }
            }

            ForEach(alerts, id: \.self) { text in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }

            if hasNotice { MenuSeparator() }

            if !status.accessibilityOK {
                PanelItem(symbol: "lock.open", title: String(localized: "Tout autoriser…"), tint: .orange, order: 2) {
                    AccessibilityGuide.start()
                }
            }
            PanelItem(symbol: "keyboard", title: String(localized: "Modifier les raccourcis…"), tint: .blue, order: 3) {
                ShortcutsLink.shared.show()                 // jamais laissée sur Macros, Communauté ou le créateur
                openWindow(id: "editor")
                MainWindow.bringForward()
            }
            PanelItem(symbol: SidebarItem.macros.symbol, title: String(localized: "Macros…"), tint: SidebarItem.macros.tint,
                      order: 4) {
                MacrosLink.shared.show()
                openWindow(id: "editor")
                MainWindow.bringForward()
            }
            if !approval.pending.isEmpty {
                // Une version organisée attend une réponse (« Plus tard », ou la question fermée).
                PanelItem(symbol: "checkmark.seal", title: String(localized: "Valider la version organisée…"),
                          tint: .green, order: 5) { CopyApprovalWindow.shared.show() }
            }
            PanelItem(symbol: "square.stack.3d.up", title: String(localized: "Organiser…"),
                      tint: OrganizerView.tint, order: 5) { OrganizerWindow.open() }
            // « Mettre en pause » retiré (28/10, « il sert à rien ») ; si l'app est en pause (⌃⌥⌘F), on peut toujours
            // reprendre d'ici.
            if !store.enabled {
                PanelItem(symbol: "play", title: String(localized: "Reprendre"), shortcut: "⌃⌥⌘F", tint: .green,
                          order: 6) { store.enabled = true }
            }
            if !AppMode.light {
                PanelItem(symbol: "link", title: String(localized: "Installer le lien avec FL Studio…"), tint: .green, order: 7) {
                    FLScriptInstaller.installWithAlert()
                }
            }

            MenuSeparator()

            PanelItem(symbol: "trash", title: String(localized: "Désinstaller FL Shortcuts…"), tint: .red, order: 8) {
                Uninstaller.confirmAndRun()
            }

            MenuSeparator()

            // Pied du panneau (maquette validée le 28/10) : ouvrir la fenêtre à gauche, quitter à droite.
            HStack(spacing: 8) {
                PanelFooterButton(title: String(localized: "Ouvrir FL Shortcuts"), tint: .blue, prominent: true) {
                    openWindow(id: "editor")
                    MainWindow.bringForward()
                }
                Spacer(minLength: 8)
                PanelFooterButton(title: String(localized: "Quitter"), detail: "⌘Q", tint: .gray, key: "q") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(8)
        .frame(width: 300)
        // Rien que le verre du menu derrière (28/10 : « pas de fond ») : plus de fondu de couleur.
        // Sort de l'icône à chaque ouverture ; se ferme au choix d'une ligne ou d'un clic ailleurs (MenuPanel).
        .menuReveal(panel.revealed)
        .background(WindowReader { MenuPanel.shared.attach($0) })
        .onAppear { MenuPanel.shared.appeared() }
    }

    /// Quelque chose est écrit au-dessus des lignes (état, échec d'une macro, avertissement) : un filet les sépare.
    private var hasNotice: Bool {
        statusLine != nil || status.lastMacro.map { !$0.ok } == true || !alerts.isEmpty
    }

    private var dotColor: Color {
        AppStatusColor.color(enabled: store.enabled, accessibilityOK: status.accessibilityOK, flRunning: fl.running,
                             link: link.status)
    }

    /// Chaîne calculée à part : pas de fermeture imbriquée dans une interpolation de LocalizedStringKey. nil quand
    /// tout va bien : ni « Actif », ni la version de FL (demandé par l'utilisateur), seulement ce qui cloche.
    private var statusLine: String? {
        guard store.enabled else { return String(localized: "En pause") }
        if !status.accessibilityOK { return String(localized: "Clavier non autorisé") }
        // FL fermé : rien (29/10, « FL n'est pas ouvert, tu peux l'enlever »).
        if AppMode.light { return nil }
        switch link.status {
        case .linked, .flClosed: return nil
        case .inactive: return String(localized: "Lien inactif")
        }
    }

    private var alerts: [String] {
        var out: [String] = []
        if status.scriptNeedsFLRestart {
            out.append(String(localized: "Le lien avec FL vient d'être mis à jour : quitte et rouvre FL Studio pour qu'il le charge."))
        }
        if status.staleTCC {
            out.append(String(localized: "Autorisation périmée : retire FL Shortcuts de la liste Accessibilité puis ajoute-le."))
        }
        if status.secureInput { out.append(String(localized: "Saisie sécurisée active dans une autre app : raccourcis muets.")) }
        if status.tapUnstable { out.append(String(localized: "macOS a coupé l'interception plusieurs fois : elle a été relancée.")) }
        if !AppMode.light, status.scriptState == .modified {
            out.append(String(localized: "Le script FL a été modifié : réinstalle le lien."))
        }
        if !AppMode.light, link.uniqueIDConflict {
            out.append(String(localized: "Conflit de port MIDI : une autre copie de FL Shortcuts tourne peut-être."))
        }
        if let warning = store.loadWarning { out.append(warning) }
        if let error = store.saveError { out.append(error) }
        if let problem = library.problem { out.append(problem) }
        return out
    }
}

/// Filet entre deux groupes de lignes, comme dans un menu.
private struct MenuSeparator: View {
    var body: some View {
        Divider().padding(.horizontal, 8).padding(.vertical, 4)
    }
}

/// Lien du pied du panneau : « Ouvrir FL Shortcuts » en bleu, « Quitter ⌘Q » en gris. Même survol que les lignes
/// (contour de sa couleur et halo dehors, le texte ne bouge pas).
private struct PanelFooterButton: View {
    let title: String
    var detail: String? = nil
    var tint: Color = .gray
    var prominent = false
    /// Raccourci réellement actif dans le panneau (avec ⌘).
    var key: KeyEquivalent? = nil
    let action: () -> Void

    var body: some View {
        Button {
            action()
            MenuPanel.shared.close()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .fontWeight(prominent ? .medium : .regular)
                    .foregroundStyle(prominent ? tint : Color.primary.opacity(0.75))
                if let detail {
                    Text(verbatim: detail).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .menuHover(tint: tint, cornerRadius: 8)
        .keyboardShortcut(key.map { KeyboardShortcut($0, modifiers: .command) })
    }
}

/// Option du panneau : icône de couleur à gauche (une colonne facile à parcourir) ; au survol, la carte du guide :
/// voile clair et liseré de sa couleur, qui grossissent ensemble avec une ombre douce de sa couleur. Choisie, elle
/// ferme le menu ; à l'ouverture, elle arrive à son tour (`order`), son icône éclot juste après.
private struct PanelItem: View {
    let symbol: String
    let title: String
    var shortcut: String? = nil
    /// Raccourci réellement actif dans le panneau (avec ⌘).
    var key: KeyEquivalent? = nil
    var tint: Color = .gray
    var order = 0
    let action: () -> Void
    @State private var hovering = false
    @ObservedObject private var panel = MenuPanel.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    var body: some View {
        Button {
            // L'action d'abord (une fenêtre qui s'ouvre prend la main), puis le menu se ferme : la fenêtre ouverte
            // reste devant (MenuPanel).
            action()
            MenuPanel.shared.close()
        } label: {
            HStack(spacing: 10) {
                SectionIcon(symbol: symbol, tint: tint, size: 22)
                    .scaleEffect(panel.revealed || reduceMotion ? 1 : 0.35)
                    .rotationEffect(.degrees(panel.revealed || reduceMotion ? 0 : -25))
                    .animation(panel.revealed
                               ? .spring(response: 0.5, dampingFraction: 0.58).delay(0.12 + Double(order) * 0.04)
                               : .easeIn(duration: 0.12), value: panel.revealed)
                Text(title)
                Spacer(minLength: 12)
                if let shortcut {
                    Text(shortcut).foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(height: 34)
            .contentShape(shape)
            .background {
                shape.fill(Color.primary.opacity(hovering ? 0.085 : 0))
                    .overlay(shape.strokeBorder(tint.opacity(hovering ? 0.6 : 0), lineWidth: hovering ? 1.5 : 1))
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering && !reduceMotion ? 1.03 : 1)
        .shadow(color: tint.opacity(hovering ? 0.3 : 0), radius: hovering ? 10 : 0, y: hovering ? 4 : 0)
        .keyboardShortcut(key.map { KeyboardShortcut($0, modifiers: .command) })
        .onHover { inside in
            withAnimation(reduceMotion ? Motion.reduced : Motion.lift) { hovering = inside }
        }
        .menuRevealRow(panel.revealed, index: order)
    }
}
