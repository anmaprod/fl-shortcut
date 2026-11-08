using FLShortcut.Core;
using FLShortcut.Core.Macros;
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
          { "trigger": { "vk": 86, "ctrl": true }, "kind": "teleport" },
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
        Assert.Equal("type:teleport", d.Shortcuts[2].UnknownAction);
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

        Assert.DoesNotContain(issues[dup1.Id], i => i.IsBlocking);
        Assert.Contains(issues[dup2.Id], i => i is ShortcutIssue.Duplicate);
        Assert.Contains(issues[bare.Id], i => i is ShortcutIssue.BareKey);
        Assert.Contains(issues[altgr.Id], i => i is ShortcutIssue.ForbiddenTrigger);
        Assert.Contains(issues[forbidden.Id], i => i is ShortcutIssue.ForbiddenTarget);
        Assert.Contains(issues[toggle.Id], i => i is ShortcutIssue.ReservedToggle);
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

public class LightModeTests
{
    private static readonly KeyCombo Mixer = new(Vk.Digit(4), Ctrl: true, Shift: true);
    private static readonly KeyCombo Mute = new(Vk.Letter('T'), Ctrl: true, Shift: true);

    private static RouterInput Down(KeyCombo c, bool repeat = false) =>
        new(RouterInput.Kinds.Down, c, IsRepeat: repeat, TargetIsFl: true);

    private static HookConfig Light(params Shortcut[] list) => HookConfig.Default with
    {
        Index = new ShortcutIndex(list, new HashSet<Guid>()),
        ActionNatives = LightMode.ActionNatives(light: true),
        AnyContext = true,
    };

    [Fact]
    public void ActionWithNativeKey_SendsFlKeyWithoutMidiLink()
    {
        var r = new KeyRouter();
        var d = r.Route(Down(Mixer), Light(Shortcut.Action(Mixer, 33)), LinkRoutingView.Offline);
        Assert.True(d.Swallow);
        Assert.Equal(new RouterEffect.Post(new KeyCombo(Vk.F(9))), Assert.Single(d.Effects));
        // Répétition : la touche de FL suit (comme une touche « Touche de FL »).
        Assert.Single(r.Route(Down(Mixer, repeat: true), Light(Shortcut.Action(Mixer, 33)), LinkRoutingView.Offline).Effects);
    }

    [Fact]
    public void ActionWithoutNativeKey_PassesThrough()
    {
        var r = new KeyRouter();
        Assert.False(r.Route(Down(Mute), Light(Shortcut.Action(Mute, 21)), LinkRoutingView.Offline).Swallow);
        Assert.IsType<ActionAvailability.Unavailable>(LightMode.Availability(21));
        Assert.IsType<ActionAvailability.Available>(LightMode.Availability(33));
    }

    [Fact]
    public void WindowContextApplies_WhenWindowUnknown()
    {
        var r = new KeyRouter();
        var cfg = Light(Shortcut.Action(Mixer, 3, ShortcutContext.PianoRoll));
        Assert.Equal(new RouterEffect.Post(new KeyCombo(Vk.Letter('R'))),
            Assert.Single(r.Route(Down(Mixer), cfg, LinkRoutingView.Offline).Effects));
    }

    [Fact]
    public void NativeKeys_AreNeverForbiddenTargets()
    {
        foreach (var (_, combo) in LightMode.ActionNatives(light: true))
            Assert.Null(ForbiddenTargets.Reason(combo));
        Assert.Empty(LightMode.ActionNatives(light: false));
    }

    /// Mêmes actions disponibles en mode léger sur Mac et Windows (LightMode.swift), sauf « nouveau pattern » :
    /// ⌘F4 sur Mac, Ctrl+F4 ferme une fenêtre sous Windows.
    [Fact]
    public void SameActionsAsMac()
    {
        var swift = File.ReadAllText(Path.Combine(RepoRoot(), "Sources", "FLShortcut", "LightMode.swift"));
        var macKeys = System.Text.RegularExpressions.Regex.Matches(swift, "case \"([a-z]+)\": return")
            .Select(m => m.Groups[1].Value).ToHashSet();
        macKeys.Remove("newpat");
        var winKeys = FlActions.All.Where(a => LightMode.NativeEquivalent(a.Id) is not null).Select(a => a.Key).ToHashSet();
        Assert.Equal(macKeys.OrderBy(k => k), winKeys.OrderBy(k => k));
    }

    private static string RepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, "Sources"))) dir = dir.Parent;
        return dir?.FullName ?? throw new DirectoryNotFoundException("racine du dépôt");
    }
}

/// FL reconnu à son signataire (WIN-04) : le certificat de FL64.exe dit « Image Line », sa version « Image-Line ».
/// 08/11 (« ça ne repère pas FL Studio… même avec un crack ») : FL reconnu à son programme, signature ou pas.
public class FlRecognitionTests
{
    [Theory]
    [InlineData("FL64.exe")]
    [InlineData("fl64.EXE")]
    [InlineData("FL.exe")]
    [InlineData("FL64 (scaled).exe")]
    public void TheProgramNameIsEnough(string file) => Assert.True(FlRecognition.Accepts(file));

    [Fact]
    public void ARenamedCopyIsRecognizedByItsVersionInfo()
    {
        Assert.True(FlRecognition.Accepts("FL Studio 2024.exe", "FL Studio", null));
        Assert.True(FlRecognition.Accepts("FLStudio.exe", null, "FL Studio 2025"));
        Assert.False(FlRecognition.Accepts("FL Studio 2024.exe", null, null));
        Assert.False(FlRecognition.Accepts("FL Studio Mobile.exe", "FL Studio Mobile", null));
        Assert.False(FlRecognition.Accepts("FLRemote.exe", "FL Studio Remote", null));
        Assert.False(FlRecognition.Accepts("chrome.exe", "FL Studio", null));
        Assert.False(FlRecognition.Accepts(null));
        Assert.True(FlRecognition.MaybeFl("FL64"));
        Assert.False(FlRecognition.MaybeFl("explorer"));
    }
}

