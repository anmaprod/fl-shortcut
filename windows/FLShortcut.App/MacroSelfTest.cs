// Essai CI des macros Windows (`--selftest-macros <dossier>`) : un faux FL dans l'appli elle-même (une vraie fenêtre
// Windows : barre de menus File/Options/Tools, fenêtre de réglages, menu de piste au clic droit, boîte « Open », dépôt
// de fichiers), et les vrais blocs joués dessus par le vrai pilote (clics, menus lus par Windows, glisser d'OLE, boîte
// « Open »). Seule cible : ce faux FL (même processus) ; aucun crochet, aucun port MIDI, aucun réglage écrit ; seul
// « macros-essai.txt » est écrit, dans un dossier qui existe déjà. Le preset d'essai est un fichier temporaire effacé.
using System.Runtime.InteropServices;
using System.Text;
using FLShortcut.App.Native;
using FLShortcut.App.Services;
using FLShortcut.Core;
using FLShortcut.Core.Macros;

namespace FLShortcut.App;

internal static class MacroSelfTest
{
    /// Le dossier donné après `--selftest-macros` (qui existe déjà), ou null : pas en mode essai.
    public static string? Folder { get; } = FolderFromCommandLine();

    private static string? FolderFromCommandLine()
    {
        var command = Environment.GetCommandLineArgs();
        var at = Array.FindIndex(command, a => string.Equals(a, "--selftest-macros", StringComparison.OrdinalIgnoreCase));
        return at >= 0 && at + 1 < command.Length && Directory.Exists(command[at + 1]) ? command[at + 1] : null;
    }

    private const int CmdTimeSelection = 101, CmdWholeSong = 102, CmdOpenState = 103, CmdSettings = 104, CmdPurge = 105,
        CmdGreyed = 106, CmdTrackOpen = 201, CmdTrackSave = 202, CmdTrackRename = 203;

    private static readonly object Gate = new();
    private static readonly List<string> Events = new();
    private static IntPtr _main, _settings;
    private static WndProc? _mainProc, _settingsProc;          // gardés vivants (sinon le GC libère les rappels)

    private static void Note(string e)
    {
        lock (Gate) Events.Add(e);
    }

    private static List<string> Seen()
    {
        lock (Gate) return Events.ToList();
    }

    /// Joue les essais sur un fil à part, écrit le rapport, puis `done` (fermeture de l'appli).
    public static void Run(string folder, Action done)
    {
        new Thread(() =>
        {
            var report = new List<string>();
            try { Scenarios(report); }
            catch (Exception e) { report.Add("ÉCHEC exception " + e.GetType().Name + " " + e.Message); }
            var failed = report.Any(l => l.StartsWith("ÉCHEC", StringComparison.Ordinal));
            report.Insert(0, failed ? "FAIL" : "PASS");
            try { File.WriteAllLines(Path.Combine(folder, "macros-essai.txt"), report); }
            catch (IOException) { }
            if (_main != IntPtr.Zero) Win32.PostMessageW(_main, WM_CLOSE, UIntPtr.Zero, IntPtr.Zero);
            done();
        }) { IsBackground = true, Name = "FL Shortcuts – essai des macros" }.Start();
    }

