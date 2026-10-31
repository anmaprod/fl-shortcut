// Organiser : le son à classer. Tampon du son capté (mono, les dernières secondes seulement, jamais écrit sur le
// disque), source du son (la capture de FL ; un faux dans les tests) et fichier de son d'un clip audio de FL, lu
// directement : son passage le plus fort, en un instant (une prise de voix commence souvent par un long silence).
// Miroir de Sources/FLShortcut/CaptureBuffer.swift et SampleFiles.swift. Les fichiers WAV et AIFF sont lus ici ;
// les autres formats (MP3, FLAC…) par Media Foundation dans l'appli.
using System.Text;

namespace FLShortcut.Core.Organizer;

public sealed class CaptureBuffer
{
    public double Rate { get; }
    public int Capacity { get; }
    private readonly List<float> _samples = new();
    private readonly object _gate = new();
    private int _chunks;
    private float _peak;

    public CaptureBuffer(double rate, double seconds)
    {
        Rate = rate;
        Capacity = Math.Max(1, (int)(rate * seconds));
    }

    /// Canaux entrelacés (L R L R…) : moyenne des canaux.
    public void AppendInterleaved(ReadOnlySpan<float> data, int frames, int channels)
    {
        if (frames <= 0 || channels <= 0) return;
        var scale = 1f / channels;
        var mono = new float[frames];
        for (var f = 0; f < frames; f++)
        {
            float sum = 0;
            for (var c = 0; c < channels; c++) sum += data[f * channels + c];
            mono[f] = sum * scale;
        }
        Append(mono);
    }

    public void Append(float[] mono)
    {
        lock (_gate)
        {
            _samples.AddRange(mono);
            if (_samples.Count > Capacity) _samples.RemoveRange(0, _samples.Count - Capacity);
            _chunks++;
            foreach (var v in mono) if (Math.Abs(v) > _peak) _peak = Math.Abs(v);
        }
    }

    /// Blocs reçus depuis la création, et la crête de tout ce qui a été reçu (diagnostic : rien n'est gardé).
    public (int Chunks, float Peak) Received { get { lock (_gate) return (_chunks, _peak); } }

    /// Le son reçu depuis le dernier `Reset` (les `Capacity` derniers échantillons), puis le tampon est vidé.
    public float[] Take()
    {
        lock (_gate)
        {
            var out_ = _samples.ToArray();
            _samples.Clear();
            return out_;
        }
    }

    public void Reset()
    {
        lock (_gate) _samples.Clear();
    }
}

/// Source du son à classer (la capture de FL ; un faux dans les tests).
public interface IAudioSource
{
    double Rate { get; }
    /// Lance une `OrganizerError` si la capture est impossible.
    void Start();
    /// Oublie le son reçu jusqu'ici.
    void Reset();
    /// Le son reçu depuis le dernier `Reset`.
    float[] Take();
    void Stop();
    /// Ce que la capture a reçu, pour « Copier le diagnostic » (nombres seulement).
    string Stats { get; }
}

/// Un passage de son, en mono.
public sealed record SampleSound(float[] Samples, double Rate);

public static class SampleFiles
{
    private static string Native(string path) => path.Replace('\\', '/');

