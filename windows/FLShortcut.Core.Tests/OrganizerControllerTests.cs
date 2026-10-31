// Organiser : le contrôleur de la fenêtre (sans fenêtre), sur un faux FL et un faux disque. Miroir des essais de
// Tests/FLShortcutTests/OrganizerWindowTests.swift (analyse sur le fichier, la seule de Windows).
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using FLShortcut.Core.Organizer;
using Xunit;

namespace FLShortcut.Core.Tests;

public sealed class OrganizerControllerTests
{
    private static readonly RgbColor Gray = new(9, 9, 9);

    /// Les attentes (« réessayer dans 2 s ») mises de côté : l'essai les lance quand il veut.
    private sealed class Later
    {
        public readonly List<Action> Pending = new();
        public void Run()
        {
            var now = Pending.ToList();
            Pending.Clear();
            foreach (var a in now) a();
        }
    }

    /// Le projet de test (FlpSample) dans un faux FL : Pad, Kick, ZENOLOGY, Snare, 808.
    private static (FakeOrganizerLink Link, FakeDisk Disk) Project(string[]? names = null)
    {
        names ??= FlpSample.DefaultNames;
        var link = new FakeOrganizerLink
        {
            Channels = names.Select((n, i) => new ChannelInfo(i, 2, i + 1, Gray, n)).ToList(),
            PatternList = new[] { "Mélodie", "Drums", "Pattern 3", "Vide" }.Select((n, i) => new PatternInfo(i, Gray, n)).ToList(),
            Mixer = Enumerable.Range(0, 40).Select(i => new MixerTrackInfo(i, Gray, i == 0 ? "Master" : $"Insert {i}")).ToList(),
            Playlist = Enumerable.Range(0, 12).Select(i => new PlaylistTrackInfo(i, false, Gray, $"Track {i + 1}")).ToList(),
        };
        var disk = new FakeDisk { Link = link };
        disk.Files[disk.Original] = FlpSample.Sample(names: names);
        return (link, disk);
    }

    private static OrganizerEnvironment Env(FakeOrganizerLink link, FakeDisk disk, Later later, Func<OrganizerLinkState>? prepare = null,
        Func<bool>? install = null, FakeAudio? audio = null, Func<CorrectionsIA?>? corrections = null, Action<string>? share = null,
        Action<string, string>? team = null, Func<IReadOnlyList<SoundFamily>>? order = null, Action<IReadOnlyList<SoundFamily>>? saveOrder = null,
        Action<string>? copy = null, List<(string, string)>? made = null) => new()
    {
        Link = () => link,
        Audio = () => (audio ?? new FakeAudio(link), null),
        Classify = () => (samples, _) => samples.Length == 0 ? (SoundFamily.Unsure, 0, "silence") : (SoundFamily.Drums, 0.9, "faux"),
        MoveUp = _ => link.MoveSelectedUp,
        MoveLeft = _ => link.MoveSelectedLeft,
        ProjectFiles = () => disk.Access,
        Timing = new OrganizerSession.Timing { Listen = 0.01, TestNote = 0.01, Tail = 0.01, Slice = 0.01 },
        Sleep = _ => { },
        PrepareLink = prepare ?? (() => new OrganizerLinkState.Ready(0)),
        InstallLink = install ?? (() => true),
        WaitInterval = 0.05,
        After = (_, action) => later.Pending.Add(action),
        DeleteSelected = _ => link.DeleteSelected,
        Corrections = corrections ?? (() => null),
        ShareCorrection = share ?? (_ => { }),
        SendFeedback = team ?? ((_, _) => { }),
        LoadFamilyOrder = order ?? (() => SoundFamilies.Order),
        SaveFamilyOrder = saveOrder ?? (_ => { }),
        Copy = copy ?? (_ => { }),
        About = () => "app 1.0 · Windows",
        CopyMade = (o, c) => made?.Add((o, c)),
    };

