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
        PaletteEntry Item(BlockType type, string? label = null, string? help = null, string? symbol = null, Func<BlockBody>? make = null)
        {
            var spec = BlockRegistry.Spec(type);
            return new PaletteEntry(type, label ?? spec.Label, help ?? spec.Help, symbol ?? spec.Symbol, spec.Category, make ?? spec.Default);
        }
        var entries = new[]
        {
            Item(BlockType.MenuBar), Item(BlockType.OpenPage), Item(BlockType.PageOption), Item(BlockType.DropFile),
            Item(BlockType.FlAction), Item(BlockType.NameColor), Item(BlockType.Organize),
            Item(BlockType.Key), Item(BlockType.MenuKey),
            Item(BlockType.Click, Loc.T("Clic à un endroit appris"), Loc.T("Clic gauche ou droit à un endroit que tu montres une fois dans FL.")),
            // Comme la palette du Mac : posé « à montrer dans FL » (Attraper, Lâcher).
            Item(BlockType.Drag, make: () => new BlockBody.Drag(new ClickTarget.ToLearn(), new ClickTarget.ToLearn())),
            Item(BlockType.MouseClick),
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

    /// Pur (testé, miroir de ClickSequenceCompiler.named du Mac) : clic dans une fenêtre de FL sur un bouton qui porte
    /// un nom → retenu par ce nom (sa place reste le repli si le nom n'est pas lu au moment du clic). Sinon inchangé.
    public static ClickTarget Named(ClickTarget target, NamedHit? hit)
    {
        if (hit is not { } h || target is not ClickTarget.FlWindowPoint { Size: { } size } w) return target;
        var spot = new NamedSpot(h.Label.Trim(), h.Dx, h.Dy, w.Corner, w.Dx, w.Dy, size, w.Title);
        return spot.IsValid ? new ClickTarget.Named(spot) : target;
    }

    /// Pur (testé) : clic dans une fenêtre de FL, « Retrouver ce bouton s'il bouge » → retenu par l'image du bouton
    /// (carré centré sur le clic, assez contrasté pour être reconnu). Sinon inchangé (sa place).
    public static ClickTarget Visual(ClickTarget target, GrayImage? patch)
    {
        if (patch is null || patch.Width != patch.Height || patch.Width is < VisualSpot.MinSide or > VisualSpot.MaxSide
            || patch.Contrast < VisualMatch.MinContrast || target is not ClickTarget.FlWindowPoint { Size: { } size } w) return target;
        var spot = new VisualSpot(w.Corner, w.Dx, w.Dy, size, w.Title, patch.Width, patch.Pixels.ToArray());
        return spot.IsValid ? new ClickTarget.Button(spot) : target;
    }

    /// La place d'un bouton retenu par son nom ou son image (« Retrouver ce bouton s'il bouge » décoché).
    public static ClickTarget Place(ClickTarget target) => target switch
    {
        ClickTarget.Named n => n.Spot.Place,
        ClickTarget.Button b => b.Spot.Place,
        _ => target,
    };

    /// Les deux bouts d'un glisser montré dans FL (comme dragTargets du Mac) : l'appui et le relâché, retenus comme
    /// des clics montrés par rapport aux fenêtres de FL d'avant l'appui ; le lâcher ignore la petite fenêtre que FL
    /// montre sous la souris pendant le glisser ; jamais dans un menu. Null et la raison si ce n'est pas un glisser.
    public static (ClickTarget From, ClickTarget To)? DragTargets(int ax, int ay, int bx, int by, IReadOnlyList<FlWin> windows, out string? why)
    {
        why = null;
        if (Math.Sqrt((double)(bx - ax) * (bx - ax) + (double)(by - ay) * (by - ay)) < 4)
        {
            why = Loc.T("Ce n'était pas un glisser : reste cliqué et glisse jusqu'à l'endroit voulu, puis recommence.");
            return null;
        }
        var plain = windows.Where(w => w.Role != FlWindowRole.Menu).ToList();
        if (LearnedTarget(ax, ay, windows) is not { } from || from is ClickTarget.OpenMenu
            || LearnedTarget(bx, by, plain) is not { } to || to is ClickTarget.OpenMenu)
        {
            why = Loc.T("Le glisser doit commencer et finir dans une fenêtre de FL (pas dans un menu) : recommence.");
            return null;
        }
        return (from, to);
    }

    /// Une macro « À apprendre » (comme MacroOutline.flags du Mac) : un bloc allumé, même dans un « si » ou une
    /// boucle, a un clic ou un glisser-déposer pas encore montré dans FL (macro venue de la Communauté ou d'un modèle).
    public static bool ToLearn(IEnumerable<Block> blocks) => blocks.Any(b => b.Enabled && (b.Body switch
    {
        BlockBody.Click { Target: ClickTarget.ToLearn } => true,
        BlockBody.Drag d => d.From is ClickTarget.ToLearn || d.To is ClickTarget.ToLearn,
        _ => false,
    } || b.Body.Children.Any(ToLearn)));

    /// Le bouton peut être retrouvé s'il bouge : clic dans une fenêtre de FL (taille retenue), ou déjà suivi.
    public static bool CanFollow(ClickTarget target) =>
        target is ClickTarget.FlWindowPoint { Size: not null } or ClickTarget.Named or ClickTarget.Button;

    /// Chemin d'un « Menu de FL » tapé (« File › Export › … », « > » accepté) : les titres, sans les vides.
    public static List<string> MenuPath(string typed) =>
        typed.Split(new[] { '›', '>' }).Select(t => t.Trim()).Where(t => t.Length > 0).ToList();

    /// Les raccourcis qui lancent cette macro.
    public static IReadOnlyList<Shortcut> ShortcutsOf(Guid macro, IEnumerable<Shortcut> shortcuts) =>
        shortcuts.Where(s => s.Kind == ShortcutKind.Macro && s.MacroRef == macro).ToList();
}

/// Un bloc de la palette du créateur : nom, aide (bulle), symbole du Mac, catégorie et bloc neuf.
public sealed record PaletteEntry(BlockType Type, string Label, string Help, string Symbol, BlockCategory Category, Func<BlockBody> Make);
