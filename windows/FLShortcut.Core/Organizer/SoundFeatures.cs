// Organiser : mesures d'un son capté (mono, float), même calcul que le Mac (Sources/FLShortcut/SoundFeatures.swift,
// qui passe par Accelerate) : enveloppe sur 40 ms (pas de 10 ms), attaques, longueur des notes, hauteur par
// autocorrélation normalisée (signal ramené au quart, 40 à 1 000 Hz), hauteur de chaque note, vibrato, part d'énergie
// sous 200 Hz et au-dessus de 6 kHz, platitude du spectre dans la bande qui porte l'énergie (FFT de 4 096 points).
// Quelques millisecondes par son ; rien n'est gardé.
namespace FLShortcut.Core.Organizer;

public sealed record SoundFeatures
{
    public double PeakDB { get; init; }
    /// Longueur moyenne d'une note (s) : de son attaque à −20 dB de son sommet (ou à la note suivante).
    public double NoteLength { get; init; }
    /// Part des trames où une hauteur nette est trouvée (0…1).
    public double PitchedFraction { get; init; }
    public double MedianF0 { get; init; }
    /// Part d'énergie sous 200 Hz (0…1).
    public double LowRatio { get; init; }
    /// Platitude du spectre dans la bande qui porte l'énergie : 0 tonal, vers 0,56 un bruit.
    public double Flatness { get; init; }
    public double OnsetsPerSecond { get; init; }
    /// Nombre de hauteurs différentes d'une note à l'autre (demi-tons).
    public int DistinctPitches { get; init; }
    /// Écart type des demi-tons autour de leur médiane glissante, dans les passages tenus.
    public double Vibrato { get; init; }
    /// Part d'énergie au-dessus de 6 kHz (0…1).
    public double HighRatio { get; init; }

    public static SoundFeatures Silent => new()
    {
        PeakDB = -120, NoteLength = 0, PitchedFraction = 0, MedianF0 = 0, LowRatio = 0, Flatness = 1,
        OnsetsPerSecond = 0, DistinctPitches = 0, Vibrato = 0,
    };

