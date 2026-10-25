// Organiser : ce que l'analyse lit et comprend du projet, ce que « Revenir comme avant » garde, le réglage de chaque
// famille (couleur ou dégradé, icône) et le plan de regroupement du Channel rack. Pur (testé). Miroir des types de
// Sources/FLShortcut/OrganizerSession.swift, OrganizerApply.swift et OrganizerPlan.swift.
using System.Text.Json;
using System.Text.Json.Nodes;

namespace FLShortcut.Core.Organizer;

/// Case de la grille des icônes de FL (« Change icon… ») : 14 colonnes, 15 rangées, 0-indexées ; écrite « 3-7 ».
/// (0, 0) est « Reset » : aucune icône.
public readonly record struct FlIcon
{
    public const int Columns = 14;
    public const int Rows = 15;
    public int Column { get; }
    public int Row { get; }

    private FlIcon(int column, int row) { Column = column; Row = row; }

    public static FlIcon? Make(int column, int row) =>
        column >= 0 && column < Columns && row >= 0 && row < Rows ? new FlIcon(column, row) : null;

    public static FlIcon? FromCode(string code)
    {
        var parts = code.Split('-');
        if (parts.Length != 2 || !int.TryParse(parts[0], out var c) || !int.TryParse(parts[1], out var r)
            || c.ToString() != parts[0] || r.ToString() != parts[1]) return null;
        return Make(c, r);
    }

    public string Code => $"{Column}-{Row}";
    public bool IsReset => Column == 0 && Row == 0;
}

/// Un son du Channel rack classé, ou une piste de la Playlist classée à l'écoute (clip audio).
public sealed record OrganizerItem
{
    public required int Index { get; init; }
    public required string Name { get; init; }
    public required SoundFamily Family { get; set; }
    public required double Confidence { get; set; }
    /// Le canal se taisait dans ses patterns : classé avec les notes d'essai (confiance plus basse).
    public bool TestNotes { get; set; }
    public required int MixerTrack { get; init; }
    public required RgbColor Color { get; init; }
    /// Ce qu'est le son (Kick, 808, Open Hat…) : d'après son nom, ou pour des drums écoutés, leur sorte.
    public SoundKind? Kind { get; set; }
    /// Classé d'après son nom, sans écoute.
    public bool ByName { get; set; }
    /// Écouté : ce que l'IA intégrée en a retenu (des nombres), pour apprendre si on le corrige (CorrectionsIA).
    public SoundPrint? SoundPrint { get; set; }
}

/// Ce que l'IA intégrée retient d'un son écouté (des nombres seulement), pour apprendre si on le corrige.
public sealed record SoundPrint(float[][] Mesures, float[] Empreinte, SoundFamily FamilleIA, SoundKind? SorteIA);

/// Ce que la dernière analyse a fait, en nombres seulement (« Copier le diagnostic ») : jamais un nom.
public sealed class OrganizerDiagnostics
{
    public int Listed, Targets, ByName, Listened, Heard, TestNotes, Patterns, Scanned, WithSounds;
    public string Activity = "?";
    public int Positions, ActiveSamples, Tracks, TracksSolo, TracksHeard, MixerUsed, Routes;
    /// « Select unused channels » de FL fait (oui / non / fichier), sons laissés de côté, tempo du projet.
    public string Selection = "?";
    public int Unused, Tempo;
    /// Projet lu dans son fichier (oui, ou ce qui l'a empêché, en mots), et ses clips dans la Playlist.
    public string File = "non";
    /// Recherche du fichier du projet (nombres et mots fixes, jamais un nom ni un chemin).
    public string Search = "";
    public int Clips;
    /// Patterns ajoutés en séparant son par son ceux qui en avaient plusieurs.
    public int Split;
    /// Règle de chaque son écouté : « c4:melodie+iv12 », « c3:corrige+iv2 », « p2:fx-long ». Des numéros, jamais un nom.
    public List<string> Rules = new();
    public string PatternMap = "";
    public string TrackMap = "";
    public string Capture = "";
    public string Error = "";

    public OrganizerDiagnostics Copy()
    {
        var c = (OrganizerDiagnostics)MemberwiseClone();
        c.Rules = new List<string>(Rules);
        return c;
    }

