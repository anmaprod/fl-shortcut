// Organiser : plan de regroupement, couleurs ou dégradés par famille, application et « Revenir comme avant ».
// Miroir de Tests/FLShortcutTests/OrganizerApplyTests.swift (sans les clips lus dans la fenêtre de FL : Windows ne lit
// jamais l'écran pour la Playlist, elle est rangée dans la copie du projet).
using FLShortcut.Core.Organizer;
using Xunit;

namespace FLShortcut.Core.Tests;

public class OrganizerApplyTests
{
    private static readonly RgbColor Gray = new(10, 10, 10);
    private static RgbColor Style(SoundFamily family) => FamilyStyles.Initial[family].Color;
    private static Dictionary<SoundFamily, FamilyStyle> Initial() => FamilyStyles.Initial.ToDictionary(kv => kv.Key, kv => kv.Value);

    private static (FakeOrganizerLink Link, OrganizerResult Result) Rack(SoundFamily?[] families, Dictionary<int, SoundKind>? kinds = null)
    {
        kinds ??= new Dictionary<int, SoundKind>();
        var link = new FakeOrganizerLink
        {
            Channels = families.Select((f, i) => new ChannelInfo(i, f is null ? ChannelInfo.AutomationType : 2, 0,
                new RgbColor((byte)i, 0, 0), $"Son {i}")).ToList(),
        };
        var items = families.Select((f, i) => (f, i)).Where(x => x.f is not null).Select(x => new OrganizerItem
        {
            Index = x.i, Name = $"Son {x.i}", Family = x.f!.Value, Confidence = 0.9, MixerTrack = 0,
            Color = new RgbColor((byte)x.i, 0, 0), Kind = kinds.TryGetValue(x.i, out var k) ? k : null,
        }).ToList();
        return (link, new OrganizerResult { Channels = link.Channels.ToList(), Items = items });
    }

    private static readonly OrganizerOptions RackOnly = new() { Patterns = false, Mixer = false, Playlist = false, Rename = false };

    private static OrganizerPlan Plan(OrganizerResult result, IReadOnlyDictionary<SoundFamily, FamilyStyle>? styles = null,
        OrganizerOptions? options = null) =>
        OrganizerPlan.Make(result, Organize.FamiliesOf(result), Organize.KindsOf(result), styles ?? Initial(), options ?? new OrganizerOptions());

    private static OrganizerApplier Applier(FakeOrganizerLink link, Func<FlIcon, OrganizerError?>? placeIcon = null) =>
        new(link, link.MoveSelectedUp, link.MoveSelectedLeft, placeIcon, link.DeleteSelected, link.MoveTrackUp, wait: _ => { });

    private static ApplyOutcome Apply(FakeOrganizerLink link, OrganizerResult result, IReadOnlyDictionary<SoundFamily, FamilyStyle>? styles = null,
        OrganizerOptions? options = null) =>
        Applier(link).Apply(Plan(result, styles, options ?? RackOnly), result, styles ?? Initial());

    private static IEnumerable<string> Names(IEnumerable<ChannelInfo> c) => c.Select(x => x.Name);

    [Fact]
    public void PlanStableAndBounded()
    {
        var small = RegroupPlan.Make(new SoundFamily?[] { SoundFamily.Melody, SoundFamily.Drums, null, SoundFamily.Drums, SoundFamily.Bass });
        Assert.Equal(new[] { 0, 4, 1, 3, 2 }, small.Final);
        Assert.Equal(new[] { new Move(4, 3), new Move(4, 1) }, small.Moves);

        ulong seed = 7;
        int Next()
        {
            seed = unchecked(seed * 6_364_136_223_846_793_005UL + 1_442_695_040_888_963_407UL);
            return (int)(seed >> 33);
        }
        var orders = new List<SoundFamily?[]> { Array.Empty<SoundFamily?>(), new SoundFamily?[] { SoundFamily.Fx } };
        foreach (var n in new[] { 2, 5, 17, 40 })
            orders.Add(Enumerable.Range(0, n).Select(_ => { var r = Next() % 7; return r == 6 ? (SoundFamily?)null : SoundFamilies.Order[r]; }).ToArray());
        orders.Add(Enumerable.Range(0, 40).Select(i => (SoundFamily?)SoundFamilies.Order[5 - i * 6 / 40]).ToArray());
        foreach (var order in orders)
        {
            var n = order.Length;
            var plan = RegroupPlan.Make(order);
            var ranks = plan.Final.Select(i => order[i]?.Rank() ?? SoundFamilies.Order.Length).ToList();
            Assert.Equal(ranks.OrderBy(r => r), ranks);
            for (var p = 1; p < plan.Final.Count; p++)
                if (ranks[p] == ranks[p - 1]) Assert.True(plan.Final[p - 1] < plan.Final[p]);
            var simulated = plan.Moves.Aggregate(Enumerable.Range(0, n).ToList(), (a, m) => RegroupPlan.Applying(m, a));
            Assert.Equal(plan.Final, simulated);
            Assert.True(plan.Moves.Sum(m => m.Up) <= n * (n - 1) / 2);
            Assert.All(plan.Moves, m => Assert.True(m.Up >= 1));
        }
    }

    [Fact]
    public void RackGroupsSameKinds()
    {
        var (link, result) = Rack(new SoundFamily?[] { SoundFamily.Drums, SoundFamily.Drums, SoundFamily.Melody, SoundFamily.Drums, SoundFamily.Drums, SoundFamily.Drums },
            new Dictionary<int, SoundKind> { [0] = SoundKind.HiHat, [1] = SoundKind.Kick, [2] = SoundKind.Lead, [3] = SoundKind.Snare, [4] = SoundKind.Kick });
        Assert.Null(Apply(link, result).Error);
        Assert.Equal(new[] { "Son 2", "Son 1", "Son 4", "Son 3", "Son 0", "Son 5" }, Names(link.Channels));
        var families = Organize.FamiliesOf(result);
        families[4] = SoundFamily.Bass;
        var plan = Organize.RackPlan(result.Channels, families, Organize.KindsOf(result));
        Assert.Equal(new[] { 2, 4, 1, 3, 0, 5 }, plan.Final);
        Assert.Null(Organize.KindOf(4, families, Organize.KindsOf(result)));
        Assert.Equal(new[] { 0, 1 }, RegroupPlan.Make(new SoundFamily?[] { SoundFamily.Drums, SoundFamily.Drums }, new SoundKind?[] { SoundKind.Snare }).Final);
    }

