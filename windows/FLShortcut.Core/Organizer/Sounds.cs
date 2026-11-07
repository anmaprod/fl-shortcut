// Organiser : les familles de sons, ce qu'est chaque son d'après son nom (Kick, 808, Open Hat…) et les règles qui
// fusionnent les mesures du son (SoundFeatures) et l'avis de l'IA intégrée (ClasseurSons). Miroir de
// Sources/FLShortcut/SoundFamilies.swift : mêmes mots, mêmes seuils, même ordre. Sur Windows, il n'y a pas l'IA de
// macOS : ses étiquettes restent vides, l'IA intégrée prend sa place dans les mêmes règles (comme sur le Mac).
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace FLShortcut.Core.Organizer;

public enum SoundFamily { Drums, Bass, Melody, Vocals, Fx, Unsure }

/// Ce qu'est un son (« BEAM KICK » : Kick, « ZEBRA 808 » : 808…), dans l'ordre des cas du Mac.
public enum SoundKind
{
    VocalLead, Backing, Ambiance, Adlib, Choir, Vocal,
    Lead, Pluck, Pad, Keys, Piano, Synth, Arp, Chords, Guitar, Strings, Bell, Flute, Brass, Organ, Melody,
    Bass808, Sub, Reese, Bass,
    Kick, Snare, Clap, Rim, Snap, HiHat, OpenHat, Perc, Tom, Shaker, Crash, Ride, Cymbal, DrumLoop, Fill, Drums,
    Riser, Downlifter, Impact, Sweep, Fx,
}

/// Sorte d'un son de drums reconnue à l'écoute (pas de nom qui la dise).
public enum DrumKind { Kick, Snare, HiHat, Clap, Cymbal, Perc, Kit, Loop }

public static class SoundFamilies
{
    public static readonly SoundFamily[] All = Enum.GetValues<SoundFamily>();

    /// Ordre des familles (choisi par l'utilisateur) : dans le Channel rack une fois organisé, et dans l'aperçu.
    public static readonly SoundFamily[] Order =
        { SoundFamily.Vocals, SoundFamily.Melody, SoundFamily.Bass, SoundFamily.Drums, SoundFamily.Fx, SoundFamily.Unsure };

    public static int Rank(this SoundFamily f) { var i = Array.IndexOf(Order, f); return i < 0 ? Order.Length : i; }

    /// Nom de la famille dans les fichiers (« drums », « vocals »…), le même que sur le Mac.
    public static string Raw(this SoundFamily f) => Lower(f.ToString());

    public static SoundFamily? FamilyFromRaw(string raw) =>
        All.Cast<SoundFamily?>().FirstOrDefault(f => f!.Value.Raw() == raw);

    public static string Label(this SoundFamily f) => f switch
    {
        SoundFamily.Drums => Loc.T("Drums"),
        SoundFamily.Bass => Loc.T("Basse"),
        SoundFamily.Melody => Loc.T("Mélodies"),
        SoundFamily.Vocals => Loc.T("Voix"),
        SoundFamily.Fx => Loc.T("FX"),
        _ => Loc.T("À vérifier"),
    };

    /// Nom d'une piste de la Playlist renommée quand ses sons ne disent pas tous la même chose.
    public static string? TrackName(this SoundFamily f) => f switch
    {
        SoundFamily.Drums => Loc.T("Drums"),
        SoundFamily.Bass => Loc.T("Basse"),
        SoundFamily.Melody => Loc.T("Mélodie"),
        SoundFamily.Vocals => Loc.T("Voix"),
        SoundFamily.Fx => Loc.T("FX"),
        _ => null,
    };

    /// Ce qu'un son de la famille peut être, dans l'ordre du Channel rack organisé.
    public static SoundKind[] Kinds(this SoundFamily f) => SoundKinds.All.Where(k => k.Family() == f).ToArray();

    internal static string Lower(string name) => char.ToLowerInvariant(name[0]) + name[1..];
}

public static class SoundKinds
{
    public static readonly SoundKind[] All = Enum.GetValues<SoundKind>();

    public static SoundFamily Family(this SoundKind k) => k switch
    {
        <= SoundKind.Vocal => SoundFamily.Vocals,
        <= SoundKind.Melody => SoundFamily.Melody,
        <= SoundKind.Bass => SoundFamily.Bass,
        <= SoundKind.Drums => SoundFamily.Drums,
        _ => SoundFamily.Fx,
    };

    /// Nom dans les fichiers (« vocalLead », « bass808 », « hiHat »…), le même que sur le Mac.
    public static string Raw(this SoundKind k) => SoundFamilies.Lower(k.ToString());

    public static SoundKind? KindFromRaw(string raw) => All.Cast<SoundKind?>().FirstOrDefault(k => k!.Value.Raw() == raw);

