// Organiser : ce qui sera fait dans tout le projet, d'après ce qu'est chaque son du Channel rack (sa famille, sa
// sorte) : sons sans aucune note supprimés (leurs pistes du Mixer remises comme neuves), Channel rack regroupé
// (familles, puis sortes), pistes du Mixer dans le même ordre avec un bus par famille juste après ses pistes (808 avec
// les drums), chaque son envoyé seulement à son bus (un son envoyé au Master prend une piste libre), pistes de la
// Playlist dans le même ordre, le tout coloré par famille et renommé simplement (« Kick », « Kick 2 », « 808 »…).
// Pur (testé). Miroir de Sources/FLShortcut/OrganizerPlan.swift.
namespace FLShortcut.Core.Organizer;

public sealed class OrganizerPlan
{
    public sealed class Area
    {
        /// Couleur et nom prévus de chaque élément, par index d'origine (Mixer : numéro de la piste).
        public Dictionary<int, RgbColor> Colors { get; set; } = new();
        public Dictionary<int, string> Names { get; set; } = new();
        /// Remontées et la disposition finale (place → index d'origine). Vides : rien ne bouge.
        public List<Move> Moves { get; set; } = new();
        public List<int> Final { get; set; } = new();
        /// Ce qu'est chaque élément (aperçu, icônes).
        public Dictionary<int, Verdict> Verdicts { get; set; } = new();
        /// Mixer : pistes vers lesquelles chaque piste d'origine enverra seulement (0 = le Master), et les bus.
        public Dictionary<int, List<int>> Routes { get; set; } = new();
        public Dictionary<int, SoundFamily> Buses { get; set; } = new();
        /// Mixer : son envoyé au Master → la piste libre qu'il prend ; pistes des sons supprimés, remises comme neuves.
        public Dictionary<int, int> Links { get; set; } = new();
        public HashSet<int> Resets { get; set; } = new();

        public bool IsEmpty => Colors.Count == 0 && Names.Count == 0 && Moves.Count == 0 && Routes.Count == 0 && Links.Count == 0;
    }

    public Area Rack { get; set; } = new();
    public Area Patterns { get; set; } = new();
    public Area Mixer { get; set; } = new();
    public Area Playlist { get; set; } = new();
    /// Sons sans aucune note supprimés du Channel rack avant tout le reste (index d'origine, dans l'ordre).
    public List<int> Deleted { get; set; } = new();
    /// Playlist (sans fichier) : patterns descendus chacun sur sa piste.
    public List<PlaylistSplit> Splits { get; set; } = new();
    /// Analyse sur le fichier : la piste de chaque clip dans la copie rangée.
    public PlaylistLayout.Result? Layout { get; set; }

    /// Ce qui a servi à faire le plan : il est refait sur le Channel rack une fois les sons supprimés.
    /// `Names` : les noms écrits dans l'aperçu (« Écrire… ») ; `Slots` : la piste du Mixer choisie pour un son (1 = piste 1).
    public sealed record PlanSource(Dictionary<int, SoundFamily> Families, Dictionary<int, SoundKind> Kinds, OrganizerOptions Options,
        Dictionary<int, string> Names, Dictionary<int, int> Slots);
    public PlanSource? Source { get; set; }

    public bool IsEmpty => Rack.IsEmpty && Patterns.IsEmpty && Mixer.IsEmpty && Playlist.IsEmpty && Deleted.Count == 0 && Splits.Count == 0;

    /// Patterns descendus au plus : au-delà, la Playlist reste comme elle est.
    public const int MaxSplits = 32;
    /// Couleur d'une piste de la Playlist jamais touchée (gris de FL).
    public static readonly RgbColor PlainTrack = new(64, 64, 64);

    private const int IntMax = int.MaxValue;

