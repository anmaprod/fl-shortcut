// Organiser sur le fichier du projet : FL enregistre le projet ouvert et l'Organiser lit son fichier : les sons de
// chaque pattern et de chaque piste sont ceux de ses notes et de ses clips, rien n'est deviné. La Playlist est rangée
// dans une copie, « <nom>_2.flp » (comme « Save new version » de FL), à côté de l'original, qui ne bouge pas ; FL ouvre
// la copie, puis Channel rack, patterns, Mixer et noms se font par le script. « Revenir comme avant » rouvre
// l'original. Pur (testé). Miroir de Sources/FLShortcut/OrganizerProjectFile.swift.
using System.Text.RegularExpressions;

namespace FLShortcut.Core.Organizer;

/// Le fichier du projet ouvert dans FL (des faux dans les tests).
public sealed class ProjectFileAccess
{
    /// FL enregistre le projet ouvert ; renvoie son fichier, celui que FL vient d'écrire (`known` : celui qu'on attend,
    /// s'il est connu). Lance une `OrganizerError` (ProjectNotFound, ou un échec).
    public required Func<string?, string> Save { get; init; }
    /// FL ouvre ce fichier à la place du projet ouvert ; faux si rien n'a pu être demandé.
    public required Func<string, bool> Open { get; init; }
    public Func<string, FlpFile> Read { get; init; } = FlpFile.Read;
    /// Jamais par-dessus un fichier qui existe.
    public Action<FlpFile, string> Write { get; init; } = (file, path) =>
    {
        using var stream = new FileStream(path, FileMode.CreateNew, FileAccess.Write);
        stream.Write(file.Encoded());
    };
    public Func<string, bool> Exists { get; init; } = p => File.Exists(p) || Directory.Exists(p);
    /// La fenêtre de FL porte le nom de ce fichier (FL l'a ouvert).
    public Func<string, bool> IsOpen { get; init; } = _ => false;
    /// Une boîte de FL attend une réponse pendant l'ouverture (« Invalid project data folder ») : son choix par défaut,
    /// qui ne change rien (« Do nothing »), validé ; son nom fixe pour le diagnostic. null : aucune boîte.
    public Func<string?> AnswerDialog { get; init; } = () => null;
    /// Ce que la dernière recherche du fichier a trouvé, en nombres et en mots fixes (jamais un nom ni un chemin).
    public Func<string> Search { get; init; } = () => "";
}

/// Le fichier lu à l'analyse : où il est, chaque clip de la Playlist et ce qu'il joue.
public sealed class ProjectSnapshot
{
    public required string Path { get; init; }
    public required List<FlpClip> Clips { get; init; }
    /// Ce que joue chaque clip (rang du clip → groupe).
    public required Dictionary<int, PlaylistGroup> Groups { get; set; }
    public required int TrackCount { get; init; }
    /// Patterns ajoutés en séparant son par son ceux qui en avaient plusieurs (« Split by channel » de FL).
    public int SplitPatterns { get; init; }

    /// Patterns posés dans la Playlist où rien ne joue : chacun sur sa piste, après les sons.
    public int SilentPatterns => Groups.Values.Where(g => g.Kind == PlaylistGroup.GroupKind.Silent).Select(g => g.Number).Distinct().Count();

    /// Les mêmes clips une fois des canaux supprimés de FL (`map` : index d'avant → maintenant).
    public ProjectSnapshot Moving(IReadOnlyDictionary<int, int> map) => new()
    {
        Path = Path,
        Clips = Clips,
        TrackCount = TrackCount,
        SplitPatterns = SplitPatterns,
        Groups = Groups.ToDictionary(kv => kv.Key, kv => kv.Value.Kind switch
        {
            PlaylistGroup.GroupKind.Sounds => PlaylistGroup.Of(kv.Value.Sounds.Where(map.ContainsKey).Select(s => map[s])),
            PlaylistGroup.GroupKind.Other => PlaylistGroup.Other(map.TryGetValue(kv.Value.Number, out var c) ? c : kv.Value.Number),
            _ => kv.Value,
        }),
    };
}

public static class ProjectFile
{
    public sealed class SoundsRead
    {
        /// Sons de chaque pattern qui en a (0 = pattern 1, comme `PatternInfo.Index`).
        public Dictionary<int, HashSet<int>> Patterns { get; } = new();
        /// Sons de chaque piste de la Playlist qui en a (0 = piste 1).
        public Dictionary<int, HashSet<int>> Tracks { get; } = new();
        /// Sons qui ont des notes dans un pattern ou un clip dans la Playlist.
        public HashSet<int> Used { get; } = new();
    }

