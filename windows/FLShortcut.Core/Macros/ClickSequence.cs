// « Enregistrer une macro » sur Windows (miroir de ClickSequenceCompiler, MacroClickSequence.swift du Mac) : les clics
// et les touches faits dans FL pendant l'enregistrement deviennent des blocs, dans l'ordre.
// - Touche dans un menu de FL ouvert : ↑ ↓ ← → Entrée Échap → « Dans le menu », lettre → « Lettres d'un menu » ;
//   ailleurs → « Touche » (raccourci compris) ; la même touche répétée → « × n ».
// - Clic : retenu par rapport à ce qu'il a touché, comme « Montrer dans FL… » (MacroDrafts.LearnedTarget) : un menu de
//   FL, ou le coin le plus proche d'une fenêtre de FL et sa taille. Bouton gauche relâché loin de l'appui : glisser.
// - Bouton qui porte un nom (lu dans la fenêtre de FL au moment du clic) : retenu par ce nom, retrouvé même s'il bouge
//   (MacroDrafts.Named, comme le Mac) ; sa place reste le repli.
// - Titre des menus de FL (FILE, EDIT…) ou bouton « Arrangement », puis un élément de son menu : « Menu de FL › … », son
//   raccourci ou l'option de « Cliquer sur… » (SmartClicks, comme le Mac, 11/11).
// - Hors de FL : ignoré. Pur et testé ; l'enregistreur de l'app (Services/MacroRecorder.cs) relève les entrées.
namespace FLShortcut.Core.Macros;

/// Fin d'un glisser : où le bouton a été relâché, et les fenêtres de FL à ce moment.
public sealed record RecordedRelease(int X, int Y, IReadOnlyList<FlWin> Windows);

/// Ce que l'enregistrement retient, dans l'ordre.
public abstract record RecordedInput
{
    /// Clic dans FL (coordonnées de l'écran), avec les fenêtres de FL juste avant lui (un menu qui se ferme au clic y est
    /// encore), de l'avant vers l'arrière. `Named` : nom du bouton cliqué, lu au moment du clic (null : pas de nom).
    /// `MenuPath` : clic dans un menu de FL, les éléments choisis dans les menus ouverts (SmartClicks.MenuPath).
    public sealed record Click(int X, int Y, bool Right, IReadOnlyList<FlWin> Windows, RecordedRelease? Release = null,
                               NamedHit? Named = null, IReadOnlyList<string>? MenuPath = null) : RecordedInput;

    /// Touche tapée dans FL (jamais journalisée) ; `MenuOpen` : un menu de FL était ouvert à ce moment.
    public sealed record Key(KeyCombo Combo, bool MenuOpen) : RecordedInput;
}

public static class ClickSequenceCompiler
{
    /// Plafonds des blocs (validation) : au-delà, un nouveau bloc commence.
    public const int MaxTimes = 20;
    public const int MaxMenuLetters = 8;
    /// Un bouton relâché à plus de tant de pixels de l'appui : un glisser.
    public const int DragDistance = 8;

    /// Les blocs, et le nombre d'entrées ignorées (hors de FL, touche sans équivalent).
    public sealed record Result(List<BlockBody> Blocks, int Ignored);

    private static readonly (ushort Vk, MenuKey Key)[] MenuVks =
    {
        (Vk.Up, MenuKey.Up), (Vk.Down, MenuKey.Down), (Vk.Left, MenuKey.Left), (Vk.Right, MenuKey.Right),
        (Vk.Return, MenuKey.Enter), (Vk.Escape, MenuKey.Escape),
    };

    /// Une touche : le bloc précédent remplacé (répétition), ou le bloc à ajouter ; (null, null) : touche ignorée.
    public static (BlockBody? Replace, BlockBody? Add) KeyStep(RecordedInput.Key k, BlockBody? previous)
    {
        var c = k.Combo;
        var plain = !c.Ctrl && !c.Alt && !c.Win;
        if (k.MenuOpen && plain && !c.Shift && MenuVks.FirstOrDefault(m => m.Vk == c.Vk) is { Vk: > 0 } menu)
        {
            if (previous is BlockBody.MenuKeyPress p && p.MenuKey == menu.Key && p.Times < MaxTimes)
                return (p with { Times = p.Times + 1 }, null);
            return (null, new BlockBody.MenuKeyPress(menu.Key, 1));
        }
        if (k.MenuOpen && plain && c.Vk is >= Vk.A and <= Vk.A + 25)
        {
            var letter = (char)('a' + c.Vk - Vk.A);
            if (previous is BlockBody.MenuLetters l && l.Letters.Length < MaxMenuLetters)
                return (l with { Letters = l.Letters + letter }, null);
            return (null, new BlockBody.MenuLetters(letter.ToString(), EnterPolicy.Never));
        }
        if (MacKeys.FromWindows(c) is not { } key) return (null, null);
        if (previous is BlockBody.Key pk && pk.Ref == key && pk.Times < MaxTimes) return (pk with { Times = pk.Times + 1 }, null);
        return (null, new BlockBody.Key(key, 1));
    }

    public static Result Compile(IReadOnlyList<RecordedInput> inputs)
    {
        var blocks = new List<BlockBody>();
        var ignored = 0;
        for (var index = 0; index < inputs.Count; index++)
        {
            var input = inputs[index];
            // Titre d'un menu de FL (ou « Arrangement »), puis un élément de son menu : le bloc le plus précis (Mac pareil).
            if (input is RecordedInput.Click { Right: false, Release: null, Named: { } named } title && !SmartClicks.InMenu(title)
                && SmartClicks.Menu(named.Label, inputs.Skip(index + 1).ToList()) is { } smart)
            {
                SmartClicks.Append(smart.Block, blocks);
                index += smart.Used;
                continue;
            }
            switch (input)
            {
                case RecordedInput.Key k:
                    var (replace, add) = KeyStep(k, blocks.LastOrDefault());
                    if (replace is not null) blocks[^1] = replace;
                    else if (add is not null) blocks.Add(add);
                    else ignored++;
                    break;
                case RecordedInput.Click c:
                    if (MacroDrafts.LearnedTarget(c.X, c.Y, c.Windows) is not { } place)
                    {
                        ignored++;
                        break;
                    }
                    var target = MacroDrafts.Named(place, c.Named);
                    if (!c.Right && c.Release is { } r
                        && Math.Abs(r.X - c.X) + Math.Abs(r.Y - c.Y) > DragDistance
                        // Lâcher : jamais dans la petite fenêtre que FL montre sous la souris pendant le glisser (nom du
                        // son tiré du Browser, 07/11, comme le Mac) : seules les fenêtres de FL comptent.
                        && MacroDrafts.LearnedTarget(r.X, r.Y, r.Windows.Where(w => w.Role != FlWindowRole.Menu).ToList()) is { } to)
                    {
                        blocks.Add(new BlockBody.Drag(target, to));
                        break;
                    }
                    blocks.Add(new BlockBody.Click(target, c.Right ? MouseButton.Right : MouseButton.Left));
                    break;
            }
        }
        return new Result(blocks, ignored);
    }
}
