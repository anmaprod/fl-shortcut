// Interpréteur des macros : mêmes essais que Tests/FLShortcutTests/MacroInterpreterTests.swift (ordre, regroupement des
// actions de FL, préconditions du premier bloc, arrêt, Échap, échecs, contrôle, variables, garde-fou, suivi). L'ancien
// modèle « Enregistrement rapide » du Mac (macro d'un raccourci) est écrit ici avec ses blocs.
using FLShortcut.Core;
using FLShortcut.Core.Macros;
using Xunit;

namespace FLShortcut.Core.Tests;

/// Faux effets : trace de chaque appel, résultats choisis, horloge contrôlée. Aucun événement envoyé.
internal sealed class FakeEffects : IMacroEffects
{
    public List<string> Trace { get; } = new();
    /// Lignes « STEP » du journal.
    public List<string> StepLines { get; } = new();
    /// Résultats successifs par nom de bloc (journal) ; Ok ensuite.
    public Dictionary<string, Queue<StepResult>> Results { get; } = new();
    public StepResult FlResult { get; set; } = new StepResult.Ok();
    public string? BeginFailure { get; set; }
    public bool TrackInFl { get; set; } = true;
    public bool KeyboardIdle { get; set; } = true;
    /// Échap après ce nombre de vérifications.
    public int? EscapeAfter { get; set; }
    public int StopChecks { get; private set; }
    /// Réponses successives de « une fenêtre est ouverte » (faux ensuite).
    public Queue<bool> WindowAnswers { get; set; } = new();
    public DateTime Now { get; set; } = new(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);
    /// Durée simulée de chaque bloc simple.
    public double BlockSeconds { get; set; }
    public bool? LarsenEarly { get; private set; }

    public void Log(string tag, string text) { if (tag == "STEP") StepLines.Add(text); }

    public string? Begin(bool startFeedbackEarly)
    {
        Trace.Add("begin");
        LarsenEarly = startFeedbackEarly;
        return BeginFailure;
    }

    public bool TargetTrackIsInFl()
    {
        Trace.Add("track?");
        return TrackInFl;
    }

    public bool WaitForKeyboardIdle(TimeSpan timeout)
    {
        Trace.Add("idle");
        return KeyboardIdle;
    }

    public string? StopReason()
    {
        StopChecks++;
        return EscapeAfter is { } n && StopChecks > n ? "Échap" : null;
    }

    public StepResult Perform(BlockBody body, RunState state)
    {
        var name = BlockRegistry.Journal(body);
        Trace.Add(name);
        Now = Now.AddSeconds(BlockSeconds);
        return Results.TryGetValue(name, out var list) && list.Count > 0 ? list.Dequeue() : new StepResult.Ok();
    }

    public StepResult FlActions(IReadOnlyList<FlActionCall> group, RunState state)
    {
        Trace.Add("fl[" + string.Join(",", group.Select(g => g.Key)) + "]");
        return FlResult;
    }

    public ConditionAnswer Evaluate(Condition c, RunState state)
    {
        Trace.Add("evaluate");
        if (c is Condition.FlState) return ConditionAnswer.Fail("lien absent");
        return ConditionAnswer.Of(WindowAnswers.Count > 0 && WindowAnswers.Dequeue());
    }

    public StepResult Pause(int ms)
    {
        Trace.Add($"pause {ms}");
        Now = Now.AddMilliseconds(ms);
        return new StepResult.Ok();
    }

    public void Cleanup(RunState state) => Trace.Add("cleanup");
}

public class MacroInterpreterTests
{
    private static readonly BlockBody Key = new BlockBody.Key(new KeyRef(new MacKey(49)));
    private static readonly KeyRef Rec = new(new MacKey(15));

    private static Block B(BlockBody body, FailurePolicy onFailure = FailurePolicy.Stop, bool enabled = true) =>
        new(body, enabled, onFailure);

    private static MacroOutcome Run(IReadOnlyList<Block> blocks, FakeEffects fx, IReadOnlyList<VariableDecl>? variables = null,
                                    RuntimeLimits? limits = null)
    {
        var p = new MacroProgram(blocks, "essai", new ValidationContext(), variables);
        Assert.Null(p.Problem);
        return new MacroInterpreter(fx, limits: limits, clock: () => fx.Now).Run(p);
    }

