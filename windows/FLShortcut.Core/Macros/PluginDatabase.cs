// « Cliquer sur… › Ajouter un instrument / un effet » avec la liste de TOUS les plugins installés, comme le Mac (09/11,
// « dans cliquer sur ils n'ont pas de liste comme sur mac… qu'il repère les plugins de la même façon ») : miroir de
// FLPluginDatabase.installed (FLPluginDatabase.swift). FL les connaît dans sa « Plugin database » (dossier de données de
// FL › Presets › Plugin database › Installed › Generators ou Effects) : un fichier par plugin (.fst, .nfo), rangés par
// format (VST, VST3…). Lu seulement, quand la liste est demandée ; rien n'y est JAMAIS écrit (demande du 28/10) : un
// plugin choisi est pris par la macro (son .fst déposé, sinon « More plugins… » du menu Add), sans rien cocher.
namespace FLShortcut.Core.Macros;

public static class PluginDatabase
{
    /// Un plugin installé : son format (dossier : VST, VST3…) et son nom (celui de son fichier).
    public sealed record Plugin(string Format, string Name);

    /// « Plugin database » de FL : à côté du script installé (dossier de données choisi dans FL), puis l'emplacement
    /// par défaut (Documents › Image-Line › FL Studio), comme le Mac.
    public static IReadOnlyList<string> Roots(string? scriptPath, string documents) =>
        Roots(scriptPath, documents.Length > 0 ? new[] { documents } : Array.Empty<string>());

    /// Mêmes dossiers que le Mac (Image-Line › FL Studio › Presets › Plugin database), cherchés à toutes les places
    /// qu'ils peuvent avoir sous Windows (09/11) : à côté du script installé ; les dossiers de données que FL a notés
    /// (`flFolders`, lus par l'appli) ; puis chaque dossier Documents possible (`documents` : celui de Windows, celui du
    /// profil, celui de OneDrive), avec l'ancienne place « Image-Line › Data › FL Studio ». Sans doublon, dans cet
    /// ordre ; la première base qui a des plugins gagne.
    public static IReadOnlyList<string> Roots(string? scriptPath, IEnumerable<string> documents, IEnumerable<string>? flFolders = null)
    {
        var roots = new List<string>();
        try
        {
            // …\FL Studio\Settings\Hardware\FL Shortcuts\device_FLShortcut.py → …\FL Studio
            if (scriptPath is { Length: > 0 } && Directory.GetParent(scriptPath)?.Parent?.Parent?.Parent is { } flStudio)
                roots.Add(Path.Combine(flStudio.FullName, "Presets", "Plugin database"));
        }
        catch (Exception e) when (e is ArgumentException or IOException or UnauthorizedAccessException or System.Security.SecurityException) { }
        foreach (var folder in flFolders ?? Array.Empty<string>())
        {
            if (folder.Trim().Length == 0 || !Path.IsPathRooted(folder)) continue;
            var f = folder.Trim().TrimEnd('\\', '/');
            if (Path.GetFileName(f).Equals("Plugin database", StringComparison.OrdinalIgnoreCase)) roots.Add(f);
            else
            {
                roots.Add(Path.Combine(f, "Presets", "Plugin database"));
                roots.Add(Path.Combine(f, "FL Studio", "Presets", "Plugin database"));
            }
        }
        var docs = documents.Where(d => d.Trim().Length > 0).ToList();
        foreach (var d in docs) roots.Add(Path.Combine(d, "Image-Line", "FL Studio", "Presets", "Plugin database"));
        foreach (var d in docs) roots.Add(Path.Combine(d, "Image-Line", "Data", "FL Studio", "Presets", "Plugin database"));
        return roots.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }

    /// Plugins installés de cette sorte (instruments ou effets), un par nom et par format, triés par format puis par
    /// nom. Vide si la base n'existe pas. Jamais d'exception.
    public static IReadOnlyList<Plugin> Installed(string root, bool effect)
    {
        var baseDir = Path.Combine(root, "Installed", effect ? "Effects" : "Generators");
        var output = new List<Plugin>();
        try
        {
            if (!Directory.Exists(baseDir)) return output;
            foreach (var formatDir in Directory.EnumerateDirectories(baseDir).OrderBy(d => Path.GetFileName(d), StringComparer.OrdinalIgnoreCase))
            {
                var format = Path.GetFileName(formatDir);
                if (format.StartsWith('.') || IsLink(formatDir)) continue;
                var names = new SortedSet<string>(Natural);
                foreach (var file in Directory.EnumerateFiles(formatDir))
                {
                    var ext = Path.GetExtension(file).ToLowerInvariant();
                    var name = Path.GetFileNameWithoutExtension(file);
                    if (ext is not (".fst" or ".nfo") || name.Length == 0 || name.StartsWith('.') || name.Contains('›')) continue;
                    names.Add(name);
                }
                output.AddRange(names.Select(n => new Plugin(format, n)));
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException) { }
        return output;
    }

    /// Tous les plugins de cette sorte trouvés dans ces bases (la première qui en a).
    public static IReadOnlyList<Plugin> Installed(IEnumerable<string> roots, bool effect) =>
        roots.Select(r => Installed(r, effect)).FirstOrDefault(list => list.Count > 0) ?? Array.Empty<Plugin>();

    /// Plugins rangés par format, dans l'ordre (rubriques de la liste).
    public static IReadOnlyList<(string Format, IReadOnlyList<string> Names)> ByFormat(IReadOnlyList<Plugin> plugins)
    {
        var output = new List<(string, IReadOnlyList<string>)>();
        foreach (var group in plugins.GroupBy(p => p.Format)) output.Add((group.Key, group.Select(p => p.Name).ToList()));
        return output;
    }

    private static bool IsLink(string path)
    {
        try { return new DirectoryInfo(path).LinkTarget is not null; }
        catch (IOException) { return true; }
    }

    /// Ordre « naturel » des noms (Serum 2 avant Serum 10), sans tenir compte des majuscules, comme le Finder.
    private static readonly IComparer<string> Natural = Comparer<string>.Create((a, b) =>
    {
        int i = 0, j = 0;
        while (i < a.Length && j < b.Length)
        {
            if (char.IsDigit(a[i]) && char.IsDigit(b[j]))
            {
                var si = i; while (i < a.Length && char.IsDigit(a[i])) i++;
                var sj = j; while (j < b.Length && char.IsDigit(b[j])) j++;
                var na = a[si..i].TrimStart('0'); var nb = b[sj..j].TrimStart('0');
                var c = na.Length != nb.Length ? na.Length.CompareTo(nb.Length) : string.CompareOrdinal(na, nb);
                if (c != 0) return c;
                continue;
            }
            var d = char.ToLowerInvariant(a[i]).CompareTo(char.ToLowerInvariant(b[j]));
            if (d != 0) return d;
            i++; j++;
        }
        var rest = (a.Length - i).CompareTo(b.Length - j);
        return rest != 0 ? rest : string.CompareOrdinal(a, b);
    });
}