    [Fact]
    public void PlanBackRestoresOrder()
    {
        var plan = RegroupPlan.Make(new SoundFamily?[] { SoundFamily.Fx, SoundFamily.Vocals, SoundFamily.Drums, null, SoundFamily.Bass, SoundFamily.Drums, SoundFamily.Melody, SoundFamily.Unsure });
        var back = RegroupPlan.Back(plan.Final);
        Assert.Equal(Enumerable.Range(0, 8), back.Aggregate(plan.Final, (a, m) => RegroupPlan.Applying(m, a)));
        Assert.Empty(RegroupPlan.Back(new[] { 0, 1, 2 }));
        Assert.Equal(new[] { 0, 1 }, RegroupPlan.Applying(new Move(0, 1), new[] { 0, 1 }));
        Assert.Equal(new[] { 0, 1, 2 }, RegroupPlan.Applying(new Move(2, 0), new[] { 0, 1, 2 }));
    }

    [Fact]
    public void FadeColorsPerFamily()
    {
        RgbColor first = new(0xE0, 0x45, 0x3A), last = new(0x3F, 0xA7, 0xE0);
        var fade = new FamilyStyle(first, last);
        Assert.Equal(new[] { "E0453A", "90768D", "3FA7E0" }, fade.Colors(3).Select(c => c.Hex));
        Assert.Equal(new[] { first }, fade.Colors(1));
        Assert.Empty(fade.Colors(0));
        Assert.Equal(new[] { first, first }, new FamilyStyle(first).Colors(2));
        var styles = Initial();
        styles[SoundFamily.Drums] = fade;
        var families = new Dictionary<int, SoundFamily> { [0] = SoundFamily.Melody, [1] = SoundFamily.Drums, [3] = SoundFamily.Drums, [4] = SoundFamily.Drums };
        var colors = Organize.PlannedColors(families, styles, new[] { 1, 3, 4, 0, 2 });
        Assert.Equal("E0453A", colors[1].Hex);
        Assert.Equal("90768D", colors[3].Hex);
        Assert.Equal("3FA7E0", colors[4].Hex);
        Assert.Equal(Style(SoundFamily.Melody), colors[0]);
        Assert.False(colors.ContainsKey(2));
    }

    [Fact]
    public void FamilyStylesSavedAsJson()
    {
        Assert.Equal(FamilyStyles.Initial.OrderBy(kv => kv.Key), FamilyStyles.Decode(null).OrderBy(kv => kv.Key));
        Assert.Equal("E0453A", Style(SoundFamily.Drums).Hex);
        Assert.Equal("8A8F98", Style(SoundFamily.Unsure).Hex);
        var styles = Initial();
        styles[SoundFamily.Melody] = new FamilyStyle(new RgbColor(0x3F, 0xA7, 0xE0), new RgbColor(0x1B, 0x4F, 0x72), FlIcon.FromCode("3-4"));
        var json = FamilyStyles.Encode(styles);
        Assert.Equal(styles.OrderBy(kv => kv.Key), FamilyStyles.Decode(json).OrderBy(kv => kv.Key));
        Assert.Contains("\"melody\":{\"color\":\"3FA7E0\",\"fade\":\"1B4F72\",\"icon\":\"3-4\"}", json);
        Assert.Equal(Style(SoundFamily.Drums), FamilyStyles.Decode("{\"drums\":{\"color\":\"zz\"}}")[SoundFamily.Drums].Color);
        Assert.Equal(FamilyStyles.Initial.OrderBy(kv => kv.Key), FamilyStyles.Decode("pas du json").OrderBy(kv => kv.Key));
    }

    [Fact]
    public void ApplyColorsInChunks()
    {
        var (link, result) = Rack(Enumerable.Repeat((SoundFamily?)SoundFamily.Melody, 70).ToArray());
        Assert.Null(Apply(link, result).Error);
        Assert.Equal(new[] { "colors channels 70", "list" }, link.Log);
        Assert.All(link.Channels, c => Assert.Equal(Style(SoundFamily.Melody), c.Color));
        var pairs = Enumerable.Range(0, 70).Select(i => (i, Gray)).ToList();
        Assert.Equal(new[] { 3 + 64 * 5, 3 + 6 * 5 }, OrganizerPayload.SetColors(ItemKind.Channels, pairs).Select(b => b.Length));
    }

    [Fact]
    public void ApplyDetectsMismatch()
    {
        var (link, result) = Rack(new SoundFamily?[] { SoundFamily.Melody, SoundFamily.Drums, SoundFamily.Bass });
        link.IgnoredColors = new HashSet<int> { 1 };
        var outcome = Apply(link, result);
        Assert.Equal(OrganizerError.Mismatch, outcome.Error);
        Assert.Equal(new[] { 0, 2, 1 }, outcome.Snapshot.Rack?.Arrangement);
        Assert.Equal(new[] { "Son 0", "Son 2", "Son 1" }, Names(link.Channels));
        Assert.Contains("Revenir comme avant", OrganizerError.Mismatch.UserMessage);
    }

    [Fact]
    public void UndoRestoresColorsNamesAndOrder()
    {
        var (link, result) = Rack(new SoundFamily?[] { SoundFamily.Fx, SoundFamily.Vocals, SoundFamily.Drums, null, SoundFamily.Bass, SoundFamily.Drums, SoundFamily.Melody, SoundFamily.Unsure });
        var original = link.Channels.ToList();
        var outcome = Apply(link, result, options: new OrganizerOptions { Patterns = false, Mixer = false, Playlist = false });
        Assert.Null(outcome.Error);
        Assert.Equal(new[] { "Voix", "Mélodie", "Basse", "Drums", "Drums 2", "FX", "Son 7", "Son 3" }, Names(link.Channels));
        Assert.Equal(Style(SoundFamily.Vocals), link.Channels[0].Color);
        Assert.Equal(new RgbColor(3, 0, 0), link.Channels[7].Color);
        var back = Applier(link).Undo(outcome.Snapshot);
        Assert.Null(back.Error);
        Assert.True(back.Snapshot.IsEmpty);
        Assert.Equal(original, link.Channels);
    }

    [Fact]
    public void IconsOnFinalPlaces()
    {
        var (link, result) = Rack(new SoundFamily?[] { SoundFamily.Melody, SoundFamily.Drums, SoundFamily.Bass });
        var styles = Initial();
        styles[SoundFamily.Drums] = styles[SoundFamily.Drums] with { Icon = FlIcon.FromCode("7-4") };
        styles[SoundFamily.Melody] = styles[SoundFamily.Melody] with { Icon = FlIcon.FromCode("6-0") };
        var placed = new List<string>();
        var outcome = Applier(link, icon => { placed.Add($"{link.Selected ?? -1}:{icon.Code}"); return null; })
            .Apply(Plan(result, styles, RackOnly), result, styles);
        Assert.Null(outcome.Error);
        Assert.Equal(new[] { "Son 0", "Son 2", "Son 1" }, Names(link.Channels));
        Assert.Equal(new[] { "0:6-0", "2:7-4" }, placed);
        var (other, otherResult) = Rack(new SoundFamily?[] { SoundFamily.Melody, SoundFamily.Drums, SoundFamily.Bass });
        var missed = Applier(other, _ => OrganizerError.Failed("Icône non posée.")).Apply(Plan(otherResult, styles, RackOnly), otherResult, styles);
        Assert.Equal(OrganizerError.Failed("Icône non posée."), missed.Error);
        Assert.Equal(new[] { 0, 2, 1 }, missed.Snapshot.Rack?.Arrangement);
    }

