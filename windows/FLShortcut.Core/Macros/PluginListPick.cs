// La ligne d'un plugin dans la liste « More plugins… » de FL, lue dans sa fenêtre (09/11, « des bugs avec l'ouverture
// de vst/plugin en passant par Cliquer sur… », Windows) : miroir de PluginListPick (MacroPluginList.swift du Mac). Avant,
// Windows ne prenait que le nom exact : une ligne lue d'un seul tenant avec ses colonnes (« Analog Lab V VST3 Arturia »)
// ou avec l'étoile des favoris devant n'était jamais reconnue, et toute la liste défilait pour rien. Pur, testé.
namespace FLShortcut.Core.Macros;

public static class PluginListPick
{
    /// Colonne « Format » de la liste de FL, à la forme de comparaison.
    public static readonly HashSet<string> Formats =
        new[] { "vst", "vst2", "vst3", "au", "fl", "clap", "aax" }.Select(MenuText.Normalized).ToHashSet();

    /// Le texte lu est-il le nom voulu (forme de comparaison) ? Même texte sans ce qui le précède (l'étoile des
    /// favoris, lue « ☆ » ou « * ») ; ou le début d'une ligne lue d'un seul tenant, suivi de la colonne du format
    /// (jamais « Serum 2 » pour « Serum », ni « Serum 2 FX » pour « Serum 2 »).
    public static bool Matches(string read, string wanted)
    {
        var text = new string(read.SkipWhile(c => !char.IsLetterOrDigit(c)).ToArray());
        if (text == wanted) return true;
        if (!text.StartsWith(wanted + " ", StringComparison.Ordinal)) return false;
        var next = text[(wanted.Length + 1)..].Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault() ?? "";
        return Formats.Contains(next);
    }

    /// Parmi les lignes au nom du plugin, celle du format préféré (`prefer`, forme de comparaison : un instrument en
    /// VST3 puis VST, un effet du Mixer en AU), la plus haute à égalité. Le format est lu juste après le nom dans une
    /// ligne d'un seul tenant, sinon à droite du nom sur la même ligne. null : absent.
    public static TextItem? Best(string name, IReadOnlyList<string> prefer, IReadOnlyList<TextItem> items)
    {
        var wanted = MenuText.Normalized(name);
        if (wanted.Length == 0) return null;
        var hits = items.Where(i => Matches(MenuText.Normalized(i.Text), wanted)).ToList();
        string? FormatOf(TextItem hit)
        {
            var text = new string(MenuText.Normalized(hit.Text).SkipWhile(c => !char.IsLetterOrDigit(c)).ToArray());
            if (text.Length > wanted.Length)
                return text[(wanted.Length + 1)..].Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
            var tolerance = Math.Max(hit.Height, 8) * 0.6;
            return items.Where(o => o.X > hit.X + hit.Width && Math.Abs(o.CenterY - hit.CenterY) < tolerance)
                .OrderBy(o => o.X).Select(o => MenuText.Normalized(o.Text)).FirstOrDefault(Formats.Contains);
        }
        int Rank(TextItem hit) => FormatOf(hit) is { } f && prefer.ToList().IndexOf(f) is var at and >= 0 ? at : prefer.Count;
        return hits.OrderBy(Rank).ThenBy(h => h.Y).Cast<TextItem?>().FirstOrDefault();
    }

    /// Où double-cliquer une ligne trouvée : au milieu du nom (une ligne lue d'un seul tenant va jusqu'aux colonnes du
    /// format et de la marque ; jamais la case devant le nom, qui en ferait un favori).
    public static (int X, int Y) NamePoint(TextItem hit, string name)
    {
        var text = hit.Text ?? "";
        var wanted = MenuText.Normalized(name);
        var read = MenuText.Normalized(text);
        if (wanted.Length == 0 || read.Length <= wanted.Length + 1) return (hit.CenterX, hit.CenterY);
        var start = read.TakeWhile(c => !char.IsLetterOrDigit(c)).Count();
        var middle = (start + wanted.Length / 2.0) / read.Length;
        return (hit.X + (int)Math.Round(hit.Width * middle), hit.CenterY);
    }

    /// Ordre des formats : instrument (Channel rack) VST3 puis VST ; effet (Mixer) AU d'abord (comme le Mac).
    public static IReadOnlyList<string> PreferredFormats(string item) =>
        (item == "Effect" ? new[] { "au", "vst3", "vst", "clap", "fl" } : new[] { "vst3", "vst", "au", "clap", "fl" })
        .Select(MenuText.Normalized).ToList();

    /// Le bouton « Find » en bas de la liste de FL (fenêtre `list`), s'il est lu.
    public static TextItem? FindButton(IReadOnlyList<TextItem> items, FlWin list)
    {
        var wanted = MenuText.Normalized("Find");
        var low = list.Y + list.Height - Math.Max(80, list.Height / 5);
        return items.Where(i => MenuText.Normalized(i.Text) == wanted && i.Y > low).Cast<TextItem?>().FirstOrDefault();
    }
}
