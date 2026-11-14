// Désinstallation Windows (UninstallTraces) : plus aucune trace de l'app, comme le Mac, sans jamais toucher à ce qui
// n'est pas à elle (autre script de FL, fichier de l'utilisateur posé dans le dossier du script).
using System.Text.Json;
using FLShortcut.Core;
using Xunit;

namespace FLShortcut.Core.Tests;

public sealed class UninstallTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "fls-desinstallation-" + Guid.NewGuid().ToString("N"));
    private string Roaming => Path.Combine(_root, "Roaming");
    private string Local => Path.Combine(_root, "Local");
    private string Documents => Path.Combine(_root, "Documents");
    private string Hardware => Path.Combine(Documents, "Image-Line", "FL Studio", "Settings", "Hardware");

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch (IOException) { }
    }

    private static void Put(string path, string text = "x")
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, text);
    }

    [Fact]
    public void EverythingOfTheAppIsRemovedAndNothingElse()
    {
        // Données sous le nom actuel et l'ancien nom.
        Put(Path.Combine(Roaming, "FL Shortcuts", "profile.json"));
        Put(Path.Combine(Roaming, "FL Shortcuts", "macros.json"));
        Put(Path.Combine(Local, "FL Shortcut", "journal.txt"));
        // Script installé dans un autre dossier Hardware, choisi à la main, et noté dans les réglages.
        var other = Path.Combine(_root, "D", "FL Studio", "Settings", "Hardware");
        var recorded = Path.Combine(other, "FL Shortcuts", UninstallTraces.ScriptFile);
        Put(recorded);
        Put(Path.Combine(Local, "FL Shortcuts", "settings.json"), JsonSerializer.Serialize(new { ScriptPath = recorded }));
        Put(Path.Combine(Local, "FL Shortcuts", "compte.bin"));
        // Script à l'emplacement par défaut, sous l'ancien nom, avec ce que Python pose à côté.
        Put(Path.Combine(Hardware, "FL Shortcut", UninstallTraces.ScriptFile));
        Directory.CreateDirectory(Path.Combine(Hardware, "FL Shortcut", "__pycache__"));
        // Ce qui n'est pas à l'app : un autre script de FL, et un fichier de l'utilisateur dans notre dossier de script.
        Put(Path.Combine(Hardware, "Autre controleur", "device_Autre.py"));
        Put(Path.Combine(Hardware, "FL Shortcuts", UninstallTraces.ScriptFile));
        Put(Path.Combine(Hardware, "FL Shortcuts", "a moi.txt"));

        var removed = UninstallTraces.RemoveAll(Roaming, Local, Documents);

        Assert.False(Directory.Exists(Path.Combine(Roaming, "FL Shortcuts")));
        Assert.False(Directory.Exists(Path.Combine(Local, "FL Shortcuts")));
        Assert.False(Directory.Exists(Path.Combine(Local, "FL Shortcut")));
        Assert.False(Directory.Exists(Path.GetDirectoryName(recorded)));
        Assert.False(Directory.Exists(Path.Combine(Hardware, "FL Shortcut")));
        Assert.True(File.Exists(Path.Combine(Hardware, "Autre controleur", "device_Autre.py")));
        Assert.True(File.Exists(Path.Combine(Hardware, "FL Shortcuts", "a moi.txt")));
        Assert.True(Directory.Exists(other));                // seulement notre dossier, jamais le dossier Hardware
        Assert.Equal(5, removed.Count);
    }

    [Fact]
    public void NothingToRemoveIsNotAnError()
    {
        Assert.Empty(UninstallTraces.RemoveAll(Roaming, Local, Documents));
    }

    [Fact]
    public void RecordedScriptIsReadSafely()
    {
        Assert.Equal(@"C:\x\device_FLShortcut.py", UninstallTraces.RecordedScript("{\"ScriptPath\":\"C:\\\\x\\\\device_FLShortcut.py\"}"));
        Assert.Null(UninstallTraces.RecordedScript("{\"ScriptPath\":null}"));
        Assert.Null(UninstallTraces.RecordedScript("illisible"));
        Assert.Null(UninstallTraces.RecordedScript("[]"));
    }

    /// Un réglage modifié par un autre programme ne fait jamais retirer un dossier qui ne porte pas notre nom.
    [Fact]
    public void ARecordedPathOutsideOurFolderIsIgnored()
    {
        var music = Path.Combine(_root, "Musique");
        Put(Path.Combine(music, UninstallTraces.ScriptFile));
        Put(Path.Combine(Local, "FL Shortcuts", "settings.json"),
            JsonSerializer.Serialize(new { ScriptPath = Path.Combine(music, UninstallTraces.ScriptFile) }));
        UninstallTraces.RemoveAll(Roaming, Local, Documents);
        Assert.True(File.Exists(Path.Combine(music, UninstallTraces.ScriptFile)));
    }
}
