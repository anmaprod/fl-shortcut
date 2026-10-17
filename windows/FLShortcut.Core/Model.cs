// Audit : REL-01 (décodage tolérant élément par élément, actions inconnues conservées et désactivées),
//         REL-20 (une seule analyse pour l'interface et l'index), SEC-05 (validation stricte, import confirmé),
//         audit 05 §6 (profils Recommandé Windows : Ctrl+Maj, jamais Ctrl+Alt ; Style Ableton ; Vide).
// Miroir de Sources/FLShortcut/Model.swift, adapté aux codes de touche virtuelle Windows.
using System.Text.Json;
using System.Text.Json.Nodes;

namespace FLShortcut.Core;

public enum ShortcutContext { Everywhere, PianoRoll, Playlist, Mixer }

public static class ShortcutContexts
{
    public static string Label(this ShortcutContext c) => c switch
    {
        ShortcutContext.PianoRoll => "Piano Roll",
        ShortcutContext.Playlist => "Playlist",
        ShortcutContext.Mixer => "Mixer",
        _ => "Partout",
    };

    public static string Raw(this ShortcutContext c) => c switch
    {
        ShortcutContext.PianoRoll => "pianoRoll",
        ShortcutContext.Playlist => "playlist",
        ShortcutContext.Mixer => "mixer",
        _ => "everywhere",
    };

    public static ShortcutContext? FromRaw(string? raw) => raw switch
    {
        "everywhere" => ShortcutContext.Everywhere,
        "pianoRoll" => ShortcutContext.PianoRoll,
        "playlist" => ShortcutContext.Playlist,
        "mixer" => ShortcutContext.Mixer,
        _ => null,
    };

    public static ShortcutContext? FromWindow(FlWindow w) => w switch
    {
        FlWindow.PianoRoll => ShortcutContext.PianoRoll,
        FlWindow.Playlist => ShortcutContext.Playlist,
        FlWindow.Mixer => ShortcutContext.Mixer,
        _ => null,
    };
}

public enum ShortcutKind { FlAction, Keystroke }

public sealed record Shortcut
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public bool Enabled { get; init; } = true;
    public KeyCombo? Trigger { get; init; }
    public ShortcutContext Context { get; init; } = ShortcutContext.Everywhere;
    public ShortcutKind Kind { get; init; } = ShortcutKind.FlAction;
    /// Id du protocole (PROTOCOL.md §6). null si l'action est inconnue de cette version.
    public int? ActionId { get; init; }
    /// Action illisible conservée telle quelle (profil plus récent relu par une version plus ancienne).
    public string? UnknownAction { get; init; }
    public KeyCombo? Target { get; init; }

    public static Shortcut Action(KeyCombo trigger, int action, ShortcutContext ctx = ShortcutContext.Everywhere) =>
        new() { Trigger = trigger, ActionId = action, Context = ctx };

    public static Shortcut Sends(KeyCombo trigger, KeyCombo target, ShortcutContext ctx = ShortcutContext.Everywhere) =>
        new() { Trigger = trigger, Kind = ShortcutKind.Keystroke, Target = target, Context = ctx };

    public RoutedAction? Routed => Kind switch
    {
        ShortcutKind.FlAction when ActionId is { } id => new RoutedAction.FlAction(id),
        ShortcutKind.Keystroke when Target is { } t => new RoutedAction.Keystroke(t),
        _ => null,
    };

    public string Label => Kind == ShortcutKind.Keystroke
        ? (Target is { } t ? $"Envoie {t}" : "Touche de FL à choisir")
        : (ActionId is { } id && FlActions.Info(id) is { } info ? info.Label : "Action inconnue");
}

public abstract record RoutedAction
{
    public sealed record FlAction(int Id) : RoutedAction;
    public sealed record Keystroke(KeyCombo Target) : RoutedAction;
}

/// Lecture / écriture du profil JSON, tolérante champ par champ (REL-01).
public static class ProfileCodec
{
    public const int FormatVersion = 2;
    public const int MaxShortcuts = 500;
    public const int MaxBytes = 512 * 1024;

    public sealed record Decoded(List<Shortcut> Shortcuts, int Skipped);

