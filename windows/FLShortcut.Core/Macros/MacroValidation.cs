// Validation des macros en blocs (SEC-05). Miroir de Sources/FLShortcut/MacroValidation.swift.
// - Règles de tout l'arbre ici (nombre de blocs, imbrication, conditions, pire durée estimée, variables), règles
//   propres à chaque bloc dans le registre (MacroRegistry.cs). Messages au format « Étape 3 : … ».
// - Un bloc inconnu (format plus récent) bloque la macro : elle n'est jamais exécutée sans lui.
namespace FLShortcut.Core.Macros;

/// Contexte de validation d'un bloc : chemin du bloc (« 3.2 »), variables, règles des fichiers.
public sealed record ValidationContext
{
    /// Fichiers : sous le dossier personnel et en .fst (macros de la bibliothèque, imports).
    public bool StrictFiles { get; init; }
    /// Copie du modèle « Enregistrement rapide » : le preset peut être hors du dossier personnel (disque externe) ;
    /// .fst toujours exigé.
    public bool PresetAnywhere { get; init; }
    public IReadOnlySet<string> Variables { get; init; } = new HashSet<string>();
    public string Path { get; init; } = "1";
    /// Dossier personnel (tests : un autre).
    public string Home { get; init; } = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    /// Message d'erreur : « Étape 3 : touche interdite (…). »
    public string Fail(string text) => Loc.F("Étape %@ : %@", Path, text);
}

public static class MacroValidation
{
    public const int MaxBlocks = 200;
    public const int MaxDepth = 4;
    public const int MaxConditionDepth = 3;
    public const int MaxConditionTerms = 6;
    public const int MaxDelayMs = 5_000;
    public const int MaxWaitMs = 120_000;
    public const int MaxRepeat = 50;
    public const int MaxWhile = 100;
    public const int MaxEstimateMs = 300_000;
    public const int MaxNameLength = 60;
    public const int MaxNoteLength = 120;
    public const int MaxVariables = 8;

    /// Seules clés de mémoire qu'un bloc peut lire et écrire (jamais une clé quelconque venue d'un fichier).
    public static readonly IReadOnlySet<string> LearnedEnterKeys = new HashSet<string> { "macroMenuEnterAfterLetter" };
    public static readonly IReadOnlySet<string> LearnedPathKeys = new HashSet<string> { "macroSpots.v2.input" };
    /// Requêtes d'état de FL prévues (PROTOCOL.md, incrément 4).
    public static readonly IReadOnlySet<string> FlQueries = new HashSet<string>
        { "isrec", "isplay", "track", "armed", "muted", "solo", "window", "channel", "pattern", "tempo" };

    /// Raison pour laquelle ces blocs ne peuvent pas tourner, ou null.
    public static string? Problem(IReadOnlyList<Block> blocks, IReadOnlyList<VariableDecl>? variables, ValidationContext context)
    {
        variables ??= Array.Empty<VariableDecl>();
        if (blocks.Count == 0) return Loc.T("La macro est vide.");
        if (FirstUnknown(blocks) is { } path && BlockAt(path, blocks)?.Body is BlockBody.Unknown unknown)
            return Loc.F("Étape %@ : bloc illisible ou d'une version plus récente de FL Shortcuts (« %@ ») : la macro est bloquée.",
                path, DisplayText.Safe(unknown.TypeName, 30));
        if (Count(blocks) > MaxBlocks) return Loc.F("Macro trop longue (%lld blocs au plus).", MaxBlocks);
        if (Depth(blocks) > MaxDepth) return Loc.F("Blocs trop imbriqués (%lld niveaux au plus).", MaxDepth);
        if (variables.Count > MaxVariables) return Loc.F("Trop de variables (%lld au plus).", MaxVariables);
        var names = new HashSet<string>();
        foreach (var v in variables)
        {
            if (!IsVariableName(v.Name) || !names.Add(v.Name)) return Loc.T("Nom de variable invalide.");
        }
        var ctx = context with { Variables = names };
        if (Check(blocks, "", 0, ctx) is { } why) return why;
        if (PageOptions.Misplaced(blocks) is { } wrong) return PageOptions.MisplacedMessage(wrong);
        if (EstimateMs(blocks) > MaxEstimateMs) return Loc.T("Macro trop longue (durée totale).");
        return null;
    }

