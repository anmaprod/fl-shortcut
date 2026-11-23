// Guide de FL Shortcuts, le même que le Mac (Guide.swift, demande du 10/11 : « la page de guide après l'installation,
// le même que sur Mac… adapter les touches ou les autres choses qui diffèrent ») : « Bienvenue », une ligne par partie,
// puis une page par partie en trois étapes d'une ligne. Mêmes textes que le Mac ; seules la touche de l'Organiser
// (Ctrl+Alt+O) et la partie « Au quotidien » parlent de Windows (le logo de la barre des tâches, Ctrl+Alt+Maj+F, le menu qui dit ce qui cloche : pas d'autorisation
// du clavier à donner ici). Pur : la fenêtre du guide (GuideView de l'appli) ne fait que dessiner ceci.
namespace FLShortcut.Core;

/// Une partie du guide : son numéro (1…), son titre, ses trois étapes d'une ligne.
public sealed record GuidePage(int Id, string Title, IReadOnlyList<string> Steps);

public static class GuideContent
{
    /// Les cinq parties, dans l'ordre du Mac (23/11 : Trouver, l'Organiser et sa touche, « Partager »).
    public static IReadOnlyList<GuidePage> Pages => new[]
    {
        new GuidePage(1, Loc.T("Tes raccourcis"), new[]
        {
            Loc.T("Dans Trouver, appuie sur une touche."),
            Loc.T("Clique Changer, puis tape la nouvelle."),
            Loc.T("« Remettre » remet celle de FL."),
        }),
        new GuidePage(2, Loc.T("Les macros"), new[]
        {
            Loc.T("Clique « Nouvelle macro »."),
            Loc.T("Ajoute ses étapes à droite."),
            Loc.T("Donne-lui une touche."),
        }),
        new GuidePage(3, Loc.T("Organiser"), new[]
        {
            Loc.T("Ouvre ton projet dans FL."),
            Loc.T("Appuie sur Ctrl+Alt+O dans FL."),
            Loc.T("Garde la version rangée, ou reviens."),
        }),
        new GuidePage(4, Loc.T("La Communauté"), new[]
        {
            Loc.T("Crée ton compte."),
            Loc.T("Ajoute les macros des autres."),
            Loc.T("« Partager » envoie les tiennes."),
        }),
        new GuidePage(5, Loc.T("Au quotidien"), new[]
        {
            Loc.T("Le logo dans la barre des tâches ouvre le menu."),
            Loc.T("Ctrl+Alt+Maj+F met en pause ou reprend."),
            Loc.T("Un souci ? Le menu de l'icône le dit."),
        }),
    };

    /// « Bienvenue », puis une page par partie.
    public static int Count => Pages.Count + 1;

    /// Une page demandée, ramenée entre « Bienvenue » (0) et la dernière partie.
    public static int Clamp(int page) => Math.Max(0, Math.Min(page, Count - 1));

    public static bool IsLast(int page) => page >= Count - 1;

    /// La partie d'une page (1…), ou null sur « Bienvenue ».
    public static GuidePage? Part(int page) => page > 0 ? Pages[Math.Min(page, Pages.Count) - 1] : null;

    /// Le bouton principal : « Découvrir » sur « Bienvenue », « C'est parti » à la fin, « Suivant » entre les deux.
    public static string NextTitle(int page) =>
        page <= 0 ? Loc.T("Découvrir") : IsLast(page) ? Loc.T("C'est parti") : Loc.T("Suivant");
}
