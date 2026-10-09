// Combinaisons de touches Windows (codes de touche virtuelle). Audit 05 : Ctrl+Alt interdit (AltGr),
// lettres par étiquette (code VK = lettre de la disposition), chiffres par position (VK_0…VK_9 restent les
// chiffres de la rangée du haut même en AZERTY).
namespace FLShortcut.Core;

public static class Vk
{
    public const ushort Back = 0x08, Tab = 0x09, Return = 0x0D, Shift = 0x10, Control = 0x11, Menu = 0x12,
        Pause = 0x13, Capital = 0x14, Escape = 0x1B, Space = 0x20, Prior = 0x21, Next = 0x22, End = 0x23,
        Home = 0x24, Left = 0x25, Up = 0x26, Right = 0x27, Down = 0x28, Snapshot = 0x2C, Insert = 0x2D,
        Delete = 0x2E, D0 = 0x30, A = 0x41, LWin = 0x5B, RWin = 0x5C, Apps = 0x5D, Numpad0 = 0x60,
        Multiply = 0x6A, Add = 0x6B, Subtract = 0x6D, Decimal = 0x6E, Divide = 0x6F, F1 = 0x70, F24 = 0x87,
        NumLock = 0x90, Scroll = 0x91, LShift = 0xA0, RShift = 0xA1, LControl = 0xA2, RControl = 0xA3,
        LMenu = 0xA4, RMenu = 0xA5;

    public static ushort Letter(char c) => (ushort)(A + (char.ToUpperInvariant(c) - 'A'));
    public static ushort Digit(int d) => (ushort)(D0 + d);
    public static ushort F(int n) => (ushort)(F1 + n - 1);

    public static bool IsModifier(ushort vk) => vk is Shift or Control or Menu or LShift or RShift
        or LControl or RControl or LMenu or RMenu or LWin or RWin or Capital or NumLock or Scroll;

    public static bool IsFunctionKey(ushort vk) => vk is >= F1 and <= F24;

    public static string Name(ushort vk)
    {
        if (vk is >= A and <= A + 25) return ((char)('A' + vk - A)).ToString();
        if (vk is >= D0 and <= D0 + 9) return ((char)('0' + vk - D0)).ToString();
        if (vk is >= Numpad0 and <= Numpad0 + 9) return $"{vk - Numpad0} (pavé)";
        if (IsFunctionKey(vk)) return $"F{vk - F1 + 1}";
        return vk switch
        {
            Back => "Retour arrière", Tab => "Tab", Return => "Entrée", Escape => "Échap", Space => "Espace",
            Prior => "Pg préc.", Next => "Pg suiv.", End => "Fin", Home => "Début", Left => "←", Up => "↑",
            Right => "→", Down => "↓", Insert => "Inser", Delete => "Suppr", Pause => "Pause",
            Multiply => "× (pavé)", Add => "+ (pavé)", Subtract => "− (pavé)", Decimal => ". (pavé)", Divide => "÷ (pavé)",
            0xBA => "OEM 1", 0xBB => "=", 0xBC => ",", 0xBD => "-", 0xBE => ".", 0xBF => "OEM 2", 0xC0 => "OEM 3",
            0xDB => "OEM 4", 0xDC => "OEM 5", 0xDD => "OEM 6", 0xDE => "OEM 7", 0xE2 => "<",
            _ => $"Touche {vk}",
        };
    }
}

public readonly record struct KeyCombo(ushort Vk, bool Ctrl = false, bool Alt = false, bool Shift = false, bool Win = false)
{
    public bool HasModifiers => Ctrl || Alt || Shift || Win;

    /// Ctrl+Alt = AltGr sur les dispositions européennes : jamais un déclencheur (il produit @, €, {…).
    public bool IsAltGr => Ctrl && Alt;

    /// Touche utilisable comme déclencheur ou cible (ni modificateur seul, ni hors plage).
    public bool IsValidKey => Vk is > 0 and < 0xFF && !global::FLShortcut.Core.Vk.IsModifier(Vk);

    public IReadOnlyList<string> Caps
    {
        get
        {
            var list = new List<string>(5);
            if (Ctrl) list.Add("Ctrl");
            if (Alt) list.Add("Alt");
            if (Shift) list.Add("Maj");
            if (Win) list.Add("Win");
            list.Add(global::FLShortcut.Core.Vk.Name(Vk));
            return list;
        }
    }

    public override string ToString() => string.Join(" + ", Caps);
}
