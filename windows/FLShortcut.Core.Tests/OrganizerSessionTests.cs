// Analyse de l'Organiser sur le fichier du projet (la seule de l'appli Windows, comme sur le Mac) : FL enregistre, le
// .flp est lu, les sons de chaque pattern et de chaque piste viennent de ses notes et de ses clips, chaque son reconnu
// à son nom ou écouté seul dans son pattern. Miroir des essais « fichier » de Tests/FLShortcutTests/OrganizerSessionTests.swift.
using FLShortcut.Core.Organizer;
using Xunit;

namespace FLShortcut.Core.Tests;

public sealed class OrganizerSessionTests
{
    private static readonly RgbColor Red = new(200, 0, 0);
    private static readonly OrganizerSession.Timing Fast = new() { Listen = 0.2, TestNote = 0.1, Tail = 0.1, Slice = 0.05 };
    private static readonly string ProjectPath = Path.Combine(Path.GetTempPath(), "projets", "Mon son.flp");

    /// Le son d'une famille : sa place dans l'ordre des familles, en amplitude (bien au-dessus de −50 dBFS).
    private static float[] Tone(SoundFamily family) => Enumerable.Repeat(0.1f * (SoundFamilies.Rank(family) + 1), 64).ToArray();

    private static readonly OrganizerSession.Classify Classify = (samples, _) =>
    {
        if (samples.Length == 0 || samples[0] <= 0.01) return (SoundFamily.Unsure, 0, "silence");
        return (SoundFamilies.Order[(int)Math.Round(samples[0] / 0.1) - 1], 0.9, "faux");
    };

    private static FakeOrganizerLink Project(string[] names, Func<int, int>? type = null)
    {
        var link = new FakeOrganizerLink
        {
            Channels = names.Select((n, i) => new ChannelInfo(i, type?.Invoke(i) ?? 2, i + 1, Red, n)).ToList(),
            PatternList = new[] { "Mélodie", "Drums", "Pattern 3", "Vide" }.Select((n, i) => new PatternInfo(i, Red, n)).ToList(),
            Mixer = Enumerable.Range(0, 7).Select(i => new MixerTrackInfo(i, Red, i == 0 ? "Master" : $"Insert {i}")).ToList(),
        };
        return link;
    }

    private static ProjectFileAccess Files(FlpFile file, string? path = null, Action? saved = null) => new()
    {
        Save = _ =>
        {
            saved?.Invoke();
            return path ?? ProjectPath;
        },
        Open = _ => false,
        Read = _ => file,
    };

    /// Analyse sur le fichier du projet (retour du propriétaire, vidéo du 21/10 : des mélodies classées « FX », des
    /// patterns oubliés) : FL enregistre le projet, les sons de chaque pattern et de chaque piste viennent de ses notes
    /// et de ses clips. Ni pattern relevé, ni chanson jouée, ni piste écoutée ; rien n'est retiré de FL avant.
    [Fact]
    public void ProjectFileGivesExactSounds()
    {
        var link = Project(FlpSample.DefaultNames);
        var audio = new FakeAudio(link) { Parts = { [2] = Tone(SoundFamily.Melody) } };
        var saves = 0;
        var session = new OrganizerSession(link, audio, Classify, Files(FlpSample.Sample(), saved: () => saves++),
            nameDrum: (_, _) => SoundKind.Kick, timing: Fast, sleep: _ => { });
        var (result, error) = session.Run();
        Assert.Null(error);
        Assert.NotNull(result);

        Assert.Equal(1, saves);   // FL enregistre le projet avant la lecture
        // index 0 = pattern 1 ; le pattern 2 séparé son par son, la 808 dans le pattern 5
        Assert.True(Same.SetMaps(new Dictionary<int, HashSet<int>> { [0] = new() { 2 }, [1] = new() { 3 }, [2] = new() { 1 }, [4] = new() { 4 } },
            result!.PatternSounds));
        Assert.Equal(new PatternInfo(4, Red, "Pattern 5"), result.Patterns[^1]);
        Assert.True(Same.SetMaps(new Dictionary<int, HashSet<int>>
        {
            [0] = new() { 2 }, [1] = new() { 3, 4 }, [2] = new() { 2 }, [3] = new() { 3, 4 }, [5] = new() { 1 },
        }, result.TrackSounds));
        Assert.Equal(new[] { 0 }, result.Unused.ToArray());   // ni note ni clip
        Assert.Equal(new[] { 1, 2, 3, 4 }, result.Items.Select(i => i.Index));
        Assert.Equal(SoundFamily.Melody, result.Items.First(i => i.Index == 2).Family);   // écouté seul dans son pattern
        Assert.Equal(ProjectPath, result.Project?.Path);
        Assert.Equal(8, result.Project?.Clips.Count);   // chaque clip du pattern 2 et son double
        Assert.Equal(1, result.Project?.SilentPatterns);
        Assert.Equal(1, result.Project?.SplitPatterns);
        Assert.DoesNotContain(link.Log, l => l.StartsWith("all") || l.StartsWith("song") || l.StartsWith("track"));   // rien n'est deviné
        Assert.Contains("solo 2 p1", link.Log);
        Assert.True(link.AllChannels);
        var diag = session.Diagnostics;
        Assert.Equal("oui", diag.File);
        Assert.Equal(8, diag.Clips);
        Assert.Contains("fichier=oui clips=8 séparés=1", diag.Text);
        Assert.DoesNotContain("ZENOLOGY", diag.Text);   // jamais un nom dans le diagnostic
        Assert.Equal(1, audio.Started);
        Assert.Equal(1, audio.Stopped);
        Assert.Equal("restore", link.Log[^1]);   // FL remis comme avant à la fin
    }

