// Classement des sons : mesures et règles (mêmes sons de synthèse, mêmes seuils que le Mac). Miroir de
// Tests/FLShortcutTests/SoundClassificationTests.swift (sans l'IA de macOS, absente de Windows).
using FLShortcut.Core.Organizer;
using Xunit;
using Xunit.Abstractions;

namespace FLShortcut.Core.Tests;

/// Sons de synthèse (mêmes recettes que le prototype qui a réglé les règles), bruit pseudo-aléatoire fixe.
public static class SynthSounds
{
    public const double Rate = 48_000;

    public sealed class Noise
    {
        private ulong _state = 0x9E37_79B9_7F4A_7C15;
        public double Uniform()
        {
            _state ^= _state >> 12; _state ^= _state << 25; _state ^= _state >> 27;
            return (double)(unchecked(_state * 2_685_821_657_736_338_717UL) >> 11) / (1UL << 53);
        }
        public double Gaussian()
        {
            double u = Math.Max(Uniform(), 1e-12), v = Uniform();
            return Math.Sqrt(-2 * Math.Log(u)) * Math.Cos(2 * Math.PI * v);
        }
    }

    public static int Count(double d) => (int)(Rate * d);

    public static double[] Place(double total, IEnumerable<(double Start, double[] Sig)> events)
    {
        var out_ = new double[Count(total)];
        foreach (var (start, sig) in events)
        {
            var i = Count(start);
            for (var k = 0; k < Math.Min(sig.Length, out_.Length - i); k++) out_[i + k] += sig[k];
        }
        return out_;
    }

    public static double[] OnePole(double[] x, double fc)
    {
        var a = Math.Exp(-2 * Math.PI * fc / Rate);
        var acc = 0.0;
        return x.Select(v => acc = (1 - a) * v + a * acc).ToArray();
    }

    public static double[] Saw(double f, double d, double maxHz = 4000) =>
        Enumerable.Range(0, Count(d)).Select(i =>
        {
            var t = i / Rate;
            double v = 0, k = 1;
            while (k * f < maxHz) { v += Math.Sin(2 * Math.PI * k * f * t) / k; k += 1; }
            return v * 0.5;
        }).ToArray();

    public static double[] Env(double d, double attack = 0.005, double release = 0.05)
    {
        int n = Count(d), a = Math.Max(1, Count(attack)), r = Math.Max(1, Count(release));
        return Enumerable.Range(0, n).Select(i =>
        {
            var e = 1.0;
            if (i < a) e = (double)i / Math.Max(a - 1, 1);
            if (i >= n - r) e *= (double)(n - 1 - i) / Math.Max(r - 1, 1);
            return e;
        }).ToArray();
    }

    public static double[] Mul(double[] a, double[] b) => a.Zip(b, (x, y) => x * y).ToArray();

    public static double[] Kick()
    {
        var phase = 0.0;
        var hit = Enumerable.Range(0, Count(0.4)).Select(i =>
        {
            var t = i / Rate;
            phase += 2 * Math.PI * (50 + 100 * Math.Exp(-t / 0.03)) / Rate;
            return Math.Sin(phase) * Math.Exp(-t / 0.12);
        }).ToArray();
        return Place(2, new[] { 0, 0.5, 1, 1.5 }.Select(s => (s, hit)));
    }

    public static double[] Snare(Noise noise, double total = 2, double[]? at = null)
    {
        var hit = Enumerable.Range(0, Count(0.3)).Select(i =>
        {
            var t = i / Rate;
            var rattle = noise.Gaussian() * Math.Exp(-t / 0.08) * 0.5;
            var body = 0.4 * Math.Sin(2 * Math.PI * 180 * t) * Math.Exp(-t / 0.05);
            return rattle + body;
        }).ToArray();
        return Place(total, (at ?? new[] { 0.5, 1.5 }).Select(s => (s, hit)));
    }