    public static Decoded Decode(string json)
    {
        if (json.Length > MaxBytes) throw new FormatException("Fichier trop volumineux pour un profil.");
        JsonNode? root;
        try { root = JsonNode.Parse(json, documentOptions: new JsonDocumentOptions { MaxDepth = 16 }); }
        catch (JsonException e) { throw new FormatException("Profil illisible.", e); }

        var items = root switch
        {
            JsonArray a => a,
            JsonObject o when o["shortcuts"] is JsonArray a2 => a2,
            _ => throw new FormatException("Profil illisible."),
        };
        if (items.Count > MaxShortcuts) throw new FormatException($"Trop de raccourcis ({MaxShortcuts} au maximum).");

        var list = new List<Shortcut>();
        var skipped = 0;
        var ids = new HashSet<Guid>();
        foreach (var node in items)
        {
            if (node is not JsonObject obj) { skipped++; continue; }
            var s = DecodeOne(obj);
            if (!ids.Add(s.Id)) s = s with { Id = Guid.NewGuid() };
            list.Add(s);
        }
        return new Decoded(list, skipped);
    }

    private static Shortcut DecodeOne(JsonObject o)
    {
        var id = TryGuid(o["id"]) ?? Guid.NewGuid();
        var enabled = TryBool(o["enabled"]) ?? true;
        var trigger = TryCombo(o["trigger"]);
        var target = TryCombo(o["target"]);
        var unknown = TryString(o["unknownAction"]);

        var context = ShortcutContext.Everywhere;
        if (TryString(o["context"]) is { } rawCtx)
        {
            if (ShortcutContexts.FromRaw(rawCtx) is { } ctx) context = ctx;
            else enabled = false;
        }

        var rawKind = TryString(o["kind"]);
        ShortcutKind kind;
        if (rawKind is null or "flAction") kind = ShortcutKind.FlAction;
        else if (rawKind == "keystroke") kind = ShortcutKind.Keystroke;
        else
        {
            return new Shortcut
            {
                Id = id, Enabled = false, Trigger = trigger, Context = context, Kind = ShortcutKind.FlAction,
                ActionId = null, UnknownAction = "type:" + rawKind, Target = target,
            };
        }

        int? actionId = null;
        if (kind == ShortcutKind.FlAction)
        {
            var rawId = TryInt(o["actionID"]);
            var rawName = TryString(o["action"]);
            if (rawId is { } n && FlActions.IsKnown(n)) actionId = n;
            else if (rawName is not null && FlActions.IdForKey(rawName) is { } byName) actionId = byName;
            else
            {
                unknown = rawName ?? (rawId is { } x ? $"id:{x}" : unknown ?? "?");
                enabled = false;                    // jamais exécuter une action « devinée »
            }
        }

        return new Shortcut
        {
            Id = id, Enabled = enabled, Trigger = trigger, Context = context, Kind = kind,
            ActionId = actionId, UnknownAction = unknown, Target = kind == ShortcutKind.Keystroke ? target : null,
        };
    }

    public static string Encode(IEnumerable<Shortcut> shortcuts)
    {
        var arr = new JsonArray();
        foreach (var s in shortcuts)
        {
            var o = new JsonObject
            {
                ["id"] = s.Id.ToString(),
                ["enabled"] = s.Enabled,
                ["context"] = s.Context.Raw(),
                ["kind"] = s.Kind == ShortcutKind.Keystroke ? "keystroke" : "flAction",
            };
            if (s.Trigger is { } t) o["trigger"] = ComboNode(t);
            if (s.Kind == ShortcutKind.FlAction && s.ActionId is { } id && FlActions.Info(id) is { } info)
            {
                o["action"] = info.Key;
                o["actionID"] = id;
            }
            if (s.UnknownAction is not null) o["unknownAction"] = s.UnknownAction;
            if (s.Target is { } tg) o["target"] = ComboNode(tg);
            arr.Add(o);
        }
        var root = new JsonObject { ["version"] = FormatVersion, ["platform"] = "windows", ["shortcuts"] = arr };
        return root.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
    }

    private static JsonObject ComboNode(KeyCombo c) => new()
    {
        ["vk"] = c.Vk, ["ctrl"] = c.Ctrl, ["alt"] = c.Alt, ["shift"] = c.Shift, ["win"] = c.Win,
    };

    private static KeyCombo? TryCombo(JsonNode? n)
    {
        if (n is not JsonObject o) return null;
        if (TryInt(o["vk"]) is not { } vk || vk is <= 0 or >= 0xFF) return null;
        return new KeyCombo((ushort)vk, TryBool(o["ctrl"]) ?? false, TryBool(o["alt"]) ?? false,
            TryBool(o["shift"]) ?? false, TryBool(o["win"]) ?? false);
    }