    public static string Name(this SoundKind k) => k switch
    {
        SoundKind.Vocal => Loc.T("Voix"),
        SoundKind.VocalLead => Loc.T("Voix lead"),
        SoundKind.Backing => Loc.T("Back"),
        SoundKind.Ambiance => Loc.T("Ambiance"),
        SoundKind.Adlib => Loc.T("Adlib"),
        SoundKind.Choir => Loc.T("Chœur"),
        SoundKind.Lead => Loc.T("Lead"),
        SoundKind.Pluck => Loc.T("Pluck"),
        SoundKind.Pad => Loc.T("Pad"),
        SoundKind.Keys => Loc.T("Keys"),
        SoundKind.Piano => Loc.T("Piano"),
        SoundKind.Synth => Loc.T("Synth"),
        SoundKind.Arp => Loc.T("Arp"),
        SoundKind.Chords => Loc.T("Chords"),
        SoundKind.Guitar => Loc.T("Guitare"),
        SoundKind.Strings => Loc.T("Strings"),
        SoundKind.Bell => Loc.T("Bell"),
        SoundKind.Flute => Loc.T("Flûte"),
        SoundKind.Brass => Loc.T("Brass"),
        SoundKind.Organ => Loc.T("Orgue"),
        SoundKind.Melody => Loc.T("Mélodie"),
        SoundKind.Bass808 => Loc.T("808"),
        SoundKind.Sub => Loc.T("Sub"),
        SoundKind.Reese => Loc.T("Reese"),
        SoundKind.Bass => Loc.T("Basse"),
        SoundKind.Kick => Loc.T("Kick"),
        SoundKind.Snare => Loc.T("Snare"),
        SoundKind.Clap => Loc.T("Clap"),
        SoundKind.Rim => Loc.T("Rim"),
        SoundKind.Snap => Loc.T("Snap"),
        SoundKind.HiHat => Loc.T("Hi-hat"),
        SoundKind.OpenHat => Loc.T("Open Hat"),
        SoundKind.Perc => Loc.T("Perc"),
        SoundKind.Tom => Loc.T("Tom"),
        SoundKind.Shaker => Loc.T("Shaker"),
        SoundKind.Crash => Loc.T("Crash"),
        SoundKind.Ride => Loc.T("Ride"),
        SoundKind.Cymbal => Loc.T("Cymbal"),
        SoundKind.DrumLoop => Loc.T("Drum loop"),
        SoundKind.Fill => Loc.T("Fill"),
        SoundKind.Drums => Loc.T("Drums"),
        SoundKind.Riser => Loc.T("Riser"),
        SoundKind.Downlifter => Loc.T("Downlifter"),
        SoundKind.Impact => Loc.T("Impact"),
        SoundKind.Sweep => Loc.T("Sweep"),
        _ => Loc.T("FX"),
    };

    /// Le mot général de sa famille (« Drums », « Basse », « Voix », « FX », « Mélodie ») : un mot précis l'emporte.
    public static bool IsGeneral(this SoundKind k) =>
        k is SoundKind.Vocal or SoundKind.Melody or SoundKind.Bass or SoundKind.Drums or SoundKind.Fx;

    public static int Rank(this SoundKind k) => (int)k;

    /// Ordre dans le Channel rack organisé : celui des cas, sauf dans la basse : Basse, Reese, Sub, puis 808, juste
    /// avant les drums. `Rank` reste l'ordre de préférence d'un mot dans un nom (« 808 Sub » : 808).
    public static readonly SoundKind[] RackOrder = All.Where(k => k.Family() != SoundFamily.Bass)
        .Concat(new[] { SoundKind.Bass, SoundKind.Reese, SoundKind.Sub, SoundKind.Bass808 }).ToArray();

    public static int RackRank(this SoundKind k) { var i = Array.IndexOf(RackOrder, k); return i < 0 ? RackOrder.Length : i; }

    /// Le bus du Mixer où va un son de cette sorte : celui de sa famille, sauf les 808 avec les drums.
    public static SoundFamily BusFamily(this SoundKind k) => k == SoundKind.Bass808 ? SoundFamily.Drums : k.Family();

    public static SoundKind Sound(this DrumKind d) => d switch
    {
        DrumKind.Kick => SoundKind.Kick,
        DrumKind.Snare => SoundKind.Snare,
        DrumKind.HiHat => SoundKind.HiHat,
        DrumKind.Clap => SoundKind.Clap,
        DrumKind.Cymbal => SoundKind.Cymbal,
        DrumKind.Perc => SoundKind.Perc,
        DrumKind.Kit => SoundKind.Drums,
        _ => SoundKind.DrumLoop,
    };
}

/// Famille et sorte d'un élément (sorte null : sa famille seule).
public readonly record struct Verdict(SoundFamily Family, SoundKind? Kind = null)
{
    /// « Kick », « 808 »…, sinon le nom de la famille ; null pour « À vérifier » (pas renommé).
    public string? BaseName => Family == SoundFamily.Unsure ? null : Kind?.Name() ?? Family.TrackName();

    /// Le bus du Mixer où il va (808 : Drums).
    public SoundFamily BusFamily => Kind?.BusFamily() ?? Family;
}

