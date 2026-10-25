// Organiser sur le fichier du projet, côté Windows : FL enregistre le projet ouvert (Ctrl+S, FL au premier plan), son
// fichier est retrouvé (celui que FL vient d'écrire : surveillé dans les dossiers habituels, sinon celui qui porte le
// nom du titre de FL ; déjà enregistré, FL ne le réécrit pas : pris tel quel), puis FL ouvre la copie rangée comme un
// double-clic dans l'Explorateur. Introuvable : l'utilisateur le montre (« Choisir le fichier… »), et le diagnostic
// dit ce que la recherche a vu. Aucune lecture de l'écran ; seuls les chemins des fichiers sont lus, jamais
// journalisés. Miroir de Sources/FLShortcut/OrganizerProjectLive.swift.
using System.Diagnostics;
using FLShortcut.Core;
using FLShortcut.Core.Organizer;

namespace FLShortcut.App.Services;

internal static class ProjectFileWindows
{
    public static ProjectFileAccess Access() => new()
    {
        Save = Save,
        Open = Open,
        IsOpen = IsOpen,
        AnswerDialog = AnswerDialog,
        Search = () => LastSearch,
    };

    private static readonly object Gate = new();
    private static string? _chosen;
    private static string _searched = "";

    /// Le projet montré par l'utilisateur (« Choisir le fichier… » de l'Organiser) : cherché en premier.
    public static string? Chosen
    {
        get { lock (Gate) return _chosen; }
        set { lock (Gate) _chosen = value; }
    }

    /// La dernière recherche, en nombres et mots fixes (jamais un nom ni un chemin).
    public static string LastSearch
    {
        get { lock (Gate) return _searched; }
        private set { lock (Gate) _searched = value; }
    }

    private sealed class Search
    {
        public int Windows, Names, Candidates, Seen, Scanned;
        public string Taken = "aucun";
        public string Text => $"fenêtres={Windows} noms={Names} candidats={Candidates} vus={Seen} parcourus={Scanned} pris={Taken}";
    }

    /// Les dossiers où l'on range ses projets : celui de FL d'abord.
    private static List<string> Folders()
    {
        var documents = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return new[]
            {
                Path.Combine(documents, "Image-Line", "FL Studio", "Projects"), documents,
                Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
                Environment.GetFolderPath(Environment.SpecialFolder.MyMusic), Path.Combine(home, "Downloads"),
            }
            .Where(d => d.Length > 0 && Directory.Exists(d))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    /// La fenêtre de FL porte le nom de ce fichier : FL l'a ouvert.
    public static bool IsOpen(string path)
    {
        if (FlControl.Process() is not { } fl) return false;
        var name = Path.GetFileNameWithoutExtension(path);
        return FlControl.Windows(fl.Pid).Any(w => ProjectFile.TitleNames(w.Title).Contains(name, StringComparer.OrdinalIgnoreCase));
    }

    /// FL enregistre ; le fichier qu'il vient d'écrire. Un projet déjà enregistré, que FL ne réécrit pas : celui qui
    /// porte le nom de sa fenêtre (ou celui montré par l'utilisateur) tel quel, sa lecture vérifiant que c'est bien le
    /// projet ouvert (mêmes canaux, mêmes patterns). Rien de trouvé : l'utilisateur le montre (`ProjectNotFound`).
    public static string Save(string? known)
    {
        if (FlControl.Process() is not { } fl) throw OrganizerError.FlClosed;
        var search = new Search();
        try
        {
            var candidates = Candidates(fl.Pid, known, search);
            var before = candidates.ToDictionary(p => p, Modified, StringComparer.OrdinalIgnoreCase);
            using var watch = new WrittenWatch(Folders().Concat(candidates.Select(c => Path.GetDirectoryName(c) ?? "")));
            var start = DateTime.UtcNow;
            if (!SendSave(fl.Pid))
            {
                search.Taken = "premier-plan";
                throw OrganizerError.Failed(Loc.T("FL Studio doit être au premier plan pour enregistrer ton projet : clique dans sa fenêtre, puis sur « Réessayer »."));
            }
            bool Written(string p) => Modified(p) is { } date && date >= start.AddSeconds(-1)
                                      && (before.TryGetValue(p, out var was) ? was is null || date > was : true);
            // FL écrit le projet (s'il a changé) : 6 secondes au plus.
            var deadline = DateTime.UtcNow.AddSeconds(6);
            while (DateTime.UtcNow < deadline)
            {
                Thread.Sleep(250);
                if (candidates.FirstOrDefault(Written) is { } written)
                {
                    search.Taken = "écrit";
                    return Settled(written);
                }
                var seen = watch.Written(start.AddSeconds(-1));
                search.Seen = Math.Max(search.Seen, seen.Count);
                if (Newest(seen) is { } recent)
                {
                    search.Taken = "surveillé";
                    return Settled(recent);
                }
            }
            if (candidates.FirstOrDefault(Written) is { } late)
            {
                search.Taken = "écrit";
                return Settled(late);
            }
            if (candidates.Count == 0 && Walk(start.AddSeconds(-1), search) is { } walked)
            {
                search.Taken = "dossier";
                return Settled(walked);
            }
            if (candidates.Count > 0)
            {
                search.Taken = "déjà-enregistré";
                return candidates[0];
            }
            AppLog.Write("ORGANIZE", $"project file not found after save ({search.Text})");
            throw OrganizerError.ProjectNotFound;
        }
        finally
        {
            LastSearch = search.Text;
        }
    }

    /// FL enregistre le projet qu'il montre (ce fichier) : Ctrl+S, FL au premier plan, puis 4 secondes au plus pour
    /// l'écrire (rien à écrire s'il n'a pas changé). Faux si FL n'a pas pu passer au premier plan.
    public static bool SaveShown(string path)
    {
        if (FlControl.Process() is not { } fl) return false;
        var before = Modified(path);
        var start = DateTime.UtcNow;
        if (!SendSave(fl.Pid)) return false;
        var deadline = DateTime.UtcNow.AddSeconds(4);
        while (DateTime.UtcNow < deadline)
        {
            Thread.Sleep(250);
            if (Modified(path) is { } date && date >= start.AddSeconds(-1) && (before is null || date > before))
            {
                Thread.Sleep(500);                                // FL finit d'écrire
                return true;
            }
        }
        return true;
    }

    /// FL ouvre ce fichier comme un double-clic dans l'Explorateur (l'appli associée aux .flp, qui le passe à la
    /// fenêtre de FL déjà ouverte) ; sans association, l'exécutable de FL avec le fichier. Faux si Windows n'a pas pu
    /// le demander.
    public static bool Open(string path)
    {
        if (Start(new ProcessStartInfo(path) { UseShellExecute = true })) return true;
        if (FlControl.Process() is { Path.Length: > 0 } fl
            && Start(new ProcessStartInfo(fl.Path) { ArgumentList = { path }, UseShellExecute = false })) return true;
        AppLog.Write("ORGANIZE", "FL could not open the project file");
        return false;
    }

    private static bool Start(ProcessStartInfo info)
    {
        try
        {
            using var process = System.Diagnostics.Process.Start(info);
            return true;
        }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException or IOException)
        {
            return false;
        }
    }

