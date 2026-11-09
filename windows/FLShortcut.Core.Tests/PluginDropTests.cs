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
    public void TheEffectGoesToTheSelectedTrackNeverToTheLastClick()
    {
        // 07/11 (vidéo : l'effet allait sur la piste sous la souris) : la première case libre de la piste choisie.
        var (fl, fx, state) = MacroEffectsWindowsTests.Start(f => f.LastAimedClick = new AimedClick(700, 500, FakeFl.Main, 1200, 800, f.Now));
        fl.Presets["Pro-Q 3"] = @"C:\db\Pro-Q 3.fst";
        fl.Texts[FakeFl.Main] = new List<TextItem> { T("Mixer - Insert 3", 900, 40, 120), T("▶ Slot 2", 900, 120), T("▶ Slot 3", 900, 140) };
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.PageOption("mixer.addEffect", "Pro-Q 3"), state));
        Assert.Equal((@"C:\db\Pro-Q 3.fst", 930, 126), Assert.Single(fl.Drops));

        // Aucune case libre lue : jamais déposé sur la piste du dernier clic (le menu, comme avant).
        (fl, fx, state) = MacroEffectsWindowsTests.Start(f => f.LastAimedClick = new AimedClick(700, 500, FakeFl.Main, 1200, 800, f.Now));
        fl.Presets["Pro-Q 3"] = @"C:\db\Pro-Q 3.fst";
        fx.Perform(new BlockBody.PageOption("mixer.addEffect", "Pro-Q 3"), state);
        Assert.Empty(fl.Drops);
        Assert.Contains(fl.Lines, l => l.Contains("no free slot read"));
    }

    /// Vidéo du 05/11 (FL 2025) : le titre « Channel rack » est à ~100 points à droite des noms, centrés dans leur
    /// bouton ; « Unsorted » sur la ligne du titre ; le Browser loin à gauche.
    [Fact]
    public void TheNamesLeftOfTheTitleAreFound()
    {
        var rack = new[]
        {
            T("Unsorted", 244, 46), T("Channel rack", 369, 46, 80), T("bass", 270, 94, 24), T("kick", 272, 124, 20),
            T("dash38", 20, 100), T("dryykt", 20, 110), T("dyajp", 20, 120), T("icon", 20, 130),
        };
        var p = PluginDrop.ChannelRackPoint(rack);
        Assert.NotNull(p);
        Assert.InRange(p!.Value.X, 280, 283);
        Assert.Equal(145, p.Value.Y);
        var mixed = new[] { T("Channel rack", 369, 46, 80), T("Kick", 271, 94, 20), T("ZENOLOGY Lead", 241, 124, 80), T("Hat", 273, 154, 16) };
        Assert.Equal(175, PluginDrop.ChannelRackPoint(mixed)!.Value.Y);
    }

    /// 06/11 (comme le Mac) : l'effet va dans la première case libre de la piste choisie du Mixer, même lue de travers ;
    /// rien si aucune case libre n'est lue.
    [Fact]
    public void TheEffectGoesToTheFirstFreeSlotOfTheSelectedTrack()
    {
        var mixer = new[] { T("Insert 1", 200, 400), T("Fruity Limiter", 900, 120, 90), T("Slot 7", 900, 300), T("Slot 3", 900, 180) };
        Assert.Equal(186, PluginDrop.MixerSlotPoint(mixer)!.Value.Y);
        Assert.Equal(146, PluginDrop.MixerSlotPoint(new[] { T("Slot l", 900, 140) })!.Value.Y);
        Assert.Null(PluginDrop.MixerSlotPoint(new[] { T("Slot machine", 900, 140), T("Insert 2", 300, 400) }));
        Assert.Equal(3, PluginDrop.SlotNumber("▶ Slot 3"));
        Assert.Equal(10, PluginDrop.SlotNumber("Slot10"));
        Assert.Equal(1, PluginDrop.SlotNumber("SIot 1"));
        Assert.Null(PluginDrop.SlotNumber("Auto-Tune Pro"));
        Assert.True(PluginDrop.PageShown(true, new[] { T("Mixer - Insert 11", 900, 40, 120) }));
        Assert.False(PluginDrop.PageShown(false, new[] { T("Playlist - Arrangement", 300, 100, 160) }));
    }

    /// 06/11 (comme le Mac) : le .fst trouvé partout dans la base (sous-dossiers, favoris de FL), même au nom un peu
    /// différent (marque, format), jamais un autre numéro.
    [Fact]
    public void EveryPluginIsFoundInTheWholeDatabase()
    {
        var root = Path.Combine(Path.GetTempPath(), "fls-db-" + Guid.NewGuid().ToString("N"));
        void Put(string relative)
        {
            var path = Path.Combine(new[] { root }.Concat(relative.Split('/')).ToArray());
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            File.WriteAllBytes(path, new byte[] { 1 });
        }
        try
        {
            Put("Installed/Generators/VST3/Arturia/Pigments.fst");
            Put("Generators/Synth classic/Sytrus.fst");
            Put("Installed/Generators/Fruity/Sytrus.nfo");
            Put("Installed/Effects/VST3/FabFilter Pro-Q 3.fst");
            Put("Installed/Generators/VST/Kontakt 7 (VST3).fst");
            Put("Installed/Generators/VST3/Serum 2.fst");
            Put("Generators/FL Shortcuts/Vital.fst");
            Assert.Equal("Pigments.fst", Path.GetFileName(PluginDrop.PresetFile(root, "Pigments", false)));
            Assert.Equal("Sytrus.fst", Path.GetFileName(PluginDrop.PresetFile(root, "Sytrus", false)));
            Assert.Equal("FabFilter Pro-Q 3.fst", Path.GetFileName(PluginDrop.PresetFile(root, "Pro-Q 3", true)));
            Assert.Equal("Kontakt 7 (VST3).fst", Path.GetFileName(PluginDrop.PresetFile(root, "Kontakt 7", false)));
            Assert.Null(PluginDrop.PresetFile(root, "Serum", false));
            Assert.Null(PluginDrop.PresetFile(root, "Vital", false));
            Assert.Null(PluginDrop.PresetFile(root, "Pro-Q 4", true));
        }
        finally
        {
            try { Directory.Delete(root, true); } catch (IOException) { }
        }
    }
}

