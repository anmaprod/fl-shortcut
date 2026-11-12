import AppKit

/// « Quitter et rouvrir FL » (12/11, « le bouton quitter et rouvrir… il ne rouvre pas automatiquement FL Studio ») :
/// décide à chaque coup d'œil (toutes les 0,5 s) s'il faut attendre, lancer FL ou s'arrêter. Le FL d'avant est attendu
/// jusqu'à son départ (le temps de répondre à « Enregistrer ? », 5 minutes au plus), puis FL est lancé une seconde
/// après ; s'il n'apparaît pas, relancé (3 fois au plus, une erreur de lancement : 2 s après). Un nouveau FL, même
/// rouvert à la main, finit l'attente : rien n'est lancé en plus. Windows : FlRelaunchPlan (mêmes règles, mêmes essais).
struct FLRelaunchPlan {
    enum Step: Equatable { case wait, launch, done, giveUp }

    static let quitLimit: TimeInterval = 300
    static let settle: TimeInterval = 1
    static let launchCheck: TimeInterval = 20
    static let retryAfterError: TimeInterval = 2
    static let maxLaunches = 3

    let oldPID: Int32
    let started: TimeInterval
    private var nextLaunch: TimeInterval?
    private(set) var launches = 0
    /// Quand le FL d'avant est parti (secondes depuis le début), pour le journal.
    private(set) var goneAt: TimeInterval?

    init(oldPID: Int32, now: TimeInterval) {
        self.oldPID = oldPID
        started = now
    }

    /// `running` : les FL qui tournent maintenant (numéros de processus).
    mutating func next(now: TimeInterval, running: [Int32]) -> Step {
        if running.contains(where: { $0 != oldPID }) { return .done }
        if running.contains(oldPID) { return now - started >= Self.quitLimit ? .giveUp : .wait }
        if goneAt == nil {
            goneAt = now
            nextLaunch = now + Self.settle
        }
        guard let at = nextLaunch, now >= at else { return .wait }
        guard launches < Self.maxLaunches else { return .giveUp }
        launches += 1
        nextLaunch = now + Self.launchCheck
        return .launch
    }

    /// Le lancement a échoué tout de suite : nouvel essai bientôt.
    mutating func launchFailed(now: TimeInterval) {
        nextLaunch = now + Self.retryAfterError
    }
}

/// La relance elle-même, sur le fil principal : FL quitté comme par ⌘Q (il demande d'enregistrer s'il le faut), puis
/// regardé toutes les 0,5 s. Avant le 12/11 : un fil d'arrière-plan attendait `isTerminated` d'une app gardée (que
/// macOS ne met à jour qu'aux tours du fil principal) et lançait FL une seule fois, sans vérifier ni rien noter.
/// Maintenant la liste des apps est relue à chaque coup d'œil et le système dit si le processus existe encore ; FL est
/// lancé, puis relancé s'il n'apparaît pas. Journal `RESTART` (nombres seulement).
final class FLRelauncher {
    static let shared = FLRelauncher()
    static let bundleID = "com.image-line.flstudio"

    private var timer: Timer?
    private var plan: FLRelaunchPlan?
    private var url: URL?
    private var clock = Date()

    /// Une relance en cours : les clics suivants ne font rien (09/11, « plusieurs clics = autant de FL »).
    var restarting: Bool { timer != nil }

    /// Faux si FL ne tourne pas ou si une relance est déjà en cours.
    @discardableResult
    func restart() -> Bool {
        guard timer == nil, let app = Self.runningFL().first,
              let url = app.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleID)
        else { return false }
        let asked = app.terminate()
        MacroLog.shared.write("RESTART", "FL quit asked: \(asked ? "yes" : "refused")")
        self.url = url
        clock = Date()
        plan = FLRelaunchPlan(oldPID: app.processIdentifier, now: 0)
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        return true
    }

    private func tick() {
        guard var plan, let url else { return stop() }
        let now = Date().timeIntervalSince(clock)
        let step = plan.next(now: now, running: Self.runningFL().map(\.processIdentifier))
        self.plan = plan
        switch step {
        case .wait:
            break
        case .launch:
            let number = plan.launches
            MacroLog.shared.write("RESTART", String(format: "FL gone after %.1f s, launch %d at %.1f s",
                                                    plan.goneAt ?? now, number, now))
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] launched, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let error {
                        MacroLog.shared.write("RESTART", "launch \(number) error \((error as NSError).code)")
                        self.plan?.launchFailed(now: Date().timeIntervalSince(self.clock))
                    } else {
                        MacroLog.shared.write("RESTART", "launch \(number) started, pid \(launched?.processIdentifier ?? 0)")
                    }
                }
            }
        case .done:
            MacroLog.shared.write("RESTART", String(format: "FL back after %.1f s (%d launch(es))", now, plan.launches))
            stop()
        case .giveUp:
            MacroLog.shared.write("RESTART", plan.goneAt == nil
                ? String(format: "FL still running after %.0f s: nothing launched", now)
                : String(format: "FL not back after %d launch(es), %.0f s", plan.launches, now))
            stop()
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        plan = nil
        url = nil
    }

    /// Les FL qui tournent vraiment : liste relue, processus encore présent pour le système.
    static func runningFL() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { app in
            !app.isTerminated && (kill(app.processIdentifier, 0) == 0 || errno == EPERM)
        }
    }
}
