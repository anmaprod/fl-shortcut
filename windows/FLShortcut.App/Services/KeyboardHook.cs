// Audit : WIN-01 (hook WH_KEYBOARD_LL installé SEULEMENT quand FL Studio est au premier plan ; rappel sans
//         allocation inutile, sans E/S, sans journal ; aucune frappe conservée), WIN-03 (décision → injection
//         différée sur le même thread, PID de FL revérifié juste avant SendInput, liste noire revérifiée),
//         REL-03 (thread dédié avec sa propre boucle de messages ; configuration immuable lue par référence),
//         REL-04 / SEC-11 (purge sur changement de fenêtre, état borné), REL-06 (effet impossible → touche rendue).
using System.Runtime.InteropServices;
using FLShortcut.App.Native;
using FLShortcut.Core;

namespace FLShortcut.App.Services;

internal sealed class KeyboardHook : IDisposable
{
    /// Marque nos propres injections (dwExtraInfo) pour ne jamais les retraiter. « FLSC ».
    internal static readonly UIntPtr Magic = new(0x464C5343);

    private const uint MsgInject = Win32.WM_APP + 2;
    private const uint MsgAction = Win32.WM_APP + 3;
    private const uint MsgRefresh = Win32.WM_APP + 4;
    private const uint MsgMask = Win32.WM_APP + 5;

    private readonly Func<int, bool> _sendAction;
    private readonly Action _onToggle;
    private readonly Action<FlProcessInfo?> _onForegroundChanged;

    private readonly KeyRouter _router = new();
    private readonly ModifierTracker _mods = new();
    private Thread? _thread;
    private uint _threadId;
    private IntPtr _kbHook = IntPtr.Zero;
    private IntPtr _fgHook = IntPtr.Zero;
    private Win32.LowLevelKeyboardProc? _kbProc;       // références gardées vivantes (sinon le GC libère le délégué)
    private Win32.WinEventProc? _fgProc;
    private volatile uint _flPid;
    private FlProcessInfo? _lastFl;
    private readonly ManualResetEventSlim _started = new();

    public volatile HookConfig Config = HookConfig.Default;
    public volatile LinkRoutingView Link = LinkRoutingView.Offline;

    /// <param name="sendAction">Envoie une action FL (trame signée) ; faux si impossible.</param>
    public KeyboardHook(Func<int, bool> sendAction, Action onToggle, Action<FlProcessInfo?> onForegroundChanged)
    {
        _sendAction = sendAction;
        _onToggle = onToggle;
        _onForegroundChanged = onForegroundChanged;
    }

    public bool IsHookInstalled => _kbHook != IntPtr.Zero;

    public void Start()
    {
        if (_thread is not null) return;
        _thread = new Thread(Run) { IsBackground = true, Name = "FL Shortcuts – clavier", Priority = ThreadPriority.AboveNormal };
        _thread.Start();
        _started.Wait(TimeSpan.FromSeconds(5));
    }

    /// Réévalue la fenêtre au premier plan (après un changement de configuration, une sortie de veille…).
    public void Refresh()
    {
        if (_threadId != 0) Win32.PostThreadMessageW(_threadId, MsgRefresh, UIntPtr.Zero, IntPtr.Zero);
    }

    public void Dispose()
    {
        if (_threadId != 0) Win32.PostThreadMessageW(_threadId, Win32.WM_QUIT, UIntPtr.Zero, IntPtr.Zero);
        _thread?.Join(TimeSpan.FromSeconds(2));
        _thread = null;
    }

    private void Run()
    {
        _threadId = Win32.GetCurrentThreadId();
        _kbProc = HookProc;
        _fgProc = ForegroundProc;
        _fgHook = Win32.SetWinEventHook(Win32.EVENT_SYSTEM_FOREGROUND, Win32.EVENT_SYSTEM_FOREGROUND, IntPtr.Zero,
            _fgProc, 0, 0, Win32.WINEVENT_OUTOFCONTEXT);   // notre propre fenêtre aussi : le hook doit tomber (WIN-01)
        EvaluateForeground();
        _started.Set();

        while (Win32.GetMessageW(out var msg, IntPtr.Zero, 0, 0) > 0)
        {
            switch (msg.message)
            {
                case MsgInject:
                    DoInject(msg.wParam, msg.lParam);
                    break;
                case MsgAction:
                    DoAction(msg.wParam, msg.lParam);
                    break;
                case MsgRefresh:
                    EvaluateForeground();
                    break;
                case MsgMask:
                    Injector.SendMask();
                    break;
                default:
                    Win32.TranslateMessage(ref msg);
                    Win32.DispatchMessageW(ref msg);
                    break;
            }
        }

        Uninstall();
        if (_fgHook != IntPtr.Zero) Win32.UnhookWinEvent(_fgHook);
        _fgHook = IntPtr.Zero;
        _threadId = 0;
    }

