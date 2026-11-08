// Mute / solo sans le lien (08/11) : le rond de la piste cliquée retrouvé tout seul. Miroir de
// Tests/FLShortcutTests/MuteDotsTests.swift (mêmes fenêtres dessinées : Mixer, Channel rack, Playlist).
using FLShortcut.Core.Macros;
using Xunit;

namespace FLShortcut.Core.Tests;

public sealed class MuteDotsTests
{
    private sealed class Canvas
    {
        public readonly int Width, Height;
        public readonly byte[] Pixels;

        public Canvas(int width, int height, (int, int, int)? c = null)
        {
            Width = width;
            Height = height;
            Pixels = new byte[width * height * 4];
            Rect(0, 0, width, height, c ?? (52, 54, 58));
        }

        public void Set(int x, int y, (int R, int G, int B) c)
        {
            if (x < 0 || y < 0 || x >= Width || y >= Height) return;
            var i = (y * Width + x) * 4;
            Pixels[i] = (byte)c.R; Pixels[i + 1] = (byte)c.G; Pixels[i + 2] = (byte)c.B; Pixels[i + 3] = 255;
        }

        public void Rect(int x, int y, int w, int h, (int, int, int) c)
        {
            for (var yy = y; yy < y + h; yy++)
                for (var xx = x; xx < x + w; xx++) Set(xx, yy, c);
        }

        public void Disk(int cx, int cy, double r, (int, int, int) c)
        {
            var reach = (int)Math.Ceiling(r);
            for (var dy = -reach; dy <= reach; dy++)
                for (var dx = -reach; dx <= reach; dx++)
                    if (dx * dx + dy * dy <= r * r) Set(cx + dx, cy + dy, c);
        }

        public void Ring(int cx, int cy, double r, (int, int, int) c)
        {
            var reach = (int)Math.Ceiling(r) + 1;
            for (var dy = -reach; dy <= reach; dy++)
                for (var dx = -reach; dx <= reach; dx++)
                    if (Math.Abs(Math.Sqrt(dx * dx + dy * dy) - r) <= 1.2) Set(cx + dx, cy + dy, c);
        }

        public RgbImage Image => new(Width, Height, Pixels);
    }

    internal static void Near(double expected, double actual, double tolerance = 1) =>
        Assert.InRange(actual, expected - tolerance, expected + tolerance);

    private static readonly (int, int, int) Pink = (225, 143, 184), Green = (110, 220, 90), Unlit = (92, 92, 96),
        Dull = (126, 87, 108);

    /// Mixer : 12 pistes de 58 pixels, nom au-dessus, rond rose dessous ; à droite, les voyants des effets. `half` :
    /// le même à moitié (écran à 100 %, ronds de 5 pixels), dans la même fenêtre de 1400 × 900.
    internal static RgbImage Mixer(ISet<int>? muted = null, bool half = false, int? soloed = null)
    {
        var k = half ? 0.5 : 1.0;
        int S(double v) => (int)Math.Round(v * k);
        var c = new Canvas(1400, 900);
        foreach (var bx in new[] { 300, 380, 460 }) c.Disk(S(bx), S(40), 8 * k, (200, 60, 60));   // barre d'outils de FL
        for (var t = 0; t < 12; t++)
        {
            var x = S(100 + t * 58);
            c.Rect(x - S(20), S(300), S(40), S(120), (60, 62, 66));
            var color = soloed is { } so ? (so == t ? Pink : Dull) : muted?.Contains(t) == true ? Unlit : Pink;
            c.Disk(x, S(440), 5.5 * k, color);
            c.Ring(x, S(480), 12 * k, (110, 110, 112));
            c.Rect(x - S(4), S(520), S(8), S(260), (40, 40, 42));
        }
        for (var slot = 0; slot < 10; slot++) c.Disk(S(1360), S(200 + slot * 40), 5 * k, Pink);
        return c.Image;
    }

    [Fact]
    public void MixerTrackUnderTheClickedName()
    {
        var onName = MuteDots.Find(Mixer(), 274, 360);
        Assert.NotNull(onName);
        Assert.Equal(MuteDots.Page.Mixer, onName!.Value.Page);
        Near(274, onName.Value.X, 1);
        Near(440, onName.Value.Y, 1);
        Assert.False(onName.Value.Inferred);
        Near(448, MuteDots.Find(Mixer(), 450, 700)!.Value.X, 1);          // clic sur le fader de la 7e piste
    }