    /// Pur (testé) : où peut être le fichier, dans l'ordre. Le chemin tel quel s'il est complet ; les dossiers de FL à
    /// la place de leurs noms (« %FLStudioFactoryData% », « %FLStudioUserData% ») ; sinon à côté du projet (chemin
    /// relatif, ou le seul nom du fichier, dans le dossier du projet et ses sous-dossiers habituels). Chemins écrits
    /// avec « / » (comparés tels quels) ; Windows les accepte.
    public static List<string> Candidates(string path, string project, IReadOnlyList<string> factory, IReadOnlyList<string> user)
    {
        var clean = Native(path);
        var out_ = new List<string>();
        void Add(string p)
        {
            var n = Native(p);
            if (!out_.Contains(n)) out_.Add(n);
        }
        var variables = new (string Name, IReadOnlyList<string> Folders)[] { ("%FLStudioFactoryData%", factory), ("%FLStudioUserData%", user) };
        var replaced = false;
        foreach (var (name, folders) in variables)
        {
            if (clean.IndexOf(name, StringComparison.OrdinalIgnoreCase) < 0) continue;
            replaced = true;
            var rest = Replace(clean, name, "").Trim('/');
            foreach (var folder in folders) Add(Native(folder).TrimEnd('/') + "/" + rest);
        }
        var folderOfProject = Native(Path.GetDirectoryName(project) ?? "");
        if (!replaced)
        {
            if (IsAbsolute(clean)) Add(clean);
            else if (!clean.Contains('%')) Add(folderOfProject.TrimEnd('/') + "/" + clean);
        }
        var file = clean.Split('/').LastOrDefault() ?? "";
        if (file.Length > 0)
        {
            var baseName = Path.GetFileNameWithoutExtension(project);
            foreach (var sub in new[] { "", "Recorded", "Audio", "Samples", baseName, baseName + "/Recorded", baseName + "/Audio" })
                Add(folderOfProject.TrimEnd('/') + "/" + (sub.Length == 0 ? file : sub + "/" + file));
        }
        return out_;
    }

    /// Chemin complet : « C:/… », « //serveur/… » ou « /… » (projet venu d'un Mac).
    private static bool IsAbsolute(string clean) =>
        clean.StartsWith('/') || (clean.Length >= 3 && char.IsLetter(clean[0]) && clean[1] == ':' && clean[2] == '/');

    private static string Replace(string text, string what, string with)
    {
        var at = text.IndexOf(what, StringComparison.OrdinalIgnoreCase);
        return at < 0 ? text : text[..at] + with + text[(at + what.Length)..];
    }

    /// Le premier qui existe ; sinon un fichier du même nom trouvé ailleurs (`search`), de préférence dans un dossier
    /// du même nom.
    public static string? Resolve(string path, string project, IReadOnlyList<string> factory, IReadOnlyList<string> user,
        Func<string, bool> exists, Func<string, IReadOnlyList<string>> search)
    {
        var found = Candidates(path, project, factory, user).FirstOrDefault(exists);
        if (found is not null) return found;
        var clean = Native(path);
        var parts = clean.Split('/').Where(p => p.Length > 0).ToArray();
        if (parts.Length == 0) return null;
        var file = parts[^1];
        var parent = parts.Length >= 2 ? parts[^2] : "";
        var results = search(file);
        return results.FirstOrDefault(r => string.Equals(Path.GetFileName(Path.GetDirectoryName(r) ?? ""), parent, StringComparison.OrdinalIgnoreCase))
               ?? results.FirstOrDefault();
    }
}

public static class SampleAudio
{
    /// Tranche de mesure de l'énergie (secondes).
    public const double Block = 0.1;
    /// 10 minutes lues au plus.
    public const double MaxSeconds = 600;

    /// Le passage le plus fort d'un son entier, `seconds` au plus.
    public static SampleSound? Loudest(float[] mono, double rate, double seconds = 3)
    {
        if (rate < 8_000 || mono.Length == 0) return null;
        var frames = (int)Math.Min(mono.Length, rate * MaxSeconds);
        var perBlock = Math.Max(1, (int)(rate * Block));
        var energies = new List<float>();
        for (var at = 0; at < frames; at += perBlock)
        {
            var end = Math.Min(frames, at + perBlock);
            float sum = 0;
            for (var i = at; i < end; i++) sum += mono[i] * mono[i];
            energies.Add(MathF.Sqrt(sum / (end - at)));
        }
        var start = LoudestStart(energies, Math.Max(1, (int)Math.Round(seconds / Block, MidpointRounding.AwayFromZero)));
        var from = Math.Min(start * perBlock, frames);
        var length = (int)Math.Min(rate * seconds, frames - from);
        if (length <= 0) return null;
        return new SampleSound(mono[from..(from + length)], rate);
    }

