// « Ajouter un instrument / un effet » en déposant le fichier du plugin pris dans la Plugin database de FL (demande et
// essais du propriétaire, 04/11 : « trop lent… faire comme le drag and drop ») : Installed › Generators › VST3 ›
// <nom>.fst déposé juste sous le dernier son du Channel rack ouvre l'instrument ; Installed › Effects › AudioUnit (ou
// VST3) › <nom>.fst déposé sur la piste du Mixer visée ouvre l'effet. Seulement les .fst (les .nfo ne marchent pas).
// Déposé SUR un son, il le REMPLACE ; ailleurs dans FL, rien. Miroir de PluginDrop (MacroPluginDrop.swift du Mac).
// Rien n'est jamais écrit dans la base de FL (règle du propriétaire) : on y lit seulement le nom des fichiers.
namespace FLShortcut.Core.Macros;

public static class PluginDrop
{
    /// Format d'un dossier de la base (« AudioUnit » → « au », « VST2 » → « vst »).
    public static string FormatKey(string folder)
    {
        var f = folder.Trim().ToLowerInvariant().Replace(" ", "");
        return f switch
        {
            "audiounit" or "audiounits" or "au" or "component" or "components" => "au",
            "vst" or "vst2" => "vst",
            "vst3" => "vst3",
            "clap" => "clap",
            "fruity" or "native" or "fl" => "fl",
            _ => f,
        };
    }

    /// Ordre des formats (comme le Mac, 03/11) : un instrument en VST3 puis VST ; un effet en AU d'abord.
    public static IReadOnlyList<string> PreferredFormats(bool effect) =>
        effect ? new[] { "au", "vst3", "vst", "clap", "fl" } : new[] { "vst3", "vst", "au", "clap", "fl" };

    /// Le .fst du plugin `name` dans la base (`root` : …\Presets\Plugin database), au format préféré ; null : absent.
    public static string? PresetFile(string root, string name, bool effect)
    {
        var wanted = MenuText.Normalized(name);
        if (wanted.Length == 0) return null;
        var kind = Path.Combine(root, "Installed", effect ? "Effects" : "Generators");
        IEnumerable<string> folders;
        try { folders = Directory.Exists(kind) ? Directory.EnumerateDirectories(kind).ToList() : new List<string>(); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return null; }
        var prefer = PreferredFormats(effect);
        int Rank(string folder)
        {
            var i = Array.IndexOf(prefer.ToArray(), FormatKey(Path.GetFileName(folder)));
            return i < 0 ? prefer.Count : i;
        }
        foreach (var folder in folders.OrderBy(Rank).ThenBy(f => f, StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                var file = Directory.EnumerateFiles(folder, "*.fst")
                    .Where(f => new FileInfo(f).LinkTarget is null)
                    .FirstOrDefault(f => MenuText.Normalized(Path.GetFileNameWithoutExtension(f)) == wanted);
                if (file is not null) return file;
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
        return null;
    }

    /// Un nom de son qu'on peut lire : 2 à 40 caractères, au moins une lettre.
    private static bool Usable(string text)
    {
        var t = text.Trim();
        return t.Length is >= 2 and <= 40 && t.Any(char.IsLetter) && !t.Contains(':');
    }

    /// Point où déposer dans le Channel rack, toujours dans l'espace entre deux lignes (jamais SUR un son : il le
    /// remplacerait) : juste sous le dernier son ; Channel rack coupé (dernier nom lu à moitié, ou dernier son au ras de
    /// `bottom`, le bas de la fenêtre) : juste au-dessus du premier (vidéo du 04/11 : « ça fonctionne tout autant »).
    /// D'après les textes lus dans la fenêtre de FL : la colonne des noms sous le titre « Channel rack », à pas
    /// réguliers (un nom illisible laisse un trou d'une ligne). null : titre absent, moins de deux noms, pas réguliers.
    public static (int X, int Y)? ChannelRackPoint(IReadOnlyList<TextItem> items, int? bottom = null)
    {
        var titleKey = MenuText.Normalized("Channel rack");
        foreach (var title in items.Where(t => MenuText.Normalized(t.Text) == titleKey).OrderBy(t => t.Y))
        {
            var top = title.Y + title.Height;
            var below = items.Where(t => t.Y > top + 2 && t.Y < top + 1500 && t.X > title.X - 40 && t.X < title.X + 520
                                         && t.Height is >= 6 and <= 40 && t.Width <= 220 && Usable(t.Text))
                             .OrderBy(t => t.X).ToList();
            // Colonnes : même bord gauche à 8 points près ; une ligne par son (une ligne lue et ses mots : un seul).
            var columns = new List<List<TextItem>>();
            foreach (var t in below)
            {
                var column = columns.FirstOrDefault(c => Math.Abs(c[0].X - t.X) <= 8);
                if (column is null) columns.Add(new List<TextItem> { t });
                else if (column.All(o => Math.Abs(o.CenterY - t.CenterY) > 4)) column.Add(t);
            }
            foreach (var column in columns.OrderByDescending(c => c.Count))
            {
                if (column.Count < 2) break;
                // Dernier nom lu à moitié (coupé par le bas du Channel rack) : pas compté dans les lignes.
                var height = column.Select(t => t.Height).OrderBy(h => h).ElementAt(column.Count / 2);
                var lastRead = column.OrderBy(t => t.CenterY).Last();
                var halfRead = lastRead.Height < height * 0.75;
                var rows = halfRead ? column.Where(t => !t.Equals(lastRead)).ToList() : column;
                if (rows.Count < 2) continue;
                var ys = rows.Select(t => t.CenterY).OrderBy(y => y).ToList();
                if (ys[0] - top > 110) continue;                         // les sons commencent juste sous le titre
                var diffs = ys.Zip(ys.Skip(1), (a, b) => b - a).ToList();
                var step = diffs.Min();
                if (step is < 12 or > 60) continue;
                if (diffs.Any(d => Math.Abs(d / (double)step - Math.Round(d / (double)step)) > 0.25 || d / (double)step > 6.5)) continue;
                var x = rows.Select(t => t.CenterX).OrderBy(v => v).ElementAt(rows.Count / 2);
                var cut = halfRead || (bottom is { } b && ys[^1] + step > b - 8);
                return cut ? (x, ys[0] - step / 2) : (x, ys[^1] + step / 2);
            }
        }
        return null;
    }
}
