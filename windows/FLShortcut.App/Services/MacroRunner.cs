// Macros sur Windows : lancement (une seule à la fois, sur son propre fil, jamais dans le hook clavier) et pilote de FL
// pour MacroEffectsWindows (Core/Macros). Miroir de Sources/FLShortcut/MacroRunner.swift. Garde-fous :
//  - la macro ne démarre que si FL est au premier plan (et pas lancé en administrateur : Windows bloquerait les
//    touches), et s'arrête dès qu'il ne l'est plus ou sur Échap ;
//  - touches à FL seul (FlControl.Send : FL devant revérifié), liste noire revérifiée avant chaque envoi ;
//  - clics seulement si FL est devant et que la fenêtre tout devant au point visé est à FL (sinon le nom du programme
//    qui la couvre est dit) ; pointeur remis où il était ;
//  - fenêtres de FL reconnues par leur classe et leur style, JAMAIS par leur titre (nom du projet) ; textes lus
//    seulement au moment du clic, dans la fenêtre de FL visée (FlScreen) ;
//  - journal (AppLog « MACRO ») : des noms de blocs, des classes de fenêtre, des nombres et des durées, jamais une
//    touche, un titre ni un texte lu.
using System.Runtime.InteropServices;
using System.Text;
using FLShortcut.App.Native;
using FLShortcut.Core;
using FLShortcut.Core.Macros;

namespace FLShortcut.App.Services;

internal sealed class MacroRunner
{
    public enum StartResult { Started, Busy, Refused }

    private readonly MidiLink _midi;
    private readonly AppSettings _settings;
    private readonly Func<bool> _light;
    private readonly Func<int> _escapes;
    private readonly Action<Action> _onUi;
    private readonly Action _openOrganizer;
    private int _busy;

    /// Fin d'une macro, sur le fil de l'interface : réussie (ou arrêtée par son bloc), et le texte du résultat.
    public event Action<bool, string>? Finished;

    public MacroRunner(MidiLink midi, AppSettings settings, Func<bool> light, Func<int> escapes, Action<Action> onUi,
                       Action openOrganizer)
    {
        _midi = midi;
        _settings = settings;
        _light = light;
        _escapes = escapes;
        _onUi = onUi;
        _openOrganizer = openOrganizer;
    }

    public bool IsRunning => Volatile.Read(ref _busy) != 0;

    /// Appelé sur le fil de l'interface : ne bloque jamais, la macro tourne sur son propre fil.
    public StartResult Start(MacroProgram program)
    {
        if (!program.IsRunnable || FlPresence.Foreground() is not { Elevated: false } fl) return StartResult.Refused;
        if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0) return StartResult.Busy;
        var thread = new Thread(() =>
        {
            MacroOutcome outcome;
            try { outcome = Execute(program, fl.Pid); }
            catch (Exception e)
            {
                AppLog.Write("MACRO", "crash " + e.GetType().Name);
                outcome = new MacroOutcome.Cancelled(Loc.T("erreur interne"));
            }
            finally { Volatile.Write(ref _busy, 0); }
            var ok = outcome is MacroOutcome.Done or MacroOutcome.Stopped;
            _onUi(() => Finished?.Invoke(ok, outcome.Text));
        }) { IsBackground = true, Name = "FL Shortcuts – macro" };
        thread.Start();
        return StartResult.Started;
    }

    private MacroOutcome Execute(MacroProgram program, uint pid)
    {
        var driver = new WindowsFlDriver(pid, _midi, _settings, _light, _escapes, _onUi, _openOrganizer);
        AppLog.Write("MACRO", $"run {program.Title}");
        driver.LogWindows();
        // Effets neufs à chaque passage : rien de l'état d'un passage ne survit au suivant.
        var outcome = new MacroInterpreter(new MacroEffectsWindows(driver)).Run(program);
        AppLog.Write("MACRO", "end " + outcome.GetType().Name);
        return outcome;
    }
}

/// Le vrai FL : fenêtres (EnumWindows), touches (SendInput, FL devant), Échap, lien MIDI.
internal sealed class WindowsFlDriver : IFlDriver
{
    private static readonly ushort[] ModifierKeys =
        { Vk.LControl, Vk.RControl, Vk.LMenu, Vk.RMenu, Vk.LShift, Vk.RShift, Vk.LWin, Vk.RWin };

    private readonly uint _pid;
    private readonly MidiLink _midi;
    private readonly AppSettings _settings;
    private readonly Func<bool> _light;
    private readonly Func<int> _escapes;
    private readonly Action<Action> _onUi;
    private readonly Action _openOrganizer;

    public WindowsFlDriver(uint pid, MidiLink midi, AppSettings settings, Func<bool> light, Func<int> escapes,
                           Action<Action> onUi, Action openOrganizer)
    {
        _pid = pid;
        _midi = midi;
        _settings = settings;
        _light = light;
        _escapes = escapes;
        _onUi = onUi;
        _openOrganizer = openOrganizer;
    }

