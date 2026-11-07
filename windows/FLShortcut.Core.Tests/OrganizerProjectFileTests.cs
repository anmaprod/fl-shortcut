// Organiser sur le fichier du projet : ce que joue chaque pattern et chaque piste, le fichier comparé au projet ouvert,
// le nom de la copie rangée (jamais par-dessus un fichier), la marque qui dit que FL l'a ouverte, le titre de FL.
// Miroir de Tests/FLShortcutTests/OrganizerProjectFileTests.swift.
using FLShortcut.Core.Organizer;
using Xunit;
using static FLShortcut.Core.Tests.FlpSample;

namespace FLShortcut.Core.Tests;

public class OrganizerProjectFileTests
{
    private static readonly HashSet<int> None = new();

    [Fact]
    public void SoundsComeFromNotesAndClips()
    {
        var project = new FlpProject(Sample());
        var sounds = ProjectFile.Sounds(project, None);
        Assert.True(Same.SetMaps(sounds.Patterns, new Dictionary<int, HashSet<int>> { [0] = new() { 2 }, [1] = new() { 3, 4 }, [2] = new() { 1 } }));
        Assert.True(Same.SetMaps(sounds.Tracks, new Dictionary<int, HashSet<int>>
        {
            [0] = new() { 2 }, [1] = new() { 3, 4 }, [2] = new() { 2 }, [3] = new() { 3, 4 }, [5] = new() { 1 },
        }));
        Assert.True(sounds.Used.SetEquals(new[] { 1, 2, 3, 4 }));
        Assert.False(ProjectFile.Sounds(project, new HashSet<int> { 1 }).Tracks.ContainsKey(5), "une automation n'est pas un son");
        Assert.Equal(new[] { PlaylistGroup.Of(new[] { 2 }), PlaylistGroup.Of(new[] { 3, 4 }), PlaylistGroup.Of(new[] { 2 }),
                PlaylistGroup.Of(new[] { 3, 4 }), PlaylistGroup.Silent(4), PlaylistGroup.Other(1) },
            project.Clips.Select(c => ProjectFile.Group(c, project, new HashSet<int> { 1 })));
        var snapshot = ProjectFile.Snapshot(project, "C:/p.flp", None);
        Assert.Equal(1, snapshot.SilentPatterns);
        Assert.Equal(PlaylistGroup.Of(new[] { 2, 3 }), snapshot.Moving(new Dictionary<int, int> { [1] = 0, [2] = 1, [3] = 2, [4] = 3 }).Groups[1]);
    }

    /// FL demandait « Invalid project data folder » en ouvrant la copie : la copie ne garde pas un dossier de données
    /// qui ne mène nulle part ; un dossier qui existe, ou écrit avec une variable de FL, reste.
    [Fact]
    public void CopyDropsAMissingDataFolder()
    {
        static FlpEvent Folder(string path) => new(ProjectFile.DataFolderEvent, FlpBytes.Utf16Z(path));
        var file = Sample();
        var projectFolder = Path.Combine(Path.GetTempPath(), "projets");
        var existing = new HashSet<string> { Path.Combine(projectFolder, "Nuit"), "C:\\Users\\moi\\Données" };
        bool Exists(string p) => existing.Contains(p);
        var cases = new (string Path, bool Kept)[]
        {
            ("/Users/ailleurs/Nuit", false), ("C:\\Users\\moi\\Ailleurs", false), ("Ancien", false),
            ("C:\\Users\\moi\\Données", true), ("Nuit", true), ("%FLStudioUserData%/Nuit", true),
        };
        foreach (var (path, kept) in cases)
        {
            var withFolder = file.Clone();
            withFolder.Events.Insert(1, Folder(path));
            var cleaned = ProjectFile.WithoutMissingDataFolder(withFolder, projectFolder, Exists);
            if (kept) Assert.Null(cleaned);
            else Assert.Equal(file.Encoded(), cleaned!.Encoded());
        }
        Assert.Null(ProjectFile.WithoutMissingDataFolder(file, projectFolder, Exists));
        Assert.True(ProjectFile.IsBlockingDialog("Invalid project data folder"));
        Assert.False(ProjectFile.IsBlockingDialog("Mon son - FL Studio 2025"));
    }

    /// Le fichier enregistré doit être le projet ouvert dans FL : sinon rien n'est touché (raison sans aucun nom).
    [Fact]
    public void FileMustBeTheOpenProject()
    {
        var project = new FlpProject(Sample());
        var channels = new[] { "Pad", "Kick", "ZENOLOGY", "Snare", "808" };
        var patterns = new Dictionary<int, string> { [0] = "Mélodie", [1] = "Drums", [2] = "Pattern 3", [3] = "Vide" };
        Assert.Null(ProjectFile.Mismatch(project, channels, patterns));
        Assert.Equal("canaux 5/4", ProjectFile.Mismatch(project, channels.Take(4).ToList(), patterns));
        var renamed = channels.ToArray();
        renamed[3] = "Clap";
        Assert.Equal("nom c3", ProjectFile.Mismatch(project, renamed, patterns));
        Assert.Equal("pattern 2", ProjectFile.Mismatch(project, channels, new Dictionary<int, string> { [0] = "Mélodie", [3] = "Vide" }));
        Assert.True(ProjectFile.Same("BETTY WHITE Hat @baby", "BETTY WHITE Hat @babyxprod"), "nom coupé par le script");
        Assert.False(ProjectFile.Same("Hat", "Hat 2"), "un nom court n'est jamais pris pour un début");
    }