/// « Cliquer sur… » : la liste de tous les plugins installés, comme le Mac (09/11, FLPluginDatabaseTests).
public sealed class PluginDatabaseTests
{
    [Fact]
    public void ListsInstalledPluginsByFormatAndName()
    {
        var root = Path.Combine(Path.GetTempPath(), "fls-plugins-" + Guid.NewGuid().ToString("N"));
        try
        {
            void Touch(string relative)
            {
                var path = Path.Combine(root, relative);
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                File.WriteAllText(path, "");
            }
            Touch(@"Installed/Generators/VST3/Serum 2.fst");
            Touch(@"Installed/Generators/VST3/Serum 2.nfo");
            Touch(@"Installed/Generators/VST3/Serum 10.fst");
            Touch(@"Installed/Generators/VST/Analog Lab V.fst");
            Touch(@"Installed/Generators/VST/notes.txt");
            Touch(@"Installed/Effects/VST3/Pro-Q 3.fst");
            var generators = PluginDatabase.Installed(root, effect: false);
            Assert.Equal(new[] { ("VST", "Analog Lab V"), ("VST3", "Serum 2"), ("VST3", "Serum 10") },
                generators.Select(p => (p.Format, p.Name)));
            Assert.Equal(new[] { "Pro-Q 3" }, PluginDatabase.Installed(root, effect: true).Select(p => p.Name));
            var groups = PluginDatabase.ByFormat(generators);
            Assert.Equal(new[] { "VST", "VST3" }, groups.Select(g => g.Format));
            Assert.Equal(2, groups[1].Names.Count);
            // Base absente : liste vide, jamais d'exception ; la première base qui en a gagne.
            Assert.Empty(PluginDatabase.Installed(Path.Combine(root, "absente"), effect: false));
            Assert.Equal(3, PluginDatabase.Installed(new[] { Path.Combine(root, "absente"), root }, effect: false).Count);
        }
        finally
        {
            try { Directory.Delete(root, recursive: true); } catch (IOException) { }
        }
    }

    [Fact]
    public void RootsBesideTheScriptThenDocuments()
    {
        var script = Path.Combine("C:", "Data", "FL Studio", "Settings", "Hardware", "FL Shortcuts", "device_FLShortcut.py");
        var roots = PluginDatabase.Roots(script, Path.Combine("C:", "Docs"));
        Assert.Equal(3, roots.Count);
        Assert.EndsWith(Path.Combine("FL Studio", "Presets", "Plugin database"), roots[0]);
        Assert.Equal(Path.Combine("C:", "Docs", "Image-Line", "FL Studio", "Presets", "Plugin database"), roots[1]);
        Assert.Equal(Path.Combine("C:", "Docs", "Image-Line", "Data", "FL Studio", "Presets", "Plugin database"), roots[2]);
        Assert.Equal(2, PluginDatabase.Roots(null, Path.Combine("C:", "Docs")).Count);
    }

    /// Mêmes dossiers que le Mac, à toutes leurs places sous Windows (09/11) : dossiers de données notés par FL, puis
    /// chaque Documents (Windows, profil, OneDrive), sans doublon, le script d'abord.
    [Fact]
    public void RootsCoverEveryWindowsDocumentsFolder()
    {
        var docs = Path.Combine(Path.GetTempPath(), "Docs");
        var drive = Path.Combine(Path.GetTempPath(), "OneDrive", "Documents");
        var data = Path.Combine(Path.GetTempPath(), "FLData");
        var roots = PluginDatabase.Roots(null, new[] { docs, drive, docs.ToUpperInvariant() }, new[] { data, "relatif", "" });
        Assert.Equal(new[]
        {
            Path.Combine(data, "Presets", "Plugin database"),
            Path.Combine(data, "FL Studio", "Presets", "Plugin database"),
            Path.Combine(docs, "Image-Line", "FL Studio", "Presets", "Plugin database"),
            Path.Combine(drive, "Image-Line", "FL Studio", "Presets", "Plugin database"),
            Path.Combine(docs, "Image-Line", "Data", "FL Studio", "Presets", "Plugin database"),
            Path.Combine(drive, "Image-Line", "Data", "FL Studio", "Presets", "Plugin database"),
        }, roots);
        var direct = Path.Combine(data, "Plugin database");
        Assert.Equal(direct, PluginDatabase.Roots(null, Array.Empty<string>(), new[] { direct })[0]);
    }
}
