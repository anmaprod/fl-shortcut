// Raccourcis qui lancent une macro de la bibliothèque : même codage que le Mac (macroRef + lien caché), analyse
// (introuvable, invalide, sans macro), index (seulement les macros prêtes) et routeur (une seule fois par appui).
using System.Text.Json.Nodes;
using FLShortcut.Core;
using FLShortcut.Core.Macros;
using Xunit;

namespace FLShortcut.Core.Tests;

public class ShortcutMacroTests
{
    private static readonly KeyCombo Trigger = new(Vk.Letter('R'), Ctrl: true, Shift: true);

    private static MacroProgram Runnable(Guid id) =>
        MacroProgram.Compile(new MacroDoc { Id = id, Name = "Pause", Blocks = new List<Block> { new(new BlockBody.Delay(100)) } });

    private static MacroProgram Broken(Guid id) =>
        MacroProgram.Compile(new MacroDoc { Id = id, Name = "", Blocks = new List<Block>() });

    private static AnalysisContext Ctx(IReadOnlyDictionary<Guid, MacroProgram>? programs) =>
        new(ProfilePresets.Toggle, ConflictTable.Default, _ => new ActionAvailability.Available(), programs);

    [Fact]
    public void CodecWritesTheReferenceAndItsHiddenLink()
    {
        var id = Guid.NewGuid();
        var json = ProfileCodec.Encode(new[] { Shortcut.RunsMacro(Trigger, id) });
        var entry = JsonNode.Parse(json)!["shortcuts"]![0]!;
        Assert.Equal("macro", (string?)entry["kind"]);
        Assert.Equal(id.ToString().ToUpperInvariant(), (string?)entry["macroRef"]);
        Assert.Equal("macroRef:" + id.ToString().ToUpperInvariant(), (string?)entry["unknownAction"]);
        Assert.Null(entry["action"]);

        var back = Assert.Single(ProfileCodec.Decode(json).Shortcuts);
        Assert.Equal(ShortcutKind.Macro, back.Kind);
        Assert.Equal(id, back.MacroRef);
        Assert.Null(back.UnknownAction);                         // le lien caché ne reste pas en mémoire
        Assert.True(back.Enabled);
    }

    /// Profil réécrit sans la clé `macroRef` : le lien caché retrouve la macro ; une clé présente garde la priorité.
    [Fact]
    public void HiddenLinkFindsTheMacroAgain()
    {
        var id = Guid.NewGuid();
        var lost = $$"""{"shortcuts": [{"kind": "macro", "trigger": {"vk": 82, "ctrl": true, "shift": true}, "unknownAction": "macroRef:{{id}}"}]}""";
        Assert.Equal(id, Assert.Single(ProfileCodec.Decode(lost).Shortcuts).MacroRef);

        var other = Guid.NewGuid();
        var both = $$"""{"shortcuts": [{"kind": "macro", "macroRef": "{{other}}", "unknownAction": "macroRef:{{id}}"}]}""";
        var s = Assert.Single(ProfileCodec.Decode(both).Shortcuts);
        Assert.Equal(other, s.MacroRef);
        Assert.Null(s.UnknownAction);

        var nothing = Assert.Single(ProfileCodec.Decode("""{"shortcuts": [{"kind": "macro"}]}""").Shortcuts);
        Assert.Equal(ShortcutKind.Macro, nothing.Kind);
        Assert.Null(nothing.MacroRef);
    }

    /// Un autre type de raccourci ne garde jamais de lien vers une macro.
    [Fact]
    public void OtherKindsDropTheMacroLink()
    {
        var id = Guid.NewGuid();
        var json = $$$"""{"shortcuts": [{"kind": "keystroke", "macroRef": "{{{id}}}", "target": {"vk": 77, "alt": true}}]}""";
        var s = Assert.Single(ProfileCodec.Decode(json).Shortcuts);
        Assert.Equal(ShortcutKind.Keystroke, s.Kind);
        Assert.Null(s.MacroRef);
        var written = ProfileCodec.Encode(new[] { s with { UnknownAction = "macroRef:" + id } });
        Assert.DoesNotContain("macroRef", written);
    }

