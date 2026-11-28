// Clics « intelligents » de l'enregistrement sur Windows (miroir de SmartClicks, MacroClickSequence.swift du Mac) : un
// clic sur un titre des menus de FL (FILE, EDIT, ADD…) suivi d'un clic dans le menu ouvert devient « Menu de FL › … »,
// ou le raccourci de FL de cet élément, ou l'option de « Cliquer sur… » qui fait la même chose (Add › Channel › … :
// ajouter un instrument) ; le bouton « Arrangement » de la Playlist suivi d'une ligne de son menu : l'option de la
// Playlist. Rien de deviné : les noms lus au clic, un seul chemin possible, sinon les clics restent des clics. Pur et
// testé ; l'enregistreur de l'app (Services/MacroRecorder.cs) lit les menus ouverts au moment du clic.
namespace FLShortcut.Core.Macros;

/// Un menu de FL ouvert au moment d'un clic enregistré : son cadre à l'écran et ses éléments lus (jamais journalisés).
public sealed record MenuSnapshot(int X, int Y, int Width, int Height, IReadOnlyList<TextItem> Items);

public static class SmartClicks
{
    /// Menus de FL dans sa fenêtre (FILE EDIT ADD…), avec le nom anglais que le bloc « Menu de FL » retrouve.
    public static readonly string[] MenuTitles = { "File", "Edit", "Add", "Patterns", "View", "Options", "Tools", "Help" };

    private static string Key(string s) => MenuText.Normalized(s);

    /// Titre d'un menu de FL pour un nom lu dans sa fenêtre (« FILE » → « File ») ; null : pas un titre de menu.
    public static string? MenuTitle(string label) => MenuTitles.FirstOrDefault(t => Key(t) == Key(label));

    /// Bouton « Arrangement » de la Playlist (son nom affiché peut être celui de l'arrangement : « Arrangement 2 »).
    public static bool IsArrangement(string label) => Key(label).StartsWith(Key("Arrangement"), StringComparison.Ordinal);

    /// Texte d'un élément tel que FL l'affiche : sans « & » (lettre soulignée), sans raccourci (après une tabulation),
    /// sans flèche de sous-menu ; « … » gardé (le bloc le retrouve avec ou sans).
    public static string Clean(string text)
    {
        var s = text;
        var tab = s.IndexOf('\t');
        if (tab >= 0) s = s[..tab];
        s = s.Replace("&&", "\u0001").Replace("&", "").Replace("\u0001", "&").Trim();
        while (s.Length > 0 && (s.EndsWith('>') || s.EndsWith('▸') || s.EndsWith('►'))) s = s[..^1].TrimEnd();
        return s;
    }

    /// Pur : les éléments choisis dans les menus ouverts (`menus` : du premier niveau au dernier) pour un clic en (x, y)
    /// dans le dernier : dans chaque menu du dessous, l'élément qui a ouvert le suivant (le sous-menu s'ouvre à sa
    /// hauteur), puis l'élément cliqué. null : un niveau sans élément sûr.
    public static List<string>? MenuPath(IReadOnlyList<MenuSnapshot> menus, int x, int y)
    {
        if (menus.Count == 0) return null;
        var path = new List<string>();
        for (var level = 0; level < menus.Count - 1; level++)
        {
            var child = menus[level + 1];
            // L'élément à la hauteur du haut du sous-menu (FL l'ouvre aligné sur lui, à quelques pixels près).
            var opener = menus[level].Items
                .Where(i => Clean(i.Text).Length > 0 && i.Y - i.Height <= child.Y && child.Y <= i.Y + i.Height)
                .OrderBy(i => Math.Abs(i.Y - child.Y)).ThenBy(i => i.Y)
                .Cast<TextItem?>().FirstOrDefault();
            if (opener is not { } o) return null;
            path.Add(Clean(o.Text));
        }
        var last = menus[^1];
        if (x < last.X || x >= last.X + last.Width || y < last.Y || y >= last.Y + last.Height) return null;
        // L'élément cliqué : celui de la ligne du clic (toute la largeur du menu compte).
        var clicked = last.Items
            .Where(i => Clean(i.Text).Length > 0 && y >= i.Y - 2 && y < i.Y + i.Height + 2)
            .OrderBy(i => Math.Abs(i.CenterY - y))
            .Cast<TextItem?>().FirstOrDefault();
        if (clicked is not { } c) return null;
        path.Add(Clean(c.Text));
        return path;
    }

    /// Pur : ligne du menu « Arrangement » → option de la Playlist (et le nom de l'arrangement à ouvrir).
    public static BlockBody? ArrangementOption(string item)
    {
        var k = Key(item);
        if (k == Key("Add one")) return new BlockBody.PageOption("playlist.arrangementAdd", "");
        if (k == Key("Clone")) return new BlockBody.PageOption("playlist.arrangementClone", "");
        if (k == Key("Rename")) return new BlockBody.PageOption("playlist.arrangementRename", "");
        if (k == Key("Delete")) return new BlockBody.PageOption("playlist.arrangementDelete", "");
        if (k == Key("Merge with")) return null;                       // sous-menu : l'arrangement choisi dedans compte
        var name = item.Trim();
        return name.Length == 0 || name.Length > PageOptions.MaxName ? null : new BlockBody.PageOption("playlist.arrangementGo", name);
    }