    public string Text
    {
        get
        {
            var lines = new[]
            {
                $"canaux={Listed} sons={Targets} nom={ByName} écoutés={Listened} entendus={Heard} notes={TestNotes}",
                $"patterns={Patterns} relevés={Scanned} avec-sons={WithSounds} activité={Activity} positions={Positions} "
                    + $"relevés-chanson={ActiveSamples} pistes={Tracks} seules={TracksSolo} écoutées={TracksHeard} "
                    + $"mixer={MixerUsed} envois={Routes}",
                $"sélection={Selection} inutilisés={Unused} tempo={Tempo} fichier={File} clips={Clips} séparés={Split}",
                Search.Length == 0 ? "" : "recherche " + Search,
                Rules.Count == 0 ? "" : "règles=" + string.Join(" ", Rules),
                PatternMap.Length == 0 ? "" : "patterns-sons=" + PatternMap,
                TrackMap.Length == 0 ? "" : "pistes-sons=" + TrackMap,
                Capture,
                Error.Length == 0 ? "" : $"erreur={Error}",
            };
            return string.Join("\n", lines.Where(l => l.Length > 0));
        }
    }
}

/// Tout ce que l'analyse a lu et compris du projet.
public sealed class OrganizerResult
{
    /// Tous les canaux, dans l'ordre du Channel rack (layers et automations compris, jamais classés).
    public required List<ChannelInfo> Channels { get; init; }
    /// Sons classés, dans l'ordre du Channel rack.
    public required List<OrganizerItem> Items { get; init; }
    public List<PatternInfo> Patterns { get; set; } = new();
    /// Sons (index des canaux) qui jouent dans chaque pattern (index 0 = pattern 1) ; patterns vides absents.
    public Dictionary<int, HashSet<int>> PatternSounds { get; set; } = new();
    /// Toutes les pistes du Mixer (Master compris).
    public List<MixerTrackInfo> Mixer { get; set; } = new();
    /// Pistes du Mixer vers lesquelles envoie chaque piste reliée à un son, ou qui en reçoit (Master : 0).
    public Dictionary<int, List<int>> Routes { get; set; } = new();
    /// Pistes de la Playlist lues.
    public List<PlaylistTrackInfo> Playlist { get; set; } = new();
    /// Sons qui jouent sur chaque piste de la Playlist (index 0 = piste 1).
    public Dictionary<int, HashSet<int>> TrackSounds { get; set; } = new();
    /// Pistes sans son du Channel rack reconnu (clips audio), classées à l'écoute.
    public List<OrganizerItem> TrackItems { get; set; } = new();
    /// Sons sans aucune note : laissés de côté, ni rangés ni colorés ni renommés, puis supprimés.
    public HashSet<int> Unused { get; set; } = new();
    /// Pistes du Mixer que seuls des sons supprimés utilisaient (remises comme neuves par « Organiser »).
    public HashSet<int> Freed { get; set; } = new();
    /// Pour chaque son : une position de la chanson (0…1) où il joue, là où le moins de pistes jouent.
    public Dictionary<int, double> SoundAt { get; set; } = new();
    /// Analyse faite sur le fichier du projet : la Playlist y est rangée, dans une copie.
    public ProjectSnapshot? Project { get; set; }

    public OrganizerResult Clone() => new()
    {
        Channels = Channels.ToList(),
        Items = Items.ToList(),
        Patterns = Patterns.ToList(),
        PatternSounds = PatternSounds.ToDictionary(kv => kv.Key, kv => kv.Value.ToHashSet()),
        Mixer = Mixer.ToList(),
        Routes = Routes.ToDictionary(kv => kv.Key, kv => kv.Value.ToList()),
        Playlist = Playlist.ToList(),
        TrackSounds = TrackSounds.ToDictionary(kv => kv.Key, kv => kv.Value.ToHashSet()),
        TrackItems = TrackItems.ToList(),
        Unused = Unused.ToHashSet(),
        Freed = Freed.ToHashSet(),
        SoundAt = new Dictionary<int, double>(SoundAt),
        Project = Project,
    };