    /// `families` et `kinds` : ce qu'est chaque son du Channel rack (index du canal), modifiable dans l'aperçu.
    /// `names` : les noms écrits dans l'aperçu (« Écrire… »), posés tels quels partout où le son a son nom ; `slots` :
    /// la piste du Mixer choisie pour un son (1 = piste 1, comme la case de FL dans le Channel rack).
    public static OrganizerPlan Make(OrganizerResult result, IReadOnlyDictionary<int, SoundFamily> families,
        IReadOnlyDictionary<int, SoundKind> kinds, IReadOnlyDictionary<SoundFamily, FamilyStyle> styles, OrganizerOptions? options = null,
        IReadOnlyDictionary<int, string>? names = null, IReadOnlyDictionary<int, int>? slots = null)
    {
        options ??= new OrganizerOptions();
        var written = (names ?? new Dictionary<int, string>()).Where(kv => kv.Value.Trim().Length > 0)
            .ToDictionary(kv => kv.Key, kv => kv.Value.Trim());
        slots ??= new Dictionary<int, int>();
        Verdict? VerdictOf(int channel) =>
            families.TryGetValue(channel, out var f) ? new Verdict(f, Organize.KindOf(channel, families, kinds)) : null;
        var plan = new OrganizerPlan
        {
            Source = new PlanSource(families.ToDictionary(kv => kv.Key, kv => kv.Value), kinds.ToDictionary(kv => kv.Key, kv => kv.Value),
                options, written, slots.ToDictionary(kv => kv.Key, kv => kv.Value)),
        };
        if (options.DeleteUnused) plan.Deleted = result.Unused.OrderBy(i => i).ToList();
        var deleted = plan.Deleted.ToHashSet();

        // Channel rack : l'ordre des familles, puis des sortes ; les noms numérotés dans cet ordre, sauf ceux écrits
        // dans l'aperçu, posés tels quels (jamais repris par la numérotation).
        var channels = result.Channels.OrderBy(c => c.Index).ToList();
        var rack = Organize.RackPlan(channels, families, kinds, options);
        var rackPlace = new Dictionary<int, int>();
        for (var place = 0; place < rack.Final.Count; place++) rackPlace[rack.Final[place]] = place;
        var channelNames = Numbered(rack.Final.Where(i => !written.ContainsKey(i)).Select(i => (Index: i, Name: VerdictOf(i)?.BaseName))
            .Where(x => x.Name is not null).Select(x => (x.Index, x.Name!)).ToList(), written.Values.ToHashSet());
        foreach (var (i, name) in written) if (channels.Any(c => c.Index == i)) channelNames[i] = name;
        if (options.Rack)
        {
            plan.Rack.Moves = rack.Moves;
            plan.Rack.Final = rack.Final;
            plan.Rack.Colors = Organize.PlannedColors(families, styles, rack.Final);
            var current = channels.ToDictionary(c => c.Index, c => c.Name);
            // « Renommer » décoché : seuls les noms écrits dans l'aperçu.
            plan.Rack.Names = channelNames.Where(kv => (options.Rename || written.ContainsKey(kv.Key))
                    && (!current.TryGetValue(kv.Key, out var n) || n != kv.Value))
                .ToDictionary(kv => kv.Key, kv => kv.Value);
            foreach (var channel in channels)
                if (VerdictOf(channel.Index) is { } v) plan.Rack.Verdicts[channel.Index] = v;
        }

        // Le nom qu'un pattern ou une piste où ne joue qu'un son prend : celui de ce son dans le Channel rack, s'il y est
        // renommé.
        string? SameName(IEnumerable<int> sounds)
        {
            var classified = sounds.Where(s => VerdictOf(s) is not null || written.ContainsKey(s)).ToList();
            if (!options.Rack || !options.Rename || classified.Count != 1) return null;
            return channelNames.TryGetValue(classified[0], out var n) ? n : null;
        }

        // Patterns : le nom qu'ils ont déjà s'il dit ce qu'ils sont, sinon ce qui y joue ; renommés, sauf un nom de
        // partie du morceau (« Intro »).
        if (options.Patterns)
        {
            var verdicts = new Dictionary<int, Verdict?>();
            var renamable = new HashSet<int>();
            var current = new Dictionary<int, string>();
            var fix = new Dictionary<int, string>();
            foreach (var pattern in result.Patterns)
            {
                var sounds = result.PatternSounds.GetValueOrDefault(pattern.Index) ?? new HashSet<int>();
                var heard = GroupVerdict(sounds.OrderBy(s => s).Select(VerdictOf).OfType<Verdict>().ToList());
                var v = Named(pattern.Name, heard);
                verdicts[pattern.Index] = v;
                if (v == heard && SameName(sounds) is { } name) fix[pattern.Index] = name;
                if (!SoundNames.IsSection(pattern.Name)) renamable.Add(pattern.Index);
                current[pattern.Index] = pattern.Name;
            }
            plan.Patterns = MakeArea(verdicts, result.Patterns.Select(p => p.Index).ToList(), current, styles, options.Rename, renamable, fix);
        }

        // Mixer : même ordre que le Channel rack.
        if (options.Mixer)
            plan.Mixer = MixerArea(result, VerdictOf, rackPlace, channelNames, styles, options, deleted, slots);

        // Playlist : chaque piste prend ce que jouent ses sons, renommée, sauf un nom de partie du morceau ; les pistes
        // rangées comme le Channel rack, celles qui ne jouent rien après.
        if (options.Playlist)
        {
            var res = result;
            // Place d'un groupe de sons : sa famille, sa sorte, puis son premier son dans le Channel rack.
            (int, int, int) Key(HashSet<int> sounds)
            {
                if (GroupVerdict(sounds.OrderBy(s => s).Select(VerdictOf).OfType<Verdict>().ToList()) is not { } v
                    || v.Family == SoundFamily.Unsure) return (IntMax, 0, 0);
                var first = sounds.Where(rackPlace.ContainsKey).Select(s => rackPlace[s]).DefaultIfEmpty(IntMax / 2).Min();
                return (options.FamilyRank(v.Family), v.Kind?.RackRank() ?? SoundKinds.RackOrder.Length, first);
            }
            if (res.Project is { } project)
            {
                // Analyse sur le fichier : chaque clip ira, dans la copie rangée, sur la piste de ses sons. Une ligne par
                // sorte pour les voix et les enregistrements faits dans FL (voix, guitare, piano…).
                var recorded = res.Channels.Where(c => SoundNames.IsRecording(c.Name)).Select(c => c.Index).ToHashSet();
                Verdict? LineVerdict(HashSet<int> sounds)
                {
                    var vs = sounds.OrderBy(s => s).Select(VerdictOf).OfType<Verdict>().ToList();
                    if (sounds.Count == 0 || vs.Count != sounds.Count) return null;
                    if (!(vs.All(v => v.Family == SoundFamily.Vocals) || sounds.IsSubsetOf(recorded))) return null;
                    return GroupVerdict(vs) is { } g && g.Family != SoundFamily.Unsure ? g : null;
                }
                var lines = new Dictionary<Verdict, HashSet<int>>();
                foreach (var group in project.Groups.Values.Where(g => g.Kind == PlaylistGroup.GroupKind.Sounds))
                {
                    var sounds = group.SoundSet;
                    if (LineVerdict(sounds) is { } v)
                    {
                        if (!lines.TryGetValue(v, out var all)) lines[v] = all = new HashSet<int>();
                        all.UnionWith(sounds);
                    }
                }
                PlaylistGroup Line(PlaylistGroup group)
                {
                    if (group.Kind != PlaylistGroup.GroupKind.Sounds || LineVerdict(group.SoundSet) is not { } v
                        || !lines.TryGetValue(v, out var all)) return group;
                    return PlaylistGroup.Of(all);
                }
                var layout = PlaylistLayout.Make(project.Clips,
                    c => Line(project.Groups.TryGetValue(c.Item, out var g) ? g : PlaylistGroup.Silent(0)), Key, project.TrackCount);
                res = res.Clone();
                if (layout is not null)
                {
                    plan.Layout = layout;
                    var listed = res.Playlist.ToDictionary(t => t.Index);
                    res.Playlist = Enumerable.Range(0, layout.Count)
                        .Select(i => listed.TryGetValue(i, out var t) ? t : new PlaylistTrackInfo(i, false, PlainTrack, "")).ToList();
                    res.TrackSounds = layout.Sounds.ToDictionary(kv => kv.Key, kv => kv.Value.ToHashSet());
                }
                else
                {
                    res.Playlist = new List<PlaylistTrackInfo>();
                    res.TrackSounds = new Dictionary<int, HashSet<int>>();
                }
                res.TrackItems = new List<OrganizerItem>();
            }
            else if (options.SplitTracks)
            {
                plan.Splits = PlaylistSplits(res, Key).Take(options.MaxSplits ?? MaxSplits).ToList();
                res = res.Splitting(plan.Splits);
            }
            var heardTracks = new Dictionary<int, Verdict>();
            foreach (var (track, sounds) in res.TrackSounds)
                if (GroupVerdict(sounds.OrderBy(s => s).Select(VerdictOf).OfType<Verdict>().ToList()) is { } v) heardTracks[track] = v;
            foreach (var item in res.TrackItems)
                if (!heardTracks.ContainsKey(item.Index)) heardTracks[item.Index] = new Verdict(item.Family, item.Kind);
            var verdicts = new Dictionary<int, Verdict?>();
            var renamable = new HashSet<int>();
            var current = new Dictionary<int, string>();
            var fix = new Dictionary<int, string>();
            foreach (var track in res.Playlist)
            {
                Verdict? heard = heardTracks.TryGetValue(track.Index, out var h) ? h : null;
                var v = Named(track.Name, heard);
                verdicts[track.Index] = v;
                if (v == heard && SameName(res.TrackSounds.GetValueOrDefault(track.Index) ?? new HashSet<int>()) is { } name)
                    fix[track.Index] = name;
                if (!SoundNames.IsSection(track.Name)) renamable.Add(track.Index);
                current[track.Index] = track.Name;
            }
            var order = PlaylistOrder(res, verdicts, rackPlace, options);
            plan.Playlist = MakeArea(verdicts, order, current, styles, options.Rename, renamable, fix);
            var indices = res.Playlist.Select(t => t.Index).OrderBy(i => i).ToList();
            if (res.Project is null && !order.SequenceEqual(indices) && indices.Count > 0)
            {
                plan.Playlist.Moves = RegroupPlan.Moves(Enumerable.Range(0, indices[^1] + 1).ToList(), order);
                plan.Playlist.Final = order;
            }
        }
        return plan;
    }

