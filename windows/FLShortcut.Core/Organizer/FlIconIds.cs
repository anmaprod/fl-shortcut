// Numéro de FL de chaque case de la grille des icônes (« 7-4 » → numéro), relevé par l'Organiser du Mac (ligne
// « icônes connues rack … mixer … » de son diagnostic) : FL n'en publie aucune table (12/11 : forum d'Image-Line, près
// de 500 icônes sans lien avec la grille). Windows ne pose pas encore d'icône par clics : seules les cases d'ici sont
// écrites dans la copie rangée (Channel rack, Mixer, Playlist). Le Mixer a ses propres numéros (12/11 : drums 75 au
// Channel rack, 105 au Mixer). Vides tant qu'aucun diagnostic du Mac ne les a donnés.
namespace FLShortcut.Core.Organizer;

public static class FlIconIds
{
    /// Channel rack et Playlist.
    public static readonly IReadOnlyDictionary<string, uint> Rack = new Dictionary<string, uint>();
    /// Mixer.
    public static readonly IReadOnlyDictionary<string, uint> Mixer = new Dictionary<string, uint>();
}
