// Preset de piste pour les macros Windows (miroir de PresetDrop.swift et PresetChooser du Mac) :
//  - dépôt : glissé comme depuis l'Explorateur (objet de données du fichier donné par le shell, le même que
//    l'Explorateur ; glisser d'OLE sur son propre fil). Le bouton est enfoncé sur une petite fenêtre de l'app posée
//    sous la piste (jamais sur FL : il pourrait déplacer la piste) ; sans bouton enfoncé, Windows ne donne pas les
//    mouvements du pointeur au glisser (essai de la CI : il ne démarrait jamais). La fenêtre se cache, le pointeur bouge
//    de quelques pixels pour que FL voie le fichier entrer, puis le bouton est relâché : FL reçoit le fichier ;
//  - boîte « Open » de FL : le chemin écrit dans son champ du nom de fichier, puis Ouvrir.
// Seulement dans FL (vérifié par l'appelant), jamais le chemin au journal (seulement sa longueur).
using System.Runtime.InteropServices;
using System.Text;
using FLShortcut.App.Native;
using FLShortcut.Core;

namespace FLShortcut.App.Services;

internal static class PresetFiles
{
    private const int DRAGDROP_S_DROP = 0x00040100;
    private const uint DROPEFFECT_COPY = 1, DROPEFFECT_MOVE = 2, DROPEFFECT_LINK = 4;
    private static readonly Guid BhidDataObject = new("B8C0BD9F-ED24-455c-83E6-D5390C4FE8C4");
    private static readonly Guid IidDataObject = new("0000010e-0000-0000-C000-000000000046");
    /// Identifiants du champ du nom de fichier des boîtes « Open » de Windows (cmb13, puis edt1 des anciennes).
    private const int FileNameCombo = 1148, FileNameEdit = 1152, IdOk = 1;

    /// Fichier glissé en (x, y) : null si FL l'a pris, sinon la raison. `inFront` : FL toujours devant.
    public static string? Drop(string path, int x, int y, Func<bool> inFront)
    {
        var t0 = Environment.TickCount64;
        var drop = new SourceWindow(path, x, y);
        var thread = new Thread(drop.Run) { IsBackground = true, Name = "FL Shortcuts – dépôt du preset" };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        if (!drop.Ready.Wait(3_000) || drop.Window == IntPtr.Zero)
        {
            drop.Source.Cancel = true;
            Thread.MemoryBarrier();
            drop.Close();
            AppLog.Write("MACRO", "DROP unreadable");
            return Loc.T("preset illisible par Windows");
        }
        var pressed = false;

        string? Abandon(string why)
        {
            drop.Source.Cancel = true;
            if (pressed) Button(false);                        // jamais de bouton laissé enfoncé
            drop.Close();
            drop.Source.Ended.Wait(1_000);
            return why;
        }

        // La petite fenêtre de départ doit être sous le pointeur (sinon le clic irait à ce qui la couvre).
        Win32.SetCursorPos(x, y);
        var under = false;
        for (var i = 0; i < 25 && !under; i++)
        {
            under = Win32.WindowFromPoint(new Win32.POINT { X = x, Y = y }) == drop.Window;
            if (!under) Thread.Sleep(20);
        }
        if (!under)
        {
            AppLog.Write("MACRO", "DROP covered");
            return Abandon(Loc.T("le glisser du preset n'a pas démarré (une fenêtre couvre la piste ?)"));
        }
        if (!inFront()) return Abandon(Loc.T("FL n'est plus au premier plan"));
        Button(true);
        pressed = true;
        // Le glisser démarre à l'appui (dans la fenêtre de départ, cachée aussitôt) ; le pointeur frémit sur place pour
        // que Windows relise l'état du glisser.
        for (var i = 0; i < 25 && !drop.Source.Started.Wait(40); i++) Win32.SetCursorPos(x + (i % 2), y);
        if (!drop.Source.Started.IsSet)
        {
            AppLog.Write("MACRO", $"DROP not started · {Environment.TickCount64 - t0} ms");
            return Abandon(Loc.T("le glisser du preset n'a pas démarré (une fenêtre couvre la piste ?)"));
        }
        // Quelques pixels à droite puis retour : FL voit le fichier entrer sur la piste, puis le reçoit au point visé.
        foreach (var dx in new[] { 4, 8, 12, 8, 4, 0 })
        {
            if (!inFront()) return Abandon(Loc.T("FL n'est plus au premier plan"));
            Win32.SetCursorPos(x + dx, y);
            Thread.Sleep(16);
        }
        Thread.Sleep(30);
        drop.Source.Release = true;
        Button(false);
        pressed = false;
        if (!drop.Source.Ended.Wait(2_000))
        {
            AppLog.Write("MACRO", $"DROP not ended · {Environment.TickCount64 - t0} ms");
            return Abandon(Loc.T("FL n'a pas répondu au dépôt du preset"));
        }
        AppLog.Write("MACRO", $"DROP ended · hr 0x{drop.Hr:X} · effect {drop.Effect} · {Environment.TickCount64 - t0} ms");
        return drop.Hr == DRAGDROP_S_DROP && drop.Effect != 0
            ? null : Loc.T("FL n'a pas pris le preset : clique d'abord au milieu de la tranche de ta piste");
    }

