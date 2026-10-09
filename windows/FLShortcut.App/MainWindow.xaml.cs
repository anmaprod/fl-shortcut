// Fenêtre principale Windows 11 (Mica, Fluent), d'après la simulation validée :
// accueil en 2 étapes (ports, lien FL), liste par rubriques, fiche d'édition, notification « Annuler ».
// Audit 05 : vocabulaire simple, nom des touches en clair, avertissements au moment de l'assignation,
// pause visible. SEC-05 : import et changement de profil confirmés.
using System.ComponentModel;
using FLShortcut.App.Services;
using FLShortcut.Core;
using Microsoft.UI;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.Storage.Pickers;
using Windows.System;
using Windows.UI.Core;

namespace FLShortcut.App;

public sealed partial class MainWindow : Window
{
    private readonly AppController _app;
    private readonly TrayIcon _tray;
    private readonly IntPtr _hwnd;
    private readonly DispatcherQueueTimer _poll;
    private DispatcherQueueTimer? _toastTimer;
    private Shortcut? _deleted;
    private bool _quitting;
    private enum LinkStep { Idle, Waiting, Linked }
    private LinkStep _linkStep = LinkStep.Idle;

    public MainWindow()
    {
        InitializeComponent();
        _hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);

        SystemBackdrop = new MicaBackdrop();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1100, 780));
        AppWindow.Closing += OnClosing;

        foreach (var cap in new[] { "Ctrl", "Maj", "4" }) ExampleCaps.Children.Add(KeyCap(cap));

        _app = new AppController(DispatcherQueue);
        _app.PropertyChanged += OnAppChanged;

        _tray = new TrayIcon(_hwnd, "FL Shortcut") { IsEnabled = () => _app.Enabled };
        _tray.OpenRequested += () => DispatcherQueue.TryEnqueue(ShowFromTray);
        _tray.ToggleRequested += () => DispatcherQueue.TryEnqueue(_app.Toggle);
        _tray.QuitRequested += () => DispatcherQueue.TryEnqueue(Quit);

        _poll = DispatcherQueue.CreateTimer();
        _poll.Interval = TimeSpan.FromSeconds(1);
        _poll.Tick += (_, _) => OnPoll();
        _poll.Start();

        BuildProfileMenu();
        _app.Start();
        ShowScreen();
        if (_app.LoadWarning is { } warning) ShowToast(warning, InfoBarSeverity.Warning);
    }

    // ---------- Fenêtre et zone de notification ----------

    private void OnClosing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (_quitting) return;
        args.Cancel = true;          // la croix cache la fenêtre : FL Shortcut continue dans la zone de notification
        sender.Hide();
    }

    private void ShowFromTray()
    {
        AppWindow.Show();
        Activate();
    }

    private void Quit()
    {
        _quitting = true;
        _poll.Stop();
        _tray.Dispose();
        _app.Dispose();
        Close();
        Application.Current.Exit();
    }

    private void OnAppChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(AppController.Groups):
                BuildGroups();
                break;
            case nameof(AppController.StatusTitle):
            case nameof(AppController.Enabled):
                UpdateStatus();
                break;
            case nameof(AppController.Onboarded):
                ShowScreen();
                break;
        }
    }

    private void OnPoll()
    {
        if (StepPorts.Visibility == Visibility.Visible) UpdatePortsStep();
        if (StepLink.Visibility == Visibility.Visible && _linkStep == LinkStep.Waiting && _app.Linked)
        {
            _linkStep = LinkStep.Linked;
            UpdateLinkStep();
        }
    }

    private void ShowScreen()
    {
        var main = _app.Onboarded;
        MainView.Visibility = main ? Visibility.Visible : Visibility.Collapsed;
        StepPorts.Visibility = main ? Visibility.Collapsed : Visibility.Visible;
        StepLink.Visibility = Visibility.Collapsed;
        if (main) { BuildGroups(); UpdateStatus(); } else UpdatePortsStep();
    }

    // ---------- Accueil ----------

    private void UpdatePortsStep()
    {
        var ok = MidiLink.PortsExist();
        PortsIcon.Glyph = ok ? "" : "";
        PortsIcon.Foreground = ok ? (Brush)Application.Current.Resources["SystemFillColorSuccessBrush"]
                                  : (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];
        PortsText.Text = ok
            ? "Prêts : « FL Shortcut » et « FL Shortcut Retour »."
            : "FL Shortcut parle à FL Studio par deux ports MIDI virtuels. Ouvre loopMIDI et crée deux ports nommés exactement « FL Shortcut » et « FL Shortcut Retour ». FL Shortcut les détecte tout seul.";
        LoopMidiLink.Visibility = ok ? Visibility.Collapsed : Visibility.Visible;
        PortsContinue.Content = ok ? "Continuer" : "En attente des ports…";
        PortsContinue.IsEnabled = ok;
    }

    private void OnPortsContinue(object sender, RoutedEventArgs e)
    {
        StepPorts.Visibility = Visibility.Collapsed;
        StepLink.Visibility = Visibility.Visible;
        _linkStep = _app.Linked ? LinkStep.Linked : LinkStep.Idle;
        UpdateLinkStep();
    }

    private void UpdateLinkStep(string? error = null)
    {
        var installed = _linkStep != LinkStep.Idle;
        var linked = _linkStep == LinkStep.Linked;
        var steps = new (string Text, bool Done)[]
        {
            ("Installer le lien dans FL Studio (un clic, ci-dessous).", installed),
            ("Dans FL Studio : Options › MIDI Settings. Input « FL Shortcut » : Enable, Controller type « FL Shortcut ».", linked),
            ("Output « FL Shortcut Retour » : même numéro de port que l'entrée. FL Shortcut le détecte tout seul.", linked),
        };
        LinkSteps.Children.Clear();
        for (var i = 0; i < steps.Length; i++) LinkSteps.Children.Add(StepCard(i + 1, steps[i].Text, steps[i].Done));

        if (error is not null)
        {
            LinkInfo.Severity = InfoBarSeverity.Error;
            LinkInfo.Title = "Installation impossible";
            LinkInfo.Message = error;
            LinkChooseFolder.Visibility = Visibility.Visible;
        }
        else
        {
            LinkInfo.Severity = linked ? InfoBarSeverity.Success : installed ? InfoBarSeverity.Warning : InfoBarSeverity.Informational;
            LinkInfo.Title = linked ? "FL Studio est relié" : installed ? "En attente de FL Studio…" : "FL Studio pas encore relié";
            LinkInfo.Message = linked ? "Clique sur « Tester » : le Mixer s'ouvre dans FL Studio." : installed ? "Fais les étapes 2 et 3 dans FL Studio." : "";
        }
        LinkPrimary.Content = installed ? "Terminer" : "Installer le lien";
        LinkPrimary.IsEnabled = !installed || linked;
        LinkTest.Visibility = linked ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnLinkPrimary(object sender, RoutedEventArgs e)
    {
        if (_linkStep == LinkStep.Idle) Install(null);
        else if (_linkStep == LinkStep.Linked)
        {
            _app.CompleteOnboarding();
            ShowScreen();
        }
    }

    private void Install(string? folder)
    {
        var error = _app.InstallScript(folder);
        if (error is null)
        {
            _linkStep = _app.Linked ? LinkStep.Linked : LinkStep.Waiting;
            LinkChooseFolder.Visibility = Visibility.Collapsed;
        }
        UpdateLinkStep(error);
    }

    private async void OnChooseFolder(object sender, RoutedEventArgs e)
    {
        var picker = new FolderPicker();
        picker.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, _hwnd);
        var folder = await picker.PickSingleFolderAsync();
        if (folder is not null) Install(folder.Path);
    }

    private void OnTest(object sender, RoutedEventArgs e) =>
        ShowToast(_app.TestLink() ? "Le Mixer vient de s'ouvrir dans FL Studio." : "FL Studio n'a pas répondu. Vérifie MIDI Settings.",
            _app.Linked ? InfoBarSeverity.Success : InfoBarSeverity.Warning);

    private void OnRepair(object sender, RoutedEventArgs e)
    {
        MainView.Visibility = Visibility.Collapsed;
        if (!_app.PortsPresent) { StepPorts.Visibility = Visibility.Visible; UpdatePortsStep(); return; }
        StepLink.Visibility = Visibility.Visible;
        _linkStep = LinkStep.Idle;
        UpdateLinkStep();
    }

    // ---------- Liste ----------

    private void UpdateStatus()
    {
        EnabledSwitch.Toggled -= OnEnabledToggled;
        EnabledSwitch.IsOn = _app.Enabled;
        EnabledSwitch.Toggled += OnEnabledToggled;

        StatusBar.Title = _app.StatusTitle;
        StatusBar.Message = _app.StatusText;
        StatusBar.Severity = _app.Status switch
        {
            StatusKind.Linked => InfoBarSeverity.Success,
            StatusKind.Paused or StatusKind.FlClosed => InfoBarSeverity.Informational,
            StatusKind.Elevated or StatusKind.Tampered => InfoBarSeverity.Error,
            _ => InfoBarSeverity.Warning,
        };
        StatusAction.Visibility = _app.Status is StatusKind.Inactive or StatusKind.NoKey or StatusKind.Tampered or StatusKind.Incompatible
            ? Visibility.Visible : Visibility.Collapsed;
        _tray.SetTooltip(_app.Enabled ? $"FL Shortcut — {_app.StatusTitle}" : "FL Shortcut — en pause");
    }

    private void OnEnabledToggled(object sender, RoutedEventArgs e) => _app.SetEnabled(EnabledSwitch.IsOn);

    private void OnSearchChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args) => _app.Query = sender.Text;

    private void BuildGroups()
    {
        GroupsPanel.Children.Clear();
        if (_app.IsEmpty)
        {
            var empty = new StackPanel { Spacing = 6, Padding = new Thickness(0, 60, 0, 0), HorizontalAlignment = HorizontalAlignment.Center };
            empty.Children.Add(new TextBlock { Text = _app.Shortcuts.Count > 0 ? "Aucun raccourci trouvé" : "Aucun raccourci", FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, HorizontalAlignment = HorizontalAlignment.Center });
            empty.Children.Add(new TextBlock { Text = _app.Shortcuts.Count > 0 ? "Essaie un autre mot." : "Clique sur « Nouveau raccourci » pour commencer.", Foreground = Secondary(), HorizontalAlignment = HorizontalAlignment.Center });
            GroupsPanel.Children.Add(empty);
            return;
        }
        foreach (var group in _app.Groups)
        {
            var panel = new StackPanel { Spacing = 3 };
            panel.Children.Add(new TextBlock { Text = group.Title, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Margin = new Thickness(2, 0, 0, 5) });
            foreach (var row in group.Rows) panel.Children.Add(RowButton(row));
            GroupsPanel.Children.Add(panel);
        }
    }

    private Button RowButton(ShortcutRow row)
    {
        var grid = new Grid { ColumnSpacing = 16 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(170) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var caps = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4, VerticalAlignment = VerticalAlignment.Center };
        foreach (var c in row.Caps) caps.Children.Add(KeyCap(c));
        grid.Children.Add(caps);

        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Spacing = 1 };
        text.Children.Add(new TextBlock { Text = row.Label });
        text.Children.Add(new TextBlock { Text = row.Description, FontSize = 12, Foreground = Secondary(), TextTrimming = TextTrimming.CharacterEllipsis });
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);

        if (!string.IsNullOrEmpty(row.Where))
        {
            var tag = new Border
            {
                Padding = new Thickness(8, 2, 8, 2), CornerRadius = new CornerRadius(4), VerticalAlignment = VerticalAlignment.Center,
                Background = (Brush)Application.Current.Resources["ControlFillColorDefaultBrush"],
                BorderBrush = (Brush)Application.Current.Resources["ControlStrokeColorDefaultBrush"], BorderThickness = new Thickness(1),
                Child = new TextBlock { Text = row.Where, FontSize = 12, Foreground = Secondary() },
            };
            Grid.SetColumn(tag, 2);
            grid.Children.Add(tag);
        }
        if (row.HasWarning)
        {
            var warn = new FontIcon { Glyph = "", FontSize = 16, VerticalAlignment = VerticalAlignment.Center,
                Foreground = (Brush)Application.Current.Resources["SystemFillColorCautionBrush"] };
            ToolTipService.SetToolTip(warn, row.WarningText);
            Grid.SetColumn(warn, 3);
            grid.Children.Add(warn);
        }
        var chevron = new FontIcon { Glyph = "", FontSize = 12, VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(chevron, 4);
        grid.Children.Add(chevron);

        var button = new Button { Style = (Style)Application.Current.Resources["RowButton"], Content = grid, Opacity = row.Opacity };
        AutomationProperties.SetName(button, $"{string.Join(" ", row.Caps)} : {row.Label}");
        button.Click += async (_, _) => await EditAsync(row.Shortcut);
        return button;
    }

    private async void OnNewShortcut(object sender, RoutedEventArgs e) => await EditAsync(null);

    // ---------- Profils, import, export ----------

    private void BuildProfileMenu()
    {
        ProfileButton.Content = $"Profil : {_app.CurrentPreset.Label()}";
        ProfileMenu.Items.Clear();
        foreach (var preset in Enum.GetValues<ProfilePreset>())
        {
            var item = new MenuFlyoutItem { Text = preset.Label() };
            ToolTipService.SetToolTip(item, preset.Summary());
            item.Click += async (_, _) => await LoadPresetAsync(preset);
            ProfileMenu.Items.Add(item);
        }
        ProfileMenu.Items.Add(new MenuFlyoutSeparator());
        var import = new MenuFlyoutItem { Text = "Importer un profil…" };
        import.Click += async (_, _) => await ImportAsync();
        ProfileMenu.Items.Add(import);
        var export = new MenuFlyoutItem { Text = "Exporter mon profil…" };
        export.Click += async (_, _) => await ExportAsync();
        ProfileMenu.Items.Add(export);
    }

    private async Task LoadPresetAsync(ProfilePreset preset)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = Root.XamlRoot,
            Title = $"Charger le profil « {preset.Label()} » ?",
            Content = new TextBlock { Text = preset.Summary() + "\n\nTes raccourcis actuels seront remplacés.", TextWrapping = TextWrapping.Wrap },
            PrimaryButtonText = "Charger",
            CloseButtonText = "Annuler",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        _app.LoadPreset(preset);
        BuildProfileMenu();
        ShowToast($"Profil « {preset.Label()} » chargé", InfoBarSeverity.Success);
    }

    private async Task ImportAsync()
    {
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add(".json");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, _hwnd);
        var file = await picker.PickSingleFileAsync();
        if (file is null) return;
        ImportPreview preview;
        try
        {
            var text = await Windows.Storage.FileIO.ReadTextAsync(file);
            preview = _app.PrepareImport(text);
        }
        catch (Exception ex)
        {
            ShowToast("Profil illisible : " + ex.Message, InfoBarSeverity.Error);
            return;
        }
        var summary = $"{preview.Shortcuts.Count} raccourci(s), dont {preview.Disabled} désactivé(s).";
        if (preview.Refused.Count > 0) summary += "\n\nCibles dangereuses refusées :\n• " + string.Join("\n• ", preview.Refused);
        var dialog = new ContentDialog
        {
            XamlRoot = Root.XamlRoot,
            Title = "Importer ce profil ?",
            Content = new TextBlock { Text = summary, TextWrapping = TextWrapping.Wrap },
            PrimaryButtonText = "Importer",
            CloseButtonText = "Annuler",
            DefaultButton = ContentDialogButton.Close,
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary) return;
        _app.ApplyImport(preview);
        ShowToast("Profil importé", InfoBarSeverity.Success);
    }

    private async Task ExportAsync()
    {
        var picker = new FileSavePicker { SuggestedFileName = "FL Shortcut - profil" };
        picker.FileTypeChoices.Add("Profil FL Shortcut", new List<string> { ".json" });
        WinRT.Interop.InitializeWithWindow.Initialize(picker, _hwnd);
        var file = await picker.PickSaveFileAsync();
        if (file is null) return;
        await Windows.Storage.FileIO.WriteTextAsync(file, _app.ExportJson());
        ShowToast("Profil exporté", InfoBarSeverity.Success);
    }

    // ---------- Fiche d'édition ----------

    private async Task EditAsync(Shortcut? existing)
    {
        var draft = existing ?? new Shortcut { ActionId = null };
        var category = draft.ActionId is { } a0 && FlActions.Info(a0) is { } i0 ? i0.Category : ActionCategory.Composition;
        string? recordingFor = null;              // "trigger" ou "target"
        var query = "";

        var dialog = new ContentDialog
        {
            XamlRoot = Root.XamlRoot,
            Title = existing is null ? "Nouveau raccourci" : "Modifier le raccourci",
            PrimaryButtonText = "Valider",
            CloseButtonText = "Annuler",
            SecondaryButtonText = existing is null ? "" : "Supprimer",
            DefaultButton = ContentDialogButton.Primary,
        };

        var body = new StackPanel { Spacing = 12, MinWidth = 480 };
        var triggerButton = CaptureButton();
        var warning = new InfoBar { IsClosable = false, IsOpen = false };
        var kinds = new RadioButtons { MaxColumns = 2, Header = "Ce que fait le raccourci" };
        kinds.Items.Add("Action dans FL");
        kinds.Items.Add("Touche de FL");
        var actionPanel = new StackPanel { Spacing = 8 };
        var search = new AutoSuggestBox { PlaceholderText = "Rechercher une action", QueryIcon = new SymbolIcon(Symbol.Find) };
        var cats = new RadioButtons { MaxColumns = 4 };
        foreach (var c in Enum.GetValues<ActionCategory>()) cats.Items.Add(new FlActionInfo(0, "", "", c, "").CategoryLabel);
        var actions = new ListView { SelectionMode = ListViewSelectionMode.Single, MaxHeight = 220 };
        var wheres = new RadioButtons { MaxColumns = 4, Header = "Où ?" };
        foreach (var w in Enum.GetValues<ShortcutContext>()) wheres.Items.Add(w.Label());
        var testButton = new Button { Content = "Tester" };
        var searchRow = new Grid { ColumnSpacing = 8 };
        searchRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        searchRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        searchRow.Children.Add(search);
        Grid.SetColumn(testButton, 1);
        searchRow.Children.Add(testButton);
        actionPanel.Children.Add(searchRow);
        actionPanel.Children.Add(cats);
        actionPanel.Children.Add(actions);
        actionPanel.Children.Add(wheres);

        var keyPanel = new StackPanel { Spacing = 6 };
        keyPanel.Children.Add(new TextBlock { Text = "Pour déplacer un raccourci de FL Studio sur une touche plus pratique.", FontSize = 13, Foreground = Secondary(), TextWrapping = TextWrapping.Wrap });
        var targetButton = CaptureButton();
        keyPanel.Children.Add(targetButton);

        body.Children.Add(new TextBlock { Text = "Ton raccourci" });
        body.Children.Add(triggerButton);
        body.Children.Add(warning);
        body.Children.Add(kinds);
        body.Children.Add(actionPanel);
        body.Children.Add(keyPanel);
        dialog.Content = new ScrollViewer { Content = body, MaxHeight = 600 };

        void Refresh()
        {
            SetCaptureContent(triggerButton, draft.Trigger, recordingFor == "trigger", "Clique ici, puis appuie sur tes touches");
            SetCaptureContent(targetButton, draft.Target, recordingFor == "target", "Clique ici, puis tape le raccourci de FL");
            var isAction = draft.Kind == ShortcutKind.FlAction;
            kinds.SelectedIndex = isAction ? 0 : 1;
            actionPanel.Visibility = isAction ? Visibility.Visible : Visibility.Collapsed;
            keyPanel.Visibility = isAction ? Visibility.Collapsed : Visibility.Visible;
            wheres.SelectedIndex = (int)draft.Context;
            cats.SelectedIndex = query.Length == 0 ? (int)category : -1;

            actions.Items.Clear();
            var list = FlActions.All.Where(x => query.Length > 0
                ? x.Label.Contains(query, StringComparison.CurrentCultureIgnoreCase)
                : x.Category == category);
            foreach (var info in list)
            {
                var availability = _app.Availability(info.Id);
                var item = new ListViewItem { Tag = info.Id, IsEnabled = availability.IsUsable };
                var stack = new StackPanel { Padding = new Thickness(0, 4, 0, 4) };
                stack.Children.Add(new TextBlock { Text = info.Label });
                if (availability is ActionAvailability.Unavailable u)
                    stack.Children.Add(new TextBlock { Text = u.Reason, FontSize = 12, Foreground = Secondary() });
                item.Content = stack;
                actions.Items.Add(item);
                if (draft.ActionId == info.Id) actions.SelectedItem = item;
            }
            testButton.IsEnabled = draft.ActionId is not null && _app.Linked;

            var issues = draft.Trigger is null && draft.Target is null ? new List<ShortcutIssue>() : _app.IssuesFor(draft).ToList();
            var blocking = issues.Where(x => x.IsBlocking && x is not ShortcutIssue.NoTrigger and not ShortcutIssue.NoTarget).ToList();
            var shown = blocking.Count > 0 ? blocking : issues.Where(x => !x.IsBlocking).ToList();
            warning.IsOpen = shown.Count > 0 && recordingFor is null;
            warning.Severity = blocking.Count > 0 ? InfoBarSeverity.Error : InfoBarSeverity.Warning;
            warning.Message = string.Join(" ", shown.Select(x => x.Message));

            dialog.IsPrimaryButtonEnabled = recordingFor is null && issues.All(x => !x.IsBlocking)
                && draft.Trigger is not null && (isAction ? draft.ActionId is not null : draft.Target is not null);
        }

        void StartRecording(string which)
        {
            recordingFor = which;
            _app.SetRecording(true);
            Refresh();
        }

        void StopRecording()
        {
            recordingFor = null;
            _app.SetRecording(false);
            Refresh();
        }

        void OnCaptureKey(object s, KeyRoutedEventArgs e)
        {
            if (recordingFor is null) return;
            e.Handled = true;
            var vk = (ushort)e.Key;
            if (Vk.IsModifier(vk)) return;
            var combo = new KeyCombo(vk, IsDown(VirtualKey.Control), IsDown(VirtualKey.Menu), IsDown(VirtualKey.Shift),
                IsDown(VirtualKey.LeftWindows) || IsDown(VirtualKey.RightWindows));
            if (e.Key == VirtualKey.Escape && !combo.HasModifiers) { StopRecording(); return; }
            draft = recordingFor == "trigger" ? draft with { Trigger = combo } : draft with { Target = combo };
            StopRecording();
        }

        triggerButton.Click += (_, _) => StartRecording("trigger");
        targetButton.Click += (_, _) => StartRecording("target");
        triggerButton.PreviewKeyDown += OnCaptureKey;
        targetButton.PreviewKeyDown += OnCaptureKey;
        triggerButton.LostFocus += (_, _) => { if (recordingFor == "trigger") StopRecording(); };
        targetButton.LostFocus += (_, _) => { if (recordingFor == "target") StopRecording(); };
        kinds.SelectionChanged += (_, _) =>
        {
            var kind = kinds.SelectedIndex == 1 ? ShortcutKind.Keystroke : ShortcutKind.FlAction;
            if (kind != draft.Kind) { draft = draft with { Kind = kind }; Refresh(); }
        };
        cats.SelectionChanged += (_, _) =>
        {
            if (cats.SelectedIndex < 0 || (ActionCategory)cats.SelectedIndex == category && query.Length == 0) return;
            category = (ActionCategory)cats.SelectedIndex;
            query = "";
            search.Text = "";
            Refresh();
        };
        search.TextChanged += (sender, _) =>
        {
            if (sender.Text == query) return;
            query = sender.Text.Trim();
            Refresh();
        };
        actions.SelectionChanged += (_, _) =>
        {
            if (actions.SelectedItem is ListViewItem { Tag: int id } && draft.ActionId != id)
            {
                draft = draft with { ActionId = id, UnknownAction = null };
                Refresh();
            }
        };
        wheres.SelectionChanged += (_, _) =>
        {
            if (wheres.SelectedIndex >= 0 && (ShortcutContext)wheres.SelectedIndex != draft.Context)
            {
                draft = draft with { Context = (ShortcutContext)wheres.SelectedIndex };
                Refresh();
            }
        };
        testButton.Click += (_, _) =>
        {
            if (draft.ActionId is not { } id) return;
            var sent = _app.TestAction(id);
            ShowToast(sent ? $"Test : « {FlActions.Info(id)?.Label} » envoyé à FL Studio" : "FL Studio n'a pas répondu.",
                sent ? InfoBarSeverity.Success : InfoBarSeverity.Warning);
        };

        Refresh();
        var result = await dialog.ShowAsync();
        _app.SetRecording(false);

        if (result == ContentDialogResult.Primary)
        {
            var final = draft.Kind == ShortcutKind.FlAction ? draft with { Target = null } : draft with { ActionId = null };
            _app.Upsert(final with { Enabled = true });
            ShowToast(existing is null ? "Raccourci ajouté" : "Raccourci modifié", InfoBarSeverity.Success);
        }
        else if (result == ContentDialogResult.Secondary && existing is not null)
        {
            _deleted = _app.Delete(existing.Id);
            ShowToast("Raccourci supprimé", InfoBarSeverity.Informational, undo: true);
        }
    }

    private static bool IsDown(VirtualKey key) =>
        InputKeyboardSource.GetKeyStateForCurrentThread(key).HasFlag(CoreVirtualKeyStates.Down);

    private Button CaptureButton() => new()
    {
        HorizontalAlignment = HorizontalAlignment.Stretch,
        HorizontalContentAlignment = HorizontalAlignment.Center,
        MinHeight = 60,
        IsTabStop = true,
    };

    private void SetCaptureContent(Button button, KeyCombo? combo, bool recording, string prompt)
    {
        if (recording || combo is null)
        {
            button.Content = new TextBlock { Text = recording ? "Appuie sur tes touches… (Échap pour annuler)" : prompt, Foreground = recording ? (Brush)Application.Current.Resources["AccentTextFillColorPrimaryBrush"] : Secondary() };
            AutomationProperties.SetName(button, recording ? "Enregistrement du raccourci en cours" : prompt);
            if (recording) button.Focus(FocusState.Programmatic);
            return;
        }
        var caps = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        foreach (var c in combo.Value.Caps) caps.Children.Add(KeyCap(c, large: true));
        button.Content = caps;
        AutomationProperties.SetName(button, "Raccourci : " + combo.Value);
    }

    // ---------- Éléments visuels ----------

    private static Border KeyCap(string text, bool large = false) => new()
    {
        Style = (Style)Application.Current.Resources["KeyCapBorder"],
        Height = large ? 34 : 26,
        MinWidth = large ? 34 : 26,
        Child = new TextBlock
        {
            Text = text,
            FontSize = large ? 15 : 12,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        },
    };

    private static Border StepCard(int number, string text, bool done)
    {
        var success = (Brush)Application.Current.Resources["SystemFillColorSuccessBrush"];
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        row.Children.Add(new Border
        {
            Width = 22, Height = 22, CornerRadius = new CornerRadius(11), VerticalAlignment = VerticalAlignment.Top,
            Background = done ? success : null,
            BorderBrush = done ? success : (Brush)Application.Current.Resources["ControlStrongStrokeColorDefaultBrush"],
            BorderThickness = new Thickness(1),
            Child = new TextBlock { Text = done ? "✓" : number.ToString(), FontSize = 12, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center },
        });
        row.Children.Add(new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, MaxWidth = 240, FontSize = 13 });
        return new Border
        {
            Padding = new Thickness(14, 10, 14, 10), CornerRadius = new CornerRadius(6), BorderThickness = new Thickness(1),
            Background = (Brush)Application.Current.Resources["CardBackgroundFillColorDefaultBrush"],
            BorderBrush = (Brush)Application.Current.Resources["CardStrokeColorDefaultBrush"],
            Child = row,
        };
    }

    private static Brush Secondary() => (Brush)Application.Current.Resources["TextFillColorSecondaryBrush"];

    private void ShowToast(string message, InfoBarSeverity severity, bool undo = false)
    {
        Toast.Message = message;
        Toast.Severity = severity;
        if (undo)
        {
            var b = new Button { Content = "Annuler" };
            b.Click += (_, _) =>
            {
                if (_deleted is { } d) _app.Upsert(d);
                _deleted = null;
                Toast.IsOpen = false;
            };
            Toast.ActionButton = b;
        }
        else Toast.ActionButton = null;
        Toast.IsOpen = true;

        _toastTimer?.Stop();
        _toastTimer = DispatcherQueue.CreateTimer();
        _toastTimer.Interval = TimeSpan.FromSeconds(3.5);
        _toastTimer.IsRepeating = false;
        _toastTimer.Tick += (_, _) => { Toast.IsOpen = false; _deleted = null; };
        _toastTimer.Start();
    }
}