    /// Ce que joue chaque pattern et chaque piste, d'après les notes et les clips. `notSounds` : canaux qui ne sont pas
    /// des sons (automations).
    public static SoundsRead Sounds(FlpProject project, ISet<int> notSounds)
    {
        var out_ = new SoundsRead();
        foreach (var pattern in project.Notes.Keys)
        {
            var sounds = project.SoundsOf(pattern);
            sounds.ExceptWith(notSounds);
            if (sounds.Count > 0) out_.Patterns[pattern - 1] = sounds;
            out_.Used.UnionWith(sounds);
        }
        foreach (var clip in project.Clips)
        {
            var sounds = Played(clip, project, notSounds);
            if (sounds.Count > 0)
            {
                if (!out_.Tracks.TryGetValue(clip.Track, out var set)) out_.Tracks[clip.Track] = set = new HashSet<int>();
                set.UnionWith(sounds);
            }
            out_.Used.UnionWith(sounds);
        }
        return out_;
    }

    private static HashSet<int> Played(FlpClip clip, FlpProject project, ISet<int> notSounds)
    {
        var sounds = clip.Source.IsPattern ? project.SoundsOf(clip.Source.Number) : project.Played(new[] { clip.Source.Number });
        sounds.ExceptWith(notSounds);
        return sounds;
    }

    /// Ce que joue un clip, pour ranger la Playlist.
    public static PlaylistGroup Group(FlpClip clip, FlpProject project, ISet<int> notSounds)
    {
        var sounds = Played(clip, project, notSounds);
        if (sounds.Count > 0) return PlaylistGroup.Of(sounds);
        return clip.Source.IsPattern ? PlaylistGroup.Silent(clip.Source.Number) : PlaylistGroup.Other(clip.Source.Number);
    }

    public static ProjectSnapshot Snapshot(FlpProject project, string path, ISet<int> notSounds, int splitPatterns = 0) => new()
    {
        Path = path,
        Clips = project.Clips,
        Groups = project.Clips.ToDictionary(c => c.Item, c => Group(c, project, notSounds)),
        TrackCount = project.TrackCount,
        SplitPatterns = splitPatterns,
    };

    /// Le projet séparé son par son (« Split by channel » de FL), relu : c'est lui que la copie rangée contient,
    /// l'analyse le prend donc aussi. Une forme inattendue : rien n'est touché.
    public static (FlpFile File, FlpProject Project, int Added) Splitting(FlpProject project, FlpFile file)
    {
        try
        {
            var split = project.SplitByChannel(file);
            if (split.Added <= 0) return (file, project, 0);
            return (split.File, new FlpProject(split.File), split.Added);
        }
        catch (FlpException)
        {
            throw OrganizerError.Failed(Loc.F("L'Organiser ne sait pas encore ranger ce projet sans risque (%@) : rien n'a été touché.", "séparation"));
        }
    }

    /// Les patterns de FL, plus ceux que la séparation ajoute (nommés comme FL les nomme : « Pattern 12 »).
    public static List<PatternInfo> Patterns(IReadOnlyList<PatternInfo> live, FlpProject project)
    {
        var known = live.Select(p => p.Index).ToHashSet();
        var color = live.Count > 0 ? live[0].Color : new RgbColor(0x48, 0x50, 0x58);
        var added = project.Notes.Keys.Where(k => !known.Contains(k - 1)).OrderBy(k => k)
            .Select(k => new PatternInfo(k - 1, color, $"Pattern {k}"));
        return live.Concat(added).ToList();
    }

    /// Nom du fichier de son de chaque canal qui en a un (clip audio, sampler) ; s'il ne dit rien, le dossier qui le
    /// contient (« …/Hat/BX 17.wav » : « Hat »).
    public static Dictionary<int, string> SampleNames(FlpProject project)
    {
        var out_ = new Dictionary<int, string>();
        foreach (var channel in project.Channels)
        {
            if (channel.Sample is not { } sample) continue;
            var folder = channel.SamplePath is { } p ? FolderName(p) : null;
            out_[channel.Iid] = SoundNames.KindOf(sample) is null && folder is not null && SoundNames.KindOf(folder) is not null
                ? folder : sample;
        }
        return out_;
    }

