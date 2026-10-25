// Organiser : le lien avec FL pour les opérations 2 à 26 du script (PROTOCOL.md §8). Les octets de chaque opération et
// le décodage des listes sont purs (testés) ; `RequestOrganizerLink` les envoie par le lien, à 20 par seconde au plus
// comme le veut le script. Les noms des sons servent à l'aperçu et aux nouveaux noms seulement : jamais journalisés.
// Miroir de Sources/FLShortcut/OrganizerLink.swift.
using System.Text;

namespace FLShortcut.Core.Organizer;

/// Genre d'éléments de FL : canaux du Channel rack, pistes du Mixer ou de la Playlist, patterns.
public enum ItemKind : byte { Channels = 1, Mixer = 2, Playlist = 3, Patterns = 4 }

/// Un canal du Channel rack, tel que le script le décrit. Type : 0 échantillon, 2 plugin, 3 layer, 4 clip audio,
/// 5 automation.
public sealed record ChannelInfo(int Index, int Type, int MixerTrack, RgbColor Color, string Name)
{
    public const int LayerType = 3;
    public const int AudioClipType = 4;
    public const int AutomationType = 5;
}

public sealed record MixerTrackInfo(int Index, RgbColor Color, string Name)
{
    /// Nom donné par FL à une piste jamais renommée (« Insert 3 », ou vide).
    public bool HasDefaultName { get { var t = Name.Trim(); return t.Length == 0 || t == $"Insert {Index}"; } }
}

/// Un pattern : index 0 = pattern 1 de FL. Nom coupé par le script (aperçu et « Revenir comme avant »).
public sealed record PatternInfo(int Index, RgbColor Color, string Name)
{
    public bool HasDefaultName { get { var t = Name.Trim(); return t.Length == 0 || t == $"Pattern {Index + 1}"; } }
}

/// Une piste de la Playlist : index 0 = piste 1 de FL.
public sealed record PlaylistTrackInfo(int Index, bool Selected, RgbColor Color, string Name)
{
    public bool HasDefaultName { get { var t = Name.Trim(); return t.Length == 0 || t == $"Track {Index + 1}"; } }
}

/// Refus de FL (raison du CC 116), panne du lien ou arrêt, avec un message pour l'utilisateur. Une exception, qui sert
/// aussi de valeur (résultat d'une analyse, d'une application) : égalité de valeur.
public sealed class OrganizerError : Exception, IEquatable<OrganizerError>
{
    public enum Kinds { Refused, Failed, Cancelled, Interrupted, Mismatch, OutdatedScript, NoResponse, FlClosed, NoSound, ProjectNotFound }

    public Kinds Kind { get; }
    public int Reason { get; }
    public string Why { get; }

    private OrganizerError(Kinds kind, int reason = 0, string why = "") : base(why.Length > 0 ? why : kind.ToString())
    {
        Kind = kind;
        Reason = reason;
        Why = why;
    }

    public static OrganizerError Refused(int reason) => new(Kinds.Refused, reason);
    public static OrganizerError Failed(string why) => new(Kinds.Failed, why: why);
    /// Échap pendant l'écoute.
    public static OrganizerError Cancelled => new(Kinds.Cancelled);
    /// La page de FL où les éléments sont déplacés n'est plus devant.
    public static OrganizerError Interrupted => new(Kinds.Interrupted);
    /// Après l'application, FL ne montre pas ce qui était prévu.
    public static OrganizerError Mismatch => new(Kinds.Mismatch);
    /// Le script chargé dans FL est l'ancien : FL doit être redémarré.
    public static OrganizerError OutdatedScript => new(Kinds.OutdatedScript);
    /// FL ne répond pas : le script n'est pas chargé (Controller type « generic controller », ports différents…).
    public static OrganizerError NoResponse => new(Kinds.NoResponse);
    public static OrganizerError FlClosed => new(Kinds.FlClosed);
    /// Pas un son reçu de FL pendant toute l'écoute.
    public static OrganizerError NoSound => new(Kinds.NoSound);
    /// Le fichier du projet ouvert reste introuvable après Ctrl+S : l'utilisateur peut le montrer.
    public static OrganizerError ProjectNotFound => new(Kinds.ProjectNotFound);

    public bool Is(Kinds kind) => Kind == kind;
    public bool IsRefused(int reason) => Kind == Kinds.Refused && Reason == reason;

