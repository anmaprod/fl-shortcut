// Suivi d'un essai lancé depuis le créateur de macros : adaptateur du protocole RunObserver de l'interpréteur.
// - Branché SEULEMENT pendant un essai depuis le créateur (le raccourci, lui, tourne sans observateur : aucun coût).
// - Publie le bloc en cours et un rapport par bloc borné (200 entrées) : seules les lignes concernées se redessinent
//   (lignes Equatable, aucun objet observé par ligne).
// - `start` est le chemin unique de l'essai : le bouton « Tester » du créateur ET l'essai « blocs » de la CI
//   (MacroSelfTest) passent par lui, puis par MacroRunner.start, comme un vrai raccourci.
import Combine
import Foundation

final class MacroRunMonitor: ObservableObject, RunObserver {
    /// État d'un bloc pendant ou après l'essai.
    enum Status: Equatable {
        case running
        case done(ms: Int)
        case warned(String)
        case failed(String)
        case cancelled(String)
    }

    static let maxEntries = 200

    @Published private(set) var current: UUID?
    @Published private(set) var statuses: [UUID: Status] = [:]
    @Published private(set) var outcome: MacroOutcome?
    @Published private(set) var running = false
    /// Bloc qui a fait échouer l'essai (« Montrer le bloc »).
    @Published private(set) var failedBlock: UUID?
    /// Durée totale du dernier essai.
    private(set) var totalMs = 0
    private var startedAt = Date()

    init() {}

    // MARK: RunObserver (file de la macro → thread principal)

    func blockStarted(_ id: UUID, path: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running else { return }
            self.current = id
            self.set(id, .running)
        }
    }

    func blockFinished(_ id: UUID, path: String, result: StepResult, ms: Int) {
        let status: Status
        switch result {
        case .ok: status = .done(ms: ms)
        case .warn(let why): status = .warned(why)
        case .fail(let why): status = .failed(why)
        case .cancel(let why): status = .cancelled(why)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running else { return }
            if self.current == id { self.current = nil }
            self.set(id, status)
            if case .failed = status, self.failedBlock == nil { self.failedBlock = id }
        }
    }

    private func set(_ id: UUID, _ status: Status) {
        guard statuses[id] != status else { return }
        if statuses[id] == nil, statuses.count >= Self.maxEntries { return }     // rapport borné
        statuses[id] = status
    }

    // MARK: Essai

    /// Efface le dernier rapport (nouvel essai, macro modifiée).
    func clear() {
        current = nil
        if !statuses.isEmpty { statuses = [:] }
        outcome = nil
        failedBlock = nil
        running = false
    }

    /// Lance l'essai (thread principal) : FL doit déjà être au premier plan. Même démarrage qu'un raccourci.
    @discardableResult
    func start(_ program: MacroProgram, pid: Int32, completion: ((MacroOutcome) -> Void)? = nil) -> MacroRunner.StartResult {
        clear()
        running = true
        startedAt = Date()
        let result = MacroRunner.shared.start(program, flPID: pid, observer: self) { [weak self] outcome in
            guard let self else { return }
            self.totalMs = Int(Date().timeIntervalSince(self.startedAt) * 1000)
            self.running = false
            self.current = nil
            self.outcome = outcome
            completion?(outcome)
        }
        if result != .started { running = false }
        return result
    }

    /// Essai impossible avant même de démarrer (FL fermé, macro invalide) : affiché comme un échec.
    func refuse(_ reason: String) {
        clear()
        outcome = .cancelled(reason: reason)
    }

    /// Capture de l'interface (mesure, `debugSnapshots` seulement) : rapport d'un essai fictif pour montrer les
    /// couleurs (fait, en cours, échec) sans lancer FL.
    func showSampleReport(done: [UUID], failed: UUID?, reason: String) {
        clear()
        for id in done { statuses[id] = .done(ms: 120) }
        if let failed {
            statuses[failed] = .failed(reason)
            failedBlock = failed
        }
        outcome = .failed(step: done.count + 1, reason: reason)
    }
}