    public static double[] Hat(Noise noise, double total = 2, double[]? at = null)
    {
        var previous = noise.Gaussian();
        var hit = Enumerable.Range(0, Count(0.12)).Select(i =>
        {
            var t = i / Rate;
            var next = noise.Gaussian();
            var v = (next - previous) * Math.Exp(-t / 0.02) * 0.3;
            previous = next;
            return v;
        }).ToArray();
        return Place(total, (at ?? Enumerable.Range(0, 8).Select(k => k * 0.25).ToArray()).Select(s => (s, hit)));
    }

    public static double[] B808()
    {
        double[] Note(double f) => Enumerable.Range(0, Count(0.95)).Select(i =>
        {
            var t = i / Rate;
            return Math.Tanh(1.5 * Math.Sin(2 * Math.PI * f * t) * Math.Exp(-t / 0.6)) * 0.8;
        }).ToArray();
        return Place(2, new[] { (0.0, Note(49)), (1.0, Note(55)) });
    }

    public static double[] Bass()
    {
        var notes = new[] { 55, 65.4, 73.4, 49 };
        return Place(2, notes.Select((f, i) => (i * 0.5, Mul(OnePole(Saw(f, 0.45), 400), Env(0.45)).Select(v => v * 1.5).ToArray())));
    }

    public static double[] Lead()
    {
        var notes = new[] { 440, 523.3, 587.3, 659.3 };
        return Place(2, notes.Select((f, i) => (i * 0.5, Mul(Saw(f, 0.45), Env(0.45)).Select(v => v * 0.6).ToArray())));
    }

    public static double[] Pad()
    {
        double[] a = Saw(220, 2, 3000), b = Saw(277.2, 2, 3000), c = Saw(329.6, 2, 3000);
        var sum = Enumerable.Range(0, a.Length).Select(i => (a[i] + b[i] + c[i]) * 0.3).ToArray();
        return Mul(OnePole(sum, 2000), Env(2, attack: 0.3, release: 0.3));
    }

    public static double[] Riser(Noise noise)
    {
        var n = Count(2);
        var acc = 0.0;
        return Enumerable.Range(0, n).Select(i =>
        {
            var fc = 500 + 7500 * (double)i / n;
            var a = Math.Exp(-2 * Math.PI * fc / Rate);
            acc = (1 - a) * noise.Gaussian() + a * acc;
            return acc * i / (n - 1) * 0.8;
        }).ToArray();
    }

    public static double[] Voice()
    {
        var n = Count(1.6);
        double phase = 0, last = 0;
        var pulses = new double[n];
        for (var i = 0; i < n; i++)
        {
            var t = i / Rate;
            phase += 150 * Math.Pow(2, 0.4 * Math.Sin(2 * Math.PI * 5.5 * t) / 12) / Rate;
            pulses[i] = Math.Floor(phase) > Math.Floor(last) ? 1 : 0;
            last = phase;
        }
        double[] Resonator(double f, double bw)
        {
            double r = Math.Exp(-Math.PI * bw / Rate), c1 = 2 * r * Math.Cos(2 * Math.PI * f / Rate), c2 = -r * r;
            double y1 = 0, y2 = 0;
            return pulses.Select(x =>
            {
                var v = x + c1 * y1 + c2 * y2;
                y2 = y1;
                y1 = v;
                return v;
            }).ToArray();
        }
        double[] a = Resonator(700, 110), b = Resonator(1220, 120), c = Resonator(2600, 160);
        var mix = Enumerable.Range(0, n).Select(i => a[i] + 0.6 * b[i] + 0.25 * c[i]).ToArray();
        var peak = mix.Max(Math.Abs);
        return Mul(mix.Select(v => v / peak * 0.7).ToArray(), Env(1.6, attack: 0.05, release: 0.15));
    }

