// Organiser : application de tout le plan dans FL (OrganizerPlan) et « Revenir comme avant ». L'application passe par
// le lien (couleurs, noms, sélection, page devant, vérification) et par ce que ferait l'utilisateur, envoyé à FL seul :
// Alt+↑ remonte un canal du Channel rack, Alt+← une piste du Mixer, Alt+Suppr supprime les sons sélectionnés. Sur le
// fichier, la Playlist est rangée dans une copie que FL ouvre ; l'original ne bouge pas. Les patterns gardent leur
// place. Miroir de OrganizerApplier (Sources/FLShortcut/OrganizerApply.swift).
namespace FLShortcut.Core.Organizer;

public sealed class OrganizerApplier
{
    private readonly IOrganizerLink _link;
    private readonly Func<int, int> _moveUp;
    private readonly Func<int, int> _moveLeft;
    private readonly Func<FlIcon, OrganizerError?> _placeIcon;
    private readonly Func<bool> _deleteSelected;
    private readonly Func<int, int, int> _moveTrack;
    private readonly Func<int?, int, int> _moveClips;
    private readonly Action<double> _wait;
    private readonly double _listen;
    private readonly ProjectFileAccess? _files;
    private readonly string _marker;
    private readonly Action<string> _report;
    /// Fois où une page de FL a été remise devant pendant les déplacements (diagnostic).
    private int _restored;
    /// Boîtes de FL répondues pendant l'ouverture de la copie (4 au plus : jamais Entrée sans fin).
    private int _dialogAnswers;

    /// `moveUp(n)` envoie Alt+↑ n fois à FL seul (Channel rack devant), `moveLeft(n)` Alt+← (Mixer devant) ; chacun
    /// renvoie le nombre de pas faits. `placeIcon` pose une icône sur l'élément sélectionné ; null si c'est fait.
    /// `deleteSelected` supprime les canaux sélectionnés (Alt+Suppr, Channel rack devant) ; faux si rien n'a pu être
    /// envoyé. `moveTrack(place, n)` remonte une piste de la Playlist (sans fichier) ; `moveClips(pattern, n)` décale
    /// les clips d'un pattern (sans fichier).
    public OrganizerApplier(IOrganizerLink link, Func<int, int> moveUp, Func<int, int>? moveLeft = null,
        Func<FlIcon, OrganizerError?>? placeIcon = null, Func<bool>? deleteSelected = null,
        Func<int, int, int>? moveTrack = null, Func<int?, int, int>? moveClips = null, Action<double>? wait = null,
        double listen = 1.5, ProjectFileAccess? files = null, string? marker = null, Action<string>? report = null)
    {
        _link = link;
        _moveUp = moveUp;
        _moveLeft = moveLeft ?? (_ => 0);
        _placeIcon = placeIcon ?? (_ => null);
        _deleteSelected = deleteSelected ?? (() => false);
        _moveTrack = moveTrack ?? ((_, _) => 0);
        _moveClips = moveClips ?? ((_, _) => 0);
        _wait = wait ?? (s => Thread.Sleep(TimeSpan.FromSeconds(s)));
        _listen = listen;
        _files = files;
        _marker = marker ?? ProjectFile.Marker(Random.Shared.Next(1000, 10000));
        _report = report ?? (_ => { });
    }

    private static List<(int Index, RgbColor Color)> Pairs(IReadOnlyDictionary<int, RgbColor> colors) =>
        colors.Keys.OrderBy(k => k).Select(k => (k, colors[k])).ToList();

    private static List<(int Index, string Name)> NamePairs(IReadOnlyDictionary<int, string> names) =>
        names.Keys.OrderBy(k => k).Select(k => (k, names[k])).ToList();

    private static OrganizerError Failure(Exception error) =>
        error as OrganizerError ?? OrganizerError.Failed(Loc.F("Organiser : étape impossible (%@).", error.GetType().Name));

