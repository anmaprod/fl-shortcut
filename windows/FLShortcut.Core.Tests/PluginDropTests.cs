// Plugin ouvert en déposant son .fst de la Plugin database de FL (essais du propriétaire, 04/11) : le bon fichier (.fst,
// format préféré), juste sous le dernier son du Channel rack (jamais sur un son), un effet sur la piste visée ; sinon le
// menu Add comme avant.
using FLShortcut.Core.Macros;
using Xunit;

namespace FLShortcut.Core.Tests;

public sealed class PluginDropTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), "fls-plugin-db-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        try { Directory.Delete(_root, recursive: true); } catch (IOException) { }
    }

    private string Put(string relative)
    {
        var path = Path.Combine(_root, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, new byte[] { 1 });
        return path;
    }

    [Fact]
    public void TheFstOfThePreferredFormatIsChosen()
    {
        Put(Path.Combine("Installed", "Generators", "VST3", "Analog Lab V.nfo"));
        var vst3 = Put(Path.Combine("Installed", "Generators", "VST3", "Analog Lab V.fst"));
        Put(Path.Combine("Installed", "Generators", "VST", "Analog Lab V.fst"));
        var au = Put(Path.Combine("Installed", "Effects", "AudioUnit", "Pro-Q 3.fst"));
        Put(Path.Combine("Installed", "Effects", "VST3", "Pro-Q 3.fst"));
        Put(Path.Combine("Installed", "Generators", "VST3", "Keys.nfo"));          // seulement un .nfo : rien
        Assert.Equal(vst3, PluginDrop.PresetFile(_root, "Analog Lab V", effect: false));
        Assert.Equal(vst3, PluginDrop.PresetFile(_root, "analog lab v", effect: false));
        Assert.Equal(au, PluginDrop.PresetFile(_root, "Pro-Q 3", effect: true));
        Assert.Null(PluginDrop.PresetFile(_root, "Keys", effect: false));
        Assert.Null(PluginDrop.PresetFile(_root, "Pro-Q 3", effect: false));       // un effet n'est pas un instrument
        Assert.Null(PluginDrop.PresetFile(Path.Combine(_root, "absent"), "Analog Lab V", effect: false));
        Assert.Equal("au", PluginDrop.FormatKey("AudioUnit"));
        Assert.Equal("vst", PluginDrop.FormatKey("VST2"));
    }

    private static TextItem T(string text, int x, int y, int w = 60, int h = 12) => new(text, x, y, w, h);

    [Fact]
    public void TheDropPointIsJustUnderTheLastChannel()
    {
        var rack = new List<TextItem>
        {
            T("Channel rack", 300, 100, 90), T("All", 420, 100, 20),
            T("Kick", 360, 140), T("Snare", 360, 166), T("Hat", 360, 192), T("Clap", 360, 218),
            T("Track 1", 40, 400), T("Track 2", 40, 430),                      // la Playlist, plus à gauche
        };
        var p = Assert.NotNull(PluginDrop.ChannelRackPoint(rack));
        Assert.Equal(390, p.X);
        // Centre du dernier son (224) + une demi-ligne (13) : dans l'espace sous le dernier son, jamais dessus.
        Assert.Equal(237, p.Y);
        Assert.True(p.Y > 218 + 12, "sous le dernier son");
        // Un nom illisible (« 808 ») laisse un trou d'une ligne : toujours régulier.
        var withGap = rack.Where(t => t.Text != "Snare").ToList();
        Assert.Equal(237, Assert.NotNull(PluginDrop.ChannelRackPoint(withGap)).Y);
        // Une ligne et ses mots lus à part : un seul son.
        var words = rack.Append(T("Kick", 360, 140, 30)).ToList();
        Assert.Equal(237, Assert.NotNull(PluginDrop.ChannelRackPoint(words)).Y);
    }

    /// Channel rack coupé (vidéo du 04/11) : juste au-dessus du premier son, dans l'espace sous le titre.
    [Fact]
    public void ACutChannelRackGetsTheDropAboveTheFirstChannel()
    {
        var rack = new List<TextItem>
        {
            T("Channel rack", 300, 100, 90), T("Kick", 360, 140), T("Snare", 360, 166), T("Hat", 360, 192),
            new TextItem("Clap", 360, 218, 60, 6),                                     // lu à moitié : coupé
        };
        Assert.Equal((390, 133), PluginDrop.ChannelRackPoint(rack));
        var full = rack.Take(4).ToList();
        Assert.Equal((390, 211), PluginDrop.ChannelRackPoint(full));
        Assert.Equal((390, 133), PluginDrop.ChannelRackPoint(full, bottom: 225));   // dernier son au ras du bas
    }

    [Fact]
    public void InDoubtThereIsNoDropPoint()
    {
        Assert.Null(PluginDrop.ChannelRackPoint(new[] { T("Kick", 360, 140), T("Snare", 360, 166) }));        // sans titre
        Assert.Null(PluginDrop.ChannelRackPoint(new[] { T("Channel rack", 300, 100, 90), T("Kick", 360, 140) }));   // un seul son
        Assert.Null(PluginDrop.ChannelRackPoint(new[]
        {
            T("Channel rack", 300, 100, 90), T("Kick", 360, 140), T("Snare", 360, 166), T("Hat", 360, 203),       // pas réguliers
        }));
    }

    [Fact]
    public void TheMacroDropsTheInstrumentOrFallsBackToTheAddMenu()
    {
        var (fl, fx, state) = MacroEffectsWindowsTests.Start();
        fl.Presets["Analog Lab V"] = @"C:\db\Analog Lab V.fst";
        fl.Texts[FakeFl.Main] = new List<TextItem>
        {
            T("Channel rack", 300, 100, 90), T("Kick", 360, 140), T("Snare", 360, 166), T("Hat", 360, 192),
        };
        var add = new BlockBody.PageOption("channelRack.addInstrument", "Analog Lab V");
        Assert.IsType<StepResult.Ok>(fx.Perform(add, state));
        Assert.Equal((@"C:\db\Analog Lab V.fst", 390, 211), Assert.Single(fl.Drops));
        Assert.All(fl.Lines, l => Assert.DoesNotContain("Analog", l));                       // aucun nom au journal

        // Channel rack illisible : pas de dépôt (jamais au hasard), le menu Add comme avant.
        (fl, fx, state) = MacroEffectsWindowsTests.Start();
        fl.Presets["Analog Lab V"] = @"C:\db\Analog Lab V.fst";
        fx.Perform(add, state);
        Assert.Empty(fl.Drops);
        Assert.Contains(fl.Lines, l => l.Contains("Channel rack not read"));
    }

    [Fact]
    public void TheEffectIsDroppedOnTheAimedMixerTrack()
    {
        var (fl, fx, state) = MacroEffectsWindowsTests.Start(f => f.LastAimedClick = new AimedClick(700, 500, FakeFl.Main, 1200, 800, f.Now));
        fl.Presets["Pro-Q 3"] = @"C:\db\Pro-Q 3.fst";
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.PageOption("mixer.addEffect", "Pro-Q 3"), state));
        Assert.Equal((@"C:\db\Pro-Q 3.fst", 700, 500), Assert.Single(fl.Drops));
    }
}
