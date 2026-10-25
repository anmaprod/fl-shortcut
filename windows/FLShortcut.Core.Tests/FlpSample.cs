// Projets de FL fabriqués pour les tests, comme FL les écrit (même forme que le projet de test du propriétaire) :
// réglages MIDI, canaux, notes de chaque pattern, Playlist, pistes, Mixer. Miroir de Tests/FLShortcutTests/FLPSample.swift.
using FLShortcut.Core.Organizer;

namespace FLShortcut.Core.Tests;

public static class FlpSample
{
    public static FlpEvent Ev(byte id, int value) => new(id, FlpBytes.Le(value, FlpEvent.FixedSize(id)!.Value));

    public static FlpEvent Text(byte id, string s) => new(id, FlpBytes.Utf16Z(s));

    public static FlpEvent Notes(params (int Channel, int Key)[] list)
    {
        var bytes = new List<byte>();
        for (var n = 0; n < list.Length; n++)
        {
            bytes.AddRange(FlpBytes.Le(n * 96, 4));
            bytes.AddRange(FlpBytes.Le(0x4000, 2));
            bytes.AddRange(FlpBytes.Le(list[n].Channel, 2));
            bytes.AddRange(FlpBytes.Le(96, 4));
            bytes.AddRange(FlpBytes.Le(list[n].Key, 2));
            bytes.AddRange(new byte[] { 0, 0, 120, 0, 100, 0, 64, 100, 128, 128 });
        }
        return new FlpEvent(224, bytes.ToArray());
    }

    public sealed record ClipSpec(int Track, int Bar, int? Pattern = null, int? Channel = null, int Bars = 4);

    public static ClipSpec P(int pattern, int track, int bar, int bars = 4) => new(track, bar, Pattern: pattern, Bars: bars);
    public static ClipSpec C(int channel, int track, int bar, int bars = 4) => new(track, bar, Channel: channel, Bars: bars);

    public static FlpEvent Playlist(IEnumerable<ClipSpec> clips, int tracks, int size = 88)
    {
        var bytes = new List<byte>();
        foreach (var c in clips)
        {
            var item = new byte[size];
            FlpBytes.Put((uint)((c.Bar - 1) * 384), item, 0, 4);
            FlpBytes.Put(0x5000, item, 4, 2);
            FlpBytes.Put((uint)(c.Pattern is { } p ? 0x5000 + p : c.Channel!.Value), item, 6, 2);
            FlpBytes.Put((uint)(c.Bars * 384), item, 8, 4);
            FlpBytes.Put((uint)(tracks - 1 - c.Track), item, 12, 2);
            FlpBytes.Put(0x7F7F7F7F, item, 20, 4);
            bytes.AddRange(item);
        }
        return new FlpEvent(233, bytes.ToArray());
    }

    public static FlpEvent Track(int number, int color = 0x404040, bool muted = false)
    {
        var data = new byte[70];
        FlpBytes.Put((uint)number, data, 0, 4);
        FlpBytes.Put((uint)color, data, 4, 4);
        data[FlpProject.TrackEnabled] = (byte)(muted ? 0 : 1);
        return new FlpEvent(238, data);
    }

    public static readonly string[] DefaultNames = { "Pad", "Kick", "ZENOLOGY", "Snare", "808" };

    public static List<ClipSpec> DefaultClips() => new()
    {
        P(1, 0, 1), P(2, 1, 1), P(1, 2, 5), P(2, 3, 5), P(4, 4, 1), C(1, 5, 9),
    };

    /// Le projet de test du propriétaire, en petit : réglages MIDI (où 64 sert à autre chose), canal 0 qui contient les
    /// noms des patterns, notes, Playlist (deux fois les mêmes patterns sur deux pistes), pistes, Mixer.
    public static FlpFile Sample(List<ClipSpec>? clips = null, Dictionary<int, string>? trackNames = null, int trackCount = 12,
        int? group = null, List<ClipSpec>? second = null, int? current = null, string[]? names = null,
        Dictionary<int, string>? samples = null, Dictionary<int, int>? types = null)
    {
        names ??= DefaultNames;
        trackNames ??= new Dictionary<int, string>();
        samples ??= new Dictionary<int, string>();
        types ??= new Dictionary<int, int>();
        var events = new List<FlpEvent> { Text(199, "26.1"), Ev(0, 64), Ev(100, 32896), Ev(64, 2), Ev(96, 0), Ev(0, 71) };
        if (group is { } g) events.Add(Ev(146, g));
        events.AddRange(new[] { Ev(65, 1), Notes((2, 60), (2, 64), (2, 67)), Ev(65, 2), Notes((3, 48), (4, 36)), Ev(65, 3), Notes((1, 60)) });
        for (var i = 0; i < names.Length; i++)
        {
            events.AddRange(new[] { Ev(64, i), Ev(21, types.TryGetValue(i, out var t) ? t : (i == 2 ? 2 : 0)),
                Text(201, i == 2 ? "Fruity Wrapper" : ""), Text(203, names[i]) });
            if (samples.TryGetValue(i, out var path)) events.Add(Text(196, path));
            if (i == 0)
                events.AddRange(new[] { Ev(65, 1), Text(193, "Mélodie"), Ev(150, 0x404040), Ev(65, 2), Text(193, "Drums"),
                    Ev(65, 4), Text(193, "Vide") });
            events.Add(Ev(128, 0x404040));
        }
        var spec = clips ?? DefaultClips();
        var arrangements = new[] { spec, second };
        for (var n = 0; n < arrangements.Length; n++)
        {
            if (arrangements[n] is not { } list) continue;
            events.AddRange(new[] { Ev(99, n), Text(241, "Arrangement"), Playlist(list, trackCount) });
            for (var tr = 0; tr < trackCount; tr++)
            {
                events.Add(Track(tr + 1));
                if (trackNames.TryGetValue(tr, out var name)) events.Add(Text(239, name));
                events.Add(Ev(43, 0));
            }
        }
        if (current is { } c) events.Add(Ev(100, c));
        events.AddRange(new[] { Text(204, "Insert 1"), Text(201, "Fruity Wrapper"), Text(203, "Reverb"), Text(236, "") });
        return new FlpFile((ushort)names.Length, 96, events);
    }

    public static bool SameEvents(IEnumerable<FlpEvent> a, IEnumerable<FlpEvent> b) => a.SequenceEqual(b);
}
