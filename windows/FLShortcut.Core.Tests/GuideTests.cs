using System.Text.RegularExpressions;
using FLShortcut.Core;
using Xunit;

namespace FLShortcut.Core.Tests;

/// Guide de Windows (10/11) : le même que le Mac (Guide.swift), sauf la partie « Au quotidien » qui parle de Windows.
public sealed class GuideTests
{
    /// Les parties du Mac, lues dans Guide.swift : titre puis ses trois étapes.
    private static List<(string Title, List<string> Steps)> MacPages()
    {
        var root = Path.GetDirectoryName(typeof(GuideTests).Assembly.Location)!;
        while (!File.Exists(Path.Combine(root, "PROTOCOL.md"))) root = Path.GetDirectoryName(root)!;
        var swift = File.ReadAllText(Path.Combine(root, "Sources", "FLShortcut", "Guide.swift"));
        var block = swift[swift.IndexOf("static let pages", StringComparison.Ordinal)..swift.IndexOf("static var count", StringComparison.Ordinal)];
        var pages = new List<(string, List<string>)>();
        foreach (var part in block.Split("GuidePage(id:").Skip(1))
        {
            var texts = Regex.Matches(part, "String\\(localized: \"((?:[^\"\\\\]|\\\\.)*)\"\\)").Select(m => Regex.Unescape(m.Groups[1].Value)).ToList();
            pages.Add((texts[0], texts.Skip(1).ToList()));
        }
        return pages;
    }

    [Fact]
    public void SamePartsAndTextsAsTheMac()
    {
        var mac = MacPages();
        var win = GuideContent.Pages;
        Assert.Equal(4, mac.Count);
        Assert.Equal(mac.Count, win.Count);
        for (var i = 0; i < win.Count; i++)
        {
            Assert.Equal(i + 1, win[i].Id);
            Assert.Equal(mac[i].Title, win[i].Title);
            Assert.Equal(3, win[i].Steps.Count);
        }
        // Raccourcis, macros, Communauté : mot pour mot les étapes du Mac.
        for (var i = 0; i < 3; i++) Assert.Equal(mac[i].Steps, win[i].Steps);
    }

    /// « Au quotidien » : l'icône près de l'horloge, la touche de pause de Windows ; aucune touche ni mot du Mac.
    [Fact]
    public void DayToDaySpeaksOfWindows()
    {
        var day = GuideContent.Pages[3];
        Assert.Contains("horloge", day.Steps[0]);
        Assert.Contains("Ctrl+Alt+Maj+F", day.Steps[1]);
        Assert.Equal(new KeyCombo(Vk.Letter('F'), Ctrl: true, Alt: true, Shift: true), ProfilePresets.Toggle);
        foreach (var step in GuideContent.Pages.SelectMany(p => p.Steps))
        {
            Assert.DoesNotMatch("[⌘⌥⌃⇧]", step);
            Assert.DoesNotContain("en haut de l'écran", step);
            Assert.DoesNotContain("(", step);                  // une phrase courte, sans parenthèse (04/11)
        }
    }

    [Fact]
    public void WelcomeThenOnePagePerPart()
    {
        Assert.Equal(5, GuideContent.Count);
        Assert.Null(GuideContent.Part(0));
        Assert.Equal(1, GuideContent.Part(1)!.Id);
        Assert.Equal(4, GuideContent.Part(4)!.Id);
        Assert.Equal(0, GuideContent.Clamp(-3));
        Assert.Equal(4, GuideContent.Clamp(12));
        Assert.False(GuideContent.IsLast(3));
        Assert.True(GuideContent.IsLast(4));
        Assert.Equal("Découvrir", GuideContent.NextTitle(0));
        Assert.Equal("Suivant", GuideContent.NextTitle(2));
        Assert.Equal("C'est parti", GuideContent.NextTitle(4));
    }

    /// Un Windows en anglais ne voit aucune ligne du guide en français.
    [Fact]
    public void EveryLineHasItsEnglish()
    {
        foreach (var page in GuideContent.Pages)
        {
            Assert.True(Loc.Has(page.Title), page.Title);
            foreach (var step in page.Steps) Assert.True(Loc.Has(step), step);
        }
        foreach (var text in new[] { "Bienvenue", "Passer", "Précédent", "Suivant", "Découvrir", "C'est parti", "Revoir le guide" })
            Assert.True(Loc.Has(text), text);
    }
}
