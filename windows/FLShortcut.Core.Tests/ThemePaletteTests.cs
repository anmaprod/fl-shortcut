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
        Assert.Equal(AppTheme.Noir, ThemePalette.Parse(null));
        Assert.Equal(AppTheme.Noir, ThemePalette.Parse("violet"));
        Assert.Equal(AppTheme.Papier, ThemePalette.Parse("papier"));
        Assert.Equal(AppTheme.Orange, ThemePalette.Parse(" Orange "));
        foreach (var theme in Enum.GetValues<AppTheme>())
            Assert.Equal(theme, ThemePalette.Parse(ThemePalette.Key(theme)));
        Assert.False(ThemePalette.IsLight(AppTheme.Noir));
        Assert.True(ThemePalette.IsLight(AppTheme.Papier));
        Assert.True(ThemePalette.IsLight(AppTheme.Orange));
    }

    [Fact]
    public void PalettesOfTheMockups()
    {
        Assert.Equal(0x000000u, ThemePalette.Of(AppTheme.Noir).Background);
        Assert.Equal(0xFFFFFFu, ThemePalette.Of(AppTheme.Noir).Text);
        Assert.Equal(0xFFFFFFu, ThemePalette.Of(AppTheme.Papier).Background);
        Assert.Equal(0x000000u, ThemePalette.Of(AppTheme.Papier).Text);
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
        uint Hex(string s) => s == "brandRed" ? ThemePalette.BrandRed : Convert.ToUInt32(s[2..], 16);
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
