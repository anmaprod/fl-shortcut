// Lien posé tout seul (13/11, « installer le lien midi dès l'installation du logiciel ») : le bon dossier
// « Settings\Hardware » de FL, jamais créé au hasard quand FL n'a jamais été ouvert.
using Xunit;

namespace FLShortcut.Core.Tests;

public class FlScriptPlaceTests
{
    private static readonly string Docs = Path.Combine(Path.GetTempPath(), "Docs");
    private static readonly string OneDrive = Path.Combine(Path.GetTempPath(), "OneDrive", "Documents");
    private static readonly string Data = Path.Combine(Path.GetTempPath(), "FLData");

    [Fact]
    public void CandidatesFollowFlsFoldersThenEachDocumentsFolder()
    {
        var c = FlScriptPlace.Candidates(new[] { Docs, OneDrive, "" }, new[] { Data, "relatif", " " });
        Assert.Equal(new[]
        {
            Path.Combine(Data, "Settings", "Hardware"),
            Path.Combine(Data, "FL Studio", "Settings", "Hardware"),
            Path.Combine(Docs, "Image-Line", "FL Studio", "Settings", "Hardware"),
            Path.Combine(OneDrive, "Image-Line", "FL Studio", "Settings", "Hardware"),
            Path.Combine(Docs, "Image-Line", "Data", "FL Studio", "Settings", "Hardware"),
            Path.Combine(OneDrive, "Image-Line", "Data", "FL Studio", "Settings", "Hardware"),
        }, c);
        var hardware = Path.Combine(Data, "Settings", "Hardware");
        Assert.Equal(hardware, Assert.Single(FlScriptPlace.Candidates(Array.Empty<string>(), new[] { hardware })));
    }

    [Fact]
    public void OnlyAFolderWhoseSettingsAlreadyExists()
    {
        var c = FlScriptPlace.Candidates(new[] { Docs, OneDrive });
        Assert.Null(FlScriptPlace.Hardware(c, _ => false));                  // FL jamais ouvert : rien
        var oneDriveSettings = Path.Combine(OneDrive, "Image-Line", "FL Studio", "Settings");
        Assert.Equal(Path.Combine(oneDriveSettings, "Hardware"), FlScriptPlace.Hardware(c, d => d == oneDriveSettings));
    }
}