/// Ce qu'est un son d'après son nom (« BEAM KICK », « ZEBRA 808 », « Vocal Chop ») : la plupart des sons de packs le
/// disent, rien n'est écouté pour eux. Mots entiers, sans casse ni accents (« Kick01 » compte comme « kick ») ; null
/// si le nom ne dit rien (« Serum 2 », « Sampler »).
public static class SoundNames
{
    public static readonly Dictionary<string, SoundKind> KindWords = new()
    {
        ["vox"] = SoundKind.Vocal, ["vocal"] = SoundKind.Vocal, ["vocals"] = SoundKind.Vocal, ["voice"] = SoundKind.Vocal,
        ["voix"] = SoundKind.Vocal, ["acapella"] = SoundKind.Vocal, ["chant"] = SoundKind.Vocal,
        ["adlib"] = SoundKind.Adlib, ["adlibs"] = SoundKind.Adlib, ["choir"] = SoundKind.Choir, ["choeur"] = SoundKind.Choir,
        ["backs"] = SoundKind.Backing, ["backing"] = SoundKind.Backing, ["bvs"] = SoundKind.Backing,
        ["lead"] = SoundKind.Lead, ["leads"] = SoundKind.Lead, ["pluck"] = SoundKind.Pluck, ["plucks"] = SoundKind.Pluck,
        ["pad"] = SoundKind.Pad, ["pads"] = SoundKind.Pad,
        ["keys"] = SoundKind.Keys, ["rhodes"] = SoundKind.Keys, ["piano"] = SoundKind.Piano, ["synth"] = SoundKind.Synth,
        ["arp"] = SoundKind.Arp, ["arpeggio"] = SoundKind.Arp,
        ["chord"] = SoundKind.Chords, ["chords"] = SoundKind.Chords, ["guitar"] = SoundKind.Guitar,
        ["guitare"] = SoundKind.Guitar, ["gtr"] = SoundKind.Guitar,
        ["string"] = SoundKind.Strings, ["strings"] = SoundKind.Strings, ["violin"] = SoundKind.Strings,
        ["cello"] = SoundKind.Strings, ["bell"] = SoundKind.Bell, ["bells"] = SoundKind.Bell,
        ["flute"] = SoundKind.Flute, ["brass"] = SoundKind.Brass, ["horn"] = SoundKind.Brass, ["organ"] = SoundKind.Organ,
        ["orgue"] = SoundKind.Organ, ["melody"] = SoundKind.Melody,
        ["melodie"] = SoundKind.Melody, ["mel"] = SoundKind.Melody, ["harp"] = SoundKind.Melody, ["sax"] = SoundKind.Melody,
        ["marimba"] = SoundKind.Melody, ["kalimba"] = SoundKind.Melody,
        ["808"] = SoundKind.Bass808, ["808s"] = SoundKind.Bass808, ["sub"] = SoundKind.Sub, ["subbass"] = SoundKind.Sub,
        ["reese"] = SoundKind.Reese, ["bass"] = SoundKind.Bass, ["basse"] = SoundKind.Bass,
        ["kick"] = SoundKind.Kick, ["kicks"] = SoundKind.Kick, ["kck"] = SoundKind.Kick, ["kik"] = SoundKind.Kick,
        ["bd"] = SoundKind.Kick, ["bassdrum"] = SoundKind.Kick,
        ["snare"] = SoundKind.Snare, ["snares"] = SoundKind.Snare, ["snr"] = SoundKind.Snare, ["sd"] = SoundKind.Snare,
        ["clap"] = SoundKind.Clap, ["claps"] = SoundKind.Clap, ["clp"] = SoundKind.Clap,
        ["rim"] = SoundKind.Rim, ["rimshot"] = SoundKind.Rim, ["snap"] = SoundKind.Snap, ["snaps"] = SoundKind.Snap,
        ["hat"] = SoundKind.HiHat, ["hats"] = SoundKind.HiHat, ["hihat"] = SoundKind.HiHat, ["hihats"] = SoundKind.HiHat,
        ["hh"] = SoundKind.HiHat, ["chh"] = SoundKind.HiHat,
        ["closedhat"] = SoundKind.HiHat, ["oh"] = SoundKind.OpenHat, ["ohh"] = SoundKind.OpenHat,
        ["openhat"] = SoundKind.OpenHat, ["openhats"] = SoundKind.OpenHat,
        ["perc"] = SoundKind.Perc, ["percs"] = SoundKind.Perc, ["percussion"] = SoundKind.Perc, ["conga"] = SoundKind.Perc,
        ["bongo"] = SoundKind.Perc, ["cowbell"] = SoundKind.Perc,
        ["clave"] = SoundKind.Perc, ["tom"] = SoundKind.Tom, ["toms"] = SoundKind.Tom, ["shaker"] = SoundKind.Shaker,
        ["tamb"] = SoundKind.Shaker, ["tambourine"] = SoundKind.Shaker,
        ["crash"] = SoundKind.Crash, ["ride"] = SoundKind.Ride, ["cymbal"] = SoundKind.Cymbal, ["cym"] = SoundKind.Cymbal,
        ["splash"] = SoundKind.Cymbal, ["china"] = SoundKind.Cymbal,
        ["drum"] = SoundKind.Drums, ["drums"] = SoundKind.Drums, ["kit"] = SoundKind.Drums,
        ["drumloop"] = SoundKind.DrumLoop, ["drumloops"] = SoundKind.DrumLoop, ["breakbeat"] = SoundKind.DrumLoop,
        ["breakbeats"] = SoundKind.DrumLoop,
        ["toploop"] = SoundKind.DrumLoop, ["fill"] = SoundKind.Fill, ["fills"] = SoundKind.Fill,
        ["drumfill"] = SoundKind.Fill, ["drumfills"] = SoundKind.Fill,
        ["riser"] = SoundKind.Riser, ["risers"] = SoundKind.Riser, ["uplifter"] = SoundKind.Riser,
        ["downlifter"] = SoundKind.Downlifter, ["impact"] = SoundKind.Impact,
        ["sweep"] = SoundKind.Sweep, ["fx"] = SoundKind.Fx, ["sfx"] = SoundKind.Fx, ["whoosh"] = SoundKind.Fx,
        ["noise"] = SoundKind.Fx, ["transition"] = SoundKind.Fx, ["reverse"] = SoundKind.Fx,
        ["zap"] = SoundKind.Fx, ["laser"] = SoundKind.Fx,
    };

