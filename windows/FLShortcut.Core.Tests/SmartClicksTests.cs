// « Enregistrer une macro » sur Windows, clics intelligents (comme le Mac, MacroClickSequence.swift) : un titre des
// menus de FL puis un élément de son menu deviennent « Menu de FL › … », son raccourci ou l'option de « Cliquer sur… ».
using FLShortcut.Core;
using FLShortcut.Core.Macros;
using Xunit;

namespace FLShortcut.Core.Tests;

public sealed class SmartClicksTests
{
    private static readonly FlWin Main = new(1, FlWindowRole.Main, 0, 0, 1600, 900);
    private static readonly FlWin FileMenu = new(2, FlWindowRole.Menu, 10, 30, 200, 300);
    private static readonly FlWin ExportMenu = new(3, FlWindowRole.Menu, 210, 148, 180, 120);

    private static TextItem Row(string text, FlWin menu, int y) => new(text, menu.X + 8, y, menu.Width - 16, 20);

    /// Le menu File (premier niveau) et son sous-menu Export, ouvert à la hauteur de « Export ».
    private static readonly MenuSnapshot File = new(FileMenu.X, FileMenu.Y, FileMenu.Width, FileMenu.Height, new[]
    {
        Row("&New", FileMenu, 36), Row("&Open...\tCtrl+O", FileMenu, 58), Row("Export ▸", FileMenu, 150), Row("Close", FileMenu, 172),
    });
    private static readonly MenuSnapshot Export = new(ExportMenu.X, ExportMenu.Y, ExportMenu.Width, ExportMenu.Height, new[]
    {
        Row("Wave file...\tCtrl+R", ExportMenu, 150), Row("MP3 file...", ExportMenu, 172), Row("Video file...", ExportMenu, 194),
    });

    private static RecordedInput.Click Title(string label, int x = 20) =>
        new(x, 10, false, new[] { Main }, Named: new NamedHit(label, 0, 0));

    private static RecordedInput.Click InMenu(params string[] path) =>
        new(250, 180, false, new[] { ExportMenu, FileMenu, Main }, MenuPath: path);

    [Fact]
    public void MenuPathFollowsTheOpenedSubmenus()
    {
        Assert.Equal(new[] { "Export", "MP3 file..." }, SmartClicks.MenuPath(new[] { File, Export }, 250, 180));
        Assert.Equal(new[] { "Open..." }, SmartClicks.MenuPath(new[] { File }, 40, 66));
        Assert.Null(SmartClicks.MenuPath(new[] { File, Export }, 900, 180));               // hors du menu
        Assert.Null(SmartClicks.MenuPath(new[] { File with { Items = Array.Empty<TextItem>() }, Export }, 250, 180));
    }

    [Fact]
    public void AMenuItemWithAShortcutBecomesThatShortcut()
    {
        var r = ClickSequenceCompiler.Compile(new RecordedInput[] { Title("FILE"), InMenu("Export", "MP3 file...") });
        var key = Assert.IsType<BlockBody.Key>(Assert.Single(r.Blocks));
        Assert.Equal(new KeyCombo(Vk.Letter('R'), Ctrl: true, Shift: true), MacKeys.ToWindows(key.Ref));
        Assert.Equal(new KeyCombo(Vk.F(9)), SmartClicks.ShortcutFor(new[] { "View", "Mixer" }));
    }

    [Fact]
    public void OtherMenuItemsBecomeFlMenuBlocks()
    {
        var r = ClickSequenceCompiler.Compile(new RecordedInput[] { Title("FILE"), InMenu("Export", "Video file...") });
        var menu = Assert.IsType<BlockBody.MenuBar>(Assert.Single(r.Blocks));
        Assert.Equal(new[] { "File", "Export", "Video file..." }, menu.Titles);
    }

    [Fact]
    public void AddChannelBecomesTheAddInstrumentOption()
    {
        var r = ClickSequenceCompiler.Compile(new RecordedInput[] { Title("ADD"), InMenu("Channel", "Serum") });
        Assert.Equal(2, r.Blocks.Count);
        Assert.Equal(new BlockBody.OpenPage(FlPage.ChannelRack), r.Blocks[0]);
        Assert.Equal(new BlockBody.PageOption("channelRack.addInstrument", "Serum"), r.Blocks[1]);
    }

    [Fact]
    public void ArrangementMenuBecomesThePlaylistOption()
    {
        var r = ClickSequenceCompiler.Compile(new RecordedInput[] { Title("Arrangement 2", 800), InMenu("Clone") });
        Assert.Equal(new BlockBody.PageOption("playlist.arrangementClone", ""), r.Blocks[^1]);
        Assert.Equal(new BlockBody.OpenPage(FlPage.Playlist), r.Blocks[0]);
        // « Merge with » ouvre un sous-menu : les clics restent des clics.
        var merge = ClickSequenceCompiler.Compile(new RecordedInput[] { Title("Arrangement", 800), InMenu("Merge with", "Arrangement 3") });
        Assert.All(merge.Blocks, b => Assert.IsType<BlockBody.Click>(b));
    }

    /// Menu illisible au clic (aucun chemin) ou bouton sans nom de menu : rien de deviné, les clics restent des clics.
    [Fact]
    public void WithoutAReadPathClicksStayClicks()
    {
        var unread = ClickSequenceCompiler.Compile(new RecordedInput[]
        {
            Title("FILE"), new RecordedInput.Click(250, 180, false, new[] { ExportMenu, FileMenu, Main }),
        });
        Assert.Equal(2, unread.Blocks.Count);
        Assert.All(unread.Blocks, b => Assert.IsType<BlockBody.Click>(b));
        var other = ClickSequenceCompiler.Compile(new RecordedInput[] { Title("Mixer"), InMenu("Export", "MP3 file...") });
        Assert.All(other.Blocks, b => Assert.IsType<BlockBody.Click>(b));
    }
}
