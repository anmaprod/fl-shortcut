// Raccourcis d'origine de FL Studio, rangés par fenêtre de FL : copie de Sources/FLShortcut/Catalog.swift (même
// identifiant, même titre, même touche en notation du Mac), écrite par un script. Sur Windows, la touche envoyée vient
// de MacKeys (⌘ → Ctrl, ⌥ → Alt). Les identifiants « fl.<page>.<touche> » sont ceux des macros (« Cliquer sur… »).
using FLShortcut.Core.Macros;

namespace FLShortcut.Core;

public enum FlSection { General, Transport, Patterns, Playlist, PianoRoll, ChannelRack, Mixer, Browser }

public static class FlSections
{
    public static string Raw(this FlSection s) => s switch
    {
        FlSection.General => "general",
        FlSection.Transport => "transport",
        FlSection.Patterns => "patterns",
        FlSection.Playlist => "playlist",
        FlSection.PianoRoll => "pianoRoll",
        FlSection.ChannelRack => "channelRack",
        FlSection.Mixer => "mixer",
        FlSection.Browser => "browser",
        _ => "general",
    };

    public static string Title(this FlSection s) => s switch
    {
        FlSection.General => Loc.T("Général"),
        FlSection.Transport => Loc.T("Lecture et enregistrement"),
        FlSection.Patterns => Loc.T("Patterns"),
        FlSection.Playlist => Loc.T("Playlist"),
        FlSection.PianoRoll => Loc.T("Piano Roll"),
        FlSection.ChannelRack => Loc.T("Channel Rack"),
        FlSection.Mixer => Loc.T("Mixer"),
        FlSection.Browser => Loc.T("Browser"),
        _ => "",
    };
}

/// Un raccourci d'origine de FL : sa touche, en notation du Mac (`Key`), et celle de Windows (`Combo`).
public sealed record FlNativeShortcut(string Id, FlSection Section, string TitleKey, KeyRef Key)
{
    public string Title => Loc.T(TitleKey);
    /// La touche sur Windows ; null : sans équivalent.
    public KeyCombo? Combo => MacKeys.ToWindows(Key);
}

public static class FlCatalog
{
    /// Lettre (son caractère d'abord, puis sa place sur un clavier QWERTY).
    private static KeyRef Ch(char letter, ushort code, bool cmd = false, bool opt = false, bool ctrl = false, bool shift = false) =>
        new(new MacKey(code, cmd, opt, ctrl, shift), letter.ToString());

    /// Touche physique (chiffres, pavé numérique, F1…F12, flèches…).
    private static KeyRef Kc(ushort code, bool cmd = false, bool opt = false, bool ctrl = false, bool shift = false) =>
        new(new MacKey(code, cmd, opt, ctrl, shift));

    /// Tous les raccourcis d'origine de FL, dans l'ordre d'affichage.
    public static IReadOnlyList<FlNativeShortcut> Native { get; } = Build();

