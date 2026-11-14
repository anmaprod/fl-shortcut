// Clics des macros sur Windows : clics appris rejoués (coin d'une fenêtre de FL de la même taille, dernier clic,
// pointeur, menu ouvert, bouton retrouvé à son nom ou à son image), glisser, et « Menu de FL » (FILE, TOOLS… en haut de
// sa fenêtre).
// Miroir de MacroEffectsMac.swift (cibles de clic) et de MenuBarAX (MacroClickSequence.swift) : les menus sont ouverts
// et choisis comme à la main (vrais clics), chaque élément retrouvé à son nom au moment du clic.
namespace FLShortcut.Core.Macros;

public sealed partial class MacroEffectsWindows
{
    /// Délais pour qu'apparaisse la fenêtre ou le menu visé quand le clic précédent vient de l'ouvrir (la fenêtre des
    /// réglages de FL peut mettre un moment à s'ouvrir la première fois). Rien n'est attendu s'il est déjà là.
    private const int WindowAppearMs = 3_000, MenuAppearMs = 1_500;

    /// Pointeur au départ, et la fenêtre de FL sous lui.
    private (int X, int Y) _origin;
    private FlWin? _originWindow;
    /// Piste visée : dernier clic de l'utilisateur dans FL (fenêtre inchangée), sinon le pointeur au départ.
    private (int X, int Y) _track;
    /// Point du dernier clic de la macro (repère « dernier clic »).
    private (int X, int Y)? _lastClick;
    /// Pointeur de l'utilisateur avant le premier clic de la macro (remis à la fin).
    private (int X, int Y)? _cursorBefore;
    /// Fenêtres de FL juste avant le dernier clic : ce qui n'y est pas vient d'être ouvert.
    private HashSet<long>? _beforeLastClick;
    /// Dernier menu attendu par « Attendre une fenêtre (menu) » : repère des clics « menu ouvert ».
    private FlWin? _lastMenu;

    private readonly record struct Spot(int X, int Y, FlWin? Popup, bool Fresh);

    private void BeginClicks(IReadOnlyList<FlWin> windows)
    {
        _origin = _fl.Cursor();
        _originWindow = windows.Where(w => w.Role != FlWindowRole.Menu && Contains(w, _origin)).Cast<FlWin?>().FirstOrDefault();
        _track = _origin;
        _lastClick = null;
        _cursorBefore = null;
        _beforeLastClick = null;
        _lastMenu = null;
        if (_fl.LastAimedClick is { } aimed)
        {
            var same = windows.Any(w => w.Id == aimed.Window && w.Width == aimed.WindowWidth && w.Height == aimed.WindowHeight);
            _fl.Log("TRACK", same ? $"remembered click ({aimed.X},{aimed.Y}), window unchanged" : "remembered click, window gone/resized → ignored");
            if (same) _track = (aimed.X, aimed.Y);
        }
        else _fl.Log("TRACK", "no remembered click → cursor");
    }

    /// Mute / solo sans le lien (08/11, « ce sera la piste sélectionnée, il n'y a pas besoin de montrer ») : le rond de
    /// la piste cliquée juste avant, retrouvé dans l'image de sa fenêtre de FL (MuteDots) ; clic gauche = mute, Ctrl +
    /// clic gauche = solo, dans le Mixer, le Channel rack et la Playlist.
    private StepResult MuteSoloWithoutLink(bool solo)
    {
        var window = _fl.Windows().Where(w => w.Role != FlWindowRole.Menu && Contains(w, _track)).Cast<FlWin?>().FirstOrDefault();
        if (window is not { } w) return new StepResult.Fail(Loc.T("clique d'abord sur ta piste dans FL, puis lance la macro"));
        if (_fl.WindowColorImage(w.Id) is not { } image) return new StepResult.Fail(Loc.T("fenêtre de FL illisible"));
        // Écran à 100 % : des ronds de 5 pixels, trop petits pour être sûrs ; l'image est alors agrandie deux fois.
        foreach (var factor in new[] { 1, 2 })
        {
            var shown = image.Scaled(factor);
            double sx = (double)shown.Width / w.Width, sy = (double)shown.Height / w.Height;
            if (MuteDots.Find(shown, (_track.X - w.X) * sx, (_track.Y - w.Y) * sy) is not { } dot) continue;
            int x = w.X + (int)Math.Round(dot.X / sx), y = w.Y + (int)Math.Round(dot.Y / sy);
            if (StopReason() is { } stop) return new StepResult.Cancel(stop);
            _cursorBefore ??= _fl.Cursor();
            if (!(solo ? _fl.ControlClick(x, y) : _fl.Click(x, y, false, 30)))
                return new StepResult.Cancel(Loc.T("FL n'est plus au premier plan"));
            _lastClick = (x, y);
            _fl.Log("MUTE", $"dot found ({dot.Page}{(dot.Inferred ? ", unlit" : "")}), {(solo ? "solo" : "mute")}");
            return new StepResult.Ok();
        }
        _fl.Log("MUTE", "no dot near the clicked track · " + MuteDots.Summary(image));
        return new StepResult.Fail(Loc.T("bouton mute introuvable : clique sur ta piste (Mixer, Channel rack ou Playlist), puis relance"));
    }

