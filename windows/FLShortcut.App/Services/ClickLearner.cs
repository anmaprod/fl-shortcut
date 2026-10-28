// « Montrer dans FL… » (créateur de macros) : FL est mis devant, puis le prochain clic gauche de l'utilisateur dans une
// fenêtre de FL est retenu, relatif à cette fenêtre ou à ce menu (MacroDrafts.LearnedTarget, miroir du Mac). Aucun
// crochet sur la souris : l'état du bouton est lu toutes les 5 ms, seulement le temps d'apprendre (une minute au plus),
// Échap annule. Le clic va à FL comme d'habitude (c'est l'utilisateur qui clique). Journal : le rôle et la taille de la
// fenêtre, jamais un titre.
using FLShortcut.App.Native;
using FLShortcut.Core;
using FLShortcut.Core.Macros;

namespace FLShortcut.App.Services;

internal static class ClickLearner
{
    private const int LeftButton = 0x01;
    private static int _busy;

    /// Lance l'apprentissage (un seul à la fois) ; `done` est appelé sur le fil de l'interface avec la cible, sinon null
    /// et la raison. Faux si un apprentissage est déjà en cours.
    public static bool Start(uint pid, Action<Action> onUi, Action<ClickTarget?, string?> done)
    {
        if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0) return false;
        new Thread(() =>
        {
            (ClickTarget? Target, string? Why) result;
            try { result = Learn(pid); }
            catch (Exception e)
            {
                AppLog.Write("MACRO", "learn crash " + e.GetType().Name);
                result = (null, Loc.T("erreur interne"));
            }
            finally { Volatile.Write(ref _busy, 0); }
            onUi(() => done(result.Target, result.Why));
        }) { IsBackground = true, Name = "FL Shortcuts – apprendre un clic" }.Start();
        return true;
    }

    private static bool Down(int vk) => (Win32.GetAsyncKeyState(vk) & 0x8000) != 0;

    private static (ClickTarget?, string?) Learn(uint pid)
    {
        if (!FlControl.BringForward(pid)) return (null, Loc.T("FL n'a pas pu passer devant : ouvre FL, puis recommence."));
        var deadline = DateTime.UtcNow.AddMinutes(1);
        while (Down(LeftButton) && DateTime.UtcNow < deadline) Thread.Sleep(5);      // le clic sur le bouton lui-même
        // Fenêtres de FL juste avant le clic (un menu peut se fermer dès l'appui) : relues toutes les 50 ms.
        var windows = WindowsFlDriver.Enumerate(pid).Select(w => w.Window).ToList();
        var readAt = DateTime.UtcNow;
        while (DateTime.UtcNow < deadline)
        {
            if (Down(Vk.Escape)) return (null, Loc.T("Annulé."));
            if (Down(LeftButton))
            {
                Win32.GetCursorPos(out var p);
                var hit = Win32.WindowFromPoint(p);
                var root = hit == IntPtr.Zero ? IntPtr.Zero : Win32.GetAncestor(hit, Win32.GA_ROOT);
                Win32.GetWindowThreadProcessId(root, out var owner);
                if (root == IntPtr.Zero || owner != pid || MacroDrafts.LearnedTarget(p.X, p.Y, windows) is not { } target)
                {
                    AppLog.Write("MACRO", "learn: click outside FL");
                    return (null, Loc.T("clic hors de FL : recommence en cliquant dans une fenêtre de FL."));
                }
                var window = windows.First(w => p.X >= w.X && p.X < w.X + w.Width && p.Y >= w.Y && p.Y < w.Y + w.Height);
                AppLog.Write("MACRO", $"learn: click in {window.Role} {window.Width}x{window.Height}");
                return (target, null);
            }
            if ((DateTime.UtcNow - readAt).TotalMilliseconds >= 50)
            {
                windows = WindowsFlDriver.Enumerate(pid).Select(w => w.Window).ToList();
                readAt = DateTime.UtcNow;
            }
            Thread.Sleep(5);
        }
        return (null, Loc.T("aucun clic dans FL pendant une minute : recommence."));
    }
}
