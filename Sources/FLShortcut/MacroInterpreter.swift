// Interpréteur des macros en blocs : contrôle du déroulement seulement, sans AppKit, testable avec de faux effets
// (FakeEffects dans les tests). Les effets réels (touches, clics, fenêtres, FL) sont dans MacroEffectsMac.swift et
// MacroFLBlocks.swift : les garde-fous restent dans la couche d'effets, jamais dans les blocs.
// Règles reprises de l'ancien moteur, à l'identique :
//  - « Échap / FL plus devant » vérifié avant chaque bloc ; journal « STEP n/total nom … » puis « STEP n nom → … » ;
//  - actions de FL CONSÉCUTIVES regroupées en un seul réveil du lien (généralisation de la fusion armement + REC) ;
//  - vérification du larsen lancée dès le début si un bloc la demande, n'importe où dans l'arbre ;
//  - en tête de macro, contrôle de la piste visée et attente du clavier au repos, pilotés par les besoins
//    (`.pisteRequise`, `.attenteClavierInterne`) du premier bloc ;
//  - avertissements cumulés (« … ; … »), nettoyage (pointeur remis) quoi qu'il arrive.
import Foundation

enum MacroOutcome: Equatable {
    case done
    case doneWithWarning(String)
    case failed(step: Int, reason: String)
    /// Échec d'un bloc imbriqué (« 3.2 »).
    case failedInBlock(path: String, label: String, reason: String)
    /// Bloc « Arrêter la macro ».
    case stopped(String?)
    case cancelled(reason: String)

    var text: String {
        switch self {
        case .done: return "Macro terminée"
        case .doneWithWarning(let why): return "Macro terminée, mais \(why)"
        case .failed(let step, let reason): return "Macro arrêtée à l'étape \(step) : \(reason)"
        case .failedInBlock(let path, let label, let reason): return "Macro arrêtée au bloc \(path) (\(label)) : \(reason)"
        case .stopped(let message): return message.map { "Macro arrêtée : \($0)" } ?? "Macro arrêtée par son bloc « Arrêter »"
        case .cancelled(let reason): return "Macro annulée : \(reason)"
        }
    }
}

enum StepResult: Equatable {
    case ok
    case warn(String)        // bloc fait, avec un avertissement affiché à la fin
    case fail(String)
    case cancel(String)
}

enum StepFailure: Error, Equatable {
    case fail(String)
    case cancel(String)
}

/// Une action de FL d'un groupe (blocs `flAction` consécutifs).
struct FLActionCall: Equatable {
    var key: String
    var fallback: ActionFallback
}

/// État d'un passage partagé entre les blocs (variables, dernier échec, compteurs). L'état propre au Mac (boîte de
/// dialogue suivie, piste visée, pointeur à remettre…) vit dans l'objet d'effets, neuf à chaque passage.
struct RunState {
    var variables: [String: Int] = [:]
    var lastFailed = false
    /// Blocs exécutés (garde-fou d'exécution).
    var executed = 0
    var warnings: [String] = []
    var startedAt = Date()
}

/// Effets d'une macro (macOS : MacroEffectsMac ; tests : faux effets). Appelés sur la file de la macro.
protocol MacroEffects: AnyObject {
    /// Journal : jamais une touche, un chemin ou un nom de piste.
    func log(_ tag: String, _ text: String)
    /// Relevés du départ (pointeur, fenêtres, piste visée), larsen lancé en avance si demandé.
    /// nil = prêt, sinon la raison du refus (autorisation manquante…).
    func begin(startFeedbackEarly: Bool) -> String?
    /// La piste visée est dans une fenêtre de FL.
    func targetTrackIsInFL() -> Bool
    /// Touches du raccourci relâchées ; faux si des modificateurs restent enfoncés.
    func waitForKeyboardIdle(timeout: TimeInterval) -> Bool
    /// Raison d'arrêter maintenant (FL plus au premier plan, Échap), sinon nil.
    func stopReason() -> String?
    /// Blocs simples (pas de contrôle, pas d'action de FL).
    func perform(_ body: BlockBody, state: inout RunState) -> StepResult
    /// Actions de FL consécutives : un seul réveil du lien ; sans lien, leurs replis un par un, dans l'ordre.
    func flActions(_ group: [FLActionCall], state: inout RunState) -> StepResult
    /// Conditions qui regardent FL (fenêtre ouverte, état de FL) ; les autres sont évaluées par l'interpréteur.
    func evaluate(_ c: Condition, state: inout RunState) -> Result<Bool, StepFailure>
    func pause(ms: Int) -> StepResult
    /// Toujours appelé à la fin (pointeur remis à sa place…).
    func cleanup(state: inout RunState)
}

/// Suivi d'un essai depuis l'éditeur (incrément 3) : nil ailleurs, donc aucun coût.
protocol RunObserver: AnyObject {
    func blockStarted(_ id: UUID, path: String)
    func blockFinished(_ id: UUID, path: String, result: StepResult, ms: Int)
}

