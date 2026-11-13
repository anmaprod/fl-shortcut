// Organiser : ce dont il a besoin du vrai PC (le contrôleur, l'analyse et l'application sont ceux du cœur, testés).
// Lien MIDI signé, son de FL, IA intégrée (ONNX), touches de FL (FL devant seulement), fichier du projet, réglages et
// copies en attente gardés dans les réglages de l'appli (vérifiés à la lecture). Miroir de OrganizerEnvironment.live
// (Sources/FLShortcut/OrganizerWindow.swift).
using System.Diagnostics;
using FLShortcut.Core;
using FLShortcut.Core.Organizer;
using Microsoft.UI.Dispatching;

namespace FLShortcut.App.Services;

internal static class OrganizerLive
{
    /// L'environnement de la fenêtre de l'Organiser. `choose` : « Choisir le fichier… » (fil de l'interface, vrai si un
    /// .flp a été montré) ; `installElsewhere` : « Autre dossier de FL… ».
    /// « Quitter et rouvrir FL » : sa fenêtre principale fermée comme par la croix (FL demande d'enregistrer s'il le
    /// faut), puis FL relancé depuis le même fichier dès qu'il est parti (2 minutes au plus).
    /// Une relance à la fois (09/11, « quand on clique plusieurs fois… ça ouvre le nombre de FL que de clics ») : les
    /// clics suivants ne font rien tant que FL n'est pas reparti puis rouvert (2 min 30 au plus).
    private static int _restarting;

    /// « Ouvrir FL Studio » (FL fermé à l'étape 2, comme le Mac) : le FL vu en dernier, sinon le plus récent installé
    /// dans Program Files › Image-Line. Un seul lancé, même après plusieurs clics.
    public static void OpenFlStudio()
    {
        if (FlPresence.RunningInstance() is not null || Interlocked.CompareExchange(ref _restarting, 1, 0) != 0) return;
        var path = _lastFlPath is { } known && File.Exists(known) ? known : InstalledFl();
        if (path is null)
        {
            Volatile.Write(ref _restarting, 0);
            return;
        }
        Start(path, "");
        _ = Task.Run(() =>
        {
            try { for (var i = 0; i < 30 && FlPresence.RunningInstance() is null; i++) Thread.Sleep(1000); }
            finally { Volatile.Write(ref _restarting, 0); }
        });
    }

    private static string? _lastFlPath;

    /// FL64.exe du dossier « FL Studio … » le plus récent de Program Files › Image-Line, s'il y en a un.
    private static string? InstalledFl()
    {
        try
        {
            var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Image-Line");
            if (!Directory.Exists(root)) return null;
            return Directory.EnumerateDirectories(root, "FL Studio*")
                .Select(d => Path.Combine(d, "FL64.exe")).Where(File.Exists)
                .OrderByDescending(File.GetLastWriteTimeUtc).FirstOrDefault();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return null; }
    }

    private static void RestartFl()
    {
        if (Interlocked.CompareExchange(ref _restarting, 1, 0) != 0) return;
        if (FlPresence.RunningInstance() is not { } fl)
        {
            Volatile.Write(ref _restarting, 0);
            return;
        }
        System.Diagnostics.Process process;
        try { process = System.Diagnostics.Process.GetProcessById((int)fl.Pid); }
        catch (ArgumentException) { Volatile.Write(ref _restarting, 0); return; }
        var path = fl.Path;
        _lastFlPath = path;
        bool asked;
        try { asked = process.CloseMainWindow(); }
        catch (InvalidOperationException) { process.Dispose(); Volatile.Write(ref _restarting, 0); return; }
        process.Dispose();
        AppLog.Write("RESTART", "FL quit asked: " + (asked ? "yes" : "no main window"));
        // 12/11 (« il ne rouvre pas automatiquement FL Studio ») : FL regardé toutes les 0,5 s, lancé dès qu'il est
        // parti, relancé s'il n'apparaît pas (FlRelaunchPlan, mêmes règles que le Mac).
        var oldPid = (int)fl.Pid;
        _ = Task.Run(() =>
        {
            try
            {
                var clock = Stopwatch.StartNew();
                var plan = new FlRelaunchPlan(oldPid, 0);
                while (true)
                {
                    Thread.Sleep(500);
                    var now = clock.Elapsed.TotalSeconds;
                    var running = FlPresence.RunningInstance() is { } r ? new[] { (int)r.Pid } : Array.Empty<int>();
                    switch (plan.Next(now, running))
                    {
                        case FlRelaunchPlan.Step.Launch:
                            var started = Start(path, "");
                            if (!started) plan.LaunchFailed(now);
                            AppLog.Write("RESTART", $"FL gone after {plan.GoneAt:0.0} s, launch {plan.Launches}: "
                                + (started ? "started" : "failed") + $" at {now:0.0} s");
                            break;
                        case FlRelaunchPlan.Step.Done:
                            AppLog.Write("RESTART", $"FL back after {now:0.0} s ({plan.Launches} launch(es))");
                            return;
                        case FlRelaunchPlan.Step.GiveUp:
                            AppLog.Write("RESTART", plan.GoneAt is null
                                ? $"FL still running after {now:0} s: nothing launched"
                                : $"FL not back after {plan.Launches} launch(es), {now:0} s");
                            return;
                    }
                }
            }
            finally { Volatile.Write(ref _restarting, 0); }
        });
    }