public class FlSignerTests
{
    [Theory]
    [InlineData("CN=Image Line, O=Image Line, L=Gent, S=Oost-Vlaanderen, C=BE")]
    [InlineData("CN=Image-Line Software NV, O=Image-Line Software NV, C=BE")]
    [InlineData("cn=imageline")]
    public void Matches_ImageLine_WithSpaceOrHyphen(string subject) => Assert.True(FlSigner.Matches(subject));

    [Theory]
    [InlineData("CN=Microsoft Corporation, O=Microsoft Corporation, C=US")]
    [InlineData("CN=Image, O=Line")]
    [InlineData("")]
    [InlineData(null)]
    public void Rejects_OtherSigners(string? subject) => Assert.False(FlSigner.Matches(subject));
}

/// Aide (miroir de SupportTests du Mac) : règles du message, texte lu par l'équipe, ticket public sans le mail,
/// recherche dans les questions, réponses en étapes, diagnostic sans rien de personnel.
public class SupportTests
{
    private static SupportMessage Message() => new()
    {
        Kind = SupportKind.Probleme, Text = "Ma macro s'arrête au 3e bloc dans le Mixer.", Email = "flshortcuts@exemple.fr",
        Error = "Macro : échec au bloc 3 (Clic)", Diagnostic = "FL Shortcuts 0.2.0 · Windows 11", Reference = "FLS-3F9A2C",
    };

    [Fact]
    public void Rules()
    {
        Assert.Null(SupportRules.Problem(Message()));
        var m = Message();
        m.Text = "Bug";
        Assert.NotNull(SupportRules.Problem(m));
        m = Message();
        m.Email = "";
        Assert.Null(SupportRules.Problem(m));
        m.Email = "pas-un-mail";
        Assert.NotNull(SupportRules.Problem(m));
    }

    [Fact]
    public void PlainText_Subject_Issue()
    {
        Assert.Equal("Référence : FLS-3F9A2C\nGenre : Un problème\nFL Shortcuts 0.2.0\nPour répondre : flshortcuts@exemple.fr\n\n" +
                     "— Message —\nMa macro s'arrête au 3e bloc dans le Mixer.\n\n— Le problème signalé —\nMacro : échec au bloc 3 (Clic)" +
                     "\n\n— État de l'app —\nFL Shortcuts 0.2.0 · Windows 11", SupportRules.PlainText(Message(), "0.2.0"));
        Assert.Equal("[FL Shortcuts] Problème · FLS-3F9A2C · Ma macro s'arrête au 3e bloc dans le Mixer.", SupportRules.Subject(Message()));
        var issue = SupportRules.IssueUri(Message(), "0.2.0");
        Assert.Equal("github.com", issue.Host);
        Assert.DoesNotContain("nina", issue.AbsoluteUri);
        Assert.StartsWith("FLS-", SupportMessage.NewReference());
        Assert.Equal(10, SupportMessage.NewReference().Length);
    }

    [Fact]
    public void FaqSearch()
    {
        List<int> Ids(string q) => HelpContent.Faq.Where(e => e.Matches(q)).Select(e => e.Id).ToList();
        Assert.Equal(HelpContent.Faq.Select(e => e.Id), Ids(""));
        Assert.Contains(7, Ids("pause"));
        Assert.Contains(8, Ids("RECU LE CODE"));
        Assert.Contains(5, Ids("macro apprendre"));
        Assert.Contains(13, Ids("loopmidi"));
        Assert.Contains(16, Ids("lien muet"));
        Assert.Empty(Ids("zzzz"));
        Assert.Equal(HelpContent.Faq.Count, HelpContent.Faq.Select(e => e.Id).Distinct().Count());
    }

    [Fact]
    public void AnswerSteps()
    {
        var parsed = HelpEntry.Steps("Vérifie trois choses. 1. FL est devant. 2. Pas en pause. 3. Le clavier est autorisé.");
        Assert.NotNull(parsed);
        Assert.Equal("Vérifie trois choses.", parsed!.Value.Intro);
        Assert.Equal(new[] { "FL est devant.", "Pas en pause.", "Le clavier est autorisé." }, parsed.Value.Steps);
        Assert.Null(HelpEntry.Steps("Attends 1,5 s puis réessaie avec Windows 11. Rien d'autre."));
        Assert.Null(HelpEntry.Steps("Une seule étape : 1. ouvre FL."));
        Assert.Null(HelpEntry.Steps("2. avant 1. : pas une suite."));
        Assert.Equal(3, HelpEntry.Steps(HelpContent.Faq.First(e => e.Id == 1).Answer)!.Value.Steps.Count);
    }

    [Fact]
    public void Diagnostic_SaysTheStateOnly()
    {
        var facts = new SupportDiagnostic.Facts("0.2.0", "Windows 11 (26100)", FlRunning: true, FlVersion: "2025.1",
            FlUnrecognized: false, FlElevated: true, Paused: false, Light: true, Link: "FL fermé", Shortcuts: 4, Macros: 3,
            LastMacro: "échec — bloc 3", Screens: new[] { "1920×1080" });
        Assert.Equal("FL Shortcuts 0.2.0 · Windows 11 (26100)\nFL Studio : ouvert (2025.1) · lancé en administrateur\n" +
                     "En pause : non\nMode : léger (sans lien MIDI)\nRaccourcis modifiés ou ajoutés : 4 · Macros : 3\n" +
                     "Dernière macro : échec — bloc 3\nÉcrans : 1920×1080", SupportDiagnostic.Text(facts));
        Assert.True(SupportDiagnostic.Report(facts, new string('x', 50_000)).Length <= SupportRules.MaxDiagnostic);
    }
}

