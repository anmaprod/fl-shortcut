// Les mots d'une étape autour de sa valeur, comme le Mac (StepSentence dans MacroCreatorMinimal.swift ; maquette
// « Minimal » du 20/11 : « Choisir [File › Save] dans le menu ») et la boîte « Ajouter une étape » du créateur
// (Clavier, FL Studio, Souris, Temps ; des verbes : « Appuyer sur une touche »).
namespace FLShortcut.Core.Macros;

public static class StepSentence
{
    /// Avant la valeur, après elle, et ce qui s'affiche en rouge pointillé tant que rien n'est choisi.
    public sealed record Parts(string Pre, string Post, string Placeholder);

    public static Parts For(BlockType? type, string verb) => type switch
    {
        BlockType.Key => new(Loc.T("Appuyer sur"), "", Loc.T("une touche")),
        BlockType.MenuKey => new(Loc.T("Appuyer dans le menu sur"), "", Loc.T("une touche")),
        BlockType.MenuLetters => new(Loc.T("Taper dans le menu"), "", Loc.T("des lettres")),
        BlockType.MenuBar or BlockType.MenuAX => new(Loc.T("Choisir"), Loc.T("dans le menu"), Loc.T("un élément")),
        BlockType.TrackMenu => new(Loc.T("Choisir dans le menu de la piste"), "", Loc.T("un élément")),
        BlockType.OpenPage => new(Loc.T("Ouvrir"), "", Loc.T("une fenêtre")),
        BlockType.PageOption => new(Loc.T("Cliquer sur"), "", Loc.T("un bouton")),
        BlockType.FlAction or BlockType.FlActionValue => new("", "", Loc.T("une action de FL")),
        BlockType.DropFile or BlockType.ChooseFile => new(Loc.T("Ouvrir le preset"), "", Loc.T("un fichier")),
        BlockType.NameColor => new(Loc.T("Renommer la piste en"), "", Loc.T("un nom")),
        BlockType.MouseClick => new(Loc.T("Faire un clic"), "", Loc.T("gauche ou droit")),
        BlockType.Click => new(Loc.T("Cliquer"), "", Loc.T("un endroit")),
        BlockType.Drag => new(Loc.T("Glisser"), "", Loc.T("un endroit")),
        BlockType.Delay or BlockType.WaitWindow or BlockType.WaitWindowClose or BlockType.WaitUntil
            => new(Loc.T("Attendre"), "", Loc.T("une durée")),
        BlockType.Organize => new(Loc.T("Organiser le projet"), "", ""),
        _ => new(verb, "", "…"),
    };

    /// La ligne de « Ajouter une étape ».
    public static string AddLabel(PaletteEntry entry) => entry.Type switch
    {
        BlockType.Key => Loc.T("Appuyer sur une touche"),
        BlockType.MenuKey => Loc.T("Appuyer dans un menu ouvert"),
        BlockType.MenuBar => Loc.T("Choisir dans un menu de FL"),
        BlockType.OpenPage => Loc.T("Ouvrir une fenêtre de FL"),
        BlockType.PageOption => Loc.T("Cliquer sur un bouton de FL"),
        BlockType.FlAction => Loc.T("Faire une action de FL"),
        BlockType.DropFile => Loc.T("Ouvrir un preset"),
        BlockType.NameColor => Loc.T("Renommer la piste"),
        BlockType.Organize => Loc.T("Organiser le projet"),
        BlockType.MouseClick => Loc.T("Faire un clic de souris"),
        BlockType.Click => Loc.T("Cliquer à un endroit appris"),
        BlockType.Drag => Loc.T("Glisser-déposer"),
        BlockType.WaitWindow => Loc.T("Attendre"),
        _ => entry.Label,
    };

    /// Ordre de la maquette : Clavier, FL Studio (menu, fenêtre, bouton, action, preset, nom), Souris, Temps.
    private static readonly BlockType[] Order =
    {
        BlockType.Key, BlockType.MenuKey, BlockType.MenuBar, BlockType.OpenPage, BlockType.PageOption, BlockType.FlAction,
        BlockType.DropFile, BlockType.NameColor, BlockType.Organize, BlockType.MouseClick, BlockType.Click, BlockType.Drag,
        BlockType.WaitWindow,
    };

    public static IReadOnlyList<(string Title, IReadOnlyList<PaletteEntry> Entries)> Groups(
        IEnumerable<(BlockCategory Category, IReadOnlyList<PaletteEntry> Entries)> palette)
    {
        var all = palette.SelectMany(p => p.Entries)
            .OrderBy(e => Array.IndexOf(Order, e.Type) is var i && i >= 0 ? i : Order.Length).ToList();
        var categories = new[]
        {
            (BlockCategory.Keyboard, Loc.T("Clavier")), (BlockCategory.Fl, Loc.T("FL Studio")),
            (BlockCategory.Mouse, Loc.T("Souris")), (BlockCategory.Windows, Loc.T("Temps")),
            (BlockCategory.Control, Loc.T("Contrôle")),
        };
        return categories
            .Select(c => (c.Item2, (IReadOnlyList<PaletteEntry>)all.Where(e => e.Category == c.Item1).ToList()))
            .Where(g => g.Item2.Count > 0)
            .ToList();
    }
}
