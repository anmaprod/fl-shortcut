// Interpréteur des macros en blocs (miroir de Sources/FLShortcut/MacroInterpreter.swift) : contrôle du déroulement
// seulement, sans Windows, testable avec de faux effets (FakeEffects dans les essais). Les effets réels (touches,
// clics, fenêtres, FL) sont dans l'appli : les garde-fous restent dans la couche d'effets, jamais dans les blocs.
// Mêmes règles que le Mac, à l'identique :
//  - « Échap / FL plus devant » vérifié avant chaque bloc ; journal « STEP n/total nom … » puis « STEP n nom → … » ;
//  - actions de FL CONSÉCUTIVES regroupées en un seul réveil du lien ;
//  - vérification du larsen lancée dès le début si un bloc la demande, n'importe où dans l'arbre ;
//  - en tête de macro, contrôle de la piste visée et attente du clavier au repos, pilotés par les besoins
//    (`TrackRequired`, `KeyboardIdleInside`) du premier bloc ;
//  - avertissements cumulés (« … ; … »), nettoyage (pointeur remis) quoi qu'il arrive.
namespace FLShortcut.Core.Macros;

public abstract record MacroOutcome
{
    public sealed record Done : MacroOutcome;
    public sealed record DoneWithWarning(string Why) : MacroOutcome;
    public sealed record Failed(int Step, string Reason) : MacroOutcome;
    /// Échec d'un bloc imbriqué (« 3.2 »).
    public sealed record FailedInBlock(string Path, string Label, string Reason) : MacroOutcome;
    /// Bloc « Arrêter la macro ».
    public sealed record Stopped(string? Message) : MacroOutcome;
    public sealed record Cancelled(string Reason) : MacroOutcome;

    public string Text => this switch
    {
        DoneWithWarning w => Loc.F("Macro terminée, mais %@", w.Why),
        Failed f => Loc.F("Macro arrêtée à l'étape %lld : %@", f.Step, f.Reason),
        FailedInBlock f => Loc.F("Macro arrêtée au bloc %@ (%@) : %@", f.Path, f.Label, f.Reason),
        Stopped { Message: { } m } => Loc.F("Macro arrêtée : %@", m),
        Stopped => Loc.T("Macro arrêtée par son bloc « Arrêter »"),
        Cancelled c => Loc.F("Macro annulée : %@", c.Reason),
        _ => Loc.T("Macro terminée"),
    };
}

public abstract record StepResult
{
    public sealed record Ok : StepResult;
    /// Bloc fait, avec un avertissement affiché à la fin.
    public sealed record Warn(string Why) : StepResult;
    public sealed record Fail(string Why) : StepResult;
    public sealed record Cancel(string Why) : StepResult;
}

/// Réponse d'une condition : vrai ou faux, ou l'échec / l'annulation qui arrête son bloc.
public readonly record struct ConditionAnswer(bool Value, StepResult? Failure = null)
{
    public static ConditionAnswer Of(bool value) => new(value);
    public static ConditionAnswer Fail(string why) => new(false, new StepResult.Fail(why));
    public static ConditionAnswer Cancel(string why) => new(false, new StepResult.Cancel(why));
}

/// Une action de FL d'un groupe (blocs `FlAction` consécutifs).
public sealed record FlActionCall(string Key, ActionFallback Fallback);

/// État d'un passage partagé entre les blocs (variables, dernier échec, compteurs). L'état propre à Windows (boîte de
/// dialogue suivie, piste visée, pointeur à remettre…) vit dans l'objet d'effets, neuf à chaque passage.
public sealed class RunState
{
    public Dictionary<string, int> Variables { get; } = new();
    public bool LastFailed { get; set; }
    /// Blocs exécutés (garde-fou d'exécution).
    public int Executed { get; set; }
    public List<string> Warnings { get; } = new();
    public DateTime StartedAt { get; }

    public RunState(DateTime startedAt) => StartedAt = startedAt;
}

