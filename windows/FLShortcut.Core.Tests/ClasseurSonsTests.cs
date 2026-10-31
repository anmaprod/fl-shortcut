// IA intégrée de l'Organiser : tranches comme YAMNet, son ramené à 16 kHz, même seuil que le modèle exporté, modèle
// ONNX présent et qui répond comme à l'apprentissage sur des sons jamais entendus (Tests/FLShortcutTests/Fixtures),
// règles de l'Organiser, corrections. Miroir de Tests/FLShortcutTests/ClasseurSonsTests.swift.
using System.Text.Json.Nodes;
using FLShortcut.Core.Organizer;
using Xunit;

namespace FLShortcut.Core.Tests;

public class ClasseurSonsTests
{
    private static string Root
    {
        get
        {
            var dir = AppContext.BaseDirectory;
            while (!File.Exists(Path.Combine(dir, "PROTOCOL.md"))) dir = Path.GetDirectoryName(dir)!;
            return dir;
        }
    }

    private static string Fixtures => Path.Combine(Root, "Tests", "FLShortcutTests", "Fixtures");
    private static string ModelPath => Path.Combine(Root, "ia", "modele", ClasseurSons.NomFichier);

    private static SampleSound Lire(string nom) => SampleAudio.ReadPcm(Path.Combine(Fixtures, nom))
                                                   ?? throw new InvalidOperationException(nom);

    private static ClasseurSons Classeur() => ClasseurSons.Ouvrir(ModelPath) ?? throw new InvalidOperationException("modèle");

    [Fact]
    public void TranchesCommeYamnet()
    {
        const int t = ClasseurSons.Tranche, p = ClasseurSons.Pas;
        Assert.Empty(ClasseurSons.Tranches(Array.Empty<float>()));
        Assert.Single(ClasseurSons.Tranches(Enumerable.Repeat(0.1f, 100).ToArray()));
        Assert.Single(ClasseurSons.Tranches(Enumerable.Repeat(0.1f, t).ToArray()));
        Assert.Equal(2, ClasseurSons.Tranches(Enumerable.Repeat(0.1f, t + 1).ToArray()).Count);
        Assert.Equal(2, ClasseurSons.Tranches(Enumerable.Repeat(0.1f, t + p).ToArray()).Count);
        Assert.Equal(3, ClasseurSons.Tranches(Enumerable.Repeat(0.1f, t + p + 1).ToArray()).Count);
        Assert.All(ClasseurSons.Tranches(Enumerable.Repeat(0.1f, 100).ToArray()), x => Assert.Equal(t, x.Length));
    }

    [Fact]
    public void SonLongGardeLesTranchesLesPlusFortes()
    {
        var son = Enumerable.Repeat(0.001f, ClasseurSons.Tranche + ClasseurSons.Pas * 40).ToArray();
        var fort = ClasseurSons.Pas * 20;
        for (var i = fort; i < fort + ClasseurSons.Tranche; i++) son[i] = 0.8f;
        var lot = ClasseurSons.Tranches(son);
        Assert.Equal(ClasseurSons.MaxTranches, lot.Count);
        Assert.Contains(lot, x => x.All(v => v == 0.8f));
    }

    [Fact]
    public void ReechantillonnageEtCrete()
    {
        var la = Enumerable.Range(0, 44_100).Select(i => (float)(0.2 * Math.Sin(2 * Math.PI * 440 * i / 44_100))).ToArray();
        Assert.InRange(Resampler.ToRate(la, 44_100, 16_000).Length, 16_000 - 160, 16_000 + 160);
        Assert.Equal(la.Length, Resampler.ToRate(la, 16_000, 16_000).Length);
        Assert.Empty(Resampler.ToRate(Array.Empty<float>(), 44_100, 16_000));
        Assert.InRange(ClasseurSons.Normaliser(la).Max(Math.Abs), 0.7 - 1e-4, 0.7 + 1e-4);
        // Le la reste un la, au même niveau (pas de repliement, pas de perte).
        var resampled = Resampler.ToRate(la, 44_100, 16_000);
        var f = SoundFeatures.Measure(resampled.Concat(resampled).Concat(resampled).ToArray(), 16_000);
        Assert.InRange(f.MedianF0, 440 * 0.98, 440 * 1.02);
        Assert.InRange(resampled.Skip(1000).Take(10_000).Max(Math.Abs), 0.19, 0.21);
    }

