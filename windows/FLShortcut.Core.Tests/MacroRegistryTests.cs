// Registre des blocs et validation des macros : mêmes essais que Tests/FLShortcutTests/MacroModelTests.swift (partie
// « Registre »), MacroValidationTests.swift et MacroPagesTests.swift, avec les touches interdites de Windows.
using FLShortcut.Core;
using FLShortcut.Core.Macros;
using FLShortcut.Core.Organizer;
using Xunit;

namespace FLShortcut.Core.Tests;

public class MacroRegistryTests
{
    private const string Home = @"C:\Users\malo";
    private static readonly KeyRef AltF4 = new(new MacKey(118, Option: true));

    private static Block B(BlockBody body) => new(body);

    private static string? Problem(IReadOnlyList<Block> blocks, IReadOnlyList<VariableDecl>? variables = null, bool strict = false) =>
        MacroValidation.Problem(blocks, variables, new ValidationContext { StrictFiles = strict, Home = Home });

    // ---------- Registre ----------

    [Fact]
    public void EveryTypeHasFrenchTextsEnglishAndASymbol()
    {
        foreach (var t in BlockTypes.All)
        {
            var s = BlockRegistry.Spec(t);
            Assert.Equal(t, s.Type);
            Assert.False(string.IsNullOrEmpty(s.Label), t.ToString());
            Assert.NotEqual(t.Raw(), s.Label);
            Assert.True(s.Help.Length > 20, t.ToString());
            Assert.False(string.IsNullOrEmpty(s.Symbol), t.ToString());
            Assert.True(Loc.Has(s.Label), $"{t} : « {s.Label} » sans anglais");
            foreach (var p in s.Params) Assert.True(Loc.Has(p.Label), $"{t} : « {p.Label} » sans anglais");
        }
    }

    /// Valeur par défaut de chaque type : valide seule (variable « n » déclarée). « Cliquer sur… » demande sa page
    /// au-dessus ; « Menu de FL » est vide, à choisir dans les menus de FL.
    [Fact]
    public void DefaultsAreValid()
    {
        foreach (var t in BlockTypes.All.Where(t => t is not BlockType.PageOption and not BlockType.MenuBar))
        {
            var problem = MacroValidation.Problem(new[] { B(BlockRegistry.Spec(t).Default()) }, new[] { new VariableDecl("n") },
                new ValidationContext());
            Assert.True(problem is null, $"{t} : {problem}");
        }
        var page = B(BlockRegistry.Spec(BlockType.OpenPage).Default());
        Assert.Null(Problem(new[] { page, B(BlockRegistry.Spec(BlockType.PageOption).Default()) }));
        Assert.NotNull(Problem(new[] { B(BlockRegistry.Spec(BlockType.PageOption).Default()) }));
    }

    [Fact]
    public void PaletteHidesLegacyAndUnfinishedBlocks()
    {
        var shown = BlockRegistry.Palette.SelectMany(p =>
        {
            Assert.All(p.Specs, s => Assert.Equal(p.Category, s.Category));
            return p.Specs.Select(s => s.Type);
        }).ToList();
        Assert.DoesNotContain(BlockType.MenuAX, shown);
        Assert.Contains(BlockType.TrackMenu, shown);
        Assert.Contains(BlockType.MenuBar, shown);
        Assert.Equal(shown.Count, shown.Distinct().Count());
    }

    /// Le journal garde les noms des anciennes étapes (les mêmes que le Mac).
    [Fact]
    public void JournalKeepsTheOldStepNames()
    {
        Assert.Equal("waitDialog", BlockRegistry.Journal(new BlockBody.WaitWindow(WindowKind.Dialog, 4_000)));
        Assert.Equal("waitDialogClose", BlockRegistry.Journal(new BlockBody.WaitWindowClose(WindowKind.Dialog, 8_000)));
        Assert.Equal("armTrack", BlockRegistry.Journal(new BlockBody.FlAction("armon", ActionFallback.TrackMenuArm)));
        Assert.Equal("recordOn", BlockRegistry.Journal(new BlockBody.FlAction("recon", ActionFallback.None)));
        Assert.Equal("menu", BlockRegistry.Journal(new BlockBody.MenuAX(new[] { "File" }, Array.Empty<ClickTarget>())));
        Assert.Equal("unknown", BlockRegistry.Journal(new BlockBody.Unknown("x", null)));
        Assert.Equal("openPage mixer", BlockRegistry.Journal(new BlockBody.OpenPage(FlPage.Mixer)));
    }

