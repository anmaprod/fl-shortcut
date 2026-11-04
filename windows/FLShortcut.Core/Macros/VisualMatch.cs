// Bouton retrouvé à son image (« Retrouver ce bouton s'il bouge », miroir de GrayImage et VisualMatch dans
// MacroVisual.swift du Mac) : une petite image du bouton, prise dans la seule fenêtre de FL au moment où on le montre,
// cherchée dans cette fenêtre au moment du clic. Pur et testé ; l'image d'une fenêtre n'est jamais gardée.
namespace FLShortcut.Core.Macros;

/// Image en niveaux de gris (8 bits), ligne par ligne.
public sealed class GrayImage
{
    public int Width { get; }
    public int Height { get; }
    public byte[] Pixels { get; }

    public GrayImage(int width, int height, byte[] pixels)
    {
        if (width < 0 || height < 0 || pixels.Length != width * height) throw new ArgumentException("taille d'image incohérente");
        Width = width;
        Height = height;
        Pixels = pixels;
    }

    public byte this[int x, int y] => Pixels[y * Width + x];

    /// Depuis des pixels BGRA (de haut en bas), comme ceux que Windows copie de l'écran.
    public static GrayImage FromBgra(byte[] bgra, int width, int height)
    {
        var gray = new byte[width * height];
        for (int i = 0, j = 0; i < gray.Length; i++, j += 4)
            gray[i] = (byte)((bgra[j + 2] * 299 + bgra[j + 1] * 587 + bgra[j] * 114 + 500) / 1000);
        return new GrayImage(width, height, gray);
    }

    /// Carré de `side` centré sur (cx, cy), entièrement dans l'image ; null sinon.
    public GrayImage? Crop(int cx, int cy, int side)
    {
        var x0 = cx - side / 2;
        var y0 = cy - side / 2;
        if (side <= 0 || x0 < 0 || y0 < 0 || x0 + side > Width || y0 + side > Height) return null;
        var output = new byte[side * side];
        for (var y = 0; y < side; y++) Array.Copy(Pixels, (y0 + y) * Width + x0, output, y * side, side);
        return new GrayImage(side, side, output);
    }

    /// Réduite d'un facteur entier (moyenne de chaque bloc).
    public GrayImage Reduced(int f)
    {
        if (f <= 1) return this;
        var w = Width / f;
        var h = Height / f;
        var output = new byte[Math.Max(0, w * h)];
        for (var y = 0; y < h; y++)
            for (var x = 0; x < w; x++)
            {
                var sum = 0;
                for (var yy = 0; yy < f; yy++)
                {
                    var row = (y * f + yy) * Width + x * f;
                    for (var xx = 0; xx < f; xx++) sum += Pixels[row + xx];
                }
                output[y * w + x] = (byte)(sum / (f * f));
            }
        return new GrayImage(w, h, output);
    }

    /// Écart type des niveaux : une image presque unie (fond vide) ne se reconnaît pas.
    public double Contrast
    {
        get
        {
            if (Pixels.Length == 0) return 0;
            double s = 0, ss = 0;
            foreach (var p in Pixels)
            {
                s += p;
                ss += (double)p * p;
            }
            var n = (double)Pixels.Length;
            var mean = s / n;
            return Math.Sqrt(Math.Max(0, ss / n - mean * mean));
        }
    }
}

public static class VisualMatch
{
    /// Score minimal (corrélation de -1 à 1) pour dire « c'est ce bouton ».
    public const double Threshold = 0.8;
    /// Contraste minimal de l'image d'un bouton (écart type des niveaux).
    public const double MinContrast = 8.0;

    /// Centre du bouton dans l'image (pixels), et son score.
    public readonly record struct Hit(int X, int Y, double Score);