/// Serveur (Supabase) : adresse acceptée en https seulement ; message à l'équipe avec ou sans compte (comme le Mac).
public class ServerTests
{
    [Fact]
    public void Config_HttpsOnly()
    {
        Assert.NotNull(ServerConfig.Resolve("https://exemple.supabase.co", "sb_publishable_abc"));
        Assert.Null(ServerConfig.Resolve("http://exemple.supabase.co", "k"));
        Assert.Null(ServerConfig.Resolve("https://user@exemple.supabase.co", "k"));
        Assert.Null(ServerConfig.Resolve("", "k"));
        Assert.Null(ServerConfig.Resolve("https://exemple.supabase.co", ""));
    }

    [Fact]
    public void Support_WithAndWithoutAccount()
    {
        var config = ServerConfig.Resolve("https://exemple.supabase.co", "sb_publishable_abc")!;
        var message = new SupportMessage { Text = "Ma macro s'arrête au 3e bloc dans le Mixer.", Email = "flshortcuts@exemple.fr", Reference = "FLS-3F9A2C" };
        var r = ServerRequests.Support(config, message, "0.2.0", token: null);
        Assert.Equal(HttpMethod.Post, r.Method);
        Assert.Equal("/rest/v1/support_requests", r.RequestUri!.AbsolutePath);
        Assert.Null(r.Headers.Authorization);
        Assert.Equal("sb_publishable_abc", r.Headers.GetValues("apikey").Single());
        var body = System.Text.Json.JsonDocument.Parse(r.Content!.ReadAsStringAsync().Result).RootElement;
        Assert.Equal("probleme", body.GetProperty("kind").GetString());
        Assert.Equal("flshortcuts@exemple.fr", body.GetProperty("email").GetString());
        Assert.Equal("FLS-3F9A2C", body.GetProperty("reference").GetString());
        Assert.Equal("Bearer jeton", ServerRequests.Support(config, message, "0.2.0", "jeton").Headers.Authorization!.ToString());
        message.Text = "Bug";
        Assert.Throws<ArgumentException>(() => ServerRequests.Support(config, message, "0.2.0", null));
    }
}

/// Compte (Windows) : mêmes règles et mêmes requêtes que CommunityClient.swift du Mac.
public class AccountTests
{
    private static readonly ServerConfig Config = ServerConfig.Resolve("https://exemple.supabase.co", "sb_publishable_abc")!;

    private static System.Text.Json.JsonElement Body(HttpRequestMessage r) =>
        System.Text.Json.JsonDocument.Parse(r.Content!.ReadAsStringAsync().Result).RootElement;

    [Fact]
    public void Rules_LikeTheMac()
    {
        Assert.Null(AccountRules.UsernameProblem("flshortcuts"));
        Assert.Null(AccountRules.UsernameProblem("fl.short-cuts_2"));
        Assert.NotNull(AccountRules.UsernameProblem("fl"));
        Assert.NotNull(AccountRules.UsernameProblem("éloïse"));
        Assert.NotNull(AccountRules.UsernameProblem(new string('a', 25)));
        Assert.Equal(new[] { "2 caractères", "une majuscule", "un chiffre", "un symbole" }, AccountRules.PasswordMissing("abcdef"));
        Assert.Equal(new[] { "1 caractère" }, AccountRules.PasswordMissing("Ab1!xyz"));
        Assert.Empty(AccountRules.PasswordMissing("Ab1!wxyz"));
        Assert.Null(AccountRules.PasswordProblem("Ab1!wxyz"));
        Assert.Equal(new[] { false, true, false, true, false }, AccountRules.PasswordChecks("abc1"));
        Assert.All(AccountRules.PasswordChecks("Ab1!wxyz"), Assert.True);
        Assert.NotNull(AccountRules.PasswordProblem("abcdefgh"));
        Assert.Equal("123456", AccountRules.Code(" 123 456 "));
        Assert.Null(AccountRules.Code("12345"));
        Assert.Null(AccountRules.Code("12345a"));
        Assert.Null(AccountRules.Code("١٢٣٤٥٦"));
    }

