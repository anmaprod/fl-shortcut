// Projet de FL lu dans son fichier (.flp) : ce que joue chaque pattern, où est chaque clip, et la copie rangée.
// Miroir de Tests/FLShortcutTests/FLPProjectTests.swift.
using FLShortcut.Core.Organizer;
using Xunit;
using static FLShortcut.Core.Tests.FlpSample;

namespace FLShortcut.Core.Tests;

public class FlpProjectTests
{
    private static FlpException Fails(Action action) => Assert.Throws<FlpException>(action);

    [Fact]
    public void FileIsRewrittenByteForByte()
    {
        var file = Sample();
        file.Events.Add(new FlpEvent(212, Enumerable.Repeat((byte)7, 300).ToArray()));   // longueur sur 2 octets
        var bytes = file.Encoded();
        var read = FlpFile.Parse(bytes);
        Assert.True(SameEvents(read.Events, file.Events));
        Assert.Equal(bytes, read.Encoded());
    }

    [Fact]
    public void DamagedFilesAreRefused()
    {
        var bytes = Sample().Encoded();
        Assert.Equal(FlpErrorKind.NotProject, Fails(() => FlpFile.Parse("RIFF"u8.ToArray().Concat(bytes.Skip(4)).ToArray())).Kind);
        Assert.Equal(FlpErrorKind.Damaged, Fails(() => FlpFile.Parse(bytes.Take(bytes.Length - 10).ToArray())).Kind);
        Assert.Equal(FlpErrorKind.NotProject, Fails(() => FlpFile.Parse(Array.Empty<byte>())).Kind);
        var endless = bytes.Take(18).Concat(FlpBytes.Le(6, 4)).Concat(new byte[] { 240, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F }).ToArray();
        Assert.Equal(FlpErrorKind.Damaged, Fails(() => FlpFile.Parse(endless)).Kind);
    }

    [Fact]
    public void ChannelsPatternsAndClipsAreRead()
    {
        var project = new FlpProject(Sample());
        Assert.Equal(new[] { "Pad", "Kick", "ZENOLOGY", "Snare", "808" }, project.Channels.Select(c => c.Name));
        Assert.Equal(new int?[] { 0, 0, 2, 0, 0 }, project.Channels.Select(c => c.Type));
        Assert.Equal(new[] { 2 }, project.SoundsOf(1));
        Assert.Equal(new[] { 3, 4 }, project.SoundsOf(2).OrderBy(x => x));
        Assert.Empty(project.SoundsOf(4));
        Assert.Equal(new Dictionary<int, int> { [2] = 3 }, project.Notes[1]);
        Assert.Equal(new Dictionary<int, string> { [1] = "Mélodie", [2] = "Drums", [4] = "Vide" }, project.PatternNames);
        Assert.Equal(12, project.TrackCount);
        Assert.Equal(88, project.ItemSize);
        Assert.Equal(new[] { ClipSource.Pattern(1), ClipSource.Pattern(2), ClipSource.Pattern(1), ClipSource.Pattern(2),
            ClipSource.Pattern(4), ClipSource.Channel(1) }, project.Clips.Select(c => c.Source));
        Assert.Equal(new[] { 0, 1, 2, 3, 4, 5 }, project.Clips.Select(c => c.Track));
        Assert.Equal(4 * 384, project.Clips[2].Position);
        Assert.Equal(4 * 384, project.Clips[2].Length);
    }

    [Fact]
    public void OlderClipSizeIsRecognized()
    {
        var file = Sample();
        var index = file.Events.FindIndex(e => e.Id == 233);
        file.Events[index] = Playlist(new[] { P(2, 3, 2) }, 12, size: 60);
        var project = new FlpProject(file);
        Assert.Equal(60, project.ItemSize);
        Assert.Equal(3, project.Clips[0].Track);
        Assert.Equal(384, project.Clips[0].Position);
    }