    private static void Scenarios(List<string> report)
    {
        var log = new List<string>();
        AppLog.Sink = (area, line) => { lock (log) log.Add($"{area} {line}"); };
        var ready = new ManualResetEventSlim();
        new Thread(() => FakeFl(ready)) { IsBackground = true, Name = "faux FL" }.Start();
        if (!ready.Wait(5_000) || _main == IntPtr.Zero)
        {
            report.Add("ÉCHEC faux FL non créé");
            return;
        }
        var pid = (uint)Environment.ProcessId;
        report.Add(FlControl.BringForward(pid) ? "OK faux FL devant" : "ÉCHEC faux FL pas devant (la suite échouera)");
        AimedClick? aimed = null;
        var driver = new WindowsFlDriver(pid, new MidiLink(), new AppSettings(), () => true, () => 0, () => aimed, a => a(), () => { });
        Win32.GetWindowRect(_main, out var m);

        StepResult Play(BlockBody body)
        {
            var fx = new MacroEffectsWindows(driver);
            fx.Begin(false);
            var state = new RunState(DateTime.UtcNow);
            var result = fx.Perform(body, state);
            fx.Cleanup(state);
            Thread.Sleep(300);
            return result;
        }
        string Text(StepResult r) => r switch
        {
            StepResult.Ok => "ok",
            StepResult.Fail f => "échec : " + f.Why,
            StepResult.Cancel c => "arrêt : " + c.Why,
            StepResult.Warn w => "avertissement : " + w.Why,
            _ => r.GetType().Name,
        };
        bool MenusOpen() => WindowsFlDriver.Enumerate(pid).Any(w => w.Window.Role == FlWindowRole.Menu);
        void Expect(string name, StepResult r, bool ok, string? evt)
        {
            var good = (r is StepResult.Ok) == ok && (evt is null || Seen().Contains(evt)) && !MenusOpen();
            report.Add($"{(good ? "OK" : "ÉCHEC")} {name} → {Text(r)}{(evt is null ? "" : $" · attendu « {evt} »")}"
                       + (MenusOpen() ? " · un menu est resté ouvert" : ""));
        }

        // 1. Menu de FL : File › Export › All playlist tracks › Time selection…, puis Tools › Macros › Purge.
        Expect("menu File › Export › All playlist tracks › Time selection",
            Play(new BlockBody.MenuBar(new[] { "File", "Export", "All playlist tracks", "Time selection..." })), true, $"cmd {CmdTimeSelection}");
        Expect("menu Tools › Macros › Purge unused audio clips",
            Play(new BlockBody.MenuBar(new[] { "Tools", "Macros", "Purge unused audio clips" })), true, $"cmd {CmdPurge}");
        // 2. Élément grisé : jamais cliqué, menus refermés.
        var greyed = Play(new BlockBody.MenuBar(new[] { "Tools", "Greyed item" }));
        Expect("élément grisé refusé", greyed, false, null);
        if (Seen().Contains($"cmd {CmdGreyed}")) report.Add("ÉCHEC l'élément grisé a été choisi");
        // 3. Options › Project general settings, puis un clic appris dans la fenêtre des réglages (400 × 300).
        Expect("menu Options › Project general settings",
            Play(new BlockBody.MenuBar(new[] { "Options", "Project general settings" })), true, $"cmd {CmdSettings}");
        Expect("clic appris dans la fenêtre des réglages",
            Play(new BlockBody.Click(new ClickTarget.FlWindowPoint(Corner.TopLeft, 60, 220, new Size2(400, 300)))), true, "settings click");
        // 4. Menu de la piste : clic droit sur la piste visée (dans le faux FL, hors de la fenêtre des réglages restée
        // ouverte), F puis O.
        aimed = new AimedClick(m.Left + 80, m.Bottom - 80, _main.ToInt64(), m.Right - m.Left, m.Bottom - m.Top, DateTime.UtcNow);
        Expect("menu de la piste (F, O)",
            Play(new BlockBody.TrackMenu("fo", new[] { "File", "Open mixer track state" }, TrackTarget.LastClicked, EnterPolicy.IfNeeded)),
            true, $"track {CmdTrackOpen}");
        // 5. Preset déposé sur la piste visée (glisser d'OLE, comme depuis l'Explorateur).
        var preset = Path.Combine(Path.GetTempPath(), $"FLS essai {Environment.ProcessId}.fst");
        File.WriteAllBytes(preset, new byte[] { 0x46, 0x4C });
        try
        {
            Expect("preset déposé sur la piste", Play(new BlockBody.DropFile(preset)), true, "drop " + Path.GetFileName(preset));
            // 6. Boîte « Open » : File › Open state… l'ouvre, le chemin y est écrit, Ouvrir.
            Play(new BlockBody.MenuBar(new[] { "File", "Open state..." }));
            var fx = new MacroEffectsWindows(driver);
            fx.Begin(false);
            var state = new RunState(DateTime.UtcNow);
            var waited = fx.Perform(new BlockBody.WaitWindow(WindowKind.Dialog, 5_000), state);
            var chosen = waited is StepResult.Ok ? fx.Perform(new BlockBody.ChooseFile(preset), state) : waited;
            Thread.Sleep(300);
            Expect("preset choisi dans la boîte « Open »", chosen, true, "open " + Path.GetFileName(preset));
        }
        finally { File.Delete(preset); }
        // 7. Lecture du texte (bouton à son nom) : la reconnaissance de texte de Windows est-elle là ?
        if (_settings != IntPtr.Zero && FlScreen.ReadWindow(_settings) is { } read)
            report.Add(read.Any(t => MenuText.Normalized(t.Text).Contains("tlme")) ? "OK texte lu dans la fenêtre des réglages"
                : $"INFO texte lu mais « Time signature » absent ({read.Count} textes)");
        else report.Add("INFO lecture du texte indisponible sur cette machine (langue de reconnaissance absente ?)");

        report.Add("");
        report.Add("Évènements du faux FL : " + string.Join(" | ", Seen()));
        report.Add("Journal :");
        lock (log) report.AddRange(log);
    }

    // ---------- Le faux FL (fil à part, sa propre boucle de messages) ----------