    private static Dictionary<int, T> Moved<T>(IReadOnlyDictionary<int, T> values, IReadOnlyDictionary<int, int> map) =>
        values.Where(kv => map.ContainsKey(kv.Key)).ToDictionary(kv => map[kv.Key], kv => kv.Value);

    /// Le même plan sur le projet une fois des sons supprimés (`map` : index d'avant → maintenant), sans rien
    /// supprimer de plus.
    public OrganizerPlan Replanned(OrganizerResult result, IReadOnlyDictionary<int, int> map, IReadOnlyDictionary<SoundFamily, FamilyStyle> styles)
    {
        if (Source is not { } source) return this;
        var rest = result.Clone();
        rest.Unused = new HashSet<int>();
        return Make(rest, Moved(source.Families, map), Moved(source.Kinds, map), styles, source.Options, Moved(source.Names, map),
            Moved(source.Slots, map));
    }

    /// Pur (testé) : les patterns à descendre pour qu'aucune piste de la Playlist ne mêle deux sons (sans fichier).
    public static List<PlaylistSplit> PlaylistSplits(OrganizerResult result, Func<HashSet<int>, (int, int, int)> key)
    {
        var patterns = result.PatternSounds.Where(kv => kv.Value.Count > 0).ToDictionary(kv => kv.Key, kv => kv.Value);
        var owners = new Dictionary<int, HashSet<int>>();
        foreach (var (pattern, sounds) in patterns)
            foreach (var sound in sounds)
            {
                if (!owners.TryGetValue(sound, out var set)) owners[sound] = set = new HashSet<int>();
                set.Add(pattern);
            }
        var places = new Dictionary<int, HashSet<int>>();
        foreach (var (track, sounds) in result.TrackSounds)
            foreach (var sound in sounds)
            {
                if (!places.TryGetValue(sound, out var set)) places[sound] = set = new HashSet<int>();
                set.Add(track);
            }
        var next = result.Playlist.Select(t => t.Index).Concat(result.TrackSounds.Keys).DefaultIfEmpty(-1).Max() + 1;
        (int Sound, double At)? HeardAt(HashSet<int> sounds)
        {
            foreach (var sound in sounds.OrderBy(s => s))
                if (result.SoundAt.TryGetValue(sound, out var at)) return (sound, at);
            return null;
        }
        var out_ = new List<PlaylistSplit>();
        foreach (var track in result.TrackSounds.Keys.OrderBy(t => t))
        {
            var sounds = result.TrackSounds[track];
            var here = patterns.Where(kv => kv.Value.Overlaps(sounds) && HeardAt(kv.Value) is not null
                    && kv.Value.All(s => owners[s].SetEquals(new[] { kv.Key }) && places.TryGetValue(s, out var p) && p.SetEquals(new[] { track })))
                .ToDictionary(kv => kv.Key, kv => kv.Value);
            if (here.Count < 2) continue;
            var ordered = here.Keys.OrderBy(p => key(here[p]).Item1).ThenBy(p => key(here[p]).Item2)
                .ThenBy(p => key(here[p]).Item3).ThenBy(p => p).ToList();
            if (HeardAt(here[ordered[0]]) is not { } stay) continue;
            foreach (var pattern in ordered.Skip(1))
            {
                if (HeardAt(here[pattern]) is not { } moved) continue;
                out_.Add(new PlaylistSplit(pattern, track, next, moved.Sound, moved.At, stay.Sound, stay.At));
                next++;
            }
        }
        return out_;
    }

