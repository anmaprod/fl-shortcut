// Journal de l'appli (étapes des macros et de l'Organiser) : des mots fixes et des nombres seulement, jamais un nom de
// son, de piste ni un texte tapé (règle du propriétaire). L'appli y branche son fichier ; rien par défaut (tests).
namespace FLShortcut.Core;

public static class AppLog
{
    /// Où vont les lignes (« ORGANIZE », « copy open after 3 s »).
    public static Action<string, string>? Sink { get; set; }

    public static void Write(string area, string line) => Sink?.Invoke(area, line);
}
