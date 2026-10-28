// Chef d'orchestre : profil, analyse unique (REL-20), index du hook, lien MIDI, statut affiché.
// Audit : REL-06 / PROTOCOL.md §5 (statut Relié / Lien inactif / FL fermé), WIN-05 (FL administrateur signalé),
//         REL-22 (script modifié détecté), audit 04 (actions grisées selon le masque ou la version de FL),
//         audit 05 (pause clairement visible, avertissements de conflit).
using System.ComponentModel;
using System.Runtime.CompilerServices;
using FLShortcut.App.Services;
using FLShortcut.Core;
using FLShortcut.Core.Macros;
using Microsoft.UI.Dispatching;

namespace FLShortcut.App;

public sealed class ShortcutRow
{
    public required Shortcut Shortcut { get; init; }
    public required IReadOnlyList<string> Caps { get; init; }
    public required string Label { get; init; }
    public required string Description { get; init; }
    public required string Category { get; init; }
    public required string Where { get; init; }
    public required bool HasWarning { get; init; }
    public required string WarningText { get; init; }
    public double Opacity => Shortcut.Enabled ? 1.0 : 0.5;
    public Microsoft.UI.Xaml.Visibility WhereVisibility => string.IsNullOrEmpty(Where) ? Microsoft.UI.Xaml.Visibility.Collapsed : Microsoft.UI.Xaml.Visibility.Visible;
    public Microsoft.UI.Xaml.Visibility WarningVisibility => HasWarning ? Microsoft.UI.Xaml.Visibility.Visible : Microsoft.UI.Xaml.Visibility.Collapsed;
}

public sealed class ShortcutGroup
{
    public required string Title { get; init; }
    public required List<ShortcutRow> Rows { get; init; }
}

internal enum StatusKind { Linked, Inactive, FlClosed, Paused, Elevated, Incompatible, NoKey, Tampered }

internal sealed class AppController : INotifyPropertyChanged, IDisposable
{
    public event PropertyChangedEventHandler? PropertyChanged;

    private readonly DispatcherQueue _ui;
    private readonly AppSettings _settings = AppSettings.Load();
    private readonly MidiLink _midi = new();
    private readonly KeyboardHook _hook;
    private List<Shortcut> _shortcuts;
    /// Bibliothèque des macros en blocs (macros.json), écrite peu après chaque changement et à la fermeture.
    private readonly MacroLibraryStore _macros = new(new MacroFileStorage());
    private DispatcherQueueTimer? _macroSave;
    private readonly MacroRunner _runner;
    /// Macros compilées avec les règles de Windows : un bloc pas encore fait ici bloque sa macro.
    private static readonly ValidationContext MacroContext = new() { PlatformProblem = MacroEffectsWindows.Unsupported };
    private Dictionary<Guid, List<ShortcutIssue>> _issues = new();
    private FlProcessInfo? _foreground;
    private FlVersion? _flVersion;
    private string _query = "";

    public AppController(DispatcherQueue ui)
    {
        _ui = ui;
        Approval = new Core.Organizer.CopyApproval(() => _settings.PendingCopies, json =>
        {
            _settings.PendingCopies = json;
            _settings.Save();
        }, RecycleBin.Files());
        _shortcuts = ProfileStore.Load(out var warning) ?? ProfilePreset.Recommended.Shortcuts();
        LoadWarning = warning;
        _midi.SetKey(SecretStore.Load());
        _midi.Changed += () => OnUi(RefreshAll);
        _macros.Changed += () => OnUi(() =>
        {
            ScheduleMacroSave();
            RefreshAll();
        });
        _runner = new MacroRunner(_midi, _settings, () => Light, () => _hook!.EscapePresses, OnUi, () => OrganizerWindow.Show(this));
        _runner.Finished += OnMacroFinished;
        _hook = new KeyboardHook(_midi.SendAction, () => OnUi(Toggle), fl => OnUi(() => OnForeground(fl)),
            program => OnUi(() => RunMacro(program)));
    }

