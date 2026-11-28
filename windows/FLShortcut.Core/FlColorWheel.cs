// Roue du « Color selector » de FL et son échelle teinte / saturation / luminance (09/11, « l'Organiser de Windows le
// même que sur Mac ») : miroir de FLColorWheel et FLHSL (Sources/FLShortcut/NameColor.swift). Pur, testé.
namespace FLShortcut.Core;

/// Teinte 0…359, saturation et luminance 0…240 (échelle de FL).
public record struct FlHsl(int Hue, int Saturation, int Luminance)
{
    public const double Scale = 240.0;

    public static FlHsl Of(RgbColor c)
    {
        double r = c.R / 255.0, g = c.G / 255.0, b = c.B / 255.0;
        double max = Math.Max(r, Math.Max(g, b)), min = Math.Min(r, Math.Min(g, b)), delta = max - min;
        var l = (max + min) / 2;
        double h = 0, s = 0;
        if (delta > 0)
        {
            s = l < 0.5 ? delta / (max + min) : delta / (2 - max - min);
            if (max == r) h = (g - b) / delta + (g < b ? 6 : 0);
            else if (max == g) h = (b - r) / delta + 2;
            else h = (r - g) / delta + 4;
            h *= 60;
        }
        return new FlHsl((int)Math.Round(h, MidpointRounding.AwayFromZero) % 360,
                         (int)Math.Round(s * Scale, MidpointRounding.AwayFromZero),
                         (int)Math.Round(l * Scale, MidpointRounding.AwayFromZero));
    }

    public RgbColor ToRgb()
    {
        var h = (((Hue % 360) + 360) % 360) / 360.0;
        var s = Math.Clamp(Saturation / Scale, 0, 1);
        var l = Math.Clamp(Luminance / Scale, 0, 1);
        return FromHsl(h, s, l);
    }

    /// HSL classique (0…1 chacun).
    public static RgbColor FromHsl(double h, double s, double l)
    {
        if (s <= 0)
        {
            var v = (byte)Math.Round(l * 255, MidpointRounding.AwayFromZero);
            return new RgbColor(v, v, v);
        }
        var q = l < 0.5 ? l * (1 + s) : l + s - l * s;
        var p = 2 * l - q;
        byte Channel(double t)
        {
            if (t < 0) t += 1;
            if (t > 1) t -= 1;
            double v;
            if (t < 1.0 / 6) v = p + (q - p) * 6 * t;
            else if (t < 1.0 / 2) v = q;
            else if (t < 2.0 / 3) v = p + (q - p) * (2.0 / 3 - t) * 6;
            else v = p;
            return (byte)Math.Round(Math.Clamp(v * 255, 0, 255), MidpointRounding.AwayFromZero);
        }
        return new RgbColor(Channel(h + 1.0 / 3), Channel(h), Channel(h - 1.0 / 3));
    }
}

/// La roue de FL : 16 secteurs (0° en haut, sens des aiguilles d'une montre), un disque central et 5 anneaux.
public static class FlColorWheel
{
    public const int Sectors = 16;
    /// Rayons relatifs (rayon extérieur = 1) des bords : disque central, puis anneaux 1 à 5 (relevés sur FL).
    public static readonly double[] Edges = { 0.174, 0.339, 0.504, 0.669, 0.835, 1.0 };
    public static readonly RgbColor Center = new(168, 168, 168);

    private static RgbColor[] List(params (byte, byte, byte)[] v) => v.Select(c => new RgbColor(c.Item1, c.Item2, c.Item3)).ToArray();

    public static readonly RgbColor[] Pale = List((253, 203, 203), (255, 224, 206), (255, 240, 200), (247, 253, 204), (219, 248, 198),
        (201, 243, 202), (189, 249, 210), (196, 254, 236), (193, 254, 254), (197, 236, 253), (202, 217, 255), (212, 205, 255),
        (232, 204, 255), (251, 202, 250), (254, 202, 242), (252, 200, 219));
    public static readonly RgbColor[] Medium = List((253, 152, 155), (249, 181, 145), (250, 223, 150), (241, 255, 149), (187, 249, 144),
        (148, 250, 152), (127, 252, 174), (127, 252, 215), (129, 254, 255), (139, 219, 255), (153, 182, 253), (173, 157, 254),
        (215, 156, 254), (246, 155, 245), (255, 152, 231), (255, 153, 192));
    public static readonly RgbColor[] Vivid = List((254, 105, 110), (253, 156, 103), (255, 214, 99), (232, 253, 92), (155, 244, 88),
        (89, 250, 102), (46, 252, 135), (46, 253, 197), (46, 253, 254), (84, 197, 251), (104, 147, 253), (129, 110, 240),
        (194, 110, 250), (244, 110, 246), (252, 105, 223), (253, 106, 161));

    /// Anneau 0 : centre ; 1 pâle ; 2 moyen ; 3 vif ; 4 et 5 : la teinte vive assombrie.
    public static RgbColor Color(int ring, int sector)
    {
        var k = ((sector % Sectors) + Sectors) % Sectors;
        switch (ring)
        {
            case 0: return Center;
            case 1: return Pale[k];
            case 2: return Medium[k];
            case 3: return Vivid[k];
            default:
                var v = FlHsl.Of(Vivid[k]);
                return (v with { Luminance = ring == 4 ? 90 : 56 }).ToRgb();
        }
    }

    /// Case sous un point, en coordonnées relatives au centre (rayon extérieur = 1, y vers le bas) ; null hors de la
    /// roue.
    public static (int Ring, int Sector)? Hit(double dx, double dy)
    {
        var r = Math.Sqrt(dx * dx + dy * dy);
        if (r > Edges[^1]) return null;
        var ring = Array.FindIndex(Edges, e => r <= e);
        if (ring < 0) return null;
        if (ring == 0) return (0, 0);
        var angle = Math.Atan2(dx, -dy) * 180 / Math.PI;
        if (angle < 0) angle += 360;
        var step = 360.0 / Sectors;
        return (ring, (int)Math.Floor((angle + step / 2) / step) % Sectors);
    }
}