    /// Mots de charleston : précédés de « open » (« OPEN HAT »), c'est un Open Hat.
    public static readonly HashSet<string> HatWords = new() { "hat", "hats", "hihat", "hihats", "hh" };
    /// « Loop » seul ne dit pas quoi : avec un mot de drums, ou « top », c'est une Drum loop.
    public static readonly HashSet<string> LoopWords = new() { "loop", "loops" };

    /// Mots du nom, sans casse ni accents ; un nombre collé à la fin d'un mot est retiré (« kick01 » → « kick »), sauf
    /// pour un mot qui n'est fait que de chiffres (« 808 »).
    public static List<string> Words(string name)
    {
        var folded = Fold(name);
        var words = new List<string>();
        var current = new StringBuilder();
        void Flush()
        {
            if (current.Length == 0) return;
            var w = current.ToString();
            current.Clear();
            if (w.Any(char.IsLetter))
                while (w.Length > 0 && char.IsNumber(w[^1])) w = w[..^1];
            words.Add(w);
        }
        foreach (var c in folded)
        {
            if (char.IsLetter(c) || char.IsNumber(c)) current.Append(c); else Flush();
        }
        Flush();
        return words;
    }

    /// Sans casse ni accents (comme `folding(.caseInsensitive, .diacriticInsensitive)` du Mac).
    public static string Fold(string text)
    {
        var decomposed = text.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(decomposed.Length);
        foreach (var c in decomposed)
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark) sb.Append(c);
        return sb.ToString().Normalize(NormalizationForm.FormC).ToLowerInvariant();
    }

    /// Ce que dit chaque mot du nom, dans l'ordre (« ALTER OPEN HAT » : Open Hat).
    public static List<SoundKind> KindsIn(IReadOnlyList<string> words)
    {
        var out_ = new List<SoundKind>();
        for (var i = 0; i < words.Count; i++)
        {
            if (HatWords.Contains(words[i]) && i > 0 && words[i - 1] == "open") { out_.Add(SoundKind.OpenHat); continue; }
            if (KindWords.TryGetValue(words[i], out var k)) out_.Add(k);
        }
        return out_;
    }

    private static readonly SoundFamily[] FamilyPreference =
        { SoundFamily.Vocals, SoundFamily.Bass, SoundFamily.Fx, SoundFamily.Melody, SoundFamily.Drums };

    /// La famille : un mot de drums précis (kick, hat…) l'emporte, sinon la première nommée dans l'ordre Voix, Basse,
    /// FX, Mélodies, Drums. Dans la famille, un mot précis passe avant le mot général, et le premier dans l'ordre de
    /// `SoundKind` l'emporte (« Sub 808 » : 808 ; « Adlib Vox » : Adlib).
    public static SoundKind? KindOf(string name)
    {
        // Enregistrement fait dans FL : seul le nom de sa piste du Mixer, après la date, peut dire ce que c'est.
        var parts = Words(RecordedTrack(name) ?? name);
        var found = KindsIn(parts);
        var named = found.Select(k => k.Family()).ToHashSet();
        var looped = parts.Any(LoopWords.Contains);
        SoundFamily family;
        if (found.Any(k => k.Family() == SoundFamily.Drums && !k.IsGeneral() && k != SoundKind.Fill && k != SoundKind.DrumLoop))
            family = SoundFamily.Drums;
        else if (FamilyPreference.Where(named.Contains).Cast<SoundFamily?>().FirstOrDefault() is { } first)
            family = first;
        else if (looped && parts.Contains("top"))
            return SoundKind.DrumLoop;
        else
            return null;
        if (family == SoundFamily.Vocals && VocalLayer(parts) is { } layer) return layer;
        var mine = found.Where(k => k.Family() == family).ToList();
        // Une boucle ou un fill de drums l'emporte sur l'élément joué (« Snare Fill » : Fill ; « Hat Loop » : Drum loop).
        if (family == SoundFamily.Drums)
        {
            if (mine.Contains(SoundKind.Fill)) return SoundKind.Fill;
            if (mine.Contains(SoundKind.DrumLoop) || looped) return SoundKind.DrumLoop;
        }
        if (mine.Count == 0) return null;
        return mine.OrderBy(k => k.IsGeneral() ? 1 : 0).ThenBy(k => k.Rank()).First();
    }

    public static readonly HashSet<string> BackWords = new() { "back", "backs", "backing", "bv", "bvs" };
    public static readonly HashSet<string> AmbianceWords = new() { "ambiance", "ambience", "amb", "atmo" };

    /// Une voix lead, des backs ou une ambiance, d'après les mots d'un nom de voix ; null : rien de plus précis.
    public static SoundKind? VocalLayer(IReadOnlyList<string> parts)
    {
        if (parts.Contains("lead")) return SoundKind.VocalLead;
        if (parts.Any(BackWords.Contains)) return SoundKind.Backing;
        if (parts.Any(AmbianceWords.Contains)) return SoundKind.Ambiance;
        return null;
    }

    private static readonly Regex RecordedDate = new(@"_\d{4}-\d{2}-\d{2}[ _]\d{2}-\d{2}-\d{2}", RegexOptions.CultureInvariant);

    /// Enregistrement fait dans FL (« untitled_2026-10-15 23-37-42_Insert 5 ») : ce qui suit la date, le nom de sa
    /// piste du Mixer ; null : pas un enregistrement.
    public static string? RecordedTrack(string name)
    {
        var m = RecordedDate.Match(name);
        return m.Success ? name[(m.Index + m.Length)..] : null;
    }

    public static bool IsRecording(string name) => RecordedTrack(name) is not null;

    public static SoundFamily? FamilyOf(string name) => KindOf(name)?.Family();

    /// Synthés de mélodies : FL donne au canal le nom du plugin (« ZENOLOGY », « Serum 2 »). Ce son n'est ni des drums
    /// ni un FX : entendu comme tel, il reste une mélodie.
    public static readonly HashSet<string> MelodicSynthWords = new()
    {
        "zenology", "serum", "vital", "sylenth", "nexus", "omnisphere", "keyscape", "massive", "spire", "pigments",
        "diva", "hive", "electra", "harmor", "sytrus", "sakura", "harmless", "poizone", "morphine", "minisynth",
        "osc", "toxic", "dune", "ana", "repro", "obxd", "surge", "dexed", "keyzone", "transistor",
    };

    /// Le nom est celui d'un synthé de mélodies et ne dit rien d'autre (« Serum 2 », pas « Serum Kick »).
    public static bool IsMelodicSynth(string name) =>
        KindOf(name) is null && Words(RecordedTrack(name) ?? name).Any(MelodicSynthWords.Contains);

    /// Un nom que l'Organiser a pu donner : une sorte ou une famille (« Mélodie », « Snare », « Hi-hat »), suivie ou
    /// non d'un numéro (« Mélodie 3 »). Il ne dit rien de sûr : une analyse d'avant a pu se tromper.
    public static bool IsGenerated(string name)
    {
        var b = name.Trim();
        var space = b.LastIndexOf(' ');
        if (space >= 0 && int.TryParse(b[(space + 1)..], NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out _))
            b = b[..space];
        return GeneratedNames.Contains(b);
    }

    /// Noms que l'Organiser donne, dans la langue de l'appli.
    public static HashSet<string> GeneratedNames =>
        SoundKinds.All.Select(k => k.Name()).Concat(SoundFamilies.All.Select(f => f.TrackName()).OfType<string>()).ToHashSet();

    /// Un nom que l'Organiser a pu donner (`kind`) reste après l'écoute s'il ne la contredit pas : même famille, et pas
    /// une autre sorte. L'écoute qui ne dit rien laisse le nom.
    public static bool Keeps(SoundKind kind, Verdict heard) =>
        heard.Family == SoundFamily.Unsure || (heard.Family == kind.Family() && (heard.Kind is null || heard.Kind == kind));

    /// Mots d'une partie du morceau : un pattern ou une piste ainsi nommés gardent leur nom.
    public static readonly HashSet<string> SectionWords = new()
    {
        "intro", "outro", "verse", "couplet", "chorus", "refrain", "hook", "drop", "bridge", "pont", "break",
        "breakdown", "build", "buildup", "interlude", "prechorus", "skit", "ending", "part", "partie", "section",
        "theme",
    };

    /// Un nom choisi pour une partie du morceau (« Intro », « Refrain 2 ») qui ne dit pas ce qu'est le son : gardé.
    public static bool IsSection(string name) => KindOf(name) is null && Words(name).Any(SectionWords.Contains);
}

