// Touches des macros : elles sont écrites comme sur le Mac (code de touche de la disposition QWERTY physique, ⌘ ⌥ ⌃ ⇧,
// et le caractère tapé). Sur Windows, la touche envoyée est celle de la même place (lettres : leur caractère d'abord,
// pour un clavier AZERTY), ⌘ devient Ctrl, ⌥ Alt, ⌃ Ctrl, ⇧ Maj — comme les raccourcis de FL d'un système à l'autre.
// Et l'inverse, pour qu'une macro enregistrée sur un PC se rejoue sur un Mac.
namespace FLShortcut.Core.Macros;

public static class MacKeys
{
    /// Code de touche du Mac → touche Windows (position physique, disposition américaine).
    private static readonly Dictionary<ushort, ushort> ToVk = new()
    {
        [0] = Vk.Letter('A'), [1] = Vk.Letter('S'), [2] = Vk.Letter('D'), [3] = Vk.Letter('F'), [4] = Vk.Letter('H'),
        [5] = Vk.Letter('G'), [6] = Vk.Letter('Z'), [7] = Vk.Letter('X'), [8] = Vk.Letter('C'), [9] = Vk.Letter('V'),
        [11] = Vk.Letter('B'), [12] = Vk.Letter('Q'), [13] = Vk.Letter('W'), [14] = Vk.Letter('E'), [15] = Vk.Letter('R'),
        [16] = Vk.Letter('Y'), [17] = Vk.Letter('T'), [31] = Vk.Letter('O'), [32] = Vk.Letter('U'), [34] = Vk.Letter('I'),
        [35] = Vk.Letter('P'), [37] = Vk.Letter('L'), [38] = Vk.Letter('J'), [40] = Vk.Letter('K'), [45] = Vk.Letter('N'),
        [46] = Vk.Letter('M'),
        [18] = Vk.Digit(1), [19] = Vk.Digit(2), [20] = Vk.Digit(3), [21] = Vk.Digit(4), [23] = Vk.Digit(5), [22] = Vk.Digit(6),
        [26] = Vk.Digit(7), [28] = Vk.Digit(8), [25] = Vk.Digit(9), [29] = Vk.Digit(0),
        [24] = 0xBB, [27] = 0xBD, [30] = 0xDD, [33] = 0xDB, [39] = 0xDE, [41] = 0xBA, [42] = 0xDC, [43] = 0xBC, [44] = 0xBF,
        [47] = 0xBE, [50] = 0xC0, [10] = 0xE2,
        [36] = Vk.Return, [48] = Vk.Tab, [49] = Vk.Space, [51] = Vk.Back, [53] = Vk.Escape, [117] = Vk.Delete,
        [115] = Vk.Home, [119] = Vk.End, [116] = Vk.Prior, [121] = Vk.Next, [114] = Vk.Insert,
        [123] = Vk.Left, [124] = Vk.Right, [125] = Vk.Down, [126] = Vk.Up,
        [122] = Vk.F(1), [120] = Vk.F(2), [99] = Vk.F(3), [118] = Vk.F(4), [96] = Vk.F(5), [97] = Vk.F(6), [98] = Vk.F(7),
        [100] = Vk.F(8), [101] = Vk.F(9), [109] = Vk.F(10), [103] = Vk.F(11), [111] = Vk.F(12),
        [82] = Vk.Numpad0, [83] = Vk.Numpad0 + 1, [84] = Vk.Numpad0 + 2, [85] = Vk.Numpad0 + 3, [86] = Vk.Numpad0 + 4,
        [87] = Vk.Numpad0 + 5, [88] = Vk.Numpad0 + 6, [89] = Vk.Numpad0 + 7, [91] = Vk.Numpad0 + 8, [92] = Vk.Numpad0 + 9,
        [65] = Vk.Decimal, [67] = Vk.Multiply, [69] = Vk.Add, [75] = Vk.Divide, [78] = Vk.Subtract, [76] = Vk.Return,
    };

    private static readonly Dictionary<ushort, ushort> FromVk = ToVk
        .Where(kv => kv.Key != 76)                                   // Entrée du pavé : la même touche que Retour
        .GroupBy(kv => kv.Value).ToDictionary(g => g.Key, g => g.First().Key);

    /// La combinaison à envoyer sur Windows ; null : touche sans équivalent.
    public static KeyCombo? ToWindows(KeyRef key)
    {
        ushort? vk = null;
        // Une lettre : son caractère d'abord (le même raccourci sur un clavier AZERTY : ⌘A reste Ctrl+A).
        if (key.Char is { Length: 1 } c && char.IsAsciiLetter(c[0])) vk = Vk.Letter(c[0]);
        else if (ToVk.TryGetValue(key.Combo.KeyCode, out var mapped)) vk = mapped;
        if (vk is null) return null;
        var m = key.Combo;
        return new KeyCombo(vk.Value, Ctrl: m.Command || m.Control, Alt: m.Option, Shift: m.Shift);
    }

    /// La même touche, écrite comme sur le Mac ; null : touche sans équivalent.
    public static KeyRef? FromWindows(KeyCombo combo)
    {
        if (!FromVk.TryGetValue(combo.Vk, out var code)) return null;
        string? ch = combo.Vk is >= Vk.A and <= Vk.A + 25 ? ((char)('a' + combo.Vk - Vk.A)).ToString() : null;
        return new KeyRef(new MacKey(code, Command: combo.Ctrl, Option: combo.Alt, Shift: combo.Shift), ch);
    }
}