    /// La page qui n'est plus devant est remise devant et le rangement continue ; arrêt seulement si elle ne revient pas.
    [Fact]
    public void PageThatChangesIsShownAgain()
    {
        var (link, result) = Rack(new SoundFamily?[] { SoundFamily.Drums, SoundFamily.Melody, SoundFamily.Vocals });
        var left = 1;
        var once = new OrganizerApplier(link, count =>
        {
            var done = link.MoveSelectedUp(count);
            if (left > 0) { left--; link.Window = FlWindow.Playlist; }
            return done;
        }, wait: _ => { });
        var outcome = once.Apply(Plan(result, options: RackOnly), result, Initial());
        Assert.Null(outcome.Error);
        Assert.Equal(new[] { "Son 2", "Son 1", "Son 0" }, Names(link.Channels));
        Assert.Equal(2, link.Log.Count(l => l == "show channelRack"));
        Assert.Contains("page remise 1", outcome.Trace);
    }

    [Fact]
    public void StopsWhenPageChanges()
    {
        var (link, result) = Rack(new SoundFamily?[] { SoundFamily.Drums, SoundFamily.Melody, SoundFamily.Vocals });
        var original = link.Channels.ToList();
        var leaving = new OrganizerApplier(link, count =>
        {
            var done = link.MoveSelectedUp(count);
            link.Window = FlWindow.Playlist;
            link.KeptWindow = FlWindow.Playlist;
            return done;
        }, wait: _ => { });
        var outcome = leaving.Apply(Plan(result, options: RackOnly), result, Initial());
        Assert.Equal(OrganizerError.Interrupted, outcome.Error);
        Assert.Equal(new[] { 2, 0, 1 }, outcome.Snapshot.Rack?.Arrangement);
        Assert.Equal(new[] { "Son 2", "Son 0", "Son 1" }, Names(link.Channels));
        link.KeptWindow = null;
        var back = Applier(link).Undo(outcome.Snapshot);
        Assert.Null(back.Error);
        Assert.Equal(original, link.Channels);

        var (half, halfResult) = Rack(new SoundFamily?[] { SoundFamily.Drums, SoundFamily.Drums, SoundFamily.Melody });
        var halfOriginal = half.Channels.ToList();
        var calls = 0;
        var partial = new OrganizerApplier(half, _ => { calls++; return calls == 1 ? half.MoveSelectedUp(1) : 0; }, wait: _ => { })
            .Apply(Plan(halfResult, options: RackOnly), halfResult, Initial());
        Assert.Equal(OrganizerError.Interrupted, partial.Error);
        Assert.Equal(new[] { 0, 2, 1 }, partial.Snapshot.Rack?.Arrangement);
        Assert.Null(Applier(half).Undo(partial.Snapshot).Error);
        Assert.Equal(halfOriginal, half.Channels);
        Assert.Contains("Revenir comme avant", OrganizerError.Interrupted.UserMessage);
    }

    /// Touches perdues : l'ordre relu dans FL remplace l'ordre supposé.
    [Fact]
    public void LostMovesAreReadBackForUndo()
    {
        var (link, result) = Rack(new SoundFamily?[] { SoundFamily.Drums, SoundFamily.Melody, SoundFamily.Vocals });
        var original = link.Channels.ToList();
        var lost = new OrganizerApplier(link, count => count, wait: _ => { });
        var outcome = lost.Apply(Plan(result, options: RackOnly), result, Initial());
        Assert.Equal(OrganizerError.Mismatch, outcome.Error);
        Assert.Equal(new[] { 0, 1, 2 }, outcome.Snapshot.Rack?.Arrangement);
        Assert.Null(Applier(link).Undo(outcome.Snapshot).Error);
        Assert.Equal(original, link.Channels);
        Assert.Equal(new[] { 1, 0 }, OrganizerApplier.Arrangement(new[] { "b", "a" }, new[] { "a", "b" }));
        Assert.Null(OrganizerApplier.Arrangement(new[] { "a", "a" }, new[] { "a", "a" }));
        Assert.Null(OrganizerApplier.Arrangement(new[] { "a", "c" }, new[] { "a", "b" }));
    }

    [Fact]
    public void GroupVerdictAndNumbering()
    {
        var kick = new Verdict(SoundFamily.Drums, SoundKind.Kick);
        var clap = new Verdict(SoundFamily.Drums, SoundKind.Clap);
        Assert.Equal(kick, OrganizerPlan.GroupVerdict(new[] { kick, kick }));
        Assert.Equal(new Verdict(SoundFamily.Drums), OrganizerPlan.GroupVerdict(new[] { kick, clap }));
        Assert.Equal(new Verdict(SoundFamily.Drums), OrganizerPlan.GroupVerdict(new[] { kick, new Verdict(SoundFamily.Drums) }));
        Assert.Equal(new Verdict(SoundFamily.Bass, SoundKind.Bass808), OrganizerPlan.GroupVerdict(new[] { new Verdict(SoundFamily.Unsure), new Verdict(SoundFamily.Bass, SoundKind.Bass808) }));
        Assert.Equal(new Verdict(SoundFamily.Bass), OrganizerPlan.GroupVerdict(new[] { new Verdict(SoundFamily.Bass), kick }));
        Assert.Null(OrganizerPlan.GroupVerdict(Array.Empty<Verdict>()));
        Assert.Null(new Verdict(SoundFamily.Unsure).BaseName);
        Assert.Equal("Drums", new Verdict(SoundFamily.Drums).BaseName);
        Assert.Equal("Open Hat", new Verdict(SoundFamily.Drums, SoundKind.OpenHat).BaseName);
        Assert.Equal(new Dictionary<int, string> { [3] = "Kick", [1] = "Snare", [0] = "Kick 3", [2] = "Kick 4" },
            OrganizerPlan.Numbered(new[] { (3, "Kick"), (1, "Snare"), (0, "Kick"), (2, "Kick") }, new HashSet<string> { "Kick 2" }));
    }