    // ---------- Consolider la piste dans la Playlist ----------

    public static string ConsolidateWhere => Loc.T("seulement dans la Playlist : clique sur le nom d'une piste de la Playlist, puis relance");

    /// « Consolider la piste dans la Playlist » (08/11, miroir de MacroConsolidate.swift) : la piste cliquée juste avant
    /// dans la Playlist (son rond mute à droite du clic le prouve : jamais un clic droit sur un clip, que FL effacerait,
    /// ni dans le Mixer ou le Channel rack), clic droit sur son en-tête, puis « Consolidate… » retrouvé à son nom dans
    /// le menu (lu par Windows, sinon dans l'image du seul menu de FL) ; un menu sans lui est refermé.
    private StepResult ConsolidateTrack()
    {
        var window = _fl.Windows().Where(w => w.Role != FlWindowRole.Menu && Contains(w, _track)).Cast<FlWin?>().FirstOrDefault();
        if (window is not { } w) return new StepResult.Fail(ConsolidateWhere);
        if (_fl.WindowColorImage(w.Id) is not { } image) return new StepResult.Fail(Loc.T("fenêtre de FL illisible"));
        MuteDots.Target? dot = null;
        foreach (var factor in new[] { 1, 2 })
        {
            var shown = image.Scaled(factor);
            double sx = (double)shown.Width / w.Width, sy = (double)shown.Height / w.Height;
            if (MuteDots.Find(shown, (_track.X - w.X) * sx, (_track.Y - w.Y) * sy) is { } found) { dot = found; break; }
        }
        if (dot is not { } d || d.Page != MuteDots.Page.Playlist)
        {
            _fl.Log("CONSOLIDATE", dot is { } other ? $"clicked track is in the {other.Page}" : "no track header under the click");
            return new StepResult.Fail(ConsolidateWhere);
        }
        if (StopReason() is { } stop) return new StepResult.Cancel(stop);
        var before = Ids();
        _beforeLastClick = before;
        _cursorBefore ??= _fl.Cursor();
        var opening = ClickAt(_track, true, 60);
        if (opening is not StepResult.Ok) return opening;
        var (opened, menu) = NewWindow(before, FlWindowRole.Menu, MenuAppearMs);
        if (opened is StepResult.Cancel) return Abandon(opened);
        if (menu is not { } m || Settled(m.Id) is not { } current)
            return Abandon(new StepResult.Fail(Loc.T("le menu de la piste ne s'est pas ouvert")));
        var items = _fl.MenuItems(current.Id);
        if (items is null)
        {
            _fl.Log("CONSOLIDATE", "menu unreadable");
            return Abandon(new StepResult.Fail(Loc.T("menu de FL illisible : mets FL devant")));
        }
        if (MenuText.StartingWith("Consolidate", items) is not { } item || item.Greyed == true)
        {
            _fl.Log("CONSOLIDATE", $"not among {items.Count} item(s)");
            return Abandon(new StepResult.Fail(ConsolidateWhere));
        }
        var clicked = ClickInside((item.X + item.Width / 2, item.Y + item.Height / 2), current, 80);
        if (clicked is not StepResult.Ok) return Abandon(clicked);
        _fl.Log("CONSOLIDATE", "Consolidate clicked");
        return new StepResult.Ok();
    }

    // ---------- « Cliquer sur… » › Playlist › Arrangement ----------

    /// Bouton « Arrangement » de la Playlist retrouvé à son nom dans les fenêtres de FL au moment du clic (la plus grande
    /// d'abord : la Playlist peut être détachée), puis `item` dans le menu qu'il ouvre, retrouvé lui aussi à son nom :
    /// « Add one », « Clone », « Rename », « Delete », « Merge with » (son sous-menu reste ouvert) ou le nom d'un
    /// arrangement. Ligne absente : menu refermé. Miroir de MacroEffectsMac.arrangementMenu ; aucun nom au journal.
    private StepResult ArrangementMenu(string item)
    {
        var wanted = MenuText.Normalized(item);
        if (wanted.Length == 0) return new StepResult.Fail(Loc.T("nom de l'arrangement à écrire dans « Cliquer sur… »"));
        if (StopReason() is { } stop) return new StepResult.Cancel(stop);
        (int X, int Y)? button = null;
        foreach (var w in _fl.Windows().Where(w => w.Role != FlWindowRole.Menu && w.Width >= 300 && w.Height >= 200)
                     .OrderByDescending(w => (long)w.Width * w.Height))
        {
            if (_fl.ReadText(w.Id) is not { } texts) continue;
            if (MenuText.ArrangementLabel(texts) is { } found) { button = found; break; }
        }
        if (button is not { } at)
        {
            _fl.Log("FL", "arrangement button not found");
            return new StepResult.Fail(Loc.T("bouton « Arrangement » introuvable : ouvre la Playlist juste au-dessus (son titre visible)"));
        }
        var before = Ids();
        _beforeLastClick = before;
        var opening = ClickAt(at, false, 60);
        if (opening is not StepResult.Ok) return opening;
        var (opened, menu) = NewWindow(before, FlWindowRole.Menu, MenuAppearMs);
        if (opened is StepResult.Cancel) return Abandon(opened);
        if (menu is not { } m || Settled(m.Id) is not { } current)
            return Abandon(new StepResult.Fail(Loc.T("le menu « Arrangement » de FL ne s'est pas ouvert")));
        var items = _fl.MenuItems(current.Id) ?? _fl.ReadText(current.Id);
        if (items?.Where(t => MenuText.Normalized(t.Text) == wanted).OrderBy(t => t.Y).Cast<TextItem?>().FirstOrDefault()
            is not { } line)
        {
            _fl.Log("FL", $"arrangement menu: line not among {items?.Count ?? 0} item(s)");
            return Abandon(new StepResult.Fail(Loc.T("cette ligne est introuvable dans le menu « Arrangement » de FL")));
        }
        var chosen = ClickInside((line.CenterX, line.CenterY), current, 80);
        if (chosen is not StepResult.Ok) return Abandon(chosen);
        _fl.Sleep(150);
        _fl.Log("FL", "arrangement menu item chosen");
        return new StepResult.Ok();
    }

