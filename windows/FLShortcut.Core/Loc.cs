// Langue de l'app : français par défaut, anglais pour un Windows réglé dans une autre langue que le français (comme le
// Mac : Info.plist, CFBundleDevelopmentRegion). Les clés sont les textes français tels que le Mac les écrit
// (« Écoute %lld sur %lld ») : la traduction anglaise est celle du Mac (Resources/en.lproj, embarquée), plus celle des
// textes propres à Windows (windows/FLShortcut.Core/en-windows.strings), écrite par scripts/localisation.py.
using System.Globalization;
using System.Reflection;
using System.Text;

namespace FLShortcut.Core;

public static class Loc
{
    private static readonly Lazy<Dictionary<string, string>> Table = new(Load);

    /// Anglais : Windows réglé dans une autre langue que le français. Modifiable (tests, mode capture).
    public static bool English { get; set; } =
        !string.Equals(CultureInfo.CurrentUICulture.TwoLetterISOLanguageName, "fr", StringComparison.OrdinalIgnoreCase);

    /// Le texte dans la langue de l'app.
    public static string T(string key) => English && Table.Value.TryGetValue(key, out var en) ? en : key;

    /// Texte avec des valeurs : `%@` (texte), `%lld` / `%d` (nombre), `%1$@` (dans l'ordre donné), `%%`.
    public static string F(string key, params object?[] args) => Format(T(key), args);

    /// La clé a-t-elle sa traduction anglaise ? (tests : aucun texte de l'app sans anglais).
    public static bool Has(string key) => Table.Value.ContainsKey(key);

    /// Pur (testé) : les valeurs mises à la place des `%…` (à la manière de `String(format:)` du Mac).
    public static string Format(string format, params object?[] args)
    {
        var sb = new StringBuilder(format.Length + 16);
        var next = 0;
        for (var i = 0; i < format.Length; i++)
        {
            var c = format[i];
            if (c != '%' || i + 1 >= format.Length) { sb.Append(c); continue; }
            if (format[i + 1] == '%') { sb.Append('%'); i++; continue; }
            var j = i + 1;
            int? position = null;
            var digits = j;
            while (digits < format.Length && char.IsDigit(format[digits])) digits++;
            if (digits > j && digits < format.Length && format[digits] == '$')
            {
                position = int.Parse(format.AsSpan(j, digits - j), CultureInfo.InvariantCulture) - 1;
                j = digits + 1;
            }
            // Précision (« %.1f ») et longueur (« l », « ll », « h », « z »).
            int? precision = null;
            if (j < format.Length && format[j] == '.')
            {
                var p = j + 1;
                while (p < format.Length && char.IsDigit(format[p])) p++;
                precision = p > j + 1 ? int.Parse(format.AsSpan(j + 1, p - j - 1), CultureInfo.InvariantCulture) : 0;
                j = p;
            }
            while (j < format.Length && "lhzqjt".Contains(format[j])) j++;
            if (j >= format.Length || !"@dDiuUxXfFeEgGs".Contains(format[j])) { sb.Append(c); continue; }
            var index = position ?? next++;
            var value = index >= 0 && index < args.Length ? args[index] : null;
            sb.Append(Render(value, format[j], precision));
            i = j;
        }
        return sb.ToString();
    }

    private static string Render(object? value, char kind, int? precision)
    {
        switch (kind)
        {
            case 'f' or 'F' or 'e' or 'E' or 'g' or 'G':
                var d = Convert.ToDouble(value ?? 0, CultureInfo.InvariantCulture);
                return d.ToString("F" + (precision ?? 6), CultureInfo.InvariantCulture);
            case 'x':
                return Convert.ToInt64(value ?? 0, CultureInfo.InvariantCulture).ToString("x", CultureInfo.InvariantCulture);
            case 'X':
                return Convert.ToInt64(value ?? 0, CultureInfo.InvariantCulture).ToString("X", CultureInfo.InvariantCulture);
            default:
                return value switch
                {
                    null => "",
                    IFormattable f => f.ToString(null, CultureInfo.InvariantCulture),
                    _ => value.ToString() ?? "",
                };
        }
    }

    private static Dictionary<string, string> Load()
    {
        var table = new Dictionary<string, string>(StringComparer.Ordinal);
        var assembly = typeof(Loc).Assembly;
        foreach (var name in new[] { "en.lproj.Localizable.strings", "en-windows.strings" })
        {
            using var stream = assembly.GetManifestResourceStream(name);
            if (stream is null) continue;
            using var reader = new StreamReader(stream, Encoding.UTF8);
            foreach (var (key, value) in Parse(reader.ReadToEnd())) table[key] = value;
        }
        return table;
    }

    /// Pur (testé) : les lignes `"clé" = "valeur";` d'un fichier .strings (commentaires `/* */` et `//` ignorés).
    public static IEnumerable<(string Key, string Value)> Parse(string text)
    {
        var i = 0;
        while (i < text.Length)
        {
            if (char.IsWhiteSpace(text[i]) || text[i] == ';') { i++; continue; }
            if (text[i] == '/' && i + 1 < text.Length && text[i + 1] == '*')
            {
                var end = text.IndexOf("*/", i + 2, StringComparison.Ordinal);
                i = end < 0 ? text.Length : end + 2;
                continue;
            }
            if (text[i] == '/' && i + 1 < text.Length && text[i + 1] == '/')
            {
                var end = text.IndexOf('\n', i);
                i = end < 0 ? text.Length : end + 1;
                continue;
            }
            if (text[i] != '"') { i++; continue; }
            var key = Quoted(text, ref i);
            while (i < text.Length && text[i] != '=' && text[i] != '"') i++;
            if (i < text.Length && text[i] == '=') i++;
            while (i < text.Length && char.IsWhiteSpace(text[i])) i++;
            if (i >= text.Length || text[i] != '"' || key is null) continue;
            var value = Quoted(text, ref i);
            if (value is not null) yield return (key, value);
        }
    }

    private static string? Quoted(string text, ref int i)
    {
        var sb = new StringBuilder();
        i++;                                   // le guillemet ouvrant
        while (i < text.Length)
        {
            var c = text[i];
            if (c == '"') { i++; return sb.ToString(); }
            if (c == '\\' && i + 1 < text.Length)
            {
                var n = text[i + 1];
                switch (n)
                {
                    case 'n': sb.Append('\n'); i += 2; continue;
                    case 't': sb.Append('\t'); i += 2; continue;
                    case 'r': sb.Append('\r'); i += 2; continue;
                    case 'U' or 'u' when i + 5 < text.Length
                        && int.TryParse(text.AsSpan(i + 2, 4), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var code):
                        sb.Append((char)code); i += 6; continue;
                    default: sb.Append(n); i += 2; continue;
                }
            }
            sb.Append(c);
            i++;
        }
        return null;
    }
}