    [Fact]
    public void PatternsNamedByTheirNameOrWhatPlays()
    {
        var (_, result) = Rack(new SoundFamily?[] { SoundFamily.Drums, SoundFamily.Bass, SoundFamily.Melody, SoundFamily.Bass },
            new Dictionary<int, SoundKind> { [0] = SoundKind.Kick, [1] = SoundKind.Bass808 });
        result.Patterns = new[] { "hi hat", "Pattern 2", "Pattern 3", "Intro", "Pattern 5", "Pattern 6", "Drums 1" }
            .Select((n, i) => new PatternInfo(i, Gray, n)).ToList();
        result.PatternSounds = new Dictionary<int, HashSet<int>> { [1] = new() { 0 }, [2] = new() { 0, 1 }, [3] = new() { 1, 3 }, [5] = new() { 1, 3 }, [6] = new() { 0 } };
        var patterns = Plan(result).Patterns;
        Assert.Equal(new Dictionary<int, string> { [0] = "Hi-hat", [1] = "Kick", [2] = "808", [5] = "Basse", [6] = "Kick" }, patterns.Names);
        Assert.Equal(Style(SoundFamily.Drums), patterns.Colors[0]);
        Assert.Equal(Style(SoundFamily.Bass), patterns.Colors[3]);
        Assert.False(patterns.Colors.ContainsKey(4));
        Assert.True(new PatternInfo(4, Gray, " Pattern 5").HasDefaultName);
        Assert.False(new PatternInfo(4, Gray, "Pattern 4").HasDefaultName);
    }

    private static OrganizerResult ByName(List<ChannelInfo> channels) => new()
    {
        Channels = channels,
        Items = channels.Where(c => SoundNames.KindOf(c.Name) is not null).Select(c =>
        {
            var kind = SoundNames.KindOf(c.Name)!.Value;
            return new OrganizerItem { Index = c.Index, Name = c.Name, Family = kind.Family(), Confidence = 0.9, MixerTrack = c.MixerTrack, Color = Gray, Kind = kind, ByName = true };
        }).ToList(),
    };

    private static List<MixerTrackInfo> MixerOf(int last, Func<int, string>? name = null) =>
        Enumerable.Range(0, last + 1).Select(i => new MixerTrackInfo(i, Gray, name?.Invoke(i) ?? (i == 0 ? "Master" : $"Insert {i}"))).ToList();

    [Fact]
    public void MixerFollowsTheRackAndKeepsSendsTogether()
    {
        var result = ByName(new List<ChannelInfo>
        {
            new(0, 2, 1, Gray, "BEAM KICK"), new(1, 2, 2, Gray, "Lead"), new(2, 2, 3, Gray, "@MEH CLAP"),
            new(3, 2, 6, Gray, "ZEBRA 808"), new(4, 2, 6, Gray, "Sub Bass"),
        });
        result.Mixer = MixerOf(8);
        result.Routes = new Dictionary<int, List<int>> { [1] = new() { 5 }, [3] = new() { 5 }, [2] = new(), [6] = new() };
        var noBus = new OrganizerOptions { Buses = false };
        var mixer = Plan(result, options: noBus).Mixer;
        Assert.Equal(new[] { 2, 6, 1, 3, 5, 4 }, mixer.Final);
        Assert.Equal(new Dictionary<int, string> { [2] = "Lead", [6] = "Basse", [1] = "Kick", [3] = "Clap", [5] = "Drums Bus" }, mixer.Names);
        Assert.Equal(new Verdict(SoundFamily.Bass), mixer.Verdicts[6]);
        Assert.Equal(Style(SoundFamily.Drums), mixer.Colors[5]);
        Assert.False(mixer.Colors.ContainsKey(4));
        Assert.Equal(mixer.Final, mixer.Moves.Aggregate(Enumerable.Range(1, 6).ToList(), (a, m) => RegroupPlan.Applying(m, a)));
        result.Mixer[5] = new MixerTrackInfo(5, Gray, "Drum Bus perso");
        Assert.False(Plan(result, options: noBus).Mixer.Names.ContainsKey(5));
        Assert.True(Plan(result, options: new OrganizerOptions { Mixer = false }).Mixer.IsEmpty);
        Assert.Empty(Plan(result, options: new OrganizerOptions { Rename = false, Buses = false }).Mixer.Names);
    }

    [Fact]
    public void MixerAppliedThenUndone()
    {
        var link = new FakeOrganizerLink
        {
            Channels = new List<ChannelInfo> { new(0, 2, 1, Gray, "BEAM KICK"), new(1, 2, 2, Gray, "Vocal Chop") },
            Mixer = MixerOf(4),
        };
        var result = new OrganizerResult
        {
            Channels = link.Channels.ToList(),
            Items = new List<OrganizerItem>
            {
                new() { Index = 0, Name = "BEAM KICK", Family = SoundFamily.Drums, Confidence = 0.9, MixerTrack = 1, Color = Gray, Kind = SoundKind.Kick, ByName = true },
                new() { Index = 1, Name = "Vocal Chop", Family = SoundFamily.Vocals, Confidence = 0.9, MixerTrack = 2, Color = Gray, Kind = SoundKind.Vocal, ByName = true },
            },
            Mixer = link.Mixer.ToList(),
        };
        var originalMixer = link.Mixer.ToList();
        var outcome = Apply(link, result, options: new OrganizerOptions { Rack = false, Patterns = false, Playlist = false, Buses = false });
        Assert.Null(outcome.Error);
        Assert.Equal(new[] { "Master", "Voix", "Kick", "Insert 3", "Insert 4" }, link.Mixer.Select(t => t.Name));
        Assert.Equal(Style(SoundFamily.Vocals), link.Mixer[1].Color);
        Assert.Equal(new[] { 2, 1 }, link.Channels.Select(c => c.MixerTrack));
        Assert.Contains("show mixer", link.Log);
        Assert.Equal(new[] { 2, 1 }, outcome.Snapshot.Mixer?.Arrangement);
        Assert.Null(Applier(link).Undo(outcome.Snapshot).Error);
        Assert.Equal(originalMixer, link.Mixer);
        Assert.Equal(new[] { 1, 2 }, link.Channels.Select(c => c.MixerTrack));
    }