    private void ForegroundProc(IntPtr hook, uint evt, IntPtr hwnd, int idObject, int idChild, uint thread, uint time) =>
        EvaluateForeground();

    /// Hook installé seulement si FL est devant (WIN-01) ; état purgé à chaque changement (SEC-11).
    private void EvaluateForeground()
    {
        var fl = FlPresence.Foreground();
        _flPid = fl is { Elevated: false } ? fl.Pid : 0;
        _router.Purge();
        _mods.Clear();
        if (_flPid != 0) Install(); else Uninstall();
        if (Equals(fl, _lastFl)) return;          // pas de rafraîchissement complet de l'appli à chaque Alt+Tab
        _lastFl = fl;
        try { _onForegroundChanged(fl); } catch { /* jamais d'exception dans la boucle */ }
    }

    private void Install()
    {
        if (_kbHook != IntPtr.Zero || _kbProc is null) return;
        _kbHook = Win32.SetWindowsHookExW(Win32.WH_KEYBOARD_LL, _kbProc, Win32.GetModuleHandleW(null), 0);
    }

    private void Uninstall()
    {
        if (_kbHook == IntPtr.Zero) return;
        Win32.UnhookWindowsHookEx(_kbHook);
        _kbHook = IntPtr.Zero;
    }

    private IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode != Win32.HC_ACTION) return Win32.CallNextHookEx(_kbHook, nCode, wParam, lParam);
        try
        {
            var data = Marshal.PtrToStructure<Win32.KBDLLHOOKSTRUCT>(lParam);
            var msg = (int)wParam;
            var isDown = msg is Win32.WM_KEYDOWN or Win32.WM_SYSKEYDOWN;
            var vk = (ushort)(data.vkCode & 0xFF);
            var own = data.dwExtraInfo == Magic;
            var injected = (data.flags & Win32.LLKHF_INJECTED) != 0;

            // Frappes injectées par d'autres logiciels : jamais remappées, mais l'état des modificateurs suit.
            var isRepeat = own ? false : _mods.Observe(vk, isDown);
            if (own || injected) return Win32.CallNextHookEx(_kbHook, nCode, wParam, lParam);

            var input = new RouterInput(isDown ? RouterInput.Kinds.Down : RouterInput.Kinds.Up, _mods.Combo(vk),
                IsRepeat: isRepeat, IsOwn: false, TargetIsFl: _flPid != 0 && FlPresence.ForegroundPid() == _flPid,
                AltGr: _mods.AltGr);
            var decision = _router.Route(input, Config, Link);

            // Alt (ou Win) tenu et déclencheur avalé : FL verrait « Alt seul » et ouvrirait son menu au relâchement.
            // Une touche neutre, envoyée avant tout effet, l'en empêche (même technique qu'AutoHotkey).
            if (decision.Swallow && isDown && !isRepeat && (_mods.Alt || _mods.Win))
                Win32.PostThreadMessageW(_threadId, MsgMask, UIntPtr.Zero, IntPtr.Zero);

            foreach (var effect in decision.Effects)
            {
                switch (effect)
                {
                    case RouterEffect.SendAction a:
                        Win32.PostThreadMessageW(_threadId, MsgAction, new UIntPtr((uint)a.Id), new IntPtr(vk));
                        break;
                    case RouterEffect.Post p:
                        Win32.PostThreadMessageW(_threadId, MsgInject, new UIntPtr(Pack(p.Combo)), new IntPtr(vk | (long)_flPid << 16));
                        break;
                    case RouterEffect.ToggleEnabled:
                        try { _onToggle(); } catch { }
                        break;
                }
            }
            if (decision.Swallow) return new IntPtr(1);
        }
        catch
        {
            _router.Purge();       // en cas de doute, ne rien avaler
        }
        return Win32.CallNextHookEx(_kbHook, nCode, wParam, lParam);
    }

    private void DoAction(UIntPtr wParam, IntPtr lParam)
    {
        var id = (int)wParam.ToUInt32();
        var vk = (ushort)(lParam.ToInt64() & 0xFFFF);
        bool ok;
        try { ok = _sendAction(id); } catch { ok = false; }
        if (!ok) _router.Release(vk);           // la touche suivante (répétition, relâchement) ira à FL
    }

    private void DoInject(UIntPtr wParam, IntPtr lParam)
    {
        var target = Unpack(wParam.ToUInt32());
        var raw = lParam.ToInt64();
        var vk = (ushort)(raw & 0xFFFF);
        var expectedPid = (uint)(raw >> 16);
        // WIN-03 : la frappe ne part que si FL est toujours devant, et jamais vers une cible interdite.
        if (expectedPid == 0 || FlPresence.ForegroundPid() != expectedPid || ForbiddenTargets.IsForbidden(target)
            || !Injector.Send(target, _mods))
        {
            _router.Release(vk);
        }
    }

    private static uint Pack(KeyCombo c) =>
        c.Vk | (c.Ctrl ? 1u << 16 : 0) | (c.Alt ? 1u << 17 : 0) | (c.Shift ? 1u << 18 : 0) | (c.Win ? 1u << 19 : 0);

    private static KeyCombo Unpack(uint v) =>
        new((ushort)(v & 0xFFFF), (v & (1u << 16)) != 0, (v & (1u << 17)) != 0, (v & (1u << 18)) != 0, (v & (1u << 19)) != 0);
}