public static class DrumNaming
{
    /// Étiquettes de l'IA de macOS → sorte de drums (vides sur Windows : gardées pour les mêmes règles).
    public static readonly Dictionary<string, DrumKind> Labels = new()
    {
        ["bass_drum"] = DrumKind.Kick, ["snare_drum"] = DrumKind.Snare, ["hi_hat"] = DrumKind.HiHat,
        ["clapping"] = DrumKind.Clap, ["finger_snapping"] = DrumKind.Clap,
        ["cymbal"] = DrumKind.Cymbal, ["gong"] = DrumKind.Cymbal, ["tambourine"] = DrumKind.Perc, ["cowbell"] = DrumKind.Perc,
        ["tabla"] = DrumKind.Perc, ["timpani"] = DrumKind.Perc,
        ["percussion"] = DrumKind.Perc, ["drum_kit"] = DrumKind.Kit, ["drum"] = DrumKind.Kit,
    };
    public const double MinConfidence = 0.3;

    /// Ce que les mesures disent sûrement l'emporte ; sinon l'étiquette la plus sûre, sinon les mesures.
    public static DrumKind Kind(SoundFeatures f, IReadOnlyDictionary<string, double> scores)
    {
        if (Measured(f) is { } sure) return sure;
        (DrumKind Kind, double Confidence)? best = null;
        foreach (var (label, confidence) in scores)
        {
            if (!Labels.TryGetValue(label, out var kind) || confidence < MinConfidence) continue;
            if (best is { } b && (b.Confidence > confidence || (b.Confidence == confidence && (int)b.Kind <= (int)kind))) continue;
            best = (kind, confidence);
        }
        if (best is { } found) return found.Kind;
        if (IsLow(f)) return DrumKind.Kick;
        if (f.HighRatio >= HatHigh) return f.NoteLength >= CymbalLength ? DrumKind.Cymbal : DrumKind.HiHat;
        if (f.PitchedFraction >= 0.6) return DrumKind.Perc;
        if (f.Flatness >= FamilyFusion.Noisy) return f.HighRatio < 0.05 && f.LowRatio < 0.05 ? DrumKind.Clap : DrumKind.Snare;
        return DrumKind.Perc;
    }