    public string UserMessage => Kind switch
    {
        Kinds.Cancelled => Loc.T("Organiser arrêté : FL est remis comme avant."),
        Kinds.Interrupted => Loc.T("La page de FL a changé pendant le rangement : Organiser s'est arrêté. « Revenir comme avant » défait ce qui a été fait."),
        Kinds.Mismatch => Loc.T("FL n'a pas tout pris : vérifie dans FL, ou clique sur « Revenir comme avant »."),
        Kinds.NoResponse => Loc.T("FL ne répond pas : le script FL Shortcuts n'est pas chargé dans FL. Vérifie ces réglages, puis « Réessayer »."),
        Kinds.FlClosed => Loc.T("FL Studio n'est pas ouvert."),
        Kinds.NoSound => Loc.T("Aucun son reçu de FL pendant l'écoute. Vérifie que les sons choisis jouent bien dans FL (Master pas coupé, sortie audio de FL vers la carte son de Windows), puis « Réessayer »."),
        Kinds.ProjectNotFound => Loc.T("Je ne retrouve pas le fichier de ton projet. Clique sur « Choisir le fichier… » et montre-moi le projet ouvert dans FL (le fichier .flp). S'il n'a jamais été enregistré, enregistre-le d'abord dans FL (Fichier › Enregistrer)."),
        Kinds.OutdatedScript => Loc.T("FL utilise encore l'ancienne version du lien : redémarre FL Studio (il charge la nouvelle au lancement), puis clique sur « Réessayer »."),
        Kinds.Refused => Reason switch
        {
            1 => Loc.T("Ouvre le Channel rack, le Mixer ou la Playlist de FL (clique dedans), puis clique sur « Réessayer »."),
            2 => Loc.T("Sélectionne au moins un élément dans FL."),
            4 => Loc.T("FL joue : appuie sur Stop, puis relance Organiser."),
            6 => Loc.T("Ta version de FL ne permet pas cette étape : mets FL Studio à jour."),
            7 => Loc.T("Sélectionne au moins 2 pistes pour un dégradé."),
            _ => Loc.F("FL a refusé l'opération (raison %lld).", Reason),
        },
        _ => Why.Length == 0 ? Why : char.ToUpperInvariant(Why[0]) + Why[1..],
    };

    /// Pour le diagnostic, comme le Mac l'écrit (« refused(4) », « cancelled ») ; un échec ne dit que son type.
    public string Code => Kind switch
    {
        Kinds.Refused => $"refused({Reason})",
        Kinds.Failed => "failed",
        _ => char.ToLowerInvariant(Kind.ToString()[0]) + Kind.ToString()[1..],
    };

    public bool Equals(OrganizerError? o) => o is not null && Kind == o.Kind && Reason == o.Reason && Why == o.Why;
    public override bool Equals(object? obj) => Equals(obj as OrganizerError);
    public override int GetHashCode() => HashCode.Combine(Kind, Reason, Why);
    public override string ToString() => Code;
}

/// Une page de la réponse de `list`.
public sealed record PayloadPage<T>(int Total, int Start, List<T> Items, bool Filtered);

public static class OrganizerPayload
{
    public const int PageSize = 16;
    public const int MaxColors = 64;
    /// Opération 10 : 16 noms au plus par commande, 64 octets UTF-8 au plus chacun.
    public const int MaxNames = 16;
    public const int NameBytes = 64;

    public static byte[] Be16(int n)
    {
        var v = (ushort)Math.Clamp(n, 0, 0xFFFF);
        return new[] { (byte)(v >> 8), (byte)(v & 0xFF) };
    }

    private static byte[] Cat(params IEnumerable<byte>[] parts) => parts.SelectMany(p => p).ToArray();

    public static byte[] List(ItemKind kind, int start) => Cat(new byte[] { 2, (byte)kind }, Be16(start));
    /// Opération 2, genre 5 (script v16, API 33) : tous les canaux, comptés dans « All ».
    public static byte[] ListAllChannels(int start) => Cat(new byte[] { 2, 5 }, Be16(start));
    /// Drapeau des opérations 3 et 6 (script v16) : le canal est compté dans « All ».
    public const byte InAll = 1;

    public static byte[] Audition(int channel, byte note, byte velocity, bool all = false)
    {
        var out_ = Cat(new byte[] { 3 }, Be16(channel), new[] { Math.Min(note, (byte)127), Math.Min(velocity, (byte)127) }).ToList();
        if (all) out_.Add(InAll);
        return out_.ToArray();
    }

    /// Une commande par paquet de 64 couleurs au plus.
    public static List<byte[]> SetColors(ItemKind kind, IReadOnlyList<(int Index, RgbColor Color)> colors)
    {
        var out_ = new List<byte[]>();
        for (var from = 0; from < colors.Count; from += MaxColors)
        {
            var chunk = colors.Skip(from).Take(MaxColors).ToList();
            out_.Add(Cat(new byte[] { 4, (byte)kind, (byte)chunk.Count },
                chunk.SelectMany(c => Cat(Be16(c.Index), new[] { c.Color.R, c.Color.G, c.Color.B }))));
        }
        return out_;
    }