    /// Le dossier qui contient le fichier (« …/Packs/Hat/BX 17.wav » : « Hat »).
    public static string? FolderName(string path)
    {
        var parts = path.Split('/', '\\').Where(s => s.Length > 0).ToArray();
        return parts.Length >= 2 ? parts[^2] : null;
    }

    /// Chemin du fichier de son de chaque clip audio (analyse sur le fichier : il est lu directement).
    public static Dictionary<int, string> ClipPaths(FlpProject project) =>
        project.Channels.Where(c => c.Type == ChannelInfo.AudioClipType && c.SamplePath is not null)
            .ToDictionary(c => c.Iid, c => c.SamplePath!);

    /// Pur (testé) : le fichier est-il celui du projet ouvert dans FL ? null si oui ; sinon ce qui diffère, en mots et
    /// nombres pour le diagnostic (jamais un nom).
    public static string? Mismatch(FlpProject project, IReadOnlyList<string> channels, IReadOnlyDictionary<int, string> patterns)
    {
        if (project.Channels.Count != channels.Count) return $"canaux {project.Channels.Count}/{channels.Count}";
        for (var i = 0; i < channels.Count; i++)
        {
            var c = project.Channels[i];
            if (c.Name is { } name && !Same(channels[i], name)) return $"nom c{c.Iid}";
        }
        foreach (var (n, name) in project.PatternNames.OrderBy(kv => kv.Key))
        {
            if (!patterns.TryGetValue(n - 1, out var live) || !Same(live, name)) return $"pattern {n}";
        }
        return null;
    }

    /// Nom lu par le script (peut-être coupé) comparé au nom complet du fichier.
    public static bool Same(string live, string full)
    {
        string l = live.Trim(' '), f = full.Trim(' ');
        return l == f || (new System.Globalization.StringInfo(l).LengthInTextElements >= 8 && f.StartsWith(l, StringComparison.Ordinal));
    }

    private static readonly Regex VersionSuffix = new("_[0-9]+$", RegexOptions.CultureInvariant);

    /// Pur (testé) : la copie rangée, à côté de l'original, nommée comme « Save new version » de FL : « Mon son.flp »
    /// donne « Mon son_2.flp », « Mon son_2.flp » donne « Mon son_3.flp »… Jamais un fichier qui existe.
    public static string CopyPath(string original, Func<string, bool> exists)
    {
        var folder = System.IO.Path.GetDirectoryName(original) ?? "";
        var name = System.IO.Path.GetFileNameWithoutExtension(original);
        var version = 1;
        var m = VersionSuffix.Match(name);
        if (m.Success && m.Index > 0 && int.TryParse(m.Value[1..], out var n) && n < 1_000_000)
        {
            version = n;
            name = name[..m.Index];
        }
        for (var k = version + 1; k <= version + 999; k++)
        {
            var path = System.IO.Path.Combine(folder, $"{name}_{k}.flp");
            if (!exists(path)) return path;
        }
        return System.IO.Path.Combine(folder, $"{name}_{Guid.NewGuid().ToString("N")[..8].ToUpperInvariant()}.flp");
    }

    /// Événement du dossier de données du projet (« project data folder » de FL, texte).
    public const byte DataFolderEvent = 202;

    /// Pur (testé) : la copie sans un dossier de données qui n'existe pas (sinon FL demande « Invalid project data
    /// folder » en ouvrant la copie, et l'Organiser comptait les sons pendant que la boîte attendait). Seulement un
    /// chemin qui ne mène nulle part : un dossier qui existe, ou écrit avec une variable de FL (%…%), est gardé. Un
    /// chemin du Mac (« /Users/… ») ne mène à rien sur ce PC. null : rien à retirer.
    public static FlpFile? WithoutMissingDataFolder(FlpFile file, string projectFolder, Func<string, bool> exists)
    {
        var out_ = file.Clone();
        var before = out_.Events.Count;
        out_.Events.RemoveAll(e =>
        {
            if (e.Id != DataFolderEvent) return false;
            var path = e.Text.Trim();
            if (path.Length == 0 || path.Contains('%')) return false;
            if (path.StartsWith('/')) return true;                       // projet venu d'un Mac : rien sur ce PC
            var full = IsWindowsAbsolute(path) ? path : System.IO.Path.Combine(projectFolder, path);
            return !exists(full);
        });
        return out_.Events.Count == before ? null : out_;
    }