    /// Channel rack sur un groupe (retour du propriétaire : « le truc du All […] c'est pas à la personne de le
    /// faire ») : sur le fichier, tous les sons sont comptés comme dans « All », sans rien demander.
    [Fact]
    public void ProjectFileCountsAllChannelsWhateverTheGroup()
    {
        var link = Project(FlpSample.DefaultNames);
        link.Group = new List<int> { 1, 3 };
        var audio = new FakeAudio(link) { Parts = { [2] = Tone(SoundFamily.Melody) } };
        var session = new OrganizerSession(link, audio, Classify, Files(FlpSample.Sample()),
            nameDrum: (_, _) => SoundKind.Kick, nameMelody: (_, _) => SoundKind.Pad, timing: Fast, sleep: _ => { });
        var (result, error) = session.Run();
        Assert.Null(error);
        Assert.True(link.AllChannels);
        Assert.Equal(5, result!.Channels.Count);
        Assert.Equal(new[] { 1, 2, 3, 4 }, result.Items.Select(i => i.Index));
        Assert.Equal(SoundKind.Pad, result.Items.First(i => i.Index == 2).Kind);   // mélodie écoutée : sa sorte
    }

    /// IA intégrée (demande du propriétaire : les mêmes choix que l'aperçu, sans changer l'organisation) : la sorte
    /// d'une voix, d'une basse ou d'un FX vient d'elle (une voix : Chœur) ; drums et mélodies gardent leurs règles.
    [Fact]
    public void EmbeddedAINamesTheKindOfEveryFamily()
    {
        var names = new[] { "Pad", "Son 1", "Son 2", "Snare", "808" };
        var link = Project(names);
        var audio = new FakeAudio(link) { Parts = { [1] = Tone(SoundFamily.Drums), [2] = Tone(SoundFamily.Vocals) } };
        var asked = new List<SoundFamily>();
        var session = new OrganizerSession(link, audio, Classify, Files(FlpSample.Sample(names: names)),
            nameDrum: (_, _) => SoundKind.Kick,
            nameKind: (_, _, family) =>
            {
                asked.Add(family);
                return family == SoundFamily.Vocals ? SoundKind.Choir : null;
            },
            timing: Fast, sleep: _ => { });
        var (result, _) = session.Run();
        Assert.Equal(SoundKind.Choir, result!.Items.First(i => i.Index == 2).Kind);
        Assert.Equal(SoundKind.Kick, result.Items.First(i => i.Index == 1).Kind);   // drums : leurs règles
        Assert.Equal(new[] { SoundFamily.Vocals }, asked);
    }