    public static byte[] SelectOne(ItemKind kind, int index) => Cat(new byte[] { 5, (byte)kind }, Be16(index));

    /// `pattern` : 1 = le premier pattern de FL ; null : celui qui est ouvert (script v11 pour le pattern).
    public static byte[] PlaySolo(int channel, int? pattern = null, bool all = false)
    {
        var out_ = Cat(new byte[] { 6 }, Be16(channel)).ToList();
        if (all)
        {
            // Avec le drapeau, pattern 0 : celui qui est ouvert.
            out_.AddRange(Be16(pattern ?? 0));
            out_.Add(InAll);
        }
        else if (pattern is { } p)
        {
            out_.AddRange(Be16(p));
        }
        return out_.ToArray();
    }

    /// Opération 6 sans canal seul : tous audibles.
    public const int AllChannels = 0xFFFF;
    public static byte[] Activity(ItemKind kind) => new byte[] { 14, (byte)kind };
    public static readonly byte[] Patterns = { 15 };
    public static byte[] PlaySong(double fraction) => Cat(new byte[] { 16 }, Be16((int)Math.Round(Math.Clamp(fraction, 0, 1) * 1000, MidpointRounding.AwayFromZero)));
    public static readonly byte[] StopRestore = { 7 };
    /// Opération 14, mode 1 (script v13) : les canaux qui jouent, ou ont joué depuis la lecture précédente.
    public static readonly byte[] HeardChannels = { 14, (byte)ItemKind.Channels, 1 };
    /// Opération 19 (script v13) : le tempo et la longueur de chaque pattern, 64 patterns par réponse.
    public static byte[] Lengths(int start) => Cat(new byte[] { 19 }, Be16(start));
    /// Opération 20 (script v13) : la piste du Mixer n'envoie plus qu'à ces pistes (0 = le Master).
    public static byte[] SetRoutes(int track, IReadOnlyList<int> dests) =>
        Cat(new byte[] { 20 }, Be16(track), new[] { (byte)Math.Clamp(dests.Count, 0, 255) }, dests.SelectMany(Be16));
    /// Opération 21 (script v13) : les canaux sélectionnés.
    public static readonly byte[] Selected = { 21 };
    /// Opération 22 (script v13) : le tempo multiplié pendant l'écoute (1 : le tempo d'avant).
    public static byte[] Speed(int factor) => new byte[] { 22, (byte)Math.Clamp(factor, 1, 8) };
    /// Opération 14, mode 1, pistes de la Playlist (script v14).
    public static readonly byte[] HeardTracks = { 14, (byte)ItemKind.Playlist, 1 };

    /// Opération 23 (script v14) : ces canaux seuls sélectionnés ; `count` : le nombre de canaux affichés.
    public static byte[] SelectChannels(IEnumerable<int> channels, int count)
    {
        var bits = new byte[(count + 7) / 8];
        foreach (var i in channels) if (i >= 0 && i < count) bits[i / 8] |= (byte)(1 << (i % 8));
        return Cat(new byte[] { 23 }, Be16(count), bits);
    }

    /// Opération 24 (script v14) : ce canal relié à cette piste du Mixer.
    public static byte[] LinkChannel(int channel, int track) => Cat(new byte[] { 24 }, Be16(channel), Be16(track));
    /// Opération 25 (script v14) : la position de la chanson.
    public static readonly byte[] SongPosition = { 25 };
    /// Opération 26 (script v15) : ce pattern ouvert (1 = le premier).
    public static byte[] PickPattern(int pattern) => Cat(new byte[] { 26 }, Be16(pattern));

    public static byte[] Gradient(RgbColor a, RgbColor b) => new byte[] { 8, a.R, a.G, a.B, b.R, b.G, b.B };

    public static readonly byte[] Page = { 9 };

    /// Opération 17 (script v12) : les pistes du Mixer vers lesquelles cette piste envoie.
    public static byte[] Routes(int track) => Cat(new byte[] { 17 }, Be16(track));

    /// Opération 18 (script v12) : cette page de FL devant ; null pour une autre page.
    public static byte[]? Show(FlWindow window) => window switch
    {
        FlWindow.Mixer => new byte[] { 18, 0 },
        FlWindow.ChannelRack => new byte[] { 18, 1 },
        FlWindow.Playlist => new byte[] { 18, 2 },
        _ => null,
    };

    /// Opération 13 (script v7) : bascule le mute, ou le solo, du canal `index` (0 = canal 1 du Channel rack).
    public static byte[] ToggleChannel(int index, bool solo) => Cat(new byte[] { 13, (byte)(solo ? 1 : 0) }, Be16(index));