    public static OrganizerEnvironment Make(AppController app, DispatcherQueue ui, Func<bool> choose, Func<bool> installElsewhere)
    {
        var worker = new SerialWorker();
        var corrections = Corrections(app);
        return new OrganizerEnvironment
        {
            Link = () => new RequestOrganizerLink(bytes => app.Midi.RunRequest(bytes, app.Light), () => app.Midi.Window),
            Audio = () => FlControl.Process() switch
            {
                null => (null, OrganizerError.FlClosed),
                { Elevated: true } => (null, OrganizerError.Failed(Loc.T("FL est lancé en administrateur : relance-le normalement."))),
                var fl => (new FlAudioCapture(fl.Pid), null),
            },
            Classify = () => OrganizerSession.LiveClassifier(ClasseurSons.Partage(), corrections),
            NameDrum = () => OrganizerSession.LiveDrumNamer(ClasseurSons.Partage(), corrections),
            NameMelody = () => OrganizerSession.LiveMelodyNamer(ClasseurSons.Partage(), corrections),
            NameKind = () => OrganizerSession.LiveKindNamer(ClasseurSons.Partage(), corrections),
            Fingerprint = () => OrganizerSession.LiveFingerprint(ClasseurSons.Partage()),
            Corrections = () => corrections,
            MoveUp = link => count => Move(count, new KeyCombo(Vk.Up, Alt: true), FlWindow.ChannelRack, link),
            MoveLeft = link => count => Move(count, new KeyCombo(Vk.Left, Alt: true), FlWindow.Mixer, link),
            DeleteSelected = link => () => DeleteSelected(link),
            ProjectFiles = ProjectFileWindows.Access,
            EscapePressed = FlControl.EscapePressed,
            LoadStyles = () => FamilyStyles.Decode(app.Settings.OrganizerStyles),
            SaveStyles = styles =>
            {
                app.Settings.OrganizerStyles = FamilyStyles.Encode(styles);
                app.Settings.Save();
            },
            LoadFamilyOrder = () => (app.Settings.OrganizerFamilyOrder ?? new List<string>())
                .Select(SoundFamilies.FamilyFromRaw).OfType<SoundFamily>().ToList(),
            SaveFamilyOrder = order =>
            {
                app.Settings.OrganizerFamilyOrder = order.Select(f => f.Raw()).ToList();
                app.Settings.Save();
            },
            PlaceIcon = _ => OrganizerError.Failed(Loc.T("Les icônes de FL ne sont pas encore posées sur Windows. Les couleurs sont posées.")),
            PrepareLink = () => PrepareLink(app),
            ReleaseLink = () => app.Midi.Release(LinkUser.Organizer),
            UseLinkAgain = () => app.Midi.Use(LinkUser.Organizer),
            InstallLink = () => app.InstallScript() is null,
            RestartFl = RestartFl,
            InstallLinkElsewhere = installElsewhere,
            ScriptPlace = () => app.Settings.ScriptPath is { } path ? (path, File.Exists(path)) : null,
            Reveal = path => Start("explorer.exe", "/select,\"" + path + "\""),
            WrongInput = () => app.Midi.WrongInput,
            SoundFile = () => SampleFileReader(),
            About = () => About(app),
            Copy = text => ui.TryEnqueue(() =>
            {
                var data = new Windows.ApplicationModel.DataTransfer.DataPackage();
                data.SetText(text);
                Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(data);
            }),
            FocusFl = () =>
            {
                if (FlControl.Process() is { } fl) FlControl.BringForward(fl.Pid);
            },
            ChooseProject = choose,
            CopyMade = (original, copy) => app.Approval.Record(original, copy),
            KeepCopy = copy => app.RequestKeep(copy),
            // « Revenir comme avant » : la version organisée à la Corbeille dès que FL l'a quittée (demande du 28/10) ;
            // encore ouverte au bout d'une minute : elle reste, la question reviendra.
            CopyUndone = copy =>
            {
                if (app.Approval.Find(copy) is not { } pending) return;
                var files = app.Approval.Files;
                Task.Run(() =>
                {
                    var gone = CopyApprovalPrompt.Fl.DiscardAfterUndo(pending, files);
                    ui.TryEnqueue(() => { if (gone) app.Approval.Done(pending); });
                });
            },
            AppVersion = AppVersion(),
            Post = action => ui.TryEnqueue(() => action()),
            Background = worker.Run,
            After = (seconds, action) =>
            {
                var timer = ui.CreateTimer();
                timer.Interval = TimeSpan.FromSeconds(Math.Max(seconds, 0.01));
                timer.IsRepeating = false;
                timer.Tick += (t, _) =>
                {
                    t.Stop();
                    action();
                };
                timer.Start();
            },
        };
    }