    /// Ce qui n'a pas exactement la forme attendue arrête tout : rien n'est deviné.
    [Fact]
    public void UnexpectedShapesStopEverything()
    {
        var two = Sample();
        two.Events.AddRange(new[] { Ev(99, 1), Playlist(new[] { P(1, 0, 1) }, 12) });
        Assert.Equal("arrangements", Fails(() => _ = new FlpProject(two)).What);
        var odd = Sample();
        var index = odd.Events.FindIndex(e => e.Id == 233);
        odd.Events[index] = odd.Events[index].With(odd.Events[index].Bytes[..^1]);
        Assert.Equal("clips", Fails(() => _ = new FlpProject(odd)).What);
        var hole = Sample();
        var second = Enumerable.Range(0, hole.Events.Count).Where(i => hole.Events[i].Id == 238).ElementAt(1);
        hole.Events[second] = Track(7);
        Assert.Equal("pistes", Fails(() => _ = new FlpProject(hole)).What);
        var stray = Sample();
        var notesAt = stray.Events.FindIndex(e => e.Id == 224);
        stray.Events[notesAt] = Notes((9, 60));
        Assert.Equal("notes", Fails(() => _ = new FlpProject(stray)).What);
    }

    /// Plusieurs arrangements : celui qui est ouvert dans FL est rangé, l'autre ne bouge pas ; sans savoir lequel est
    /// ouvert, rien n'est deviné.
    [Fact]
    public void OpenArrangementIsTheOneOrganized()
    {
        var second = new List<ClipSpec> { P(2, 0, 1) };
        var file = Sample(second: second, current: 1);
        var open = new FlpProject(file);
        Assert.Equal(new[] { ClipSource.Pattern(2) }, open.Clips.Select(c => c.Source));
        Assert.Equal(12, open.TrackCount);
        Assert.Equal(6, new FlpProject(Sample(second: second, current: 0)).Clips.Count);
        Assert.Equal("arrangements", Fails(() => _ = new FlpProject(Sample(second: second))).What);
        Assert.Equal(6, new FlpProject(Sample(second: new List<ClipSpec>())).Clips.Count);
        var copy = open.Rearranged(file, new Dictionary<int, int> { [0] = 3 });
        Assert.Equal(new[] { 3 }, new FlpProject(copy).Clips.Select(c => c.Track));
        Assert.Equal(file.Events.First(e => e.Id == 233), copy.Events.First(e => e.Id == 233));
        List<FlpEvent> First(FlpFile f)
        {
            var at = f.Events.FindIndex(e => e.Id == 99 && e.Value == 1);
            return f.Events.Take(at).Where(e => e.Id is 238 or 239).ToList();
        }
        Assert.True(SameEvents(First(copy), First(file)), "ni ses pistes");
    }

    /// « Split by channel » de FL : le pattern 2 (Snare et 808) garde la Snare ; la 808 a son pattern 5, et chaque clip
    /// du pattern 2 son double à la même place, sur la même piste.
    [Fact]
    public void SplitByChannel()
    {
        var file = Sample();
        var project = new FlpProject(file);
        var split = project.SplitByChannel(file);
        Assert.Equal(1, split.Added);
        var after = new FlpProject(FlpFile.Parse(split.File.Encoded()));
        Assert.Equal(new[] { 2 }, after.SoundsOf(1));
        Assert.Equal(new[] { 3 }, after.SoundsOf(2));
        Assert.Equal(new[] { 4 }, after.SoundsOf(5));
        Assert.Equal(new Dictionary<int, int> { [4] = 1 }, after.Notes[5]);
        Assert.Equal(project.Clips.Count + 2, after.Clips.Count);
        var copies = after.Clips.Where(c => c.Source == ClipSource.Pattern(5)).ToList();
        var originals = project.Clips.Where(c => c.Source == ClipSource.Pattern(2)).ToList();
        Assert.Equal(originals.Select(c => c.Position), copies.Select(c => c.Position));
        Assert.Equal(originals.Select(c => c.Track), copies.Select(c => c.Track));
        Assert.Equal(originals.Select(c => c.Length), copies.Select(c => c.Length));
        Assert.Equal(after.Clips.Select(c => c.Position).OrderBy(p => p), after.Clips.Select(c => c.Position));
        Assert.Equal(project.PatternNames, after.PatternNames);
        Assert.Equal(project.Channels, after.Channels);
        Assert.Equal(project.TrackCount, after.TrackCount);
        // Le fichier d'origine n'est pas touché.
        Assert.Equal(Sample().Encoded(), file.Encoded());

        var single = Sample();
        var secondNotes = Enumerable.Range(0, single.Events.Count).Where(i => single.Events[i].Id == 224).ElementAt(1);
        single.Events[secondNotes] = Notes((3, 48));
        var none = new FlpProject(single).SplitByChannel(single);
        Assert.Equal(0, none.Added);
        Assert.True(SameEvents(single.Events, none.File.Events));
    }