    private static string? TryString(JsonNode? n) =>
        n is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;

    private static bool? TryBool(JsonNode? n) =>
        n is JsonValue v && v.TryGetValue<bool>(out var b) ? b : null;

    private static int? TryInt(JsonNode? n)
    {
        if (n is not JsonValue v) return null;
        if (v.TryGetValue<int>(out var i)) return i;
        if (v.TryGetValue<long>(out var l) && l is >= int.MinValue and <= int.MaxValue) return (int)l;
        return null;
    }

    private static Guid? TryGuid(JsonNode? n) =>
        TryString(n) is { } s && Guid.TryParse(s, out var g) ? g : null;
}

/// Texte venu d'un profil importé, affiché dans l'interface (relecture 11) : sans caractères de contrôle ni de
/// mise en forme invisibles (inversion bidi U+202E, largeur nulle…) qui pourraient maquiller un libellé, et raccourci.
/// TextBlock n'interprète aucun balisage : seul l'aspect est en jeu, jamais l'exécution.
public static class DisplayText
{
    public static string Safe(string? raw, int max = 40)
    {
        if (string.IsNullOrEmpty(raw)) return "";
        var sb = new System.Text.StringBuilder(Math.Min(raw.Length, max) + 1);
        var truncated = false;
        foreach (var ch in raw)
        {
            if (char.IsControl(ch) || char.GetUnicodeCategory(ch) == System.Globalization.UnicodeCategory.Format) continue;
            if (sb.Length >= max) { truncated = true; break; }
            sb.Append(ch);
        }
        // Ne jamais couper une paire de substitution en deux.
        if (truncated && sb.Length > 0 && char.IsHighSurrogate(sb[sb.Length - 1])) sb.Length--;
        if (truncated) sb.Append('…');
        return sb.ToString();
    }
}

public abstract record ShortcutIssue
{
    public sealed record NoTrigger : ShortcutIssue;
    public sealed record NoTarget : ShortcutIssue;
    public sealed record InvalidKey : ShortcutIssue;
    public sealed record UnknownAction(string Raw) : ShortcutIssue;
    public sealed record ForbiddenTarget(string Why) : ShortcutIssue;
    public sealed record ForbiddenTrigger(string Why) : ShortcutIssue;
    public sealed record ReservedToggle : ShortcutIssue;
    public sealed record Duplicate : ShortcutIssue;
    public sealed record BareKey : ShortcutIssue;
    public sealed record WindowsConflict(string What) : ShortcutIssue;
    public sealed record FlConflict(string What) : ShortcutIssue;
    public sealed record Loop : ShortcutIssue;
    public sealed record Unavailable(string Why) : ShortcutIssue;

    public bool IsBlocking => this is NoTrigger or NoTarget or InvalidKey or UnknownAction or ForbiddenTarget
        or ForbiddenTrigger or ReservedToggle or Duplicate;

    public string Message => this switch
    {
        NoTrigger => "Aucun raccourci défini.",
        NoTarget => "Aucune touche de FL choisie.",
        InvalidKey => "Touche non prise en charge.",
        UnknownAction u => $"Action inconnue (« {DisplayText.Safe(u.Raw)} ») : mets à jour FL Shortcuts.",
        ForbiddenTarget f => $"Cible interdite : {f.Why}.",
        ForbiddenTrigger f => $"Raccourci impossible : {f.Why}.",
        ReservedToggle => "Réservé à Ctrl+Alt+Maj+F (mettre FL Shortcuts en pause).",
        Duplicate => "Déjà utilisé dans ce contexte : seul le premier compte.",
        BareKey => "Touche seule : elle ne pourra plus servir à taper du texte dans FL ni à jouer des notes.",
        WindowsConflict w => $"Conflit : {w.What}.",
        FlConflict f => $"Remplace un raccourci natif — {f.What}.",
        Loop => "La touche envoyée est aussi un déclencheur : elle sera envoyée telle quelle, sans enchaînement.",
        Unavailable u => u.Why,
        _ => "",
    };
}

public sealed record AnalysisContext(KeyCombo Toggle, ConflictTable Conflicts, Func<int, ActionAvailability> Availability);

