// Mode léger (par défaut) : FL Shortcuts ne met RIEN dans FL Studio. Pas de script, pas de port MIDI, pas de loopMIDI.
// Il n'envoie que des touches d'origine de FL, seulement quand FL est au premier plan.
// - Raccourcis d'origine déplacés : ta touche → la touche de FL (FL l'applique à sa fenêtre active).
// - Actions qui ont un équivalent clavier dans FL : ta touche → cette touche de FL.
// - Les autres actions (mute/solo de piste, volume ±0,5 dB, preset suivant…) demandent le script : masquées.
// Miroir de Sources/FLShortcut/LightMode.swift (⌘ du Mac = Ctrl, ⌥ = Alt), sans Ctrl+Alt (AltGr, cibles interdites).
namespace FLShortcut.Core;

public static class LightMode
{
    /// Touche d'origine de FL (Windows) qui fait la même chose que l'action, si elle existe.
    public static KeyCombo? NativeEquivalent(int id)
    {
        static KeyCombo Ctrl(char c) => new(Vk.Letter(c), Ctrl: true);
        return FlActions.Info(id)?.Key switch
        {
            "play" => new KeyCombo(Vk.Space),                  // lecture / stop
            "rec" => new KeyCombo(Vk.Letter('R')),
            "metro" => Ctrl('M'),
            "count" => Ctrl('P'),
            "wait" => Ctrl('I'),
            "pnext" => new KeyCombo(Vk.Add),                   // + du pavé numérique
            "pprev" => new KeyCombo(Vk.Subtract),              // − du pavé numérique
            "quant" => Ctrl('Q'),                              // quantize rapide
            "pl" => new KeyCombo(Vk.F(5)),
            "cr" => new KeyCombo(Vk.F(6)),
            "pr" => new KeyCombo(Vk.F(7)),
            "mx" => new KeyCombo(Vk.F(9)),
            "br" => new KeyCombo(Vk.F(8), Alt: true),          // Alt+F8
            "undo" => Ctrl('Z'),
            "save" => Ctrl('S'),
            _ => null,
        };
    }

    /// Table action → touche de FL (vide si les actions passent par le lien MIDI).
    public static IReadOnlyDictionary<int, KeyCombo> ActionNatives(bool light)
    {
        var map = new Dictionary<int, KeyCombo>();
        if (!light) return map;
        foreach (var info in FlActions.All)
            if (NativeEquivalent(info.Id) is { } k && !ForbiddenTargets.IsForbidden(k)) map[info.Id] = k;
        return map;
    }

    /// Disponibilité d'une action en mode léger : seulement celles qui ont une touche d'origine.
    public static ActionAvailability Availability(int id) =>
        !FlActions.IsKnown(id) ? new ActionAvailability.Unavailable("Action inconnue")
        : NativeEquivalent(id) is not null ? new ActionAvailability.Available()
        : new ActionAvailability.Unavailable("Demande le lien MIDI avec FL (désactivé en mode léger)");
}
