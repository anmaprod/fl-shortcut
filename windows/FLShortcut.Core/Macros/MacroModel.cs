// Macros en blocs (format 2) : données pures, testables. Miroir de Sources/FLShortcut/MacroModel.swift : MÊME JSON
// (identifiants stables, en ASCII, jamais traduits), pour qu'une macro (.flsmacro, sauvegarde du compte) passe d'un Mac
// à un PC et retour.
// - Codage piloté par le champ `type` : {"type":"if","id":…,"condition":…,"then":[…],"else":[…]}.
// - Décodage tolérant : un bloc de type inconnu (version plus récente) ou illisible est conservé TEL QUEL
//   (`BlockBody.Unknown`) et la macro qui le contient est bloquée : jamais exécutée sans lui (REL-01).
// - Les touches sont celles du Mac (code de touche, ⌘ ⌥ ⌃ ⇧) avec leur caractère : MacKeys les traduit pour Windows.
using System.Text.Json.Nodes;
using FLShortcut.Core.Organizer;

namespace FLShortcut.Core.Macros;

/// Lecture prudente d'une valeur JSON (jamais d'exception).
internal static class J
{
    public static string? Str(JsonNode? n) => n is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;
    public static bool? Bool(JsonNode? n) => n is JsonValue v && v.TryGetValue<bool>(out var b) ? b : null;

    public static double? Num(JsonNode? n)
    {
        if (n is not JsonValue v) return null;
        if (v.TryGetValue<double>(out var d)) return d;
        if (v.TryGetValue<int>(out var i)) return i;
        if (v.TryGetValue<long>(out var l)) return l;
        return null;
    }

    /// Entier exact seulement (1.5 ou 1e300 : null).
    public static int? Int(JsonNode? n) =>
        Num(n) is { } d && double.IsFinite(d) && d == Math.Floor(d) && d >= int.MinValue && d <= int.MaxValue ? (int)d : null;

    public static JsonArray? Arr(JsonNode? n) => n as JsonArray;
    public static JsonObject? Obj(JsonNode? n) => n as JsonObject;

    /// Le nombre tel que le Mac l'écrit : entier s'il l'est.
    public static JsonNode Number(double d) => d == Math.Floor(d) && Math.Abs(d) < 1e15 ? JsonValue.Create((long)d) : JsonValue.Create(d);
}

/// Une macro en blocs (bibliothèque `macros.json`, échange `.flsmacro`).
public sealed class MacroDoc
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public int Format { get; set; } = 2;
    /// ≤ 60, affiché avec précaution (DisplayText.Safe).
    public string Name { get; set; } = "Macro";
    public List<Block> Blocks { get; set; } = new();
    /// ≤ 8 entiers.
    public List<VariableDecl> Variables { get; set; } = new();
    public MacroOrigin? Origin { get; set; }
    /// +1 à chaque enregistrement : clé du cache de validation.
    public int Revision { get; set; }

    /// Tolérant : chaque champ manquant prend sa valeur par défaut ; les blocs ne font jamais échouer la lecture.
    public static MacroDoc FromJson(JsonNode? json)
    {
        var o = J.Obj(json);
        var doc = new MacroDoc();
        if (o is null) return doc;
        if (J.Str(o["id"]) is { } id && Guid.TryParse(id, out var guid)) doc.Id = guid;
        doc.Format = J.Int(o["format"]) ?? 2;
        doc.Name = J.Str(o["name"]) ?? "Macro";
        doc.Blocks = J.Arr(o["blocks"])?.Select(b => Block.FromJson(b)).ToList() ?? new List<Block>();
        doc.Variables = J.Arr(o["variables"])?.Select(VariableDecl.FromJson).OfType<VariableDecl>().ToList() ?? new List<VariableDecl>();
        doc.Origin = MacroOrigin.FromJson(o["origin"]);
        doc.Revision = J.Int(o["revision"]) ?? 0;
        return doc;
    }

    public JsonObject ToJson()
    {
        var o = new JsonObject
        {
            ["id"] = MacroIds.Text(Id),
            ["format"] = Format,
            ["name"] = Name,
            ["blocks"] = new JsonArray(Blocks.Select(b => b.ToJson()).ToArray()),
        };
        if (Variables.Count > 0) o["variables"] = new JsonArray(Variables.Select(v => (JsonNode)v.ToJson()).ToArray());
        if (Origin is not null) o["origin"] = Origin.ToJson();
        o["revision"] = Revision;
        return o;
    }
}

internal static class MacroIds
{
    /// Comme `UUID.uuidString` du Mac : majuscules.
    public static string Text(Guid id) => id.ToString("D").ToUpperInvariant();
}

/// Variable entière d'une macro (jamais de texte).
public sealed record VariableDecl(string Name, int Initial = 0)
{
    public static VariableDecl? FromJson(JsonNode? n) =>
        J.Obj(n) is { } o && J.Str(o["name"]) is { } name ? new VariableDecl(name, J.Int(o["initial"]) ?? 0) : null;

    public JsonObject ToJson() => new() { ["name"] = Name, ["initial"] = Initial };
}

/// D'où vient une macro : modèle développé, import, enregistrement, ancienne macro reprise.
public sealed record MacroOrigin(string Kind, string? Template = null)
{
    public static MacroOrigin Imported => new("imported");
    public static MacroOrigin Recorded => new("recorded");
    public static MacroOrigin Legacy => new("legacy");
    public static MacroOrigin FromTemplate(string name) => new("template", name);

    public static MacroOrigin? FromJson(JsonNode? n) => J.Str(J.Obj(n)?["kind"]) switch
    {
        "template" => FromTemplate(J.Str(n!["name"]) ?? "?"),
        "imported" => Imported,
        "recorded" => Recorded,
        "legacy" => Legacy,
        _ => null,
    };

    public JsonObject ToJson()
    {
        var o = new JsonObject { ["kind"] = Kind };
        if (Kind == "template") o["name"] = Template ?? "?";
        return o;
    }
}

public enum FailurePolicy
{
    Stop,
    /// Le bloc qui échoue est sauté (« dernier bloc échoué » devient vrai) ; la macro continue.
    KeepGoing,
}

/// Les types de blocs, par leur nom JSON (stable).
public enum BlockType
{
    Key, MenuLetters, MenuKey, Click, Delay, WaitWindow, WaitWindowClose, Drag, TrackMenu, ChooseFile, DropFile, FlAction,
    FlActionValue, SelectInput, FeedbackCheck, NameColor, SoundCard, Organize, OpenPage, PageOption, MenuBar, MenuAX,
    IfElse, RepeatCount, RepeatWhile, WaitUntil, SetVariable, Stop, Comment,
}

