// Registre des blocs : l'endroit unique d'où l'interface, l'exécution, la validation, le journal et la documentation
// tirent leurs informations. Miroir de Sources/FLShortcut/MacroRegistry.swift (mêmes règles, mêmes noms dans le journal,
// mêmes durées estimées) ; seules les phrases d'aide qui parlent du Mac (⌘, Finder, barre des menus de macOS) sont
// écrites pour Windows. `BlockRegistry.Spec` est un switch exhaustif : un BlockType ajouté sans fiche lève une exception
// dans les tests.
using FLShortcut.Core.Organizer;

namespace FLShortcut.Core.Macros;

public enum BlockCategory { Keyboard, Mouse, Windows, Fl, Control }

public static class BlockCategories
{
    /// Nom affiché de la catégorie (palette, recherche).
    public static string Label(this BlockCategory c) => c switch
    {
        BlockCategory.Keyboard => Loc.T("Clavier"),
        BlockCategory.Mouse => Loc.T("Souris"),
        BlockCategory.Windows => Loc.T("Attente"),       // un seul bloc « Attendre » (comme le Mac, 28/10)
        BlockCategory.Fl => Loc.T("FL Studio"),
        _ => Loc.T("Contrôle"),
    };
}

/// Ce dont un bloc a besoin, agrégé pour toute la macro.
[Flags]
public enum BlockNeeds
{
    None = 0,
    FlInFront = 1 << 0,
    /// Le clavier doit être au repos avant le premier événement : attendu avant le premier bloc…
    KeyboardIdle = 1 << 1,
    /// … sauf si ce bloc l'attend lui-même, juste avant son premier clic (menu de la piste).
    KeyboardIdleInside = 1 << 2,
    /// Vise la dernière piste cliquée dans FL.
    AimedTrack = 1 << 3,
    /// En tête de macro : refus d'emblée si la piste visée est hors de FL (« clique d'abord sur ta piste »).
    TrackRequired = 1 << 4,
    /// Passe par le lien avec FL (réveil bref) ; un repli clavier peut exister.
    MidiLink = 1 << 5,
    /// Demande l'extension du lien (paramètres, requêtes).
    MidiExtensions = 1 << 6,
    /// Vérification du larsen lancée dès le début de la macro.
    FeedbackEarly = 1 << 7,
    /// Clics envoyés par le système (pointeur déplacé puis remis).
    Clicks = 1 << 8,
}

/// Sorte de valeur d'un paramètre (l'inspecteur du créateur est construit à partir de ce schéma).
public abstract record ParamKind
{
    public sealed record Key : ParamKind;
    public sealed record Ms(int Min, int Max) : ParamKind;
    public sealed record Number(int Min, int Max) : ParamKind;
    public sealed record Letters(int Max) : ParamKind;
    public sealed record MenuKey : ParamKind;
    public sealed record Target : ParamKind;
    public sealed record Window : ParamKind;
    public sealed record File(IReadOnlyList<string> Extensions) : ParamKind;
    public sealed record FlAction : ParamKind;
    public sealed record Condition : ParamKind;
    public sealed record Variable : ParamKind;
    public sealed record Text(int Max) : ParamKind;
    public sealed record Blocks : ParamKind;
    public sealed record Color : ParamKind;
    public sealed record Icon : ParamKind;
}

public sealed record ParamSpec(string Id, string Label, ParamKind Kind, string? Help = null);

public enum BlockContainer { None, Body, IfElse }

/// Ce que l'import d'une macro (.flsmacro) fait du bloc.
public abstract record ImportPolicy
{
    public sealed record Ok : ImportPolicy;
    /// À relire avant de s'en servir (raison, en français : jamais affichée telle quelle).
    public sealed record ToReview(string Reason) : ImportPolicy;
    /// Positions apprises retirées (propres à l'ordinateur qui les a apprises).
    public sealed record StripPositions : ImportPolicy;
}

public sealed record BlockSpec
{
    public required BlockType Type { get; init; }
    /// « Touche », « Lettres d'un menu de FL », « Si… sinon ».
    public required string Label { get; init; }
    public required BlockCategory Category { get; init; }
    /// Symbole du Mac (SF Symbol), traduit en icône de Windows par l'interface.
    public required string Symbol { get; init; }
    /// Phrase de la palette.
    public required string Help { get; init; }
    public required IReadOnlyList<ParamSpec> Params { get; init; }
    public BlockContainer Container { get; init; } = BlockContainer.None;
    public bool InPalette { get; init; } = true;
    public required Func<BlockBody, BlockNeeds> Needs { get; init; }
    public required Func<BlockBody> Default { get; init; }
    /// Ligne de la liste : « Ctrl + S × 2 ».
    public required Func<BlockBody, string> Summary { get; init; }
    /// Nom du bloc dans le journal : JAMAIS une touche, un chemin ou un nom de piste.
    public required Func<BlockBody, string> Journal { get; init; }
    public required Func<BlockBody, int> EstimateMs { get; init; }
    public required Func<BlockBody, ValidationContext, string?> Validate { get; init; }
    public required ImportPolicy Import { get; init; }
}

public static class BlockRegistry
{
    private static (bool English, Dictionary<BlockType, BlockSpec> Specs)? _cache;
    private static readonly object Gate = new();

    /// La fiche d'un type de bloc (dans la langue de l'app).
    public static BlockSpec Spec(BlockType t)
    {
        lock (Gate)
        {
            if (_cache is not { } c || c.English != Loc.English) _cache = c = (Loc.English, Enum.GetValues<BlockType>().ToDictionary(x => x, Specs.Make));
            return c.Specs[t];
        }
    }

    /// Palette du créateur, par catégorie, sans les blocs cachés.
    public static IReadOnlyList<(BlockCategory Category, IReadOnlyList<BlockSpec> Specs)> Palette =>
        Enum.GetValues<BlockCategory>()
            .Select(cat => (cat, (IReadOnlyList<BlockSpec>)Enum.GetValues<BlockType>().Select(Spec).Where(s => s.Category == cat && s.InPalette).ToList()))
            .ToList();

    public static BlockNeeds Needs(BlockBody body) => body.Type is { } t ? Spec(t).Needs(body) : BlockNeeds.None;

    /// Nom du bloc dans le journal (« waitDialog », « armTrack »…), comparable d'une version à l'autre et au Mac.
    public static string Journal(BlockBody body) => body.Type is { } t ? Spec(t).Journal(body) : "unknown";

    public static string Label(BlockBody body) => body.Type is { } t ? Spec(t).Label : Loc.T("Bloc inconnu");

    public static int EstimateMs(BlockBody body) => body.Type is { } t ? Spec(t).EstimateMs(body) : 0;
}