public static class ShortcutAnalyzer
{
    public static Dictionary<Guid, List<ShortcutIssue>> Analyze(IReadOnlyList<Shortcut> shortcuts, AnalysisContext ctx)
    {
        var output = new Dictionary<Guid, List<ShortcutIssue>>();
        var seen = new Dictionary<KeyCombo, HashSet<ShortcutContext>>();
        var activeTriggers = new HashSet<KeyCombo>();

        foreach (var s in shortcuts)
        {
            var list = new List<ShortcutIssue>();
            if (s.Kind == ShortcutKind.FlAction)
            {
                if (s.ActionId is { } id)
                {
                    if (ctx.Availability(id) is ActionAvailability.Unavailable u) list.Add(new ShortcutIssue.Unavailable(u.Reason));
                }
                else list.Add(new ShortcutIssue.UnknownAction(s.UnknownAction ?? "?"));
            }
            else
            {
                if (s.Target is { } t)
                {
                    if (!t.IsValidKey) list.Add(new ShortcutIssue.InvalidKey());
                    else if (ForbiddenTargets.Reason(t) is { } why) list.Add(new ShortcutIssue.ForbiddenTarget(why));
                }
                else list.Add(new ShortcutIssue.NoTarget());
            }

            if (s.Trigger is { } trig)
            {
                if (!trig.IsValidKey) list.Add(new ShortcutIssue.InvalidKey());
                if (trig.Win) list.Add(new ShortcutIssue.ForbiddenTrigger("Win+… est réservé à Windows"));
                if (trig.IsAltGr) list.Add(new ShortcutIssue.ForbiddenTrigger("Ctrl+Alt correspond à AltGr (@, €, {…)"));
                if (trig == ctx.Toggle) list.Add(new ShortcutIssue.ReservedToggle());
                if (!trig.HasModifiers && !Vk.IsFunctionKey(trig.Vk)) list.Add(new ShortcutIssue.BareKey());
                if (ctx.Conflicts.WindowsConflict(trig) is { } w) list.Add(new ShortcutIssue.WindowsConflict(w));
                if (ctx.Conflicts.FlConflict(trig) is { } f) list.Add(new ShortcutIssue.FlConflict(f));
                if (s.Enabled && !list.Any(i => i.IsBlocking))
                {
                    if (seen.TryGetValue(trig, out var ctxs) && ctxs.Contains(s.Context)) list.Add(new ShortcutIssue.Duplicate());
                    else
                    {
                        if (!seen.TryGetValue(trig, out var set)) seen[trig] = set = new HashSet<ShortcutContext>();
                        set.Add(s.Context);
                        activeTriggers.Add(trig);
                    }
                }
            }
            else list.Add(new ShortcutIssue.NoTrigger());
            output[s.Id] = list;
        }

        foreach (var s in shortcuts.Where(s => s.Enabled && s.Kind == ShortcutKind.Keystroke))
        {
            if (s.Target is { } t && activeTriggers.Contains(t) && !output[s.Id].Any(i => i.IsBlocking))
                output[s.Id].Add(new ShortcutIssue.Loop());
        }
        return output;
    }

    public static HashSet<Guid> Blocked(Dictionary<Guid, List<ShortcutIssue>> issues) =>
        issues.Where(kv => kv.Value.Any(i => i.IsBlocking)).Select(kv => kv.Key).ToHashSet();
}

public enum ProfilePreset { Recommended, Ableton, Empty }

public static class ProfilePresets
{
    /// Pause globale : trois modificateurs, rare et difficile à taper par accident (audit 05).
    public static readonly KeyCombo Toggle = new(Vk.Letter('F'), Ctrl: true, Alt: true, Shift: true);

    public static string Label(this ProfilePreset p) => p switch
    {
        ProfilePreset.Recommended => "Recommandé",
        ProfilePreset.Ableton => "Style Ableton",
        _ => "Vide",
    };

    public static string Summary(this ProfilePreset p) => p switch
    {
        ProfilePreset.Recommended => "Ctrl+Maj+1…5 pour les fenêtres, Ctrl+Maj+D/F patterns, Ctrl+Maj+T/G mute/solo, Ctrl+Maj+K métronome, Ctrl+Y rétablir. Rien n'écrase FL.",
        ProfilePreset.Ableton => "Tab, 0 et Ctrl+Maj+←/→ comme dans Ableton. Contient des touches seules.",
        _ => "Aucun raccourci.",
    };

