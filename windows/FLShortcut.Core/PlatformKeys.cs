// Traducteur des raccourcis entre Mac et PC (demande du 04/11 : « une sorte d'interpréteur qui modifie le raccourci
// selon le type de pc »). Une touche garde sa PLACE sur le clavier : le code de touche du Mac (place physique) devient
// le code de place du PC (scan code), puis la touche que la disposition du PC (AZERTY, QWERTY…) met à cette place ; ⌘
// devient Ctrl (comme les raccourcis de FL d'un système à l'autre), ⌥ Alt, ⌃ Ctrl, ⇧ Maj. Et l'inverse.
// Profil du Mac (profile.json : {"version":2,"remaps":[…]}) lu et écrit ici ; chaque raccourci venu du Mac garde son
// écriture d'origine (`Shortcut.Mac`) : s'il n'a pas changé sur le PC, il repart à l'identique (⌃ du Mac, page…).
using System.Text.Json;
using System.Text.Json.Nodes;

namespace FLShortcut.Core;

/// Disposition du clavier du PC : quelle touche est à quelle place.
public interface IKeyLayout
{
    ushort? VkForScan(ushort scan);
    ushort? ScanForVk(ushort vk);
}

/// QWERTY américain : la disposition des essais, et le repli si celle du PC ne se lit pas.
public sealed class UsKeyLayout : IKeyLayout
{
    public static readonly UsKeyLayout Shared = new();

    private static readonly Dictionary<ushort, ushort> Vks = new()
    {
        [0x02] = Vk.Digit(1), [0x03] = Vk.Digit(2), [0x04] = Vk.Digit(3), [0x05] = Vk.Digit(4), [0x06] = Vk.Digit(5),
        [0x07] = Vk.Digit(6), [0x08] = Vk.Digit(7), [0x09] = Vk.Digit(8), [0x0A] = Vk.Digit(9), [0x0B] = Vk.Digit(0),
        [0x0C] = 0xBD, [0x0D] = 0xBB,
        [0x10] = Vk.Letter('Q'), [0x11] = Vk.Letter('W'), [0x12] = Vk.Letter('E'), [0x13] = Vk.Letter('R'),
        [0x14] = Vk.Letter('T'), [0x15] = Vk.Letter('Y'), [0x16] = Vk.Letter('U'), [0x17] = Vk.Letter('I'),
        [0x18] = Vk.Letter('O'), [0x19] = Vk.Letter('P'), [0x1A] = 0xDB, [0x1B] = 0xDD,
        [0x1E] = Vk.Letter('A'), [0x1F] = Vk.Letter('S'), [0x20] = Vk.Letter('D'), [0x21] = Vk.Letter('F'),
        [0x22] = Vk.Letter('G'), [0x23] = Vk.Letter('H'), [0x24] = Vk.Letter('J'), [0x25] = Vk.Letter('K'),
        [0x26] = Vk.Letter('L'), [0x27] = 0xBA, [0x28] = 0xDE, [0x29] = 0xC0, [0x2B] = 0xDC,
        [0x2C] = Vk.Letter('Z'), [0x2D] = Vk.Letter('X'), [0x2E] = Vk.Letter('C'), [0x2F] = Vk.Letter('V'),
        [0x30] = Vk.Letter('B'), [0x31] = Vk.Letter('N'), [0x32] = Vk.Letter('M'), [0x33] = 0xBC, [0x34] = 0xBE,
        [0x35] = 0xBF, [0x56] = 0xE2,
    };

    private static readonly Dictionary<ushort, ushort> Scans = Vks.ToDictionary(kv => kv.Value, kv => kv.Key);

    public ushort? VkForScan(ushort scan) => Vks.TryGetValue(scan, out var vk) ? vk : null;
    public ushort? ScanForVk(ushort vk) => Scans.TryGetValue(vk, out var scan) ? scan : null;
}

