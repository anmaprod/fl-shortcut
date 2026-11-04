// Icône de la zone de notification (Shell_NotifyIcon) sur la fenêtre principale, sans dépendance tierce. Clic : la
// fenêtre ; clic droit : le menu noir comme celui du Mac (TrayMenu, construit par la fenêtre principale).
// Logo « A » (choisi par le propriétaire le 04/11, à la place du petit clavier), toujours en couleurs : le rond rouge,
// le cercle blanc sur une barre des tâches sombre et noir sur une claire (réglage « mode de Windows », lu dans le
// Registre et suivi quand il change), comme la barre des menus du Mac (MenuBarIcon).
using System.Runtime.InteropServices;
using FLShortcut.App.Native;
using Microsoft.Win32;

namespace FLShortcut.App;

internal sealed class TrayIcon : IDisposable
{
    private const uint CallbackMessage = Win32.WM_APP + 10;
    private const uint WmSettingChange = 0x001A;
    private const int SmCxSmIcon = 49;

    private readonly IntPtr _hwnd;
    private readonly Win32.SubclassProc _proc;
    private IntPtr _icon;
    private bool _ownsIcon;
    private bool? _light;
    private string _tooltip;
    private bool _added;

    public event Action? OpenRequested;
    public event Action? MenuRequested;

    public TrayIcon(IntPtr hwnd, string tooltip)
    {
        _hwnd = hwnd;
        _tooltip = tooltip;
        _proc = WndProc;
        Win32.SetWindowSubclass(_hwnd, _proc, new UIntPtr(0x464C), UIntPtr.Zero);
        LoadIcon();
        var data = Data(tooltip);
        _added = Win32.Shell_NotifyIconW(Win32.NIM_ADD, ref data);
    }

    /// Le logo pour la barre des tâches d'aujourd'hui (claire ou sombre) ; rien ne change s'il est déjà le bon.
    /// Secours : l'icône de l'exécutable, sinon celle de Windows.
    private void LoadIcon()
    {
        var light = TaskbarIsLight();
        if (_light == light && _icon != IntPtr.Zero) return;
        var icon = FromResource(light ? "TrayClaire.ico" : "TraySombre.ico");
        var owns = icon != IntPtr.Zero;
        if (icon == IntPtr.Zero)
        {
            var small = new IntPtr[1];
            var exe = Environment.ProcessPath;
            if (exe is not null && Win32.ExtractIconExW(exe, 0, null, small, 1) > 0 && small[0] != IntPtr.Zero)
            {
                icon = small[0];
                owns = true;
            }
            else icon = Win32.LoadIconW(IntPtr.Zero, Win32.IDI_APPLICATION);
        }
        var (old, oldOwned) = (_icon, _ownsIcon);
        (_icon, _ownsIcon, _light) = (icon, owns, light);
        if (_added)
        {
            var data = Data(_tooltip);
            Win32.Shell_NotifyIconW(Win32.NIM_MODIFY, ref data);
        }
        if (oldOwned && old != IntPtr.Zero) Win32.DestroyIcon(old);
    }

