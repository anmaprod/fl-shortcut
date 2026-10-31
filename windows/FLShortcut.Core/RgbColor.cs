// Couleur d'un élément de FL (canal, piste, pattern), comme RGBColor du Mac (Sources/FLShortcut/NameColor.swift).
using System.Globalization;

namespace FLShortcut.Core;

public readonly record struct RgbColor(byte R, byte G, byte B)
{
    /// Accepte « E0453A », « #e0453a » ; refuse toute autre longueur ou tout caractère non hexadécimal.
    public static RgbColor? FromHex(string hex)
    {
        var text = hex.Trim();
        if (text.StartsWith('#')) text = text[1..];
        if (text.Length != 6 || !text.All(Uri.IsHexDigit)) return null;
        var v = uint.Parse(text, NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        return new RgbColor((byte)(v >> 16), (byte)(v >> 8), (byte)v);
    }

    public string Hex => $"{R:X2}{G:X2}{B:X2}";

    /// Couleur à `t` (0 = soi, 1 = `other`) en ligne droite sur chaque composante, arrondie au plus proche comme le
    /// script (`int(a + (b − a) × t + 0,5)`) et comme « Gradient color… » de FL.
    public RgbColor Lerp(RgbColor other, double t)
    {
        var u = Math.Min(Math.Max(t, 0), 1);
        byte Mix(byte a, byte b) => (byte)Math.Min(Math.Max(Math.Floor(a + (b - a) * u + 0.5), 0), 255);
        return new RgbColor(Mix(R, other.R), Mix(G, other.G), Mix(B, other.B));
    }

    public override string ToString() => Hex;
}