    /// L'ancien modèle « Enregistrement rapide » du Mac, en blocs : menu de la piste, boîte « Open », pause, armement
    /// + REC, entrée 1, larsen.
    private static List<Block> OldTemplate() => new()
    {
        B(MacroTemplates.OpenStateMenu),
        B(new BlockBody.WaitWindow(WindowKind.Dialog, 5_000)),
        B(new BlockBody.WaitWindowClose(WindowKind.Dialog, 60_000)),
        B(new BlockBody.Delay(300)),
        B(new BlockBody.FlAction("armon", ActionFallback.TrackMenuArm)),
        B(new BlockBody.FlAction("recon", ActionFallback.Key(Rec))),
        B(new BlockBody.SelectInput(new LearnedRef("macroSpots.v2.input"))),
        B(new BlockBody.FeedbackCheck()),
    };

    // ---------- Modèle « Enregistrement rapide » ----------

    /// Même ordre que l'ancien moteur, armement + REC en un seul réveil, journal au même format.
    [Fact]
    public void TemplateRunsInTheOldOrder()
    {
        var fx = new FakeEffects();
        Assert.Equal(new MacroOutcome.Done(), Run(OldTemplate(), fx));
        Assert.Equal(new[] { "begin", "track?", "trackMenu", "waitDialog", "waitDialogClose", "delay", "fl[armon,recon]",
                             "selectInput", "feedbackCheck", "cleanup" }, fx.Trace);
        Assert.True(fx.LarsenEarly);
        Assert.Equal(new[]
        {
            "1/8 trackMenu …", "1 trackMenu → ok in 0 ms",
            "2/8 waitDialog …", "2 waitDialog → ok in 0 ms",
            "3/8 waitDialogClose …", "3 waitDialogClose → ok in 0 ms",
            "4/8 delay …", "4 delay → ok in 0 ms",
            "5/8 armTrack …", "5 armTrack → ok in 0 ms",
            "7/8 selectInput …", "7 selectInput → ok in 0 ms",
            "8/8 feedbackCheck …", "8 feedbackCheck → ok in 0 ms",
        }, fx.StepLines);
        // Une vérification « Échap / FL devant » par bloc (le groupe armement + REC compte pour un).
        Assert.Equal(7, fx.StopChecks);
    }

    /// Sans le larsen, il n'est jamais lancé ; clavier au repos avant le dépôt (jamais Ctrl + appui).
    [Fact]
    public void WithoutFeedbackBlockNothingStartsEarly()
    {
        var blocks = new List<Block>
        {
            B(new BlockBody.DropFile(@"C:\Users\test\Voix.fst")),
            B(new BlockBody.Delay(300)),
            B(new BlockBody.FlAction("armon", ActionFallback.TrackMenuArm)),
            B(new BlockBody.FlAction("recon", ActionFallback.Key(Rec))),
            B(new BlockBody.SelectInput(new LearnedRef("macroSpots.v2.input"))),
        };
        var fx = new FakeEffects();
        Assert.Equal(new MacroOutcome.Done(), Run(blocks, fx));
        Assert.False(fx.LarsenEarly);
        Assert.Equal(new[] { "begin", "track?", "idle", "dropFile", "delay", "fl[armon,recon]", "selectInput", "cleanup" }, fx.Trace);
        Assert.Contains("5/5 selectInput …", fx.StepLines);
    }

    [Fact]
    public void TrackOutsideFlIsRefusedBeforeAnything()
    {
        var fx = new FakeEffects { TrackInFl = false };
        Assert.Equal(new MacroOutcome.Failed(1, "clique d'abord sur ta piste dans le Mixer de FL, puis refais le raccourci"),
            Run(OldTemplate(), fx));
        Assert.Equal(new[] { "begin", "track?", "cleanup" }, fx.Trace);
    }

    [Fact]
    public void BeginFailureStopsAtStep1()
    {
        var fx = new FakeEffects { BeginFailure = "autorise FL Shortcuts" };
        Assert.Equal(new MacroOutcome.Failed(1, "autorise FL Shortcuts"), Run(new[] { B(new BlockBody.Delay(1)) }, fx));
        Assert.Equal(new[] { "begin", "cleanup" }, fx.Trace);
    }

