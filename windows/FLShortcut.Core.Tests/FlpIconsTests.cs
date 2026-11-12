using FLShortcut.Core.Organizer;
using Xunit;
using static FLShortcut.Core.Tests.FlpSample;

namespace FLShortcut.Core.Tests;

/// 12/11, comme le Mac (testKnownIconsAreWrittenInTheCopy) : les icônes connues écrites dans la copie, à la forme vue
/// dans le projet du propriétaire (FL 26.1).
public class FlpIconsTests
{
    private static List<FlpEvent> Insert(string? name, bool color, int? icon = null)
    {
        var out_ = new List<FlpEvent>();
        if (color) out_.Add(Ev(149, 0x1F3BFF));
        out_.Add(Ev(42, 0));
        if (name is not null) out_.Add(Text(204, name));
        if (icon is { } i) out_.Add(Ev(95, i));
        out_.AddRange(new[] { Text(236, ""), Ev(98, 0), Text(235, ""), Ev(154, 0), Ev(147, 0) });
        return out_;
    }

    private static FlpFile WithFlMixer()
    {
        var file = Sample();
        var types = Enumerable.Range(0, file.Events.Count).Where(i => file.Events[i].Id == 21).Reverse().ToList();
        foreach (var at in types) file.Events.Insert(at + 1, Ev(155, 0));          // FL l'écrit toujours, à 0
        file.Events.RemoveRange(file.Events.Count - 4, 4);                         // le Mixer de l'exemple…
        file.Events.AddRange(Insert(null, false));                                 // … remplacé par celui de FL
        file.Events.AddRange(Insert("Basse", true));
        file.Events.AddRange(Insert(null, false));
        file.Events.AddRange(Insert("Kick", true, 7));
        return file;
    }

    [Fact]
    public void KnownIconsAreWrittenInTheCopy()
    {
        var file = WithFlMixer();
        var written = FlpIcons.WithIcons(file, new Dictionary<int, uint> { [0] = 2, [1] = 4, [9] = 4 },
            new Dictionary<int, uint> { [0] = 2, [1] = 2, [3] = 4, [8] = 4 });
        Assert.Equal(new[] { 0, 1 }, written.Channels.OrderBy(x => x));
        Assert.Equal(new[] { 1, 3 }, written.Inserts.OrderBy(x => x));
        var events = written.File.Events;
        // Le premier 155 de chaque son, dans l'ordre : 2, 4, puis 0.
        var icons = Enumerable.Range(0, events.Count).Where(i => events[i].Id == 155).Select(i => events[i].Value).ToList();
        Assert.Equal(new uint[] { 2, 4, 0, 0, 0 }, icons);
        var starts = Enumerable.Range(0, events.Count).Where(i => events[i].Id == 236).ToList();
        List<byte> Before(int k)
        {
            var output = Enumerable.Range(starts[k - 1], starts[k] - starts[k - 1]).Last(i => events[i].Id == 147);
            return events.Skip(output + 1).Take(starts[k] - output - 1).Select(e => e.Id).ToList();
        }
        Assert.Equal(new byte[] { 149, 42, 204, 95 }, Before(1));
        Assert.Equal(new byte[] { 42 }, Before(2));
        Assert.Equal(new byte[] { 149, 42, 204, 95 }, Before(3));
        Assert.Equal(new uint[] { 2, 4 }, events.Where(e => e.Id == 95).Select(e => e.Value));
        Assert.Equal((2, 2), FlpIcons.IconCounts(written.File));
        // L'original n'a pas bougé.
        Assert.Equal(1, file.Events.Count(e => e.Id == 95));
    }

    [Fact]
    public void UnexpectedMixerGetsNothing()
    {
        var written = FlpIcons.WithIcons(Sample(), new Dictionary<int, uint>(), new Dictionary<int, uint> { [1] = 2 });
        Assert.Empty(written.Inserts);
    }

    [Fact]
    public void OnlyKnownNumbersAreWritten()
    {
        var drums = FlIcon.FromCode("7-4")!.Value;
        var bass = FlIcon.FromCode("6-0")!.Value;
        var known = FlpIcons.KnownIcons(new Dictionary<int, FlIcon> { [0] = drums, [2] = drums, [3] = bass },
            new Dictionary<string, uint> { ["7-4"] = 4 });
        Assert.Equal(new Dictionary<int, uint> { [0] = 4, [2] = 4 }, known);
    }
}
