// Textes lus dans une fenêtre de FL au moment du clic (menu de FL, bouton retrouvé à son nom) : comparaison tolérante
// et choix de l'élément. Miroir de TextLook (Sources/FLShortcut/MacroVisual.swift). Un texte lu n'est jamais gardé ni
// journalisé (ce peut être le nom d'une piste) : seuls des nombres vont au journal.
using System.Globalization;
using System.Text;

namespace FLShortcut.Core.Macros;

/// Texte lu dans une fenêtre de FL, ou élément d'un menu de FL : son cadre en pixels de l'écran, et s'il est grisé
/// (null : on ne sait pas, texte lu dans l'image).
public readonly record struct TextItem(string Text, int X, int Y, int Width, int Height, bool? Greyed = null)
{
    public int CenterX => X + Width / 2;
    public int CenterY => Y + Height / 2;
}

/// Dernier clic de l'utilisateur dans une fenêtre normale de FL (la piste visée) : le point, la fenêtre et sa taille.
public readonly record struct AimedClick(int X, int Y, long Window, int WindowWidth, int WindowHeight, DateTime At);

public static class MenuText
{
    /// Forme de comparaison : sans « & » (lettre soulignée), sans raccourci (après une tabulation), sans casse ni
    /// accents, sans « … » ni flèche de sous-menu au bout, espaces simples, et les confusions de lecture courantes (0/O,
    /// 1/l/I/|) ramenées à une seule lettre (comme le Mac).
    public static string Normalized(string text)
    {
        var s = text;
        var tab = s.IndexOf('\t');
        if (tab >= 0) s = s[..tab];
        s = s.Replace("&&", "\u0001").Replace("&", "").Replace("\u0001", "&").Replace("…", " ").Replace("...", " ");
        var decomposed = s.Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(decomposed.Length);
        foreach (var c in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(c) == UnicodeCategory.NonSpacingMark) continue;
            sb.Append(char.ToLowerInvariant(c) switch
            {
                '0' => 'o',
                '1' or 'i' or '|' or '!' => 'l',
                var other => other,
            });
        }
        var t = string.Join(' ', sb.ToString().Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        while (t.Length > 0 && (t.EndsWith('.') || t.EndsWith('…') || t.EndsWith('>') || t.EndsWith('▸') || t.EndsWith('►')
                                || t.EndsWith(':')))
            t = t[..^1].TrimEnd();
        return t;
    }

    /// Pur (testé) : l'élément qui porte ce titre. D'abord le même texte (le plus haut, puis le plus à gauche) ; sinon
    /// une ligne qui commence par le titre suivi d'un raccourci (lu sur la même ligne dans l'image), la plus courte ;
    /// sinon, pour un titre de 5 lettres ou plus, une lettre près (lecture de l'image). null : absent.
    public static TextItem? Find(string title, IReadOnlyList<TextItem> items)
    {
        var wanted = Normalized(title);
        if (wanted.Length == 0) return null;
        var forms = items.Select(i => (Item: i, Form: Normalized(i.Text))).Where(p => p.Form.Length > 0).ToList();
        static IEnumerable<(TextItem Item, string Form)> Ordered(IEnumerable<(TextItem Item, string Form)> list) =>
            list.OrderBy(p => p.Item.Y).ThenBy(p => p.Item.X);
        var exact = Ordered(forms.Where(p => p.Form == wanted)).ToList();
        if (exact.Count > 0) return exact[0].Item;
        var prefix = forms.Where(p => p.Form.StartsWith(wanted + " ", StringComparison.Ordinal)
                                      && LooksLikeShortcut(p.Form[(wanted.Length + 1)..]))
            .OrderBy(p => p.Form.Length).ThenBy(p => p.Item.Y).ToList();
        if (prefix.Count > 0) return prefix[0].Item;
        if (wanted.Length < 5) return null;
        var close = Ordered(forms.Where(p => Math.Abs(p.Form.Length - wanted.Length) <= 1 && Distance(p.Form, wanted) <= 1)).ToList();
        return close.Count > 0 ? close[0].Item : null;
    }

    private static readonly HashSet<string> KeyNames = new() { "del", "delete", "lns", "lnsert", "enter", "esc", "space", "tab", "backspace" };

    /// Reste d'une ligne de menu qui ressemble à un raccourci (« ctrl+s », « f5 », « del ») — dans la forme de
    /// comparaison, où « 1 » et « i » sont devenus « l ».
    private static bool LooksLikeShortcut(string rest)
    {
        var r = rest.Trim();
        if (r.Contains('+')) return true;
        if (r.Length is >= 2 and <= 3 && r[0] == 'f' && r[1..].All(c => char.IsDigit(c) || c == 'l')) return true;
        return KeyNames.Contains(r);
    }

    /// Pur (testé) : le nom d'un bouton parmi les textes lus (même texte, à la forme de comparaison près), le plus
    /// proche de (`x`, `y`) s'il y est plusieurs fois (miroir de TextLook.find du Mac).
    public static TextItem? Nearest(string label, IReadOnlyList<TextItem> items, int x, int y)
    {
        var wanted = Normalized(label);
        if (wanted.Length == 0) return null;
        return items.Where(i => Normalized(i.Text) == wanted)
            .OrderBy(i => (long)(i.CenterX - x) * (i.CenterX - x) + (long)(i.CenterY - y) * (i.CenterY - y))
            .Cast<TextItem?>().FirstOrDefault();
    }

    /// Distance d'édition (insertion, suppression, remplacement), bornée aux textes courts des menus.
    public static int Distance(string a, string b)
    {
        if (a.Length > 80 || b.Length > 80) return int.MaxValue;
        var previous = new int[b.Length + 1];
        var current = new int[b.Length + 1];
        for (var j = 0; j <= b.Length; j++) previous[j] = j;
        for (var i = 1; i <= a.Length; i++)
        {
            current[0] = i;
            for (var j = 1; j <= b.Length; j++)
                current[j] = Math.Min(Math.Min(current[j - 1] + 1, previous[j] + 1), previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1));
            (previous, current) = (current, previous);
        }
        return previous[b.Length];
    }
}