    [Fact]
    public void Requests_PathsAndHeaders()
    {
        var up = AccountRequests.SignUp(Config, "flshortcuts@exemple.fr", "Ab1!wxyz", "flshortcuts");
        Assert.Equal("/auth/v1/signup", up.RequestUri!.AbsolutePath);
        Assert.Null(up.Headers.Authorization);
        Assert.Equal("flshortcuts", Body(up).GetProperty("data").GetProperty("username").GetString());
        Assert.Throws<ArgumentException>(() => AccountRequests.SignUp(Config, "flshortcuts@exemple.fr", "faible", "flshortcuts"));
        Assert.Throws<ArgumentException>(() => AccountRequests.SignUp(Config, "pas-un-mail", "Ab1!wxyz", "flshortcuts"));

        var signIn = AccountRequests.SignIn(Config, "flshortcuts@exemple.fr", "x");
        Assert.Equal("/auth/v1/token", signIn.RequestUri!.AbsolutePath);
        Assert.Equal("?grant_type=password", signIn.RequestUri.Query);

        var verify = AccountRequests.VerifyCode(Config, "flshortcuts@exemple.fr", "123 456", CodeKind.Recovery);
        Assert.Equal("recovery", Body(verify).GetProperty("type").GetString());
        Assert.Equal("123456", Body(verify).GetProperty("token").GetString());
        Assert.Throws<ArgumentException>(() => AccountRequests.VerifyCode(Config, "flshortcuts@exemple.fr", "12", CodeKind.Signup));

        var session = new AccountSession("jeton", "suite", DateTimeOffset.UnixEpoch.AddHours(1), Guid.Empty, "flshortcuts@exemple.fr", "flshortcuts");
        var name = AccountRequests.SetUsername(Config, "flshortcuts2", session);
        Assert.Equal("/rest/v1/rpc/set_username", name.RequestUri!.AbsolutePath);
        Assert.Equal("flshortcuts2", Body(name).GetProperty("p_name").GetString());
        Assert.Equal("Bearer jeton", name.Headers.Authorization!.ToString());
        Assert.Equal("/rest/v1/rpc/delete_my_account", AccountRequests.DeleteAccount(Config, session).RequestUri!.AbsolutePath);
        Assert.Equal("/rest/v1/rpc/remove_avatar", AccountRequests.RemoveAvatar(Config, session).RequestUri!.AbsolutePath);
        var jpeg = new byte[] { 0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 0xFF, 0xD9 };
        Assert.Equal(Convert.ToBase64String(jpeg), Body(AccountRequests.SetAvatar(Config, jpeg, session)).GetProperty("p_image").GetString());
        Assert.Throws<ArgumentException>(() => AccountRequests.SetAvatar(Config, new byte[AccountRules.MaxPhotoBytes + 1], session));
        var a = Guid.Parse("6f1d2c1e-0000-4000-8000-000000000001");
        Assert.Equal("in.(" + a + ")", AccountRequests.AvatarFilter(new[] { a, a }));
        var photos = AccountRequests.DecodeAvatars("[{\"user_id\":\"" + a + "\",\"image\":\"" + Convert.ToBase64String(jpeg) + "\",\"updated_at\":\"x\"},{\"user_id\":\"" + Guid.Empty + "\",\"image\":\"pas une image\"}]");
        Assert.Equal(jpeg, photos[a]);
        Assert.Single(photos);
        Assert.Equal(HttpMethod.Put, AccountRequests.UpdatePassword(Config, "Ab1!wxyz", session).Method);
        Assert.Equal("suite", Body(AccountRequests.Refresh(Config, session)).GetProperty("refresh_token").GetString());
        Assert.Equal("/rest/v1/rpc/username_available", AccountRequests.UsernameAvailable(Config, "flshortcuts").RequestUri!.AbsolutePath);
    }

    [Fact]
    public void Session_DecodedOrNull()
    {
        var now = DateTimeOffset.UnixEpoch;
        var json = """
            {"access_token":"a","refresh_token":"r","expires_in":3600,
             "user":{"id":"6f1d2c1e-0000-4000-8000-000000000001","email":"flshortcuts@exemple.fr","user_metadata":{"username":"flshortcuts"}}}
            """;
        var s = AccountRequests.DecodeSession(json, now)!;
        Assert.Equal("flshortcuts", s.Username);
        Assert.Equal(now.AddHours(1), s.ExpiresAt);
        Assert.False(s.Expired(now));
        Assert.True(s.Expired(now.AddMinutes(59.5)));
        Assert.Null(AccountRequests.DecodeSession("""{"id":"x","email":"flshortcuts@exemple.fr"}""", now));
        Assert.Null(AccountRequests.DecodeSession("pas du json", now));
    }

    [Fact]
    public void ServerMessage_Translated()
    {
        Assert.Equal("Mail ou mot de passe incorrect.",
            AccountRequests.ServerMessage("""{"error":"invalid_grant","error_description":"Invalid login credentials"}"""));
        Assert.Equal("Code incorrect ou expiré : vérifie-le, ou demande un nouveau code.",
            AccountRequests.ServerMessage("""{"code":403,"error_code":"otp_expired","msg":"Token has expired or is invalid"}"""));
        Assert.Equal("Autre chose", AccountRequests.ServerMessage("""{"msg":"Autre chose"}"""));
        Assert.Equal("Le serveur n'a pas répondu.", AccountRequests.ServerMessage(""));
        Assert.Equal("Session expirée : reconnecte-toi.", AccountRequests.ServerMessage("{}", 401));
        Assert.Equal("Ce pseudo est déjà pris.", AccountRequests.ServerMessage("""{"message":"duplicate key value violates unique constraint \"profiles_username_key\""}""", 409));
        Assert.Equal("Erreur du serveur 500.", AccountRequests.ServerMessage("", 500));
    }

    [Fact]
    public void Photo_CroppedLikeTheMac()
    {
        Assert.Equal((100, 0, 400), AccountRules.CropRect(600, 400));
        Assert.Equal((0, 0, 400), AccountRules.CropRect(600, 400, dx: -1));
        Assert.Equal((200, 0, 400), AccountRules.CropRect(600, 400, dx: 5));
        Assert.Equal((200, 100, 200), AccountRules.CropRect(600, 400, zoom: 2));
        Assert.True(AccountRules.PhotoAcceptable(new byte[] { 0xFF, 0xD8, 0xFF, 0xDB }));
        Assert.Equal("F", AccountRules.Initial("fl.shortcuts"));
        Assert.Equal("?", AccountRules.Initial("._-"));
        Assert.Equal(AccountRules.InitialColorIndex("FLShortcuts"), AccountRules.InitialColorIndex("flshortcuts"));
        // Même calcul que ProfilePhoto.colorIndex du Mac : « ab » → (97 × 31 + 98) % 8 = 3105 % 8 = 1.
        Assert.Equal(1, AccountRules.InitialColorIndex("ab"));
        Assert.False(AccountRules.PhotoAcceptable(new byte[] { 0x89, 0x50, 0x4E, 0x47 }));
    }
}