    /// Jamais une touche, un chemin, un nom de piste ou un texte de l'utilisateur dans le journal.
    [Fact]
    public void JournalNeverContainsPrivateData()
    {
        var bodies = new BlockBody[]
        {
            new BlockBody.ChooseFile(@"C:\Users\secret\Presets\Voix lead.fst"),
            new BlockBody.Key(new KeyRef(new MacKey(1, Command: true), "s"), 1),
            new BlockBody.TrackMenu("fo", new[] { "Piste secrète", "Voix" }, TrackTarget.LastClicked, EnterPolicy.IfNeeded),
            new BlockBody.Comment("secret"), new BlockBody.Stop("secret"), new BlockBody.SetVariable("secret", IntSource.Constant(1)),
            new BlockBody.FlAction("secret", ActionFallback.None), new BlockBody.MenuAX(new[] { "Secret" }, Array.Empty<ClickTarget>()),
            new BlockBody.NameColor("SecretTrack", null), new BlockBody.PageOption("channelRack.addInstrument", "Secret Synth"),
        };
        foreach (var body in bodies)
        {
            var line = BlockRegistry.Journal(body).ToLowerInvariant();
            foreach (var word in new[] { "secret", "voix", "users", "fst", "piste", "ctrl" }) Assert.DoesNotContain(word, line);
        }
    }

    [Fact]
    public void SummaryLines()
    {
        Assert.Equal("Ctrl + S × 2", BlockRegistry.Spec(BlockType.Key).Summary(new BlockBody.Key(new KeyRef(new MacKey(1, Command: true), "s"), 2)));
        Assert.Equal("File › Open mixer track state", BlockRegistry.Spec(BlockType.TrackMenu).Summary(Specs.OpenStateMenu));
        Assert.Equal("1,5 s", BlockRegistry.Spec(BlockType.Delay).Summary(new BlockBody.Delay(1_500)));
        Assert.Equal("200 ms", BlockRegistry.Spec(BlockType.Delay).Summary(new BlockBody.Delay(200)));
        Assert.Equal("Voix.fst", BlockRegistry.Spec(BlockType.ChooseFile).Summary(new BlockBody.ChooseFile(@"C:\Users\a\Voix.fst")));
        Assert.Equal("Voix.fst", BlockRegistry.Spec(BlockType.ChooseFile).Summary(new BlockBody.ChooseFile("/Users/a/Voix.fst")));
        Assert.Equal("Boîte de dialogue · 4 s au plus", BlockRegistry.Spec(BlockType.WaitWindow).Summary(new BlockBody.WaitWindow(WindowKind.Dialog, 4_000)));
        Assert.Equal("Mute du canal 3", BlockRegistry.Spec(BlockType.PageOption).Summary(new BlockBody.PageOption("channelRack.chMute", "3")));
        Assert.Equal("Si une boîte de dialogue est ouverte",
            BlockRegistry.Spec(BlockType.IfElse).Summary(new BlockBody.IfElse(new Condition.WindowOpen(WindowKind.Dialog), new(), new())));
    }

    [Fact]
    public void NeedsAreAggregatedOverTheWholeTree()
    {
        // Au fond d'un « si », un bloc actif compte ; inactif, non.
        var nested = B(new BlockBody.IfElse(new Condition.WindowOpen(WindowKind.Dialog), new List<Block> { B(new BlockBody.FeedbackCheck()) },
            new List<Block> { new(new BlockBody.FlAction("recon", ActionFallback.None), enabled: false) }));
        var needs = MacroValidation.Needs(new[] { nested });
        Assert.True(needs.HasFlag(BlockNeeds.FeedbackEarly));
        Assert.False(needs.HasFlag(BlockNeeds.MidiLink));
        Assert.True(MacroValidation.Needs(new[] { B(new BlockBody.FlActionValue("trnext", IntSource.Constant(1))) }).HasFlag(BlockNeeds.MidiExtensions));
        var menu = MacroValidation.Needs(new[] { B(Specs.OpenStateMenu) });
        Assert.True(menu.HasFlag(BlockNeeds.AimedTrack | BlockNeeds.TrackRequired | BlockNeeds.KeyboardIdleInside | BlockNeeds.Clicks));
        // Mute sans lien : par la piste visée.
        Assert.True(BlockRegistry.Needs(new BlockBody.FlAction("mute", ActionFallback.None)).HasFlag(BlockNeeds.AimedTrack));
        Assert.True(BlockRegistry.Needs(new BlockBody.NameColor("Kick", null)).HasFlag(BlockNeeds.MidiLink));
    }

    // ---------- Validation ----------

    [Fact]
    public void EmptyMacro() => Assert.Equal("La macro est vide.", Problem(Array.Empty<Block>()));