    private static List<FlNativeShortcut> Build()
    {
        var all = new List<FlNativeShortcut>();
        void N(FlSection s, string id, string title, KeyRef key) => all.Add(new FlNativeShortcut($"fl.{s.Raw()}.{id}", s, title, key));
        // Général
        N(FlSection.General, "cmd-z", "Annuler / rétablir la dernière modification", Ch('z', 6, cmd: true));
        N(FlSection.General, "cmd-opt-z", "Annuler pas à pas", Ch('z', 6, cmd: true, opt: true));
        N(FlSection.General, "cmd-s", "Enregistrer le projet", Ch('s', 1, cmd: true));
        N(FlSection.General, "cmd-shift-s", "Enregistrer sous", Ch('s', 1, cmd: true, shift: true));
        N(FlSection.General, "cmd-n", "Enregistrer une nouvelle version", Ch('n', 45, cmd: true));
        N(FlSection.General, "cmd-o", "Ouvrir un projet", Ch('o', 31, cmd: true));
        N(FlSection.General, "cmd-r", "Exporter en WAV", Ch('r', 15, cmd: true));
        N(FlSection.General, "cmd-shift-r", "Exporter en MP3", Ch('r', 15, cmd: true, shift: true));
        N(FlSection.General, "cmd-shift-m", "Exporter en MIDI", Ch('m', 46, cmd: true, shift: true));
        N(FlSection.General, "cmd-shift-h", "Réorganiser les fenêtres", Ch('h', 4, cmd: true, shift: true));
        N(FlSection.General, "f5", "Afficher / masquer la Playlist", Kc(96));
        N(FlSection.General, "f6", "Afficher / masquer le Channel Rack", Kc(97));
        N(FlSection.General, "f7", "Afficher / masquer le Piano Roll", Kc(98));
        N(FlSection.General, "f8", "Ouvrir le Plugin Picker", Kc(100));
        N(FlSection.General, "f9", "Afficher / masquer le Mixer", Kc(101));
        N(FlSection.General, "opt-f8", "Afficher / masquer le Browser", Kc(100, opt: true));
        N(FlSection.General, "f10", "Réglages MIDI", Kc(109));
        N(FlSection.General, "f11", "Infos du morceau", Kc(103));
        N(FlSection.General, "f12", "Fermer toutes les fenêtres", Kc(111));
        N(FlSection.General, "f1", "Aide", Kc(122));
        N(FlSection.General, "f3", "Choisir un outil de la fenêtre active", Kc(99));
        N(FlSection.General, "tab", "Passer d'une fenêtre à l'autre", Kc(48));
        N(FlSection.General, "esc", "Fermer la fenêtre", Kc(53));
        N(FlSection.General, "return", "Agrandir / réduire la Playlist", Kc(36));
        N(FlSection.General, "opt-0", "Ouvrir le projet récent 0", Kc(29, opt: true));
        N(FlSection.General, "opt-1", "Ouvrir le projet récent 1", Kc(18, opt: true));
        N(FlSection.General, "opt-2", "Ouvrir le projet récent 2", Kc(19, opt: true));
        N(FlSection.General, "opt-3", "Ouvrir le projet récent 3", Kc(20, opt: true));
        N(FlSection.General, "opt-4", "Ouvrir le projet récent 4", Kc(21, opt: true));
        N(FlSection.General, "opt-5", "Ouvrir le projet récent 5", Kc(23, opt: true));
        N(FlSection.General, "opt-6", "Ouvrir le projet récent 6", Kc(22, opt: true));
        N(FlSection.General, "opt-7", "Ouvrir le projet récent 7", Kc(26, opt: true));
        N(FlSection.General, "opt-8", "Ouvrir le projet récent 8", Kc(28, opt: true));
        N(FlSection.General, "opt-9", "Ouvrir le projet récent 9", Kc(25, opt: true));
        // Lecture et enregistrement
        N(FlSection.Transport, "space", "Lecture / Stop", Kc(49));
        N(FlSection.Transport, "cmd-space", "Lecture / Pause", Kc(49, cmd: true));
        N(FlSection.Transport, "r", "Activer / couper l'enregistrement", Ch('r', 15));
        N(FlSection.Transport, "l", "Bascule Pattern / Song", Ch('l', 37));
        N(FlSection.Transport, "cmd-m", "Métronome", Ch('m', 46, cmd: true));
        N(FlSection.Transport, "cmd-p", "Décompte avant l'enregistrement", Ch('p', 35, cmd: true));
        N(FlSection.Transport, "cmd-i", "Attendre une note pour lancer l'enregistrement", Ch('i', 34, cmd: true));
        N(FlSection.Transport, "cmd-b", "Mélanger les notes enregistrées (blend)", Ch('b', 11, cmd: true));
        N(FlSection.Transport, "cmd-e", "Mode Step Edit", Ch('e', 14, cmd: true));
        N(FlSection.Transport, "cmd-h", "Couper tous les sons (panique)", Ch('h', 4, cmd: true));
        N(FlSection.Transport, "cmd-t", "Clavier d'ordinateur → clavier-piano", Ch('t', 17, cmd: true));
        N(FlSection.Transport, "bksp", "Magnétisme : Ligne / Aucun", Kc(51));
        N(FlSection.Transport, "np0", "Avance rapide", Kc(82));
        N(FlSection.Transport, "npmul", "Mesure suivante (mode Song)", Kc(67));
        N(FlSection.Transport, "npdiv", "Mesure précédente (mode Song)", Kc(75));
        N(FlSection.Transport, "opt-np2", "Clavier-piano : octave 2", Kc(84, opt: true));
        N(FlSection.Transport, "opt-np3", "Clavier-piano : octave 3", Kc(85, opt: true));
        N(FlSection.Transport, "opt-np4", "Clavier-piano : octave 4", Kc(86, opt: true));
        N(FlSection.Transport, "opt-np5", "Clavier-piano : octave 5", Kc(87, opt: true));
        N(FlSection.Transport, "opt-np6", "Clavier-piano : octave 6", Kc(88, opt: true));
        // Patterns
        N(FlSection.Patterns, "np1", "Choisir le pattern 1", Kc(83));
        N(FlSection.Patterns, "np2", "Choisir le pattern 2", Kc(84));
        N(FlSection.Patterns, "np3", "Choisir le pattern 3", Kc(85));
        N(FlSection.Patterns, "np4", "Choisir le pattern 4", Kc(86));
        N(FlSection.Patterns, "np5", "Choisir le pattern 5", Kc(87));
        N(FlSection.Patterns, "np6", "Choisir le pattern 6", Kc(88));
        N(FlSection.Patterns, "np7", "Choisir le pattern 7", Kc(89));
        N(FlSection.Patterns, "np8", "Choisir le pattern 8", Kc(91));
        N(FlSection.Patterns, "np9", "Choisir le pattern 9", Kc(92));
        N(FlSection.Patterns, "npplus", "Pattern suivant", Kc(69));
        N(FlSection.Patterns, "npminus", "Pattern précédent", Kc(78));
        N(FlSection.Patterns, "cmd-f4", "Pattern vide suivant", Kc(118, cmd: true));
        N(FlSection.Patterns, "f4", "Pattern vide suivant, avec son nom", Kc(118));
        N(FlSection.Patterns, "f2", "Renommer le pattern (et changer sa couleur)", Kc(120));
        // Playlist
        N(FlSection.Playlist, "p", "Outil crayon", Ch('p', 35));
        N(FlSection.Playlist, "b", "Outil pinceau", Ch('b', 11));
        N(FlSection.Playlist, "d", "Outil suppression", Ch('d', 2));
        N(FlSection.Playlist, "t", "Outil mute", Ch('t', 17));
        N(FlSection.Playlist, "s", "Outil slip", Ch('s', 1));
        N(FlSection.Playlist, "c", "Outil découpe", Ch('c', 8));
        N(FlSection.Playlist, "e", "Outil sélection", Ch('e', 14));
        N(FlSection.Playlist, "y", "Outil lecture", Ch('y', 16));
        N(FlSection.Playlist, "z", "Outil zoom", Ch('z', 6));
        N(FlSection.Playlist, "5", "Zoomer sur la sélection", Kc(23));
        N(FlSection.Playlist, "6", "Zoomer sur les Performance Clips", Kc(22));
        N(FlSection.Playlist, "7", "Transposer vers le bas", Kc(26));
        N(FlSection.Playlist, "8", "Transposer vers le haut", Kc(28));
        N(FlSection.Playlist, "9", "Inverser (clips audio)", Kc(25));
        N(FlSection.Playlist, "bksp", "Magnétisme global", Kc(51));
        N(FlSection.Playlist, "del", "Supprimer la source du clip / pattern", Kc(117));
        N(FlSection.Playlist, "home", "Tête de lecture au début", Kc(115));
        N(FlSection.Playlist, "opt-m", "Mettre la sélection en mute", Ch('m', 46, opt: true));
        N(FlSection.Playlist, "opt-shift-m", "Enlever le mute de la sélection", Ch('m', 46, opt: true, shift: true));
        N(FlSection.Playlist, "opt-g", "Dégrouper la sélection", Ch('g', 5, opt: true));
        N(FlSection.Playlist, "opt-p", "Ouvrir le Picker Panel", Ch('p', 35, opt: true));
        N(FlSection.Playlist, "opt-t", "Ajouter un marqueur", Ch('t', 17, opt: true));
        N(FlSection.Playlist, "opt-npmul", "Marqueur suivant", Kc(67, opt: true));
        N(FlSection.Playlist, "opt-npdiv", "Marqueur précédent", Kc(75, opt: true));
        N(FlSection.Playlist, "cmd-a", "Tout sélectionner", Ch('a', 0, cmd: true));
        N(FlSection.Playlist, "cmd-opt-c", "Consolider les clips (depuis le premier)", Ch('c', 8, cmd: true, opt: true));
        N(FlSection.Playlist, "cmd-opt-shift-c", "Consolider les clips (depuis le début)", Ch('c', 8, cmd: true, opt: true, shift: true));
        N(FlSection.Playlist, "cmd-opt-g", "Couleur de la grille", Ch('g', 5, cmd: true, opt: true));
        N(FlSection.Playlist, "cmd-opt-home", "Redimensionner par la gauche", Kc(115, cmd: true, opt: true));
        N(FlSection.Playlist, "cmd-b", "Dupliquer la sélection à droite", Ch('b', 11, cmd: true));
        N(FlSection.Playlist, "cmd-c", "Copier", Ch('c', 8, cmd: true));
        N(FlSection.Playlist, "cmd-d", "Désélectionner", Ch('d', 2, cmd: true));
        N(FlSection.Playlist, "cmd-f8", "Ouvrir le Project Picker", Kc(100, cmd: true));
        N(FlSection.Playlist, "cmd-left", "Sélectionner le temps avant", Kc(123, cmd: true));
        N(FlSection.Playlist, "cmd-right", "Sélectionner le temps après", Kc(124, cmd: true));
        N(FlSection.Playlist, "cmd-p", "Mode Performance", Ch('p', 35, cmd: true));
        N(FlSection.Playlist, "cmd-t", "Ajouter un marqueur de temps", Ch('t', 17, cmd: true));
        N(FlSection.Playlist, "cmd-v", "Coller", Ch('v', 9, cmd: true));
        N(FlSection.Playlist, "cmd-x", "Couper", Ch('x', 7, cmd: true));
        N(FlSection.Playlist, "cmd-return", "Sélectionner le temps autour de la sélection", Kc(36, cmd: true));
        N(FlSection.Playlist, "pgup", "Zoom avant", Kc(116));
        N(FlSection.Playlist, "pgdn", "Zoom arrière", Kc(121));
        N(FlSection.Playlist, "shift-0", "Centrer sur la tête de lecture", Kc(29, shift: true));
        N(FlSection.Playlist, "shift-1", "Zoom horizontal niveau 1", Kc(18, shift: true));
        N(FlSection.Playlist, "shift-2", "Zoom horizontal niveau 2", Kc(19, shift: true));
        N(FlSection.Playlist, "shift-3", "Zoom horizontal niveau 3", Kc(20, shift: true));
        N(FlSection.Playlist, "shift-4", "Tout afficher", Kc(21, shift: true));
        N(FlSection.Playlist, "shift-5", "Zoomer sur la sélection", Kc(23, shift: true));
        N(FlSection.Playlist, "shift-6", "Ajuster à la zone Performance", Kc(22, shift: true));
        N(FlSection.Playlist, "shift-opt-t", "Choisir une signature rythmique", Ch('t', 17, opt: true, shift: true));
        N(FlSection.Playlist, "shift-c", "Sélectionner les clips de même source", Ch('c', 8, shift: true));
        N(FlSection.Playlist, "shift-g", "Grouper les clips", Ch('g', 5, shift: true));
        N(FlSection.Playlist, "shift-i", "Inverser la sélection", Ch('i', 34, shift: true));
        N(FlSection.Playlist, "shift-left", "Déplacer la sélection à gauche", Kc(123, shift: true));
        N(FlSection.Playlist, "shift-right", "Déplacer la sélection à droite", Kc(124, shift: true));
        N(FlSection.Playlist, "shift-up", "Déplacer la sélection vers le haut", Kc(126, shift: true));
        N(FlSection.Playlist, "shift-down", "Déplacer la sélection vers le bas", Kc(125, shift: true));
        N(FlSection.Playlist, "shift-m", "Changer le mode de stretch", Ch('m', 46, shift: true));
        N(FlSection.Playlist, "shift-q", "Quantize rapide du début des clips", Ch('q', 12, shift: true));
        // Piano Roll
        N(FlSection.PianoRoll, "p", "Outil crayon", Ch('p', 35));
        N(FlSection.PianoRoll, "b", "Outil pinceau", Ch('b', 11));
        N(FlSection.PianoRoll, "d", "Outil suppression", Ch('d', 2));
        N(FlSection.PianoRoll, "t", "Outil mute", Ch('t', 17));
        N(FlSection.PianoRoll, "c", "Outil découpe", Ch('c', 8));
        N(FlSection.PianoRoll, "e", "Outil sélection", Ch('e', 14));
        N(FlSection.PianoRoll, "y", "Outil lecture", Ch('y', 16));
        N(FlSection.PianoRoll, "z", "Outil zoom", Ch('z', 6));
        N(FlSection.PianoRoll, "s", "Notes glissées (slide)", Ch('s', 1));
        N(FlSection.PianoRoll, "o", "Portamento", Ch('o', 31));
        N(FlSection.PianoRoll, "f", "Propriété suivante dans la zone d'événements", Ch('f', 3));
        N(FlSection.PianoRoll, "g", "Instrument au-dessus", Ch('g', 5));
        N(FlSection.PianoRoll, "h", "Instrument au-dessus avec des notes", Ch('h', 4));
        N(FlSection.PianoRoll, "j", "Instrument en dessous avec des notes", Ch('j', 38));
        N(FlSection.PianoRoll, "k", "Instrument en dessous", Ch('k', 40));
        N(FlSection.PianoRoll, "m", "Mode d'affichage du clavier", Ch('m', 46));
        N(FlSection.PianoRoll, "bksp", "Magnétisme global", Kc(51));
        N(FlSection.PianoRoll, "del", "Supprimer la sélection", Kc(117));
        N(FlSection.PianoRoll, "pgup", "Zoom avant", Kc(116));
        N(FlSection.PianoRoll, "pgdn", "Zoom arrière", Kc(121));
        N(FlSection.PianoRoll, "opt-a", "Arpégiateur", Ch('a', 0, opt: true));
        N(FlSection.PianoRoll, "opt-left", "Décaler à gauche", Kc(123, opt: true));
        N(FlSection.PianoRoll, "opt-right", "Décaler à droite", Kc(124, opt: true));
        N(FlSection.PianoRoll, "opt-up", "Décaler vers le haut", Kc(126, opt: true));
        N(FlSection.PianoRoll, "opt-down", "Décaler vers le bas", Kc(125, opt: true));
        N(FlSection.PianoRoll, "opt-b", "Aides de notes", Ch('b', 11, opt: true));
        N(FlSection.PianoRoll, "opt-c", "Couleur des notes", Ch('c', 8, opt: true));
        N(FlSection.PianoRoll, "opt-e", "Riff Machine", Ch('e', 14, opt: true));
        N(FlSection.PianoRoll, "opt-f", "Flam", Ch('f', 3, opt: true));
        N(FlSection.PianoRoll, "opt-g", "Dégrouper les notes", Ch('g', 5, opt: true));
        N(FlSection.PianoRoll, "opt-k", "Outil Limit", Ch('k', 40, opt: true));
        N(FlSection.PianoRoll, "opt-l", "Outil Articulate", Ch('l', 37, opt: true));
        N(FlSection.PianoRoll, "opt-m", "Mettre la sélection en mute", Ch('m', 46, opt: true));
        N(FlSection.PianoRoll, "opt-shift-m", "Enlever le mute de la sélection", Ch('m', 46, opt: true, shift: true));
        N(FlSection.PianoRoll, "opt-n", "Vue forme d'onde", Ch('n', 45, opt: true));
        N(FlSection.PianoRoll, "opt-o", "Outil LFO", Ch('o', 31, opt: true));
        N(FlSection.PianoRoll, "opt-q", "Quantize", Ch('q', 12, opt: true));
        N(FlSection.PianoRoll, "opt-r", "Outil Randomize", Ch('r', 15, opt: true));
        N(FlSection.PianoRoll, "opt-s", "Outil Strum", Ch('s', 1, opt: true));
        N(FlSection.PianoRoll, "opt-u", "Outil Chop", Ch('u', 32, opt: true));
        N(FlSection.PianoRoll, "opt-v", "Ghost channels", Ch('v', 9, opt: true));
        N(FlSection.PianoRoll, "opt-w", "Claw Machine", Ch('w', 13, opt: true));
        N(FlSection.PianoRoll, "opt-x", "Scale Levels", Ch('x', 7, opt: true));
        N(FlSection.PianoRoll, "opt-y", "Score Flipper", Ch('y', 16, opt: true));
        N(FlSection.PianoRoll, "cmd-a", "Tout sélectionner", Ch('a', 0, cmd: true));
        N(FlSection.PianoRoll, "cmd-opt-g", "Couleur de la grille", Ch('g', 5, cmd: true, opt: true));
        N(FlSection.PianoRoll, "cmd-opt-home", "Redimensionner par la gauche", Kc(115, cmd: true, opt: true));
        N(FlSection.PianoRoll, "cmd-b", "Dupliquer la sélection à droite", Ch('b', 11, cmd: true));
        N(FlSection.PianoRoll, "cmd-c", "Copier", Ch('c', 8, cmd: true));
        N(FlSection.PianoRoll, "cmd-d", "Désélectionner", Ch('d', 2, cmd: true));
        N(FlSection.PianoRoll, "cmd-g", "Coller les notes entre elles (glue)", Ch('g', 5, cmd: true));
        N(FlSection.PianoRoll, "cmd-i", "Insérer la valeur du contrôleur", Ch('i', 34, cmd: true));
        N(FlSection.PianoRoll, "cmd-l", "Legato rapide", Ch('l', 37, cmd: true));
        N(FlSection.PianoRoll, "cmd-left", "Sélectionner le temps avant", Kc(123, cmd: true));
        N(FlSection.PianoRoll, "cmd-right", "Sélectionner le temps après", Kc(124, cmd: true));
        N(FlSection.PianoRoll, "cmd-m", "Importer un fichier MIDI", Ch('m', 46, cmd: true));
        N(FlSection.PianoRoll, "cmd-opt-q", "Quantize rapide", Ch('q', 12, cmd: true, opt: true));
        N(FlSection.PianoRoll, "cmd-return", "Sélectionner le temps autour de la sélection", Kc(36, cmd: true));
        N(FlSection.PianoRoll, "cmd-u", "Chop rapide", Ch('u', 32, cmd: true));
        N(FlSection.PianoRoll, "cmd-up", "Transposer d'une octave vers le haut", Kc(126, cmd: true));
        N(FlSection.PianoRoll, "cmd-down", "Transposer d'une octave vers le bas", Kc(125, cmd: true));
        N(FlSection.PianoRoll, "cmd-v", "Coller", Ch('v', 9, cmd: true));
        N(FlSection.PianoRoll, "cmd-x", "Couper", Ch('x', 7, cmd: true));
        N(FlSection.PianoRoll, "shift-0", "Centrer sur la tête de lecture", Kc(29, shift: true));
        N(FlSection.PianoRoll, "shift-1", "Zoom horizontal niveau 1", Kc(18, shift: true));
        N(FlSection.PianoRoll, "shift-2", "Zoom horizontal niveau 2", Kc(19, shift: true));
        N(FlSection.PianoRoll, "shift-3", "Zoom horizontal niveau 3", Kc(20, shift: true));
        N(FlSection.PianoRoll, "shift-4", "Tout afficher", Kc(21, shift: true));
        N(FlSection.PianoRoll, "shift-5", "Zoomer sur la sélection", Kc(23, shift: true));
        N(FlSection.PianoRoll, "shift-opt-t", "Choisir une signature rythmique", Ch('t', 17, opt: true, shift: true));
        N(FlSection.PianoRoll, "shift-c", "Sélectionner par couleur", Ch('c', 8, shift: true));
        N(FlSection.PianoRoll, "shift-cmd-v", "Coller depuis le presse-papiers MIDI", Ch('v', 9, cmd: true, shift: true));
        N(FlSection.PianoRoll, "shift-d", "Effacer la longueur des notes", Ch('d', 2, shift: true));
        N(FlSection.PianoRoll, "shift-f", "Parcourir les propriétés de note", Ch('f', 3, shift: true));
        N(FlSection.PianoRoll, "shift-g", "Grouper la sélection", Ch('g', 5, shift: true));
        N(FlSection.PianoRoll, "shift-h", "Instrument suivant avec des notes", Ch('h', 4, shift: true));
        N(FlSection.PianoRoll, "shift-i", "Inverser la sélection", Ch('i', 34, shift: true));
        N(FlSection.PianoRoll, "shift-k", "Instrument suivant", Ch('k', 40, shift: true));
        N(FlSection.PianoRoll, "shift-left", "Déplacer la sélection à gauche", Kc(123, shift: true));
        N(FlSection.PianoRoll, "shift-right", "Déplacer la sélection à droite", Kc(124, shift: true));
        N(FlSection.PianoRoll, "shift-up", "Déplacer la sélection vers le haut", Kc(126, shift: true));
        N(FlSection.PianoRoll, "shift-down", "Déplacer la sélection vers le bas", Kc(125, shift: true));
        N(FlSection.PianoRoll, "shift-m", "Sélectionner des groupes de notes au hasard", Ch('m', 46, shift: true));
        N(FlSection.PianoRoll, "shift-n", "Désactiver l'accord choisi", Ch('n', 45, shift: true));
        N(FlSection.PianoRoll, "shift-r", "Sélection au hasard", Ch('r', 15, shift: true));
        // Channel Rack
        N(FlSection.ChannelRack, "1", "Mute du canal 1", Kc(18));
        N(FlSection.ChannelRack, "2", "Mute du canal 2", Kc(19));
        N(FlSection.ChannelRack, "3", "Mute du canal 3", Kc(20));
        N(FlSection.ChannelRack, "4", "Mute du canal 4", Kc(21));
        N(FlSection.ChannelRack, "5", "Mute du canal 5", Kc(23));
        N(FlSection.ChannelRack, "6", "Mute du canal 6", Kc(22));
        N(FlSection.ChannelRack, "7", "Mute du canal 7", Kc(26));
        N(FlSection.ChannelRack, "8", "Mute du canal 8", Kc(28));
        N(FlSection.ChannelRack, "9", "Mute du canal 9", Kc(25));
        N(FlSection.ChannelRack, "0", "Mute du canal 10", Kc(29));
        N(FlSection.ChannelRack, "cmd-1", "Solo du canal 1", Kc(18, cmd: true));
        N(FlSection.ChannelRack, "cmd-2", "Solo du canal 2", Kc(19, cmd: true));
        N(FlSection.ChannelRack, "cmd-3", "Solo du canal 3", Kc(20, cmd: true));
        N(FlSection.ChannelRack, "cmd-4", "Solo du canal 4", Kc(21, cmd: true));
        N(FlSection.ChannelRack, "cmd-5", "Solo du canal 5", Kc(23, cmd: true));
        N(FlSection.ChannelRack, "cmd-6", "Solo du canal 6", Kc(22, cmd: true));
        N(FlSection.ChannelRack, "cmd-7", "Solo du canal 7", Kc(26, cmd: true));
        N(FlSection.ChannelRack, "cmd-8", "Solo du canal 8", Kc(28, cmd: true));
        N(FlSection.ChannelRack, "cmd-9", "Solo du canal 9", Kc(25, cmd: true));
        N(FlSection.ChannelRack, "cmd-0", "Solo du canal 10", Kc(29, cmd: true));
        N(FlSection.ChannelRack, "down", "Canal en dessous", Kc(125));
        N(FlSection.ChannelRack, "up", "Canal au-dessus", Kc(126));
        N(FlSection.ChannelRack, "pgup", "Groupe de canaux suivant", Kc(116));
        N(FlSection.ChannelRack, "pgdn", "Groupe de canaux précédent", Kc(121));
        N(FlSection.ChannelRack, "opt-c", "Cloner les canaux", Ch('c', 8, opt: true));
        N(FlSection.ChannelRack, "opt-del", "Supprimer les canaux", Kc(117, opt: true));
        N(FlSection.ChannelRack, "opt-down", "Descendre les canaux", Kc(125, opt: true));
        N(FlSection.ChannelRack, "opt-up", "Monter les canaux", Kc(126, opt: true));
        N(FlSection.ChannelRack, "opt-g", "Grouper les canaux", Ch('g', 5, opt: true));
        N(FlSection.ChannelRack, "opt-m", "Afficher les sélecteurs de piste Mixer", Ch('m', 46, opt: true));
        N(FlSection.ChannelRack, "opt-u", "Dézipper les canaux", Ch('u', 32, opt: true));
        N(FlSection.ChannelRack, "opt-z", "Zipper les canaux", Ch('z', 6, opt: true));
        N(FlSection.ChannelRack, "cmd-opt-r", "Re-stretch de tous les clips audio", Ch('r', 15, cmd: true, opt: true));
        N(FlSection.ChannelRack, "cmd-c", "Copier les pas / la partition", Ch('c', 8, cmd: true));
        N(FlSection.ChannelRack, "cmd-l", "Envoyer vers des pistes Mixer libres", Ch('l', 37, cmd: true));
        N(FlSection.ChannelRack, "cmd-v", "Coller les pas / la partition", Ch('v', 9, cmd: true));
        N(FlSection.ChannelRack, "cmd-x", "Couper les pas / la partition", Ch('x', 7, cmd: true));
        N(FlSection.ChannelRack, "cmd-return", "Aller à la Playlist", Kc(36, cmd: true));
        N(FlSection.ChannelRack, "shift-cmd-left", "Décaler les pas à gauche", Kc(123, cmd: true, shift: true));
        N(FlSection.ChannelRack, "shift-cmd-right", "Décaler les pas à droite", Kc(124, cmd: true, shift: true));
        N(FlSection.ChannelRack, "shift-down", "Étendre la sélection vers le bas", Kc(125, shift: true));
        N(FlSection.ChannelRack, "shift-up", "Étendre la sélection vers le haut", Kc(126, shift: true));
        // Mixer
        N(FlSection.Mixer, "s", "Solo de la piste", Ch('s', 1));
        N(FlSection.Mixer, "opt-l", "Sélectionner les canaux liés à la piste", Ch('l', 37, opt: true));
        N(FlSection.Mixer, "opt-left", "Déplacer la piste à gauche", Kc(123, opt: true));
        N(FlSection.Mixer, "opt-right", "Déplacer la piste à droite", Kc(124, opt: true));
        N(FlSection.Mixer, "opt-r", "Rendu des pistes armées en .wav", Ch('r', 15, opt: true));
        N(FlSection.Mixer, "opt-s", "Solo avec les pistes reliées", Ch('s', 1, opt: true));
        N(FlSection.Mixer, "opt-w", "Vue « Wave » des vumètres", Ch('w', 13, opt: true));
        N(FlSection.Mixer, "cmd-a", "Sélectionner toutes les pistes", Ch('a', 0, cmd: true));
        N(FlSection.Mixer, "cmd-l", "Lier les canaux à la piste", Ch('l', 37, cmd: true));
        N(FlSection.Mixer, "cmd-shift-s", "Enregistrer l'état de la piste", Ch('s', 1, cmd: true, shift: true));
        N(FlSection.Mixer, "ctrl-return", "Propriétés de la piste", Kc(36, ctrl: true));
        N(FlSection.Mixer, "f2", "Renommer la piste", Kc(120));
        N(FlSection.Mixer, "shift-cmd-l", "Lier les canaux à partir de cette piste", Ch('l', 37, cmd: true, shift: true));
        // Browser
        N(FlSection.Browser, "return", "Remplacer le canal par l'élément choisi", Kc(36));
        N(FlSection.Browser, "shift-up", "Élément précédent, avec préécoute", Kc(126, shift: true));
        N(FlSection.Browser, "shift-down", "Élément suivant, avec préécoute", Kc(125, shift: true));
        return all;
    }
}