    private static bool Contains(FlWin w, (int X, int Y) p) => p.X >= w.X && p.X < w.X + w.Width && p.Y >= w.Y && p.Y < w.Y + w.Height;

    private static bool SameSize(FlWin w, Size2 size) => Math.Abs(w.Width - size.Width) <= 2 && Math.Abs(w.Height - size.Height) <= 2;

    private static (int X, int Y) Point(FlWin w, Corner corner, double dx, double dy)
    {
        var x = corner is Corner.TopLeft or Corner.BottomLeft ? w.X : w.X + w.Width;
        var y = corner is Corner.TopLeft or Corner.TopRight ? w.Y : w.Y + w.Height;
        return (x + (int)Math.Round(dx), y + (int)Math.Round(dy));
    }

    private HashSet<long> Ids() => _fl.Windows().Select(w => w.Id).ToHashSet();

    /// Fenêtre de FL de cette taille (à 2 pixels près) visée par un clic appris : celle qui contient la piste visée,
    /// sinon la plus à l'avant. Jamais un menu, jamais reconnue à son titre (sur Windows, aucun titre n'est lu).
    private FlWin? TargetWindow(Size2 size)
    {
        var fits = _fl.Windows().Where(w => w.Role != FlWindowRole.Menu && SameSize(w, size)).ToList();
        return fits.Where(w => Contains(w, _track)).Cast<FlWin?>().FirstOrDefault() ?? (fits.Count > 0 ? fits[0] : null);
    }

    /// Bouton retrouvé à son nom dans sa fenêtre, lue une fois à ce moment-là ; nom absent ou fenêtre illisible : sa
    /// place apprise. NoWindow : sa fenêtre n'est pas (encore) ouverte. Le nom n'est jamais journalisé.
    private (bool NoWindow, (int X, int Y) Point, FlWin Window) NamedPoint(NamedSpot spot)
    {
        if (TargetWindow(spot.Size) is not { } w) return (true, default, default);
        var place = Point(w, spot.Corner, spot.Px, spot.Py);
        var expected = (X: place.X - (int)Math.Round(spot.Dx), Y: place.Y - (int)Math.Round(spot.Dy));
        if (_fl.ReadText(w.Id) is not { } items)
        {
            _fl.Log("CLICK", "window unreadable: learned place used");
            return (false, place, w);
        }
        if (MenuText.Nearest(spot.Label, items, expected.X, expected.Y) is not { } item)
        {
            _fl.Log("CLICK", "button name not found: learned place used");
            return (false, place, w);
        }
        _fl.Log("CLICK", $"button found by its name (moved {item.CenterX - expected.X},{item.CenterY - expected.Y})");
        return (false, (item.CenterX + (int)Math.Round(spot.Dx), item.CenterY + (int)Math.Round(spot.Dy)), w);
    }

    /// Bouton retrouvé à son image dans sa fenêtre, lue une fois à ce moment-là (VisualMatch, comme le Mac) ; null :
    /// fenêtre absente ou illisible, ou bouton pas (encore) affiché. Jamais sa place à l'aveugle.
    private ((int X, int Y) Point, FlWin Window)? ButtonPoint(VisualSpot spot)
    {
        if (TargetWindow(spot.Size) is not { } w) return null;
        if (_fl.WindowImage(w.Id) is not { Width: > 0, Height: > 0 } image)
        {
            _fl.Log("CLICK", "window image unreadable");
            return null;
        }
        var expected = Point(w, spot.Corner, spot.Dx, spot.Dy);
        var sx = (double)w.Width / image.Width;
        var sy = (double)w.Height / image.Height;
        var hintX = (int)Math.Round((expected.X - w.X) / sx);
        var hintY = (int)Math.Round((expected.Y - w.Y) / sy);
        if (VisualMatch.Find(spot.Image, image, hintX, hintY) is not { } hit) return null;
        _fl.Log("CLICK", $"button found by its image (score {hit.Score.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture)}, "
                         + $"moved {hit.X - hintX},{hit.Y - hintY})");
        return ((w.X + (int)Math.Round(hit.X * sx), w.Y + (int)Math.Round(hit.Y * sy)), w);
    }