    /// Nom en UTF-8, coupé à `NameBytes` octets sans couper un caractère ; null s'il est vide.
    public static byte[]? NameUtf8(string name)
    {
        var out_ = new List<byte>();
        var trimmed = name.Trim();
        var e = System.Globalization.StringInfo.GetTextElementEnumerator(trimmed);
        while (e.MoveNext())
        {
            var bytes = Encoding.UTF8.GetBytes((string)e.Current);
            if (out_.Count + bytes.Length > NameBytes) break;
            out_.AddRange(bytes);
        }
        return out_.Count == 0 ? null : out_.ToArray();
    }

    /// Octets d'une commande qui tiennent dans `MaxDataUnits` unités une fois en 7 bits.
    public const int MaxCommandBytes = FlProtocol.MaxDataUnits * 7 / 8;

    /// Une commande par paquet de 16 noms au plus, et qui tient dans une trame ; un nom vide n'est pas envoyé, sauf
    /// pour une piste du Mixer : FL lui remet son nom (« Insert 3 »).
    public static List<byte[]> SetNames(ItemKind kind, IReadOnlyList<(int Index, string Name)> names)
    {
        var out_ = new List<byte[]>();
        var entries = new List<byte[]>();
        void Flush()
        {
            if (entries.Count == 0) return;
            out_.Add(Cat(new byte[] { 10, (byte)kind, (byte)entries.Count }, entries.SelectMany(x => x)));
            entries.Clear();
        }
        foreach (var item in names)
        {
            var reset = item.Name.Length == 0 && kind == ItemKind.Mixer;
            var bytes = NameUtf8(item.Name) ?? (reset ? Array.Empty<byte>() : null);
            if (bytes is null) continue;
            var entry = Cat(Be16(item.Index), new[] { (byte)bytes.Length }, bytes);
            if (entries.Count == MaxNames || 3 + entries.Sum(x => x.Length) + entry.Length > MaxCommandBytes) Flush();
            entries.Add(entry);
        }
        Flush();
        return out_;
    }

    public static byte[] PlayTrack(int index) => Cat(new byte[] { 11 }, Be16(index));

    /// Position dans la chanson (0…1), en pour mille.
    public static byte[] Seek(double fraction) =>
        Cat(new byte[] { 12 }, Be16((int)Math.Round(Math.Clamp(fraction, 0, 1) * 1000, MidpointRounding.AwayFromZero)));

    private sealed class Reader
    {
        private readonly byte[] _bytes;
        public int At;
        public Reader(byte[] bytes) => _bytes = bytes;
        public bool Done => At == _bytes.Length;
        public int? U8() => At < _bytes.Length ? _bytes[At++] : null;
        public int? U16() => U8() is { } hi && U8() is { } lo ? hi << 8 | lo : null;
        public RgbColor? Color() => U8() is { } r && U8() is { } g && U8() is { } b ? new RgbColor((byte)r, (byte)g, (byte)b) : null;
        public string? Name()
        {
            if (U8() is not { } n || At + n > _bytes.Length) return null;
            var s = Encoding.UTF8.GetString(_bytes, At, n);
            At += n;
            return s;
        }
    }

    /// En-tête `[genre, total (2), début (2), n, filtré]` : null si ce n'est pas une réponse de ce genre.
    private static (int Total, int Start, int N, bool Filtered)? Header(Reader r, ItemKind kind)
    {
        if (r.U8() != (int)kind || r.U16() is not { } total || r.U16() is not { } start || r.U8() is not { } n
            || r.U8() is not { } filtered || n > PageSize || start + n > total) return null;
        return (total, start, n, filtered != 0);
    }

    public static PayloadPage<ChannelInfo>? DecodeChannels(byte[] bytes)
    {
        var r = new Reader(bytes);
        if (Header(r, ItemKind.Channels) is not { } h) return null;
        var items = new List<ChannelInfo>();
        for (var i = 0; i < h.N; i++)
        {
            if (r.U8() is not { } type || r.U16() is not { } fx || r.Color() is not { } color || r.Name() is not { } name) return null;
            items.Add(new ChannelInfo(h.Start + i, type, fx, color, name));
        }
        return r.Done ? new PayloadPage<ChannelInfo>(h.Total, h.Start, items, h.Filtered) : null;
    }

    /// Réponse de l'opération 9 : le code de la page devant.
    public static FlWindow? DecodePage(byte[] bytes) => bytes.Length == 1 ? FlWindowCodes.FromCode(bytes[0]) : null;

    /// Réponse de l'opération 11 : la longueur de la chanson en mesures (0 si FL ne la donne pas).
    public static int? DecodeBars(byte[] bytes) => bytes.Length == 2 ? bytes[0] << 8 | bytes[1] : null;