    /// Un premier bloc qui ne clique pas sur la piste attend le clavier au repos (touches du raccourci relâchées).
    [Fact]
    public void OtherFirstBlocksWaitForTheKeyboard()
    {
        var fx = new FakeEffects();
        Assert.Equal(new MacroOutcome.Done(), Run(new[] { B(new BlockBody.Comment("note")), B(new BlockBody.Delay(1)) }, fx));
        Assert.Equal(new[] { "begin", "idle", "delay", "cleanup" }, fx.Trace);
        var held = new FakeEffects { KeyboardIdle = false };
        Assert.Equal(new MacroOutcome.Cancelled("relâche les touches du raccourci"), Run(new[] { B(new BlockBody.Delay(1)) }, held));
        Assert.Equal(new[] { "begin", "idle", "cleanup" }, held.Trace);
    }

    [Fact]
    public void UnrunnableProgramNeverStarts()
    {
        var fx = new FakeEffects();
        var p = new MacroProgram(new[] { B(new BlockBody.Unknown("futur", null)) }, "x", new ValidationContext());
        var outcome = Assert.IsType<MacroOutcome.Failed>(new MacroInterpreter(fx).Run(p));
        Assert.Equal(1, outcome.Step);
        Assert.Equal(new[] { "cleanup" }, fx.Trace);
    }

    /// Macro de la bibliothèque : nom et blocs validés ensemble ; une macro au nom vide ne tourne jamais.
    [Fact]
    public void CompiledDocKeepsItsBlocksOrItsReason()
    {
        var doc = new MacroDoc { Name = "Essai", Blocks = new List<Block> { B(new BlockBody.Delay(1)), B(Key) } };
        var ok = MacroProgram.Compile(doc);
        Assert.True(ok.IsRunnable, ok.Problem);
        Assert.Equal(doc.Id, ok.Id);
        Assert.Equal("delay > key", ok.Title);
        Assert.True(ok.Needs.HasFlag(BlockNeeds.KeyboardIdle));

        var unnamed = MacroProgram.Compile(new MacroDoc { Name = "", Blocks = doc.Blocks });
        Assert.False(unnamed.IsRunnable);
        Assert.Empty(unnamed.Blocks);
        var fx = new FakeEffects();
        Assert.Equal(new MacroOutcome.Failed(1, "Nom de macro invalide."), new MacroInterpreter(fx).Run(unnamed));
        Assert.Equal(new[] { "cleanup" }, fx.Trace);
    }

    // ---------- Actions de FL ----------

    [Fact]
    public void ConsecutiveFlActionsShareOneWake()
    {
        var fx = new FakeEffects();
        Run(new[]
        {
            B(new BlockBody.FlAction("armon", ActionFallback.TrackMenuArm)),
            B(new BlockBody.FlAction("play", ActionFallback.None), enabled: false),
            B(new BlockBody.FlAction("recon", ActionFallback.None)),
            B(new BlockBody.Delay(1)),
            B(new BlockBody.FlAction("recon", ActionFallback.None)),
            B(new BlockBody.FlAction("stop", ActionFallback.None), FailurePolicy.KeepGoing),
        }, fx);
        Assert.Equal(new[] { "begin", "idle", "fl[armon,recon]", "delay", "fl[recon]", "fl[stop]", "cleanup" }, fx.Trace);
    }

    [Fact]
    public void FlActionWarningIsKept()
    {
        const string why = "armement non fait : le menu de la piste ne s'est pas ouvert";
        var fx = new FakeEffects { FlResult = new StepResult.Warn(why) };
        Assert.Equal(new MacroOutcome.DoneWithWarning(why),
            Run(new[] { B(new BlockBody.FlAction("armon", ActionFallback.TrackMenuArm)), B(new BlockBody.Delay(1)) }, fx));
    }

    // ---------- Arrêts et échecs ----------

    [Fact]
    public void EscapeCancelsAndCleansUp()
    {
        var fx = new FakeEffects { EscapeAfter = 2 };
        Assert.Equal(new MacroOutcome.Cancelled("Échap"),
            Run(new[] { B(new BlockBody.Delay(1)), B(new BlockBody.Delay(2)), B(new BlockBody.Delay(3)) }, fx));
        Assert.Equal(new[] { "begin", "idle", "delay", "delay", "cleanup" }, fx.Trace);
    }