    /// Lien installé : script remis dans FL s'il en a disparu (FL le relira à son prochain lancement), lien tenu par
    /// l'Organiser jusqu'à la fin du rangement ou sa fermeture (le temps que FL voie le script : 2 secondes la première
    /// fois). FL ouvert avant les ports de l'appli : il ne les voit pas, « Quitte et rouvre FL » (08/11 au soir).
    private static bool _flBeforePortsLogged;

    private static OrganizerLinkState PrepareLink(AppController app)
    {
        if (FlPresence.RunningInstance() is { } running) _lastFlPath = running.Path;     // pour « Ouvrir FL Studio »
        if (!app.Midi.HasKey) return new OrganizerLinkState.NotInstalled();
        if (app.RepairScriptIfMissing()) return new OrganizerLinkState.Restored();
        MidiLink.PortsReady();
        var before = MidiServicesPorts.FlOpenedBefore();
        if (before != _flBeforePortsLogged)
        {
            _flBeforePortsLogged = before;                   // une ligne par changement, pas toutes les 2 s
            if (before) AppLog.Write("MIDI", "FL opened before the ports: restart asked");
        }
        if (before) return new OrganizerLinkState.Restored();
        var fresh = app.Midi.Use(LinkUser.Organizer);
        return new OrganizerLinkState.Ready(fresh ? 2 : 0);
    }

    /// Alt + flèche (↑ dans le Channel rack, ← dans le Mixer) envoyé à FL seul, 15 ms entre deux ; s'arrête dès que FL
    /// n'est plus au premier plan. La page devant est demandée à FL une fois (une requête), pas à chaque touche.
    private static int Move(int count, KeyCombo key, FlWindow page, IOrganizerLink link)
    {
        if (count <= 0 || FlControl.Process() is not { } fl) return 0;
        // -1 : FL pas au premier plan, aucune touche envoyée (diagnostic « FL derrière », 12/11, comme le Mac).
        if (!FlControl.BringForward(fl.Pid)) return -1;
        if (link.Window != page) return 0;
        var done = 0;
        while (done < count && FlControl.Send(fl.Pid, key))
        {
            done++;
            Thread.Sleep(15);
        }
        return done == 0 ? -1 : done;
    }

    /// « Delete selected » du Channel rack comme le ferait l'utilisateur : Alt + Suppr, FL devant, le Channel rack
    /// devant. Une fenêtre de FL ouverte par la touche (une confirmation) est validée par Entrée.
    private static bool DeleteSelected(IOrganizerLink link)
    {
        if (FlControl.Process() is not { } fl || !FlControl.BringForward(fl.Pid) || link.Window != FlWindow.ChannelRack) return false;
        var before = FlControl.Windows(fl.Pid).Select(w => w.Handle).ToHashSet();
        if (!FlControl.Send(fl.Pid, new KeyCombo(Vk.Delete, Alt: true))) return false;
        for (var i = 0; i < 10; i++)
        {
            Thread.Sleep(100);
            var opened = FlControl.Windows(fl.Pid).Where(w => !before.Contains(w.Handle) && w.Width >= 150 && w.Height >= 80).ToList();
            if (opened.Count == 0) continue;
            AppLog.Write("ORGANIZE", "delete: FL asked for a confirmation, Return");
            FlControl.Send(fl.Pid, new KeyCombo(Vk.Return));
            break;
        }
        Thread.Sleep(200);
        return true;
    }

    /// Les corrections de l'IA gardées sur ce PC (fichier de l'appli, écrit d'un coup), l'accord dans les réglages.
    private static CorrectionsIA Corrections(AppController app) => new(
        Path.Combine(AppPaths.Local, "corrections-ia.json"),
        () => app.Settings.ShareCorrections,
        value =>
        {
            app.Settings.ShareCorrections = value;
            app.Settings.Save();
        },
        (path, bytes) => SafeFile.WriteAtomic(path, bytes),
        path =>
        {
            try
            {
                if (!File.Exists(path)) return null;
                SafeFile.EnsureNoLinks(path);
                return new FileInfo(path).Length > 8_000_000 ? null : File.ReadAllBytes(path);
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return null; }
        });