    /// Tout le plan, page par page : la copie rangée ouverte (sur le fichier), sons sans note supprimés (puis le plan
    /// refait sur ce qui reste), sons envoyés au Master reliés à leur piste, Channel rack, patterns, Mixer, Playlist.
    /// Une page que FL n'a pas toute prise n'arrête pas les suivantes : elle est dite à la fin (`Mismatch`) ; une
    /// erreur arrête là. Le mémo de chaque page est posé avant d'y toucher.
    public ApplyOutcome Apply(OrganizerPlan plan, OrganizerResult result, IReadOnlyDictionary<SoundFamily, FamilyStyle> styles)
    {
        var outcome = new ApplyOutcome();
        var verified = true;
        _restored = 0;
        try
        {
            if (result.Project is { } project)
            {
                // Toujours dans une copie (son Channel rack sur « All ») ; la Playlist n'y est rangée que si on l'a demandé.
                (plan, result) = OpenOrganizedCopy(project, plan, result, outcome, styles, plan.Source?.Options.Playlist == true);
            }
            if (plan.Deleted.Count > 0)
            {
                if (DeleteUnused(plan.Deleted, result, outcome.Trace) is { } shifted)
                {
                    // FL a pu n'en supprimer qu'une partie : les autres restent de côté (sélectionnés à la fin).
                    outcome.Deleted = shifted.Gone;
                    outcome.NotDeleted = plan.Deleted.Count - shifted.Gone;
                    result = shifted.Result;
                    plan = plan.Replanned(shifted.Result, shifted.Map, styles);
                }
                else
                {
                    // Rien de supprimé : le plan sans suppression (les sons restent de côté, leurs pistes aussi).
                    outcome.NotDeleted = plan.Deleted.Count;
                    plan = plan.Replanned(result, result.Channels.ToDictionary(c => c.Index, c => c.Index), styles);
                }
            }
            if (plan.Mixer.Links.Count > 0)
            {
                outcome.Snapshot.Links = new Dictionary<int, int>();
                if (!ApplyLinks(plan.Mixer.Links, result, outcome.Snapshot.Links)) verified = false;
            }
            if (!plan.Rack.IsEmpty)
            {
                outcome.Snapshot.Rack = new AreaSnapshot();
                if (!ApplyRack(plan.Rack, result, styles, outcome.Snapshot.Rack)) verified = false;
            }
            if (!plan.Patterns.IsEmpty)
            {
                outcome.Snapshot.Patterns = new AreaSnapshot();
                if (!ApplyPatterns(plan.Patterns, result, outcome.Snapshot.Patterns)) verified = false;
            }
            if (!plan.Mixer.IsEmpty)
            {
                outcome.Snapshot.Mixer = new AreaSnapshot();
                if (!ApplyMixer(plan.Mixer, result, styles, outcome.Snapshot.Mixer)) verified = false;
            }
            if (plan.Splits.Count > 0)
            {
                // Sans fichier seulement (l'appli analyse toujours le fichier) : patterns descendus un par un.
                outcome.Snapshot.Splits = new List<PlaylistSplit>();
                var done = ApplySplits(plan.Splits, outcome.Snapshot.Splits);
                outcome.Split = done;
                if (done < plan.Splits.Count)
                {
                    outcome.PlaylistMixed = true;
                    var replanned = plan.LimitingSplits(done, result, styles);
                    plan.Playlist = replanned.Playlist;
                    plan.Splits = replanned.Splits;
                }
                if (outcome.Snapshot.Splits.Count == 0) outcome.Snapshot.Splits = null;
                if (plan.Splits.Count > 0) result.Playlist = _link.ListPlaylist(plan.Splits.Max(s => s.To) + 1);
            }
            if (!plan.Playlist.IsEmpty)
            {
                outcome.Snapshot.Playlist = new AreaSnapshot();
                if (!ApplyPlaylist(plan.Playlist, result, outcome.Snapshot.Playlist, outcome)) verified = false;
            }
            if (outcome.NotDeleted > 0)
            {
                // Sons sans note pas supprimés : sélectionnés de nouveau à leur place d'arrivée, pour que l'utilisateur
                // les supprime lui-même.
                var arrangement = outcome.Snapshot.Rack?.Arrangement ?? new List<int>();
                var places = result.Unused.Select(u => arrangement.Count == 0 ? u : arrangement.IndexOf(u)).Where(p => p >= 0).ToHashSet();
                try { _link.SelectChannels(places, result.Channels.Count); } catch (OrganizerError) { }
            }
            if (!verified) outcome.Error = OrganizerError.Mismatch;
            if (outcome.Copy is { } copy && _files is not null)
            {
                // La copie rangée n'a pas été enregistrée par FL : l'utilisateur le fera (Ctrl+S).
                try { _files.Save(copy); }
                catch (OrganizerError) { outcome.CopyNotSaved = true; }
            }
        }
        catch (Exception e)
        {
            outcome.Error = Failure(e);
            if (outcome.Error.Is(OrganizerError.Kinds.Refused) && _link.LastRefusal is { } refusal) outcome.Trace.Add($"refus {refusal}");
        }
        if (_restored > 0) outcome.Trace.Add($"page remise {_restored}");
        return outcome;
    }

    /// FL ouvre la copie rangée attendue : un nom de pattern posé pour ça dans la copie, lu par le script (au plus
    /// `OpenChecks` fois, toutes les demi-secondes, 3 minutes : un gros projet charge ses plugins).
    public const int OpenChecks = 360;

