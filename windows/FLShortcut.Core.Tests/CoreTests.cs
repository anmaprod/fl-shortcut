using FLShortcut.Core;
using Xunit;

namespace FLShortcut.Core.Tests;

public class ProtocolTests
{
    private static readonly byte[] Key = Enumerable.Range(0, 16).Select(i => (byte)i).ToArray();
    private static readonly byte[] Nonce = { 17, 42, 99, 5 };

    [Fact]
    public void TestVector_FromProtocolMd()
    {
        Assert.Equal(new byte[] { 17, 42, 99, 5, 0, 2, 44, 12 }, FrameSigner.Message(Nonce, 300, 12));
        var signer = FrameSigner.Create(Key)!;
        Assert.Equal(new byte[] { 87, 59, 101, 12 }, signer.Mac(Nonce, 300, 12));
    }

    [Fact]
    public void Frame_HasEightCcsInOrder()
    {
        var frame = FrameEncoder.Frame(300, 12, Nonce, FrameSigner.Create(Key)!)!;
        Assert.Equal(Enumerable.Range(104, 8).Select(i => (byte)i), frame.Select(m => m.Cc));
        Assert.Equal(new byte[] { 0, 2, 44, 12, 87, 59, 101, 12 }, frame.Select(m => m.Value));
        Assert.All(frame, m => Assert.Equal(0xBF, m.Bytes[0]));
        Assert.Equal(0xBFu | 104u << 8, frame[0].ShortMessage);
    }

    [Theory]
    [InlineData(0u, 12)]
    [InlineData(1u << 21, 12)]
    [InlineData(1u, 0)]
    [InlineData(1u, 43)]
    public void Frame_RejectsOutOfRange(uint seq, int action) =>
        Assert.Null(FrameEncoder.Frame(seq, action, Nonce, FrameSigner.Create(Key)!));

    [Fact]
    public void Signer_RequiresSixteenBytes()
    {
        Assert.Null(FrameSigner.Create(new byte[15]));
        Assert.Null(FrameSigner.Create(null));
    }

    [Fact]
    public void CapabilityMask_BitLayout()
    {
        // CC 90+k porte les bits 7k…7k+6 ; bit j = action 7k+j+1.
        var m = CapabilityMask.FromCcValues(new byte[] { 1, 1, 0, 0, 0, 4 });
        Assert.True(m.Contains(1));
        Assert.True(m.Contains(8));
        Assert.True(m.Contains(38));
        Assert.False(m.Contains(2));
        Assert.False(m.Contains(0));
        Assert.False(m.Contains(43));
        Assert.Equal(new byte[] { 1, 1, 0, 0, 0, 4 }, m.CcValues());
    }

    private static IncomingEvent? FeedHello(IncomingDecoder d, byte proto = 2)
    {
        IncomingEvent? last = null;
        void Cc(byte cc, byte v) => last = d.Feed(0xBF, cc, v);
        Cc(120, 1);
        Cc(121, 17); Cc(122, 42); Cc(123, 99); Cc(124, 5);
        Cc(125, 45); Cc(126, proto);
        for (byte k = 0; k < 6; k++) Cc((byte)(90 + k), 127);
        Cc(120, 127);
        return last;
    }

    [Fact]
    public void Decoder_ParsesHello()
    {
        var e = Assert.IsType<IncomingEvent.Hello>(FeedHello(new IncomingDecoder()));
        Assert.Equal(Nonce, e.Info.Nonce);
        Assert.Equal(45, e.Info.ApiVersion);
        Assert.True(e.Info.Capabilities.Contains(38));
    }

    [Fact]
    public void Decoder_IncompatibleProtocol() =>
        Assert.IsType<IncomingEvent.Incompatible>(FeedHello(new IncomingDecoder(), proto: 3));