    /// Clips audio, samplers : le nom du fichier de son, sans dossier ni extension.
    [Fact]
    public void SampleFileNames()
    {
        var file = Sample(samples: new Dictionary<int, string> { [1] = "C:\\Packs\\Drums\\D30 Kick 85 Sexyy.wav", [3] = "/Users/x/Packs/ANMA - Hat House.wav" });
        var project = new FlpProject(file);
        Assert.Equal(new[] { null, "D30 Kick 85 Sexyy", null, "ANMA - Hat House", null }, project.Channels.Select(c => c.Sample));
        Assert.Equal(new Dictionary<int, string> { [1] = "D30 Kick 85 Sexyy", [3] = "ANMA - Hat House" }, ProjectFile.SampleNames(project));
        Assert.Equal("Kick.final", FlpProject.FileName("Kick.final.wav"));
        Assert.Equal("Kick", FlpProject.FileName("Kick"));
        Assert.Null(FlpProject.FileName(""));
    }

    /// Nom du fichier qui ne dit rien : le dossier qui le contient. Chemin de chaque clip audio, pour le lire.
    [Fact]
    public void SampleFolderAndClipPaths()
    {
        const string hat = "%FLStudioFactoryData%/Data/Patches/Packs/Drums/Hat/BX 17.wav";
        const string take = "%FLStudioUserData%/Audio/Recorded/prise 2.wav";
        var file = Sample(samples: new Dictionary<int, string> { [1] = hat, [3] = take }, types: new Dictionary<int, int> { [3] = ChannelInfo.AudioClipType });
        var project = new FlpProject(file);
        Assert.Equal(new Dictionary<int, string> { [1] = "Hat", [3] = "prise 2" }, ProjectFile.SampleNames(project));
        Assert.Equal(new Dictionary<int, string> { [3] = take }, ProjectFile.ClipPaths(project));
        Assert.Equal("Snare", ProjectFile.FolderName("C:\\Packs\\Snare\\x.wav"));
        Assert.Null(ProjectFile.FolderName("x.wav"));
    }

    /// Channel rack sur un groupe : la copie le montre sur « All », rien d'autre ne change.
    [Fact]
    public void CopyShowsAllChannels()
    {
        var file = Sample(group: 2);
        var project = new FlpProject(file);
        Assert.True(project.ShowsGroup);
        var all = project.ShowingAll(file);
        Assert.False(new FlpProject(all).ShowsGroup);
        Assert.Equal(new[] { new byte[] { 0xFF, 0xFF, 0xFF, 0xFF } }, all.Events.Where(e => e.Id == 146).Select(e => e.Bytes));
        Assert.True(SameEvents(all.Events.Where(e => e.Id != 146), file.Events.Where(e => e.Id != 146)));
        var copy = project.Rearranged(file, new Dictionary<int, int>());
        Assert.Equal(new[] { new byte[] { 0xFF, 0xFF, 0xFF, 0xFF } }, copy.Events.Where(e => e.Id == 146).Select(e => e.Bytes));
        Assert.False(new FlpProject(Sample(group: -1)).ShowsGroup);
        Assert.Empty(Sample().Events.Where(e => e.Id == 146));
        Assert.Equal(Sample().Encoded(), new FlpProject(Sample()).ShowingAll(Sample()).Encoded());
    }

