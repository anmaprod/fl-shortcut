// Modèles de macro de la galerie du créateur et choix du « Menu de la piste ». Miroir de
// Sources/FLShortcut/MacroTemplates.swift : les mêmes modèles (les macros du propriétaire), avec des ids neufs à
// chaque copie. Les anciennes macros du Mac (étapes, « Enregistrement rapide » en ligne) n'existent pas sur Windows.
namespace FLShortcut.Core.Macros;

/// Un élément du menu de la piste : nom affiché dans la liste, titres de FL (ligne du bloc), lettres soulignées.
public sealed record TrackMenuChoice(string Id, string Name, IReadOnlyList<string> Labels, string Letters, EnterPolicy Enter);

/// Un modèle de la galerie : une macro en blocs prête à modifier.
public sealed record MacroTemplate(string Id, string Title, string Summary, string Symbol, Func<MacroDoc> Make);

public static class MacroTemplates
{
    /// Éléments du menu de la piste qu'on choisit dans une liste (bloc « Menu de la piste ») : lettres soulignées du
    /// menu de FL 2026 (les mêmes que le Mac). « Autre » garde les lettres tapées à la main.
    public static IReadOnlyList<TrackMenuChoice> TrackMenuChoices => new[]
    {
        new TrackMenuChoice("openState", Loc.T("Ouvrir un état de piste (preset de piste)"), new[] { "File", "Open mixer track state" }, "fo",
            EnterPolicy.Learned(Specs.EnterAfterLetterKey)),
        new TrackMenuChoice("saveState", Loc.T("Enregistrer l'état de la piste"), new[] { "File", "Save mixer track state as" }, "fs", EnterPolicy.IfNeeded),
        new TrackMenuChoice("rename", Loc.T("Renommer, couleur et icône"), new[] { "Rename, color and icon" }, "r", EnterPolicy.IfNeeded),
        new TrackMenuChoice("assignAudio", Loc.T("Créer sa piste audio (Playlist)"), new[] { "Assign to new Audio track(s)" }, "a", EnterPolicy.IfNeeded),
    };

    public static TrackMenuChoice? TrackMenuChoice(string letters) => TrackMenuChoices.FirstOrDefault(c => c.Letters == letters);

    /// Clic droit sur la dernière piste cliquée › File › Open mixer track state (lettres soulignées), Entrée apprise.
    public static BlockBody OpenStateMenu => Specs.OpenStateMenu;