    [Fact]
    public void BusPerFamilyAppliedThenUndone()
    {
        var kinds = new SoundKind?[] { SoundKind.Lead, SoundKind.Lead, SoundKind.Bass, SoundKind.Bass808, SoundKind.Kick, SoundKind.Clap, null };
        var tracks = new[] { 1, 2, 4, 5, 6, 7, 8 };
        var link = new FakeOrganizerLink
        {
            Channels = kinds.Select((_, i) => new ChannelInfo(i, 2, tracks[i], Gray, $"Son {i}")).ToList(),
            Mixer = MixerOf(12, i => i == 0 ? "Master" : i == 3 ? "Melody Bus" : $"Insert {i}"),
            RoutesMap = new Dictionary<int, List<int>> { [1] = new() { 3 }, [2] = new() { 3 }, [3] = new() { 0 }, [4] = new() { 0 }, [5] = new() { 0 }, [6] = new() { 0 }, [7] = new() { 0 }, [8] = new() { 0 } },
        };
        var items = kinds.Select((k, i) => (k, i)).Where(x => x.k is not null).Select(x => new OrganizerItem
        {
            Index = x.i, Name = $"Son {x.i}", Family = x.k!.Value.Family(), Confidence = 0.9, MixerTrack = tracks[x.i], Color = Gray, Kind = x.k,
        }).ToList();
        var result = new OrganizerResult
        {
            Channels = link.Channels.ToList(), Items = items, Mixer = link.Mixer.ToList(),
            Routes = link.RoutesMap.ToDictionary(kv => kv.Key, kv => kv.Value.ToList()), Unused = new HashSet<int> { 6 },
        };
        var mixer = Plan(result).Mixer;
        Assert.Equal(new[] { 1, 2, 3, 4, 9, 5, 6, 7, 10, 8 }, mixer.Final);
        Assert.Equal(new Dictionary<int, SoundFamily> { [3] = SoundFamily.Melody, [9] = SoundFamily.Bass, [10] = SoundFamily.Drums }, mixer.Buses);
        Assert.Equal(new[] { "3:0", "4:9", "5:10", "6:10", "7:10", "9:0", "10:0" },
            mixer.Routes.OrderBy(kv => kv.Key).Select(kv => $"{kv.Key}:{string.Join(",", kv.Value)}"));
        Assert.Equal(new Dictionary<int, string> { [1] = "Lead", [2] = "Lead 2", [4] = "Basse", [9] = "Basse Bus", [5] = "808", [6] = "Kick", [7] = "Clap", [10] = "Drums Bus" }, mixer.Names);
        Assert.Equal(Style(SoundFamily.Drums), mixer.Colors[10]);
        Assert.False(mixer.Colors.ContainsKey(8));

        var originalMixer = link.Mixer.ToList();
        var originalRoutes = link.RoutesMap.ToDictionary(kv => kv.Key, kv => kv.Value.ToList());
        var outcome = Apply(link, result, options: new OrganizerOptions { Rack = false, Patterns = false, Playlist = false, DeleteUnused = false });
        Assert.Null(outcome.Error);
        Assert.Equal(new[] { "Master", "Lead", "Lead 2", "Melody Bus", "Basse", "Basse Bus", "808", "Kick", "Clap", "Drums Bus", "Insert 8", "Insert 11", "Insert 12" },
            link.Mixer.Select(t => t.Name));
        Assert.Equal(new[] { "1:3", "2:3", "3:0", "4:5", "5:0", "6:9", "7:9", "8:9", "9:0", "10:0" },
            link.RoutesMap.Where(kv => kv.Value.Count > 0).OrderBy(kv => kv.Key).Select(kv => $"{kv.Key}:{string.Join(",", kv.Value)}"));
        Assert.Equal(new[] { 1, 2, 4, 6, 7, 8, 10 }, link.Channels.Select(c => c.MixerTrack));
        Assert.Null(Applier(link).Undo(outcome.Snapshot).Error);
        Assert.Equal(originalMixer, link.Mixer);
        Assert.Equal(originalRoutes.OrderBy(kv => kv.Key).Select(kv => $"{kv.Key}:{string.Join(",", kv.Value)}"),
            link.RoutesMap.Where(kv => kv.Value.Count > 0).OrderBy(kv => kv.Key).Select(kv => $"{kv.Key}:{string.Join(",", kv.Value)}"));
        Assert.Equal(tracks, link.Channels.Select(c => c.MixerTrack));
    }

    [Fact]
    public void TracksAlreadySentElsewhereKeepTheirSends()
    {
        var kinds = new[] { SoundKind.Lead, SoundKind.Lead, SoundKind.Kick, SoundKind.Snare };
        var result = new OrganizerResult
        {
            Channels = kinds.Select((_, i) => new ChannelInfo(i, 2, i + 1, Gray, $"Son {i}")).ToList(),
            Items = kinds.Select((k, i) => new OrganizerItem { Index = i, Name = $"Son {i}", Family = k.Family(), Confidence = 0.9, MixerTrack = i + 1, Color = Gray, Kind = k }).ToList(),
            Mixer = MixerOf(10, i => i == 0 ? "Master" : i == 5 ? "Sidechain" : $"Insert {i}"),
            Routes = new Dictionary<int, List<int>> { [1] = new() { 0 }, [2] = new() { 0, 5 }, [3] = new() { 0 }, [4] = new() { 0 }, [5] = new() { 0 } },
        };
        static string R(Dictionary<int, List<int>> routes) => string.Join(" ", routes.OrderBy(kv => kv.Key).Select(kv => $"{kv.Key}:{string.Join(",", kv.Value)}"));
        var mixer = Plan(result).Mixer;
        Assert.Equal(new Dictionary<int, SoundFamily> { [6] = SoundFamily.Melody, [7] = SoundFamily.Drums }, mixer.Buses);
        Assert.Equal("1:6 3:7 4:7 6:0 7:0", R(mixer.Routes));
        Assert.Equal(new[] { 1, 2, 6, 3, 4, 7, 5 }, mixer.Final);
        result.Routes = new Dictionary<int, List<int>> { [1] = new() { 0, 5 }, [2] = new() { 0, 5 }, [3] = new() { 0 }, [4] = new() { 0 }, [5] = new() { 0 } };
        var shared = Plan(result).Mixer;
        Assert.Equal(new Dictionary<int, SoundFamily> { [6] = SoundFamily.Drums }, shared.Buses);
        Assert.Equal("3:6 4:6 6:0", R(shared.Routes));
        Assert.Equal(new[] { 1, 2, 3, 4, 6, 5 }, shared.Final);
    }

    /// Deux sons sans note (leurs pistes du Mixer en noir), une boucle de batterie envoyée au Master.
    private static (FakeOrganizerLink Link, OrganizerResult Result) CleanupProject()
    {
        var black = new RgbColor(0, 0, 0);
        var link = new FakeOrganizerLink
        {
            Channels = new List<ChannelInfo>
            {
                new(0, 2, 1, Gray, "Son 0"), new(1, 2, 2, Gray, "Serum 2"), new(2, 2, 3, Gray, "Son 2"),
                new(3, 0, 4, Gray, "KiCK - BREW"), new(4, ChannelInfo.AudioClipType, 0, Gray, "Son 4"),
            },
            Mixer = Enumerable.Range(0, 13).Select(i => i switch
            {
                0 => new MixerTrackInfo(0, Gray, "Master"),
                2 => new MixerTrackInfo(2, black, "Serum 2"),
                4 => new MixerTrackInfo(4, black, "KiCK - BREW"),
                9 => new MixerTrackInfo(9, black, "Serum 2"),
                _ => new MixerTrackInfo(i, Gray, $"Insert {i}"),
            }).ToList(),
            RoutesMap = new Dictionary<int, List<int>> { [1] = new() { 0 }, [3] = new() { 0 } },
        };
        var kinds = new Dictionary<int, SoundKind> { [0] = SoundKind.Kick, [2] = SoundKind.Lead, [4] = SoundKind.Drums };
        var items = kinds.Keys.OrderBy(k => k).Select(i => new OrganizerItem
        {
            Index = i, Name = link.Channels[i].Name, Family = kinds[i].Family(), Confidence = 0.9, MixerTrack = link.Channels[i].MixerTrack, Color = Gray, Kind = kinds[i],
        }).ToList();
        return (link, new OrganizerResult
        {
            Channels = link.Channels.ToList(), Items = items, Mixer = link.Mixer.ToList(),
            Routes = link.RoutesMap.ToDictionary(kv => kv.Key, kv => kv.Value.ToList()), Unused = new HashSet<int> { 1, 3 },
        });
    }

