// Signataire de FL Studio (audit WIN-04 : FL reconnu à la signature Authenticode d'Image-Line, jamais au titre). Le
// certificat de FL64.exe dit « Image Line » (espace) alors que sa version dit « Image-Line » (tiret) : chercher
// « Image-Line » seul ne reconnaissait jamais FL, et rien ne marchait sous Windows (raccourcis, macros, Organiser ;
// retour d'un ami du propriétaire, 03/11). On compare les seules lettres, sans majuscules.
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