    /// Le même plan, les patterns descendus limités aux `count` premiers (ceux que FL a laissé faire).
    public OrganizerPlan LimitingSplits(int count, OrganizerResult result, IReadOnlyDictionary<SoundFamily, FamilyStyle> styles)
    {
        if (Source is not { } source) return this;
        var rest = result.Clone();
        rest.Unused = new HashSet<int>();
        return Make(rest, source.Families, source.Kinds, styles, source.Options with { MaxSplits = count }, source.Names, source.Slots);
    }

    /// La Playlist prévue de nouveau sur ce projet, sans pattern à descendre en entier.
    public Area ReplannedPlaylist(OrganizerResult result, IReadOnlyDictionary<SoundFamily, FamilyStyle> styles)
    {
        if (Source is not { } source) return Playlist;
        var rest = result.Clone();
        rest.Unused = new HashSet<int>();
        return Make(rest, source.Families, source.Kinds, styles, source.Options with { SplitTracks = false }, source.Names, source.Slots).Playlist;
    }

    /// Pistes de la Playlist lues, dans l'ordre du Channel rack : familles dans leur ordre, puis sortes ; à égalité,
    /// celle dont le premier son est le plus haut dans le Channel rack, puis leur ordre d'avant.
    private static List<int> PlaylistOrder(OrganizerResult result, IReadOnlyDictionary<int, Verdict?> verdicts, IReadOnlyDictionary<int, int> rackPlace,
        OrganizerOptions options)
    {
        (int, int, int, int) Key(int t)
        {
            if (!verdicts.TryGetValue(t, out var vv) || vv is not { } v || v.Family == SoundFamily.Unsure) return (IntMax, 0, 0, t);
            var first = (result.TrackSounds.GetValueOrDefault(t) ?? new HashSet<int>()).Where(rackPlace.ContainsKey)
                .Select(s => rackPlace[s]).DefaultIfEmpty(IntMax / 2).Min();
            return (options.FamilyRank(v.Family), v.Kind?.RackRank() ?? SoundKinds.RackOrder.Length, first, t);
        }
        return result.Playlist.Select(t => t.Index).OrderBy(Key).ToList();
    }

    /// Ce qu'est un pattern ou une piste : son nom s'il dit précisément ce qu'il est, sinon ce qui y joue, sinon son
    /// nom général. Un nom que l'Organiser a pu donner cède à ce qui y joue s'il dit autre chose.
    private static Verdict? Named(string name, Verdict? heard)
    {
        if (SoundNames.KindOf(name) is not { } kind || (kind.IsGeneral() && heard is not null)) return heard;
        if (SoundNames.IsGenerated(name) && heard is { } h && !SoundNames.Keeps(kind, h)) return heard;
        return new Verdict(kind.Family(), kind);
    }