    /// Macro de la bibliothèque : nom, format, puis ses blocs.
    public static string? Problem(MacroDoc doc, ValidationContext context)
    {
        if (doc.Format > 2) return Loc.T("Macro d'une version plus récente de FL Shortcuts : elle est bloquée.");
        if (doc.Name.Length == 0 || doc.Name.Length > MaxNameLength) return Loc.T("Nom de macro invalide.");
        return Problem(doc.Blocks, doc.Variables, context);
    }

    private static string? Check(IReadOnlyList<Block> blocks, string prefix, int offset, ValidationContext ctx)
    {
        for (var i = 0; i < blocks.Count; i++)
        {
            var b = blocks[i];
            var c = ctx with { Path = Path(prefix, offset + i + 1) };
            if (b.Note is { } note && note.Length > MaxNoteLength) return c.Fail(Loc.T("note trop longue."));
            if (b.Body.Type is not { } type) return c.Fail(Loc.T("bloc inconnu."));
            if (BlockRegistry.Spec(type).Validate(b.Body, c) is { } why) return why;
            foreach (var (start, child) in ChildLists(b.Body))
                if (Check(child, c.Path, start, ctx) is { } inner) return inner;
        }
        return null;
    }

    /// Chemin d'un bloc : « 3 », puis « 3.2 » pour le 2e bloc imbriqué dans le bloc 3.
    public static string Path(string prefix, int number) =>
        prefix.Length == 0 ? number.ToString(System.Globalization.CultureInfo.InvariantCulture) : $"{prefix}.{number}";

    /// Listes imbriquées avec le numéro de départ de leurs blocs : « alors » et corps commencent à 1, « sinon »
    /// poursuit la numérotation après « alors » (comme la liste à plat de l'éditeur).
    public static IReadOnlyList<(int Start, List<Block> Blocks)> ChildLists(BlockBody body) => body switch
    {
        BlockBody.IfElse i => new[] { (0, i.Then), (i.Then.Count, i.Otherwise) },
        BlockBody.RepeatCount r => new[] { (0, r.Blocks) },
        BlockBody.RepeatWhile w => new[] { (0, w.Blocks) },
        _ => Array.Empty<(int, List<Block>)>(),
    };

    public static string? ConditionProblem(Condition c, ValidationContext ctx)
    {
        if (ConditionDepth(c) > MaxConditionDepth || ConditionTerms(c) > MaxConditionTerms)
            return ctx.Fail(Loc.F("condition trop compliquée (%lld niveaux, %lld termes au plus).", MaxConditionDepth, MaxConditionTerms));
        foreach (var leaf in ConditionLeaves(c))
        {
            switch (leaf)
            {
                case Condition.Variable v when !ctx.Variables.Contains(v.Name): return ctx.Fail(Loc.T("variable inconnue."));
                case Condition.FlState s when !FlQueries.Contains(s.Query): return ctx.Fail(Loc.T("état de FL inconnu."));
            }
        }
        return null;
    }

    public static string? SourceProblem(IntSource v, ValidationContext ctx) => v.Kind switch
    {
        "variable" => ctx.Variables.Contains(v.Name ?? "") ? null : ctx.Fail(Loc.T("variable inconnue.")),
        "flState" => FlQueries.Contains(v.Name ?? "") ? null : ctx.Fail(Loc.T("état de FL inconnu.")),
        _ => null,
    };

    public static bool IsVariableName(string s) =>
        s.Length is >= 1 and <= 16 && s[0] is >= 'a' and <= 'z' && s.All(ch => ch is >= 'a' and <= 'z' or >= '0' and <= '9' or '_');

    // ---------- Mesures de l'arbre ----------

    /// Blocs au total, imbrication comprise.
    public static int Count(IReadOnlyList<Block> blocks) => blocks.Sum(b => 1 + b.Body.Children.Sum(Count));

    /// Niveaux d'imbrication (0 : aucun bloc dans un autre).
    public static int Depth(IReadOnlyList<Block> blocks) =>
        blocks.Select(b => b.Body.Children.Select(list => 1 + Depth(list)).DefaultIfEmpty(0).Max()).DefaultIfEmpty(0).Max();

    public static int ConditionDepth(Condition c) => c switch
    {
        Condition.Not n => 1 + ConditionDepth(n.Inner),
        Condition.All a => 1 + a.List.Select(ConditionDepth).DefaultIfEmpty(0).Max(),
        Condition.Any a => 1 + a.List.Select(ConditionDepth).DefaultIfEmpty(0).Max(),
        _ => 1,
    };

    public static int ConditionTerms(Condition c) => ConditionLeaves(c).Count;

