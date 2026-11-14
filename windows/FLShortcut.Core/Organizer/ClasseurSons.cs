// Organiser : l'IA intégrée qui classe les sons (YAMNet de Google, licence Apache 2.0, plus des têtes apprises sur des
// sons libres de droits ; hors ligne). Même modèle que le Mac (ia/modele/classeur_sons.onnx, ia/README.md), mêmes
// règles que Sources/FLShortcut/ClasseurSons.swift : son ramené en mono 16 kHz, crête à 0,7, coupé en tranches de
// 0,975 s (pas 0,48 s ; 16 au plus, les plus fortes) ; pour chaque tranche la famille, la sorte parmi les choix de
// l'aperçu, et ses 1216 mesures (gardées quand on corrige le son : CorrectionsIA). Voix dès que la tranche la plus
// « voix » passe le seuil ; sinon la famille est la moyenne des tranches. Libéré avec l'Organiser.
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;

namespace FLShortcut.Core.Organizer;

public enum ClasseurFamille { Voix, Melodie, Basse, Drums, Fx }

/// Ce que l'IA intégrée entend dans un son.
public sealed record ClasseurAvis(double[] Familles, double VoixMax, ClasseurFamille Famille, double[] Sortes, float[][] Mesures)
{
    /// Pour retrouver un son déjà corrigé (CorrectionsIA) : moyenne des empreintes YAMNet des tranches, de longueur 1.
    public float[]? Empreinte => ClasseurSons.EmpreinteDe(Mesures);

    /// La sorte la plus probable parmi celles d'une famille de l'Organiser, et sa part parmi elles (0…1).
    public (SoundKind Kind, double Part)? Sorte(SoundFamily famille)
    {
        var permises = Enumerable.Range(0, ClasseurSons.SortesModele.Length)
            .Where(i => ClasseurSons.SortesModele[i].Family() == famille).ToList();
        var total = permises.Sum(i => Sortes[i]);
        if (total <= 0 || permises.Count == 0) return null;
        var meilleure = permises.Aggregate((a, b) => Sortes[b] > Sortes[a] ? b : a);
        return (ClasseurSons.SortesModele[meilleure], Sortes[meilleure] / total);
    }

    /// La sorte, seulement si elle l'emporte nettement parmi celles de la famille (`PartMin`).
    public SoundKind? SorteNette(SoundFamily famille) =>
        Sorte(famille) is { } s && s.Part >= ClasseurSons.PartMin ? s.Kind : null;
}

public sealed class ClasseurSons : IDisposable
{
    /// Sortes du modèle, dans l'ordre de sa sortie « sorte » (classeur_sons.json, vérifié par les tests).
    public static readonly SoundKind[] SortesModele =
    {
        SoundKind.Vocal, SoundKind.VocalLead, SoundKind.Choir, SoundKind.Adlib, SoundKind.Ambiance,
        SoundKind.Lead, SoundKind.Pluck, SoundKind.Pad, SoundKind.Keys, SoundKind.Piano, SoundKind.Arp, SoundKind.Chords,
        SoundKind.Guitar, SoundKind.Strings, SoundKind.Bell, SoundKind.Flute, SoundKind.Brass, SoundKind.Organ, SoundKind.Melody,
        SoundKind.Bass808, SoundKind.Sub, SoundKind.Reese, SoundKind.Bass,
        SoundKind.Kick, SoundKind.Snare, SoundKind.Clap, SoundKind.Rim, SoundKind.Snap, SoundKind.HiHat, SoundKind.OpenHat,
        SoundKind.Perc, SoundKind.Tom, SoundKind.Shaker, SoundKind.Crash, SoundKind.Ride, SoundKind.Cymbal, SoundKind.DrumLoop,
        SoundKind.Fill, SoundKind.Drums,
        SoundKind.Riser, SoundKind.Downlifter, SoundKind.Impact, SoundKind.Sweep, SoundKind.Fx,
    };

    /// Seuil des voix appris (ia/modele/classeur_sons.json, vérifié par les tests).
    public const double SeuilVoix = 0.37;
    public const double PartMin = 0.5;
    public const double Frequence = 16_000;
    public const int Tranche = 15_600;
    public const int Pas = 7_680;
    public const int MaxTranches = 16;
    /// Version du modèle (ia/modele/classeur_sons.json), envoyée avec une correction partagée.
    public const int VersionModele = 2;
    public const int TailleMesures = 1216;
    public const int TailleEmpreinte = 1024;
    public const string NomFichier = "classeur_sons.onnx";

    private readonly InferenceSession _session;
    private readonly object _gate = new();
    /// Dernier son écouté et son avis : le classement puis la sorte d'un même son ne l'écoutent qu'une fois.
    private (float[] Samples, double Rate, ClasseurAvis? Avis)? _dernier;

    private ClasseurSons(InferenceSession session) => _session = session;