    [Fact]
    public void CancelFromABlockStopsEverything()
    {
        var fx = new FakeEffects();
        fx.Results["waitDialog"] = new Queue<StepResult>(new StepResult[] { new StepResult.Cancel("FL n'est plus au premier plan") });
        Assert.Equal(new MacroOutcome.Cancelled("FL n'est plus au premier plan"),
            Run(new[] { B(new BlockBody.WaitWindow(WindowKind.Dialog, 500), FailurePolicy.KeepGoing), B(new BlockBody.Delay(1)) }, fx));
        Assert.DoesNotContain("delay", fx.Trace);
    }

    [Fact]
    public void FailureStopsWithTheOldMessage()
    {
        var fx = new FakeEffects();
        fx.Results["delay"] = new Queue<StepResult>(new StepResult[] { new StepResult.Ok(), new StepResult.Fail("boîte de dialogue introuvable") });
        var outcome = Run(new[] { B(new BlockBody.Delay(1)), B(new BlockBody.Delay(2)), B(new BlockBody.Delay(3)) }, fx);
        Assert.Equal(new MacroOutcome.Failed(2, "boîte de dialogue introuvable"), outcome);
        Assert.Equal("Macro arrêtée à l'étape 2 : boîte de dialogue introuvable", outcome.Text);
        Assert.Equal(2, fx.Trace.Count(t => t == "delay"));
        Assert.Equal("2 delay → FAIL: boîte de dialogue introuvable in 0 ms", fx.StepLines[^1]);
    }

    /// « Continuer si échec » : le bloc est sauté, « le bloc précédent a échoué » devient vrai.
    [Fact]
    public void KeepGoingSetsLastBlockFailed()
    {
        var fx = new FakeEffects();
        fx.Results["delay"] = new Queue<StepResult>(new StepResult[] { new StepResult.Fail("boom") });
        var outcome = Run(new[]
        {
            B(new BlockBody.Delay(1), FailurePolicy.KeepGoing),
            B(new BlockBody.IfElse(new Condition.LastBlockFailed(), new List<Block> { B(Key) }, new List<Block>())),
            B(new BlockBody.IfElse(new Condition.LastBlockFailed(), new List<Block> { B(new BlockBody.MenuKeyPress(MenuKey.Down)) }, new List<Block>())),
        }, fx);
        Assert.Equal(new MacroOutcome.DoneWithWarning("étape 1 non faite (boom)"), outcome);
        Assert.Contains("key", fx.Trace);
        Assert.DoesNotContain("menuKey", fx.Trace);          // le « si » précédent a réussi
    }

    [Fact]
    public void WarningsAreJoined()
    {
        var fx = new FakeEffects();
        fx.Results["delay"] = new Queue<StepResult>(new StepResult[] { new StepResult.Warn("a"), new StepResult.Warn("b") });
        Assert.Equal(new MacroOutcome.DoneWithWarning("a ; b"), Run(new[] { B(new BlockBody.Delay(1)), B(new BlockBody.Delay(2)) }, fx));
    }

    [Fact]
    public void StopBlockEndsTheMacro()
    {
        var fx = new FakeEffects();
        var outcome = Run(new[] { B(new BlockBody.Delay(1)), B(new BlockBody.Stop("fini")), B(new BlockBody.Delay(2)) }, fx);
        Assert.Equal(new MacroOutcome.Stopped("fini"), outcome);
        Assert.Equal(1, fx.Trace.Count(t => t == "delay"));
        Assert.Equal("cleanup", fx.Trace[^1]);
    }

    // ---------- Contrôle ----------