    /// Bouton gauche enfoncé ou relâché là où est le pointeur (marqué comme venant de l'app).
    private static void Button(bool down)
    {
        var input = new[]
        {
            new Win32.INPUT
            {
                type = Win32.INPUT_MOUSE,
                U = new Win32.InputUnion
                {
                    mi = new Win32.MOUSEINPUT
                    {
                        dwFlags = down ? Win32.MOUSEEVENTF_LEFTDOWN : Win32.MOUSEEVENTF_LEFTUP,
                        dwExtraInfo = KeyboardHook.Magic,
                    },
                },
            },
        };
        Win32.SendInput(1, input, Marshal.SizeOf<Win32.INPUT>());
    }

    /// Fenêtre de départ du glisser : 8 × 8 points presque invisibles, au-dessus de tout, jamais activée, posée sous le
    /// point visé. L'appui du bouton y arrive (pas à FL) ; le glisser d'OLE part de là, sur son propre fil, et la fenêtre
    /// se cache dès qu'il a démarré (FL est alors sous le pointeur et voit le fichier entrer).
    private sealed class SourceWindow
    {
        private const string ClassName = "FLShortcutsPresetDrag";
        private const uint WS_POPUP = 0x80000000, WS_EX_LAYERED = 0x00080000, WS_EX_TOPMOST = 0x00000008,
            WS_EX_TOOLWINDOW = 0x00000080, WS_EX_NOACTIVATE = 0x08000000, LWA_ALPHA = 0x2;
        private const uint WM_CLOSE = 0x0010, WM_DESTROY = 0x0002, WM_LBUTTONDOWN = 0x0201;
        private const int SW_HIDE = 0, SW_SHOWNOACTIVATE = 4, Half = 4;
        private static readonly WndProc Proc = Dispatch;
        private static int _registered;
        [ThreadStatic] private static SourceWindow? _current;

        private readonly string _path;
        private readonly int _x, _y;
        private IntPtr _data;
        private bool _dragging;
        public readonly DropSource Source = new();
        public readonly ManualResetEventSlim Ready = new();
        public volatile IntPtr Window;
        public int Hr;
        public uint Effect;

        public SourceWindow(string path, int x, int y)
        {
            _path = path;
            _x = x;
            _y = y;
        }