    public static SoundFeatures Measure(float[] samples, double rate)
    {
        if (rate < 8_000 || samples.Length == 0) return Silent;
        float peak = 0;
        foreach (var s in samples) peak = Math.Max(peak, Math.Abs(s));
        var peakDB = 20 * Math.Log10(Math.Max(peak, 1e-9));
        if (peakDB < FamilyFusion.SilenceDB || samples.Length < rate * 0.05) return Silent with { PeakDB = peakDB };

        // Enveloppe : énergie par tranche de 10 ms, moyennée sur 40 ms.
        var hop = (int)(rate * 0.01);
        var n = samples.Length / hop;
        var energy = new double[n];
        for (var k = 0; k < n; k++)
        {
            double e = 0;
            for (var i = k * hop; i < (k + 1) * hop; i++) e += (double)samples[i] * samples[i];
            energy[k] = (float)(e / hop);
        }
        var db = new double[n];
        for (var k = 0; k < n; k++)
        {
            int lo = Math.Max(0, k - 2), hi = Math.Min(n, k + 2);
            double sum = 0;
            for (var i = lo; i < hi; i++) sum += energy[i];
            db[k] = 20 * Math.Log10(Math.Sqrt(sum / (hi - lo)) + 1e-9);
        }
        var top = n > 0 ? db.Max() : -180;
        var activeFloor = Math.Max(top - 40, -60);
        var active = db.Select(v => v > activeFloor).ToArray();

        // Attaques : +6 dB sur les 30 ms d'avant, assez fortes, 50 ms d'écart au moins.
        var onsets = new List<int>();
        for (var k = 0; k < n; k++)
        {
            double lo = -120;
            if (k > 0)
            {
                lo = double.MaxValue;
                for (var i = Math.Max(0, k - 3); i < k; i++) lo = Math.Min(lo, db[i]);
            }
            if (db[k] - lo > 6 && db[k] > top - 30 && (onsets.Count == 0 || k - onsets[^1] >= 5)) onsets.Add(k);
        }
        var lengths = new List<int>();
        for (var j = 0; j < onsets.Count; j++)
        {
            var k = onsets[j];
            var end = j + 1 < onsets.Count ? onsets[j + 1] : n;
            var local = db[k];
            var upto = Math.Min(k + 6, end);
            if (upto > k) { local = double.MinValue; for (var i = k; i < upto; i++) local = Math.Max(local, db[i]); }
            var m = k;
            while (m < end && db[m] > local - 20) m++;
            lengths.Add(m - k);
        }
        var noteLength = lengths.Count == 0 ? active.Count(a => a) * 0.01 : (double)lengths.Sum() / lengths.Count * 0.01;

        // Hauteur : signal ramené au quart (moyenne de 4 échantillons), trames de 1 024 au pas de 512.
        const int d = 4;
        var rd = rate / d;
        var y = new float[samples.Length / d];
        for (var i = 0; i < y.Length; i++)
            y[i] = (samples[i * d] + samples[i * d + 1] + samples[i * d + 2] + samples[i * d + 3]) / 4;
        const int frameN = 1024, frameH = 512;
        int lmin = (int)(rd / 1000), lmax = (int)(rd / 40);
        var starts = new List<int>();
        if (y.Length >= frameN) for (var s = 0; s <= y.Length - frameN; s += frameH) starts.Add(s);
        var frameDB = new List<double>();
        foreach (var s in starts)
        {
            double e = 0;
            for (var i = s; i < s + frameN; i++) e += (double)y[i] * y[i];
            frameDB.Add(20 * Math.Log10(Math.Sqrt((float)(e / frameN)) + 1e-9));
        }
        var yTop = frameDB.Count > 0 ? frameDB.Max() : -120;
        var chosen = starts.Where((_, i) => frameDB[i] > yTop - 25).ToList();
        if (chosen.Count > 48)
            chosen = Enumerable.Range(0, 48).Select(q => chosen[(int)Math.Round(q * (double)(chosen.Count - 1) / 47, MidpointRounding.AwayFromZero)]).ToList();
        var f0s = new List<double>();
        var seq = new List<(double F0, int Pos)>();
        var nacf = new double[lmax + 2];
        var cumulative = new double[frameN + 1];
        foreach (var s in chosen)
        {
            for (var i = 0; i < frameN; i++)
            {
                double v = y[s + i];
                cumulative[i + 1] = cumulative[i] + v * v;
            }
            for (var lag = lmin; lag <= lmax; lag++)
            {
                double dot = 0;
                var count = frameN - lag;
                for (var i = 0; i < count; i++) dot += (double)y[s + i] * y[s + i + lag];
                var e0 = cumulative[frameN - lag];
                var eL = cumulative[frameN] - cumulative[lag];
                var norm = Math.Sqrt(e0 * eL) + 1e-12;
                nacf[lag] = (float)dot / norm;
            }
            var center = s + frameN / 2.0;
            var pos = (int)(center * d / hop);
            double best = 0;
            for (var l = lmin; l <= lmax; l++) best = l == lmin ? nacf[l] : Math.Max(best, nacf[l]);
            if (best < 0.75)
            {
                seq.Add((0, pos));
                continue;
            }
            // Plus petit retard qui atteint 92 % du meilleur et qui est un sommet (évite les sous-octaves).
            var threshold = 0.92 * best;
            var found = -1;
            for (var l = lmin + 1; l < lmax; l++)
            {
                var v = nacf[l];
                if (v >= threshold && v >= nacf[l - 1] && v >= nacf[l + 1]) { found = l; break; }
            }
            if (found < 0)
            {
                found = lmin;
                for (var l = lmin; l <= lmax; l++) if (nacf[l] > nacf[found]) found = l;
            }
            double exact = found;
            if (found > lmin && found < lmax)
            {
                double a = nacf[found - 1], b = nacf[found], c = nacf[found + 1];
                var den = a - 2 * b + c;
                var off = Math.Abs(den) > 1e-12 ? 0.5 * (a - c) / den : 0;
                exact += Math.Max(-0.5, Math.Min(0.5, off));
            }
            var f0 = rd / exact;
            f0s.Add(f0);
            seq.Add((f0, pos));
        }
        var pitchedFraction = chosen.Count == 0 ? 0 : (double)f0s.Count / chosen.Count;
        var medianF0 = Median(f0s) ?? 0;

        // Hauteur de chaque note (médiane de ses trames tonales) : un kick qui glisse garde une seule hauteur.
        var distinct = 0;
        var vibrato = 0.0;
        if (f0s.Count > 0)
        {
            var bounds = (onsets.Count == 0 ? new List<int> { 0 } : onsets.ToList());
            bounds.Add(n);
            var notes = new HashSet<int>();
            for (var j = 0; j < bounds.Count - 1; j++)
            {
                var values = seq.Where(x => x.F0 > 0 && bounds[j] <= x.Pos && x.Pos < bounds[j + 1]).Select(x => x.F0).ToList();
                if (Median(values) is { } m) notes.Add((int)Math.Round(12 * Math.Log2(m / 440), MidpointRounding.AwayFromZero));
            }
            distinct = notes.Count;
            // Vibrato : demi-tons moins leur médiane glissante (5 trames), dans les suites de 5 trames tonales ou plus.
            var residuals = new List<double>();
            var run = new List<double>();
            foreach (var item in seq.Append((0.0, 0)))
            {
                if (item.Item1 > 0)
                {
                    run.Add(12 * Math.Log2(item.Item1 / 440));
                    continue;
                }
                if (run.Count >= 5)
                {
                    for (var i = 0; i < run.Count; i++)
                    {
                        var window = run.GetRange(Math.Max(0, i - 2), Math.Min(run.Count, i + 3) - Math.Max(0, i - 2));
                        var local = Median(window) ?? run[i];
                        var r = run[i] - local;
                        if (Math.Abs(r) <= 1.5) residuals.Add(r);       // changements de note et erreurs d'octave à part
                    }
                }
                run.Clear();
            }
            if (residuals.Count >= 5)
            {
                var mean = residuals.Average();
                vibrato = Math.Sqrt(residuals.Sum(r => (r - mean) * (r - mean)) / residuals.Count);
            }
        }

        // Spectre : trames de 4 096 (16 au plus) parmi les passages actifs.
        var spectral = Spectrum(samples, rate, active, hop);

        return new SoundFeatures
        {
            PeakDB = peakDB, NoteLength = noteLength, PitchedFraction = pitchedFraction, MedianF0 = medianF0,
            LowRatio = spectral.Low, Flatness = spectral.Flatness, OnsetsPerSecond = onsets.Count / (samples.Length / rate),
            DistinctPitches = distinct, Vibrato = vibrato, HighRatio = spectral.High,
        };
    }

