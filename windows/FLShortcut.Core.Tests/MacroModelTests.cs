// Macros en blocs : codage JSON identique au Mac (identifiants stables, décodage tolérant, blocs inconnus conservés).
// Mêmes essais que Tests/FLShortcutTests/MacroModelTests.swift (partie « Codage »), plus des macros écrites par le Mac.
using System.Text.Json.Nodes;
using FLShortcut.Core;
using FLShortcut.Core.Macros;
using FLShortcut.Core.Organizer;
using Xunit;

namespace FLShortcut.Core.Tests;

public class MacroModelTests
{
    private static List<Block> RoundTrip(IEnumerable<Block> blocks)
    {
        var json = new JsonArray(blocks.Select(b => b.ToJson()).ToArray()).ToJsonString();
        return JsonNode.Parse(json)!.AsArray().Select(n => Block.FromJson(n)).ToList();
    }

    private static List<Block> Parse(string json) => JsonNode.Parse(json)!.AsArray().Select(n => Block.FromJson(n)).ToList();

    private static void AssertSame(IReadOnlyList<Block> expected, IReadOnlyList<Block> actual)
    {
        Assert.Equal(expected.Count, actual.Count);
        for (var i = 0; i < expected.Count; i++)
            Assert.Equal(expected[i].ToJson()?.ToJsonString() ?? "null", actual[i].ToJson()?.ToJsonString() ?? "null");
    }

    [Fact]
    public void RichValuesRoundTrip()
    {
        var hop = new PopupHop(115, 54, new Size2(230, 88));
        var blocks = new List<Block>
        {
            new(new BlockBody.Key(new KeyRef(new MacKey(1, Command: true, Shift: true), "s"), 2), enabled: false,
                onFailure: FailurePolicy.KeepGoing, note: "enregistrer"),
            new(new BlockBody.Click(new ClickTarget.FlWindowPoint(Corner.BottomRight, -12.5, -40, new Size2(940, 652)), MouseButton.Right)),
            new(new BlockBody.Click(new ClickTarget.OpenMenu(hop))),
            new(new BlockBody.Click(new ClickTarget.Track(0, 300))),
            new(new BlockBody.Click(new ClickTarget.LastClick(3, 4))),
            new(new BlockBody.Click(new ClickTarget.StartCursor(-1, 2))),
            new(new BlockBody.Click(new ClickTarget.CursorXWindowY(12, 640))),
            new(new BlockBody.MenuLetters("sa", EnterPolicy.Always)),
            new(new BlockBody.MenuKeyPress(MenuKey.Left)),
            new(new BlockBody.WaitWindow(WindowKind.Menu, 1_500)),
            new(new BlockBody.WaitWindowClose(WindowKind.Menu, 800)),
            new(new BlockBody.FlAction("recon", ActionFallback.Key(new KeyRef(new MacKey(15))))),
            new(new BlockBody.FlAction("play", ActionFallback.None)),
            new(new BlockBody.FlActionValue("trnext", IntSource.Variable("n"))),
            new(new BlockBody.MenuAX(new[] { "File", "Open mixer track state" }, new ClickTarget[] { new ClickTarget.StartCursor(4, 5) })),
            new(new BlockBody.IfElse(
                new Condition.All(new Condition[]
                {
                    new Condition.WindowOpen(WindowKind.Dialog), new Condition.Not(new Condition.LastBlockFailed()),
                    new Condition.Any(new Condition[] { new Condition.Variable("n", CompareOp.Lt, 3), new Condition.FlState("isrec", CompareOp.Eq, 0) }),
                }),
                new List<Block> { new(new BlockBody.Delay(100)) },
                new List<Block> { new(new BlockBody.RepeatCount(3, new List<Block> { new(new BlockBody.MenuKeyPress(MenuKey.Down, 5)) })) })),
            new(new BlockBody.RepeatWhile(new Condition.WindowOpen(WindowKind.Menu), 7, new List<Block> { new(new BlockBody.Comment("tour")) })),
            new(new BlockBody.WaitUntil(new Condition.Not(new Condition.WindowOpen(WindowKind.Dialog)), 2_000)),
            new(new BlockBody.SetVariable("n", IntSource.FlState("track"))),
            new(new BlockBody.Stop("fini")),
            new(new BlockBody.OpenPage(FlPage.Mixer)),
            new(new BlockBody.PageOption("mixer.armon", "")),
            new(new BlockBody.MenuBar(new[] { "Tools", "Macros" })),
            new(new BlockBody.TrackMenu("fo", new[] { "File", "Open mixer track state" }, TrackTarget.LastClicked, EnterPolicy.IfNeeded)),
            new(new BlockBody.DropFile("~/Presets/Voix.fst")),
            new(new BlockBody.Drag(new ClickTarget.StartCursor(0, 0), new ClickTarget.ToLearn())),
        };
        AssertSame(blocks, RoundTrip(blocks));
    }