    /// Place du bouton `patch` dans `image`, ou null s'il n'y est pas. (hintX, hintY) : centre attendu (endroit montré) ;
    /// à score presque égal (0,03), la place la plus proche gagne.
    public static Hit? Find(GrayImage patch, GrayImage image, int hintX, int hintY)
    {
        if (patch.Width < 4 || patch.Height < 4 || image.Width < patch.Width || image.Height < patch.Height
            || patch.Contrast < MinContrast) return null;
        // 1. Image réduite au tiers : toutes les places, les 8 meilleures retenues (pas deux au même endroit).
        var f = patch.Width >= 18 ? 3 : 1;
        var small = image.Reduced(f);
        var smallPatch = patch.Reduced(f);
        var coarse = Scores(smallPatch, small, 0, small.Width - smallPatch.Width, 0, small.Height - smallPatch.Height);
        coarse.Sort((a, b) => b.Score.CompareTo(a.Score));
        var picks = new List<(int X, int Y)>();
        foreach (var c in coarse)
        {
            if (c.Score < Threshold - 0.25) break;
            if (picks.Any(p => Math.Abs(p.X - c.X) * f < patch.Width / 2 && Math.Abs(p.Y - c.Y) * f < patch.Height / 2)) continue;
            picks.Add((c.X, c.Y));
            if (picks.Count == 8) break;
        }
        // 2. Au pixel près autour de chacune, sur l'image entière.
        var best = new List<Hit>();
        foreach (var p in picks)
        {
            int x0 = p.X * f, y0 = p.Y * f;
            int xa = Math.Max(0, x0 - f - 1), xb = Math.Min(image.Width - patch.Width, x0 + f + 1);
            int ya = Math.Max(0, y0 - f - 1), yb = Math.Min(image.Height - patch.Height, y0 + f + 1);
            if (xa > xb || ya > yb) continue;
            var fine = Scores(patch, image, xa, xb, ya, yb);
            if (fine.Count == 0) continue;
            var top = fine.MaxBy(s => s.Score);
            best.Add(new Hit(top.X + patch.Width / 2, top.Y + patch.Height / 2, top.Score));
        }
        if (best.Count == 0) return null;
        var max = best.Max(h => h.Score);
        if (max < Threshold) return null;
        return best.Where(h => h.Score >= max - 0.03)
            .OrderBy(h => (long)(h.X - hintX) * (h.X - hintX) + (long)(h.Y - hintY) * (h.Y - hintY))
            .First();
    }

    /// Corrélation normalisée du motif à chaque place (coin haut gauche) de [xa, xb] × [ya, yb].
    private static List<(int X, int Y, double Score)> Scores(GrayImage patch, GrayImage image, int xa, int xb, int ya, int yb)
    {
        var output = new List<(int X, int Y, double Score)>();
        int pw = patch.Width, ph = patch.Height;
        var n = (double)(pw * ph);
        var pMean = 0.0;
        foreach (var v in patch.Pixels) pMean += v;
        pMean /= n;
        var centered = new double[pw * ph];
        var pNorm = 0.0;
        for (var i = 0; i < centered.Length; i++)
        {
            centered[i] = patch.Pixels[i] - pMean;
            pNorm += centered[i] * centered[i];
        }
        if (pNorm <= 0 || xa > xb || ya > yb) return output;
        var px = image.Pixels;
        var iw = image.Width;
        for (var y = ya; y <= yb; y++)
            for (var x = xa; x <= xb; x++)
            {
                double sum = 0, sumSq = 0, cross = 0;
                for (var py = 0; py < ph; py++)
                {
                    var row = (y + py) * iw + x;
                    var prow = py * pw;
                    for (var pxi = 0; pxi < pw; pxi++)
                    {
                        double v = px[row + pxi];
                        sum += v;
                        sumSq += v * v;
                        cross += v * centered[prow + pxi];
                    }
                }
                var variance = sumSq - sum * sum / n;
                if (variance <= 1) continue;
                output.Add((x, y, cross / Math.Sqrt(variance * pNorm)));
            }
        return output;
    }
}