    /// Clips audio (vidéo du propriétaire : un kick nommé « Keys », un hi-hat « Snare ») : le nom du fichier de son dit
    /// ce qu'est le son quand le nom du canal ne le dit pas, ou a été donné par l'Organiser ; rien n'est écouté pour eux.
    [Fact]
    public void SampleFileNameTellsWhatTheSoundIs()
    {
        var names = new[] { "Pad", "Keys 2", "ZENOLOGY", "Snare 3", "808" };
        var link = Project(names);
        var audio = new FakeAudio(link)
        {
            Parts = { [1] = Tone(SoundFamily.Melody), [2] = Tone(SoundFamily.Melody), [3] = Tone(SoundFamily.Drums) },
        };
        var file = FlpSample.Sample(names: names, samples: new() { [1] = @"C:\Packs\D30 Kick 85 Sexyy.wav", [3] = "/Packs/ANMA - Hat House.wav" });
        var session = new OrganizerSession(link, audio, Classify, Files(file), nameDrum: (_, _) => SoundKind.Snare,
            timing: Fast, sleep: _ => { });
        var (result, _) = session.Run();
        Assert.Equal(SoundKind.Kick, result!.Items.First(i => i.Index == 1).Kind);
        Assert.Equal(SoundKind.HiHat, result.Items.First(i => i.Index == 3).Kind);
        Assert.DoesNotContain(link.Log, l => l.StartsWith("solo 1") || l.StartsWith("solo 3"));
        Assert.DoesNotContain("Kick", session.Diagnostics.Text);   // jamais un nom dans le diagnostic
    }

    /// Un clip audio (une prise de voix) est lu directement dans son fichier, sans le faire jouer par FL (projets de
    /// voix du propriétaire : jouées dans FL, elles commençaient par un silence, étaient mal reconnues).
    [Fact]
    public void AudioClipIsReadFromItsFile()
    {
        var names = new[] { "Pad", "untitled_2026-10-15 23-37-42_Insert 5", "ZENOLOGY", "Snare", "808" };
        var link = Project(names, i => i == 1 ? ChannelInfo.AudioClipType : 2);
        var audio = new FakeAudio(link) { Parts = { [2] = Tone(SoundFamily.Melody) } };
        const string path = @"%FLStudioUserData%\Audio\Recorded\untitled_2026-10-15 23-37-42_Insert 5.wav";
        var file = FlpSample.Sample(names: names, samples: new() { [1] = path }, types: new() { [1] = ChannelInfo.AudioClipType });
        var voice = Tone(SoundFamily.Vocals);
        var asked = new List<string>();
        var session = new OrganizerSession(link, audio, Classify, Files(file), nameDrum: (_, _) => SoundKind.Kick,
            timing: Fast, sleep: _ => { },
            soundFile: (wanted, _) =>
            {
                asked.Add(wanted);
                return new SampleSound(voice, 48_000);
            });
        var (result, _) = session.Run();
        Assert.Equal(SoundFamily.Vocals, result!.Items.First(i => i.Index == 1).Family);
        Assert.Equal(new[] { path }, asked);
        Assert.DoesNotContain(link.Log, l => l.StartsWith("solo 1") || l.StartsWith("note 1 "));   // rien joué dans FL
        Assert.Contains("c1:faux+fichier", session.Diagnostics.Rules);
    }

    /// Une prise pas retrouvée sur le disque commence souvent par un silence : elle est écoutée une fois qu'elle sonne
    /// dans FL ; muette jusqu'au bout : « À vérifier ». Chaque note est toujours coupée.
    [Fact]
    public void RecordingIsHeardOnceItSounds()
    {
        var names = new[] { "Pad", "untitled_2026-10-15 23-37-42_Insert 5", "ZENOLOGY", "Snare", "808" };
        var link = Project(names, i => i == 1 ? ChannelInfo.AudioClipType : 2);
        var audio = new FakeAudio(link)
        {
            Parts = { [2] = Tone(SoundFamily.Melody) },
            TestSounds = { [1] = Tone(SoundFamily.Vocals) },
            SilentTakes = { [1] = 60 },
        };
        var file = FlpSample.Sample(names: names, samples: new() { [1] = "introuvable.wav" }, types: new() { [1] = ChannelInfo.AudioClipType });
        var session = new OrganizerSession(link, audio, Classify, Files(file), nameDrum: (_, _) => SoundKind.Kick,
            timing: Fast, sleep: _ => { }, soundFile: (_, _) => null);
        var (result, _) = session.Run();
        Assert.Equal(SoundFamily.Vocals, result!.Items.First(i => i.Index == 1).Family);
        Assert.Equal(2, link.Log.Count(l => l.StartsWith("note 1 ")));   // la note de base, puis coupée

        audio.SilentTakes[1] = 10_000;
        (result, _) = new OrganizerSession(link, audio, Classify, Files(file), nameDrum: (_, _) => SoundKind.Kick,
            timing: Fast, sleep: _ => { }, soundFile: (_, _) => null).Run();
        Assert.Equal(SoundFamily.Unsure, result!.Items.First(i => i.Index == 1).Family);
    }