/// Effets d'une macro (Windows : l'appli ; essais : faux effets). Appelés sur le fil de la macro.
public interface IMacroEffects
{
    /// Journal : jamais une touche, un chemin ou un nom de piste.
    void Log(string tag, string text);
    /// Relevés du départ (pointeur, fenêtres, piste visée), larsen lancé en avance si demandé.
    /// null = prêt, sinon la raison du refus.
    string? Begin(bool startFeedbackEarly);
    /// La piste visée est dans une fenêtre de FL.
    bool TargetTrackIsInFl();
    /// Touches du raccourci relâchées ; faux si des touches de modification restent enfoncées.
    bool WaitForKeyboardIdle(TimeSpan timeout);
    /// Raison d'arrêter maintenant (FL plus au premier plan, Échap), sinon null.
    string? StopReason();
    /// Blocs simples (pas de contrôle, pas d'action de FL).
    StepResult Perform(BlockBody body, RunState state);
    /// Actions de FL consécutives : un seul réveil du lien ; sans lien, leurs replis un par un, dans l'ordre.
    StepResult FlActions(IReadOnlyList<FlActionCall> group, RunState state);
    /// Conditions qui regardent FL (fenêtre ouverte, état de FL) ; les autres sont évaluées par l'interpréteur.
    ConditionAnswer Evaluate(Condition c, RunState state);
    StepResult Pause(int ms);
    /// Toujours appelé à la fin (pointeur remis à sa place…).
    void Cleanup(RunState state);
}

/// Suivi d'un essai depuis le créateur : null ailleurs, donc aucun coût.
public interface IRunObserver
{
    void BlockStarted(Guid id, string path);
    void BlockFinished(Guid id, string path, StepResult result, int ms);
}

/// Garde-fou d'exécution : jamais plus de 2 000 blocs ni 300 s, même avec des boucles.
public sealed record RuntimeLimits(int MaxBlocks = 2_000, double MaxSeconds = 300)
{
    public static RuntimeLimits Standard { get; } = new();
}

public sealed class MacroInterpreter
{
    private readonly IMacroEffects _effects;
    private readonly IRunObserver? _observer;
    private readonly RuntimeLimits _limits;
    private readonly Func<DateTime> _clock;

    public MacroInterpreter(IMacroEffects effects, IRunObserver? observer = null, RuntimeLimits? limits = null,
                            Func<DateTime>? clock = null)
    {
        _effects = effects;
        _observer = observer;
        _limits = limits ?? RuntimeLimits.Standard;
        _clock = clock ?? (() => DateTime.UtcNow);
    }

    private abstract record Flow
    {
        public sealed record Next : Flow;
        public sealed record Stop(string? Message) : Flow;
        public sealed record Fail(string Path, string Label, string Reason) : Flow;
        public sealed record Cancel(string Why) : Flow;
    }

    private static readonly Flow NextFlow = new Flow.Next();

    /// Délai entre deux vérifications d'une condition « attendre que ».
    public const int PollMs = 250;

    public MacroOutcome Run(MacroProgram program)
    {
        var state = new RunState(_clock());
        foreach (var v in program.Variables) state.Variables[v.Name] = v.Initial;
        try
        {
            if (!program.IsRunnable) return new MacroOutcome.Failed(1, program.Problem ?? Loc.T("macro invalide"));
            if (_effects.Begin(program.Needs.HasFlag(BlockNeeds.FeedbackEarly)) is { } why) return new MacroOutcome.Failed(1, why);
            var first = program.Blocks.FirstOrDefault(b => b.Enabled && b.Body is not BlockBody.Comment);
            var firstNeeds = first is null ? BlockNeeds.None : BlockRegistry.Needs(first.Body);
            if (firstNeeds.HasFlag(BlockNeeds.TrackRequired) && !_effects.TargetTrackIsInFl())
                return new MacroOutcome.Failed(1, Loc.T("clique d'abord sur ta piste dans le Mixer de FL, puis refais le raccourci"));
            // Un bloc qui clique sur la piste attend lui-même le clavier au repos ; les autres premiers blocs, ici.
            if (firstNeeds.HasFlag(BlockNeeds.KeyboardIdle) && !firstNeeds.HasFlag(BlockNeeds.KeyboardIdleInside)
                && !_effects.WaitForKeyboardIdle(TimeSpan.FromSeconds(1.5)))
                return new MacroOutcome.Cancelled(Loc.T("relâche les touches du raccourci"));
            return Run(program.Blocks, "", 0, state) switch
            {
                Flow.Stop s => new MacroOutcome.Stopped(s.Message),
                Flow.Fail f => int.TryParse(f.Path, out var n)
                    ? new MacroOutcome.Failed(n, f.Reason)
                    : new MacroOutcome.FailedInBlock(f.Path, f.Label, f.Reason),
                Flow.Cancel c => new MacroOutcome.Cancelled(c.Why),
                _ => state.Warnings.Count == 0
                    ? new MacroOutcome.Done()
                    : new MacroOutcome.DoneWithWarning(string.Join(" ; ", state.Warnings)),
            };
        }
        finally
        {
            _effects.Cleanup(state);
        }
    }