    public static double? Median(IReadOnlyCollection<double> values)
    {
        if (values.Count == 0) return null;
        var v = values.OrderBy(x => x).ToArray();
        return v.Length % 2 == 1 ? v[v.Length / 2] : (v[v.Length / 2 - 1] + v[v.Length / 2]) / 2;
    }

    private static (double Low, double Flatness, double High) Spectrum(float[] x, double rate, bool[] active, int hop)
    {
        const int m = 4096;
        if (x.Length < m) return (0, 1, 0);
        var starts = new List<int>();
        for (var s = 0; s <= x.Length - m; s += m)
        {
            int a = s / hop, b = Math.Min(active.Length, (s + m) / hop);
            if (a < b && active.Skip(a).Take(b - a).Any(v => v)) starts.Add(s);
        }
        if (starts.Count > 16)
            starts = Enumerable.Range(0, 16).Select(q => starts[(int)Math.Round(q * (double)(starts.Count - 1) / 15, MidpointRounding.AwayFromZero)]).ToList();
        if (starts.Count == 0) return (0, 1, 0);
        var window = new double[m];
        for (var i = 0; i < m; i++) window[i] = 0.5 * (1 - Math.Cos(2 * Math.PI * i / m));
        var re = new double[m];
        var im = new double[m];
        var power = new double[m / 2 + 1];
        var binHz = rate / m;
        // Cases de 20 Hz à 20 kHz.
        int first = (int)Math.Ceiling(20 / binHz), last = Math.Min(m / 2, (int)Math.Floor(20_000 / binHz));
        if (first >= last) return (0, 1, 0);
        var lows = new List<double>();
        var flats = new List<double>();
        var highs = new List<double>();
        foreach (var s in starts)
        {
            for (var i = 0; i < m; i++)
            {
                re[i] = (float)(x[s + i] * window[i]);
                im[i] = 0;
            }
            Fft.Forward(re, im);
            for (var k = 0; k <= m / 2; k++) power[k] = re[k] * re[k] + im[k] * im[k];
            double total = 1e-12, low = 0, high = 0;
            for (var k = first; k <= last; k++)
            {
                total += power[k];
                var hz = k * binHz;
                if (hz < 200) low += power[k]; else if (hz >= 6_000) high += power[k];
            }
            lows.Add(low / total);
            highs.Add(high / total);
            flats.Add(BandFlatness(power, first, last, total));
        }
        return (lows.Average(), flats.Average(), highs.Average());
    }

