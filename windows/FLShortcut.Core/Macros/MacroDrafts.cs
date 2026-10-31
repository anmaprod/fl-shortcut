// Page Macros de Windows : ce que l'interface fait d'une macro, sans fenêtre (essayé par MacroDraftsTests). Une macro
// modifiée est toujours une COPIE remise au magasin (MacroLibraryStore.Update : révision + 1 seulement si elle change).
namespace FLShortcut.Core.Macros;

public static class MacroDrafts
{
    /// Copie modifiable (même id, même révision).
    public static MacroDoc Copy(MacroDoc doc) => MacroDoc.FromJson(doc.ToJson());

    /// Palette du créateur sur ce système : par catégorie, les blocs que `platform` ne refuse pas.
    public static IReadOnlyList<(BlockCategory Category, IReadOnlyList<BlockSpec> Specs)> Palette(Func<BlockBody, string?>? platform) =>
        BlockRegistry.Palette
            .Select(p => (p.Category, (IReadOnlyList<BlockSpec>)p.Specs.Where(s => platform?.Invoke(s.Default()) is null).ToList()))
            .Where(p => p.Item2.Count > 0)
            .ToList();

    /// Palette du créateur comme celle du Mac (PaletteCatalog.items) : FL Studio d'abord (Menu de FL en tête), puis
    /// Clavier, Souris, un seul « Attendre » ; ni Contrôle, ni blocs retirés avec le propriétaire (mute, solo, armer…).
    /// Seulement les blocs que ce système sait jouer (`platform`) et régler (`editable`).
    public static IReadOnlyList<(BlockCategory Category, IReadOnlyList<PaletteEntry> Entries)> CreatorPalette(
        Func<BlockBody, string?>? platform, Func<BlockType, bool> editable)
    {
        PaletteEntry Item(BlockType type, string? label = null, string? help = null, string? symbol = null)
        {
            var spec = BlockRegistry.Spec(type);
            return new PaletteEntry(type, label ?? spec.Label, help ?? spec.Help, symbol ?? spec.Symbol, spec.Category, spec.Default);
        }
        var entries = new[]
        {
            Item(BlockType.MenuBar), Item(BlockType.OpenPage), Item(BlockType.PageOption), Item(BlockType.DropFile),
            Item(BlockType.FlAction), Item(BlockType.NameColor), Item(BlockType.SoundCard), Item(BlockType.Organize),
            Item(BlockType.Key), Item(BlockType.MenuKey),
            Item(BlockType.Click, Loc.T("Clic à un endroit appris"), Loc.T("Clic gauche ou droit à un endroit que tu montres une fois dans FL.")),
            Item(BlockType.Drag),
            Item(BlockType.WaitWindow, Loc.T("Attendre"), Loc.T("Attend une boîte ou un menu de FL, ou fait une pause."), "clock"),
        };
        var order = new[] { BlockCategory.Fl, BlockCategory.Keyboard, BlockCategory.Mouse, BlockCategory.Windows };
        return order
            .Select(c => (c, (IReadOnlyList<PaletteEntry>)entries
                .Where(e => e.Category == c && editable(e.Type) && platform?.Invoke(e.Make()) is null).ToList()))
            .Where(p => p.Item2.Count > 0)
            .ToList();
    }

    /// Nouvelle macro vide, au nom unique (« Nouvelle macro 2 »…).
    public static MacroDoc Empty(MacroLibraryStore store) => new() { Name = store.UniqueName(Loc.T("Nouvelle macro")) };

    /// Copie d'un modèle de la galerie : ids neufs, nom unique.
    public static MacroDoc FromTemplate(MacroTemplate template, MacroLibraryStore store)
    {
        var doc = template.Make();
        doc.Name = store.UniqueName(doc.Name);
        doc.Blocks = MacroTemplates.FreshIds(doc.Blocks);
        return doc;
    }

    /// Le bloc `index` déplacé de `delta` places (bornes respectées) ; faux s'il ne bouge pas.
    public static bool Move(List<Block> blocks, int index, int delta)
    {
        var to = index + delta;
        if (index < 0 || index >= blocks.Count || to < 0 || to >= blocks.Count || delta == 0) return false;
        var block = blocks[index];
        blocks.RemoveAt(index);
        blocks.Insert(to, block);
        return true;
    }

    /// Nom tapé : espaces retirés, 60 caractères au plus ; null s'il est vide ou déjà pris par une autre macro.
    public static string? CleanName(string typed, MacroDoc doc, MacroLibraryStore store)
    {
        var name = typed.Trim();
        if (name.Length == 0) return null;
        if (name.Length > MacroValidation.MaxNameLength) name = name[..MacroValidation.MaxNameLength].TrimEnd();
        return store.Macros.Any(m => m.Id != doc.Id && m.Name == name) ? null : name;
    }

    /// Pur (testé) : cible d'un clic montré par l'utilisateur en (`x`, `y`), d'après les fenêtres de FL juste avant le
    /// clic (de l'avant vers l'arrière ; miroir de MacroEditing.learnedTarget du Mac). Dans un menu de FL : relative à
    /// ce menu. Dans une autre fenêtre de FL : relative à son coin le plus proche, taille retenue (c'est elle qu'on
    /// retrouve au rejeu). Ailleurs : null.
    public static ClickTarget? LearnedTarget(int x, int y, IReadOnlyList<FlWin> windows)
    {
        if (windows.Where(w => x >= w.X && x < w.X + w.Width && y >= w.Y && y < w.Y + w.Height).Cast<FlWin?>().FirstOrDefault()
            is not { } w) return null;
        var size = new Size2(w.Width, w.Height);
        ClickTarget target;
        if (w.Role == FlWindowRole.Menu)
            target = new ClickTarget.OpenMenu(new PopupHop(x - w.X, y - w.Y, size));
        else
        {
            var left = x - w.X <= w.X + w.Width - x;
            var top = y - w.Y <= w.Y + w.Height - y;
            var corner = top ? (left ? Corner.TopLeft : Corner.TopRight) : (left ? Corner.BottomLeft : Corner.BottomRight);
            target = new ClickTarget.FlWindowPoint(corner, x - (left ? w.X : w.X + w.Width), y - (top ? w.Y : w.Y + w.Height), size);
        }
        return target.IsFinite ? target : null;
    }

    /// Chemin d'un « Menu de FL » tapé (« File › Export › … », « > » accepté) : les titres, sans les vides.
    public static List<string> MenuPath(string typed) =>
        typed.Split(new[] { '›', '>' }).Select(t => t.Trim()).Where(t => t.Length > 0).ToList();

    /// Les raccourcis qui lancent cette macro.
    public static IReadOnlyList<Shortcut> ShortcutsOf(Guid macro, IEnumerable<Shortcut> shortcuts) =>
        shortcuts.Where(s => s.Kind == ShortcutKind.Macro && s.MacroRef == macro).ToList();
}

/// Un bloc de la palette du créateur : nom, aide (bulle), symbole du Mac, catégorie et bloc neuf.
public sealed record PaletteEntry(BlockType Type, string Label, string Help, string Symbol, BlockCategory Category, Func<BlockBody> Make);