    [Fact]
    public void ForbiddenKeysAreRefused()
    {
        Assert.Equal("Étape 1 : touche interdite (Alt+F4 ferme l'application).", Problem(new[] { B(new BlockBody.Key(AltF4, 1)) }));
        Assert.Equal("Étape 2 : touche REC interdite (Alt+F4 ferme l'application).",
            Problem(new[] { B(new BlockBody.Delay(1)), B(new BlockBody.FlAction("recon", ActionFallback.Key(AltF4))) }));
        // ⌘⌥ (Ctrl+Alt sur Windows) : AltGr, jamais envoyé.
        Assert.StartsWith("Étape 1 : touche interdite (Ctrl+Alt",
            Problem(new[] { B(new BlockBody.Key(new KeyRef(new MacKey(1, Command: true, Option: true), "s"), 1)) }));
        Assert.Equal("Étape 1 : touche non prise en charge.", Problem(new[] { B(new BlockBody.Key(new KeyRef(new MacKey(56)), 1)) }));
        Assert.Equal("Étape 1 : pause hors limites.", Problem(new[] { B(new BlockBody.Delay(5_001)) }));
        Assert.Equal("Étape 1 : attente hors limites.", Problem(new[] { B(new BlockBody.WaitWindow(WindowKind.Dialog, 99)) }));
        Assert.Equal("Étape 1 : chemin de fichier invalide.", Problem(new[] { B(new BlockBody.ChooseFile("C:\\a\nb.fst")) }));
        Assert.Equal("Étape 1 : position invalide.",
            Problem(new[] { B(new BlockBody.Click(new ClickTarget.StartCursor(double.PositiveInfinity, 0))) }));
    }

    /// Une touche interdite au fond d'un « si » est trouvée ; le sinon continue la numérotation du alors.
    [Fact]
    public void ForbiddenKeyDeepInsideIsFound()
    {
        var inner = B(new BlockBody.IfElse(new Condition.WindowOpen(WindowKind.Dialog),
            new List<Block> { B(new BlockBody.Delay(1)), B(new BlockBody.Delay(1)) },
            new List<Block> { B(new BlockBody.RepeatCount(2, new List<Block> { B(new BlockBody.Key(AltF4, 1)) })) }));
        Assert.StartsWith("Étape 2.3.1 : touche interdite", Problem(new[] { B(new BlockBody.Delay(1)), inner }));
    }

    [Fact]
    public void TreeLimits()
    {
        Assert.Null(Problem(Enumerable.Range(0, MacroValidation.MaxBlocks).Select(_ => B(new BlockBody.Delay(1))).ToList()));
        Assert.Equal("Macro trop longue (200 blocs au plus).",
            Problem(Enumerable.Range(0, MacroValidation.MaxBlocks + 1).Select(_ => B(new BlockBody.Delay(1))).ToList()));
        var nested = new List<Block> { B(new BlockBody.Delay(1)) };
        for (var i = 0; i < MacroValidation.MaxDepth; i++) nested = new List<Block> { B(new BlockBody.RepeatCount(1, nested)) };
        Assert.Null(Problem(nested));
        Assert.Equal("Blocs trop imbriqués (4 niveaux au plus).", Problem(new[] { B(new BlockBody.RepeatCount(1, nested)) }));
        Assert.Equal("Étape 1 : nombre de répétitions hors limites.", Problem(new[] { B(new BlockBody.RepeatCount(51, new())) }));
        Assert.Equal("Étape 1 : nombre de tours hors limites.",
            Problem(new[] { B(new BlockBody.RepeatWhile(new Condition.WindowOpen(WindowKind.Menu), 101, new())) }));
        Assert.Equal("Étape 1 : attente hors limites.",
            Problem(new[] { B(new BlockBody.WaitUntil(new Condition.WindowOpen(WindowKind.Menu), 120_001)) }));
    }

    /// Pire durée : corps × nombre de tours, délais d'attente ; 300 s au plus.
    [Fact]
    public void WorstCaseDuration()
    {
        Assert.Null(Problem(new[] { B(new BlockBody.RepeatCount(50, new List<Block> { B(new BlockBody.Delay(5_000)) })) }));
        Assert.Equal("Macro trop longue (durée totale).",
            Problem(new[] { B(new BlockBody.RepeatCount(50, new List<Block> { B(new BlockBody.Delay(5_000)), B(new BlockBody.Delay(2_000)) })) }));
        Assert.Equal(950, MacroValidation.EstimateMs(new[] { B(new BlockBody.IfElse(new Condition.LastBlockFailed(),
            new List<Block> { B(new BlockBody.Delay(300)) }, new List<Block> { B(new BlockBody.Delay(900)) })) }));
        Assert.Equal(0, MacroValidation.EstimateMs(new[] { new Block(new BlockBody.Delay(900), enabled: false) }));
        // Boucles imbriquées : saturé, jamais négatif.
        var deep = new List<Block> { B(new BlockBody.WaitWindow(WindowKind.Dialog, 120_000)) };
        for (var i = 0; i < 4; i++) deep = new List<Block> { B(new BlockBody.RepeatCount(50, deep)) };
        Assert.True(MacroValidation.EstimateMs(deep) > MacroValidation.MaxEstimateMs);
    }