public static class BlockTypes
{
    private static readonly Dictionary<BlockType, string> Raws = new()
    {
        [BlockType.Key] = "key", [BlockType.MenuLetters] = "menuLetters", [BlockType.MenuKey] = "menuKey",
        [BlockType.Click] = "click", [BlockType.Delay] = "delay", [BlockType.WaitWindow] = "waitWindow",
        [BlockType.WaitWindowClose] = "waitWindowClose", [BlockType.Drag] = "drag", [BlockType.TrackMenu] = "trackMenu",
        [BlockType.ChooseFile] = "chooseFile", [BlockType.DropFile] = "dropFile", [BlockType.FlAction] = "flAction",
        [BlockType.FlActionValue] = "flActionValue", [BlockType.SelectInput] = "selectInput",
        [BlockType.FeedbackCheck] = "feedbackCheck", [BlockType.NameColor] = "nameColor", [BlockType.SoundCard] = "soundCard",
        [BlockType.Organize] = "organize", [BlockType.OpenPage] = "openPage", [BlockType.PageOption] = "pageOption",
        [BlockType.MenuBar] = "menuBar", [BlockType.MenuAX] = "menuAX", [BlockType.IfElse] = "if",
        [BlockType.RepeatCount] = "repeat", [BlockType.RepeatWhile] = "while", [BlockType.WaitUntil] = "waitUntil",
        [BlockType.SetVariable] = "setVariable", [BlockType.Stop] = "stop", [BlockType.Comment] = "comment",
    };

    private static readonly Dictionary<string, BlockType> ByRaw = Raws.ToDictionary(kv => kv.Value, kv => kv.Key);

    public static string Raw(this BlockType t) => Raws[t];
    public static BlockType? FromRaw(string raw) => ByRaw.TryGetValue(raw, out var t) ? t : null;
    public static IReadOnlyList<BlockType> All { get; } = Enum.GetValues<BlockType>();
}

public sealed class Block
{
    /// Stable : surlignage, rapport par bloc, positions apprises.
    public Guid Id { get; set; } = Guid.NewGuid();
    /// Case à cocher.
    public bool Enabled { get; set; } = true;
    public FailurePolicy OnFailure { get; set; } = FailurePolicy.Stop;
    /// Commentaire ≤ 120.
    public string? Note { get; set; }
    public BlockBody Body { get; set; }

    public Block(BlockBody body, bool enabled = true, FailurePolicy onFailure = FailurePolicy.Stop, string? note = null, Guid? id = null)
    {
        Body = body;
        Enabled = enabled;
        OnFailure = onFailure;
        Note = note;
        Id = id ?? Guid.NewGuid();
    }

    /// Imbrication au-delà de laquelle plus rien n'est interprété (fichier piégé) : bloc conservé tel quel.
    public const int MaxParseDepth = 16;

    /// Champs communs à tous les blocs (hors paramètres).
    public static readonly string[] CommonKeys = { "type", "id", "enabled", "onFailure", "note" };

    /// Jamais d'échec : tout ce qui n'est pas compris devient `Unknown` (conservé, macro bloquée).
    public static Block FromJson(JsonNode? json, int depth = 0)
    {
        var o = J.Obj(json);
        var typeName = J.Str(o?["type"]) ?? "?";
        var id = J.Str(o?["id"]) is { } text && Guid.TryParse(text, out var g) ? g : Guid.NewGuid();
        var enabled = J.Bool(o?["enabled"]) ?? true;
        var onFailure = J.Str(o?["onFailure"]) == "continue" ? FailurePolicy.KeepGoing : FailurePolicy.Stop;
        var note = J.Str(o?["note"]);
        BlockBody body;
        if (o is not null && depth < MaxParseDepth && BlockTypes.FromRaw(typeName) is { } type && BlockBody.Parse(type, o, depth) is { } parsed)
        {
            body = parsed;
        }
        else if (o is not null)
        {
            // Paramètres gardés tels quels ; les champs communs (id, case à cocher…) sont rendus à l'écriture.
            var raw = (JsonObject)o.DeepClone();
            foreach (var key in CommonKeys) raw.Remove(key);
            body = new BlockBody.Unknown(typeName, raw);
        }
        else
        {
            body = new BlockBody.Unknown(typeName, json?.DeepClone());
        }
        return new Block(body, enabled, onFailure, note, id);
    }

    /// null : un bloc illisible qui était `null` dans le fichier, réécrit tel quel.
    public JsonNode? ToJson()
    {
        JsonObject o;
        if (Body is BlockBody.Unknown unknown)
        {
            if (unknown.Raw is not JsonObject r) return unknown.Raw?.DeepClone();
            o = (JsonObject)r.DeepClone();
            o["type"] = unknown.TypeName;
        }
        else
        {
            o = Body.Params();
            o["type"] = Body.Type!.Value.Raw();
        }
        o["id"] = MacroIds.Text(Id);
        o["enabled"] = Enabled;
        o["onFailure"] = OnFailure == FailurePolicy.KeepGoing ? "continue" : "stop";
        if (Note is not null) o["note"] = Note; else o.Remove("note");
        return o;
    }

    /// Même bloc, même JSON (comparaison des essais).
    public bool SameAs(Block other) => ToJson()?.ToJsonString() == other.ToJson()?.ToJsonString();
}