public static class PlatformKeys
{
    /// Touches qui écrivent quelque chose (lettres, chiffres, ponctuation) : code du Mac → place sur le PC (scan code).
    private static readonly Dictionary<ushort, ushort> CharScan = new()
    {
        [0] = 0x1E, [1] = 0x1F, [2] = 0x20, [3] = 0x21, [4] = 0x23, [5] = 0x22, [6] = 0x2C, [7] = 0x2D, [8] = 0x2E,
        [9] = 0x2F, [11] = 0x30, [12] = 0x10, [13] = 0x11, [14] = 0x12, [15] = 0x13, [16] = 0x15, [17] = 0x14,
        [31] = 0x18, [32] = 0x16, [34] = 0x17, [35] = 0x19, [37] = 0x26, [38] = 0x24, [40] = 0x25, [45] = 0x31,
        [46] = 0x32,
        [18] = 0x02, [19] = 0x03, [20] = 0x04, [21] = 0x05, [23] = 0x06, [22] = 0x07, [26] = 0x08, [28] = 0x09,
        [25] = 0x0A, [29] = 0x0B, [27] = 0x0C, [24] = 0x0D,
        [33] = 0x1A, [30] = 0x1B, [41] = 0x27, [39] = 0x28, [50] = 0x29, [42] = 0x2B, [43] = 0x33, [47] = 0x34,
        [44] = 0x35, [10] = 0x56,
    };

    /// Touches sans caractère (flèches, F1…, Entrée, pavé numérique) : la même touche partout.
    private static readonly Dictionary<ushort, ushort> FixedVk = new()
    {
        [36] = Vk.Return, [76] = Vk.Return, [48] = Vk.Tab, [49] = Vk.Space, [51] = Vk.Back, [53] = Vk.Escape,
        [117] = Vk.Delete, [115] = Vk.Home, [119] = Vk.End, [116] = Vk.Prior, [121] = Vk.Next, [114] = Vk.Insert,
        [123] = Vk.Left, [124] = Vk.Right, [125] = Vk.Down, [126] = Vk.Up,
        [122] = Vk.F(1), [120] = Vk.F(2), [99] = Vk.F(3), [118] = Vk.F(4), [96] = Vk.F(5), [97] = Vk.F(6),
        [98] = Vk.F(7), [100] = Vk.F(8), [101] = Vk.F(9), [109] = Vk.F(10), [103] = Vk.F(11), [111] = Vk.F(12),
        [82] = Vk.Numpad0, [83] = Vk.Numpad0 + 1, [84] = Vk.Numpad0 + 2, [85] = Vk.Numpad0 + 3, [86] = Vk.Numpad0 + 4,
        [87] = Vk.Numpad0 + 5, [88] = Vk.Numpad0 + 6, [89] = Vk.Numpad0 + 7, [91] = Vk.Numpad0 + 8,
        [92] = Vk.Numpad0 + 9, [65] = Vk.Decimal, [67] = Vk.Multiply, [69] = Vk.Add, [75] = Vk.Divide,
        [78] = Vk.Subtract,
        // Boutons de souris (KeyCombo.mouseBase du Mac : 200 + numéro de macOS) : molette, puis les deux du côté.
        [202] = Vk.MButton, [203] = Vk.XButton1, [204] = Vk.XButton2,
    };

    private static readonly Dictionary<ushort, ushort> ScanChar = CharScan.ToDictionary(kv => kv.Value, kv => kv.Key);
    private static readonly Dictionary<ushort, ushort> VkFixed = FixedVk.Where(kv => kv.Key != 76)     // Entrée du pavé
        .ToDictionary(kv => kv.Value, kv => kv.Key);

    /// La touche du Mac sur ce PC ; null : pas d'équivalent.
    public static KeyCombo? MacToPc(MacKeyCombo mac, IKeyLayout layout)
    {
        ushort? vk = FixedVk.TryGetValue(mac.KeyCode, out var fixedVk) ? fixedVk
                   : CharScan.TryGetValue(mac.KeyCode, out var scan) ? layout.VkForScan(scan) : null;
        if (vk is not { } v) return null;
        return new KeyCombo(v, Ctrl: mac.Command || mac.Control, Alt: mac.Option, Shift: mac.Shift);
    }

    /// La touche du PC sur un Mac ; null : pas d'équivalent (touche Windows, touche inconnue).
    public static MacKeyCombo? PcToMac(KeyCombo pc, IKeyLayout layout)
    {
        if (pc.Win) return null;
        ushort? code = VkFixed.TryGetValue(pc.Vk, out var fixedCode) ? fixedCode
                     : layout.ScanForVk(pc.Vk) is { } scan && ScanChar.TryGetValue(scan, out var c) ? c : null;
        if (code is not { } k) return null;
        return new MacKeyCombo(k, Command: pc.Ctrl, Option: pc.Alt, Shift: pc.Shift);
    }
}