    [Fact]
    public void WholeProjectOrganizedInACopyThenUndone()
    {
        var (link, disk) = Project();
        var made = new List<(string, string)>();
        var closings = 0;
        var controller = new OrganizerController(Env(link, disk, new Later(), made: made)) { OnClose = () => closings++ };
        controller.Start();
        Assert.IsType<OrganizerPhase.Preview>(controller.Phase);
        Assert.Equal("Organiser", controller.Title);
        // Pad sans note (supprimé), ZENOLOGY muet : « À vérifier ».
        Assert.Equal(new[] { SoundFamily.Bass, SoundFamily.Drums, SoundFamily.Unsure }, controller.PresentFamilies);
        Assert.Equal(new[] { "Kick", "Snare" }, controller.Members(SoundFamily.Drums).Select(m => m.NewName ?? m.Name));
        Assert.True(controller.OrganizesCopy);
        Assert.Contains(controller.Summary, l => l.Contains("Playlist rangée dans une copie"));

        controller.Apply();
        var applied = Assert.IsType<OrganizerPhase.Applied>(controller.Phase);
        Assert.True(applied.Error is null, controller.DiagnosticText);
        var copy = Path.Combine(Path.GetDirectoryName(disk.Original)!, "Mon son_2.flp");
        Assert.Equal(new[] { (disk.Original, copy) }, made);
        Assert.Contains("Mon son_2.flp", controller.DoneText);
        Assert.True(controller.CanUndo);
        Assert.True(controller.CanGiveFeedback);

        controller.Undo();
        Assert.Equal(new OrganizerPhase.Undone(null), controller.Phase);
        Assert.Equal(disk.Original, disk.Opened[^1]);   // l'original rouvert
        controller.Close();
        controller.Close();
        Assert.Equal(1, closings);
    }

    [Fact]
    public void SetupWhenLinkMissingThenWaitsAndGoesOn()
    {
        var (link, disk) = Project();
        var later = new Later();
        var installed = false;
        var controller = new OrganizerController(Env(link, disk, later,
            prepare: () => installed ? new OrganizerLinkState.Ready(0) : new OrganizerLinkState.NotInstalled(),
            install: () => installed = true));
        controller.Start();
        Assert.IsType<OrganizerPhase.Setup>(controller.Phase);
        Assert.True(controller.CanRetry);
        Assert.Empty(link.Log);   // rien n'est envoyé à FL
        controller.InstallLink();
        Assert.Equal(new OrganizerPhase.Waiting(OrganizerWait.RestartFl), controller.Phase);
        later.Run();   // l'essai d'après, tout seul
        Assert.IsType<OrganizerPhase.Preview>(controller.Phase);
        Assert.False(controller.CanRetry);
    }

    [Fact]
    public void WaitsAreSortedFromRealFailures()
    {
        Assert.Equal(OrganizerWait.NoResponse, OrganizerController.WaitReason(OrganizerError.NoResponse));
        Assert.Equal(OrganizerWait.WrongInput, OrganizerController.WaitReason(OrganizerError.NoResponse, wrongInput: true));
        Assert.Equal(OrganizerWait.RestartFl, OrganizerController.WaitReason(OrganizerError.OutdatedScript));
        Assert.Equal(OrganizerWait.OpenFl, OrganizerController.WaitReason(OrganizerError.FlClosed));
        Assert.Equal(OrganizerWait.StopPlayback, OrganizerController.WaitReason(OrganizerError.Refused(4)));
        Assert.Null(OrganizerController.WaitReason(OrganizerError.Cancelled));

        // Un ancien script : l'Organiser attend que FL redémarre, puis continue tout seul.
        var (link, disk) = Project();
        link.V14 = false;
        var later = new Later();
        var controller = new OrganizerController(Env(link, disk, later));
        controller.Start();
        Assert.Equal(new OrganizerPhase.Waiting(OrganizerWait.RestartFl), controller.Phase);
        link.V14 = true;
        later.Run();
        Assert.IsType<OrganizerPhase.Preview>(controller.Phase);
    }