    [Fact]
    public void Decoder_IgnoresIncompleteHelloAndOtherChannels()
    {
        var d = new IncomingDecoder();
        d.Feed(0xBF, 120, 1);
        d.Feed(0xBF, 121, 1);
        Assert.Null(d.Feed(0xBF, 120, 127));
        Assert.Null(d.Feed(0xB0, 118, 0));                     // canal 1
        Assert.IsType<IncomingEvent.Heartbeat>(d.Feed(0xBF, 118, 1));
        Assert.Equal(new IncomingEvent.Window(FlWindow.PianoRoll), d.Feed(0xBF, 117, 3));
        Assert.Equal(new IncomingEvent.Window(FlWindow.Unknown), d.Feed(0xBF, 117, 9));
        Assert.Equal(new IncomingEvent.Ack(12), d.FeedShortMessage(0xBFu | 119u << 8 | 12u << 16));
    }

    [Fact]
    public void Session_SequenceAndAliveness()
    {
        var now = DateTimeOffset.UnixEpoch;
        var s = new LinkSession(() => now);
        var signer = FrameSigner.Create(Key)!;
        Assert.Null(s.NextFrame(1, signer));                   // pas de HELLO
        Assert.True(s.ShouldPing());
        Assert.False(s.ShouldPing());                          // limité

        var hello = Assert.IsType<IncomingEvent.Hello>(FeedHello(new IncomingDecoder()));
        s.Apply(hello);
        Assert.True(s.Alive);
        var f1 = s.NextFrame(12, signer)!;
        var f2 = s.NextFrame(12, signer)!;
        Assert.Equal(new byte[] { 0, 0, 1 }, f1.Take(3).Select(m => m.Value));
        Assert.Equal(new byte[] { 0, 0, 2 }, f2.Take(3).Select(m => m.Value));

        now += TimeSpan.FromSeconds(7);
        Assert.False(s.Alive);
        s.Apply(new IncomingEvent.Heartbeat());
        Assert.True(s.Alive);

        s.Apply(hello);                                        // nouveau HELLO : séquence repart de 1
        Assert.Equal(new byte[] { 0, 0, 1 }, s.NextFrame(1, signer)!.Take(3).Select(m => m.Value));
    }
}

public class ModelTests
{
    [Fact]
    public void Codec_RoundTrip()
    {
        var list = ProfilePreset.Recommended.Shortcuts();
        list.Add(Shortcut.Sends(new KeyCombo(Vk.Letter('Q'), Ctrl: true, Shift: true), new KeyCombo(Vk.Letter('M'), Alt: true)));
        var decoded = ProfileCodec.Decode(ProfileCodec.Encode(list));
        Assert.Equal(list, decoded.Shortcuts);
        Assert.Equal(0, decoded.Skipped);
    }

    [Fact]
    public void Codec_IsTolerant()
    {
        const string json = """
        { "shortcuts": [
          { "trigger": { "vk": 84, "ctrl": true, "shift": true }, "action": "mute" },
          { "trigger": { "vk": 85, "ctrl": true }, "action": "futureAction" },
          { "trigger": { "vk": 86, "ctrl": true }, "kind": "macro" },
          { "trigger": { "vk": 87, "ctrl": true }, "context": "arrangement", "actionID": 1 },
          42,
          { "trigger": { "vk": 999 }, "actionID": 1 }
        ] }
        """;
        var d = ProfileCodec.Decode(json);
        Assert.Equal(1, d.Skipped);
        Assert.Equal(5, d.Shortcuts.Count);
        Assert.Equal(21, d.Shortcuts[0].ActionId);
        Assert.True(d.Shortcuts[0].Enabled);
        Assert.False(d.Shortcuts[1].Enabled);
        Assert.Equal("futureAction", d.Shortcuts[1].UnknownAction);
        Assert.False(d.Shortcuts[2].Enabled);
        Assert.False(d.Shortcuts[3].Enabled);
        Assert.Null(d.Shortcuts[4].Trigger);
    }

    [Fact]
    public void Codec_RejectsGarbage()
    {
        Assert.Throws<FormatException>(() => ProfileCodec.Decode("not json"));
        Assert.Throws<FormatException>(() => ProfileCodec.Decode("\"text\""));
    }

    private static AnalysisContext Ctx() =>
        new(ProfilePresets.Toggle, ConflictTable.Default, id => new ActionAvailability.Available());