    /// Réponse de l'opération 14 : `[genre, n (2), bits]` → index des éléments qui jouent ; null si illisible.
    public static HashSet<int>? DecodeActivity(byte[] bytes, ItemKind kind)
    {
        if (bytes.Length < 3 || bytes[0] != (byte)kind) return null;
        var n = bytes[1] << 8 | bytes[2];
        if (bytes.Length != 3 + (n + 7) / 8) return null;
        var out_ = new HashSet<int>();
        for (var i = 0; i < n; i++) if ((bytes[3 + i / 8] & (1 << (i % 8))) != 0) out_.Add(i);
        return out_;
    }

    /// Réponse de l'opération 21 : `[n (2), bits]` → les canaux sélectionnés ; null si illisible.
    public static HashSet<int>? DecodeSelected(byte[] bytes)
    {
        if (bytes.Length < 2) return null;
        var n = bytes[0] << 8 | bytes[1];
        if (bytes.Length != 2 + (n + 7) / 8) return null;
        var out_ = new HashSet<int>();
        for (var i = 0; i < n; i++) if ((bytes[2 + i / 8] & (1 << (i % 8))) != 0) out_.Add(i);
        return out_;
    }

    /// Réponse de l'opération 19 : `[tempo × 100 (2), total (2), début (2), n, temps (2) × n]` ; null si illisible.
    public static (double Tempo, int Total, int Start, List<int> Beats)? DecodeLengths(byte[] bytes)
    {
        var r = new Reader(bytes);
        if (r.U16() is not { } tempo || r.U16() is not { } total || r.U16() is not { } start || r.U8() is not { } n
            || start + n > total) return null;
        var beats = new List<int>();
        for (var i = 0; i < n; i++)
        {
            if (r.U16() is not { } b) return null;
            beats.Add(b);
        }
        return r.Done ? (tempo / 100.0, total, start, beats) : null;
    }

    /// Réponse de l'opération 22 : `[tempo d'avant × 100 (2), tempo maintenant × 100 (2)]`.
    public static (double Before, double Now)? DecodeSpeed(byte[] bytes) =>
        bytes.Length == 4 ? ((bytes[0] << 8 | bytes[1]) / 100.0, (bytes[2] << 8 | bytes[3]) / 100.0) : null;

    /// Réponse de l'opération 25 : la position de la chanson (0…1).
    public static double? DecodePosition(byte[] bytes)
    {
        if (bytes.Length != 2) return null;
        var permille = bytes[0] << 8 | bytes[1];
        return permille <= 1000 ? permille / 1000.0 : null;
    }

    /// Réponse de l'opération 15 : nombre de patterns et pattern ouvert.
    public static (int Count, int Current)? DecodePatterns(byte[] bytes) =>
        bytes.Length == 4 ? (bytes[0] << 8 | bytes[1], bytes[2] << 8 | bytes[3]) : null;

    public static PayloadPage<PlaylistTrackInfo>? DecodePlaylist(byte[] bytes)
    {
        var r = new Reader(bytes);
        if (Header(r, ItemKind.Playlist) is not { } h) return null;
        var items = new List<PlaylistTrackInfo>();
        for (var i = 0; i < h.N; i++)
        {
            if (r.U8() is not { } selected || r.Color() is not { } color || r.Name() is not { } name) return null;
            items.Add(new PlaylistTrackInfo(h.Start + i, selected != 0, color, name));
        }
        return r.Done ? new PayloadPage<PlaylistTrackInfo>(h.Total, h.Start, items, h.Filtered) : null;
    }

    public static PayloadPage<PatternInfo>? DecodePatternList(byte[] bytes)
    {
        var r = new Reader(bytes);
        if (Header(r, ItemKind.Patterns) is not { } h) return null;
        var items = new List<PatternInfo>();
        for (var i = 0; i < h.N; i++)
        {
            if (r.Color() is not { } color || r.Name() is not { } name) return null;
            items.Add(new PatternInfo(h.Start + i, color, name));
        }
        return r.Done ? new PayloadPage<PatternInfo>(h.Total, h.Start, items, h.Filtered) : null;
    }

    /// Réponse de l'opération 17 : `[piste (2), n, (destination (2)) × n]` ; null si illisible ou d'une autre piste.
    public static List<int>? DecodeRoutes(byte[] bytes, int track)
    {
        var r = new Reader(bytes);
        if (r.U16() != track || r.U8() is not { } n) return null;
        var out_ = new List<int>();
        for (var i = 0; i < n; i++)
        {
            if (r.U16() is not { } d) return null;
            out_.Add(d);
        }
        return r.Done ? out_ : null;
    }

    public static PayloadPage<MixerTrackInfo>? DecodeMixer(byte[] bytes)
    {
        var r = new Reader(bytes);
        if (Header(r, ItemKind.Mixer) is not { } h) return null;
        var items = new List<MixerTrackInfo>();
        for (var i = 0; i < h.N; i++)
        {
            if (r.Color() is not { } color || r.Name() is not { } name) return null;
            items.Add(new MixerTrackInfo(h.Start + i, color, name));
        }
        return r.Done ? new PayloadPage<MixerTrackInfo>(h.Total, h.Start, items, h.Filtered) : null;
    }
}