    /// Fichier du projet introuvable : « Choisir le fichier… » le fait montrer, puis l'analyse repart toute seule.
    [Fact]
    public void ProjectNotFoundAsksForTheFile()
    {
        var (link, _) = Project();
        var saves = 0;
        var asked = 0;
        var env = Env(link, new FakeDisk(), new Later());
        env = new OrganizerEnvironment
        {
            Link = env.Link, Audio = env.Audio, Classify = env.Classify, MoveUp = env.MoveUp, Sleep = env.Sleep, After = env.After,
            ProjectFiles = () => new ProjectFileAccess
            {
                Save = _ => { saves++; throw OrganizerError.ProjectNotFound; },
                Open = _ => false,
            },
            ChooseProject = () => { asked++; return true; },
        };
        var controller = new OrganizerController(env);
        controller.Start();
        Assert.Equal(new OrganizerPhase.Failed(OrganizerError.ProjectNotFound.UserMessage), controller.Phase);
        Assert.True(controller.ProjectMissing);
        controller.ChooseProject();
        Assert.Equal(1, asked);
        Assert.Equal(2, saves);
        Assert.True(controller.ProjectMissing);
    }

    /// Rangés d'après leur nom : l'aperçu montre ce qu'est chaque son et le nom qu'il prendra ; changé à la main, il suit.
    [Fact]
    public void PreviewShowsWhatEachSoundIs()
    {
        var (link, disk) = Project(new[] { "Pad", "BEAM KICK", "ZENOLOGY", "@MEH CLAP", "ZEBRA 808" });
        var controller = new OrganizerController(Env(link, disk, new Later()));
        controller.Start();
        Assert.Equal(new[] { "BEAM KICK", "@MEH CLAP" }, controller.Members(SoundFamily.Drums).Select(m => m.Name));
        Assert.Equal(new SoundKind?[] { SoundKind.Kick, SoundKind.Clap }, controller.Members(SoundFamily.Drums).Select(m => m.Kind));
        controller.SetFamily(1, SoundFamily.Bass);
        Assert.Null(controller.KindOf(1));
        controller.SetKind(1, SoundKind.Kick);
        Assert.Equal(SoundFamily.Drums, controller.Families[1]);
        controller.SetOptions(controller.Options with { Rename = false });
        Assert.All(controller.Members(SoundFamily.Drums), m => Assert.Null(m.NewName));
    }

    /// Places dans le Mixer, noms écrits, ordre des familles glissées (gardé à l'application).
    [Fact]
    public void PlacesNamesAndFamilyOrder()
    {
        var (link, disk) = Project(new[] { "Pad", "BEAM KICK", "ZENOLOGY", "@MEH CLAP", "ZEBRA 808" });
        IReadOnlyList<SoundFamily>? saved = null;
        var controller = new OrganizerController(Env(link, disk, new Later(), order: () => new[] { SoundFamily.Drums },
            saveOrder: o => saved = o));
        Assert.Equal(new[] { SoundFamily.Drums, SoundFamily.Vocals, SoundFamily.Melody, SoundFamily.Bass, SoundFamily.Fx, SoundFamily.Unsure },
            controller.Options.FamilyOrder);
        controller.Start();
        Assert.Equal(SoundFamily.Drums, controller.PresentFamilies[0]);
        controller.SetSlot(1, 20);
        Assert.Equal(20, controller.Members(SoundFamily.Drums)[0].Slot);
        Assert.True(controller.Members(SoundFamily.Drums)[0].Pinned);
        controller.SetSlot(1, null);
        controller.SetMixerStart(SoundFamily.Drums, 30);
        Assert.Equal(30, controller.MixerRange(SoundFamily.Drums)?.First);   // Kick, Clap, 808, bus
        Assert.True(controller.PlacesChosen);
        controller.AutoArrange();
        Assert.False(controller.PlacesChosen);
        controller.SetName(1, "  Boom  ");
        Assert.Equal("Boom", controller.Members(SoundFamily.Drums)[0].NewName);
        Assert.True(controller.Members(SoundFamily.Drums)[0].Written);
        controller.SetName(1, "");
        Assert.False(controller.Names.ContainsKey(1));
        controller.MoveFamily(SoundFamily.Bass, SoundFamily.Drums);
        Assert.Equal(SoundFamily.Bass, controller.PresentFamilies[0]);
        controller.ShiftFamily(SoundFamily.Unsure, -1);
        Assert.Equal(new[] { SoundFamily.Bass, SoundFamily.Unsure, SoundFamily.Drums }, controller.PresentFamilies);
        Assert.Equal(new[] { SoundFamily.Melody, SoundFamily.Drums, SoundFamily.Vocals },
            OrganizerController.Moving(SoundFamily.Vocals, SoundFamily.Drums, new[] { SoundFamily.Vocals, SoundFamily.Melody, SoundFamily.Drums }));
        controller.Apply();
        Assert.Equal(new[] { SoundFamily.Bass, SoundFamily.Unsure, SoundFamily.Drums }, saved!.Take(3));
    }