    /// Point visé, et le menu dans lequel il doit tomber (cible « menu ouvert »).
    private ((int X, int Y) Point, FlWin? Popup)? Resolve(ClickTarget target)
    {
        switch (target)
        {
            case ClickTarget.StartCursor s:
                return ((_origin.X + (int)Math.Round(s.Dx), _origin.Y + (int)Math.Round(s.Dy)), null);
            case ClickTarget.FlWindowPoint w:
            {
                var frame = w.Size is { } size ? TargetWindow(size) : _originWindow;
                return frame is { } f ? (Point(f, w.Corner, w.Dx, w.Dy), null) : null;
            }
            case ClickTarget.CursorXWindowY c:
                return _originWindow is { } ow ? ((_origin.X + (int)Math.Round(c.Dx), ow.Y + (int)Math.Round(c.Dy)), null) : null;
            case ClickTarget.LastClick l:
                return _lastClick is { } last ? ((last.X + (int)Math.Round(l.Dx), last.Y + (int)Math.Round(l.Dy)), null) : null;
            case ClickTarget.Track t:
                return ((_track.X + (int)Math.Round(t.Dx), _track.Y + (int)Math.Round(t.Dy)), null);
            case ClickTarget.OpenMenu m:
            {
                var windows = _fl.Windows();
                // Le menu attendu par « Attendre un menu » (toujours là, au même endroit), sinon le menu ouvert par la
                // macro qui a la forme apprise (le plus à l'avant : un sous-menu passe devant le menu qui l'a ouvert).
                var remembered = _lastMenu is { } lm ? windows.Where(w => w == lm).Cast<FlWin?>().FirstOrDefault() : null;
                var menu = remembered is { } r && m.Hop.Fits(r.Width, r.Height) ? r
                    : windows.Where(w => w.Role == FlWindowRole.Menu && !_start.Contains(w.Id) && m.Hop.Fits(w.Width, w.Height))
                        .Cast<FlWin?>().FirstOrDefault();
                if (menu is not { } found) return null;
                var (x, y) = m.Hop.Point(found.X, found.Y, found.Width);
                return (((int)Math.Round(x), (int)Math.Round(y)), found);
            }
            case ClickTarget.Named n:
            {
                var (noWindow, p, _) = NamedPoint(n.Spot);
                return noWindow ? null : (p, null);
            }
            case ClickTarget.Button b:
                return ButtonPoint(b.Spot) is { } seen ? (seen.Point, null) : null;
            default:
                return null;                    // à montrer dans FL : jamais de clic à l'aveugle
        }
    }

    /// Cible d'un clic appris, et si sa fenêtre ou son menu vient d'être ouvert (absent juste avant le clic précédent de
    /// la macro, ou au départ). Un menu tout juste ouvert passe avant un menu plus ancien de la même forme.
    private Spot? Locate(ClickTarget target)
    {
        var baseline = _beforeLastClick ?? _start;
        switch (target)
        {
            case ClickTarget.FlWindowPoint { Size: { } size } w:
            {
                if (TargetWindow(size) is not { } win) return null;
                var p = Point(win, w.Corner, w.Dx, w.Dy);
                return new Spot(p.X, p.Y, null, !baseline.Contains(win.Id));
            }
            case ClickTarget.Named n:
            {
                var (noWindow, p, win) = NamedPoint(n.Spot);
                return noWindow ? null : new Spot(p.X, p.Y, null, !baseline.Contains(win.Id));
            }
            case ClickTarget.Button b:
            {
                if (ButtonPoint(b.Spot) is not { } found) return null;
                return new Spot(found.Point.X, found.Point.Y, null, !baseline.Contains(found.Window.Id));
            }
            case ClickTarget.OpenMenu m:
            {
                var fitting = _fl.Windows()
                    .Where(w => w.Role == FlWindowRole.Menu && !_start.Contains(w.Id) && m.Hop.Fits(w.Width, w.Height)).ToList();
                if (fitting.Count == 0) return null;
                var menu = fitting.Where(w => !baseline.Contains(w.Id)).Cast<FlWin?>().FirstOrDefault() ?? fitting[0];
                var (x, y) = m.Hop.Point(menu.X, menu.Y, menu.Width);
                return new Spot((int)Math.Round(x), (int)Math.Round(y), menu, !baseline.Contains(menu.Id));
            }
            default:
                return Resolve(target) is { } r ? new Spot(r.Point.X, r.Point.Y, r.Popup, false) : null;
        }
    }

    /// Fenêtre (taille retenue) ou menu de FL : attendu s'il n'est pas encore là. Autres cibles : jamais attendues.
    private static int? AppearTimeout(ClickTarget target) => target switch
    {
        ClickTarget.FlWindowPoint { Size: not null } or ClickTarget.Named or ClickTarget.Button => WindowAppearMs,
        ClickTarget.OpenMenu => MenuAppearMs,
        _ => null,
    };