/// Échange d'une macro (.flsmacro) : le même fichier que le Mac ; positions retirées, chemins relatifs, ids neufs.
public class MacroExchangeTests
{
    private const string Home = @"C:\Users\flshortcuts";

    private static MacroDoc Sample() => new()
    {
        Name = "Voix lead",
        Blocks = new List<FLShortcut.Core.Macros.Block>
        {
            new(new BlockBody.Delay(200)),
            new(new BlockBody.Click(new ClickTarget.FlWindowPoint(Corner.TopLeft, 12, 34, new Size2(940, 652)))),
            new(new BlockBody.ChooseFile(@"C:\Users\flshortcuts\Documents\Voix lead.fst")),
            new(new BlockBody.RepeatCount(2, new List<FLShortcut.Core.Macros.Block> { new(new BlockBody.Click(new ClickTarget.LastClick(1, 2))) })),
        },
    };

    [Fact]
    public void Export_StripsPositionsAndHome()
    {
        var json = System.Text.Json.Nodes.JsonNode.Parse(MacroExchange.Export(Sample(), "0.2.0", Home))!;
        Assert.Equal("flsmacro", json["format"]!.GetValue<string>());
        Assert.Equal(1, json["version"]!.GetValue<int>());
        Assert.Equal("FL Shortcuts 0.2.0 (Windows)", json["exportedBy"]!.GetValue<string>());
        var text = json.ToJsonString();
        Assert.DoesNotContain("flshortcuts\\\\Documents", text);
        Assert.Contains("~/Documents/Voix lead.fst", text);
        // La taille de la fenêtre apprise (940 × 652) ne part pas ; « 940 » seul pouvait se trouver dans un identifiant
        // tiré au hasard (CI du 04/11 : « …9940… »), d'où la paire, jamais dans un identifiant.
        Assert.DoesNotContain("940,652", text);
        Assert.Contains("\"toLearn\"", text);
        Assert.Equal("~/Documents/a.fst", MacroExchange.Relative(@"c:\users\FLSHORTCUTS\Documents\a.fst", Home));
        Assert.Equal(@"D:\Presets\a.fst", MacroExchange.Relative(@"D:\Presets\a.fst", Home));
        Assert.Equal(@"C:\Users\flshortcuts\Documents\a.fst", MacroExchange.Absolute("~/Documents/a.fst", Home));
        Assert.Equal("/Users/flshortcuts/Documents/a.fst", MacroExchange.Absolute("~/Documents/a.fst", "/Users/flshortcuts"));
    }

    [Fact]
    public void Import_FreshIdsEveryClickToShowAndNotes()
    {
        var original = Sample();
        var preview = MacroExchange.PrepareImport(MacroExchange.Export(original, "0.2.0", Home), @"C:\Users\autre");
        var doc = preview.Doc;
        Assert.Equal("Voix lead", doc.Name);
        Assert.Equal("imported", doc.Origin!.Kind);
        Assert.NotEqual(original.Blocks[0].Id, doc.Blocks[0].Id);
        Assert.IsType<ClickTarget.ToLearn>(((BlockBody.Click)doc.Blocks[1].Body).Target);
        Assert.Equal(@"C:\Users\autre\Documents\Voix lead.fst", ((BlockBody.ChooseFile)doc.Blocks[2].Body).Path);
        var inner = ((BlockBody.RepeatCount)doc.Blocks[3].Body).Blocks[0];
        Assert.IsType<ClickTarget.ToLearn>(((BlockBody.Click)inner.Body).Target);
        Assert.Equal(5, preview.Lines.Count);
        Assert.StartsWith("1. ", preview.Lines[0]);
        Assert.StartsWith("    4.1. ", preview.Lines[4]);
        Assert.Contains(preview.Warnings, w => w.Contains("chaque clic"));
        Assert.Contains(MacroExchange.Notes(preview), n => n.Contains("sans raccourci"));
    }

    [Fact]
    public void Import_RefusesWhatIsNotAMacro()
    {
        Assert.Throws<MacroExchange.ImportFailure>(() => MacroExchange.PrepareImport("pas du json"u8.ToArray(), Home));
        Assert.Throws<MacroExchange.ImportFailure>(() => MacroExchange.PrepareImport("""{"format":"autre","macro":{"blocks":[]}}"""u8.ToArray(), Home));
        Assert.Throws<MacroExchange.ImportFailure>(() => MacroExchange.PrepareImport("""{"format":"flsmacro","version":9,"macro":{"blocks":[]}}"""u8.ToArray(), Home));
        Assert.Throws<MacroExchange.ImportFailure>(() => MacroExchange.PrepareImport(new byte[MacroExchange.MaxBytes + 1], Home));
        var unnamed = MacroExchange.PrepareImport("""{"format":"flsmacro","macro":{"name":"","blocks":[{"type":"futur"}]}}"""u8.ToArray(), Home);
        Assert.Equal("Macro importée", unnamed.Doc.Name);
        Assert.Equal(1, unnamed.SensitiveCount);
        Assert.Contains("Bloc inconnu", unnamed.Lines[0]);
    }
}

/// Communauté : mêmes requêtes et mêmes règles que le Mac.
public class CommunityTests
{
    private static readonly ServerConfig Config = ServerConfig.Resolve("https://exemple.supabase.co", "sb_publishable_abc")!;
    private static readonly AccountSession Session = new("jeton", "suite", DateTimeOffset.UnixEpoch.AddHours(1),
        Guid.Parse("6f1d2c1e-0000-4000-8000-000000000001"), "flshortcuts@exemple.fr", "flshortcuts");