    private static string Describe(StepResult r) => r switch
    {
        StepResult.Warn w => $"warn: {w.Why}",
        StepResult.Fail f => $"FAIL: {f.Why}",
        StepResult.Cancel c => $"cancel: {c.Why}",
        _ => "ok",
    };

    private int MsSince(DateTime t) => (int)(_clock() - t).TotalMilliseconds;

    private Flow Run(IReadOnlyList<Block> blocks, string prefix, int offset, RunState state)
    {
        var total = offset + blocks.Count;
        var index = 0;
        while (index < blocks.Count)
        {
            var block = blocks[index];
            var path = MacroValidation.Path(prefix, offset + index + 1);
            index++;
            if (!block.Enabled || block.Body is BlockBody.Comment) continue;
            var label = BlockRegistry.Label(block.Body);
            if (state.Executed >= _limits.MaxBlocks)
                return new Flow.Fail(path, label, Loc.F("trop de blocs exécutés (%lld au plus)", _limits.MaxBlocks));
            if ((_clock() - state.StartedAt).TotalSeconds > _limits.MaxSeconds)
                return new Flow.Fail(path, label, Loc.F("macro trop longue (%lld s au plus)", (int)_limits.MaxSeconds));
            if (_effects.StopReason() is { } stop) return new Flow.Cancel(stop);

            // Actions de FL consécutives (blocs inactifs sautés) : un seul réveil du lien.
            var group = new List<Block> { block };
            if (block.Body is BlockBody.FlAction)
            {
                while (index < blocks.Count)
                {
                    var next = blocks[index];
                    if (!next.Enabled) { index++; continue; }
                    if (next.Body is not BlockBody.FlAction || next.OnFailure != block.OnFailure) break;
                    group.Add(next);
                    index++;
                }
            }

            var name = BlockRegistry.Journal(block.Body);
            _effects.Log("STEP", $"{path}/{total} {name} …");
            foreach (var b in group) _observer?.BlockStarted(b.Id, path);
            var began = _clock();
            state.Executed += group.Count;

            StepResult result;
            var inner = NextFlow;
            switch (block.Body)
            {
                case BlockBody.FlAction:
                    result = _effects.FlActions(group.Select(b => b.Body).OfType<BlockBody.FlAction>()
                        .Select(a => new FlActionCall(a.ActionKey, a.Fallback)).ToList(), state);
                    break;

                case BlockBody.IfElse ie:
                {
                    var answer = Evaluate(ie.Condition, state);
                    if (answer.Failure is { } failure) { result = failure; break; }
                    inner = answer.Value ? Run(ie.Then, path, 0, state) : Run(ie.Otherwise, path, ie.Then.Count, state);
                    result = new StepResult.Ok();
                    break;
                }

                case BlockBody.RepeatCount rc:
                    result = new StepResult.Ok();
                    for (var turn = 0; turn < Math.Max(rc.Count, 0); turn++)
                    {
                        inner = Run(rc.Blocks, path, 0, state);
                        if (inner is not Flow.Next) break;
                    }
                    break;

                case BlockBody.RepeatWhile rw:
                {
                    result = new StepResult.Ok();
                    var turns = 0;
                    while (true)
                    {
                        var answer = Evaluate(rw.Condition, state);
                        if (answer.Failure is { } failure) { result = failure; break; }
                        if (!answer.Value) break;
                        if (turns >= rw.MaxIterations)
                        {
                            result = new StepResult.Fail(Loc.F("condition toujours vraie après %lld tours", rw.MaxIterations));
                            break;
                        }
                        turns++;
                        inner = Run(rw.Blocks, path, 0, state);
                        if (inner is not Flow.Next) break;
                    }
                    break;
                }

                case BlockBody.WaitUntil wu:
                    result = WaitUntil(wu.Condition, wu.TimeoutMs, began, state);
                    break;

                case BlockBody.SetVariable sv:
                    if (sv.Value.Kind == "flState")
                    {
                        result = new StepResult.Fail(Loc.T("lecture de l'état de FL : demande l'extension du lien avec FL"));
                    }
                    else
                    {
                        state.Variables[sv.Variable] = sv.Value.Kind == "variable"
                            ? state.Variables.GetValueOrDefault(sv.Value.Name ?? "")
                            : sv.Value.Value;
                        result = new StepResult.Ok();
                    }
                    break;

                case BlockBody.Stop s:
                    _effects.Log("STEP", $"{path} {name} → ok in {MsSince(began)} ms");
                    Finished(group, path, new StepResult.Ok(), MsSince(began));
                    return new Flow.Stop(s.Message);

                case BlockBody.Unknown:
                    result = new StepResult.Fail(Loc.T("bloc inconnu : macro d'une version plus récente"));
                    break;

                default:
                    result = _effects.Perform(block.Body, state);
                    break;
            }

            var elapsed = MsSince(began);
            if (inner is not Flow.Next)
            {
                // Un bloc imbriqué a arrêté la macro : son propre chemin est gardé.
                _effects.Log("STEP", $"{path} {name} → {InnerText(inner)} in {elapsed} ms");
                Finished(group, path, new StepResult.Ok(), elapsed);
                return inner;
            }
            _effects.Log("STEP", $"{path} {name} → {Describe(result)} in {elapsed} ms");
            Finished(group, path, result, elapsed);
            switch (result)
            {
                case StepResult.Warn w:
                    state.LastFailed = false;
                    state.Warnings.Add(w.Why);
                    break;
                case StepResult.Fail f:
                    if (block.OnFailure != FailurePolicy.KeepGoing) return new Flow.Fail(path, label, f.Why);
                    state.LastFailed = true;
                    state.Warnings.Add(Loc.F("étape %@ non faite (%@)", path, f.Why));
                    break;
                case StepResult.Cancel c:
                    return new Flow.Cancel(c.Why);
                default:
                    state.LastFailed = false;
                    break;
            }
        }
        return NextFlow;
    }

