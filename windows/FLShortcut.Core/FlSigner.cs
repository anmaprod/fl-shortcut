// Reconnaissance de FL Studio sous Windows. 03/11 : le certificat de FL64.exe dit « Image Line » (sans tiret).
// 08/11 (« un ami a FL Studio crack… ça ne repère pas FL Studio… que ce soit accessible à tout le monde ») : la
// signature d'Image-Line n'est plus exigée, seulement notée dans le diagnostic ; FL est reconnu à son programme.
namespace FLShortcut.Core;

public static class FlSigner
{
    /// Le sujet du certificat (« CN=Image Line, O=Image Line, L=Gent, C=BE ») est-il celui d'Image-Line ?
    public static bool Matches(string? subject)
    {
        if (string.IsNullOrEmpty(subject)) return false;
        var letters = new string(subject.Where(char.IsLetter).ToArray());
        return letters.Contains("imageline", StringComparison.OrdinalIgnoreCase);
    }
}

/// FL Studio reconnu à son programme, avec ou sans la signature d'Image-Line.
public static class FlRecognition
{
    /// Noms du programme de FL Studio (64 bits, 32 bits, mode « scaled »).
    public static readonly string[] ExeNames = { "FL64.exe", "FL.exe", "FL64 (scaled).exe" };

    /// Pur (testé) : un programme est FL Studio s'il porte l'un de ses noms ; sinon, un programme dont le nom commence
    /// par « FL » et que ses informations de version disent « FL Studio » (copie renommée). Jamais FL Studio Mobile ni
    /// FL Studio Remote (autres applis, sans le script).
    public static bool Accepts(string? fileName, string? productName = null, string? description = null)
    {
        if (string.IsNullOrWhiteSpace(fileName)) return false;
        var file = fileName.Trim();
        if (ExeNames.Any(n => string.Equals(n, file, StringComparison.OrdinalIgnoreCase))) return true;
        if (!file.StartsWith("FL", StringComparison.OrdinalIgnoreCase)
            || !file.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)) return false;
        static bool SaysFlStudio(string? s) =>
            s is not null && s.Contains("FL Studio", StringComparison.OrdinalIgnoreCase)
            && !s.Contains("Mobile", StringComparison.OrdinalIgnoreCase) && !s.Contains("Remote", StringComparison.OrdinalIgnoreCase);
        return SaysFlStudio(productName) || SaysFlStudio(description);
    }

    /// Nom de processus (sans « .exe ») qui vaut la peine d'être regardé de plus près.
    public static bool MaybeFl(string? processName) =>
        processName is not null && processName.StartsWith("FL", StringComparison.OrdinalIgnoreCase);
}