    [Fact]
    public void ConditionsAreBounded()
    {
        var leaf = new Condition.WindowOpen(WindowKind.Dialog);
        Assert.Null(Problem(new[] { B(new BlockBody.WaitUntil(new Condition.All(Enumerable.Repeat<Condition>(leaf, 6).ToList()), 1_000)) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.WaitUntil(new Condition.All(Enumerable.Repeat<Condition>(leaf, 7).ToList()), 1_000)) }));
        Assert.Null(Problem(new[] { B(new BlockBody.WaitUntil(new Condition.Not(new Condition.Not(leaf)), 1_000)) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.WaitUntil(new Condition.Not(new Condition.Not(new Condition.Not(leaf))), 1_000)) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.WaitUntil(new Condition.FlState("nope", CompareOp.Eq, 1), 1_000)) }));
        Assert.Null(Problem(new[] { B(new BlockBody.WaitUntil(new Condition.FlState("isrec", CompareOp.Eq, 1), 1_000)) }));
    }

    [Fact]
    public void VariablesMustBeDeclared()
    {
        var set = B(new BlockBody.SetVariable("n", IntSource.Constant(1)));
        Assert.Equal("Étape 1 : variable inconnue.", Problem(new[] { set }));
        Assert.Null(Problem(new[] { set }, new[] { new VariableDecl("n") }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.IfElse(new Condition.Variable("m", CompareOp.Eq, 1), new(), new())) }, new[] { new VariableDecl("n") }));
        Assert.NotNull(Problem(new[] { set }, new[] { new VariableDecl("N") }));
        Assert.NotNull(Problem(new[] { set }, new[] { new VariableDecl("n"), new VariableDecl("n") }));
        Assert.NotNull(Problem(new[] { set }, Enumerable.Range(0, 9).Select(i => new VariableDecl($"v{i}")).ToList()));
    }

    /// Un fichier importé ne peut jamais faire lire ou écrire une clé de mémoire quelconque.
    [Fact]
    public void LearnedKeysAreWhitelisted()
    {
        var menu = new BlockBody.TrackMenu("fo", Array.Empty<string>(), TrackTarget.LastClicked, EnterPolicy.Learned("enabled"));
        Assert.Equal("Étape 1 : mémoire de l'Entrée inconnue.", Problem(new[] { B(menu) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.MenuLetters("f", EnterPolicy.Learned("midiActions"))) }));
        Assert.Equal("Étape 1 : positions apprises inconnues.", Problem(new[] { B(new BlockBody.SelectInput(new LearnedRef("enabled"))) }));
        Assert.Null(Problem(new[] { B(Specs.OpenStateMenu), B(BlockRegistry.Spec(BlockType.SelectInput).Default()) }));
    }

    [Fact]
    public void MenuBlocks()
    {
        Assert.Null(Problem(new[] { B(new BlockBody.MenuLetters("sa", EnterPolicy.Never)) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.MenuLetters("f1", EnterPolicy.Never)) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.MenuLetters("", EnterPolicy.Never)) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.TrackMenu("fo", Array.Empty<string>(), TrackTarget.LastClicked, EnterPolicy.Never)) }));
        Assert.Null(Problem(new[] { B(new BlockBody.TrackMenu("r", Array.Empty<string>(), TrackTarget.LastClicked, EnterPolicy.IfNeeded)) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.TrackMenu("", Array.Empty<string>(), TrackTarget.LastClicked, EnterPolicy.IfNeeded)) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.TrackMenu("foxy", Array.Empty<string>(), TrackTarget.LastClicked, EnterPolicy.IfNeeded)) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.MenuKeyPress(MenuKey.Down, 21)) }));
        var hop = new PopupHop(10, 10, new Size2(200, 100));
        Assert.Null(Problem(new[] { B(new BlockBody.Click(new ClickTarget.OpenMenu(hop))) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.Click(new ClickTarget.OpenMenu(hop), MouseButton.Right)) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.FlAction("recon", ActionFallback.TrackMenuArm)) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.FlAction("teleport", ActionFallback.None)) }));
        Assert.Equal("Étape 1 : choisis l'élément dans les menus de FL.", Problem(new[] { B(new BlockBody.MenuBar(Array.Empty<string>())) }));
        Assert.Null(Problem(new[] { B(new BlockBody.MenuBar(new[] { "File", "Export", "Wave file..." })) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.MenuBar(new[] { "File" })) }));
    }

    /// Bibliothèque et imports : preset .fst du dossier personnel seulement ; modèle et anciennes macros : comme avant.
    [Fact]
    public void StrictFiles()
    {
        Assert.Null(Problem(new[] { B(new BlockBody.ChooseFile(@"D:\Disque\Voix.fst")) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.ChooseFile(@"D:\Disque\Voix.fst")) }, strict: true));
        Assert.Null(Problem(new[] { B(new BlockBody.ChooseFile(Home + @"\Documents\Voix.fst")) }, strict: true));
        Assert.Null(Problem(new[] { B(new BlockBody.ChooseFile(@"c:\users\MALO\Documents\Voix.FST")) }, strict: true));
        Assert.NotNull(Problem(new[] { B(new BlockBody.ChooseFile(Home + @"\Documents\Voix.txt")) }, strict: true));
        Assert.NotNull(Problem(new[] { B(new BlockBody.ChooseFile(Home + @"\..\x\Voix.fst")) }, strict: true));
        Assert.NotNull(Problem(new[] { B(new BlockBody.ChooseFile(Home + @"2\Voix.fst")) }, strict: true));
        // Macro reçue d'un Mac : chemin du Mac, à rechoisir.
        Assert.NotNull(Problem(new[] { B(new BlockBody.ChooseFile("/Users/malo/Voix.fst")) }, strict: true));
        Assert.Equal("Étape 1 : preset à choisir dans le créateur.", Problem(new[] { B(new BlockBody.DropFile("")) }));
        // Copie du modèle « Enregistrement rapide » : n'importe quel disque, mais un .fst.
        var anywhere = new ValidationContext { StrictFiles = true, PresetAnywhere = true, Home = Home };
        Assert.Null(MacroValidation.Problem(new[] { B(new BlockBody.ChooseFile(@"D:\Disque\Voix.fst")) }, null, anywhere));
        Assert.NotNull(MacroValidation.Problem(new[] { B(new BlockBody.ChooseFile(@"D:\Disque\Voix.wav")) }, null, anywhere));
    }

    [Fact]
    public void MacroDocNameAndFormat()
    {
        var blocks = new List<Block> { B(new BlockBody.Delay(1)) };
        var ctx = new ValidationContext();
        Assert.Null(MacroValidation.Problem(new MacroDoc { Name = "Ma macro", Blocks = blocks }, ctx));
        Assert.NotNull(MacroValidation.Problem(new MacroDoc { Name = new string('x', 61), Blocks = blocks }, ctx));
        Assert.NotNull(MacroValidation.Problem(new MacroDoc { Name = "Plus récente", Blocks = blocks, Format = 3 }, ctx));
    }

    [Fact]
    public void UnknownBlockBlocksTheMacroWithItsPath()
    {
        var unknown = new Block(new BlockBody.Unknown("teleport", null));
        var tree = new[] { B(new BlockBody.Delay(1)), B(new BlockBody.RepeatCount(2, new List<Block> { B(new BlockBody.Delay(1)), unknown })) };
        Assert.Equal("Étape 2.2 : bloc illisible ou d'une version plus récente de FL Shortcuts (« teleport ») : la macro est bloquée.", Problem(tree));
    }

    [Fact]
    public void NotesAndTextsAreBounded()
    {
        Assert.NotNull(Problem(new[] { new Block(new BlockBody.Delay(1), note: new string('n', 121)) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.Stop(new string('m', 121))) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.Comment(new string('c', 201))) }));
    }

    [Fact]
    public void BlockPaths()
    {
        var tree = new[]
        {
            B(new BlockBody.Delay(1)),
            B(new BlockBody.IfElse(new Condition.LastBlockFailed(), new List<Block> { B(new BlockBody.Delay(2)) },
                new List<Block> { B(new BlockBody.Delay(3)), B(new BlockBody.Delay(4)) })),
        };
        Assert.Equal(new BlockBody.Delay(4), MacroValidation.BlockAt("2.3", tree)?.Body);
        Assert.Equal(new BlockBody.Delay(2), MacroValidation.BlockAt("2.1", tree)?.Body);
        Assert.Null(MacroValidation.BlockAt("3", tree));
        Assert.Null(MacroValidation.BlockAt("x", tree));
        Assert.Equal(5, MacroValidation.Count(tree));
        Assert.Equal(1, MacroValidation.Depth(tree));
    }

    // ---------- Nom et couleur ----------

    [Fact]
    public void NameColorValidation()
    {
        var red = NameColorPayload.DefaultColor;
        Assert.Equal("Étape 1 : donne un nom ou une couleur.", Problem(new[] { B(new BlockBody.NameColor(null, null)) }));
        Assert.Null(Problem(new[] { B(new BlockBody.NameColor("Kick", null)) }));
        Assert.Null(Problem(new[] { B(new BlockBody.NameColor(null, red)) }));
        Assert.Null(Problem(new[] { B(new BlockBody.NameColor("Café 🎹", red)) }));
        Assert.Null(Problem(new[] { B(new BlockBody.NameColor(new string('é', 64), null)) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.NameColor(new string('a', 65), null)) }));
        Assert.NotNull(Problem(new[] { B(new BlockBody.NameColor("x\u0007y", null)) }));
        Assert.Equal("Étape 1 : donne un nom ou une couleur.", Problem(new[] { B(new BlockBody.NameColor("   ", null)) }));
        // é décomposé (e + accent) : 2 points de code, comme le compte le script.
        Assert.NotNull(Problem(new[] { B(new BlockBody.NameColor(string.Concat(Enumerable.Repeat("e\u0301", 33)), null)) }));
    }

    [Fact]
    public void FadeNeedsColorAndNoName()
    {
        var red = NameColorPayload.DefaultColor;
        var dark = new RgbColor(0x60, 0x10, 0x10);
        var icon = FlIcon.FromCode("1-0");
        Assert.Null(Problem(new[] { B(new BlockBody.NameColor(null, red, dark)) }));
        Assert.Equal("Étape 1 : un dégradé demande ses deux couleurs.", Problem(new[] { B(new BlockBody.NameColor(null, null, dark)) }));
        Assert.Equal("Étape 1 : un dégradé ne change pas le nom : retire le nom.", Problem(new[] { B(new BlockBody.NameColor("Kick", red, dark)) }));
        Assert.Null(Problem(new[] { B(new BlockBody.NameColor(null, null, null, icon)) }));
        Assert.Equal("Étape 1 : un dégradé ne pose pas d'icône : retire l'icône.", Problem(new[] { B(new BlockBody.NameColor(null, red, dark, icon)) }));
    }

    [Fact]
    public void NameColorTexts()
    {
        var red = NameColorPayload.DefaultColor;
        Assert.Equal("Kick · #E0453A", NameColorPayload.Summary("Kick", red));
        Assert.Equal("Kick", NameColorPayload.Summary(" Kick ", null));
        Assert.Equal("couleur #E0453A", NameColorPayload.Summary(null, red));
        Assert.Equal("dégradé #E0453A → #601010", NameColorPayload.Summary(null, red, new RgbColor(0x60, 0x10, 0x10)));
        Assert.Equal("nom et couleur à choisir", NameColorPayload.Summary(null, null));
        Assert.Equal("Ouvre le Mixer, le Channel rack ou la Playlist.", NameColorPayload.Message(1));
        Assert.Equal("FL a refusé le nom ou la couleur.", NameColorPayload.Message(5));
        Assert.Equal("Sélectionne au moins 2 pistes pour un dégradé.", NameColorPayload.Message(7));
        // Données de l'opération 1 : comme le Mac.
        Assert.Equal(new byte[] { 1, 3, 0xE0, 0x45, 0x3A, 2, (byte)'H', (byte)'i' }, new NameColorPayload(" Hi ", red).Bytes);
        Assert.Equal(new byte[] { 1, 2, 0xE0, 0x45, 0x3A, 0 }, new NameColorPayload(null, red).Bytes);
    }

    [Fact]
    public void ShortcutWaitingNamesTheBlockToSet()
    {
        var blocks = new[] { B(new BlockBody.Key(new KeyRef(new MacKey(1)), 1)), B(new BlockBody.ChooseFile("")) };
        Assert.Equal("Raccourci gardé, mais pas encore actif : règle d'abord le bloc 2 « " + BlockRegistry.Spec(BlockType.ChooseFile).Label
                     + " » (preset .fst attendu dans ton dossier personnel).",
            MacroValidation.ShortcutWaiting("Étape 2 : preset .fst attendu dans ton dossier personnel.", blocks));
        Assert.Equal("Raccourci gardé, mais pas encore actif : la macro est vide.", MacroValidation.ShortcutWaiting("La macro est vide.", Array.Empty<Block>()));
    }

    [Fact]
    public void StepMessagesAreSplitWithTheirOwnFormat()
    {
        var failed = new ValidationContext().Fail("position invalide.");
        Assert.Equal("1", MacroValidation.SplitStep(failed)?.Path);
        Assert.Equal("position invalide.", MacroValidation.SplitStep("Étape 3.2 : position invalide.")?.Text);
        Assert.Null(MacroValidation.SplitStep("La macro est vide."));
        Assert.Null(MacroValidation.SplitStep("Étape : rien"));
    }

    // ---------- Pages de FL et « Cliquer sur… » ----------

    [Fact]
    public void EachPageListsOnlyItsOwnOptions()
    {
        foreach (var page in Enum.GetValues<FlPage>())
        {
            var options = PageOptions.Options(page);
            Assert.All(options, o => Assert.Equal(page, o.Page));
            Assert.All(options, o => Assert.StartsWith(page.Raw() + ".", o.Id));
            Assert.Equal(options.Count, options.Select(o => o.Id).Distinct().Count());
            Assert.All(options, o => Assert.True(PageOptions.IsKnown(o.Id)));
        }
        Assert.Contains(PageOptions.Options(FlPage.Mixer), o => o.Id == "mixer.armon");
        Assert.Contains(PageOptions.Options(FlPage.ChannelRack), o => o.Id == "channelRack.addInstrument");
        // Touches 1 à 0 et F2 remplacées par « Mute d'un canal » et « Renommer » : plus proposées, toujours comprises.
        Assert.DoesNotContain(PageOptions.Options(FlPage.ChannelRack), o => o.Id == "channelRack.fl.channelRack.1");
        Assert.True(PageOptions.IsKnown("channelRack.fl.channelRack.1"));
        Assert.Null(PageOptions.Option("playlist.nope"));
        Assert.Equal(FlPage.Playlist, PageOptions.PageOf("playlist.marker"));
    }

    [Fact]
    public void OptionsPlayTheSafestWay()
    {
        // Armer : le lien, sinon le menu de la piste.
        Assert.Equal(new BlockBody.FlAction("armon", ActionFallback.TrackMenuArm), PageOptions.Body(PageOptions.Option("mixer.armon")!, ""));
        // Instrument : menu Add de FL › Channel › son nom (sous-menus compris).
        Assert.Equal(new[] { "Add", "Channel", "Fruity", "Fruity Limiter" },
            ((BlockBody.MenuBar)PageOptions.Body(PageOptions.Option("channelRack.addInstrument")!, "Fruity › Fruity Limiter")!).Titles);
        // Raccourci de FL de la page : sa touche.
        var key = PageOptions.Options(FlPage.Playlist).First(o => o.Kind is PageOption.OptionKind.Shortcut);
        Assert.IsType<BlockBody.Key>(PageOptions.Body(key, ""));
        Assert.True(PageOptions.UsesLink("mixer.mute"));
        Assert.False(PageOptions.UsesLink("channelRack.addInstrument"));
        Assert.True(PageOptions.Clicks("playlist.arrangementAdd"));
        // Page ouverte : le lien, sinon sa touche (F9 pour le Mixer).
        Assert.Equal(new KeyCombo(Vk.F(9)), MacKeys.ToWindows(((BlockBody.FlAction)FlPage.Mixer.OpenBody()).Fallback.KeyRef!));
        Assert.Equal(new KeyCombo(Vk.F(8), Alt: true), MacKeys.ToWindows(((BlockBody.FlAction)FlPage.Browser.OpenBody()).Fallback.KeyRef!));
        // Canal 1 à 10 : la touche de FL ; Ctrl pour le solo.
        Assert.Equal(new KeyCombo(Vk.Digit(3)), MacKeys.ToWindows(PageOptions.ChannelKey(3, solo: false)!));
        Assert.Equal(new KeyCombo(Vk.Digit(0), Ctrl: true), MacKeys.ToWindows(PageOptions.ChannelKey(10, solo: true)!));
        Assert.Null(PageOptions.ChannelKey(11, solo: false));
    }

    [Fact]
    public void ChannelNumberAndTrackNameAreAskedFor()
    {
        var page = B(new BlockBody.OpenPage(FlPage.ChannelRack));
        Assert.Equal("Étape 2 : écris le numéro du canal (1 à 999).", Problem(new[] { page, B(new BlockBody.PageOption("channelRack.chMute", "0")) }));
        Assert.Null(Problem(new[] { page, B(new BlockBody.PageOption("channelRack.chMute", " 12 ")) }));
        var mixer = B(new BlockBody.OpenPage(FlPage.Mixer));
        Assert.Equal("Étape 2 : écris le nouveau nom de la piste.", Problem(new[] { mixer, B(new BlockBody.PageOption("mixer.rename", "  ")) }));
        Assert.Null(Problem(new[] { mixer, B(new BlockBody.PageOption("mixer.rename", "Voix")) }));
        Assert.Equal("Étape 2 : choisis le plugin à ajouter (comme dans le menu Add de FL).",
            Problem(new[] { mixer, B(new BlockBody.PageOption("mixer.addEffect", "A › › B")) }));
        Assert.Null(Problem(new[] { mixer, B(new BlockBody.PageOption("mixer.addEffect", "Fruity Limiter")) }));
        Assert.Equal("Étape 1 : choisis l'option à cliquer.", Problem(new[] { B(new BlockBody.PageOption(null, "")) }));
        Assert.Equal("Étape 2 : option de FL inconnue.", Problem(new[] { mixer, B(new BlockBody.PageOption("mixer.teleport", "")) }));
    }

    /// Une option hors de sa page est signalée sur son étape, numérotée comme la validation.
    [Fact]
    public void OptionOutsideItsPageIsReportedOnItsStep()
    {
        var blocks = new[]
        {
            B(new BlockBody.OpenPage(FlPage.Mixer)),
            B(new BlockBody.RepeatCount(2, new List<Block> { B(new BlockBody.PageOption("mixer.armon", "")), B(new BlockBody.PageOption("playlist.marker", "")) })),
        };
        Assert.Equal("Étape 2.2 : cette option n'est pas dans Mixer, la page ouverte au-dessus : choisis-en une de cette page.", Problem(blocks));
        Assert.Equal("Étape 1 : ajoute « Ouvrir une page de FL » juste au-dessus et choisis la page de cette option.",
            Problem(new[] { B(new BlockBody.PageOption("mixer.armon", "")) }));
        Assert.Equal("Étape 1 : choisis la page de FL à ouvrir.", Problem(new[] { B(new BlockBody.OpenPage(null)) }));
    }

    // ---------- Catalogue des raccourcis de FL ----------

    [Fact]
    public void CatalogMatchesTheMacAndEveryTitleHasItsEnglish()
    {
        var all = FlCatalog.Native;
        Assert.Equal(270, all.Count);
        Assert.Equal(all.Count, all.Select(e => e.Id).Distinct().Count());
        Assert.All(all, e => Assert.True(Loc.Has(e.TitleKey), $"« {e.TitleKey} » sans anglais"));
        Assert.All(Enum.GetValues<FlSection>(), s => Assert.True(Loc.Has(s.Title()), s.ToString()));
        var save = all.Single(e => e.Id == "fl.general.cmd-s");
        Assert.Equal(new KeyCombo(Vk.Letter('S'), Ctrl: true), save.Combo);
        Assert.Equal(new KeyCombo(Vk.F(5)), all.Single(e => e.Id == "fl.general.f5").Combo);
        // Toutes ont une touche sur Windows.
        Assert.All(all, e => Assert.NotNull(e.Combo));
    }
}

