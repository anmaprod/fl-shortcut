// Macros sur Windows : lancement (une seule à la fois, sur son propre fil, jamais dans le hook clavier) et pilote de FL
// pour MacroEffectsWindows (Core/Macros). Miroir de Sources/FLShortcut/MacroRunner.swift. Garde-fous :
//  - la macro ne démarre que si FL est au premier plan (et pas lancé en administrateur : Windows bloquerait les
//    touches), et s'arrête dès qu'il ne l'est plus ou sur Échap ;
//  - touches à FL seul (FlControl.Send : FL devant revérifié), liste noire revérifiée avant chaque envoi ;
//  - fenêtres de FL reconnues par leur classe et leur style, JAMAIS par leur titre (nom du projet) ;
//  - journal (AppLog « MACRO ») : des noms de blocs, des classes de fenêtre et des durées, jamais une touche ni un titre.
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

    /// Diagnostic du départ : classe, rôle et taille de chaque fenêtre de FL (jamais le titre).
    public void LogWindows()
    {
        foreach (var (window, cls) in Enumerate())
            Log("WIN", $"{cls} {window.Role} {window.Width}x{window.Height}");
    }

    /// Fenêtres visibles de FL, de la plus en avant à la plus en arrière (ordre d'EnumWindows), 40 au plus.
    private List<(FlWin Window, string Class)> Enumerate()
    {
        var main = FlControl.MainWindow(_pid);
        var output = new List<(FlWin, string)>();
        var name = new StringBuilder(64);
        Win32.EnumWindows((hwnd, _) =>
        {
            Win32.GetWindowThreadProcessId(hwnd, out var owner);
            if (owner != _pid || !Win32.IsWindowVisible(hwnd)) return true;
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