    /// Mêmes règles avec l'IA intégrée : ce que les mesures disent sûrement d'abord (l'IA intégrée pouvant préciser un
    /// métal), puis sa sorte (`embedded`, nette), puis les étiquettes et les mesures.
    public static SoundKind Kind(SoundFeatures f, IReadOnlyDictionary<string, double> scores, SoundKind? embedded)
    {
        if (Measured(f) is { } sure)
        {
            if (sure == DrumKind.Loop) return embedded == SoundKind.Fill ? SoundKind.Fill : SoundKind.DrumLoop;
            if (embedded is { } e && Metals.Contains(e)) return e;
            return sure.Sound();
        }
        return embedded ?? Kind(f, scores).Sound();
    }

    public static readonly HashSet<SoundKind> Metals = new()
        { SoundKind.HiHat, SoundKind.OpenHat, SoundKind.Cymbal, SoundKind.Crash, SoundKind.Ride };

    public static DrumKind? Measured(SoundFeatures f)
    {
        if (IsLow(f) && f.HighRatio >= FamilyFusion.LoopHigh) return DrumKind.Loop;
        if (f.HighRatio >= SureHatHigh && f.Flatness >= FamilyFusion.Noisy)
            return f.NoteLength >= CymbalLength ? DrumKind.Cymbal : DrumKind.HiHat;
        return null;
    }

    private static bool IsLow(SoundFeatures f) =>
        f.LowRatio >= 0.5 || (f.MedianF0 > 0 && f.MedianF0 < FamilyFusion.LowF0 && f.PitchedFraction >= 0.3);

    public const double HatHigh = 0.7;
    public const double SureHatHigh = 0.85;
    public const double CymbalLength = 1.0;
}

public static class MelodyNaming
{
    public static readonly Dictionary<string, SoundKind> Labels = new()
    {
        ["piano"] = SoundKind.Piano, ["harpsichord"] = SoundKind.Piano, ["electric_piano"] = SoundKind.Keys,
        ["keyboard_musical"] = SoundKind.Keys,
        ["organ"] = SoundKind.Organ, ["electronic_organ"] = SoundKind.Organ, ["hammond_organ"] = SoundKind.Organ,
        ["accordion"] = SoundKind.Organ,
        ["guitar"] = SoundKind.Guitar, ["electric_guitar"] = SoundKind.Guitar, ["acoustic_guitar"] = SoundKind.Guitar,
        ["steel_guitar_slide_guitar"] = SoundKind.Guitar,
        ["banjo"] = SoundKind.Guitar, ["mandolin"] = SoundKind.Guitar, ["ukulele"] = SoundKind.Guitar, ["sitar"] = SoundKind.Guitar,
        ["bowed_string_instrument"] = SoundKind.Strings, ["violin_fiddle"] = SoundKind.Strings, ["cello"] = SoundKind.Strings,
        ["orchestra"] = SoundKind.Strings,
        ["flute"] = SoundKind.Flute, ["clarinet"] = SoundKind.Flute, ["oboe"] = SoundKind.Flute,
        ["wind_instrument"] = SoundKind.Flute,
        ["brass_instrument"] = SoundKind.Brass, ["french_horn"] = SoundKind.Brass, ["trumpet"] = SoundKind.Brass,
        ["trombone"] = SoundKind.Brass,
        ["bell"] = SoundKind.Bell, ["church_bell"] = SoundKind.Bell, ["chime"] = SoundKind.Bell, ["wind_chime"] = SoundKind.Bell,
        ["glockenspiel"] = SoundKind.Bell,
        ["vibraphone"] = SoundKind.Bell, ["marimba_xylophone"] = SoundKind.Bell, ["steelpan"] = SoundKind.Bell,
    };
    public const double MinConfidence = 0.3;
    public const double PluckLength = 0.35;
    public const double PadLength = 1.2;
    public const double ArpOnsets = 4.0;

