using Xunit;

namespace FLShortcut.Core.Tests;

/// Windows MIDI Services (21/11) : la copie de l'API de Microsoft seulement sur Windows 11 25H2 et plus récent, la même
/// limite dans l'appli et l'installeur, le même paquet dans la CI.
public class MidiServicesSupportTests
{
    [Theory]
    [InlineData(19045, false)] // Windows 10 22H2
    [InlineData(22631, false)] // Windows 11 23H2
    [InlineData(26100, false)] // Windows 11 24H2 (et Windows Server 2025 de la CI)
    [InlineData(26200, true)]  // Windows 11 25H2
    [InlineData(28000, true)]  // Windows 11 26H1
    public void OnlyFrom25H2(int build, bool supported) => Assert.Equal(supported, MidiServicesSupport.Supported(build));

    [Fact]
    public void TheInstallerUsesTheSameLimit()
    {
        var iss = File.ReadAllText(Path.Combine(RepoRoot(), "windows", "installer", "FLShortcut.iss"));
        Assert.Contains("Version.Build >= " + MidiServicesSupport.MinBuild, iss);
        Assert.Contains(MidiServicesSupport.ApiFile, iss);
    }

    [Fact]
    public void TheBuildUsesTheSamePackage()
    {
        var workflow = File.ReadAllText(Path.Combine(RepoRoot(), ".github", "workflows", "build.yml"));
        Assert.Contains("'" + MidiServicesSupport.PackageUrl + "'", workflow);
        Assert.Contains("'" + MidiServicesSupport.PackageSha256 + "'", workflow);
        Assert.Matches("^[0-9a-f]{64}$", MidiServicesSupport.PackageSha256);
        Assert.StartsWith("https://github.com/microsoft/MIDI/releases/download/", MidiServicesSupport.PackageUrl);
    }

    private static string RepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, "Sources"))) dir = dir.Parent;
        return dir?.FullName ?? throw new DirectoryNotFoundException("racine du dépôt");
    }
}
