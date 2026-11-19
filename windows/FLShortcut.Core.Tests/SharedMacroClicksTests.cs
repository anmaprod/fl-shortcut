// Macro partagée (Communauté, fichier .flsmacro) rejouée dans le FL d'un autre ordinateur (demande du 19/11 : « que
// FL Shortcuts analyse le clic et fasse le même dans FL que dans les autres ordis ») : un bouton est retrouvé par son nom
// ou son image, même dans une fenêtre d'une autre taille et à une autre échelle d'écran ; un point d'une fenêtre de
// plugin, en proportion ; le reste est à montrer une fois. Jamais de clic à l'aveugle.
using FLShortcut.Core.Macros;
using Xunit;

namespace FLShortcut.Core.Tests;

public sealed class SharedMacroClicksTests
{
    private const string Home = @"C:\Users\flshortcuts";

    /// Bouton dessiné à l'échelle `scale` : damier noir et blanc de 4 cases de 6 × scale pixels, coin en (bx, by).
    private static GrayImage WindowWithScaledButton(int width, int height, int bx, int by, double scale)
    {
        var pixels = Enumerable.Repeat((byte)40, width * height).ToArray();
        var side = (int)Math.Round(24 * scale);
        var cell = 6 * scale;
        for (var y = 0; y < side; y++)
            for (var x = 0; x < side; x++)
                pixels[(by + y) * width + bx + x] = (((int)(x / cell) + (int)(y / cell)) % 2 == 0) ? (byte)250 : (byte)10;
        return new GrayImage(width, height, pixels);
    }

    [Fact]
    public void WhatASharedMacroKeepsOfEachClick()
    {
        var size = new Size2(500, 400);
        var named = new ClickTarget.Named(new NamedSpot("Insert 1", 0, 0, Corner.TopLeft, 60, 30, size));
        var sharedNamed = Assert.IsType<ClickTarget.Named>(named.Portable());
        Assert.True(sharedNamed.Spot.Loose && sharedNamed.IsLoose);

        var patch = MacroEffectsWindowsTests.WindowWithButton(500, 400, 100, 80).Crop(112, 92, VisualSpot.DefaultSide)!;
        var place = new ClickTarget.FlWindowPoint(Corner.TopLeft, 112, 92, size);
        // Place gardée ici, avec l'image du bouton dessous : sur cet ordinateur rien ne change.
        var withLook = Assert.IsType<ClickTarget.FlWindowPoint>(MacroDrafts.WithLook(place, patch));
        Assert.NotNull(withLook.Look);
        Assert.False(withLook.IsLoose);
        // Partagée : cherchée à son image chez l'autre.
        var shared = Assert.IsType<ClickTarget.Button>(withLook.Portable());
        Assert.True(shared.Spot.Loose);
        Assert.Equal((112.0, 92.0), (shared.Spot.Dx, shared.Spot.Dy));
        // Fond uni : pas d'image retenue, l'endroit est à montrer chez l'autre.
        var plain = MacroDrafts.WithLook(place, MacroEffectsWindowsTests.WindowWithButton(500, 400, 100, 80).Crop(300, 300, VisualSpot.DefaultSide));
        Assert.IsType<ClickTarget.ToLearn>(plain.Portable());
        // Fenêtre d'un plugin (titre) : même endroit en proportion.
        var plugin = new ClickTarget.FlWindowPoint(Corner.TopLeft, 200, 150, new Size2(800, 600), "Serum");
        Assert.True(Assert.IsType<ClickTarget.FlWindowPoint>(plugin.Portable()).Loose);
        // Décalages depuis la souris, la piste, le dernier clic ; menus : à montrer une fois.
        Assert.IsType<ClickTarget.ToLearn>(new ClickTarget.LastClick(4, 0).Portable());
        Assert.IsType<ClickTarget.ToLearn>(new ClickTarget.Track(4, 0).Portable());
        Assert.IsType<ClickTarget.ToLearn>(new ClickTarget.OpenMenu(new PopupHop(10, 10, new Size2(200, 300))).Portable());
        // Tout se garde dans le fichier (JSON commun au Mac), et repasser par Portable ne change rien.
        foreach (var t in new ClickTarget[] { sharedNamed, shared, withLook, plugin.Portable() })
        {
            Assert.Equal(t, ClickTarget.FromJson(t.ToJson()));
            if (t.IsLoose) Assert.Equal(t, t.Portable());
        }
    }