    /// Le classeur depuis le fichier du modèle ; null s'il manque ou ne se charge pas.
    public static ClasseurSons? Ouvrir(string chemin)
    {
        if (!File.Exists(chemin)) return null;
        try
        {
            // Processeur seul : la précision de l'apprentissage, un résultat stable (comme le Mac, cpuOnly).
            var options = new SessionOptions { GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL };
            return new ClasseurSons(new InferenceSession(chemin, options));
        }
        catch (Exception)
        {
            return null;
        }
    }

    private static readonly object PartageGate = new();
    private static WeakReference<ClasseurSons>? _enCours;

    /// Le classeur des écoutes en cours (classement et sorte d'un même Organiser), créé à la demande à côté de
    /// l'appli, et libéré quand plus personne ne le garde.
    public static ClasseurSons? Partage(string? chemin = null)
    {
        lock (PartageGate)
        {
            if (_enCours is not null && _enCours.TryGetTarget(out var vivant)) return vivant;
            var nouveau = Ouvrir(chemin ?? Path.Combine(AppContext.BaseDirectory, NomFichier));
            _enCours = nouveau is null ? null : new WeakReference<ClasseurSons>(nouveau);
            return nouveau;
        }
    }

    /// Avis sur un son (échantillons à `rate` Hz) ; null si le son est vide ou si le modèle n'a pas répondu.
    public ClasseurAvis? Avis(float[] samples, double rate)
    {
        lock (_gate)
        {
            if (_dernier is { } d && d.Rate == rate && d.Samples.AsSpan().SequenceEqual(samples)) return d.Avis;
            var avis = Ecouter(samples, rate);
            _dernier = (samples, rate, avis);
            return avis;
        }
    }

    private ClasseurAvis? Ecouter(float[] samples, double rate)
    {
        var lot = Tranches(Normaliser(Resampler.ToRate(samples, rate, Frequence)));
        if (lot.Count == 0) return null;
        try
        {
            var entree = new DenseTensor<float>(new[] { lot.Count, Tranche });
            for (var i = 0; i < lot.Count; i++)
                for (var j = 0; j < Tranche; j++) entree[i, j] = lot[i][j];
            using var sorties = _session.Run(new[] { NamedOnnxValue.CreateFromTensor("son", entree) });
            var familles = sorties.First(s => s.Name == "famille").AsTensor<float>();
            var sortes = sorties.First(s => s.Name == "sorte").AsTensor<float>();
            var nf = Enum.GetValues<ClasseurFamille>().Length;
            if (familles.Dimensions[^1] != nf || sortes.Dimensions[^1] != SortesModele.Length) return null;
            var n = lot.Count;
            var moyFamilles = Enumerable.Range(0, nf).Select(k => Enumerable.Range(0, n).Average(i => (double)familles[i, k])).ToArray();
            var moySortes = Enumerable.Range(0, SortesModele.Length).Select(k => Enumerable.Range(0, n).Average(i => (double)sortes[i, k])).ToArray();
            var voixMax = Enumerable.Range(0, n).Max(i => (double)familles[i, (int)ClasseurFamille.Voix]);
            var mesures = Array.Empty<float[]>();
            var sortieMesures = sorties.FirstOrDefault(s => s.Name == "mesures")?.AsTensor<float>();
            if (sortieMesures is { Rank: 2 } m && m.Dimensions[0] == n && m.Dimensions[1] == TailleMesures)
                mesures = Enumerable.Range(0, n).Select(i => Enumerable.Range(0, TailleMesures).Select(k => m[i, k]).ToArray()).ToArray();
            return Decider(moyFamilles, voixMax, moySortes, mesures);
        }
        catch (Exception)
        {
            return null;
        }
    }

    /// Moyenne des empreintes YAMNet (les 1024 premiers nombres) des tranches, ramenée à une longueur de 1.
    public static float[]? EmpreinteDe(IReadOnlyList<float[]> mesures)
    {
        if (mesures.Count == 0 || mesures.Any(t => t.Length < TailleEmpreinte)) return null;
        var somme = new float[TailleEmpreinte];
        foreach (var tranche in mesures)
            for (var i = 0; i < TailleEmpreinte; i++) somme[i] += tranche[i];
        var norme = MathF.Sqrt(somme.Sum(v => v * v));
        if (norme <= 0) return null;
        return somme.Select(v => v / norme).ToArray();
    }

    /// Décision : voix si la tranche la plus « voix » passe le seuil, sinon la meilleure autre famille.
    public static ClasseurAvis Decider(double[] familles, double voixMax, double[] sortes, float[][]? mesures = null)
    {
        var famille = voixMax >= SeuilVoix ? ClasseurFamille.Voix
            : Enum.GetValues<ClasseurFamille>().Where(f => f != ClasseurFamille.Voix)
                .Aggregate((a, b) => familles[(int)b] > familles[(int)a] ? b : a);
        return new ClasseurAvis(familles, voixMax, famille, sortes, mesures ?? Array.Empty<float[]>());
    }