    [Fact]
    public void Recommended_HasNoBlockingIssueNorAltGrNorBareKeys()
    {
        var list = ProfilePreset.Recommended.Shortcuts();
        var issues = ShortcutAnalyzer.Analyze(list, Ctx());
        Assert.Empty(ShortcutAnalyzer.Blocked(issues));
        Assert.All(list, s => Assert.False(s.Trigger!.Value.IsAltGr));
        Assert.All(issues.Values, l => Assert.DoesNotContain(l, i => i is ShortcutIssue.BareKey or ShortcutIssue.FlConflict));
    }

    [Fact]
    public void Analyzer_FlagsProblems()
    {
        var dup1 = Shortcut.Action(new KeyCombo(Vk.Letter('J'), Ctrl: true, Shift: true), 1);
        var dup2 = Shortcut.Action(new KeyCombo(Vk.Letter('J'), Ctrl: true, Shift: true), 2);
        var bare = Shortcut.Action(new KeyCombo(Vk.D0), 21);
        var altgr = Shortcut.Action(new KeyCombo(Vk.Letter('E'), Ctrl: true, Alt: true), 1);
        var forbidden = Shortcut.Sends(new KeyCombo(Vk.Letter('K'), Ctrl: true, Shift: true), new KeyCombo(Vk.F(4), Alt: true));
        var toggle = Shortcut.Action(ProfilePresets.Toggle, 1);
        var issues = ShortcutAnalyzer.Analyze(new[] { dup1, dup2, bare, altgr, forbidden, toggle }, Ctx());

        Assert.Empty(issues[dup1].Where(i => i.IsBlocking));
        Assert.Contains(issues[dup2], i => i is ShortcutIssue.Duplicate);
        Assert.Contains(issues[bare], i => i is ShortcutIssue.BareKey);
        Assert.Contains(issues[altgr], i => i is ShortcutIssue.ForbiddenTrigger);
        Assert.Contains(issues[forbidden], i => i is ShortcutIssue.ForbiddenTarget);
        Assert.Contains(issues[toggle], i => i is ShortcutIssue.ReservedToggle);
    }

    [Fact]
    public void Importer_DisablesDangerousTargets()
    {
        var evil = new[]
        {
            Shortcut.Sends(new KeyCombo(Vk.Letter('K'), Ctrl: true, Shift: true), new KeyCombo(Vk.F(4), Alt: true)),
            Shortcut.Sends(new KeyCombo(Vk.Letter('L'), Ctrl: true, Shift: true), new KeyCombo(Vk.Letter('R'), Win: true)),
        };
        var p = ProfileImporter.Prepare(ProfileCodec.Encode(evil));
        Assert.Equal(2, p.Refused.Count);
        Assert.All(p.Shortcuts, s => Assert.False(s.Enabled));
        Assert.DoesNotContain(p.Shortcuts, s => evil.Any(e => e.Id == s.Id));
    }

    [Theory]
    [InlineData("21.0.3", "21.0.3", 0)]
    [InlineData("2024.1.0", "24.1", 0)]
    [InlineData("20.6.2", "20.7", -1)]
    [InlineData("25.2.5.4890", "21.0.3", 1)]
    public void FlVersion_Compares(string a, string b, int sign) =>
        Assert.Equal(sign, Math.Sign(FlVersion.Parse(a)!.CompareTo(FlVersion.Parse(b))));

    [Fact]
    public void Availability_UsesMaskThenVersion()
    {
        var mask = CapabilityMask.FromCcValues(new byte[] { 1, 0, 0, 0, 0, 0 });
        Assert.IsType<ActionAvailability.Available>(AvailabilityResolver.Resolve(1, mask, null));
        Assert.IsType<ActionAvailability.Unavailable>(AvailabilityResolver.Resolve(12, mask, null));
        Assert.IsType<ActionAvailability.Unavailable>(AvailabilityResolver.Resolve(12, null, FlVersion.Parse("21.0.2")));
        Assert.IsType<ActionAvailability.Available>(AvailabilityResolver.Resolve(12, null, FlVersion.Parse("2024.1")));
        Assert.IsType<ActionAvailability.Unavailable>(AvailabilityResolver.Resolve(1, null, FlVersion.Parse("20.6")));
        Assert.IsType<ActionAvailability.Unverified>(AvailabilityResolver.Resolve(1, null, null));
    }