    [Fact]
    public void UnusedSoundsDeletedAndMasterSoundGetsATrack()
    {
        var (link, result) = CleanupProject();
        var preview = Plan(result);
        Assert.Equal(new[] { 1, 3 }, preview.Deleted);
        Assert.Equal(new Dictionary<int, int> { [4] = 5 }, preview.Mixer.Links);
        Assert.Equal(new[] { 2, 4, 9 }, preview.Mixer.Resets.OrderBy(x => x));
        var outcome = Applier(link).Apply(preview, result, Initial());
        Assert.Null(outcome.Error);
        Assert.Equal(2, outcome.Deleted);
        Assert.Equal(new[] { "list", "select 1,3", "show channelRack" }, link.Log.Take(3));
        Assert.Contains("delete", link.Log);
        Assert.Contains("link 2 5", link.Log);
        Assert.Equal(new[] { "Lead", "Kick", "Drums" }, Names(link.Channels));
        Assert.Equal(new[] { 1, 3, 4 }, link.Channels.Select(c => c.MixerTrack));
        Assert.Equal(new[] { "Master", "Lead", "Mélodie Bus", "Kick", "Drums", "Drums Bus", "", "" }, link.Mixer.Take(8).Select(t => t.Name));
        Assert.Equal(Gray, link.Mixer[6].Color);
        Assert.Equal(Gray, link.Mixer[7].Color);
        Assert.True(link.Mixer[6].HasDefaultName);
        Assert.Equal(("", Gray.Hex), (link.Mixer[9].Name, link.Mixer[9].Color.Hex));
        Assert.Null(Applier(link).Undo(outcome.Snapshot).Error);
        Assert.Equal(new[] { "Son 0", "Son 2", "Son 4" }, Names(link.Channels));
        Assert.Equal(new[] { 1, 3, 0 }, link.Channels.Select(c => c.MixerTrack));
        Assert.Equal(new[] { "Master", "Insert 1", "Serum 2", "Insert 3", "KiCK - BREW" }, link.Mixer.Take(5).Select(t => t.Name));
        Assert.Equal(new RgbColor(0, 0, 0), link.Mixer[2].Color);
        Assert.Equal("Serum 2", link.Mixer[9].Name);
    }

    [Fact]
    public void DeletionRefusedKeepsTheRest()
    {
        var (link, result) = CleanupProject();
        var refusing = new OrganizerApplier(link, link.MoveSelectedUp, link.MoveSelectedLeft, deleteSelected: () => false, wait: _ => { });
        var outcome = refusing.Apply(Plan(result), result, Initial());
        Assert.Null(outcome.Error);
        Assert.Equal((0, 2), (outcome.Deleted, outcome.NotDeleted));
        Assert.Equal(new[] { "Lead", "Kick", "Drums", "Serum 2", "KiCK - BREW" }, Names(link.Channels));
        Assert.Equal(new[] { 3, 4 }, link.UnusedSelection.OrderBy(x => x));
        Assert.Contains(link.Mixer, t => t.Name == "Serum 2");
    }

    [Fact]
    public void RemovingChannels()
    {
        var (_, full) = CleanupProject();
        full.PatternSounds = new Dictionary<int, HashSet<int>> { [0] = new() { 0, 1 }, [1] = new() { 3 } };
        full.TrackSounds = new Dictionary<int, HashSet<int>> { [2] = new() { 2, 3, 4 } };
        var (after, map) = full.Removing(new HashSet<int> { 1, 3 });
        Assert.Equal(new Dictionary<int, int> { [0] = 0, [2] = 1, [4] = 2 }, map);
        Assert.Equal(new[] { 0, 1, 2 }, after.Channels.Select(c => c.Index));
        Assert.Equal(new[] { "Son 0", "Son 2", "Son 4" }, Names(after.Channels));
        Assert.Equal(new[] { 0, 1, 2 }, after.Items.Select(i => i.Index));
        Assert.True(Same.SetMaps(after.PatternSounds, new Dictionary<int, HashSet<int>> { [0] = new() { 0 } }));
        Assert.True(Same.SetMaps(after.TrackSounds, new Dictionary<int, HashSet<int>> { [2] = new() { 1, 2 } }));
        Assert.Empty(after.Unused);
        Assert.Equal(new[] { 2, 4 }, after.Freed.OrderBy(x => x));
    }

    [Fact]
    public void SectionNamesAreKept()
    {
        Assert.True(SoundNames.IsSection("Intro"));
        Assert.True(SoundNames.IsSection("Refrain 2"));
        Assert.True(SoundNames.IsSection("HOOK"));
        Assert.False(SoundNames.IsSection("Kick Intro"));
        Assert.False(SoundNames.IsSection("Serum 2 #3"));
        Assert.False(SoundNames.IsSection("Pattern 3"));
        Assert.False(SoundNames.IsSection("Track 8"));
    }

    [Fact]
    public void BassBefore808()
    {
        var (link, result) = Rack(new SoundFamily?[] { SoundFamily.Drums, SoundFamily.Bass, SoundFamily.Bass, SoundFamily.Melody },
            new Dictionary<int, SoundKind> { [0] = SoundKind.Kick, [1] = SoundKind.Bass808, [2] = SoundKind.Bass });
        Assert.Null(Apply(link, result).Error);
        Assert.Equal(new[] { "Son 3", "Son 2", "Son 1", "Son 0" }, Names(link.Channels));
    }

    private static (FakeOrganizerLink Link, OrganizerResult Result) PlaylistResult((SoundFamily, SoundKind?)[] channels,
        Dictionary<int, HashSet<int>> sounds, int tracks)
    {
        var link = new FakeOrganizerLink
        {
            Channels = channels.Select((_, i) => new ChannelInfo(i, 2, 0, Gray, $"Son {i}")).ToList(),
            Playlist = Enumerable.Range(0, tracks).Select(i => new PlaylistTrackInfo(i, false, Gray, i == 0 ? "Lead" : $"Track {i + 1}")).ToList(),
        };
        var items = channels.Select((c, i) => new OrganizerItem { Index = i, Name = $"Son {i}", Family = c.Item1, Confidence = 0.9, MixerTrack = 0, Color = Gray, Kind = c.Item2 }).ToList();
        return (link, new OrganizerResult { Channels = link.Channels.ToList(), Items = items, Playlist = link.Playlist.ToList(), TrackSounds = sounds });
    }