    /// Un bloc écrit par le Mac se relit et se réécrit à l'identique (mêmes clés, mêmes valeurs).
    [Fact]
    public void BlocksWrittenByTheMacAreReadAndRewrittenAsIs()
    {
        const string mac = """
            [{"type":"key","id":"F15C0009-0000-4000-8000-000000000001","enabled":true,"onFailure":"stop","key":{"combo":{"keyCode":1,"command":true},"char":"s"},"times":1},
             {"type":"trackMenu","id":"F15C0009-0000-4000-8000-000000000002","enabled":true,"onFailure":"continue","letters":"fo","labels":["File","Open mixer track state"],"target":"lastClicked","finalEnter":{"mode":"learned","key":"macroSpots.v2.openState"}},
             {"type":"click","id":"F15C0009-0000-4000-8000-000000000003","enabled":true,"onFailure":"stop","target":{"anchor":"flWindow","corner":"topRight","dx":-135,"dy":90,"size":[940,652]},"button":"left"},
             {"type":"nameColor","id":"F15C0009-0000-4000-8000-000000000004","enabled":true,"onFailure":"stop","color":"E0453A","fade":"7A2620","icon":"3-7"}]
            """;
        var blocks = Parse(mac);
        Assert.IsType<BlockBody.Key>(blocks[0].Body);
        var track = Assert.IsType<BlockBody.TrackMenu>(blocks[1].Body);
        Assert.Equal("macroSpots.v2.openState", track.FinalEnter.LegacyKey);
        Assert.Equal(FailurePolicy.KeepGoing, blocks[1].OnFailure);
        var click = Assert.IsType<BlockBody.Click>(blocks[2].Body);
        Assert.Equal(new ClickTarget.FlWindowPoint(Corner.TopRight, -135, 90, new Size2(940, 652)), click.Target);
        var color = Assert.IsType<BlockBody.NameColor>(blocks[3].Body);
        Assert.Equal("3-7", color.Icon?.Code);
        var original = JsonNode.Parse(mac)!.AsArray();
        for (var i = 0; i < blocks.Count; i++)
            Assert.True(JsonNode.DeepEquals(original[i], blocks[i].ToJson()), $"bloc {i + 1} : {blocks[i].ToJson()!.ToJsonString()}");
    }

    [Fact]
    public void MacroDocRoundTripAndTolerance()
    {
        var doc = new MacroDoc
        {
            Name = "Armer et enregistrer",
            Blocks = new List<Block> { new(new BlockBody.Delay(50)), new(new BlockBody.FeedbackCheck()) },
            Variables = new List<VariableDecl> { new("n", 2) },
            Origin = MacroOrigin.FromTemplate("autoRecord"),
            Revision = 4,
        };
        var back = MacroDoc.FromJson(JsonNode.Parse(doc.ToJson().ToJsonString()));
        Assert.Equal(doc.ToJson().ToJsonString(), back.ToJson().ToJsonString());
        // Champs manquants : valeurs par défaut, jamais d'échec.
        var sparse = MacroDoc.FromJson(JsonNode.Parse("""{"blocks":[{"type":"delay","ms":50}]}"""));
        Assert.Equal(2, sparse.Format);
        Assert.Equal("Macro", sparse.Name);
        Assert.Equal(new BlockBody.Delay(50), sparse.Blocks.Single().Body);
        Assert.True(sparse.Blocks[0].Enabled);
        Assert.Equal(FailurePolicy.Stop, sparse.Blocks[0].OnFailure);
    }

