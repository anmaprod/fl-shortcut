// Touches seules (sans Ctrl, Alt ni Win) : elles lancent leur raccourci, SAUF quand FL s'en sert à ce moment-là (09/11,
// « que ça soit encore utilisable pour écrire dans FL, car sur Mac on n'a pas ce problème ») : miroir de TypingGuard du
// Mac (Sources/FLShortcut/TypingGuard.swift).
// - Menu de FL ouvert (petite fenêtre surgissante devant FL) : ses lettres choisissent un élément.
// - Boîte de FL tout devant (renommer, taper une valeur, recherche…) : boîte de dialogue, ou petite fenêtre devant la
//   fenêtre principale (moins d'un sixième de sa surface).
// - Champ de texte qui a la main dans FL (curseur de saisie de Windows).
// Évalué seulement quand une touche seule lance un raccourci (KeyboardHook), jamais au repos ; fenêtres et curseur de
// saisie seulement : jamais l'écran, jamais le texte tapé. Pur, testé.
using FLShortcut.Core.Macros;

namespace FLShortcut.Core;

public static class TypingGuardRules
{
    public enum Reason { Menu, Dialog, TextField }

    /// `windows` : fenêtres visibles de FL, de la plus en avant à la plus en arrière ; `caret` : un curseur de saisie
    /// est posé dans FL.
    public static Reason? Decide(IReadOnlyList<FlWin> windows, bool caret)
    {
        var main = windows.FirstOrDefault(w => w.Role == FlWindowRole.Main);
        static long Area(FlWin w) => (long)w.Width * w.Height;
        var mainArea = main.Id != 0 ? Area(main) : 0;
        // Un menu : petit (moins d'un tiers de la fenêtre principale), jamais une grande fenêtre détachée de FL.
        if (windows.Any(w => w.Role == FlWindowRole.Menu && (mainArea == 0 || Area(w) < mainArea / 3))) return Reason.Menu;
        var front = windows.FirstOrDefault(w => w.Role != FlWindowRole.Other);
        if (front.Id != 0 && front.Role != FlWindowRole.Main)
        {
            if (front.Role == FlWindowRole.Dialog) return Reason.Dialog;
            if (mainArea > 0 && Area(front) < mainArea / 6) return Reason.Dialog;
        }
        return caret ? Reason.TextField : null;
    }
}
