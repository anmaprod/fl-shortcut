// Organiser : FL mis devant et ses touches (Alt+↑, Alt+←, Alt+Suppr, Ctrl+S, Entrée) envoyées à FL seul, comme le
// ferait l'utilisateur. Rien ne part si FL n'est pas au premier plan (WIN-03, comme les raccourcis). Les titres des
// fenêtres de FL sont lus pour retrouver le projet ouvert : jamais l'écran, jamais journalisés.
// Miroir des aides « live » de Sources/FLShortcut/OrganizerWindow.swift.
using System.Text;
using FLShortcut.App.Native;
using FLShortcut.Core;

namespace FLShortcut.App.Services;

internal static class FlControl
{
    internal sealed record Window(IntPtr Handle, string Title, int Width, int Height);

    /// FL au premier plan d'abord, sinon le premier FL ouvert.
    public static FlProcessInfo? Process() => FlPresence.Foreground() ?? FlPresence.RunningInstance();

    public static bool InFront(uint pid) => pid != 0 && FlPresence.ForegroundPid() == pid;

    /// Fenêtres visibles de FL (au plus 40), avec leur titre et leur taille.
    public static List<Window> Windows(uint pid)
    {
        var out_ = new List<Window>();
        Win32.EnumWindows((hwnd, _) =>
        {
            Win32.GetWindowThreadProcessId(hwnd, out var owner);
            if (owner != pid || !Win32.IsWindowVisible(hwnd)) return true;
            var length = Win32.GetWindowTextLengthW(hwnd);
            var text = new StringBuilder(Math.Clamp(length + 1, 1, 1024));
            Win32.GetWindowTextW(hwnd, text, text.Capacity);
            Win32.GetWindowRect(hwnd, out var r);
            out_.Add(new Window(hwnd, text.ToString(), r.Right - r.Left, r.Bottom - r.Top));
            return out_.Count < 40;
        }, IntPtr.Zero);
        return out_;
    }

    /// La fenêtre principale de FL : la plus grande, titrée, sans propriétaire.
    public static IntPtr MainWindow(uint pid) => Windows(pid)
        .Where(w => w.Title.Length > 0 && Win32.GetWindow(w.Handle, Win32.GW_OWNER) == IntPtr.Zero)
        .OrderByDescending(w => (long)w.Width * w.Height)
        .Select(w => w.Handle)
        .FirstOrDefault();

    /// FL mis devant (1 seconde au plus) ; faux s'il n'a pas pu passer au premier plan.
    public static bool BringForward(uint pid)
    {
        if (InFront(pid)) return true;
        var main = MainWindow(pid);
        if (main == IntPtr.Zero) return false;
        if (Win32.IsIconic(main)) Win32.ShowWindow(main, Win32.SW_RESTORE);
        // Une touche neutre d'abord : Windows laisse alors l'appli mettre une autre fenêtre devant.
        Injector.SendMask();
        Win32.SetForegroundWindow(main);
        for (var i = 0; i < 10 && !InFront(pid); i++) Thread.Sleep(100);
        return InFront(pid);
    }

    /// Une combinaison envoyée à FL seul : faux si FL n'est plus devant.
    public static bool Send(uint pid, KeyCombo combo) => InFront(pid) && Injector.Send(combo, Physical());

    public static bool EscapePressed() => (Win32.GetAsyncKeyState(Vk.Escape) & 0x8000) != 0;

    /// Les touches de modification vraiment enfoncées : relâchées le temps de la combinaison, puis remises.
    private static ModifierTracker Physical()
    {
        var tracker = new ModifierTracker();
        foreach (var vk in new[] { Vk.LControl, Vk.RControl, Vk.LMenu, Vk.RMenu, Vk.LShift, Vk.RShift, Vk.LWin, Vk.RWin })
        {
            if ((Win32.GetAsyncKeyState(vk) & 0x8000) != 0) tracker.Observe(vk, true);
        }
        return tracker;
    }
}