    /// Analyse sur le fichier : FL enregistre le projet, qui doit être resté tel qu'à l'analyse (sinon rien n'est
    /// touché) ; la copie rangée est écrite à côté de l'original et FL l'ouvre. Le nom de pattern qui la marque est
    /// remis aussitôt, puis tout le reste se fait dans la copie. L'original ne bouge pas.
    private (OrganizerPlan Plan, OrganizerResult Result) OpenOrganizedCopy(ProjectSnapshot project, OrganizerPlan plan,
        OrganizerResult result, ApplyOutcome outcome, IReadOnlyDictionary<SoundFamily, FamilyStyle> styles, bool arrange)
    {
        if (_files is not { } files) throw OrganizerError.Failed(Loc.T("Le fichier de ton projet n'est pas accessible : rien n'a été touché."));
        var layout = arrange ? plan.Layout : null;
        if (arrange && layout is null)
            throw OrganizerError.Failed(Loc.T("Ta Playlist a plus de pistes à remplir que FL n'en a : rien n'a été touché."));
        // La copie montre tous les sons (« All ») : le groupe affiché, compté par le script, est celui de l'analyse.
        _link.AllChannels = false;
        var read = ProjectFile.Read(files, project.Path, result.Channels, result.Patterns);
        // Séparé son par son comme à l'analyse : les mêmes clips, les mêmes sons, sinon le projet a changé.
        var split = ProjectFile.Splitting(read.Project, read.File);
        var notSounds = result.Channels.Where(c => c.Type == ChannelInfo.AutomationType).Select(c => c.Index).ToHashSet();
        if (!split.Project.Clips.SequenceEqual(project.Clips)
            || !Same.SetMaps(ProjectFile.Sounds(split.Project, notSounds).Patterns, result.PatternSounds))
            throw OrganizerError.Failed(Loc.T("Ton projet a changé depuis l'analyse : rien n'a été touché. Ferme l'Organiser, puis relance-le."));
        FlpFile copy;
        try
        {
            copy = layout is not null ? split.Project.Rearranged(split.File, layout.Tracks) : split.Project.ShowingAll(split.File);
        }
        catch (FlpException)
        {
            throw OrganizerError.Failed(Loc.F("L'Organiser ne sait pas encore ranger ce projet sans risque (%@) : rien n'a été touché.", "clips"));
        }
        if (ProjectFile.Marking(copy, _marker) is not { } marked)
            throw OrganizerError.Failed(Loc.F("L'Organiser ne sait pas encore ranger ce projet sans risque (%@) : rien n'a été touché.", "patterns"));
        var markedFile = marked.File;
        // Un dossier de données qui n'existe plus (projet déplacé, projet du Mac) : FL bloquerait l'ouverture de la
        // copie sur sa question ; la copie ne le garde pas (l'original, lui, ne bouge pas).
        if (ProjectFile.WithoutMissingDataFolder(markedFile, Path.GetDirectoryName(read.Path) ?? "", files.Exists) is { } cleaned)
        {
            markedFile = cleaned;
            outcome.Trace.Add("dossier-données=retiré");
        }
        var path = ProjectFile.CopyPath(read.Path, files.Exists);
        try
        {
            files.Write(markedFile, path);
        }
        catch (Exception e) when (e is not OrganizerError)
        {
            throw ProjectFile.Denied(e) ? ProjectFile.DeniedError
                : OrganizerError.Failed(Loc.T("La copie rangée n'a pas pu être écrite à côté de ton projet : rien n'a été touché."));
        }
        if (!files.Open(path))
            throw OrganizerError.Failed(Loc.T("FL n'a pas pu ouvrir la copie rangée : elle est à côté de ton projet, ouvre-la dans FL. Ton projet n'a pas bougé."));
        outcome.Copy = path;
        outcome.Snapshot.Original = read.Path;
        AppLog.Write("ORGANIZE", $"organized copy written ({project.Clips.Count} clips, {layout?.Count ?? 0} tracks), opening");
        // FL l'a ouverte quand le script lit la marque, ou quand sa fenêtre porte le nom de la copie.
        _report(Loc.T("FL ouvre la copie rangée…"));
        var started = DateTime.UtcNow;
        var how = "non";                                   // diagnostic : le script a lu la marque, ou la fenêtre
        for (var check = 0; check < OpenChecks; check++)
        {
            _wait(0.5);
            AnswerDialogs(outcome.Trace);
            if (ShowsMark(marked.Mark)) how = "marque";
            else if (files.IsOpen(path)) how = "fenêtre";
            if (how != "non") break;
            if (check % 4 == 3) _report(Loc.F("FL ouvre la copie rangée… %lld s", (int)(DateTime.UtcNow - started).TotalSeconds));
        }
        var waited = (int)(DateTime.UtcNow - started).TotalSeconds;
        outcome.Trace.Add($"ouverture={how} {waited} s");
        AppLog.Write("ORGANIZE", $"copy {(how != "non" ? "open" : "not open")} after {waited} s");
        if (how == "non")
            throw OrganizerError.Failed(Loc.T("FL n'a pas ouvert la copie rangée à temps : elle est à côté de ton projet, ouvre-la dans FL, puis relance l'Organiser. Ton projet n'a pas bougé."));
        _report(Loc.T("FL charge les sons de la copie…"));
        var calmFrom = DateTime.UtcNow;
        WaitUntilCalm(result.Channels.Count, outcome.Trace);
        outcome.Trace.Add($"calme {(int)(DateTime.UtcNow - calmFrom).TotalSeconds} s");
        AppLog.Write("ORGANIZE", $"FL answers after {(int)(DateTime.UtcNow - calmFrom).TotalSeconds} s, arranging");
        // La marque remise : le nom d'avant (une marque restée d'un essai où FL l'avait ouverte trop tard n'est jamais
        // reprise). Un canal garde son nom d'avant.
        if (marked.Mark.IsPattern)
        {
            var n = marked.Mark.Number;
            var before = read.Project.PatternNames.TryGetValue(n, out var b) && !ProjectFile.IsMarker(b) ? b : null;
            var name = plan.Patterns.Names.GetValueOrDefault(n - 1) ?? before ?? $"Pattern {n}";
            Retrying(() => { _link.SetNames(ItemKind.Patterns, new[] { (n - 1, name) }); return 0; });
        }
        else
        {
            var c = marked.Mark.Number;
            var beforeName = read.Project.Channels[c].Name is { } bn && !ProjectFile.IsMarker(bn) ? bn : null;
            var name = beforeName ?? result.Channels.FirstOrDefault(x => x.Index == c)?.Name ?? $"Channel {c + 1}";
            Retrying(() => { _link.SetNames(ItemKind.Channels, new[] { (c, name) }); return 0; });
        }
        _report(Loc.T("Rangement dans la copie…"));
        if (layout is not null)
        {
            result = result.Clone();
            result.Playlist = Retrying(() => _link.ListPlaylist(layout.Count));
            plan.Playlist = plan.ReplannedPlaylist(result, styles);
        }
        return (plan, result);
    }

    /// La marque de la copie, lue par le script.
    private bool ShowsMark(ProjectFile.Mark mark)
    {
        string? name = null;
        try
        {
            name = mark.IsPattern
                ? _link.ListPatterns().FirstOrDefault(p => p.Index == mark.Number - 1)?.Name
                : _link.ListChannels().FirstOrDefault(c => c.Index == mark.Number)?.Name;
        }
        catch (OrganizerError) { }
        return name is not null && ProjectFile.Same(name, _marker);
    }

    /// Une boîte de FL qui attend une réponse pendant l'ouverture de la copie : répondue par son choix par défaut.
    private void AnswerDialogs(List<string> trace)
    {
        if (_dialogAnswers >= 4 || _files?.AnswerDialog() is not { } name) return;
        _dialogAnswers++;
        trace.Add($"boîte={name}");
        AppLog.Write("ORGANIZE", $"FL dialog answered ({name})");
    }

    /// FL a ouvert la copie mais charge encore ses plugins et ses sons : la suite attend qu'il réponde deux fois de
    /// suite en moins de 3 s AVEC tous les sons de l'analyse, 2 min 30 au plus.
    public const int CalmChecks = 150;
    public const double CalmAnswer = 3;
    public const double CalmLimit = 150;