    public void Log(string tag, string text) => AppLog.Write("MACRO", $"{tag} {text}");

    public bool InFront() => FlControl.InFront(_pid);

    public int EscapePresses => _escapes();

    public bool EscapeDown() => FlControl.EscapePressed();

    public bool ModifiersDown() => ModifierKeys.Any(Down);

    /// Une touche enfoncée (souris, verrouillages et touches de modification à part).
    public bool AnyKeyDown()
    {
        for (var vk = 0x08; vk <= 0xFE; vk++)
        {
            if (vk is 0x10 or 0x11 or 0x12 or 0x14 or 0x90 or 0x91 || ModifierKeys.Contains((ushort)vk)) continue;
            if (Down((ushort)vk)) return true;
        }
        return false;
    }

    private static bool Down(ushort vk) => (Win32.GetAsyncKeyState(vk) & 0x8000) != 0;

    public bool Send(KeyCombo combo) => !ForbiddenTargets.IsForbidden(combo) && FlControl.Send(_pid, combo);

    public IReadOnlyList<FlWin> Windows() => Enumerate().Select(w => w.Window).ToList();

    public void Sleep(int ms) => Thread.Sleep(ms);

    public DateTime Now => DateTime.UtcNow;

    public string? RunActions(IReadOnlyList<int> ids) => _midi.RunBriefly(ids, brief: _light());

    public FlWindow? KnownPage => _midi.RoutingView().KnownWindow;

    public bool? Learned(string key) =>
        _settings.MacroMemory is { } memory && memory.TryGetValue(key, out var value) ? value : null;

    public void Learn(string key, bool? value) => _onUi(() =>
    {
        var memory = _settings.MacroMemory ??= new Dictionary<string, bool>();
        if (value is { } v) memory[key] = v; else memory.Remove(key);
        _settings.Save();
    });

    public void OpenOrganizer() => _onUi(_openOrganizer);

    public (int X, int Y) Cursor() => Win32.GetCursorPos(out var p) ? (p.X, p.Y) : (0, 0);

    public void MoveCursor(int x, int y) => Win32.SetCursorPos(x, y);

    /// Fenêtre tout devant en ce point : à FL (sa fenêtre de premier niveau), sinon le nom du programme qui la couvre.
    public (long? Window, string? Cover) At(int x, int y)
    {
        var hit = Win32.WindowFromPoint(new Win32.POINT { X = x, Y = y });
        if (hit == IntPtr.Zero) return (null, null);
        var root = Win32.GetAncestor(hit, Win32.GA_ROOT);
        if (root == IntPtr.Zero) root = hit;
        Win32.GetWindowThreadProcessId(root, out var owner);
        if (owner == _pid) return (root.ToInt64(), null);
        return (null, ProcessName(owner) ?? Loc.T("une autre app"));
    }