    /// Un bloc d'une version plus récente est conservé tel quel (réécrit à l'identique).
    [Fact]
    public void UnknownBlockIsKeptAsIs()
    {
        var blocks = Parse("""
            [{"type":"teleport","id":"F15C0009-0000-4000-8000-000000000042","destination":{"x":1,"y":[2,3]},"enabled":false},
             {"type":"delay","id":"F15C0009-0000-4000-8000-000000000043","ms":100}]
            """);
        var unknown = Assert.IsType<BlockBody.Unknown>(blocks[0].Body);
        Assert.Equal("teleport", unknown.TypeName);
        Assert.Equal(1, unknown.Raw!["destination"]!["x"]!.GetValue<int>());
        Assert.Equal("F15C0009-0000-4000-8000-000000000042", MacroIdsText(blocks[0].Id));
        Assert.False(blocks[0].Enabled);
        Assert.Equal(new BlockBody.Delay(100), blocks[1].Body);
        AssertSame(blocks, RoundTrip(blocks));
        Assert.Equal("teleport", blocks[0].ToJson()!["type"]!.GetValue<string>());
        Assert.NotNull(blocks[0].ToJson()!["destination"]);
    }

    private static string MacroIdsText(Guid id) => id.ToString("D").ToUpperInvariant();

    /// Un bloc connu mais illisible devient inconnu : jamais deviné.
    [Fact]
    public void MalformedKnownBlockIsKept()
    {
        var blocks = Parse("""[{"type":"delay","ms":"beaucoup"},{"type":"if","condition":{"type":"windowOpen","window":"dialog"},"then":[{"type":"key"}]}]""");
        Assert.Equal("delay", Assert.IsType<BlockBody.Unknown>(blocks[0].Body).TypeName);
        var ifElse = Assert.IsType<BlockBody.IfElse>(blocks[1].Body);
        Assert.Equal("key", Assert.IsType<BlockBody.Unknown>(ifElse.Then.Single().Body).TypeName);
        Assert.Empty(ifElse.Otherwise);
    }

    [Fact]
    public void DecodingNeverFailsOnGarbage()
    {
        var blocks = Parse("""[1, "x", null, {"type": 3}, {"type":"comment"}]""");
        Assert.Equal(5, blocks.Count);
        Assert.Equal(4, blocks.Take(4).Count(b => b.Body is BlockBody.Unknown));
        Assert.Equal(new BlockBody.Comment(""), blocks[4].Body);
        var b = Block.FromJson(JsonNode.Parse("""{"type":"delay","ms":5,"id":"nope","onFailure":"retry"}"""));
        Assert.Equal(FailurePolicy.Stop, b.OnFailure);
        Assert.Equal(new BlockBody.Delay(5), b.Body);
        var c = Block.FromJson(JsonNode.Parse("""{"type":"delay","ms":5,"onFailure":"continue"}"""));
        Assert.Equal(FailurePolicy.KeepGoing, c.OnFailure);
        AssertSame(blocks, RoundTrip(blocks));
    }

    /// Imbrication démesurée (fichier piégé) : le fond n'est pas interprété.
    [Fact]
    public void DeepNestingIsBounded()
    {
        var json = """{"type":"delay","ms":1}""";
        // 20 niveaux : au-delà de 31, la lecture JSON de .NET refuse déjà le fichier (64 niveaux d'objets et de listes).
        for (var i = 0; i < 20; i++) json = $$"""{"type":"repeat","count":1,"blocks":[{{json}}]}""";
        var block = Block.FromJson(JsonNode.Parse(json));
        var depth = 0;
        var body = block.Body;
        while (body is BlockBody.RepeatCount r) { body = r.Blocks.Single().Body; depth++; }
        Assert.IsType<BlockBody.Unknown>(body);
        Assert.Equal(Block.MaxParseDepth, depth);
    }

    [Fact]
    public void NameColorKeysAreStrict()
    {
        var red = RgbColor.FromHex("E0453A")!.Value;
        var blocks = new List<Block>
        {
            new(new BlockBody.NameColor("Kick", red)), new(new BlockBody.NameColor(null, red)), new(new BlockBody.NameColor("Voix", null)),
        };
        AssertSame(blocks, RoundTrip(blocks));
        Assert.Equal("E0453A", blocks[0].ToJson()!["color"]!.GetValue<string>());
        Assert.Null(blocks[1].ToJson()!["name"]);
        foreach (var raw in new[]
                 {
                     """{"type":"nameColor","color":"ZZZ"}""", """{"type":"nameColor","name":12}""",
                     """{"type":"nameColor","color":"F2A0D8","fade":"nope"}""", """{"type":"nameColor","color":"F2A0D8","icon":"14-0"}""",
                     """{"type":"nameColor","color":"F2A0D8","icon":7}""",
                 })
            Assert.Equal("nameColor", Assert.IsType<BlockBody.Unknown>(Block.FromJson(JsonNode.Parse(raw)).Body).TypeName);
        Assert.Equal(new BlockBody.NameColor(null, red), Block.FromJson(JsonNode.Parse("""{"type":"nameColor","color":"#e0453a"}""")).Body);
    }