    private void WaitUntilCalm(int expected, List<string> trace)
    {
        var calm = 0;
        var count = -1;
        var answers = 0;
        var slowest = 0.0;
        var started = DateTime.UtcNow;
        for (var check = 0; check < CalmChecks; check++)
        {
            _wait(0.5);
            AnswerDialogs(trace);
            var asked = DateTime.UtcNow;
            List<ChannelInfo>? listed = null;
            try { listed = _link.ListChannels(); } catch (OrganizerError) { }
            var took = (DateTime.UtcNow - asked).TotalSeconds;
            if (listed is not null)
            {
                answers++;
                slowest = Math.Max(slowest, took);
                count = listed.Count;
            }
            calm = listed is not null && took < CalmAnswer ? calm + 1 : 0;
            if ((calm >= 2 && count == expected) || (DateTime.UtcNow - started).TotalSeconds > CalmLimit) break;
            if (check % 4 == 3) _report(Loc.F("FL charge les sons de la copie… %lld s", (int)(DateTime.UtcNow - started).TotalSeconds));
        }
        trace.Add($"réponses={answers} lente={(int)Math.Round(slowest * 10, MidpointRounding.AwayFromZero)}ds");
        if (calm < 2)
            throw OrganizerError.Failed(Loc.T("FL ne répond plus assez vite depuis l'ouverture de la copie rangée. Elle est ouverte dans FL avec sa Playlist rangée : relance l'Organiser dessus pour finir le reste. Ton projet d'origine n'a pas bougé."));
        // La copie montre tous les sons (« All ») : autant que l'analyse, sinon rien ne serait à sa place.
        if (count != expected)
            throw OrganizerError.Failed(Loc.F("La copie rangée ouverte dans FL n'a pas les mêmes sons que l'analyse (%lld au lieu de %lld) : rien d'autre n'a été fait. Ton projet n'a pas bougé.", count, expected));
    }

    /// Une demande à FL réessayée (3 fois, une seconde d'écart) : juste après l'ouverture, FL peut encore être occupé.
    /// Un refus de FL n'est pas réessayé.
    private T Retrying<T>(Func<T> request)
    {
        OrganizerError last = OrganizerError.NoResponse;
        for (var attempt = 0; attempt < 3; attempt++)
        {
            if (attempt > 0) _wait(1);
            try
            {
                return request();
            }
            catch (OrganizerError e) when (e.Kind == OrganizerError.Kinds.Refused)
            {
                throw;
            }
            catch (OrganizerError e)
            {
                last = e;
            }
        }
        throw last;
    }

    /// Sons sans aucune note supprimés : sélectionnés seuls par le script (relus), Channel rack devant, puis « Delete
    /// selected » de FL (Alt+Suppr) ; vérifié en relisant le Channel rack. null si FL n'a rien supprimé. Autre chose
    /// de supprimé, ou un Channel rack changé depuis l'analyse : arrêt.
    /// Relectures du Channel rack après la suppression (0,35 s d'écart, 6 s au plus) : FL supprime les sons un par un
    /// (vidéo du propriétaire, 25/10 : relu trop tôt, il n'avait pas fini et l'Organiser s'arrêtait).
    public const int DeleteChecks = 17;
    public const double DeleteCheck = 0.35;

    /// Sons sans aucune note supprimés : sélectionnés seuls par le script (relus), Channel rack devant, puis « Delete
    /// selected » de FL (Alt+Suppr). Le Channel rack est relu jusqu'à ce que FL ait fini (tous partis, ou deux fois le
    /// même) ; ce que FL a vraiment supprimé (`Removed`) sert pour la suite, même s'il n'en a supprimé qu'une partie.
    /// null si rien n'est parti. Un autre son supprimé, ou un Channel rack changé autrement : arrêt (dans la copie :
    /// « Revenir comme avant » rouvre l'original).
    private (OrganizerResult Result, Dictionary<int, int> Map, int Gone)? DeleteUnused(List<int> deleted, OrganizerResult result,
        List<string> trace)
    {
        var channels = result.Channels.OrderBy(c => c.Index).ToList();
        if (!_link.ListChannels().Select(c => c.Name).SequenceEqual(channels.Select(c => c.Name)))
            throw OrganizerError.Failed(Loc.T("Le Channel rack a changé depuis l'analyse : relance Organiser."));
        var set = deleted.ToHashSet();
        _link.SelectChannels(set, channels.Count);
        if (!_link.SelectedChannels().SetEquals(set)) return null;
        _link.Show(FlWindow.ChannelRack);
        if (_link.Window != FlWindow.ChannelRack || !_deleteSelected()) return null;
        var expected = result.Removing(set).Result.Channels.Select(c => c.Name).ToList();
        List<ChannelInfo>? previous = null;
        var now = _link.ListChannels();
        for (var check = 0; check < DeleteChecks; check++)
        {
            if (now.Select(c => c.Name).SequenceEqual(expected)) break;
            if (previous is not null && check >= 3 && SameRack(previous, now)) break;
            previous = now;
            _wait(DeleteCheck);
            now = _link.ListChannels();
        }
        var gone = Removed(channels, now, set);
        var others = gone?.Count(i => !set.Contains(i)) ?? -1;
        trace.Add($"suppression prévus={set.Count} avant={channels.Count} après={now.Count} partis={gone?.Count ?? -1} autres={others}");
        if (gone is null)
            throw OrganizerError.Failed(Loc.T("Après la suppression des sons sans note, le Channel rack de la copie rangée ne correspond plus à l'analyse : Organiser s'est arrêté. « Revenir comme avant » rouvre ton projet d'origine, qui n'a pas bougé."));
        if (others > 0)
            throw OrganizerError.Failed(Loc.T("FL a supprimé d'autres sons que ceux sans note dans la copie rangée : Organiser s'est arrêté. « Revenir comme avant » rouvre ton projet d'origine, qui n'a pas bougé."));
        if (gone.Count == 0) return null;
        var shifted = result.Removing(gone);
        return (shifted.Result, shifted.Map, gone.Count);
    }

    private static bool SameRack(IReadOnlyList<ChannelInfo> a, IReadOnlyList<ChannelInfo> b) =>
        a.Count == b.Count && a.Zip(b).All(p => SameChannel(p.First, p.Second));

    /// Un même canal avant et après des suppressions : son nom, sa sorte, sa piste du Mixer et sa couleur (sa place
    /// change).
    private static bool SameChannel(ChannelInfo a, ChannelInfo b) =>
        a.Name == b.Name && a.Type == b.Type && a.MixerTrack == b.MixerTrack && a.Color == b.Color;