/// Les fiches (construites dans la langue de l'app).
internal static class Specs
{
    private const BlockNeeds Base = BlockNeeds.FlInFront | BlockNeeds.KeyboardIdle;

    /// Clé de mémoire de l'Entrée après la dernière lettre d'un menu (la même que le Mac).
    public const string EnterAfterLetterKey = "macroMenuEnterAfterLetter";
    /// Positions apprises de « (none) » → entrée 1 (la même clé que le Mac).
    public const string InputPathKey = "macroSpots.v2.input";

    /// Clic droit sur la dernière piste cliquée › File › Open mixer track state (lettres soulignées), Entrée apprise.
    public static BlockBody OpenStateMenu => new BlockBody.TrackMenu("fo", new[] { "File", "Open mixer track state" },
        TrackTarget.LastClicked, EnterPolicy.Learned(EnterAfterLetterKey));

    /// Preset d'exemple, là où FL range les presets du Mixer.
    public static string DefaultPreset => System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),
        "Image-Line", "FL Studio", "Presets", "Mixer presets", "Preset.fst");

    public static string Seconds(int ms) => ms % 1000 == 0
        ? Loc.F("%lld s", ms / 1000)
        : (ms / 1000.0).ToString("0.0", System.Globalization.CultureInfo.InvariantCulture).Replace('.', ',') + " s";

    private static string Times(int n) => n > 1 ? $" × {n}" : "";

    private static string WindowName(WindowKind k) => k == WindowKind.Dialog ? Loc.T("Boîte de dialogue") : Loc.T("Menu");

    public static string Describe(Condition c) => c switch
    {
        Condition.WindowOpen w => w.Window == WindowKind.Dialog ? Loc.T("une boîte de dialogue est ouverte") : Loc.T("un menu de FL est ouvert"),
        Condition.FlState s => Loc.F("FL : %@ %@ %lld", s.Query, s.Op.Symbol(), s.Value),
        Condition.Variable v => $"{DisplayText.Safe(v.Name, 16)} {v.Op.Symbol()} {v.Value}",
        Condition.LastBlockFailed => Loc.T("le bloc précédent a échoué"),
        Condition.Not n => Loc.F("non (%@)", Describe(n.Inner)),
        Condition.All a => string.Join(Loc.T(" et "), a.List.Select(Describe)),
        Condition.Any a => string.Join(Loc.T(" ou "), a.List.Select(Describe)),
        _ => "",
    };

    public static string Describe(IntSource v) => v.Kind switch
    {
        "variable" => DisplayText.Safe(v.Name, 16),
        "flState" => Loc.F("FL : %@", v.Name ?? ""),
        _ => v.Value.ToString(System.Globalization.CultureInfo.InvariantCulture),
    };

    public static string Describe(ClickTarget t) => t switch
    {
        ClickTarget.FlWindowPoint => Loc.T("fenêtre de FL"),
        ClickTarget.OpenMenu => Loc.T("menu ouvert"),
        ClickTarget.Button => Loc.T("bouton retrouvé à son image"),
        ClickTarget.Named => Loc.T("bouton retrouvé à son nom"),
        ClickTarget.Track => Loc.T("piste visée"),
        ClickTarget.LastClick => Loc.T("après le clic précédent"),
        ClickTarget.StartCursor => Loc.T("curseur au départ"),
        ClickTarget.CursorXWindowY => Loc.T("colonne du curseur"),
        _ => Loc.T("à montrer dans FL"),
    };

    /// Lettres a à z seulement (lettres soulignées des menus de FL).
    private static bool LettersOk(string letters) => letters.All(ch => ch is >= 'a' and <= 'z');

    private static string Upper(string letters) => string.Join(" › ", letters.Select(ch => char.ToUpperInvariant(ch).ToString()));

    /// Nom du fichier d'un chemin (écrit sur un Mac ou sur un PC).
    private static string FileName(string path) => path[(path.LastIndexOfAny(new[] { '/', '\\' }) + 1)..];

    public static string? KeyProblem(KeyRef key, ValidationContext ctx, string? what = null)
    {
        what ??= Loc.T("touche");
        if (MacKeys.ToWindows(key) is not { } combo || !combo.IsValidKey) return ctx.Fail(Loc.F("%@ non prise en charge.", what));
        if (ForbiddenTargets.Reason(combo) is { } why) return ctx.Fail(Loc.F("%@ interdite (%@).", what, why));
        return null;
    }

    private static string? EnterProblem(EnterPolicy e, ValidationContext ctx) =>
        e.Mode == "learned" && !MacroValidation.LearnedEnterKeys.Contains(e.LegacyKey ?? "") ? ctx.Fail(Loc.T("mémoire de l'Entrée inconnue.")) : null;

    private static BlockNeeds ConditionNeeds(Condition c) => c switch
    {
        Condition.FlState => BlockNeeds.MidiLink | BlockNeeds.MidiExtensions,
        Condition.Not n => ConditionNeeds(n.Inner),
        Condition.All a => a.List.Aggregate(BlockNeeds.None, (acc, x) => acc | ConditionNeeds(x)),
        Condition.Any a => a.List.Aggregate(BlockNeeds.None, (acc, x) => acc | ConditionNeeds(x)),
        _ => BlockNeeds.None,
    };

    private static BlockNeeds SourceNeeds(IntSource v) => v.Kind == "flState" ? BlockNeeds.MidiLink | BlockNeeds.MidiExtensions : BlockNeeds.None;

    /// Mute / solo sans le script : bouton mute de la piste cliquée juste avant (comme MuteSolo.handlesWithoutLink du Mac).
    public static bool MuteSoloWithoutLink(string key) => key is "mute" or "solo";

    private static string ActionLabel(string key) =>
        FlActions.IdForKey(key) is { } id && FlActions.Info(id) is { } info ? Loc.T(info.Label) : DisplayText.Safe(key, 20);

    /// Chemin d'un preset (choisi dans la boîte « Open » ou déposé sur la piste) : mêmes règles pour les deux blocs.
    private static string? PresetFileProblem(string p, ValidationContext ctx)
    {
        // Modèle tout neuf, ou macro reçue d'un autre ordinateur : le preset est à choisir sur celui-ci.
        if (p.Length == 0) return ctx.Fail(Loc.T("preset à choisir dans le créateur."));
        if (p.Length > 1024 || p.Any(char.IsControl)) return ctx.Fail(Loc.T("chemin de fichier invalide."));
        if (!ctx.StrictFiles) return null;
        var home = ctx.Home.TrimEnd('\\', '/');
        var rooted = p.Length > 2 && char.IsAsciiLetter(p[0]) && p[1] == ':' && p[2] is '\\' or '/' || p.StartsWith(@"\\", StringComparison.Ordinal);
        var placeOk = ctx.PresetAnywhere ? rooted
            : home.Length > 0 && (p.StartsWith(home + "\\", StringComparison.OrdinalIgnoreCase) || p.StartsWith(home + "/", StringComparison.OrdinalIgnoreCase));
        var parts = p.Split('\\', '/');
        if (!placeOk || parts.Contains("..") || !FileName(p).EndsWith(".fst", StringComparison.OrdinalIgnoreCase))
            return ctx.Fail(ctx.PresetAnywhere ? Loc.T("preset .fst attendu.") : Loc.T("preset .fst attendu dans ton dossier personnel."));
        return null;
    }

    private static string? WaitValidator(BlockBody body, ValidationContext ctx)
    {
        var ms = body switch { BlockBody.WaitWindow w => w.TimeoutMs, BlockBody.WaitWindowClose w => w.TimeoutMs, _ => 100 };
        return ms is >= 100 and <= MacroValidation.MaxWaitMs ? null : ctx.Fail(Loc.T("attente hors limites."));
    }

    public static BlockSpec Make(BlockType type) => type switch
    {
        BlockType.Key => new BlockSpec
        {
            Type = type, Label = Loc.T("Touche ou raccourci"), Category = BlockCategory.Keyboard, Symbol = "keyboard",
            Help = Loc.T("Envoie une touche ou un raccourci à FL."),
            Params = new[] { new ParamSpec("key", Loc.T("Touche"), new ParamKind.Key()), new ParamSpec("times", Loc.T("Nombre de fois"), new ParamKind.Number(1, 20)) },
            Needs = _ => Base,
            Default = () => new BlockBody.Key(new KeyRef(new MacKey(49), " "), 1),
            Summary = b => b is BlockBody.Key k ? (MacKeys.ToWindows(k.Ref)?.ToString() ?? "?") + Times(k.Times) : "",
            Journal = _ => "key",
            EstimateMs = b => b is BlockBody.Key k ? 50 * Math.Max(k.Times, 1) : 0,
            Validate = (b, ctx) => b is not BlockBody.Key k ? null
                : k.Times is < 1 or > 20 ? ctx.Fail(Loc.T("nombre de fois hors limites.")) : KeyProblem(k.Ref, ctx),
            Import = new ImportPolicy.ToReview("touche envoyée à FL"),
        },
        BlockType.MenuLetters => new BlockSpec
        {
            Type = type, Label = Loc.T("Lettres d'un menu de FL"), Category = BlockCategory.Keyboard, Symbol = "character.cursor.ibeam",
            Help = Loc.T("Tape les lettres soulignées d'un menu de FL ouvert."),
            Params = new[] { new ParamSpec("letters", Loc.T("Lettres"), new ParamKind.Letters(8)), new ParamSpec("finalEnter", Loc.T("Entrée à la fin"), new ParamKind.MenuKey()) },
            Needs = _ => Base,
            Default = () => new BlockBody.MenuLetters("f", EnterPolicy.Never),
            Summary = b => b is BlockBody.MenuLetters m ? Upper(m.Letters) : "",
            Journal = _ => "menuLetters",
            EstimateMs = b => b is BlockBody.MenuLetters m ? 600 * m.Letters.Length + 800 : 0,
            Validate = (b, ctx) => b is not BlockBody.MenuLetters m ? null
                : m.Letters.Length is < 1 or > 8 || !LettersOk(m.Letters) ? ctx.Fail(Loc.T("lettres de menu invalides (a à z)."))
                : EnterProblem(m.FinalEnter, ctx),
            Import = new ImportPolicy.Ok(),
        },
        BlockType.MenuKey => new BlockSpec
        {
            Type = type, Label = Loc.T("Touche de menu"), Category = BlockCategory.Keyboard, Symbol = "arrow.up.arrow.down",
            Help = Loc.T("Flèche, Entrée ou Échap dans un menu de FL."),
            Params = new[] { new ParamSpec("menuKey", Loc.T("Touche"), new ParamKind.MenuKey()), new ParamSpec("times", Loc.T("Nombre de fois"), new ParamKind.Number(1, 20)) },
            Needs = _ => Base,
            Default = () => new BlockBody.MenuKeyPress(MenuKey.Down, 1),
            Summary = b => b is BlockBody.MenuKeyPress m ? m.MenuKey.Symbol() + Times(m.Times) : "",
            Journal = _ => "menuKey",
            EstimateMs = b => b is BlockBody.MenuKeyPress m ? 50 * Math.Max(m.Times, 1) : 0,
            Validate = (b, ctx) => b is BlockBody.MenuKeyPress { Times: < 1 or > 20 } ? ctx.Fail(Loc.T("nombre de fois hors limites.")) : null,
            Import = new ImportPolicy.Ok(),
        },
        BlockType.Click => new BlockSpec
        {
            Type = type, Label = Loc.T("Clic"), Category = BlockCategory.Mouse, Symbol = "cursorarrow.click",
            Help = Loc.T("Clic gauche ou droit à un endroit de FL."),
            Params = new[] { new ParamSpec("target", Loc.T("Où"), new ParamKind.Target()), new ParamSpec("button", Loc.T("Bouton"), new ParamKind.Number(0, 1)) },
            Needs = b => Base | BlockNeeds.Clicks | (b is BlockBody.Click { Target: ClickTarget.Track } ? BlockNeeds.AimedTrack : BlockNeeds.None),
            Default = () => new BlockBody.Click(new ClickTarget.Track(0, 0), MouseButton.Left),
            Summary = b => b is BlockBody.Click c ? (c.Button == MouseButton.Right ? Loc.T("Clic droit · ") : Loc.T("Clic · ")) + Describe(c.Target) : "",
            Journal = _ => "click",
            EstimateMs = _ => 300,
            Validate = (b, ctx) => b switch
            {
                BlockBody.Click { Target: ClickTarget.ToLearn } => ctx.Fail(Loc.T("position à montrer dans FL (« Montrer dans FL… » dans le créateur).")),
                BlockBody.Click c when !c.Target.IsFinite => ctx.Fail(Loc.T("position invalide.")),
                BlockBody.Click { Target: ClickTarget.OpenMenu, Button: MouseButton.Right } => ctx.Fail(Loc.T("clic droit impossible dans un menu ouvert.")),
                _ => null,
            },
            Import = new ImportPolicy.StripPositions(),
        },
        BlockType.Drag => new BlockSpec
        {
            Type = type, Label = Loc.T("Glisser-déposer"), Category = BlockCategory.Mouse, Symbol = "hand.draw",
            Help = Loc.T("Glisse d'un endroit de FL à un autre."),
            Params = new[] { new ParamSpec("from", Loc.T("Glisser"), new ParamKind.Target()) },
            Needs = b => Base | BlockNeeds.Clicks | (b is BlockBody.Drag d && (d.From.IsTrack || d.To.IsTrack) ? BlockNeeds.AimedTrack : BlockNeeds.None),
            Default = () => new BlockBody.Drag(new ClickTarget.LastClick(0, 0), new ClickTarget.StartCursor(0, 0)),
            Summary = b => b is BlockBody.Drag d ? Describe(d.From) + " → " + Describe(d.To) : "",
            Journal = _ => "drag",
            EstimateMs = _ => 700,
            Validate = (b, ctx) => b switch
            {
                BlockBody.Drag d when d.From is ClickTarget.ToLearn || d.To is ClickTarget.ToLearn =>
                    ctx.Fail(Loc.T("glisser à montrer dans FL (« Montrer dans FL… » dans le créateur).")),
                BlockBody.Drag d when !d.From.IsFinite || !d.To.IsFinite => ctx.Fail(Loc.T("position invalide.")),
                BlockBody.Drag { From: ClickTarget.OpenMenu } => ctx.Fail(Loc.T("glisser impossible depuis un menu ouvert.")),
                BlockBody.Drag { To: ClickTarget.OpenMenu } => ctx.Fail(Loc.T("glisser impossible vers un menu ouvert.")),
                _ => null,
            },
            Import = new ImportPolicy.StripPositions(),
        },
        BlockType.Delay => new BlockSpec
        {
            Type = type, Label = Loc.T("Attendre un temps fixe"), Category = BlockCategory.Windows, Symbol = "hourglass",
            Help = Loc.T("Fait une pause (5 s au plus)."),
            Params = new[] { new ParamSpec("wait", Loc.T("Attendre"), new ParamKind.Window()), new ParamSpec("ms", Loc.T("Durée (ms)"), new ParamKind.Ms(0, MacroValidation.MaxDelayMs)) },
            Needs = _ => Base,
            Default = () => new BlockBody.Delay(200),
            Summary = b => b is BlockBody.Delay d ? (d.Ms < 1000 ? Loc.F("%lld ms", d.Ms) : Seconds(d.Ms)) : "",
            Journal = _ => "delay",
            EstimateMs = b => b is BlockBody.Delay d ? Math.Max(d.Ms, 0) : 0,
            Validate = (b, ctx) => b is BlockBody.Delay { Ms: < 0 or > MacroValidation.MaxDelayMs } ? ctx.Fail(Loc.T("pause hors limites.")) : null,
            Import = new ImportPolicy.Ok(),
        },
        BlockType.WaitWindow => new BlockSpec
        {
            Type = type, Label = Loc.T("Attendre une fenêtre"), Category = BlockCategory.Windows, Symbol = "macwindow.badge.plus",
            Help = Loc.T("Attend qu'une boîte ou un menu de FL s'ouvre."),
            Params = new[] { new ParamSpec("wait", Loc.T("Attendre"), new ParamKind.Window()), new ParamSpec("timeoutMs", Loc.T("Au plus (ms)"), new ParamKind.Ms(100, MacroValidation.MaxWaitMs)) },
            Needs = _ => Base,
            Default = () => new BlockBody.WaitWindow(WindowKind.Dialog, 4_000),
            Summary = b => b is BlockBody.WaitWindow w ? Loc.F("%@ · %@ au plus", WindowName(w.Window), Seconds(w.TimeoutMs)) : "",
            Journal = b => b is BlockBody.WaitWindow w ? (w.Window == WindowKind.Dialog ? "waitDialog" : "waitMenu") : "waitWindow",
            EstimateMs = b => b is BlockBody.WaitWindow w ? Math.Max(w.TimeoutMs, 0) : 0,
            Validate = WaitValidator,
            Import = new ImportPolicy.Ok(),
        },
        BlockType.WaitWindowClose => new BlockSpec
        {
            Type = type, Label = Loc.T("Attendre la fermeture"), Category = BlockCategory.Windows, Symbol = "macwindow",
            Help = Loc.T("Attend qu'une boîte ou un menu de FL se ferme."),
            Params = new[] { new ParamSpec("wait", Loc.T("Attendre"), new ParamKind.Window()), new ParamSpec("timeoutMs", Loc.T("Au plus (ms)"), new ParamKind.Ms(100, MacroValidation.MaxWaitMs)) },
            Needs = _ => Base,
            Default = () => new BlockBody.WaitWindowClose(WindowKind.Dialog, 8_000),
            Summary = b => b is BlockBody.WaitWindowClose w ? Loc.F("%@ fermée · %@ au plus", WindowName(w.Window), Seconds(w.TimeoutMs)) : "",
            Journal = b => b is BlockBody.WaitWindowClose w ? (w.Window == WindowKind.Dialog ? "waitDialogClose" : "waitMenuClose") : "waitWindowClose",
            EstimateMs = b => b is BlockBody.WaitWindowClose w ? Math.Max(w.TimeoutMs, 0) : 0,
            Validate = WaitValidator,
            Import = new ImportPolicy.Ok(),
        },
        BlockType.TrackMenu => new BlockSpec
        {
            Type = type, Label = Loc.T("Menu de la piste"), Category = BlockCategory.Fl, Symbol = "list.bullet.rectangle",
            Help = Loc.T("Choisit un élément du menu d'une piste du Mixer."),
            Params = new[] { new ParamSpec("letters", Loc.T("Élément"), new ParamKind.Letters(3)), new ParamSpec("finalEnter", Loc.T("Entrée à la fin"), new ParamKind.MenuKey()) },
            Needs = b => Base | BlockNeeds.KeyboardIdleInside | BlockNeeds.Clicks
                         | (b is BlockBody.TrackMenu { Target: TrackTarget.LastClicked } ? BlockNeeds.AimedTrack | BlockNeeds.TrackRequired : BlockNeeds.None),
            Default = () => OpenStateMenu,
            Summary = b => b is not BlockBody.TrackMenu t ? ""
                : t.Labels.Count == 0 ? Upper(t.Letters) : string.Join(" › ", t.Labels.Select(l => DisplayText.Safe(l, 40))),
            Journal = _ => "trackMenu",
            EstimateMs = _ => 4_000,
            Validate = (b, ctx) =>
            {
                if (b is not BlockBody.TrackMenu t) return null;
                // Lettres des sous-menus puis celle de l'élément (1 à 3, a à z) : « R » pour un élément du menu lui-même,
                // « F O » pour File › Open mixer track state.
                if (t.Labels.Count > 3 || t.Labels.Any(l => l.Length is 0 or > 160)) return ctx.Fail(Loc.T("titres de menu invalides."));
                if (t.Letters.Length is < 1 or > 3 || !LettersOk(t.Letters))
                    return ctx.Fail(Loc.T("choisis l'élément du menu de la piste (ou 1 à 3 lettres soulignées, a à z)."));
                if (t.FinalEnter.Mode == "never") return ctx.Fail(Loc.T("le menu de la piste doit se fermer sur son dernier élément."));
                return EnterProblem(t.FinalEnter, ctx);
            },
            Import = new ImportPolicy.Ok(),
        },
        BlockType.ChooseFile => new BlockSpec
        {
            Type = type, Label = Loc.T("Ouvrir un preset (boîte Open)"), Category = BlockCategory.Fl, Symbol = "doc.badge.arrow.up",
            Help = Loc.T("Ouvre le preset choisi dans la boîte « Open » de FL."),
            Params = new[] { new ParamSpec("path", Loc.T("Fichier"), new ParamKind.File(new[] { "fst" })) },
            Needs = _ => Base,
            Default = () => new BlockBody.ChooseFile(DefaultPreset),
            Summary = b => b is BlockBody.ChooseFile f ? DisplayText.Safe(FileName(f.Path), 40) : "",
            Journal = _ => "chooseFile",
            EstimateMs = _ => 3_000,
            Validate = (b, ctx) => b is BlockBody.ChooseFile f ? PresetFileProblem(f.Path, ctx) : null,
            Import = new ImportPolicy.ToReview("fichier à rechoisir sur cette machine"),
        },
        BlockType.DropFile => new BlockSpec
        {
            Type = type, Label = Loc.T("Ouvrir un preset"), Category = BlockCategory.Fl, Symbol = "square.and.arrow.down.on.square",
            Help = Loc.T("Ouvre le preset que tu veux dans ton Mixer."),
            Params = new[] { new ParamSpec("path", Loc.T("Fichier"), new ParamKind.File(new[] { "fst" })) },
            Needs = _ => Base | BlockNeeds.Clicks | BlockNeeds.AimedTrack | BlockNeeds.TrackRequired,
            Default = () => new BlockBody.DropFile(DefaultPreset),
            Summary = b => b is BlockBody.DropFile f ? DisplayText.Safe(FileName(f.Path), 40) : "",
            Journal = _ => "dropFile",
            EstimateMs = _ => 600,
            Validate = (b, ctx) => b is BlockBody.DropFile f ? PresetFileProblem(f.Path, ctx) : null,
            Import = new ImportPolicy.ToReview("fichier à rechoisir sur cette machine"),
        },
        BlockType.FlAction => new BlockSpec
        {
            Type = type, Label = Loc.T("Action de FL"), Category = BlockCategory.Fl, Symbol = "bolt.horizontal",
            Help = Loc.T("Lance une action de FL (Mixer, Playlist, métronome…)."),
            Params = new[] { new ParamSpec("action", Loc.T("Action"), new ParamKind.FlAction()), new ParamSpec("fallback", Loc.T("Sans lien"), new ParamKind.Key()) },
            Needs = b =>
            {
                var n = Base | BlockNeeds.MidiLink;
                if (b is BlockBody.FlAction { Fallback.Kind: "trackMenuArm" }) n |= BlockNeeds.Clicks | BlockNeeds.AimedTrack;
                // Mute / solo sans le script : bouton mute de la piste cliquée juste avant.
                if (b is BlockBody.FlAction { Fallback.Kind: "none" } a && MuteSoloWithoutLink(a.ActionKey)) n |= BlockNeeds.Clicks | BlockNeeds.AimedTrack;
                return n;
            },
            Default = () => new BlockBody.FlAction("armon", ActionFallback.TrackMenuArm),
            Summary = b => b is BlockBody.FlAction a ? ActionLabel(a.ActionKey) : "",
            Journal = b => b is not BlockBody.FlAction a ? "flAction" : a.ActionKey switch
            {
                "armon" => "armTrack",
                "recon" => "recordOn",
                _ => FlActions.IdForKey(a.ActionKey) is not null ? $"flAction {a.ActionKey}" : "flAction ?",
            },
            EstimateMs = _ => 3_000,
            Validate = (b, ctx) =>
            {
                if (b is not BlockBody.FlAction a) return null;
                if (FlActions.IdForKey(a.ActionKey) is null) return ctx.Fail(Loc.T("action de FL inconnue."));
                return a.Fallback.Kind switch
                {
                    "trackMenuArm" => a.ActionKey == "armon" ? null : ctx.Fail(Loc.T("le menu de la piste ne sait qu'armer la piste.")),
                    "key" when a.Fallback.KeyRef is { } k => KeyProblem(k, ctx, a.ActionKey == "recon" ? Loc.T("touche REC") : Loc.T("touche de secours")),
                    _ => null,
                };
            },
            Import = new ImportPolicy.ToReview("passe par le lien avec FL"),
        },
        BlockType.FlActionValue => new BlockSpec
        {
            Type = type, Label = Loc.T("Action de FL avec valeur"), Category = BlockCategory.Fl, Symbol = "slider.horizontal.3",
            Help = Loc.T("Action de FL avec un nombre (piste, pattern…)."),
            Params = new[] { new ParamSpec("action", Loc.T("Action"), new ParamKind.FlAction()), new ParamSpec("value", Loc.T("Valeur"), new ParamKind.Variable()) },
            InPalette = false,
            Needs = b => b is BlockBody.FlActionValue v ? Base | BlockNeeds.MidiLink | BlockNeeds.MidiExtensions | SourceNeeds(v.Value) : Base,
            Default = () => new BlockBody.FlActionValue("trnext", IntSource.Constant(1)),
            Summary = b => b is BlockBody.FlActionValue v ? $"{ActionLabel(v.ActionKey)} · {Describe(v.Value)}" : "",
            Journal = b => b is BlockBody.FlActionValue v && FlActions.IdForKey(v.ActionKey) is not null ? $"flActionValue {v.ActionKey}" : "flActionValue ?",
            EstimateMs = _ => 3_000,
            Validate = (b, ctx) => b is not BlockBody.FlActionValue v ? null
                : FlActions.IdForKey(v.ActionKey) is null ? ctx.Fail(Loc.T("action de FL inconnue.")) : MacroValidation.SourceProblem(v.Value, ctx),
            Import = new ImportPolicy.ToReview("passe par le lien avec FL"),
        },
        BlockType.SelectInput => new BlockSpec
        {
            Type = type, Label = Loc.T("Choisir l'entrée 1"), Category = BlockCategory.Fl, Symbol = "mic",
            Help = Loc.T("Choisit l'entrée 1 de la piste."),
            Params = Array.Empty<ParamSpec>(),
            Needs = _ => Base | BlockNeeds.Clicks | BlockNeeds.AimedTrack,
            Default = () => new BlockBody.SelectInput(new LearnedRef(InputPathKey)),
            Summary = _ => Loc.T("« (none) » → entrée 1"),
            Journal = _ => "selectInput",
            EstimateMs = _ => 3_000,
            Validate = (b, ctx) => b is BlockBody.SelectInput s && !MacroValidation.LearnedPathKeys.Contains(s.Learned.Key)
                ? ctx.Fail(Loc.T("positions apprises inconnues.")) : null,
            Import = new ImportPolicy.StripPositions(),
        },
        BlockType.NameColor => new BlockSpec
        {
            Type = type, Label = Loc.T("Nom et couleur"), Category = BlockCategory.Fl, Symbol = "paintpalette",
            Help = Loc.T("Donne un nom et une couleur à l'élément choisi dans FL."),
            Params = new[]
            {
                new ParamSpec("name", Loc.T("Nom"), new ParamKind.Text(NameColorPayload.MaxNameScalars)),
                new ParamSpec("color", Loc.T("Couleur"), new ParamKind.Color()),
                new ParamSpec("icon", Loc.T("Icône"), new ParamKind.Icon()),
            },
            Needs = _ => Base | BlockNeeds.MidiLink,
            Default = () => new BlockBody.NameColor(null, NameColorPayload.DefaultColor),
            Summary = b => b is BlockBody.NameColor n ? NameColorPayload.Summary(n.Name, n.Color, n.Fade, n.Icon) : "",
            Journal = _ => "nameColor",
            // L'icône passe par deux fenêtres de FL (nom, grille).
            EstimateMs = b => b is BlockBody.NameColor { Icon: not null } ? 1_800 : 300,
            Validate = (b, ctx) =>
            {
                if (b is not BlockBody.NameColor n) return null;
                var payload = new NameColorPayload(n.Name, n.Color);
                if (n.Fade is not null)
                {
                    // Comme « Gradient color… » de FL : une couleur de départ, et jamais de nom (plusieurs pistes).
                    if (payload.Color is null) return ctx.Fail(Loc.T("un dégradé demande ses deux couleurs."));
                    if (payload.Name is not null) return ctx.Fail(Loc.T("un dégradé ne change pas le nom : retire le nom."));
                    if (n.Icon is not null) return ctx.Fail(Loc.T("un dégradé ne pose pas d'icône : retire l'icône."));
                }
                if (payload.Name is null && payload.Color is null && n.Icon is null) return ctx.Fail(Loc.T("donne un nom ou une couleur."));
                return payload.Name is { } name && NameColorPayload.NameProblem(name) is { } why ? ctx.Fail(why) : null;
            },
            Import = new ImportPolicy.ToReview("renomme et colore dans FL"),
        },
        BlockType.SoundCard => new BlockSpec
        {
            Type = type, Label = Loc.T("Carte son branchée"), Category = BlockCategory.Fl, Symbol = "hifispeaker.and.homepod",
            Help = Loc.T("La carte son branchée (USB…) devient la sortie et l'entrée du PC ; FL la suit tout seul s'il est réglé une fois sur « Primary Sound Driver » dans Options › Audio settings."),
            Params = Array.Empty<ParamSpec>(),
            Needs = _ => BlockNeeds.None,
            Default = () => new BlockBody.SoundCard(),
            Summary = _ => Loc.T("sortie et entrée du PC"),
            Journal = _ => "soundCard",
            EstimateMs = _ => 200,
            Validate = (_, _) => null,
            Import = new ImportPolicy.Ok(),
        },
        BlockType.Organize => new BlockSpec
        {
            Type = type, Label = Loc.T("Organiser"), Category = BlockCategory.Fl, Symbol = "square.stack.3d.up",
            Help = Loc.T("Range, colore et renomme tout le projet."),
            Params = Array.Empty<ParamSpec>(),
            Needs = _ => Base | BlockNeeds.MidiLink,
            Default = () => new BlockBody.Organize(),
            Summary = _ => Loc.T("range, colore, renomme le projet"),
            Journal = _ => "organize",
            EstimateMs = _ => 200,
            Validate = (_, _) => null,
            Import = new ImportPolicy.Ok(),
        },
        BlockType.FeedbackCheck => new BlockSpec
        {
            Type = type, Label = Loc.T("Vérifier le larsen"), Category = BlockCategory.Fl, Symbol = "speaker.wave.2",
            Help = Loc.T("Prévient si le micro risque de faire du larsen."),
            Params = Array.Empty<ParamSpec>(),
            Needs = _ => Base | BlockNeeds.FeedbackEarly,
            Default = () => new BlockBody.FeedbackCheck(),
            Summary = _ => Loc.T("Micro et sortie de l'ordinateur"),
            Journal = _ => "feedbackCheck",
            EstimateMs = _ => 3_000,
            Validate = (_, _) => null,
            Import = new ImportPolicy.Ok(),
        },
        BlockType.OpenPage => new BlockSpec
        {
            Type = type, Label = Loc.T("Ouvrir une page de FL"), Category = BlockCategory.Fl, Symbol = "macwindow",
            Help = Loc.T("Met devant une page de FL (Playlist, Mixer…)."),
            Params = new[] { new ParamSpec("page", Loc.T("Page"), new ParamKind.Window()) },
            Needs = _ => Base | BlockNeeds.MidiLink,
            Default = () => new BlockBody.OpenPage(FlPage.Mixer),
            Summary = b => b is BlockBody.OpenPage p ? p.Page?.Title() ?? Loc.T("page à choisir") : "",
            Journal = b => b is BlockBody.OpenPage p ? $"openPage {p.Page?.Raw() ?? "?"}" : "openPage",
            EstimateMs = _ => 600,
            Validate = (b, ctx) => b is BlockBody.OpenPage { Page: null } ? ctx.Fail(Loc.T("choisis la page de FL à ouvrir.")) : null,
            Import = new ImportPolicy.Ok(),
        },
        BlockType.PageOption => new BlockSpec
        {
            Type = type, Label = Loc.T("Cliquer sur…"), Category = BlockCategory.Fl, Symbol = "cursorarrow.click.2",
            Help = Loc.T("Une option de la page de FL ouverte au-dessus."),
            Params = new[] { new ParamSpec("option", Loc.T("Option"), new ParamKind.FlAction()), new ParamSpec("name", Loc.T("Valeur"), new ParamKind.Text(PageOptions.MaxName)) },
            Needs = b =>
            {
                if (b is not BlockBody.PageOption { Option: { } id }) return Base;
                if (PageOptions.Clicks(id)) return Base | BlockNeeds.Clicks;
                if (!PageOptions.UsesLink(id)) return Base;
                // Armer, mute ou solo sans le lien : par la piste visée (comme « Action de FL »).
                return id is "mixer.armon" or "mixer.mute" or "mixer.solo"
                    ? Base | BlockNeeds.MidiLink | BlockNeeds.Clicks | BlockNeeds.AimedTrack : Base | BlockNeeds.MidiLink;
            },
            // Valide sous la page par défaut d'« Ouvrir une page de FL » (Mixer) ; la palette les donne à choisir.
            Default = () => new BlockBody.PageOption("mixer.armon", ""),
            Summary = b =>
            {
                if (b is not BlockBody.PageOption p) return "";
                if (p.Option is not { } id || PageOptions.Option(id) is not { } option) return Loc.T("option à choisir");
                var value = p.Name.Trim();
                return option.Field switch
                {
                    PageField.Channel => PageOptions.Channel(value) is { } n && option.Kind is PageOption.OptionKind.ChannelToggle t
                        ? Loc.F("%@ du canal %lld", t.Solo ? "Solo" : "Mute", n) : option.Label,
                    PageField.Plugin or PageField.Name or PageField.Arrangement =>
                        value.Length == 0 ? option.Label : Loc.F("%@ : %@", option.Label, DisplayText.Safe(value, 30)),
                    _ => option.Label,
                };
            },
            Journal = b => b is BlockBody.PageOption p ? $"pageOption {(p.Option is { } id ? PageOptions.PageOf(id)?.Raw() : null) ?? "?"}" : "pageOption",
            EstimateMs = _ => 800,
            Validate = (b, ctx) =>
            {
                if (b is not BlockBody.PageOption p) return null;
                if (p.Option is not { } id) return ctx.Fail(Loc.T("choisis l'option à cliquer."));
                if (!PageOptions.IsKnown(id)) return ctx.Fail(Loc.T("option de FL inconnue."));
                return PageOptions.FieldOf(id) is { } field && PageOptions.ValueProblem(field, p.Name) is { } problem ? ctx.Fail(problem) : null;
            },
            Import = new ImportPolicy.Ok(),
        },
        BlockType.MenuBar => new BlockSpec
        {
            Type = type, Label = Loc.T("Menu de FL"), Category = BlockCategory.Fl, Symbol = "menubar.rectangle",
            Help = Loc.T("Choisit un élément des menus de FL (File › Export › …)."),
            Params = Array.Empty<ParamSpec>(),
            Needs = _ => Base,
            Default = () => new BlockBody.MenuBar(Array.Empty<string>()),
            Summary = b => b is not BlockBody.MenuBar m ? ""
                : m.Titles.Count == 0 ? Loc.T("à choisir") : string.Join(" › ", m.Titles.Select(t => DisplayText.Safe(t, 30))),
            Journal = _ => "menuBar",
            EstimateMs = _ => 400,
            Validate = (b, ctx) =>
            {
                if (b is not BlockBody.MenuBar m) return null;
                if (m.Titles.Count == 0) return ctx.Fail(Loc.T("choisis l'élément dans les menus de FL."));
                if (m.Titles.Count is < 2 or > PageOptions.MaxMenuDepth || m.Titles.Any(t => t.Trim().Length == 0 || t.Length > 80))
                    return ctx.Fail(Loc.T("chemin de menu invalide."));
                return null;
            },
            Import = new ImportPolicy.Ok(),
        },
        BlockType.MenuAX => new BlockSpec
        {
            Type = type, Label = Loc.T("Menu (ancien format)"), Category = BlockCategory.Fl, Symbol = "filemenu.and.selection",
            Help = Loc.T("Choisit un élément de menu par son titre."),
            Params = new[] { new ParamSpec("titles", Loc.T("Titres"), new ParamKind.Text(80)), new ParamSpec("fallback", Loc.T("Clics de secours"), new ParamKind.Target()) },
            InPalette = false,
            Needs = _ => Base | BlockNeeds.Clicks,
            Default = () => new BlockBody.MenuAX(new[] { "File" }, Array.Empty<ClickTarget>()),
            Summary = b => b is BlockBody.MenuAX m ? string.Join(" › ", m.Titles.Select(t => DisplayText.Safe(t, 30))) : "",
            Journal = _ => "menu",
            EstimateMs = _ => 2_000,
            Validate = (b, ctx) =>
            {
                if (b is not BlockBody.MenuAX m) return null;
                if (m.Titles.Count is < 1 or > 3 || m.Titles.Any(t => t.Length is 0 or > 80)) return ctx.Fail(Loc.T("titres de menu invalides."));
                if (m.Fallback.Count > 3 || m.Fallback.Any(t => !t.IsFinite)) return ctx.Fail(Loc.T("positions de secours invalides."));
                return null;
            },
            Import = new ImportPolicy.StripPositions(),
        },
        BlockType.IfElse => new BlockSpec
        {
            Type = type, Label = Loc.T("Si… sinon"), Category = BlockCategory.Control, Symbol = "arrow.triangle.branch",
            Help = Loc.T("Fait les blocs « alors » si la condition est vraie, sinon les blocs « sinon »."),
            Params = new[]
            {
                new ParamSpec("condition", Loc.T("Condition"), new ParamKind.Condition()),
                new ParamSpec("then", Loc.T("Alors"), new ParamKind.Blocks()), new ParamSpec("else", Loc.T("Sinon"), new ParamKind.Blocks()),
            },
            Container = BlockContainer.IfElse,
            Needs = b => b.CarriedCondition is { } c ? Base | ConditionNeeds(c) : Base,
            Default = () => new BlockBody.IfElse(new Condition.WindowOpen(WindowKind.Dialog), new List<Block>(), new List<Block>()),
            Summary = b => b.CarriedCondition is { } c ? Loc.T("Si ") + Describe(c) : Loc.T("Si"),
            Journal = _ => "if",
            EstimateMs = b => b is BlockBody.IfElse i ? 50 + Math.Max(MacroValidation.EstimateMs(i.Then), MacroValidation.EstimateMs(i.Otherwise)) : 0,
            Validate = (b, ctx) => b.CarriedCondition is { } c ? MacroValidation.ConditionProblem(c, ctx) : null,
            Import = new ImportPolicy.Ok(),
        },
        BlockType.RepeatCount => new BlockSpec
        {
            Type = type, Label = Loc.T("Répéter"), Category = BlockCategory.Control, Symbol = "repeat",
            Help = Loc.F("Répète les blocs N fois (%lld au plus).", MacroValidation.MaxRepeat),
            Params = new[] { new ParamSpec("count", Loc.T("Nombre de fois"), new ParamKind.Number(1, MacroValidation.MaxRepeat)), new ParamSpec("blocks", Loc.T("Blocs"), new ParamKind.Blocks()) },
            Container = BlockContainer.Body,
            Needs = _ => Base,
            Default = () => new BlockBody.RepeatCount(2, new List<Block>()),
            Summary = b => b is BlockBody.RepeatCount r ? Loc.F("%lld fois", r.Count) : "",
            Journal = _ => "repeat",
            EstimateMs = b => b is BlockBody.RepeatCount r ? MacroValidation.Times(Math.Max(r.Count, 0), MacroValidation.EstimateMs(r.Blocks)) : 0,
            Validate = (b, ctx) => b is BlockBody.RepeatCount { Count: < 1 or > MacroValidation.MaxRepeat } ? ctx.Fail(Loc.T("nombre de répétitions hors limites.")) : null,
            Import = new ImportPolicy.Ok(),
        },
        BlockType.RepeatWhile => new BlockSpec
        {
            Type = type, Label = Loc.T("Tant que"), Category = BlockCategory.Control, Symbol = "arrow.clockwise",
            Help = Loc.F("Répète les blocs tant que la condition est vraie (%lld tours au plus).", MacroValidation.MaxWhile),
            Params = new[]
            {
                new ParamSpec("condition", Loc.T("Condition"), new ParamKind.Condition()),
                new ParamSpec("maxIterations", Loc.T("Tours au plus"), new ParamKind.Number(1, MacroValidation.MaxWhile)),
                new ParamSpec("blocks", Loc.T("Blocs"), new ParamKind.Blocks()),
            },
            Container = BlockContainer.Body,
            Needs = b => b.CarriedCondition is { } c ? Base | ConditionNeeds(c) : Base,
            Default = () => new BlockBody.RepeatWhile(new Condition.WindowOpen(WindowKind.Menu), 10, new List<Block>()),
            Summary = b => b.CarriedCondition is { } c ? Loc.T("Tant que ") + Describe(c) : Loc.T("Tant que"),
            Journal = _ => "while",
            EstimateMs = b => b is BlockBody.RepeatWhile w ? MacroValidation.Times(Math.Max(w.MaxIterations, 0), 50 + MacroValidation.EstimateMs(w.Blocks)) : 0,
            Validate = (b, ctx) => b is not BlockBody.RepeatWhile w ? null
                : w.MaxIterations is < 1 or > MacroValidation.MaxWhile ? ctx.Fail(Loc.T("nombre de tours hors limites."))
                : MacroValidation.ConditionProblem(w.Condition, ctx),
            Import = new ImportPolicy.Ok(),
        },
        BlockType.WaitUntil => new BlockSpec
        {
            Type = type, Label = Loc.T("Attendre que"), Category = BlockCategory.Control, Symbol = "clock.badge.checkmark",
            Help = Loc.T("Attend que la condition devienne vraie (vérifiée 4 fois par seconde, 120 s au plus)."),
            Params = new[] { new ParamSpec("condition", Loc.T("Condition"), new ParamKind.Condition()), new ParamSpec("timeoutMs", Loc.T("Au plus (ms)"), new ParamKind.Ms(100, MacroValidation.MaxWaitMs)) },
            Needs = b => b.CarriedCondition is { } c ? Base | ConditionNeeds(c) : Base,
            Default = () => new BlockBody.WaitUntil(new Condition.WindowOpen(WindowKind.Dialog), 4_000),
            Summary = b => b is BlockBody.WaitUntil u ? Loc.F("Jusqu'à ce que %@ · %@ au plus", Describe(u.Condition), Seconds(u.TimeoutMs)) : "",
            Journal = _ => "waitUntil",
            EstimateMs = b => b is BlockBody.WaitUntil u ? Math.Max(u.TimeoutMs, 0) : 0,
            Validate = (b, ctx) => b is not BlockBody.WaitUntil u ? null
                : u.TimeoutMs is < 100 or > MacroValidation.MaxWaitMs ? ctx.Fail(Loc.T("attente hors limites."))
                : MacroValidation.ConditionProblem(u.Condition, ctx),
            Import = new ImportPolicy.Ok(),
        },
        BlockType.SetVariable => new BlockSpec
        {
            Type = type, Label = Loc.T("Régler une variable"), Category = BlockCategory.Control, Symbol = "number",
            Help = Loc.T("Donne une valeur (nombre entier) à une variable de la macro."),
            Params = new[] { new ParamSpec("variable", Loc.T("Variable"), new ParamKind.Variable()), new ParamSpec("value", Loc.T("Valeur"), new ParamKind.Variable()) },
            InPalette = false,
            Needs = b => b is BlockBody.SetVariable s ? Base | SourceNeeds(s.Value) : Base,
            Default = () => new BlockBody.SetVariable("n", IntSource.Constant(0)),
            Summary = b => b is BlockBody.SetVariable s ? $"{DisplayText.Safe(s.Variable, 16)} = {Describe(s.Value)}" : "",
            Journal = _ => "setVariable",
            EstimateMs = b => b is BlockBody.SetVariable { Value.Kind: "flState" } ? 500 : 0,
            Validate = (b, ctx) => b is not BlockBody.SetVariable s ? null
                : !ctx.Variables.Contains(s.Variable) ? ctx.Fail(Loc.T("variable inconnue.")) : MacroValidation.SourceProblem(s.Value, ctx),
            Import = new ImportPolicy.Ok(),
        },
        BlockType.Stop => new BlockSpec
        {
            Type = type, Label = Loc.T("Arrêter la macro"), Category = BlockCategory.Control, Symbol = "stop.circle",
            Help = Loc.T("Arrête la macro ici, avec un message facultatif."),
            Params = new[] { new ParamSpec("message", Loc.T("Message"), new ParamKind.Text(120)) },
            Needs = _ => Base,
            Default = () => new BlockBody.Stop(null),
            Summary = b => b is BlockBody.Stop { Message: { } m } ? DisplayText.Safe(m, 60) : Loc.T("Fin de la macro"),
            Journal = _ => "stop",
            EstimateMs = _ => 0,
            Validate = (b, ctx) => b is BlockBody.Stop { Message: { } m } && m.Length > MacroValidation.MaxNoteLength ? ctx.Fail(Loc.T("message trop long.")) : null,
            Import = new ImportPolicy.Ok(),
        },
        BlockType.Comment => new BlockSpec
        {
            Type = type, Label = Loc.T("Commentaire"), Category = BlockCategory.Control, Symbol = "text.bubble",
            Help = Loc.T("Note pour toi, ignorée à l'exécution."),
            Params = new[] { new ParamSpec("text", Loc.T("Texte"), new ParamKind.Text(200)) },
            Needs = _ => BlockNeeds.None,
            Default = () => new BlockBody.Comment("Note"),
            Summary = b => b is BlockBody.Comment c ? DisplayText.Safe(c.Text, 60) : "",
            Journal = _ => "comment",
            EstimateMs = _ => 0,
            Validate = (b, ctx) => b is BlockBody.Comment { Text.Length: > 200 } ? ctx.Fail(Loc.T("commentaire trop long.")) : null,
            Import = new ImportPolicy.Ok(),
        },
        _ => throw new ArgumentOutOfRangeException(nameof(type), type, "bloc sans fiche"),
    };
}