    /// Un nom que l'Organiser a pu donner est vérifié à l'écoute ; un synthé de mélodies n'est jamais drums ni FX.
    [Fact]
    public void GeneratedNamesAreHeardAndSynthsStayMelodies()
    {
        var names = new[] { "Pad", "Mélodie 3", "Serum 2", "Snare", "808" };
        var link = Project(names);
        var audio = new FakeAudio(link) { Parts = { [1] = Tone(SoundFamily.Drums), [2] = Tone(SoundFamily.Drums) } };
        var session = new OrganizerSession(link, audio, Classify, Files(FlpSample.Sample(names: names)),
            nameDrum: (_, _) => SoundKind.Kick, timing: Fast, sleep: _ => { });
        var (result, _) = session.Run();
        Assert.Equal(SoundFamily.Drums, result!.Items.First(i => i.Index == 1).Family);   // « Mélodie 3 » contredit par l'écoute
        Assert.Equal(SoundFamily.Melody, result.Items.First(i => i.Index == 2).Family);
        Assert.Contains("c2:synthe", session.Diagnostics.Rules);
    }

    /// Tout muet et rien de nommé : `NoSound` (la capture ne reçoit rien).
    [Fact]
    public void SilentCaptureWithoutNamesIsNoSound()
    {
        var names = new[] { "Son 0", "Son 1", "Son 2", "Son 3", "Son 4" };
        var link = Project(names);
        var audio = new FakeAudio(link);
        var (_, error) = new OrganizerSession(link, audio, Classify, Files(FlpSample.Sample(names: names)),
            timing: Fast, sleep: _ => { }).Run();
        Assert.Equal(OrganizerError.NoSound, error);
        Assert.Equal(1, audio.Stopped);
        Assert.Equal("restore", link.Log[^1]);
    }

    /// Le fichier enregistré n'est pas le projet ouvert (autres sons) : rien n'est touché, la raison est dite.
    [Fact]
    public void OtherProjectFileStopsEverything()
    {
        var link = new FakeOrganizerLink
        {
            Channels = new() { new ChannelInfo(0, 2, 0, Red, "Pad"), new ChannelInfo(1, 2, 0, Red, "Kick") },
        };
        var audio = new FakeAudio(link);
        var session = new OrganizerSession(link, audio, Classify, Files(FlpSample.Sample(), Path.Combine(Path.GetTempPath(), "projets", "Autre.flp")),
            timing: Fast, sleep: _ => { });
        var (_, error) = session.Run();
        Assert.NotNull(error);
        Assert.True(error!.Is(OrganizerError.Kinds.Failed));
        Assert.Contains("rien n'a été touché", error.UserMessage);
        Assert.Equal("canaux 5/2", session.Diagnostics.File);
        Assert.Equal(0, audio.Started);   // rien n'est écouté

        var unsaved = new OrganizerSession(link, audio, Classify, new ProjectFileAccess
        {
            Save = _ => throw OrganizerError.Failed("pas enregistré"),
            Open = _ => false,
        }, timing: Fast, sleep: _ => { });
        Assert.Equal(OrganizerError.Failed("pas enregistré"), unsaved.Run().Error);
    }

    /// Fichier du projet introuvable : l'erreur le dit (bouton « Choisir le fichier… »), et le diagnostic donne ce que
    /// la recherche a vu, en nombres.
    [Fact]
    public void ProjectFileNotFoundIsDiagnosed()
    {
        var link = new FakeOrganizerLink { Channels = new() { new ChannelInfo(0, 2, 0, Red, "Pad") } };
        var audio = new FakeAudio(link);
        var session = new OrganizerSession(link, audio, Classify, new ProjectFileAccess
        {
            Save = _ => throw OrganizerError.ProjectNotFound,
            Open = _ => false,
            Search = () => "fenêtres=1 noms=0 candidats=0 récents=0 parcourus=12 pris=aucun",
        }, timing: Fast, sleep: _ => { });
        Assert.Equal(OrganizerError.ProjectNotFound, session.Run().Error);
        Assert.Equal("introuvable", session.Diagnostics.File);
        Assert.Contains("recherche fenêtres=1 noms=0 candidats=0", session.Diagnostics.Text);
        Assert.Contains("Choisir le fichier", OrganizerError.ProjectNotFound.UserMessage);
        Assert.Equal(0, audio.Started);
    }