    /// Arpège en doubles croches à 93 BPM : notes de pluck brèves, quatre hauteurs qui tournent.
    public static double[] Arp()
    {
        var step = 60.0 / 93 / 4;
        var notes = new[] { 261.6, 329.6, 392.0, 523.3 };
        double[] Pluck(double f, double d)
        {
            var decay = Enumerable.Range(0, Count(d)).Select(i => Math.Exp(-i / Rate / 0.08)).ToArray();
            return Mul(Saw(f, d, 6000), decay).Select(v => v * 0.7).ToArray();
        }
        return Place(2, Enumerable.Range(0, (int)(2 / step)).Select(k => (k * step, Pluck(notes[k % 4], step * 0.9))));
    }

    /// Boucle de batterie à 93 BPM : kick sur 1 et 3, snare sur 2 et 4, charleston en croches.
    public static double[] DrumLoop(Noise noise)
    {
        double beat = 60.0 / 93, total = 2.0;
        var hit = Kick().Take(Count(0.4)).ToArray();
        var out_ = Place(total, new[] { (0.0, hit), (2 * beat, hit) });
        var snares = Snare(noise, total, new[] { beat, 3 * beat });
        var hats = Hat(noise, total, Enumerable.Range(0, (int)(total / (beat / 2))).Select(k => k * beat / 2).ToArray());
        for (var i = 0; i < out_.Length; i++) out_[i] += snares[i] + hats[i] * 0.8;
        return out_;
    }

    /// Charleston fermé et brillant : bruit filtré passe-haut (8 kHz), très bref, en doubles croches.
    public static double[] BrightHat(Noise noise)
    {
        var raw = Enumerable.Range(0, Count(0.06)).Select(_ => noise.Gaussian()).ToArray();
        var smooth = OnePole(raw, 8000);
        var hit = raw.Select((v, i) => (v - smooth[i]) * Math.Exp(-i / Rate / 0.015) * 0.5).ToArray();
        return Place(2, Enumerable.Range(0, 16).Select(k => (k * 0.125, hit)));
    }

    public static float[] F(double[] x) => x.Select(v => (float)v).ToArray();

    public static List<(string Name, float[] Samples, SoundFamily Expected, DrumKind? Drum)> Reported()
    {
        var noise = new Noise();
        var loop = DrumLoop(noise);
        var hat = BrightHat(noise);
        return new()
        {
            ("arp", F(Arp()), SoundFamily.Melody, null), ("loop", F(loop), SoundFamily.Drums, DrumKind.Loop),
            ("hat", F(hat), SoundFamily.Drums, DrumKind.HiHat),
        };
    }

    public static List<(string Name, float[] Samples, SoundFamily Expected)> All()
    {
        var noise = new Noise();
        var snare = Snare(noise);
        var hat = Hat(noise);
        var riser = Riser(noise);
        return new()
        {
            ("kick", F(Kick()), SoundFamily.Drums), ("snare", F(snare), SoundFamily.Drums), ("hat", F(hat), SoundFamily.Drums),
            ("808", F(B808()), SoundFamily.Bass), ("bass", F(Bass()), SoundFamily.Bass), ("lead", F(Lead()), SoundFamily.Melody),
            ("pad", F(Pad()), SoundFamily.Melody), ("riser", F(riser), SoundFamily.Fx), ("voice", F(Voice()), SoundFamily.Vocals),
        };
    }
}

public class SoundClassificationTests
{
    private readonly ITestOutputHelper _out;
    public SoundClassificationTests(ITestOutputHelper output) => _out = output;

    private static float[] Sine(double f, double d) =>
        Enumerable.Range(0, (int)(48_000 * d)).Select(i => (float)(0.5 * Math.Sin(2 * Math.PI * f / 48_000 * i))).ToArray();

    private static SoundFeatures Feat(double len, double pitched, double f0, double low, double flat, int distinct = 1,
        double vib = 0, double high = 0, double onsets = 2) => new()
    {
        PeakDB = -6, NoteLength = len, PitchedFraction = pitched, MedianF0 = f0, LowRatio = low, Flatness = flat,
        OnsetsPerSecond = onsets, DistinctPitches = distinct, Vibrato = vib, HighRatio = high,
    };

