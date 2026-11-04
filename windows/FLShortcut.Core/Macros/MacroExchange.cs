// Échange d'une macro (.flsmacro), le même fichier que le Mac (MacroExchange.swift) : partage dans la Communauté, ajout
// d'une macro partagée. À l'export, les positions apprises sont retirées (propres à chaque ordinateur) et les chemins
// rendus relatifs au dossier personnel (« ~/… ») ; à l'import, aucun clic n'est repris d'un fichier : chaque clic et
// chaque glisser est à montrer de nouveau dans FL, les chemins « ~/… » sont rendus à ce PC, les ids sont neufs et la
// macro arrive sans raccourci. Taille, nombre de blocs et imbrication bornés (fichier piégé).
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace FLShortcut.Core.Macros;

public static class MacroExchange
{
    public const string Format = "flsmacro";
    public const int Version = 1;
    public const string FileExtension = "flsmacro";
    public const int MaxBytes = 256 * 1024;

    public sealed class ImportFailure : Exception
    {
        public ImportFailure(string message) : base(message) { }
        public static ImportFailure TooLarge => new(Loc.T("Fichier trop volumineux pour une macro (256 Ko au plus)."));
        public static ImportFailure NotAMacro => new(Loc.T("Ce fichier n'est pas une macro de FL Shortcuts (.flsmacro)."));
        public static ImportFailure NewerVersion =>
            new(Loc.T("Macro d'une version plus récente de FL Shortcuts : mets l'app à jour pour l'importer."));
    }

    // ---------- Export ----------

    /// Copie à partager : positions apprises retirées, chemins relatifs au dossier personnel.
    public static List<Block> Sharable(IEnumerable<Block> blocks, string home) => blocks.Select(b =>
    {
        BlockBody body = b.Body switch
        {
            BlockBody.Click c when c.Target.IsLearnedPosition => c with { Target = new ClickTarget.ToLearn() },
            BlockBody.Drag d when d.From.IsLearnedPosition || d.To.IsLearnedPosition =>
                new BlockBody.Drag(new ClickTarget.ToLearn(), new ClickTarget.ToLearn()),
            BlockBody.MenuAX m => m with { Fallback = Array.Empty<ClickTarget>() },
            BlockBody.ChooseFile f => new BlockBody.ChooseFile(Relative(f.Path, home)),
            BlockBody.DropFile f => new BlockBody.DropFile(Relative(f.Path, home)),
            var other => other.ReplacingChildren(other.Children.Select(list => Sharable(list, home)).ToList()),
        };
        return new Block(body, b.Enabled, b.OnFailure, b.Note, b.Id);
    }).ToList();

