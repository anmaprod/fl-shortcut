// Fenêtre principale Windows 11 (Mica, Fluent 2), d'après la simulation validée :
// accueil en 2 étapes (ports, lien FL), volet de rubriques à gauche comme Réglages, cartes, fiche d'édition,
// notification acrylique « Annuler ». Animations : voir Motion.cs (désactivées si Windows les coupe).
// Audit 05 : vocabulaire simple, nom des touches en clair, avertissements au moment de l'assignation,
// pause visible. SEC-05 : import et changement de profil confirmés.
using System.ComponentModel;
using FLShortcut.App.Services;
using FLShortcut.Core;
using Microsoft.UI;
using Microsoft.UI.Input;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Composition.SystemBackdrops;
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
    // Nom complet : Windows.System (importé pour VirtualKey) contient aussi un DispatcherQueueTimer (CS0104).
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer _poll;
    private Microsoft.UI.Dispatching.DispatcherQueueTimer? _toastTimer;
    private Shortcut? _deleted;
    private bool _quitting;
    private enum LinkStep { Idle, Waiting, Linked }
    private LinkStep _linkStep = LinkStep.Idle;
    private string _navFilter = "";                       // "" = toutes les rubriques
    private HashSet<Guid> _shownRows = new();             // pour n'animer que les lignes nouvelles
    private bool _animateNextBuild = true;
    private StatusKind? _shownStatus;
    private bool? _shownPortsOk;
    private bool _toastLeaving;

    public MainWindow() : this(photos: false) { }

    /// `photos` : mode photos de la CI : ni hook clavier, ni port MIDI, ni question de validation.
    internal MainWindow(bool photos)
    {
        InitializeComponent();
        _hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);

        // Windows 11 : Mica. Windows 10 : acrylique du bureau. Sinon fond uni (sans fond, la fenêtre serait noire).
        if (MicaController.IsSupported())
            SystemBackdrop = new MicaBackdrop { Kind = MicaKind.Base };
        else if (DesktopAcrylicController.IsSupported())
            SystemBackdrop = new DesktopAcrylicBackdrop();
        else
            Root.Background = Res<Brush>("ApplicationPageBackgroundThemeBrush");
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        if (AppWindowTitleBar.IsCustomizationSupported())
            AppWindow.TitleBar.PreferredHeightOption = TitleBarHeightOption.Tall;   // boutons de fenêtre alignés sur la barre de 48 px
        AppWindow.Resize(new Windows.Graphics.SizeInt32(1180, 800));
        Toast.Shadow = new ThemeShadow();
        Toast.Translation = new System.Numerics.Vector3(0, 0, 32);
        AppWindow.Closing += OnClosing;

        foreach (var cap in new[] { "Ctrl", "Maj", "4" }) ExampleCaps.Children.Add(KeyCap(cap));

        _app = new AppController(DispatcherQueue);
        _app.PropertyChanged += OnAppChanged;

        _tray = new TrayIcon(_hwnd, "FL Shortcuts") { IsEnabled = () => _app.Enabled };
        _tray.OpenRequested += () => DispatcherQueue.TryEnqueue(ShowFromTray);
        _tray.ToggleRequested += () => DispatcherQueue.TryEnqueue(_app.Toggle);
        _tray.QuitRequested += () => DispatcherQueue.TryEnqueue(Quit);
        _tray.HasPendingCopy = () => _app.Approval.Pending.Count > 0;
        _tray.OrganizeRequested += () => DispatcherQueue.TryEnqueue(() => OrganizerWindow.Show(_app));
        _tray.ApproveRequested += () => DispatcherQueue.TryEnqueue(() =>
        {
            ShowFromTray(ask: false);
            CopyApprovalPrompt.Ask(Root.XamlRoot, _app, force: true);
        });

        _poll = DispatcherQueue.CreateTimer();
        _poll.Interval = TimeSpan.FromSeconds(1);
        _poll.Tick += (_, _) => OnPoll();
        _poll.Start();

        BuildProfileMenu();
        if (_app.Light) NavLink.Visibility = Visibility.Collapsed;   // mode léger : rien à relier
        if (!photos) _app.Start();
        ShowScreen();
        if (_app.LoadWarning is { } warning) ShowToast(warning, InfoBarSeverity.Warning);
        // Une version organisée attend (Organiser fermé) : la question à la réouverture de FL Shortcuts.
        if (!photos) Root.Loaded += (_, _) => CopyApprovalPrompt.Ask(Root.XamlRoot, _app, force: false);
    }

    // ---------- Fenêtre et zone de notification ----------

    private void OnClosing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (_quitting) return;
        args.Cancel = true;          // la croix cache la fenêtre : FL Shortcuts continue dans la zone de notification
        sender.Hide();
    }

    private void ShowFromTray() => ShowFromTray(ask: true);

    private void ShowFromTray(bool ask)
    {
        AppWindow.Show();
        Activate();
        if (ask) CopyApprovalPrompt.Ask(Root.XamlRoot, _app, force: false);
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
        if (main)
        {
            _animateNextBuild = true;
            BuildGroups();
            UpdateStatus();
            Motion.Enter(MainContent, fromY: 24);
        }
        else
        {
            UpdatePortsStep();
            UpdateBackLinks();
            Motion.Enter(StepPortsContent, fromY: 24);
        }
    }

    private void OnBackToMain(object sender, RoutedEventArgs e) => ShowScreen();

    /// « Retour aux raccourcis » seulement quand l'accueil a déjà été fait (réparation).
    private void UpdateBackLinks()
    {
        var v = _app.Onboarded ? Visibility.Visible : Visibility.Collapsed;
        PortsBack.Visibility = v;
        LinkBack.Visibility = v;
    }

    // ---------- Accueil ----------

    private void UpdatePortsStep()
    {
        var ok = MidiLink.PortsExist();
        PortsIcon.Glyph = ok ? "\uE73E" : "\uE895";
        var tint = ok ? Res<Brush>("SystemFillColorSuccessBrush") : Res<Brush>("AccentTextFillColorPrimaryBrush");
        PortsIcon.Foreground = tint;
        PortsHalo.Fill = tint;
        if (_shownPortsOk is { } before && before != ok) Motion.Pop(PortsIcon);
        _shownPortsOk = ok;
        PortsText.Text = ok
            ? "Prêts : « FL Shortcuts » et « FL Shortcuts Retour »."
            : "FL Shortcuts parle à FL Studio par deux ports MIDI virtuels. Ouvre loopMIDI et crée deux ports nommés exactement « FL Shortcuts » et « FL Shortcuts Retour ». FL Shortcuts les détecte tout seul.";
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
        UpdateBackLinks();
        Motion.Enter(StepLinkContent, fromX: 40, fromY: 0);      // page suivante : glisse depuis la droite
    }

    private void UpdateLinkStep(string? error = null)
    {
        var installed = _linkStep != LinkStep.Idle;
        var linked = _linkStep == LinkStep.Linked;
        var steps = new (string Text, bool Done)[]
        {
            ("Installer le lien dans FL Studio (un clic, ci-dessous).", installed),
            ("Dans FL Studio : Options › MIDI Settings. Input « FL Shortcuts » : Enable, Controller type « FL Shortcuts ».", linked),
            ("Output « FL Shortcuts Retour » : même numéro de port que l'entrée. FL Shortcuts le détecte tout seul.", linked),
        };
        LinkSteps.Children.Clear();
        for (var i = 0; i < steps.Length; i++) LinkSteps.Children.Add(StepCard(i + 1, steps[i].Text, steps[i].Done));
        if (linked) Motion.Pop(LinkInfo, from: 0.96);

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

    private void OnRepair(object sender, RoutedEventArgs e) => Repair();

    private void Repair()
    {
        MainView.Visibility = Visibility.Collapsed;
        UpdateBackLinks();
        if (!_app.PortsPresent)
        {
            StepPorts.Visibility = Visibility.Visible;
            UpdatePortsStep();
            Motion.Enter(StepPortsContent, fromY: 24);
            return;
        }
        StepLink.Visibility = Visibility.Visible;
        _linkStep = LinkStep.Idle;
        UpdateLinkStep();
        Motion.Enter(StepLinkContent, fromY: 24);
    }

    // ---------- Volet de rubriques ----------

    private void OnNavChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItemContainer?.Tag is not string tag || tag.StartsWith('#') || tag == _navFilter) return;
        _navFilter = tag;
        PageTitle.Text = tag.Length == 0 ? "Raccourcis" : tag;
        _animateNextBuild = true;
        BuildGroups();
        Motion.Enter(PageTitle, fromY: 8, durationMs: Motion.Normal);
    }

    private void OnNavInvoked(NavigationView sender, NavigationViewItemInvokedEventArgs args)
    {
        if (args.InvokedItemContainer?.Tag is "#link") Repair();
        else if (args.InvokedItemContainer?.Tag is "#organize") OrganizerWindow.Show(_app);
    }

    // ---------- Liste ----------

    private void UpdateStatus()
    {
        EnabledSwitch.Toggled -= OnEnabledToggled;
        EnabledSwitch.IsOn = _app.Enabled;
        EnabledSwitch.Toggled += OnEnabledToggled;

        StatusTitle.Text = _app.StatusTitle;
        StatusMessage.Text = _app.StatusText;
        var (glyph, brushKey) = _app.Status switch
        {
            StatusKind.Linked => ("\uE73E", "SystemFillColorSuccessBrush"),
            StatusKind.Paused => ("\uE769", "SystemFillColorCautionBrush"),
            StatusKind.FlClosed => ("\uE7E8", "SystemFillColorNeutralBrush"),
            StatusKind.Elevated or StatusKind.Tampered => ("\uE783", "SystemFillColorCriticalBrush"),
            _ => ("\uE7BA", "SystemFillColorCautionBrush"),
        };
        var tint = Res<Brush>(brushKey);
        StatusGlyph.Glyph = glyph;
        StatusGlyph.Foreground = tint;
        StatusHalo.Fill = tint;
        if (_shownStatus is { } before && before != _app.Status) Motion.Pop(StatusBadge);
        _shownStatus = _app.Status;
        AutomationProperties.SetName(StatusCard, $"{_app.StatusTitle}. {_app.StatusText}");
        StatusAction.Visibility = _app.Status is StatusKind.Inactive or StatusKind.NoKey or StatusKind.Tampered or StatusKind.Incompatible
            ? Visibility.Visible : Visibility.Collapsed;
        PausePill.Visibility = _app.Enabled ? Visibility.Collapsed : Visibility.Visible;
        _tray.SetTooltip(_app.Enabled ? $"FL Shortcuts — {_app.StatusTitle}" : "FL Shortcuts — en pause");
    }

    private void OnEnabledToggled(object sender, RoutedEventArgs e) => _app.SetEnabled(EnabledSwitch.IsOn);

    private void OnSearchChanged(AutoSuggestBox sender, AutoSuggestBoxTextChangedEventArgs args) => _app.Query = sender.Text;

    private void BuildGroups()
    {
        var animateAll = _animateNextBuild;
        _animateNextBuild = false;
        UpdateNavBadges();

        GroupsPanel.Children.Clear();
        var groups = _app.Groups.Where(g => _navFilter.Length == 0 || g.Title == _navFilter).ToList();
        if (groups.Count == 0)
        {
            var searching = _app.Query.Trim().Length > 0;
            var empty = new StackPanel { Spacing = 8, Padding = new Thickness(0, 64, 0, 0), HorizontalAlignment = HorizontalAlignment.Center };
            empty.Children.Add(new FontIcon { Glyph = searching ? "\uE721" : "\uE765", FontSize = 40, Foreground = Secondary() });
            empty.Children.Add(new TextBlock { Text = searching ? "Aucun raccourci trouvé" : "Aucun raccourci ici", Style = Res<Style>("SubtitleTextBlockStyle"), HorizontalAlignment = HorizontalAlignment.Center });
            empty.Children.Add(new TextBlock { Text = searching ? "Essaie un autre mot." : "Clique sur « Nouveau raccourci » pour en créer un.", Foreground = Secondary(), HorizontalAlignment = HorizontalAlignment.Center });
            GroupsPanel.Children.Add(empty);
            if (animateAll) Motion.Enter(empty, fromY: 12);
            _shownRows = new HashSet<Guid>(_app.Shortcuts.Select(x => x.Id));
            return;
        }

        var index = 0;
        foreach (var group in groups)
        {
            var panel = new StackPanel { Spacing = 2 };
            var header = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(2, 0, 0, 6) };
            header.Children.Add(new TextBlock { Text = group.Title, Style = Res<Style>("BodyStrongTextBlockStyle") });
            header.Children.Add(new TextBlock { Text = group.Rows.Count.ToString(), Foreground = Secondary(), VerticalAlignment = VerticalAlignment.Center });
            panel.Children.Add(header);
            foreach (var row in group.Rows)
            {
                var button = RowButton(row);
                panel.Children.Add(button);
                if (!animateAll && !_shownRows.Contains(row.Shortcut.Id)) Motion.Enter(button, fromY: 10);   // ligne ajoutée
            }
            GroupsPanel.Children.Add(panel);
            if (animateAll) Motion.Enter(panel, fromY: 16, delayMs: Math.Min(index, 6) * 40);           // cascade
            index++;
        }
        _shownRows = new HashSet<Guid>(_app.Shortcuts.Select(x => x.Id));
    }

    /// Pastille « attention » sur une rubrique du volet quand un de ses raccourcis a un problème.
    private void UpdateNavBadges()
    {
        var withWarnings = _app.Groups.Where(g => g.Rows.Any(r => r.HasWarning)).Select(g => g.Title).ToHashSet();
        foreach (var item in new[] { NavComposition, NavRecording, NavMix, NavNavigation, NavKeys })
        {
            var warn = item.Tag is string t && withWarnings.Contains(t);
            if (!warn) { item.InfoBadge = null; continue; }
            if (item.InfoBadge is not null) continue;
            var badge = new InfoBadge();
            if (TryRes<Style>("CautionIconInfoBadgeStyle") is { } style) badge.Style = style;
            item.InfoBadge = badge;
        }
    }

    private static string CategoryGlyph(string category) => category switch
    {
        "Composition" => "\uE8D6",
        "Enregistrement" => "\uE7C8",
        "Mix" => "\uE767",
        "Navigation" => "\uE8A9",
        _ => "\uE765",
    };

    /// Ligne façon carte de Réglages : icône, intitulé + description, puis à droite le lieu, l'alerte, les touches.
    private Button RowButton(ShortcutRow row)
    {
        var grid = new Grid { ColumnSpacing = 16 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        grid.Children.Add(new FontIcon { Glyph = CategoryGlyph(row.Category), FontSize = 18, VerticalAlignment = VerticalAlignment.Center });

        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Spacing = 1 };
        text.Children.Add(new TextBlock { Text = row.Label, TextTrimming = TextTrimming.CharacterEllipsis });
        text.Children.Add(new TextBlock { Text = row.Description, Style = Res<Style>("CaptionTextBlockStyle"), Foreground = Secondary(), TextTrimming = TextTrimming.CharacterEllipsis });
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);

        if (!string.IsNullOrEmpty(row.Where))
        {
            var tag = new Border
            {
                Padding = new Thickness(8, 2, 8, 3), CornerRadius = new CornerRadius(10), VerticalAlignment = VerticalAlignment.Center,
                Background = Res<Brush>("SubtleFillColorSecondaryBrush"),
                Child = new TextBlock { Text = row.Where, FontSize = 12, Foreground = Secondary() },
            };
            Grid.SetColumn(tag, 2);
            grid.Children.Add(tag);
        }
        if (row.HasWarning)
        {
            var warn = new FontIcon { Glyph = "\uE7BA", FontSize = 16, VerticalAlignment = VerticalAlignment.Center,
                Foreground = Res<Brush>("SystemFillColorCautionBrush") };
            ToolTipService.SetToolTip(warn, row.WarningText);
            Grid.SetColumn(warn, 3);
            grid.Children.Add(warn);
        }

        var caps = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4, VerticalAlignment = VerticalAlignment.Center };
        foreach (var c in row.Caps) caps.Children.Add(KeyCap(c));
        Grid.SetColumn(caps, 4);
        grid.Children.Add(caps);

        var chevron = new FontIcon { Glyph = "\uE76C", FontSize = 12, VerticalAlignment = VerticalAlignment.Center, Foreground = Secondary() };
        Grid.SetColumn(chevron, 5);
        grid.Children.Add(chevron);

        var button = new Button { Style = Res<Style>("RowButton"), Content = grid, Opacity = row.Opacity };
        var help = row.HasWarning ? $" Attention : {row.WarningText}" : "";
        AutomationProperties.SetName(button, $"{string.Join(" ", row.Caps)} : {row.Label}.{help}");
        button.Click += async (_, _) => await EditAsync(row.Shortcut);

        // Clic droit : activer / désactiver, supprimer (comme sur Mac).
        var menu = new MenuFlyout();
        var toggle = new MenuFlyoutItem
        {
            Text = row.Shortcut.Enabled ? "Désactiver" : "Activer",
            Icon = new FontIcon { Glyph = row.Shortcut.Enabled ? "\uE769" : "\uE768" },
        };
        toggle.Click += (_, _) => _app.Upsert(row.Shortcut with { Enabled = !row.Shortcut.Enabled });
        var delete = new MenuFlyoutItem { Text = "Supprimer", Icon = new FontIcon { Glyph = "\uE74D" } };
        delete.Click += (_, _) => DeleteWithUndo(row.Shortcut.Id);
        menu.Items.Add(toggle);
        menu.Items.Add(delete);
        button.ContextFlyout = menu;
        return button;
    }

    private void DeleteWithUndo(Guid id)
    {
        _deleted = _app.Delete(id);
        if (_deleted is not null) ShowToast("Raccourci supprimé", InfoBarSeverity.Informational, undo: true);
    }

    private async void OnNewShortcut(object sender, RoutedEventArgs e) => await EditAsync(null);

    // ---------- Profils, import, export ----------

    private void BuildProfileMenu()
    {
        ProfileLabel.Text = $"Profil : {_app.CurrentPreset.Label()}";
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
            Style = Res<Style>("DefaultContentDialogStyle"),   // sinon, créé en code, le dialogue garde l'ancien style
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
            Style = Res<Style>("DefaultContentDialogStyle"),   // sinon, créé en code, le dialogue garde l'ancien style
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
        var picker = new FileSavePicker { SuggestedFileName = "FL Shortcuts - profil" };
        picker.FileTypeChoices.Add("Profil FL Shortcuts", new List<string> { ".json" });
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
            Style = Res<Style>("DefaultContentDialogStyle"),   // sinon, créé en code, le dialogue garde l'ancien style
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
        // Rubriques : SelectorBar (Windows App SDK 1.5+), l'indicateur glisse d'une rubrique à l'autre.
        var cats = new SelectorBar();
        foreach (var c in Enum.GetValues<ActionCategory>())
        {
            var label = new FlActionInfo(0, "", "", c, "").CategoryLabel;
            cats.Items.Add(new SelectorBarItem { Text = label, Tag = c, Icon = new FontIcon { Glyph = CategoryGlyph(label) } });
        }
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

        body.Children.Add(new TextBlock { Text = "Ton raccourci", Style = Res<Style>("BodyStrongTextBlockStyle") });
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
            // Raccourci de macro : ni action ni touche (la macro se choisit dans la page Macros), type gardé.
            kinds.SelectedIndex = isAction ? 0 : draft.Kind == ShortcutKind.Keystroke ? 1 : -1;
            actionPanel.Visibility = isAction ? Visibility.Visible : Visibility.Collapsed;
            keyPanel.Visibility = draft.Kind == ShortcutKind.Keystroke ? Visibility.Visible : Visibility.Collapsed;
            wheres.SelectedIndex = (int)draft.Context;
            cats.SelectedItem = query.Length == 0 ? cats.Items.FirstOrDefault(x => x.Tag is ActionCategory c && c == category) : null;

            actions.Items.Clear();
            var list = FlActions.All.Where(x => query.Length > 0
                ? (x.Label + " " + x.Detail()).Contains(query, StringComparison.CurrentCultureIgnoreCase)
                : x.Category == category);
            foreach (var info in list)
            {
                var availability = _app.Availability(info.Id);
                var item = new ListViewItem { Tag = info.Id, IsEnabled = availability.IsUsable };
                var stack = new StackPanel { Padding = new Thickness(0, 6, 0, 6), Spacing = 1 };
                stack.Children.Add(new TextBlock { Text = info.Label });
                stack.Children.Add(new TextBlock
                {
                    Text = availability is ActionAvailability.Unavailable u ? u.Reason : info.Detail(),
                    Style = Res<Style>("CaptionTextBlockStyle"), Foreground = Secondary(), TextWrapping = TextWrapping.Wrap,
                });
                item.Content = stack;
                actions.Items.Add(item);
                if (draft.ActionId == info.Id) actions.SelectedItem = item;
            }
            testButton.IsEnabled = draft.ActionId is not null && _app.Linked && !_app.Light;

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
            if (kinds.SelectedIndex < 0) return;
            var kind = kinds.SelectedIndex == 1 ? ShortcutKind.Keystroke : ShortcutKind.FlAction;
            if (kind != draft.Kind) { draft = draft with { Kind = kind, MacroRef = null }; Refresh(); }
        };
        cats.SelectionChanged += (bar, _) =>
        {
            if (bar.SelectedItem?.Tag is not ActionCategory picked || picked == category && query.Length == 0) return;
            category = picked;
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
                // Refresh vide et remplit la liste : jamais pendant son propre SelectionChanged.
                DispatcherQueue.TryEnqueue(() => Refresh());
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
            var final = draft.Kind switch
            {
                ShortcutKind.FlAction => draft with { Target = null },
                ShortcutKind.Keystroke => draft with { ActionId = null },
                _ => draft with { ActionId = null, Target = null },
            };
            _app.Upsert(final with { Enabled = true });
            ShowToast(existing is null ? "Raccourci ajouté" : "Raccourci modifié", InfoBarSeverity.Success);
        }
        else if (result == ContentDialogResult.Secondary && existing is not null)
        {
            DeleteWithUndo(existing.Id);
        }
    }

    private static bool IsDown(VirtualKey key) =>
        InputKeyboardSource.GetKeyStateForCurrentThread(key).HasFlag(CoreVirtualKeyStates.Down);

    private Button CaptureButton() => new()
    {
        HorizontalAlignment = HorizontalAlignment.Stretch,
        HorizontalContentAlignment = HorizontalAlignment.Center,
        MinHeight = 76,
        CornerRadius = Lookup("OverlayCornerRadius") is CornerRadius r ? r : new CornerRadius(8),
        IsTabStop = true,
    };

    private void SetCaptureContent(Button button, KeyCombo? combo, bool recording, string prompt)
    {
        // Bordure d'accentuation pendant l'enregistrement, comme un champ actif de Windows 11.
        if (recording)
        {
            button.BorderBrush = Res<Brush>("AccentFillColorDefaultBrush");
            button.BorderThickness = new Thickness(2);
        }
        else
        {
            button.ClearValue(Control.BorderBrushProperty);
            button.ClearValue(Control.BorderThicknessProperty);
        }
        if (recording || combo is null)
        {
            var hint = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
            var tint = recording ? Res<Brush>("AccentTextFillColorPrimaryBrush") : Secondary();
            hint.Children.Add(new FontIcon { Glyph = recording ? "\uE765" : "\uE710", FontSize = 16, Foreground = tint });
            hint.Children.Add(new TextBlock { Text = recording ? "Appuie sur tes touches… (Échap pour annuler)" : prompt,
                Foreground = tint, VerticalAlignment = VerticalAlignment.Center });
            button.Content = hint;
            button.Tag = null;
            AutomationProperties.SetName(button, recording ? "Enregistrement du raccourci en cours" : prompt);
            if (recording) button.Focus(FocusState.Programmatic);
            return;
        }
        var caps = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        var isNewCombo = button.Tag is not KeyCombo shown || shown != combo.Value;
        var i = 0;
        foreach (var c in combo.Value.Caps)
        {
            var cap = KeyCap(c, large: true);
            caps.Children.Add(cap);
            if (isNewCombo) Motion.Pop(cap, delayMs: i++ * 35, from: 0.7);      // les touches « se posent »
        }
        button.Tag = combo.Value;
        button.Content = caps;
        AutomationProperties.SetName(button, "Raccourci : " + combo.Value);
    }

    // ---------- Éléments visuels ----------

    private static Border KeyCap(string text, bool large = false) => new()
    {
        Style = Res<Style>("KeyCapBorder"),
        Height = large ? 40 : 26,
        MinWidth = large ? 40 : 26,
        Padding = new Thickness(large ? 12 : 8, 0, large ? 12 : 8, 0),
        Child = new TextBlock
        {
            Text = text,
            FontSize = large ? 16 : 12,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        },
    };

    private static Border StepCard(int number, string text, bool done)
    {
        var success = Res<Brush>("SystemFillColorSuccessBrush");
        var row = new Grid { ColumnSpacing = 12 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var dot = new Border
        {
            Width = 24, Height = 24, CornerRadius = new CornerRadius(12), VerticalAlignment = VerticalAlignment.Top,
            Background = done ? success : Res<Brush>("SubtleFillColorSecondaryBrush"),
            Child = done
                ? new FontIcon { Glyph = "\uE73E", FontSize = 12, Foreground = Res<Brush>("TextOnAccentFillColorPrimaryBrush") }
                : new TextBlock { Text = number.ToString(), FontSize = 12, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center },
        };
        row.Children.Add(dot);
        var label = new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, FontSize = 13 };
        Grid.SetColumn(label, 1);
        row.Children.Add(label);
        var card = new Border
        {
            Style = Res<Style>("Card"),
            Padding = new Thickness(14, 12, 14, 12),
            Child = row,
        };
        AutomationProperties.SetName(card, $"Étape {number} {(done ? "faite" : "à faire")} : {text}");
        return card;
    }

    private static Brush Secondary() => Res<Brush>("TextFillColorSecondaryBrush");

    /// Ressource du thème (Fluent) ou de App.xaml. Clé absente (autre version du Windows App SDK) : repli neutre
    /// (pinceau gris, style par défaut) au lieu d'une exception qui ferait tomber la fenêtre (relecture 11).
    private static T Res<T>(string key) where T : class
    {
        if (Lookup(key) is T found) return found;
        return typeof(T) == typeof(Brush) ? (T)(object)new SolidColorBrush(Colors.Gray) : null!;
    }

    private static T? TryRes<T>(string key) where T : class => Lookup(key) as T;

    /// L'indexeur cherche aussi dans les dictionnaires fusionnés et de thème (XamlControlsResources) ;
    /// TryGetValue passe par HasKey, dont la recherche dans ces dictionnaires n'est pas garantie.
    private static object? Lookup(string key)
    {
        try { return Application.Current.Resources[key]; }
        catch (Exception) { return null; }        // KeyNotFoundException ou COMException selon la projection
    }

    // ---------- Notification ----------

    private void ShowToast(string message, InfoBarSeverity severity, bool undo = false)
    {
        var (glyph, brush) = severity switch
        {
            InfoBarSeverity.Success => ("\uE73E", "SystemFillColorSuccessBrush"),
            InfoBarSeverity.Warning => ("\uE7BA", "SystemFillColorCautionBrush"),
            InfoBarSeverity.Error => ("\uE783", "SystemFillColorCriticalBrush"),
            _ => ("\uE946", "AccentTextFillColorPrimaryBrush"),
        };
        ToastIcon.Glyph = glyph;
        ToastIcon.Foreground = Res<Brush>(brush);
        ToastText.Text = message;
        ToastUndo.Visibility = undo ? Visibility.Visible : Visibility.Collapsed;
        AutomationProperties.SetName(Toast, message);

        var replacing = Toast.Visibility == Visibility.Visible && !_toastLeaving;
        Toast.Visibility = Visibility.Visible;
        _toastLeaving = false;
        if (replacing) Motion.Pop(Toast, from: 0.96);           // remplace la précédente sans clignoter
        else Motion.Enter(Toast, fromY: 24, durationMs: Motion.Normal, opacity: 1);

        _toastTimer?.Stop();
        _toastTimer = DispatcherQueue.CreateTimer();
        _toastTimer.Interval = TimeSpan.FromSeconds(undo ? 5 : 3.5);
        _toastTimer.IsRepeating = false;
        _toastTimer.Tick += (_, _) => HideToast();
        _toastTimer.Start();
    }

    private void HideToast()
    {
        _toastTimer?.Stop();
        _deleted = null;
        if (Toast.Visibility != Visibility.Visible || _toastLeaving) return;
        _toastLeaving = true;
        Motion.Exit(Toast, () =>
        {
            // Une nouvelle notification a pu arriver pendant le fondu : elle a remis _toastLeaving à false.
            if (!_toastLeaving) return;
            _toastLeaving = false;
            Toast.Visibility = Visibility.Collapsed;
        });
    }

    private void OnToastUndo(object sender, RoutedEventArgs e)
    {
        if (_deleted is { } d) _app.Upsert(d);
        HideToast();
    }

    private void OnToastClose(object sender, RoutedEventArgs e) => HideToast();
}
