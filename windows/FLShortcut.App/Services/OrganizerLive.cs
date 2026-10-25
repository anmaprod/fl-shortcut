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
                { Elevated: true } => (null, OrganizerError.Failed(Loc.T("FL Studio est lancé en administrateur : Windows empêche FL Shortcuts d'agir dessus. Relance FL Studio normalement, puis « Réessayer »."))),
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
            InstallLink = () => app.InstallScript() is null,
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
            CopyUndone = copy => app.Approval.Forget(copy),
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

    /// Lien installé : script remis dans FL s'il en a disparu (FL le relira à son prochain lancement), ports ouverts à
    /// la demande (le temps que FL voie le script : 2 secondes la première fois).
    private static OrganizerLinkState PrepareLink(AppController app)
    {
        if (!app.Midi.HasKey) return new OrganizerLinkState.NotInstalled();
        if (app.RepairScriptIfMissing()) return new OrganizerLinkState.Restored();
        var fresh = !app.Midi.Started;
        app.Midi.Start();
        return new OrganizerLinkState.Ready(fresh ? 2 : 0);
    }

    /// Alt + flèche (↑ dans le Channel rack, ← dans le Mixer) envoyé à FL seul, 15 ms entre deux ; s'arrête dès que FL
    /// n'est plus au premier plan. La page devant est demandée à FL une fois (une requête), pas à chaque touche.
    private static int Move(int count, KeyCombo key, FlWindow page, IOrganizerLink link)
    {
        if (count <= 0 || FlControl.Process() is not { } fl || !FlControl.BringForward(fl.Pid)) return 0;
        if (link.Window != page) return 0;
        var done = 0;
        while (done < count && FlControl.Send(fl.Pid, key))
        {
            done++;
            Thread.Sleep(15);
        }
        return done;
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
               + $"· léger={(app.Light ? "oui" : "non")} · admin={(fl?.Elevated == true ? "oui" : "non")}";
    }

    private static string AppVersion() =>
        typeof(OrganizerLive).Assembly.GetName().Version?.ToString(3) ?? "?";

    private static void Start(string file, string arguments)
    {
        try { using var _ = Process.Start(new ProcessStartInfo(file, arguments) { UseShellExecute = false }); }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException) { }
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