/// Envoi atomique d'une combinaison (un seul SendInput) : les modificateurs physiques qui ne font pas partie
/// de la cible sont relâchés puis rétablis, pour que FL reçoive exactement la combinaison voulue.
internal static class Injector
{
    private static readonly ushort[] ExtendedKeys =
    {
        Vk.Prior, Vk.Next, Vk.End, Vk.Home, Vk.Left, Vk.Up, Vk.Right, Vk.Down, Vk.Insert, Vk.Delete,
        Vk.Divide, Vk.RControl, Vk.RMenu, Vk.LWin, Vk.RWin, Vk.Apps, Vk.NumLock,
    };

    /// Touche non attribuée (VK 0xE8) : neutralise un Alt ou un Win « seul » (menu de FL, menu Démarrer).
    private const ushort MaskVk = 0xE8;

    private static Win32.INPUT Input(ushort vk, bool up) => new()
    {
        type = Win32.INPUT_KEYBOARD,
        U = new Win32.InputUnion
        {
            ki = new Win32.KEYBDINPUT
            {
                wVk = vk,
                dwFlags = (up ? Win32.KEYEVENTF_KEYUP : 0) | (Array.IndexOf(ExtendedKeys, vk) >= 0 ? Win32.KEYEVENTF_EXTENDEDKEY : 0),
                dwExtraInfo = KeyboardHook.Magic,
            },
        },
    };

    public static void SendMask()
    {
        var arr = new[] { Input(MaskVk, up: false), Input(MaskVk, up: true) };
        Win32.SendInput((uint)arr.Length, arr, Marshal.SizeOf<Win32.INPUT>());
    }

    public static bool Send(KeyCombo target, ModifierTracker physical)
    {
        var inputs = new List<Win32.INPUT>(16);
        var released = new List<ushort>();
        var pressed = new List<ushort>();

        void Key(ushort vk, bool up) => inputs.Add(Input(vk, up));

        void Align(bool isDown, bool wanted, ushort genericVk)
        {
            if (isDown && !wanted) { Key(genericVk, up: true); released.Add(genericVk); }
            else if (!isDown && wanted) { Key(genericVk, up: false); pressed.Add(genericVk); }
        }

        Align(physical.Ctrl, target.Ctrl, Vk.Control);
        Align(physical.Alt, target.Alt, Vk.Menu);
        Align(physical.Shift, target.Shift, Vk.Shift);
        Align(physical.Win, target.Win, Vk.LWin);

        Key(target.Vk, up: false);
        Key(target.Vk, up: true);

        foreach (var vk in Enumerable.Reverse(pressed)) Key(vk, up: true);
        foreach (var vk in released) Key(vk, up: false);
        if (released.Contains(Vk.Menu) || released.Contains(Vk.LWin)) { Key(MaskVk, up: false); Key(MaskVk, up: true); }

        var arr = inputs.ToArray();
        var sent = Win32.SendInput((uint)arr.Length, arr, Marshal.SizeOf<Win32.INPUT>());
        return sent == arr.Length;
    }
}