    private static string Missing(ClickTarget target) => target switch
    {
        ClickTarget.FlWindowPoint { Size: { } size } =>
            Loc.F("fenêtre de FL de %lld × %lld introuvable : remontre le clic",
                (long)size.Width, (long)size.Height),
        ClickTarget.Named n =>
            Loc.F("fenêtre de FL de %lld × %lld introuvable : remontre le clic",
                (long)n.Spot.Size.Width, (long)n.Spot.Size.Height),
        ClickTarget.Button => Loc.T("bouton introuvable dans FL : remontre-le"),
        ClickTarget.OpenMenu => Loc.T("le menu de FL attendu ne s'est pas ouvert"),
        ClickTarget.ToLearn => Loc.T("position à montrer dans FL."),
        _ => Loc.T("position introuvable"),
    };

    private StepResult Click(ClickTarget target, bool right)
    {
        if (!target.IsFinite) return new StepResult.Fail(Loc.T("position introuvable"));
        var found = Locate(target);
        if (AppearTimeout(target) is { } timeout && (found is null || found.Value.Fresh || found.Value.Popup is not null))
        {
            // Fenêtre ou menu que le clic précédent ouvre : attendu s'il n'est pas encore là, puis lu deux fois de suite
            // au même endroit (FL a fini de le placer). Seul un menu plus ancien de la forme apprise : un sous-menu tout
            // juste ouvert peut encore passer devant (0,3 s). Échap et la perte du premier plan l'interrompent.
            var t0 = _fl.Now;
            (int, int)? previous = null;
            while (true)
            {
                var elapsed = (_fl.Now - t0).TotalMilliseconds;
                if (found is { } f)
                {
                    if (f.Fresh)
                    {
                        if (previous == (f.X, f.Y)) break;
                        previous = (f.X, f.Y);
                    }
                    else if (elapsed >= 300) break;
                }
                else previous = null;
                if (elapsed >= timeout) break;
                if (StopReason() is { } stop) return new StepResult.Cancel(stop);
                _fl.Sleep(15);
                found = Locate(target);
            }
            var ms = (int)(_fl.Now - t0).TotalMilliseconds;
            if (ms >= 30 || found is null)
                _fl.Log("CLICK", found is null ? $"target still missing after {ms} ms" : $"target ready after {ms} ms");
            // Fenêtre qui vient de s'ouvrir : un court instant pour qu'elle passe au premier plan de FL.
            if (found is { Fresh: true, Popup: null } && Pause(80) is StepResult.Cancel c) return c;
        }
        if (found is not { } spot) return new StepResult.Fail(Missing(target));
        _beforeLastClick = Ids();
        return spot.Popup is { } popup ? ClickInside((spot.X, spot.Y), popup, 35) : ClickAt((spot.X, spot.Y), right, 30);
    }

    /// « Clic de souris » (05/11) : un clic là où est la souris, seulement sur une fenêtre de FL tout devant (aucune autre
    /// appli ne la couvre), comme un clic appris.
    private StepResult MouseClick(BlockBody.MouseClick m)
    {
        var p = _fl.Cursor();
        var (window, cover) = _fl.At(p.X, p.Y);
        if (window is null)
        {
            if (cover is not null) return new StepResult.Fail(Loc.F("« %@ » couvre FL à cet endroit", cover));
            _fl.Log("CLICK", $"mouse click refused ({p.X},{p.Y}): outside every FL window");
            return new StepResult.Fail(Loc.T("la souris est hors de FL"));
        }
        if (StopReason() is { } stop) return new StepResult.Cancel(stop);
        if (!_fl.MouseClick(p.X, p.Y, m.Button, m.Twice)) return new StepResult.Cancel(Loc.T("FL n'est plus au premier plan"));
        _fl.Log("CLICK", $"mouse {m.Button.Raw()}{(m.Twice ? " double" : "")} ({p.X},{p.Y})");
        _lastClick = p;
        return new StepResult.Ok();
    }

    /// Clic en `p` seulement s'il tombe sur une fenêtre de FL tout devant (aucune autre appli ne la couvre).
    private StepResult ClickAt((int X, int Y) p, bool right, int hoverMs)
    {
        var (window, cover) = _fl.At(p.X, p.Y);
        if (window is null)
        {
            if (cover is not null) return new StepResult.Fail(Loc.F("« %@ » couvre FL à cet endroit", cover));
            _fl.Log("CLICK", $"refused ({p.X},{p.Y}): outside every FL window");
            return new StepResult.Fail(Loc.T("le point visé est hors de FL"));
        }
        if (StopReason() is { } stop) return new StepResult.Cancel(stop);
        _cursorBefore ??= _fl.Cursor();
        if (!_fl.Click(p.X, p.Y, right, hoverMs)) return new StepResult.Cancel(Loc.T("FL n'est plus au premier plan"));
        _fl.Log("CLICK", $"{(right ? "right" : "left")} ({p.X},{p.Y})");
        _lastClick = p;
        return new StepResult.Ok();
    }

