// FL simulé pour l'Organiser : tout le projet (Channel rack, patterns, Mixer, Playlist), journal des opérations, mémo
// de l'écoute comme le script, déplacements au clavier (Alt+↑ dans le Channel rack, Alt+← dans le Mixer) ; capture et
// disque simulés. Miroir de FakeOrganizerLink, FakeAudio et FakeDisk (Tests/FLShortcutTests).
using FLShortcut.Core.Organizer;

namespace FLShortcut.Core.Tests;

public sealed class FakeOrganizerLink : IOrganizerLink
{
    public FlWindow Window { get; set; } = FlWindow.ChannelRack;
    public List<ChannelInfo> Channels = new();
    /// Toutes les pistes du Mixer, Master compris (index = numéro de la piste).
    public List<MixerTrackInfo> Mixer = new();
    public List<PlaylistTrackInfo> Playlist = new();
    public List<PatternInfo> PatternList = new();
    /// Script v14 simulé ; faux : un ancien script, qui refuse ses nouvelles opérations.
    public bool V14 = true;
    public List<int> Lengths = new();
    public double Tempo = 120;
    public HashSet<int> UnusedSelection = new();
    public bool Song = true;
    /// Sons qui jouent dans chaque pattern (1 = le premier).
    public Dictionary<int, HashSet<int>> PatternSounds = new();
    public Dictionary<int, HashSet<int>> TrackChannels = new();
    public Dictionary<int, List<int>> RoutesMap = new();
    public int CurrentPattern = 1;
    public int Bars = 32;
    public bool Playing;
    public readonly List<string> Log = new();
    public int? Solo { get; private set; }
    public int? Track { get; private set; }
    private bool _memo;
    public int? PlayedPattern { get; private set; }
    public int? Selected { get; private set; }
    private int? _selectedTrack;
    public HashSet<int> IgnoredColors = new();
    public ItemKind IgnoredKind = ItemKind.Channels;
    /// Page que l'utilisateur garde devant : `Show` ne la change pas.
    public FlWindow? KeptWindow;
    public bool AllChannels { get; set; }
    /// Channel rack sur un groupe : les rangs dans « All » des canaux qu'il montre ; null : tous.
    public List<int>? Group;

    public FlWindow Page() => Window;

    public List<ChannelInfo> ListChannels()
    {
        Log.Add("list");
        if (_pendingDeletes.Count > 0)
        {
            // FL supprime lentement : un son de plus à chaque relecture.
            var gone = _pendingDeletes.Dequeue();
            Channels = Channels.Where(c => c.Index != gone).Select((c, i) => c with { Index = i }).ToList();
            _pendingDeletes = new Queue<int>(_pendingDeletes.Select(p => p > gone ? p - 1 : p));
        }
        if (Group is null || AllChannels) return Channels.ToList();
        return Group.Select((i, k) => Channels[i] with { Index = k }).ToList();
    }

    public List<MixerTrackInfo> ListMixer()
    {
        Log.Add("mixer");
        return Mixer.ToList();
    }

    public List<PlaylistTrackInfo> ListPlaylist(int limit)
    {
        Log.Add("playlist");
        return Playlist.Take(limit).ToList();
    }

    public List<PatternInfo> ListPatterns()
    {
        Log.Add("patterns");
        return PatternList.ToList();
    }

    public List<int> Routes(int track)
    {
        Log.Add($"routes {track}");
        return RoutesMap.TryGetValue(track, out var r) ? r.ToList() : new List<int>();
    }

    public void SetRoutes(int track, IReadOnlyList<int> dests)
    {
        Log.Add($"send {track} {string.Join(",", dests.OrderBy(d => d))}");
        RoutesMap[track] = dests.OrderBy(d => d).ToList();
    }

    public (double Tempo, List<int> Beats) PatternLengths()
    {
        if (!V14) throw OrganizerError.OutdatedScript;
        return (Tempo, Enumerable.Range(0, PatternList.Count).Select(i => i < Lengths.Count ? Lengths[i] : 16).ToList());
    }

    public (double Before, double Now) Speed(int factor)
    {
        if (!_memo) throw OrganizerError.Refused(5);
        Log.Add($"speed {factor}");
        return (Tempo, Math.Min(Tempo * factor, 520));
    }

    public HashSet<int> HeardChannels() => ActiveChannels();
    public HashSet<int> SelectedChannels() => UnusedSelection.ToHashSet();

    public void Show(FlWindow window)
    {
        Log.Add($"show {Lower(window.ToString())}");
        Window = KeptWindow ?? window;
    }