    [Fact]
    public void PlaylistNames()
    {
        var (_, result) = PlaylistResult(new (SoundFamily, SoundKind?)[] { (SoundFamily.Melody, SoundKind.Lead), (SoundFamily.Drums, SoundKind.Kick), (SoundFamily.Drums, SoundKind.OpenHat), (SoundFamily.Vocals, null), (SoundFamily.Unsure, null) },
            new Dictionary<int, HashSet<int>> { [0] = new() { 0 }, [1] = new() { 1 }, [2] = new() { 1 }, [3] = new() { 2 }, [4] = new() { 4 }, [6] = new() { 3 }, [7] = new() { 1, 2 } }, 8);
        Assert.Equal(new Dictionary<int, string> { [1] = "Kick", [2] = "Kick", [3] = "Open Hat", [6] = "Voix", [7] = "Drums" }, Plan(result).Playlist.Names);
        Assert.Equal(new[] { "Voix", "Mélodie", "Basse", "Drums", "FX" }, SoundFamilies.Order.Select(f => f.TrackName()).OfType<string>());
        result.Playlist[0] = new PlaylistTrackInfo(0, false, Gray, "drums 2");
        Assert.Equal("Lead", Plan(result).Playlist.Names[0]);
    }

    [Fact]
    public void PlaylistColorsNamesAndUndo()
    {
        var (link, result) = PlaylistResult(new (SoundFamily, SoundKind?)[] { (SoundFamily.Melody, null), (SoundFamily.Drums, SoundKind.Snare), (SoundFamily.Bass, null) },
            new Dictionary<int, HashSet<int>> { [0] = new() { 0 }, [1] = new() { 1 }, [2] = new() { 2 } }, 4);
        var original = link.Playlist.ToList();
        var outcome = Apply(link, result, options: new OrganizerOptions { Rack = false, Patterns = false, Mixer = false });
        Assert.Null(outcome.Error);
        Assert.False(outcome.PlaylistUnordered);
        Assert.Equal(new[] { "colors playlist 3", "names playlist 2", "playlist", "show playlist" }, link.Log);
        Assert.Equal(new[] { "Lead", "Basse", "Snare", "Track 4" }, link.Playlist.Select(t => t.Name));
        Assert.Equal(new[] { Style(SoundFamily.Melody), Style(SoundFamily.Bass), Style(SoundFamily.Drums), Gray }, link.Playlist.Select(t => t.Color));
        Assert.Equal(new Dictionary<int, string> { [1] = "Track 2", [2] = "Track 3" }, outcome.Snapshot.Playlist?.Names);
        Assert.Equal(new[] { 0, 2, 1, 3 }, outcome.Snapshot.Playlist?.Arrangement);
        Assert.Null(Applier(link).Undo(outcome.Snapshot).Error);
        Assert.Equal(original, link.Playlist);
        var (other, otherResult) = PlaylistResult(new (SoundFamily, SoundKind?)[] { (SoundFamily.Melody, null), (SoundFamily.Drums, null) },
            new Dictionary<int, HashSet<int>> { [0] = new() { 0 }, [1] = new() { 1 } }, 2);
        other.IgnoredKind = ItemKind.Playlist;
        other.IgnoredColors = new HashSet<int> { 1 };
        Assert.Equal(OrganizerError.Mismatch, Apply(other, otherResult, options: new OrganizerOptions { Rack = false, Patterns = false, Mixer = false }).Error);
    }

    // ---------- Sur le fichier du projet ----------

    /// Le projet de test en petit, analysé sur son fichier ; Kick, mélodie, Snare et 808 classés, « Pad » sans note.
    private static (FakeOrganizerLink Link, OrganizerResult Result) FileProject(FakeDisk disk)
    {
        var names = new[] { "Pad", "Kick", "ZENOLOGY", "Snare", "808" };
        var link = new FakeOrganizerLink
        {
            Channels = names.Select((n, i) => new ChannelInfo(i, 2, 0, Gray, n)).ToList(),
            PatternList = new[] { "Mélodie", "Drums", "Pattern 3", "Vide" }.Select((n, i) => new PatternInfo(i, Gray, n)).ToList(),
            Playlist = Enumerable.Range(0, 12).Select(i => new PlaylistTrackInfo(i, false, Gray, $"Track {i + 1}")).ToList(),
        };
        disk.Link = link;
        var verdicts = new (int, SoundFamily, SoundKind?)[] { (1, SoundFamily.Drums, SoundKind.Kick), (2, SoundFamily.Melody, null), (3, SoundFamily.Drums, SoundKind.Snare), (4, SoundFamily.Bass, SoundKind.Bass808) };
        var items = verdicts.Select(v => new OrganizerItem { Index = v.Item1, Name = names[v.Item1], Family = v.Item2, Confidence = 0.9, MixerTrack = 0, Color = Gray, Kind = v.Item3 }).ToList();
        var file = disk.Files[disk.Original];
        var split = ProjectFile.Splitting(new FlpProject(file), file);
        var result = new OrganizerResult
        {
            Channels = link.Channels.ToList(), Items = items, Patterns = ProjectFile.Patterns(link.PatternList, split.Project),
            PatternSounds = ProjectFile.Sounds(split.Project, new HashSet<int>()).Patterns, Unused = new HashSet<int> { 0 },
            Project = ProjectFile.Snapshot(split.Project, disk.Original, new HashSet<int>(), split.Added),
        };
        return (link, result);
    }

    private static readonly OrganizerOptions FileOptions = new() { Rack = false, Mixer = false, DeleteUnused = false };

    /// FL enregistre le projet, la copie rangée est écrite à côté et FL l'ouvre ; le reste se fait dans la copie, que FL
    /// enregistre ; « Revenir comme avant » rouvre l'original, qui n'a pas bougé.
    [Fact]
    public void PlaylistOrganizedInACopyOfTheProject()
    {
        var disk = new FakeDisk();
        var (link, result) = FileProject(disk);
        var applier = new OrganizerApplier(link, link.MoveSelectedUp, wait: _ => { }, listen: 0, files: disk.Access, marker: "FL Shortcuts 1234");
        var plan = Plan(result, options: FileOptions);
        var layout = plan.Layout!;
        Assert.Empty(plan.Splits);
        Assert.Empty(plan.Playlist.Moves);
        Assert.Equal(5, layout.Count);
        Assert.Equal(new Dictionary<int, int> { [0] = 0, [4] = 0, [2] = 1, [6] = 1, [7] = 2, [1] = 3, [5] = 3, [3] = 4 }, layout.Tracks);

        var outcome = applier.Apply(plan, result, Initial());
        Assert.Null(outcome.Error);
        var copyPath = Path.Combine(Path.GetDirectoryName(disk.Original)!, "Mon son_2.flp");
        Assert.Equal(copyPath, outcome.Copy);
        Assert.Equal(new[] { copyPath }, disk.Opened);
        Assert.Equal(new[] { disk.Original, copyPath }, disk.Saved);
        Assert.Equal(FlpSample.Sample().Encoded(), disk.Files[disk.Original].Encoded());
        var sample = FlpSample.Sample();
        var before = ProjectFile.Splitting(new FlpProject(sample), sample).Project;
        var copy = new FlpProject(disk.Files[copyPath]);
        Assert.Equal(new Dictionary<int, int> { [4] = 1 }, copy.Notes[5]);
        Assert.Equal(before.Clips.Select(c => layout.Tracks[c.Item]), copy.Clips.Select(c => c.Track));
        Assert.Equal(before.Clips.Select(c => c.Source), copy.Clips.Select(c => c.Source));
        Assert.Equal(before.Clips.Select(c => c.Position), copy.Clips.Select(c => c.Position));
        Assert.DoesNotContain(link.PatternList, p => p.Name.StartsWith("FL Shortcuts", StringComparison.Ordinal));
        Assert.Equal(disk.Original, outcome.Snapshot.Original);
        var back = applier.Undo(outcome.Snapshot);
        Assert.Null(back.Error);
        Assert.Equal(disk.Original, disk.Opened[^1]);
        Assert.True(back.Snapshot.IsEmpty);
    }