    public static byte[] Export(MacroDoc doc, string appVersion, string home)
    {
        var macro = new JsonObject
        {
            ["name"] = doc.Name,
            ["blocks"] = new JsonArray(Sharable(doc.Blocks, home).Select(b => b.ToJson()).ToArray()),
        };
        if (doc.Variables.Count > 0)
            macro["variables"] = new JsonArray(doc.Variables.Select(v => (JsonNode)v.ToJson()).ToArray());
        var file = new JsonObject
        {
            ["exportedBy"] = $"FL Shortcuts {appVersion} (Windows)",
            ["format"] = Format,
            ["macro"] = macro,
            ["version"] = Version,
        };
        return Encoding.UTF8.GetBytes(file.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
    }

    /// « C:\Users\toi\Documents\a.fst » → « ~/Documents/a.fst » (séparateurs « / », comme sur le Mac) ; ailleurs : tel quel.
    public static string Relative(string path, string home)
    {
        var root = home.TrimEnd('\\', '/');
        if (root.Length == 0 || path.Length <= root.Length + 1) return path;
        var sep = path[root.Length];
        if (!path.StartsWith(root, StringComparison.OrdinalIgnoreCase) || sep is not ('\\' or '/')) return path;
        return "~/" + path[(root.Length + 1)..].Replace('\\', '/');
    }

    /// « ~/Documents/a.fst » → dans le dossier personnel de ce PC (séparateur de `home`) ; sinon tel quel.
    public static string Absolute(string path, string home)
    {
        if (!path.StartsWith("~/", StringComparison.Ordinal)) return path;
        var sep = home.Contains('\\') ? '\\' : '/';
        return home.TrimEnd('\\', '/') + sep + path[2..].Replace('/', sep);
    }

    // ---------- Import ----------

    /// Macro prête à entrer dans la bibliothèque, ses étapes en une ligne chacune (retrait selon l'imbrication), ce
    /// qu'il faudra faire avant de s'en servir, et le nombre de blocs à relire.
    public sealed record Preview(MacroDoc Doc, List<string> Lines, List<string> Warnings, int SensitiveCount);

    public static Preview PrepareImport(byte[] data, string home)
    {
        if (data.Length > MaxBytes) throw ImportFailure.TooLarge;
        JsonObject root;
        try { root = JsonNode.Parse(data) as JsonObject ?? throw ImportFailure.NotAMacro; }
        catch (JsonException) { throw ImportFailure.NotAMacro; }
        if (J.Str(root["format"]) != Format || root["macro"] is not JsonObject macro) throw ImportFailure.NotAMacro;
        if ((J.Int(root["version"]) ?? 1) > Version) throw ImportFailure.NewerVersion;
        if (macro["blocks"] is not JsonArray list) throw ImportFailure.NotAMacro;
        var parsed = list.Select(n => Block.FromJson(n)).ToList();
        if (MacroValidation.Count(parsed) > MacroValidation.MaxBlocks)
            throw new ImportFailure(Loc.F("Macro trop longue (%lld blocs au plus).", MacroValidation.MaxBlocks));
        if (MacroValidation.Depth(parsed) > MacroValidation.MaxDepth)
            throw new ImportFailure(Loc.F("Blocs trop imbriqués (%lld niveaux au plus).", MacroValidation.MaxDepth));
        var variables = (J.Arr(macro["variables"]) ?? new JsonArray())
            .Select(VariableDecl.FromJson).OfType<VariableDecl>().Take(MacroValidation.MaxVariables).ToList();
        // Nom nettoyé (ni contrôle ni bidi), coupé sans points de suspension.
        var cleaned = DisplayText.Safe(J.Str(macro["name"]) ?? "", 4_096);
        var name = new string(cleaned.Take(MacroValidation.MaxNameLength).ToArray()).Trim();
        if (name.Length == 0) name = Loc.T("Macro importée");
        // Positions jamais reprises d'un fichier, même fabriqué à la main : chaque clic est à montrer sur ce PC.
        var blocks = Localized(Sharable(MacroTemplates.FreshIds(parsed), home), home);
        var doc = new MacroDoc { Name = name, Blocks = blocks, Variables = variables, Origin = MacroOrigin.Imported };
        var lines = new List<string>();
        var warnings = new SortedSet<string>(StringComparer.Ordinal);
        var sensitive = 0;
        Describe(blocks, "", 0, 0, lines, warnings, ref sensitive);
        return new Preview(doc, lines, warnings.ToList(), sensitive);
    }

    /// Chemins « ~/… » rendus à ce PC ; chaque clic et chaque glisser, quel que soit son repère, est à montrer de nouveau.
    private static List<Block> Localized(IEnumerable<Block> blocks, string home) => blocks.Select(b =>
    {
        BlockBody body = b.Body switch
        {
            BlockBody.ChooseFile f => new BlockBody.ChooseFile(Absolute(f.Path, home)),
            BlockBody.DropFile f => new BlockBody.DropFile(Absolute(f.Path, home)),
            BlockBody.Click c => c with { Target = new ClickTarget.ToLearn() },
            BlockBody.Drag => new BlockBody.Drag(new ClickTarget.ToLearn(), new ClickTarget.ToLearn()),
            var other => other.ReplacingChildren(other.Children.Select(list => Localized(list, home)).ToList()),
        };
        return new Block(body, b.Enabled, b.OnFailure, b.Note, b.Id);
    }).ToList();

    private static void Describe(IReadOnlyList<Block> blocks, string prefix, int offset, int depth, List<string> lines,
                                 SortedSet<string> warnings, ref int sensitive)
    {
        for (var i = 0; i < blocks.Count; i++)
        {
            var b = blocks[i];
            var path = MacroValidation.Path(prefix, offset + i + 1);
            var indent = new string(' ', depth * 4);
            string text;
            if (b.Body.Type is { } type)
            {
                var spec = BlockRegistry.Spec(type);
                var value = spec.Summary(b.Body);
                text = value.Length == 0 ? spec.Label : Loc.F("%@ : %@", spec.Label, value);
                var marks = new List<string>();
                switch (b.Body)
                {
                    case BlockBody.Click { Target: ClickTarget.ToLearn }:
                        marks.Add(Loc.T("clic : position à montrer dans FL"));
                        warnings.Add(Loc.T("Montre de nouveau chaque clic dans FL (positions propres à chaque ordinateur)."));
                        break;
                    case BlockBody.Click:
                        marks.Add(Loc.T("clic dans FL"));
                        break;
                    case BlockBody.Drag { From: ClickTarget.ToLearn }:
                        marks.Add(Loc.T("glisser : endroits à montrer dans FL"));
                        warnings.Add(Loc.T("Montre de nouveau chaque glisser-déposer dans FL (positions propres à chaque ordinateur)."));
                        break;
                    case BlockBody.Drag:
                        marks.Add(Loc.T("glisser dans FL"));
                        break;
                    case BlockBody.ChooseFile or BlockBody.DropFile:
                        marks.Add(Loc.T("fichier"));
                        warnings.Add(Loc.T("Rechoisis le preset : le fichier doit exister sur ce PC."));
                        break;
                }
                if (BlockRegistry.Needs(b.Body).HasFlag(BlockNeeds.MidiLink)) marks.Add(Loc.T("lien avec FL"));
                if (!spec.InPalette && type != BlockType.MenuBar)        // « Menu de FL » : créé par l'enregistreur
                {
                    marks.Add(Loc.T("bloc caché (ancien format)"));
                    warnings.Add(Loc.T("Un bloc caché de l'ancien format est inclus : relis-le dans le créateur avant de t'en servir."));
                }
                if (spec.Import is not ImportPolicy.Ok || !spec.InPalette) sensitive++;
                if (marks.Count > 0) text += " — " + string.Join(", ", marks);
            }
            else
            {
                sensitive++;
                text = Loc.T("Bloc inconnu (version plus récente) : la macro restera bloquée");
                warnings.Add(Loc.T("Un bloc vient d'une version plus récente de FL Shortcuts : la macro ne tournera pas."));
            }
            if (!b.Enabled) text += Loc.T(" (désactivé)");
            lines.Add($"{indent}{path}. {text}");
            foreach (var (start, child) in MacroValidation.ChildLists(b.Body))
                Describe(child, path, start, depth + 1, lines, warnings, ref sensitive);
        }
    }

    /// Ce qu'il faut savoir avant de s'en servir (comme la fiche d'un partage du Mac).
    public static List<string> Notes(Preview preview)
    {
        var notes = new List<string>(preview.Warnings);
        if (preview.SensitiveCount == 1)
            notes.Add(Loc.T("1 étape tape des touches, clique ou ouvre un fichier : relis-la dans le créateur."));
        else if (preview.SensitiveCount > 1)
            notes.Add(Loc.F("%lld étapes tapent des touches, cliquent ou ouvrent des fichiers : relis-les dans le créateur.", preview.SensitiveCount));
        notes.Add(Loc.T("Elle arrive sans raccourci : rien ne se lance tant que tu ne lui en as pas choisi un."));
        return notes;
    }
}