    /// Clic gauche en `p` seulement si `p` est dans `popup`, que le menu est toujours là au même endroit et qu'il est la
    /// fenêtre de FL tout devant en `p` (survol d'abord : les menus de FL suivent le pointeur).
    private StepResult ClickInside((int X, int Y) p, FlWin popup, int hoverMs)
    {
        if (StopReason() is { } stop) return new StepResult.Cancel(stop);
        if (!_fl.Windows().Contains(popup)) return new StepResult.Fail(Loc.T("le menu de FL s'est fermé avant le clic"));
        if (p.X < popup.X + 2 || p.X >= popup.X + popup.Width - 2 || p.Y < popup.Y + 2 || p.Y >= popup.Y + popup.Height - 2)
            return new StepResult.Fail(Loc.T("point hors du menu : réapprends les clics"));
        var (window, cover) = _fl.At(p.X, p.Y);
        if (window != popup.Id)
            return new StepResult.Fail(cover is not null ? Loc.F("« %@ » couvre le menu de FL", cover) : Loc.T("une autre fenêtre de FL couvre le menu"));
        _cursorBefore ??= _fl.Cursor();
        if (!_fl.Click(p.X, p.Y, false, hoverMs)) return new StepResult.Cancel(Loc.T("FL n'est plus au premier plan"));
        _fl.Log("CLICK", $"in menu ({p.X},{p.Y})");
        _lastClick = p;
        return new StepResult.Ok();
    }

    /// Glisser : les deux endroits retrouvés (sans attente : la page de FL est déjà ouverte), dans FL et rien ne les
    /// couvre ; puis appui, glissé, relâché.
    private StepResult Drag(ClickTarget from, ClickTarget to)
    {
        if (!from.IsFinite || !to.IsFinite) return new StepResult.Fail(Loc.T("position invalide"));
        if (Locate(from) is not { Popup: null } a)
            return new StepResult.Fail(Loc.T("endroit où attraper introuvable : remontre le glisser"));
        if (Locate(to) is not { Popup: null } b)
            return new StepResult.Fail(Loc.T("endroit où lâcher introuvable : remontre le glisser"));
        foreach (var (x, y) in new[] { (a.X, a.Y), (b.X, b.Y) })
        {
            var (window, cover) = _fl.At(x, y);
            if (window is not null) continue;
            if (cover is not null) return new StepResult.Fail(Loc.F("« %@ » couvre FL à cet endroit", cover));
            _fl.Log("DRAG", $"refused ({x},{y}): outside every FL window");
            return new StepResult.Fail(Loc.T("le glisser sort de FL"));
        }
        if (StopReason() is { } stop) return new StepResult.Cancel(stop);
        _beforeLastClick = Ids();
        _cursorBefore ??= _fl.Cursor();
        if (!_fl.Drag(a.X, a.Y, b.X, b.Y)) return new StepResult.Cancel(Loc.T("FL n'est plus au premier plan"));
        _fl.Log("DRAG", $"({a.X},{a.Y}) → ({b.X},{b.Y})");
        _lastClick = (b.X, b.Y);
        return new StepResult.Ok();
    }

    // ---------- Menu de FL (FILE, EDIT, ADD… en haut de sa fenêtre) ----------

