// Surveillant du lien avec FL (08/11, « FL rame… il faudrait un capteur… le MIDI ne doit pas rester activé ») : miroir
// de LinkWatch (MIDILink.swift). En mode léger, tant que les ports du lien sont ouverts, chaque seconde : quelqu'un
// s'en sert-il vraiment ? (un bloc de macro en cours ou juste fini, l'Organiser entre « Démarrer » et la fin du
// rangement). Sinon le lien est rendu, et le journal le dit (ligne MIDI « watchdog »).
namespace FLShortcut.Core;

/// Qui a besoin du lien en mode léger.
public enum LinkUser { Organizer, Macro }

public static class LinkWatch
{
    /// Macro : lien gardé ce temps après son dernier bloc qui s'en est servi (les blocs suivants ne le rouvrent pas).
    public const double MacroLinger = 3;
    /// Organiser fermé ou rangement fini : le temps de remettre FL comme avant par le lien.
    public const double OrganizerGrace = 4;

    public sealed record Verdict(IReadOnlyList<LinkUser> Release, bool CloseNow, bool OrganizerGone);

    /// - macro : aucun bloc en cours et le dernier fini depuis plus de `MacroLinger` + 2 s ;
    /// - Organiser : il ne tient plus le lien depuis `OrganizerGrace` s ;
    /// - personne : ports fermés tout de suite.
    public static Verdict Decide(IReadOnlyCollection<LinkUser> holders, int activeBorrows, double sinceLastBorrow,
        bool organizerHolds, double? organizerGoneFor)
    {
        var release = new List<LinkUser>();
        if (holders.Contains(LinkUser.Macro) && activeBorrows == 0 && sinceLastBorrow > MacroLinger + 2)
            release.Add(LinkUser.Macro);
        var gone = holders.Contains(LinkUser.Organizer) && !organizerHolds;
        if (gone && organizerGoneFor is { } g && g >= OrganizerGrace) release.Add(LinkUser.Organizer);
        return new Verdict(release, holders.Count == 0 && activeBorrows == 0, gone);
    }
}