    /// Le fichier de son d'un clip audio de FL (WAV ou AIFF), retrouvé comme FL le ferait, puis son passage le plus fort.
    private static OrganizerSession.SoundFile SampleFileReader()
    {
        var (factory, user) = FlFolders();
        return (path, project) =>
        {
            var found = SampleFiles.Resolve(path, project, factory, user, File.Exists, name => SearchSample(name, user));
            return found is not null && SampleAudio.ReadPcm(found) is { } sound ? SampleAudio.Loudest(sound.Samples, sound.Rate) : null;
        };
    }

    /// « %FLStudioFactoryData% » : le dossier où FL est installé ; « %FLStudioUserData% » : ses données dans Documents.
    private static (List<string> Factory, List<string> User) FlFolders()
    {
        var factory = new List<string>();
        if (FlControl.Process() is { Path.Length: > 0 } fl && Path.GetDirectoryName(fl.Path) is { } install) factory.Add(install);
        var programs = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        var imageLine = Path.Combine(programs, "Image-Line");
        if (Directory.Exists(imageLine))
            factory.AddRange(Directory.EnumerateDirectories(imageLine, "FL Studio*").OrderDescending());
        var documents = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
        var user = new List<string>
        {
            Path.Combine(documents, "Image-Line", "FL Studio"), Path.Combine(documents, "Image-Line", "Data", "FL Studio"),
        };
        return (factory.Distinct(StringComparer.OrdinalIgnoreCase).ToList(), user);
    }

    /// Un son du même nom ailleurs (dossiers de FL et dossiers habituels, 2 secondes au plus, 20 au plus).
    private static IReadOnlyList<string> SearchSample(string name, IReadOnlyList<string> user)
    {
        if (name.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0 || name.Contains('*') || name.Contains('?')) return Array.Empty<string>();
        var folders = user.Concat(new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.MyMusic),
            Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads"),
        }).Where(Directory.Exists).Distinct(StringComparer.OrdinalIgnoreCase);
        var options = new EnumerationOptions
        {
            RecurseSubdirectories = true, MaxRecursionDepth = 8, IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.System | FileAttributes.ReparsePoint, MatchCasing = MatchCasing.CaseInsensitive,
        };
        var budget = DateTime.UtcNow.AddSeconds(2);
        var out_ = new List<string>();
        foreach (var folder in folders)
        {
            try
            {
                foreach (var path in Directory.EnumerateFiles(folder, name, options))
                {
                    out_.Add(path);
                    if (out_.Count >= 20 || DateTime.UtcNow > budget) return out_;
                }
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
            if (DateTime.UtcNow > budget) break;
        }
        return out_;
    }

    /// En-tête du diagnostic : versions et état du lien (aucun nom).
    private static string About(AppController app)
    {
        var fl = FlControl.Process();
        var hello = app.Midi.Hello;
        return $"app {AppVersion()} · Windows {Environment.OSVersion.Version} · FL {fl?.Version?.ToString() ?? "?"} "
               + $"· API {hello?.ApiVersion.ToString() ?? "?"} · lien {(hello is null ? "muet" : "ok")} · ports {(MidiLink.PortsExist() ? "oui" : "non")} "
               + $"({MidiServicesPorts.Source()}{(MidiServicesPorts.FlOpenedBefore() ? ", FL ouvert avant" : "")}) "
               + $"· {app.Midi.Counters} "
               + $"· léger={(app.Light ? "oui" : "non")} · admin={(fl?.Elevated == true ? "oui" : "non")} "
               + $"· signé={(fl is null ? "?" : fl.Signed ? "oui" : "non")}";
    }

    private static string AppVersion() =>
        typeof(OrganizerLive).Assembly.GetName().Version?.ToString(3) ?? "?";

    /// Lancé depuis son propre dossier (comme par l'Explorateur) ; faux si Windows n'a rien lancé.
    private static bool Start(string file, string arguments)
    {
        try
        {
            var info = new ProcessStartInfo(file, arguments) { UseShellExecute = false };
            if (Path.GetDirectoryName(file) is { Length: > 0 } folder) info.WorkingDirectory = folder;
            using var started = Process.Start(info);
            return started is not null;
        }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            AppLog.Write("RESTART", "launch error " + (e is System.ComponentModel.Win32Exception w ? w.NativeErrorCode : -1));
            return false;
        }
    }

    /// Un travail long à la fois, hors du fil de l'interface (dans l'ordre).
    private sealed class SerialWorker
    {
        private readonly object _gate = new();
        private Task _last = Task.CompletedTask;

        public void Run(Action action)
        {
            lock (_gate)
            {
                _last = _last.ContinueWith(_ =>
                {
                    try { action(); }
                    catch (Exception e) { AppLog.Write("ORGANIZE", "background step failed: " + e.GetType().Name); }
                }, CancellationToken.None, TaskContinuationOptions.LongRunning, TaskScheduler.Default);
            }
        }
    }
}