    /// Même seuil, mêmes tranches et mêmes classes que le modèle exporté (ia/modele/classeur_sons.json).
    [Fact]
    public void ReglagesCommeLeModeleExporte()
    {
        var meta = JsonNode.Parse(File.ReadAllText(Path.Combine(Root, "ia", "modele", "classeur_sons.json")))!.AsObject();
        Assert.Equal(ClasseurSons.SeuilVoix, meta["seuil_voix"]!.GetValue<double>());
        Assert.Equal(ClasseurSons.Tranche, meta["tranche"]!.GetValue<int>());
        Assert.Equal(ClasseurSons.Pas, meta["pas"]!.GetValue<int>());
        Assert.Equal(ClasseurSons.MaxTranches, meta["max_tranches"]!.GetValue<int>());
        Assert.Equal(Enum.GetValues<ClasseurFamille>().Length, meta["familles"]!.AsArray().Count);
        Assert.Equal(ClasseurSons.SortesModele.Select(k => k.Raw()), meta["sortes"]!.AsArray().Select(n => n!.GetValue<string>()));
        Assert.Equal(ClasseurSons.VersionModele, meta["version"]!.GetValue<int>());
    }

    [Fact]
    public void SortesCommeLApercu()
    {
        Assert.Equal(ClasseurSons.SortesModele.Length, ClasseurSons.SortesModele.Distinct().Count());
        Assert.Equal(new[] { SoundKind.Backing, SoundKind.Synth }, SoundKinds.All.Except(ClasseurSons.SortesModele));
    }

    [Fact]
    public void Decision()
    {
        var sortes = new double[ClasseurSons.SortesModele.Length];
        int Rang(SoundKind k) => Array.IndexOf(ClasseurSons.SortesModele, k);
        sortes[Rang(SoundKind.Choir)] = 0.3;
        sortes[Rang(SoundKind.Snare)] = 0.2;
        sortes[Rang(SoundKind.Clap)] = 0.1;
        sortes[Rang(SoundKind.Bass808)] = 0.05;
        sortes[Rang(SoundKind.Reese)] = 0.15;
        var a = ClasseurSons.Decider(new[] { 0.3, 0.1, 0.0, 0.5, 0.1 }, 0.9, sortes);
        Assert.Equal(ClasseurFamille.Voix, a.Famille);
        Assert.Equal(SoundKind.Choir, a.Sorte(SoundFamily.Vocals)?.Kind);
        Assert.InRange(a.Sorte(SoundFamily.Vocals)!.Value.Part, 1 - 1e-9, 1 + 1e-9);
        a = ClasseurSons.Decider(new[] { 0.3, 0.1, 0.0, 0.5, 0.1 }, 0.1, sortes);
        Assert.Equal(ClasseurFamille.Drums, a.Famille);
        Assert.Equal(SoundKind.Snare, a.Sorte(SoundFamily.Drums)?.Kind);
        Assert.InRange(a.Sorte(SoundFamily.Drums)!.Value.Part, 2.0 / 3 - 1e-9, 2.0 / 3 + 1e-9);
        Assert.Equal(SoundKind.Reese, a.Sorte(SoundFamily.Bass)?.Kind);
        Assert.Null(a.Sorte(SoundFamily.Melody));
        Assert.Null(a.Sorte(SoundFamily.Unsure));
    }

    /// Sons jamais entendus à l'apprentissage : la bonne famille, la même sorte et les mêmes probabilités que le modèle
    /// ONNX de l'apprentissage (essais_app.py).
    [Fact]
    public void SonsJamaisEntendus()
    {
        using var classeur = Classeur();
        var attendus = JsonNode.Parse(File.ReadAllText(Path.Combine(Fixtures, "attendus.json")))!.AsObject();
        Assert.NotEmpty(attendus);
        var noms = new[] { "voix", "melodie", "basse", "drums", "fx" };
        foreach (var (fichier, node) in attendus.OrderBy(kv => kv.Key, StringComparer.Ordinal))
        {
            var a = node!.AsObject();
            var son = Lire(fichier);
            var avis = classeur.Avis(son.Samples, son.Rate) ?? throw new InvalidOperationException(fichier);
            Assert.True(a["famille_voulue"]!.GetValue<string>() == noms[(int)avis.Famille], $"{fichier} : mauvaise famille ({noms[(int)avis.Famille]})");
            var voix = a["voix_max"]!.GetValue<double>();
            Assert.True(Math.Abs(avis.VoixMax - voix) <= 0.08, $"{fichier} : voix {avis.VoixMax:F3} au lieu de {voix:F3}");
            var famille = ClasseurSons.Famille(avis.Famille);
            if (a["sorte"]?.GetValue<string>() is { } sorte)
                Assert.True(sorte == avis.Sorte(famille)?.Kind.Raw(), $"{fichier} : sorte {avis.Sorte(famille)?.Kind.Raw()} au lieu de {sorte}");
        }
    }