    /// Pur (testé) : le projet une fois ces canaux supprimés de FL (les suivants remontent d'autant), et l'index de
    /// chaque canal gardé, avant → maintenant. Les pistes du Mixer que seuls eux utilisaient vont dans `Freed`.
    public (OrganizerResult Result, Dictionary<int, int> Map) Removing(ISet<int> deleted)
    {
        var map = new Dictionary<int, int>();
        var kept = new List<ChannelInfo>();
        foreach (var c in Channels.OrderBy(c => c.Index))
        {
            if (deleted.Contains(c.Index)) continue;
            map[c.Index] = kept.Count;
            kept.Add(c with { Index = kept.Count });
        }
        HashSet<int> Moved(IEnumerable<int> set) => set.Where(map.ContainsKey).Select(i => map[i]).ToHashSet();
        var items = Items.Where(i => map.ContainsKey(i.Index)).Select(i => i with { Index = map[i.Index], SoundPrint = null }).ToList();
        var keptTracks = kept.Select(c => c.MixerTrack).ToHashSet();
        var out_ = new OrganizerResult
        {
            Channels = kept,
            Items = items,
            Patterns = Patterns,
            PatternSounds = PatternSounds.Select(kv => (kv.Key, Moved(kv.Value))).Where(x => x.Item2.Count > 0).ToDictionary(x => x.Key, x => x.Item2),
            Mixer = Mixer,
            Routes = Routes,
            Playlist = Playlist,
            TrackSounds = TrackSounds.Select(kv => (kv.Key, Moved(kv.Value))).Where(x => x.Item2.Count > 0).ToDictionary(x => x.Key, x => x.Item2),
            TrackItems = TrackItems,
            Unused = Moved(Unused),
            SoundAt = SoundAt.Where(kv => map.ContainsKey(kv.Key)).ToDictionary(kv => map[kv.Key], kv => kv.Value),
            Project = Project?.Moving(map),
            Freed = Freed.Union(Channels.Where(c => deleted.Contains(c.Index)).Select(c => c.MixerTrack))
                .Where(t => t > 0 && !keptTracks.Contains(t)).ToHashSet(),
        };
        return (out_, map);
    }

    /// Pur (testé) : la Playlist une fois ces patterns descendus : leurs sons quittent leur piste pour la nouvelle,
    /// une piste vide (sans nom ; sa vraie couleur est relue dans FL avant d'y toucher).
    public OrganizerResult Splitting(IEnumerable<PlaylistSplit> splits)
    {
        var out_ = Clone();
        foreach (var split in splits)
        {
            var moved = PatternSounds.GetValueOrDefault(split.Pattern) ?? new HashSet<int>();
            if (out_.TrackSounds.TryGetValue(split.From, out var from)) from.ExceptWith(moved);
            out_.TrackSounds[split.To] = moved.ToHashSet();
            if (!out_.Playlist.Any(t => t.Index == split.To))
                out_.Playlist.Add(new PlaylistTrackInfo(split.To, false, new RgbColor(0x56, 0x5D, 0x6A), ""));
        }
        out_.Playlist = out_.Playlist.OrderBy(t => t.Index).ToList();
        return out_;
    }
}

/// Ce que l'utilisateur garde dans « Organiser ».
public sealed record OrganizerOptions
{
    public bool Rack { get; init; } = true;
    public bool Patterns { get; init; } = true;
    public bool Mixer { get; init; } = true;
    public bool Playlist { get; init; } = true;
    /// Renommer (sinon : couleurs et ordre seulement).
    public bool Rename { get; init; } = true;
    /// Mixer : un bus par famille (les 808 avec les drums), chaque son envoyé seulement à son bus.
    public bool Buses { get; init; } = true;
    /// Sons sans aucune note supprimés du Channel rack, leurs pistes du Mixer remises comme neuves.
    public bool DeleteUnused { get; init; } = true;
    /// Playlist : un son par piste ; `MaxSplits` : les premiers seulement (ceux que FL a laissé faire).
    public bool SplitTracks { get; init; } = true;
    public int? MaxSplits { get; init; }
}

/// Un pattern descendu de la piste de la Playlist qu'il partage avec un autre son vers une piste vide, à lui.
public sealed record PlaylistSplit(int Pattern, int From, int To, int Sound, double At, int Kept, double KeptAt);