public class MacroTemplateTests
{
    /// Chaque modèle se lit et ne demande que ce qui se règle sur chaque ordinateur (clics à montrer, preset, plugin).
    [Fact]
    public void GalleryTemplatesAreReadyOrAskForTheirSetting()
    {
        var gallery = MacroTemplates.Gallery;
        Assert.Equal(new[] { "threeFour", "quickDrop", "exportStems", "openVST", "purgeAudio" }, gallery.Select(t => t.Id));
        foreach (var t in gallery)
        {
            Assert.True(Loc.Has(t.Title), t.Id);
            Assert.True(Loc.Has(t.Summary), t.Id);
            var doc = t.Make();
            Assert.Equal(t.Id, doc.Origin?.Template);
            var problem = MacroValidation.Problem(doc, new ValidationContext { StrictFiles = true });
            switch (t.Id)
            {
                case "exportStems" or "purgeAudio":
                    Assert.Null(problem);
                    break;
                case "threeFour":
                    Assert.Equal("Étape 2 : position à montrer dans FL (« Montrer dans FL… » dans le créateur).", problem);
                    break;
                case "quickDrop":
                    Assert.Equal("Étape 1 : preset à choisir dans le créateur.", problem);
                    break;
                case "openVST":
                    Assert.Equal("Étape 2 : choisis le plugin à ajouter (comme dans le menu Add de FL).", problem);
                    break;
            }
            // Le même JSON après un aller-retour (macro partagée avec un Mac).
            var again = MacroDoc.FromJson(System.Text.Json.Nodes.JsonNode.Parse(doc.ToJson().ToJsonString()));
            Assert.Equal(doc.ToJson().ToJsonString(), again.ToJson().ToJsonString());
        }
        // Deux copies d'un modèle ne partagent jamais un id.
        Assert.NotEqual(gallery[0].Make().Blocks[0].Id, gallery[0].Make().Blocks[0].Id);
    }