    [Fact]
    public void SorteParLIaIntegree()
    {
        var classeur = ClasseurSons.Partage(ModelPath) ?? throw new InvalidOperationException("modèle");
        Assert.Same(classeur, ClasseurSons.Partage(ModelPath));
        var son = Lire("voix-parole.wav");
        var avis = classeur.Avis(son.Samples, son.Rate)!;
        Assert.Same(avis, classeur.Avis(son.Samples, son.Rate));
        var nommer = OrganizerSession.LiveKindNamer(classeur, null);
        var attendue = avis.Sorte(SoundFamily.Vocals)!.Value;
        Assert.Equal(attendue.Part >= ClasseurSons.PartMin ? attendue.Kind : null, nommer(son.Samples, son.Rate, SoundFamily.Vocals));
        Assert.Null(nommer(son.Samples, son.Rate, SoundFamily.Unsure));
        Assert.Equal(SoundFamily.Drums, nommer(son.Samples, son.Rate, SoundFamily.Drums)?.Family() ?? SoundFamily.Drums);
    }

    [Fact]
    public void RegleVoixDeLIaIntegree()
    {
        var ton = Enumerable.Range(0, 44_100).Select(i => (float)(0.5 * Math.Sin(2 * Math.PI * 220 * i / 44_100))).ToArray();
        var mesures = SoundFeatures.Measure(ton, 44_100);
        var ia = new AILabels(voice: 0.2) { EmbeddedVoice = 0.95 };
        var voix = FamilyFusion.DecideWithRule(mesures, ia);
        Assert.Equal(SoundFamily.Vocals, voix.Family);
        Assert.Equal("voix-iv", voix.Rule);
        ia.EmbeddedVoice = 0.05;
        Assert.NotEqual(SoundFamily.Vocals, FamilyFusion.DecideWithRule(mesures, ia).Family);
        ia.EmbeddedVoice = null;
        Assert.NotEqual(SoundFamily.Vocals, FamilyFusion.DecideWithRule(mesures, ia).Family);
    }

    [Fact]
    public void LIaIntegreeDansLesReglesDAvant()
    {
        static SoundFeatures F(double len, double low, double flat, double high = 0, double f0 = 0) => new()
        {
            PeakDB = -6, NoteLength = len, PitchedFraction = f0 > 0 ? 0.6 : 0, MedianF0 = f0, LowRatio = low, Flatness = flat,
            OnsetsPerSecond = 4, DistinctPitches = 1, Vibrato = 0, HighRatio = high,
        };
        var none = new Dictionary<string, double>();
        var boucle = F(0.17, 0.5, 0.26, 0.41);
        Assert.Equal(SoundKind.DrumLoop, DrumNaming.Kind(boucle, none, SoundKind.Kick));
        Assert.Equal(SoundKind.Fill, DrumNaming.Kind(boucle, none, SoundKind.Fill));
        var hat = F(0.1, 0, 0.6, 0.9);
        Assert.Equal(SoundKind.HiHat, DrumNaming.Kind(hat, none, SoundKind.Snare));
        Assert.Equal(SoundKind.OpenHat, DrumNaming.Kind(hat, none, SoundKind.OpenHat));
        var neutre = F(0.2, 0.2, 0.1);
        Assert.Equal(SoundKind.Rim, DrumNaming.Kind(neutre, new Dictionary<string, double> { ["bass_drum"] = 0.8 }, SoundKind.Rim));
        Assert.Equal(SoundKind.Kick, DrumNaming.Kind(neutre, new Dictionary<string, double> { ["bass_drum"] = 0.8 }, null));
        Assert.Equal(SoundKind.Pad, MelodyNaming.Kind(neutre, new Dictionary<string, double> { ["piano"] = 0.7 }, SoundKind.Pad));
        Assert.Equal(SoundKind.Piano, MelodyNaming.Kind(neutre, new Dictionary<string, double> { ["piano"] = 0.7 }, null));

        var ia = new AILabels(voice: 0.3);
        var avis = ClasseurSons.Decider(new[] { 0.05, 0.1, 0.05, 0.75, 0.05 }, 0.2, new double[ClasseurSons.SortesModele.Length]);
        ia.Merge(avis);
        Assert.Equal(0.3, ia.Voice);
        Assert.Equal(0.2, ia.EmbeddedVoice);
        Assert.InRange(ia.Drums, 0.75 - 1e-9, 0.75 + 1e-9);
        Assert.InRange(ia.Instrument, 0.15 - 1e-9, 0.15 + 1e-9);
        var faible = avis with { Familles = new[] { 0, 0, 0, 0.1, 0 } };
        var avant = new AILabels(0, drums: 0.8, instrument: 0.6);
        avant.Merge(faible);
        Assert.Equal(0.8, avant.Drums);
        Assert.Equal(0.6, avant.Instrument);
        var notes = new SoundFeatures
        {
            PeakDB = -6, NoteLength = 0.16, PitchedFraction = 0.9, MedianF0 = 391, LowRatio = 0.01, Flatness = 0.01,
            OnsetsPerSecond = 6, DistinctPitches = 4, Vibrato = 0, HighRatio = 0,
        };
        Assert.Equal(SoundFamily.Melody, FamilyFusion.Decide(notes, new AILabels(0, drums: 0.95)).Family);
    }