    private static readonly Dictionary<string, double> NoScores = new();

    [Fact]
    public void FeaturesOfSine()
    {
        var f = SoundFeatures.Measure(Sine(220, 1), 48_000);
        Assert.InRange(f.MedianF0, 220 * 0.98, 220 * 1.02);
        Assert.True(f.PitchedFraction >= 0.9);
        Assert.True(f.Flatness < 0.05);
        var low = SoundFeatures.Measure(Sine(55, 1), 48_000);
        Assert.InRange(low.MedianF0, 55 * 0.98, 55 * 1.02);
        Assert.True(low.LowRatio > 0.9);
    }

    [Fact]
    public void FeaturesOfNoise()
    {
        var noise = new SynthSounds.Noise();
        var x = Enumerable.Range(0, 48_000).Select(_ => (float)(noise.Gaussian() * 0.3)).ToArray();
        var f = SoundFeatures.Measure(x, 48_000);
        Assert.True(f.Flatness > 0.3);
        Assert.True(f.PitchedFraction < 0.2);
    }

    [Fact]
    public void SilenceIsUnsure()
    {
        var quiet = Enumerable.Repeat(0.000_1f, 48_000).ToArray();
        var f = SoundFeatures.Measure(quiet, 48_000);
        Assert.True(f.PeakDB < FamilyFusion.SilenceDB);
        Assert.Equal(SoundFamily.Unsure, FamilyFusion.Decide(f, AILabels.None).Family);
        Assert.Equal(SoundFamily.Unsure, FamilyFusion.Decide(SoundFeatures.Measure(Array.Empty<float>(), 48_000), AILabels.None).Family);
    }

    /// Une mesure par règle, dans l'ordre.
    [Fact]
    public void FusionRules()
    {
        Assert.Equal(SoundFamily.Vocals, FamilyFusion.Decide(Feat(1, 1, 150, 0, 0), new AILabels(voice: 0.8)).Family);
        Assert.Equal(SoundFamily.Bass, FamilyFusion.Decide(Feat(0.9, 1, 50, 0.9, 0), AILabels.None).Family);
        Assert.Equal(SoundFamily.Bass, FamilyFusion.Decide(Feat(0.2, 1, 60, 0.9, 0, distinct: 4), AILabels.None).Family);
        Assert.Equal(SoundFamily.Drums, FamilyFusion.Decide(Feat(0.3, 0.9, 50, 1, 0), AILabels.None).Family);
        Assert.Equal(SoundFamily.Drums, FamilyFusion.Decide(Feat(0.1, 0, 0, 0, 0.3), AILabels.None).Family);
        Assert.Equal(SoundFamily.Fx, FamilyFusion.Decide(Feat(2, 0, 0, 0, 0.45), new AILabels(0, 0, 0.9)).Family);
        Assert.Equal(SoundFamily.Vocals, FamilyFusion.Decide(Feat(1.5, 1, 150, 0, 0, vib: 0.3), new AILabels(voice: 0.2)).Family);
        Assert.Equal("melodie", FamilyFusion.DecideWithRule(Feat(1.5, 1, 150, 0, 0, vib: 0.3), AILabels.None).Rule);
        Assert.Equal(SoundFamily.Melody, FamilyFusion.DecideWithRule(Feat(1.5, 1, 150, 0, 0, vib: 0.3), new AILabels(voice: 0.1)).Family);
        Assert.Equal("voix-ia", FamilyFusion.DecideWithRule(Feat(1, 1, 150, 0, 0), new AILabels(voice: 0.8)).Rule);
        Assert.True(AILabels.FromScores(new Dictionary<string, double> { ["applause"] = 0.4 }).Heard);
        Assert.False(AILabels.FromScores(NoScores).Heard);
        Assert.Equal(SoundFamily.Melody, FamilyFusion.Decide(Feat(0.45, 1, 440, 0, 0), new AILabels(0, drums: 0.7)).Family);
        Assert.Equal(SoundFamily.Melody, FamilyFusion.Decide(Feat(2, 0.2, 220, 0, 0.1), AILabels.None).Family);
        Assert.Equal(SoundFamily.Fx, FamilyFusion.Decide(Feat(2, 0.2, 0, 0, 0.2), AILabels.None).Family);
        Assert.Equal(SoundFamily.Unsure, FamilyFusion.Decide(Feat(0.2, 0.4, 300, 0, 0.17), AILabels.None).Family);
        // L'IA intégrée entend une voix : règle « voix-iv ».
        var embedded = new AILabels { EmbeddedVoice = 0.9 };
        Assert.Equal("voix-iv", FamilyFusion.DecideWithRule(Feat(2, 0, 0, 0, 0.45), embedded).Rule);
    }