    private static string Lower(string s) => char.ToLowerInvariant(s[0]) + s[1..];

    public void SetColors(ItemKind kind, IReadOnlyList<(int Index, RgbColor Color)> colors)
    {
        if (colors.Count == 0) return;
        Log.Add($"colors {Lower(kind.ToString())} {colors.Count}");
        foreach (var (index, color) in colors)
        {
            if (kind == IgnoredKind && IgnoredColors.Contains(index)) continue;
            switch (kind)
            {
                case ItemKind.Channels:
                    if (index >= 0 && index < Channels.Count) Channels[index] = Channels[index] with { Index = index, Color = color };
                    break;
                case ItemKind.Mixer:
                    if (index >= 0 && index < Mixer.Count) Mixer[index] = Mixer[index] with { Color = color };
                    break;
                case ItemKind.Playlist:
                    if (index >= 0 && index < Playlist.Count) Playlist[index] = Playlist[index] with { Color = color };
                    break;
                case ItemKind.Patterns:
                    if (index >= 0 && index < PatternList.Count) PatternList[index] = PatternList[index] with { Color = color };
                    break;
            }
        }
    }

    public void SetNames(ItemKind kind, IReadOnlyList<(int Index, string Name)> names)
    {
        if (names.Count == 0) return;
        Log.Add($"names {Lower(kind.ToString())} {names.Count}");
        foreach (var (index, name) in names)
        {
            switch (kind)
            {
                case ItemKind.Channels:
                    if (index >= 0 && index < Channels.Count) Channels[index] = Channels[index] with { Index = index, Name = name };
                    break;
                case ItemKind.Mixer:
                    if (index >= 0 && index < Mixer.Count) Mixer[index] = Mixer[index] with { Name = name };
                    break;
                case ItemKind.Playlist:
                    if (index >= 0 && index < Playlist.Count) Playlist[index] = Playlist[index] with { Name = name };
                    break;
                case ItemKind.Patterns:
                    if (index >= 0 && index < PatternList.Count) PatternList[index] = PatternList[index] with { Name = name };
                    break;
            }
        }
    }

    public void SelectOne(ItemKind kind, int index)
    {
        Log.Add($"select {Lower(kind.ToString())} {index}");
        if (kind == ItemKind.Mixer) _selectedTrack = index; else Selected = index;
    }

    /// Alt+↑ simulé : le canal sélectionné remonte d'une place par pas, tant que le Channel rack est devant.
    public int MoveSelectedUp(int count)
    {
        var done = 0;
        while (done < count && Window == FlWindow.ChannelRack && Selected is { } at && at > 0)
        {
            (Channels[at], Channels[at - 1]) = (Channels[at - 1], Channels[at]);
            Selected = at - 1;
            done++;
        }
        Channels = Channels.Select((c, i) => c with { Index = i }).ToList();
        return done;
    }

    /// Alt+← simulé : la piste du Mixer sélectionnée passe à gauche d'une place par pas, tant que le Mixer est devant ;
    /// jamais à la place du Master. Les canaux reliés et les envois suivent leur piste, comme dans FL.
    public int MoveSelectedLeft(int count)
    {
        var done = 0;
        while (done < count && Window == FlWindow.Mixer && _selectedTrack is { } at && at > 1 && at < Mixer.Count)
        {
            (Mixer[at], Mixer[at - 1]) = (Mixer[at - 1], Mixer[at]);
            int Swapped(int t) => t == at ? at - 1 : t == at - 1 ? at : t;
            Channels = Channels.Select(c => c with { MixerTrack = Swapped(c.MixerTrack) }).ToList();
            RoutesMap = RoutesMap.ToDictionary(kv => Swapped(kv.Key), kv => kv.Value.Select(Swapped).OrderBy(x => x).ToList());
            _selectedTrack = at - 1;
            done++;
        }
        Mixer = Mixer.Select((t, i) => t with { Index = i }).ToList();
        return done;
    }

    /// Patterns et sons que ce FL refuse de jouer (données refusées, raison 5).
    public HashSet<int> RefusedPatterns = new();
    public HashSet<int> RefusedChannels = new();

    public void PlaySolo(int channel, int? pattern = null)
    {
        if (pattern is { } p0 && RefusedPatterns.Contains(p0) || RefusedChannels.Contains(channel)) throw OrganizerError.Refused(5);
        if (!_memo && Playing) throw OrganizerError.Refused(4);
        _memo = true;
        Playing = true;
        PlayedPattern = pattern;
        Track = null;
        if (channel == OrganizerPayload.AllChannels)
        {
            Solo = null;
            Log.Add($"all {pattern ?? 0}");
        }
        else
        {
            Solo = channel;
            Log.Add(pattern is { } p ? $"solo {channel} p{p}" : $"solo {channel}");
        }
    }

