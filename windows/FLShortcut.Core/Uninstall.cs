// Désinstallation sur Windows, comme le Mac (Uninstaller.swift : « plus aucune trace ») : le désinstalleur d'Inno
// Setup (lancé par « Désinstaller FL Shortcuts… » du menu de l'icône, ou par Paramètres › Applications) ferme l'app,
// puis la relance avec « --uninstall-cleanup », qui retire ce que l'app a écrit hors de son dossier : raccourcis et
// macros (%APPDATA%), réglages, clé du lien, session du compte et journal (%LOCALAPPDATA%), script dans FL Studio.
// Inno retire ensuite le dossier de l'app, le menu Démarrer, l'icône du Bureau et le lancement au démarrage.
// Une mise à jour ne passe jamais par ici : rien n'est perdu d'une version à l'autre.
using System.Text.Json;

namespace FLShortcut.Core;

public static class UninstallTraces
{
    /// Nom de l'app, puis son ancien nom (« FL Shortcut »).
    public static readonly string[] Names = { "FL Shortcuts", "FL Shortcut" };
    public const string ScriptFile = "device_FLShortcut.py";

    /// Dossiers de données, sous les deux noms.
    public static List<string> DataFolders(string roaming, string local) =>
        Names.SelectMany(n => new[] { Path.Combine(roaming, n), Path.Combine(local, n) }).ToList();

    /// Dossiers du script dans FL Studio : celui que l'app a noté (un autre dossier Hardware choisi à la main), puis
    /// l'emplacement par défaut, sous les deux noms.
    public static List<string> ScriptFolders(string documents, string? recordedScript)
    {
        var folders = new List<string>();
        if (recordedScript is { Length: > 0 } && Path.GetDirectoryName(recordedScript) is { Length: > 0 } dir)
            folders.Add(dir);
        var hardware = Path.Combine(documents, "Image-Line", "FL Studio", "Settings", "Hardware");
        folders.AddRange(Names.Select(n => Path.Combine(hardware, n)));
        return folders.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }

    /// Chemin du script noté dans settings.json (« ScriptPath ») ; null s'il n'y est pas ou si le fichier est illisible.
    public static string? RecordedScript(string settingsJson)
    {
        try
        {
            using var doc = JsonDocument.Parse(settingsJson);
            return doc.RootElement.ValueKind == JsonValueKind.Object
                   && doc.RootElement.TryGetProperty("ScriptPath", out var p) && p.ValueKind == JsonValueKind.String
                ? p.GetString() : null;
        }
        catch (JsonException) { return null; }
    }

    /// Le dossier ne contient que notre script (et ce que Python ou Windows posent à côté) : jamais un dossier de
    /// l'utilisateur, ni un autre script de FL.
    public static bool OnlyOurScript(string dir) =>
        Directory.EnumerateFileSystemEntries(dir)
            .Select(Path.GetFileName)
            .All(n => string.Equals(n, ScriptFile, StringComparison.OrdinalIgnoreCase)
                      || string.Equals(n, "__pycache__", StringComparison.OrdinalIgnoreCase)
                      || string.Equals(n, "desktop.ini", StringComparison.OrdinalIgnoreCase));

    /// Retire tout ; renvoie ce qui a été retiré (dossiers, pour le journal de la CI). Un lien n'est jamais suivi ;
    /// un dossier du script n'est retiré que s'il porte notre nom et ne contient que notre script.
    public static List<string> RemoveAll(string roaming, string local, string documents)
    {
        // Le chemin du script est lu AVANT de retirer les réglages qui le notent.
        string? recorded = null;
        foreach (var name in Names)
        {
            var settings = Path.Combine(local, name, "settings.json");
            try
            {
                if (File.Exists(settings) && RecordedScript(File.ReadAllText(settings)) is { } path) { recorded = path; break; }
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
        var removed = new List<string>();
        foreach (var dir in ScriptFolders(documents, recorded))
        {
            var leaf = Path.GetFileName(Path.TrimEndingDirectorySeparator(dir));
            if (!Names.Contains(leaf, StringComparer.OrdinalIgnoreCase)) continue;
            if (TryDelete(dir, onlyOurScript: true)) removed.Add(dir);
        }
        foreach (var dir in DataFolders(roaming, local))
            if (TryDelete(dir, onlyOurScript: false)) removed.Add(dir);
        return removed;
    }

    private static bool TryDelete(string dir, bool onlyOurScript)
    {
        try
        {
            if (!Directory.Exists(dir)) return false;
            if (new DirectoryInfo(dir).LinkTarget is not null) return false;
            if (onlyOurScript && !OnlyOurScript(dir)) return false;
            Directory.Delete(dir, recursive: true);
            return true;
        }
        catch (IOException) { return false; }
        catch (UnauthorizedAccessException) { return false; }
    }
}