    public static SoundKind? Kind(SoundFeatures f, IReadOnlyDictionary<string, double> scores)
    {
        (SoundKind Kind, double Confidence)? best = null;
        foreach (var (label, confidence) in scores)
        {
            if (!Labels.TryGetValue(label, out var kind) || confidence < MinConfidence) continue;
            if (best is { } b && (b.Confidence > confidence || (b.Confidence == confidence && b.Kind.Rank() <= kind.Rank()))) continue;
            best = (kind, confidence);
        }
        if (best is { } found) return found.Kind;
        if (f.PeakDB < FamilyFusion.SilenceDB || f.NoteLength <= 0) return null;
        if (f.NoteLength < PluckLength)
            return f.OnsetsPerSecond >= ArpOnsets && f.DistinctPitches >= 3 ? SoundKind.Arp : SoundKind.Pluck;
        if (f.NoteLength >= PadLength && f.OnsetsPerSecond < 1.5) return SoundKind.Pad;
        if (f.PitchedFraction >= 0.6) return SoundKind.Lead;
        return null;
    }

    /// Mêmes règles avec l'IA intégrée : sa sorte (`embedded`, nette) d'abord.
    public static SoundKind? Kind(SoundFeatures f, IReadOnlyDictionary<string, double> scores, SoundKind? embedded) =>
        embedded ?? Kind(f, scores);
}

/// Avis de l'IA, ramené à trois familles d'étiquettes (confiance 0…1), et celui de l'IA intégrée qui prend la même
/// place dans les règles (`Merge`).
public sealed record AILabels
{
    public double Voice { get; set; }
    public double Drums { get; set; }
    public double Instrument { get; set; }
    /// L'IA a rendu au moins un résultat.
    public bool Heard { get; set; }
    /// Probabilité de voix de l'IA intégrée (tranche la plus « voix ») ; null si elle n'a pas écouté.
    public double? EmbeddedVoice { get; set; }

    public static AILabels None => new();

    public AILabels() { }

    public AILabels(double voice, double drums = 0, double instrument = 0)
    {
        Voice = voice;
        Drums = drums;
        Instrument = instrument;
        Heard = voice > 0 || drums > 0 || instrument > 0;
    }

    /// Depuis des scores (étiquette → confiance) ; les étiquettes hors table sont ignorées.
    public static AILabels FromScores(IReadOnlyDictionary<string, double> scores)
    {
        var out_ = new AILabels { Heard = scores.Count > 0 };
        foreach (var (label, confidence) in scores)
        {
            if (!FamilyFusion.LabelTable.TryGetValue(label, out var kind)) continue;
            switch (kind)
            {
                case FamilyFusion.LabelKind.Voice: out_.Voice = Math.Max(out_.Voice, confidence); break;
                case FamilyFusion.LabelKind.Drums: out_.Drums = Math.Max(out_.Drums, confidence); break;
                default: out_.Instrument = Math.Max(out_.Instrument, confidence); break;
            }
        }
        return out_;
    }

    /// L'IA intégrée dans les règles : sa voix pour « voix-iv », ses drums et ses instruments (mélodie + basse) quand
    /// elle en entend plus.
    public void Merge(ClasseurAvis avis)
    {
        EmbeddedVoice = avis.VoixMax;
        Drums = Math.Max(Drums, avis.Familles[(int)ClasseurFamille.Drums]);
        Instrument = Math.Max(Instrument, avis.Familles[(int)ClasseurFamille.Melodie] + avis.Familles[(int)ClasseurFamille.Basse]);
    }
}

public static class FamilyFusion
{
    public enum LabelKind { Voice, Drums, Instrument }

    public static readonly Dictionary<string, LabelKind> LabelTable = BuildTable();