    [Fact]
    public void FreshIdsAndNotesReachNestedBlocks()
    {
        var inner = new Block(new BlockBody.Delay(1), note: "dedans");
        var tree = new List<Block> { new(new BlockBody.RepeatCount(2, new List<Block> { inner }), note: "boucle") };
        var fresh = MacroTemplates.FreshIds(tree);
        var copied = ((BlockBody.RepeatCount)fresh[0].Body).Blocks[0];
        Assert.NotEqual(inner.Id, copied.Id);
        Assert.Equal("dedans", copied.Note);
        var bare = MacroTemplates.WithoutNotes(tree);
        Assert.Null(bare[0].Note);
        Assert.Null(((BlockBody.RepeatCount)bare[0].Body).Blocks[0].Note);
        Assert.Equal(inner.Id, ((BlockBody.RepeatCount)bare[0].Body).Blocks[0].Id);
    }

    /// Liste du « Menu de la piste » : chaque élément est valable, lettres distinctes, et « Ouvrir un état de piste »
    /// est exactement le bloc du modèle.
    [Fact]
    public void TrackMenuChoices()
    {
        var choices = MacroTemplates.TrackMenuChoices;
        Assert.Equal(choices.Count, choices.Select(c => c.Letters).Distinct().Count());
        foreach (var c in choices)
        {
            var body = new BlockBody.TrackMenu(c.Letters, c.Labels, TrackTarget.LastClicked, c.Enter);
            Assert.Null(MacroValidation.Problem(new[] { new Block(body) }, null, new ValidationContext()));
            Assert.Equal(c.Id, MacroTemplates.TrackMenuChoice(c.Letters)?.Id);
            Assert.True(Loc.Has(c.Name), c.Id);
        }
        var open = (BlockBody.TrackMenu)MacroTemplates.OpenStateMenu;
        var choice = MacroTemplates.TrackMenuChoice(open.Letters)!;
        Assert.Equal("openState", choice.Id);
        Assert.Equal(open.Labels, choice.Labels);
        Assert.Equal(open.FinalEnter, choice.Enter);
        Assert.Null(MacroTemplates.TrackMenuChoice("xy"));
    }

    [Fact]
    public void ArmThroughTrackMenuIsValid()
    {
        var rec = new KeyRef(new MacKey(15), "r");
        Assert.Null(MacroValidation.Problem(MacroTemplates.ArmThroughTrackMenu(rec), null, new ValidationContext()));
    }
}