/// Réglage d'une famille, gardé dans les réglages : couleur, dégradé (de `Color` à `Fade`), icône.
public sealed record FamilyStyle(RgbColor Color, RgbColor? Fade = null, FlIcon? Icon = null)
{
    /// Couleur de chaque son de la famille, dans l'ordre (même arrondi que l'opération 8 du script).
    public List<RgbColor> Colors(int count)
    {
        if (count <= 0) return new List<RgbColor>();
        if (Fade is not { } fade || count <= 1) return Enumerable.Repeat(Color, count).ToList();
        return Enumerable.Range(0, count).Select(i => Color.Lerp(fade, (double)i / (count - 1))).ToList();
    }
}

/// Réglages des familles ; valeurs de départ de la conception.
public static class FamilyStyles
{
    public static readonly IReadOnlyDictionary<SoundFamily, FamilyStyle> Initial = new Dictionary<SoundFamily, FamilyStyle>
    {
        [SoundFamily.Drums] = new(new RgbColor(0xE0, 0x45, 0x3A)),
        [SoundFamily.Bass] = new(new RgbColor(0x8E, 0x5B, 0xE8)),
        [SoundFamily.Melody] = new(new RgbColor(0x3F, 0xA7, 0xE0)),
        [SoundFamily.Vocals] = new(new RgbColor(0xF2, 0xA9, 0x3B)),
        [SoundFamily.Fx] = new(new RgbColor(0x4F, 0xC4, 0x8E)),
        [SoundFamily.Unsure] = new(new RgbColor(0x8A, 0x8F, 0x98)),
    };

    /// Les réglages gardés (JSON comme sur le Mac : {"drums": {"color": "E0453A", "fade": …, "icon": "3-7"}}) ; une
    /// famille absente prend sa valeur de départ (tout illisible → valeurs de départ).
    public static Dictionary<SoundFamily, FamilyStyle> Decode(string? json)
    {
        var out_ = Initial.ToDictionary(kv => kv.Key, kv => kv.Value);
        if (string.IsNullOrEmpty(json)) return out_;
        try
        {
            if (JsonNode.Parse(json) is not JsonObject root) return out_;
            foreach (var (name, node) in root)
            {
                if (SoundFamilies.FamilyFromRaw(name) is not { } family || node is not JsonObject o) continue;
                if (o["color"]?.GetValue<string>() is not { } hex || RgbColor.FromHex(hex) is not { } color) continue;
                var fade = o["fade"]?.GetValue<string>() is { } f ? RgbColor.FromHex(f) : null;
                var icon = o["icon"]?.GetValue<string>() is { } i ? FlIcon.FromCode(i) : null;
                out_[family] = new FamilyStyle(color, fade, icon);
            }
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or FormatException)
        {
            return Initial.ToDictionary(kv => kv.Key, kv => kv.Value);
        }
        return out_;
    }

    public static string Encode(IReadOnlyDictionary<SoundFamily, FamilyStyle> styles)
    {
        var root = new JsonObject();
        foreach (var (family, style) in styles.OrderBy(kv => kv.Key.Raw(), StringComparer.Ordinal))
        {
            var o = new JsonObject { ["color"] = style.Color.Hex };
            if (style.Fade is { } fade) o["fade"] = fade.Hex;
            if (style.Icon is { } icon) o["icon"] = icon.Code;
            root[family.Raw()] = o;
        }
        return root.ToJsonString();
    }
}

/// Une remontée : l'élément à la place `From` monte de `Up` places (Alt+↑ × Up).
public readonly record struct Move(int From, int Up);

public static class RegroupPlan
{
    /// Tri stable par famille (ordre des familles ; canaux non écoutés à la fin), et dans une famille par ce qu'est le
    /// son. `Final[p]` est l'index d'origine du canal qui finit à la place p.
    public static (List<Move> Moves, List<int> Final) Make(IReadOnlyList<SoundFamily?> order, IReadOnlyList<SoundKind?>? kinds = null)
    {
        kinds ??= Array.Empty<SoundKind?>();
        var rank = order.Select(f => f?.Rank() ?? SoundFamilies.Order.Length).ToArray();
        var sub = Enumerable.Range(0, order.Count).Select(i =>
            i < kinds.Count && kinds[i] is { } k && k.Family() == order[i] ? k.RackRank() : SoundKinds.RackOrder.Length).ToArray();
        var final = Enumerable.Range(0, order.Count).OrderBy(i => rank[i]).ThenBy(i => sub[i]).ThenBy(i => i).ToList();
        return (Moves(Enumerable.Range(0, order.Count).ToList(), final), final);
    }