    [Fact]
    public void ScriptTemplate_InjectsOnce()
    {
        var key = Enumerable.Range(0, 16).Select(i => (byte)i).ToArray();
        var output = ScriptTemplate.Inject(key, "# x\nKEY_HEX = \"__FLSHORTCUT_KEY__\"\n");
        Assert.Contains("KEY_HEX = \"000102030405060708090a0b0c0d0e0f\"", output);
        Assert.Throws<FormatException>(() => ScriptTemplate.Inject(key, "KEY_HEX = \"__FLSHORTCUT_KEY__\"\n# __FLSHORTCUT_KEY__\n"));
        Assert.Throws<FormatException>(() => ScriptTemplate.Inject(key, "OTHER = \"__FLSHORTCUT_KEY__\"\n"));
        Assert.Throws<ArgumentException>(() => ScriptTemplate.Inject(new byte[3], "KEY_HEX = \"__FLSHORTCUT_KEY__\"\n"));
    }

    [Fact]
    public void ScriptTemplate_RealScriptHasSinglePlaceholder()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "device_FLShortcut.py");
        var script = File.ReadAllText(path);
        var output = ScriptTemplate.Inject(new byte[16], script);
        Assert.DoesNotContain(ScriptTemplate.Placeholder, output);
    }
}

public class RouterTests
{
    private static readonly KeyCombo Mute = new(Vk.Letter('T'), Ctrl: true, Shift: true);
    private static readonly KeyCombo Send = new(Vk.Letter('Q'), Ctrl: true, Shift: true);
    private static readonly KeyCombo Target = new(Vk.Letter('M'), Alt: true);

    private static (HookConfig, LinkRoutingView) Setup(bool linked = true)
    {
        var list = new List<Shortcut>
        {
            Shortcut.Action(Mute, 21),
            Shortcut.Action(Mute, 23, ShortcutContext.PianoRoll),
            Shortcut.Sends(Send, Target),
            Shortcut.Sends(new KeyCombo(Vk.Letter('W'), Ctrl: true, Shift: true), new KeyCombo(Vk.F(4), Alt: true)),
        };
        var cfg = HookConfig.Default with { Index = new ShortcutIndex(list, new HashSet<Guid>()) };
        var caps = CapabilityMask.FromBits((1UL << 42) - 1);
        var link = new LinkRoutingView(linked, FlWindow.Mixer, caps, CanSign: true);
        return (cfg, link);
    }

    private static RouterInput Down(KeyCombo c, bool repeat = false) =>
        new(RouterInput.Kinds.Down, c, IsRepeat: repeat, TargetIsFl: true);
    private static RouterInput Up(KeyCombo c) => new(RouterInput.Kinds.Up, c, TargetIsFl: true);

    [Fact]
    public void Action_SwallowedOnceAndKeyUpFollows()
    {
        var (cfg, link) = Setup();
        var r = new KeyRouter();
        Assert.Equal(new RouterEffect.SendAction(21), Assert.Single(r.Route(Down(Mute), cfg, link).Effects));
        var rep = r.Route(Down(Mute, repeat: true), cfg, link);
        Assert.True(rep.Swallow);
        Assert.Empty(rep.Effects);                             // pas d'action répétée
        Assert.True(r.Route(Up(Mute), cfg, link).Swallow);
        Assert.False(r.Route(Up(Mute), cfg, link).Swallow);    // keyUp suivant : passe
        Assert.Equal(0, r.OwnedCount);
    }

    [Fact]
    public void ContextSpecificWins()
    {
        var (cfg, link) = Setup();
        var pr = link with { Window = FlWindow.PianoRoll };
        var r = new KeyRouter();
        Assert.Equal(new RouterEffect.SendAction(23), Assert.Single(r.Route(Down(Mute), cfg, pr).Effects));
    }

