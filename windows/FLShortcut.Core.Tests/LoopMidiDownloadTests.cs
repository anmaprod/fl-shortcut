using System.Text;
using Xunit;

namespace FLShortcut.Core.Tests;

/// loopMIDI installé avec FL Shortcuts (16/11) : seul le fichier officiel, reconnu à son empreinte, est lancé ; l'installeur
/// et l'accueil de l'appli téléchargent le même.
public class LoopMidiDownloadTests
{
    [Fact]
    public void OnlyTheOfficialArchiveIsAccepted()
    {
        Assert.False(LoopMidiDownload.IsGenuine(Array.Empty<byte>()));
        Assert.False(LoopMidiDownload.IsGenuine(Encoding.UTF8.GetBytes("pas loopMIDI")));
        Assert.Matches("^[0-9a-f]{64}$", LoopMidiDownload.Sha256);
        Assert.StartsWith("https://www.tobias-erichsen.de/", LoopMidiDownload.Url);
    }

    [Theory]
    [InlineData(0, true)]
    [InlineData(3010, true)]
    [InlineData(1602, false)] // annulé
    [InlineData(1223, false)] // autorisation de Windows refusée
    public void SetupExitCodes(int code, bool installed) => Assert.Equal(installed, LoopMidiDownload.Succeeded(code));

    [Fact]
    public void InstallerUsesTheSameFile()
    {
        var iss = File.ReadAllText(Path.Combine(RepoRoot(), "windows", "installer", "FLShortcut.iss"));
        Assert.Contains("'" + LoopMidiDownload.Url + "'", iss);
        Assert.Contains("'" + LoopMidiDownload.Sha256 + "'", iss);
        Assert.Contains("'" + LoopMidiDownload.SetupName + "'", iss);
        Assert.Contains("'" + LoopMidiDownload.SetupArguments + "'", iss);
    }

    private static string RepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, "Sources"))) dir = dir.Parent;
        return dir?.FullName ?? throw new DirectoryNotFoundException("racine du dépôt");
    }
}