    [Fact]
    public void LayerPlaysItsChildren()
    {
        var file = Sample();
        var pad = file.Events.FindIndex(e => e.Id == 203 && e.Text == "Pad");
        file.Events[pad - 2] = Ev(21, 3);
        file.Events.InsertRange(pad + 1, new[] { Ev(94, 3), Ev(94, 4) });
        var project = new FlpProject(file);
        Assert.Equal(3, project.Channels[0].Type);
        Assert.Equal(new[] { 3, 4 }, project.Channels[0].Children);
        Assert.Equal(new[] { 2, 3, 4 }, project.Played(new[] { 0, 2 }).OrderBy(x => x));
    }

    private static Func<FlpClip, PlaylistGroup> Group(FlpProject project) => clip =>
    {
        if (!clip.Source.IsPattern) return PlaylistGroup.Of(new[] { clip.Source.Number });
        var sounds = project.SoundsOf(clip.Source.Number);
        return sounds.Count == 0 ? PlaylistGroup.Silent(clip.Source.Number) : PlaylistGroup.Of(sounds);
    };

    /// Les mêmes patterns posés deux fois, sur deux pistes ; chaque pattern finit seul sur sa piste avec toutes ses
    /// répétitions, mélodies d'abord, puis drums, puis le pattern vide.
    [Fact]
    public void SameSoundsShareOneTrack()
    {
        var project = new FlpProject(Sample());
        var melody = new HashSet<int> { 2 };
        var layout = PlaylistLayout.Make(project.Clips, Group(project), s => (s.IsSubsetOf(melody) ? 0 : 1, 0, s.Min()), project.TrackCount)!;
        Assert.Equal(new Dictionary<int, int> { [0] = 0, [2] = 0, [1] = 2, [3] = 2, [5] = 1, [4] = 3 }, layout.Tracks);
        Assert.Equal(new[] { 0, 1, 2 }, layout.Sounds.Keys.OrderBy(k => k));
        Assert.Equal(new[] { 2 }, layout.Sounds[0]);
        Assert.Equal(new[] { 1 }, layout.Sounds[1]);
        Assert.Equal(new[] { 3, 4 }, layout.Sounds[2].OrderBy(x => x));
        Assert.Equal(4, layout.Count);
    }

    [Fact]
    public void OverlappingClipsOfOneSoundGetAnotherTrack()
    {
        var clips = new List<ClipSpec> { P(1, 0, 1, bars: 8), P(1, 3, 5), P(1, 2, 9), P(3, 1, 1) };
        var project = new FlpProject(Sample(clips: clips));
        var layout = PlaylistLayout.Make(project.Clips, Group(project), s => (0, 0, s.Min()), project.TrackCount)!;
        Assert.Equal(new Dictionary<int, int> { [3] = 0, [0] = 1, [2] = 1, [1] = 2 }, layout.Tracks);
        Assert.Equal(new[] { 1 }, layout.Sounds[0]);
        Assert.Equal(new[] { 2 }, layout.Sounds[1]);
        Assert.Equal(new[] { 2 }, layout.Sounds[2]);
        Assert.Null(PlaylistLayout.Make(project.Clips, Group(project), s => (0, 0, s.Min()), 2));
    }