    /// Cases plus étroites que ça (un son pur : quelques cases) : élargies autour de leur milieu.
    public const int MinFlatBins = 32;

    /// Pur (testé) : platitude des cases de `[from, to]` qui portent de 5 % à 95 % de l'énergie (`total`), élargies à
    /// `MinFlatBins` cases autour de leur milieu.
    public static double BandFlatness(double[] power, int from, int to, double total)
    {
        int a = -1, b = to;
        var acc = 0.0;
        for (var k = from; k <= to; k++)
        {
            acc += power[k];
            if (a < 0 && acc / total >= 0.05) a = k;
            if (acc / total >= 0.95) { b = k; break; }
        }
        if (a < 0) a = from;
        if (b - a + 1 < MinFlatBins)
        {
            var mid = (a + b) / 2;
            a = Math.Max(from, mid - MinFlatBins / 2);
            b = Math.Min(to, a + MinFlatBins - 1);
            a = Math.Max(from, b - MinFlatBins + 1);
        }
        double logSum = 0, sum = 0;
        for (var k = a; k <= b; k++)
        {
            var p = power[k] + 1e-12;
            logSum += Math.Log(p);
            sum += p;
        }
        double count = b - a + 1;
        return Math.Exp(logSum / count) / (sum / count);
    }
}

/// FFT complexe en place (radix 2, taille puissance de deux).
public static class Fft
{
    public static void Forward(double[] re, double[] im)
    {
        var n = re.Length;
        for (int i = 1, j = 0; i < n; i++)
        {
            var bit = n >> 1;
            for (; (j & bit) != 0; bit >>= 1) j ^= bit;
            j ^= bit;
            if (i < j)
            {
                (re[i], re[j]) = (re[j], re[i]);
                (im[i], im[j]) = (im[j], im[i]);
            }
        }
        for (var len = 2; len <= n; len <<= 1)
        {
            var angle = -2 * Math.PI / len;
            double wr = Math.Cos(angle), wi = Math.Sin(angle);
            for (var i = 0; i < n; i += len)
            {
                double cr = 1, ci = 0;
                for (var k = 0; k < len / 2; k++)
                {
                    int a = i + k, b = i + k + len / 2;
                    var tr = re[b] * cr - im[b] * ci;
                    var ti = re[b] * ci + im[b] * cr;
                    re[b] = re[a] - tr;
                    im[b] = im[a] - ti;
                    re[a] += tr;
                    im[a] += ti;
                    var next = cr * wr - ci * wi;
                    ci = cr * wi + ci * wr;
                    cr = next;
                }
            }
        }
    }
}