    /// Fichiers qui peuvent être le projet ouvert, du plus sûr au moins sûr : celui montré par l'utilisateur, celui
    /// qu'on attend, puis ceux qui portent le nom du titre d'une fenêtre de FL (dossiers habituels), le plus récent
    /// d'abord. Jamais une copie de secours de FL.
    private static List<string> Candidates(uint pid, string? known, Search search)
    {
        var out_ = new List<string>();
        void Add(string? path)
        {
            if (path is null || !path.EndsWith(".flp", StringComparison.OrdinalIgnoreCase) || IsBackup(path)
                || out_.Contains(path, StringComparer.OrdinalIgnoreCase) || !File.Exists(path)) return;
            out_.Add(path);
        }
        Add(Chosen);
        Add(known);
        var windows = FlControl.Windows(pid);
        search.Windows = windows.Count;
        var names = new List<string>();
        foreach (var w in windows)
        {
            foreach (var name in ProjectFile.TitleNames(w.Title))
            {
                if (!names.Contains(name, StringComparer.OrdinalIgnoreCase)) names.Add(name);
            }
        }
        search.Names = names.Count;
        if (names.Count > 0)
        {
            var wanted = new HashSet<string>(names.Select(n => n + ".flp"), StringComparer.OrdinalIgnoreCase);
            var named = Files(search, 4).Where(p => wanted.Contains(Path.GetFileName(p)));
            foreach (var path in named.OrderByDescending(p => Modified(p) ?? DateTime.MinValue)) Add(path);
        }
        search.Candidates = out_.Count;
        return out_;
    }

    /// Un .flp écrit à l'instant, cherché dans les dossiers habituels (4 secondes au plus).
    private static string? Walk(DateTime since, Search search) =>
        Newest(Files(search, 4).Where(p => Modified(p) is { } d && d >= since).ToList());