    /// Pur (testé) : les canaux (index d'avant) que FL a supprimés, d'après le Channel rack relu : `after` doit être
    /// `before` moins quelques canaux, dans le même ordre. Deux canaux pareils : celui qui était prévu (`planned`) est
    /// pris pour le supprimé. null : FL montre autre chose (un canal renommé, déplacé ou ajouté).
    public static HashSet<int>? Removed(IReadOnlyList<ChannelInfo> before, IReadOnlyList<ChannelInfo> after, ISet<int> planned)
    {
        int n = before.Count, m = after.Count;
        if (m > n) return null;
        const int Impossible = int.MaxValue / 2;
        // cost[i, j] : le moins de canaux non prévus supprimés pour que before[i…] devienne after[j…].
        var cost = new int[n + 1, m + 1];
        for (var j = 0; j <= m; j++) cost[n, j] = j == m ? 0 : Impossible;
        for (var i = n - 1; i >= 0; i--)
        {
            var drop = planned.Contains(before[i].Index) ? 0 : 1;
            for (var j = m; j >= 0; j--)
            {
                var best = Math.Min(Impossible, cost[i + 1, j] + drop);
                if (j < m && SameChannel(before[i], after[j])) best = Math.Min(best, cost[i + 1, j + 1]);
                cost[i, j] = best;
            }
        }
        if (cost[0, 0] >= Impossible) return null;
        var out_ = new HashSet<int>();
        int a = 0, b = 0;
        while (a < n)
        {
            // Garder le canal quand c'est aussi bien : le moins de suppressions possible.
            if (b < m && SameChannel(before[a], after[b]) && cost[a + 1, b + 1] == cost[a, b])
            {
                a++;
                b++;
            }
            else
            {
                out_.Add(before[a].Index);
                a++;
            }
        }
        return out_;
    }

    /// Sons envoyés au Master reliés chacun à sa piste libre, avant tout déplacement (index d'origine), relus.
    private bool ApplyLinks(Dictionary<int, int> links, OrganizerResult result, Dictionary<int, int> saved)
    {
        var before = result.Channels.ToDictionary(c => c.Index, c => c.MixerTrack);
        foreach (var (channel, track) in links.OrderBy(kv => kv.Key))
        {
            saved[channel] = before.GetValueOrDefault(channel);
            _link.LinkChannel(channel, track);
        }
        var now = _link.ListChannels().ToDictionary(c => c.Index, c => c.MixerTrack);
        return links.All(kv => now.TryGetValue(kv.Key, out var t) && t == kv.Value);
    }

    /// Channel rack : couleurs et noms (places d'origine), remontées, relecture de l'ordre et des couleurs, icônes.
    private bool ApplyRack(OrganizerPlan.Area area, OrganizerResult result, IReadOnlyDictionary<SoundFamily, FamilyStyle> styles, AreaSnapshot snap)
    {
        var channels = result.Channels.OrderBy(c => c.Index).ToList();
        foreach (var channel in channels)
        {
            if (area.Colors.ContainsKey(channel.Index)) snap.Colors[channel.Index] = channel.Color;
            if (area.Names.ContainsKey(channel.Index)) snap.Names[channel.Index] = channel.Name;
        }
        snap.Arrangement = Enumerable.Range(0, channels.Count).ToList();
        var icons = Organize.PlannedIcons(area.Verdicts.ToDictionary(kv => kv.Key, kv => kv.Value.Family), styles);
        if (area.Moves.Count > 0 || icons.Count > 0) _link.Show(FlWindow.ChannelRack);
        _link.SetColors(ItemKind.Channels, Pairs(area.Colors));
        _link.SetNames(ItemKind.Channels, NamePairs(area.Names));
        // Noms tels qu'ils sont maintenant dans FL, par index d'origine : pour relire l'ordre.
        var names = channels.Select(c => area.Names.GetValueOrDefault(c.Index) ?? c.Name).ToList();
        try
        {
            MoveAll(area.Moves, snap, FlWindow.ChannelRack, ItemKind.Channels, 0, _moveUp);
        }
        catch (Exception)
        {
            // Arrêt en route : l'ordre relu dans FL, pour que « Revenir comme avant » remette chaque chose à sa place.
            try
            {
                if (Arrangement(_link.ListChannels().Select(c => c.Name).ToList(), names) is { } seen) snap.Arrangement = seen;
            }
            catch (OrganizerError) { }
            throw;
        }
        var listed = _link.ListChannels();
        // L'ordre que FL montre vraiment (une touche Alt+↑ perdue) : une seconde passe depuis cet ordre.
        var regrouped = true;
        if (Arrangement(listed.Select(c => c.Name).ToList(), names) is { } first && !first.SequenceEqual(area.Final) && area.Final.Count > 0)
        {
            snap.Arrangement = first;
            MoveAll(RegroupPlan.Moves(first, area.Final), snap, FlWindow.ChannelRack, ItemKind.Channels, 0, _moveUp);
            listed = _link.ListChannels();
        }
        if (Arrangement(listed.Select(c => c.Name).ToList(), names) is { } after)
        {
            regrouped = area.Final.Count == 0 || after.SequenceEqual(area.Final);
            snap.Arrangement = after;
        }
        var now = listed.Select(c => (RgbColor?)c.Color).ToList();
        var expected = snap.Arrangement.Select(i => (RgbColor?)(area.Colors.TryGetValue(i, out var c) ? c : channels[i].Color)).ToList();
        if (!regrouped || !now.SequenceEqual(expected)) return false;
        var arrangement = snap.Arrangement;
        PlaceIcons(icons, ItemKind.Channels, i => { var at = arrangement.IndexOf(i); return at < 0 ? null : at; });
        return true;
    }