/// Ce dont l'Organiser a besoin de FL (un faux dans les tests). Les erreurs sont des `OrganizerError`.
public interface IOrganizerLink
{
    /// Page de FL devant, vérifiée pendant l'application (déplacements, icônes).
    FlWindow Window { get; }
    /// Page de FL devant, demandée au script (opération 9).
    FlWindow Page();
    /// Canaux comptés dans « All » (script v16, API 33), même si le Channel rack montre un groupe. Remis à faux par
    /// `ListChannels` si le script ou FL ne le permettent pas.
    bool AllChannels { get; set; }
    List<ChannelInfo> ListChannels();
    List<MixerTrackInfo> ListMixer();
    /// Les `limit` premières pistes de la Playlist (toutes si elle en a moins).
    List<PlaylistTrackInfo> ListPlaylist(int limit);
    List<PatternInfo> ListPatterns();
    /// Pistes du Mixer vers lesquelles cette piste envoie (le Master compris : 0).
    List<int> Routes(int track);
    void SetRoutes(int track, IReadOnlyList<int> dests);
    (double Tempo, List<int> Beats) PatternLengths();
    (double Before, double Now) Speed(int factor);
    HashSet<int> HeardChannels();
    HashSet<int> SelectedChannels();
    HashSet<int> HeardTracks();
    double SongPosition();
    void SelectChannels(IReadOnlyCollection<int> channels, int count);
    void LinkChannel(int channel, int track);
    /// Cette page de FL devant (Channel rack, Mixer, Playlist), comme ses raccourcis F6, F9, F5.
    void Show(FlWindow window);
    void SetColors(ItemKind kind, IReadOnlyList<(int Index, RgbColor Color)> colors);
    void SetNames(ItemKind kind, IReadOnlyList<(int Index, string Name)> names);
    void SelectOne(ItemKind kind, int index);
    /// Ce canal seul audible, dans ce pattern (1 = le premier ; null : celui qui est ouvert).
    void PlaySolo(int channel, int? pattern = null);
    (int Count, int Current) PatternsInfo();
    int PickPattern(int pattern);
    HashSet<int> ActiveChannels();
    HashSet<int> ActiveTracks();
    int PlaySong(double fraction);
    int PlayTrack(int index);
    void Seek(double fraction);
    /// Toujours sans erreur : FL est remis comme avant autant que possible (appelé aussi après une erreur).
    void StopRestore();
    void Audition(int channel, byte note, byte velocity);
}

/// Opérations envoyées une par une, 60 ms au moins entre deux (le script refuse plus de 20 trames par seconde).
public sealed class RequestOrganizerLink : IOrganizerLink
{
    public static readonly TimeSpan MinInterval = TimeSpan.FromSeconds(0.06);
    /// Garde-fou : 4 096 éléments au plus (256 pages).
    public const int MaxPages = 256;

    private readonly Func<byte[], RequestReply> _request;
    private readonly Func<FlWindow> _currentWindow;
    private readonly Action<TimeSpan> _sleep;
    private DateTime? _last;
    /// Une opération 9 à 12 a déjà répondu : le script est le v6 (un refus 5 est alors une vraie donnée refusée).
    private bool _newOpsSeen;

    public bool AllChannels { get; set; }

    public RequestOrganizerLink(Func<byte[], RequestReply> request, Func<FlWindow> window, Action<TimeSpan>? sleep = null)
    {
        _request = request;
        _currentWindow = window;
        _sleep = sleep ?? Thread.Sleep;
    }

    /// Demandée au script à chaque fois ; celle reçue par le lien seulement si le script ne répond pas.
    public FlWindow Window
    {
        get
        {
            try { return Page(); }
            catch (OrganizerError) { return _currentWindow(); }
        }
    }

    public FlWindow Page()
    {
        try
        {
            if (OrganizerPayload.DecodePage(Send(OrganizerPayload.Page)) is not { } window)
                throw OrganizerError.Failed(Loc.T("page de FL illisible"));
            _newOpsSeen = true;
            return window;
        }
        catch (OrganizerError e) when (e.IsRefused(5))
        {
            for (var i = 0; i < 12; i++)
            {
                var routed = _currentWindow();
                if (routed != FlWindow.Unknown) return routed;
                _sleep(TimeSpan.FromSeconds(0.05));
            }
            throw OrganizerError.OutdatedScript;
        }
    }