    /// Couleurs (dégradé de chaque famille dans l'ordre donné) et noms numérotés dans cet ordre ; `fixedNames` : les
    /// noms déjà décidés (celui de l'unique son), jamais repris par la numérotation. Un nom déjà porté n'est pas reposé.
    private static Area MakeArea(IReadOnlyDictionary<int, Verdict?> verdicts, IReadOnlyList<int> order, IReadOnlyDictionary<int, string> current,
        IReadOnlyDictionary<SoundFamily, FamilyStyle> styles, bool rename, ISet<int> renamable, IReadOnlyDictionary<int, string> fixedNames)
    {
        var out_ = new Area
        {
            Verdicts = verdicts.Where(kv => kv.Value is not null).ToDictionary(kv => kv.Key, kv => kv.Value!.Value),
        };
        out_.Colors = Organize.PlannedColors(out_.Verdicts.ToDictionary(kv => kv.Key, kv => kv.Value.Family), styles, order);
        if (rename)
        {
            var bases = order.Where(i => renamable.Contains(i) && !fixedNames.ContainsKey(i)
                    && out_.Verdicts.TryGetValue(i, out var v) && v.BaseName is not null)
                .Select(i => (i, out_.Verdicts[i].BaseName!)).ToList();
            var names = Numbered(bases, fixedNames.Values.ToHashSet());
            foreach (var (i, name) in fixedNames) if (renamable.Contains(i)) names[i] = name;
            out_.Names = names.Where(kv => !current.TryGetValue(kv.Key, out var c) || c != kv.Value).ToDictionary(kv => kv.Key, kv => kv.Value);
        }
        return out_;
    }