    /// L'IA apprend de ses erreurs : un son changé dans l'aperçu est retenu sans rien demander (pas partagé sans
    /// accord) ; « Pas content ? » retient ses corrections et, la case cochée, les partage (des nombres, jamais un nom).
    [Fact]
    public void CorrectionsAreLearnedThenShared()
    {
        var names = new[] { "Son 0", "Son 1", "Son 2", "Son 3", "Son 4" };
        var (link, disk) = Project(names);
        var audio = new FakeAudio(link) { Parts = { [1] = new float[64].Select(_ => 0.3f).ToArray(), [2] = new float[64].Select(_ => 0.25f).ToArray() } };
        bool? share = null;
        var stored = new Dictionary<string, byte[]>();
        var store = new CorrectionsIA(Path.Combine(Path.GetTempPath(), Guid.NewGuid() + ".json"), () => share, s => share = s,
            (p, b) => stored[p] = b, p => stored.TryGetValue(p, out var b) ? b : null);
        var shared = new List<string>();
        var team = new List<(string, string)>();
        var env = Env(link, disk, new Later(), audio: audio, corrections: () => store, share: shared.Add, team: (m, d) => team.Add((m, d)));
        env = new OrganizerEnvironment
        {
            Link = env.Link, Audio = env.Audio, Classify = env.Classify, MoveUp = env.MoveUp, MoveLeft = env.MoveLeft, Sleep = env.Sleep,
            After = env.After, ProjectFiles = env.ProjectFiles, Timing = env.Timing, DeleteSelected = env.DeleteSelected,
            Corrections = env.Corrections, ShareCorrection = env.ShareCorrection, SendFeedback = env.SendFeedback,
            Fingerprint = () => (samples, _) =>
            {
                var empreinte = new float[ClasseurSons.TailleEmpreinte];
                empreinte[(int)Math.Round(samples[0] * 100)] = 1;
                return new SoundPrint(new[] { new float[ClasseurSons.TailleMesures] }, empreinte, SoundFamily.Drums, null);
            },
        };
        var controller = new OrganizerController(env);
        controller.Start();
        Assert.Equal(new[] { 1, 2 }, controller.Correctable.Select(i => i.Index));
        controller.SetKind(2, SoundKind.Bass808);
        controller.Apply();
        Assert.Equal(1, controller.Learned);
        Assert.Equal(1, store.Nombre);
        Assert.Null(store.Partage);
        Assert.Empty(shared);

        var feedback = new OrganizerFeedback { Other = true, OtherText = "Les clips de voix sont trop bas.", Share = true };
        feedback.Reasons.Add(OrganizerFeedback.Reason.Kind);
        feedback.Reasons.Add(OrganizerFeedback.Reason.Playlist);
        feedback.Fixes[1] = new OrganizerFeedback.Fix(SoundFamily.Drums, SoundKind.Snare);
        controller.SubmitFeedback(feedback);
        Assert.Equal(2, controller.Learned);
        Assert.True(store.Partage);
        Assert.False(controller.CanGiveFeedback);
        var body = Assert.Single(shared);
        var json = JsonNode.Parse(body)!.AsObject();
        Assert.Equal("drums", json["famille"]?.GetValue<string>());
        Assert.Equal("snare", json["sorte"]?.GetValue<string>());
        Assert.DoesNotContain("Son 1", body);
        var (message, diagnostic) = Assert.Single(team);
        Assert.Contains("Playlist", message);
        Assert.Contains("trop bas", message);
        Assert.DoesNotContain("Son 1", diagnostic);
    }

