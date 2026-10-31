// Ce que l'Organiser lit dans un projet de FL (.flp) : les canaux du Channel rack, les sons qui jouent dans chaque
// pattern (leurs notes), chaque clip de la Playlist (pattern ou canal, piste, position, longueur) ; puis la copie
// rangée, où seuls les clips changent de piste. Tout est lu, rien n'est deviné : ce qui ne ressemble pas exactement à
// ce qui est attendu arrête tout (`FlpException` Unsupported). Format : PROTOCOL.md §9. Pur (testé).
// Miroir de Sources/FLShortcut/FLPProject.swift.
namespace FLShortcut.Core.Organizer;

public sealed record FlpChannel(int Iid, int? Type, string? Name, IReadOnlyList<int> Children, string? SamplePath = null)
{
    /// Nom de ce fichier, sans dossier ni extension.
    public string? Sample => SamplePath is null ? null : FlpProject.FileName(SamplePath);

    public bool Equals(FlpChannel? o) => o is not null && Iid == o.Iid && Type == o.Type && Name == o.Name
        && Children.SequenceEqual(o.Children) && SamplePath == o.SamplePath;
    public override int GetHashCode() => HashCode.Combine(Iid, Type, Name, SamplePath);
}

/// Ce que joue un clip : un pattern (1 = pattern 1) ou un canal du Channel rack (clip audio, automation).
public readonly record struct ClipSource(bool IsPattern, int Number)
{
    public static ClipSource Pattern(int n) => new(true, n);
    public static ClipSource Channel(int c) => new(false, c);
}

/// `Item` : rang du clip dans la Playlist du fichier ; début et longueur en pas (`ppq` par noire) ; `Track` : 0 = piste 1.
public sealed record FlpClip(int Item, ClipSource Source, int Position, int Length, int Track)
{
    public int End => Position + Math.Max(Length, 1);
}

public sealed class FlpProject
{
    public static class Ev
    {
        public const byte ChannelType = 21;
        public const byte Channel = 64;
        public const byte Pattern = 65;
        public const byte Children = 94;
        public const byte Arrangement = 99;
        /// Arrangement ouvert (écrit après les arrangements).
        public const byte CurrentArrangement = 100;
        /// Groupe affiché par le Channel rack (-1 : « All »), écrit avant les canaux.
        public const byte ChannelGroup = 146;
        public const byte PatternName = 193;
        /// Chemin du fichier de son d'un canal.
        public const byte SamplePath = 196;
        public const byte ChannelName = 203;
        public const byte MixerName = 204;
        public const byte Notes = 224;
        public const byte Playlist = 233;
        public const byte MixerParams = 236;
        public const byte Track = 238;
        public const byte TrackName = 239;
    }

    /// Une note : 24 octets (position, drapeaux, canal sur 2 octets à la place 6…).
    public const int NoteSize = 24;
    /// Un clip de la Playlist : 88 octets (FL 2024 et plus), 60 (FL 21) ou 32 (avant).
    public static readonly int[] ItemSizes = { 88, 60, 32 };
    /// Écrit dans chaque clip devant son numéro : au-delà, un pattern ; en dessous, un canal.
    public const int PatternBase = 0x5000;
    /// Dans une piste (238) : 1 à cette place si elle joue, 0 si elle est coupée.
    public const int TrackEnabled = 12;
    /// Type d'un layer dans le fichier.
    public const int LayerType = 3;

    public int Ppq { get; }
    public List<FlpChannel> Channels { get; }
    /// Pour chaque pattern qui a des notes (1 = pattern 1) : ses canaux et leur nombre de notes.
    public Dictionary<int, Dictionary<int, int>> Notes { get; }
    /// Nom de chaque pattern nommé (1 = pattern 1).
    public Dictionary<int, string> PatternNames { get; }
    /// Clips de la Playlist (celle de l'arrangement qui en a).
    public List<FlpClip> Clips { get; }
    /// Pistes de la Playlist (500 dans FL 20 et plus).
    public int TrackCount { get; }
    /// Où écrire : l'événement de la Playlist, la taille d'un clip, l'événement de chaque piste (dans l'ordre).
    public int? PlaylistEvent { get; }
    public int ItemSize { get; }
    public List<int> TrackEvents { get; }
    /// Notes de chaque pattern (1 = pattern 1) : l'événement 224 ; et le premier canal (les notes sont écrites avant).
    public Dictionary<int, int> NoteEvents { get; }
    public int? FirstChannelEvent { get; }
    /// Événement du groupe affiché par le Channel rack (null : pas écrit) ; vrai si ce n'est pas « All ».
    public int? GroupEvent { get; }
    public bool ShowsGroup { get; }
    /// Pistes coupées (mute) dans FL (0 = piste 1) : un clip qui en part ou y arrive changerait de son.
    public HashSet<int> MutedTracks { get; }