    [Fact]
    public void IfElseAndNestedFailurePath()
    {
        var fx = new FakeEffects { WindowAnswers = new Queue<bool>(new[] { true, false }) };
        Run(new[]
        {
            B(new BlockBody.IfElse(new Condition.WindowOpen(WindowKind.Dialog), new List<Block> { B(Key) }, new List<Block> { B(new BlockBody.Delay(1)) })),
            B(new BlockBody.IfElse(new Condition.WindowOpen(WindowKind.Dialog), new List<Block> { B(Key) }, new List<Block> { B(new BlockBody.Delay(1)) })),
        }, fx);
        Assert.Equal(new[] { "begin", "idle", "evaluate", "key", "evaluate", "delay", "cleanup" }, fx.Trace);

        var failing = new FakeEffects();
        failing.Results["key"] = new Queue<StepResult>(new StepResult[] { new StepResult.Fail("touche interdite") });
        var outcome = Run(new[]
        {
            B(new BlockBody.Delay(1)),
            B(new BlockBody.IfElse(new Condition.LastBlockFailed(), new List<Block>(), new List<Block> { B(new BlockBody.Delay(2)), B(Key) })),
        }, failing);
        // Le sinon continue la numérotation du alors (vide) : 2.2.
        Assert.Equal(new MacroOutcome.FailedInBlock("2.2", "Touche ou raccourci", "touche interdite"), outcome);
        Assert.Equal("Macro arrêtée au bloc 2.2 (Touche ou raccourci) : touche interdite", outcome.Text);
        Assert.Contains("2.2/2 key …", failing.StepLines);
    }

    [Fact]
    public void RepeatAndWhile()
    {
        var fx = new FakeEffects { WindowAnswers = new Queue<bool>(new[] { true, true, false }) };
        Run(new[]
        {
            B(new BlockBody.RepeatCount(3, new List<Block> { B(new BlockBody.MenuKeyPress(MenuKey.Down)) })),
            B(new BlockBody.RepeatWhile(new Condition.WindowOpen(WindowKind.Menu), 10, new List<Block> { B(Key) })),
        }, fx);
        Assert.Equal(3, fx.Trace.Count(t => t == "menuKey"));
        Assert.Equal(2, fx.Trace.Count(t => t == "key"));

        var endless = new FakeEffects { WindowAnswers = new Queue<bool>(Enumerable.Repeat(true, 10)) };
        var outcome = Run(new[] { B(new BlockBody.RepeatWhile(new Condition.WindowOpen(WindowKind.Menu), 2, new List<Block> { B(Key) })) }, endless);
        Assert.Equal(new MacroOutcome.Failed(1, "condition toujours vraie après 2 tours"), outcome);
        Assert.Equal(2, endless.Trace.Count(t => t == "key"));
    }

    [Fact]
    public void WaitUntilPollsFourTimesASecond()
    {
        var fx = new FakeEffects { WindowAnswers = new Queue<bool>(new[] { false, false, true }) };
        Assert.Equal(new MacroOutcome.Done(), Run(new[] { B(new BlockBody.WaitUntil(new Condition.WindowOpen(WindowKind.Dialog), 1_000)) }, fx));
        Assert.Equal(2, fx.Trace.Count(t => t == "pause 250"));

        var never = new FakeEffects();
        var outcome = Run(new[] { B(new BlockBody.WaitUntil(new Condition.WindowOpen(WindowKind.Dialog), 1_000)) }, never);
        Assert.Equal(new MacroOutcome.Failed(1, "condition toujours fausse après 1 s"), outcome);
        Assert.Equal(4, never.Trace.Count(t => t == "pause 250"));
    }

    [Fact]
    public void Variables()
    {
        var fx = new FakeEffects();
        Run(new[]
        {
            B(new BlockBody.SetVariable("n", IntSource.Constant(3))),
            B(new BlockBody.IfElse(new Condition.All(new Condition[]
            {
                new Condition.Variable("n", CompareOp.Eq, 3),
                new Condition.Not(new Condition.Variable("m", CompareOp.Gt, 0)),
            }), new List<Block> { B(Key) }, new List<Block>())),
        }, fx, new[] { new VariableDecl("n"), new VariableDecl("m") });
        Assert.Contains("key", fx.Trace);

        // Une variable copiée d'une autre ; valeur de départ déclarée.
        var copy = new FakeEffects();
        Run(new[]
        {
            B(new BlockBody.SetVariable("n", IntSource.Variable("m"))),
            B(new BlockBody.IfElse(new Condition.Variable("n", CompareOp.Eq, 7), new List<Block> { B(Key) }, new List<Block>())),
        }, copy, new[] { new VariableDecl("n"), new VariableDecl("m", 7) });
        Assert.Contains("key", copy.Trace);
    }