/// Garde-fou d'exécution : jamais plus de 2 000 blocs ni 300 s, même avec des boucles.
struct RuntimeLimits {
    var maxBlocks = 2_000
    var maxSeconds: TimeInterval = 300

    static let standard = RuntimeLimits()
}

final class MacroInterpreter {
    private let effects: MacroEffects
    private weak var observer: RunObserver?
    private let limits: RuntimeLimits
    private let clock: () -> Date

    init(effects: MacroEffects, observer: RunObserver? = nil, limits: RuntimeLimits = .standard,
         clock: @escaping () -> Date = Date.init) {
        self.effects = effects
        self.observer = observer
        self.limits = limits
        self.clock = clock
    }

    private enum Flow: Equatable {
        case next
        case stop(String?)
        case fail(path: String, label: String, reason: String)
        case cancel(String)
    }

    /// Délai entre deux vérifications d'une condition « attendre que ».
    static let pollMs = 250

    func run(_ program: MacroProgram) -> MacroOutcome {
        var state = RunState(startedAt: clock())
        for v in program.variables { state.variables[v.name] = v.initial }
        defer { effects.cleanup(state: &state) }
        guard program.isRunnable else { return .failed(step: 1, reason: program.problem ?? "macro invalide") }
        if let why = effects.begin(startFeedbackEarly: program.needs.contains(.larsenEnAvance)) {
            return .failed(step: 1, reason: why)
        }
        let first = program.blocks.first { $0.enabled && $0.body.type != .comment }
        let firstNeeds = first.map { BlockRegistry.needs(of: $0.body) } ?? []
        if firstNeeds.contains(.pisteRequise), !effects.targetTrackIsInFL() {
            return .failed(step: 1, reason: "clique d'abord sur ta piste dans le Mixer de FL, puis refais le raccourci")
        }
        // Un bloc qui clique sur la piste attend lui-même le clavier au repos ; les autres premiers blocs, ici.
        if firstNeeds.contains(.clavierAuRepos), !firstNeeds.contains(.attenteClavierInterne),
           !effects.waitForKeyboardIdle(timeout: 1.5) {
            return .cancelled(reason: "relâche les touches du raccourci")
        }
        switch run(program.blocks, prefix: "", offset: 0, state: &state) {
        case .next:
            return state.warnings.isEmpty ? .done : .doneWithWarning(state.warnings.joined(separator: " ; "))
        case .stop(let message):
            return .stopped(message)
        case .fail(let path, let label, let reason):
            if let n = Int(path) { return .failed(step: n, reason: reason) }
            return .failedInBlock(path: path, label: label, reason: reason)
        case .cancel(let why):
            return .cancelled(reason: why)
        }
    }

    private func describe(_ r: StepResult) -> String {
        switch r {
        case .ok: return "ok"
        case .warn(let why): return "warn: \(why)"
        case .fail(let why): return "FAIL: \(why)"
        case .cancel(let why): return "cancel: \(why)"
        }
    }

    private func ms(since t: Date) -> Int { Int(clock().timeIntervalSince(t) * 1000) }