    /// Pur (testé) : la tranche où commence le passage le plus fort de `window` tranches ; le silence du début de ce
    /// passage est sauté (un son court commence à son attaque).
    public static int LoudestStart(IReadOnlyList<float> energies, int window)
    {
        if (energies.Count == 0) return 0;
        var w = Math.Max(1, Math.Min(window, energies.Count));
        float sum = 0;
        for (var i = 0; i < w; i++) sum += energies[i];
        var bestStart = 0;
        var bestSum = sum;
        for (var i = 1; i <= energies.Count - w; i++)
        {
            sum += energies[i + w - 1] - energies[i - 1];
            if (sum > bestSum)
            {
                bestSum = sum;
                bestStart = i;
            }
        }
        var peak = energies.Max();
        var start = bestStart;
        while (start < bestStart + w - 1 && start < energies.Count - 1 && energies[start] < peak * 0.05f) start++;
        return start;
    }

    /// Un fichier WAV ou AIFF en mono (moyenne des canaux) ; null s'il ne se lit pas (autre format).
    public static SampleSound? ReadPcm(string path)
    {
        try
        {
            using var stream = File.OpenRead(path);
            var max = (long)Math.Min(stream.Length, 2L << 30);
            using var reader = new BinaryReader(stream);
            var id = Encoding.ASCII.GetString(reader.ReadBytes(4));
            if (id is "RIFF" or "RF64") return ReadWave(reader, max);
            if (id == "FORM") return ReadAiff(reader);
            return null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or EndOfStreamException or ArgumentException)
        {
            return null;
        }
    }

    private static SampleSound? ReadWave(BinaryReader r, long length)
    {
        r.ReadUInt32();
        if (Encoding.ASCII.GetString(r.ReadBytes(4)) != "WAVE") return null;
        int format = 0, channels = 0, bits = 0;
        double rate = 0;
        while (r.BaseStream.Position + 8 <= r.BaseStream.Length)
        {
            var chunk = Encoding.ASCII.GetString(r.ReadBytes(4));
            long size = r.ReadUInt32();
            if (chunk == "fmt ")
            {
                format = r.ReadUInt16();
                channels = r.ReadUInt16();
                rate = r.ReadUInt32();
                r.ReadUInt32();
                r.ReadUInt16();
                bits = r.ReadUInt16();
                var rest = size - 16;
                if (format == 0xFFFE && rest >= 10)
                {
                    r.ReadUInt16();
                    r.ReadUInt16();
                    r.ReadUInt32();
                    format = r.ReadUInt16();                 // les deux premiers octets du GUID : le vrai format
                    rest -= 10;
                }
                if (rest > 0) r.BaseStream.Seek(rest, SeekOrigin.Current);
            }
            else if (chunk == "data")
            {
                if (channels <= 0 || rate < 8_000 || bits <= 0) return null;
                if (size == 0xFFFFFFFF || r.BaseStream.Position + size > r.BaseStream.Length) size = r.BaseStream.Length - r.BaseStream.Position;
                var bytesPerSample = bits / 8;
                var frameBytes = bytesPerSample * channels;
                var frames = (int)Math.Min(size / frameBytes, (long)(rate * MaxSeconds));
                var data = r.ReadBytes(frames * frameBytes);
                var mono = new float[data.Length / frameBytes];
                for (var f = 0; f < mono.Length; f++)
                {
                    float sum = 0;
                    for (var c = 0; c < channels; c++)
                        sum += Sample(data, (f * channels + c) * bytesPerSample, bits, format == 3, bigEndian: false);
                    mono[f] = sum / channels;
                }
                return new SampleSound(mono, rate);
            }
            else
            {
                r.BaseStream.Seek(size + (size & 1), SeekOrigin.Current);
            }
        }
        return null;
    }

