// Audit : WIN-03 / SEC-05 (liste noire NON contournable des cibles « Touche de FL » : Alt+F4, Alt+Tab,
//         Alt+Échap, Ctrl+Échap, Ctrl+Maj+Échap, Win+…, Ctrl+Alt+… ; appliquée à l'édition, à l'import, au
//         chargement ET juste avant chaque injection), audit 05 §5-6 (conflits Windows et FL, AltGr).
namespace FLShortcut.Core;

public static class ForbiddenTargets
{
    /// Raison du refus, ou null si la cible est autorisée.
    public static string? Reason(KeyCombo c)
    {
        if (c.Win) return Loc.T("Win+… est réservé à Windows");
        if (c.Ctrl && c.Alt) return Loc.T("Ctrl+Alt est réservé à AltGr");
        if (c.Alt && c.Vk == Vk.F(4)) return Loc.T("Alt+F4 ferme l'application");
        if (c.Alt && c.Vk == Vk.Tab) return Loc.T("Alt+Tab change d'application");
        if (c.Alt && c.Vk == Vk.Escape) return Loc.T("Alt+Échap change d'application");
        if (c.Ctrl && c.Vk == Vk.Escape) return c.Shift ? Loc.T("Ctrl+Maj+Échap ouvre le Gestionnaire des tâches") : Loc.T("Ctrl+Échap ouvre le menu Démarrer");
        if (c.Vk is Vk.LWin or Vk.RWin or Vk.Apps) return Loc.T("Touche système");
        if (c.Vk == Vk.Snapshot) return Loc.T("Capture d'écran système");
        return null;
    }

    public static bool IsForbidden(KeyCombo c) => Reason(c) is not null;
}

/// Raccourcis déjà pris par Windows ou par FL Studio (avertissements seulement). Textes traduits à l'affichage
/// (ShortcutIssue.Message) : leur anglais est dans en-windows.strings, vérifié par les essais.
public sealed class ConflictTable
{
    public IReadOnlyDictionary<KeyCombo, string> Windows { get; }
    public IReadOnlyDictionary<KeyCombo, string> Fl { get; }

    private ConflictTable(Dictionary<KeyCombo, string> win, Dictionary<KeyCombo, string> fl)
    {
        Windows = win;
        Fl = fl;
    }

    public string? WindowsConflict(KeyCombo c) => Windows.TryGetValue(c, out var s) ? s : null;
    public string? FlConflict(KeyCombo c) => Fl.TryGetValue(c, out var s) ? s : null;

    public static ConflictTable Default { get; } = Build();

    private static ConflictTable Build()
    {
        static KeyCombo Ctrl(char ch, bool shift = false) => new(Vk.Letter(ch), Ctrl: true, Shift: shift);

        var win = new Dictionary<KeyCombo, string>
        {
            [new KeyCombo(Vk.Shift, Ctrl: true)] = "Windows : changer de disposition de clavier",
            [new KeyCombo(Vk.Space, Ctrl: true)] = "Windows : basculer la méthode de saisie",
            [new KeyCombo(Vk.Space, Alt: true)] = "Windows : menu de la fenêtre",
            [new KeyCombo(Vk.F(4), Alt: true)] = "Windows : fermer l'application",
            [new KeyCombo(Vk.Tab, Alt: true)] = "Windows : changer d'application",
            [new KeyCombo(Vk.Escape, Ctrl: true)] = "Windows : menu Démarrer",
            [new KeyCombo(Vk.Escape, Ctrl: true, Shift: true)] = "Windows : Gestionnaire des tâches",
            [new KeyCombo(Vk.Letter('S'), Shift: true, Win: true)] = "Windows : outil Capture",
        };
        // Ctrl+Maj+chiffre peut être attribué à une disposition (Paramètres › Saisie) : on le signale si la
        // configuration de l'utilisateur l'active (rempli par l'appli au démarrage), pas par défaut.

        var fl = new Dictionary<KeyCombo, string>
        {
            [new KeyCombo(Vk.Space)] = "FL : lecture / stop",
            [new KeyCombo(Vk.F(5))] = "FL : Playlist",
            [new KeyCombo(Vk.F(6))] = "FL : Channel Rack",
            [new KeyCombo(Vk.F(7))] = "FL : Piano Roll",
            [new KeyCombo(Vk.F(8))] = "FL : Plugin picker",
            [new KeyCombo(Vk.F(9))] = "FL : Mixer",
            [Ctrl('S')] = "FL : enregistrer le projet",
            [Ctrl('S', shift: true)] = "FL : enregistrer sous",
            [Ctrl('Z')] = "FL : annuler",
            [Ctrl('O')] = "FL : ouvrir un projet",
            [Ctrl('N')] = "FL : nouveau projet",
            [Ctrl('R')] = "FL : exporter en WAV",
            [Ctrl('M', shift: true)] = "FL : exporter en MIDI",
            [Ctrl('T')] = "FL : clavier-piano",
            [Ctrl('Q')] = "FL : quantize rapide",
            [Ctrl('L')] = "FL : lier au Mixer",
            [Ctrl('C')] = "FL : copier",
            [Ctrl('V')] = "FL : coller",
            [Ctrl('X')] = "FL : couper",
            [new KeyCombo(Vk.Letter('M'), Alt: true)] = "FL : mute des clips",
            [new KeyCombo(Vk.Letter('Z'), Ctrl: true, Alt: true)] = "FL : rétablir",
        };
        foreach (var (ch, label) in new (char, string)[]
                 {
                     ('L', "FL : bascule Pattern / Song"), ('R', "FL : enregistrement"), ('P', "FL : outil crayon"),
                     ('B', "FL : outil pinceau"), ('D', "FL : outil suppression"), ('T', "FL : outil mute"),
                     ('S', "FL : outil slip / solo du Mixer"), ('C', "FL : outil découpe"), ('E', "FL : outil sélection"),
                     ('Z', "FL : outil zoom"), ('Y', "FL : outil lecture"),
                 })
        {
            fl[new KeyCombo(Vk.Letter(ch))] = label;
        }
        return new ConflictTable(win, fl);
    }
}