    private func run(_ blocks: [Block], prefix: String, offset: Int, state: inout RunState) -> Flow {
        let total = offset + blocks.count
        var index = 0
        while index < blocks.count {
            let block = blocks[index]
            let path = MacroValidation.path(prefix, offset + index + 1)
            index += 1
            guard block.enabled else { continue }
            if case .comment = block.body { continue }
            let label = BlockRegistry.label(of: block.body)
            if state.executed >= limits.maxBlocks {
                return .fail(path: path, label: label, reason: "trop de blocs exécutés (\(limits.maxBlocks) au plus)")
            }
            if clock().timeIntervalSince(state.startedAt) > limits.maxSeconds {
                return .fail(path: path, label: label, reason: "macro trop longue (\(Int(limits.maxSeconds)) s au plus)")
            }
            if let stop = effects.stopReason() { return .cancel(stop) }

            // Actions de FL consécutives (blocs inactifs sautés) : un seul réveil du lien.
            var group = [block]
            if case .flAction = block.body {
                while index < blocks.count {
                    let next = blocks[index]
                    if !next.enabled { index += 1; continue }
                    guard case .flAction = next.body, next.onFailure == block.onFailure else { break }
                    group.append(next)
                    index += 1
                }
            }

            let name = BlockRegistry.journal(of: block.body)
            effects.log("STEP", "\(path)/\(total) \(name) …")
            for b in group { observer?.blockStarted(b.id, path: path) }
            let began = clock()
            state.executed += group.count

            var result: StepResult
            var inner = Flow.next
            switch block.body {
            case .flAction:
                let calls = group.compactMap { b -> FLActionCall? in
                    guard case .flAction(let key, let fallback) = b.body else { return nil }
                    return FLActionCall(key: key, fallback: fallback)
                }
                result = effects.flActions(calls, state: &state)

            case .ifElse(let c, let then, let otherwise):
                switch evaluate(c, &state) {
                case .success(let yes):
                    inner = yes ? run(then, prefix: path, offset: 0, state: &state)
                                : run(otherwise, prefix: path, offset: then.count, state: &state)
                    result = .ok
                case .failure(let f):
                    result = Self.result(f)
                }

            case .repeatCount(let n, let body):
                result = .ok
                for _ in 0..<max(n, 0) {
                    inner = run(body, prefix: path, offset: 0, state: &state)
                    if inner != .next { break }
                }

            case .repeatWhile(let c, let maxTurns, let body):
                result = .ok
                var turns = 0
                loop: while true {
                    switch evaluate(c, &state) {
                    case .success(false):
                        break loop
                    case .success(true):
                        guard turns < maxTurns else {
                            result = .fail("condition toujours vraie après \(maxTurns) tours")
                            break loop
                        }
                        turns += 1
                        inner = run(body, prefix: path, offset: 0, state: &state)
                        if inner != .next { break loop }
                    case .failure(let f):
                        result = Self.result(f)
                        break loop
                    }
                }

            case .waitUntil(let c, let timeoutMs):
                result = waitUntil(c, timeoutMs: timeoutMs, began: began, state: &state)

            case .setVariable(let variable, let source):
                switch value(of: source, state: state) {
                case .success(let v):
                    state.variables[variable] = v
                    result = .ok
                case .failure(let f):
                    result = Self.result(f)
                }

            case .stop(let message):
                effects.log("STEP", "\(path) \(name) → ok in \(ms(since: began)) ms")
                for b in group { observer?.blockFinished(b.id, path: path, result: .ok, ms: ms(since: began)) }
                return .stop(message)

            case .unknown:
                result = .fail("bloc inconnu : macro d'une version plus récente")

            default:
                result = effects.perform(block.body, state: &state)
            }

            let elapsed = ms(since: began)
            if inner != .next {
                // Un bloc imbriqué a arrêté la macro : son propre chemin est gardé.
                effects.log("STEP", "\(path) \(name) → \(innerText(inner)) in \(elapsed) ms")
                for b in group { observer?.blockFinished(b.id, path: path, result: .ok, ms: elapsed) }
                return inner
            }
            effects.log("STEP", "\(path) \(name) → \(describe(result)) in \(elapsed) ms")
            for b in group { observer?.blockFinished(b.id, path: path, result: result, ms: elapsed) }
            switch result {
            case .ok:
                state.lastFailed = false
            case .warn(let why):
                state.lastFailed = false
                state.warnings.append(why)
            case .fail(let why):
                guard block.onFailure == .keepGoing else { return .fail(path: path, label: label, reason: why) }
                state.lastFailed = true
                state.warnings.append("étape \(path) non faite (\(why))")
            case .cancel(let why):
                return .cancel(why)
            }
        }
        return .next
    }

    private func innerText(_ f: Flow) -> String {
        switch f {
        case .next: return "ok"
        case .stop: return "stop"
        case .fail(let path, _, let why): return "FAIL at \(path): \(why)"
        case .cancel(let why): return "cancel: \(why)"
        }
    }

    private static func result(_ f: StepFailure) -> StepResult {
        switch f {
        case .fail(let why): return .fail(why)
        case .cancel(let why): return .cancel(why)
        }
    }

    private func waitUntil(_ c: Condition, timeoutMs: Int, began: Date, state: inout RunState) -> StepResult {
        while true {
            switch evaluate(c, &state) {
            case .success(true):
                return .ok
            case .success(false):
                if ms(since: began) >= timeoutMs {
                    return .fail("condition toujours fausse après \(timeoutMs / 1000) s")
                }
                let p = effects.pause(ms: Self.pollMs)
                if case .cancel = p { return p }
            case .failure(let f):
                return Self.result(f)
            }
        }
    }

    /// Conditions sans effet évaluées ici ; celles qui regardent FL, par les effets.
    private func evaluate(_ c: Condition, _ state: inout RunState) -> Result<Bool, StepFailure> {
        switch c {
        case .variable(let name, let op, let v):
            return .success(op.holds(state.variables[name] ?? 0, v))
        case .lastBlockFailed:
            return .success(state.lastFailed)
        case .not(let inner):
            return evaluate(inner, &state).map { !$0 }
        case .all(let list):
            for x in list {
                switch evaluate(x, &state) {
                case .success(true): continue
                case .success(false): return .success(false)
                case .failure(let f): return .failure(f)
                }
            }
            return .success(true)
        case .any(let list):
            for x in list {
                switch evaluate(x, &state) {
                case .success(true): return .success(true)
                case .success(false): continue
                case .failure(let f): return .failure(f)
                }
            }
            return .success(false)
        case .windowOpen, .flState:
            return effects.evaluate(c, state: &state)
        }
    }

    private func value(of source: IntSource, state: RunState) -> Result<Int, StepFailure> {
        switch source {
        case .constant(let v): return .success(v)
        case .variable(let name): return .success(state.variables[name] ?? 0)
        case .flState: return .failure(.fail("lecture de l'état de FL : demande l'extension du lien avec FL"))
        }
    }
}
