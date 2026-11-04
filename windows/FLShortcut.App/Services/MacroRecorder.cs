// « Enregistrer une macro » sur Windows (comme le Mac, MacroClickSequence.swift) : FL passe devant, et chaque clic et
// chaque touche faits dans FL sont relevés, puis changés en blocs (ClickSequenceCompiler, pur et testé).
// - Pendant l'enregistrement SEULEMENT, et seulement dans FL : souris et clavier lus toutes les 5 ms (comme « Montrer
//   dans FL… », ClickLearner : aucun crochet de plus) ; fenêtres de FL relevées toutes les 50 ms (un menu qui se
//   ferme au clic y est encore). Jamais l'écran. 120 s et 80 clics ou touches au plus.
// - Fin : retour dans FL Shortcuts (le bouton « Terminer » du créateur, ou sa fenêtre remise devant), ou une limite.
// - Clics et touches restent en mémoire : jamais journalisés (le journal dit seulement combien).
using FLShortcut.App.Native;
using FLShortcut.Core;
using FLShortcut.Core.Macros;

namespace FLShortcut.App.Services;

internal static class MacroRecorder
{
    public const int MaxSeconds = 120;
    public const int MaxInputs = 80;
    private const int LeftButton = 0x01, RightButton = 0x02;
    private static int _busy;
    private static volatile bool _stop;

    public static bool Busy => Volatile.Read(ref _busy) == 1;

    /// Termine l'enregistrement en cours (bouton « Terminer »).
    public static void Stop() => _stop = true;