    private static void FakeFl(ManualResetEventSlim ready)
    {
        var instance = Win32.GetModuleHandleW(null);
        _mainProc = MainProc;
        _settingsProc = SettingsProc;
        Register("FLSEssaiPrincipal", _mainProc, instance);
        Register("FLSEssaiReglages", _settingsProc, instance);
        _main = CreateWindowExW(0, "FLSEssaiPrincipal", "FL Studio (essai)", WS_OVERLAPPEDWINDOW | WS_VISIBLE,
            100, 100, 900, 620, IntPtr.Zero, IntPtr.Zero, instance, IntPtr.Zero);
        if (_main != IntPtr.Zero)
        {
            SetMenu(_main, MenuBar());
            DragAcceptFiles(_main, true);
        }
        ready.Set();
        while (Win32.GetMessageW(out var msg, IntPtr.Zero, 0, 0) > 0)
        {
            Win32.TranslateMessage(ref msg);
            Win32.DispatchMessageW(ref msg);
        }
    }

    private static void Register(string name, WndProc proc, IntPtr instance)
    {
        var wc = new WNDCLASSEXW
        {
            cbSize = (uint)Marshal.SizeOf<WNDCLASSEXW>(),
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(proc),
            hInstance = instance,
            hCursor = LoadCursorW(IntPtr.Zero, new IntPtr(32512)),
            hbrBackground = new IntPtr(6),                    // COLOR_WINDOW + 1
            lpszClassName = name,
        };
        RegisterClassExW(ref wc);
    }

    private static IntPtr Popup(params (string Text, int Id, IntPtr Sub, bool Greyed)[] items)
    {
        var menu = Win32.CreatePopupMenu();
        foreach (var (text, id, sub, grey) in items)
            Win32.AppendMenuW(menu, (sub != IntPtr.Zero ? Win32.MF_POPUP : 0) | (grey ? Win32.MF_GRAYED : 0),
                sub != IntPtr.Zero ? (UIntPtr)(ulong)sub.ToInt64() : new UIntPtr((uint)id), text);
        return menu;
    }

    private static IntPtr MenuBar()
    {
        var all = Popup(("Time selection...", CmdTimeSelection, IntPtr.Zero, false), ("Whole song", CmdWholeSong, IntPtr.Zero, false));
        var export = Popup(("Wave file...", 199, IntPtr.Zero, false), ("All playlist tracks", 0, all, false));
        var file = Popup(("&New\tCtrl+N", 198, IntPtr.Zero, false), ("&Open state...", CmdOpenState, IntPtr.Zero, false), ("&Export", 0, export, false));
        var options = Popup(("&Project general settings", CmdSettings, IntPtr.Zero, false), ("&Audio settings", 197, IntPtr.Zero, false));
        var macros = Popup(("Purge unused audio clips", CmdPurge, IntPtr.Zero, false));
        var tools = Popup(("&Macros", 0, macros, false), ("Greyed item", CmdGreyed, IntPtr.Zero, true));
        var bar = CreateMenu();
        foreach (var (title, sub) in new[] { ("&FILE", file), ("&OPTIONS", options), ("&TOOLS", tools) })
            Win32.AppendMenuW(bar, Win32.MF_POPUP, (UIntPtr)(ulong)sub.ToInt64(), title);
        return bar;
    }

    private static IntPtr MainProc(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        switch (msg)
        {
            case Win32.WM_COMMAND:
            {
                var id = (int)(wParam.ToInt64() & 0xFFFF);
                Note($"cmd {id}");
                if (id == CmdSettings && _settings == IntPtr.Zero)
                {
                    _settings = CreateWindowExW(0, "FLSEssaiReglages", "Project general settings", WS_POPUP | WS_CAPTION | WS_SYSMENU | WS_VISIBLE,
                        250, 180, 400, 300, hwnd, IntPtr.Zero, Win32.GetModuleHandleW(null), IntPtr.Zero);
                    CreateWindowExW(0, "STATIC", "Time signature 3/4", WS_CHILD | WS_VISIBLE, 20, 20, 300, 30, _settings, IntPtr.Zero,
                        Win32.GetModuleHandleW(null), IntPtr.Zero);
                }
                if (id == CmdOpenState) OpenBox(hwnd);
                return IntPtr.Zero;
            }
            case WM_RBUTTONDOWN:
            {
                var track = Popup(("&Open mixer track state", CmdTrackOpen, IntPtr.Zero, false), ("&Save mixer track state as", CmdTrackSave, IntPtr.Zero, false));
                var menu = Popup(("&File", 0, track, false), ("&Rename, color and icon", CmdTrackRename, IntPtr.Zero, false));
                Win32.GetCursorPos(out var p);
                Win32.SetForegroundWindow(hwnd);
                var chosen = Win32.TrackPopupMenuEx(menu, Win32.TPM_RETURNCMD | Win32.TPM_RIGHTBUTTON, p.X, p.Y, hwnd, IntPtr.Zero);
                Win32.DestroyMenu(menu);
                Note($"track {chosen}");
                return IntPtr.Zero;
            }
            case WM_DROPFILES:
            {
                var name = new StringBuilder(520);
                DragQueryFileW(wParam, 0, name, (uint)name.Capacity);
                DragFinish(wParam);
                Note("drop " + Path.GetFileName(name.ToString()));
                return IntPtr.Zero;
            }
            case WM_CLOSE:
                DestroyWindow(hwnd);
                return IntPtr.Zero;
            case WM_DESTROY:
                PostQuitMessage(0);
                return IntPtr.Zero;
        }
        return DefWindowProcW(hwnd, msg, wParam, lParam);
    }