/// Touche écrite comme dans le profil du Mac (KeyCombo de Model.swift).
public readonly record struct MacKeyCombo(ushort KeyCode, bool Command = false, bool Option = false, bool Control = false,
                                          bool Shift = false)
{
    public JsonObject ToJson() => new()
    {
        ["keyCode"] = KeyCode, ["command"] = Command, ["option"] = Option, ["control"] = Control, ["shift"] = Shift,
    };

    public static MacKeyCombo? FromJson(JsonNode? n)
    {
        if (n is not JsonObject o || o["keyCode"] is not JsonValue v || !v.TryGetValue<int>(out var code) || code is < 0 or > 0xFFFF)
            return null;
        static bool B(JsonNode? x) => x is JsonValue b && b.TryGetValue<bool>(out var r) && r;
        return new MacKeyCombo((ushort)code, B(o["command"]), B(o["option"]), B(o["control"]), B(o["shift"]));
    }
}

/// Profil du Mac lu et écrit sur Windows (Communauté, sauvegarde du compte).
public static class MacProfile
{
    /// Raccourcis traduits ; `Untranslatable` : touche sans équivalent (raccourci gardé, éteint) ; `Duplicates` :
    /// deux raccourcis du Mac devenus la même touche sur le PC (⌘X et ⌃X → Ctrl+X : le second éteint).
    public sealed record Translated(List<Shortcut> Shortcuts, int Untranslatable, int Duplicates);

    /// Marque gardée sur Windows seulement (jamais envoyée au Mac) : raccourci éteint ici car en double.
    private const string PcOff = "flsPcOff";

    /// Un profil écrit par le Mac (« remaps », touches en « keyCode »), pas un profil de Windows.
    public static bool IsMacProfile(string json)
    {
        try
        {
            var root = JsonNode.Parse(json, documentOptions: new JsonDocumentOptions { MaxDepth = 16 });
            if (root is JsonObject obj) return obj["remaps"] is JsonArray;
            return root is JsonArray a && a.OfType<JsonObject>().Any(r => r["trigger"] is JsonObject t && t["keyCode"] is not null);
        }
        catch (JsonException) { return false; }
    }

    public static Translated FromMac(string json, IKeyLayout layout)
    {
        if (json.Length > ProfileCodec.MaxBytes) throw new FormatException("Fichier trop volumineux pour un profil.");
        JsonNode? root;
        try { root = JsonNode.Parse(json, documentOptions: new JsonDocumentOptions { MaxDepth = 16 }); }
        catch (JsonException e) { throw new FormatException(Loc.T("Profil illisible."), e); }
        var items = root switch
        {
            JsonObject o when o["remaps"] is JsonArray a => a,
            JsonArray a => a,
            _ => throw new FormatException(Loc.T("Profil illisible.")),
        };
        if (items.Count > ProfileCodec.MaxShortcuts) throw new FormatException(Loc.F("Trop de raccourcis : %lld au plus.", ProfileCodec.MaxShortcuts));

        var raws = items.OfType<JsonObject>().ToList();
        var windows = new JsonArray();
        var untranslatable = 0;
        foreach (var raw in raws)
        {
            var (converted, lost) = Convert(raw, layout);
            if (lost) untranslatable++;
            windows.Add(converted);
        }
        var decoded = ProfileCodec.Decode(windows.ToJsonString());
        var list = decoded.Shortcuts.Select((s, i) => s with { Mac = (JsonObject)raws[i].DeepClone() }).ToList();
        // Deux raccourcis du Mac devenus la même touche : le premier garde la touche, les suivants s'éteignent.
        var used = new HashSet<(KeyCombo, ShortcutContext)>();
        var duplicates = 0;
        for (var i = 0; i < list.Count; i++)
        {
            var s = list[i];
            if (!s.Enabled || s.Trigger is not { } t) continue;
            if (!used.Add((t, s.Context)))
            {
                // Éteint ici seulement : il repart allumé vers le Mac tant qu'il n'est pas changé sur le PC.
                var mac = (JsonObject)s.Mac!.DeepClone();
                mac[PcOff] = true;
                list[i] = s with { Enabled = false, Mac = mac };
                duplicates++;
            }
        }
        return new Translated(list, untranslatable, duplicates);
    }