/// Ce que fait un bloc.
public abstract record BlockBody
{
    // Clavier
    public sealed record Key(KeyRef Ref, int Times = 1) : BlockBody;
    /// « Lettres d'un menu de FL » (seulement si un menu est ouvert).
    public sealed record MenuLetters(string Letters, EnterPolicy FinalEnter) : BlockBody;
    /// ↑ ↓ ← → Entrée Échap, seulement dans un menu ouvert.
    public sealed record MenuKeyPress(MenuKey MenuKey, int Times = 1) : BlockBody;
    // Souris
    public sealed record Click(ClickTarget Target, MouseButton Button = MouseButton.Left) : BlockBody;
    /// Appui à `From`, glissé jusqu'à `To`, relâché.
    public sealed record Drag(ClickTarget From, ClickTarget To) : BlockBody;
    // Fenêtres et attentes
    public sealed record Delay(int Ms) : BlockBody;
    public sealed record WaitWindow(WindowKind Window, int TimeoutMs) : BlockBody;
    public sealed record WaitWindowClose(WindowKind Window, int TimeoutMs) : BlockBody;
    // FL. `Labels` : libellés du menu, pour les messages seulement.
    public sealed record TrackMenu(string Letters, IReadOnlyList<string> Labels, TrackTarget Target, EnterPolicy FinalEnter) : BlockBody;
    public sealed record ChooseFile(string Path) : BlockBody;
    /// Preset glissé sur la dernière piste cliquée (pas de menu ni de boîte « Ouvrir »).
    public sealed record DropFile(string Path) : BlockBody;
    /// Clé stable du protocole ; repli : touche / chemin clavier.
    public sealed record FlAction(string ActionKey, ActionFallback Fallback) : BlockBody;
    public sealed record FlActionValue(string ActionKey, IntSource Value) : BlockBody;
    public sealed record SelectInput(LearnedRef Learned) : BlockBody;
    public sealed record FeedbackCheck : BlockBody;
    /// Nom et/ou couleur de l'élément sélectionné de la page de FL devant ; `Fade` : dégradé ; `Icon` : icône de FL.
    public sealed record NameColor(string? Name, RgbColor? Color, RgbColor? Fade = null, FlIcon? Icon = null) : BlockBody;
    /// La carte son branchée devient la sortie et l'entrée de l'ordinateur.
    public sealed record SoundCard : BlockBody;
    /// Ouvre l'Organiser ; le bloc se termine aussitôt.
    public sealed record Organize : BlockBody;
    /// Met devant une page de FL, seulement si elle n'y est pas déjà ; null : page encore à choisir.
    public sealed record OpenPage(FlPage? Page) : BlockBody;
    /// « Cliquer sur… » : une option de la page ouverte au-dessus ; `Name` : le plugin à ajouter. null : à choisir.
    public sealed record PageOption(string? Option, string Name) : BlockBody;
    /// Élément d'un menu de FL (titre du menu, puis des éléments).
    public sealed record MenuBar(IReadOnlyList<string> Titles) : BlockBody;
    /// Ancienne étape `menu` (reprise des anciennes macros, hors palette).
    public sealed record MenuAX(IReadOnlyList<string> Titles, IReadOnlyList<ClickTarget> Fallback) : BlockBody;
    // Contrôle
    public sealed record IfElse(Condition Condition, List<Block> Then, List<Block> Otherwise) : BlockBody;
    public sealed record RepeatCount(int Count, List<Block> Blocks) : BlockBody;
    public sealed record RepeatWhile(Condition Condition, int MaxIterations, List<Block> Blocks) : BlockBody;
    public sealed record WaitUntil(Condition Condition, int TimeoutMs) : BlockBody;
    public sealed record SetVariable(string Variable, IntSource Value) : BlockBody;
    public sealed record Stop(string? Message) : BlockBody;
    public sealed record Comment(string Text) : BlockBody;
    /// Format plus récent ou bloc illisible : conservé tel quel, macro BLOQUÉE (jamais exécutée sans lui).
    public sealed record Unknown(string TypeName, JsonNode? Raw) : BlockBody;

    /// null pour un bloc inconnu.
    public BlockType? Type => this switch
    {
        Key => BlockType.Key,
        MenuLetters => BlockType.MenuLetters,
        MenuKeyPress => BlockType.MenuKey,
        Click => BlockType.Click,
        Drag => BlockType.Drag,
        Delay => BlockType.Delay,
        WaitWindow => BlockType.WaitWindow,
        WaitWindowClose => BlockType.WaitWindowClose,
        TrackMenu => BlockType.TrackMenu,
        ChooseFile => BlockType.ChooseFile,
        DropFile => BlockType.DropFile,
        FlAction => BlockType.FlAction,
        FlActionValue => BlockType.FlActionValue,
        SelectInput => BlockType.SelectInput,
        FeedbackCheck => BlockType.FeedbackCheck,
        NameColor => BlockType.NameColor,
        SoundCard => BlockType.SoundCard,
        Organize => BlockType.Organize,
        OpenPage => BlockType.OpenPage,
        PageOption => BlockType.PageOption,
        MenuBar => BlockType.MenuBar,
        MenuAX => BlockType.MenuAX,
        IfElse => BlockType.IfElse,
        RepeatCount => BlockType.RepeatCount,
        RepeatWhile => BlockType.RepeatWhile,
        WaitUntil => BlockType.WaitUntil,
        SetVariable => BlockType.SetVariable,
        Stop => BlockType.Stop,
        Comment => BlockType.Comment,
        _ => null,
    };

    /// Listes de blocs imbriquées (alors puis sinon, corps d'une boucle).
    public IReadOnlyList<List<Block>> Children => this switch
    {
        IfElse i => new[] { i.Then, i.Otherwise },
        RepeatCount r => new[] { r.Blocks },
        RepeatWhile w => new[] { w.Blocks },
        _ => Array.Empty<List<Block>>(),
    };

    /// Le même bloc avec d'autres listes imbriquées (dans l'ordre de `Children`).
    public BlockBody ReplacingChildren(IReadOnlyList<List<Block>> lists) => this switch
    {
        IfElse i when lists.Count == 2 => i with { Then = lists[0], Otherwise = lists[1] },
        RepeatCount r when lists.Count == 1 => r with { Blocks = lists[0] },
        RepeatWhile w when lists.Count == 1 => w with { Blocks = lists[0] },
        _ => this,
    };

    /// Condition portée par le bloc (si, tant que, attendre que).
    public Condition? CarriedCondition => this switch
    {
        IfElse i => i.Condition,
        RepeatWhile w => w.Condition,
        WaitUntil u => u.Condition,
        _ => null,
    };

    // ---------- Codage des paramètres (identifiants JSON stables) ----------

    private static JsonArray Strings(IEnumerable<string> list) => new(list.Select(s => (JsonNode)JsonValue.Create(s)!).ToArray());
    private static JsonArray BlockArray(IEnumerable<Block> list) => new(list.Select(b => b.ToJson()).ToArray());