    private sealed class OpenChannel
    {
        public int Iid;
        public int? Type;
        public string? Name;
        public List<int> Children = new();
        public string? SamplePath;
    }

    private sealed class ArrangementRead
    {
        public int Index;
        public int? Playlist;
        public List<int> Tracks = new();
    }

    public FlpProject(FlpFile file)
    {
        var channels = new List<FlpChannel>();
        OpenChannel? channel = null;
        var notes = new Dictionary<int, Dictionary<int, int>>();
        var noteEvents = new Dictionary<int, int>();
        int? firstChannel = null;
        var names = new Dictionary<int, string>();
        int? pattern = null;
        var arrangements = new List<ArrangementRead>();
        int? current = null;
        (int Event, uint Value)? group = null;
        void CloseChannel()
        {
            if (channel is not null)
                channels.Add(new FlpChannel(channel.Iid, channel.Type, channel.Name, channel.Children.ToArray(), channel.SamplePath));
            channel = null;
        }
        var events = file.Events;
        for (var i = 0; i < events.Count; i++)
        {
            var e = events[i];
            switch (e.Id)
            {
                case Ev.Channel:
                    // Un canal commence par son numéro suivi de son type ; le même numéro d'événement sert ailleurs
                    // (réglages MIDI du projet, avant les canaux) : ignoré.
                    if (i + 1 >= events.Count || events[i + 1].Id != Ev.ChannelType) break;
                    CloseChannel();
                    if ((int)e.Value != channels.Count) throw FlpException.Unsupported("canaux");
                    channel = new OpenChannel { Iid = (int)e.Value, Type = (int)events[i + 1].Value };
                    firstChannel ??= i;
                    break;
                case Ev.ChannelName:
                    if (channel is not null && channel.Name is null) channel.Name = e.Text;
                    break;
                case Ev.SamplePath:
                    if (channel is not null && channel.SamplePath is null) channel.SamplePath = e.Text;
                    break;
                case Ev.Children:
                    channel?.Children.Add((int)e.Value);
                    break;
                case Ev.Pattern:
                    // Les patterns (noms, couleurs) sont écrits au milieu du premier canal : il ne prend plus rien après.
                    CloseChannel();
                    if (e.Value < 1) throw FlpException.Unsupported("patterns");
                    pattern = (int)e.Value;
                    break;
                case Ev.PatternName:
                    if (pattern is { } named) names[named] = e.Text;
                    break;
                case Ev.Notes:
                    if (pattern is not { } p || e.Bytes.Length % NoteSize != 0) throw FlpException.Unsupported("notes");
                    if (firstChannel is null) noteEvents[p] = i;
                    for (var start = 0; start < e.Bytes.Length; start += NoteSize)
                    {
                        var on = (int)FlpBytes.UInt(e.Bytes, start + 6, 2);
                        if (!notes.TryGetValue(p, out var byChannel)) notes[p] = byChannel = new Dictionary<int, int>();
                        byChannel[on] = byChannel.GetValueOrDefault(on) + 1;
                    }
                    break;
                case Ev.Arrangement:
                    CloseChannel();
                    pattern = null;
                    arrangements.Add(new ArrangementRead { Index = (int)e.Value });
                    break;
                case Ev.CurrentArrangement:
                    if (arrangements.Count > 0) current = (int)e.Value;
                    break;
                case Ev.ChannelGroup:
                    if (channels.Count == 0 && channel is null && group is null) group = (i, e.Value);
                    break;
                case Ev.Playlist:
                    if (arrangements.Count == 0 || arrangements[^1].Playlist is not null) throw FlpException.Unsupported("playlist");
                    arrangements[^1].Playlist = i;
                    break;
                case Ev.Track:
                    if (arrangements.Count == 0) throw FlpException.Unsupported("pistes");
                    arrangements[^1].Tracks.Add(i);
                    break;
                case Ev.MixerName:
                case Ev.MixerParams:
                    // Le Mixer suit les canaux : un nom d'effet n'est jamais pris pour celui d'un canal.
                    CloseChannel();
                    break;
            }
        }
        CloseChannel();
        // L'en-tête dit combien de canaux le projet a : la lecture doit les avoir tous trouvés.
        if (file.ChannelCount != 0 && channels.Count != file.ChannelCount) throw FlpException.Unsupported("canaux");
        Channels = channels;
        Notes = notes;
        NoteEvents = noteEvents;
        FirstChannelEvent = firstChannel;
        PatternNames = names;
        Ppq = file.Ppq;
        if (Ppq <= 0) throw FlpException.Unsupported("ppq");
        if (!notes.Values.All(n => n.Keys.All(k => k < channels.Count))) throw FlpException.Unsupported("notes");

        GroupEvent = group?.Event;
        ShowsGroup = group is { } g && g.Value != 0xFFFF_FFFF;
        // L'arrangement rangé : celui qui est ouvert dans FL ; sans le savoir, le seul qui a des clips.
        var filled = arrangements.Where(a => a.Playlist is { } pl && events[pl].Bytes.Length > 0).ToList();
        var open = current is { } c ? arrangements.FirstOrDefault(a => a.Index == c) : null;
        if (open is null && filled.Count > 1) throw FlpException.Unsupported("arrangements");
        var arrangement = open ?? filled.FirstOrDefault();
        if (arrangement?.Playlist is not { } playlist || events[playlist].Bytes.Length == 0)
        {
            PlaylistEvent = null;
            ItemSize = ItemSizes[0];
            TrackEvents = (open ?? arrangements.FirstOrDefault())?.Tracks.ToList() ?? new List<int>();
            TrackCount = TrackEvents.Count;
            MutedTracks = new HashSet<int>();
            Clips = new List<FlpClip>();
            return;
        }
        PlaylistEvent = playlist;
        TrackEvents = arrangement.Tracks.ToList();
        TrackCount = TrackEvents.Count;
        if (TrackCount <= 0) throw FlpException.Unsupported("pistes");
        var muted = new HashSet<int>();
        for (var t = 0; t < TrackEvents.Count; t++)
        {
            var data = events[TrackEvents[t]].Bytes;
            // Chaque piste dit son numéro (1 = piste 1), sa couleur et si elle joue : dans l'ordre, sans trou.
            if (data.Length <= TrackEnabled || FlpBytes.UInt(data, 0, 4) != t + 1) throw FlpException.Unsupported("pistes");
            if (data[TrackEnabled] == 0) muted.Add(t);
        }
        MutedTracks = muted;
        var bytes = events[playlist].Bytes;
        if (ItemSizeOf(bytes) is not { } size) throw FlpException.Unsupported("clips");
        ItemSize = size;
        var clips = new List<FlpClip>();
        for (int start = 0, n = 0; start < bytes.Length; start += size, n++)
        {
            var index = (int)FlpBytes.UInt(bytes, start + 6, 2);
            var reversed = (int)FlpBytes.UInt(bytes, start + 12, 2);
            if (reversed >= TrackCount) throw FlpException.Unsupported("clips");
            var source = index > PatternBase ? ClipSource.Pattern(index - PatternBase) : ClipSource.Channel(index);
            if (!source.IsPattern && source.Number >= channels.Count) throw FlpException.Unsupported("clips");
            clips.Add(new FlpClip(n, source, (int)FlpBytes.UInt(bytes, start, 4), (int)FlpBytes.UInt(bytes, start + 8, 4),
                TrackCount - 1 - reversed));
        }
        Clips = clips;
    }