    private byte[] Send(byte[] bytes)
    {
        if (_last is { } last)
        {
            var wait = MinInterval - (DateTime.UtcNow - last);
            if (wait > TimeSpan.Zero) _sleep(wait);
        }
        try
        {
            return _request(bytes) switch
            {
                RequestReply.Answered a => a.Bytes,
                RequestReply.Refused r => throw OrganizerError.Refused(r.Reason),
                RequestReply.Failed f => throw (f.Why == LinkCore.NoResponse ? OrganizerError.NoResponse : OrganizerError.Failed(f.Why)),
                _ => throw OrganizerError.Failed("?"),
            };
        }
        finally
        {
            _last = DateTime.UtcNow;
        }
    }

    public List<ChannelInfo> ListChannels()
    {
        if (AllChannels)
        {
            try
            {
                return ChannelPages(OrganizerPayload.ListAllChannels);
            }
            catch (OrganizerError e) when (e.IsRefused(5) || e.IsRefused(6))
            {
                // Script d'avant la v16 (genre inconnu : 5) ou FL d'avant l'API 33 (6) : le groupe affiché.
                AllChannels = false;
            }
        }
        return ChannelPages(start => OrganizerPayload.List(ItemKind.Channels, start));
    }

    private List<ChannelInfo> ChannelPages(Func<int, byte[]> list)
    {
        var all = new List<ChannelInfo>();
        for (var i = 0; i < MaxPages; i++)
        {
            if (OrganizerPayload.DecodeChannels(Send(list(all.Count))) is not { } page || page.Start != all.Count)
                throw OrganizerError.Failed(Loc.T("liste des canaux illisible"));
            all.AddRange(page.Items);
            if (all.Count >= page.Total || page.Items.Count == 0) return all;
        }
        throw OrganizerError.Failed(Loc.T("trop de canaux"));
    }

    public List<MixerTrackInfo> ListMixer()
    {
        var all = new List<MixerTrackInfo>();
        for (var i = 0; i < MaxPages; i++)
        {
            if (OrganizerPayload.DecodeMixer(Send(OrganizerPayload.List(ItemKind.Mixer, all.Count))) is not { } page || page.Start != all.Count)
                throw OrganizerError.Failed(Loc.T("liste du Mixer illisible"));
            all.AddRange(page.Items);
            if (all.Count >= page.Total || page.Items.Count == 0) return all;
        }
        throw OrganizerError.Failed(Loc.T("trop de pistes"));
    }

    public List<PlaylistTrackInfo> ListPlaylist(int limit)
    {
        var all = new List<PlaylistTrackInfo>();
        for (var i = 0; i < MaxPages; i++)
        {
            if (OrganizerPayload.DecodePlaylist(Send(OrganizerPayload.List(ItemKind.Playlist, all.Count))) is not { } page || page.Start != all.Count)
                throw OrganizerError.Failed(Loc.T("liste de la Playlist illisible"));
            all.AddRange(page.Items);
            if (all.Count >= Math.Min(page.Total, limit) || page.Items.Count == 0) return all.Take(limit).ToList();
        }
        throw OrganizerError.Failed(Loc.T("trop de pistes"));
    }

    public List<PatternInfo> ListPatterns()
    {
        var all = new List<PatternInfo>();
        for (var i = 0; i < MaxPages; i++)
        {
            var answer = V11(() => Send(OrganizerPayload.List(ItemKind.Patterns, all.Count)));
            if (OrganizerPayload.DecodePatternList(answer) is not { } page || page.Start != all.Count)
                throw OrganizerError.Failed(Loc.T("liste des patterns illisible"));
            all.AddRange(page.Items);
            if (all.Count >= page.Total || page.Items.Count == 0) return all;
        }
        throw OrganizerError.Failed(Loc.T("trop de patterns"));
    }

    private static OrganizerError Unreadable => OrganizerError.Failed(Loc.T("réponse de FL illisible"));

    public List<int> Routes(int track) =>
        OrganizerPayload.DecodeRoutes(V11(() => Send(OrganizerPayload.Routes(track))), track) ?? throw Unreadable;

    public void Show(FlWindow window)
    {
        if (OrganizerPayload.Show(window) is not { } bytes) return;
        V11(() => Send(bytes));
    }

    public void SetRoutes(int track, IReadOnlyList<int> dests) => V11(() => Send(OrganizerPayload.SetRoutes(track, dests)));

    public (double Tempo, List<int> Beats) PatternLengths()
    {
        var beats = new List<int>();
        var tempo = 0.0;
        for (var i = 0; i < MaxPages; i++)
        {
            var answer = V11(() => Send(OrganizerPayload.Lengths(beats.Count)));
            if (OrganizerPayload.DecodeLengths(answer) is not { } page || page.Start != beats.Count) throw Unreadable;
            tempo = page.Tempo;
            beats.AddRange(page.Beats);
            if (beats.Count >= page.Total || page.Beats.Count == 0) return (tempo, beats);
        }
        throw OrganizerError.Failed(Loc.T("trop de patterns"));
    }

