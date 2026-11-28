// Menu du logo (barre des tâches depuis le 21/11 : plus d'icône sous la flèche) comme celui du Mac (20/11, « ça c'est vraiment pas beau du tout ») : comme
// les menus de la maquette « Minimal » (`.menu`) : carte carrée au fond du thème, trait d'encre de 2, lignes de 16 en
// texte normal, survol plein d'encre ; « Ouvrir FL Shortcuts » et « Quitter » en lignes, « Désinstaller » à part en
// gris. Se ferme dès qu'on clique ailleurs ; une fenêtre à la fois. Construit en code.
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

    /// Le fond du thème, comme la carte du menu du Mac (MenuBackground).
    private static Color MenuColor => WindowColor;
    // 28/11 (« trop grosse… reprends la taille d'avant », « tout le menu ») : plus petit, comme le Mac (MenuSize).
    private const double MenuWidth = 220;
    private const double RowHeight = 26;
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
        new Entry("keyboard", Blue, Loc.T("Modifier les raccourcis…"), () => { }),
        new Entry("macros", Purple, Loc.T("Macros…"), () => { }),
        new Entry("organize", Indigo, Loc.T("Organiser…"), () => { }),
        new Entry("trash", Gray, Loc.T("Désinstaller FL Shortcuts…"), () => { }),
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
        var corner = Win32.DWMWCP_DONOTROUND;          // style suisse : coins carrés
        Win32.DwmSetWindowAttribute(_hwnd, Win32.DWMWA_WINDOW_CORNER_PREFERENCE, ref corner, sizeof(int));

        var stack = new StackPanel();
        // En tête (comme le Mac) : le rond de la zone de notification et « FL Shortcuts », sans état ; dessous,
        // seulement ce qui cloche.
        var head = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(12, 11, 12, 9) };
        head.Children.Add(Round(18, Text, MenuColor));
        var name = Label("FL Shortcuts", 14.5, Text, semibold: true);
        name.VerticalAlignment = VerticalAlignment.Center;
        head.Children.Add(name);
        stack.Children.Add(head);
        if (!ok)
        {
            var state = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, Margin = new Thickness(12, 0, 12, 7) };
            state.Children.Add(new Rectangle { Width = 6, Height = 6, Fill = Brush(Red), VerticalAlignment = VerticalAlignment.Center });
            state.Children.Add(Label(status, 11, Secondary));
            stack.Children.Add(state);
        }
        stack.Children.Add(Separator());
        foreach (var entry in entries.Where(e => e.Icon != "trash")) stack.Children.Add(Row(entry.Title, () => Run(entry.Run)));
        stack.Children.Add(Separator());
        stack.Children.Add(Row(Loc.T("Ouvrir FL Shortcuts"), () => Run(open)));
        stack.Children.Add(Row(Loc.T("Quitter"), () => Run(quit)));
        // Comme le Mac (maquette du 28/10) : « Désinstaller FL Shortcuts… » à part, sous un trait, en simple texte gris.
        foreach (var entry in entries.Where(e => e.Icon == "trash"))
        {
            stack.Children.Add(Separator());
            stack.Children.Add(Row(entry.Title, () => Run(entry.Run), size: 11.5, color: Secondary, height: 24));
        }

        _panel = new Border
        {
            Child = stack,
            Padding = new Thickness(0, 0, 0, 4),
            Background = Brush(MenuColor),
            BorderBrush = Brush(Text),
            BorderThickness = new Thickness(2),
            RequestedTheme = MacLook.SurfaceTheme,
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

    /// Le rond de la zone de notification (marque/rond-A-barre-blanc.svg) : un grand cercle décalé en haut à droite,
    /// un jour, puis le rond plein.
    private static Canvas Round(double size, Color ink, Color background)
    {
        var k = size / 1024;
        var canvas = new Canvas { Width = size, Height = size, VerticalAlignment = VerticalAlignment.Center };
        Ellipse Circle(double cx, double cy, double r) => new()
        {
            Width = 2 * r * k, Height = 2 * r * k, Margin = new Thickness((cx - r) * k, (cy - r) * k, 0, 0),
        };
        var ring = Circle(590, 440, 365);
        ring.Stroke = Brush(ink);
        ring.StrokeThickness = 70 * k;
        var gap = Circle(470, 580, 345);
        gap.Fill = Brush(background);
        var dot = Circle(470, 580, 290);
        dot.Fill = Brush(ink);
        canvas.Children.Add(ring);
        canvas.Children.Add(gap);
        canvas.Children.Add(dot);
        AutomationProperties.SetAccessibilityView(canvas, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        return canvas;
    }

    /// Une ligne (20/11, comme `.menu button` de la maquette) : 16 en texte normal, 16 sur les côtés, toute la largeur ;
    /// survolée, pleine d'encre, texte au fond du thème. Son action après la fermeture du menu.
    private static Button Row(string text, Action click, double size = 13, Color? color = null, double height = RowHeight)
    {
        var label = Label(text, size, color ?? Text);
        label.VerticalAlignment = VerticalAlignment.Center;
        label.TextTrimming = TextTrimming.CharacterEllipsis;
        var row = Option(label, click, minHeight: height, padding: new Thickness(12, 0, 12, 0),
                         hover: on => label.Foreground = Brush(on ? WindowColor : color ?? Text));
        row.HorizontalAlignment = HorizontalAlignment.Stretch;
        row.HorizontalContentAlignment = HorizontalAlignment.Left;
        AutomationProperties.SetName(row, text);
        return row;
    }

    private void Run(Action action)
    {
        CloseMenu();
        action();
    }

    /// Trait fin entre deux groupes, comme `.menu .other` de la maquette.
    private static Rectangle Separator() => new()
    {
        Height = 1, Fill = Brush(Faint), Margin = new Thickness(0, 4, 0, 4), IsHitTestVisible = false,
    };

    /// La taille de la fenêtre : celle du panneau.
    private void FitSize()
    {
        var scale = Win32.GetDpiForWindow(_hwnd) / 96.0;
        _panel.Measure(new Windows.Foundation.Size(MenuWidth, double.PositiveInfinity));
        var height = Math.Ceiling(_panel.DesiredSize.Height);
        _window.ResizeClient(new Windows.Graphics.SizeInt32((int)Math.Ceiling(MenuWidth * scale), (int)Math.Ceiling(height * scale)));
    }

    /// Au-dessus du pointeur et centré sur lui (21/11 : juste au-dessus du logo cliqué dans la barre des tâches),
    /// toujours dans la zone de travail de l'écran (barre des tâches en bas, en haut ou sur le côté).
    private void Place()
    {
        Win32.GetCursorPos(out var pt);
        var size = _window.Size;
        var area = DisplayArea.GetFromPoint(new Windows.Graphics.PointInt32(pt.X, pt.Y), DisplayAreaFallback.Nearest).WorkArea;
        var x = Math.Clamp(pt.X - size.Width / 2, area.X, Math.Max(area.X, area.X + area.Width - size.Width));
        var y = Math.Clamp(pt.Y - size.Height, area.Y, Math.Max(area.Y, area.Y + area.Height - size.Height));
        _window.Move(new Windows.Graphics.PointInt32(x, y));
    }
}