    /// Patterns : couleurs et noms, puis relecture.
    private bool ApplyPatterns(OrganizerPlan.Area area, OrganizerResult result, AreaSnapshot snap)
    {
        foreach (var pattern in result.Patterns)
        {
            if (area.Colors.ContainsKey(pattern.Index)) snap.Colors[pattern.Index] = pattern.Color;
            if (area.Names.ContainsKey(pattern.Index)) snap.Names[pattern.Index] = pattern.Name;
        }
        _link.SetColors(ItemKind.Patterns, Pairs(area.Colors));
        _link.SetNames(ItemKind.Patterns, NamePairs(area.Names));
        var colors = new Dictionary<int, RgbColor>();
        var names = new Dictionary<int, string>();
        foreach (var pattern in _link.ListPatterns())
        {
            colors[pattern.Index] = pattern.Color;
            names[pattern.Index] = pattern.Name;
        }
        return area.Colors.All(kv => colors.TryGetValue(kv.Key, out var c) && c == kv.Value) && NamesMatch(area.Names, names);
    }

    /// Mixer : couleurs et noms (pistes d'origine), envois, puis Mixer devant et chaque piste décalée à gauche
    /// (Alt+←), relecture de l'ordre, des couleurs et des noms, icônes. Le Master ne bouge jamais.
    private bool ApplyMixer(OrganizerPlan.Area area, OrganizerResult result, IReadOnlyDictionary<SoundFamily, FamilyStyle> styles, AreaSnapshot snap)
    {
        var byIndex = result.Mixer.ToDictionary(t => t.Index);
        foreach (var index in area.Colors.Keys) if (byIndex.TryGetValue(index, out var t)) snap.Colors[index] = t.Color;
        foreach (var index in area.Names.Keys) if (byIndex.TryGetValue(index, out var t)) snap.Names[index] = t.Name;
        var span = area.Final.Count;                                       // pistes 1…span
        snap.Arrangement = span > 0 ? Enumerable.Range(1, span).ToList() : new List<int>();
        // Envois (numéros d'origine, avant tout déplacement : FL les fait suivre les pistes) : ceux d'avant gardés pour
        // « Revenir comme avant », posés, relus.
        var routesOk = true;
        foreach (var track in area.Routes.Keys.OrderBy(t => t))
        {
            var wanted = area.Routes[track].ToHashSet();
            var before = _link.Routes(track);
            if (before.ToHashSet().SetEquals(wanted)) continue;
            snap.Routes[track] = before;
            _link.SetRoutes(track, wanted.OrderBy(t => t).ToList());
            if (!_link.Routes(track).ToHashSet().SetEquals(wanted)) routesOk = false;
        }
        // Pistes des sons supprimés : leur nom de FL remis une fois les pistes à leur place.
        var named = area.Names.Where(kv => kv.Value.Length > 0).ToDictionary(kv => kv.Key, kv => kv.Value);
        var resets = area.Names.Where(kv => kv.Value.Length == 0).Select(kv => kv.Key).OrderBy(k => k).ToList();
        _link.SetColors(ItemKind.Mixer, Pairs(area.Colors));
        _link.SetNames(ItemKind.Mixer, NamePairs(named));
        // Noms tels qu'ils sont maintenant dans FL, par piste d'origine (pistes 1…span) : pour relire l'ordre.
        var names = span > 0
            ? Enumerable.Range(1, span).Select(t => named.GetValueOrDefault(t) ?? byIndex.GetValueOrDefault(t)?.Name ?? "").ToList()
            : new List<string>();
        var icons = Organize.PlannedIcons(area.Verdicts.ToDictionary(kv => kv.Key, kv => kv.Value.Family), styles);
        if (area.Moves.Count > 0 || icons.Count > 0) _link.Show(FlWindow.Mixer);
        List<string> Tracks(IEnumerable<MixerTrackInfo> listed) =>
            listed.Where(t => t.Index >= 1 && t.Index <= span).OrderBy(t => t.Index).Select(t => t.Name).ToList();
        try
        {
            MoveAll(area.Moves, snap, FlWindow.Mixer, ItemKind.Mixer, 1, _moveLeft);
        }
        catch (Exception)
        {
            try
            {
                if (span > 0 && Arrangement(Tracks(_link.ListMixer()), names) is { } seen) snap.Arrangement = seen.Select(x => x + 1).ToList();
            }
            catch (OrganizerError) { }
            throw;
        }
        var listedMixer = _link.ListMixer();
        // Seconde passe depuis l'ordre que FL montre, s'il n'est pas celui prévu (une touche Alt+← perdue).
        if (span > 0 && Arrangement(Tracks(listedMixer), names) is { } first && !first.Select(x => x + 1).SequenceEqual(area.Final))
        {
            snap.Arrangement = first.Select(x => x + 1).ToList();
            MoveAll(RegroupPlan.Moves(snap.Arrangement, area.Final), snap, FlWindow.Mixer, ItemKind.Mixer, 1, _moveLeft);
            listedMixer = _link.ListMixer();
        }
        var now = listedMixer.ToDictionary(t => t.Index);
        var regrouped = true;
        if (span > 0 && Arrangement(Tracks(listedMixer), names) is { } seenAfter)
        {
            var tracks = seenAfter.Select(x => x + 1).ToList();
            regrouped = tracks.SequenceEqual(area.Final);
            snap.Arrangement = tracks;
        }
        // Chaque piste d'origine est maintenant à la place où l'ordre relu la met.
        var arrangement = snap.Arrangement;
        int Place(int original) { var at = arrangement.IndexOf(original); return at < 0 ? original : at + 1; }
        var colorsOk = area.Colors.All(kv => now.TryGetValue(Place(kv.Key), out var t) && t.Color == kv.Value);
        var read = new Dictionary<int, string>();
        foreach (var index in named.Keys) if (now.TryGetValue(Place(index), out var t)) read[index] = t.Name;
        var resetOk = true;
        if (resets.Count > 0)
        {
            _link.SetNames(ItemKind.Mixer, resets.Select(r => (Place(r), "")).ToList());
            var after = _link.ListMixer().ToDictionary(t => t.Index);
            resetOk = resets.All(r => after.TryGetValue(Place(r), out var t) && t.HasDefaultName);
        }
        if (!regrouped || !colorsOk || !routesOk || !resetOk || !NamesMatch(named, read)) return false;
        PlaceIcons(icons, ItemKind.Mixer, i => Place(i));
        return true;
    }