    [Fact]
    public void LinkInactive_ActionPassesThrough()
    {
        var (cfg, link) = Setup(linked: false);
        var r = new KeyRouter();
        Assert.False(r.Route(Down(Mute), cfg, link).Swallow);
        Assert.False(r.Route(Up(Mute), cfg, link).Swallow);
    }

    [Fact]
    public void Keystroke_RepeatsAndForbiddenNeverPosted()
    {
        var (cfg, link) = Setup();
        var r = new KeyRouter();
        Assert.Equal(new RouterEffect.Post(Target), Assert.Single(r.Route(Down(Send), cfg, link).Effects));
        Assert.Equal(new RouterEffect.Post(Target), Assert.Single(r.Route(Down(Send, repeat: true), cfg, link).Effects));
        var forbidden = r.Route(Down(new KeyCombo(Vk.Letter('W'), Ctrl: true, Shift: true)), cfg, link);
        Assert.False(forbidden.Swallow);
    }

    [Fact]
    public void NotFl_AltGr_Recording_Own_AllPass()
    {
        var (cfg, link) = Setup();
        var r = new KeyRouter();
        Assert.False(r.Route(new RouterInput(RouterInput.Kinds.Down, Mute, TargetIsFl: false), cfg, link).Swallow);
        Assert.False(r.Route(new RouterInput(RouterInput.Kinds.Down, Mute, TargetIsFl: true, AltGr: true), cfg, link).Swallow);
        Assert.False(r.Route(Down(Mute), cfg with { Recording = true }, link).Swallow);
        Assert.False(r.Route(new RouterInput(RouterInput.Kinds.Down, Mute, IsOwn: true, TargetIsFl: true), cfg, link).Swallow);
        Assert.False(r.Route(Down(Mute), cfg with { Enabled = false }, link).Swallow);
    }

    [Fact]
    public void Toggle_WorksEvenWhenPaused_AndReleaseFreesKey()
    {
        var (cfg, link) = Setup();
        var r = new KeyRouter();
        var d = r.Route(Down(ProfilePresets.Toggle), cfg with { Enabled = false }, link);
        Assert.IsType<RouterEffect.ToggleEnabled>(Assert.Single(d.Effects));
        r.Route(Down(Mute), cfg, link);
        r.Release(Mute.Vk);
        Assert.False(r.Route(Up(Mute), cfg, link).Swallow);
        r.Route(Down(Send), cfg, link);
        r.Route(new RouterInput(RouterInput.Kinds.Reset, default), cfg, link);
        Assert.Equal(0, r.OwnedCount);
    }

    [Fact]
    public void ModifierTracker_RepeatAndAltGr()
    {
        var t = new ModifierTracker();
        Assert.False(t.Observe(Vk.LControl, true));
        Assert.False(t.Observe(Vk.LShift, true));
        Assert.False(t.Observe(Vk.Letter('T'), true));
        Assert.True(t.Observe(Vk.Letter('T'), true));          // auto-répétition
        Assert.Equal(Mute, t.Combo(Vk.Letter('T')));
        t.Observe(Vk.RMenu, true);
        Assert.True(t.AltGr);
        t.Clear();
        Assert.False(t.Ctrl);
    }
}

public class ActionTextTests
{
    [Fact]
    public void EveryActionHasItsOwnDescription()
    {
        foreach (var a in FlActions.All)
        {
            var d = a.Detail();
            Assert.False(string.IsNullOrWhiteSpace(d));
            Assert.NotEqual(a.Label, d);          // une phrase qui dit ce que fait l'action, pas le nom répété
        }
    }
}

public class DisplayTextTests
{
    [Fact]
    public void ImportedTextIsCleanedAndClipped()
    {
        Assert.Equal("teleport", DisplayText.Safe("tele‮port"));          // inversion bidi retirée
        Assert.Equal("ab", DisplayText.Safe("a\u0000\n​b"));                // contrôle et largeur nulle retirés
        Assert.Equal("", DisplayText.Safe(null));
        Assert.Equal(new string('x', 40) + "…", DisplayText.Safe(new string('x', 500)));
        Assert.Equal(new string('x', 39) + "…", DisplayText.Safe(new string('x', 39) + "😀😀"));   // paire non coupée
    }
}
