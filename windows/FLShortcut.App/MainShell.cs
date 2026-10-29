// Fenêtre principale comme le Mac (29/10, le propriétaire : « exactement la même interface sur win ») : Main.dc.html —
// fond noir plein, barre de gauche dans une plaque claire (recherche, pages de FL, Macros, Mes raccourcis), en-tête de
// la page (titre en gras), raccourcis en cartes titrées sur deux colonnes, touche changée en bleu avec ↺ devant, survol
// plein de la couleur de la page. Rien d'inutile (ni pastille d'état, ni compteur, ni interrupteur de pause) : un
// bandeau seulement quand il faut agir. Construit en code (comme l'Organiser), donc vérifiable sous Linux.
// Les boutons fermer / réduire / agrandir restent ceux de Windows, à droite.
using FLShortcut.Core;
using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal sealed partial class MainShell
{
    /// Barre de titre (boutons de Windows) : rien de cliquable dessous ; l'en-tête des pages est posé sous elle.
    private const double TitleBarHeight = 48;
    private const double SidebarWidth = 252;
    /// Largeur de page à partir de laquelle les cartes passent sur deux colonnes (comme le Mac).
    private const double TwoColumnWidth = 660;

    private enum PageKind { Section, Custom }

    private readonly Window _window;
    private readonly Grid _root;
    private readonly AppController _app;
    private readonly TrayIcon? _tray;
    private readonly IntPtr _hwnd;
    private readonly bool _photos;
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer _poll;
    private bool _quitting;

    // Page affichée
    private PageKind _kind = PageKind.Section;
    private FlSection _section = FlSection.General;
    private string _query = "";
    private KeyCombo? _keySearch;
    private bool _keyListening;
    private int _columns = 2;
    private readonly HashSet<string> _dismissed = new();

    // Éléments
    private readonly Grid _main = new() { Padding = new Thickness(8), ColumnSpacing = 8 };
    private readonly StackPanel _sidebarGroups = new() { Spacing = 14 };
    private readonly TextBox _search = new();
    private readonly Button _keyButton;
    private readonly TextBlock _title = Label("", 22, Text, bold: true);
    private readonly StackPanel _capsule = new() { Orientation = Orientation.Horizontal, Spacing = 2 };
    private readonly Border _capsuleBorder;
    private readonly StackPanel _notices = new() { Spacing = 8, Margin = new Thickness(26, 0, 26, 0) };
    private readonly ScrollViewer _scroll = new() { HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
    private readonly Border _titleBar = new() { Height = TitleBarHeight, VerticalAlignment = VerticalAlignment.Top, Background = Brush(Colors.Transparent) };

    public MainShell(Window window, Grid root, bool photos)
    {
        _window = window;
        _root = root;
        _photos = photos;
        _hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);

        root.Background = Brush(WindowColor);
        root.RequestedTheme = ElementTheme.Dark;
        window.Title = "FL Shortcuts";
        window.ExtendsContentIntoTitleBar = true;
        _titleBar.Margin = new Thickness(SidebarWidth + 16, 0, 0, 0);
        window.SetTitleBar(_titleBar);
        if (AppWindowTitleBar.IsCustomizationSupported())
        {
            var bar = window.AppWindow.TitleBar;
            bar.PreferredHeightOption = TitleBarHeightOption.Tall;
            bar.ButtonBackgroundColor = Colors.Transparent;
            bar.ButtonInactiveBackgroundColor = Colors.Transparent;
            bar.ButtonForegroundColor = Text;
            bar.ButtonInactiveForegroundColor = Secondary;
            bar.ButtonHoverBackgroundColor = White(0.1);
            bar.ButtonHoverForegroundColor = Colors.White;
            bar.ButtonPressedBackgroundColor = White(0.18);
            bar.ButtonPressedForegroundColor = Colors.White;
        }
        window.AppWindow.Resize(new Windows.Graphics.SizeInt32(1180, 760));
        window.AppWindow.Closing += OnClosing;

        _app = new AppController(window.DispatcherQueue);
        _app.PropertyChanged += (_, e) =>
        {
            switch (e.PropertyName)
            {
                case nameof(AppController.Catalog): RenderPage(); break;
                case nameof(AppController.StatusTitle):
                case nameof(AppController.Enabled): RenderNotices(); UpdateTooltip(); break;
                case nameof(AppController.Onboarded): ShowScreen(); break;
            }
        };

        if (!photos)
        {
            _tray = new TrayIcon(_hwnd, "FL Shortcuts") { IsEnabled = () => _app.Enabled };
            _tray.OpenRequested += () => window.DispatcherQueue.TryEnqueue(() => ShowFromTray(ask: true));
            _tray.ToggleRequested += () => window.DispatcherQueue.TryEnqueue(_app.Toggle);
            _tray.QuitRequested += () => window.DispatcherQueue.TryEnqueue(Quit);
            _tray.HasPendingCopy = () => _app.Approval.Pending.Count > 0;
            _tray.OrganizeRequested += () => window.DispatcherQueue.TryEnqueue(() => OrganizerWindow.Show(_app));
            _tray.MacrosRequested += () => window.DispatcherQueue.TryEnqueue(() => MacrosWindow.Show(_app));
            _tray.ApproveRequested += () => window.DispatcherQueue.TryEnqueue(() =>
            {
                ShowFromTray(ask: false);
                CopyApprovalPrompt.Ask(_root.XamlRoot, _app, force: true);
            });
        }

        _poll = window.DispatcherQueue.CreateTimer();
        _poll.Interval = TimeSpan.FromSeconds(1);
        _poll.Tick += (_, _) => OnPoll();
        _poll.Start();

        // Barre de gauche et page.
        _keyButton = KeySearchButton();
        _capsuleBorder = new Border
        {
            Child = _capsule,
            Padding = new Thickness(3),
            CornerRadius = new CornerRadius(25),
            Background = Brush(White(0.10)),
            BorderBrush = Brush(White(0.18)),
            BorderThickness = new Thickness(1),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
        };
        BuildMain();
        BuildWelcome();
        BuildToast();
        root.Children.Add(_main);
        root.Children.Add(_welcome);
        root.Children.Add(_toast);
        root.Children.Add(_titleBar);
        root.PreviewKeyDown += OnRootKey;

        if (photos) _app.PreparePages();
        else _app.Start();
        ShowScreen();
        _app.MacroFinished += (ok, text) => { if (!ok) ShowToast(text); };
        if (!photos) root.Loaded += (_, _) => CopyApprovalPrompt.Ask(_root.XamlRoot, _app, force: false);
    }

    // ---------- Fenêtre et zone de notification ----------

    private void OnClosing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (_quitting || _photos) return;
        args.Cancel = true;          // la croix cache la fenêtre : FL Shortcuts continue dans la zone de notification
        sender.Hide();
    }

    private void ShowFromTray(bool ask)
    {
        _window.AppWindow.Show();
        _window.Activate();
        if (ask) CopyApprovalPrompt.Ask(_root.XamlRoot, _app, force: false);
    }

    private void Quit()
    {
        _quitting = true;
        _poll.Stop();
        _tray?.Dispose();
        _app.Dispose();
        _window.Close();
        Application.Current.Exit();
    }

    private void UpdateTooltip() =>
        _tray?.SetTooltip(_app.Enabled ? $"FL Shortcuts — {Loc.T(_app.StatusTitle)}" : "FL Shortcuts — " + Loc.T("En pause"));

    /// Accueil (ports MIDI, lien avec FL) tant qu'il n'est pas fait ; sinon la fenêtre des raccourcis.
    private void ShowScreen()
    {
        var main = _app.Onboarded;
        _main.Visibility = main ? Visibility.Visible : Visibility.Collapsed;
        _welcome.Visibility = main ? Visibility.Collapsed : Visibility.Visible;
        if (main)
        {
            RenderSidebar();
            RenderPage();
            RenderNotices();
            UpdateTooltip();
        }
        else
        {
            ShowWelcomePorts();
        }
    }

    /// Mode photos de la CI : une page donnée (« general », « playlist », « custom », « recherche »…).
    public void ShowPage(string page)
    {
        _query = "";
        _keySearch = null;
        _search.Text = "";
        switch (page)
        {
            case "custom": _kind = PageKind.Custom; break;
            case "recherche": _query = "Outil"; _search.Text = _query; break;
            default:
                _kind = PageKind.Section;
                _section = Enum.GetValues<FlSection>().FirstOrDefault(s => s.Raw().Equals(page, StringComparison.OrdinalIgnoreCase));
                break;
        }
        RenderSidebar();
        RenderPage();
    }

    // ---------- Barre de gauche ----------

    private void BuildMain()
    {
        _main.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(SidebarWidth) });
        _main.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        // Recherche : une capsule claire, la loupe, le champ sans cadre, le clavier (chercher avec ses touches).
        foreach (var key in new[] { "TextControlBackground", "TextControlBackgroundPointerOver", "TextControlBackgroundFocused",
                                    "TextControlBorderBrush", "TextControlBorderBrushPointerOver", "TextControlBorderBrushFocused" })
            _search.Resources[key] = Brush(Colors.Transparent);
        _search.Resources["TextControlForeground"] = Brush(Text);
        _search.Resources["TextControlForegroundFocused"] = Brush(Text);
        _search.Resources["TextControlForegroundPointerOver"] = Brush(Text);
        _search.Resources["TextControlPlaceholderForeground"] = Brush(Secondary);
        _search.Resources["TextControlPlaceholderForegroundFocused"] = Brush(Tertiary);
        _search.Resources["TextControlPlaceholderForegroundPointerOver"] = Brush(Secondary);
        _search.BorderThickness = new Thickness(0);
        _search.Background = Brush(Colors.Transparent);
        _search.PlaceholderText = Loc.T("Rechercher");
        _search.FontSize = 13;
        _search.Padding = new Thickness(4, 6, 4, 4);
        _search.MinHeight = 30;
        _search.VerticalAlignment = VerticalAlignment.Center;
        AutomationProperties.SetName(_search, Loc.T("Rechercher"));
        _search.TextChanged += (_, _) =>
        {
            var text = _search.Text;
            if (text == _query) return;
            _query = text;
            if (_keySearch is { } k && k.ToString() != text) _keySearch = null;
            RenderSidebar();
            RenderPage();
        };
        var searchRow = new Grid { ColumnSpacing = 2 };
        searchRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        searchRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        searchRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var loupe = Icon("search", 13, Secondary);
        loupe.Margin = new Thickness(2, 0, 0, 0);
        searchRow.Children.Add(loupe);
        Grid.SetColumn(_search, 1);
        searchRow.Children.Add(_search);
        Grid.SetColumn(_keyButton, 2);
        searchRow.Children.Add(_keyButton);
        var searchCapsule = new Border
        {
            Child = searchRow,
            Height = 34,
            Padding = new Thickness(8, 0, 6, 0),
            CornerRadius = new CornerRadius(17),
            Background = Brush(White(0.10)),
            BorderBrush = Brush(White(0.16)),
            BorderThickness = new Thickness(1),
        };
        searchCapsule.Tapped += (_, _) => _search.Focus(FocusState.Programmatic);

        var sidebarStack = new Grid { RowSpacing = 14 };
        sidebarStack.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        sidebarStack.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        sidebarStack.Children.Add(searchCapsule);
        var groupsScroll = new ScrollViewer
        {
            Content = _sidebarGroups,
            VerticalScrollBarVisibility = ScrollBarVisibility.Hidden,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        };
        Grid.SetRow(groupsScroll, 1);
        sidebarStack.Children.Add(groupsScroll);
        var sidebar = Plate(sidebarStack, 19, 0.10, 0.04, 0.16);
        sidebar.Padding = new Thickness(10, 14, 10, 16);
        _main.Children.Add(sidebar);

        // Page : en-tête (titre, capsule) sous la barre de titre, bandeaux, puis les cartes qui défilent.
        var page = new Grid { RowSpacing = 6 };
        page.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        page.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        page.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var header = new Grid { Margin = new Thickness(26, TitleBarHeight - 8, 26, 4), MinHeight = 52 };
        header.Children.Add(_title);
        header.Children.Add(_capsuleBorder);
        page.Children.Add(header);
        Grid.SetRow(_notices, 1);
        page.Children.Add(_notices);
        Grid.SetRow(_scroll, 2);
        page.Children.Add(_scroll);
        _scroll.SizeChanged += (_, e) =>
        {
            var columns = e.NewSize.Width - 52 >= TwoColumnWidth ? 2 : 1;
            if (columns == _columns) return;
            _columns = columns;
            RenderPage();
        };
        Grid.SetColumn(page, 1);
        _main.Children.Add(page);
    }

    private void RenderSidebar()
    {
        _sidebarGroups.Children.Clear();
        var searching = _query.Trim().Length > 0;
        var fl = Group(Loc.T("FL Studio"));
        foreach (var s in Enum.GetValues<FlSection>())
        {
            var section = s;
            fl.Children.Add(SidebarRow(IconName(s), Tint(s), s.Title(),
                !searching && _kind == PageKind.Section && _section == s, () => Choose(PageKind.Section, section)));
        }
        _sidebarGroups.Children.Add(fl);
        var automate = Group(Loc.T("Automatiser"));
        automate.Children.Add(SidebarRow("macros", Purple, Loc.T("Macros"), false, () => MacrosWindow.Show(_app)));
        _sidebarGroups.Children.Add(automate);
        var custom = Group(Loc.T("Personnalisé"));
        custom.Children.Add(SidebarRow("custom", Pink, Loc.T("Mes raccourcis"),
            !searching && _kind == PageKind.Custom, () => Choose(PageKind.Custom, _section)));
        _sidebarGroups.Children.Add(custom);
    }

    /// Titre gris d'un groupe de la barre de gauche (« FL Studio », « Automatiser »…) et ses lignes.
    private static StackPanel Group(string title)
    {
        var group = new StackPanel { Spacing = 2 };
        var label = Label(title, 11, Secondary, semibold: true);
        label.Margin = new Thickness(10, 0, 10, 4);
        AutomationProperties.SetHeadingLevel(label, Microsoft.UI.Xaml.Automation.Peers.AutomationHeadingLevel.Level2);
        group.Children.Add(label);
        return group;
    }

    /// Une ligne de la barre de gauche : carré de couleur (22 points), puis le nom ; choisie : pastille bleue.
    private static Button SidebarRow(string icon, Color tint, string title, bool selected, Action choose)
    {
        var tile = Tile(icon, tint, 22);
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        row.Children.Add(tile);
        row.Children.Add(Label(title, 13));
        var button = Option(row, tint, 9, choose, selected, on => SetTileHover(tile, icon, tint, on));
        AutomationProperties.SetName(button, title);
        return button;
    }

    private void Choose(PageKind kind, FlSection section)
    {
        _kind = kind;
        _section = section;
        _query = "";
        _keySearch = null;
        _search.Text = "";
        RenderSidebar();
        RenderPage();
        _scroll.ChangeView(null, 0, null, disableAnimation: true);
    }

    // ---------- Recherche avec une touche ----------

    private Button KeySearchButton()
    {
        var button = new Button
        {
            Style = PlainButton,
            Width = 26,
            Height = 26,
            HorizontalAlignment = HorizontalAlignment.Right,
            HorizontalContentAlignment = HorizontalAlignment.Center,
            CornerRadius = new CornerRadius(6),
            Content = Icon("keyboard", 15, Secondary),
        };
        ToolTipService.SetToolTip(button, Loc.T("Rechercher avec un raccourci : appuie sur les touches que tu connais"));
        AutomationProperties.SetName(button, Loc.T("Rechercher avec un raccourci"));
        button.Click += (_, _) =>
        {
            if (_keyListening) StopKeySearch();
            else StartKeySearch();
        };
        return button;
    }

    private void StartKeySearch()
    {
        _keyListening = true;
        _app.SetRecording(true);
        _keyButton.Content = Icon("keyboard", 15, Accent);
        _keyButton.Focus(FocusState.Programmatic);
        RenderNotices();
    }

    private void StopKeySearch()
    {
        _keyListening = false;
        _app.SetRecording(false);
        _keyButton.Content = Icon("keyboard", 15, Secondary);
        RenderNotices();
    }

    /// Touches appuyées pendant la recherche par raccourci (Échap annule) ; les autres touches suivent leur cours.
    private void OnRootKey(object sender, KeyRoutedEventArgs e)
    {
        if (!_keyListening) return;
        var vk = (ushort)e.Key;
        if (Vk.IsModifier(vk)) return;
        e.Handled = true;
        var combo = CurrentCombo(vk);
        if (e.Key == Windows.System.VirtualKey.Escape && !combo.HasModifiers)
        {
            StopKeySearch();
            return;
        }
        if (!combo.IsValidKey) return;
        StopKeySearch();
        _keySearch = combo;
        _query = combo.ToString();
        _search.Text = _query;
        RenderSidebar();
        RenderPage();
    }

    private static bool IsDown(Windows.System.VirtualKey key) =>
        Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(key).HasFlag(Windows.UI.Core.CoreVirtualKeyStates.Down);

    private static KeyCombo CurrentCombo(ushort vk) => new(vk, IsDown(Windows.System.VirtualKey.Control),
        IsDown(Windows.System.VirtualKey.Menu), IsDown(Windows.System.VirtualKey.Shift),
        IsDown(Windows.System.VirtualKey.LeftWindows) || IsDown(Windows.System.VirtualKey.RightWindows));

    // ---------- Bandeaux (seulement quand il faut agir) ----------

    private void RenderNotices()
    {
        _notices.Children.Clear();
        if (_keyListening)
            _notices.Children.Add(Notice("keyboard", Accent, Loc.T("Appuie sur le raccourci que tu connais : la recherche montre ce qu'il fait."),
                Loc.T("Annuler"), StopKeySearch));
        switch (_app.Status)
        {
            case StatusKind.Paused:
                _notices.Children.Add(Notice("warning", Orange, Loc.T("En pause : FL Studio utilise ses raccourcis d'origine"),
                    Loc.T("Reprendre"), _app.Toggle));
                break;
            case StatusKind.Elevated:
                _notices.Children.Add(Notice("warning", Red, Loc.T(_app.StatusText), null, null));
                break;
            case StatusKind.Inactive or StatusKind.NoKey or StatusKind.Tampered or StatusKind.Incompatible:
                _notices.Children.Add(Notice("warning", _app.Status == StatusKind.Tampered ? Red : Orange,
                    Loc.T(_app.StatusTitle) + " : " + Loc.T(_app.StatusText), Loc.T("Réparer"), Repair));
                break;
        }
        foreach (var warning in new[] { _app.LoadWarning, _app.MacroProblem })
        {
            if (warning is null || _dismissed.Contains(warning)) continue;
            var text = warning;
            _notices.Children.Add(Notice("warning", Secondary, text, Loc.T("OK"), () =>
            {
                _dismissed.Add(text);
                RenderNotices();
            }));
        }
        _notices.Visibility = _notices.Children.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    /// Un bandeau : une icône de couleur, une phrase, un bouton (comme NoticeItem du Mac).
    private static Border Notice(string icon, Color tint, string text, string? button, Action? action)
    {
        var grid = new Grid { ColumnSpacing = 10 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(Icon(icon, 15, tint, WindowColor));
        var label = Paragraph(text, 13, Text);
        label.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(label, 1);
        grid.Children.Add(label);
        if (button is not null && action is not null)
        {
            var b = Soft(button, action);
            Grid.SetColumn(b, 2);
            grid.Children.Add(b);
        }
        return new Border
        {
            Child = grid,
            Padding = new Thickness(14, 8, 8, 8),
            CornerRadius = new CornerRadius(14),
            Background = Brush(WithOpacity(tint, 0.16)),
            BorderBrush = Brush(WithOpacity(tint, 0.35)),
            BorderThickness = new Thickness(1),
        };
    }

    // ---------- Pages ----------

    private sealed record PageCard(string Title, List<FrameworkElement> Rows);

    private void RenderPage()
    {
        if (!_app.Onboarded) return;
        var (rows, others) = _app.Catalog;
        var q = _query.Trim();
        _capsule.Children.Clear();
        _capsuleBorder.Visibility = Visibility.Collapsed;
        List<PageCard> cards;
        Color tint;
        if (q.Length > 0)
        {
            _title.Text = Loc.T("Rechercher");
            tint = Accent;
            cards = SearchCards(rows, others, q);
            if (cards.Count == 0)
            {
                ShowEmpty("search",
                    _keySearch is not null ? Loc.T("Aucun raccourci") : Loc.T("Aucun résultat"),
                    _keySearch is { } k ? Loc.F("Rien n'utilise %@ : ces touches sont libres.", k.ToString())
                                        : Loc.F("Aucun raccourci ne correspond à « %@ ».", q));
                return;
            }
        }
        else if (_kind == PageKind.Custom)
        {
            _title.Text = Loc.T("Mes raccourcis");
            tint = Pink;
            cards = new List<PageCard>();
            var changed = MyShortcuts.Changed(rows);
            foreach (var s in Enum.GetValues<FlSection>())
            {
                var mine = changed.Where(r => r.Entry.Section == s).ToList();
                if (mine.Count > 0) cards.Add(new PageCard(s.Title(), mine.Select(r => CatalogRowView(r, Pink)).ToList()));
            }
            var created = MyShortcuts.Created(others, _app.Starters);
            if (created.Count > 0)
                cards.Add(new PageCard(Loc.T("Créés par toi"), created.Select(s => CustomRowView(s, Pink)).ToList()));
            if (cards.Count == 0)
            {
                ShowEmpty("custom", Loc.T("Aucun raccourci changé"),
                    Loc.T("Chaque raccourci que tu changes arrive ici, avec ceux que tu crées. Les macros ont leur page."));
                return;
            }
        }
        else
        {
            _title.Text = _section.Title();
            tint = Tint(_section);
            var mine = rows.Where(r => r.Entry.Section == _section).ToList();
            cards = CatalogGroups.Cards(_section, mine.Where(r => r.Entry.IsNative), r => r.Entry)
                .Select(c => new PageCard(c.Title, c.Rows.Select(r => CatalogRowView(r, tint)).ToList())).ToList();
            var extras = mine.Where(r => !r.Entry.IsNative).ToList();
            if (extras.Count > 0)
                cards.Add(new PageCard(Loc.T("Actions en plus"), extras.Select(r => CatalogRowView(r, tint)).ToList()));
        }
        ShowCards(cards);
    }

    /// Recherche : les raccourcis de toutes les pages, une carte par page ; avec une touche appuyée (bouton clavier) :
    /// ce qui se lance sur ces touches, ou les portait dans FL.
    private List<PageCard> SearchCards(List<CatalogRow> rows, List<Shortcut> others, string q)
    {
        bool Matches(CatalogRow r) => _keySearch is { } k
            ? r.Current == k || r.Entry.DefaultTrigger == k
            : $"{r.Entry.Title} {r.Entry.Detail} {r.Current} {r.Entry.Section.Title()}".Contains(q, StringComparison.CurrentCultureIgnoreCase);
        var cards = new List<PageCard>();
        foreach (var s in Enum.GetValues<FlSection>())
        {
            var found = rows.Where(r => r.Entry.Section == s && Matches(r)).ToList();
            if (found.Count > 0) cards.Add(new PageCard(s.Title(), found.Select(r => CatalogRowView(r, Tint(s))).ToList()));
        }
        var mine = others.Where(o => o.Kind != ShortcutKind.Macro && (_keySearch is { } k
            ? o.Trigger == k
            : $"{_app.TitleOf(o)} {o.Trigger}".Contains(q, StringComparison.CurrentCultureIgnoreCase))).ToList();
        if (mine.Count > 0) cards.Add(new PageCard(Loc.T("Mes raccourcis"), mine.Select(o => CustomRowView(o, Pink)).ToList()));
        return cards;
    }

    /// Cartes sur une ou deux colonnes (comme CardMasonry du Mac) ; la page repart du haut.
    private void ShowCards(List<PageCard> cards)
    {
        var columns = CatalogGroups.Columns(cards, _columns, c => c.Rows.Count);
        var grid = new Grid { ColumnSpacing = 24, Padding = new Thickness(26, 10, 26, 24) };
        for (var i = 0; i < Math.Max(_columns, columns.Count); i++)
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        for (var i = 0; i < columns.Count; i++)
        {
            var stack = new StackPanel { Spacing = 20 };
            foreach (var card in columns[i]) stack.Children.Add(TitledCard(card.Title, card.Rows));
            Grid.SetColumn(stack, i);
            grid.Children.Add(stack);
        }
        _scroll.Content = grid;
    }

    private void ShowEmpty(string icon, string title, string text)
    {
        var stack = new StackPanel { Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center, Padding = new Thickness(24, 80, 24, 24), MaxWidth = 420 };
        var tile = Tile(icon, icon == "custom" ? Pink : Gray, 44);
        tile.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Children.Add(tile);
        var heading = Label(title, 17, Text, bold: true);
        heading.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Children.Add(heading);
        var body = Paragraph(text, 13);
        body.TextAlignment = TextAlignment.Center;
        stack.Children.Add(body);
        _scroll.Content = stack;
    }

    /// Carte de raccourcis : son titre gris au-dessus, ses lignes dans une plaque claire, un trait fin entre deux.
    private static StackPanel TitledCard(string title, List<FrameworkElement> rows)
    {
        var card = new StackPanel { Spacing = 6 };
        var label = Label(title, 12, Secondary, semibold: true);
        label.Margin = new Thickness(12, 0, 0, 0);
        AutomationProperties.SetHeadingLevel(label, Microsoft.UI.Xaml.Automation.Peers.AutomationHeadingLevel.Level3);
        card.Children.Add(label);
        var list = new StackPanel();
        for (var i = 0; i < rows.Count; i++)
        {
            var cell = new Grid();
            cell.Children.Add(rows[i]);
            if (i > 0)
                cell.Children.Add(new Rectangle { Height = 1, Fill = Brush(White(0.06)), VerticalAlignment = VerticalAlignment.Top,
                                                  Margin = new Thickness(10, 0, 10, 0), IsHitTestVisible = false });
            list.Children.Add(cell);
        }
        var plate = Plate(list, 14);
        plate.Padding = new Thickness(2);
        card.Children.Add(plate);
        return card;
    }

    /// Ligne d'un raccourci de FL : son nom ; ⚠ si la touche est prise ; ↺ juste avant une touche changée ; la touche
    /// (bleue si changée). Un clic ouvre « Changer la touche ».
    private FrameworkElement CatalogRowView(CatalogRow row, Color tint)
    {
        var grid = new Grid { ColumnSpacing = 8 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var title = Label(row.Entry.Title, 13);
        ToolTipService.SetToolTip(title, row.Entry.IsNative ? Loc.T("Raccourci d'origine de FL Studio") : row.Entry.Detail);
        grid.Children.Add(title);

        var warnings = new List<string>();
        if (row.TakenBy is { } taken)
            warnings.Add(Loc.F("Touche aussi utilisée par « %@ ». Clique sur la touche pour en choisir une autre.", taken));
        if (row.Shortcut is { } s) warnings.AddRange(_app.IssuesOf(s.Id).Select(i => i.Message));
        if (warnings.Count > 0)
        {
            var warn = Icon("warning", 13, Orange, WindowColor);
            ToolTipService.SetToolTip(warn, string.Join("\n", warnings));
            Grid.SetColumn(warn, 1);
            grid.Children.Add(warn);
        }
        if (!row.IsDefault)
        {
            var reset = RoundIcon("reset", Loc.T("Revenir à : ") + (row.Entry.DefaultTrigger?.ToString() ?? Loc.T("aucune touche")),
                () => Reset(row), 28);
            Grid.SetColumn(reset, 2);
            grid.Children.Add(reset);
        }
        var keys = Keys(row.Current, changed: !row.IsDefault);
        Grid.SetColumn(keys, 3);
        grid.Children.Add(keys);

        var option = Option(grid, tint, 10, () => EditKey(row), minHeight: 36);
        AutomationProperties.SetName(option, $"{row.Entry.Title} : {row.Current?.ToString() ?? Loc.T("aucune")}");
        AutomationProperties.SetHelpText(option, Loc.T("Changer la touche"));
        var menu = new MenuFlyout();
        var change = new MenuFlyoutItem { Text = Loc.T("Changer la touche…") };
        change.Click += (_, _) => EditKey(row);
        var resetItem = new MenuFlyoutItem { Text = Loc.T("Réinitialiser"), IsEnabled = !row.IsDefault };
        resetItem.Click += (_, _) => Reset(row);
        menu.Items.Add(change);
        menu.Items.Add(resetItem);
        option.ContextFlyout = menu;
        return option;
    }

    /// Ligne d'un raccourci que tu as créé : son nom (et sa fenêtre de FL), sa touche, « Supprimer ».
    private FrameworkElement CustomRowView(Shortcut s, Color tint)
    {
        var grid = new Grid { ColumnSpacing = 8 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Spacing = 1 };
        text.Children.Add(Label(_app.TitleOf(s), 13));
        var caption = _app.SubtitleOf(s);
        if (caption.Length > 0) text.Children.Add(Label(char.ToUpper(caption[0]) + caption[1..], 11, Secondary));
        grid.Children.Add(text);
        var issues = _app.IssuesOf(s.Id);
        if (issues.Count > 0)
        {
            var warn = Icon("warning", 13, Orange, WindowColor);
            ToolTipService.SetToolTip(warn, string.Join("\n", issues.Select(i => i.Message)));
            Grid.SetColumn(warn, 1);
            grid.Children.Add(warn);
        }
        var keys = Keys(s.Trigger);
        Grid.SetColumn(keys, 2);
        grid.Children.Add(keys);
        var delete = RoundIcon("trash", Loc.T("Supprimer"), () => Delete(s), 28);
        Grid.SetColumn(delete, 3);
        grid.Children.Add(delete);
        var option = Option(grid, tint, 10, async () => await EditCustomAsync(s), minHeight: 40);
        option.Opacity = s.Enabled ? 1 : 0.5;
        AutomationProperties.SetName(option, $"{_app.TitleOf(s)} : {s.Trigger?.ToString() ?? Loc.T("aucune")}");
        var menu = new MenuFlyout();
        var toggle = new MenuFlyoutItem { Text = s.Enabled ? Loc.T("Désactiver") : Loc.T("Activer") };
        toggle.Click += (_, _) => _app.Upsert(s with { Enabled = !s.Enabled });
        var remove = new MenuFlyoutItem { Text = Loc.T("Supprimer") };
        remove.Click += (_, _) => Delete(s);
        menu.Items.Add(toggle);
        menu.Items.Add(remove);
        option.ContextFlyout = menu;
        return option;
    }

    private void Reset(CatalogRow row)
    {
        var before = _app.ResetRow(row);
        ShowToast(Loc.F("« %@ » réinitialisé", row.Entry.Title), () => _app.Restore(before));
    }

    private void Delete(Shortcut s)
    {
        if (_app.Delete(s.Id) is { } deleted) ShowToast(Loc.T("Raccourci supprimé"), () => _app.Upsert(deleted));
    }

    // ---------- Notification (« Annuler ») ----------

    private Border _toast = null!;
    private TextBlock _toastText = null!;
    private Button _toastUndo = null!;
    private Action? _undo;
    private Microsoft.UI.Dispatching.DispatcherQueueTimer? _toastTimer;

    private void BuildToast()
    {
        _toastText = Label("", 13, Text);
        _toastText.TextWrapping = TextWrapping.Wrap;
        _toastText.MaxWidth = 440;
        _toastUndo = new Button
        {
            Style = PlainButton,
            Content = Label(Loc.T("Annuler"), 13, Link, semibold: true),
            HorizontalAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(6, 2, 6, 2),
            CornerRadius = new CornerRadius(6),
        };
        _toastUndo.Click += (_, _) =>
        {
            _undo?.Invoke();
            HideToast();
        };
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        row.Children.Add(_toastText);
        row.Children.Add(_toastUndo);
        _toast = new Border
        {
            Child = row,
            Padding = new Thickness(18, 10, 12, 10),
            CornerRadius = new CornerRadius(20),
            Background = Brush(Rgb(0x2C, 0x2C, 0x2E)),
            BorderBrush = Brush(White(0.16)),
            BorderThickness = new Thickness(1),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(SidebarWidth, 0, 0, 24),
            Visibility = Visibility.Collapsed,
        };
    }

    private void ShowToast(string message, Action? undo = null)
    {
        _toastText.Text = message;
        _undo = undo;
        _toastUndo.Visibility = undo is null ? Visibility.Collapsed : Visibility.Visible;
        _toast.Visibility = Visibility.Visible;
        AutomationProperties.SetName(_toast, message);
        _toastTimer?.Stop();
        _toastTimer = _window.DispatcherQueue.CreateTimer();
        _toastTimer.Interval = TimeSpan.FromSeconds(undo is null ? 3.5 : 5);
        _toastTimer.IsRepeating = false;
        _toastTimer.Tick += (_, _) => HideToast();
        _toastTimer.Start();
    }

    private void HideToast()
    {
        _toastTimer?.Stop();
        _undo = null;
        _toast.Visibility = Visibility.Collapsed;
    }
}