    [Fact]
    public void ReportedSoundsByRule()
    {
        Assert.Equal(SoundFamily.Melody, FamilyFusion.Decide(Feat(0.32, 0.27, 66, 0.04, 0.07), AILabels.None).Family);
        Assert.Equal(SoundFamily.Melody, FamilyFusion.Decide(Feat(2.5, 0.04, 65, 0.03, 0.12), AILabels.None).Family);
        Assert.Equal(SoundFamily.Melody, FamilyFusion.Decide(Feat(0.62, 0.75, 398, 0.01, 0.04, distinct: 4, vib: 0.42), AILabels.None).Family);
        Assert.Equal(SoundFamily.Melody, FamilyFusion.Decide(Feat(0.16, 0.9, 391, 0.01, 0.01, distinct: 4), new AILabels(0, drums: 0.7)).Family);
        var loop = Feat(0.17, 0.64, 52, 0.5, 0.26, high: 0.41, distinct: 2);
        Assert.Equal(SoundFamily.Drums, FamilyFusion.Decide(loop, AILabels.None).Family);
        Assert.Equal(DrumKind.Loop, DrumNaming.Kind(loop, new Dictionary<string, double> { ["bass_drum"] = 0.6 }));
        var open = Feat(0.6, 0, 0, 0, 0.59, high: 0.94, onsets: 1.2);
        Assert.Equal(SoundFamily.Drums, FamilyFusion.Decide(open, AILabels.None).Family);
        Assert.Equal(SoundFamily.Fx, FamilyFusion.Decide(Feat(1.9, 0, 0, 0.05, 0.4, high: 0.31, onsets: 0), AILabels.None).Family);
        var hat = Feat(0.1, 0, 0, 0, 0.6, high: 0.9, onsets: 3);
        Assert.Equal(SoundFamily.Drums, FamilyFusion.Decide(hat, AILabels.None).Family);
        Assert.Equal(DrumKind.HiHat, DrumNaming.Kind(hat, new Dictionary<string, double> { ["snare_drum"] = 0.5 }));
        Assert.Equal(DrumKind.HiHat, DrumNaming.Kind(open, NoScores));
    }

    /// Les trois sons des retours, synthétisés : famille et sorte par les mesures seules.
    [Fact]
    public void ReportedSynthSounds()
    {
        foreach (var s in SynthSounds.Reported())
        {
            var f = SoundFeatures.Measure(s.Samples, SynthSounds.Rate);
            var detail = $"len={f.NoteLength:F2} pitched={f.PitchedFraction:F2} f0={f.MedianF0:F0} low={f.LowRatio:F2} flat={f.Flatness:F3} high={f.HighRatio:F2} distinct={f.DistinctPitches}";
            _out.WriteLine($"ORGANISER: {s.Name} {detail}");
            Assert.True(s.Expected == FamilyFusion.Decide(f, AILabels.None).Family, $"{s.Name} {detail}");
            if (s.Drum is { } drum) Assert.True(drum == DrumNaming.Kind(f, NoScores), $"{s.Name} {detail}");
        }
    }