    public void Start()
    {
        if (!Light) _midi.Start();          // mode léger : aucun port MIDI ouvert, rien dans FL
        _hook.Start();
        RefreshAll();
    }

    // ---------- État affiché ----------

    public string? LoadWarning { get; }
    /// Fin d'une macro (fil de l'interface) : réussie, et le texte du résultat.
    public event Action<bool, string>? MacroFinished;

    /// Bibliothèque des macros illisible, inaccessible ou impossible à enregistrer (jamais de macro perdue en silence).
    public string? MacroProblem => _macros.Problem;
    internal MacroLibraryStore Macros => _macros;
    /// Mode léger (défaut) : FL Shortcuts n'envoie que des touches d'origine de FL, sans script ni MIDI.
    public bool Light => !(_settings.MidiActions ?? _settings.ScriptPath is not null);
    /// En mode léger, rien à configurer : pas d'accueil (ni loopMIDI, ni MIDI Settings).
    public bool Onboarded => _settings.Onboarded || Light;
    public bool Enabled => _settings.Enabled;
    public ProfilePreset CurrentPreset => Enum.TryParse<ProfilePreset>(_settings.Profile, out var p) ? p : ProfilePreset.Recommended;
    public IReadOnlyList<Shortcut> Shortcuts => _shortcuts;
    public List<ShortcutGroup> Groups { get; private set; } = new();
    public bool IsEmpty => Groups.Count == 0;
    public StatusKind Status { get; private set; }
    public string StatusTitle { get; private set; } = "";
    public string StatusText { get; private set; } = "";
    public bool PortsPresent => _midi.PortsPresent || MidiLink.PortsExist();
    public bool Linked => _midi.Alive;
    /// Pour l'Organiser : le lien MIDI, les réglages, les versions organisées en attente de validation.
    internal MidiLink Midi => _midi;
    internal AppSettings Settings => _settings;
    internal Core.Organizer.CopyApproval Approval { get; }

    public string Query
    {
        get => _query;
        set { if (_query != value) { _query = value; RebuildRows(); } }
    }

    // ---------- Actions ----------

    public void Toggle()
    {
        _settings.Enabled = !_settings.Enabled;
        _settings.Save();
        RefreshAll();
    }

    public void SetEnabled(bool on)
    {
        if (_settings.Enabled == on) return;
        Toggle();
    }

    public void CompleteOnboarding()
    {
        _settings.Onboarded = true;
        _settings.Save();
        Raise(nameof(Onboarded));
    }

    /// Installe le script FL avec une nouvelle clé. Renvoie un message d'erreur, ou null si tout va bien.
    public string? InstallScript(string? hardwareFolder = null)
    {
        try
        {
            var folder = hardwareFolder ?? ScriptInstaller.DefaultHardwareFolder;
            if (!Directory.Exists(Path.GetDirectoryName(folder)))
                return "Dossier de FL Studio introuvable. Choisis le dossier « Settings\\Hardware » de FL Studio.";
            var key = SecretStore.CreateNew();
            var (path, sha) = ScriptInstaller.Install(folder, key);
            _settings.ScriptPath = path;
            _settings.ScriptSha256 = sha;
            _settings.Save();
            _midi.SetKey(key);
            RefreshAll();
            return null;
        }
        catch (Exception e)
        {
            return "Installation impossible : " + e.Message;
        }
    }

    /// Le script a disparu de FL Studio (dossier vidé, FL réinstallé) : remis à sa place avec la même clé. Vrai s'il
    /// vient d'être remis (FL ne le lira qu'à son prochain lancement).
    public bool RepairScriptIfMissing()
    {
        if (_settings.ScriptPath is not { } path || File.Exists(path) || SecretStore.Load() is not { } key) return false;
        try
        {
            var (installed, sha) = ScriptInstaller.Install(Path.GetDirectoryName(Path.GetDirectoryName(path)!)!, key);
            _settings.ScriptPath = installed;
            _settings.ScriptSha256 = sha;
            _settings.Save();
            return true;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return false;
        }
    }

    /// « Tester » : ouvre le Mixer dans FL (action 33).
    public bool TestLink() => _midi.SendAction(33);