    /// Chemin complet de Windows (« C:\… », « \\serveur\… »), quel que soit le système qui le lit.
    public static bool IsWindowsAbsolute(string path) =>
        (path.Length >= 3 && char.IsAsciiLetter(path[0]) && path[1] == ':' && path[2] is '\\' or '/')
        || path.StartsWith("\\\\", StringComparison.Ordinal);

    /// Pur (testé) : boîte de FL qui arrête l'ouverture d'un projet jusqu'à une réponse (titre de sa fenêtre).
    public static bool IsBlockingDialog(string title) => title.ToLowerInvariant().Contains("invalid project data folder");

    /// Ce qui porte la marque de la copie : un pattern (1 = pattern 1) ou un canal (rang dans le Channel rack).
    public readonly record struct Mark(bool IsPattern, int Number)
    {
        public static Mark Pattern(int n) => new(true, n);
        public static Mark Channel(int c) => new(false, c);
    }

    /// Pur (testé) : la copie marquée, pour savoir que FL l'a ouverte : le premier pattern nommé (d'un nom que le
    /// script peut remettre en entier) prend le nom `marker` ; sinon le nom est ajouté au premier pattern décrit qui
    /// n'en a pas ; sinon il va sur le premier canal nommé. null : rien de possible.
    public static (FlpFile File, Mark Mark)? Marking(FlpFile file, string marker)
    {
        var text = FlpBytes.Utf16Z(marker);
        var name = new FlpEvent(FlpProject.Ev.PatternName, text);
        var out_ = file.Clone();
        int? pattern = null;
        var named = new HashSet<int>();
        var described = new List<(int Index, int Pattern)>();
        (int Iid, int? Named)? channel = null;
        (int Index, int Iid)? channelMark = null;
        var events = file.Events;
        for (var i = 0; i < events.Count; i++)
        {
            var e = events[i];
            var next = i + 1 < events.Count ? events[i + 1].Id : (byte)0;
            switch (e.Id)
            {
                case FlpProject.Ev.Pattern:
                    pattern = (int)e.Value;
                    channel = null;
                    // Le pattern et ses notes (224, contrôles 223) ; ou sa description (nom, couleur…).
                    if (next != FlpProject.Ev.Notes && next != 223) described.Add((i, (int)e.Value));
                    break;
                case FlpProject.Ev.PatternName:
                    if (pattern is not { } p) break;
                    named.Add(p);
                    if (System.Text.Encoding.UTF8.GetByteCount(e.Text) <= OrganizerPayload.NameBytes)
                    {
                        out_.Events[i] = name;
                        return (out_, Mark.Pattern(p));
                    }
                    break;
                case FlpProject.Ev.Channel when next == FlpProject.Ev.ChannelType:
                    channel = ((int)e.Value, null);
                    break;
                case FlpProject.Ev.ChannelName:
                    if (channel is { } c && c.Named is null)
                    {
                        channel = (c.Iid, i);
                        if (channelMark is null && System.Text.Encoding.UTF8.GetByteCount(e.Text) <= OrganizerPayload.NameBytes)
                            channelMark = (i, c.Iid);
                    }
                    break;
                case FlpProject.Ev.Arrangement:
                case FlpProject.Ev.MixerName:
                case FlpProject.Ev.MixerParams:
                    pattern = null;
                    channel = null;
                    break;
            }
        }
        var free = described.Where(d => !named.Contains(d.Pattern)).Cast<(int Index, int Pattern)?>().FirstOrDefault();
        if (free is { } f)
        {
            out_.Events.Insert(f.Index + 1, name);
            return (out_, Mark.Pattern(f.Pattern));
        }
        if (channelMark is not { } cm) return null;
        out_.Events[cm.Index] = new FlpEvent(FlpProject.Ev.ChannelName, text);
        return (out_, Mark.Channel(cm.Iid));
    }

    /// Nom de pattern qui marque la copie : jamais celui d'un son.
    public static string Marker(int n) => $"FL Shortcuts {n}";