    /// Playlist : couleurs et noms (pistes d'origine), vérifiés sur les pistes touchées ; puis, sans fichier, les
    /// pistes remontées une à une.
    private bool ApplyPlaylist(OrganizerPlan.Area area, OrganizerResult result, AreaSnapshot snap, ApplyOutcome outcome)
    {
        foreach (var track in result.Playlist)
        {
            if (area.Colors.ContainsKey(track.Index)) snap.Colors[track.Index] = track.Color;
            // Nom de FL lu vide : remis en « Track n » (un nom vide ne peut pas être posé).
            if (area.Names.ContainsKey(track.Index)) snap.Names[track.Index] = track.Name.Length == 0 ? $"Track {track.Index + 1}" : track.Name;
        }
        _link.SetColors(ItemKind.Playlist, Pairs(area.Colors));
        _link.SetNames(ItemKind.Playlist, NamePairs(area.Names));
        var ok = true;
        var last = Math.Max(area.Colors.Keys.DefaultIfEmpty(-1).Max(), area.Names.Keys.DefaultIfEmpty(-1).Max());
        if (last >= 0)
        {
            var colors = new Dictionary<int, RgbColor>();
            var names = new Dictionary<int, string>();
            foreach (var track in _link.ListPlaylist(last + 1))
            {
                colors[track.Index] = track.Color;
                names[track.Index] = track.Name;
            }
            ok = area.Colors.All(kv => colors.TryGetValue(kv.Key, out var c) && c == kv.Value) && NamesMatch(area.Names, names);
        }
        if (area.Moves.Count == 0) return ok;
        snap.Arrangement = Enumerable.Range(0, area.Final.Count).ToList();
        _link.Show(FlWindow.Playlist);
        foreach (var step in area.Moves)
        {
            var done = _moveTrack(step.From, step.Up);
            snap.Arrangement = RegroupPlan.Applying(new Move(step.From, done), snap.Arrangement);
            if (done < step.Up)
            {
                outcome.PlaylistUnordered = true;
                break;
            }
        }
        return ok;
    }

    /// Sans fichier : chaque pattern à descendre, ses clips décalés sur sa piste vide et vérifiés à l'écoute ; au
    /// moindre doute, ils remontent et tout s'arrête là. Renvoie le nombre de patterns descendus.
    private int ApplySplits(List<PlaylistSplit> splits, List<PlaylistSplit> done)
    {
        foreach (var split in splits)
        {
            var rows = split.To - split.From;
            var moved = _moveClips(split.Pattern + 1, rows);
            if (moved == rows && Heard(split.To, split.At).Contains(split.Sound) && Heard(split.From, split.KeptAt).Contains(split.Kept))
            {
                done.Add(split);
                continue;
            }
            if (moved <= 0) break;
            var back = _moveClips(null, -moved);
            if (back != moved || !Heard(split.From, split.KeptAt).Contains(split.Kept))
                throw OrganizerError.Failed(Loc.T("Des clips de la Playlist n'ont pas pu être remis à leur place : annule dans FL (Edit › Undo), puis réessaie."));
            break;
        }
        return done.Count;
    }

    /// Sons qui jouent sur cette piste seule, à cette position de la chanson.
    private HashSet<int> Heard(int track, double position)
    {
        try
        {
            _link.PlayTrack(track);
            if (position > 0) _link.Seek(position);
            _wait(0.2);
            _link.HeardChannels();
            _wait(_listen);
            return _link.HeardChannels();
        }
        catch (OrganizerError)
        {
            return new HashSet<int>();
        }
        finally
        {
            _link.StopRestore();
        }
    }

    /// Noms comparés tels que le script les lit (coupés) : le nom relu est le début du nom posé.
    public static bool NamesMatch(IReadOnlyDictionary<int, string> sent, IReadOnlyDictionary<int, string> read) =>
        sent.All(item =>
        {
            if (!read.TryGetValue(item.Key, out var got) || OrganizerPayload.NameUtf8(item.Value) is not { } bytes) return false;
            var readBytes = System.Text.Encoding.UTF8.GetBytes(got);
            return readBytes.Length > 0 && bytes.Take(readBytes.Length).SequenceEqual(readBytes);
        });

    /// Icônes en dernier (FL ne dit pas lesquelles étaient là : « Revenir comme avant » ne les retire pas).
    private void PlaceIcons(Dictionary<int, FlIcon> icons, ItemKind kind, Func<int, int?> place)
    {
        var page = kind == ItemKind.Channels ? FlWindow.ChannelRack : FlWindow.Mixer;
        foreach (var index in icons.Keys.OrderBy(k => k))
        {
            if (place(index) is not { } at) continue;
            if (_link.Window != page) throw OrganizerError.Interrupted;
            _link.SelectOne(kind, at);
            if (_placeIcon(icons[index]) is { } error) throw error;
        }
    }

    /// Pur (testé) : place → index d'origine, d'après les noms relus dans FL ; null si un nom se répète ou ne
    /// correspond pas.
    public static List<int>? Arrangement(IReadOnlyList<string> now, IReadOnlyList<string> original)
    {
        if (now.Count != original.Count || original.Distinct().Count() != original.Count) return null;
        var at = new Dictionary<string, int>();
        for (var i = 0; i < original.Count; i++) at[original[i]] = i;
        var out_ = now.Where(at.ContainsKey).Select(n => at[n]).ToList();
        return out_.Count == now.Count && out_.Distinct().Count() == out_.Count ? out_ : null;
    }

    /// Une page de FL qui n'est plus devant pendant les déplacements est remise devant ; arrêt si elle repart encore
    /// après `PageRetries` fois.
    public const int PageRetries = 4;

