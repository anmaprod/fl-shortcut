// Touche seule laissée à FL quand il s'en sert (09/11, comme TypingGuard du Mac) : fenêtres de FL (menu, boîte devant)
// et curseur de saisie de Windows (champ de texte qui a la main), relus seulement quand une touche seule lance un
// raccourci. Jamais l'écran, jamais le texte tapé. La règle elle-même : TypingGuardRules (cœur, testée).
using System.Runtime.InteropServices;
using FLShortcut.App.Native;
using FLShortcut.Core;

namespace FLShortcut.App.Services;

internal static class TypingGuard
{
    /// Raison de laisser la touche à FL en ce moment, sinon null (le raccourci est lancé). Jamais d'exception.
    public static TypingGuardRules.Reason? Reason(uint pid)
    {
        try
        {
            var main = FlControl.MainWindow(pid);
            var caret = false;
            if (main != IntPtr.Zero)
            {
                var thread = Win32.GetWindowThreadProcessId(main, out _);
                var info = new Win32.GUITHREADINFO { cbSize = Marshal.SizeOf<Win32.GUITHREADINFO>() };
                if (thread != 0 && Win32.GetGUIThreadInfo(thread, ref info))
                {
                    if ((info.flags & (Win32.GUI_INMENUMODE | Win32.GUI_POPUPMENUMODE)) != 0) return TypingGuardRules.Reason.Menu;
                    caret = info.hwndCaret != IntPtr.Zero;
                }
            }
            var windows = WindowsFlDriver.Enumerate(pid).Select(w => w.Window).ToList();
            return TypingGuardRules.Decide(windows, caret);
        }
        catch
        {
            return null;
        }
    }
}
