// Mute et solo d'une piste sans le lien avec FL (08/11, « ce sera la piste sélectionnée… il n'y a pas besoin de
// montrer ») : miroir de MuteDots.swift. Le petit rond de couleur de la piste est retrouvé tout seul dans l'image de la
// fenêtre de FL, au moment du clic :
// - Mixer : juste sous le nom de chaque piste → une RANGÉE de ronds à pas réguliers ;
// - Channel rack : à gauche des deux boutons et de la case du numéro → une COLONNE, la piste cliquée à droite ;
// - Playlist : en bas à droite de l'en-tête de chaque piste → une COLONNE, la piste cliquée à gauche.
// Rond éteint (piste coupée) : sa place vient de ses voisins, vérifiée (un disque, pas autre chose). Pur et testé.
namespace FLShortcut.Core.Macros;

/// Image en couleurs, 4 octets par pixel (rouge, vert, bleu, alpha), repère en haut à gauche.
public sealed class RgbImage
{
    public int Width { get; }
    public int Height { get; }
    public byte[] Pixels { get; }

    public RgbImage(int width, int height, byte[] pixels)
    {
        Width = width;
        Height = height;
        Pixels = pixels;
    }

    /// Pixels BGRA copiés de l'écran (Windows) remis en RGBA.
    public static RgbImage FromBgra(byte[] bgra, int width, int height)
    {
        var rgba = new byte[width * height * 4];
        for (var i = 0; i + 3 < rgba.Length && i + 3 < bgra.Length; i += 4)
        {
            rgba[i] = bgra[i + 2];
            rgba[i + 1] = bgra[i + 1];
            rgba[i + 2] = bgra[i];
            rgba[i + 3] = 255;
        }
        return new RgbImage(width, height, rgba);
    }

    /// Agrandie `factor` fois (chaque pixel répété) : un écran à 100 % montre des ronds de 5 pixels, trop petits.
    public RgbImage Scaled(int factor)
    {
        if (factor <= 1) return this;
        int w = Width * factor, h = Height * factor;
        var out_ = new byte[w * h * 4];
        for (var y = 0; y < h; y++)
            for (var x = 0; x < w; x++)
                Array.Copy(Pixels, ((y / factor) * Width + x / factor) * 4, out_, (y * w + x) * 4, 4);
        return new RgbImage(w, h, out_);
    }

    public (int R, int G, int B) Rgb(int x, int y)
    {
        var i = (y * Width + x) * 4;
        return (Pixels[i], Pixels[i + 1], Pixels[i + 2]);
    }

    public double Luminance(int x, int y)
    {
        var c = Rgb(x, y);
        return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B;
    }

    /// Pixel d'une couleur franche et claire (un voyant allumé), pas un gris ni un noir.
    public bool Lit(int x, int y)
    {
        var c = Rgb(x, y);
        int hi = Math.Max(c.R, Math.Max(c.G, c.B)), lo = Math.Min(c.R, Math.Min(c.G, c.B));
        return hi - lo >= MuteDots.MinSaturation && hi >= MuteDots.MinBrightness;
    }

    /// Couleur terne, ni grise ni franche : un rond éteint (rose terne quand la piste est coupée ou qu'une autre est en
    /// solo, vidéo du 08/11).
    public bool Faint(int x, int y)
    {
        var c = Rgb(x, y);
        int hi = Math.Max(c.R, Math.Max(c.G, c.B)), lo = Math.Min(c.R, Math.Min(c.G, c.B));
        return hi - lo >= 18 && hi >= 85 && !(hi - lo >= MuteDots.MinSaturation && hi >= MuteDots.MinBrightness);
    }
}

public static class MuteDots
{
    public const int MinSaturation = 50;
    public const int MinBrightness = 110;
    public const int MinDiameter = 5, MaxDiameter = 32;
    /// Distance (pixels de l'image) entre le nom d'une piste et son rond, dans le Channel rack et la Playlist.
    public const double ChannelReach = 700, PlaylistReach = 640;

    /// `Lit` : allumé (couleur franche) ; sinon un rond éteint, d'une couleur terne.
    public readonly record struct Blob(double X, double Y, double Diameter, bool Lit = true);

    public enum Page { Mixer, ChannelRack, Playlist }

    /// `Inferred` : rond éteint (vu terne, ou sa place déduite de ses voisins).
    public readonly record struct Target(double X, double Y, bool Inferred, Page Page);