    [Fact]
    public void MesuresEtEmpreinte()
    {
        using var classeur = Classeur();
        var son = Lire("voix-chant-44k.wav");
        var avis = classeur.Avis(son.Samples, son.Rate)!;
        Assert.Equal(ClasseurSons.Tranches(Resampler.ToRate(son.Samples, son.Rate, ClasseurSons.Frequence)).Count, avis.Mesures.Length);
        Assert.All(avis.Mesures, m => Assert.Equal(ClasseurSons.TailleMesures, m.Length));
        var empreinte = avis.Empreinte!;
        Assert.Equal(ClasseurSons.TailleEmpreinte, empreinte.Length);
        Assert.InRange(CorrectionsIA.Ressemblance(empreinte, empreinte), 1 - 1e-4, 1 + 1e-4);
        Assert.Null(ClasseurSons.EmpreinteDe(Array.Empty<float[]>()));
    }

    private sealed class Magasin : IDisposable
    {
        public readonly string Dossier = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        public bool? Partage;
        public string Fichier => Path.Combine(Dossier, "corrections-ia.json");

        public CorrectionsIA Ouvrir() => new(Fichier, () => Partage, v => Partage = v,
            (path, data) => { Directory.CreateDirectory(Dossier); File.WriteAllBytes(path, data); },
            path => File.Exists(path) ? File.ReadAllBytes(path) : null);

