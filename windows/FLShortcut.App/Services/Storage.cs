// Audit : SEC-01 / PROTOCOL.md §2 (clé de 16 octets par installation, protégée par DPAPI « utilisateur »),
//         SEC-05 / SEC-06 / WIN-08 (aucun lien symbolique ni jonction suivi, fichier temporaire dans le même dossier
//         puis remplacement atomique), REL-01 / REL-02 (profil tolérant, copie de secours, écriture atomique),
//         REL-22 (empreinte SHA-256 du script installé pour détecter une modification).
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FLShortcut.Core;
using FLShortcut.Core.Macros;

namespace FLShortcut.App.Services;

internal static class AppPaths
{
    /// %LOCALAPPDATA%\FL Shortcuts (clé, réglages) — jamais itinérant.
    public static string Local { get; } = Ensure(Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FL Shortcuts"));

    /// %APPDATA%\FL Shortcuts (profil de raccourcis).
    public static string Roaming { get; } = Ensure(Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "FL Shortcuts"));

    /// Nom de l'app avant « FL Shortcuts ».
    public const string OldName = "FL Shortcut";

    /// Un dossier à l'ancien nom (un vrai dossier, pas un lien) prend le nouveau nom avec son contenu, si le nouveau
    /// n'existe pas encore ; en cas d'échec, l'ancien reste utilisé (rien n'est perdu).
    private static string Ensure(string dir)
    {
        var old = Path.Combine(Path.GetDirectoryName(dir)!, OldName);
        if (!Directory.Exists(dir) && Directory.Exists(old) && new DirectoryInfo(old).LinkTarget is null)
        {
            try { Directory.Move(old, dir); }
            catch (IOException) { return old; }
            catch (UnauthorizedAccessException) { return old; }
        }
        Directory.CreateDirectory(dir);
        return dir;
    }
}

internal static class SafeFile
{
    /// Refuse un fichier, ou l'un de ses 3 dossiers parents, qui serait un lien symbolique ou une jonction (SEC-06).
    /// On s'arrête là : un profil Windows déplacé par jonction (C:\Users → D:\Users) reste accepté, et les
    /// dossiers OneDrive (fichiers à la demande) ne sont pas des liens.
    public static void EnsureNoLinks(string path, int levels = 3)
    {
        var full = Path.GetFullPath(path);
        if (File.Exists(full) && new FileInfo(full).LinkTarget is not null) throw new IOException($"Fichier refusé (lien) : {full}");
        var d = Directory.Exists(full) ? new DirectoryInfo(full) : new FileInfo(full).Directory;
        for (var i = 0; i <= levels && d is not null; i++, d = d.Parent)
        {
            if (d.Exists && d.LinkTarget is not null) throw new IOException($"Dossier refusé (lien) : {d.FullName}");
        }
    }

