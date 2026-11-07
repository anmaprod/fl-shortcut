using FLShortcut.Core;
using Xunit;

namespace FLShortcut.Core.Tests;

/// Raccourcis et macros lancés par un bouton de souris (05/11) : molette cliquée et boutons du côté, comme le Mac
/// (KeyCombo.mouseBase : 202, 203, 204), seulement comme déclencheur.
public sealed class MouseTriggerTests
{
    private static readonly KeyCombo Side = new(Vk.XButton1);
    private static readonly UsKeyLayout Us = UsKeyLayout.Shared;

    [Fact]
    public void MouseButtonsAreTriggersNeverTargets()
    {
        Assert.True(Side.IsMouseButton);
        Assert.True(Side.IsValidKey);
        Assert.False(Side.IsValidTarget, "jamais envoyé à FL");
        Assert.False(new KeyCombo(Vk.Letter('S')).IsMouseButton);
        Assert.Equal("Souris 4", Vk.Name(Vk.XButton1, english: false));
        Assert.Equal("Mouse 5", Vk.Name(Vk.XButton2, english: true));
        Assert.Equal("Wheel", Vk.Name(Vk.MButton, english: true));
    }

    [Fact]
    public void SamePlaceAsOnTheMac()
    {
        Assert.Equal(new KeyCombo(Vk.MButton), PlatformKeys.MacToPc(new MacKeyCombo(202), Us));
        Assert.Equal(new KeyCombo(Vk.XButton1, Ctrl: true), PlatformKeys.MacToPc(new MacKeyCombo(203, Command: true), Us));
        Assert.Equal(new MacKeyCombo(204, Shift: true), PlatformKeys.PcToMac(new KeyCombo(Vk.XButton2, Shift: true), Us));
        Assert.Null(PlatformKeys.MacToPc(new MacKeyCombo(205), Us));                  // 6e bouton : rien sur Windows
    }

    [Fact]
    public void ABareMouseButtonIsAValidShortcutButNotATarget()
    {
        var ctx = new AnalysisContext(ProfilePresets.Toggle, ConflictTable.Default, id => new ActionAvailability.Available());
        var good = Shortcut.Sends(Side, new KeyCombo(Vk.Letter('S'), Ctrl: true));
        var bad = Shortcut.Sends(new KeyCombo(Vk.Letter('K'), Ctrl: true, Shift: true), Side);
        var issues = ShortcutAnalyzer.Analyze(new[] { good, bad }, ctx);
        Assert.DoesNotContain(issues[good.Id], i => i is ShortcutIssue.BareKey || i.IsBlocking);
        Assert.Contains(issues[bad.Id], i => i is ShortcutIssue.InvalidKey);
    }

    [Fact]
    public void TheRouterRunsItOnPressAndSwallowsTheRelease()
    {
        var target = new KeyCombo(Vk.Letter('S'), Ctrl: true);
        var index = new ShortcutIndex(new[] { Shortcut.Sends(Side, target) }, new HashSet<Guid>());
        Assert.True(index.HasMouseTrigger);
        Assert.False(ShortcutIndex.Empty.HasMouseTrigger);
        var cfg = HookConfig.Default with { Index = index };
        var r = new KeyRouter();
        var down = r.Route(new RouterInput(RouterInput.Kinds.Down, Side, TargetIsFl: true), cfg, LinkRoutingView.Offline);
        Assert.True(down.Swallow);
        Assert.Equal(new RouterEffect.Post(target), Assert.Single(down.Effects));
        Assert.True(r.Route(new RouterInput(RouterInput.Kinds.Up, Side, TargetIsFl: true), cfg, LinkRoutingView.Offline).Swallow);
        Assert.False(r.Route(new RouterInput(RouterInput.Kinds.Down, new KeyCombo(Vk.MButton), TargetIsFl: true), cfg,
            LinkRoutingView.Offline).Swallow, "un autre bouton reste à FL");
    }
}