    public JsonObject Params() => this switch
    {
        Key k => new JsonObject { ["key"] = k.Ref.ToJson(), ["times"] = k.Times },
        MenuLetters m => new JsonObject { ["letters"] = m.Letters, ["finalEnter"] = m.FinalEnter.ToJson() },
        MenuKeyPress m => new JsonObject { ["menuKey"] = m.MenuKey.Raw(), ["times"] = m.Times },
        Click c => new JsonObject { ["target"] = c.Target.ToJson(), ["button"] = c.Button == MouseButton.Right ? "right" : "left" },
        Drag d => new JsonObject { ["from"] = d.From.ToJson(), ["to"] = d.To.ToJson() },
        Delay d => new JsonObject { ["ms"] = d.Ms },
        WaitWindow w => new JsonObject { ["window"] = w.Window.Raw(), ["timeoutMs"] = w.TimeoutMs },
        WaitWindowClose w => new JsonObject { ["window"] = w.Window.Raw(), ["timeoutMs"] = w.TimeoutMs },
        TrackMenu t => new JsonObject
        {
            ["letters"] = t.Letters, ["labels"] = Strings(t.Labels), ["target"] = t.Target == TrackTarget.Cursor ? "cursor" : "lastClicked",
            ["finalEnter"] = t.FinalEnter.ToJson(),
        },
        ChooseFile c => new JsonObject { ["path"] = c.Path },
        DropFile d => new JsonObject { ["path"] = d.Path },
        FlAction a => new JsonObject { ["action"] = a.ActionKey, ["fallback"] = a.Fallback.ToJson() },
        FlActionValue a => new JsonObject { ["action"] = a.ActionKey, ["value"] = a.Value.ToJson() },
        SelectInput s => new JsonObject { ["learned"] = s.Learned.ToJson() },
        FeedbackCheck or SoundCard or Organize => new JsonObject(),
        OpenPage p => p.Page is { } page ? new JsonObject { ["page"] = page.Raw() } : new JsonObject(),
        PageOption p => p.Option is { } option ? new JsonObject { ["name"] = p.Name, ["option"] = option } : new JsonObject { ["name"] = p.Name },
        NameColor n => NameColorParams(n),
        MenuBar m => new JsonObject { ["titles"] = Strings(m.Titles) },
        MenuAX m => new JsonObject { ["titles"] = Strings(m.Titles), ["fallback"] = new JsonArray(m.Fallback.Select(t => (JsonNode)t.ToJson()).ToArray()) },
        IfElse i => new JsonObject { ["condition"] = i.Condition.ToJson(), ["then"] = BlockArray(i.Then), ["else"] = BlockArray(i.Otherwise) },
        RepeatCount r => new JsonObject { ["count"] = r.Count, ["blocks"] = BlockArray(r.Blocks) },
        RepeatWhile w => new JsonObject { ["condition"] = w.Condition.ToJson(), ["maxIterations"] = w.MaxIterations, ["blocks"] = BlockArray(w.Blocks) },
        WaitUntil u => new JsonObject { ["condition"] = u.Condition.ToJson(), ["timeoutMs"] = u.TimeoutMs },
        SetVariable s => new JsonObject { ["variable"] = s.Variable, ["value"] = s.Value.ToJson() },
        Stop s => s.Message is { } message ? new JsonObject { ["message"] = message } : new JsonObject(),
        Comment c => new JsonObject { ["text"] = c.Text },
        Unknown u => u.Raw is JsonObject o ? (JsonObject)o.DeepClone() : new JsonObject(),
        _ => new JsonObject(),
    };

    private static JsonObject NameColorParams(NameColor n)
    {
        var p = new JsonObject();
        if (n.Name is not null) p["name"] = n.Name;
        if (n.Color is { } color) p["color"] = color.Hex;
        if (n.Fade is { } fade) p["fade"] = fade.Hex;
        if (n.Icon is { } icon) p["icon"] = icon.Code;
        return p;
    }

    /// null = paramètres illisibles (le bloc devient `Unknown`, conservé et bloquant).
    public static BlockBody? Parse(BlockType type, JsonObject j, int depth)
    {
        List<Block>? List(string key) => J.Arr(j[key])?.Select(b => Block.FromJson(b, depth + 1)).ToList();
        string? Letters(string key) => J.Str(j[key]);
        switch (type)
        {
            case BlockType.Key:
                return KeyRef.FromJson(j["key"]) is { } k ? new Key(k, J.Int(j["times"]) ?? 1) : null;
            case BlockType.MenuLetters:
                return Letters("letters") is { } ml && EnterPolicy.FromJson(j["finalEnter"]) is { } me ? new MenuLetters(ml, me) : null;
            case BlockType.MenuKey:
                return MenuKeys.FromRaw(J.Str(j["menuKey"])) is { } mk ? new MenuKeyPress(mk, J.Int(j["times"]) ?? 1) : null;
            case BlockType.Click:
            {
                var button = J.Str(j["button"]) ?? "left";
                if (button is not ("left" or "right") || ClickTarget.FromJson(j["target"]) is not { } t) return null;
                return new Click(t, button == "right" ? MouseButton.Right : MouseButton.Left);
            }
            case BlockType.Drag:
                return ClickTarget.FromJson(j["from"]) is { } from && ClickTarget.FromJson(j["to"]) is { } to ? new Drag(from, to) : null;
            case BlockType.Delay:
                return J.Int(j["ms"]) is { } ms ? new Delay(ms) : null;
            case BlockType.WaitWindow:
            case BlockType.WaitWindowClose:
            {
                if (WindowKinds.FromRaw(J.Str(j["window"])) is not { } kind || J.Int(j["timeoutMs"]) is not { } timeout) return null;
                return type == BlockType.WaitWindow ? new WaitWindow(kind, timeout) : new WaitWindowClose(kind, timeout);
            }
            case BlockType.TrackMenu:
            {
                if (Letters("letters") is not { } l || EnterPolicy.FromJson(j["finalEnter"]) is not { } e) return null;
                var target = J.Str(j["target"]) switch { "lastClicked" => TrackTarget.LastClicked, "cursor" => TrackTarget.Cursor, _ => (TrackTarget?)null };
                if (target is null) return null;
                var labels = J.Arr(j["labels"])?.Select(J.Str).OfType<string>().ToList() ?? new List<string>();
                return new TrackMenu(l, labels, target.Value, e);
            }
            case BlockType.ChooseFile:
                return J.Str(j["path"]) is { } path ? new ChooseFile(path) : null;
            case BlockType.DropFile:
                return J.Str(j["path"]) is { } drop ? new DropFile(drop) : null;
            case BlockType.FlAction:
                return J.Str(j["action"]) is { } key && ActionFallback.FromJson(j["fallback"]) is { } fb ? new FlAction(key, fb) : null;
            case BlockType.FlActionValue:
                return J.Str(j["action"]) is { } vkey && IntSource.FromJson(j["value"]) is { } value ? new FlActionValue(vkey, value) : null;
            case BlockType.SelectInput:
                return LearnedRef.FromJson(j["learned"]) is { } r ? new SelectInput(r) : null;
            case BlockType.FeedbackCheck:
                return new FeedbackCheck();
            case BlockType.SoundCard:
                return new SoundCard();
            case BlockType.Organize:
                return new Organize();
            case BlockType.OpenPage:
            {
                if (j["page"] is null) return new OpenPage(null);
                return FlPages.FromRaw(J.Str(j["page"])) is { } page ? new OpenPage(page) : null;
            }
            case BlockType.PageOption:
                if (j["option"] is not null && J.Str(j["option"]) is null) return null;
                return new PageOption(J.Str(j["option"]), J.Str(j["name"]) ?? "");
            case BlockType.NameColor:
            {
                // Clé présente mais illisible (nom non texte, couleur hors format) : bloc illisible, conservé et bloquant.
                if (j["name"] is not null && J.Str(j["name"]) is null) return null;
                bool Color(string key, out RgbColor? color)
                {
                    color = null;
                    if (j[key] is null) return true;
                    if (J.Str(j[key]) is not { } hex || RgbColor.FromHex(hex) is not { } c) return false;
                    color = c;
                    return true;
                }
                if (!Color("color", out var col) || !Color("fade", out var fade)) return null;
                FlIcon? icon = null;
                if (j["icon"] is not null)
                {
                    if (J.Str(j["icon"]) is not { } code || FlIcon.FromCode(code) is not { } i) return null;
                    icon = i;
                }
                return new NameColor(J.Str(j["name"]), col, fade, icon);
            }
            case BlockType.MenuBar:
            {
                if (J.Arr(j["titles"]) is not { } list) return null;
                var titles = list.Select(J.Str).ToList();
                return titles.Any(t => t is null) ? null : new MenuBar(titles!);
            }
            case BlockType.MenuAX:
            {
                if (J.Arr(j["titles"]) is not { } list) return null;
                var titles = list.Select(J.Str).OfType<string>().ToList();
                var fallback = new List<ClickTarget>();
                foreach (var v in J.Arr(j["fallback"]) ?? new JsonArray())
                {
                    if (ClickTarget.FromJson(v) is not { } t) return null;
                    fallback.Add(t);
                }
                return new MenuAX(titles, fallback);
            }
            case BlockType.IfElse:
                return Condition.FromJson(j["condition"]) is { } c && List("then") is { } then ? new IfElse(c, then, List("else") ?? new List<Block>()) : null;
            case BlockType.RepeatCount:
                return J.Int(j["count"]) is { } n && List("blocks") is { } body ? new RepeatCount(n, body) : null;
            case BlockType.RepeatWhile:
                return Condition.FromJson(j["condition"]) is { } wc && J.Int(j["maxIterations"]) is { } max && List("blocks") is { } wbody
                    ? new RepeatWhile(wc, max, wbody) : null;
            case BlockType.WaitUntil:
                return Condition.FromJson(j["condition"]) is { } uc && J.Int(j["timeoutMs"]) is { } ut ? new WaitUntil(uc, ut) : null;
            case BlockType.SetVariable:
                return J.Str(j["variable"]) is { } name && IntSource.FromJson(j["value"]) is { } sv ? new SetVariable(name, sv) : null;
            case BlockType.Stop:
                return new Stop(J.Str(j["message"]));
            case BlockType.Comment:
                return new Comment(J.Str(j["text"]) ?? "");
            default:
                return null;
        }
    }
}