    [Fact]
    public void Requests_LikeTheMac()
    {
        var list = CommunityRequests.Shares(Config, Session, "macro", "Voix (lead)*", Session.UserId);
        var query = Uri.UnescapeDataString(list.RequestUri!.Query);
        Assert.Equal("/rest/v1/shares", list.RequestUri.AbsolutePath);
        Assert.Contains("kind=eq.macro", query);
        Assert.Contains("author_id=eq.6f1d2c1e-0000-4000-8000-000000000001", query);
        Assert.Contains("or=(title.ilike.*Voix lead*,notes.ilike.*Voix lead*)", query);
        Assert.Equal("Bearer jeton", list.Headers.Authorization!.ToString());
        var publish = CommunityRequests.Publish(Config, Session, "macro", "  Voix lead  ", "Explication", "{}"u8.ToArray(), "0.2.0");
        var body = System.Text.Json.JsonDocument.Parse(publish.Content!.ReadAsStringAsync().Result).RootElement;
        Assert.Equal("Voix lead", body.GetProperty("title").GetString());
        Assert.Equal("{}", body.GetProperty("payload").GetString());
        Assert.Throws<ArgumentException>(() => CommunityRequests.Publish(Config, Session, "macro", "ab", "", "{}"u8.ToArray(), "0.2.0"));
        Assert.Throws<ArgumentException>(() => CommunityRequests.Report(Config, Session, Guid.Empty, "  x "));
        Assert.Equal(HttpMethod.Delete, CommunityRequests.Delete(Config, Session, Guid.Empty).Method);
        Assert.Equal("", CommunityRules.SearchPattern("&|*()"));
    }

    [Fact]
    public void Decode_SharesAndPayload()
    {
        var shares = CommunityRequests.DecodeShares("""
            [{"id":"6f1d2c1e-0000-4000-8000-000000000002","author_id":"6f1d2c1e-0000-4000-8000-000000000001","kind":"macro",
              "title":"Voix lead","notes":"","app_version":"0.2.0","created_at":"2026-10-16T18:02:11+00:00","author":{"username":"flshortcuts"}},
             {"id":"pas un id","author_id":"x","kind":"macro","title":"?"},
             {"id":"6f1d2c1e-0000-4000-8000-000000000003","author_id":"6f1d2c1e-0000-4000-8000-000000000001","kind":"autre","title":"Autre"}]
            """);
        var share = Assert.Single(shares);
        Assert.True(share.IsMacro);
        Assert.Equal("16/10/2026", share.Day);
        Assert.Equal("Macro · par @flshortcuts · 16/10/2026", share.Byline);
        Assert.Equal("{}"u8.ToArray(), CommunityRequests.DecodePayload("""[{"payload":"{}"}]"""));
        Assert.Null(CommunityRequests.DecodePayload("[]"));
    }
}

/// Traducteur des raccourcis Mac ↔ PC : la même place sur le clavier, ⌘ → Ctrl, aller-retour sans perte.
public class PlatformKeysTests
{
    /// AZERTY : A et Q, Z et W échangés (le reste comme le QWERTY américain).
    private sealed class Azerty : IKeyLayout
    {
        private static ushort Swap(ushort vk) => vk switch
        {
            0x41 => 0x51, 0x51 => 0x41, 0x5A => 0x57, 0x57 => 0x5A, _ => vk,
        };
        public ushort? VkForScan(ushort scan) => UsKeyLayout.Shared.VkForScan(scan) is { } vk ? Swap(vk) : null;
        public ushort? ScanForVk(ushort vk) => UsKeyLayout.Shared.ScanForVk(Swap(vk));
    }

    private static readonly int Action = Enumerable.Range(0, 400).First(i => FlActions.IsKnown(i));
    private static string ActionKey => FlActions.Info(Action)!.Key;

    [Fact]
    public void Keys_KeepTheirPlace()
    {
        var us = UsKeyLayout.Shared;
        Assert.Equal(new KeyCombo(Vk.Letter('S'), Ctrl: true), PlatformKeys.MacToPc(new MacKeyCombo(1, Command: true), us));
        Assert.Equal(new KeyCombo(Vk.F(1), Alt: true, Shift: true), PlatformKeys.MacToPc(new MacKeyCombo(122, Option: true, Shift: true), us));
        Assert.Equal(new KeyCombo(Vk.Letter('S'), Ctrl: true), PlatformKeys.MacToPc(new MacKeyCombo(1, Control: true), us));
        // ⌘ + la touche marquée A sur un Mac AZERTY (code 12, place du Q) : Ctrl + A sur un PC AZERTY.
        Assert.Equal(new KeyCombo(Vk.Letter('A'), Ctrl: true), PlatformKeys.MacToPc(new MacKeyCombo(12, Command: true), new Azerty()));
        Assert.Equal(new MacKeyCombo(12, Command: true), PlatformKeys.PcToMac(new KeyCombo(Vk.Letter('A'), Ctrl: true), new Azerty()));
        Assert.Equal(new MacKeyCombo(1, Command: true), PlatformKeys.PcToMac(new KeyCombo(Vk.Letter('S'), Ctrl: true), us));
        Assert.Equal(new MacKeyCombo(126), PlatformKeys.PcToMac(new KeyCombo(Vk.Up), us));
        Assert.Null(PlatformKeys.PcToMac(new KeyCombo(Vk.Letter('S'), Win: true), us));
        Assert.Null(PlatformKeys.MacToPc(new MacKeyCombo(200, Command: true), us));
    }