    /// Lance l'enregistrement de FL (`pid`) ; `done` est appelé sur le fil de l'interface avec les entrées relevées et,
    /// s'il s'est arrêté tout seul, la raison. `isFl`/`isUs` : la fenêtre (racine) est-elle FL, ou FL Shortcuts ? (essai
    /// de la CI : le faux FL est dans l'appli). Faux si un enregistrement est déjà en cours.
    public static bool Start(uint pid, Action<Action> onUi, Action<List<RecordedInput>, string?> done,
                             Func<IntPtr, bool>? isFl = null, Func<IntPtr, bool>? isUs = null,
                             Func<List<FlWin>>? windows = null)
    {
        if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0) return false;
        _stop = false;
        var us = (uint)Environment.ProcessId;
        isFl ??= root => Owner(root) == pid;
        isUs ??= root => Owner(root) == us;
        windows ??= () => WindowsFlDriver.Enumerate(pid).Select(w => w.Window).ToList();
        new Thread(() =>
        {
            var inputs = new List<RecordedInput>();
            string? why;
            try { why = Record(pid, isFl, isUs, windows, inputs); }
            catch (Exception e)
            {
                AppLog.Write("MACRO", "record crash " + e.GetType().Name);
                why = Loc.T("erreur interne");
            }
            finally { Volatile.Write(ref _busy, 0); }
            onUi(() => done(inputs, why));
        }) { IsBackground = true, Name = "FL Shortcuts – enregistrer une macro" }.Start();
        return true;
    }

    private static uint Owner(IntPtr window)
    {
        if (window == IntPtr.Zero) return 0;
        Win32.GetWindowThreadProcessId(window, out var owner);
        return owner;
    }

    private static IntPtr RootAt(Win32.POINT p)
    {
        var hit = Win32.WindowFromPoint(p);
        return hit == IntPtr.Zero ? IntPtr.Zero : Win32.GetAncestor(hit, Win32.GA_ROOT);
    }

    private static IntPtr Foreground()
    {
        var fg = Win32.GetForegroundWindow();
        return fg == IntPtr.Zero ? IntPtr.Zero : Win32.GetAncestor(fg, Win32.GA_ROOT);
    }

    private static bool Down(int vk) => (Win32.GetAsyncKeyState(vk) & 0x8000) != 0;

    /// Touches relevées : tout sauf les boutons de la souris et les touches de modification seules.
    private static bool Recordable(int vk) =>
        vk is >= 0x08 and <= 0xFE
        && vk is not (0x10 or 0x11 or 0x12 or 0x5B or 0x5C or 0x5D) && vk is not (>= 0xA0 and <= 0xA5);

    private static string? Record(uint pid, Func<IntPtr, bool> isFl, Func<IntPtr, bool> isUs, Func<List<FlWin>> readWindows,
                                  List<RecordedInput> inputs)
    {
        if (pid != 0 && !FlControl.BringForward(pid)) return Loc.T("FL n'a pas pu passer devant : ouvre FL, puis recommence.");
        var start = DateTime.UtcNow;
        var deadline = start.AddSeconds(MaxSeconds);
        var windows = readWindows();
        var readAt = DateTime.UtcNow;
        var held = new bool[256];
        for (var vk = 0; vk < 256; vk++) held[vk] = Recordable(vk) && Down(vk);      // touches déjà tenues : pas relevées
        var leftWas = Down(LeftButton);
        var rightWas = Down(RightButton);
        (int X, int Y, List<FlWin> Windows)? pressed = null;                          // bouton gauche appuyé dans FL
        var ignored = 0;
        string? why = null;
        while (!_stop)
        {
            var now = DateTime.UtcNow;
            if (now >= deadline) { why = Loc.F("%lld s au plus.", MaxSeconds); break; }
            if (inputs.Count >= MaxInputs) { why = Loc.F("%lld clics ou touches au plus.", MaxInputs); break; }
            var front = Foreground();
            // Retour dans FL Shortcuts : c'est fini (pas tout de suite : FL est en train de passer devant).
            if (pressed is null && (now - start).TotalMilliseconds > 800 && front != IntPtr.Zero && isUs(front)) break;
            if ((now - readAt).TotalMilliseconds >= 50 && pressed is null)
            {
                windows = readWindows();
                readAt = now;
            }
            // Souris.
            var left = Down(LeftButton);
            if (left && !leftWas)
            {
                Win32.GetCursorPos(out var p);
                if (isFl(RootAt(p))) pressed = (p.X, p.Y, windows);
                else if (!isUs(RootAt(p))) ignored++;
            }
            else if (!left && leftWas && pressed is { } down)
            {
                Win32.GetCursorPos(out var p);
                var release = Math.Abs(p.X - down.X) + Math.Abs(p.Y - down.Y) > ClickSequenceCompiler.DragDistance
                    ? new RecordedRelease(p.X, p.Y, readWindows()) : null;
                inputs.Add(new RecordedInput.Click(down.X, down.Y, false, down.Windows, release));
                pressed = null;
            }
            leftWas = left;
            var right = Down(RightButton);
            if (right && !rightWas)
            {
                Win32.GetCursorPos(out var p);
                if (isFl(RootAt(p))) inputs.Add(new RecordedInput.Click(p.X, p.Y, true, windows));
                else if (!isUs(RootAt(p))) ignored++;
            }
            rightWas = right;
            // Clavier : seulement quand FL est devant.
            var flFront = front != IntPtr.Zero && isFl(front);
            for (var vk = 0; vk < 256; vk++)
            {
                if (!Recordable(vk)) continue;
                var down = Down(vk);
                if (down && !held[vk] && flFront)
                {
                    var combo = new KeyCombo((ushort)vk, Ctrl: Down(0x11), Alt: Down(0x12), Shift: Down(0x10),
                                             Win: Down(0x5B) || Down(0x5C));
                    inputs.Add(new RecordedInput.Key(combo, windows.Any(w => w.Role == FlWindowRole.Menu)));
                }
                held[vk] = down;
            }
            Thread.Sleep(5);
        }
        AppLog.Write("MACRO", $"record: {inputs.Count} inputs, {ignored} outside FL, {(DateTime.UtcNow - start).TotalSeconds:0} s");
        return why;
    }
}
