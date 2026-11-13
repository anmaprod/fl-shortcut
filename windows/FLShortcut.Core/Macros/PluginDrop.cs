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

    /// Le .fst du plugin `name` dans la base (`root` : …\Presets\Plugin database) ; null : absent.
    /// 06/11 (comme le Mac, « il n'y a que pour Analog Lab que ça fonctionne… mets ça pour tout ») : cherché dans TOUTE
    /// la base, sous-dossiers compris : d'abord Installed › Generators ou Effects (format préféré), puis les catégories
    /// de favoris de FL. Le nom : identique, sinon sans la marque ni le format (« FabFilter Pro-Q 3 », « Analog Lab V
    /// (VST3) »), jamais un autre numéro (« Serum » n'ouvre pas « Serum 2 »). Seulement des .fst ; jamais un lien.
    public static string? PresetFile(string root, string name, bool effect)
    {
        var wanted = MenuText.Normalized(name);
        var wantedKey = LooseKey(name);
        if (wanted.Length == 0 || wantedKey.Length == 0) return null;
        var prefer = PreferredFormats(effect);
        var kind = effect ? "Effects" : "Generators";
        (int Level, int Source, int Format, int Gap, string Path)? best = null;
        var bases = new[] { Path.Combine(root, "Installed", kind), Path.Combine(root, kind) };
        for (var source = 0; source < bases.Length; source++)
        {
            foreach (var (file, top) in FstFiles(bases[source], source == 1 ? FavoritesFolderToSkip : null))
            {
                var stem = Path.GetFileNameWithoutExtension(file);
                if (MatchLevel(stem, wanted, wantedKey) is not { } level) continue;
                var at = prefer.ToList().IndexOf(FormatKey(top));
                var format = source == 0 && at >= 0 ? at : prefer.Count;
                var rank = (level, source, format, Math.Abs(LooseKey(stem).Length - wantedKey.Length), file);
                if (best is null || Compare(rank, best.Value) < 0) best = rank;
            }
        }
        return best?.Path;

        static int Compare((int, int, int, int, string) a, (int, int, int, int, string) b)
        {
            var c = a.Item1.CompareTo(b.Item1);
            if (c == 0) c = a.Item2.CompareTo(b.Item2);
            if (c == 0) c = a.Item3.CompareTo(b.Item3);
            if (c == 0) c = a.Item4.CompareTo(b.Item4);
            return c != 0 ? c : string.CompareOrdinal(a.Item5, b.Item5);
        }
    }

    /// Catégorie qu'ajoutaient d'anciennes versions dans les favoris de FL : jamais prise.
    private const string FavoritesFolderToSkip = "FL Shortcuts";

    private static readonly HashSet<string> FormatWords = new(StringComparer.Ordinal)
        { "vst", "vst2", "vst3", "au", "aax", "clap", "x64", "x86", "64bit", "32bit", "aufx", "aumu" };

    /// Le nom en lettres et chiffres seuls, minuscules, sans les mots de format (« vst3 », « au », « x64 »…).
    public static string LooseKey(string name)
    {
        var decomposed = name.Normalize(System.Text.NormalizationForm.FormD);
        var words = new List<string>();
        var current = new System.Text.StringBuilder();
        void Flush()
        {
            if (current.Length > 0 && !FormatWords.Contains(current.ToString())) words.Add(current.ToString());
            current.Clear();
        }
        foreach (var c in decomposed)
        {
            if (System.Globalization.CharUnicodeInfo.GetUnicodeCategory(c) == System.Globalization.UnicodeCategory.NonSpacingMark) continue;
            if (char.IsLetterOrDigit(c)) current.Append(char.ToLowerInvariant(c));
            else Flush();
        }
        Flush();
        return string.Concat(words);
    }

    /// 0 nom identique, 1 identique sans la marque ni le format, 2 contenu l'un dans l'autre sans autre chiffre ;
    /// null : un autre plugin.
    public static int? MatchLevel(string stem, string wanted, string wantedKey)
    {
        if (MenuText.Normalized(stem) == wanted) return 0;
        var key = LooseKey(stem);
        if (key == wantedKey) return 1;
        if (wantedKey.Length < 4 || key.Length < 4) return null;
        var (longer, shorter) = key.Length > wantedKey.Length ? (key, wantedKey) : (wantedKey, key);
        var at = longer.IndexOf(shorter, StringComparison.Ordinal);
        if (at < 0) return null;
        var rest = longer.Remove(at, shorter.Length);
        return rest.Any(char.IsDigit) ? null : 2;
    }

    /// Un nom de son qu'on peut lire : 2 à 40 caractères, au moins une lettre.
    private static bool Usable(string text)
    {
        var t = text.Trim();
        return t.Length is >= 2 and <= 40 && t.Any(char.IsLetter) && !t.Contains(':');
    }

    /// Les .fst sous `folder` (sous-dossiers compris), avec leur premier dossier (le format sous Installed) ; `skip` : un
    /// dossier du premier niveau laissé de côté. 50 000 fichiers et 8 niveaux au plus. Jamais un vrai lien (lien
    /// symbolique, jonction) ; 09/11 : les fichiers d'un Documents synchronisé par OneDrive (réglage par défaut de
    /// Windows) portent aussi une marque de « point d'analyse » : ils étaient sautés, aucun .fst n'était trouvé, et le
    /// plugin passait par les menus de FL au lieu d'être glissé. Ils sont pris maintenant.
    private static List<(string File, string Top)> FstFiles(string folder, string? skip)
    {
        var found = new List<(string, string)>();
        if (!Directory.Exists(folder)) return found;
        var options = new EnumerationOptions { IgnoreInaccessible = true, AttributesToSkip = FileAttributes.Hidden | FileAttributes.System };
        void Walk(string dir, string top, int depth)
        {
            if (found.Count >= 50_000) return;
            try
            {
                foreach (var file in Directory.EnumerateFiles(dir, "*.fst", options))
                {
                    if (found.Count >= 50_000) return;
                    if (IsLink(file)) continue;
                    found.Add((file, top));
                }
                if (depth >= 8) return;
                foreach (var sub in Directory.EnumerateDirectories(dir, "*", options))
                {
                    if (IsLink(sub)) continue;
                    var name = Path.GetFileName(sub);
                    if (depth == 0 && skip is not null && string.Equals(name, skip, StringComparison.OrdinalIgnoreCase)) continue;
                    Walk(sub, depth == 0 ? name : top, depth + 1);
                }
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.SecurityException) { }
        }
        Walk(folder, "", 0);
        return found;
    }

    /// Vrai lien (symbolique ou jonction) : jamais suivi. Un fichier de OneDrive n'en est pas un.
    private static bool IsLink(string path)
    {
        try { return (File.Exists(path) ? new FileInfo(path).LinkTarget : new DirectoryInfo(path).LinkTarget) is not null; }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return true; }
    }

    /// La première case d'effet vide de la piste choisie du Mixer (06/11, comme le Mac, « ça vise la piste qui est
    /// sélectionnée ») : dans le Mixer de FL, les cases libres de la piste choisie s'appellent « Slot 1 »…« Slot 10 » ;
    /// on dépose sur la plus petite. Lecture tolérante (« Slot l », « slot 1 »). null : aucune case libre lue.
    public static (int X, int Y)? MixerSlotPoint(IReadOnlyList<TextItem> items)
    {
        (int Number, int X, int Y)? best = null;
        foreach (var item in items)
        {
            if (SlotNumber(item.Text) is not { } number) continue;
            if (best is null || number < best.Value.Number) best = (number, item.CenterX, item.CenterY);
        }
        return best is { } b ? (b.X, b.Y) : null;
    }

    private static readonly System.Text.RegularExpressions.Regex SlotPattern =
        new(@"s[l1i|]ot\s*[0-9lio|]{1,2}\b", System.Text.RegularExpressions.RegexOptions.CultureInvariant);

    /// Le numéro d'une case libre lue « Slot 3 », même avec la flèche devant (« ▶ Slot 3 ») ou mal lue (« Slot3 »,
    /// « Slot l », « SIot 1 ») ; null : autre chose (07/11, comme le Mac).
    public static int? SlotNumber(string text)
    {
        var match = SlotPattern.Match(text.ToLowerInvariant());
        if (!match.Success) return null;
        var digits = new string(match.Value[4..].Where(c => !char.IsWhiteSpace(c))
            .Select(c => c is 'l' or 'i' or '|' ? '1' : c == 'o' ? '0' : c).ToArray());
        return int.TryParse(digits, System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var n)
               && n is >= 1 and <= 10 ? n : null;
    }

    /// La page est-elle à l'écran ? Son titre lu (« Channel rack », ou « Mixer » / « Mixer - Insert 3 ») : jamais sa
    /// touche quand elle est déjà là, la touche la refermerait.
    public static bool PageShown(bool effect, IReadOnlyList<TextItem> items) => items.Any(item =>
    {
        var t = MenuText.Normalized(item.Text);
        return effect && (t == MenuText.Normalized("Mixer") || t.StartsWith(MenuText.Normalized("Mixer -"), StringComparison.Ordinal));
    }) || (!effect && Titles(items, "Channel rack").Any());

    /// Le titre `title` (« Channel rack ») parmi les textes lus (09/11, Windows) : lu seul, au début d'une ligne plus
    /// longue (« Channel rack All » : la lecture de Windows colle parfois le mot voisin), ou en deux mots voisins sur la
    /// même ligne. Avant, seul le titre lu seul comptait : le plugin n'était pas déposé (menu Add à la place).
    public static IEnumerable<TextItem> Titles(IReadOnlyList<TextItem> items, string title)
    {
        var key = MenuText.Normalized(title);
        if (key.Length == 0) yield break;
        foreach (var t in items)
        {
            var n = MenuText.Normalized(t.Text);
            if (n == key) yield return t;
            else if (n.StartsWith(key + " ", StringComparison.Ordinal))
                yield return t with { Width = Math.Max(1, (int)Math.Round(t.Width * key.Length / (double)n.Length)) };
            // 13/11 : l'icône du haut-parleur de FL lue juste devant (« 4) Channel rack ») : un signe ou deux, pas un mot.
            else if (n.EndsWith(" " + key, StringComparison.Ordinal) && n.Length - key.Length - 1 is > 0 and <= 3
                     && !n[..(n.Length - key.Length - 1)].Any(char.IsWhiteSpace))
            {
                var width = Math.Max(1, (int)Math.Round(t.Width * key.Length / (double)n.Length));
                yield return t with { X = t.X + t.Width - width, Width = width };
            }
        }
        var words = key.Split(' ');
        if (words.Length != 2) yield break;
        foreach (var first in items.Where(t => MenuText.Normalized(t.Text) == words[0]))
        {
            var line = Math.Max(first.Height, 8);
            var second = items.Where(o => MenuText.Normalized(o.Text) == words[1] && Math.Abs(o.CenterY - first.CenterY) < line * 0.6
                                          && o.X >= first.X + first.Width - 2 && o.X - (first.X + first.Width) <= line * 2)
                .OrderBy(o => o.X).Cast<TextItem?>().FirstOrDefault();
            if (second is not { } s) continue;
            var top = Math.Min(first.Y, s.Y);
            yield return new TextItem(title, first.X, top, s.X + s.Width - first.X, Math.Max(first.Y + first.Height, s.Y + s.Height) - top);
        }
    }

    /// Point où déposer dans le Channel rack, toujours dans l'espace entre deux lignes (jamais SUR un son : il le
    /// remplacerait) : juste sous le dernier son ; Channel rack coupé (dernier nom lu à moitié, ou dernier son au ras de
    /// `bottom`, le bas de la fenêtre) : juste au-dessus du premier (vidéo du 04/11 : « ça fonctionne tout autant »).
    /// D'après les textes lus dans la fenêtre de FL : la colonne des noms sous le titre « Channel rack », à pas
    /// réguliers (un nom illisible laisse un trou d'une ligne). null : titre absent, moins de deux noms, pas réguliers.
    public static (int X, int Y)? ChannelRackPoint(IReadOnlyList<TextItem> items, int? bottom = null)
    {
        foreach (var title in Titles(items, "Channel rack").OrderBy(t => t.Y).ToList())
        {
            var top = title.Y + title.Height;
            // Vidéo du 05/11 (FL 2025) : le titre est à ~100 points à droite des noms, centrés dans leur bouton : noms
            // cherchés jusqu'à 240 points à gauche du titre ; colonne = même bord gauche OU même centre ; la plus proche
            // du titre l'emporte à nombre égal.
            var below = items.Where(t => t.Y > top + 2 && t.Y < top + 1500 && t.X > title.X - 240 && t.X < title.X + 520
                                         && t.Height is >= 6 and <= 40 && t.Width <= 220 && Usable(t.Text))
                             .OrderBy(t => t.X).ToList();
            // Colonnes : même bord gauche ou même centre à 8 points près ; une ligne par son.
            var columns = new List<List<TextItem>>();
            foreach (var t in below)
            {
                var column = columns.FirstOrDefault(c => Math.Abs(c[0].X - t.X) <= 8 || Math.Abs(c[0].CenterX - t.CenterX) <= 8);
                if (column is null) columns.Add(new List<TextItem> { t });
                else if (column.All(o => Math.Abs(o.CenterY - t.CenterY) > 4)) column.Add(t);
            }
            foreach (var column in columns.OrderByDescending(c => c.Count).ThenBy(c => Math.Abs(c[0].CenterX - title.CenterX)))
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

/// Quand appuyer sur la touche de la page avant de déposer un plugin (13/11, miroir de `DropPageWait` du Mac). Le bloc
/// d'avant vient souvent d'appuyer sur cette touche : une 2e la refermerait. Donc : la page est lue jusqu'à 1,5 s sans
/// rien toucher ; toujours absente, sa touche une seule fois, puis relue jusqu'à 2,5 s ; titre lu mais aucune place sûre
/// (moins de deux sons lus…) : pas de touche, on arrête après la même attente.
public static class DropPageWait
{
    public enum Step { Read, PressKey, GiveUp }

    public const int PauseMs = 250;
    public const int BeforeKeyMs = 1_500;
    public const int AfterKeyMs = 2_500;

    /// `waited` : depuis le début ; `sinceKey` : depuis la touche (null : pas encore appuyée) ; `seen` : titre déjà lu.
    public static Step Next(int waited, int? sinceKey, bool seen)
    {
        if (sinceKey is { } k) return k < AfterKeyMs ? Step.Read : Step.GiveUp;
        if (waited < BeforeKeyMs) return Step.Read;
        return seen ? Step.GiveUp : Step.PressKey;
    }
}