    /// Pur (testé) : les noms de projet possibles dans le titre de la fenêtre de FL (« Mon son - FL Studio 2025 »,
    /// « Mon son.flp * ») : chaque morceau, sans « FL Studio », sans « .flp » ni la marque des changements.
    public static List<string> TitleNames(string title)
    {
        IEnumerable<string> parts = new[] { title };
        foreach (var separator in new[] { " - ", " — ", " – " }) parts = parts.SelectMany(p => p.Split(separator));
        var out_ = new List<string>();
        foreach (var part in parts)
        {
            var name = part.Trim(' ');
            while (name.EndsWith('*')) name = name[..^1].Trim(' ');
            if (name.EndsWith(".flp", StringComparison.OrdinalIgnoreCase)) name = name[..^4];
            name = name.Trim(' ');
            if (name.Length == 0 || name.Contains("FL Studio", StringComparison.OrdinalIgnoreCase) || out_.Contains(name)) continue;
            out_.Add(name);
        }
        return out_;
    }

    /// Le projet ouvert dans FL, lu dans son fichier : FL l'enregistre, puis le fichier est lu et comparé au projet
    /// ouvert (mêmes canaux, mêmes patterns). Ce qui ne va pas arrête tout, avant que rien ne soit touché ; `why`
    /// reçoit la raison en mots (diagnostic : jamais un nom).
    public static (string Path, FlpFile File, FlpProject Project) Read(ProjectFileAccess files, string? known,
        IReadOnlyList<ChannelInfo> channels, IReadOnlyList<PatternInfo> patterns, Action<string>? why = null)
    {
        why ??= _ => { };
        string path;
        try
        {
            path = files.Save(known);
        }
        catch (OrganizerError e)
        {
            why(e.Is(OrganizerError.Kinds.ProjectNotFound) ? "introuvable" : "enregistrement");
            throw;
        }
        FlpFile file;
        FlpProject project;
        try
        {
            file = files.Read(path);
            project = new FlpProject(file);
        }
        catch (FlpException e) when (e.Kind == FlpErrorKind.Unsupported)
        {
            why(e.What);
            if (e.What == "arrangements")
                throw OrganizerError.Failed(Loc.T("Ton projet a plusieurs arrangements avec des clips : l'Organiser ne range pour l'instant qu'un seul arrangement. Rien n'a été touché."));
            throw OrganizerError.Failed(Loc.F("L'Organiser ne sait pas encore ranger ce projet sans risque (%@) : rien n'a été touché.", e.What));
        }
        catch (Exception e) when (e is not OrganizerError)
        {
            why(Denied(e) ? "autorisation" : "lecture");
            throw Denied(e) ? DeniedError : OrganizerError.Failed(Loc.T("Le fichier de ton projet n'a pas pu être lu : rien n'a été touché."));
        }
        var names = patterns.ToDictionary(p => p.Index, p => p.Name);
        var live = channels.OrderBy(c => c.Index).Select(c => c.Name).ToList();
        if (Mismatch(project, live, names) is { } what)
        {
            why(what);
            throw OrganizerError.Failed(Loc.T("Le fichier enregistré ne correspond pas au projet ouvert dans FL : rien n'a été touché. Si le Channel rack ne montre qu'un groupe de sons, choisis « All » en haut du Channel rack. Puis clique sur « Réessayer »."));
        }
        if (project.Clips.Any(c => project.MutedTracks.Contains(c.Track)))
        {
            why("piste coupée");
            throw OrganizerError.Failed(Loc.T("Une piste de ta Playlist est coupée (mute) : réactive-la dans FL (ou retire ses clips), puis clique sur « Réessayer ». Rien n'a été touché."));
        }
        return (path, file, project);
    }

    /// Windows n'a pas laissé lire ou écrire le dossier du projet (accès contrôlé aux dossiers, droits…).
    public static bool Denied(Exception error) => error is UnauthorizedAccessException;

    public static OrganizerError DeniedError =>
        OrganizerError.Failed(Loc.T("Windows n'a pas laissé FL Shortcuts ouvrir le dossier de ton projet (Sécurité Windows › Protection contre les ransomwares › Accès contrôlé aux dossiers : autorise FL Shortcuts), puis clique sur « Réessayer ». Rien n'a été touché."));

    private static readonly Regex MarkerName = new("^FL Shortcuts [0-9]+$", RegexOptions.CultureInvariant);

    /// Nom posé dans une copie pour la reconnaître (resté si FL l'a ouverte trop tard) : jamais repris comme nom.
    public static bool IsMarker(string name) => MarkerName.IsMatch(name);
}
