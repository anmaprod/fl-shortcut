// Page Macros de Windows (sans fenêtre) : palette des blocs faits sur Windows, nouvelle macro et modèles, blocs
// déplacés, noms, raccourcis d'une macro.
using FLShortcut.Core;
using FLShortcut.Core.Macros;
using Xunit;

namespace FLShortcut.Core.Tests;

public class MacroDraftsTests
{
    [Fact]
    public void PaletteKeepsOnlyBlocksThatWorkHere()
    {
        var all = MacroDrafts.Palette(null).SelectMany(p => p.Specs).Select(s => s.Type).ToHashSet();
        var windows = MacroDrafts.Palette(MacroEffectsWindows.Unsupported).SelectMany(p => p.Specs).Select(s => s.Type).ToHashSet();
        Assert.Contains(BlockType.Key, windows);
        Assert.Contains(BlockType.Delay, windows);
        Assert.Contains(BlockType.WaitWindow, windows);
        Assert.Contains(BlockType.Click, windows);
        Assert.Contains(BlockType.MenuBar, windows);
        Assert.DoesNotContain(BlockType.SoundCard, windows);
        Assert.True(windows.IsSubsetOf(all));
        Assert.All(MacroDrafts.Palette(MacroEffectsWindows.Unsupported), p => Assert.NotEmpty(p.Specs));
    }

    [Fact]
    public void NewMacrosGetUniqueNamesAndFreshIds()
    {
        var store = new MacroLibraryStore(new MemoryMacroLibraryStorage());
        var first = store.Add(MacroDrafts.Empty(store));
        Assert.Equal("Nouvelle macro", first.Name);
        Assert.Equal("Nouvelle macro 2", MacroDrafts.Empty(store).Name);

        var template = MacroTemplates.Gallery.First(t => t.Id == "openVST");
        var a = store.Add(MacroDrafts.FromTemplate(template, store));
        var b = MacroDrafts.FromTemplate(template, store);
        Assert.Equal("Ouvre un VST 2", b.Name);
        Assert.Empty(a.Blocks.Select(x => x.Id).Intersect(b.Blocks.Select(x => x.Id)));
        Assert.Equal("openVST", b.Origin?.Template);
    }

    [Fact]
    public void BlocksMoveWithinBounds()
    {
        var blocks = new List<Block> { new(new BlockBody.Delay(1)), new(new BlockBody.Delay(2)), new(new BlockBody.Delay(3)) };
        Assert.True(MacroDrafts.Move(blocks, 0, 1));
        Assert.Equal(new[] { 2, 1, 3 }, blocks.Select(b => ((BlockBody.Delay)b.Body).Ms));
        Assert.False(MacroDrafts.Move(blocks, 0, -1));
        Assert.False(MacroDrafts.Move(blocks, 2, 1));
        Assert.True(MacroDrafts.Move(blocks, 2, -2));
        Assert.Equal(new[] { 3, 2, 1 }, blocks.Select(b => ((BlockBody.Delay)b.Body).Ms));
    }

    [Fact]
    public void CopiesAreIndependentAndUpdateTheStore()
    {
        var store = new MacroLibraryStore(new MemoryMacroLibraryStorage());
        var doc = store.Add(new MacroDoc { Name = "A", Blocks = new List<Block> { new(new BlockBody.Delay(100)) } });
        var copy = MacroDrafts.Copy(doc);
        copy.Blocks.Add(new Block(new BlockBody.Delay(200)));
        Assert.Single(store.Doc(doc.Id)!.Blocks);                          // l'original ne bouge pas
        Assert.Equal(1, store.Update(copy)!.Revision);
        Assert.Equal(2, store.Doc(doc.Id)!.Blocks.Count);
    }

    [Fact]
    public void NamesAreCleanedAndNeverShared()
    {
        var store = new MacroLibraryStore(new MemoryMacroLibraryStorage());
        var a = store.Add(new MacroDoc { Name = "Export" });
        var b = store.Add(new MacroDoc { Name = "Autre" });
        Assert.Equal("Export final", MacroDrafts.CleanName("  Export final ", b, store));
        Assert.Null(MacroDrafts.CleanName("Export", b, store));
        Assert.Equal("Export", MacroDrafts.CleanName("Export", a, store));      // son propre nom
        Assert.Null(MacroDrafts.CleanName("   ", a, store));
        Assert.Equal(MacroValidation.MaxNameLength, MacroDrafts.CleanName(new string('x', 90), a, store)!.Length);
    }

    [Fact]
    public void ShortcutsOfAMacro()
    {
        var id = Guid.NewGuid();
        var list = new[]
        {
            Shortcut.RunsMacro(new KeyCombo(Vk.Letter('R'), Ctrl: true, Shift: true), id),
            Shortcut.RunsMacro(new KeyCombo(Vk.Letter('T'), Ctrl: true, Shift: true), Guid.NewGuid()),
            Shortcut.Action(new KeyCombo(Vk.Letter('M'), Ctrl: true, Shift: true), 21),
        };
        Assert.Same(list[0], Assert.Single(MacroDrafts.ShortcutsOf(id, list)));
    }

    [Fact]
    public void MessagesHaveTheirEnglish() => Assert.True(Loc.Has("Nouvelle macro"));
}
