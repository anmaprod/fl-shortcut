// Effets des macros sur Windows, essayés sur un faux FL (fenêtres, touches, horloge simulée) : touches à FL seul et
// liste noire, arrêt (FL plus devant, Échap), menus ouverts par la macro, boîtes de dialogue, actions de FL et leurs
// replis, pages, blocs pas encore faits pour Windows (bloqués à la validation).
using FLShortcut.Core;
using FLShortcut.Core.Macros;
using Xunit;

namespace FLShortcut.Core.Tests;

/// Faux FL : fenêtres ouvertes (la plus en avant d'abord), touches reçues, réactions aux touches, horloge simulée.
internal sealed class FakeFl : IFlDriver
{
    public const long Main = 1;
    public List<FlWin> Open { get; } = new() { new FlWin(Main, FlWindowRole.Main, 0, 0, 1200, 800) };
    public List<KeyCombo> Sent { get; } = new();
    public List<List<int>> Actions { get; } = new();
    public List<string> Lines { get; } = new();
    /// Raison donnée par le lien (null : FL fait les actions).
    public string? LinkFailure { get; set; } = "lien endormi";
    public FlWindow? KnownPage { get; set; }
    public bool Front { get; set; } = true;
    public int EscapePresses { get; set; }
    public bool Modifiers { get; set; }
    public Dictionary<string, bool?> Memory { get; } = new();
    public int OrganizerOpened { get; private set; }
    public DateTime Now { get; private set; } = new(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);
    /// Réaction de FL à une touche reçue.
    public Action<KeyCombo>? OnKey { get; set; }
    private readonly List<(DateTime At, Action Do)> _timeline = new();

    public void After(int ms, Action a) => _timeline.Add((Now.AddMilliseconds(ms), a));
    public void Show(long id, FlWindowRole role) => Open.Insert(0, new FlWin(id, role, 100, 100, 300, 200));
    public void Hide(long id) => Open.RemoveAll(w => w.Id == id);

    public void Log(string tag, string text) => Lines.Add($"{tag} {text}");
    public bool InFront() => Front;
    public bool EscapeDown() => false;
    public bool ModifiersDown() => Modifiers;
    public bool AnyKeyDown() => false;

    public bool Send(KeyCombo combo)
    {
        if (!Front) return false;
        Sent.Add(combo);
        OnKey?.Invoke(combo);
        return true;
    }

    public IReadOnlyList<FlWin> Windows() => Open.ToList();

    public void Sleep(int ms)
    {
        Now = Now.AddMilliseconds(ms);
        foreach (var due in _timeline.Where(t => t.At <= Now).ToList())
        {
            _timeline.Remove(due);
            due.Do();
        }
    }

    public string? RunActions(IReadOnlyList<int> ids)
    {
        Actions.Add(ids.ToList());
        return LinkFailure;
    }

    public bool? Learned(string key) => Memory.TryGetValue(key, out var v) ? v : null;
    public void Learn(string key, bool? value) => Memory[key] = value;
    public void OpenOrganizer() => OrganizerOpened++;
}

public class MacroEffectsWindowsTests
{
    private static readonly KeyRef CtrlS = new(new MacKey(1, Command: true), "s");
    private static readonly KeyRef AltF4 = new(new MacKey(118, Option: true));
    /// Touche qui, dans le faux FL, ouvre le menu 10 (comme un clic droit).
    private static readonly KeyRef MenuOpener = new(new MacKey(45, Control: true, Shift: true), "n");
    private static readonly KeyCombo MenuOpenerCombo = new(Vk.Letter('N'), Ctrl: true, Shift: true);

    private static (FakeFl Fl, MacroEffectsWindows Fx, RunState State) Start(Action<FakeFl>? setup = null)
    {
        var fl = new FakeFl();
        setup?.Invoke(fl);
        var fx = new MacroEffectsWindows(fl);
        Assert.Null(fx.Begin(false));
        return (fl, fx, new RunState(fl.Now));
    }