// ---------- Paramètres ----------

/// Touche du Mac : code de touche (disposition QWERTY physique) et modificateurs ⌘ ⌥ ⌃ ⇧.
public readonly record struct MacKey(ushort KeyCode, bool Command = false, bool Option = false, bool Control = false, bool Shift = false)
{
    public static MacKey? FromJson(JsonNode? n)
    {
        if (J.Obj(n) is not { } o || J.Int(o["keyCode"]) is not { } code || code < 0 || code > ushort.MaxValue) return null;
        return new MacKey((ushort)code, J.Bool(o["command"]) ?? false, J.Bool(o["option"]) ?? false,
            J.Bool(o["control"]) ?? false, J.Bool(o["shift"]) ?? false);
    }

    public JsonObject ToJson()
    {
        var o = new JsonObject { ["keyCode"] = KeyCode };
        if (Command) o["command"] = true;
        if (Option) o["option"] = true;
        if (Control) o["control"] = true;
        if (Shift) o["shift"] = true;
        return o;
    }
}

/// Touche portable : code du Mac + caractère (la touche envoyée sur Windows en est déduite : MacKeys).
public sealed record KeyRef(MacKey Combo, string? Char = null)
{
    public static KeyRef? FromJson(JsonNode? n) =>
        J.Obj(n) is { } o && MacKey.FromJson(o["combo"]) is { } combo ? new KeyRef(combo, J.Str(o["char"])) : null;

    public JsonObject ToJson()
    {
        var o = new JsonObject { ["combo"] = Combo.ToJson() };
        if (Char is not null) o["char"] = Char;
        return o;
    }
}

/// Entrée après la dernière lettre d'un menu de FL.
public sealed record EnterPolicy(string Mode, string? LegacyKey = null)
{
    /// Apprise au premier passage, retenue sous une clé historique (liste blanche : validation).
    public static EnterPolicy Learned(string key) => new("learned", key);
    /// Toujours (après une courte attente, seulement si les menus restent ouverts).
    public static EnterPolicy Always => new("always");
    /// Seulement si les menus restent ouverts après la lettre.
    public static EnterPolicy IfNeeded => new("ifNeeded");
    /// Jamais (les lettres ne font que naviguer).
    public static EnterPolicy Never => new("never");

    public static EnterPolicy? FromJson(JsonNode? n) => J.Str(J.Obj(n)?["mode"]) switch
    {
        "learned" => J.Str(n!["key"]) is { } key ? Learned(key) : null,
        "always" => Always,
        "ifNeeded" => IfNeeded,
        "never" => Never,
        _ => null,
    };

    public JsonObject ToJson()
    {
        var o = new JsonObject { ["mode"] = Mode };
        if (Mode == "learned") o["key"] = LegacyKey ?? "";
        return o;
    }
}

public enum MenuKey { Up, Down, Left, Right, Enter, Escape }

public static class MenuKeys
{
    public static string Raw(this MenuKey k) => SoundFamilies.Lower(k.ToString());
    public static MenuKey? FromRaw(string? raw) => Enum.GetValues<MenuKey>().Cast<MenuKey?>().FirstOrDefault(k => k!.Value.Raw() == raw);

    /// La touche Windows.
    public static ushort Vk(this MenuKey k) => k switch
    {
        MenuKey.Up => Core.Vk.Up,
        MenuKey.Down => Core.Vk.Down,
        MenuKey.Left => Core.Vk.Left,
        MenuKey.Right => Core.Vk.Right,
        MenuKey.Enter => Core.Vk.Return,
        _ => Core.Vk.Escape,
    };

    public static string Symbol(this MenuKey k) => k switch
    {
        MenuKey.Up => "↑",
        MenuKey.Down => "↓",
        MenuKey.Left => "←",
        MenuKey.Right => "→",
        MenuKey.Enter => Loc.T("Entrée"),
        _ => Loc.T("Échap"),
    };
}

public enum MouseButton { Left, Right }

public enum WindowKind { Dialog, Menu }

public static class WindowKinds
{
    public static string Raw(this WindowKind k) => k == WindowKind.Menu ? "menu" : "dialog";
    public static WindowKind? FromRaw(string? raw) => raw switch { "dialog" => WindowKind.Dialog, "menu" => WindowKind.Menu, _ => null };
}

public enum TrackTarget
{
    /// Dernière piste cliquée dans FL, sinon le curseur au démarrage.
    LastClicked,
    /// Curseur au démarrage de la macro.
    Cursor,
}

/// Les pages de FL qu'un bloc met devant.
public enum FlPage { Playlist, ChannelRack, PianoRoll, Mixer, Browser }

public static class FlPages
{
    public static string Raw(this FlPage p) => p switch
    {
        FlPage.Playlist => "playlist",
        FlPage.ChannelRack => "channelRack",
        FlPage.PianoRoll => "pianoRoll",
        FlPage.Mixer => "mixer",
        _ => "browser",
    };

    public static FlPage? FromRaw(string? raw) => Enum.GetValues<FlPage>().Cast<FlPage?>().FirstOrDefault(p => p!.Value.Raw() == raw);

