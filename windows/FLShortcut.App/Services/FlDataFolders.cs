// Où chercher la « Plugin database » de FL sous Windows (09/11, « les mêmes dossiers que pour Mac… Image-Line › Plugin
// database › Installed › Effects et Generators ») : PluginDatabase.Roots (cœur, testé) avec les dossiers propres à ce
// PC : le script installé, les dossiers de données notés par FL dans le registre, et chaque dossier Documents possible
// (celui de Windows, celui du profil, celui de OneDrive). Lu seulement ; jamais d'exception.
using Microsoft.Win32;
using FLShortcut.Core.Macros;

namespace FLShortcut.App.Services;

internal static class FlDataFolders
{
    public static IReadOnlyList<string> PluginRoots(string? scriptPath) =>
        PluginDatabase.Roots(scriptPath, Documents(), Registered());

    /// Les dossiers « Settings\Hardware » de FL possibles (13/11 : lien posé tout seul au lancement).
    public static IReadOnlyList<string> HardwareCandidates() => FLShortcut.Core.FlScriptPlace.Candidates(Documents(), Registered());

    /// Les dossiers Documents possibles, sans doublon.
    private static List<string> Documents()
    {
        var output = new List<string>();
        void Add(string? path)
        {
            if (!string.IsNullOrWhiteSpace(path) && !output.Contains(path, StringComparer.OrdinalIgnoreCase)) output.Add(path);
        }
        Add(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments));
        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        if (profile.Length > 0) Add(Path.Combine(profile, "Documents"));
        foreach (var name in new[] { "OneDrive", "OneDriveConsumer", "OneDriveCommercial" })
            if (Environment.GetEnvironmentVariable(name) is { Length: > 0 } drive) Add(Path.Combine(drive, "Documents"));
        return output;
    }

    /// Dossiers de données que FL a notés pour cet utilisateur (Software › Image-Line › Shared › Paths) : seulement des
    /// chemins complets ; rien d'autre n'est lu.
    private static List<string> Registered()
    {
        var output = new List<string>();
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Image-Line\Shared\Paths");
            if (key is null) return output;
            foreach (var name in key.GetValueNames())
            {
                if (key.GetValue(name) is string { Length: > 2 and < 400 } path && Path.IsPathRooted(path)) output.Add(path);
            }
        }
        catch (Exception e) when (e is System.Security.SecurityException or IOException or UnauthorizedAccessException) { }
        return output;
    }
}