    /// Trois notes nettes : une mélodie, même brève et bruitée ; un synthé de mélodies se reconnaît à son nom.
    [Fact]
    public void SeveralNotesAreAMelody()
    {
        var stabs = Feat(0.15, 0.35, 330, 0, 0.4, distinct: 3, high: 0.2, onsets: 4);
        Assert.Equal("melodie-notes", FamilyFusion.DecideWithRule(stabs, new AILabels(0, drums: 0.8)).Rule);
        Assert.Equal(SoundFamily.Drums, FamilyFusion.Decide(stabs with { DistinctPitches = 1 }, AILabels.None).Family);
        Assert.True(SoundNames.IsMelodicSynth("ZENOLOGY"));
        Assert.True(SoundNames.IsMelodicSynth("Serum 2"));
        Assert.True(SoundNames.IsMelodicSynth("Sylenth1 #2"));
        Assert.True(SoundNames.IsMelodicSynth("3x Osc"));
        Assert.False(SoundNames.IsMelodicSynth("Serum Kick"));
        Assert.False(SoundNames.IsMelodicSynth("FPC"));
        Assert.False(SoundNames.IsMelodicSynth("Sampler"));
    }

    [Fact]
    public void DrumNamingRules()
    {
        static SoundFeatures F(double len, double low, double flat, double f0 = 0, double pitched = 0, double high = 0) => new()
        {
            PeakDB = -6, NoteLength = len, PitchedFraction = pitched, MedianF0 = f0, LowRatio = low, Flatness = flat,
            OnsetsPerSecond = 4, DistinctPitches = 1, Vibrato = 0, HighRatio = high,
        };
        var neutral = F(0.2, 0.2, 0.1);
        Assert.Equal(DrumKind.Kick, DrumNaming.Kind(neutral, new Dictionary<string, double> { ["bass_drum"] = 0.8, ["snare_drum"] = 0.4 }));
        Assert.Equal(DrumKind.HiHat, DrumNaming.Kind(neutral, new Dictionary<string, double> { ["clapping"] = 0.5, ["hi_hat"] = 0.5 }));
        Assert.Equal(DrumKind.Kit, DrumNaming.Kind(neutral, new Dictionary<string, double> { ["drum_kit"] = 0.9, ["bass_drum"] = 0.4 }));
        Assert.Equal(DrumKind.Perc, DrumNaming.Kind(neutral, new Dictionary<string, double> { ["snare_drum"] = 0.2, ["speech"] = 0.9 }));
        Assert.Equal(DrumKind.Kick, DrumNaming.Kind(F(0.3, 0.9, 0.05), NoScores));
        Assert.Equal(DrumKind.Kick, DrumNaming.Kind(F(0.3, 0.2, 0.05, f0: 55, pitched: 0.8), NoScores));
        Assert.Equal(DrumKind.HiHat, DrumNaming.Kind(F(0.1, 0, 0.5, high: 0.9), NoScores));
        Assert.Equal(DrumKind.Cymbal, DrumNaming.Kind(F(1.2, 0, 0.5, high: 0.9), NoScores));
        Assert.Equal(DrumKind.Snare, DrumNaming.Kind(F(0.2, 0.2, 0.3, high: 0.3), NoScores));
        Assert.Equal(DrumKind.Clap, DrumNaming.Kind(F(0.3, 0, 0.56), NoScores));
        Assert.Equal(DrumKind.Perc, DrumNaming.Kind(F(0.1, 0, 0.35, f0: 820, pitched: 1), NoScores));
        Assert.Equal(DrumKind.Loop, DrumNaming.Kind(F(0.2, 0.6, 0.26, high: 0.4), NoScores));
        Loc.English = false;
        Assert.Equal(new[] { "Kick", "Snare", "Hi-hat", "Clap", "Cymbal", "Perc", "Drums", "Drum loop" },
            Enum.GetValues<DrumKind>().Select(d => d.Sound().Name()));
        foreach (var label in DrumNaming.Labels.Keys) Assert.Equal(FamilyFusion.LabelKind.Drums, FamilyFusion.LabelTable[label]);
        // L'IA intégrée précise un métal ; une boucle mesurée entendue comme un fill est un Fill.
        var metal = F(0.1, 0, 0.5, high: 0.9);
        Assert.Equal(SoundKind.OpenHat, DrumNaming.Kind(metal, NoScores, SoundKind.OpenHat));
        Assert.Equal(SoundKind.Fill, DrumNaming.Kind(F(0.2, 0.6, 0.26, high: 0.4), NoScores, SoundKind.Fill));
        Assert.Equal(SoundKind.Snare, DrumNaming.Kind(neutral, NoScores, SoundKind.Snare));
    }

