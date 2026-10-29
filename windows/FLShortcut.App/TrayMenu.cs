// Menu de l'icône (zone de notification) comme celui du Mac (29/10, « plus de Liquid Glass… fond noir ») : un panneau
// noir plein aux coins arrondis, l'état en haut (point de couleur), une ligne par action (carré de couleur, nom ; au
// survol, pleine de sa couleur, texte en blanc), puis « Ouvrir FL Shortcuts » en bleu et « Quitter » en bas. Se ferme
// dès qu'on clique ailleurs ; une fenêtre à la fois. Construit en code, toujours sombre.
// Une fenêtre faite d'emblée sans barre de titre (AppWindow à la présentation « menu »), le panneau posé dedans
// (DesktopWindowXamlSource) : retirer la barre d'une fenêtre WinUI déjà créée (SetBorderAndTitleBar ou présentation
// « menu ») fait libérer deux fois par le Windows App SDK l'objet d'accessibilité de ses boutons
// (CTitleBarCaptionButtonsFragmentProvider, CI du 29/10 sous page heap) : mémoire abîmée, puis l'appli tombe.
using FLShortcut.App.Native;
using FLShortcut.Core;
using Microsoft.UI;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal sealed class TrayMenu
{
    /// Une ligne du menu : son carré de couleur, son nom, ce qu'elle fait.
    public sealed record Entry(string Icon, Color Tint, string Title, Action Run);

    /// Le noir du menu du Mac (MenuBackground).
    private static readonly Color MenuColor = Rgb(0x1C, 0x1C, 0x1F);
    private const double MenuWidth = 280;
    private const uint WM_ACTIVATE = 0x0006;
    private static readonly UIntPtr SubclassId = new(0x464D);

    private static TrayMenu? _open;
    private readonly AppWindow _window;
    private readonly IntPtr _hwnd;
    private readonly DesktopWindowXamlSource _source;
    private readonly DispatcherQueue _queue;
    private readonly Border _panel;
    private readonly Win32.SubclassProc? _proc;
    private bool _closed;

    /// Le panneau dessiné (photos de la CI).
    public UIElement Content => _panel;

    /// Le menu près du pointeur (au-dessus et à gauche, comme ceux de Windows), devant tout.
    public static void Show(string status, bool ok, IReadOnlyList<Entry> entries, Action open, Action quit)
    {
        _open?.CloseMenu();
        var menu = new TrayMenu(status, ok, entries, open, quit, photo: false);
        _open = menu;
        menu.Place();
        menu.Activate();
        Win32.SetForegroundWindow(menu._hwnd);
    }

    /// Mode photos (CI) : le menu avec des lignes d'exemple ; rien ne s'y passe.
    public static TrayMenu Demo() => new(Loc.T("Relié à FL Studio"), true, new[]
    {
        new Entry("keyboard", Accent, Loc.T("Modifier les raccourcis…"), () => { }),
        new Entry("macros", Purple, Loc.T("Macros…"), () => { }),
        new Entry("organize", Indigo, Loc.T("Organiser…"), () => { }),
    }, () => { }, () => { }, photo: true);

    public void Activate() => _window.Show(true);

    public void Close() => CloseMenu();

    private TrayMenu(string status, bool ok, IReadOnlyList<Entry> entries, Action open, Action quit, bool photo)
    {
        _queue = DispatcherQueue.GetForCurrentThread();
        _window = AppWindow.Create(OverlappedPresenter.CreateForContextMenu());
        _window.Title = "FL Shortcuts";
        _window.IsShownInSwitchers = false;
        _hwnd = Win32Interop.GetWindowFromWindowId(_window.Id);
        var corner = Win32.DWMWCP_ROUND;
        Win32.DwmSetWindowAttribute(_hwnd, Win32.DWMWA_WINDOW_CORNER_PREFERENCE, ref corner, sizeof(int));

        var stack = new StackPanel { Spacing = 2 };
        // L'état, en petit, avec son point de couleur.
        var state = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 7, Margin = new Thickness(12, 8, 12, 8) };
        state.Children.Add(new Ellipse { Width = 7, Height = 7, Fill = Brush(ok ? Green : Orange), VerticalAlignment = VerticalAlignment.Center });
        state.Children.Add(Label(status, 11.5, Secondary));
        stack.Children.Add(state);
        stack.Children.Add(Separator());
        foreach (var entry in entries) stack.Children.Add(Row(entry));
        stack.Children.Add(Separator());

        var footer = new Grid { Margin = new Thickness(0, 2, 0, 0) };
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footer.Children.Add(FooterButton(Loc.T("Ouvrir FL Shortcuts"), Link, open));
        var quitButton = FooterButton(Loc.T("Quitter"), Text, quit);
        Grid.SetColumn(quitButton, 1);
        footer.Children.Add(quitButton);
        stack.Children.Add(footer);

        _panel = new Border
        {
            Child = stack,
            Padding = new Thickness(6),
            Background = Brush(MenuColor),
            BorderBrush = Brush(White(0.10)),
            BorderThickness = new Thickness(1),
            RequestedTheme = ElementTheme.Dark,
            Width = MenuWidth,
        };
        _source = new DesktopWindowXamlSource();
        _source.Initialize(_window.Id);
        _source.SiteBridge.ResizePolicy = Microsoft.UI.Content.ContentSizePolicy.ResizeContentToParentWindow;
        _source.Content = _panel;
        if (!photo)
        {
            // Un clic ailleurs : la fenêtre n'est plus active, le menu se ferme (comme un menu de Windows).
            _proc = WndProc;
            Win32.SetWindowSubclass(_hwnd, _proc, SubclassId, UIntPtr.Zero);
            _panel.KeyDown += (_, e) =>
            {
                if (e.Key == Windows.System.VirtualKey.Escape) CloseMenu();
            };
        }
        FitSize();
    }

    private IntPtr WndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam, UIntPtr id, UIntPtr refData)
    {
        if (msg == WM_ACTIVATE && (wParam.ToInt64() & 0xFFFF) == 0) _queue.TryEnqueue(CloseMenu);
        return Win32.DefSubclassProc(hWnd, msg, wParam, lParam);
    }

    /// Caché tout de suite ; défait au tour suivant (jamais pendant le clic de l'une de ses lignes).
    private void CloseMenu()
    {
        if (_closed) return;
        _closed = true;
        if (_open == this) _open = null;
        _window.Hide();
        _queue.TryEnqueue(() =>
        {
            if (_proc is not null) Win32.RemoveWindowSubclass(_hwnd, _proc, SubclassId);
            _source.Dispose();
            _window.Destroy();
        });
    }

    /// Une ligne : son action après la fermeture du menu (une fenêtre qui s'ouvre passe devant).
    private Button Row(Entry entry)
    {
        var tile = Tile(entry.Icon, entry.Tint, 24);
        var content = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 11 };
        content.Children.Add(tile);
        var title = Label(entry.Title, 13.5);
        title.VerticalAlignment = VerticalAlignment.Center;
        content.Children.Add(title);
        var row = Option(content, entry.Tint, 9, () => Run(entry.Run), minHeight: 40, padding: new Thickness(10, 0, 10, 0),
                         hover: on => SetTileHover(tile, entry.Icon, entry.Tint, on));
        AutomationProperties.SetName(row, entry.Title);
        return row;
    }

    private Button FooterButton(string text, Color color, Action click)
    {
        var button = new Button
        {
            Style = PlainButton,
            HorizontalAlignment = HorizontalAlignment.Left,
            Content = Label(text, 13, color, semibold: color == Link),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(10, 7, 10, 7),
        };
        button.PointerEntered += (_, _) => button.Background = Brush(White(0.08));
        button.PointerExited += (_, _) => button.Background = Brush(Colors.Transparent);
        button.Click += (_, _) => Run(click);
        AutomationProperties.SetName(button, text);
        return button;
    }

    private void Run(Action action)
    {
        CloseMenu();
        action();
    }

    private static Rectangle Separator() => new()
    {
        Height = 1, Fill = Brush(White(0.08)), Margin = new Thickness(10, 4, 10, 4), IsHitTestVisible = false,
    };

    /// La taille de la fenêtre : celle du panneau.
    private void FitSize()
    {
        var scale = Win32.GetDpiForWindow(_hwnd) / 96.0;
        _panel.Measure(new Windows.Foundation.Size(MenuWidth, double.PositiveInfinity));
        var height = Math.Ceiling(_panel.DesiredSize.Height);
        _window.ResizeClient(new Windows.Graphics.SizeInt32((int)Math.Ceiling(MenuWidth * scale), (int)Math.Ceiling(height * scale)));
    }

    /// Au-dessus et à gauche du pointeur, toujours dans la zone de travail de l'écran (barre des tâches en bas, en
    /// haut ou sur le côté).
    private void Place()
    {
        Win32.GetCursorPos(out var pt);
        var size = _window.Size;
        var area = DisplayArea.GetFromPoint(new Windows.Graphics.PointInt32(pt.X, pt.Y), DisplayAreaFallback.Nearest).WorkArea;
        var x = Math.Clamp(pt.X - size.Width, area.X, Math.Max(area.X, area.X + area.Width - size.Width));
        var y = Math.Clamp(pt.Y - size.Height, area.Y, Math.Max(area.Y, area.Y + area.Height - size.Height));
        _window.Move(new Windows.Graphics.PointInt32(x, y));
    }
}