    /// « Tester » dans la fiche : envoie l'action choisie à FL.
    public bool TestAction(int id) => _midi.SendAction(id);

    public ActionAvailability Availability(int id) => Light
        ? LightMode.Availability(id)
        : AvailabilityResolver.Resolve(id, _midi.Hello?.Capabilities, _flVersion);

    public IReadOnlyList<ShortcutIssue> IssuesFor(Shortcut draft)
    {
        // Le brouillon est analysé après les autres raccourcis, pour qu'un doublon soit signalé sur lui.
        var list = _shortcuts.Where(s => s.Id != draft.Id).ToList();
        list.Add(draft with { Enabled = true });
        return ShortcutAnalyzer.Analyze(list, NewAnalysisContext())[draft.Id];
    }

    public void Upsert(Shortcut s)
    {
        var i = _shortcuts.FindIndex(x => x.Id == s.Id);
        if (i >= 0) _shortcuts[i] = s; else _shortcuts.Add(s);
        Persist();
    }

    public Shortcut? Delete(Guid id)
    {
        var s = _shortcuts.FirstOrDefault(x => x.Id == id);
        if (s is null) return null;
        _shortcuts.Remove(s);
        Persist();
        return s;
    }

    public void LoadPreset(ProfilePreset preset)
    {
        _shortcuts = preset.Shortcuts();
        _settings.Profile = preset.ToString();
        _settings.Save();
        Persist();
    }

    public ImportPreview PrepareImport(string json) => ProfileImporter.Prepare(json);

    public void ApplyImport(ImportPreview preview)
    {
        _shortcuts.AddRange(preview.Shortcuts);
        Persist();
    }

    public string ExportJson() => ProfileCodec.Encode(_shortcuts);

    public void SetRecording(bool recording) => _hook.Config = _hook.Config with { Recording = recording };

    // ---------- Interne ----------

    private AnalysisContext NewAnalysisContext() =>
        new(ProfilePresets.Toggle, ConflictTable.Default, Availability, _macros.Programs(MacroContext));

    // ---------- Page Macros ----------

    /// Ce qui empêche la macro de tourner sous Windows (bloc pas encore fait ici…), sinon null.
    public string? MacroIssue(Guid macro) =>
        _macros.Programs(MacroContext).TryGetValue(macro, out var program) ? program.Problem : null;

    /// « Montrer dans FL… » : FL mis devant, puis le prochain clic de l'utilisateur dans FL, rendu à `done` (sur le fil
    /// de l'interface). Renvoie ce qui l'empêche (FL fermé, apprentissage déjà en cours), sinon null.
    public string? LearnClick(Action<ClickTarget?, string?> done)
    {
        if (FlControl.Process() is not { } fl) return Loc.T("Ouvre FL Studio, puis recommence.");
        return ClickLearner.Start(fl.Pid, OnUi, done) ? null : Loc.T("Un clic est déjà en train d'être appris.");
    }

    /// Premier raccourci qui lance cette macro.
    public Shortcut? MacroShortcut(Guid macro) => MacroDrafts.ShortcutsOf(macro, _shortcuts).FirstOrDefault();

    /// Donne ce déclencheur à la macro (son raccourci est modifié, ou créé). Renvoie le problème qui l'en empêche
    /// (doublon, touche réservée…), sinon null. Une macro pas encore prête garde son raccourci (bloqué jusque-là).
    public string? SetMacroShortcut(Guid macro, KeyCombo trigger)
    {
        var draft = MacroShortcut(macro) is { } existing ? existing with { Trigger = trigger, Enabled = true }
            : Shortcut.RunsMacro(trigger, macro);
        var blocking = IssuesFor(draft).Where(i => i.IsBlocking && i is not ShortcutIssue.MacroInvalid).ToList();
        if (blocking.Count > 0) return string.Join(" ", blocking.Select(i => i.Message));
        Upsert(draft);
        return null;
    }