    public static string Title(this FlPage p) => p switch
    {
        FlPage.Playlist => Loc.T("Playlist"),
        FlPage.ChannelRack => Loc.T("Channel Rack"),
        FlPage.PianoRoll => Loc.T("Piano Roll"),
        FlPage.Mixer => Loc.T("Mixer"),
        _ => Loc.T("Browser"),
    };

    /// Action du script de FL qui la met devant (PROTOCOL.md §6).
    public static string ActionKey(this FlPage p) => p switch
    {
        FlPage.Playlist => "pl",
        FlPage.ChannelRack => "cr",
        FlPage.PianoRoll => "pr",
        FlPage.Mixer => "mx",
        _ => "br",
    };

    /// Page devant selon le lien avec FL.
    public static FlWindow Window(this FlPage p) => p switch
    {
        FlPage.Playlist => FlWindow.Playlist,
        FlPage.ChannelRack => FlWindow.ChannelRack,
        FlPage.PianoRoll => FlWindow.PianoRoll,
        FlPage.Mixer => FlWindow.Mixer,
        _ => FlWindow.Browser,
    };
}

/// Sans lien avec FL : ce que fait le bloc « Action de FL ».
public sealed record ActionFallback(string Kind, KeyRef? KeyRef = null)
{
    /// Rien : le bloc échoue (« ce bloc a besoin du lien avec FL »).
    public static ActionFallback None => new("none");
    /// Menu de la piste › S › ← › ↓×5 › Entrée = « Arm selected track(s) » (n'éteint jamais).
    public static ActionFallback TrackMenuArm => new("trackMenuArm");
    /// Une touche de FL (REC : R).
    public static ActionFallback Key(KeyRef key) => new("key", key);

    public static ActionFallback? FromJson(JsonNode? n) => J.Str(J.Obj(n)?["kind"]) switch
    {
        "none" => None,
        "trackMenuArm" => TrackMenuArm,
        "key" => KeyRef.FromJson(n!["key"]) is { } k ? Key(k) : null,
        _ => null,
    };

    public JsonObject ToJson()
    {
        var o = new JsonObject { ["kind"] = Kind };
        if (Kind == "key" && KeyRef is not null) o["key"] = KeyRef.ToJson();
        return o;
    }
}

/// Valeur entière : constante, variable, ou état de FL lu par le lien.
public sealed record IntSource(string Kind, int Value = 0, string? Name = null)
{
    public static IntSource Constant(int v) => new("const", v);
    public static IntSource Variable(string name) => new("variable", Name: name);
    public static IntSource FlState(string query) => new("flState", Name: query);

    public static IntSource? FromJson(JsonNode? n) => J.Str(J.Obj(n)?["kind"]) switch
    {
        "const" => J.Int(n!["value"]) is { } v ? Constant(v) : null,
        "variable" => J.Str(n!["name"]) is { } name ? Variable(name) : null,
        "flState" => J.Str(n!["query"]) is { } q ? FlState(q) : null,
        _ => null,
    };

    public JsonObject ToJson() => Kind switch
    {
        "const" => new JsonObject { ["kind"] = "const", ["value"] = Value },
        "variable" => new JsonObject { ["kind"] = "variable", ["name"] = Name },
        _ => new JsonObject { ["kind"] = "flState", ["query"] = Name },
    };
}

/// Positions apprises d'un bloc (clé historique : rien à réapprendre).
public sealed record LearnedRef(string Key)
{
    public static LearnedRef? FromJson(JsonNode? n) =>
        J.Str(J.Obj(n)?["kind"]) == "legacy" && J.Str(n!["key"]) is { } key ? new LearnedRef(key) : null;

    public JsonObject ToJson() => new() { ["kind"] = "legacy", ["key"] = Key };
}

public enum CompareOp { Eq, Ne, Lt, Le, Gt, Ge }

public static class CompareOps
{
    public static string Raw(this CompareOp op) => SoundFamilies.Lower(op.ToString());
    public static CompareOp? FromRaw(string? raw) => Enum.GetValues<CompareOp>().Cast<CompareOp?>().FirstOrDefault(o => o!.Value.Raw() == raw);

    public static bool Holds(this CompareOp op, int a, int b) => op switch
    {
        CompareOp.Eq => a == b,
        CompareOp.Ne => a != b,
        CompareOp.Lt => a < b,
        CompareOp.Le => a <= b,
        CompareOp.Gt => a > b,
        _ => a >= b,
    };

    public static string Symbol(this CompareOp op) => op switch
    {
        CompareOp.Eq => "=",
        CompareOp.Ne => "≠",
        CompareOp.Lt => "<",
        CompareOp.Le => "≤",
        CompareOp.Gt => ">",
        _ => "≥",
    };
}

public abstract record Condition
{
    /// Local, sans MIDI.
    public sealed record WindowOpen(WindowKind Window) : Condition;
    /// Lien MIDI.
    public sealed record FlState(string Query, CompareOp Op, int Value) : Condition;
    public sealed record Variable(string Name, CompareOp Op, int Value) : Condition;
    /// Utile avec « continuer si ça échoue ».
    public sealed record LastBlockFailed : Condition;
    public sealed record Not(Condition Inner) : Condition;
    public sealed record All(IReadOnlyList<Condition> List) : Condition;
    public sealed record Any(IReadOnlyList<Condition> List) : Condition;

    public const int MaxParseDepth = 8;

    public static Condition? FromJson(JsonNode? json, int depth = 0)
    {
        if (J.Obj(json) is not { } o || depth >= MaxParseDepth) return null;
        List<Condition>? Many()
        {
            if (J.Arr(o["conditions"]) is not { } a) return null;
            var list = new List<Condition>();
            foreach (var v in a)
            {
                if (FromJson(v, depth + 1) is not { } c) return null;
                list.Add(c);
            }
            return list;
        }
        switch (J.Str(o["type"]))
        {
            case "windowOpen":
                return WindowKinds.FromRaw(J.Str(o["window"])) is { } kind ? new WindowOpen(kind) : null;
            case "flState":
                return J.Str(o["query"]) is { } q && CompareOps.FromRaw(J.Str(o["op"])) is { } op && J.Int(o["value"]) is { } v
                    ? new FlState(q, op, v) : null;
            case "variable":
                return J.Str(o["name"]) is { } name && CompareOps.FromRaw(J.Str(o["op"])) is { } vop && J.Int(o["value"]) is { } vv
                    ? new Variable(name, vop, vv) : null;
            case "lastBlockFailed":
                return new LastBlockFailed();
            case "not":
                return FromJson(o["condition"], depth + 1) is { } inner ? new Not(inner) : null;
            case "all":
                return Many() is { } all ? new All(all) : null;
            case "any":
                return Many() is { } any ? new Any(any) : null;
            default:
                return null;
        }
    }