    /// Les .flp des dossiers habituels (6 niveaux au plus, dans le temps donné), jamais une copie de secours.
    private static IEnumerable<string> Files(Search search, double seconds)
    {
        var budget = DateTime.UtcNow.AddSeconds(seconds);
        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true, MaxRecursionDepth = 6, IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.Hidden | FileAttributes.System | FileAttributes.ReparsePoint,
            MatchCasing = MatchCasing.CaseInsensitive,
        };
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var folder in Folders())
        {
            if (DateTime.UtcNow > budget) yield break;
            IEnumerator<string> walk;
            try { walk = Directory.EnumerateFiles(folder, "*.flp", options).GetEnumerator(); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { continue; }
            using (walk)
            {
                while (DateTime.UtcNow <= budget)
                {
                    try { if (!walk.MoveNext()) break; }
                    catch (Exception e) when (e is IOException or UnauthorizedAccessException) { break; }
                    search.Scanned++;
                    var path = walk.Current;
                    if (!IsBackup(path) && seen.Add(path)) yield return path;
                }
            }
        }
    }

    private static string? Newest(IReadOnlyCollection<string> paths) =>
        paths.OrderByDescending(p => Modified(p) ?? DateTime.MinValue).FirstOrDefault();

    /// Copie de secours de FL (l'ancienne version, gardée à chaque enregistrement) ou enregistrement automatique :
    /// jamais pris pour le projet.
    private static bool IsBackup(string path)
    {
        var name = Path.GetFileName(path).ToLowerInvariant();
        return path.Split('\\', '/').Any(p => p.Equals("backup", StringComparison.OrdinalIgnoreCase))
               || name.Contains("(overwritten") || name.Contains("autosave");
    }

    /// Fichier fini d'écrire : sa taille ne bouge plus (2 secondes au plus).
    private static string Settled(string path)
    {
        long size = -1;
        for (var i = 0; i < 10; i++)
        {
            long now;
            try { now = new FileInfo(path).Length; }
            catch (IOException) { now = -1; }
            if (now == size && now > 0) break;
            size = now;
            Thread.Sleep(200);
        }
        return path;
    }

    private static DateTime? Modified(string path)
    {
        try { return File.Exists(path) ? File.GetLastWriteTimeUtc(path) : null; }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return null; }
    }

    /// Une boîte de FL qui bloque l'ouverture de la copie (« Invalid project data folder ») : FL devant, Entrée valide
    /// son choix par défaut (« Do nothing », comme l'utilisateur l'aurait fait). Lue par les titres des fenêtres de FL.
    /// null : aucune boîte, ou FL pas devant.
    public static string? AnswerDialog()
    {
        if (FlControl.Process() is not { } fl
            || !FlControl.Windows(fl.Pid).Any(w => ProjectFile.IsBlockingDialog(w.Title))) return null;
        if (!FlControl.BringForward(fl.Pid)) return null;
        return FlControl.Send(fl.Pid, new KeyCombo(Vk.Return)) ? "dossier-données" : null;
    }

    /// Ctrl+S envoyé à FL seul, FL au premier plan.
    private static bool SendSave(uint pid) => FlControl.BringForward(pid) && FlControl.Send(pid, new KeyCombo(Vk.Letter('S'), Ctrl: true));

    /// Les .flp écrits dans ces dossiers (et leurs sous-dossiers) pendant l'enregistrement ; FL écrit parfois un
    /// fichier temporaire puis le renomme : le nom final compte.
    private sealed class WrittenWatch : IDisposable
    {
        private readonly List<FileSystemWatcher> _watchers = new();
        private readonly HashSet<string> _paths = new(StringComparer.OrdinalIgnoreCase);

        public WrittenWatch(IEnumerable<string> folders)
        {
            foreach (var folder in folders.Where(f => f.Length > 0 && Directory.Exists(f)).Distinct(StringComparer.OrdinalIgnoreCase).Take(8))
            {
                try
                {
                    var w = new FileSystemWatcher(folder, "*.flp")
                    {
                        IncludeSubdirectories = true,
                        NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.Size,
                    };
                    w.Changed += (_, e) => Note(e.FullPath);
                    w.Created += (_, e) => Note(e.FullPath);
                    w.Renamed += (_, e) => Note(e.FullPath);
                    w.EnableRaisingEvents = true;
                    _watchers.Add(w);
                }
                catch (Exception e) when (e is IOException or ArgumentException or UnauthorizedAccessException) { }
            }
        }

        private void Note(string path)
        {
            if (!path.EndsWith(".flp", StringComparison.OrdinalIgnoreCase) || IsBackup(path)) return;
            lock (_paths) _paths.Add(path);
        }

        public List<string> Written(DateTime since)
        {
            lock (_paths) return _paths.Where(p => Modified(p) is { } d && d >= since).ToList();
        }

        public void Dispose()
        {
            foreach (var w in _watchers) w.Dispose();
        }
    }
}