    /// Déplacements un par un (élément sélectionné puis touches) ; la disposition suit ce qui a vraiment été fait.
    /// `offset` : index FL de la place 0 (Mixer : 1, le Master ne bouge pas).
    private void MoveAll(List<Move> moves, AreaSnapshot snap, FlWindow page, ItemKind kind, int offset, Func<int, int> key)
    {
        var retries = 0;
        void Restore()
        {
            retries++;
            _restored++;
            if (retries > PageRetries) throw OrganizerError.Interrupted;
            try { _link.Show(page); } catch (OrganizerError) { }
            _wait(0.5);
        }
        // Mixer : la disposition est en numéros de pistes (place 0 = piste 1), ramenée à la base des places.
        var arrangement = snap.Arrangement.Select(x => x - offset).ToList();
        try
        {
            foreach (var step in moves)
            {
                var place = step.From;
                var left = step.Up;
                while (left > 0)
                {
                    if (_link.Window != page)
                    {
                        Restore();
                        continue;
                    }
                    _link.SelectOne(kind, place + offset);
                    var done = Math.Min(Math.Max(key(left), 0), left);
                    arrangement = RegroupPlan.Applying(new Move(place, done), arrangement);
                    place -= done;
                    left -= done;
                    if (done == 0) Restore();
                }
            }
        }
        finally
        {
            snap.Arrangement = arrangement.Select(x => x + offset).ToList();
        }
    }

    /// « Revenir comme avant » : rangé dans une copie, l'original rouvert dans FL (tout revient, sons supprimés
    /// compris) ; sinon Playlist, Mixer, patterns, Channel rack remis, puis les sons reliés à une piste renvoyés au
    /// Master. Chaque page remise sort du mémo : un retour interrompu reprend là où il s'est arrêté.
    public ApplyOutcome Undo(OrganizerSnapshot snapshot)
    {
        var outcome = new ApplyOutcome { Snapshot = snapshot };
        if (snapshot.Original is { } original)
        {
            if (_files is null || !_files.Open(original))
            {
                outcome.Error = OrganizerError.Failed(Loc.T("FL n'a pas pu rouvrir ton projet d'origine : il est toujours là, ouvre-le dans FL."));
                return outcome;
            }
            outcome.Snapshot = new OrganizerSnapshot();
            return outcome;
        }
        try
        {
            if (snapshot.Playlist is { } s)
            {
                var arrangement = s.Arrangement;
                int Current(int o) { var at = arrangement.IndexOf(o); return at < 0 ? o : at; }
                _link.SetColors(ItemKind.Playlist, Pairs(s.Colors.ToDictionary(kv => Current(kv.Key), kv => kv.Value)));
                _link.SetNames(ItemKind.Playlist, NamePairs(s.Names.ToDictionary(kv => Current(kv.Key), kv => kv.Value)));
                s.Colors = new Dictionary<int, RgbColor>();
                s.Names = new Dictionary<int, string>();
                var places = arrangement.ToList();
                var back = RegroupPlan.Back(places);
                if (back.Count > 0) _link.Show(FlWindow.Playlist);
                foreach (var step in back)
                {
                    var done = _moveTrack(step.From, step.Up);
                    places = RegroupPlan.Applying(new Move(step.From, done), places);
                    s.Arrangement = places;
                    if (done < step.Up) throw OrganizerError.Interrupted;
                }
                outcome.Snapshot.Playlist = null;
            }
            if (snapshot.Splits is { } splits)
            {
                for (var i = splits.Count - 1; i >= 0; i--)
                {
                    var split = splits[i];
                    var rows = split.To - split.From;
                    if (_moveClips(split.Pattern + 1, -rows) != rows) throw OrganizerError.Interrupted;
                    splits.RemoveAt(i);
                }
                outcome.Snapshot.Splits = null;
            }
            if (snapshot.Mixer is { } mixer)
            {
                UndoArranged(mixer, ItemKind.Mixer, FlWindow.Mixer, 1, _moveLeft);
                // Les envois d'origine, une fois chaque piste revenue à sa place.
                foreach (var (track, dests) in mixer.Routes.OrderBy(kv => kv.Key).ToList())
                {
                    _link.SetRoutes(track, dests);
                    mixer.Routes.Remove(track);
                }
                outcome.Snapshot.Mixer = null;
            }
            if (snapshot.Patterns is { } patterns)
            {
                _link.SetColors(ItemKind.Patterns, Pairs(patterns.Colors));
                _link.SetNames(ItemKind.Patterns, NamePairs(patterns.Names));
                outcome.Snapshot.Patterns = null;
            }
            if (snapshot.Rack is { } rack)
            {
                UndoArranged(rack, ItemKind.Channels, FlWindow.ChannelRack, 0, _moveUp);
                outcome.Snapshot.Rack = null;
            }
            // Les sons envoyés au Master y retournent, une fois chaque canal revenu à sa place.
            if (snapshot.Links is { } links)
            {
                foreach (var (channel, track) in links.OrderBy(kv => kv.Key).ToList())
                {
                    _link.LinkChannel(channel, track);
                    links.Remove(channel);
                }
                outcome.Snapshot.Links = null;
            }
        }
        catch (Exception e)
        {
            outcome.Error = Failure(e);
        }
        return outcome;
    }

    /// Couleurs et noms d'origine sur la place actuelle de chaque élément, puis déplacements vers l'ordre d'origine.
    private void UndoArranged(AreaSnapshot s, ItemKind kind, FlWindow page, int offset, Func<int, int> key)
    {
        var arrangement = s.Arrangement;
        int Current(int original) { var place = arrangement.IndexOf(original); return place < 0 ? original : place + offset; }
        _link.SetColors(kind, Pairs(s.Colors.ToDictionary(kv => Current(kv.Key), kv => kv.Value)));
        _link.SetNames(kind, NamePairs(s.Names.ToDictionary(kv => Current(kv.Key), kv => kv.Value)));
        s.Colors = new Dictionary<int, RgbColor>();
        s.Names = new Dictionary<int, string>();
        var back = RegroupPlan.Back(arrangement.Select(x => x - offset).ToList());
        if (back.Count == 0) return;
        _link.Show(page);
        MoveAll(back, s, page, kind, offset, key);
    }
}