    /// Taille d'un clip : celle (une seule) pour laquelle chaque clip porte la marque des clips à sa place.
    public static int? ItemSizeOf(byte[] bytes)
    {
        var fits = ItemSizes.Where(size => bytes.Length % size == 0 && Enumerable.Range(0, bytes.Length / size)
            .All(k => FlpBytes.UInt(bytes, k * size + 4, 2) == PatternBase)).ToList();
        return fits.Count == 1 ? fits[0] : null;
    }

    /// Sons qui jouent dans ce pattern (1 = pattern 1) : ses canaux qui ont des notes, un layer remplacé par ce qu'il
    /// joue.
    public HashSet<int> SoundsOf(int pattern) =>
        Played(Notes.TryGetValue(pattern, out var n) ? n.Keys.ToHashSet() : new HashSet<int>());

    /// Un layer joue ses canaux (et ceux des layers qu'il contient).
    public HashSet<int> Played(IEnumerable<int> channels)
    {
        var out_ = new HashSet<int>();
        var todo = channels.ToList();
        var seen = new HashSet<int>();
        while (todo.Count > 0)
        {
            var c = todo[^1];
            todo.RemoveAt(todo.Count - 1);
            if (!seen.Add(c)) continue;
            var layer = c < Channels.Count && Channels[c].Type == LayerType;
            var children = layer ? Channels[c].Children : Array.Empty<int>();
            if (children.Count == 0) out_.Add(c); else todo.AddRange(children);
        }
        return out_;
    }