    public (int Count, int Current) PatternsInfo() => (PatternList.Count, CurrentPattern);

    public int PickPattern(int pattern)
    {
        if (!V14) throw OrganizerError.OutdatedScript;
        Log.Add($"pick {pattern}");
        CurrentPattern = pattern;
        return pattern;
    }

    public HashSet<int> ActiveChannels()
    {
        if (Track is { } t) return TrackChannels.TryGetValue(t, out var s) ? s.ToHashSet() : new HashSet<int>();
        if (Solo is null && PlayedPattern is { } p) return PatternSounds.TryGetValue(p, out var ps) ? ps.ToHashSet() : new HashSet<int>();
        return new HashSet<int>();
    }

    public HashSet<int> ActiveTracks() => new();

    public HashSet<int> HeardTracks()
    {
        if (!V14) throw OrganizerError.OutdatedScript;
        return ActiveTracks();
    }

    public double SongPosition() => 0;

    public void SelectChannels(IReadOnlyCollection<int> channels, int count)
    {
        if (count != Channels.Count) throw OrganizerError.Refused(5);
        Log.Add($"select {string.Join(",", channels.OrderBy(c => c))}");
        UnusedSelection = channels.ToHashSet();
    }

    public void LinkChannel(int channel, int track)
    {
        if (channel < 0 || channel >= Channels.Count) throw OrganizerError.Refused(5);
        Log.Add($"link {channel} {track}");
        Channels[channel] = Channels[channel] with { MixerTrack = track };
    }

    /// Alt+Suppr simulé : les canaux sélectionnés supprimés, les suivants remontent (Channel rack devant).
    public bool DeleteSelected()
    {
        if (Window != FlWindow.ChannelRack) return false;
        Log.Add("delete");
        var doomed = UnusedSelection.OrderBy(i => i).Take(DeletesOnly ?? int.MaxValue).Concat(DeletesAlso).ToHashSet();
        UnusedSelection = UnusedSelection.Except(doomed).ToHashSet();
        if (DeletesSlowly)
        {
            // Le premier tout de suite, les autres un par un, à chaque relecture (index d'après les précédents).
            var order = doomed.OrderByDescending(i => i).ToList();
            var first = order[^1];
            Channels = Channels.Where(c => c.Index != first).Select((c, i) => c with { Index = i }).ToList();
            _pendingDeletes = new Queue<int>(order.Take(order.Count - 1).Select(i => i - 1));
            return true;
        }
        Channels = Channels.Where(c => !doomed.Contains(c.Index)).Select((c, i) => c with { Index = i }).ToList();
        UnusedSelection = UnusedSelection.Where(i => i < Channels.Count).ToHashSet();
        return true;
    }

    /// FL qui supprime lentement (un son à chaque relecture), qui n'en supprime que les premiers, ou d'autres aussi.
    public bool DeletesSlowly;
    public int? DeletesOnly;
    public List<int> DeletesAlso = new();
    private Queue<int> _pendingDeletes = new();

    /// « Move up » simulé : la piste de la Playlist à cette place remonte d'autant (Playlist devant).
    public int MoveTrackUp(int place, int count)
    {
        var done = 0;
        var at = place;
        while (done < count && Window == FlWindow.Playlist && at > 0 && at < Playlist.Count)
        {
            (Playlist[at], Playlist[at - 1]) = (Playlist[at - 1], Playlist[at]);
            at--;
            done++;
        }
        Playlist = Playlist.Select((t, i) => t with { Index = i }).ToList();
        return done;
    }

    public int PlaySong(double fraction)
    {
        if (!Song) throw OrganizerError.Refused(6);
        if (!_memo && Playing) throw OrganizerError.Refused(4);
        _memo = true;
        Playing = true;
        Solo = null;
        Track = null;
        Log.Add($"song {(int)Math.Round(fraction * 1000)}");
        return Bars;
    }

    public int PlayTrack(int index)
    {
        if (!_memo && Playing) throw OrganizerError.Refused(4);
        _memo = true;
        Playing = true;
        Track = index;
        Log.Add($"track {index}");
        return Bars;
    }

    public void Seek(double fraction)
    {
        if (!_memo || Track is null) throw OrganizerError.Refused(5);
        Log.Add($"seek {(int)Math.Round(fraction * 1000)}");
    }

