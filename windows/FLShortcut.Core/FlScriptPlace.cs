// Où poser tout seul le script de FL (13/11, comme le Mac : « ça fonctionne mais que si j'installe le lien midi
// d'organiser… installer le lien midi dès l'installation du logiciel ») : le dossier « Settings\Hardware » de FL, à
// toutes les places qu'il peut avoir sous Windows (dossiers de données notés par FL, puis chaque Documents possible,
// avec l'ancienne place « Image-Line\Data\FL Studio »). Pur ; jamais d'exception.
namespace FLShortcut.Core;

public static class FlScriptPlace
{
    /// Les dossiers « Settings\Hardware » possibles, sans doublon, dans cet ordre : ceux des dossiers de données notés
    /// par FL (`flFolders`), puis ceux de chaque dossier Documents (`documents`).
    public static IReadOnlyList<string> Candidates(IEnumerable<string> documents, IEnumerable<string>? flFolders = null)
    {
        var output = new List<string>();
        foreach (var folder in flFolders ?? Array.Empty<string>())
        {
            if (folder.Trim().Length == 0 || !Path.IsPathRooted(folder.Trim())) continue;
            var f = folder.Trim().TrimEnd('\\', '/');
            if (Path.GetFileName(f).Equals("Hardware", StringComparison.OrdinalIgnoreCase)) output.Add(f);
            else
            {
                output.Add(Path.Combine(f, "Settings", "Hardware"));
                output.Add(Path.Combine(f, "FL Studio", "Settings", "Hardware"));
            }
        }
        var docs = documents.Where(d => d.Trim().Length > 0).ToList();
        foreach (var d in docs) output.Add(Path.Combine(d, "Image-Line", "FL Studio", "Settings", "Hardware"));
        foreach (var d in docs) output.Add(Path.Combine(d, "Image-Line", "Data", "FL Studio", "Settings", "Hardware"));
        return output.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    }

    /// Le premier dossier « Hardware » dont le dossier « Settings » existe déjà (FL ouvert au moins une fois) ; null :
    /// FL jamais ouvert, rien n'est créé au hasard.
    public static string? Hardware(IEnumerable<string> candidates, Func<string, bool> directoryExists)
    {
        foreach (var hardware in candidates)
        {
            try
            {
                if (Path.GetDirectoryName(hardware) is { Length: > 0 } settings && directoryExists(settings)) return hardware;
            }
            catch (Exception e) when (e is ArgumentException or PathTooLongException) { }
        }
        return null;
    }
}
