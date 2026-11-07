// « Montrer dans FL… » (créateur de macros) : FL est mis devant, puis le prochain clic gauche de l'utilisateur dans une
// fenêtre de FL est retenu, relatif à cette fenêtre ou à ce menu (MacroDrafts.LearnedTarget, miroir du Mac). Comme le
// Mac (demande du 04/11 : « si c'est un bouton il va l'apprendre le bouton en lui même, pas un endroit ») : un bouton
// qui porte un nom est retenu par ce nom, lu sous le clic dans la seule fenêtre de FL au moment du clic ; sinon, avec
// « Retrouver ce bouton s'il bouge », par son image ; sinon par sa place. Aucun crochet sur la souris : l'état du bouton
// est lu toutes les 5 ms, seulement le temps d'apprendre (une minute au plus), Échap annule. Le clic va à FL comme
// d'habitude (c'est l'utilisateur qui clique). Journal : le rôle et la taille de la fenêtre, jamais un titre ni un nom.
using FLShortcut.App.Native;
using FLShortcut.Core;
using FLShortcut.Core.Macros;

namespace FLShortcut.App.Services;

internal static class ClickLearner
{
    private const int LeftButton = 0x01;
    private static int _busy;

    /// Lance l'apprentissage (un seul à la fois) ; `done` est appelé sur le fil de l'interface avec la cible et un mot pour
    /// l'utilisateur, ou null et la raison. `visual` : « Retrouver ce bouton s'il bouge » (son image s'il n'a pas de nom).
    /// Faux si un apprentissage est déjà en cours.
    public static bool Start(uint pid, bool visual, Action<Action> onUi, Action<ClickTarget?, string?> done)
    {
        if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0) return false;
        new Thread(() =>
        {
            (ClickTarget? Target, string? Why) result;
            try { result = Learn(pid, visual); }
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

    private static (ClickTarget?, string?) Learn(uint pid, bool visual)
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
                return Button(target, (IntPtr)window.Id, p.X, p.Y, visual);
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

    /// Clic dans une fenêtre de FL (pas un menu) : le bouton sous lui, par son nom, sinon son image (`visual`), sinon sa
    /// place. La zone autour du clic est copiée tout de suite (avant que FL ne change), lue, puis oubliée.
    private static (ClickTarget?, string?) Button(ClickTarget place, IntPtr window, int x, int y, bool visual)
    {
        if (!MacroDrafts.CanFollow(place) || FlScreen.Around(window, x, y) is not { } shot) return (place, null);
        var named = MacroDrafts.Named(place, FlScreen.NameAt(shot, x, y));
        if (named is ClickTarget.Named n)
        {
            AppLog.Write("MACRO", "learn: button kept by its name");
            return (named, Loc.F("Bouton retenu par son nom « %@ ».", n.Spot.Label.Length > 30 ? n.Spot.Label[..30] + "…" : n.Spot.Label));
        }
        if (!visual) return (place, null);
        var image = MacroDrafts.Visual(place, FlScreen.PatchAt(shot, x, y));
        AppLog.Write("MACRO", image is ClickTarget.Button ? "learn: button kept by its image" : "learn: nothing to recognize, place kept");
        return image is ClickTarget.Button
            ? (image, Loc.T("Bouton retenu à son image."))
            : (place, Loc.T("Rien de reconnaissable ici : endroit retenu."));
    }
}