    /// Écriture atomique : fichier temporaire dans le même dossier, puis remplacement (REL-02).
    public static void WriteAtomic(string path, byte[] content)
    {
        var dir = Path.GetDirectoryName(Path.GetFullPath(path))!;
        Directory.CreateDirectory(dir);
        EnsureNoLinks(path);
        var tmp = Path.Combine(dir, $".{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");
        try
        {
            using (var fs = new FileStream(tmp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            {
                fs.Write(content);
                fs.Flush(true);
            }
            File.Move(tmp, path, overwrite: true);
        }
        finally
        {
            try { if (File.Exists(tmp)) File.Delete(tmp); } catch { /* nettoyage au mieux */ }
        }
    }
}

/// Clé du lien appli ↔ script FL, chiffrée par DPAPI pour l'utilisateur courant.
internal static class SecretStore
{
    private static string KeyPath => Path.Combine(AppPaths.Local, "link.key");
    // Ancien nom de l'app gardé exprès : changer ce texte rendrait illisibles les clés déjà enregistrées.
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("FL Shortcut link key v2");

    public static byte[]? Load()
    {
        try
        {
            if (!File.Exists(KeyPath)) return null;
            SafeFile.EnsureNoLinks(KeyPath);
            var key = ProtectedData.Unprotect(File.ReadAllBytes(KeyPath), Entropy, DataProtectionScope.CurrentUser);
            return key.Length == FlProtocol.KeyLength ? key : null;
        }
        catch { return null; }
    }

    public static byte[] CreateNew()
    {
        var key = RandomNumberGenerator.GetBytes(FlProtocol.KeyLength);
        SafeFile.WriteAtomic(KeyPath, ProtectedData.Protect(key, Entropy, DataProtectionScope.CurrentUser));
        return key;
    }
}

internal sealed class AppSettings
{
    public bool Enabled { get; set; } = true;
    public bool Onboarded { get; set; }
    public string? ScriptPath { get; set; }
    public string? ScriptSha256 { get; set; }
    public string Profile { get; set; } = "Recommended";
    /// Vrai = actions MIDI avec le script dans FL (loopMIDI requis). Faux = mode léger, rien dans FL.
    /// Absent (null) : mode léger pour une nouvelle installation, mode MIDI pour qui avait déjà installé le
    /// script (mise à jour sans rien casser).
    public bool? MidiActions { get; set; }
    /// Organiser : couleur, dégradé, icône et départ dans le Mixer de chaque famille (JSON comme sur le Mac).
    public string? OrganizerStyles { get; set; }
    /// Organiser : l'ordre des familles glissées dans l'aperçu.
    public List<string>? OrganizerFamilyOrder { get; set; }
    /// Organiser : le tuto en images a été vu (plus montré tout seul ; « Revoir le tuto » dans Options). Rien de sensible.
    public bool OrganizerTutorialSeen { get; set; }
    /// Accord pour partager les corrections de l'IA (null : jamais demandé).
    public bool? ShareCorrections { get; set; }
    /// Versions organisées en attente de validation (relues par CopyApprovalRules.Decode : seules les sûres restent).
    public string? PendingCopies { get; set; }
    /// Macros : ce qui a été appris (Entrée après la dernière lettre d'un menu de FL). Clés de la liste blanche
    /// seulement (MacroValidation.LearnedEnterKeys), jamais lues pour autre chose.
    public Dictionary<string, bool>? MacroMemory { get; set; }

    private static string FilePath => Path.Combine(AppPaths.Local, "settings.json");

    public static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath)) ?? new AppSettings();
        }
        catch { /* réglages illisibles : valeurs par défaut */ }
        return new AppSettings();
    }

    public void Save()
    {
        try { SafeFile.WriteAtomic(FilePath, JsonSerializer.SerializeToUtf8Bytes(this, new JsonSerializerOptions { WriteIndented = true })); }
        catch { /* non bloquant */ }
    }
}

internal static class ProfileStore
{
    private static string FilePath => Path.Combine(AppPaths.Roaming, "profile.json");

    /// Profil enregistré, ou null s'il n'existe pas. Un fichier illisible est mis de côté (jamais écrasé).
    public static List<Shortcut>? Load(out string? warning)
    {
        warning = null;
        if (!File.Exists(FilePath)) return null;
        try
        {
            SafeFile.EnsureNoLinks(FilePath);
            var decoded = ProfileCodec.Decode(File.ReadAllText(FilePath));
            if (decoded.Skipped > 0) warning = $"{decoded.Skipped} raccourci(s) illisible(s) ont été ignorés.";
            return decoded.Shortcuts;
        }
        catch (Exception e)
        {
            try { File.Copy(FilePath, Path.Combine(AppPaths.Roaming, $"profile.illisible-{DateTime.Now:yyyyMMdd-HHmmss}.json")); }
            catch { }
            warning = $"Ton profil était illisible ({e.Message}). Une copie a été gardée, le profil recommandé est chargé.";
            return null;
        }
    }

    public static void Save(IEnumerable<Shortcut> shortcuts) =>
        SafeFile.WriteAtomic(FilePath, Encoding.UTF8.GetBytes(ProfileCodec.Encode(shortcuts)));
}

/// Journal de l'appli (AppLog : étapes des macros et de l'Organiser, des mots fixes et des nombres seulement) dans
/// %LOCALAPPDATA%\FL Shortcuts\journal.txt ; au-delà de 512 Ko, l'ancien devient journal.1.txt (un seul gardé).
internal static class AppLogFile
{
    private const long MaxBytes = 512 * 1024;
    private static readonly object Gate = new();
    private static string FilePath => Path.Combine(AppPaths.Local, "journal.txt");

    public static void Install() => AppLog.Sink = Write;

    private static void Write(string area, string line)
    {
        lock (Gate)
        {
            try
            {
                SafeFile.EnsureNoLinks(FilePath);
                if (File.Exists(FilePath) && new FileInfo(FilePath).Length > MaxBytes)
                    File.Move(FilePath, Path.Combine(AppPaths.Local, "journal.1.txt"), overwrite: true);
                File.AppendAllText(FilePath, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff} {area} {line}{Environment.NewLine}");
            }
            catch { /* journal au mieux : jamais bloquant */ }
        }
    }
}