    /// Un raccourci du Mac écrit comme sur Windows (touches traduites) ; `lost` : une touche sans équivalent.
    private static (JsonObject Converted, bool Lost) Convert(JsonObject raw, IKeyLayout layout)
    {
        var w = (JsonObject)raw.DeepClone();
        foreach (var key in new[] { "trigger", "target", "page", "macro" }) w.Remove(key);
        var lost = false;
        if (MacKeyCombo.FromJson(raw["trigger"]) is { } trigger)
        {
            if (PlatformKeys.MacToPc(trigger, layout) is { } pc) w["trigger"] = ProfileCodec.ComboNode(pc);
            else lost = true;
        }
        if (MacKeyCombo.FromJson(raw["target"]) is { } target)
        {
            if (PlatformKeys.MacToPc(target, layout) is { } pc) w["target"] = ProfileCodec.ComboNode(pc);
            else lost = true;
        }
        // Macro d'un ancien profil du Mac (portée par le profil, sans bibliothèque) : pas sur Windows.
        var legacyMacro = J(raw, "kind") == "macro" && raw["macroRef"] is null
                          && J(raw, "unknownAction")?.StartsWith(Shortcut.MacroRefPrefix, StringComparison.Ordinal) != true;
        if (lost || legacyMacro) w["enabled"] = false;
        return (w, lost);
    }

    private static string? J(JsonObject o, string key) => o[key] is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;

    /// Les raccourcis de ce PC écrits comme sur le Mac. Un raccourci venu du Mac et pas changé ici repart tel qu'il
    /// était (même ⌃, même page) ; sinon il est traduit. Touche sans équivalent sur le Mac : raccourci gardé, éteint.
    public static string ToMac(IEnumerable<Shortcut> shortcuts, IKeyLayout layout)
    {
        var remaps = new JsonArray();
        foreach (var s in shortcuts) remaps.Add(ToMacOne(s, layout));
        var root = new JsonObject { ["remaps"] = remaps, ["version"] = 2 };
        return root.ToJsonString(new JsonSerializerOptions { WriteIndented = true });
    }

    private static JsonObject ToMacOne(Shortcut s, IKeyLayout layout)
    {
        if (s.Mac is { } original && Unchanged(s, original, layout))
        {
            var same = (JsonObject)original.DeepClone();
            same.Remove(PcOff);
            return same;
        }
        var o = new JsonObject
        {
            ["id"] = s.Id.ToString().ToUpperInvariant(),
            ["enabled"] = s.Enabled,
            ["context"] = s.Context.Raw(),
            ["kind"] = s.Kind switch { ShortcutKind.Keystroke => "keystroke", ShortcutKind.Macro => "macro", _ => "flAction" },
        };
        if (s.Trigger is { } t)
        {
            if (PlatformKeys.PcToMac(t, layout) is { } mac) o["trigger"] = mac.ToJson();
            else o["enabled"] = false;
        }
        if (s.Kind == ShortcutKind.FlAction && s.ActionId is { } id && FlActions.Info(id) is { } info)
        {
            o["action"] = info.Key;
            o["actionID"] = id;
        }
        if (s.Kind == ShortcutKind.Macro && s.MacroRef is { } r)
        {
            o["macroRef"] = r.ToString().ToUpperInvariant();
            o["unknownAction"] = Shortcut.MacroRefPrefix + r.ToString().ToUpperInvariant();
        }
        else if (s.UnknownAction is not null && !s.UnknownAction.StartsWith(Shortcut.MacroRefPrefix, StringComparison.Ordinal))
        {
            o["unknownAction"] = s.UnknownAction;
        }
        if (s.Kind == ShortcutKind.Keystroke && s.Target is { } tg)
        {
            if (PlatformKeys.PcToMac(tg, layout) is { } mac) o["target"] = mac.ToJson();
            else o["enabled"] = false;
        }
        if (s.Mac?["page"] is JsonValue page) o["page"] = page.DeepClone();       // page du Mac où il a été créé
        return o;
    }

    /// Le raccourci est encore celui que le Mac a donné (traduction de l'original = le raccourci d'aujourd'hui).
    private static bool Unchanged(Shortcut s, JsonObject original, IKeyLayout layout)
    {
        var (converted, _) = Convert(original, layout);
        var decoded = ProfileCodec.Decode(new JsonArray(converted).ToJsonString()).Shortcuts;
        if (decoded.Count != 1) return false;
        var o = decoded[0];
        return o.Id == s.Id && o.Trigger == s.Trigger && o.Target == s.Target && o.Context == s.Context && o.Kind == s.Kind
               && o.ActionId == s.ActionId && o.MacroRef == s.MacroRef && o.UnknownAction == s.UnknownAction
               && (o.Enabled && original[PcOff] is null) == s.Enabled;
    }
}