    [Fact]
    public void ExportThenImportKeepsTheClicksThatCanBeFound()
    {
        var size = new Size2(940, 652);
        var patch = MacroEffectsWindowsTests.WindowWithButton(500, 400, 100, 80).Crop(112, 92, VisualSpot.DefaultSide)!;
        var doc = new MacroDoc
        {
            Name = "Export",
            Blocks = new List<Block>
            {
                new(new BlockBody.Click(new ClickTarget.Named(new NamedSpot("FILE", 0, 0, Corner.TopLeft, 20, 12, size)))),
                new(new BlockBody.Click(MacroDrafts.WithLook(new ClickTarget.FlWindowPoint(Corner.TopLeft, 112, 92, size), patch))),
                new(new BlockBody.Click(new ClickTarget.FlWindowPoint(Corner.TopLeft, 300, 300, size))),
            },
        };
        var preview = MacroExchange.PrepareImport(MacroExchange.Export(doc, "0.2.0", Home), @"C:\Users\autre");
        var targets = preview.Doc.Blocks.Select(b => ((BlockBody.Click)b.Body).Target).ToList();
        Assert.True(Assert.IsType<ClickTarget.Named>(targets[0]).Spot.Loose);
        Assert.True(Assert.IsType<ClickTarget.Button>(targets[1]).Spot.Loose);
        Assert.IsType<ClickTarget.ToLearn>(targets[2]);
        Assert.Contains("bouton retrouvé par son nom", preview.Lines[0]);
        Assert.Contains("bouton retrouvé à son image", preview.Lines[1]);
        Assert.Contains("position à montrer", preview.Lines[2]);
    }