    /// Nom d'un fichier d'après son chemin (« …/Packs/Drums/D30 Kick 85.wav » : « D30 Kick 85 ») ; null s'il est vide.
    public static string? FileName(string path)
    {
        var last = path.Split('/', '\\').LastOrDefault(s => s.Length > 0) ?? "";
        var dot = last.LastIndexOf('.');
        var name = dot >= 0 ? last[..dot] : last;
        return name.Length == 0 ? null : name;
    }

    /// Pur (testé) : « Split by channel » de FL sur tout le projet. Un pattern où jouent plusieurs canaux garde les
    /// notes de son premier canal ; chaque autre canal a son nouveau pattern (numéros après le dernier), avec ses
    /// notes, et chaque clip de ce pattern, dans chaque arrangement, a son double à la même place et sur la même piste
    /// pour chaque nouveau pattern. Le morceau sonne pareil. Les clips sont ensuite écrits dans l'ordre de leur début,
    /// comme FL. Renvoie le fichier et le nombre de patterns ajoutés.
    public (FlpFile File, int Added) SplitByChannel(FlpFile file)
    {
        var several = NoteEvents.Keys.OrderBy(k => k).Where(k => (Notes.GetValueOrDefault(k)?.Count ?? 0) > 1).ToList();
        if (several.Count == 0) return (file, 0);
        if (FirstChannelEvent is not { } insertAt) throw FlpException.Unsupported("patterns");
        var out_ = file.Clone();
        var next = file.Events.Where(e => e.Id == Ev.Pattern).Select(e => (int)e.Value).DefaultIfEmpty(0).Max() + 1;
        var added = new List<FlpEvent>();
        var copies = new Dictionary<int, List<int>>();               // pattern d'origine → nouveaux patterns
        foreach (var pattern in several)
        {
            if (!NoteEvents.TryGetValue(pattern, out var index)) continue;
            var bytes = file.Events[index].Bytes;
            var byChannel = new Dictionary<int, List<byte>>();
            for (var start = 0; start < bytes.Length; start += NoteSize)
            {
                var on = (int)FlpBytes.UInt(bytes, start + 6, 2);
                if (!byChannel.TryGetValue(on, out var list)) byChannel[on] = list = new List<byte>();
                list.AddRange(bytes[start..(start + NoteSize)]);
            }
            var order = byChannel.Keys.OrderBy(k => k).ToList();
            if (order.Count == 0) continue;
            out_.Events[index] = out_.Events[index].With(byChannel[order[0]].ToArray());
            foreach (var on in order.Skip(1))
            {
                if (next > 999) throw FlpException.Unsupported("patterns");
                added.Add(new FlpEvent(Ev.Pattern, FlpBytes.Le(next, 2)));
                added.Add(new FlpEvent(Ev.Notes, byChannel[on].ToArray()));
                if (!copies.TryGetValue(pattern, out var made)) copies[pattern] = made = new List<int>();
                made.Add(next);
                next++;
            }
        }
        for (var i = 0; i < out_.Events.Count; i++)
        {
            var e = out_.Events[i];
            if (e.Id != Ev.Playlist || e.Bytes.Length == 0) continue;
            if (ItemSizeOf(e.Bytes) is not { } size) throw FlpException.Unsupported("clips");
            var items = new List<byte[]>();
            for (var start = 0; start < e.Bytes.Length; start += size)
            {
                var item = e.Bytes[start..(start + size)];
                items.Add(item);
                var source = (int)FlpBytes.UInt(item, 6, 2);
                if (source <= PatternBase) continue;
                foreach (var made in copies.GetValueOrDefault(source - PatternBase) ?? new List<int>())
                {
                    var copy = (byte[])item.Clone();
                    FlpBytes.Put((uint)(PatternBase + made), copy, 6, 2);
                    items.Add(copy);
                }
            }
            // Tri stable par début (OrderBy de .NET est stable : à égalité, l'ordre d'avant).
            var sorted = items.Select((item, n) => (item, n))
                .OrderBy(x => FlpBytes.UInt(x.item, 0, 4)).ThenBy(x => x.n).SelectMany(x => x.item).ToArray();
            out_.Events[i] = e.With(sorted);
        }
        out_.Events.InsertRange(insertAt, added);
        return (out_, added.Count / 2);
    }