    /// Crête ramenée à 0,7 (le niveau d'un sample ne doit pas compter, comme à l'apprentissage).
    public static float[] Normaliser(float[] samples)
    {
        var crete = samples.Length == 0 ? 0 : samples.Max(v => Math.Abs(v));
        if (crete <= 1e-4f) return samples;
        var gain = 0.7f / crete;
        return samples.Select(v => v * gain).ToArray();
    }

    /// Tranches de `Tranche` échantillons tous les `Pas` (la dernière complétée de silence, comme YAMNet) ; au-delà de
    /// `MaxTranches`, les plus fortes, dans l'ordre du son. Vide pour un son vide.
    public static List<float[]> Tranches(float[] samples)
    {
        var lot = new List<float[]>();
        if (samples.Length == 0) return lot;
        var n = 1 + Math.Max(0, (int)Math.Ceiling((samples.Length - Tranche) / (double)Pas));
        for (var i = 0; i < n; i++)
        {
            var t = new float[Tranche];
            var debut = i * Pas;
            Array.Copy(samples, debut, t, 0, Math.Min(Tranche, samples.Length - debut));
            lot.Add(t);
        }
        if (lot.Count <= MaxTranches) return lot;
        var energie = lot.Select(t => t.Sum(v => v * v)).ToArray();
        var fortes = Enumerable.Range(0, lot.Count).OrderByDescending(i => energie[i]).Take(MaxTranches).ToHashSet();
        return Enumerable.Range(0, lot.Count).Where(fortes.Contains).Select(i => lot[i]).ToList();
    }

    /// Famille de l'Organiser pour une famille de l'IA intégrée.
    public static SoundFamily Famille(ClasseurFamille f) => f switch
    {
        ClasseurFamille.Voix => SoundFamily.Vocals,
        ClasseurFamille.Melodie => SoundFamily.Melody,
        ClasseurFamille.Basse => SoundFamily.Bass,
        ClasseurFamille.Drums => SoundFamily.Drums,
        _ => SoundFamily.Fx,
    };

    public void Dispose() => _session.Dispose();
}

/// Rééchantillonnage de bonne qualité (sinus cardinal fenêtré de Kaiser), pour ramener un son à 16 kHz.
public static class Resampler
{
    public static float[] ToRate(float[] samples, double from, double to)
    {
        if (samples.Length == 0 || from <= 0) return Array.Empty<float>();
        if (from == to) return samples;
        var ratio = to / from;
        var cutoff = Math.Min(1.0, ratio) * 0.97;           // fréquence de coupure (part du Nyquist d'entrée)
        const int zeros = 24;                               // passages par zéro de chaque côté
        var half = zeros / cutoff;                          // demi-largeur du noyau, en échantillons d'entrée
        var count = (int)Math.Floor(samples.Length * ratio);
        var out_ = new float[count];
        for (var i = 0; i < count; i++)
        {
            var t = i / ratio;
            var first = (int)Math.Ceiling(t - half);
            var last = (int)Math.Floor(t + half);
            double sum = 0;
            for (var k = Math.Max(first, 0); k <= Math.Min(last, samples.Length - 1); k++)
            {
                var x = t - k;
                var u = Math.Abs(x) / half;
                if (u >= 1) continue;
                var arg = Math.PI * cutoff * x;
                var sinc = Math.Abs(arg) < 1e-12 ? 1 : Math.Sin(arg) / arg;
                sum += samples[k] * cutoff * sinc * Window(u);
            }
            out_[i] = (float)sum;
        }
        return out_;
    }

    private const double Beta = 9.0;
    private const int WindowSteps = 4096;
    /// Fenêtre de Kaiser tabulée sur [0, 1] (calculée une fois).
    private static readonly double[] WindowTable = BuildWindow();

    private static double[] BuildWindow()
    {
        var table = new double[WindowSteps + 2];
        var i0Beta = BesselI0(Beta);
        for (var i = 0; i <= WindowSteps + 1; i++)
        {
            var u = Math.Min(1.0, (double)i / WindowSteps);
            table[i] = BesselI0(Beta * Math.Sqrt(1 - u * u)) / i0Beta;
        }
        return table;
    }

    private static double Window(double u)
    {
        var p = u * WindowSteps;
        var i = (int)p;
        var f = p - i;
        return WindowTable[i] * (1 - f) + WindowTable[i + 1] * f;
    }

    private static double BesselI0(double x)
    {
        double sum = 1, term = 1;
        var q = x * x / 4;
        for (var k = 1; k < 50; k++)
        {
            term *= q / (k * k);
            sum += term;
            if (term < sum * 1e-12) break;
        }
        return sum;
    }
}