    /// Remontées qui ramènent la disposition `final` (place → index d'origine) dans l'ordre d'origine.
    public static List<Move> Back(IReadOnlyList<int> final) => Moves(final.ToList(), final.OrderBy(x => x).ToList());

    /// Chaque élément de `target`, dans l'ordre, est remonté à sa place (tri par insertion).
    public static List<Move> Moves(IReadOnlyList<int> current, IReadOnlyList<int> target)
    {
        var arrangement = current.ToList();
        var out_ = new List<Move>();
        for (var place = 0; place < target.Count; place++)
        {
            var id = target[place];
            var at = arrangement.IndexOf(id);
            if (at < 0 || at <= place) continue;
            out_.Add(new Move(at, at - place));
            arrangement.RemoveAt(at);
            arrangement.Insert(place, id);
        }
        return out_;
    }

    /// Disposition après une remontée (sans effet hors limites).
    public static List<int> Applying(Move move, IReadOnlyList<int> arrangement)
    {
        if (move.Up <= 0 || move.From < 0 || move.From >= arrangement.Count || move.From - move.Up < 0) return arrangement.ToList();
        var out_ = arrangement.ToList();
        var id = out_[move.From];
        out_.RemoveAt(move.From);
        out_.Insert(move.From - move.Up, id);
        return out_;
    }
}

/// Ce qu'il faut pour « Revenir comme avant » dans une page de FL.
public sealed class AreaSnapshot
{
    /// Couleur et nom d'origine de chaque élément touché, par index d'origine (Mixer : numéro de la piste).
    public Dictionary<int, RgbColor> Colors { get; set; } = new();
    public Dictionary<int, string> Names { get; set; } = new();
    /// Place → index d'origine, après ce qui a déjà été fait (Mixer : place 0 = piste 1) ; vide si rien ne bouge.
    public List<int> Arrangement { get; set; } = new();
    /// Mixer : envois d'origine des pistes changées (numéros d'origine ; 0 = le Master).
    public Dictionary<int, List<int>> Routes { get; set; } = new();
}

/// Ce qu'il faut pour « Revenir comme avant » : chaque page touchée, jusqu'à là où l'application s'est arrêtée.
public sealed class OrganizerSnapshot
{
    public AreaSnapshot? Rack { get; set; }
    public AreaSnapshot? Patterns { get; set; }
    public AreaSnapshot? Mixer { get; set; }
    public AreaSnapshot? Playlist { get; set; }
    /// Sons envoyés au Master reliés à une piste : leur piste d'avant (index d'origine du canal).
    public Dictionary<int, int>? Links { get; set; }
    /// Patterns descendus chacun sur sa piste de la Playlist, dans l'ordre (remontés à l'envers).
    public List<PlaylistSplit>? Splits { get; set; }
    /// Rangé dans une copie du projet : l'original, que « Revenir comme avant » rouvre dans FL (il n'a pas bougé).
    public string? Original { get; set; }

    public bool IsEmpty => Rack is null && Patterns is null && Mixer is null && Playlist is null && Links is null
                           && Splits is null && Original is null;
}

public sealed class ApplyOutcome
{
    public OrganizerSnapshot Snapshot { get; set; } = new();
    /// null si tout a été fait et vérifié.
    public OrganizerError? Error { get; set; }
    /// Sons sans aucune note supprimés ; ou laissés là, FL ne les ayant pas supprimés (ils restent sélectionnés).
    public int Deleted { get; set; }
    public int NotDeleted { get; set; }
    /// Pistes de la Playlist pas rangées (FL n'a pas laissé faire) : noms et couleurs sont posés.
    public bool PlaylistUnordered { get; set; }
    /// Patterns descendus chacun sur sa piste ; d'autres prévus, que FL n'a pas laissé descendre.
    public int Split { get; set; }
    public bool PlaylistMixed { get; set; }
    /// La copie rangée ouverte dans FL ; FL ne l'a pas enregistrée à la fin (à faire soi-même : Ctrl+S).
    public string? Copy { get; set; }
    public bool CopyNotSaved { get; set; }
    /// Étapes de l'application en mots et nombres (diagnostic : jamais un nom).
    public List<string> Trace { get; } = new();
}