    private string MacJson() => $$$"""
        {"version":2,"remaps":[
          {"id":"6F1D2C1E-0000-4000-8000-000000000001","enabled":true,"context":"everywhere","kind":"flAction",
           "action":"{{{ActionKey}}}","actionID":{{{Action}}},"trigger":{"keyCode":1,"command":true,"option":false,"control":false,"shift":false}},
          {"id":"6F1D2C1E-0000-4000-8000-000000000002","enabled":true,"context":"everywhere","kind":"flAction","page":"mixer",
           "action":"{{{ActionKey}}}","actionID":{{{Action}}},"trigger":{"keyCode":1,"command":false,"option":false,"control":true,"shift":false}},
          {"id":"6F1D2C1E-0000-4000-8000-000000000003","enabled":true,"context":"mixer","kind":"keystroke",
           "trigger":{"keyCode":200,"command":true},"target":{"keyCode":35,"command":false}}
        ]}
        """;

    [Fact]
    public void FromMac_TranslatesAndTurnsOffWhatCannotWork()
    {
        Assert.True(MacProfile.IsMacProfile(MacJson()));
        Assert.False(MacProfile.IsMacProfile(ProfileCodec.Encode(new[] { Shortcut.Action(new KeyCombo(Vk.Letter('S'), Ctrl: true), Action) })));
        var t = MacProfile.FromMac(MacJson(), UsKeyLayout.Shared);
        Assert.Equal(3, t.Shortcuts.Count);
        Assert.Equal(new KeyCombo(Vk.Letter('S'), Ctrl: true), t.Shortcuts[0].Trigger);
        Assert.True(t.Shortcuts[0].Enabled);
        Assert.False(t.Shortcuts[1].Enabled);                // ⌃S : la même touche que ⌘S sur le PC
        Assert.False(t.Shortcuts[2].Enabled);                // touche sans équivalent
        Assert.Equal(1, t.Duplicates);
        Assert.Equal(1, t.Untranslatable);
        Assert.Equal(new KeyCombo(Vk.Letter('P')), t.Shortcuts[2].Target);
        // Le format de Windows garde l'écriture du Mac.
        var again = ProfileCodec.Decode(ProfileCodec.Encode(t.Shortcuts)).Shortcuts;
        Assert.NotNull(again[1].Mac);
    }

    [Fact]
    public void ToMac_RoundTripWithoutLoss()
    {
        var t = MacProfile.FromMac(MacJson(), UsKeyLayout.Shared);
        var back = System.Text.Json.Nodes.JsonNode.Parse(MacProfile.ToMac(t.Shortcuts, UsKeyLayout.Shared))!["remaps"]!.AsArray();
        var original = System.Text.Json.Nodes.JsonNode.Parse(MacJson())!["remaps"]!.AsArray();
        for (var i = 0; i < original.Count; i++)
            Assert.True(System.Text.Json.Nodes.JsonNode.DeepEquals(original[i], back[i]), $"raccourci {i + 1} changé : {back[i]}");
        // Changé sur le PC : traduit (Ctrl → ⌘), la page du Mac gardée.
        var changed = t.Shortcuts.ToList();
        changed[1] = changed[1] with { Trigger = new KeyCombo(Vk.Letter('D'), Ctrl: true, Shift: true), Enabled = true };
        var out1 = System.Text.Json.Nodes.JsonNode.Parse(MacProfile.ToMac(changed, UsKeyLayout.Shared))!["remaps"]![1]!;
        Assert.Equal(2, out1["trigger"]!["keyCode"]!.GetValue<int>());
        Assert.True(out1["trigger"]!["command"]!.GetValue<bool>());
        Assert.True(out1["trigger"]!["shift"]!.GetValue<bool>());
        Assert.Equal("mixer", out1["page"]!.GetValue<string>());
        Assert.Null(out1["flsPcOff"]);
        // Créé sur le PC : écrit comme un raccourci du Mac.
        var made = MacProfile.ToMac(new[] { Shortcut.Action(new KeyCombo(Vk.F(5), Alt: true), Action) }, UsKeyLayout.Shared);
        var macBack = MacProfile.FromMac(made, UsKeyLayout.Shared).Shortcuts.Single();
        Assert.Equal(new KeyCombo(Vk.F(5), Alt: true), macBack.Trigger);
        Assert.Equal(Action, macBack.ActionId);
    }

    [Fact]
    public void Import_AcceptsAMacProfile()
    {
        var preview = ProfileImporter.Prepare(MacJson(), UsKeyLayout.Shared);
        Assert.Equal(3, preview.Shortcuts.Count);
        Assert.Equal(2, preview.Disabled);
    }
}

/// Sauvegarde en ligne commune au Mac et au PC : mêmes règles que le Mac, contenu au format du Mac.
public class BackupTests
{
    private static readonly int Action = Enumerable.Range(0, 400).First(i => FlActions.IsKnown(i));

    [Fact]
    public void Rules_LikeTheMac()
    {
        Assert.Equal(BackupDecision.Upload, BackupRules.Decide(null, false, false, null, false));
        Assert.Equal(BackupDecision.InSync, BackupRules.Decide(3, true, false, null, true));
        Assert.Equal(BackupDecision.Upload, BackupRules.Decide(3, false, false, 3, true));
        Assert.Equal(BackupDecision.Restore, BackupRules.Decide(4, false, false, 3, false));
        Assert.Equal(BackupDecision.Ask, BackupRules.Decide(4, false, false, 3, true));
        Assert.Equal(BackupDecision.Restore, BackupRules.Decide(4, false, true, null, false));
        Assert.Equal(BackupDecision.Ask, BackupRules.Decide(4, false, false, null, false));
        Assert.Equal("12 raccourcis · 1 macro", BackupRules.Summary(12, 1));
    }