    /// « Copier le diagnostic » : versions, étape et ce que l'écoute a fait, jamais un nom de son.
    [Fact]
    public void DiagnosticIsCopiedWithoutNames()
    {
        var names = new[] { "Secret Serum", "Son 1", "Son 2", "Son 3", "Son 4" };
        var (link, disk) = Project(names);
        var copied = new List<string>();
        var controller = new OrganizerController(Env(link, disk, new Later(), copy: copied.Add));
        controller.Start();
        Assert.Equal(new OrganizerPhase.Failed(OrganizerError.NoSound.UserMessage), controller.Phase);
        controller.CopyDiagnostic();
        var text = Assert.Single(copied);
        Assert.Contains("app 1.0 · Windows", text);
        Assert.Contains("étape=échec", text);
        Assert.Contains("capture=", text);
        Assert.DoesNotContain("Secret", text);
        Assert.True(controller.Copied);
    }

    /// Écrans de démonstration (photos de la CI), avec les sons d'exemple.
    [Fact]
    public void DemoScreens()
    {
        var (link, disk) = Project();
        var controller = new OrganizerController(Env(link, disk, new Later()));
        foreach (var screen in new[] { "installer", "attente", "aide", "ecoute", "apercu", "fini" })
        {
            controller.ShowDemo(screen);
            if (screen == "apercu")
            {
                Assert.IsType<OrganizerPhase.Preview>(controller.Phase);
                Assert.NotEmpty(controller.PresentFamilies);
                Assert.NotEmpty(controller.Summary);
            }
        }
        Assert.Equal(new OrganizerPhase.Applied(null), controller.Phase);
        Assert.Empty(link.Log);
    }

    /// Tout texte affiché par le cœur Windows a son anglais (un Windows en anglais ne verrait jamais du français).
    [Fact]
    public void EveryTextHasItsEnglish()
    {
        var root = Path.GetDirectoryName(typeof(OrganizerControllerTests).Assembly.Location)!;
        while (!File.Exists(Path.Combine(root, "PROTOCOL.md"))) root = Path.GetDirectoryName(root)!;
        var call = new Regex("Loc\\.[TF]\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"", RegexOptions.CultureInvariant);
        var missing = new List<string>();
        // Le cœur et l'appli (ses textes passent aussi par Loc).
        var files = new[] { "FLShortcut.Core", "FLShortcut.App" }
            .SelectMany(d => Directory.EnumerateFiles(Path.Combine(root, "windows", d), "*.cs", SearchOption.AllDirectories));
        foreach (var file in files)
        {
            if (file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")) continue;
            foreach (Match m in call.Matches(File.ReadAllText(file)))
            {
                var key = Regex.Unescape(m.Groups[1].Value);
                if (!Loc.Has(key)) missing.Add($"{Path.GetFileName(file)} : {key}");
            }
        }
        Assert.True(missing.Count == 0, "Textes sans anglais :\n" + string.Join("\n", missing));
    }

    /// Les familles de l'aperçu sur deux colonnes (comme le Mac) : dans l'ordre, coupées là où les colonnes ont la
    /// hauteur la plus proche ; une seule colonne si la fenêtre est étroite ou s'il n'y a qu'une famille.
    [Fact]
    public void FamilyColumns_LikeTheMac()
    {
        var sizes = new Dictionary<string, int> { ["Drums"] = 3, ["Basse"] = 1, ["Mélodies"] = 2, ["Voix"] = 1, ["FX"] = 1 };
        var order = new[] { "Basse", "Drums", "FX", "Mélodies", "Voix" };
        var two = OrganizerController.FamilyColumns(order, 2, f => sizes[f]);
        Assert.Equal(new[] { "Basse", "Drums" }, two[0]);
        Assert.Equal(new[] { "FX", "Mélodies", "Voix" }, two[1]);
        Assert.Equal(order, two.SelectMany(c => c));
        Assert.Equal(order, Assert.Single(OrganizerController.FamilyColumns(order, 1, f => sizes[f])));
        Assert.Equal(new[] { "Drums" }, Assert.Single(OrganizerController.FamilyColumns(new[] { "Drums" }, 2, f => sizes[f])));
    }
}
