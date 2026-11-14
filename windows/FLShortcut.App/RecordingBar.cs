// Barre « ● Enregistrement » pendant « Enregistrer clics et touches » (09/11, « il n'y a pas la barre d'enregistrement
// et c'est pas pareil que sur mac ») : miroir du RecordingPanel du Mac (MacroClickSequence.swift). Petit panneau en haut
// à droite de l'écran, devant FL, qui ne lui prend jamais le premier plan (WS_EX_NOACTIVATE : un clic dessus n'est pas
// enregistré et ne termine rien tout seul) ; point rouge, « Enregistrement des clics et des touches », ce qui est déjà
// relevé (« 2 clics · 1 touche enregistrés »), Annuler et Terminer. Déplaçable en le tirant.
// Fenêtre faite d'emblée sans barre de titre (présentation « menu », comme TrayMenu : JAMAIS retirer la barre d'une
// fenêtre WinUI déjà créée).
using FLShortcut.App.Native;
using FLShortcut.App.Services;
using FLShortcut.Core;
using Microsoft.UI;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Shapes;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal sealed class RecordingBar
{
    private const uint WM_NCLBUTTONDOWN = 0x00A1;
    private const int HTCAPTION = 2;

    private static RecordingBar? _shown;
    private readonly AppWindow _window;
    private readonly IntPtr _hwnd;
    private readonly DesktopWindowXamlSource _source;
    private readonly DispatcherQueue _queue;
    private readonly DispatcherQueueTimer _timer;
    private readonly Border _panel;
    private readonly TextBlock _detail;
    private bool _closed;

    /// Le panneau dessiné (photos de la CI).
    public UIElement Content => _panel;

    /// Montre la barre (une seule à la fois) ; elle se ferme quand l'enregistrement se termine.
    public static void Show()
    {
        _shown?.Close();
        var bar = new RecordingBar(photo: false);
        _shown = bar;
        bar.Place();
        bar._window.Show(false);                       // jamais activée : FL reste devant
        Win32.SetWindowPos(bar._hwnd, Win32.HWND_TOPMOST, 0, 0, 0, 0,
                           Win32.SWP_NOMOVE | Win32.SWP_NOSIZE | Win32.SWP_NOACTIVATE | Win32.SWP_SHOWWINDOW);
    }

    /// Fin de l'enregistrement (Terminer, Annuler, retour dans FL Shortcuts, limite atteinte).
    public static void Hide()
    {
        _shown?.Close();
        _shown = null;
    }

    /// Mode photos (CI) : la barre avec « 2 clics · 1 touche enregistrés ».
    public static RecordingBar Demo()
    {
        var bar = new RecordingBar(photo: true);
        bar._detail.Text = Detail(3, 1);
        return bar;
    }

    /// Mode photos : la barre montrée puis fermée.
    public void Activate() => _window.Show(true);
    public void Dismiss() => Close();

    private RecordingBar(bool photo)
    {
        _queue = DispatcherQueue.GetForCurrentThread();
        _window = AppWindow.Create(OverlappedPresenter.CreateForContextMenu());
        _window.Title = "FL Shortcuts";
        _window.IsShownInSwitchers = false;
        _hwnd = Win32Interop.GetWindowFromWindowId(_window.Id);
        var corner = Win32.DWMWCP_DONOTROUND;          // style suisse : coins carrés
        Win32.DwmSetWindowAttribute(_hwnd, Win32.DWMWA_WINDOW_CORNER_PREFERENCE, ref corner, sizeof(int));
        if (!photo)
        {
            var ex = Win32.GetWindowLongPtrW(_hwnd, Win32.GWL_EXSTYLE).ToInt64();
            Win32.SetWindowLongPtrW(_hwnd, Win32.GWL_EXSTYLE,
                new IntPtr(ex | Win32.WS_EX_NOACTIVATE | Win32.WS_EX_TOPMOST | Win32.WS_EX_TOOLWINDOW));
        }

        var row = new Grid { ColumnSpacing = 12 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.Children.Add(new Ellipse { Width = 10, Height = 10, Fill = Brush(Red), VerticalAlignment = VerticalAlignment.Center });
        var text = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center, MinWidth = 170 };
        text.Children.Add(Label(Loc.T("Enregistrement des clics et des touches"), 13, Text, semibold: true));
        _detail = Label(Detail(0, 0), 11, Secondary);
        text.Children.Add(_detail);
        Grid.SetColumn(text, 1);
        row.Children.Add(text);
        var cancel = Soft(Loc.T("Annuler"), () => MacroRecorder.Cancel());
        cancel.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(cancel, 2);
        row.Children.Add(cancel);
        var finish = Primary(Loc.T("Terminer"), () => MacroRecorder.Stop());
        finish.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(finish, 3);
        row.Children.Add(finish);

        _panel = new Border
        {
            Child = row,
            Padding = new Thickness(16, 10, 16, 10),
            Background = Brush(WindowColor),
            BorderBrush = Brush(LineColor),
            BorderThickness = new Thickness(1),
            RequestedTheme = SurfaceTheme,
        };
        // Tirée par son fond (pas par ses boutons) : la fenêtre suit, comme le panneau du Mac.
        _panel.PointerPressed += (_, e) =>
        {
            if (photo || e.OriginalSource is not (Border or Grid or StackPanel or TextBlock or Ellipse)) return;
            Win32.ReleaseCapture();
            Win32.SendMessageW(_hwnd, WM_NCLBUTTONDOWN, new IntPtr(HTCAPTION), IntPtr.Zero);
        };
        _source = new DesktopWindowXamlSource();
        _source.Initialize(_window.Id);
        _source.SiteBridge.ResizePolicy = Microsoft.UI.Content.ContentSizePolicy.ResizeContentToParentWindow;
        _source.Content = _panel;
        FitSize();

        _timer = _queue.CreateTimer();
        _timer.Interval = TimeSpan.FromMilliseconds(200);
        _timer.Tick += (_, _) =>
        {
            var detail = Detail(MacroRecorder.Count, MacroRecorder.KeyCount);
            if (_detail.Text != detail) _detail.Text = detail;
            if (!MacroRecorder.Busy) Close();
        };
        if (!photo) _timer.Start();
    }

    /// « 2 clics · 1 touche enregistrés » (mêmes textes que le Mac), ou la consigne tant que rien n'est relevé.
    public static string Detail(int count, int keys)
    {
        if (count <= 0) return Loc.T("Clique et tape dans FL (flèches, raccourcis…), dans l'ordre.");
        var clicks = count - keys;
        var parts = new List<string>();
        if (clicks > 0) parts.Add(clicks == 1 ? Loc.T("1 clic") : Loc.F("%lld clics", clicks));
        if (keys > 0) parts.Add(keys == 1 ? Loc.T("1 touche") : Loc.F("%lld touches", keys));
        return string.Join(" · ", parts) + (count == 1 ? Loc.T(" enregistré") : Loc.T(" enregistrés"));
    }

    private void Close()
    {
        if (_closed) return;
        _closed = true;
        if (_shown == this) _shown = null;
        _timer.Stop();
        _window.Hide();
        _queue.TryEnqueue(() =>
        {
            _source.Dispose();
            _window.Destroy();
        });
    }

    /// La taille de la fenêtre : celle du panneau.
    private void FitSize()
    {
        var scale = Win32.GetDpiForWindow(_hwnd) / 96.0;
        _panel.Measure(new Windows.Foundation.Size(double.PositiveInfinity, double.PositiveInfinity));
        var size = _panel.DesiredSize;
        _window.ResizeClient(new Windows.Graphics.SizeInt32((int)Math.Ceiling(Math.Max(size.Width, 460) * scale),
                                                             (int)Math.Ceiling(size.Height * scale)));
    }

    /// En haut à droite de l'écran principal (zone de travail), comme le panneau du Mac.
    private void Place()
    {
        var area = DisplayArea.Primary.WorkArea;
        var scale = Win32.GetDpiForWindow(_hwnd) / 96.0;
        var size = _window.Size;
        _window.Move(new Windows.Graphics.PointInt32(area.X + area.Width - size.Width - (int)(16 * scale),
                                                     area.Y + (int)(12 * scale)));
    }
}