    public (double Before, double Now) Speed(int factor) =>
        OrganizerPayload.DecodeSpeed(V11(() => Send(OrganizerPayload.Speed(factor)))) ?? throw Unreadable;

    public HashSet<int> HeardChannels() =>
        OrganizerPayload.DecodeActivity(V11(() => Send(OrganizerPayload.HeardChannels)), ItemKind.Channels) ?? throw Unreadable;

    public HashSet<int> SelectedChannels() =>
        OrganizerPayload.DecodeSelected(V11(() => Send(OrganizerPayload.Selected))) ?? throw Unreadable;

    public HashSet<int> HeardTracks() =>
        OrganizerPayload.DecodeActivity(V11(() => Send(OrganizerPayload.HeardTracks)), ItemKind.Playlist) ?? throw Unreadable;

    public double SongPosition() =>
        OrganizerPayload.DecodePosition(V11(() => Send(OrganizerPayload.SongPosition))) ?? throw Unreadable;

    public void SelectChannels(IReadOnlyCollection<int> channels, int count) =>
        V11(() => Send(OrganizerPayload.SelectChannels(channels, count)));

    public void LinkChannel(int channel, int track) => V11(() => Send(OrganizerPayload.LinkChannel(channel, track)));

    public void SetColors(ItemKind kind, IReadOnlyList<(int Index, RgbColor Color)> colors)
    {
        foreach (var chunk in OrganizerPayload.SetColors(kind, colors)) Send(chunk);
    }

    public void SetNames(ItemKind kind, IReadOnlyList<(int Index, string Name)> names)
    {
        foreach (var chunk in OrganizerPayload.SetNames(kind, names)) NewOps(() => Send(chunk));
    }

    public int PlayTrack(int index) =>
        OrganizerPayload.DecodeBars(NewOps(() => Send(OrganizerPayload.PlayTrack(index)))) ?? throw Unreadable;

    public void Seek(double fraction) => NewOps(() => Send(OrganizerPayload.Seek(fraction)));

    /// Opérations 10 à 12 : un script v5 les refuse (5) sans rien faire ; FL doit charger la nouvelle version.
    private T NewOps<T>(Func<T> body)
    {
        try
        {
            var out_ = body();
            _newOpsSeen = true;
            return out_;
        }
        catch (OrganizerError e) when (e.IsRefused(5) && !_newOpsSeen)
        {
            throw OrganizerError.OutdatedScript;
        }
    }

    public void SelectOne(ItemKind kind, int index) => Send(OrganizerPayload.SelectOne(kind, index));

    public void PlaySolo(int channel, int? pattern = null)
    {
        if (AllChannels) Send(OrganizerPayload.PlaySolo(channel, pattern, all: true));
        else if (pattern is null) Send(OrganizerPayload.PlaySolo(channel));
        else V11(() => Send(OrganizerPayload.PlaySolo(channel, pattern)));
    }

    public (int Count, int Current) PatternsInfo() =>
        OrganizerPayload.DecodePatterns(V11(() => Send(OrganizerPayload.Patterns))) ?? throw Unreadable;

    public int PickPattern(int pattern) =>
        (OrganizerPayload.DecodePatterns(V11(() => Send(OrganizerPayload.PickPattern(pattern)))) ?? throw Unreadable).Current;

    public HashSet<int> ActiveChannels() => Activity(ItemKind.Channels);
    public HashSet<int> ActiveTracks() => Activity(ItemKind.Playlist);

    private HashSet<int> Activity(ItemKind kind) =>
        OrganizerPayload.DecodeActivity(V11(() => Send(OrganizerPayload.Activity(kind))), kind) ?? throw Unreadable;

    public int PlaySong(double fraction) =>
        OrganizerPayload.DecodeBars(V11(() => Send(OrganizerPayload.PlaySong(fraction)))) ?? throw Unreadable;

    /// Opérations du script v11 à v16 : un script plus ancien les refuse (5) ; FL doit charger la nouvelle version.
    private static T V11<T>(Func<T> body)
    {
        try
        {
            return body();
        }
        catch (OrganizerError e) when (e.IsRefused(5))
        {
            throw OrganizerError.OutdatedScript;
        }
    }

    public void StopRestore()
    {
        // Deux essais : c'est ce qui remet les sourdines de l'utilisateur.
        for (var i = 0; i < 2; i++)
        {
            try { Send(OrganizerPayload.StopRestore); return; }
            catch (OrganizerError) { }
        }
    }

    public void Audition(int channel, byte note, byte velocity) =>
        Send(OrganizerPayload.Audition(channel, note, velocity, AllChannels));
}