    [Fact]
    public void AnalyzerReportsMissingOrBrokenMacros()
    {
        var ok = Guid.NewGuid();
        var broken = Guid.NewGuid();
        var programs = new Dictionary<Guid, MacroProgram> { [ok] = Runnable(ok), [broken] = Broken(broken) };
        var good = Shortcut.RunsMacro(Trigger, ok);
        var gone = Shortcut.RunsMacro(new KeyCombo(Vk.Letter('J'), Ctrl: true, Shift: true), Guid.NewGuid());
        var bad = Shortcut.RunsMacro(new KeyCombo(Vk.Letter('K'), Ctrl: true, Shift: true), broken);
        var none = new Shortcut { Trigger = new KeyCombo(Vk.Letter('L'), Ctrl: true, Shift: true), Kind = ShortcutKind.Macro };

        var issues = ShortcutAnalyzer.Analyze(new[] { good, gone, bad, none }, Ctx(programs));
        Assert.Empty(issues[good.Id]);
        Assert.Equal("Macro introuvable dans la bibliothèque (supprimée ?).",
            Assert.IsType<ShortcutIssue.MacroInvalid>(Assert.Single(issues[gone.Id])).Message);
        Assert.Equal("Nom de macro invalide.", Assert.Single(issues[bad.Id]).Message);
        Assert.Equal("Aucune macro configurée.", Assert.Single(issues[none.Id]).Message);
        Assert.Equal(new[] { gone.Id, bad.Id, none.Id }.ToHashSet(), ShortcutAnalyzer.Blocked(issues));

        // Sans bibliothèque chargée : la macro est introuvable, jamais lancée.
        Assert.Contains(ShortcutAnalyzer.Analyze(new[] { good }, Ctx(null))[good.Id], i => i is ShortcutIssue.MacroInvalid);
    }

    [Fact]
    public void IndexHoldsOnlyRunnableMacros()
    {
        var ok = Guid.NewGuid();
        var broken = Guid.NewGuid();
        var programs = new Dictionary<Guid, MacroProgram> { [ok] = Runnable(ok), [broken] = Broken(broken) };
        var list = new[]
        {
            Shortcut.RunsMacro(Trigger, ok),
            Shortcut.RunsMacro(new KeyCombo(Vk.Letter('K'), Ctrl: true, Shift: true), broken),
        };
        var index = new ShortcutIndex(list, new HashSet<Guid>(), programs);
        Assert.Equal(1, index.Count);
        Assert.Same(programs[ok], Assert.IsType<RoutedAction.Macro>(index.Lookup(Trigger, FlWindow.Mixer)!.Action).Program);
        Assert.Equal(0, new ShortcutIndex(list, new HashSet<Guid>()).Count);    // sans programmes : aucune macro
    }

    /// Une macro part une seule fois par appui ; répétitions et relâchement sont avalés, même sans lien MIDI.
    [Fact]
    public void RouterRunsAMacroOncePerPress()
    {
        var id = Guid.NewGuid();
        var programs = new Dictionary<Guid, MacroProgram> { [id] = Runnable(id) };
        var cfg = HookConfig.Default with
        {
            Index = new ShortcutIndex(new[] { Shortcut.RunsMacro(Trigger, id) }, new HashSet<Guid>(), programs),
        };
        var r = new KeyRouter();
        var down = r.Route(new RouterInput(RouterInput.Kinds.Down, Trigger, TargetIsFl: true), cfg, LinkRoutingView.Offline);
        Assert.True(down.Swallow);
        Assert.Same(programs[id], Assert.IsType<RouterEffect.RunMacro>(Assert.Single(down.Effects)).Program);
        var repeat = r.Route(new RouterInput(RouterInput.Kinds.Down, Trigger, IsRepeat: true, TargetIsFl: true), cfg, LinkRoutingView.Offline);
        Assert.True(repeat.Swallow);
        Assert.Empty(repeat.Effects);
        Assert.True(r.Route(new RouterInput(RouterInput.Kinds.Up, Trigger, TargetIsFl: true), cfg, LinkRoutingView.Offline).Swallow);
        Assert.Equal(0, r.OwnedCount);

        // FL pas devant : la touche n'est pas prise.
        Assert.False(r.Route(new RouterInput(RouterInput.Kinds.Down, Trigger), cfg, LinkRoutingView.Offline).Swallow);
    }

    [Fact]
    public void MessagesHaveTheirEnglish()
    {
        Assert.True(Loc.Has("Aucune macro configurée."));
        Assert.True(Loc.Has("Macro introuvable dans la bibliothèque (supprimée ?)."));
    }
}
