// Icône de la zone de notification (Shell_NotifyIcon) sur la fenêtre principale, sans dépendance tierce. Clic : la
// fenêtre ; clic droit : le menu noir comme celui du Mac (TrayMenu, construit par la fenêtre principale).
using FLShortcut.App.Native;

namespace FLShortcut.App;

internal sealed class TrayIcon : IDisposable
{
    private const uint CallbackMessage = Win32.WM_APP + 10;

    private readonly IntPtr _hwnd;
    private readonly Win32.SubclassProc _proc;
    private readonly IntPtr _icon;
    private readonly bool _ownsIcon;
    private bool _added;

    public event Action? OpenRequested;
    public event Action? MenuRequested;

    public TrayIcon(IntPtr hwnd, string tooltip)
    {
        _hwnd = hwnd;
        _proc = WndProc;
        Win32.SetWindowSubclass(_hwnd, _proc, new UIntPtr(0x464C), UIntPtr.Zero);

        var small = new IntPtr[1];
        var exe = Environment.ProcessPath;
        if (exe is not null && Win32.ExtractIconExW(exe, 0, null, small, 1) > 0 && small[0] != IntPtr.Zero)
        {
            _icon = small[0];
            _ownsIcon = true;
        }
        else
        {
            _icon = Win32.LoadIconW(IntPtr.Zero, Win32.IDI_APPLICATION);
        }

        var data = Data(tooltip);
        _added = Win32.Shell_NotifyIconW(Win32.NIM_ADD, ref data);
    }

    public void SetTooltip(string tooltip)
    {
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