    /// Nommée comme « Save new version » de FL, jamais par-dessus un fichier.
    [Fact]
    public void CopyNameNeverOverwrites()
    {
        var folder = Path.Combine(Path.GetTempPath(), "projets");
        var original = Path.Combine(folder, "Mon son.flp");
        Assert.Equal("Mon son_2.flp", Path.GetFileName(ProjectFile.CopyPath(original, _ => false)));
        var taken = new HashSet<string> { "Mon son_2.flp", "Mon son_3.flp" };
        Assert.Equal("Mon son_4.flp", Path.GetFileName(ProjectFile.CopyPath(original, p => taken.Contains(Path.GetFileName(p)))));
        Assert.Equal(Path.Combine(folder, "Mon son_4.flp"),
            ProjectFile.CopyPath(Path.Combine(folder, "Mon son_2.flp"), p => taken.Contains(Path.GetFileName(p))));
        Assert.Equal("_7_2.flp", Path.GetFileName(ProjectFile.CopyPath(Path.Combine(folder, "_7.flp"), _ => false)));
    }

    [Fact]
    public void MarkerIsPutOnANamedPattern()
    {
        var file = Sample();
        var marked = ProjectFile.Marking(file, "FL Shortcuts 42")!.Value;
        Assert.Equal(ProjectFile.Mark.Pattern(1), marked.Mark);
        var project = new FlpProject(marked.File);
        Assert.Equal(new Dictionary<int, string> { [1] = "FL Shortcuts 42", [2] = "Drums", [4] = "Vide" }, project.PatternNames);
        Assert.Equal(new FlpProject(file).Clips, project.Clips);
        // Aucun pattern nommé : le nom est ajouté au premier pattern décrit (pas à celui de ses notes).
        var unnamed = file.Clone();
        unnamed.Events.RemoveAll(e => e.Id == 193);
        var added = ProjectFile.Marking(unnamed, "FL Shortcuts 42")!.Value;
        Assert.Equal(ProjectFile.Mark.Pattern(1), added.Mark);
        Assert.Equal(new Dictionary<int, string> { [1] = "FL Shortcuts 42" }, new FlpProject(added.File).PatternNames);
        Assert.Equal(new FlpProject(file).Notes.Keys.OrderBy(k => k), new FlpProject(added.File).Notes.Keys.OrderBy(k => k));
        // Un seul pattern, jamais nommé : la marque va sur le premier canal nommé ; rien d'autre ne change.
        var bare = unnamed.Clone();
        bare.Events = unnamed.Events.Where((e, i) => e.Id != 65 || (i + 1 < unnamed.Events.Count && unnamed.Events[i + 1].Id == 224)).ToList();
        var onChannel = ProjectFile.Marking(bare, "FL Shortcuts 42")!.Value;
        Assert.Equal(ProjectFile.Mark.Channel(0), onChannel.Mark);
        Assert.Equal(new[] { "FL Shortcuts 42", "Kick", "ZENOLOGY", "Snare", "808" }, new FlpProject(onChannel.File).Channels.Select(c => c.Name));
        Assert.Equal(bare.Events.Count, onChannel.File.Events.Count);
        var nameless = bare.Clone();
        nameless.Events.RemoveAll(e => e.Id == 203);
        Assert.Null(ProjectFile.Marking(nameless, "FL Shortcuts 42"));
    }

    [Fact]
    public void ProjectNameInFlTitle()
    {
        Assert.Equal(new[] { "rio leyva typz" }, ProjectFile.TitleNames("rio leyva typz - FL Studio 2025"));
        Assert.Equal(new[] { "Mon son" }, ProjectFile.TitleNames("FL Studio 2025 - Mon son.flp *"));
        Assert.Equal(new[] { "Mon son" }, ProjectFile.TitleNames("Mon son.flp"));
        Assert.Empty(ProjectFile.TitleNames("FL Studio 2025"));
        Assert.Empty(ProjectFile.TitleNames(""));
    }

    /// Rien n'est touché, avec ce qu'il faut faire : piste coupée, dossier refusé par Windows, marque restée.
    [Fact]
    public void ReadingStopsWithAClearReason()
    {
        var channels = new[] { "Pad", "Kick", "ZENOLOGY", "Snare", "808" }.Select((n, i) => new ChannelInfo(i, 2, 0, new RgbColor(0, 0, 0), n)).ToList();
        var patterns = new[] { "Mélodie", "Drums", "Pattern 3", "Vide" }.Select((n, i) => new PatternInfo(i, new RgbColor(0, 0, 0), n)).ToList();
        const string path = "C:/projets/Mon son.flp";
        var muted = Sample();
        var track = muted.Events.FindIndex(e => e.Id == 238);
        muted.Events[track] = Track(1, muted: true);
        var why = "";
        var files = new ProjectFileAccess { Save = _ => path, Open = _ => false, Read = _ => muted };
        Assert.Throws<OrganizerError>(() => ProjectFile.Read(files, null, channels, patterns, w => why = w));
        Assert.Equal("piste coupée", why);
        var locked = new ProjectFileAccess { Save = _ => path, Open = _ => false, Read = _ => throw new UnauthorizedAccessException() };
        var error = Assert.Throws<OrganizerError>(() => ProjectFile.Read(locked, null, channels, patterns, w => why = w));
        Assert.Equal(ProjectFile.DeniedError, error);
        Assert.Equal("autorisation", why);
        Assert.True(ProjectFile.IsMarker("FL Shortcuts 4821"));
        Assert.False(ProjectFile.IsMarker("FL Shortcuts 4821 bis"));
        // Un nom trop long pour être remis par le script n'est pas pris pour la marque.
        var longName = Sample();
        var first = longName.Events.FindIndex(e => e.Id == 193);
        longName.Events[first] = Text(193, new string('é', 40));
        Assert.Equal(ProjectFile.Mark.Pattern(2), ProjectFile.Marking(longName, "FL Shortcuts 1")?.Mark);
    }
}