    /// Le Channel rack de la copie montre tous les sons (« All ») : la suite se fait sur tous. Rien d'autre ne change.
    public FlpFile ShowingAll(FlpFile file)
    {
        var out_ = file.Clone();
        if (GroupEvent is { } g) out_.Events[g] = out_.Events[g].With(new byte[] { 0xFF, 0xFF, 0xFF, 0xFF });
        return out_;
    }

    /// La copie rangée : chaque clip sur sa nouvelle piste (`tracks` : rang du clip → piste, 0 = piste 1). Les pistes
    /// où il y a des clips, avant ou après, perdent leur nom, reprennent la couleur des pistes jamais touchées et
    /// jouent. Un clip sur une piste coupée arrête tout (il se mettrait à jouer). Tout le reste est recopié octet pour
    /// octet.
    public FlpFile Rearranged(FlpFile file, IReadOnlyDictionary<int, int> tracks)
    {
        var out_ = ShowingAll(file);
        if (PlaylistEvent is not { } playlistEvent) return out_;
        if (!Clips.All(c => !MutedTracks.Contains(c.Track))) throw FlpException.Unsupported("piste coupée");
        var bytes = (byte[])out_.Events[playlistEvent].Bytes.Clone();
        foreach (var (item, track) in tracks)
        {
            if (item < 0 || item >= Clips.Count || track < 0 || track >= TrackCount) throw FlpException.Unsupported("clips");
            FlpBytes.Put((uint)(TrackCount - 1 - track), bytes, item * ItemSize + 12, 2);
        }
        out_.Events[playlistEvent] = out_.Events[playlistEvent].With(bytes);

        var touched = Clips.Select(c => c.Track).Concat(Clips.Select(c => tracks.TryGetValue(c.Item, out var t) ? t : c.Track))
            .ToHashSet();
        var counts = new Dictionary<uint, int>();
        foreach (var index in TrackEvents)
        {
            var color = FlpBytes.UInt(file.Events[index].Bytes, 4, 4);
            counts[color] = counts.GetValueOrDefault(color) + 1;
        }
        // La couleur la plus fréquente ; à égalité, la plus petite.
        uint plain = counts.Count == 0 ? 0 : counts.OrderByDescending(kv => kv.Value).ThenBy(kv => kv.Key).First().Key;
        var removed = new List<int>();
        foreach (var track in touched.OrderBy(t => t))
        {
            var index = TrackEvents[track];
            var data = (byte[])out_.Events[index].Bytes.Clone();
            FlpBytes.Put(plain, data, 4, 4);
            data[TrackEnabled] = 1;
            out_.Events[index] = out_.Events[index].With(data);
            var next = index + 1;
            while (next < out_.Events.Count && next <= index + 3 && out_.Events[next].Id != Ev.Track
                   && out_.Events[next].Id != Ev.Arrangement)
            {
                if (out_.Events[next].Id == Ev.TrackName) removed.Add(next);
                next++;
            }
        }
        foreach (var index in removed.OrderByDescending(i => i)) out_.Events.RemoveAt(index);
        return out_;
    }
}

/// Ce que joue un clip, pour ranger la Playlist : ses sons (rangs du Channel rack) ; un pattern où rien ne joue
/// (seul sur sa piste) ; un canal qui n'est pas un son (automation : seul sur sa piste). Égalité de valeur.
public sealed class PlaylistGroup : IEquatable<PlaylistGroup>
{
    public enum GroupKind { Sounds, Silent, Other }

    public GroupKind Kind { get; }
    /// Sons, triés (Sounds) ; vide sinon.
    public IReadOnlyList<int> Sounds { get; }
    /// Le pattern (Silent) ou le canal (Other).
    public int Number { get; }

    private PlaylistGroup(GroupKind kind, IReadOnlyList<int> sounds, int number)
    {
        Kind = kind;
        Sounds = sounds;
        Number = number;
    }

    public static PlaylistGroup Of(IEnumerable<int> sounds) => new(GroupKind.Sounds, sounds.Distinct().OrderBy(s => s).ToArray(), 0);
    public static PlaylistGroup Silent(int pattern) => new(GroupKind.Silent, Array.Empty<int>(), pattern);
    public static PlaylistGroup Other(int channel) => new(GroupKind.Other, Array.Empty<int>(), channel);

