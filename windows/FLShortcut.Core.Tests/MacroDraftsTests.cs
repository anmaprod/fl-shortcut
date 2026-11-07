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
    public void CreatorPaletteIsTheMacOne()
    {
        var palette = MacroDrafts.CreatorPalette(MacroEffectsWindows.Unsupported, _ => true);
        Assert.Equal(new[] { BlockCategory.Fl, BlockCategory.Keyboard, BlockCategory.Mouse, BlockCategory.Windows },
            palette.Select(p => p.Category));
        var fl = palette[0].Entries.Select(e => e.Type).ToList();
        Assert.Equal(BlockType.MenuBar, fl[0]);
        Assert.DoesNotContain(BlockType.SoundCard, fl);                      // carte son : pas encore sur Windows
        var all = palette.SelectMany(p => p.Entries).ToList();
        Assert.DoesNotContain(all, e => e.Category == BlockCategory.Control);
        Assert.DoesNotContain(all, e => e.Type is BlockType.Delay or BlockType.WaitWindowClose or BlockType.TrackMenu);
        var wait = Assert.Single(all, e => e.Type == BlockType.WaitWindow);
        Assert.Equal(("Attendre", "clock"), (wait.Label, wait.Symbol));
        Assert.Equal("Clic à un endroit appris", Assert.Single(all, e => e.Type == BlockType.Click).Label);
        Assert.All(all, e => Assert.Equal(e.Type, e.Make().Type));
        Assert.DoesNotContain(MacroDrafts.CreatorPalette(null, t => t != BlockType.Drag).SelectMany(p => p.Entries),
            e => e.Type == BlockType.Drag);
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

    /// Clic montré : dans un menu, relatif à ce menu ; dans une fenêtre, relatif à son coin le plus proche ; ailleurs, rien.
    [Fact]
    public void ShownClickIsKeptRelativeToItsWindow()
    {
        var windows = new List<FlWin>
        {
            new(20, FlWindowRole.Menu, 400, 300, 200, 150),
            new(40, FlWindowRole.Dialog, 300, 200, 500, 400),
            new(1, FlWindowRole.Main, 0, 0, 1200, 800),
        };
        Assert.Equal(new ClickTarget.OpenMenu(new PopupHop(10, 20, new Size2(200, 150))), MacroDrafts.LearnedTarget(410, 320, windows));
        Assert.Equal(new ClickTarget.FlWindowPoint(Corner.TopLeft, 20, 30, new Size2(500, 400)), MacroDrafts.LearnedTarget(320, 230, windows));
        Assert.Equal(new ClickTarget.FlWindowPoint(Corner.BottomRight, -10, -5, new Size2(500, 400)), MacroDrafts.LearnedTarget(790, 595, windows));
        Assert.Equal(new ClickTarget.FlWindowPoint(Corner.BottomLeft, 5, -10, new Size2(1200, 800)), MacroDrafts.LearnedTarget(5, 790, windows));
        Assert.Null(MacroDrafts.LearnedTarget(1500, 100, windows));
    }

    [Fact]
    public void TypedMenuPathKeepsItsTitles()
    {
        Assert.Equal(new[] { "File", "Export", "All playlist tracks", "Time selection..." },
            MacroDrafts.MenuPath(" File › Export>All playlist tracks ›  Time selection... "));
        Assert.Empty(MacroDrafts.MenuPath(" › "));
    }
}
