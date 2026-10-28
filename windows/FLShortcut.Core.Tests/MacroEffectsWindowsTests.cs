// Effets des macros sur Windows, essayés sur un faux FL (fenêtres, touches, souris, textes lus, horloge simulée) :
// touches à FL seul et liste noire, arrêt (FL plus devant, Échap), menus ouverts par la macro, boîtes de dialogue,
// actions de FL et leurs replis, pages, clics appris, Menu de FL, blocs pas encore faits pour Windows (bloqués à la
// validation).
using FLShortcut.Core;
using FLShortcut.Core.Macros;
using FLShortcut.Core.Organizer;
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

    public (int X, int Y) Pointer { get; set; } = (600, 400);
    public List<(int X, int Y, bool Right)> Clicks { get; } = new();
    public List<(int AX, int AY, int BX, int BY)> Drags { get; } = new();
    /// Réaction de FL à un clic reçu.
    public Action<int, int, bool>? OnClick { get; set; }
    /// Programme qui couvre tout FL (null : rien).
    public string? Cover { get; set; }
    public List<TextItem>? Bar { get; set; }
    public Dictionary<long, List<TextItem>> MenuTexts { get; } = new();
    public Dictionary<long, List<TextItem>> Texts { get; } = new();
    public int MenusCancelled { get; private set; }
    public AimedClick? LastAimedClick { get; set; }
    public List<byte[]> Data { get; } = new();
    public List<byte[]> Requests { get; } = new();
    /// Réponse du lien aux commandes avec données (null : faites).
    public int? DataRefusal { get; set; }
    public bool LinkInstalled { get; set; } = true;
    public List<(string Path, int X, int Y)> Drops { get; } = new();
    public List<(long Dialog, string Path)> Chosen { get; } = new();

    public string? DropFile(string path, int x, int y)
    {
        Drops.Add((path, x, y));
        return null;
    }

    public string? ChooseFile(long dialog, string path)
    {
        Chosen.Add((dialog, path));
        Hide(dialog);
        return null;
    }

    public DataReply RunData(IReadOnlyList<byte> units)
    {
        Data.Add(Pack7.Unpack(units.ToArray()) ?? Array.Empty<byte>());
        return DataRefusal is { } r ? new DataReply.Refused(r) : new DataReply.Done();
    }

    public RequestReply RunRequest(byte[] bytes)
    {
        Requests.Add(bytes);
        return DataRefusal is { } r ? new RequestReply.Refused(r) : new RequestReply.Answered(Array.Empty<byte>());
    }

    public void After(int ms, Action a) => _timeline.Add((Now.AddMilliseconds(ms), a));
    public void Show(long id, FlWindowRole role) => Open.Insert(0, new FlWin(id, role, 100, 100, 300, 200));
    public void Show(long id, FlWindowRole role, int x, int y, int width, int height) =>
        Open.Insert(0, new FlWin(id, role, x, y, width, height));
    public void Hide(long id) => Open.RemoveAll(w => w.Id == id);

    public (int X, int Y) Cursor() => Pointer;
    public void MoveCursor(int x, int y) => Pointer = (x, y);

    public (long? Window, string? Cover) At(int x, int y)
    {
        if (Cover is not null) return (null, Cover);
        foreach (var w in Open)
            if (x >= w.X && x < w.X + w.Width && y >= w.Y && y < w.Y + w.Height) return (w.Id, null);
        return (null, null);
    }

    public bool Click(int x, int y, bool right, int hoverMs)
    {
        if (!Front) return false;
        Pointer = (x, y);
        Sleep(hoverMs);
        Clicks.Add((x, y, right));
        OnClick?.Invoke(x, y, right);
        return true;
    }

    public bool Drag(int ax, int ay, int bx, int by)
    {
        if (!Front) return false;
        Drags.Add((ax, ay, bx, by));
        Pointer = (bx, by);
        return true;
    }

    public IReadOnlyList<TextItem>? MenuBar() => Bar;
    public IReadOnlyList<TextItem>? MenuItems(long window) => MenuTexts.TryGetValue(window, out var items) ? items : null;
    public IReadOnlyList<TextItem>? ReadText(long window) => Texts.TryGetValue(window, out var items) ? items : null;
    public void CancelMenus() => MenusCancelled++;

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
        return Start(fl);
    }

    private static (FakeFl Fl, MacroEffectsWindows Fx, RunState State) Start(FakeFl fl)
    {
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
                new(new BlockBody.MenuBar(new[] { "File", "Export" })),
                new(new BlockBody.SoundCard()),
            },
        };
        Assert.Equal("Étape 2 : bloc « Carte son branchée » pas encore pris en charge sur Windows.", MacroProgram.Compile(doc, ctx).Problem);
        Assert.Null(MacroEffectsWindows.Unsupported(new BlockBody.DropFile("x.fst")));
        Assert.Null(MacroProgram.Compile(doc).Problem);                          // sans règle du système : rien

        doc.Blocks[1].Enabled = false;
        Assert.True(MacroProgram.Compile(doc, ctx).IsRunnable);
        Assert.NotNull(MacroEffectsWindows.Unsupported(new BlockBody.Click(
            new ClickTarget.Button(new VisualSpot(Corner.TopLeft, 1, 1, new Size2(100, 100), null, 12, new byte[144])))));
    }

    // ---------- Clics appris ----------

    /// Clic appris dans la fenêtre des réglages que la touche précédente ouvre un peu plus tard : attendue, puis cliquée
    /// à sa place ; le clic suivant part de lui ; le pointeur revient où il était.
    [Fact]
    public void LearnedClickWaitsForItsWindow()
    {
        var (fl, fx, state) = Start();
        fl.OnKey = _ => fl.After(400, () => fl.Show(40, FlWindowRole.Dialog, 300, 200, 500, 400));
        fx.Perform(new BlockBody.Key(CtrlS), state);
        var click = new BlockBody.Click(new ClickTarget.FlWindowPoint(Corner.TopLeft, 120, 80, new Size2(500, 400)));
        Assert.IsType<StepResult.Ok>(fx.Perform(click, state));
        Assert.Equal((420, 280, false), Assert.Single(fl.Clicks));
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.Click(new ClickTarget.LastClick(10, 0), MouseButton.Right), state));
        Assert.Equal((430, 280, true), fl.Clicks[^1]);
        fx.Cleanup(state);
        Assert.Equal((600, 400), fl.Pointer);
    }

    [Fact]
    public void LearnedClickRefusesAMissingWindowAnotherAppOrOutsideFl()
    {
        var (fl, fx, state) = Start();
        var click = new BlockBody.Click(new ClickTarget.FlWindowPoint(Corner.TopLeft, 10, 10, new Size2(500, 400)));
        Assert.Equal("fenêtre de FL de 500 × 400 introuvable (pas ouverte, ou changée de taille : montre de nouveau le clic)",
            Assert.IsType<StepResult.Fail>(fx.Perform(click, state)).Why);

        Assert.Equal("le point visé est hors de FL",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.Click(new ClickTarget.StartCursor(4000, 0)), state)).Why);
        fl.Cover = "Discord";
        Assert.Equal("« Discord » couvre FL à cet endroit",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.Click(new ClickTarget.StartCursor(0, 0)), state)).Why);
        Assert.Empty(fl.Clicks);
    }

    /// Bouton retrouvé à son nom : là où il est maintenant (déplacé de 20 pixels), sinon sa place apprise.
    [Fact]
    public void NamedButtonIsFoundWhereItIsNow()
    {
        var (fl, fx, state) = Start(f => f.Show(40, FlWindowRole.Other, 300, 200, 500, 400));
        var spot = new NamedSpot("Insert 1", 0, 0, Corner.TopLeft, 60, 30, new Size2(500, 400));
        fl.Texts[40] = new() { new TextItem("Master", 320, 222, 40, 16), new TextItem("Insert 1", 360, 222, 40, 16) };
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.Click(new ClickTarget.Named(spot)), state));
        Assert.Equal((380, 230, false), fl.Clicks[^1]);
        Assert.All(fl.Lines, l => Assert.DoesNotContain("Insert", l));               // jamais le nom au journal

        fl.Texts.Clear();                                                            // illisible : sa place
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.Click(new ClickTarget.Named(spot)), state));
        Assert.Equal((360, 230, false), fl.Clicks[^1]);
    }

    /// Piste visée : le dernier clic de l'utilisateur dans FL si sa fenêtre n'a pas changé, sinon le pointeur.
    [Fact]
    public void AimedTrackIsTheLastClickInAnUnchangedWindow()
    {
        var (fl, fx, state) = Start(f => f.LastAimedClick = new AimedClick(700, 500, FakeFl.Main, 1200, 800, f.Now));
        Assert.True(fx.TargetTrackIsInFl());
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.Click(new ClickTarget.Track(0, 4)), state));
        Assert.Equal((700, 504, false), fl.Clicks[^1]);

        (fl, fx, state) = Start(f => f.LastAimedClick = new AimedClick(700, 500, FakeFl.Main, 1000, 800, f.Now));
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.Click(new ClickTarget.Track(0, 0)), state));
        Assert.Equal((600, 400, false), fl.Clicks[^1]);                              // fenêtre changée : le pointeur
    }

    [Fact]
    public void DragGoesFromOneSpotToTheOther()
    {
        var (fl, fx, state) = Start();
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.Drag(new ClickTarget.StartCursor(0, 0), new ClickTarget.StartCursor(100, 20)), state));
        Assert.Equal((600, 400, 700, 420), Assert.Single(fl.Drags));
        Assert.Equal("le glisser sort de FL",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.Drag(new ClickTarget.StartCursor(0, 0), new ClickTarget.StartCursor(5000, 0)), state)).Why);
    }

    // ---------- Nom et couleur ----------

    /// Nom et couleur par le lien (opération 1), dégradé (opération 8), refus de FL expliqué ; jamais le nom au journal.
    [Fact]
    public void NameAndColorGoThroughTheLink()
    {
        var (fl, fx, state) = Start();
        var red = new RgbColor(0xE0, 0x45, 0x3A);
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.NameColor("Kick", red), state));
        Assert.Equal(new byte[] { 1, 3, 0xE0, 0x45, 0x3A, 4, (byte)'K', (byte)'i', (byte)'c', (byte)'k' }, Assert.Single(fl.Data));
        Assert.All(fl.Lines, l => Assert.DoesNotContain("Kick", l));

        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.NameColor(null, red, new RgbColor(0, 0, 255)), state));
        Assert.Equal(new byte[] { 8, 0xE0, 0x45, 0x3A, 0, 0, 255 }, Assert.Single(fl.Requests));

        Assert.IsType<StepResult.Warn>(fx.Perform(new BlockBody.NameColor("Kick", red, null, FlIcon.Make(2, 3)), state));

        fl.DataRefusal = 2;
        Assert.Equal("Sélectionne une piste ou un canal.",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.NameColor("Kick", red), state)).Why);
    }

    // ---------- Menu de la piste, preset ----------

    /// Clic droit sur la dernière piste cliquée, puis F (sous-menu File) et O (Open mixer track state) : FL referme son
    /// menu tout seul, pas d'Entrée.
    [Fact]
    public void TrackMenuRightClicksTheAimedTrackThenTypesTheLetters()
    {
        var (fl, fx, state) = Start(f => f.LastAimedClick = new AimedClick(700, 500, FakeFl.Main, 1200, 800, f.Now));
        fl.OnClick = (_, _, right) => { if (right) fl.After(50, () => fl.Show(10, FlWindowRole.Menu, 690, 490, 180, 300)); };
        fl.OnKey = c =>
        {
            if (c.Vk == Vk.Letter('F')) fl.After(60, () => fl.Show(11, FlWindowRole.Menu, 870, 500, 200, 120));
            else if (c.Vk == Vk.Letter('O')) fl.After(40, () => { fl.Hide(11); fl.Hide(10); });
        };
        var block = new BlockBody.TrackMenu("fo", new[] { "File", "Open mixer track state" }, TrackTarget.LastClicked, EnterPolicy.IfNeeded);
        Assert.IsType<StepResult.Ok>(fx.Perform(block, state));
        Assert.Equal((700, 500, true), Assert.Single(fl.Clicks));
        Assert.Equal(new[] { Vk.Letter('F'), Vk.Letter('O') }, fl.Sent.Select(c => c.Vk));
        Assert.DoesNotContain(fl.Open, w => w.Role == FlWindowRole.Menu);
        fx.Cleanup(state);
        Assert.Equal((600, 400), fl.Pointer);
    }

    /// Preset déposé sur la piste visée ; preset absent ou piste hors de FL : dit, rien n'est glissé. Chemin jamais au
    /// journal. Boîte « Open » : le chemin y est écrit.
    [Fact]
    public void PresetIsDroppedOnTheAimedTrackOrChosenInTheOpenBox()
    {
        var preset = Path.Combine(Path.GetTempPath(), $"FLS essai {Guid.NewGuid():N}.fst");
        File.WriteAllBytes(preset, new byte[] { 1 });
        try
        {
            var (fl, fx, state) = Start(f => f.LastAimedClick = new AimedClick(700, 500, FakeFl.Main, 1200, 800, f.Now));
            Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.DropFile(preset), state));
            Assert.Equal((preset, 700, 500), Assert.Single(fl.Drops));
            Assert.All(fl.Lines, l => Assert.DoesNotContain("essai", l));
            Assert.StartsWith("preset introuvable (",
                Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.DropFile(preset + ".absent"), state)).Why);

            (fl, fx, state) = Start(f => f.Pointer = (5000, 5000));
            Assert.Equal("la piste visée est hors de FL : clique d'abord sur ta piste dans le Mixer",
                Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.DropFile(preset), state)).Why);
            Assert.Empty(fl.Drops);

            (fl, fx, state) = Start();
            Assert.Equal("boîte « Open » introuvable",
                Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.ChooseFile(preset), state)).Why);
            fl.Show(30, FlWindowRole.Dialog);
            Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.ChooseFile(preset), state));
            Assert.Equal((30L, preset), Assert.Single(fl.Chosen));
        }
        finally { File.Delete(preset); }
    }

    // ---------- « Cliquer sur… » ----------

    /// Mute d'un canal : par le lien, sinon la touche de FL (canaux 1 à 10) ; renommer : par le lien ; menu Arrangement :
    /// pas encore sous Windows.
    [Fact]
    public void PageOptionsUseTheLinkOrTheirKey()
    {
        var (fl, fx, state) = Start();
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.PageOption("channelRack.chMute", "3"), state));
        Assert.Equal(new byte[] { 13, 0, 0, 2 }, Assert.Single(fl.Requests));

        fl.LinkInstalled = false;
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.PageOption("channelRack.chMute", "3"), state));
        Assert.Equal(new KeyCombo(Vk.Digit(3)), Assert.Single(fl.Sent));
        Assert.Single(fl.Requests);

        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.PageOption("mixer.rename", "Lead"), state));
        Assert.Equal(new byte[] { 1, 1, 0, 0, 0, 4, (byte)'L', (byte)'e', (byte)'a', (byte)'d' }, Assert.Single(fl.Data));
        Assert.All(fl.Lines, l => Assert.DoesNotContain("Lead", l));

        Assert.NotNull(MacroEffectsWindows.Unsupported(new BlockBody.PageOption("playlist.arrangementGo", "Arrangement 2")));
    }

    /// « Ajouter un instrument » : ADD › Channel › le plugin, par le menu de FL ; plugin absent : dit comme tel.
    [Fact]
    public void AddInstrumentGoesThroughTheAddMenu()
    {
        var done = new List<string>();
        var fl = new FakeFl { Bar = new() { new("FILE", 10, 4, 30, 12), new("ADD", 90, 4, 30, 12) } };
        var add = new List<TextItem> { Entry("Channel", 92, 24) };
        var channel = new List<TextItem> { Entry("Serum", 292, 26), Entry("Sytrus", 292, 46) };
        fl.OnClick = (x, y, _) =>
        {
            if (Hit(fl.Bar[1], x, y)) { fl.Show(30, FlWindowRole.Menu, 90, 20, 200, 60); fl.MenuTexts[30] = add; }
            else if (fl.Open.Any(w => w.Id == 30) && Hit(add[0], x, y)) { fl.Show(31, FlWindowRole.Menu, 290, 22, 200, 60); fl.MenuTexts[31] = channel; }
            else if (fl.Open.Any(w => w.Id == 31) && Hit(channel[0], x, y)) { done.Add("serum"); fl.Hide(31); fl.Hide(30); }
        };
        fl.OnKey = c =>
        {
            if (c.Vk != Vk.Escape) return;
            var top = fl.Open.FirstOrDefault(w => w.Role == FlWindowRole.Menu);
            if (top.Id != 0) fl.Hide(top.Id);
        };
        var (_, fx, state) = Start(fl);
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.PageOption("channelRack.addInstrument", "Serum"), state));
        Assert.Equal(new[] { "serum" }, done);
        Assert.All(fl.Lines, l => Assert.DoesNotContain("Serum", l));
        Assert.Equal("plugin introuvable dans le menu Add de FL : choisis-le de nouveau dans « Cliquer sur… »",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.PageOption("channelRack.addInstrument", "Massive"), state)).Why);
        Assert.DoesNotContain(fl.Open, w => w.Role == FlWindowRole.Menu);
    }

    // ---------- Menu de FL ----------

    private static TextItem Entry(string text, int x, int y, bool? greyed = null) => new(text, x, y, 150, 16, greyed);

    private static bool Hit(TextItem i, int x, int y) => x >= i.X && x < i.X + i.Width && y >= i.Y && y < i.Y + i.Height;

    /// FL simulé : FILE › Export › All playlist tracks › Time selection… ; chaque clic ouvre le menu suivant un peu plus
    /// tard, Échap referme le menu tout devant. `flRefuses` : le dernier élément ne fait rien (grisé dans FL).
    private static FakeFl MenuFl(List<string> done, bool flRefuses = false, bool? greyedFlag = null, int fillAfterMs = 0)
    {
        var fl = new FakeFl();
        fl.Bar = new() { new("FILE", 10, 4, 30, 12), new("EDIT", 50, 4, 30, 12), new("OPTIONS", 100, 4, 60, 12) };
        var file = new List<TextItem> { Entry("&New\tCtrl+N", 12, 24), Entry("Export", 12, 44) };
        var export = new List<TextItem> { Entry("Wave file...", 212, 46), Entry("All playlist tracks", 212, 66) };
        var all = new List<TextItem> { Entry("Time selection...", 432, 68, greyedFlag), Entry("Whole song", 432, 88) };
        bool IsOpen(long id) => fl.Open.Any(w => w.Id == id);
        fl.OnClick = (x, y, _) =>
        {
            if (Hit(fl.Bar[0], x, y))
                fl.After(60, () => { fl.Show(20, FlWindowRole.Menu, 10, 20, 200, 120); fl.MenuTexts[20] = file; });
            else if (IsOpen(20) && Hit(file[1], x, y))
                fl.After(60, () => { fl.Show(21, FlWindowRole.Menu, 210, 42, 220, 100); fl.MenuTexts[21] = export; });
            else if (IsOpen(21) && Hit(export[1], x, y))
                fl.After(60, () =>
                {
                    fl.Show(22, FlWindowRole.Menu, 430, 64, 200, 80);
                    fl.MenuTexts[22] = new();
                    fl.After(fillAfterMs, () => fl.MenuTexts[22] = all);                 // menu rempli à son ouverture
                });
            else if (IsOpen(22) && Hit(all[0], x, y) && !flRefuses)
            {
                done.Add("export time selection");
                fl.After(30, () => { fl.Hide(22); fl.Hide(21); fl.Hide(20); });
            }
        };
        fl.OnKey = c =>
        {
            if (c.Vk != Vk.Escape) return;
            var top = fl.Open.FirstOrDefault(w => w.Role == FlWindowRole.Menu);
            if (top.Id != 0) fl.Hide(top.Id);
        };
        return fl;
    }

    private static readonly string[] ExportPath = { "File", "Export", "All playlist tracks", "Time selection..." };

    /// Comme à la main : FILE en haut de FL, puis chaque élément dans le menu qui s'ouvre (un menu rempli à son
    /// ouverture est attendu) ; rien d'ouvert à la fin, aucun titre au journal, le pointeur revient.
    [Fact]
    public void MenuBarOpensEachMenuLikeByHand()
    {
        var done = new List<string>();
        var (fl, fx, state) = Start(MenuFl(done, fillAfterMs: 500));
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.MenuBar(ExportPath), state));
        Assert.Equal(new[] { "export time selection" }, done);
        Assert.Equal(4, fl.Clicks.Count);
        Assert.DoesNotContain(fl.Open, w => w.Role == FlWindowRole.Menu);
        Assert.All(fl.Lines, l =>
        {
            Assert.DoesNotContain("xport", l);
            Assert.DoesNotContain("election", l);
            Assert.DoesNotContain("FILE", l);
        });
        fx.Cleanup(state);
        Assert.Equal((600, 400), fl.Pointer);
    }

    /// Élément grisé (lu par Windows) : jamais cliqué, menus refermés ; grisé inconnu (lu dans l'image) et FL qui ne fait
    /// rien : dit, menus refermés.
    [Fact]
    public void MenuBarNeverClicksAGreyedItemAndClosesItsMenus()
    {
        var done = new List<string>();
        var (fl, fx, state) = Start(MenuFl(done, flRefuses: true, greyedFlag: true));
        Assert.Equal("élément grisé dans le menu de FL",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.MenuBar(ExportPath), state)).Why);
        Assert.Equal(3, fl.Clicks.Count);
        Assert.DoesNotContain(fl.Open, w => w.Role == FlWindowRole.Menu);
        Assert.Equal(1, fl.MenusCancelled);

        (fl, fx, state) = Start(MenuFl(done, flRefuses: true));
        Assert.Equal("le menu de FL est resté ouvert (élément grisé ?)",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.MenuBar(ExportPath), state)).Why);
        Assert.Equal(4, fl.Clicks.Count);
        Assert.DoesNotContain(fl.Open, w => w.Role == FlWindowRole.Menu);
        Assert.Empty(done);
    }

    [Fact]
    public void MenuBarSaysWhatIsMissing()
    {
        var done = new List<string>();
        var (fl, fx, state) = Start(MenuFl(done));
        Assert.Equal("élément introuvable dans le menu de FL (renommé, ou FL dans une autre langue ?)",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.MenuBar(new[] { "File", "Import" }), state)).Why);
        Assert.DoesNotContain(fl.Open, w => w.Role == FlWindowRole.Menu);
        Assert.Equal("élément introuvable dans le menu de FL (renommé, ou FL dans une autre langue ?)",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.MenuBar(new[] { "Tools", "Macros" }), state)).Why);
        Assert.Equal("chemin de menu incomplet",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.MenuBar(new[] { "File" }), state)).Why);

        fl.Bar = null;
        Assert.Equal("titres du menu de FL illisibles en haut de sa fenêtre (FL est-il bien devant ?)",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.MenuBar(ExportPath), state)).Why);
        Assert.Empty(done);
    }

    /// Lecture tolérante : « & » et raccourci d'un menu standard, « … », casse, une lettre mal lue dans l'image.
    [Fact]
    public void MenuTextComparesLikeAPerson()
    {
        var items = new List<TextItem>
        {
            new("&Save\tCtrl+S", 0, 0, 100, 16), new("Save as...  Ctrl+Shift+S", 0, 20, 100, 16),
            new("Project genera1 settings", 0, 40, 100, 16), new("Purge unused audio clips", 0, 60, 100, 16),
        };
        Assert.Equal(0, MenuText.Find("Save", items)!.Value.Y);
        Assert.Equal(20, MenuText.Find("Save as…", items)!.Value.Y);
        Assert.Equal(40, MenuText.Find("Project general settings", items)!.Value.Y);
        Assert.Equal(60, MenuText.Find("PURGE UNUSED AUDIO CLIPS", items)!.Value.Y);
        Assert.Null(MenuText.Find("Purge", items));
        Assert.Null(MenuText.Find("Sove", items));                                    // mot court : jamais à une lettre près
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
                     "action de FL inconnue", "élément introuvable dans le menu de FL (renommé, ou FL dans une autre langue ?)",
                     "titres du menu de FL illisibles en haut de sa fenêtre (FL est-il bien devant ?)",
                     "le menu de FL est resté ouvert (élément grisé ?)", "élément grisé dans le menu de FL",
                     "bouton retrouvé à son image : pas encore sur Windows (montre de nouveau le clic sur ce PC).",
                     "« %@ » couvre FL à cet endroit", "« %@ » couvre le menu de FL", "le point visé est hors de FL",
                     "icône pas encore posée sous Windows (pose-la dans FL avec F2)",
                 })
            Assert.True(Loc.Has(key), $"« {key} » sans anglais");
    }
}