        /// Fil STA : objet de données du fichier (celui de l'Explorateur), fenêtre, puis ses messages jusqu'à sa fin.
        public void Run()
        {
            OleInitialize(IntPtr.Zero);
            _current = this;
            try
            {
                if (SHCreateItemFromParsingName(_path, IntPtr.Zero, typeof(IShellItem).GUID, out var item) != 0) return;
                var handler = BhidDataObject;
                var iid = IidDataObject;
                item.BindToHandler(IntPtr.Zero, ref handler, ref iid, out _data);
                Marshal.ReleaseComObject(item);
                if (_data == IntPtr.Zero) return;
                var instance = Win32.GetModuleHandleW(null);
                if (Interlocked.Exchange(ref _registered, 1) == 0)
                {
                    var wc = new WNDCLASSEXW
                    {
                        cbSize = (uint)Marshal.SizeOf<WNDCLASSEXW>(),
                        lpfnWndProc = Marshal.GetFunctionPointerForDelegate(Proc),
                        hInstance = instance,
                        lpszClassName = ClassName,
                    };
                    RegisterClassExW(ref wc);
                }
                var hwnd = CreateWindowExW(WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, ClassName, null, WS_POPUP,
                    _x - Half, _y - Half, 2 * Half, 2 * Half, IntPtr.Zero, IntPtr.Zero, instance, IntPtr.Zero);
                if (hwnd == IntPtr.Zero) return;
                SetLayeredWindowAttributes(hwnd, 0, 1, LWA_ALPHA);    // presque transparente, mais reçoit le clic
                Source.Starting = () => ShowWindow(hwnd, SW_HIDE);
                ShowWindow(hwnd, SW_SHOWNOACTIVATE);
                Window = hwnd;
                Thread.MemoryBarrier();
                if (Source.Cancel) return;                       // l'appelant a déjà renoncé (fenêtre détruite plus bas)
                Ready.Set();
                while (Win32.GetMessageW(out var msg, IntPtr.Zero, 0, 0) > 0)
                {
                    Win32.TranslateMessage(ref msg);
                    Win32.DispatchMessageW(ref msg);
                }
            }
            catch (Exception e)
            {
                AppLog.Write("MACRO", "DROP error " + e.GetType().Name);
            }
            finally
            {
                Ready.Set();
                if (Window != IntPtr.Zero && IsWindowAlive(Window)) DestroyWindow(Window);
                if (_data != IntPtr.Zero) Marshal.Release(_data);
                _current = null;
                Source.Ended.Set();
                OleUninitialize();
            }
        }

        /// Fermeture demandée d'un autre fil (sans effet pendant le glisser : il s'arrête par Cancel).
        public void Close()
        {
            if (Window != IntPtr.Zero) Win32.PostMessageW(Window, WM_CLOSE, UIntPtr.Zero, IntPtr.Zero);
        }

        private static IntPtr Dispatch(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam)
        {
            var self = _current;
            switch (msg)
            {
                case WM_LBUTTONDOWN when self is { _dragging: false } && !self.Source.Cancel:
                    self._dragging = true;
                    self.Hr = DoDragDrop(self._data, self.Source, DROPEFFECT_COPY | DROPEFFECT_MOVE | DROPEFFECT_LINK, out self.Effect);
                    self._dragging = false;
                    DestroyWindow(hwnd);
                    return IntPtr.Zero;
                case WM_CLOSE:
                    if (self is not { _dragging: true }) DestroyWindow(hwnd);
                    return IntPtr.Zero;
                case WM_DESTROY:
                    PostQuitMessage(0);
                    return IntPtr.Zero;
            }
            return DefWindowProcW(hwnd, msg, wParam, lParam);
        }