    [Fact]
    public void ClickTargetsAreBounded()
    {
        Assert.False(new ClickTarget.Track(double.PositiveInfinity, 0).IsFinite);
        Assert.False(new ClickTarget.StartCursor(5001, 0).IsFinite);
        Assert.True(new ClickTarget.FlWindowPoint(Corner.TopLeft, 1, 2, null).IsLearnedPosition);
        Assert.False(new ClickTarget.Track(1, 2).IsLearnedPosition);
        // Titre de plugin sans taille : refusé (on ne saurait pas quelle fenêtre).
        Assert.False(new ClickTarget.FlWindowPoint(Corner.TopLeft, 1, 2, null, "Serum").IsFinite);
        Assert.Null(ClickTarget.FromJson(JsonNode.Parse("""{"anchor":"flWindow","corner":"middle"}""")));
        Assert.Null(ClickTarget.FromJson(JsonNode.Parse("""{"anchor":"flWindow","corner":"topLeft","size":[1]}""")));
        Assert.Null(ClickTarget.FromJson(JsonNode.Parse("""{"anchor":"named","label":"1","corner":"topLeft","size":[10,10],"px":1,"py":1}""")));
        Assert.NotNull(ClickTarget.FromJson(JsonNode.Parse("""{"anchor":"named","label":"FILE","corner":"topLeft","size":[10,10],"px":1,"py":1}""")));
    }
}

public class MacKeysTests
{
    [Fact]
    public void MacKeysBecomeTheSameWindowsShortcut()
    {
        // ⌘S (code 1, « s ») → Ctrl+S ; ⇧⌘Z → Ctrl+Maj+Z ; ⌥↑ → Alt+↑ ; R seule (REC) → R.
        Assert.Equal(new KeyCombo(Vk.Letter('S'), Ctrl: true), MacKeys.ToWindows(new KeyRef(new MacKey(1, Command: true), "s")));
        Assert.Equal(new KeyCombo(Vk.Letter('Z'), Ctrl: true, Shift: true), MacKeys.ToWindows(new KeyRef(new MacKey(6, Command: true, Shift: true))));
        Assert.Equal(new KeyCombo(Vk.Up, Alt: true), MacKeys.ToWindows(new KeyRef(new MacKey(126, Option: true))));
        Assert.Equal(new KeyCombo(Vk.Letter('R')), MacKeys.ToWindows(new KeyRef(new MacKey(15))));
        // AZERTY sur le Mac : la touche A est au code de Q (12), le caractère dit « a » : Ctrl+A sur Windows.
        Assert.Equal(new KeyCombo(Vk.Letter('A'), Ctrl: true), MacKeys.ToWindows(new KeyRef(new MacKey(12, Command: true), "a")));
        Assert.Equal(new KeyCombo(Vk.F(5)), MacKeys.ToWindows(new KeyRef(new MacKey(96))));
        Assert.Null(MacKeys.ToWindows(new KeyRef(new MacKey(200))));
    }

    [Fact]
    public void WindowsKeysAreWrittenLikeOnTheMac()
    {
        foreach (var combo in new[]
                 {
                     new KeyCombo(Vk.Letter('S'), Ctrl: true), new KeyCombo(Vk.Up, Alt: true), new KeyCombo(Vk.Delete, Alt: true),
                     new KeyCombo(Vk.Return), new KeyCombo(Vk.F(12), Shift: true), new KeyCombo(Vk.Digit(7)),
                 })
        {
            var mac = MacKeys.FromWindows(combo);
            Assert.NotNull(mac);
            Assert.Equal(combo, MacKeys.ToWindows(mac!));
        }
        Assert.Equal("s", MacKeys.FromWindows(new KeyCombo(Vk.Letter('S'), Ctrl: true))!.Char);
        Assert.True(MacKeys.FromWindows(new KeyCombo(Vk.Letter('S'), Ctrl: true))!.Combo.Command);
    }
}