    /// Pistes du Mixer reliées à un son classé, dans l'ordre du Channel rack ; un son classé envoyé au Master prend
    /// d'abord une piste libre. Avec `buses` : un bus par famille juste après ses pistes, chaque piste envoyée
    /// seulement à son bus, le bus au Master ; une piste qui envoie déjà à une autre piste que le Master reste avec sa
    /// famille sans que ses envois changent ; « À vérifier » : sans bus. Sans : les pistes reliées par un envoi côte
    /// à côte. Les autres pistes suivent ; avec `cleanup`, celles des sons supprimés et celles qui ont un nom sans
    /// aucun son ni envoi reçu sont remises comme neuves. Une piste avec un seul son prend le nom de ce son ; un bus
    /// « <famille> Bus », s'il a encore le nom de FL.
    private static Area MixerArea(OrganizerResult result, Func<int, Verdict?> verdict, IReadOnlyDictionary<int, int> rackPlace,
        IReadOnlyDictionary<int, string> channelNames, IReadOnlyDictionary<SoundFamily, FamilyStyle> styles,
        OrganizerOptions options, ISet<int> deleted, IReadOnlyDictionary<int, int> slots)
    {
        bool rename = options.Rename, buses = options.Buses, cleanup = options.DeleteUnused;
        var last = result.Mixer.Count - 2;                            // la dernière piste est « Current »
        if (last < 1) return new Area();
        bool InRange(int t) => t >= 1 && t <= last;
        var out_ = new Area();
        var sounds = Organize.Sounds(result.Channels);
        var kept = sounds.Where(c => !deleted.Contains(c.Index)).ToList();
        // Pistes libérées par les sons supprimés (ici ou avant), qu'aucun son gardé n'utilise.
        var keptTracks = kept.Select(c => c.MixerTrack).ToHashSet();
        var freed = sounds.Where(c => deleted.Contains(c.Index)).Select(c => c.MixerTrack).Concat(result.Freed)
            .Where(t => InRange(t) && !keptTracks.Contains(t)).ToHashSet();
        // Envois entre pistes (sans le Master).
        var sources = new Dictionary<int, List<int>>();
        foreach (var (from, dests) in result.Routes)
        {
            if (!InRange(from)) continue;
            foreach (var d in dests)
            {
                if (!InRange(d) || d == from) continue;
                if (!sources.TryGetValue(d, out var list)) sources[d] = list = new List<int>();
                list.Add(from);
            }
        }
        // Pistes libres : nom de FL (ou libérée), aucun son gardé ni canal relié, aucun envoi connu ; libérées en dernier.
        var routed = sources.Keys.Concat(sources.Values.SelectMany(v => v)).ToHashSet();
        var everUsed = result.Channels.Select(c => c.MixerTrack).ToHashSet();
        var free = result.Mixer.Where(t => InRange(t.Index) && !keptTracks.Contains(t.Index) && !routed.Contains(t.Index)
                && ((t.HasDefaultName && !everUsed.Contains(t.Index)) || freed.Contains(t.Index)))
            .Select(t => t.Index).OrderBy(t => freed.Contains(t) ? 1 : 0).ThenBy(t => t).ToList();
        int Place(int index) => rackPlace.TryGetValue(index, out var p) ? p : IntMax;
        // Un son classé envoyé au Master : une piste libre, dans l'ordre du Channel rack.
        foreach (var channel in kept.OrderBy(c => Place(c.Index)))
        {
            if (channel.MixerTrack != 0 || verdict(channel.Index) is null || free.Count == 0) continue;
            out_.Links[channel.Index] = free[0];
            free.RemoveAt(0);
        }
        var linked = new Dictionary<int, List<int>>();                // piste → sons, dans l'ordre du Channel rack
        foreach (var channel in kept)
        {
            if (verdict(channel.Index) is null) continue;
            var track = out_.Links.TryGetValue(channel.Index, out var l) ? l : channel.MixerTrack;
            if (!InRange(track)) continue;
            if (!linked.TryGetValue(track, out var list)) linked[track] = list = new List<int>();
            list.Add(channel.Index);
        }
        foreach (var track in linked.Keys.ToList()) linked[track] = linked[track].OrderBy(Place).ToList();
        var key = new Dictionary<int, double>();
        foreach (var (track, members) in linked)
        {
            key[track] = members.Where(rackPlace.ContainsKey).Select(m => rackPlace[m]).DefaultIfEmpty(IntMax / 2).Min();
            if (GroupVerdict(members.Select(verdict).OfType<Verdict>().ToList()) is { } v) out_.Verdicts[track] = v;
        }
        (double, int) SortKey(int t) => (key.TryGetValue(t, out var k) ? k : IntMax / 2, t);

        var layout = new List<int>();
        if (linked.Count > 0)
        {
            layout = buses
                ? BusLayout(linked, sources, result.Routes, free, SortKey, out_)
                : GroupedLayout(linked, sources, key, out_);
        }
        // Pistes des sons supprimés pas reprises, et pistes nommées sans aucun son ni envoi reçu : comme neuves.
        var idle = cleanup
            ? result.Mixer.Where(t => InRange(t.Index) && !t.HasDefaultName && !everUsed.Contains(t.Index) && !sources.ContainsKey(t.Index))
                .Select(t => t.Index).ToHashSet()
            : new HashSet<int>();
        out_.Resets = freed.Union(idle).Except(layout).Except(out_.Links.Values).ToHashSet();
        // Places choisies dans l'aperçu : d'abord celles des sons (la case de chaque son, comme dans le Channel rack de
        // FL), puis le départ de chaque famille, dans l'ordre des familles (ses pistes à la suite, son bus compris).
        var pins = new List<(int Track, int Slot)>();
        foreach (var channel in kept.OrderBy(c => Place(c.Index)))
        {
            if (!slots.TryGetValue(channel.Index, out var slot) || verdict(channel.Index) is null) continue;
            var track = out_.Links.TryGetValue(channel.Index, out var l) ? l : channel.MixerTrack;
            if (InRange(track)) pins.Add((track, slot));
        }
        foreach (var family in options.FamilyOrder)
        {
            if ((styles.TryGetValue(family, out var style) ? style : FamilyStyles.Initial.GetValueOrDefault(family))?.MixerStart is not { } start) continue;
            foreach (var track in layout.Where(t => out_.Verdicts.TryGetValue(t, out var v) && v.BusFamily == family))
                pins.Add((track, start));
        }
        var relevant = layout.ToHashSet();
        if (relevant.Count > 0)
        {
            var target = Pinned(layout, pins, last);
            var currentOrder = Enumerable.Range(1, target.Count).ToList();
            if (!target.SequenceEqual(currentOrder)) out_.Moves = RegroupPlan.Moves(currentOrder, target);
            out_.Final = target;
            out_.Colors = Organize.PlannedColors(out_.Verdicts.ToDictionary(kv => kv.Key, kv => kv.Value.Family), styles, target);
        }
        var fresh = DefaultColor(result, everUsed, routed);
        var byIndex = result.Mixer.ToDictionary(t => t.Index);
        foreach (var track in out_.Resets)
        {
            if (fresh is { } f && (!byIndex.TryGetValue(track, out var info) || info.Color != f)) out_.Colors[track] = f;
            if (byIndex.TryGetValue(track, out var t2) && !t2.HasDefaultName) out_.Names[track] = "";
        }
        if (rename)
        {
            var bases = new List<(int, string)>();
            var taken = new HashSet<string>();
            foreach (var track in layout)
            {
                if (linked.TryGetValue(track, out var members) && members.Count == 1 && channelNames.TryGetValue(members[0], out var name))
                {
                    out_.Names[track] = name;
                    taken.Add(name);
                }
                else if (out_.Verdicts.TryGetValue(track, out var v) && v.BaseName is { } b)
                {
                    if (linked.ContainsKey(track)) bases.Add((track, b));
                    else if ((byIndex.TryGetValue(track, out var info) && info.HasDefaultName) || freed.Contains(track))
                        bases.Add((track, Loc.F("%@ Bus", b)));
                }
            }
            foreach (var (k, v) in Numbered(bases, taken)) out_.Names.TryAdd(k, v);
            out_.Names = out_.Names.Where(kv => !byIndex.TryGetValue(kv.Key, out var info) || info.Name != kv.Value)
                .ToDictionary(kv => kv.Key, kv => kv.Value);
        }
        return out_;
    }