    private static string? ProcessName(uint pid)
    {
        var h = Win32.OpenProcess(Win32.PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (h == IntPtr.Zero) return null;
        try
        {
            var buffer = new StringBuilder(1024);
            var size = (uint)buffer.Capacity;
            return Win32.QueryFullProcessImageNameW(h, 0, buffer, ref size) ? Path.GetFileNameWithoutExtension(buffer.ToString()) : null;
        }
        finally { Win32.CloseHandle(h); }
    }

    private static void Mouse(uint flags)
    {
        var input = new[]
        {
            new Win32.INPUT
            {
                type = Win32.INPUT_MOUSE,
                U = new Win32.InputUnion { mi = new Win32.MOUSEINPUT { dwFlags = flags, dwExtraInfo = KeyboardHook.Magic } },
            },
        };
        Win32.SendInput(1, input, Marshal.SizeOf<Win32.INPUT>());
    }

    /// Pointeur posé, survol (les menus de FL suivent le pointeur), appui, relâché : FL revérifié devant avant l'appui.
    public bool Click(int x, int y, bool right, int hoverMs)
    {
        if (!InFront()) return false;
        Win32.SetCursorPos(x, y);
        Mouse(Win32.MOUSEEVENTF_MOVE);
        Thread.Sleep(Math.Max(hoverMs, 10));
        if (!InFront()) return false;
        Mouse(right ? Win32.MOUSEEVENTF_RIGHTDOWN : Win32.MOUSEEVENTF_LEFTDOWN);
        Thread.Sleep(50);
        Mouse(right ? Win32.MOUSEEVENTF_RIGHTUP : Win32.MOUSEEVENTF_LEFTUP);
        return true;
    }

    /// Appui, une vingtaine de pas (16 ms chacun), un temps au-dessus de l'arrivée pour que FL la voie, relâché
    /// (toujours, même si FL n'est plus devant).
    public bool Drag(int ax, int ay, int bx, int by)
    {
        if (!InFront()) return false;
        Win32.SetCursorPos(ax, ay);
        Mouse(Win32.MOUSEEVENTF_MOVE);
        Thread.Sleep(30);
        Mouse(Win32.MOUSEEVENTF_LEFTDOWN);
        try
        {
            const int steps = 20;
            for (var i = 1; i <= steps; i++)
            {
                Win32.SetCursorPos(ax + (bx - ax) * i / steps, ay + (by - ay) * i / steps);
                Mouse(Win32.MOUSEEVENTF_MOVE);
                Thread.Sleep(16);
            }
            Thread.Sleep(60);
        }
        finally { Mouse(Win32.MOUSEEVENTF_LEFTUP); }
        return true;
    }

    public IReadOnlyList<TextItem>? MenuBar() => FlScreen.MenuBar(FlControl.MainWindow(_pid));

    public IReadOnlyList<TextItem>? MenuItems(long window) => Owned(window) ? FlScreen.MenuItems((IntPtr)window) : null;

    public IReadOnlyList<TextItem>? ReadText(long window) => Owned(window) ? FlScreen.ReadWindow((IntPtr)window) : null;

    /// Fenêtre de FL (jamais celle d'un autre programme), visible.
    private bool Owned(long window)
    {
        var hwnd = (IntPtr)window;
        Win32.GetWindowThreadProcessId(hwnd, out var owner);
        return owner == _pid && Win32.IsWindowVisible(hwnd);
    }

    /// Plus aucun menu de FL actif (titre resté surligné en haut de FL après Échap).
    public void CancelMenus()
    {
        var main = FlControl.MainWindow(_pid);
        if (main != IntPtr.Zero) Win32.PostMessageW(main, Win32.WM_CANCELMODE, UIntPtr.Zero, IntPtr.Zero);
    }

    /// Pas encore suivi sur Windows : la piste visée est le pointeur au départ.
    public AimedClick? LastAimedClick => null;

    /// Diagnostic du départ : classe, rôle et taille de chaque fenêtre de FL (jamais le titre).
    public void LogWindows()
    {
        foreach (var (window, cls) in Enumerate())
            Log("WIN", $"{cls} {window.Role} {window.Width}x{window.Height}");
    }

    private List<(FlWin Window, string Class)> Enumerate() => Enumerate(_pid);

    /// Fenêtres visibles de FL, de la plus en avant à la plus en arrière (ordre d'EnumWindows), 40 au plus.
    internal static List<(FlWin Window, string Class)> Enumerate(uint pid)
    {
        var main = FlControl.MainWindow(pid);
        var output = new List<(FlWin, string)>();
        var name = new StringBuilder(64);
        Win32.EnumWindows((hwnd, _) =>
        {
            Win32.GetWindowThreadProcessId(hwnd, out var owner);
            if (owner != pid || !Win32.IsWindowVisible(hwnd)) return true;
            name.Clear();
            Win32.GetClassNameW(hwnd, name, name.Capacity);
            var cls = name.ToString();
            Win32.GetWindowRect(hwnd, out var r);
            var role = Role(hwnd, main, cls, r.Right - r.Left, r.Bottom - r.Top);
            output.Add((new FlWin(hwnd.ToInt64(), role, r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top), cls));
            return output.Count < 40;
        }, IntPtr.Zero);
        return output;
    }

    /// Menu : menu standard de Windows (#32768), ou fenêtre surgissante sans barre de titre (menus de FL) ; bulles
    /// d'aide et toutes petites fenêtres à part. Boîte de dialogue : boîte standard (#32770, « Open »…), ou fenêtre
    /// titrée de taille fixe qui appartient à FL (Project general settings…).
    internal static FlWindowRole Role(IntPtr hwnd, IntPtr main, string cls, int width, int height)
    {
        if (hwnd == main) return FlWindowRole.Main;
        if (cls == "#32768") return FlWindowRole.Menu;
        if (cls == "#32770") return FlWindowRole.Dialog;
        if (cls.Contains("hint", StringComparison.OrdinalIgnoreCase) || cls.Contains("tooltip", StringComparison.OrdinalIgnoreCase)
            || width < 40 || height < 16)
            return FlWindowRole.Other;
        var style = Win32.GetWindowLongPtrW(hwnd, Win32.GWL_STYLE).ToInt64();
        var captioned = (style & Win32.WS_CAPTION) == Win32.WS_CAPTION;
        if ((style & Win32.WS_POPUP) != 0 && !captioned) return FlWindowRole.Menu;
        var owned = Win32.GetWindow(hwnd, Win32.GW_OWNER) != IntPtr.Zero;
        if (owned && captioned && (style & Win32.WS_THICKFRAME) == 0) return FlWindowRole.Dialog;
        return FlWindowRole.Other;
    }
}