    /// Comme à la main : clic sur le titre en haut de FL, puis sur chaque élément dans le menu qui s'ouvre, retrouvé à
    /// son nom au moment du clic (lu par Windows dans un menu standard, sinon dans l'image du seul menu de FL). Un
    /// élément grisé n'est jamais cliqué ; après un échec, plus aucun menu ouvert par la macro ne reste. Journal : des
    /// niveaux et des nombres, jamais un titre.
    private StepResult MenuBar(IReadOnlyList<string> titles)
    {
        if (titles.Count < 2 || titles.Any(t => t.Trim().Length == 0)) return new StepResult.Fail(Loc.T("chemin de menu incomplet"));
        if (StopReason() is { } stop) return new StepResult.Cancel(stop);
        var bar = _fl.MenuBar();
        if (bar is not { Count: > 0 })
        {
            _fl.Log("MENU", "menu bar unreadable");
            return new StepResult.Fail(Loc.T("menu de FL illisible : mets FL devant"));
        }
        if (MenuText.Find(titles[0], bar) is not { } top)
        {
            _fl.Log("MENU", $"title not found among {bar.Count} item(s)");
            return new StepResult.Fail(Loc.T("élément introuvable dans le menu de FL"));
        }
        var before = Ids();
        _beforeLastClick = before;
        var opening = ClickAt((top.CenterX, top.CenterY), false, 60);
        if (opening is not StepResult.Ok) return opening;
        var (opened, menu) = NewWindow(before, FlWindowRole.Menu, MenuAppearMs);
        if (opened is StepResult.Cancel) return Abandon(opened);
        if (menu is not { } current)
        {
            _fl.Log("MENU", "level 1 did not open");
            return Abandon(new StepResult.Fail(Loc.T("le menu de FL attendu ne s'est pas ouvert")));
        }
        _fl.Log("MENU", "level 1 open");
        for (var level = 1; level < titles.Count; level++)
        {
            // Menu posé (même place deux fois de suite), puis son élément : un menu rempli à son ouverture (Add ›
            // Channel…) peut mettre un moment à montrer ses éléments.
            if (Settled(current.Id) is not { } settled)
                return Abandon(new StepResult.Fail(Loc.T("le menu de FL s'est fermé avant le clic")));
            current = settled;
            TextItem? entry = null;
            var count = 0;
            var deadline = _fl.Now.AddMilliseconds(2_000);
            while (true)
            {
                if (StopReason() is { } s) return Abandon(new StepResult.Cancel(s));
                var items = _fl.MenuItems(current.Id);
                count = items?.Count ?? 0;
                if (items is not null && MenuText.Find(titles[level], items) is { } e)
                {
                    entry = e;
                    break;
                }
                if (_fl.Now >= deadline || !AnyOpen(new HashSet<long> { current.Id })) break;
                _fl.Sleep(100);
            }
            if (entry is not { } item)
            {
                _fl.Log("MENU", $"item {level + 1} not found among {count}");
                return Abandon(new StepResult.Fail(Loc.T("élément introuvable dans le menu de FL")));
            }
            if (item.Greyed == true)
            {
                _fl.Log("MENU", $"item {level + 1} grayed out");
                return Abandon(new StepResult.Fail(Loc.T("élément grisé dans le menu de FL")));
            }
            var known = Ids();
            _beforeLastClick = known;
            var clicked = ClickInside((item.CenterX, item.CenterY), current, 80);
            if (clicked is not StepResult.Ok) return Abandon(clicked);
            if (level + 1 < titles.Count)
            {
                var (result, sub) = NewWindow(known, FlWindowRole.Menu, MenuAppearMs);
                if (result is StepResult.Cancel) return Abandon(result);
                if (sub is not { } next)
                {
                    _fl.Log("MENU", $"level {level + 1} did not open");
                    return Abandon(new StepResult.Fail(Loc.T("le menu de FL attendu ne s'est pas ouvert")));
                }
                _fl.Log("MENU", $"level {level + 1} open");
                current = next;
                continue;
            }
            // Dernier élément : FL referme ses menus. Encore ouverts : l'élément n'a rien fait (grisé ?).
            switch (Gone(MenusOpenedByMacro(), 1_500))
            {
                case StepResult.Ok:
                    _fl.Log("MENU", $"item {level + 1} chosen");
                    return new StepResult.Ok();
                case StepResult.Cancel c:
                    return Abandon(c);
                default:
                    _fl.Log("MENU", "menu stayed open after the last item");
                    return Abandon(new StepResult.Fail(item.Greyed == false
                        ? Loc.T("le menu de FL est resté ouvert")
                        : Loc.T("le menu de FL est resté ouvert")));
            }
        }
        return new StepResult.Ok();
    }

    /// Menus ouverts par la macro refermés (Échap, puis sans touche), et le résultat tel quel.
    private StepResult Abandon(StepResult result)
    {
        CloseMenus();
        _fl.CancelMenus();
        return result;
    }

    /// La fenêtre une fois posée (même place deux fois de suite, 0,4 s au plus) ; null si elle a disparu.
    private FlWin? Settled(long id)
    {
        FlWin? previous = null;
        var deadline = _fl.Now.AddMilliseconds(400);
        while (true)
        {
            var now = _fl.Windows().Where(w => w.Id == id).Cast<FlWin?>().FirstOrDefault();
            if (now is null) return null;
            if (now == previous || _fl.Now >= deadline) return now;
            previous = now;
            _fl.Sleep(40);
        }
    }

    // ---------- Plugin hors des favoris (« More plugins… ») ----------

    /// Pages de la liste lues au plus (une page : ce qu'on voit, puis la molette).
    private const int PluginListPages = 15;