    public void RemoveMacroShortcut(Guid macro)
    {
        foreach (var s in MacroDrafts.ShortcutsOf(macro, _shortcuts)) _shortcuts.Remove(s);
        Persist();
    }

    /// Supprime la macro et ses raccourcis.
    public void DeleteMacro(Guid macro)
    {
        _macros.Remove(macro);
        RemoveMacroShortcut(macro);
    }

    /// Raccourci d'une macro (le hook l'a avalé) : une macro à la fois ; FL plus devant ou macro invalide : rien.
    private void RunMacro(MacroProgram program)
    {
        var result = _runner.Start(program);
        if (result != MacroRunner.StartResult.Started) AppLog.Write("MACRO", "not started: " + result);
    }

    private void OnMacroFinished(bool ok, string text)
    {
        if (!ok) Native.Win32.MessageBeep(Native.Win32.MB_ICONWARNING);
        MacroFinished?.Invoke(ok, text);
    }

    private void ScheduleMacroSave()
    {
        if (_macroSave is null)
        {
            _macroSave = _ui.CreateTimer();
            _macroSave.Interval = TimeSpan.FromMilliseconds(500);
            _macroSave.IsRepeating = false;
            _macroSave.Tick += (_, _) =>
            {
                _macros.SaveNow();
                if (_macros.SaveError is not null) Raise(nameof(MacroProblem));
            };
        }
        _macroSave.Stop();
        _macroSave.Start();
    }

    private void Persist()
    {
        try { ProfileStore.Save(_shortcuts); }
        catch { /* le profil reste en mémoire ; nouvel essai à la prochaine modification */ }
        RefreshAll();
    }

    private void OnForeground(FlProcessInfo? fl)
    {
        _foreground = fl;
        if (fl?.Version is { } v) _flVersion = v;
        RefreshAll();
    }

    private void RefreshAll()
    {
        if (_flVersion is null && FlPresence.RunningInstance() is { Version: { } v }) _flVersion = v;
        _issues = ShortcutAnalyzer.Analyze(_shortcuts, NewAnalysisContext());
        var blocked = ShortcutAnalyzer.Blocked(_issues);
        _hook.Config = _hook.Config with
        {
            Enabled = _settings.Enabled,
            Index = new ShortcutIndex(_shortcuts, blocked, _macros.Programs(MacroContext)),
            Toggle = ProfilePresets.Toggle,
            ActionNatives = LightMode.ActionNatives(Light),
            AnyContext = Light,
        };
        _hook.Link = _midi.RoutingView();
        UpdateStatus();
        RebuildRows();
        Raise(nameof(Enabled));
        Raise(nameof(PortsPresent));
        Raise(nameof(Linked));
    }

    private void UpdateStatus()
    {
        var flRunning = _foreground is not null || FlPresence.IsRunning();
        if (!_settings.Enabled)
            Set(StatusKind.Paused, "En pause", "FL Studio utilise ses raccourcis d'origine.");
        else if (_foreground is { Elevated: true })
            Set(StatusKind.Elevated, "FL Studio est lancé en administrateur",
                "Relance FL Studio normalement : Windows empêche FL Shortcuts d'agir sur une appli administrateur.");
        else if (Light)
        {
            if (flRunning) Set(StatusKind.Linked, "Actif dans FL Studio", "Tes raccourcis marchent quand FL Studio est au premier plan.");
            else Set(StatusKind.FlClosed, "FL Studio n'est pas ouvert", "Tes raccourcis marcheront dès que tu l'ouvres.");
        }
        else if (!_midi.HasKey)
            Set(StatusKind.NoKey, "Lien non installé", "Installe le lien avec FL Studio pour utiliser les actions.");
        else if (_settings.ScriptPath is not null && !ScriptInstaller.IsIntact(_settings.ScriptPath, _settings.ScriptSha256))
            Set(StatusKind.Tampered, "Le script FL a été modifié", "Réinstalle le lien pour retrouver un script sûr.");
        else if (_midi.Incompatible)
            Set(StatusKind.Incompatible, "Script FL d'une autre version", "Réinstalle le lien pour mettre le script à jour.");
        else
        {
            var link = LinkStatusExtensions.Resolve(flRunning, _midi.Alive);
            switch (link)
            {
                case LinkStatus.Linked:
                    Set(StatusKind.Linked, "Relié à FL Studio", "Actif quand FL Studio est au premier plan.");
                    break;
                case LinkStatus.Inactive:
                    Set(StatusKind.Inactive, "Lien inactif",
                        PortsPresent ? "Dans FL Studio : Options › MIDI Settings, active « FL Shortcuts »."
                                     : "Les ports MIDI « FL Shortcuts » sont introuvables.");
                    break;
                default:
                    Set(StatusKind.FlClosed, "FL Studio n'est pas ouvert", "Tes raccourcis marcheront dès que tu l'ouvres.");
                    break;
            }
        }
    }