    /// Pur (testé) : la disposition du Mixer (place p → piste d'origine, place 0 = piste 1) avec les places choisies :
    /// chaque piste de `pins` à sa place (1 = piste 1), ou à la suivante libre si elle est prise (la première dans
    /// `pins` l'emporte), jamais au-delà de `last` ; les autres pistes de `auto` dans leur ordre, puis toutes les autres
    /// dans le leur. Sans place choisie : `auto`, puis les autres pistes jusqu'à la plus grande.
    public static List<int> Pinned(IReadOnlyList<int> auto, IReadOnlyList<(int Track, int Slot)> pins, int last)
    {
        var taken = new Dictionary<int, int>();                     // place → piste
        var pinned = new HashSet<int>();
        foreach (var (track, slot) in pins)
        {
            if (pinned.Contains(track) || track < 1 || track > last) continue;
            var at = Math.Max(1, slot);
            while (at <= last && taken.ContainsKey(at)) at++;
            if (at > last) continue;
            taken[at] = track;
            pinned.Add(track);
        }
        var size = auto.Concat(pinned).Concat(taken.Keys).DefaultIfEmpty(0).Max();
        var autoSet = auto.ToHashSet();
        var rest = new Queue<int>(auto.Where(t => !pinned.Contains(t))
            .Concat(Enumerable.Range(1, size).Where(t => !autoSet.Contains(t) && !pinned.Contains(t))));
        var out_ = new List<int>(size);
        for (var place = 1; place <= size; place++) out_.Add(taken.TryGetValue(place, out var t) ? t : rest.Dequeue());
        return out_;
    }

    /// Couleur d'une piste du Mixer jamais touchée (la plus fréquente parmi celles qui ont le nom de FL, sans son ni
    /// envoi) ; null s'il n'y en a pas.
    private static RgbColor? DefaultColor(OrganizerResult result, ISet<int> used, ISet<int> routed)
    {
        var last = result.Mixer.Count - 2;
        if (last < 1) return null;
        var counts = new Dictionary<RgbColor, int>();
        foreach (var t in result.Mixer)
        {
            if (t.Index < 1 || t.Index > last || !t.HasDefaultName || used.Contains(t.Index) || routed.Contains(t.Index)) continue;
            counts[t.Color] = counts.GetValueOrDefault(t.Color) + 1;
        }
        if (counts.Count == 0) return null;
        // La plus fréquente ; à égalité, la plus petite en hexadécimal.
        return counts.OrderByDescending(kv => kv.Value).ThenBy(kv => kv.Key.Hex, StringComparer.Ordinal).First().Key;
    }

    /// Un bus par famille : les pistes de la famille (808 : Drums) dans l'ordre du Channel rack, puis son bus ; les
    /// familles dans l'ordre de leur premier son ; une piste « À vérifier » seule à sa place. Seules les pistes qui
    /// n'envoient qu'au Master vont dans le bus. Un bus déjà là reçoit des pistes de la famille qui n'envoient qu'à lui.
    private static List<int> BusLayout(Dictionary<int, List<int>> linked, Dictionary<int, List<int>> sources,
        Dictionary<int, List<int>> routes, List<int> free, Func<int, (double, int)> sortKey, Area out_)
    {
        // Pistes qui envoient déjà à une autre piste que le Master : leurs envois ne changent pas.
        var sendsOn = sources.Values.SelectMany(v => v).ToHashSet();
        var members = new Dictionary<SoundFamily, List<int>>();
        var alone = new List<int>();
        foreach (var track in linked.Keys)
        {
            if (out_.Verdicts.TryGetValue(track, out var v) && v.Family != SoundFamily.Unsure)
            {
                if (!members.TryGetValue(v.BusFamily, out var list)) members[v.BusFamily] = list = new List<int>();
                list.Add(track);
            }
            else
            {
                alone.Add(track);
            }
        }
        // Bus déjà là : une piste sans son qui reçoit le plus de pistes de la famille.
        var taken = linked.Keys.ToHashSet();
        var busOf = new Dictionary<SoundFamily, int>();
        foreach (var family in SoundFamilies.Order)
        {
            if (!members.TryGetValue(family, out var tracks)) continue;
            var mine = tracks.ToHashSet();
            var candidates = sources.Where(kv => !taken.Contains(kv.Key))
                .Select(kv => (Track: kv.Key, Count: kv.Value.Count(f => mine.Contains(f) && routes.TryGetValue(f, out var r) && r.Count == 1 && r[0] == kv.Key)))
                .Where(c => c.Count > 0).ToList();
            if (candidates.Count > 0)
            {
                var best = candidates.OrderByDescending(c => c.Count).ThenBy(c => c.Track).First();
                busOf[family] = best.Track;
                taken.Add(best.Track);
            }
        }
        // Sinon une piste libre.
        free.RemoveAll(taken.Contains);
        foreach (var family in SoundFamilies.Order)
        {
            if (busOf.ContainsKey(family) || free.Count == 0) continue;
            if (!(members.GetValueOrDefault(family) ?? new List<int>()).Any(t => !sendsOn.Contains(t))) continue;
            busOf[family] = free[0];
            free.RemoveAt(0);
        }
        var blocks = alone.Select(t => new List<int> { t }).ToList();
        foreach (var (family, tracks) in members)
        {
            var sorted = tracks.OrderBy(t => sortKey(t)).ToList();
            if (!busOf.TryGetValue(family, out var bus))
            {
                blocks.Add(sorted);
                continue;
            }
            blocks.Add(sorted.Append(bus).ToList());
            foreach (var t in sorted) if (!sendsOn.Contains(t)) out_.Routes[t] = new List<int> { bus };
            if (!sendsOn.Contains(bus)) out_.Routes[bus] = new List<int> { 0 };
            out_.Buses[bus] = family;
            out_.Verdicts[bus] = new Verdict(family);
        }
        return blocks.OrderBy(b => sortKey(b[0])).SelectMany(b => b).ToList();
    }