    public static List<Condition> ConditionLeaves(Condition c) => c switch
    {
        Condition.Not n => ConditionLeaves(n.Inner),
        Condition.All a => a.List.SelectMany(ConditionLeaves).ToList(),
        Condition.Any a => a.List.SelectMany(ConditionLeaves).ToList(),
        _ => new List<Condition> { c },
    };

    /// Plafond des durées (jamais de débordement).
    private const long Saturated = int.MaxValue / 2;

    /// Pire durée estimée (blocs actifs ; corps × nombre de tours ; délais d'attente), saturée.
    public static int EstimateMs(IReadOnlyList<Block> blocks)
    {
        long total = 0;
        foreach (var b in blocks)
        {
            if (!b.Enabled) continue;
            total = Math.Min(total + BlockRegistry.EstimateMs(b.Body), Saturated);
        }
        return (int)total;
    }

    /// Produit saturé (boucles imbriquées).
    public static int Times(int n, int ms) => (int)Math.Min((long)n * ms, Saturated);

    /// Besoins agrégés des blocs actifs (arbre entier).
    public static BlockNeeds Needs(IReadOnlyList<Block> blocks)
    {
        var acc = BlockNeeds.None;
        foreach (var b in blocks)
        {
            if (!b.Enabled) continue;
            acc |= BlockRegistry.Needs(b.Body);
            foreach (var list in b.Body.Children) acc |= Needs(list);
        }
        return acc;
    }

    /// Chemin du premier bloc inconnu (« 3.2 »), null s'il n'y en a pas.
    public static string? FirstUnknown(IReadOnlyList<Block> blocks, string prefix = "", int offset = 0)
    {
        for (var i = 0; i < blocks.Count; i++)
        {
            var p = Path(prefix, offset + i + 1);
            if (blocks[i].Body is BlockBody.Unknown) return p;
            foreach (var (start, child) in ChildLists(blocks[i].Body))
                if (FirstUnknown(child, p, start) is { } found) return found;
        }
        return null;
    }

    /// Pur (testé) : message du raccourci d'une macro pas encore prête. « Étape 3 : preset .fst attendu. » →
    /// « Raccourci gardé, mais pas encore actif : règle d'abord le bloc 3 « Ouvrir un preset (boîte Open) » (preset
    /// .fst attendu). »
    public static string ShortcutWaiting(string problem, IReadOnlyList<Block> blocks)
    {
        var lead = Loc.T("Raccourci gardé, mais pas encore actif");
        if (SplitStep(problem) is not { } step)
            return Loc.F("%@ : ", lead) + (problem.Length > 0 ? problem[..1].ToLowerInvariant() + problem[1..] : "");
        var reason = step.Text.Trim();
        if (reason.EndsWith('.')) reason = reason[..^1];
        var label = BlockAt(step.Path, blocks)?.Body.Type is { } type ? Loc.F(" « %@ »", BlockRegistry.Spec(type).Label) : "";
        return Loc.F("%@ : règle d'abord le bloc %@%@ (%@).", lead, step.Path, label, reason);
    }

    /// Pur (testé) : un message au format « Étape 3.2 : position invalide. » coupé en chemin (« 3.2 ») et texte
    /// (« position invalide. »), dans la langue de l'app ; null pour un autre message.
    public static (string Path, string Text)? SplitStep(string message)
    {
        var template = Loc.T("Étape %@ : %@");
        var a = template.IndexOf("%@", StringComparison.Ordinal);
        var b = a < 0 ? -1 : template.IndexOf("%@", a + 2, StringComparison.Ordinal);
        if (a < 0 || b < 0) return null;
        var lead = template[..a];
        var separator = template[(a + 2)..b];
        if (lead.Length == 0 || separator.Length == 0 || !message.StartsWith(lead, StringComparison.Ordinal)) return null;
        var sep = message.IndexOf(separator, lead.Length, StringComparison.Ordinal);
        if (sep <= lead.Length) return null;
        return (message[lead.Length..sep], message[(sep + separator.Length)..]);
    }

    /// Bloc désigné par un chemin (« 3.2 ») ; dans un « si », la numérotation du sinon suit celle du alors.
    public static Block? BlockAt(string path, IReadOnlyList<Block> blocks)
    {
        IReadOnlyList<Block> list = blocks;
        Block? found = null;
        foreach (var part in path.Split('.'))
        {
            if (!int.TryParse(part, System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var n)
                || n < 1 || n > list.Count) return null;
            found = list[n - 1];
            list = found.Body.Children.SelectMany(l => l).ToList();
        }
        return found;
    }
}