    private void Set(StatusKind kind, string title, string text)
    {
        Status = kind;
        StatusTitle = title;
        StatusText = text;
        Raise(nameof(Status));
        Raise(nameof(StatusTitle));
        Raise(nameof(StatusText));
    }

    private void RebuildRows()
    {
        var q = _query.Trim();
        var cats = new[] { "Composition", "Enregistrement", "Mix", "Navigation", "Touches de FL" };
        var rows = _shortcuts.Select(ToRow)
            .Where(r => q.Length == 0
                        || r.Label.Contains(q, StringComparison.CurrentCultureIgnoreCase)
                        || r.Description.Contains(q, StringComparison.CurrentCultureIgnoreCase)
                        || string.Join(" ", r.Caps).Contains(q, StringComparison.CurrentCultureIgnoreCase))
            .ToList();
        Groups = cats
            .Select(c => new ShortcutGroup { Title = c, Rows = rows.Where(r => CategoryOf(r.Shortcut) == c).ToList() })
            .Where(g => g.Rows.Count > 0)
            .ToList();
        Raise(nameof(Groups));
        Raise(nameof(IsEmpty));
    }

    private static string CategoryOf(Shortcut s) =>
        s.Kind == ShortcutKind.Keystroke ? "Touches de FL"
        : s.Kind == ShortcutKind.Macro ? "Macros"
        : s.ActionId is { } id && FlActions.Info(id) is { } info ? info.CategoryLabel : "Navigation";

    private ShortcutRow ToRow(Shortcut s)
    {
        var issues = _issues.TryGetValue(s.Id, out var l) ? l : new List<ShortcutIssue>();
        var desc = s.Kind == ShortcutKind.Macro ? "Macro de ta bibliothèque"
            : s.Kind == ShortcutKind.Keystroke
            ? (s.Target is { } t && ConflictTable.Default.FlConflict(t) is { } fl ? "Dans " + fl : "Raccourci de FL Studio")
            : s.ActionId is { } id && Availability(id) is ActionAvailability.Unavailable u ? u.Reason
            : s.ActionId is { } id2 && FlActions.Info(id2) is { } info ? info.Detail()
            : s.UnknownAction is { } unknown ? $"Action inconnue ({DisplayText.Safe(unknown)}) : mets FL Shortcuts à jour" : "";
        return new ShortcutRow
        {
            Shortcut = s,
            Caps = s.Trigger?.Caps ?? new[] { "?" },
            Label = s.Kind == ShortcutKind.Macro && s.MacroRef is { } r && _macros.Doc(r) is { } doc
                ? DisplayText.Safe(doc.Name, MacroValidation.MaxNameLength) : s.Label,
            Description = desc,
            Category = CategoryOf(s),
            Where = s.Context == ShortcutContext.Everywhere ? "" : s.Context.Label(),
            HasWarning = issues.Count > 0,
            WarningText = string.Join(" ", issues.Select(i => i.Message)),
        };
    }

    private void OnUi(Action a)
    {
        if (_ui.HasThreadAccess) a();
        else _ui.TryEnqueue(() => a());
    }

    private void Raise([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    public void Dispose()
    {
        _macroSave?.Stop();
        _macros.SaveNow();
        _hook.Dispose();
        _midi.Dispose();
    }
}