    [Fact]
    public void MelodyNamingRules()
    {
        static SoundFeatures F(double len, double onsets = 2, int distinct = 1, double pitched = 0.8) => new()
        {
            PeakDB = -6, NoteLength = len, PitchedFraction = pitched, MedianF0 = 440, LowRatio = 0, Flatness = 0.05,
            OnsetsPerSecond = onsets, DistinctPitches = distinct, Vibrato = 0, HighRatio = 0,
        };
        var line = F(0.6);
        Assert.Equal(SoundKind.Piano, MelodyNaming.Kind(line, new Dictionary<string, double> { ["piano"] = 0.7, ["guitar"] = 0.4 }));
        Assert.Equal(SoundKind.Keys, MelodyNaming.Kind(line, new Dictionary<string, double> { ["electric_piano"] = 0.5 }));
        Assert.Equal(SoundKind.Strings, MelodyNaming.Kind(line, new Dictionary<string, double> { ["violin_fiddle"] = 0.6, ["synthesizer"] = 0.9 }));
        Assert.Equal(SoundKind.Lead, MelodyNaming.Kind(line, new Dictionary<string, double> { ["guitar"] = 0.2 }));
        Assert.Equal(SoundKind.Pluck, MelodyNaming.Kind(F(0.15), NoScores));
        Assert.Equal(SoundKind.Arp, MelodyNaming.Kind(F(0.15, onsets: 6, distinct: 4), NoScores));
        Assert.Equal(SoundKind.Pad, MelodyNaming.Kind(F(2, onsets: 0.5), NoScores));
        Assert.Null(MelodyNaming.Kind(F(0.6, pitched: 0.3), NoScores));
        Assert.Null(MelodyNaming.Kind(SoundFeatures.Silent, NoScores));
        foreach (var (label, kind) in MelodyNaming.Labels)
        {
            Assert.Equal(FamilyFusion.LabelKind.Instrument, FamilyFusion.LabelTable[label]);
            Assert.Equal(SoundFamily.Melody, kind.Family());
        }
    }

    /// Mesures seules (sans IA) : 8 sur 9 au moins ; la voix demande l'IA.
    [Fact]
    public void SynthSoundsByFeatures()
    {
        var ok = 0;
        foreach (var s in SynthSounds.All())
        {
            var f = SoundFeatures.Measure(s.Samples, SynthSounds.Rate);
            var got = FamilyFusion.Decide(f, AILabels.None).Family;
            if (got == s.Expected) ok++;
            _out.WriteLine($"ORGANISER: {s.Name,-6} {(got == s.Expected ? "ok " : "NON")} {got} (attendu {s.Expected}) len={f.NoteLength:F2} pitched={f.PitchedFraction:F2} f0={f.MedianF0:F0} low={f.LowRatio:F2} flat={f.Flatness:F3} high={f.HighRatio:F2} distinct={f.DistinctPitches} vib={f.Vibrato:F2}");
        }
        Assert.True(ok >= 8, $"{ok}/9");
    }
}