    /// Ronds alignés à pas réguliers : une rangée (Mixer) ou une colonne (Channel rack, Playlist).
    public sealed record Series(bool Horizontal, IReadOnlyList<Blob> Members, double Step, double Line, double Diameter)
    {
        public double Along(Blob b) => Horizontal ? b.X : b.Y;
        public int LitCount => Members.Count(m => m.Lit);
    }

    private static readonly (int, int)[] Neighbours = { (-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1) };

    /// Petites taches rondes et pleines : d'une couleur franche (ronds allumés), puis d'une couleur terne (éteints).
    public static List<Blob> Blobs(RgbImage image) => Shapes(image, true).Concat(Shapes(image, false)).ToList();

    private static List<Blob> Shapes(RgbImage image, bool lit)
    {
        int w = image.Width, h = image.Height;
        var output = new List<Blob>();
        if (w <= 0 || h <= 0 || image.Pixels.Length < w * h * 4) return output;
        Func<int, int, bool> seed = lit ? image.Lit : image.Faint;
        var seen = new bool[w * h];
        var stack = new Stack<int>();
        var members = new List<int>();
        for (var start = 0; start < w * h; start++)
        {
            if (seen[start]) continue;
            seen[start] = true;
            if (!seed(start % w, start / w)) continue;
            int minX = start % w, maxX = minX, minY = start / w, maxY = minY, count = 0;
            long sumX = 0, sumY = 0;
            members.Clear();
            stack.Push(start);
            while (stack.Count > 0)
            {
                var p = stack.Pop();
                int px = p % w, py = p / w;
                count++;
                if (count <= 1200) members.Add(p);
                sumX += px;
                sumY += py;
                minX = Math.Min(minX, px); maxX = Math.Max(maxX, px); minY = Math.Min(minY, py); maxY = Math.Max(maxY, py);
                if (count > 4000) continue;                    // grande surface : jamais un rond (on la vide)
                foreach (var (dx, dy) in Neighbours)
                {
                    int nx = px + dx, ny = py + dy;
                    if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                    var n = ny * w + nx;
                    if (seen[n]) continue;
                    seen[n] = true;
                    if (seed(nx, ny)) stack.Push(n);
                }
            }
            int bw = maxX - minX + 1, bh = maxY - minY + 1;
            if (bw < MinDiameter || bw > MaxDiameter || bh < MinDiameter || bh > MaxDiameter) continue;
            var aspect = (double)bw / bh;
            var fill = (double)count / (bw * bh);
            // Plus large que haut jusqu'à 1,7 : le bas brillant d'un rond, presque blanc, n'est pas compté.
            if (aspect < 0.7 || aspect > 1.7 || fill < 0.6 || fill > 0.9) continue;
            // Un disque laisse ses coins vides : presque rien hors de l'ellipse inscrite dans son cadre.
            double cx = (minX + maxX) / 2.0, cy = (minY + maxY) / 2.0, a = Math.Max(1, bw / 2.0), b = Math.Max(1, bh / 2.0);
            var outside = members.Count(p =>
            {
                double u = (p % w - cx) / a, v = (p / w - cy) / b;
                return u * u + v * v > 1.35;
            });
            if (outside > 0.06 * members.Count) continue;
            output.Add(new Blob((double)sumX / count, (double)sumY / count, (bw + bh) / 2.0, lit));
        }
        return output;
    }

