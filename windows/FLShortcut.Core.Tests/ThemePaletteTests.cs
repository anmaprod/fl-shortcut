using System.Text.RegularExpressions;
using FLShortcut.Core;
using Xunit;

namespace FLShortcut.Core.Tests;

/// Thèmes (04/11) : les mêmes que le Mac (AppTheme.swift), mêmes noms dans les réglages, mêmes couleurs.
public sealed class ThemePaletteTests
{
    [Fact]
    public void ThemesAndTheirSettingNames()
    {
        Assert.Equal(AppTheme.Papier, ThemePalette.Parse(null));
        Assert.Equal(AppTheme.Papier, ThemePalette.Parse("violet"));
        Assert.Equal(AppTheme.Noir, ThemePalette.Parse("noir"));
        Assert.Equal(AppTheme.Papier, ThemePalette.Parse("papier"));
        Assert.Equal(AppTheme.Orange, ThemePalette.Parse(" Orange "));
        foreach (var theme in Enum.GetValues<AppTheme>())
            Assert.Equal(theme, ThemePalette.Parse(ThemePalette.Key(theme)));
        Assert.False(ThemePalette.IsLight(AppTheme.Noir));
        Assert.True(ThemePalette.IsLight(AppTheme.Papier));
        Assert.True(ThemePalette.IsLight(AppTheme.Orange));
    }

    /// Demande du 07/11 (comme le Mac) : les thèmes seulement avec un compte connecté ; sans compte, Papier
    /// (direction A du 17/11, pour tout le monde).
    [Fact]
    public void ThemesOnlyWithAnAccount()
    {
        Assert.Equal(AppTheme.Papier, ThemePalette.Shown("noir", signedIn: false));
        Assert.Equal(AppTheme.Papier, ThemePalette.Shown("orange", signedIn: false));
        Assert.Equal(AppTheme.Noir, ThemePalette.Shown("noir", signedIn: true));
        Assert.Equal(AppTheme.Orange, ThemePalette.Shown("orange", signedIn: true));
        Assert.Equal(AppTheme.Papier, ThemePalette.Shown(null, signedIn: true));
    }

    [Fact]
    public void PalettesOfTheMockups()
    {
        Assert.Equal(0x000000u, ThemePalette.Of(AppTheme.Noir).Background);
        Assert.Equal(0xFFFFFFu, ThemePalette.Of(AppTheme.Noir).Text);
        Assert.Equal(0xF3F2EEu, ThemePalette.Of(AppTheme.Papier).Background);
        Assert.Equal(0x111111u, ThemePalette.Of(AppTheme.Papier).Text);
        Assert.Equal(0xFF3B1Fu, ThemePalette.Of(AppTheme.Papier).Red);
        Assert.Equal(ThemePalette.BrandRed, ThemePalette.Of(AppTheme.Orange).Background);
        Assert.Equal(0xFFFFFFu, ThemePalette.Of(AppTheme.Orange).Red);
        Assert.Equal(0x000000u, ThemePalette.Of(AppTheme.Orange, inverse: true).Background);
        // Une partie inversée ne change rien hors du thème Orange.
        Assert.Same(ThemePalette.Of(AppTheme.Papier), ThemePalette.Of(AppTheme.Papier, inverse: true));
        Assert.Same(ThemePalette.Of(AppTheme.Noir), ThemePalette.Of(AppTheme.Noir, inverse: true));
    }

    /// Les couleurs de chaque thème sont celles du Mac (SwissPalette dans AppTheme.swift), dans le même ordre.
    [Fact]
    public void SameColorsAsTheMac()
    {
        var root = Path.GetDirectoryName(typeof(ThemePaletteTests).Assembly.Location)!;
        while (!File.Exists(Path.Combine(root, "PROTOCOL.md"))) root = Path.GetDirectoryName(root)!;
        var swift = File.ReadAllText(Path.Combine(root, "Sources", "FLShortcut", "AppTheme.swift"));
        uint Hex(string s) => s switch
        {
            "brandRed" => ThemePalette.BrandRed,
            "paperRed" => ThemePalette.PaperRed,
            _ => Convert.ToUInt32(s[2..], 16),
        };
        var pairs = new (string Name, ThemePalette Win)[]
        {
            ("noir", ThemePalette.Noir), ("papier", ThemePalette.Papier), ("orange", ThemePalette.Orange),
            ("orangeInverse", ThemePalette.OrangeInverse),
        };
        foreach (var (name, win) in pairs)
        {
            var m = Regex.Match(swift,
                $@"static let {name} = SwissPalette\(background: (\w+), text: (\w+), gray: (\w+), soft: (\w+),\s*" +
                @"line: (\w+), faint: (\w+), keyLine: (\w+), red: (\w+)\)");
            Assert.True(m.Success, name);
            var mac = m.Groups.Values.Skip(1).Select(g => Hex(g.Value)).ToArray();
            Assert.Equal(mac, new[] { win.Background, win.Text, win.Gray, win.Soft, win.Line, win.Faint, win.KeyLine, win.Red });
        }
    }
}