    private static IntPtr SettingsProc(IntPtr hwnd, uint msg, IntPtr wParam, IntPtr lParam)
    {
        if (msg == Win32.WM_LBUTTONDOWN) Note("settings click");
        return DefWindowProcW(hwnd, msg, wParam, lParam);
    }

    /// La boîte « Open » standard de Windows, comme celle de FL ; le fichier choisi est noté (son nom seulement).
    private static void OpenBox(IntPtr owner)
    {
        var buffer = Marshal.AllocHGlobal(520 * 2);
        try
        {
            Marshal.Copy(new byte[520 * 2], 0, buffer, 520 * 2);
            var ofn = new OPENFILENAMEW
            {
                lStructSize = (uint)Marshal.SizeOf<OPENFILENAMEW>(),
                hwndOwner = owner,
                lpstrFile = buffer,
                nMaxFile = 520,
                Flags = 0x00080000 | 0x00001000 | 0x00000008,       // OFN_EXPLORER | OFN_FILEMUSTEXIST | OFN_NOCHANGEDIR
            };
            Note(GetOpenFileNameW(ref ofn) ? "open " + Path.GetFileName(Marshal.PtrToStringUni(buffer) ?? "") : "open annulé");
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    // ---------- Déclarations propres au faux FL ----------

    private const uint WS_OVERLAPPEDWINDOW = 0x00CF0000, WS_VISIBLE = 0x10000000, WS_POPUP = 0x80000000, WS_CAPTION = 0x00C00000,
        WS_SYSMENU = 0x00080000, WS_CHILD = 0x40000000;
    private const uint WM_CLOSE = 0x0010, WM_DESTROY = 0x0002, WM_RBUTTONDOWN = 0x0204, WM_DROPFILES = 0x0233;

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

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct OPENFILENAMEW
    {
        public uint lStructSize;
        public IntPtr hwndOwner;
        public IntPtr hInstance;
        public string? lpstrFilter;
        public IntPtr lpstrCustomFilter;
        public uint nMaxCustFilter;
        public uint nFilterIndex;
        public IntPtr lpstrFile;
        public uint nMaxFile;
        public IntPtr lpstrFileTitle;
        public uint nMaxFileTitle;
        public string? lpstrInitialDir;
        public string? lpstrTitle;
        public uint Flags;
        public ushort nFileOffset;
        public ushort nFileExtension;
        public string? lpstrDefExt;
        public IntPtr lCustData;
        public IntPtr lpfnHook;
        public IntPtr lpTemplateName;
        public IntPtr pvReserved;
        public uint dwReserved;
        public uint FlagsEx;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern ushort RegisterClassExW(ref WNDCLASSEXW wc);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateWindowExW(uint exStyle, string className, string windowName, uint style, int x, int y, int width,
        int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);
    [DllImport("user32.dll")] private static extern IntPtr DefWindowProcW(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyWindow(IntPtr hWnd);
    [DllImport("user32.dll")] private static extern IntPtr CreateMenu();
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetMenu(IntPtr hWnd, IntPtr hMenu);
    [DllImport("user32.dll")] private static extern void PostQuitMessage(int exitCode);
    [DllImport("user32.dll")] private static extern IntPtr LoadCursorW(IntPtr instance, IntPtr name);
    [DllImport("shell32.dll")] private static extern void DragAcceptFiles(IntPtr hWnd, [MarshalAs(UnmanagedType.Bool)] bool accept);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] private static extern uint DragQueryFileW(IntPtr drop, uint index, StringBuilder? file, uint count);
    [DllImport("shell32.dll")] private static extern void DragFinish(IntPtr drop);
    [DllImport("comdlg32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetOpenFileNameW(ref OPENFILENAMEW ofn);
}