    /// Ronds de même taille, alignés, à pas réguliers (un trou d'un ou plusieurs pas : des ronds éteints). Au moins deux.
    public static List<Series> FindSeries(IReadOnlyList<Blob> blobs)
    {
        var output = new List<Series>();
        foreach (var horizontal in new[] { true, false })
        {
            Func<Blob, double> across = b => horizontal ? b.Y : b.X;
            Func<Blob, double> along = b => horizontal ? b.X : b.Y;
            var groups = new List<List<Blob>>();
            foreach (var b in blobs.OrderBy(across))
            {
                var tolerance = Math.Max(2, 0.35 * b.Diameter);
                var i = groups.FindLastIndex(g => Math.Abs(across(g[0]) - across(b)) <= tolerance
                                                  && Math.Abs(g[0].Diameter - b.Diameter) <= 0.4 * g[0].Diameter);
                if (i >= 0) groups[i].Add(b);
                else groups.Add(new List<Blob> { b });
            }
            foreach (var group in groups.Where(g => g.Count >= 2))
            {
                var sorted = group.OrderBy(along).ToList();
                var d = sorted.Select(b => b.Diameter).OrderBy(x => x).ElementAt(sorted.Count / 2);
                var gaps = sorted.Zip(sorted.Skip(1), (p, q) => along(q) - along(p)).ToList();
                // Pas plausible : plus de 1,5 rond et au plus 20 (une piste de la Playlist très haute).
                var plausible = gaps.Where(g => g >= 1.5 * d && g <= 20 * d).ToList();
                if (plausible.Count == 0) continue;
                var smallest = plausible.Min();
                var near = gaps.Where(g => Math.Abs(g / smallest - 1) <= 0.2).OrderBy(x => x).ToList();
                var step = near[near.Count / 2];
                var chain = new List<Blob> { sorted[0] };
                void Flush()
                {
                    if (chain.Count < 2) return;
                    var line = chain.Select(across).OrderBy(x => x).ElementAt(chain.Count / 2);
                    output.Add(new Series(horizontal, chain.ToList(), step, line, d));
                }
                for (var k = 1; k < sorted.Count; k++)
                {
                    var r = gaps[k - 1] / step;
                    if (r >= 0.8 && Math.Abs(r - Math.Round(r)) <= 0.2 && Math.Round(r) <= 12) chain.Add(sorted[k]);
                    else
                    {
                        Flush();
                        chain = new List<Blob> { sorted[k] };
                    }
                }
                Flush();
            }
        }
        return output;
    }

    /// Les séries qui peuvent être des pistes : une rangée du Mixer d'au moins quatre ronds (trois voyants de la barre
    /// d'outils de FL ne sont pas un Mixer, vidéo du 08/11) ; une colonne d'au moins trois (deux s'il n'y a rien
    /// d'autre) ; jamais la colonne des voyants des effets juste à droite du Mixer (un clic dessus allumerait un effet).
    public static List<Series> Usable(IReadOnlyList<Series> all)
    {
        var rows = all.Where(s => s.Horizontal && s.Members.Count >= 4).ToList();
        var columns = all.Where(s => !s.Horizontal).ToList();
        var threeColumns = columns.Where(s => s.Members.Count >= 3).ToList();
        var pool = rows.Concat(threeColumns.Count == 0 && rows.Count == 0 ? columns : threeColumns).ToList();
        var mixers = rows.Where(s => s.LitCount > 0).ToList();
        return pool.Where(s =>
        {
            if (s.Horizontal) return true;
            double top = s.Along(s.Members[0]), bottom = s.Along(s.Members[^1]);
            return !mixers.Any(m =>
            {
                var right = m.Along(m.Members[^1]) + m.Step;
                return s.Line > right && s.Line - right < 12 * m.Step
                    && bottom >= m.Line - 6 * m.Step && top <= m.Line + 6 * m.Step;
            });
        }).ToList();
    }

    /// Le rond de la piste cliquée en (x, y) (pixels de l'image), ou null : aucune rangée ni colonne de ronds autour.
    public static Target? Find(RgbImage image, double x, double y)
    {
        var all = Usable(FindSeries(Blobs(image)));
        // Une série où au moins un rond est allumé passe avant une série toute terne.
        foreach (var wantsLit in new[] { true, false })
        {
            (double Score, int Count, Target Target)? best = null;
            foreach (var s in all.Where(s => s.LitCount > 0 == wantsLit))
            {
                if (Candidate(s, x, y, image) is not { } c) continue;
                if (best is not { } b || c.Score < b.Score - 0.05 || (Math.Abs(c.Score - b.Score) <= 0.05 && s.Members.Count > b.Count))
                    best = (c.Score, s.Members.Count, c.Target);
            }
            if (best is { } found) return found.Target;
        }
        return null;
    }

    /// Ce qui a été vu (nombres seulement, pour le journal) : ronds allumés + éteints, séries (ronds/allumés@pas).
    public static string Summary(RgbImage image)
    {
        var b = Blobs(image);
        var s = Usable(FindSeries(b));
        return $"dots={b.Count(x => x.Lit)}+{b.Count(x => !x.Lit)} series={s.Count}"
               + string.Concat(s.Take(8).Select(x => $" {(x.Horizontal ? "row" : "col")}{x.Members.Count}/{x.LitCount}@{(int)x.Step}"));
    }

