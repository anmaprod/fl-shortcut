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
    /// Plus petite fenêtre (06/11, comme le Mac `EditorView.minWindowWidth`), en points.
    internal const double MinWindowWidth = 980, MinWindowHeight = 620;

    /// Barre de titre (boutons de Windows) : rien de cliquable dessous ; l'en-tête des pages est posé sous elle.
    private const double TitleBarHeight = 48;
    private const double SidebarWidth = 252;
    /// Largeur de page à partir de laquelle les cartes passent sur deux colonnes (comme le Mac).
    private const double TwoColumnWidth = 660;

    /// 16/11 (maquette « plus lisible ») : « Trouver un raccourci » d'abord, la page d'ouverture.
    private enum PageKind { Find, Section, Macros, Custom, Help, Account, Community }

    private readonly Window _window;
    private readonly Grid _root;
    private readonly AppController _app;
    private readonly TrayIcon? _tray;
    private readonly IntPtr _hwnd;
    private readonly bool _photos;
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer _poll;
    private Services.AutoUpdateWin? _updates;
    private bool _quitting;

    // Page affichée
    private PageKind _kind = PageKind.Find;
    private FlSection _section = FlSection.General;
    private string _query = "";
    private KeyCombo? _keySearch;
    private bool _keyListening;
    private int _columns = 2;
    private readonly HashSet<string> _dismissed = new();

    // Éléments
    private readonly Grid _main = new() { Padding = new Thickness(8), ColumnSpacing = 8 };
    private readonly StackPanel _sidebarGroups = new() { Spacing = 14 };
    /// Maquette « Minimal » (20/11, comme le Mac) : les menus en haut, et la colonne des pages de « Raccourcis ».
    private readonly StackPanel _navBar = new() { Orientation = Orientation.Horizontal, Spacing = 24, VerticalAlignment = VerticalAlignment.Center };
    /// Les menus dans la barre de titre (maquette « Minimal »), à gauche ; la zone qui déplace la fenêtre est à droite.
    private Border _navHost = null!;

    /// Menus visibles avec les pages et le créateur (pas sur l'accueil ni le guide) ; la barre de titre suit.
    private void UpdateTitleBarRegion()
    {
        var shown = _main.Visibility == Visibility.Visible || _macros.Creator.Visibility == Visibility.Visible;
        _navHost.Visibility = shown ? Visibility.Visible : Visibility.Collapsed;
        _titleBar.Margin = new Thickness(shown && _navHost.ActualWidth > 0 ? _navHost.ActualWidth + 8 : 16, 0, 0, 0);
    }
    private Border? _subnav;
    private readonly StackPanel _findSteps = new() { Orientation = Orientation.Horizontal, Spacing = 24, Visibility = Visibility.Collapsed };
    /// Case « tape son nom » de « Trouver un raccourci » (maquette « plus lisible » du 16/11).
    private readonly TextBox _search = new();
    /// Gros titre de page (style suisse : 46, gras, serré, souligné d'un trait blanc).
    private readonly TextBlock _title = SwissTitle(76);
    /// Surtitre de la page (direction A du 17/11) : « 02 — RACCOURCIS ».
    private readonly TextBlock _eyebrow = SwissLabel("", 11);
    /// 11/11 : flèche seule, sans cadre, devant le titre de la page d'une personne de la Communauté (son pseudo).
    private readonly Button _titleBack = new()
    {
        Style = PlainButton,
        Content = Icon("arrow.left", 26, Text),
        Padding = new Thickness(2, 0, 2, 0),
        VerticalAlignment = VerticalAlignment.Center,
        Visibility = Visibility.Collapsed,
    };
    private readonly StackPanel _capsule = new() { Orientation = Orientation.Horizontal, Spacing = 2 };
    private readonly Border _capsuleBorder;
    /// Bouton de la page dans l'en-tête, à gauche du compte (« Partager » de la Communauté, comme le Mac).
    private readonly ContentControl _headerAction = new() { VerticalAlignment = VerticalAlignment.Center, IsTabStop = false };
    private readonly StackPanel _notices = new() { Spacing = 8, Margin = new Thickness(ReadableInset, 0, ReadableInset, 0) };
    private readonly ScrollViewer _scroll = new() { HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
    /// Page posée au-dessus de la page (10/11, fiche et « Partager » de la Communauté, comme le Mac) : la page derrière
    /// s'assombrit et ne reçoit plus les clics ; la carte est au milieu. Tab reste dedans.
    private readonly Grid _above = new() { Visibility = Visibility.Collapsed, TabFocusNavigation = KeyboardNavigationMode.Cycle };
    private readonly MacrosPage _macros;
    private readonly HelpPage _help;
    private readonly AccountPage _account;
    private readonly CommunityPage _community;
    /// Bouton du compte en haut à droite (sa photo, ou l'icône du compte), comme le Mac.
    private readonly Border _accountSlot = new() { VerticalAlignment = VerticalAlignment.Center };
    /// Dernière macro ratée (« Signaler ce problème… » du menu de l'icône, comme le Mac).
    private string? _lastFailure;
    /// Mode photos : la macro d'exemple ouverte dans le créateur.
    private readonly Guid _demoMacro;
    private readonly Border _titleBar = new() { Height = TitleBarHeight, VerticalAlignment = VerticalAlignment.Top, Background = Brush(Colors.Transparent) };

    public MainShell(Window window, Grid root, bool photos)
    {
        _window = window;
        _root = root;
        _photos = photos;
        _hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);

        root.Background = Brush(WindowColor);
        root.RequestedTheme = MacLook.SurfaceTheme;
        ReleaseFieldsOnOutsideClick(root);
        window.Title = "FL Shortcuts";
        window.ExtendsContentIntoTitleBar = true;
        _titleBar.Margin = new Thickness(16, 0, 0, 0);
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
            bar.ButtonHoverForegroundColor = MacLook.Text;
            bar.ButtonPressedBackgroundColor = White(0.18);
            bar.ButtonPressedForegroundColor = MacLook.Text;
        }
        window.AppWindow.Resize(new Windows.Graphics.SizeInt32(1180, 760));
        window.AppWindow.Closing += OnClosing;
        // 06/11 (comme le Mac, « quand je réduis la page au plus petit, c'est très mal découpé ») : jamais plus petite
        // que 980 × 620 points, où chaque page garde sa mise en page.
        window.AppWindow.Changed += (sender, change) =>
        {
            if (!change.DidSizeChange) return;
            var scale = Native.Win32.GetDpiForWindow(_hwnd) / 96.0;
            int minWidth = (int)(MinWindowWidth * scale), minHeight = (int)(MinWindowHeight * scale);
            var size = sender.Size;
            if (size.Width < minWidth || size.Height < minHeight)
                sender.Resize(new Windows.Graphics.SizeInt32(Math.Max(size.Width, minWidth), Math.Max(size.Height, minHeight)));
        };

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
            _tray = new TrayIcon(_hwnd, "FL Shortcuts");
            _tray.OpenRequested += () => window.DispatcherQueue.TryEnqueue(() => ShowFromTray(ask: true));
            _tray.MenuRequested += () => window.DispatcherQueue.TryEnqueue(ShowTrayMenu);
            // FL Shortcuts relancé alors qu'il tourne déjà (App.OnLaunched) : la bulle montre où est son icône.
            ShowSignal.Listen(() => window.DispatcherQueue.TryEnqueue(() => TrayTip(alreadyRunning: true)));
        }

        _poll = window.DispatcherQueue.CreateTimer();
        _poll.Interval = TimeSpan.FromSeconds(1);
        _poll.Tick += (_, _) => OnPoll();
        _poll.Start();

        // Barre de gauche et page.
        // Barre de gauche : noire sous Orange (MacLook.Inverted), comme le Mac.
        _capsuleBorder = new Border
        {
            Child = _capsule,
            Padding = new Thickness(3),
            CornerRadius = new CornerRadius(0),
            Background = Brush(MacLook.WindowColor),
            BorderBrush = Brush(Text),
            BorderThickness = new Thickness(1),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Center,
        };
        BuildMain();
        BuildWelcome();
        BuildToast();
        // Macros : la page de la fenêtre et le créateur, posé au-dessus quand une macro est ouverte (comme le Mac).
        var (macroStore, demoMacro) = photos ? MacrosPage.DemoStore() : (_app.Macros, Guid.Empty);
        _demoMacro = demoMacro;
        _help = new HelpPage(_app, () => { if (_kind == PageKind.Help) RenderPage(); }, ShowToast)
        {
            ShowGuide = () => ShowGuide(plain: false),
        };
        // La carte de connexion sert aussi à la page Communauté (sans compte).
        _account = new AccountPage(() => { if (_kind is PageKind.Account or PageKind.Community) RenderPage(); }, ConfirmAsync, _hwnd);
        _account.ThemeCard = () => AccountPage.ThemeTabs(Theme, ChooseTheme);
        _community = new CommunityPage(_app, _account, () => { if (_kind == PageKind.Community) RenderPage(); }, ShowToast, ConfirmAsync)
        {
            AboveChanged = UpdateAbove,
            OpenAccount = () => Choose(PageKind.Account, _section),
            // 11/11 : point rouge de la barre de gauche, et « Noter » dans le message qui suit un ajout.
            BadgeChanged = () => RenderSidebar(),
            ToastAction = ShowToastWithAction,
        };
        _account.Changed += UpdateAccountButton;
        // Nouveautés des gens suivis : au lancement (compte connecté), à chaque connexion, puis toutes les 30 min.
        _account.Changed += () => _community.StartWatch(_window.DispatcherQueue);
        _community.StartWatch(_window.DispatcherQueue);
        // Sauvegarde en ligne commune avec le Mac (raccourcis traduits), suivie par la page Mon compte.
        var backup = new Services.AccountBackupWin(_app, _account);
        _account.Backup = backup;
        _account.Choose = ChooseAsync;
        // Thèmes seulement avec un compte (07/11, comme le Mac) : connexion, déconnexion, fin de la sauvegarde.
        _account.Changed += ThemeFollowsAccount;
        backup.Changed += ThemeFollowsAccount;
        _help.Token = async () =>
        {
            if (_account.Session is null) return null;
            try { return (await _account.FreshSession())?.AccessToken; }
            catch (Exception) { return _account.Session?.AccessToken; }      // hors ligne : l'ancien jeton
        };
        _app.SendSupport = _help.SendQuietly;
        // Aide › Mes messages (20/11) : le compte, « Se connecter », la fenêtre pour « Ajouter une capture ».
        _help.Session = async () =>
        {
            if (_account.Session is null) return null;
            try { return await _account.FreshSession(); }
            catch (Exception) { return _account.Session; }
        };
        _help.SignedIn = () => _account.Session is not null;
        _help.SignIn = () => Choose(PageKind.Account, _section);
        _help.Hwnd = _hwnd;
        _account.Changed += () =>
        {
            _help.Forget();
            if (_kind == PageKind.Help) RenderPage();
        };
        UpdateAccountButton();
        _macros = new MacrosPage(_app, macroStore, photos, window,
            listChanged: () => { if (_kind == PageKind.Macros) RenderPage(); },
            creatorShown: on =>
            {
                _main.Visibility = on || !_app.Onboarded ? Visibility.Collapsed : Visibility.Visible;
                RenderSidebar();                         // « Macros » choisi dans les menus du haut pendant le créateur
            },
            toast: ShowToast);
        // Touche d'une macro (liste du 16/11) : la fiche de son raccourci, comme les autres raccourcis.
        _macros.EditShortcut = EditCustomAsync;
        root.Children.Add(_main);
        root.Children.Add(_macros.Creator);
        root.Children.Add(_navHost);                     // sous l'accueil et le guide, qui le couvrent
        root.Children.Add(_welcome);
        root.Children.Add(_guideLayer);
        root.Children.Add(_toast);
        root.Children.Add(_titleBar);
        // La barre de titre (zone qui déplace la fenêtre) commence après les menus : sinon elle prend leurs clics.
        _navHost.SizeChanged += (_, _) => UpdateTitleBarRegion();
        _main.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (_, _) => UpdateTitleBarRegion());
        _macros.Creator.RegisterPropertyChangedCallback(UIElement.VisibilityProperty, (_, _) => UpdateTitleBarRegion());
        UpdateTitleBarRegion();
        root.PreviewKeyDown += OnRootKey;

        if (photos) _app.PreparePages();
        else
        {
            _app.Start();
            // Mises à jour toutes seules (19/11) : seulement une version publiée ; posées quand FL est fermé et la
            // fenêtre cachée (comme le Mac).
            _updates = new Services.AutoUpdateWin(window.DispatcherQueue, Services.FlPresence.IsRunning, () => _window.AppWindow.IsVisible, Quit);
            _updates.Start();
        }
        ShowScreen();
        _app.MacroFinished += (ok, text) =>
        {
            _lastFailure = ok ? null : text;
            if (!ok) ShowToast(text);
        };
        if (!photos) root.Loaded += (_, _) => CopyApprovalPrompt.Ask(_root.XamlRoot, _app, force: false);
        // 13/11 : « Garder » de l'écran de fin de l'Organiser, la version rangée gardée tout de suite.
        _app.KeepRequested += copy =>
        {
            ShowFromTray(ask: false);
            CopyApprovalPrompt.Ask(_root.XamlRoot, _app, force: true, keepCopy: copy);
        };
    }

    // ---------- Fenêtre et zone de notification ----------

    /// Comme le Mac (03/11) : la fenêtre au premier lancement (ou tant que l'accueil n'est pas fini), ensuite l'icône
    /// seule près de l'horloge ; la fenêtre s'ouvre d'un clic sur l'icône.
    internal bool ShowAtLaunch => !_app.Settings.WindowShownAtLaunch || !_app.Onboarded;

    /// Après le lancement : fenêtre montrée (retenu pour les prochaines fois), sinon la bulle qui montre l'icône.
    internal void Launched(bool windowShown)
    {
        if (windowShown)
        {
            if (_app.Settings.WindowShownAtLaunch) return;
            _app.Settings.WindowShownAtLaunch = true;
            _app.Settings.Save();
        }
        else if (!Environment.GetCommandLineArgs().Any(a => string.Equals(a, "--tray", StringComparison.OrdinalIgnoreCase)))
        {
            _tipShown = true;
            TrayTip(alreadyRunning: false);          // lancé à la main : dire où il est (pas au démarrage de Windows)
        }
    }

    private bool _tipShown;

    private void TrayTip(bool alreadyRunning) => _tray?.Notify(
        alreadyRunning ? Loc.T("FL Shortcuts est déjà ouvert") : Loc.T("FL Shortcuts est prêt"),
        Loc.T("Son icône est près de l'horloge. Clic : la fenêtre. Clic droit : le menu."));

    private void OnClosing(AppWindow sender, AppWindowClosingEventArgs args)
    {
        if (_quitting || _photos) return;
        args.Cancel = true;          // la croix cache la fenêtre : FL Shortcuts continue dans la zone de notification
        sender.Hide();
        if (_tipShown) return;
        _tipShown = true;            // la première fois : la bulle montre où il est resté
        TrayTip(alreadyRunning: false);
    }

    private void ShowFromTray(bool ask)
    {
        _window.AppWindow.Show();
        _window.Activate();
        if (ask) CopyApprovalPrompt.Ask(_root.XamlRoot, _app, force: false);
    }

    /// Le menu de l'icône, noir comme celui du Mac : l'état, les fenêtres de l'appli, « Ouvrir FL Shortcuts », « Quitter ».
    private void ShowTrayMenu()
    {
        var entries = new List<TrayMenu.Entry>();
        // Comme le Mac : après une macro ratée, le formulaire de l'Aide prêt avec l'erreur.
        if (_lastFailure is { } failure)
            entries.Add(new("warning", Orange, Loc.T("Signaler ce problème…"), () =>
            {
                ShowFromTray(ask: false);
                _help.Report("Macro : " + failure);
                _lastFailure = null;
                Choose(PageKind.Help, _section);
            }));
        entries.Add(new("keyboard", Blue, Loc.T("Modifier les raccourcis…"), () => ShowFromTray(ask: false)));
        if (_app.Approval.Pending.Count > 0)
            entries.Add(new("check", Green, Loc.T("Valider la version organisée…"), () =>
            {
                ShowFromTray(ask: false);
                CopyApprovalPrompt.Ask(_root.XamlRoot, _app, force: true);
            }));
        entries.Add(new("macros", Purple, Loc.T("Macros…"), () =>
        {
            ShowFromTray(ask: false);
            _macros.Back();
            if (_app.Onboarded) Choose(PageKind.Macros, _section);
        }));
        entries.Add(new("organize", Indigo, Loc.T("Organiser…"), () => OrganizerWindow.Show(_app)));
        // Comme le Mac : reprendre si l'app est en pause, installer le lien (hors mode léger), désinstaller.
        if (!_app.Enabled) entries.Add(new("check", Green, Loc.T("Reprendre"), _app.Toggle));
        if (!_app.Light)
            entries.Add(new("link", Green, Loc.T("Installer le lien avec FL Studio…"), () =>
            {
                ShowFromTray(ask: false);
                Repair();
            }));
        if (Uninstaller() is { } uninstall)
            entries.Add(new("trash", Gray, Loc.T("Désinstaller FL Shortcuts…"), () =>
            {
                try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(uninstall) { UseShellExecute = true }); }
                catch { /* annulé (contrôle de compte) : rien à faire */ }
            }));
        var status = _app.Enabled ? Loc.T(_app.StatusTitle) : Loc.T("En pause");
        TrayMenu.Show(status, _app.Enabled && _app.Status is StatusKind.Linked or StatusKind.FlClosed, entries, () => ShowFromTray(ask: true), Quit);
    }

    /// Un clic hors du champ qui a la main la lui fait lâcher (07/11 au soir, comme le Mac : la recherche de l'Aide
    /// gardait la main) ; elle passe à une case invisible, sans cadre de focus.
    private static void ReleaseFieldsOnOutsideClick(Grid root)
    {
        var sink = new ContentControl { IsTabStop = true, Width = 0, Height = 0, UseSystemFocusVisuals = false, Opacity = 0 };
        AutomationProperties.SetAccessibilityView(sink, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        root.Children.Add(sink);
        root.AddHandler(UIElement.PointerPressedEvent, new PointerEventHandler((_, e) =>
        {
            if (root.XamlRoot is not { } xamlRoot || FocusManager.GetFocusedElement(xamlRoot) is not TextBox box) return;
            for (var node = e.OriginalSource as DependencyObject; node is not null; node = VisualTreeHelper.GetParent(node))
                if (ReferenceEquals(node, box) || node is TextBox) return;          // dans un champ : il garde ou prend la main
            sink.Focus(FocusState.Programmatic);
        }), handledEventsToo: true);
    }

    /// Le désinstalleur posé par l'installeur à côté de l'appli (il demande lui-même confirmation), s'il existe.
    private static string? Uninstaller()
    {
        var path = System.IO.Path.Combine(AppContext.BaseDirectory, "unins000.exe");
        return System.IO.File.Exists(path) ? path : null;
    }

    /// Thème choisi dans Mon compte (seulement avec un compte, 07/11) : enregistré, puis l'app relancée sur Mon compte
    /// (ses pages sont construites une fois, dans leurs couleurs ; la nouvelle copie attend que celle-ci soit partie,
    /// App.OnLaunched). Relance impossible : le thème est pris au prochain lancement.
    private void ChooseTheme(AppTheme theme)
    {
        if (theme == Theme || _account.Session is null) return;
        _app.Settings.Theme = ThemePalette.Key(theme);
        _app.Settings.Save();
        if (_photos) return;
        RelaunchForTheme();
    }

    private bool _themeRelaunch;

    /// Connexion ou déconnexion qui change le thème affiché (sans compte : Noir ; connecté : le thème choisi) : l'app
    /// relancée sur Mon compte, une fois la sauvegarde en ligne au repos (jamais pendant une lecture, un envoi ou la
    /// question « ce PC ou le compte »).
    private void ThemeFollowsAccount()
    {
        if (_photos || _quitting || _themeRelaunch || !ThemeChangedByAccount()) return;
        _themeRelaunch = true;
        _root.DispatcherQueue.TryEnqueue(async () =>
        {
            await Task.Delay(800);
            _themeRelaunch = false;
            if (!_quitting && ThemeChangedByAccount()) RelaunchForTheme();
        });
    }

    private bool ThemeChangedByAccount() =>
        ThemePalette.Shown(_app.Settings.Theme, _account.Session is not null) != Theme
        && _account.Backup?.Status is not (Services.AccountBackupWin.State.Checking or Services.AccountBackupWin.State.Saving
                                           or Services.AccountBackupWin.State.Choice);

    private void RelaunchForTheme()
    {
        try
        {
            if (Environment.ProcessPath is not { } exe) return;
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(exe, "--theme-relaunch") { UseShellExecute = false });
        }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            AppLog.Write("THEME", "relance impossible : " + e.GetType().Name);
            return;
        }
        Quit();
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
        if (!main) _macros.Back();
        _main.Visibility = main && !_macros.Editing ? Visibility.Visible : Visibility.Collapsed;
        _welcome.Visibility = main ? Visibility.Collapsed : Visibility.Visible;
        if (main)
        {
            RenderSidebar();
            RenderPage();
            RenderNotices();
            UpdateTooltip();
            ShowGuideIfNeverSeen();
        }
        else
        {
            _welcomeShown = true;
            ShowWelcomePorts();
        }
    }

    /// Mode photos de la CI : une page donnée (« general », « playlist », « custom », « recherche »…).
    public void ShowPage(string page)
    {
        // « guide », « guide-1 »… « guide-4 » : le guide posé sur la page Général (« Bienvenue », puis une partie).
        CloseGuide();
        if (page.StartsWith("guide", StringComparison.Ordinal))
        {
            ShowPage("general");
            ShowGuide(plain: false, page: int.TryParse(page.AsSpan(page.IndexOf('-') + 1), out var part) ? part : 0);
            return;
        }
        // « accueil » : la page d'accueil (loopMIDI à installer, 08/11) ; les autres pages la cachent.
        if (page == "accueil")
        {
            _main.Visibility = Visibility.Collapsed;
            _welcome.Visibility = Visibility.Visible;
            ShowWelcomePorts();
            return;
        }
        _welcome.Visibility = Visibility.Collapsed;
        _main.Visibility = Visibility.Visible;
        _query = "";
        _keySearch = null;
        _search.Text = "";
        _macros.Back();
        switch (page)
        {
            case "custom": _kind = PageKind.Custom; break;
            case "aide": _kind = PageKind.Help; _help.ShowScreen("aide"); break;
            case "aide-ecrire": _kind = PageKind.Help; _help.ShowScreen("ecrire"); break;
            case "aide-messages": _kind = PageKind.Help; _help.ShowScreen("messages"); break;
            case "aide-fil": _kind = PageKind.Help; _help.ShowScreen("fil"); break;
            case "compte": _kind = PageKind.Account; break;
            case "communaute": _kind = PageKind.Community; _community.Demo(detail: false); break;
            case "communaute-fiche": _kind = PageKind.Community; _community.Demo(detail: true); break;
            case "communaute-abonnements": _kind = PageKind.Community; _community.DemoScreen("abonnements"); break;
            case "communaute-personne": _kind = PageKind.Community; _community.DemoScreen("personne"); break;
            case "communaute-note": _kind = PageKind.Community; _community.DemoScreen("note"); break;
            case "trouver": _kind = PageKind.Find; _findTyping = false; break;
            case "recherche":
                _kind = PageKind.Find;
                _findTyping = true;
                _query = "Zoom";
                _search.Text = _query;
                break;
            case "macros": _kind = PageKind.Macros; break;
            case "macros-createur":
                _kind = PageKind.Macros;
                _macros.OpenDemo(_demoMacro);
                return;
            default:
                _kind = PageKind.Section;
                _section = Enum.GetValues<FlSection>().FirstOrDefault(s => s.Raw().Equals(page, StringComparison.OrdinalIgnoreCase));
                break;
        }
        RenderSidebar();
        RenderPage();
        UpdateAccountButton();
    }

    // ---------- Barre de gauche ----------

    private void BuildMain()
    {
        // Maquette « Minimal » (20/11) : les menus en haut (sous la barre de titre), puis la colonne des pages de
        // « Raccourcis » (seulement dans cette partie) et la page.
        _main.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        _main.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        _main.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        _main.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        // 20/11 (vidéo : « beaucoup de choses oubliées ») : les menus sont DANS la barre de titre (_navHost, posé sur
        // la fenêtre, aussi au-dessus du créateur) ; ici, seulement la place de la barre de titre.
        _navHost = new Border
        {
            Child = _navBar,
            Height = TitleBarHeight,
            VerticalAlignment = VerticalAlignment.Top,
            HorizontalAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(ReadableInset, 0, 16, 0),
            Background = Brush(Colors.Transparent),
        };
        var titleSpace = new Border { Height = TitleBarHeight - 8 };
        Grid.SetColumnSpan(titleSpace, 2);
        _main.Children.Add(titleSpace);

        // La barre de gauche est construite dans ses couleurs : noire sous Orange (maquette du 04/11), comme le Mac.
        var inverted = Inverted();
        // Recherche : une capsule claire, la loupe, le champ sans cadre, le clavier (chercher avec ses touches).
        foreach (var key in new[] { "TextControlBackground", "TextControlBackgroundPointerOver", "TextControlBackgroundFocused",
                                    "TextControlBorderBrush", "TextControlBorderBrushPointerOver", "TextControlBorderBrushFocused" })
            _search.Resources[key] = Brush(Colors.Transparent);
        _search.Resources["TextControlForeground"] = Brush(Text);
        _search.Resources["TextControlForegroundFocused"] = Brush(Text);
        _search.Resources["TextControlForegroundPointerOver"] = Brush(Text);
        _search.Resources["TextControlPlaceholderForeground"] = Brush(Secondary);
        _search.Resources["TextControlPlaceholderForegroundFocused"] = Brush(Secondary);
        // Vidéo du 04/11 (Mac : « quand on clique dans la barre de recherche, la barre et le mot rechercher se décalent… la
        // barre blanche pas bleue ») : rien ne bouge au clic (pas de trait plus épais quand le champ a la main), le texte
        // reste blanc, la sélection grise, jamais de bleu.
        _search.Resources["TextControlBorderThemeThicknessFocused"] = new Thickness(0);
        _search.Resources["TextControlBorderThemeThickness"] = new Thickness(0);
        _search.SelectionHighlightColor = Brush(Tertiary);
        _search.Resources["TextControlPlaceholderForegroundPointerOver"] = Brush(Secondary);
        _search.BorderThickness = new Thickness(0);
        _search.Background = Brush(Colors.Transparent);
        _search.PlaceholderText = Loc.T("Tape son nom");
        _search.FontSize = 18;
        _search.Padding = new Thickness(0, 6, 4, 4);
        _search.MinHeight = 30;
        _search.VerticalAlignment = VerticalAlignment.Center;
        AutomationProperties.SetName(_search, Loc.T("Tape son nom"));
        _search.TextChanged += (_, _) =>
        {
            var text = _search.Text;
            if (text == _query) return;
            var cleared = (text.Length == 0) != (_query.Length == 0);
            _query = text;
            if (cleared) UpdateFindField();               // × apparaît ou disparaît (la case garde la main)
            if (_kind == PageKind.Find) RenderFindResults();
        };

        // 16/11 (maquette « plus lisible ») : « fl shortcuts. » en haut, puis les parties ; plus de recherche ici.
        var sidebarStack = new Grid { RowSpacing = 0 };
        sidebarStack.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        sidebarStack.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        var groupsScroll = new ScrollViewer
        {
            Content = _sidebarGroups,
            VerticalScrollBarVisibility = ScrollBarVisibility.Hidden,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        };
        Grid.SetRow(groupsScroll, 1);
        sidebarStack.Children.Add(groupsScroll);
        // Les pages de FL à gauche de « Raccourcis » (maquette « Minimal »), du fond de la page.
        var sidebar = new Border
        {
            Child = sidebarStack,
            Width = 200 + ReadableInset,
            Padding = new Thickness(ReadableInset, 40, 0, 24),
            Visibility = Visibility.Collapsed,
        };
        _subnav = sidebar;
        inverted.Dispose();
        Grid.SetRow(sidebar, 1);
        _main.Children.Add(sidebar);

        // Page : en-tête (titre, capsule) sous la barre de titre, bandeaux, puis les cartes qui défilent.
        var page = new Grid { RowSpacing = 6 };
        page.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        page.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        page.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        // 16/11 (maquette « plus lisible ») : le titre et son point carré, un trait fin ; à droite, les boutons de la
        // page. Plus de « CLIQUE SUR UNE TOUCHE POUR LA CHANGER » dessous (16/11, « toutes fioritures tu les enlèves »)
        // ni de cadre du compte en haut (Mon compte est sous « Plus »).
        var header = new Grid { MinHeight = 72, Padding = new Thickness(0, 0, 0, 24) };
        ToolTipService.SetToolTip(_titleBack, Loc.T("Revenir à la Communauté"));
        AutomationProperties.SetName(_titleBack, Loc.T("Revenir"));
        _titleBack.Click += (_, _) => _community.LeavePerson();
        // Direction A (17/11) : le surtitre, puis le très grand titre (Inter Display, serré) qui rétrécit plutôt que de
        // se couper (« Lecture et enregistrement ») ; trait d'encre dessous.
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        _title.TextWrapping = TextWrapping.NoWrap;
        _title.LineStackingStrategy = LineStackingStrategy.BlockLineHeight;
        var titleFit = new Viewbox
        {
            Stretch = Stretch.Uniform,
            StretchDirection = StretchDirection.DownOnly,
            HorizontalAlignment = HorizontalAlignment.Left,
            Child = _title,
        };
        // Une grille (pas une pile horizontale) : la largeur du titre est bornée, la Viewbox peut le rétrécir ; la
        // flèche ← (page d'une personne) seulement devant le titre, le surtitre reste au bord de la page.
        var titleRow = new Grid { VerticalAlignment = VerticalAlignment.Bottom };
        titleRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        titleRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        _titleBack.VerticalAlignment = VerticalAlignment.Center;
        // L'écart seulement quand la flèche est là : sinon le titre part du bord de la liste.
        _titleBack.Margin = new Thickness(0, 0, 14, 0);
        titleRow.Children.Add(_titleBack);
        Grid.SetColumn(titleFit, 1);
        titleRow.Children.Add(titleFit);
        _eyebrow.Visibility = Visibility.Collapsed;          // plus de surtitre numéroté (maquette « Minimal »)
        var titleStack = new StackPanel { Spacing = 14, VerticalAlignment = VerticalAlignment.Bottom, Children = { _eyebrow, _findSteps, titleRow } };
        header.Children.Add(titleStack);
        var right = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 12,
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(12, 0, 0, 4),
            Children = { _headerAction },
        };
        Grid.SetColumn(right, 1);
        header.Children.Add(right);
        _titleRule = Rule(Text);
        _titleRule.VerticalAlignment = VerticalAlignment.Bottom;
        _titleRule.Margin = new Thickness(0, 0, 0, -24);       // sous la marge de l'en-tête, comme la maquette
        Grid.SetColumnSpan(_titleRule, 2);
        header.Children.Add(_titleRule);
        var headerHost = _headerHost;
        headerHost.Margin = new Thickness(ReadableInset, 28, ReadableInset, 4);
        headerHost.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MaxWidth = ReadableMaxWidth });
        headerHost.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        headerHost.Children.Add(header);
        page.Children.Add(headerHost);
        Grid.SetRow(_notices, 1);
        page.Children.Add(_notices);
        Grid.SetRow(_scroll, 2);
        page.Children.Add(_scroll);
        Grid.SetRow(_above, 1);
        Grid.SetRowSpan(_above, 2);
        page.Children.Add(_above);
        _scroll.SizeChanged += (_, e) =>
        {
            var columns = e.NewSize.Width - 52 >= TwoColumnWidth ? 2 : 1;
            if (columns == _columns) return;
            _columns = columns;
            RenderPage();
        };
        Grid.SetColumn(page, 1);
        Grid.SetRow(page, 1);
        _main.Children.Add(page);
    }

    private void Choose(PageKind kind, FlSection section)
    {
        // Un menu du haut cliqué dans le créateur : il se referme d'abord (comme le Mac).
        if (_macros.Editing) _macros.Back();
        if (kind != PageKind.Community) _community.Leave();
        if (kind != PageKind.Find && _keyListening) StopKeySearch();
        _kind = kind;
        _section = section;
        OpenPart(kind);
        RenderSidebar();
        RenderPage();
        UpdateAccountButton();
        _scroll.ChangeView(null, 0, null, disableAnimation: true);
    }

    // ---------- Recherche avec une touche ----------

    /// La grande case de « Trouver un raccourci » attend les touches (Échap annule).
    private void StartKeySearch()
    {
        _keyListening = true;
        _findTyping = false;
        _app.SetRecording(true);
        UpdateFindField();
        _findKey.Focus(FocusState.Programmatic);
    }

    private void StopKeySearch()
    {
        _keyListening = false;
        _app.SetRecording(false);
        UpdateFindField();
    }

    /// Touches appuyées pendant la recherche par raccourci (Échap annule) ; les autres touches suivent leur cours.
    private void OnRootKey(object sender, KeyRoutedEventArgs e)
    {
        if (GuideKey(e)) return;
        if (e.Key == Windows.System.VirtualKey.Escape && _above.Visibility == Visibility.Visible && _community.CloseAbove())
        {
            e.Handled = true;
            return;
        }
        var vk = (ushort)e.Key;
        if (Vk.IsModifier(vk)) return;
        var combo = CurrentCombo(vk);
        // Alt+F4 garde son rôle.
        if (combo.Alt && vk == 0x73) return;
        // Maquette « Minimal » (20/11) : une ligne ou l'étape 3 de « Trouver » attend une touche.
        if (MinimalKey(e, combo)) return;
        if (!_keyListening) return;
        e.Handled = true;
        if (e.Key == Windows.System.VirtualKey.Escape && !combo.HasModifiers)
        {
            _keySearch = null;                              // Échap : la case se vide et écoute encore
            RenderPage();
            return;
        }
        if (!combo.IsValidKey) return;
        _keySearch = combo;                                 // elle écoute encore : une autre touche remplace celle-ci
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
        switch (_app.Status)
        {
            case StatusKind.Paused:
                _notices.Children.Add(Notice("warning", Orange, Loc.T("En pause"),
                    Loc.T("Reprendre"), _app.Toggle));
                break;
            case StatusKind.Elevated:
                _notices.Children.Add(Notice("warning", Red, Loc.T(_app.StatusText), null, null));
                break;
            case StatusKind.Unrecognized:
                _notices.Children.Add(Notice("warning", Red, Loc.T(_app.StatusTitle) + " : " + Loc.T(_app.StatusText), null, null));
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
        // Style suisse : bandeau noir au cadre fin, un trait de sa couleur à gauche (comme le Mac).
        return new Border
        {
            Child = new Border
            {
                Child = grid,
                Padding = new Thickness(14, 8, 8, 8),
                BorderBrush = Brush(tint),
                BorderThickness = new Thickness(2, 0, 0, 0),
            },
            Background = Brush(MacLook.WindowColor),
            BorderBrush = Brush(LineColor),
            BorderThickness = new Thickness(1),
        };
    }

    /// Titre de la page (direction A du 17/11, comme le Mac) : son surtitre numéroté, puis le titre tel quel, très grand
    /// (« Appuie sur / un raccourci. » sur deux lignes).
    /// 20/11 (maquette « Minimal », comme le Mac) : le titre en 32 demi-gras ; « Trouver » : ses trois étapes à la place.
    /// En-tête de la page (titre, bouton à droite) : caché sur Mon compte et la Communauté sans compte (maquette).
    private readonly Grid _headerHost = new();

    /// `text` vide : pas de titre ni d'en-tête (maquette « Minimal » : Compte, Communauté sans compte).
    private void SetTitle(string text)
    {
        _headerHost.Visibility = text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        var find = _kind == PageKind.Find;
        _eyebrow.Text = Eyebrow(_kind).ToUpper(System.Globalization.CultureInfo.CurrentCulture);
        _title.FontSize = 32;
        _title.LineHeight = 36;
        _title.CharacterSpacing = -20;
        _title.FontWeight = Microsoft.UI.Text.FontWeights.SemiBold;
        _title.Text = text;
        _title.Visibility = find ? Visibility.Collapsed : Visibility.Visible;
        _findSteps.Visibility = find ? Visibility.Visible : Visibility.Collapsed;
        if (find) UpdateFindSteps();
    }

    /// Étapes de « Trouver » : 1 Touche, 2 Action (ce qu'elle fait est affiché), 3 Nouvelle touche.
    private void UpdateFindSteps()
    {
        var now = _findDone is not null ? 4 : _findEditing is not null ? 3 : (_findTyping ? _query.Trim().Length > 0 : _keySearch is not null) ? 2 : 1;
        _findSteps.Children.Clear();
        var names = new[] { Loc.T("Touche"), Loc.T("Action"), Loc.T("Nouvelle touche") };
        for (var i = 0; i < names.Length; i++)
        {
            var n = i + 1;
            // Maquette : l'étape en cours, numéro rouge et nom à l'encre en demi-gras ; passées en gris ; suivantes pâles.
            var color = n == now ? Text : n < now ? Secondary : Tertiary;
            var step = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            step.Children.Add(Label(n.ToString(System.Globalization.CultureInfo.InvariantCulture), 13, n == now ? Red : color, semibold: n == now));
            step.Children.Add(Label(names[i], 13, color, semibold: n == now));
            _findSteps.Children.Add(step);
        }
        _findSteps.Margin = new Thickness(0, 28, 0, 0);
    }

    /// Le compte en haut à droite (maquette du 05/11, comme le Mac) : cadre de 2 points à l'encre, plein du fond de la
    /// page (la grille de Papier ne passe pas dedans), le rond de la photo ou de l'initiale, puis le pseudo ; sans
    /// compte, « Se connecter ». Survolé : plein d'encre. Il ouvre « Modifier le profil » sur la page Mon compte.
    private void UpdateAccountButton()
    {
        var session = _account.Session;
        var help = session is not null && _kind == PageKind.Account ? Loc.T("Modifier le profil") : Loc.T("Mon compte");
        FrameworkElement Face(bool hovered)
        {
            var ink = hovered ? MacLook.WindowColor : Text;
            FrameworkElement round = session is not null
                ? AccountPage.Avatar(_account.MyPhoto, session.Username, 30)
                : new Border
                {
                    Width = 30, Height = 30, CornerRadius = new CornerRadius(15),
                    BorderBrush = Brush(ink), BorderThickness = new Thickness(1.5),
                    Child = new FontIcon
                    {
                        Glyph = "\uE77B",
                        FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"),
                        FontSize = 13,
                        Foreground = Brush(ink),
                    },
                };
            return new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 10,
                Children = { round, Label(session?.Username ?? Loc.T("Se connecter"), 14, ink, bold: true) },
            };
        }
        var button = new Button
        {
            Style = PlainButton,
            Height = 40,
            Padding = new Thickness(5, 0, 14, 0),
            HorizontalContentAlignment = HorizontalAlignment.Left,
            VerticalContentAlignment = VerticalAlignment.Center,
            Content = Face(false),
            Background = Brush(MacLook.WindowColor),
            BorderBrush = Brush(Text),
            BorderThickness = new Thickness(2),
        };
        button.PointerEntered += (_, _) => { button.Background = Brush(MacLook.Text); button.Content = Face(true); };
        button.PointerExited += (_, _) => { button.Background = Brush(MacLook.WindowColor); button.Content = Face(false); };
        button.Click += (_, _) =>
        {
            if (_account.Session is not null && _kind == PageKind.Account) _account.EditProfile();
            else Choose(PageKind.Account, _section);
        };
        ToolTipService.SetToolTip(button, help);
        AutomationProperties.SetName(button, Loc.T("Mon compte"));
        _accountSlot.Child = button;
    }

    // ---------- Pages ----------

    /// La fiche ou « Partager » de la Communauté, posés au-dessus de la page ; rien sur les autres pages.
    private void UpdateAbove()
    {
        var card = _kind == PageKind.Community ? _community.Above() : null;
        _above.Children.Clear();
        if (card is null)
        {
            _above.Visibility = Visibility.Collapsed;
            return;
        }
        _above.Background = Brush(Color.FromArgb(0x8C, 0, 0, 0));
        _above.Children.Add(card);
        _above.Visibility = Visibility.Visible;
    }

    private void RenderPage()
    {
        if (!_app.Onboarded) return;
        UpdateAbove();
        var (rows, others) = _app.Catalog;
        _capsule.Children.Clear();
        _capsuleBorder.Visibility = Visibility.Collapsed;
        _headerAction.Content = null;
        _titleBack.Visibility = Visibility.Collapsed;
        switch (_kind)
        {
            case PageKind.Find:
                // 16/11 (maquette « plus lisible ») : « appuie sur un raccourci », la grande case et ce qu'elle trouve.
                SetTitle(Loc.T("Appuie sur un raccourci"));
                SetTitleRule(false);
                _scroll.Content = FindPage();
                UpdateFindField();
                RenderFindResults();
                // Maquette « Minimal » : la case écoute dès l'ouverture.
                if (!_keyListening && !_findTyping && _findEditing is null && _findDone is null) StartKeySearch();
                return;
            case PageKind.Macros:
                SetTitle(Loc.T("Macros"));
                SetTitleRule(true);
                _headerAction.Content = _macros.HeaderActions();
                _scroll.Content = _macros.ListContent(_columns);
                return;
            case PageKind.Community:
                // 11/11 : sur la page d'une personne, son pseudo à la place de « communauté. », la flèche pour revenir.
                // Sans compte (maquette, comme le Mac) : pas de titre, seulement « Connecte-toi pour voir la Communauté. ».
                SetTitle(_account.Session is null && !_photos ? "" : _community.PersonName ?? Loc.T("Communauté"));
                SetTitleRule(true);
                if (_community.PersonName is not null) _titleBack.Visibility = Visibility.Visible;
                _scroll.Content = _community.Content(_columns);
                _headerAction.Content = _community.HeaderShare();
                return;
            case PageKind.Account:
                // Maquette « Minimal » (comme le Mac) : pas de titre, la page commence par la photo ou « Connexion ».
                SetTitle("");
                SetTitleRule(true);
                // Sans compte, la connexion seule (07/11 au soir : plus la carte des thèmes) ; connecté, le thème est
                // sous le profil.
                _scroll.Content = _account.Content(_columns);
                return;
            case PageKind.Help:
                SetTitle(_help.Title);
                SetTitleRule(true);
                _scroll.Content = _help.Content(_columns);
                // 20/11 (maquette « Minimal », comme le Mac) : « Écrire à l'équipe » en haut de la page.
                _headerAction.Content = _help.HeaderWrite();
                return;
            case PageKind.Custom:
            {
                SetTitle(Loc.T("Mes raccourcis"));
                // 05/11 (« juste action, page, puis raccourci, avec le bouton réinitialiser derrière ») : une seule liste
                // courte, comme le Mac ; lignes lisibles du 16/11.
                var changed = MyShortcuts.Changed(rows);
                var created = MyShortcuts.Created(others, _app.Starters);
                SetTitleRule(true);
                if (changed.Count == 0 && created.Count == 0)
                {
                    var none = Paragraph(Loc.T("Aucun raccourci changé."), 16, Secondary);
                    none.Margin = new Thickness(0, 24, 0, 0);
                    _scroll.Content = Readable(none);
                    return;
                }
                // Maquette « Minimal » : un trait d'encre, puis les lignes, la page sous le nom.
                var list = new StackPanel { Children = { new Rectangle { Height = 2, Fill = Brush(Text), Margin = new Thickness(0, 8, 0, 0) } } };
                foreach (var r in changed) list.Children.Add(CatalogLine(r, FindDetail(r)));
                foreach (var c in created) list.Children.Add(CustomLine(c, Loc.T("Créé par toi")));
                _scroll.Content = Readable(list);
                return;
            }
            default:
            {
                SetTitle(_section.Title());
                SetTitleRule(true);
                // 16/11 (maquette) : chaque groupe de FL avec son nom à gauche, puis les actions en plus.
                var mine = rows.Where(r => r.Entry.Section == _section).ToList();
                var groups = CatalogGroups.Cards(_section, mine.Where(r => r.Entry.IsNative), r => r.Entry)
                    .Select(c => (c.Title, c.Rows.Select(r => CatalogLine(r)).ToList())).ToList();
                var extras = mine.Where(r => !r.Entry.IsNative).ToList();
                if (extras.Count > 0) groups.Add((Loc.T("Actions en plus"), extras.Select(r => CatalogLine(r)).ToList()));
                ShowGroups(groups);
                return;
            }
        }
    }

    /// Page vide, comme celle du Mac (08/11, « la page quand tu n'as pas de raccourci n'est pas la même ») : au milieu de
    /// la page, l'icône creuse en gris, le titre en gras gris, une phrase grise dessous ; plus de carré de couleur.
    private void ShowEmpty(string icon, string title, string text)
    {
        var stack = new StackPanel { Spacing = 10, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, MaxWidth = 440 };
        var mark = Icon(icon, 34, Tertiary);
        mark.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Children.Add(mark);
        var heading = Label(title, 22, Secondary, bold: true);
        heading.HorizontalAlignment = HorizontalAlignment.Center;
        heading.Margin = new Thickness(0, 6, 0, 0);
        stack.Children.Add(heading);
        if (text.Length > 0)
        {
            var body = Paragraph(text, 12.5, Secondary);
            body.TextAlignment = TextAlignment.Center;
            stack.Children.Add(body);
        }
        _scroll.Content = new Grid { MinHeight = 420, Padding = new Thickness(24), Children = { stack } };
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
    private Button _toastAction = null!;
    private TextBlock _toastActionLabel = null!;
    private Action? _toastRun;
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
            CornerRadius = new CornerRadius(0),
        };
        _toastUndo.Click += (_, _) =>
        {
            _undo?.Invoke();
            HideToast();
        };
        _toastActionLabel = Label("", 13, Link, semibold: true);
        _toastAction = new Button
        {
            Style = PlainButton,
            Content = _toastActionLabel,
            HorizontalAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(6, 2, 6, 2),
            CornerRadius = new CornerRadius(0),
            Visibility = Visibility.Collapsed,
        };
        _toastAction.Click += (_, _) =>
        {
            var run = _toastRun;
            HideToast();
            run?.Invoke();
        };
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        row.Children.Add(_toastText);
        row.Children.Add(_toastUndo);
        row.Children.Add(_toastAction);
        _toast = new Border
        {
            Child = row,
            Padding = new Thickness(18, 10, 12, 10),
            CornerRadius = new CornerRadius(0),
            Background = Brush(Rgb(0x2C, 0x2C, 0x2E)),
            BorderBrush = Brush(LineColor),
            BorderThickness = new Thickness(1),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(0, 0, 0, 24),
            Visibility = Visibility.Collapsed,
        };
    }

    /// Le petit message avec un bouton de plus (« Noter » après un ajout de la Communauté, 11/11).
    private void ShowToastWithAction(string message, Action? undo, string label, Action action)
    {
        ShowToast(message, undo);
        _toastActionLabel.Text = label;
        _toastRun = action;
        _toastAction.Visibility = Visibility.Visible;
        AutomationProperties.SetName(_toastAction, label);
        _toastTimer!.Interval = TimeSpan.FromSeconds(6);
    }

    private void ShowToast(string message, Action? undo = null)
    {
        _toastText.Text = message;
        _undo = undo;
        _toastRun = null;
        _toastAction.Visibility = Visibility.Collapsed;
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