    /// Fin de chaque bloc du groupe, pour le suivi d'un essai (sans observateur : rien).
    private void Finished(IEnumerable<Block> group, string path, StepResult result, int ms)
    {
        foreach (var b in group) _observer?.BlockFinished(b.Id, path, result, ms);
    }

    private static string InnerText(Flow f) => f switch
    {
        Flow.Stop => "stop",
        Flow.Fail fail => $"FAIL at {fail.Path}: {fail.Reason}",
        Flow.Cancel c => $"cancel: {c.Why}",
        _ => "ok",
    };

    private StepResult WaitUntil(Condition c, int timeoutMs, DateTime began, RunState state)
    {
        while (true)
        {
            var answer = Evaluate(c, state);
            if (answer.Failure is { } failure) return failure;
            if (answer.Value) return new StepResult.Ok();
            if (MsSince(began) >= timeoutMs) return new StepResult.Fail(Loc.F("condition toujours fausse après %lld s", timeoutMs / 1000));
            if (_effects.Pause(PollMs) is StepResult.Cancel cancel) return cancel;
        }
    }

    /// Conditions sans effet évaluées ici ; celles qui regardent FL, par les effets.
    private ConditionAnswer Evaluate(Condition c, RunState state)
    {
        switch (c)
        {
            case Condition.Variable v:
                return ConditionAnswer.Of(v.Op.Holds(state.Variables.GetValueOrDefault(v.Name), v.Value));
            case Condition.LastBlockFailed:
                return ConditionAnswer.Of(state.LastFailed);
            case Condition.Not n:
            {
                var inner = Evaluate(n.Inner, state);
                return inner.Failure is null ? ConditionAnswer.Of(!inner.Value) : inner;
            }
            case Condition.All all:
                foreach (var x in all.List)
                {
                    var answer = Evaluate(x, state);
                    if (answer.Failure is not null || !answer.Value) return answer;
                }
                return ConditionAnswer.Of(true);
            case Condition.Any any:
                foreach (var x in any.List)
                {
                    var answer = Evaluate(x, state);
                    if (answer.Failure is not null || answer.Value) return answer;
                }
                return ConditionAnswer.Of(false);
            default:
                return _effects.Evaluate(c, state);
        }
    }
}