        private delegate IntPtr WndProc(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WNDCLASSEXW
        {
            public uint cbSize;
            public uint style;
            public IntPtr lpfnWndProc;
            public int cbClsExtra;
            public int cbWndExtra;
            public IntPtr hInstance;
            public IntPtr hIcon;
            public IntPtr hCursor;
            public IntPtr hbrBackground;
            public string? lpszMenuName;
            public string lpszClassName;
            public IntPtr hIconSm;
        }

        [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern ushort RegisterClassExW(ref WNDCLASSEXW wc);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr CreateWindowExW(uint exStyle, string className, string? windowName, uint style, int x, int y, int width,
            int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);
        [DllImport("user32.dll")] private static extern IntPtr DefWindowProcW(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool DestroyWindow(IntPtr hWnd);
        [DllImport("user32.dll", EntryPoint = "IsWindow")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWindowAlive(IntPtr hWnd);
        [DllImport("user32.dll")] private static extern void PostQuitMessage(int exitCode);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ShowWindow(IntPtr hWnd, int command);
        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetLayeredWindowAttributes(IntPtr hWnd, uint colorKey, byte alpha, uint flags);
    }

    /// Chemin écrit dans la boîte « Open » (fenêtre de FL `pid`), puis Ouvrir : null si elle s'est refermée.
    public static string? Choose(IntPtr dialog, string path, uint pid)
    {
        Win32.GetWindowThreadProcessId(dialog, out var owner);
        if (owner != pid || !Win32.IsWindowVisible(dialog)) return Loc.T("boîte « Open » introuvable");
        if (FileNameField(dialog) is not { } field) return Loc.T("champ du nom de fichier introuvable dans la boîte « Open »");
        if (Win32.SendMessageTimeoutText(field, Win32.WM_SETTEXT, UIntPtr.Zero, path, Win32.SMTO_ABORTIFHUNG, 1_000, out _) == IntPtr.Zero)
            return Loc.T("la boîte « Open » n'a pas répondu");
        Thread.Sleep(30);
        Win32.PostMessageW(dialog, Win32.WM_COMMAND, new UIntPtr(IdOk), IntPtr.Zero);              // Ouvrir
        for (var i = 0; i < 60; i++)
        {
            Thread.Sleep(50);
            if (!Win32.IsWindow(dialog) || !Win32.IsWindowVisible(dialog)) return null;
        }
        return Loc.T("la boîte « Open » n'a pas pris le fichier");
    }

    /// Champ du nom de fichier : la liste déroulante cmb13 (son champ de texte), sinon le champ edt1 ; cherchés parmi
    /// tous les descendants (les boîtes récentes les rangent plus bas).
    private static IntPtr? FileNameField(IntPtr dialog)
    {
        IntPtr? found = null;
        var name = new StringBuilder(32);
        Win32.EnumChildWindows(dialog, (child, _) =>
        {
            var id = Win32.GetDlgCtrlID(child);
            if (id != FileNameCombo && id != FileNameEdit) return true;
            name.Clear();
            Win32.GetClassNameW(child, name, name.Capacity);
            if (name.ToString() == "Edit")
            {
                found = child;
                return false;
            }
            IntPtr? edit = null;
            Win32.EnumChildWindows(child, (inner, _) =>
            {
                name.Clear();
                Win32.GetClassNameW(inner, name, name.Capacity);
                if (name.ToString() != "Edit") return true;
                edit = inner;
                return false;
            }, IntPtr.Zero);
            if (edit is null) return true;
            found = edit;
            return false;
        }, IntPtr.Zero);
        return found;
    }

    [DllImport("ole32.dll")] private static extern int OleInitialize(IntPtr reserved);
    [DllImport("ole32.dll")] private static extern void OleUninitialize();
    [DllImport("ole32.dll")] private static extern int DoDragDrop(IntPtr dataObject, IDropSource source, uint okEffects, out uint effect);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
    private static extern int SHCreateItemFromParsingName(string path, IntPtr bindContext, [MarshalAs(UnmanagedType.LPStruct)] Guid riid,
        out IShellItem item);

    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem
    {
        void BindToHandler(IntPtr bindContext, ref Guid handler, ref Guid riid, out IntPtr result);
    }
}

[ComImport, Guid("00000121-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IDropSource
{
    [PreserveSig] int QueryContinueDrag([MarshalAs(UnmanagedType.Bool)] bool escapePressed, uint keyState);
    [PreserveSig] int GiveFeedback(uint effect);
}

/// Source du glisser : continue tant que le bouton est enfoncé ; relâché par la macro (Release) → déposé, relâché
/// autrement, Échap ou l'abandon → annulé. `Starting` est appelé une fois, au premier tour du glisser.
[ComVisible(true)]
internal sealed class DropSource : IDropSource
{
    private const int S_OK = 0, DRAGDROP_S_DROP = 0x00040100, DRAGDROP_S_CANCEL = 0x00040101, DRAGDROP_S_USEDEFAULTCURSORS = 0x00040102;
    private const uint MK_LBUTTON = 0x1;

    public readonly ManualResetEventSlim Started = new();
    public readonly ManualResetEventSlim Ended = new();
    public volatile bool Release;
    public volatile bool Cancel;
    public Action? Starting;

    public int QueryContinueDrag(bool escapePressed, uint keyState)
    {
        Begin();
        if (escapePressed || Cancel) return DRAGDROP_S_CANCEL;
        if ((keyState & MK_LBUTTON) != 0) return S_OK;
        return Release ? DRAGDROP_S_DROP : DRAGDROP_S_CANCEL;
    }

    public int GiveFeedback(uint effect)
    {
        Begin();
        return DRAGDROP_S_USEDEFAULTCURSORS;
    }

    private void Begin()
    {
        if (Started.IsSet) return;
        Starting?.Invoke();
        Started.Set();
    }
}
