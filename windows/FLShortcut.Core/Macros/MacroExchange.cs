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
        public static ImportFailure TooLarge => new(Loc.T("Fichier trop gros pour une macro."));
        public static ImportFailure NotAMacro => new(Loc.T("Ce fichier n'est pas une macro de FL Shortcuts."));
        public static ImportFailure NewerVersion =>
            new(Loc.T("Macro d'une version plus récente de FL Shortcuts : mets l'app à jour pour l'importer."));
    }

    // ---------- Export ----------

    /// Copie à partager : chaque clic gardé sous une forme qui se retrouve dans le FL d'un autre ordinateur (bouton par son
    /// nom ou son image, point d'une fenêtre de plugin en proportion : ClickTarget.Portable), le reste à montrer une fois ;
    /// chemins relatifs au dossier personnel.
    public static List<Block> Sharable(IEnumerable<Block> blocks, string home) => blocks.Select(b =>
    {
        BlockBody body = b.Body switch
        {
            BlockBody.Click c => c with { Target = c.Target.Portable() },
            BlockBody.Drag d => new BlockBody.Drag(d.From.Portable(), d.To.Portable()),
            BlockBody.MenuAX m => m with { Fallback = Array.Empty<ClickTarget>() },
            BlockBody.ChooseFile f => new BlockBody.ChooseFile(Relative(f.Path, home)),
            BlockBody.DropFile f => new BlockBody.DropFile(Relative(f.Path, home)),
            var other => other.ReplacingChildren(other.Children.Select(list => Sharable(list, home)).ToList()),
        };
        return new Block(body, b.Enabled, b.OnFailure, b.Note, b.Id);
    }).ToList();

    // ---------- Presets joints (19/11 : « le preset part avec la macro ») ----------

    /// Un preset joint : 150 Ko au plus chacun, 180 Ko en tout (le fichier partagé fait 256 Ko au plus).
    public const int MaxAttachedBytes = 150 * 1024, MaxAttachedTotal = 180 * 1024;

    /// Preset d'une macro importée à écrire sur ce PC (Documents › FL Shortcuts › Presets) quand on l'ajoute.
    public sealed record AttachedFile(string Path, byte[] Data);

    /// Nom de fichier sûr : le dernier élément du chemin, sans caractère de contrôle ni séparateur, 80 caractères au plus,
    /// toujours en .fst ; null sinon (jamais d'autre sorte de fichier).
    public static string? SafePresetName(string? name)
    {
        if (name is null) return null;
        var last = name.Split('/', '\\').Last();
        var clean = new string(last.Where(c => !char.IsControl(c) && c is not (':' or '*' or '?' or '"' or '<' or '>' or '|')).ToArray()).Trim();
        if (clean.Length < 5 || clean.StartsWith('.') || !clean.EndsWith(".fst", StringComparison.OrdinalIgnoreCase)) return null;
        return clean.Length <= 80 ? clean : clean[..76] + ".fst";
    }

    /// Lecture sûre d'un preset à joindre : fichier .fst ordinaire (pas un lien), 150 Ko au plus ; null sinon.
    public static byte[]? ReadPreset(string path)
    {
        try
        {
            var info = new FileInfo(path);
            if (!info.Exists || info.LinkTarget is not null || info.Length > MaxAttachedBytes
                || !info.Extension.Equals(".fst", StringComparison.OrdinalIgnoreCase)) return null;
            return File.ReadAllBytes(path);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException) { return null; }
    }

    private static bool IsFileBlock(JsonObject o) => J.Str(o["type"]) is "chooseFile" or "dropFile";

    /// Chaque preset (Ouvrir un preset, preset glissé) part avec la macro, tant qu'il est lisible et que le total tient.
    private static void Attach(JsonNode? node, string home, Func<string, byte[]?> read, ref int total)
    {
        switch (node)
        {
            case JsonObject o:
                if (IsFileBlock(o) && J.Str(o["path"]) is { } path && SafePresetName(path) is { } name
                    && read(Absolute(path, home)) is { } bytes && bytes.Length <= MaxAttachedBytes && total + bytes.Length <= MaxAttachedTotal)
                {
                    o["attached"] = new JsonObject { ["name"] = name, ["data"] = Convert.ToBase64String(bytes) };
                    total += bytes.Length;
                }
                foreach (var (_, child) in o.ToList()) Attach(child, home, read, ref total);
                break;
            case JsonArray a:
                foreach (var child in a.ToList()) Attach(child, home, read, ref total);
                break;
        }
    }

    /// Presets joints d'un fichier importé : le même fichier déjà là (chemin d'origine ou dossier des presets) est repris
    /// tel quel ; sinon écrit dans `presets` sous un nom libre (« Bass 2.fst »), jamais par-dessus un autre fichier. Le
    /// chemin du bloc devient celui de ce PC ; la clé « attached » est retirée.
    private static void Unpack(JsonNode? node, string home, string presets, Func<string, byte[]?> existing, List<AttachedFile> files)
    {
        switch (node)
        {
            case JsonObject o:
                if (IsFileBlock(o) && o["attached"] is JsonObject att)
                {
                    o.Remove("attached");
                    byte[]? bytes = null;
                    try { bytes = J.Str(att["data"]) is { } d && d.Length <= MaxAttachedBytes * 4 / 3 + 8 ? Convert.FromBase64String(d) : null; }
                    catch (FormatException) { bytes = null; }
                    if (bytes is { Length: > 0 and <= MaxAttachedBytes } && SafePresetName(J.Str(att["name"])) is { } name)
                    {
                        var original = J.Str(o["path"]) is { } p ? Absolute(p, home) : null;
                        if (original is not null && existing(original) is { } there && there.AsSpan().SequenceEqual(bytes))
                            o["path"] = original;
                        else
                        {
                            var sep = presets.Contains('\\') ? '\\' : '/';
                            var stem = name[..^4];
                            for (var n = 1; n <= 50; n++)
                            {
                                var dest = presets.TrimEnd('\\', '/') + sep + (n == 1 ? name : $"{stem} {n}.fst");
                                var planned = files.FirstOrDefault(f => f.Path == dest);
                                var onDisk = planned?.Data ?? existing(dest);
                                if (onDisk is not null && !onDisk.AsSpan().SequenceEqual(bytes)) continue;
                                o["path"] = dest;
                                if (onDisk is null) files.Add(new AttachedFile(dest, bytes));
                                break;
                            }
                        }
                    }
                }
                foreach (var (_, child) in o.ToList()) Unpack(child, home, presets, existing, files);
                break;
            case JsonArray a:
                foreach (var child in a.ToList()) Unpack(child, home, presets, existing, files);
                break;
        }
    }

    /// Écrit les presets joints d'une macro qu'on ajoute (Documents › FL Shortcuts › Presets) ; un fichier déjà là n'est
    /// jamais remplacé. La raison si l'un n'a pas pu être écrit, sinon null.
    public static string? WriteAttached(IEnumerable<AttachedFile> files)
    {
        foreach (var f in files)
        {
            try
            {
                if (SafePresetName(f.Path) is null || f.Data.Length > MaxAttachedBytes) continue;
                Directory.CreateDirectory(Path.GetDirectoryName(f.Path)!);
                using var stream = new FileStream(f.Path, FileMode.CreateNew, FileAccess.Write);
                stream.Write(f.Data);
            }
            catch (IOException) when (File.Exists(f.Path)) { }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException)
            {
                return Loc.T("un preset joint n'a pas pu être enregistré dans Documents › FL Shortcuts › Presets");
            }
        }
        return null;
    }

    public static byte[] Export(MacroDoc doc, string appVersion, string home, Func<string, byte[]?>? read = null)
    {
        var blocks = new JsonArray(Sharable(doc.Blocks, home).Select(b => b.ToJson()).ToArray());
        var total = 0;
        Attach(blocks, home, read ?? ReadPreset, ref total);
        var macro = new JsonObject
        {
            ["name"] = doc.Name,
            ["blocks"] = blocks,
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
    /// Files : presets joints à écrire quand on ajoute la macro (WriteAttached).
    public sealed record Preview(MacroDoc Doc, List<string> Lines, List<string> Warnings, int SensitiveCount,
        IReadOnlyList<AttachedFile>? Files = null);

    /// `presets` : dossier des presets joints (Documents › FL Shortcuts › Presets) ; `existing` : contenu d'un fichier
    /// déjà sur ce PC (null : absent).
    public static Preview PrepareImport(byte[] data, string home, string? presets = null, Func<string, byte[]?>? existing = null)
    {
        if (data.Length > MaxBytes) throw ImportFailure.TooLarge;
        JsonObject root;
        try { root = JsonNode.Parse(data) as JsonObject ?? throw ImportFailure.NotAMacro; }
        catch (JsonException) { throw ImportFailure.NotAMacro; }
        if (J.Str(root["format"]) != Format || root["macro"] is not JsonObject macro) throw ImportFailure.NotAMacro;
        if ((J.Int(root["version"]) ?? 1) > Version) throw ImportFailure.NewerVersion;
        if (macro["blocks"] is not JsonArray list) throw ImportFailure.NotAMacro;
        var files = new List<AttachedFile>();
        var presetFolder = presets ?? string.Join(home.Contains('\\') ? '\\' : '/', home.TrimEnd('\\', '/'), "Documents", "FL Shortcuts", "Presets");
        Unpack(list, home, presetFolder, existing ?? ReadPreset, files);
        var parsed = list.Select(n => Block.FromJson(n)).ToList();
        if (MacroValidation.Count(parsed) > MacroValidation.MaxBlocks)
            throw new ImportFailure(Loc.F("Macro trop longue : %lld blocs au plus.", MacroValidation.MaxBlocks));
        if (MacroValidation.Depth(parsed) > MacroValidation.MaxDepth)
            throw new ImportFailure(Loc.F("Blocs trop imbriqués : %lld niveaux au plus.", MacroValidation.MaxDepth));
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
        var joined = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        CollectFilePaths(blocks, joined, presetFolder);
        Describe(blocks, "", 0, 0, lines, warnings, ref sensitive, joined);
        return new Preview(doc, lines, warnings.ToList(), sensitive, files);
    }

    /// Chemins « ~/… » rendus à ce PC ; chaque clic et chaque glisser reste retrouvable ici (ClickTarget.Portable, même pour
    /// un fichier fait à la main), sinon à montrer de nouveau.
    private static List<Block> Localized(IEnumerable<Block> blocks, string home) => blocks.Select(b =>
    {
        BlockBody body = b.Body switch
        {
            BlockBody.ChooseFile f => new BlockBody.ChooseFile(Absolute(f.Path, home)),
            BlockBody.DropFile f => new BlockBody.DropFile(Absolute(f.Path, home)),
            BlockBody.Click c => c with { Target = c.Target.Portable() },
            BlockBody.Drag d => new BlockBody.Drag(d.From.Portable(), d.To.Portable()),
            var other => other.ReplacingChildren(other.Children.Select(list => Localized(list, home)).ToList()),
        };
        return new Block(body, b.Enabled, b.OnFailure, b.Note, b.Id);
    }).ToList();

    /// Chemins des presets qui sont là (joints, rangés dans `presets`).
    private static void CollectFilePaths(IEnumerable<Block> blocks, HashSet<string> joined, string presets)
    {
        foreach (var b in blocks)
        {
            var p = b.Body switch { BlockBody.ChooseFile f => f.Path, BlockBody.DropFile d => d.Path, _ => null };
            if (p is not null && p.StartsWith(presets.TrimEnd('\\', '/'), StringComparison.OrdinalIgnoreCase)) joined.Add(p);
            foreach (var list in b.Body.Children) CollectFilePaths(list, joined, presets);
        }
    }

    private static void Describe(IReadOnlyList<Block> blocks, string prefix, int offset, int depth, List<string> lines,
                                 SortedSet<string> warnings, ref int sensitive, ISet<string> joined)
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
                        warnings.Add(Loc.T("Remontre chaque clic dans FL."));
                        break;
                    case BlockBody.Click { Target: ClickTarget.Named }:
                        marks.Add(Loc.T("clic : bouton retrouvé par son nom"));
                        break;
                    case BlockBody.Click { Target: ClickTarget.Button }:
                        marks.Add(Loc.T("clic : bouton retrouvé à son image"));
                        break;
                    case BlockBody.Click { Target: ClickTarget.FlWindowPoint }:
                        marks.Add(Loc.T("clic : même endroit de la fenêtre du plugin"));
                        break;
                    case BlockBody.Click:
                        marks.Add(Loc.T("clic dans FL"));
                        break;
                    case BlockBody.Drag { From: ClickTarget.ToLearn }:
                        marks.Add(Loc.T("glisser : endroits à montrer dans FL"));
                        warnings.Add(Loc.T("Remontre chaque glisser dans FL."));
                        break;
                    case BlockBody.Drag:
                        marks.Add(Loc.T("glisser dans FL"));
                        break;
                    case BlockBody.ChooseFile { Path: var p } when joined.Contains(p):
                    case BlockBody.DropFile { Path: var q } when joined.Contains(q):
                        marks.Add(Loc.T("preset joint"));
                        break;
                    case BlockBody.ChooseFile or BlockBody.DropFile:
                        marks.Add(Loc.T("fichier"));
                        warnings.Add(Loc.T("Rechoisis le preset : le fichier doit exister sur ce PC."));
                        break;
                }
                if (BlockRegistry.Needs(b.Body).HasFlag(BlockNeeds.MidiLink)) marks.Add(Loc.T("lien avec FL"));
                if (!spec.InPalette && type != BlockType.MenuBar)        // « Menu de FL » : créé par l'enregistreur
                {
                    marks.Add(Loc.T("ancien bloc caché"));
                    warnings.Add(Loc.T("Un ancien bloc caché est inclus : relis-le."));
                }
                if (spec.Import is not ImportPolicy.Ok || !spec.InPalette) sensitive++;
                if (marks.Count > 0) text += " — " + string.Join(", ", marks);
            }
            else
            {
                sensitive++;
                text = Loc.T("Bloc inconnu : la macro restera bloquée");
                warnings.Add(Loc.T("Un bloc vient d'une version plus récente de FL Shortcuts : la macro ne tournera pas."));
            }
            if (!b.Enabled) text += Loc.T(" · éteint");
            lines.Add($"{indent}{path}. {text}");
            foreach (var (start, child) in MacroValidation.ChildLists(b.Body))
                Describe(child, path, start, depth + 1, lines, warnings, ref sensitive, joined);
        }
    }

    /// Ce qu'il faut savoir avant de s'en servir (comme la fiche d'un partage du Mac).
    public static List<string> Notes(Preview preview)
    {
        var notes = new List<string>(preview.Warnings);
        if (preview.SensitiveCount == 1)
            notes.Add(Loc.T("1 étape à relire dans le créateur."));
        else if (preview.SensitiveCount > 1)
            notes.Add(Loc.F("%lld étapes à relire dans le créateur.", preview.SensitiveCount));
        return notes;
    }
}