    /// Comme le script : sans écoute en cours (pas de mémo), rien ne change.
    public void StopRestore()
    {
        Log.Add("restore");
        if (_memo) Playing = false;
        _memo = false;
        Solo = null;
        Track = null;
        PlayedPattern = null;
    }

    public void Audition(int channel, byte note, byte velocity) => Log.Add($"note {channel} {note} {velocity}");
}

/// Capture simulée : le son de la partie du canal en solo, ou celui de ses notes d'essai.
public sealed class FakeAudio : IAudioSource
{
    public double Rate => 48_000;
    private readonly FakeOrganizerLink _link;
    public Dictionary<int, float[]> Parts = new();
    public Dictionary<int, float[]> TestSounds = new();
    public Dictionary<int, float[]> Clips = new();
    public int Started { get; private set; }
    public int Stopped { get; private set; }
    private int _mark;
    /// Clip audio qui commence par un silence : lectures muettes avant son son.
    public Dictionary<int, int> SilentTakes = new();

    public FakeAudio(FakeOrganizerLink link) => _link = link;

    public void Start() => Started++;
    public void Stop() => Stopped++;
    public void Reset() => _mark = _link.Log.Count;
    public string Stats => "capture=essai";

    public float[] Take()
    {
        if (_link.Track is { } track) return Clips.TryGetValue(track, out var c) ? c : Array.Empty<float>();
        if (_link.Solo is not { } channel) return Array.Empty<float>();
        if (_link.Log.Skip(_mark).Any(l => l.StartsWith($"note {channel} ", StringComparison.Ordinal)))
        {
            if (SilentTakes.TryGetValue(channel, out var n) && n > 0)
            {
                SilentTakes[channel] = n - 1;
                return Array.Empty<float>();
            }
            return TestSounds.TryGetValue(channel, out var t) ? t : Array.Empty<float>();
        }
        return Parts.TryGetValue(channel, out var p) ? p : Array.Empty<float>();
    }
}

/// Disque et FL simulés pour l'Organiser sur le fichier : le projet (« Mon son.flp »), la copie rangée, FL qui
/// enregistre et qui ouvre un fichier (le Channel rack et les noms de ses patterns deviennent les siens).
public sealed class FakeDisk
{
    public readonly string Original = Path.Combine(Path.GetTempPath(), "projets", "Mon son.flp");
    public readonly Dictionary<string, FlpFile> Files = new();
    public readonly List<string> Opened = new();
    public readonly List<string> Saved = new();
    /// Faux : FL ne charge jamais le fichier demandé.
    public bool Loads = true;
    /// Vrai : en ouvrant un fichier, FL demande « Invalid project data folder » ; tant que la boîte n'est pas
    /// répondue, son Channel rack n'a que 2 sons. `AnswersDialog` faux : la réponse n'arrive jamais.
    public bool AsksDataFolder;
    public bool AnswersDialog = true;
    public int Answered;
    private List<ChannelInfo>? _waiting;
    public FakeOrganizerLink? Link;

    public FakeDisk() => Files[Original] = FlpSample.Sample();

    public ProjectFileAccess Access => new()
    {
        Save = known =>
        {
            var path = known ?? Original;
            Saved.Add(path);
            return path;
        },
        Open = path =>
        {
            Opened.Add(path);
            if (!Loads || Link is not { } link || !Files.TryGetValue(path, out var file)) return true;
            FlpProject project;
            try { project = new FlpProject(file); } catch (FlpException) { return true; }
            foreach (var (n, name) in project.PatternNames)
                if (n - 1 < link.PatternList.Count) link.PatternList[n - 1] = link.PatternList[n - 1] with { Name = name };
            // Les patterns ajoutés par la séparation, comme FL les montre.
            var last = project.Notes.Keys.DefaultIfEmpty(0).Max();
            while (link.PatternList.Count < last)
            {
                var n = link.PatternList.Count + 1;
                link.PatternList.Add(new PatternInfo(n - 1, new RgbColor(0x48, 0x50, 0x58), $"Pattern {n}"));
            }
            if (AsksDataFolder)
            {
                _waiting = link.Channels.ToList();
                link.Channels = link.Channels.Take(2).ToList();
            }
            return true;
        },
        Read = path => Files.TryGetValue(path, out var file) ? file : throw FlpException.Damaged(),
        Write = (file, path) =>
        {
            if (Files.ContainsKey(path)) throw new IOException("existe");
            Files[path] = file;
        },
        Exists = Files.ContainsKey,
        AnswerDialog = () =>
        {
            if (!AnswersDialog || _waiting is not { } full || Link is not { } link) return null;
            link.Channels = full;
            _waiting = null;
            Answered++;
            return "dossier-données";
        },
    };
}