/// Les règles communes au plan et à l'application (OrganizerApplier du Mac).
public static class Organize
{
    /// Ce qu'est chaque son classé (par index du canal), quand c'est connu (Kick, 808…).
    public static Dictionary<int, SoundKind> KindsOf(OrganizerResult result) =>
        result.Items.Where(i => i.Kind is not null).ToDictionary(i => i.Index, i => i.Kind!.Value);

    /// Famille de chaque son classé (par index du canal).
    public static Dictionary<int, SoundFamily> FamiliesOf(OrganizerResult result) =>
        result.Items.ToDictionary(i => i.Index, i => i.Family);

    /// Ce qu'est l'élément s'il va avec sa famille (une famille changée dans l'aperçu fait oublier l'ancien).
    public static SoundKind? KindOf(int index, IReadOnlyDictionary<int, SoundFamily> families, IReadOnlyDictionary<int, SoundKind> kinds)
    {
        if (!kinds.TryGetValue(index, out var kind) || !families.TryGetValue(index, out var family) || kind.Family() != family) return null;
        return kind;
    }

    /// Plan de regroupement du Channel rack : par famille, puis par ce qu'est chaque son.
    public static (List<Move> Moves, List<int> Final) RackPlan(IReadOnlyList<ChannelInfo> channels,
        IReadOnlyDictionary<int, SoundFamily> families, IReadOnlyDictionary<int, SoundKind> kinds) =>
        RegroupPlan.Make(channels.Select(c => families.TryGetValue(c.Index, out var f) ? f : (SoundFamily?)null).ToList(),
            channels.Select(c => KindOf(c.Index, families, kinds)).ToList());

    /// Icône de chaque élément : celle de sa famille ; aucune si la famille n'en a pas.
    public static Dictionary<int, FlIcon> PlannedIcons(IReadOnlyDictionary<int, SoundFamily> families,
        IReadOnlyDictionary<SoundFamily, FamilyStyle> styles)
    {
        var out_ = new Dictionary<int, FlIcon>();
        foreach (var (index, family) in families)
        {
            var style = styles.TryGetValue(family, out var s) ? s : FamilyStyles.Initial.GetValueOrDefault(family);
            if (style?.Icon is { } icon) out_[index] = icon;
        }
        return out_;
    }

    /// Couleur prévue de chaque élément (par index d'origine), famille par famille dans l'ordre `order`.
    public static Dictionary<int, RgbColor> PlannedColors(IReadOnlyDictionary<int, SoundFamily> families,
        IReadOnlyDictionary<SoundFamily, FamilyStyle> styles, IReadOnlyList<int> order)
    {
        var out_ = new Dictionary<int, RgbColor>();
        foreach (var family in SoundFamilies.Order)
        {
            var style = styles.TryGetValue(family, out var s) ? s : FamilyStyles.Initial.GetValueOrDefault(family);
            if (style is null) continue;
            var members = order.Where(i => families.TryGetValue(i, out var f) && f == family).ToList();
            var colors = style.Colors(members.Count);
            for (var k = 0; k < members.Count; k++) out_[members[k]] = colors[k];
        }
        return out_;
    }

    /// Sons à classer : ni layers ni automations.
    public static List<ChannelInfo> Sounds(IEnumerable<ChannelInfo> channels) =>
        channels.Where(c => c.Type != ChannelInfo.LayerType && c.Type != ChannelInfo.AutomationType).ToList();
}

/// Égalités de valeur pour les ensembles et les tables (comme `==` du Mac).
public static class Same
{
    public static bool Sets(ISet<int>? a, ISet<int>? b) => (a?.Count ?? 0) == (b?.Count ?? 0) && (a is null || b is null || a.SetEquals(b));

    public static bool SetMaps(IReadOnlyDictionary<int, HashSet<int>> a, IReadOnlyDictionary<int, HashSet<int>> b) =>
        a.Count == b.Count && a.All(kv => b.TryGetValue(kv.Key, out var other) && kv.Value.SetEquals(other));

    public static bool Maps<T>(IReadOnlyDictionary<int, T> a, IReadOnlyDictionary<int, T> b) =>
        a.Count == b.Count && a.All(kv => b.TryGetValue(kv.Key, out var other) && EqualityComparer<T>.Default.Equals(kv.Value, other));
}