    /// La copie : seuls les clips changent de piste ; les pistes où il y avait ou où il y a des clips perdent leur
    /// ancien nom et leur couleur (rien d'autre ne bouge, octet pour octet).
    [Fact]
    public void CopyMovesOnlyTheClips()
    {
        var file = Sample(trackNames: new Dictionary<int, string> { [1] = "Intro", [9] = "Voix plus tard" });
        var colored = Enumerable.Range(0, file.Events.Count).Where(i => file.Events[i].Id == 238).ElementAt(3);
        file.Events[colored] = Track(4, color: 0x00FF00);
        var project = new FlpProject(file);
        var moves = new Dictionary<int, int> { [0] = 0, [2] = 0, [1] = 2, [3] = 2, [5] = 1, [4] = 3 };
        var copy = project.Rearranged(file, moves);
        var again = new FlpProject(FlpFile.Parse(copy.Encoded()));
        Assert.Equal(new[] { 0, 2, 0, 2, 3, 1 }, again.Clips.Select(c => c.Track));
        Assert.Equal(project.Clips.Select(c => c.Source), again.Clips.Select(c => c.Source));
        Assert.Equal(project.Clips.Select(c => c.Position), again.Clips.Select(c => c.Position));
        Assert.Equal(project.Clips.Select(c => c.Length), again.Clips.Select(c => c.Length));
        Assert.Equal(new[] { "Voix plus tard" }, copy.Events.Where(e => e.Id == 239).Select(e => e.Text));
        Assert.Equal(new uint[] { 0x404040 }, copy.Events.Where(e => e.Id == 238).Select(e => FlpBytes.UInt(e.Bytes, 4, 4)).Distinct());
        static IEnumerable<FlpEvent> Others(FlpFile f) => f.Events.Where(e => e.Id is not (233 or 238 or 239));
        Assert.True(SameEvents(Others(copy), Others(file)));
        var playlist = file.Events.FindIndex(e => e.Id == 233);
        var same = project.Rearranged(file, project.Clips.ToDictionary(c => c.Item, c => c.Track));
        Assert.Equal(file.Events[playlist], same.Events[playlist]);
        Assert.Equal("clips", Fails(() => project.Rearranged(file, new Dictionary<int, int> { [0] = 12 })).What);
    }

    /// Une piste coupée (mute) : un clip qui en part se mettrait à jouer dans la copie, donc rien n'est fait.
    [Fact]
    public void MutedTrackStopsTheCopy()
    {
        var file = Sample();
        var tracks = Enumerable.Range(0, file.Events.Count).Where(i => file.Events[i].Id == 238).ToList();
        file.Events[tracks[3]] = Track(4, muted: true);
        var project = new FlpProject(file);
        Assert.Equal(new[] { 3 }, project.MutedTracks);
        Assert.Equal("piste coupée", Fails(() => project.Rearranged(file, new Dictionary<int, int> { [3] = 2 })).What);
        var quiet = Sample();
        quiet.Events[tracks[9]] = Track(10, muted: true);
        var copy = new FlpProject(quiet).Rearranged(quiet, new Dictionary<int, int> { [0] = 9, [5] = 0 });
        Assert.Empty(new FlpProject(copy).MutedTracks);
        Assert.Equal(new[] { 9 }, new FlpProject(new FlpProject(quiet).Rearranged(quiet, new Dictionary<int, int>())).MutedTracks);
    }

    /// FL 2025 : l'événement 172 a un octet de forme, puis 2 ou 4 octets.
    [Fact]
    public void Fl2025EventKeepsTheReadingAligned()
    {
        var file = Sample();
        file.Events.InsertRange(1, new[] { new FlpEvent(172, new byte[] { 1, 1, 0 }), Text(192, "FL Studio 26.1"),
            new FlpEvent(172, new byte[] { 0, 1, 0, 0, 0 }), Ev(37, 2) });
        var read = FlpFile.Parse(file.Encoded());
        Assert.True(SameEvents(file.Events, read.Events));
        Assert.Equal(file.Encoded(), read.Encoded());
        Assert.Equal(new[] { 2 }, new FlpProject(read).SoundsOf(1));
        var odd = Sample();
        odd.Events.Insert(1, new FlpEvent(172, new byte[] { 2, 0, 0, 0 }));
        Assert.Equal("événement 172", Fails(() => FlpFile.Parse(odd.Encoded())).What);
    }

    /// Des notes de pattern ailleurs qu'au début d'un événement (avant les canaux) : tout s'arrête.
    [Fact]
    public void HiddenNotesStopEverything()
    {
        var file = Sample();
        var notes = Notes((2, 60));
        var hidden = new byte[] { 65, 1, 0, 224, (byte)notes.Bytes.Length }.Concat(notes.Bytes);
        file.Events.Insert(1, new FlpEvent(212, new byte[] { 9, 9 }.Concat(hidden).ToArray()));
        Assert.Equal("lecture", Fails(() => FlpFile.Parse(file.Encoded())).What);
        var fewer = new FlpFile(9, 96, Sample().Events);
        Assert.Equal("canaux", Fails(() => _ = new FlpProject(fewer)).What);
    }
}