    /// Bouton nommé : cherché par son nom dans une fenêtre d'une autre taille (écran plus grand chez l'autre).
    [Fact]
    public void ASharedNamedButtonIsFoundInAWindowOfAnotherSize()
    {
        var (fl, fx, state) = MacroEffectsWindowsTests.Start(f => f.Show(40, FlWindowRole.Other, 300, 200, 750, 600));
        var spot = new NamedSpot("Insert 1", 0, 0, Corner.TopLeft, 60, 30, new Size2(500, 400), Loose: true);
        fl.Texts[40] = new() { new TextItem("Master", 320, 222, 40, 16), new TextItem("Insert 1", 380, 240, 40, 16) };
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.Click(new ClickTarget.Named(spot)), state));
        Assert.Equal((400, 248, false), fl.Clicks[^1]);
        Assert.All(fl.Lines, l => Assert.DoesNotContain("Insert", l));               // jamais le nom au journal

        // Nom absent de toutes les fenêtres : aucun clic, la raison dite.
        fl.Texts[40] = new() { new TextItem("Master", 320, 222, 40, 16) };
        fl.Texts[FakeFl.Main] = new();
        var before = fl.Clicks.Count;
        Assert.Equal("bouton de la macro partagée introuvable dans FL",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.Click(new ClickTarget.Named(spot)), state)).Why);
        Assert.Equal(before, fl.Clicks.Count);
    }

    /// Bouton retenu à son image sur un écran, retrouvé chez l'autre dessiné une fois et demie plus grand (Windows à
    /// 150 %), ailleurs dans une fenêtre d'une autre taille.
    [Fact]
    public void ASharedButtonImageIsFoundAtAnotherScale()
    {
        var learned = WindowWithScaledButton(500, 400, 100, 80, 1);
        var patch = learned.Crop(112, 92, VisualSpot.DefaultSide)!;
        var spot = new VisualSpot(Corner.TopLeft, 112, 92, new Size2(500, 400), null, patch.Width, patch.Pixels, Loose: true);

        var (fl, fx, state) = MacroEffectsWindowsTests.Start(f => f.Show(40, FlWindowRole.Other, 100, 100, 750, 600));
        fl.Images[40] = WindowWithScaledButton(750, 600, 400, 300, 1.5);              // bouton de 36 pixels en (400, 300)
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.Click(new ClickTarget.Button(spot)), state));
        var (x, y, _) = fl.Clicks[^1];
        Assert.InRange(x, 100 + 418 - 2, 100 + 418 + 2);                             // centre du bouton : 400 + 18
        Assert.InRange(y, 100 + 318 - 2, 100 + 318 + 2);
        Assert.Contains(fl.Lines, l => l.Contains("found by its image"));

        // Plus là : jamais de clic à l'aveugle.
        fl.Images[40] = new GrayImage(750, 600, Enumerable.Repeat((byte)40, 750 * 600).ToArray());
        var before = fl.Clicks.Count;
        Assert.Equal("bouton de la macro partagée introuvable dans FL",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.Click(new ClickTarget.Button(spot)), state)).Why);
        Assert.Equal(before, fl.Clicks.Count);
    }

    /// Point d'une fenêtre de plugin : la seule fenêtre de la même forme, au même endroit en proportion ; deux fenêtres de
    /// cette forme : trop incertain, rien n'est cliqué.
    [Fact]
    public void ASharedPluginPointIsPlacedInProportion()
    {
        var target = new ClickTarget.FlWindowPoint(Corner.TopLeft, 200, 150, new Size2(800, 600), "Serum", Loose: true);
        var (fl, fx, state) = MacroEffectsWindowsTests.Start(f => f.Show(50, FlWindowRole.Other, 100, 100, 1200, 900));
        Assert.IsType<StepResult.Ok>(fx.Perform(new BlockBody.Click(target), state));
        Assert.Equal((100 + 300, 100 + 225, false), fl.Clicks[^1]);

        fl.Show(51, FlWindowRole.Other, 200, 150, 400, 300);
        var before = fl.Clicks.Count;
        Assert.Equal("fenêtre du plugin de la macro partagée introuvable dans FL",
            Assert.IsType<StepResult.Fail>(fx.Perform(new BlockBody.Click(target), state)).Why);
        Assert.Equal(before, fl.Clicks.Count);
    }

    // ---------- Presets joints (« le preset part avec la macro ») ----------

    private static MacroDoc WithPreset(string path) => new()
    {
        Name = "Basse",
        Blocks = new List<Block> { new(new BlockBody.DropFile(path)), new(new BlockBody.Delay(100)) },
    };

    [Fact]
    public void ThePresetTravelsWithTheMacroAndLandsInThePresetsFolder()
    {
        var bytes = Enumerable.Range(0, 3000).Select(i => (byte)(i * 7)).ToArray();
        var source = Home + @"\Documents\Image-Line\FL Studio\Presets\Bass.fst";
        var file = MacroExchange.Export(WithPreset(source), "0.2.0", Home, p => p == source ? bytes : null);
        Assert.Contains("\"attached\"", System.Text.Encoding.UTF8.GetString(file));

        // Chez l'autre : rien de ce nom, le preset est rangé dans Documents › FL Shortcuts › Presets.
        const string other = @"C:\Users\autre";
        const string presets = @"C:\Users\autre\Documents\FL Shortcuts\Presets";
        var preview = MacroExchange.PrepareImport(file, other, presets, _ => null);
        var drop = Assert.IsType<BlockBody.DropFile>(preview.Doc.Blocks[0].Body);
        Assert.Equal(presets + @"\Bass.fst", drop.Path);
        var written = Assert.Single(preview.Files!);
        Assert.Equal(bytes, written.Data);
        Assert.Contains("preset joint", preview.Lines[0]);
        Assert.DoesNotContain(preview.Warnings, w => w.Contains("Rechoisis"));

        // Un autre fichier du même nom est déjà là : jamais remplacé, « Bass 2.fst ».
        var taken = MacroExchange.PrepareImport(file, other, presets, p => p == presets + @"\Bass.fst" ? new byte[] { 1 } : null);
        Assert.Equal(presets + @"\Bass 2.fst", ((BlockBody.DropFile)taken.Doc.Blocks[0].Body).Path);
        // Le même preset est déjà à sa place d'origine (preset d'usine) : repris tel quel, rien à écrire.
        var same = MacroExchange.PrepareImport(file, other, presets, p => p == other + @"\Documents\Image-Line\FL Studio\Presets\Bass.fst" ? bytes : null);
        Assert.Equal(other + @"\Documents\Image-Line\FL Studio\Presets\Bass.fst", ((BlockBody.DropFile)same.Doc.Blocks[0].Body).Path);
        Assert.Empty(same.Files!);
    }

    [Fact]
    public void OnlySmallFstPresetsTravel()
    {
        var source = Home + @"\Documents\Bass.fst";
        var big = MacroExchange.Export(WithPreset(source), "0.2.0", Home, _ => new byte[MacroExchange.MaxAttachedBytes + 1]);
        Assert.DoesNotContain("\"attached\"", System.Text.Encoding.UTF8.GetString(big));
        var preview = MacroExchange.PrepareImport(big, @"C:\Users\autre", @"C:\P", _ => null);
        Assert.Contains(preview.Warnings, w => w.Contains("Rechoisis"));               // pas joint : à rechoisir

        Assert.Equal("Bass.fst", MacroExchange.SafePresetName(@"C:\a\b\Bass.fst"));
        Assert.Equal("Lead.FST", MacroExchange.SafePresetName("~/x/Lead.FST"));
        Assert.Null(MacroExchange.SafePresetName("virus.exe"));
        Assert.Null(MacroExchange.SafePresetName("../.fst"));
        Assert.Null(MacroExchange.SafePresetName(null));
    }

    [Fact]
    public void AttachedPresetsAreWrittenNeverOverAnotherFile()
    {
        var dir = Path.Combine(Path.GetTempPath(), "fls-presets-" + Guid.NewGuid().ToString("N"));
        try
        {
            var path = Path.Combine(dir, "Bass.fst");
            Assert.Null(MacroExchange.WriteAttached(new[] { new MacroExchange.AttachedFile(path, new byte[] { 1, 2, 3 }) }));
            Assert.Equal(new byte[] { 1, 2, 3 }, File.ReadAllBytes(path));
            Assert.Null(MacroExchange.WriteAttached(new[] { new MacroExchange.AttachedFile(path, new byte[] { 9 }) }));
            Assert.Equal(new byte[] { 1, 2, 3 }, File.ReadAllBytes(path));                  // jamais remplacé
            MacroExchange.WriteAttached(new[] { new MacroExchange.AttachedFile(Path.Combine(dir, "x.exe"), new byte[] { 1 }) });
            Assert.False(File.Exists(Path.Combine(dir, "x.exe")));                         // jamais autre chose qu'un .fst
        }
        finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
    }

    [Fact]
    public void AnImageCanBeResizedBothWays()
    {
        var image = WindowWithScaledButton(40, 40, 8, 8, 1);
        var bigger = image.Resized(1.5);
        Assert.Equal((60, 60), (bigger.Width, bigger.Height));
        Assert.Same(image, image.Resized(1));
        var smaller = image.Resized(0.5);
        Assert.Equal((20, 20), (smaller.Width, smaller.Height));
    }
}