    public HashSet<int> SoundSet => Sounds.ToHashSet();

    public bool Equals(PlaylistGroup? o) => o is not null && Kind == o.Kind && Number == o.Number && Sounds.SequenceEqual(o.Sounds);
    public override bool Equals(object? obj) => Equals(obj as PlaylistGroup);
    public override int GetHashCode()
    {
        var h = new HashCode();
        h.Add(Kind);
        h.Add(Number);
        foreach (var s in Sounds) h.Add(s);
        return h.ToHashCode();
    }
    public override string ToString() => Kind == GroupKind.Sounds ? $"sons[{string.Join(",", Sounds)}]" : $"{Kind}({Number})";
}

/// Playlist rangée : chaque son sur sa piste, tous les clips qui jouent les mêmes sons réunis sur la même piste.
public static class PlaylistLayout
{
    public sealed class Result
    {
        /// Nouvelle piste de chaque clip (rang du clip → piste, 0 = piste 1).
        public Dictionary<int, int> Tracks { get; } = new();
        /// Sons qui jouent sur chaque piste (les pistes sans son n'y sont pas).
        public Dictionary<int, HashSet<int>> Sounds { get; } = new();
        /// Pistes utilisées (les premières).
        public int Count { get; set; }
    }

    /// Pur (testé) : chaque groupe a sa piste, les groupes de sons dans l'ordre de `key` (familles, sortes, place dans
    /// le Channel rack) puis de leur premier clip ; ensuite les patterns muets, puis le reste (automations). Un clip qui
    /// en chevaucherait un autre du même groupe va sur une piste de plus, juste dessous : jamais l'un sur l'autre.
    /// null : plus de pistes qu'il n'y en a dans FL.
    public static Result? Make(IReadOnlyList<FlpClip> clips, Func<FlpClip, PlaylistGroup> group,
        Func<HashSet<int>, (int, int, int)> key, int trackCount)
    {
        var members = new Dictionary<PlaylistGroup, List<FlpClip>>();
        foreach (var clip in clips)
        {
            var g = group(clip);
            if (!members.TryGetValue(g, out var list)) members[g] = list = new List<FlpClip>();
            list.Add(clip);
        }
        List<FlpClip> Sorted(PlaylistGroup g) =>
            members[g].OrderBy(c => c.Position).ThenBy(c => c.Track).ThenBy(c => c.Item).ToList();
        int[] Rank(PlaylistGroup g)
        {
            var first = Sorted(g)[0];
            switch (g.Kind)
            {
                case PlaylistGroup.GroupKind.Sounds:
                    var k = key(g.SoundSet);
                    return new[] { 0, k.Item1, k.Item2, k.Item3, first.Position, first.Track, first.Item };
                case PlaylistGroup.GroupKind.Silent:
                    return new[] { 1, 0, 0, 0, first.Position, first.Track, first.Item };
                default:
                    return new[] { 2, 0, 0, 0, first.Position, first.Track, first.Item };
            }
        }
        var order = members.Keys.Select(g => (Group: g, Rank: Rank(g))).ToList();
        order.Sort((a, b) => Lexicographic(a.Rank, b.Rank));
        var out_ = new Result();
        foreach (var (g, _) in order)
        {
            var lanes = new List<List<FlpClip>>();
            foreach (var clip in Sorted(g))
            {
                var free = lanes.FindIndex(lane => lane.All(o => o.End <= clip.Position || clip.End <= o.Position));
                if (free >= 0) lanes[free].Add(clip); else lanes.Add(new List<FlpClip> { clip });
            }
            foreach (var lane in lanes)
            {
                var track = out_.Count;
                out_.Count++;
                foreach (var clip in lane) out_.Tracks[clip.Item] = track;
                if (g.Kind == PlaylistGroup.GroupKind.Sounds && g.Sounds.Count > 0) out_.Sounds[track] = g.SoundSet;
            }
        }
        return out_.Count <= trackCount ? out_ : null;
    }

    /// Comparaison de deux suites de nombres, élément par élément (la plus courte d'abord à égalité).
    public static int Lexicographic(IReadOnlyList<int> a, IReadOnlyList<int> b)
    {
        for (var i = 0; i < Math.Min(a.Count, b.Count); i++)
        {
            var c = a[i].CompareTo(b[i]);
            if (c != 0) return c;
        }
        return a.Count.CompareTo(b.Count);
    }
}