    private static Dictionary<string, LabelKind> BuildTable()
    {
        var t = new Dictionary<string, LabelKind>();
        foreach (var l in new[] { "speech", "singing", "rapping", "humming", "yodeling", "whispering", "shout", "yell" })
            t[l] = LabelKind.Voice;
        foreach (var l in new[] { "drum", "drum_kit", "bass_drum", "snare_drum", "tabla", "timpani", "cymbal", "hi_hat",
                     "tambourine", "cowbell", "gong", "percussion", "clapping", "finger_snapping" })
            t[l] = LabelKind.Drums;
        foreach (var l in new[] { "music", "plucked_string_instrument", "guitar", "electric_guitar",
                     "acoustic_guitar", "bass_guitar", "steel_guitar_slide_guitar", "banjo", "sitar", "mandolin",
                     "ukulele", "zither", "keyboard_musical", "piano", "electric_piano", "organ", "electronic_organ",
                     "hammond_organ", "synthesizer", "harpsichord", "bowed_string_instrument",
                     "violin_fiddle", "cello", "double_bass", "harp", "wind_instrument", "brass_instrument",
                     "french_horn", "trumpet", "trombone", "flute", "saxophone", "clarinet", "oboe", "bassoon",
                     "harmonica", "accordion", "bagpipes", "marimba_xylophone", "glockenspiel", "vibraphone",
                     "steelpan", "bell", "church_bell", "chime", "wind_chime", "orchestra", "theremin" })
            t[l] = LabelKind.Instrument;
        return t;
    }

    public const double SilenceDB = -50.0;
    public const double LowF0 = 130.0;
    public const double ShortNote = 0.4;
    public const double Tonal = 0.15;
    public const double Noisy = 0.2;
    public const double LoopHigh = 0.08;
    public const double RingHigh = 0.6;
    /// Voix au vibrato : l'IA doit au moins entendre un peu de voix.
    public const double VibratoVoice = 0.15;

    public static (SoundFamily Family, double Confidence) Decide(SoundFeatures f, AILabels ai)
    {
        var v = DecideWithRule(f, ai);
        return (v.Family, v.Confidence);
    }

    /// Famille, confiance et règle appliquée (diagnostic, jamais un nom) : silence, voix-ia, voix-iv, boucle, basse,
    /// melodie-notes, drums-court, drums-ia, cymbale, fx-bruit, voix-vibrato, melodie, fx-long, incertain.
    public static (SoundFamily Family, double Confidence, string Rule) DecideWithRule(SoundFeatures f, AILabels ai)
    {
        if (f.PeakDB < SilenceDB) return (SoundFamily.Unsure, 0, "silence");
        if (ai.Voice >= 0.5) return (SoundFamily.Vocals, ai.Voice, "voix-ia");
        if (ai.EmbeddedVoice is { } voice && voice >= ClasseurSons.SeuilVoix) return (SoundFamily.Vocals, voice, "voix-iv");
        var low = f.PitchedFraction >= 0.4 && f.MedianF0 > 0 && f.MedianF0 < LowF0 && f.LowRatio >= 0.5;
        var isShort = f.NoteLength < ShortNote;
        bool isNoisy = f.Flatness >= Noisy, isTonal = f.Flatness < Tonal;
        if (low && isShort && f.HighRatio >= LoopHigh) return (SoundFamily.Drums, Math.Max(ai.Drums, 0.75), "boucle");
        if (low && (f.NoteLength >= 0.35 || f.DistinctPitches >= 2)) return (SoundFamily.Bass, 0.8, "basse");
        if (!low && f.DistinctPitches >= 3 && f.PitchedFraction >= 0.3)
            return (SoundFamily.Melody, Math.Max(ai.Instrument, 0.7), "melodie-notes");
        if ((isShort && isNoisy) || (low && f.NoteLength < 0.35)) return (SoundFamily.Drums, Math.Max(ai.Drums, 0.75), "drums-court");
        if (isShort && ai.Drums >= 0.6 && ai.Drums > ai.Instrument && !(isTonal && f.DistinctPitches >= 3))
            return (SoundFamily.Drums, ai.Drums, "drums-ia");
        if (!isShort && isNoisy && f.HighRatio >= RingHigh && f.OnsetsPerSecond > 0) return (SoundFamily.Drums, 0.7, "cymbale");
        if (!isShort && f.PitchedFraction < 0.3 && isNoisy) return (SoundFamily.Fx, 0.7, "fx-bruit");
        if (f.Vibrato >= 0.12 && f.Vibrato <= 0.8 && f.MedianF0 >= 80 && f.MedianF0 <= 500 && f.PitchedFraction >= 0.6
            && f.NoteLength >= 0.5 && f.DistinctPitches <= 2 && ai.Instrument < 0.5
            && Math.Max(ai.Voice, ai.EmbeddedVoice ?? 0) >= VibratoVoice)
            return (SoundFamily.Vocals, 0.55, "voix-vibrato");
        if (f.PitchedFraction >= 0.5 || ai.Instrument >= 0.5 || isTonal)
            return (SoundFamily.Melody, Math.Max(ai.Instrument, 0.7), "melodie");
        if (!isShort) return (SoundFamily.Fx, 0.5, "fx-long");
        return (SoundFamily.Unsure, 0.3, "incertain");
    }
}