    public JsonObject ToJson() => this switch
    {
        WindowOpen w => new JsonObject { ["type"] = "windowOpen", ["window"] = w.Window.Raw() },
        FlState f => new JsonObject { ["type"] = "flState", ["query"] = f.Query, ["op"] = f.Op.Raw(), ["value"] = f.Value },
        Variable v => new JsonObject { ["type"] = "variable", ["name"] = v.Name, ["op"] = v.Op.Raw(), ["value"] = v.Value },
        LastBlockFailed => new JsonObject { ["type"] = "lastBlockFailed" },
        Not n => new JsonObject { ["type"] = "not", ["condition"] = n.Inner.ToJson() },
        All a => new JsonObject { ["type"] = "all", ["conditions"] = new JsonArray(a.List.Select(c => (JsonNode)c.ToJson()).ToArray()) },
        Any a => new JsonObject { ["type"] = "any", ["conditions"] = new JsonArray(a.List.Select(c => (JsonNode)c.ToJson()).ToArray()) },
        _ => new JsonObject(),
    };
}

public enum Corner { TopLeft, TopRight, BottomLeft, BottomRight }

public static class Corners
{
    public static string Raw(this Corner c) => c switch
    {
        Corner.TopLeft => "topLeft",
        Corner.TopRight => "topRight",
        Corner.BottomLeft => "bottomLeft",
        _ => "bottomRight",
    };

    public static Corner? FromRaw(string? raw) => Enum.GetValues<Corner>().Cast<Corner?>().FirstOrDefault(c => c!.Value.Raw() == raw);
}

/// Taille en points (largeur, hauteur).
public readonly record struct Size2(double Width, double Height)
{
    public bool IsPlausible => double.IsFinite(Width) && double.IsFinite(Height) && Width > 0 && Height > 0 && Width <= 10_000 && Height <= 10_000;

    public static Size2? FromJson(JsonNode? n) =>
        J.Arr(n) is { Count: 2 } a && J.Num(a[0]) is { } w && J.Num(a[1]) is { } h ? new Size2(w, h) : null;

    public JsonArray ToJson() => new(J.Number(Width), J.Number(Height));
}

/// Bouton retrouvé à son nom (« FILE », « Insert 1 ») : le texte lu, où tombait le clic par rapport à lui, et sa place.
public sealed record NamedSpot(string Label, double Dx, double Dy, Corner Corner, double Px, double Py, Size2 Size, string? Title = null)
{
    public ClickTarget Place => new ClickTarget.FlWindowPoint(Corner, Px, Py, Size, Title);

    public bool IsValid
    {
        get
        {
            static bool Ok(double v) => double.IsFinite(v) && Math.Abs(v) <= 5000;
            return TextLook.IsUsable(Label) && Ok(Dx) && Ok(Dy) && Math.Abs(Dx) <= 200 && Math.Abs(Dy) <= 200 && Ok(Px) && Ok(Py)
                   && Size.IsPlausible && (Title is null || (Title.Length > 0 && Title.Length <= ClickTarget.MaxTitle));
        }
    }
}

/// Bouton retrouvé à son image : sa place et son image (niveaux de gris, carré de `Side` points).
public sealed record VisualSpot(Corner Corner, double Dx, double Dy, Size2 Size, string? Title, int Side, byte[] Pixels)
{
    public const int MinSide = 12, MaxSide = 64, DefaultSide = 26;

    public ClickTarget Place => new ClickTarget.FlWindowPoint(Corner, Dx, Dy, Size, Title);

    public bool IsValid =>
        double.IsFinite(Dx) && double.IsFinite(Dy) && Math.Abs(Dx) <= 5000 && Math.Abs(Dy) <= 5000 && Size.IsPlausible
        && Side >= MinSide && Side <= MaxSide && Pixels.Length == Side * Side
        && (Title is null || (Title.Length > 0 && Title.Length <= ClickTarget.MaxTitle));

    public bool Equals(VisualSpot? other) =>
        other is not null && Corner == other.Corner && Dx == other.Dx && Dy == other.Dy && Size == other.Size && Title == other.Title
        && Side == other.Side && Pixels.AsSpan().SequenceEqual(other.Pixels);

    public override int GetHashCode() => HashCode.Combine(Corner, Dx, Dy, Size, Title, Side, Pixels.Length);
}

/// Un clic dans un menu que FL a ouvert, relatif au coin haut-gauche de ce menu (indépendant de l'endroit où FL l'a placé).
public readonly record struct PopupHop(double OffsetX, double OffsetY, Size2 Size)
{
    /// Même menu qu'à l'apprentissage : même hauteur (lignes), largeur assez libre.
    public bool Fits(double width, double height) =>
        Math.Abs(height - Size.Height) <= 3 && width >= Size.Width * 0.5 && width <= Size.Width * 2.5 && OffsetY >= 1 && OffsetY <= height - 1;

    public (double X, double Y) Point(double left, double top, double width) => (left + Math.Min(Math.Max(OffsetX, 8), width - 8), top + OffsetY);
}

/// Où cliquer, retrouvé à chaque exécution (jamais un point absolu de l'écran).
public abstract record ClickTarget
{
    /// Coin d'une fenêtre de FL. Taille retenue : la fenêtre de cette taille ; sans taille : celle sous le curseur au
    /// démarrage. Titre : fenêtre d'un plugin, reconnue à son nom parmi plusieurs de la même taille.
    public sealed record FlWindowPoint(Corner Corner, double Dx, double Dy, Size2? Size, string? Title = null) : ClickTarget;
    /// Relatif au dernier menu de FL ouvert.
    public sealed record OpenMenu(PopupHop Hop) : ClickTarget;
    /// Bouton de FL qui peut bouger, cherché à son image au moment du clic.
    public sealed record Button(VisualSpot Spot) : ClickTarget;
    /// Bouton de FL qui porte un nom, cherché par ce nom au moment du clic.
    public sealed record Named(NamedSpot Spot) : ClickTarget;
    /// Depuis la piste visée.
    public sealed record Track(double Dx, double Dy) : ClickTarget;
    public sealed record LastClick(double Dx, double Dy) : ClickTarget;
    public sealed record StartCursor(double Dx, double Dy) : ClickTarget;
    /// x depuis le curseur, y depuis le haut de la fenêtre de FL.
    public sealed record CursorXWindowY(double Dx, double Dy) : ClickTarget;
    /// Position encore à montrer dans FL. La macro est bloquée.
    public sealed record ToLearn : ClickTarget;

    /// Longueur maximale du titre d'une fenêtre de plugin retenu.
    public const int MaxTitle = 120;