/// Ce qu'est un son d'après son nom (mêmes mots que le Mac).
public class SoundNamesTests
{
    [Fact]
    public void KindsFromNames()
    {
        Assert.Equal(SoundKind.Kick, SoundNames.KindOf("BEAM KICK"));
        Assert.Equal(SoundKind.Bass808, SoundNames.KindOf("ZEBRA 808"));
        Assert.Equal(SoundKind.OpenHat, SoundNames.KindOf("ALTER OPEN HAT"));
        Assert.Equal(SoundKind.Clap, SoundNames.KindOf("@MEH CLAP"));
        Assert.Equal(SoundKind.Vocal, SoundNames.KindOf("Vocal Chop"));
        Assert.Equal(SoundKind.Bass, SoundNames.KindOf("Synth Bass"));
        Assert.Equal(SoundKind.Kick, SoundNames.KindOf("808 Kick"));
        Assert.Equal(SoundKind.Bass808, SoundNames.KindOf("Sub 808"));
        Assert.Equal(SoundKind.Adlib, SoundNames.KindOf("Adlib Vox"));
        Assert.Equal(SoundKind.Kick, SoundNames.KindOf("Kick01"));
        Assert.Equal(SoundKind.Fill, SoundNames.KindOf("Snare Fill"));
        Assert.Equal(SoundKind.DrumLoop, SoundNames.KindOf("Hat Loop"));
        Assert.Equal(SoundKind.DrumLoop, SoundNames.KindOf("Top Loop"));
        Assert.Equal(SoundKind.Melody, SoundNames.KindOf("Melody Loop"));
        Assert.Equal(SoundKind.VocalLead, SoundNames.KindOf("Lead Vox"));
        Assert.Equal(SoundKind.Backing, SoundNames.KindOf("Vocal Back 2"));
        Assert.Equal(SoundKind.Choir, SoundNames.KindOf("Chœur") ?? SoundNames.KindOf("Choeur"));
        Assert.Equal(SoundKind.Melody, SoundNames.KindOf("Mélodie"));
        Assert.Null(SoundNames.KindOf("Serum 2"));
        Assert.Null(SoundNames.KindOf("Sampler"));
        Assert.Equal("_Insert 5", SoundNames.RecordedTrack("untitled_2026-10-15 23-37-42_Insert 5"));
        Assert.Null(SoundNames.KindOf("untitled_2026-10-15 23-37-42_Insert 5"));
        Assert.Equal(SoundKind.Guitar, SoundNames.KindOf("Mon son_2026-10-15 23-37-42_Guitar"));
        Assert.True(SoundNames.IsSection("Refrain 2"));
        Assert.False(SoundNames.IsSection("Kick intro"));
        Loc.English = false;
        Assert.True(SoundNames.IsGenerated("Mélodie 3"));
        Assert.True(SoundNames.IsGenerated("Snare"));
        Assert.False(SoundNames.IsGenerated("Serum 2"));
    }

    [Fact]
    public void RackOrderPutsBassBefore808()
    {
        var bass = SoundKinds.RackOrder.Where(k => k.Family() == SoundFamily.Bass).ToArray();
        Assert.Equal(new[] { SoundKind.Bass, SoundKind.Reese, SoundKind.Sub, SoundKind.Bass808 }, bass);
        Assert.Equal(SoundFamily.Drums, SoundKind.Bass808.BusFamily());
        Assert.Equal("bass808", SoundKind.Bass808.Raw());
        Assert.Equal("hiHat", SoundKind.HiHat.Raw());
        Assert.Equal(SoundKind.VocalLead, SoundKinds.KindFromRaw("vocalLead"));
        Assert.Equal(SoundFamily.Vocals, SoundFamilies.FamilyFromRaw("vocals"));
    }
}