    /// Un ancien script (v13 ou avant) : rien n'est touché, FL doit être redémarré.
    [Fact]
    public void OldScriptAsksForARestart()
    {
        var link = Project(FlpSample.DefaultNames);
        link.V14 = false;
        var audio = new FakeAudio(link);
        var (_, error) = new OrganizerSession(link, audio, Classify, Files(FlpSample.Sample()), timing: Fast, sleep: _ => { }).Run();
        Assert.Equal(OrganizerError.OutdatedScript, error);
        Assert.Equal(0, audio.Started);
        Assert.DoesNotContain(link.Log, l => l.StartsWith("solo") || l.StartsWith("speed"));
    }

    /// Retour de l'utilisateur : « j'avais dit non pour l'accélérateur de BPM ». Rien ne change le tempo du projet.
    [Fact]
    public void TempoIsNeverChanged()
    {
        var link = Project(FlpSample.DefaultNames);
        var audio = new FakeAudio(link) { Parts = { [2] = Tone(SoundFamily.Melody) } };
        new OrganizerSession(link, audio, Classify, Files(FlpSample.Sample()), timing: Fast, sleep: _ => { }).Run();
        Assert.DoesNotContain(link.Log, l => l.StartsWith("speed"));
    }

    /// Échap pendant l'écoute : l'analyse s'arrête, FL est toujours remis comme avant, chaque note coupée.
    [Fact]
    public void CancelAlwaysRestores()
    {
        var names = new[] { "Son 0", "Son 1", "Son 2", "Son 3", "Son 4" };
        var link = Project(names);
        var audio = new FakeAudio(link);
        var pressed = 0;
        var session = new OrganizerSession(link, audio, Classify, Files(FlpSample.Sample(names: names)), timing: Fast,
            sleep: _ => { }, escape: () => ++pressed > 3);
        Assert.Equal(OrganizerError.Cancelled, session.Run().Error);
        Assert.Equal("restore", link.Log[^1]);
        Assert.Equal(1, audio.Stopped);
        var on = link.Log.Count(l => l.StartsWith("note ") && !l.EndsWith(" 0"));
        var off = link.Log.Count(l => l.StartsWith("note ") && l.EndsWith(" 0"));
        Assert.Equal(on, off);
    }

    [Fact]
    public void PureHelpers()
    {
        Assert.True(Same.Maps(new Dictionary<int, int> { [1] = 1, [5] = 3 },
            OrganizerSession.Homes(new Dictionary<int, HashSet<int>> { [2] = new() { 5, 1 }, [0] = new() { 1 } })));   // le premier pattern où le son joue
        Assert.Equal("piste1:c1 piste4:c0,c2",
            OrganizerSession.SoundMap(new Dictionary<int, HashSet<int>> { [3] = new() { 2, 0 }, [0] = new() { 1 } }, "piste"));   // des numéros seulement, dans l'ordre
        var channels = new[]
        {
            new ChannelInfo(0, 2, 0, Red, "Son 0"), new ChannelInfo(1, 2, 0, Red, "Son 1"),
            new ChannelInfo(2, ChannelInfo.AudioClipType, 0, Red, "Son 2"), new ChannelInfo(3, ChannelInfo.AutomationType, 0, Red, "Son 3"),
        };
        Assert.Equal(new[] { 1 }, OrganizerSession.Unused(channels, new HashSet<int> { 1, 2, 3 }, new HashSet<int>(), false).ToArray());
        Assert.Equal(new[] { 1 }, OrganizerSession.Unused(channels, new HashSet<int> { 0, 1 }, new HashSet<int> { 0 }, true).ToArray());   // entendu : jamais de côté
        Assert.Equal(new[] { 1 }, OrganizerSession.Unused(channels, null, new HashSet<int> { 0 }, true).ToArray());
        Assert.Empty(OrganizerSession.Unused(channels, null, new HashSet<int> { 0 }, false));
        Assert.Empty(OrganizerSession.Unused(channels, null, new HashSet<int>(), true));   // rien relevé
        Assert.Equal(-180, OrganizerSession.PeakDB(Array.Empty<float>()));
        Assert.Equal(-20, OrganizerSession.PeakDB(new[] { 0.05f, -0.1f }), 3);
    }
}