    [Fact]
    public void KeysGoToFlAndForbiddenKeysAreRefused()
    {
        var (fl, fx, state) = Start();
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.Key(CtrlS, 2), state));
        Assert.Equal(new[] { new KeyCombo(Vk.Letter('S'), Ctrl: true), new KeyCombo(Vk.Letter('S'), Ctrl: true) }, fl.Sent);
        Assert.All(fl.Lines, l => Assert.DoesNotContain("Ctrl", l));                  // jamais la touche au journal

        fl.Sent.Clear();
        Assert.Equal("touche interdite", Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.Key(AltF4), state)).Why);
        Assert.Empty(fl.Sent);
    }

    [Fact]
    public void StopsWhenFlLeavesOrOnEscape()
    {
        var (fl, fx, state) = Start();
        fl.After(300, () => fl.Front = false);
        Assert.Equal("FL n'est plus au premier plan", Assert.IsType<StepResult.Cancel>(fx.Perform(new BlockBody.Delay(2000), state)).Why);

        (fl, fx, _) = Start();
        fl.After(100, () => fl.EscapePresses++);              // appui bref tombé entre deux lectures
        Assert.Equal("Échap", Assert.IsType<StepResult.Cancel>(fx.Pause(1000)).Why);
    }

    [Fact]
    public void KeyboardIdleWaitsForModifiers()
    {
        var (fl, fx, _) = Start(f => f.Modifiers = true);
        fl.After(200, () => fl.Modifiers = false);
        Assert.True(fx.WaitForKeyboardIdle(TimeSpan.FromSeconds(1)));
        fl.Modifiers = true;
        Assert.False(fx.WaitForKeyboardIdle(TimeSpan.FromMilliseconds(300)));
    }

    /// Lettres et flèches seulement dans un menu ouvert par la macro : un menu déjà là au départ ne compte pas.
    [Fact]
    public void MenuKeysOnlyInAMenuOpenedByTheMacro()
    {
        var (fl, fx, state) = Start(f => f.Show(5, FlWindowRole.Menu));
        Assert.Equal("aucun menu de FL ouvert par la macro",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.MenuLetters("fo", EnterPolicy.IfNeeded), state)).Why);
        Assert.Equal("aucun menu de FL ouvert par la macro",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.MenuKeyPress(MenuKey.Down), state)).Why);
        Assert.Empty(fl.Sent);
    }

    /// Touche → menu ; « f » ouvre un sous-menu, « o » choisit l'élément : sans Entrée, et c'est appris ; puis un FL
    /// qui demande Entrée : envoyée, et apprise aussi.
    [Fact]
    public void MenuLettersFollowSubmenusAndLearnEnter()
    {
        const string key = "macroMenuEnterAfterLetter";
        var (fl, fx, state) = Start();
        fl.OnKey = c =>
        {
            if (c == MenuOpenerCombo) fl.After(100, () => fl.Show(10, FlWindowRole.Menu));
            else if (c.Vk == Vk.Letter('F')) fl.After(80, () => fl.Show(11, FlWindowRole.Menu));
            else if (c.Vk == Vk.Letter('O')) fl.After(50, () => { fl.Hide(11); fl.Hide(10); });
        };
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.Key(MenuOpener), state));
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.WaitWindow(WindowKind.Menu, 1500), state));
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.MenuLetters("fo", EnterPolicy.Learned(key)), state));
        Assert.DoesNotContain(new KeyCombo(Vk.Return), fl.Sent);
        Assert.False(fl.Memory[key]);

        (fl, fx, state) = Start();
        fl.Memory[key] = null;
        fl.OnKey = c =>
        {
            if (c == MenuOpenerCombo) fl.Show(10, FlWindowRole.Menu);
            else if (c.Vk == Vk.Return) fl.After(40, () => fl.Hide(10));
        };
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.Key(MenuOpener), state));
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.MenuLetters("o", EnterPolicy.Learned(key)), state));
        Assert.Equal(new KeyCombo(Vk.Return), fl.Sent[^1]);
        Assert.True(fl.Memory[key]);
    }

    /// Menu qui ne répond pas à Entrée : Échap le referme (jamais laissé ouvert), l'échec est dit.
    [Fact]
    public void StuckMenuIsClosedAfterAFailure()
    {
        var (fl, fx, state) = Start();
        fl.OnKey = c =>
        {
            if (c == MenuOpenerCombo) fl.Show(10, FlWindowRole.Menu);
            else if (c.Vk == Vk.Escape) fl.Hide(10);
        };
        fx.Perform(new BlockBody.Key(MenuOpener), state);
        Assert.Equal("le menu de FL n'a pas répondu",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.MenuLetters("x", EnterPolicy.Always), state)).Why);
        Assert.Equal(new KeyCombo(Vk.Escape), fl.Sent[^1]);
        Assert.DoesNotContain(fl.Open, w => w.Role == FlWindowRole.Menu);
    }

    [Fact]
    public void MenuArrowsStopWhenTheMenuCloses()
    {
        var (fl, fx, state) = Start();
        fl.OnKey = c =>
        {
            if (c == MenuOpenerCombo) fl.Show(10, FlWindowRole.Menu);
            else if (c.Vk == Vk.Return) fl.Hide(10);
        };
        fx.Perform(new BlockBody.Key(MenuOpener), state);
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.MenuKeyPress(MenuKey.Down, 5), state));
        Assert.Equal(5, fl.Sent.Count(c => c.Vk == Vk.Down));
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.MenuKeyPress(MenuKey.Enter, 2), state));   // 2e Entrée : menu déjà fermé
        Assert.Single(fl.Sent, c => c.Vk == Vk.Return);
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.WaitWindowClose(WindowKind.Menu, 500), state));
    }

    [Fact]
    public void DialogIsFollowedUntilItCloses()
    {
        var (fl, fx, state) = Start(f => f.Show(7, FlWindowRole.Dialog));          // une boîte déjà là : ignorée
        fl.OnKey = _ => fl.After(250, () => fl.Show(30, FlWindowRole.Dialog));
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.Key(CtrlS), state));
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.WaitWindow(WindowKind.Dialog, 1000), state));
        Assert.True(fx.Evaluate(new Condition.WindowOpen(WindowKind.Dialog), state).Value);
        fl.After(2000, () => fl.Hide(30));
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.WaitWindowClose(WindowKind.Dialog, 60_000), state));
        Assert.False(fx.Evaluate(new Condition.WindowOpen(WindowKind.Dialog), state).Value);

        Assert.Equal("boîte de dialogue introuvable",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.WaitWindow(WindowKind.Dialog, 300), state)).Why);
    }

    [Fact]
    public void FlActionsUseTheLinkThenTheirFallback()
    {
        var mute = FlActions.IdForKey("mute")!.Value;
        var rec = FlActions.IdForKey("recon")!.Value;
        var (fl, fx, state) = Start(f => f.LinkFailure = null);
        var group = new[]
        {
            new FlActionCall("mute", ActionFallback.None),
            new FlActionCall("recon", ActionFallback.Key(new KeyRef(new MacKey(15), "r"))),
        };
        Assert.IsType<StepResult.Ok>(fx.FlActions(group, state));
        Assert.Equal(new[] { mute, rec }, Assert.Single(fl.Actions));            // un seul réveil du lien
        Assert.Empty(fl.Sent);

        (fl, fx, state) = Start();
        Assert.IsType<StepResult.Ok>(fx.FlActions(new[] { group[1] }, state));
        Assert.Equal(new KeyCombo(Vk.Letter('R')), Assert.Single(fl.Sent));     // touche REC de FL

        Assert.Equal("ce bloc a besoin du lien avec FL (lien endormi)",
            Assert.IsType<StepResult.Fail>(fx.FlActions(new[] { group[0] }, state)).Why);
        Assert.StartsWith("armement non fait",
            Assert.IsType<StepResult.Warn>(fx.FlActions(new[] { new FlActionCall("armon", ActionFallback.TrackMenuArm) }, state)).Why);
        Assert.Equal("action de FL inconnue",
            Assert.IsType<StepResult.Fail>(fx.FlActions(new[] { new FlActionCall("teleport", ActionFallback.None) }, state)).Why);
    }

    [Fact]
    public void PagesComeForwardByTheirKeyOrTheLink()
    {
        var (fl, fx, state) = Start(f => f.KnownPage = FlWindow.Mixer);
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.OpenPage(FlPage.Mixer), state));
        Assert.Empty(fl.Sent);
        Assert.Empty(fl.Actions);                                                // déjà devant : rien

        (fl, fx, state) = Start();
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.OpenPage(FlPage.Mixer), state));
        Assert.Equal(new KeyCombo(Vk.F(9)), Assert.Single(fl.Sent));             // lien endormi : F9 tout de suite
        Assert.Empty(fl.Actions);

        (fl, fx, state) = Start(f => { f.KnownPage = FlWindow.Playlist; f.LinkFailure = null; });
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.OpenPage(FlPage.Mixer), state));
        Assert.Equal(new[] { FlActions.IdForKey("mx")!.Value }, Assert.Single(fl.Actions));

        Assert.Equal("page de FL à choisir dans la macro",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.OpenPage(null), state)).Why);
    }

    [Fact]
    public void OrganizeOpensTheOrganizer()
    {
        var (fl, fx, state) = Start();
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.Organize(), state));
        Assert.Equal(1, fl.OrganizerOpened);
    }

    /// Un bloc pas encore fait pour Windows bloque sa macro (le raccourci reste à FL) ; désactivé, il ne gêne pas.
    [Fact]
    public void UnsupportedBlocksBlockTheMacro()
    {
        var ctx = new ValidationContext { PlatformProblem = MacroEffectsWindows.Unsupported };
        var doc = new MacroDoc
        {
            Name = "Export",
            Blocks = new List<Block>
            {
                new(new BlockBody.Key(CtrlS)),
                new(new BlockBody.MenuBar(new[] { "File", "Export" })),
            },
        };
        Assert.Equal("Étape 2 : bloc « Menu de FL » pas encore pris en charge sur Windows.", MacroProgram.Compile(doc, ctx).Problem);
        Assert.Null(MacroProgram.Compile(doc).Problem);                          // sans règle du système : rien

        doc.Blocks[1].Enabled = false;
        Assert.True(MacroProgram.Compile(doc, ctx).IsRunnable);
    }

    /// De bout en bout : l'interpréteur et les effets Windows sur le faux FL.
    [Fact]
    public void InterpreterRunsAMacroOnTheFakeFl()
    {
        var fl = new FakeFl();
        fl.OnKey = c => { if (c.Vk == Vk.Letter('S') && c.Ctrl) fl.After(200, () => fl.Show(30, FlWindowRole.Dialog)); };
        var doc = new MacroDoc
        {
            Name = "Enregistrer",
            Blocks = new List<Block>
            {
                new(new BlockBody.Key(CtrlS)),
                new(new BlockBody.WaitWindow(WindowKind.Dialog, 2000)),
                new(new BlockBody.Delay(100)),
            },
        };
        var program = MacroProgram.Compile(doc, new ValidationContext { PlatformProblem = MacroEffectsWindows.Unsupported });
        Assert.True(program.IsRunnable, program.Problem);
        var outcome = new MacroInterpreter(new MacroEffectsWindows(fl), clock: () => fl.Now).Run(program);
        Assert.IsType<MacroOutcome.Done>(outcome);
        Assert.Contains(fl.Lines, l => l.StartsWith("DIALOG opened", StringComparison.Ordinal));
    }

    [Fact]
    public void MessagesHaveTheirEnglish()
    {
        foreach (var key in new[]
                 {
                     "bloc « %@ » pas encore pris en charge sur Windows.", "pas encore sur Windows", "FL n'est plus au premier plan",
                     "Échap", "touche interdite", "touche non prise en charge", "aucun menu de FL ouvert par la macro",
                     "le menu de FL n'a pas répondu", "boîte de dialogue introuvable", "la boîte de dialogue ne se ferme pas",
                     "ce bloc a besoin du lien avec FL (%@)", "armement non fait : %@", "page de FL à choisir dans la macro",
                     "action de FL inconnue",
                 })
            Assert.True(Loc.Has(key), $"« {key} » sans anglais");
    }
}