    private static SampleSound? ReadAiff(BinaryReader r)
    {
        r.ReadUInt32();
        var form = Encoding.ASCII.GetString(r.ReadBytes(4));
        if (form != "AIFF" && form != "AIFC") return null;
        int channels = 0, bits = 0;
        double rate = 0;
        var isFloat = false;
        while (r.BaseStream.Position + 8 <= r.BaseStream.Length)
        {
            var chunk = Encoding.ASCII.GetString(r.ReadBytes(4));
            long size = BigEndian(r.ReadBytes(4));
            var start = r.BaseStream.Position;
            if (chunk == "COMM")
            {
                channels = (int)BigEndian(r.ReadBytes(2));
                r.ReadBytes(4);
                bits = (int)BigEndian(r.ReadBytes(2));
                rate = Extended(r.ReadBytes(10));
                if (form == "AIFC" && size >= 22)
                {
                    var compression = Encoding.ASCII.GetString(r.ReadBytes(4));
                    if (compression is "fl32" or "FL32") isFloat = true;
                    else if (compression is not ("NONE" or "none" or "twos")) return null;
                }
            }
            else if (chunk == "SSND")
            {
                var offset = BigEndian(r.ReadBytes(4));
                r.ReadBytes(4);
                r.BaseStream.Seek(offset, SeekOrigin.Current);
                if (channels <= 0 || rate < 8_000 || bits <= 0) return null;
                var bytesPerSample = (bits + 7) / 8;
                var frameBytes = bytesPerSample * channels;
                var available = size - 8 - offset;
                var frames = (int)Math.Min(available / frameBytes, (long)(rate * MaxSeconds));
                var data = r.ReadBytes(frames * frameBytes);
                var mono = new float[data.Length / frameBytes];
                for (var f = 0; f < mono.Length; f++)
                {
                    float sum = 0;
                    for (var c = 0; c < channels; c++)
                        sum += Sample(data, (f * channels + c) * bytesPerSample, bytesPerSample * 8, isFloat, bigEndian: true);
                    mono[f] = sum / channels;
                }
                return new SampleSound(mono, rate);
            }
            r.BaseStream.Seek(start + size + (size & 1), SeekOrigin.Begin);
        }
        return null;
    }

    private static float Sample(byte[] d, int at, int bits, bool isFloat, bool bigEndian)
    {
        byte B(int k) => bigEndian ? d[at + bits / 8 - 1 - k] : d[at + k];
        if (isFloat && bits == 32) return BitConverter.ToSingle(new[] { B(0), B(1), B(2), B(3) }, 0);
        if (isFloat && bits == 64) return (float)BitConverter.ToDouble(new[] { B(0), B(1), B(2), B(3), B(4), B(5), B(6), B(7) }, 0);
        switch (bits)
        {
            case 8: return bigEndian ? (sbyte)d[at] / 128f : (d[at] - 128) / 128f;
            case 16: return (short)(B(0) | B(1) << 8) / 32768f;
            case 24: return ((B(0) | B(1) << 8 | B(2) << 16) << 8 >> 8) / 8388608f;
            case 32: return (B(0) | B(1) << 8 | B(2) << 16 | B(3) << 24) / 2147483648f;
            default: return 0;
        }
    }

    private static long BigEndian(byte[] b)
    {
        long v = 0;
        foreach (var x in b) v = v << 8 | x;
        return v;
    }

    /// Nombre à virgule de 80 bits (fréquence d'un AIFF).
    private static double Extended(byte[] b)
    {
        var exponent = ((b[0] & 0x7F) << 8) | b[1];
        ulong mantissa = 0;
        for (var i = 2; i < 10; i++) mantissa = mantissa << 8 | b[i];
        if (exponent == 0 && mantissa == 0) return 0;
        var value = mantissa * Math.Pow(2, exponent - 16383 - 63);
        return (b[0] & 0x80) != 0 ? -value : value;
    }
}