    /// Barre des tâches claire (« Choisir votre mode Windows » : clair) ; sombre si le réglage est absent.
    private static bool TaskbarIsLight()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("SystemUsesLightTheme") is int value && value != 0;
        }
        catch (Exception e) when (e is System.Security.SecurityException or UnauthorizedAccessException or IOException)
        {
            return false;
        }
    }

    /// L'icône `name` embarquée dans l'appli (.ico fait de PNG, scripts/icone.py), à la taille d'une petite icône de
    /// cet écran ; IntPtr.Zero si elle manque.
    private IntPtr FromResource(string name)
    {
        try
        {
            using var stream = typeof(TrayIcon).Assembly.GetManifestResourceStream(name);
            if (stream is null) return IntPtr.Zero;
            var bytes = new byte[stream.Length];
            stream.ReadExactly(bytes);
            var dpi = Win32.GetDpiForWindow(_hwnd);
            var size = GetSystemMetricsForDpi(SmCxSmIcon, dpi == 0 ? 96 : dpi);
            if (size <= 0) size = 16;
            return PngFor(bytes, size) is { } png
                ? CreateIconFromResourceEx(png, (uint)png.Length, true, 0x00030000, size, size, 0) : IntPtr.Zero;
        }
        catch (Exception e) when (e is IOException or ArgumentException or OverflowException)
        {
            return IntPtr.Zero;
        }
    }

    /// Dans un .ico, l'image la plus petite d'au moins `size` pixels (sinon la plus grande).
    private static byte[]? PngFor(byte[] ico, int size)
    {
        if (ico.Length < 6 || BitConverter.ToUInt16(ico, 2) != 1) return null;
        var count = BitConverter.ToUInt16(ico, 4);
        (int Width, int Offset, int Length)? best = null;
        for (var i = 0; i < count && 6 + 16 * (i + 1) <= ico.Length; i++)
        {
            var at = 6 + 16 * i;
            var width = ico[at] == 0 ? 256 : ico[at];
            var length = (int)BitConverter.ToUInt32(ico, at + 8);
            var offset = (int)BitConverter.ToUInt32(ico, at + 12);
            if (offset < 0 || length <= 0 || offset + length > ico.Length) continue;
            var better = best is not { } b
                         || (width >= size && (b.Width < size || width < b.Width))
                         || (b.Width < size && width > b.Width);
            if (better) best = (width, offset, length);
        }
        return best is { } pick ? ico[pick.Offset..(pick.Offset + pick.Length)] : null;
    }

    [DllImport("user32.dll")] private static extern int GetSystemMetricsForDpi(int index, uint dpi);
    [DllImport("user32.dll")]
    private static extern IntPtr CreateIconFromResourceEx(byte[] data, uint size, bool icon, uint version, int cx, int cy, uint flags);

    /// Bulle près de l'icône (Windows 11 : une notification), pour la retrouver : sous « ^ » quand Windows la cache.
    public void Notify(string title, string text)
    {
        if (!_added) return;
        var data = Data("FL Shortcuts");
        data.uFlags |= Win32.NIF_INFO;
        data.szInfoTitle = title.Length > 63 ? title[..63] : title;
        data.szInfo = text.Length > 255 ? text[..255] : text;
        data.dwInfoFlags = Win32.NIIF_INFO;
        Win32.Shell_NotifyIconW(Win32.NIM_MODIFY, ref data);
    }

    public void SetTooltip(string tooltip)
    {
        _tooltip = tooltip;
        if (!_added) return;
        var data = Data(tooltip);
        Win32.Shell_NotifyIconW(Win32.NIM_MODIFY, ref data);
    }

    private Win32.NOTIFYICONDATAW Data(string tooltip) => new()
    {
        cbSize = (uint)System.Runtime.InteropServices.Marshal.SizeOf<Win32.NOTIFYICONDATAW>(),
        hWnd = _hwnd,
        uID = 1,
        uFlags = Win32.NIF_MESSAGE | Win32.NIF_ICON | Win32.NIF_TIP,
        uCallbackMessage = CallbackMessage,
        hIcon = _icon,
        szTip = tooltip.Length > 127 ? tooltip[..127] : tooltip,
        szInfo = "",
        szInfoTitle = "",
    };

    private IntPtr WndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam, UIntPtr id, UIntPtr refData)
    {
        if (msg == CallbackMessage)
        {
            var mouse = (uint)(lParam.ToInt64() & 0xFFFF);
            if (mouse == Win32.WM_LBUTTONUP) OpenRequested?.Invoke();
            else if (mouse is Win32.WM_RBUTTONUP or Win32.WM_CONTEXTMENU) MenuRequested?.Invoke();
            return IntPtr.Zero;
        }
        // Mode clair ou sombre changé dans Windows : le cercle du logo suit la barre des tâches.
        if (msg == WmSettingChange && lParam != IntPtr.Zero && Marshal.PtrToStringUni(lParam) == "ImmersiveColorSet") LoadIcon();
        return Win32.DefSubclassProc(hWnd, msg, wParam, lParam);
    }

    public void Dispose()
    {
        if (_added)
        {
            var data = Data("");
            Win32.Shell_NotifyIconW(Win32.NIM_DELETE, ref data);
            _added = false;
        }
        Win32.RemoveWindowSubclass(_hwnd, _proc, new UIntPtr(0x464C));
        if (_ownsIcon) Win32.DestroyIcon(_icon);
    }
}