    /// Les modèles : les quatre macros du propriétaire, puis « Supprimer les clips audio inutilisés ». Certains blocs
    /// se règlent sur chaque ordinateur : le preset à choisir, les clics à montrer.
    public static IReadOnlyList<MacroTemplate> Gallery => new[]
    {
        new MacroTemplate("threeFour", Loc.T("3/4"),
            Loc.T("Options › Project general settings, puis deux clics que tu montres une fois dans FL (par exemple la mesure en 3/4)."),
            "metronome", () => new MacroDoc
            {
                Name = Loc.T("3/4"),
                Blocks = new List<Block>
                {
                    new(new BlockBody.MenuBar(new[] { "Options", "Project general settings" })),
                    new(new BlockBody.Click(new ClickTarget.ToLearn())),
                    new(new BlockBody.Click(new ClickTarget.ToLearn())),
                },
                Origin = MacroOrigin.FromTemplate("threeFour"),
            }),
        new MacroTemplate("quickDrop", Loc.T("Enregistrement Rapide"),
            Loc.T("Dépose ton preset de piste sur la dernière piste cliquée du Mixer, sans menu ni boîte « Open ». Choisis le preset une fois dans le créateur."),
            "record.circle", () => new MacroDoc
            {
                Name = Loc.T("Enregistrement Rapide"),
                Blocks = new List<Block> { new(new BlockBody.DropFile("")) },
                Origin = MacroOrigin.FromTemplate("quickDrop"),
            }),
        new MacroTemplate("exportStems", Loc.T("Export Stems"),
            Loc.T("File › Export › All playlist tracks › Time selection, par le menu de FL en haut de sa fenêtre : une piste audio par piste de la Playlist."),
            "square.stack.3d.down.right", () => new MacroDoc
            {
                Name = Loc.T("Export Stems"),
                Blocks = new List<Block> { new(new BlockBody.MenuBar(new[] { "File", "Export", "All playlist tracks", "Time selection..." })) },
                Origin = MacroOrigin.FromTemplate("exportStems"),
            }),
        new MacroTemplate("openVST", Loc.T("Ouvre un VST"),
            Loc.T("Ouvre le Channel rack et y ajoute un instrument (VST, plugin) : choisis-le une fois dans le créateur."),
            "pianokeys", () => new MacroDoc
            {
                Name = Loc.T("Ouvre un VST"),
                Blocks = new List<Block>
                {
                    new(new BlockBody.OpenPage(FlPage.ChannelRack)),
                    new(new BlockBody.PageOption("channelRack.addInstrument", "")),
                },
                Origin = MacroOrigin.FromTemplate("openVST"),
            }),
        new MacroTemplate("purgeAudio", Loc.T("Supprimer les clips audio inutilisés"),
            Loc.T("Tools › Macros › Purge unused audio clips, par le menu de FL en haut de sa fenêtre : FL retire du projet les clips audio qui ne sont pas dans la Playlist (rien n'est effacé de ton disque)."),
            "trash", () => new MacroDoc
            {
                Name = "Supprimer les clips audio inutilisés",
                // Sur Windows, le menu TOOLS de FL range ses macros dans « Macros » (sur le Mac, la barre des menus
                // de macOS les met à plat dans Tools).
                Blocks = new List<Block> { new(new BlockBody.MenuBar(new[] { "Tools", "Macros", "Purge unused audio clips" })) },
                Origin = MacroOrigin.FromTemplate("purgeAudio"),
            }),
    };

    /// Copie avec des ids neufs, imbrication comprise (deux copies d'un modèle ne partagent jamais un id).
    public static List<Block> FreshIds(IEnumerable<Block> blocks) => blocks.Select(b =>
        new Block(b.Body.ReplacingChildren(b.Body.Children.Select(FreshIds).ToList()), b.Enabled, b.OnFailure, b.Note)).ToList();

    /// Les mêmes blocs sans aucune note, imbrications comprises.
    public static List<Block> WithoutNotes(IEnumerable<Block> blocks) => blocks.Select(b =>
        new Block(b.Body.ReplacingChildren(b.Body.Children.Select(WithoutNotes).ToList()), b.Enabled, b.OnFailure, null, b.Id)).ToList();

    /// Armer la piste visée par son menu, avec des blocs simples : clic droit sur la piste, S (Select), ←, ↓ ×5,
    /// Entrée = « Arm selected track(s) », puis la touche REC de FL.
    public static List<Block> ArmThroughTrackMenu(KeyRef rec) => new()
    {
        new(new BlockBody.Click(new ClickTarget.Track(0, 0), MouseButton.Right)),        // menu de la piste
        new(new BlockBody.WaitWindow(WindowKind.Menu, 1_500)),
        new(new BlockBody.MenuLetters("s", EnterPolicy.Never)),                          // Select
        new(new BlockBody.Delay(200)),
        new(new BlockBody.MenuKeyPress(MenuKey.Left, 1)),
        new(new BlockBody.MenuKeyPress(MenuKey.Down, 5)),                                // jusqu'à « Arm selected track(s) »
        new(new BlockBody.MenuKeyPress(MenuKey.Enter, 1)),
        new(new BlockBody.WaitWindowClose(WindowKind.Menu, 1_000)),
        new(new BlockBody.Key(rec, 1)),                                                  // touche REC de FL
    };
}
