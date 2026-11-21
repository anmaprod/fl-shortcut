using FLShortcut.Core;
using FLShortcut.Core.Organizer;
using Xunit;
using static FLShortcut.Core.Tests.FlpSample;

namespace FLShortcut.Core.Tests;

/// 13/11 : le Channel rack rangé dans la copie (`FlpChannelOrder.Reordering`) et le projet suivi
/// (`OrganizerResult.Reordering`). Miroir de Tests/FLShortcutTests/FLPChannelOrderTests.swift.
public class FlpChannelOrderTests
{
    private static readonly string[] Names = { "Pad", "Kick", "ZENOLOGY", "Snare", "808" };

    private static bool SameEvents(FlpFile a, FlpFile b) =>
        a.Events.Count == b.Events.Count && a.Events.Zip(b.Events).All(p => p.First.Id == p.Second.Id
            && p.First.Bytes.SequenceEqual(p.Second.Bytes));

    [Fact]
    public void ChannelsMoveWithTheirNotesAndClips()
    {
        var file = Sample(flOrder: true);
        var before = new FlpProject(file);
        var order = new[] { 3, 4, 1, 0, 2 };
        var moved = FlpChannelOrder.Reordering(file, order);
        Assert.NotNull(moved);
        Assert.Equal(file.Events.Count, moved!.Events.Count);
        var after = new FlpProject(moved);
        Assert.Equal(Enumerable.Range(0, 5), after.Channels.Select(c => c.Iid));
        Assert.Equal(order.Select(i => Names[i]), after.Channels.Select(c => c.Name));
        Assert.Equal(order.Select(i => before.Channels[i].Type), after.Channels.Select(c => c.Type));
        Assert.Equal(before.PatternNames, after.PatternNames);
        // Notes : Snare (3) → place 0, 808 (4) → 1, Kick (1) → 2, ZENOLOGY (2) → 4.
        Assert.Equal(new Dictionary<int, int> { [4] = 3 }, after.Notes[1]);
        Assert.Equal(new Dictionary<int, int> { [0] = 1, [1] = 1 }, after.Notes[2]);
        Assert.Equal(new Dictionary<int, int> { [2] = 1 }, after.Notes[3]);
        // Le clip du canal 1 (Kick) suit le Kick (place 2) ; les clips des patterns ne bougent pas.
        Assert.Single(before.Clips, c => c.Source == ClipSource.Channel(1));
        Assert.Equal(before.Clips.Select(c => c.Source == ClipSource.Channel(1) ? ClipSource.Channel(2) : c.Source),
            after.Clips.Select(c => c.Source));
        Assert.Equal(before.Clips.Select(c => c.Track), after.Clips.Select(c => c.Track));
    }

    [Fact]
    public void SameOrderGivesTheSameFile()
    {
        var file = Sample(flOrder: true);
        Assert.True(SameEvents(file, FlpChannelOrder.Reordering(file, new[] { 0, 1, 2, 3, 4 })!));
        var once = FlpChannelOrder.Reordering(file, new[] { 1, 0, 2, 3, 4 })!;
        Assert.False(SameEvents(file, once));
        Assert.True(SameEvents(file, FlpChannelOrder.Reordering(once, new[] { 1, 0, 2, 3, 4 })!));
    }

    [Fact]
    public void RefusedWhenAChannelCouldBePointedAtOtherwise()
    {
        var order = new[] { 1, 0, 2, 3, 4 };
        Assert.Null(FlpChannelOrder.Reordering(Sample(types: new() { [2] = 3 }, flOrder: true), order));
        Assert.Null(FlpChannelOrder.Reordering(Sample(types: new() { [4] = 5 }, flOrder: true), order));
        foreach (var id in new byte[] { 223, 227, 234 })
        {
            var file = Sample(flOrder: true);
            file.Events.Insert(3, new FlpEvent(id, new byte[] { 0, 0, 0, 0 }));
            Assert.Null(FlpChannelOrder.Reordering(file, order));
        }
        Assert.Null(FlpChannelOrder.Reordering(Sample(), order));
        var same = Sample(flOrder: true);
        Assert.Null(FlpChannelOrder.Reordering(same, new[] { 0, 0, 2, 3, 4 }));
        Assert.Null(FlpChannelOrder.Reordering(same, new[] { 1, 0, 2, 3 }));
        var renumbered = Sample(flOrder: true);
        var at = Enumerable.Range(0, renumbered.Events.Count - 1).First(i => renumbered.Events[i].Id == 64
            && renumbered.Events[i + 1].Id == 21 && renumbered.Events[i].Value == 1);
        renumbered.Events[at] = new FlpEvent(64, FlpBytes.Le(7, 2));
        Assert.Null(FlpChannelOrder.Reordering(renumbered, order));
    }

    [Fact]
    public void ResultFollowsTheNewPlaces()
    {
        var gray = new RgbColor(0x40, 0x40, 0x40);
        var result = new OrganizerResult
        {
            Channels = Names.Select((n, i) => new ChannelInfo(i, 2, i + 1, gray, n)).ToList(),
            Items = new List<OrganizerItem>
            {
                new() { Index = 2, Name = "ZENOLOGY", Family = SoundFamily.Melody, Confidence = 1, MixerTrack = 3, Color = gray },
            },
            PatternSounds = new() { [0] = new() { 2 }, [1] = new() { 3, 4 } },
            TrackSounds = new() { [5] = new() { 1 } },
            Unused = new() { 0 },
            SoundAt = new() { [2] = 1.5 },
            Freed = new() { 9 },
        };
        var moved = result.Reordering(new[] { 3, 1, 4, 0, 2 });
        Assert.NotNull(moved);
        var (now, map) = moved!.Value;
        Assert.Equal(new Dictionary<int, int> { [3] = 0, [1] = 1, [4] = 2, [0] = 3, [2] = 4 }, map);
        Assert.Equal(new[] { "Snare", "Kick", "808", "Pad", "ZENOLOGY" }, now.Channels.Select(c => c.Name));
        Assert.Equal(Enumerable.Range(0, 5), now.Channels.Select(c => c.Index));
        Assert.Equal(new[] { 4, 2, 5, 1, 3 }, now.Channels.Select(c => c.MixerTrack));
        Assert.Equal(new[] { 4 }, now.Items.Select(i => i.Index));
        Assert.Equal(new HashSet<int> { 4 }, now.PatternSounds[0]);
        Assert.Equal(new HashSet<int> { 0, 2 }, now.PatternSounds[1]);
        Assert.Equal(new HashSet<int> { 1 }, now.TrackSounds[5]);
        Assert.Equal(new HashSet<int> { 3 }, now.Unused);
        Assert.Equal(new Dictionary<int, double> { [4] = 1.5 }, now.SoundAt);
        Assert.Equal(new HashSet<int> { 9 }, now.Freed);
        Assert.Null(result.Reordering(new[] { 0, 1, 2 }));
    }
}