    [Fact]
    public void MutedMixerTrackIsFoundBetweenItsNeighbours()
    {
        var t = MuteDots.Find(Mixer(new HashSet<int> { 4 }), 332, 360);
        Assert.NotNull(t);
        Near(332, t!.Value.X, 1.5);
        Assert.True(t.Value.Inferred);
    }

    [Fact]
    public void SoloedMixerTrackIsFoundAmongDullDots()
    {
        var image = Mixer(soloed: 3);
        var soloed = MuteDots.Find(image, 274, 360);
        Assert.NotNull(soloed);
        Near(274, soloed!.Value.X);
        Assert.False(soloed.Value.Inferred);
        var other = MuteDots.Find(image, 448, 360);
        Assert.NotNull(other);
        Near(448, other!.Value.X);
        Assert.True(other.Value.Inferred);
    }

    [Fact]
    public void EffectSlotsNextToTheMixerAreNeverClicked() => Assert.Null(MuteDots.Find(Mixer(), 1300, 320));

    private static RgbImage ChannelRack((int, int, int) dot, ISet<int>? muted = null)
    {
        var c = new Canvas(1200, 600, (46, 48, 52));
        foreach (var bx in new[] { 40, 120, 200 }) c.Disk(bx, 20, 8, (200, 60, 60));   // barre d'outils de FL
        for (var row = 0; row < 6; row++)
        {
            var y = 80 + row * 52;
            c.Disk(60, y, 5.5, muted?.Contains(row) == true ? Unlit : dot);
            c.Ring(100, y, 10, (120, 120, 124));
            c.Ring(140, y, 10, (120, 120, 124));
            c.Rect(166, y - 12, 30, 24, (30, 30, 32));
            c.Rect(210, y - 18, 200, 36, (84, 86, 92));
            for (var step = 0; step < 16; step++)
                if ((step + row) % 3 == 0) c.Rect(430 + step * 34, y - 20, 26, 40, (200, 90, 60));
        }
        return c.Image;
    }

    [Fact]
    public void ChannelRackDotLeftOfTheClickedName()
    {
        foreach (var dot in new[] { Pink, Green })
        {
            var t = MuteDots.Find(ChannelRack(dot), 300, 184);
            Assert.NotNull(t);
            Assert.Equal(MuteDots.Page.ChannelRack, t!.Value.Page);
            Near(60, t.Value.X, 1);
            Near(184, t.Value.Y, 1);
        }
        var muted = MuteDots.Find(ChannelRack(Pink, new HashSet<int> { 2 }), 300, 186);
        Assert.NotNull(muted);
        Near(184, muted!.Value.Y, 1.5);
        Assert.True(muted.Value.Inferred);
    }

    internal static RgbImage Playlist()
    {
        var c = new Canvas(1300, 800, (40, 42, 46));
        for (var track = 0; track < 7; track++)
        {
            var top = 40 + track * 90;
            c.Rect(20, top + 2, 340, 86, (62, 64, 70));
            c.Rect(40, top + 14, 160, 22, (90, 92, 98));
            c.Disk(338, top + 70, 5.5, Pink);
            if (track % 2 == 0) c.Rect(400 + track * 40, top + 6, 300, 78, (120, 70, 200));
        }
        return c.Image;
    }

    [Theory]
    [InlineData(228, 290)]
    [InlineData(245, 290)]
    [InlineData(305, 290)]
    [InlineData(60, 110)]
    public void PlaylistDotAtTheBottomRightOfTheClickedHeader(double clickY, double expected)
    {
        var t = MuteDots.Find(Playlist(), 110, clickY);
        Assert.NotNull(t);
        Assert.Equal(MuteDots.Page.Playlist, t!.Value.Page);
        Near(338, t.Value.X, 1);
        Near(expected, t.Value.Y, 1);
    }

    [Fact]
    public void NothingAroundTheClickGivesNothing()
    {
        Assert.Null(MuteDots.Find(new Canvas(400, 300).Image, 200, 150));
        Assert.Null(MuteDots.Find(Playlist(), 1250, 300));
    }
}
