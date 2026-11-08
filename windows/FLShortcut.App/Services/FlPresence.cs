// Audit : WIN-04 (FL identifié par le chemin complet de son exécutable, jamais par le titre de fenêtre ; la signature
//         Authenticode d'Image-Line, vérifiée par WinVerifyTrust, n'est plus exigée depuis le 08/11 — « que la
//         personne qui a même un crack puisse travailler avec FL Shortcuts » — seulement notée pour le diagnostic),
//         WIN-05 (FL lancé en administrateur détecté et signalé, jamais d'élévation), audit 04 (version lue dans FL64.exe).
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography.X509Certificates;
using System.Text;
using FLShortcut.App.Native;
using FLShortcut.Core;

namespace FLShortcut.App.Services;

/// `Signed` : signature d'Image-Line valide (diagnostic seulement : FL est reconnu sans elle).
internal sealed record FlProcessInfo(uint Pid, string Path, FlVersion? Version, bool Elevated, bool Signed = false);

internal static class FlPresence
{
    private static readonly string[] ExeNames = FlRecognition.ExeNames;

    /// (pid, heure de création) → FL ou non. Un pid réutilisé par un autre processus change d'heure de création.
    private static readonly ConcurrentDictionary<(uint, long), FlProcessInfo?> ByProcess = new();
    /// Chemin + date de modification → signature valide d'Image-Line.
    private static readonly ConcurrentDictionary<(string, DateTime), bool> SignatureCache = new();

    /// Processus au premier plan s'il s'agit de FL Studio (appel rapide : cache après la première vérification).
    public static FlProcessInfo? Foreground()
    {
        var hwnd = Win32.GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return null;
        Win32.GetWindowThreadProcessId(hwnd, out var pid);
        return pid == 0 ? null : Identify(pid);
    }

    public static uint ForegroundPid()
    {
        var hwnd = Win32.GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return 0;
        Win32.GetWindowThreadProcessId(hwnd, out var pid);
        return pid;
    }

    public static FlProcessInfo? Identify(uint pid)
    {
        var h = Win32.OpenProcess(Win32.PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (h == IntPtr.Zero)
        {
            // Accès refusé à un processus nommé FL : très probablement FL lancé en administrateur (WIN-05).
            return Marshal.GetLastWin32Error() == Win32.ERROR_ACCESS_DENIED && LooksLikeFlByName(pid)
                ? new FlProcessInfo(pid, "", null, Elevated: true)
                : null;
        }
        try
        {
            if (!Win32.GetProcessTimes(h, out var created, out _, out _, out _)) created = 0;
            return ByProcess.GetOrAdd((pid, created), _ => Inspect(h, pid));
        }
        finally
        {
            Win32.CloseHandle(h);
        }
    }

    /// FL Studio est-il lancé (n'importe quelle instance, signée ou non) ?
    public static bool IsRunning() => RunningInstance() is not null;

    /// Un processus porte le nom de FL Studio mais n'est pas reconnu (signature d'Image-Line absente ou invalide) :
    /// dit tel quel à l'utilisateur, au lieu de « FL Studio n'est pas ouvert » et de raccourcis qui ne font rien.
    public static bool NamedButUnrecognized()
    {
        foreach (var name in ExeNames)
        {
            Process[] procs;
            try { procs = Process.GetProcessesByName(System.IO.Path.GetFileNameWithoutExtension(name)); }
            catch { continue; }
            var unrecognized = false;
            foreach (var p in procs)
            {
                using (p)
                {
                    if (Identify((uint)p.Id) is null) unrecognized = true;
                }
            }
            if (unrecognized) return true;
        }
        return false;
    }

    public static FlProcessInfo? RunningInstance()
    {
        foreach (var name in ExeNames)
        {
            Process[] procs;
            try { procs = Process.GetProcessesByName(System.IO.Path.GetFileNameWithoutExtension(name)); }
            catch { continue; }
            foreach (var p in procs)
            {
                using (p)
                {
                    var info = Identify((uint)p.Id);
                    if (info is not null) return info;
                }
            }
        }
        // Copie renommée (« FL Studio 2024.exe »…) : les processus dont le nom commence par « FL », reconnus à leurs
        // informations de version.
        Process[] all;
        try { all = Process.GetProcesses(); }
        catch { return null; }
        FlProcessInfo? found = null;
        foreach (var p in all)
        {
            using (p)
            {
                if (found is not null || !FlRecognition.MaybeFl(p.ProcessName)) continue;
                found = Identify((uint)p.Id);
            }
        }
        return found;
    }

    private static FlProcessInfo? Inspect(IntPtr h, uint pid)
    {
        var sb = new StringBuilder(1024);
        var size = (uint)sb.Capacity;
        if (!Win32.QueryFullProcessImageNameW(h, 0, sb, ref size)) return null;
        var path = sb.ToString();
        var file = System.IO.Path.GetFileName(path);
        if (!FlRecognition.MaybeFl(file)) return null;                // rien d'autre n'est lu pour les autres programmes

        FlVersion? version = null;
        string? product = null, description = null;
        try
        {
            var fvi = FileVersionInfo.GetVersionInfo(path);
            version = FlVersion.Parse(fvi.ProductVersion) ?? FlVersion.Parse(fvi.FileVersion);
            product = fvi.ProductName;
            description = fvi.FileDescription;
        }
        catch { /* version inconnue : les actions resteront « non vérifiées » jusqu'au HELLO */ }
        if (!FlRecognition.Accepts(file, product, description)) return null;

        return new FlProcessInfo(pid, path, version, IsElevated(h), IsSignedByImageLine(path));
    }

    private static bool LooksLikeFlByName(uint pid)
    {
        try
        {
            using var p = Process.GetProcessById((int)pid);
            return ExeNames.Any(n => string.Equals(System.IO.Path.GetFileNameWithoutExtension(n), p.ProcessName,
                StringComparison.OrdinalIgnoreCase));
        }
        catch { return false; }
    }

    private static bool IsElevated(IntPtr process)
    {
        if (!Win32.OpenProcessToken(process, Win32.TOKEN_QUERY, out var token)) return false;
        try
        {
            return Win32.GetTokenInformation(token, Win32.TokenElevation, out var elevated, sizeof(int), out _) && elevated != 0;
        }
        finally { Win32.CloseHandle(token); }
    }

    internal static bool IsSignedByImageLine(string path)
    {
        DateTime stamp;
        try { stamp = File.GetLastWriteTimeUtc(path); }
        catch { return false; }
        return SignatureCache.GetOrAdd((path, stamp), _ => WinTrust.Verify(path) && SignerMatches(path));
    }

    private static bool SignerMatches(string path)
    {
        try
        {
#pragma warning disable SYSLIB0057 // CreateFromSignedFile : lecture du signataire après validation par WinVerifyTrust
            var cert = X509Certificate.CreateFromSignedFile(path);
#pragma warning restore SYSLIB0057
            return FlSigner.Matches(cert.Subject);       // « Image Line » ou « Image-Line »
        }
        catch { return false; }
    }
}

/// Vérification Authenticode (WinVerifyTrust, action WINTRUST_ACTION_GENERIC_VERIFY_V2), sans interface.
internal static class WinTrust
{
    private static readonly Guid GenericVerifyV2 = new("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");
    private const uint WTD_UI_NONE = 2, WTD_REVOKE_NONE = 0, WTD_CHOICE_FILE = 1;
    private const uint WTD_STATEACTION_VERIFY = 1, WTD_STATEACTION_CLOSE = 2, WTD_CACHE_ONLY_URL_RETRIEVAL = 0x1000;