/// Bibliothèque des macros : %APPDATA%\FL Shortcuts\macros.json (même format que le Mac). Fichier ou dossier lié,
/// ou trop gros : refusé (MacroLibraryStore le dit et n'écrit plus). Copies de secours à côté : « precedente »
/// unique (remplacée à chaque lancement), les autres datées.
internal sealed class MacroFileStorage : IMacroLibraryStorage
{
    private readonly string _path;

    public MacroFileStorage(string? path = null) => _path = path ?? Path.Combine(AppPaths.Roaming, "macros.json");

    public byte[]? Read()
    {
        if (!File.Exists(_path)) return null;
        SafeFile.EnsureNoLinks(_path);
        if (new FileInfo(_path).Length > MacroLibraryCodec.MaxBytes) throw new IOException(Loc.T("fichier de plus de 8 Mo"));
        return File.ReadAllBytes(_path);
    }

    public void Write(byte[] data) => SafeFile.WriteAtomic(_path, data);

    public string Backup(byte[] data, string label)
    {
        var name = label == MacroLibraryStore.PreviousLabel
            ? $"macros.{label}.json" : $"macros.{label}-{DateTimeOffset.UtcNow.ToUnixTimeSeconds()}.json";
        SafeFile.WriteAtomic(Path.Combine(Path.GetDirectoryName(_path)!, name), data);
        return name;
    }
}

/// Installe le script FL avec la clé de l'installation.
internal static class ScriptInstaller
{
    public const string FileName = "device_FLShortcut.py";

    public static string DefaultHardwareFolder => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "Image-Line", "FL Studio", "Settings", "Hardware");

    public static string Template()
    {
        using var s = Assembly.GetExecutingAssembly().GetManifestResourceStream(FileName)
            ?? throw new InvalidOperationException("Script FL introuvable dans l'application.");
        using var r = new StreamReader(s, Encoding.UTF8);
        return r.ReadToEnd();
    }

    /// Écrit « Hardware\FL Shortcuts\device_FLShortcut.py ». Renvoie le chemin et l'empreinte SHA-256.
    public static (string Path, string Sha256) Install(string hardwareFolder, byte[] key)
    {
        if (!string.Equals(Path.GetFileName(Path.TrimEndingDirectorySeparator(hardwareFolder)), "Hardware", StringComparison.OrdinalIgnoreCase))
            throw new IOException("Choisis le dossier « Settings\\Hardware » de FL Studio.");
        var dir = Path.Combine(hardwareFolder, "FL Shortcuts");
        Directory.CreateDirectory(dir);
        SafeFile.EnsureNoLinks(dir);
        var content = Encoding.UTF8.GetBytes(ScriptTemplate.Inject(key, Template()));
        var path = Path.Combine(dir, FileName);
        SafeFile.WriteAtomic(path, content);
        // Ancien nom de l'app : son dossier de script est retiré (FL proposerait deux fois le Controller type),
        // seulement s'il ne contient que notre script.
        var old = Path.Combine(hardwareFolder, AppPaths.OldName);
        try
        {
            if (Directory.Exists(old) && new DirectoryInfo(old).LinkTarget is null
                && File.Exists(Path.Combine(old, FileName)) && OnlyOurScript(old))
                Directory.Delete(old, true);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        return (path, Convert.ToHexString(SHA256.HashData(content)));
    }

    /// Le script installé a-t-il été modifié par un autre logiciel depuis l'installation ?
    public static bool IsIntact(string? path, string? sha256)
    {
        if (path is null || sha256 is null || !File.Exists(path)) return false;
        try
        {
            if (!string.Equals(Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))), sha256, StringComparison.OrdinalIgnoreCase))
                return false;
            // Audit 03 (WIN-10/11) : un autre fichier Python (ex. « transport.py ») ou un dossier à côté du script
            // pourrait masquer un module de FL et exécuter du code dans FL. Seul notre script est accepté.
            return OnlyOurScript(Path.GetDirectoryName(path)!);
        }
        catch { return false; }
    }

    private static bool OnlyOurScript(string dir) =>
        Directory.EnumerateFileSystemEntries(dir)
            .Select(Path.GetFileName)
            .All(n => string.Equals(n, FileName, StringComparison.OrdinalIgnoreCase)
                      || string.Equals(n, "__pycache__", StringComparison.OrdinalIgnoreCase)
                      || string.Equals(n, "desktop.ini", StringComparison.OrdinalIgnoreCase));
}