        public void Dispose()
        {
            try { Directory.Delete(Dossier, true); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }

    private static float[] Unite(int i, int? j = null)
    {
        var v = new float[ClasseurSons.TailleEmpreinte];
        v[i] = 1;
        if (j is not { } k) return v;
        v[k] = 1;
        return v.Select(x => x / MathF.Sqrt(2)).ToArray();
    }

    /// Les corrections restent sur ce PC (relues au lancement suivant) ; seul un son presque identique est retrouvé ; un
    /// même son corrigé deux fois garde la dernière réponse ; 500 au plus.
    [Fact]
    public void CorrectionsGardeesSurLePc()
    {
        using var m = new Magasin();
        var store = m.Ouvrir();
        Assert.Null(store.Cherche(Unite(3)));
        store.Ajoute(new CorrectionIA(Unite(3), SoundFamily.Vocals, SoundKind.Choir, DateTimeOffset.UtcNow));
        Assert.Equal(SoundKind.Choir, store.Cherche(Unite(3))?.Sorte);
        Assert.Null(store.Cherche(Unite(3, 4)));
        Assert.Null(store.Cherche(null));
        store.Ajoute(new CorrectionIA(Unite(3), SoundFamily.Vocals, SoundKind.Adlib, DateTimeOffset.UtcNow));
        Assert.Equal(1, store.Nombre);
        Assert.Equal(SoundKind.Adlib, m.Ouvrir().Cherche(Unite(3))?.Sorte);
        for (var i = 0; i < CorrectionsIA.Maximum + 5; i++)
            store.Ajoute(new CorrectionIA(Unite(i % 1000, i / 1000 + 1000), SoundFamily.Drums, null, DateTimeOffset.UtcNow));
        Assert.Equal(CorrectionsIA.Maximum, store.Nombre);
    }

    /// Ce qui part au serveur (accord donné) : des nombres en 16 bits et des noms de familles et de sortes de l'IA.
    [Fact]
    public void EnvoiDesCorrections()
    {
        var mesures = Enumerable.Repeat(Enumerable.Range(0, ClasseurSons.TailleMesures).Select(i => i / 2f).ToArray(), 10).ToArray();
        var ecoute = new SoundPrint(mesures, Unite(1), SoundFamily.Melody, SoundKind.Lead);
        var corps = CorrectionsIA.Envoi(ecoute, (SoundFamily.Melody, SoundKind.Lead), (SoundFamily.Vocals, SoundKind.Backing),
            new[] { "voice" }, "0.1.0")!;
        Assert.Equal("melodie", corps["famille_ia"]!.GetValue<string>());
        Assert.Equal("lead", corps["sorte_ia"]!.GetValue<string>());
        Assert.Equal("voix", corps["famille"]!.GetValue<string>());
        Assert.Null(corps["sorte"]);
        Assert.Equal(CorrectionsIA.TranchesEnvoyees, corps["tranches"]!.GetValue<int>());
        var brut = Convert.FromBase64String(corps["mesures"]!.GetValue<string>());
        Assert.Equal(CorrectionsIA.TranchesEnvoyees * ClasseurSons.TailleMesures * 2, brut.Length);
        Assert.Equal(new ushort[] { 0x0000, 0x3800, 0x3C00 }, Enumerable.Range(0, 3).Select(i => (ushort)(brut[2 * i] | brut[2 * i + 1] << 8)));
        Assert.Equal(new[] { "app_version", "famille", "famille_avant", "famille_ia", "mesures", "modele", "raisons", "sorte_avant", "sorte_ia", "tranches" },
            corps.Select(kv => kv.Key).OrderBy(k => k, StringComparer.Ordinal));
        Assert.Null(CorrectionsIA.Envoi(ecoute, (SoundFamily.Melody, null), (SoundFamily.Unsure, null), Array.Empty<string>(), "0.1.0"));
    }

    /// Un son corrigé par l'utilisateur est rangé comme il l'a dit, avant toute règle ; sa sorte aussi.
    [Fact]
    public void RegleCorrige()
    {
        using var classeur = Classeur();
        using var m = new Magasin();
        var store = m.Ouvrir();
        var son = Lire("voix-parole.wav");
        var empreinte = classeur.Avis(son.Samples, son.Rate)!.Empreinte!;
        var classer = OrganizerSession.LiveClassifier(classeur, store);
        Assert.Equal(SoundFamily.Vocals, classer(son.Samples, son.Rate).Family);
        store.Ajoute(new CorrectionIA(empreinte, SoundFamily.Drums, SoundKind.Rim, DateTimeOffset.UtcNow));
        var verdict = classer(son.Samples, son.Rate);
        Assert.Equal(SoundFamily.Drums, verdict.Family);
        Assert.StartsWith("corrige", verdict.Rule);
        Assert.Equal(SoundKind.Rim, OrganizerSession.LiveDrumNamer(classeur, store)(son.Samples, son.Rate));
        Assert.NotEqual(SoundKind.Rim, OrganizerSession.LiveKindNamer(classeur, store)(son.Samples, son.Rate, SoundFamily.Fx));
    }

    /// Le classement réel écrit ce que l'IA intégrée a entendu (« +iv » et un nombre), jamais un nom.
    [Fact]
    public void DiagnosticDeLIaIntegree()
    {
        using var classeur = Classeur();
        var son = Lire("voix-parole.wav");
        var verdict = OrganizerSession.LiveClassifier(classeur, null)(son.Samples, son.Rate);
        Assert.Equal(SoundFamily.Vocals, verdict.Family);
        Assert.Matches(@"\+iv\d+$", verdict.Rule);
    }

    /// Le fichier d'un clip audio : son passage le plus fort (WAV et AIFF lus sans rien d'autre).
    [Fact]
    public void FichierDeSonLu()
    {
        var son = Lire("voix-chant-44k.wav");
        Assert.Equal(44_100, son.Rate);
        Assert.True(son.Samples.Length > 40_000);
        var passage = SampleAudio.Loudest(son.Samples, son.Rate, 1)!;
        Assert.Equal(44_100, passage.Samples.Length);
        Assert.Equal(0, SampleAudio.LoudestStart(new float[] { 0, 0, 1, 1, 0 }, 2) - 2);
        Assert.Equal(4, SampleAudio.LoudestStart(new float[] { 0, 0, 0, 0.01f, 1, 1, 0 }, 3));
        Assert.Null(SampleAudio.ReadPcm(Path.Combine(Fixtures, "attendus.json")));
    }
}