    [StructLayout(LayoutKind.Sequential)]
    private struct WINTRUST_FILE_INFO
    {
        public uint cbStruct;
        public IntPtr pcwszFilePath;
        public IntPtr hFile;
        public IntPtr pgKnownSubject;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WINTRUST_DATA
    {
        public uint cbStruct;
        public IntPtr pPolicyCallbackData;
        public IntPtr pSIPClientData;
        public uint dwUIChoice;
        public uint fdwRevocationChecks;
        public uint dwUnionChoice;
        public IntPtr pFile;
        public uint dwStateAction;
        public IntPtr hWVTStateData;
        public IntPtr pwszURLReference;
        public uint dwProvFlags;
        public uint dwUIContext;
        public IntPtr pSignatureSettings;
    }

    [DllImport("wintrust.dll", CharSet = CharSet.Unicode)]
    private static extern int WinVerifyTrust(IntPtr hwnd, ref Guid pgActionID, ref WINTRUST_DATA pWVTData);

    public static bool Verify(string path)
    {
        var pathPtr = Marshal.StringToHGlobalUni(path);
        var fileInfo = new WINTRUST_FILE_INFO
        {
            cbStruct = (uint)Marshal.SizeOf<WINTRUST_FILE_INFO>(),
            pcwszFilePath = pathPtr,
        };
        var filePtr = Marshal.AllocHGlobal(Marshal.SizeOf<WINTRUST_FILE_INFO>());
        try
        {
            Marshal.StructureToPtr(fileInfo, filePtr, false);
            var data = new WINTRUST_DATA
            {
                cbStruct = (uint)Marshal.SizeOf<WINTRUST_DATA>(),
                dwUIChoice = WTD_UI_NONE,
                fdwRevocationChecks = WTD_REVOKE_NONE,
                dwUnionChoice = WTD_CHOICE_FILE,
                pFile = filePtr,
                dwStateAction = WTD_STATEACTION_VERIFY,
                dwProvFlags = WTD_CACHE_ONLY_URL_RETRIEVAL,
            };
            var action = GenericVerifyV2;
            var result = WinVerifyTrust(new IntPtr(-1), ref action, ref data);
            data.dwStateAction = WTD_STATEACTION_CLOSE;
            WinVerifyTrust(new IntPtr(-1), ref action, ref data);
            return result == 0;
        }
        catch { return false; }
        finally
        {
            Marshal.FreeHGlobal(filePtr);
            Marshal.FreeHGlobal(pathPtr);
        }
    }
}