    /// Décalages finis et bornés (±5000), taille plausible, titre court.
    public bool IsFinite
    {
        get
        {
            static bool Ok(double v) => double.IsFinite(v) && Math.Abs(v) <= 5000;
            return this switch
            {
                FlWindowPoint w => Ok(w.Dx) && Ok(w.Dy) && (w.Size is not { } s || s.IsPlausible)
                                   && (w.Title is null || (w.Title.Length > 0 && w.Title.Length <= MaxTitle && w.Size is not null)),
                OpenMenu m => Ok(m.Hop.OffsetX) && Ok(m.Hop.OffsetY) && m.Hop.Size.Width >= 16 && m.Hop.Size.Width <= 2000
                              && m.Hop.Size.Height >= 16 && m.Hop.Size.Height <= 4000,
                Button b => b.Spot.IsValid,
                Named n => n.Spot.IsValid,
                Track t => Ok(t.Dx) && Ok(t.Dy),
                LastClick l => Ok(l.Dx) && Ok(l.Dy),
                StartCursor s => Ok(s.Dx) && Ok(s.Dy),
                CursorXWindowY c => Ok(c.Dx) && Ok(c.Dy),
                _ => true,
            };
        }
    }

    /// Position apprise en montrant le clic dans FL (retirée à l'export : propre à cette machine).
    public bool IsLearnedPosition => this is FlWindowPoint or OpenMenu or Button or Named or CursorXWindowY;

    /// Relatif à la piste visée (la macro demande une piste cliquée avant le raccourci).
    public bool IsTrack => this is Track;

    public static ClickTarget? FromJson(JsonNode? json)
    {
        if (J.Obj(json) is not { } o) return null;
        var dx = J.Num(o["dx"]) ?? 0;
        var dy = J.Num(o["dy"]) ?? 0;
        // Clé présente mais illisible (titre non texte, taille hors format) : illisible.
        bool OptionalTitle(out string? title)
        {
            title = J.Str(o["title"]);
            return o["title"] is null || title is not null;
        }
        switch (J.Str(o["anchor"]))
        {
            case "flWindow":
            {
                if (Corners.FromRaw(J.Str(o["corner"])) is not { } corner) return null;
                var size = Size2.FromJson(o["size"]);
                if (o["size"] is not null && size is null) return null;
                if (!OptionalTitle(out var title)) return null;
                return new FlWindowPoint(corner, dx, dy, size, title);
            }
            case "openMenu":
                return Size2.FromJson(o["offset"]) is { } offset && Size2.FromJson(o["size"]) is { } menuSize
                    ? new OpenMenu(new PopupHop(offset.Width, offset.Height, menuSize)) : null;
            case "button":
            {
                if (Corners.FromRaw(J.Str(o["corner"])) is not { } corner || Size2.FromJson(o["size"]) is not { } s
                    || J.Int(o["side"]) is not { } side || side < VisualSpot.MinSide || side > VisualSpot.MaxSide
                    || J.Str(o["pixels"]) is not { } encoded || !OptionalTitle(out var title)) return null;
                byte[] pixels;
                try { pixels = Convert.FromBase64String(encoded); }
                catch (FormatException) { return null; }
                var spot = new VisualSpot(corner, dx, dy, s, title, side, pixels);
                return spot.IsValid ? new Button(spot) : null;
            }
            case "named":
            {
                if (J.Str(o["label"]) is not { } label || Corners.FromRaw(J.Str(o["corner"])) is not { } corner
                    || Size2.FromJson(o["size"]) is not { } s || J.Num(o["px"]) is not { } px || J.Num(o["py"]) is not { } py
                    || !OptionalTitle(out var title)) return null;
                var spot = new NamedSpot(label, dx, dy, corner, px, py, s, title);
                return spot.IsValid ? new Named(spot) : null;
            }
            case "track": return new Track(dx, dy);
            case "lastClick": return new LastClick(dx, dy);
            case "startCursor": return new StartCursor(dx, dy);
            case "cursorXWindowY": return new CursorXWindowY(dx, dy);
            case "toLearn": return new ToLearn();
            default: return null;
        }
    }

    public JsonObject ToJson()
    {
        JsonObject Offset(string anchor, double dx, double dy) => new() { ["anchor"] = anchor, ["dx"] = J.Number(dx), ["dy"] = J.Number(dy) };
        switch (this)
        {
            case FlWindowPoint w:
            {
                var o = new JsonObject { ["anchor"] = "flWindow", ["corner"] = w.Corner.Raw(), ["dx"] = J.Number(w.Dx), ["dy"] = J.Number(w.Dy) };
                if (w.Size is { } size) o["size"] = size.ToJson();
                if (w.Title is not null) o["title"] = w.Title;
                return o;
            }
            case OpenMenu m:
                return new JsonObject
                {
                    ["anchor"] = "openMenu", ["offset"] = new JsonArray(J.Number(m.Hop.OffsetX), J.Number(m.Hop.OffsetY)),
                    ["size"] = m.Hop.Size.ToJson(),
                };
            case Button b:
            {
                var o = new JsonObject
                {
                    ["anchor"] = "button", ["corner"] = b.Spot.Corner.Raw(), ["dx"] = J.Number(b.Spot.Dx), ["dy"] = J.Number(b.Spot.Dy),
                    ["size"] = b.Spot.Size.ToJson(), ["side"] = b.Spot.Side, ["pixels"] = Convert.ToBase64String(b.Spot.Pixels),
                };
                if (b.Spot.Title is not null) o["title"] = b.Spot.Title;
                return o;
            }
            case Named n:
            {
                var o = new JsonObject
                {
                    ["anchor"] = "named", ["label"] = n.Spot.Label, ["dx"] = J.Number(n.Spot.Dx), ["dy"] = J.Number(n.Spot.Dy),
                    ["corner"] = n.Spot.Corner.Raw(), ["px"] = J.Number(n.Spot.Px), ["py"] = J.Number(n.Spot.Py), ["size"] = n.Spot.Size.ToJson(),
                };
                if (n.Spot.Title is not null) o["title"] = n.Spot.Title;
                return o;
            }
            case Track t: return Offset("track", t.Dx, t.Dy);
            case LastClick l: return Offset("lastClick", l.Dx, l.Dy);
            case StartCursor s: return Offset("startCursor", s.Dx, s.Dy);
            case CursorXWindowY c: return Offset("cursorXWindowY", c.Dx, c.Dy);
            default: return new JsonObject { ["anchor"] = "toLearn" };
        }
    }
}

/// Textes des fenêtres de FL lus pour retrouver un bouton à son nom (règles pures, communes au Mac).
public static class TextLook
{
    /// Nom qu'on peut retenir : 2 à 40 caractères, au moins une lettre, et pas un affichage de valeur qui change avec
    /// le clic (« Device : X », « Mixer - Insert 3 », « ● REC »).
    public static bool IsUsable(string text)
    {
        var t = text.Trim();
        return t.Length is >= 2 and <= 40 && t.Any(char.IsLetter) && !t.Any(c => ":•●○◉".Contains(c))
               && !t.Contains(" - ") && !t.Contains(" – ");
    }
}