    /// D'abord le menu Add de FL lui-même (comme le Mac, 09/11) : un plugin qui y est (favori de FL) est pris là, comme à
    /// la main, sans parcourir la liste. Sinon Add › Channel (ou Effect) › More plugins..., le nom tapé dans « Find » de
    /// la liste (sans « Find » lisible, la liste défile), puis le plugin retrouvé dans la liste (ligne lue d'un seul
    /// tenant ou avec l'étoile comprise, format préféré : PluginListPick) et double-cliqué au milieu de son nom : FL
    /// l'ouvre. Jamais la case devant le nom (elle en ferait un favori). Rien n'est ajouté aux listes de FL (demande du
    /// propriétaire, 28/10). Le nom n'est jamais journalisé.
    private StepResult AddFromPluginList(string plugin, string item)
    {
        switch (MenuBar(new[] { "Add", item, plugin }))
        {
            case StepResult.Ok:
                _fl.Log("PLUGIN", "taken from the Add menu");
                return new StepResult.Ok();
            case StepResult.Cancel cancelled:
                return cancelled;
        }
        _fl.Log("PLUGIN", "not in the Add menu: More plugins");
        var before = Ids();
        var opened = MenuBar(new[] { "Add", item, PageOptions.MorePlugins });
        if (opened is not StepResult.Ok) return opened;
        FlWin? list = null;
        var deadline = _fl.Now.AddMilliseconds(3_000);
        while (list is null)
        {
            if (StopReason() is { } stop) return new StepResult.Cancel(stop);
            list = _fl.Windows().Where(w => !before.Contains(w.Id) && w.Role != FlWindowRole.Menu && w.Width >= 320 && w.Height >= 200)
                .Cast<FlWin?>().FirstOrDefault();
            if (list is null && _fl.Now >= deadline) return new StepResult.Fail(Loc.T("la liste « More plugins… » de FL ne s'est pas ouverte"));
            if (list is null) _fl.Sleep(50);
        }
        var window = list.Value;
        _fl.Log("PLUGIN", $"plugin list {window.Width}x{window.Height}");
        if (SearchPluginList(window, plugin) is { } halted)
        {
            ClosePluginList(window);
            return new StepResult.Cancel(halted);
        }
        var prefer = PluginListPick.PreferredFormats(item);
        List<string>? previous = null;
        for (var page = 0; page < PluginListPages; page++)
        {
            if (StopReason() is { } stop)
            {
                ClosePluginList(window);
                return new StepResult.Cancel(stop);
            }
            if (_fl.ReadText(window.Id) is not { } items)
            {
                ClosePluginList(window);
                return new StepResult.Fail(Loc.T("liste « More plugins… » de FL illisible"));
            }
            if (PluginListPick.Best(plugin, prefer, items) is { } hit)
            {
                var at = PluginListPick.NamePoint(hit, plugin);
                _fl.Log("PLUGIN", $"found on page {page + 1}");
                _cursorBefore ??= _fl.Cursor();
                if (!_fl.DoubleClick(at.X, at.Y)) return new StepResult.Cancel(Loc.T("FL n'est plus au premier plan"));
                _lastClick = at;
                // La liste se ferme d'elle-même, ou reste ouverte : refermée (le plugin est ouvert).
                if (Gone(new HashSet<long> { window.Id }, 1_500, checkStop: false) is not StepResult.Ok) ClosePluginList(window);
                return new StepResult.Ok();
            }
            var texts = items.Select(t => t.Text).ToList();
            if (previous is not null && texts.SequenceEqual(previous)) break;             // bas de la liste
            previous = texts;
            _cursorBefore ??= _fl.Cursor();
            _fl.Scroll(window.X + window.Width / 2, window.Y + window.Height / 2, -3);
            _fl.Sleep(200);
        }
        ClosePluginList(window);
        _fl.Log("PLUGIN", "not found in the list");
        return new StepResult.Fail(Loc.T("plugin introuvable dans « More plugins… » de FL : vérifie son nom, ou choisis-le de nouveau dans « Cliquer sur… »"));
    }

    /// « Find » de la liste cliqué, puis le nom du plugin tapé (comme le Mac) : dans la petite fenêtre que FL ouvre alors
    /// (validée par Entrée), ou dans la liste elle-même. Rien si « Find » n'est pas lu ou si le nom ne peut pas être
    /// tapé : la liste défile. null, ou la raison d'un arrêt (Échap).
    private string? SearchPluginList(FlWin list, string plugin)
    {
        if (_fl.ReadText(list.Id) is not { } items || PluginListPick.FindButton(items, list) is not { } find)
        {
            _fl.Log("PLUGIN", "no Find button read: the list scrolls");
            return null;
        }
        if (StopReason() is { } stop) return stop;
        var before = Ids();
        switch (ClickAt((find.CenterX, find.CenterY), false, 60))
        {
            case StepResult.Cancel { Why: var why }: return why;
            case StepResult.Fail:
                _fl.Log("PLUGIN", "Find not clicked: the list scrolls");
                return null;
        }
        FlWin? prompt = null;
        var until = _fl.Now.AddMilliseconds(800);
        while (prompt is null && _fl.Now < until)
        {
            if (StopReason() is { } halted) return halted;
            prompt = _fl.Windows().Where(w => !before.Contains(w.Id)).Cast<FlWin?>().FirstOrDefault();
            if (prompt is null) _fl.Sleep(30);
        }
        _fl.Sleep(200);
        // Touches du raccourci encore tenues : attendues relâchées (Ctrl + lettre ferait un raccourci de FL).
        for (var i = 0; i < 50 && _fl.ModifiersDown(); i++) _fl.Sleep(20);
        if (!_fl.TypeText(plugin))
        {
            _fl.Log("PLUGIN", "name not typed in Find: the list scrolls");
            if (prompt is { } open) { _fl.Send(new KeyCombo(Vk.Escape)); Gone(new HashSet<long> { open.Id }, 800, checkStop: false); }
            return StopReason();
        }
        if (prompt is { } window)
        {
            _fl.Send(new KeyCombo(Vk.Return));                                            // Entrée : la recherche est lancée
            Gone(new HashSet<long> { window.Id }, 1_500, checkStop: false);
        }
        _fl.Log("PLUGIN", $"name typed in Find ({(prompt is null ? "in the list" : "in its window")})");
        _fl.Sleep(400);
        return null;
    }

    /// Échap tant que la liste est encore là (jamais d'Échap à l'aveugle) : elle se referme.
    private void ClosePluginList(FlWin list)
    {
        for (var attempt = 0; attempt < 2 && AnyOpen(new HashSet<long> { list.Id }); attempt++)
        {
            if (!_fl.Send(new KeyCombo(Vk.Escape))) return;
            Gone(new HashSet<long> { list.Id }, 500, checkStop: false);
        }
    }
}
