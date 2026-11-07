// « Enregistrer une macro » sur Windows : les clics et les touches relevés dans FL deviennent les mêmes blocs que sur
// le Mac (ClickSequenceCompiler).
using FLShortcut.Core;
using FLShortcut.Core.Macros;
using Xunit;

namespace FLShortcut.Core.Tests;

public sealed class ClickSequenceTests
{
    private static readonly FlWin Main = new(1, FlWindowRole.Main, 0, 0, 1600, 900);
    private static readonly FlWin Menu = new(2, FlWindowRole.Menu, 100, 40, 200, 300);
    private static readonly IReadOnlyList<FlWin> MainOnly = new[] { Main };
    private static readonly IReadOnlyList<FlWin> MenuOpen = new[] { Menu, Main };

    private static RecordedInput.Key K(ushort vk, bool ctrl = false, bool menu = false, bool shift = false) =>
        new(new KeyCombo(vk, Ctrl: ctrl, Shift: shift), menu);

    [Fact]
    public void KeysBecomeKeyBlocksAndRepeatsAreCounted()
    {
        var r = ClickSequenceCompiler.Compile(new RecordedInput[] { K(Vk.Letter('S'), ctrl: true), K(Vk.Letter('S'), ctrl: true), K(Vk.F(5)) });
        Assert.Equal(2, r.Blocks.Count);
        var save = Assert.IsType<BlockBody.Key>(r.Blocks[0]);
        Assert.Equal(2, save.Times);
        Assert.True(save.Ref.Combo.Command);
        Assert.Equal("s", save.Ref.Char);
        Assert.Equal(new KeyCombo(Vk.Letter('S'), Ctrl: true), MacKeys.ToWindows(save.Ref));
        Assert.Equal(new KeyCombo(Vk.F(5)), MacKeys.ToWindows(Assert.IsType<BlockBody.Key>(r.Blocks[1]).Ref));
        Assert.Equal(0, r.Ignored);
    }

    [Fact]
    public void InAnOpenMenuArrowsEnterAndLettersBecomeMenuBlocks()
    {
        var r = ClickSequenceCompiler.Compile(new RecordedInput[]
        {
            K(Vk.Down, menu: true), K(Vk.Down, menu: true), K(Vk.Return, menu: true),
            K(Vk.Letter('E'), menu: true), K(Vk.Letter('X'), menu: true),
            K(Vk.Down),                                              // menu refermé : une touche ordinaire
        });
        Assert.Equal(new BlockBody.MenuKeyPress(MenuKey.Down, 2), r.Blocks[0]);
        Assert.Equal(new BlockBody.MenuKeyPress(MenuKey.Enter, 1), r.Blocks[1]);
        var letters = Assert.IsType<BlockBody.MenuLetters>(r.Blocks[2]);
        Assert.Equal("ex", letters.Letters);
        Assert.Equal("never", letters.FinalEnter.Mode);
        Assert.IsType<BlockBody.Key>(r.Blocks[3]);
    }

    [Fact]
    public void RepeatsStopAtTheBlockLimits()
    {
        var downs = Enumerable.Repeat<RecordedInput>(K(Vk.Down, menu: true), ClickSequenceCompiler.MaxTimes + 1).ToList();
        var r = ClickSequenceCompiler.Compile(downs);
        Assert.Equal(new BlockBody.MenuKeyPress(MenuKey.Down, ClickSequenceCompiler.MaxTimes), r.Blocks[0]);
        Assert.Equal(new BlockBody.MenuKeyPress(MenuKey.Down, 1), r.Blocks[1]);
        var letters = Enumerable.Repeat<RecordedInput>(K(Vk.Letter('A'), menu: true), ClickSequenceCompiler.MaxMenuLetters + 1).ToList();
        var l = ClickSequenceCompiler.Compile(letters);
        Assert.Equal(new string('a', ClickSequenceCompiler.MaxMenuLetters), Assert.IsType<BlockBody.MenuLetters>(l.Blocks[0]).Letters);
        Assert.Equal("a", Assert.IsType<BlockBody.MenuLetters>(l.Blocks[1]).Letters);
    }

    [Fact]
    public void ClicksAreLearnedLikeShowInFl()
    {
        var r = ClickSequenceCompiler.Compile(new RecordedInput[]
        {
            new RecordedInput.Click(30, 20, false, MainOnly),
            new RecordedInput.Click(150, 100, false, MenuOpen),
            new RecordedInput.Click(1590, 890, true, MainOnly),
            new RecordedInput.Click(2000, 20, false, MainOnly),    // hors de FL
        });
        Assert.Equal(3, r.Blocks.Count);
        Assert.Equal(1, r.Ignored);
        var first = Assert.IsType<BlockBody.Click>(r.Blocks[0]);
        Assert.Equal(new ClickTarget.FlWindowPoint(Corner.TopLeft, 30, 20, new Size2(1600, 900)), first.Target);
        Assert.Equal(MouseButton.Left, first.Button);
        Assert.IsType<ClickTarget.OpenMenu>(Assert.IsType<BlockBody.Click>(r.Blocks[1]).Target);
        var right = Assert.IsType<BlockBody.Click>(r.Blocks[2]);
        Assert.Equal(MouseButton.Right, right.Button);
        Assert.Equal(Corner.BottomRight, Assert.IsType<ClickTarget.FlWindowPoint>(right.Target).Corner);
    }

    [Fact]
    public void ALeftButtonReleasedFarAwayIsADrag()
    {
        var r = ClickSequenceCompiler.Compile(new RecordedInput[]
        {
            new RecordedInput.Click(100, 100, false, MainOnly, new RecordedRelease(400, 300, MainOnly)),
            new RecordedInput.Click(100, 100, false, MainOnly, new RecordedRelease(103, 102, MainOnly)),   // à peine bougé
        });
        Assert.IsType<BlockBody.Drag>(r.Blocks[0]);
        Assert.IsType<BlockBody.Click>(r.Blocks[1]);
    }

    /// 07/11 (comme le Mac) : le nom du son que FL montre sous la souris pendant le glisser n'est pas un menu ouvert.
    [Fact]
    public void ADragIgnoresTheLabelFlShowsUnderTheMouse()
    {
        var label = new FlWin(3, FlWindowRole.Menu, 390, 290, 120, 20);
        var r = ClickSequenceCompiler.Compile(new RecordedInput[]
        {
            new RecordedInput.Click(100, 100, false, MainOnly, new RecordedRelease(400, 300, new[] { label, Main })),
        });
        var drag = Assert.IsType<BlockBody.Drag>(r.Blocks[0]);
        Assert.IsType<ClickTarget.FlWindowPoint>(drag.To);
    }

    [Fact]
    public void KeysWithoutEquivalentAreIgnoredAndEveryBlockIsValid()
    {
        var r = ClickSequenceCompiler.Compile(new RecordedInput[]
        {
            K(0xFF), K(Vk.Letter('S'), ctrl: true), new RecordedInput.Click(30, 20, false, MainOnly),
            K(Vk.Down, menu: true), K(Vk.Letter('E'), menu: true),
        });
        Assert.Equal(1, r.Ignored);
        var macro = r.Blocks.Select(b => new Block(b)).ToList();
        Assert.Null(MacroValidation.Problem(macro, null, new ValidationContext { Home = Path.GetTempPath() }));
    }
}