    public static List<Shortcut> Shortcuts(this ProfilePreset p)
    {
        static KeyCombo Cs(ushort vk) => new(vk, Ctrl: true, Shift: true);
        var windows = new[] { 30, 31, 32, 33, 34 };      // Playlist, Channel Rack, Piano Roll, Mixer, Browser
        var redo = Shortcut.Action(new KeyCombo(Vk.Letter('Y'), Ctrl: true), 37);
        switch (p)
        {
            case ProfilePreset.Recommended:
            {
                var list = windows.Select((a, i) => Shortcut.Action(Cs(Vk.Digit(i + 1)), a)).ToList();
                list.Add(Shortcut.Action(Cs(Vk.Letter('D')), 14));   // pattern précédent
                list.Add(Shortcut.Action(Cs(Vk.Letter('F')), 13));   // pattern suivant
                list.Add(Shortcut.Action(Cs(Vk.Letter('T')), 21));   // mute (T = outil mute de FL)
                list.Add(Shortcut.Action(Cs(Vk.Letter('G')), 22));   // solo (Ctrl+Maj+S = « Enregistrer sous » dans FL)
                list.Add(Shortcut.Action(Cs(Vk.Letter('K')), 4));    // métronome (Ctrl+Maj+M = export MIDI dans FL)
                list.Add(redo);
                return list;
            }
            case ProfilePreset.Ableton:
            {
                var list = new List<Shortcut>
                {
                    Shortcut.Action(new KeyCombo(Vk.Tab), 35),
                    Shortcut.Action(new KeyCombo(Vk.D0), 21, ShortcutContext.Mixer),
                    redo,
                    Shortcut.Action(Cs(Vk.Right), 13),
                    Shortcut.Action(Cs(Vk.Left), 14),
                };
                list.AddRange(windows.Select((a, i) => Shortcut.Action(Cs(Vk.Digit(i + 1)), a)));
                return list;
            }
            default:
                return new List<Shortcut>();
        }
    }
}

/// Import d'un profil partagé : validé, résumé, appliqué seulement après confirmation (SEC-05).
public sealed record ImportPreview(List<Shortcut> Shortcuts, int Skipped, int Disabled, List<string> Refused);

public static class ProfileImporter
{
    public static ImportPreview Prepare(string json)
    {
        var decoded = ProfileCodec.Decode(json);
        var refused = new List<string>();
        var list = new List<Shortcut>();
        var disabled = 0;
        foreach (var s in decoded.Shortcuts)
        {
            var item = s with { Id = Guid.NewGuid() };
            if (item.Kind == ShortcutKind.Keystroke && item.Target is { } t && ForbiddenTargets.Reason(t) is { } why)
            {
                refused.Add($"{item.Trigger?.ToString() ?? "?"} → {t} : {why}");
                item = item with { Enabled = false };
            }
            if (item.Trigger is { } trig && (trig.Win || trig.IsAltGr)) item = item with { Enabled = false };
            if (!item.Enabled) disabled++;
            list.Add(item);
        }
        return new ImportPreview(list, decoded.Skipped, disabled, refused);
    }
}

/// Injection de la clé dans le script FL (PROTOCOL.md §2) : l'unique occurrence du marqueur, sur la ligne
/// `KEY_HEX = "__FLSHORTCUT_KEY__"`, est remplacée par 32 caractères hexadécimaux minuscules.
public static class ScriptTemplate
{
    public const string Placeholder = "__FLSHORTCUT_KEY__";
    public const string KeyLine = "KEY_HEX = \"__FLSHORTCUT_KEY__\"";

    public static string Inject(byte[] key, string template)
    {
        if (key.Length != FlProtocol.KeyLength) throw new ArgumentException("La clé doit faire 16 octets.", nameof(key));
        var first = template.IndexOf(Placeholder, StringComparison.Ordinal);
        if (first < 0 || template.IndexOf(Placeholder, first + 1, StringComparison.Ordinal) >= 0)
            throw new FormatException("Le marqueur de clé doit apparaître exactement une fois.");
        var lineStart = template.LastIndexOf('\n', first) + 1;
        var lineEnd = template.IndexOf('\n', first);
        var line = (lineEnd < 0 ? template[lineStart..] : template[lineStart..lineEnd]).TrimEnd('\r');
        if (line != KeyLine) throw new FormatException("Le marqueur de clé n'est pas sur la ligne attendue.");
        return template.Replace(Placeholder, FlProtocol.Hex(key), StringComparison.Ordinal);
    }
}
