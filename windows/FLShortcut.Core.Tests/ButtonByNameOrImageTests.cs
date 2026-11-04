// Clic appris « intelligent » sur Windows (demande du 04/11 : « si c'est un bouton il va l'apprendre le bouton en lui
// même, pas un endroit sur l'écran ») : nom du bouton lu sous le clic, sinon son image ; comme le Mac.
using FLShortcut.Core.Macros;
using Xunit;

namespace FLShortcut.Core.Tests;

public sealed class ButtonByNameOrImageTests
{
    private static TextItem T(string text, int x, int y, int w = 60, int h = 14) => new(text, x, y, w, h);

    [Fact]
    public void TheNameUnderTheClickIsTheButtonName()
    {
        var items = new List<TextItem>
        {
            T("FILE EDIT ADD PATTERNS", 10, 10, 220), T("FILE", 10, 10, 40), T("EDIT", 60, 10, 40),
            T("Insert 1", 300, 200, 50), T("Mixer - Insert 3", 300, 240, 120),
        };
        Assert.Equal("EDIT", TextLook.Label(70, 16, items)?.Text);                 // le mot cliqué, pas la ligne
        Assert.Equal("Insert 1", TextLook.Label(352, 205, items)?.Text);           // à 6 pixels près
        Assert.Null(TextLook.Label(320, 245, items));                              // affichage qui change : jamais
        Assert.Null(TextLook.Label(600, 400, items));                              // rien sous le clic
        // Un texte coupé par le bord de la zone lue n'est pas un nom.
        Assert.Null(TextLook.Label(20, 16, items, region: (10, 0, 300, 100)));
        var hit = Assert.IsType<NamedHit>(TextLook.Hit(330, 210, items));
        Assert.Equal(("Insert 1", 5.0, 3.0), (hit.Label, hit.Dx, hit.Dy));
    }

    [Fact]
    public void ALearnedClickKeepsTheButtonNameOrItsImage()
    {
        var place = new ClickTarget.FlWindowPoint(Corner.TopLeft, 40, 30, new Size2(500, 400));
        var named = Assert.IsType<ClickTarget.Named>(MacroDrafts.Named(place, new NamedHit("Insert 1", 2, -1)));
        Assert.Equal(("Insert 1", 40.0, 30.0), (named.Spot.Label, named.Spot.Px, named.Spot.Py));
        Assert.Equal(place, MacroDrafts.Place(named));
        Assert.Equal(place, MacroDrafts.Named(place, null));
        Assert.Equal(place, MacroDrafts.Named(place, new NamedHit("Device : X", 0, 0)));      // nom pas retenu
        var menu = new ClickTarget.OpenMenu(new PopupHop(10, 10, new Size2(200, 300)));
        Assert.Equal(menu, MacroDrafts.Named(menu, new NamedHit("Insert 1", 0, 0)));          // un menu : sa place

        var window = MacroEffectsWindowsTests.WindowWithButton(500, 400, 28, 18);
        var image = Assert.IsType<ClickTarget.Button>(MacroDrafts.Visual(place, window.Crop(40, 30, VisualSpot.DefaultSide)));
        Assert.Equal(VisualSpot.DefaultSide, image.Spot.Side);
        Assert.Equal(place, MacroDrafts.Place(image));
        // Fond uni : rien à reconnaître, sa place.
        Assert.Equal(place, MacroDrafts.Visual(place, window.Crop(300, 300, VisualSpot.DefaultSide)));
        Assert.True(MacroDrafts.CanFollow(place) && MacroDrafts.CanFollow(named) && MacroDrafts.CanFollow(image));
        Assert.False(MacroDrafts.CanFollow(menu));
        // Il se garde dans la macro (JSON commun au Mac).
        Assert.Equal(image, ClickTarget.FromJson(image.ToJson()));
        Assert.Equal(named, ClickTarget.FromJson(named.ToJson()));
    }

    [Fact]
    public void TheButtonImageIsFoundWhereItMoved()
    {
        var learned = MacroEffectsWindowsTests.WindowWithButton(400, 300, 50, 60);
        var patch = Assert.IsType<GrayImage>(learned.Crop(62, 72, VisualSpot.DefaultSide));
        var moved = MacroEffectsWindowsTests.WindowWithButton(400, 300, 250, 200);
        var hit = Assert.IsType<VisualMatch.Hit>(VisualMatch.Find(patch, moved, 62, 72));
        Assert.Equal((262, 212), (hit.X, hit.Y));
        Assert.True(hit.Score >= VisualMatch.Threshold);
        Assert.Null(VisualMatch.Find(patch, new GrayImage(400, 300, new byte[400 * 300]), 62, 72));
        Assert.Equal(new byte[] { 76, 150, 29 }, GrayImage.FromBgra(new byte[] { 0, 0, 255, 255, 0, 255, 0, 255, 255, 0, 0, 255 }, 3, 1).Pixels);
    }

    [Fact]
    public void ARecordedClickOnANamedButtonKeepsItsName()
    {
        var windows = new List<FlWin> { new(7, FlWindowRole.Dialog, 100, 100, 400, 300) };
        var result = ClickSequenceCompiler.Compile(new RecordedInput[]
        {
            new RecordedInput.Click(160, 150, false, windows, Named: new NamedHit("Time signature", 4, 0)),
            new RecordedInput.Click(160, 250, false, windows),
        });
        var first = Assert.IsType<BlockBody.Click>(result.Blocks[0]);
        Assert.Equal("Time signature", Assert.IsType<ClickTarget.Named>(first.Target).Spot.Label);
        Assert.IsType<ClickTarget.FlWindowPoint>(Assert.IsType<BlockBody.Click>(result.Blocks[1]).Target);
    }
}