    /// Pur : élément des menus de FL qui est une option de « Cliquer sur… » : Add › Channel › … (ajouter un instrument,
    /// Channel rack) et Add › Effect › … (ajouter un effet, Mixer), avec le plugin choisi.
    public static BlockBody? PageOptionForMenu(IReadOnlyList<string> path)
    {
        if (path.Count < 3 || Key(path[0]) != Key("Add")) return null;
        var name = string.Join(PageOptions.PathSeparator, path.Skip(2));
        if (Key(path[1]) == Key("Channel")) return new BlockBody.PageOption("channelRack.addInstrument", name);
        if (Key(path[1]) == Key("Effect")) return new BlockBody.PageOption("mixer.addEffect", name);
        return null;
    }

    private static KeyCombo F(int n, bool alt = false) => new((ushort)(Vk.F1 + n - 1), Alt: alt);
    private static KeyCombo Ctrl(char letter, bool shift = false) => new(Vk.Letter(letter), Ctrl: true, Shift: shift);

    /// Éléments des menus de FL qui ont leur raccourci dans FL sous Windows (les mêmes que le Mac).
    private static readonly (string[] Path, KeyCombo Combo)[] Shortcuts =
    {
        (new[] { "View", "Playlist" }, F(5)),
        (new[] { "View", "Channel rack" }, F(6)),
        (new[] { "View", "Piano roll" }, F(7)),
        (new[] { "View", "Plugin picker" }, F(8)),
        (new[] { "View", "Mixer" }, F(9)),
        (new[] { "View", "Browser" }, F(8, alt: true)),
        (new[] { "Options", "MIDI settings" }, F(10)),
        (new[] { "File", "Open" }, Ctrl('O')),
        (new[] { "File", "Save" }, Ctrl('S')),
        (new[] { "File", "Save as" }, Ctrl('S', shift: true)),
        (new[] { "File", "Save new version" }, Ctrl('N')),
        (new[] { "File", "Export", "Wave file" }, Ctrl('R')),
        (new[] { "File", "Export", "MP3 file" }, Ctrl('R', shift: true)),
        (new[] { "File", "Export", "MIDI file" }, Ctrl('M', shift: true)),
        (new[] { "Edit", "Undo" }, Ctrl('Z')),
    };

    /// Pur : le raccourci de FL d'un élément de ses menus, s'il en a un : enregistré, il devient ce raccourci
    /// (instantané, sans ouvrir de menu). Comparés sans casse, « … » ni lettre soulignée.
    public static KeyCombo? ShortcutFor(IReadOnlyList<string> path)
    {
        foreach (var (known, combo) in Shortcuts)
            if (known.Length == path.Count && known.Zip(path).All(p => Key(p.First) == Key(p.Second))) return combo;
        return null;
    }

    /// Ajoute le bloc le plus précis : un élément de menu qui a son raccourci dans FL devient ce raccourci, une option de
    /// « Cliquer sur… » cette option (avec sa page juste au-dessus, règle des options), sinon le bloc tel quel.
    public static void Append(BlockBody body, List<BlockBody> output)
    {
        if (body is BlockBody.MenuBar bar)
        {
            if (ShortcutFor(bar.Titles) is { } combo && MacKeys.FromWindows(combo) is { } key)
            {
                output.Add(new BlockBody.Key(key, 1));
                return;
            }
            if (PageOptionForMenu(bar.Titles) is { } option) body = option;
        }
        if (body is BlockBody.PageOption { Option: { } id } && PageOptions.PageOf(id) is { } page && !PageShown(page, output))
            output.Add(new BlockBody.OpenPage(page));
        output.Add(body);
    }

    /// La page est déjà devant juste au-dessus : « Ouvrir une page de FL » ou une option de cette page.
    public static bool PageShown(FlPage page, IReadOnlyList<BlockBody> blocks) => blocks.LastOrDefault() switch
    {
        BlockBody.OpenPage { Page: { } p } => p == page,
        BlockBody.PageOption { Option: { } id } => PageOptions.PageOf(id) == page,
        _ => false,
    };

    /// Pur : clic sur `label` dans la fenêtre de FL, suivi de `next` (ce qui a été enregistré après) : le bloc qui le
    /// remplace et combien d'éléments de `next` il prend (les clics dans le menu ouvert). null : un clic.
    public static (BlockBody Block, int Used)? Menu(string label, IReadOnlyList<RecordedInput> next)
    {
        var top = MenuTitle(label);
        if (top is null && !IsArrangement(label)) return null;
        // Clics qui suivent dans un menu de FL ouvert, avec le chemin lu au clic.
        var clicks = 0;
        RecordedInput.Click? last = null;
        foreach (var input in next)
        {
            if (input is not RecordedInput.Click { Right: false, Release: null } m || !InMenu(m)) break;
            clicks++;
            last = m;
        }
        if (last?.MenuPath is not { Count: > 0 } path) return null;
        if (top is not null) return (new BlockBody.MenuBar(new[] { top }.Concat(path).ToList()), clicks);
        if (path.Take(path.Count - 1).Any(p => Key(p) == Key("Merge with")) || ArrangementOption(path[^1]) is not { } option) return null;
        return (option, clicks);
    }

    /// Le clic est tombé dans un menu de FL (la fenêtre de devant à cet endroit).
    public static bool InMenu(RecordedInput.Click c) =>
        c.Windows.FirstOrDefault(w => c.X >= w.X && c.X < w.X + w.Width && c.Y >= w.Y && c.Y < w.Y + w.Height) is { Id: not 0 } w
        && w.Role == FlWindowRole.Menu;
}