    /// Sans bus : les pistes reliées par un envoi d'un bloc, celle qui reçoit juste après la dernière qui lui envoie.
    private static List<int> GroupedLayout(Dictionary<int, List<int>> linked, Dictionary<int, List<int>> sources,
        Dictionary<int, double> key, Area out_)
    {
        var relevant = linked.Keys.ToHashSet();
        var grew = true;
        while (grew)
        {
            grew = false;
            foreach (var (d, froms) in sources)
            {
                if (relevant.Contains(d) || !froms.Any(relevant.Contains)) continue;
                relevant.Add(d);
                grew = true;
            }
        }
        for (var pass = 0; pass < relevant.Count; pass++)                  // groupes de groupes : une passe par niveau
        {
            foreach (var track in relevant.OrderBy(t => t))
            {
                if (linked.ContainsKey(track)) continue;
                var fromKeys = (sources.GetValueOrDefault(track) ?? new List<int>()).Where(key.ContainsKey).Select(f => key[f]).ToList();
                if (fromKeys.Count > 0) key[track] = fromKeys.Max() + 0.5;
            }
        }
        var group = relevant.ToDictionary(t => t, t => t);
        int Root(int t)
        {
            while (group.TryGetValue(t, out var up) && up != t) t = up;
            return t;
        }
        foreach (var (d, froms) in sources)
        {
            if (!relevant.Contains(d)) continue;
            foreach (var from in froms)
            {
                if (!relevant.Contains(from)) continue;
                int a = Root(from), b = Root(d);
                if (a != b) group[Math.Max(a, b)] = Math.Min(a, b);
            }
        }
        var blocks = new Dictionary<int, List<int>>();
        foreach (var track in relevant)
        {
            var r = Root(track);
            if (!blocks.TryGetValue(r, out var list)) blocks[r] = list = new List<int>();
            list.Add(track);
        }
        (double, int) Ordered(int t) => (key.TryGetValue(t, out var k) ? k : IntMax / 2, t);
        var layout = blocks.Values.Select(b => b.OrderBy(Ordered).ToList()).OrderBy(b => Ordered(b[0])).SelectMany(b => b).ToList();
        // Une piste de groupe : la famille des pistes qui lui envoient.
        foreach (var track in layout)
        {
            if (linked.ContainsKey(track)) continue;
            var from = (sources.GetValueOrDefault(track) ?? new List<int>()).Where(out_.Verdicts.ContainsKey).Select(f => out_.Verdicts[f]).ToList();
            if (GroupVerdict(from) is { } v) out_.Verdicts[track] = new Verdict(v.Family);
        }
        return layout;
    }

    /// Pur (testé) : ce qu'est un ensemble de sons : la famille la plus présente (« À vérifier » seulement s'il n'y a
    /// rien d'autre ; égalité : l'ordre des familles), et leur sorte quand tous ceux de cette famille disent la même ;
    /// null s'il n'y a rien.
    public static Verdict? GroupVerdict(IReadOnlyList<Verdict> members)
    {
        var sure = members.Where(v => v.Family != SoundFamily.Unsure).ToList();
        var pool = sure.Count == 0 ? members.ToList() : sure;
        if (pool.Count == 0) return null;
        var family = pool.GroupBy(v => v.Family).OrderByDescending(g => g.Count()).ThenBy(g => g.Key.Rank()).First().Key;
        var same = pool.Where(v => v.Family == family).ToList();
        var kinds = same.Where(v => v.Kind is not null).Select(v => v.Kind!.Value).Distinct().ToList();
        SoundKind? kind = kinds.Count == 1 && same.All(v => v.Kind is not null) ? kinds[0] : null;
        return new Verdict(family, kind);
    }

    /// Pur (testé) : noms numérotés dans l'ordre donné (« Kick », « Kick 2 »…), sans reprendre un nom de `taken`.
    public static Dictionary<int, string> Numbered(IReadOnlyList<(int Index, string Name)> bases, ISet<string>? taken = null)
    {
        var count = new Dictionary<string, int>();
        var used = taken is null ? new HashSet<string>() : new HashSet<string>(taken);
        var out_ = new Dictionary<int, string>();
        foreach (var (index, baseName) in bases)
        {
            var n = count.GetValueOrDefault(baseName);
            string name;
            do
            {
                n++;
                name = n == 1 ? baseName : $"{baseName} {n}";
            } while (used.Contains(name));
            count[baseName] = n;
            used.Add(name);
            out_[index] = name;
        }
        return out_;
    }
}