    private static (double Score, Target Target)? Candidate(Series s, double x, double y, RgbImage image)
    {
        double first = s.Along(s.Members[0]), last = s.Along(s.Members[^1]);
        Page page;
        double along, score;
        if (s.Horizontal)
        {
            // Mixer : du nom (vertical, haut de cinq pas au-dessus du rond) jusqu'au fader et plus bas.
            if (x < first - s.Step || x > last + s.Step || y < s.Line - 6 * s.Step || y > s.Line + 14 * s.Step) return null;
            page = Page.Mixer;
            along = x;
            score = Math.Abs(y - s.Line) / s.Step;
        }
        else if (x >= s.Line)
        {
            // Channel rack : le nom du son à droite des ronds, le rond au milieu de sa ligne.
            if (x > s.Line + ChannelReach || y < first - s.Step || y > last + s.Step) return null;
            page = Page.ChannelRack;
            along = y;
            score = (x - s.Line) / s.Step;
        }
        else
        {
            // Playlist : le rond en bas à droite de l'en-tête (de 0,75 pas au-dessus à 0,25 dessous).
            if (x < s.Line - PlaylistReach || y < first - 0.75 * s.Step || y > last + 0.25 * s.Step) return null;
            page = Page.Playlist;
            along = y + 0.25 * s.Step;
            score = (s.Line - x) / s.Step;
        }
        if (Spot(s, along, image) is not { } spot) return null;
        return s.Horizontal
            ? (score, new Target(spot.Along, s.Line, spot.Inferred, page))
            : (score, new Target(s.Line, spot.Along, spot.Inferred, page));
    }

    /// Le rond le plus proche le long de la série : allumé à moins d'un demi-pas, sinon la place d'un rond éteint entre
    /// deux voisins (ou un pas au-delà du dernier), vérifiée dans l'image.
    private static (double Along, bool Inferred)? Spot(Series s, double value, RgbImage image)
    {
        var positions = s.Members.Select(s.Along).ToList();
        var nearest = s.Members.OrderBy(m => Math.Abs(s.Along(m) - value)).First();
        if (Math.Abs(s.Along(nearest) - value) <= 0.5 * s.Step) return (s.Along(nearest), !nearest.Lit);
        double guess;
        var right = positions.FindIndex(p => p > value);
        if (right > 0)
        {
            double a = positions[right - 1], b = positions[right];
            var n = Math.Max(1, Math.Round((b - a) / s.Step));
            var pitch = (b - a) / n;
            guess = a + Math.Round((value - a) / pitch) * pitch;
        }
        else if (value > positions[^1]) guess = positions[^1] + Math.Max(1, Math.Round((value - positions[^1]) / s.Step)) * s.Step;
        else guess = positions[0] - Math.Max(1, Math.Round((positions[0] - value) / s.Step)) * s.Step;
        if (Math.Abs(guess - value) > 0.5 * s.Step + 1) return null;
        var (px, py) = s.Horizontal ? (guess, s.Line) : (s.Line, guess);
        return LooksLikeDisk(image, px, py, s.Diameter) ? (guess, true) : null;
    }

    /// Un rond éteint à cette place : un disque uni, net sur ce qui l'entoure, sans couleur franche.
    public static bool LooksLikeDisk(RgbImage image, double x, double y, double d)
    {
        var r = d / 2;
        int cx = (int)Math.Round(x), cy = (int)Math.Round(y), reach = (int)Math.Ceiling(r * 1.9);
        if (cx - reach < 0 || cy - reach < 0 || cx + reach >= image.Width || cy + reach >= image.Height) return false;
        var inner = new List<double>();
        var ring = new List<double>();
        for (var dy = -reach; dy <= reach; dy++)
            for (var dx = -reach; dx <= reach; dx++)
            {
                var dist = Math.Sqrt(dx * dx + dy * dy);
                if (image.Lit(cx + dx, cy + dy)) return false;
                var l = image.Luminance(cx + dx, cy + dy);
                if (dist <= 0.55 * r) inner.Add(l);
                else if (dist >= 1.35 * r && dist <= 1.85 * r) ring.Add(l);
            }
        if (inner.Count == 0 || ring.Count == 0) return false;
        double mi = inner.Average(), mr = ring.Average();
        var spread = Math.Sqrt(inner.Select(v => (v - mi) * (v - mi)).Average());
        return Math.Abs(mi - mr) >= 8 && spread <= 18;
    }
}