    [Fact]
    public void RecentColors_TravelInsideTheProfile_LikeTheMac()
    {
        // 08/11 : les 10 couleurs récentes partent avec le compte, dans le profil ; les versions d'avant les ignorent.
        var shortcuts = new List<Shortcut> { Shortcut.Action(new KeyCombo(Vk.Letter('S'), Ctrl: true), Action) };
        var content = BackupCodec.Of(shortcuts, new List<MacroDoc>(), UsKeyLayout.Shared, new[] { "E0453A", "nope", "3a9be0" });
        Assert.Equal(new[] { "E0453A", "3A9BE0" }, BackupCodec.Colors(content.Profile));
        Assert.Single(BackupCodec.Decode(content, UsKeyLayout.Shared).Shortcuts);           // le profil se relit comme avant
        Assert.Empty(BackupCodec.Colors(BackupCodec.Of(shortcuts, new List<MacroDoc>(), UsKeyLayout.Shared).Profile));
        Assert.False(BackupCodec.Same(content, shortcuts, new List<MacroDoc>(), UsKeyLayout.Shared), "une couleur changée est à envoyer");
        Assert.True(BackupCodec.Same(content, shortcuts, new List<MacroDoc>(), UsKeyLayout.Shared, new[] { "E0453A", "3A9BE0" }));
        // Comme FL : la dernière en tête, une déjà là remonte, une 11e chasse la plus ancienne.
        var list = Enumerable.Range(0, 10).Select(i => $"0000{i:X2}").ToList();
        Assert.Equal("000005", RecentColorList.Remember(list, "000005")[0]);
        var eleven = RecentColorList.Remember(list, "FFFFFF");
        Assert.Equal(10, eleven.Count);
        Assert.Equal("FFFFFF", eleven[0]);
        Assert.DoesNotContain("000009", eleven);
    }

    [Fact]
    public void Content_RoundTripAndSame()
    {
        var shortcuts = new List<Shortcut> { Shortcut.Action(new KeyCombo(Vk.Letter('S'), Ctrl: true), Action) };
        var macros = new List<MacroDoc> { new() { Name = "Voix lead", Blocks = new() { new(new BlockBody.Delay(200)) } } };
        var content = BackupCodec.Of(shortcuts, macros, UsKeyLayout.Shared);
        Assert.True(MacProfile.IsMacProfile(content.Profile));
        var (back, backMacros) = BackupCodec.Decode(content, UsKeyLayout.Shared);
        Assert.Equal(new KeyCombo(Vk.Letter('S'), Ctrl: true), back.Single().Trigger);
        Assert.Equal("Voix lead", backMacros.Single().Name);
        Assert.True(BackupCodec.Same(content, back, backMacros, UsKeyLayout.Shared));
        Assert.True(BackupCodec.Same(content, shortcuts, macros, UsKeyLayout.Shared));
        var changed = new List<Shortcut> { shortcuts[0] with { Trigger = new KeyCombo(Vk.Letter('D'), Ctrl: true) } };
        Assert.False(BackupCodec.Same(content, changed, macros, UsKeyLayout.Shared));
        Assert.False(BackupCodec.Same(content, shortcuts, new List<MacroDoc>(), UsKeyLayout.Shared));
        Assert.Equal("1 raccourci · 1 macro", BackupCodec.Summary(content, UsKeyLayout.Shared));
        Assert.Throws<BackupFailure>(() => BackupCodec.Decode(new BackupContent("pas du json", content.Macros), UsKeyLayout.Shared));
        Assert.Throws<BackupFailure>(() => BackupCodec.Decode(new BackupContent("""{"version":9,"remaps":[]}""", content.Macros), UsKeyLayout.Shared));
        Assert.True(BackupCodec.Untouched(ProfilePreset.Recommended.Shortcuts(), 0));
        Assert.False(BackupCodec.Untouched(shortcuts, 0));
        Assert.False(BackupCodec.Untouched(ProfilePreset.Recommended.Shortcuts(), 1));
    }

    [Fact]
    public void Requests_AndAnswers()
    {
        var config = ServerConfig.Resolve("https://exemple.supabase.co", "sb_publishable_abc")!;
        var session = new AccountSession("jeton", "suite", DateTimeOffset.UnixEpoch.AddHours(1), Guid.Empty, "flshortcuts@exemple.fr", "flshortcuts");
        var save = BackupRequests.Save(config, session, new BackupContent("{}", "{}"), 7, false, "0.2.0");
        var body = System.Text.Json.JsonDocument.Parse(save.Content!.ReadAsStringAsync().Result).RootElement;
        Assert.Equal("/rest/v1/rpc/save_backup", save.RequestUri!.AbsolutePath);
        Assert.Equal(7, body.GetProperty("p_base").GetInt64());
        Assert.False(body.GetProperty("p_force").GetBoolean());
        Assert.Equal("Bearer jeton", save.Headers.Authorization!.ToString());
        Assert.Null(BackupRequests.DecodeRevision("[]"));
        Assert.Equal((7L, "2026-11-04T10:12:00+00:00"), BackupRequests.DecodeRevision("""[{"revision":7,"updated_at":"2026-11-04T10:12:00+00:00"}]"""));
        Assert.Equal(7, BackupRequests.DecodeBackup("""[{"profile":"{}","macros":"{}","revision":7}]""")!.Revision);
        Assert.Equal(8, BackupRequests.DecodeSaved("8"));
        Assert.True(BackupRequests.IsConflict("""{"message":"Sauvegarde plus récente sur le serveur"}"""));
        Assert.False(BackupRequests.IsConflict("""{"message":"autre"}"""));
    }
}