    /// En ouvrant la copie, FL demande « Invalid project data folder » : la boîte est répondue, puis les sons sont
    /// comptés une fois tous là ; sans réponse possible, le message le dit.
    [Fact]
    public void DataFolderDialogIsAnsweredBeforeCountingSounds()
    {
        var disk = new FakeDisk { AsksDataFolder = true };
        var (link, result) = FileProject(disk);
        var outcome = new OrganizerApplier(link, link.MoveSelectedUp, wait: _ => { }, listen: 0, files: disk.Access)
            .Apply(Plan(result, options: FileOptions), result, Initial());
        Assert.Null(outcome.Error);
        Assert.Equal(1, disk.Answered);
        Assert.Contains("boîte=dossier-données", outcome.Trace);

        var stuck = new FakeDisk { AsksDataFolder = true, AnswersDialog = false };
        var (stuckLink, stuckResult) = FileProject(stuck);
        var blocked = new OrganizerApplier(stuckLink, stuckLink.MoveSelectedUp, wait: _ => { }, listen: 0, files: stuck.Access)
            .Apply(Plan(stuckResult, options: FileOptions), stuckResult, Initial());
        Assert.Equal(OrganizerError.Failed(Loc.F("La copie rangée ouverte dans FL n'a pas les mêmes sons que l'analyse (%lld au lieu de %lld) : rien d'autre n'a été fait. Ton projet n'a pas bougé.", 2, 5)), blocked.Error);
    }

    /// Voix enregistrées : les clips d'une même sorte de voix sur une seule piste, ceux qui se chevauchent juste dessous.
    [Fact]
    public void RecordingsShareOneLinePerKind()
    {
        var clips = new List<FlpSample.ClipSpec> { FlpSample.C(0, 0, 1), FlpSample.C(1, 3, 9), FlpSample.C(0, 6, 3), FlpSample.C(3, 2, 1), FlpSample.C(2, 7, 1), FlpSample.C(4, 9, 9) };
        var project = new FlpProject(FlpSample.Sample(clips: clips));
        var names = new[] { "Pad", "Kick", "untitled_2026-10-15 23-37-42_Insert 5", "Snare", "untitled_2026-10-15 23-50-12_Insert 5" };
        var channels = names.Select((n, i) => new ChannelInfo(i, ChannelInfo.AudioClipType, 0, Gray, n)).ToList();
        var kinds = new Dictionary<int, SoundKind> { [0] = SoundKind.Vocal, [1] = SoundKind.Vocal, [2] = SoundKind.Guitar, [3] = SoundKind.Backing, [4] = SoundKind.Guitar };
        var items = kinds.Keys.OrderBy(k => k).Select(i => new OrganizerItem { Index = i, Name = names[i], Family = kinds[i].Family(), Confidence = 0.9, MixerTrack = 0, Color = Gray, Kind = kinds[i] }).ToList();
        var result = new OrganizerResult
        {
            Channels = channels, Items = items, PatternSounds = ProjectFile.Sounds(project, new HashSet<int>()).Patterns,
            Project = ProjectFile.Snapshot(project, "C:/projets/Voix.flp", new HashSet<int>()),
        };
        var layout = Plan(result, options: new OrganizerOptions { Rack = false, Patterns = false, Mixer = false }).Layout!;
        Assert.Equal(new Dictionary<int, int> { [3] = 0, [0] = 1, [1] = 1, [2] = 2, [4] = 3, [5] = 3 }, layout.Tracks);
        Assert.Equal(4, layout.Count);
        Assert.Equal(new[] { 3 }, layout.Sounds[0]);
        Assert.Equal(new[] { 0, 1 }, layout.Sounds[1].OrderBy(x => x));
        Assert.Equal(new[] { 0, 1 }, layout.Sounds[2].OrderBy(x => x));
        Assert.Equal(new[] { 2, 4 }, layout.Sounds[3].OrderBy(x => x));
    }

    /// Le projet a changé depuis l'analyse, ou FL n'ouvre pas la copie : rien n'est touché dans FL.
    [Fact]
    public void CopyRefusedWhenTheProjectChangedOrDoesNotOpen()
    {
        var disk = new FakeDisk();
        var (link, result) = FileProject(disk);
        var plan = Plan(result, options: FileOptions);
        disk.Files[disk.Original] = FlpSample.Sample(clips: new List<FlpSample.ClipSpec> { FlpSample.P(1, 0, 1) });
        var changed = new OrganizerApplier(link, link.MoveSelectedUp, wait: _ => { }, listen: 0, files: disk.Access).Apply(plan, result, Initial());
        Assert.Equal(OrganizerError.Failed(Loc.T("Ton projet a changé depuis l'analyse : rien n'a été touché. Ferme l'Organiser, puis relance-le.")), changed.Error);
        Assert.Null(changed.Copy);
        Assert.True(changed.Snapshot.IsEmpty);
        Assert.Empty(disk.Opened);
        Assert.Single(disk.Files);
        Assert.DoesNotContain(link.Log, l => l.StartsWith("colors") || l.StartsWith("names"));

        disk.Files[disk.Original] = FlpSample.Sample();
        disk.Loads = false;
        var stuck = new OrganizerApplier(link, link.MoveSelectedUp, wait: _ => { }, listen: 0, files: disk.Access).Apply(plan, result, Initial());
        Assert.Equal(OrganizerError.Failed(Loc.T("FL n'a pas ouvert la copie rangée à temps : elle est à côté de ton projet, ouvre-la dans FL, puis relance l'Organiser. Ton projet n'a pas bougé.")), stuck.Error);
        Assert.Equal(disk.Original, stuck.Snapshot.Original);
        Assert.DoesNotContain(link.Log, l => l.StartsWith("colors") || l.StartsWith("names"));
    }
}