    [Fact]
    public void FlStateConditionFailsClearly()
    {
        var fx = new FakeEffects();
        var outcome = Run(new[] { B(new BlockBody.IfElse(new Condition.FlState("isrec", CompareOp.Eq, 0), new List<Block> { B(Key) }, new List<Block>())) }, fx);
        Assert.Equal(new MacroOutcome.Failed(1, "lien absent"), outcome);
    }

    [Fact]
    public void CommentsAndDisabledBlocksAreSkipped()
    {
        var fx = new FakeEffects();
        Run(new[] { B(new BlockBody.Delay(1)), B(new BlockBody.Comment("rien")), B(Key, enabled: false), B(new BlockBody.MenuKeyPress(MenuKey.Up)) }, fx);
        Assert.Equal(new[] { "begin", "idle", "delay", "menuKey", "cleanup" }, fx.Trace);
        Assert.Equal("1/4 delay …", fx.StepLines[0]);
        Assert.Contains("4/4 menuKey …", fx.StepLines);
    }

    // ---------- Garde-fou d'exécution ----------

    [Fact]
    public void RuntimeLimitsStopEndlessMacros()
    {
        var fx = new FakeEffects();
        var outcome = Run(new[] { B(new BlockBody.RepeatCount(10, new List<Block> { B(new BlockBody.Delay(1)) })) }, fx,
            limits: new RuntimeLimits(MaxBlocks: 4, MaxSeconds: 300));
        var failed = Assert.IsType<MacroOutcome.FailedInBlock>(outcome);
        Assert.Contains("trop de blocs", failed.Reason);
        Assert.Equal(3, fx.Trace.Count(t => t == "delay"));

        var slow = new FakeEffects { BlockSeconds = 0.6 };
        var late = Run(new[] { B(new BlockBody.Delay(1)), B(new BlockBody.Delay(1)), B(new BlockBody.Delay(1)) }, slow,
            limits: new RuntimeLimits(MaxBlocks: 100, MaxSeconds: 1));
        Assert.Equal(new MacroOutcome.Failed(3, "macro trop longue (1 s au plus)"), late);
    }

    private sealed class Spy : IRunObserver
    {
        public List<string> Events { get; } = new();
        public void BlockStarted(Guid id, string path) => Events.Add($"+{path}");
        public void BlockFinished(Guid id, string path, StepResult result, int ms) =>
            Events.Add($"-{path} {(result is StepResult.Ok ? "ok" : result.ToString())}");
    }

    /// Suivi d'un essai : chaque bloc commencé puis fini, avec son chemin et son résultat.
    [Fact]
    public void ObserverSeesEveryBlock()
    {
        var spy = new Spy();
        var fx = new FakeEffects();
        var p = new MacroProgram(new[] { B(new BlockBody.Delay(1)), B(new BlockBody.RepeatCount(1, new List<Block> { B(Key) })) }, "x",
            new ValidationContext());
        Assert.Equal(new MacroOutcome.Done(), new MacroInterpreter(fx, spy, clock: () => fx.Now).Run(p));
        Assert.Equal(new[] { "+1", "-1 ok", "+2", "+2.1", "-2.1 ok", "-2 ok" }, spy.Events);
    }

    /// Tous les textes de l'interpréteur ont leur anglais (celui du Mac).
    [Fact]
    public void OutcomesHaveTheirEnglish()
    {
        foreach (var key in new[]
                 {
                     "Macro terminée", "Macro terminée, mais %@", "Macro arrêtée à l'étape %lld : %@",
                     "Macro arrêtée au bloc %@ (%@) : %@", "Macro arrêtée : %@", "Macro arrêtée par son bloc « Arrêter »",
                     "Macro annulée : %@", "macro invalide", "clique d'abord sur ta piste dans le Mixer de FL, puis refais le raccourci",
                     "relâche les touches du raccourci", "trop de blocs exécutés (%lld au plus)", "macro trop longue (%lld s au plus)",
                     "condition toujours vraie après %lld tours", "condition toujours fausse après %lld s",
                     "lecture de l'état de FL : demande l'extension du lien avec FL",
                     "bloc inconnu : macro d'une version plus récente", "étape %@ non faite (%@)",
                 })
            Assert.True(Loc.Has(key), $"« {key} » sans anglais");
    }
}
