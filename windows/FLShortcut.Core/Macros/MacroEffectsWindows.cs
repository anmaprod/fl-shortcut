// Effets des macros sur Windows (miroir de Sources/FLShortcut/MacroEffectsMac.swift et MacroFLBlocks.swift ; clics et
// Menu de FL dans MacroEffectsWindowsClicks.cs). La logique est ici, les appels à Windows dans le pilote (IFlDriver, dans
// l'appli) : les blocs sont essayés sur un faux FL (MacroEffectsWindowsTests). Garde-fous, comme sur le Mac :
//  - FL au premier plan avant chaque touche ; Échap (même un appui bref) arrête la macro ;
//  - touches à FL seul, revérifiées contre la liste noire (Alt+F4, Ctrl+Q…) avant l'envoi ;
//  - lettres et flèches d'un menu seulement tant qu'un menu ouvert par la macro est là (sinon une lettre irait à FL :
//    clavier-piano…) ;
//  - boîte de dialogue et menus suivis par leurs fenêtres (absentes au départ), jamais par leur titre ;
//  - clics seulement dans une fenêtre de FL tout devant au point visé (rien d'autre ne la couvre) ; pointeur remis
//    où il était à la fin ;
//  - textes de FL lus seulement au moment du clic, dans la fenêtre visée, jamais gardés ;
//  - journal : des noms de blocs, des nombres et des durées, jamais une touche, un titre, un texte lu ou un chemin.
// Un bloc pas encore fait pour Windows bloque sa macro dès la validation (`Unsupported`) : son raccourci reste à FL.
using FLShortcut.Core.Organizer;

namespace FLShortcut.Core.Macros;

public enum FlWindowRole { Main, Dialog, Menu, Other }

/// Fenêtre visible de FL : son identifiant (handle), son rôle et sa place. Jamais son titre (nom du projet).
public readonly record struct FlWin(long Id, FlWindowRole Role, int X, int Y, int Width, int Height);

/// Ce que les macros demandent à Windows et au lien avec FL (appli : Win32 et MIDI ; essais : un faux FL).
public interface IFlDriver
{
    void Log(string tag, string text);
    /// FL au premier plan.
    bool InFront();
    /// Appuis sur Échap vus depuis le lancement (un appui bref tombé entre deux lectures compte).
    int EscapePresses { get; }
    bool EscapeDown();
    bool ModifiersDown();
    bool AnyKeyDown();
    /// Combinaison envoyée à FL seul ; faux si FL n'est plus devant.
    bool Send(KeyCombo combo);
    /// Fenêtres visibles de FL, de la plus en avant à la plus en arrière.
    IReadOnlyList<FlWin> Windows();
    void Sleep(int ms);
    DateTime Now { get; }
    /// Actions du script, dans l'ordre (lien réveillé brièvement) : null si FL les a faites, sinon la raison.
    string? RunActions(IReadOnlyList<int> ids);
    /// Page de FL devant d'après le lien (null : inconnue, lien endormi).
    FlWindow? KnownPage { get; }
    /// Entrée après la dernière lettre d'un menu, apprise (clés de MacroValidation.LearnedEnterKeys seulement).
    bool? Learned(string key);
    void Learn(string key, bool? value);
    /// Ouvre la fenêtre de l'Organiser (elle a ses propres garde-fous).
    void OpenOrganizer();
    /// Pointeur de la souris (pixels de l'écran).
    (int X, int Y) Cursor();
    /// Pointeur remis là (fin de macro : là où l'utilisateur l'avait laissé).
    void MoveCursor(int x, int y);
    /// Fenêtre de FL tout devant en ce point ; sinon null, et le nom du programme qui couvre FL là (null : rien).
    (long? Window, string? Cover) At(int x, int y);
    /// Clic en ce point (survol `hoverMs`, appui, relâché) ; faux si FL n'est plus devant.
    bool Click(int x, int y, bool right, int hoverMs);
    /// Appui en (ax, ay), glissé, relâché en (bx, by) (le bouton est toujours relâché) ; faux si FL n'est plus devant.
    bool Drag(int ax, int ay, int bx, int by);
    /// Titres de la barre des menus de FL (en haut de sa fenêtre principale), lus maintenant ; null : illisibles.
    IReadOnlyList<TextItem>? MenuBar();
    /// Éléments du menu de FL ouvert dans cette fenêtre, lus maintenant ; null : illisibles.
    IReadOnlyList<TextItem>? MenuItems(long window);
    /// Textes lus dans cette fenêtre de FL, maintenant ; null : illisible.
    IReadOnlyList<TextItem>? ReadText(long window);
    /// Menus de FL refermés sans touche (fin d'un Menu de FL raté : plus rien de surligné en haut de FL).
    void CancelMenus();
    /// Dernier clic de l'utilisateur dans une fenêtre normale de FL, s'il est récent (la piste visée).
    AimedClick? LastAimedClick { get; }
    /// Commande avec données du lien (PROTOCOL.md §7 : Nom et couleur), lien réveillé brièvement.
    DataReply RunData(IReadOnlyList<byte> units);
    /// Opération 2 à 26 du lien (PROTOCOL.md §8 : dégradé), lien réveillé brièvement.
    RequestReply RunRequest(byte[] bytes);
    /// Lien avec FL installé (clé et ports MIDI) : sinon, ses commandes échoueraient après une attente.
    bool LinkInstalled { get; }
    /// Fichier glissé depuis l'Explorateur et déposé en ce point de FL ; null si FL l'a pris, sinon la raison.
    string? DropFile(string path, int x, int y);
    /// Chemin écrit dans la boîte « Open » de FL (cette fenêtre), puis Ouvrir ; null si elle s'est refermée, sinon la
    /// raison.
    string? ChooseFile(long dialog, string path);
}

public sealed partial class MacroEffectsWindows : IMacroEffects
{
    private readonly IFlDriver _fl;
    /// Fenêtres visibles au départ : ce qui n'y est pas a été ouvert par la macro.
    private HashSet<long> _start = new();
    private List<FlWin> _startWindows = new();
    private int _escapesAtStart;
    /// Boîte de dialogue ouverte par la macro (« Attendre une fenêtre » → « Attendre sa fermeture »).
    private long? _dialog;
    private int _dialogsAtStart;

    public MacroEffectsWindows(IFlDriver fl) => _fl = fl;

    /// Bloc pas encore fait pour Windows : la raison (la macro est bloquée à la validation), sinon null.
    public static string? Unsupported(BlockBody body) => body switch
    {
        BlockBody.Click { Target: ClickTarget.Button } or BlockBody.Drag { From: ClickTarget.Button }
            or BlockBody.Drag { To: ClickTarget.Button }
            => Loc.T("bouton retrouvé à son image : pas encore sur Windows (montre de nouveau le clic sur ce PC)."),
        BlockBody.PageOption { Option: { } id } when PageOptions.Option(id)?.Kind is Macros.PageOption.OptionKind.Arrangement
            => Loc.T("menu « Arrangement » de la Playlist : pas encore sur Windows."),
        BlockBody.SelectInput or BlockBody.FeedbackCheck or BlockBody.SoundCard or BlockBody.MenuAX
            => Loc.F("bloc « %@ » pas encore pris en charge sur Windows.",
                body.Type is { } type ? BlockRegistry.Spec(type).Label : "?"),
        _ => null,
    };

    // ---------- Protocole IMacroEffects ----------

    public void Log(string tag, string text) => _fl.Log(tag, text);

    public string? Begin(bool startFeedbackEarly)
    {
        var windows = _fl.Windows();
        _startWindows = windows.ToList();
        _start = windows.Select(w => w.Id).ToHashSet();
        _dialogsAtStart = windows.Count(w => w.Role == FlWindowRole.Dialog);
        _escapesAtStart = _fl.EscapePresses;
        _dialog = null;
        _fl.Log("START", $"{windows.Count} window(s), {_dialogsAtStart} dialog(s)");
        BeginClicks(windows);
        return null;
    }

    /// La piste visée (dernier clic dans FL, sinon le pointeur au départ) est dans une fenêtre de FL (relevé du départ).
    public bool TargetTrackIsInFl() => _startWindows.Any(w => w.Role != FlWindowRole.Menu && Contains(w, _track));

    /// Aucune touche de modification enfoncée ; une autre touche tenue ne retarde pas plus de 0,3 s. Faux seulement
    /// si des touches de modification restent enfoncées.
    public bool WaitForKeyboardIdle(TimeSpan timeout)
    {
        var start = _fl.Now;
        DateTime? modsUpAt = null;
        var modsUp = false;
        while (_fl.Now - start < timeout)
        {
            modsUp = !_fl.ModifiersDown();
            if (modsUp)
            {
                if (!_fl.AnyKeyDown()) return true;
                modsUpAt ??= _fl.Now;
                if (_fl.Now - modsUpAt.Value > TimeSpan.FromMilliseconds(300)) break;
            }
            else modsUpAt = null;
            _fl.Sleep(10);
        }
        _fl.Log("KEYS", modsUp ? "a key is still down → going on" : "modifiers still held");
        return modsUp;
    }

    public string? StopReason()
    {
        if (!_fl.InFront()) return Loc.T("FL n'est plus au premier plan");
        if (_fl.EscapeDown() || _fl.EscapePresses != _escapesAtStart) return Loc.T("Échap");
        return null;
    }

    public StepResult Pause(int ms)
    {
        var left = ms;
        while (left > 0)
        {
            if (StopReason() is { } stop) return new StepResult.Cancel(stop);
            var slice = Math.Min(left, 50);
            _fl.Sleep(slice);
            left -= slice;
        }
        return new StepResult.Ok();
    }

    /// Pointeur remis où l'utilisateur l'avait laissé, s'il a été déplacé par un clic.
    public void Cleanup(RunState state)
    {
        if (_cursorBefore is not { } p) return;
        _cursorBefore = null;
        _fl.MoveCursor(p.X, p.Y);
    }

    public StepResult Perform(BlockBody body, RunState state)
    {
        if (Unsupported(body) is { } missing) return new StepResult.Fail(missing);
        switch (body)
        {
            case BlockBody.Delay d:
                return Pause(d.Ms);
            case BlockBody.Click c:
                return Click(c.Target, c.Button == MouseButton.Right);
            case BlockBody.Drag d:
                return Drag(d.From, d.To);
            case BlockBody.MenuBar m:
                return MenuBar(m.Titles);
            case BlockBody.Key k:
                return Key(k.Ref, k.Times);
            case BlockBody.MenuKeyPress m:
                return MenuKey(m.MenuKey, m.Times);
            case BlockBody.MenuLetters l:
                return MenuLetters(l.Letters, l.FinalEnter);
            case BlockBody.WaitWindow { Window: WindowKind.Dialog } w:
                return WaitDialogOpen(w.TimeoutMs);
            case BlockBody.WaitWindow w:
                return WaitMenuOpen(w.TimeoutMs);
            case BlockBody.WaitWindowClose { Window: WindowKind.Dialog } w:
                return WaitDialogClosed(w.TimeoutMs);
            case BlockBody.WaitWindowClose w:
                return WaitMenuClosed(w.TimeoutMs);
            case BlockBody.FlAction a:
                return FlActions(new[] { new FlActionCall(a.ActionKey, a.Fallback) }, state);
            case BlockBody.FlActionValue:
                return new StepResult.Fail(Loc.T("action avec valeur : demande l'extension du lien avec FL"));
            case BlockBody.OpenPage p:
                return OpenPage(p.Page, state);
            case BlockBody.NameColor n:
                return NameColor(n);
            case BlockBody.PageOption p:
                return ClickOn(p, state);
            case BlockBody.TrackMenu t:
                return TrackMenu(t);
            case BlockBody.DropFile d:
                return DropFile(d.Path);
            case BlockBody.ChooseFile c:
                return ChooseFile(c.Path);
            case BlockBody.Organize:
                // La suite se passe dans la fenêtre de l'Organiser (ses propres garde-fous).
                _fl.Log("FL", "organizer opened");
                _fl.OpenOrganizer();
                return new StepResult.Ok();
            default:
                return new StepResult.Fail(Loc.T("bloc inconnu."));
        }
    }

    public StepResult FlActions(IReadOnlyList<FlActionCall> group, RunState state)
    {
        var ids = group.Select(c => Core.FlActions.IdForKey(c.Key)).ToList();
        if (ids.Count == 0 || ids.Any(id => id is null)) return new StepResult.Fail(Loc.T("action de FL inconnue"));
        if (_fl.RunActions(ids.Select(id => id!.Value).ToList()) is not { } why)
        {
            _fl.Log("MIDI", $"{group.Count} action(s) acknowledged");
            return new StepResult.Ok();
        }
        _fl.Log("MIDI", "unavailable → keyboard");
        var warnings = new List<string>();
        foreach (var call in group)
        {
            switch (call.Fallback.Kind)
            {
                case "key" when call.Fallback.KeyRef is { } key:
                {
                    if (StopReason() is { } stop) return new StepResult.Cancel(stop);
                    var rec = call.Key == "recon";
                    if (MacKeys.ToWindows(key) is not { } combo || ForbiddenTargets.IsForbidden(combo))
                    {
                        warnings.Add(rec ? Loc.T("REC non lancé (touche interdite)")
                                         : Loc.F("action « %@ » non faite (touche interdite)", call.Key));
                        break;
                    }
                    _fl.Sleep(30);
                    if (!_fl.Send(combo)) return new StepResult.Cancel(Loc.T("FL n'est plus au premier plan"));
                    _fl.Log("KEY", rec ? "REC key" : "fallback key");
                    break;
                }
                case "trackMenuArm":
                    warnings.Add(Loc.F("armement non fait : %@", Loc.T("pas encore sur Windows")));
                    break;
                default:
                    return new StepResult.Fail(Loc.F("ce bloc a besoin du lien avec FL (%@)", why));
            }
        }
        return warnings.Count == 0 ? new StepResult.Ok() : new StepResult.Warn(string.Join(" ; ", warnings));
    }

    public ConditionAnswer Evaluate(Condition c, RunState state) => c switch
    {
        Condition.WindowOpen { Window: WindowKind.Dialog } => ConditionAnswer.Of(FreshDialog() is not null),
        Condition.WindowOpen => ConditionAnswer.Of(MenusOpenedByMacro().Count > 0),
        Condition.FlState => ConditionAnswer.Fail(Loc.T("condition sur l'état de FL : demande l'extension du lien avec FL")),
        _ => ConditionAnswer.Fail(Loc.T("condition évaluée par l'interpréteur")),
    };

    // ---------- Touches ----------

    private StepResult Key(KeyRef key, int times)
    {
        if (MacKeys.ToWindows(key) is not { } combo) return new StepResult.Fail(Loc.T("touche non prise en charge"));
        if (ForbiddenTargets.IsForbidden(combo)) return new StepResult.Fail(Loc.T("touche interdite"));
        for (var i = 0; i < Math.Max(times, 1); i++)
        {
            if (i > 0) _fl.Sleep(15);
            if (StopReason() is { } stop) return new StepResult.Cancel(stop);
            if (!_fl.Send(combo)) return new StepResult.Cancel(Loc.T("FL n'est plus au premier plan"));
            _fl.Log("KEY", "key sent (hidden)");
        }
        return new StepResult.Ok();
    }

    /// Flèche, Entrée ou Échap, seulement tant qu'un menu ouvert par la macro est là.
    private StepResult MenuKey(MenuKey key, int times)
    {
        var opened = MenusOpenedByMacro();
        if (opened.Count == 0) return new StepResult.Fail(Loc.T("aucun menu de FL ouvert par la macro"));
        for (var i = 0; i < Math.Max(times, 1); i++)
        {
            if (!AnyOpen(opened))
                return i > 0 && key is Macros.MenuKey.Enter or Macros.MenuKey.Escape
                    ? new StepResult.Ok() : new StepResult.Fail(Loc.T("le menu de FL s'est fermé"));
            if (StopReason() is { } stop) return new StepResult.Cancel(stop);
            if (!_fl.Send(new KeyCombo(key.Vk()))) return new StepResult.Cancel(Loc.T("FL n'est plus au premier plan"));
            _fl.Log("KEY", "menu key " + key.Raw());
            _fl.Sleep(15);
        }
        return new StepResult.Ok();
    }

    private static ushort? LetterVk(char c) => c is >= 'a' and <= 'z' ? Vk.Letter(char.ToUpperInvariant(c)) : null;

    /// Lettres soulignées dans un menu ouvert par la macro (chaque lettre seulement si un de ces menus est encore là),
    /// puis Entrée selon la règle du bloc.
    private StepResult MenuLetters(string letters, EnterPolicy enter)
    {
        var opened = MenusOpenedByMacro();
        if (opened.Count == 0) return new StepResult.Fail(Loc.T("aucun menu de FL ouvert par la macro"));
        var lower = letters.ToLowerInvariant();
        if (lower.Length == 0 || lower.Any(c => LetterVk(c) is null)) return new StepResult.Fail(Loc.T("lettre de menu non prise en charge"));
        for (var i = 0; i < lower.Length; i++)
        {
            if (!AnyOpen(opened)) return new StepResult.Fail(Loc.T("le menu de FL s'est fermé tout seul"));
            if (StopReason() is { } stop) return new StepResult.Cancel(stop);
            var known = _fl.Windows().Select(w => w.Id).ToHashSet();
            if (!_fl.Send(new KeyCombo(LetterVk(lower[i])!.Value))) return new StepResult.Cancel(Loc.T("FL n'est plus au premier plan"));
            _fl.Log("KEY", "menu letter");
            if (i + 1 == lower.Length) break;
            // La lettre a pu ouvrir un sous-menu (suivi avec les autres), ou seulement surligner son élément.
            var (result, sub) = NewWindow(known, FlWindowRole.Menu, 600);
            if (result is StepResult.Cancel c) return c;
            if (sub is { } s) opened.Add(s.Id);
        }
        if (enter.Mode == "never") return new StepResult.Ok();
        var needsEnter = ReadEnter(enter);
        if (needsEnter != true)
        {
            switch (Gone(opened, needsEnter == false ? 800 : 500))
            {
                case StepResult.Ok:
                    WriteEnter(enter, false);
                    return new StepResult.Ok();
                case StepResult.Cancel c:
                    return c;
            }
        }
        else
        {
            Gone(opened, 120);
            if (!AnyOpen(opened))
            {
                WriteEnter(enter, false);
                return new StepResult.Ok();
            }
        }
        if (!_fl.Send(new KeyCombo(Vk.Return))) return new StepResult.Cancel(Loc.T("FL n'est plus au premier plan"));
        switch (Gone(opened, 800))
        {
            case StepResult.Ok:
                WriteEnter(enter, true);
                return new StepResult.Ok();
            case StepResult.Cancel c:
                return c;
            default:
                CloseMenus();
                WriteEnter(enter, null);
                return new StepResult.Fail(Loc.T("le menu de FL n'a pas répondu"));
        }
    }

    private bool? ReadEnter(EnterPolicy p) => p.Mode switch
    {
        "learned" when p.LegacyKey is { } key && MacroValidation.LearnedEnterKeys.Contains(key) => _fl.Learned(key),
        "always" => true,
        _ => null,
    };

    private void WriteEnter(EnterPolicy p, bool? value)
    {
        if (p.Mode == "learned" && p.LegacyKey is { } key && MacroValidation.LearnedEnterKeys.Contains(key)) _fl.Learn(key, value);
    }

    /// Échap sur les menus ouverts par la macro (3 fois au plus) : jamais un menu laissé ouvert après un échec.
    private void CloseMenus()
    {
        for (var attempt = 1; attempt <= 3; attempt++)
        {
            var open = MenusOpenedByMacro();
            if (open.Count == 0) return;
            _fl.Log("ESC", $"attempt {attempt}: {open.Count} menu(s)");
            if (!_fl.Send(new KeyCombo(Vk.Escape))) return;
            Gone(new HashSet<long> { open.First() }, 300, checkStop: false);
        }
    }

    // ---------- Fenêtres ----------

    private HashSet<long> MenusOpenedByMacro() =>
        _fl.Windows().Where(w => w.Role == FlWindowRole.Menu && !_start.Contains(w.Id)).Select(w => w.Id).ToHashSet();

    private bool AnyOpen(IReadOnlySet<long> ids) => _fl.Windows().Any(w => ids.Contains(w.Id));

    private FlWin? FreshDialog() =>
        _fl.Windows().Where(w => w.Role == FlWindowRole.Dialog && !_start.Contains(w.Id)).Cast<FlWin?>().FirstOrDefault();

    /// Attend une fenêtre de ce rôle absente de `known` : Ok et la fenêtre, Cancel, ou Fail (délai passé).
    private (StepResult Result, FlWin? Window) NewWindow(IReadOnlySet<long> known, FlWindowRole role, int timeoutMs)
    {
        var deadline = _fl.Now.AddMilliseconds(timeoutMs);
        while (true)
        {
            if (StopReason() is { } stop) return (new StepResult.Cancel(stop), null);
            var fresh = _fl.Windows().Where(w => w.Role == role && !known.Contains(w.Id)).Cast<FlWin?>().FirstOrDefault();
            if (fresh is not null) return (new StepResult.Ok(), fresh);
            if (_fl.Now >= deadline) return (new StepResult.Fail(""), null);
            _fl.Sleep(30);
        }
    }

    /// Attend que toutes ces fenêtres aient disparu : Ok, Cancel, ou Fail (délai passé).
    private StepResult Gone(IReadOnlySet<long> ids, int timeoutMs, bool checkStop = true)
    {
        var deadline = _fl.Now.AddMilliseconds(timeoutMs);
        while (true)
        {
            if (checkStop && StopReason() is { } stop) return new StepResult.Cancel(stop);
            if (!AnyOpen(ids)) return new StepResult.Ok();
            if (_fl.Now >= deadline) return new StepResult.Fail("");
            _fl.Sleep(timeoutMs > 10_000 ? 50 : 30);
        }
    }

    private StepResult WaitDialogOpen(int timeoutMs)
    {
        var (result, dialog) = NewWindow(_start, FlWindowRole.Dialog, timeoutMs);
        if (result is StepResult.Cancel) return result;
        if (dialog is not { } d)
        {
            _fl.Log("DIALOG", $"none after {timeoutMs} ms");
            return new StepResult.Fail(Loc.T("boîte de dialogue introuvable"));
        }
        _dialog = d.Id;
        _fl.Log("DIALOG", "opened");
        return new StepResult.Ok();
    }

    private StepResult WaitDialogClosed(int timeoutMs)
    {
        var failure = Loc.T("la boîte de dialogue ne se ferme pas");
        if (_dialog is not { } id)
        {
            // Aucune boîte suivie : pas plus de boîtes qu'au départ.
            var deadline = _fl.Now.AddMilliseconds(timeoutMs);
            while (true)
            {
                if (StopReason() is { } stop) return new StepResult.Cancel(stop);
                if (_fl.Windows().Count(w => w.Role == FlWindowRole.Dialog) <= _dialogsAtStart) return new StepResult.Ok();
                if (_fl.Now >= deadline) return new StepResult.Fail(failure);
                _fl.Sleep(timeoutMs > 10_000 ? 100 : 30);
            }
        }
        var gone = Gone(new HashSet<long> { id }, timeoutMs);
        if (gone is StepResult.Cancel) return gone;
        if (gone is not StepResult.Ok) return new StepResult.Fail(failure);
        _fl.Log("DIALOG", "closed");
        _dialog = null;
        return gone;
    }

    private StepResult WaitMenuOpen(int timeoutMs)
    {
        var (result, menu) = NewWindow(_start, FlWindowRole.Menu, timeoutMs);
        if (result is StepResult.Cancel) return result;
        if (menu is null) return new StepResult.Fail(Loc.T("aucun menu de FL ne s'est ouvert"));
        _lastMenu = menu;                                    // repère des clics « menu ouvert »
        _fl.Log("MENU", "menu open");
        return result;
    }

    private StepResult WaitMenuClosed(int timeoutMs)
    {
        var open = MenusOpenedByMacro();
        if (open.Count == 0) return new StepResult.Ok();
        var gone = Gone(open, timeoutMs);
        if (gone is StepResult.Cancel) return gone;
        if (gone is not StepResult.Ok) return new StepResult.Fail(Loc.T("le menu de FL est resté ouvert"));
        _fl.Log("MENU", "menus closed");
        return gone;
    }

    // ---------- Nom et couleur ----------

    /// Dégradé de la première à la dernière couleur sur les éléments sélectionnés (opération 8), ou nom et couleur de
    /// l'élément sélectionné (opération 1), par le lien avec FL. L'icône (fenêtre F2 de FL) n'est pas encore posée sous
    /// Windows : dit, le reste est fait. Journal : jamais le nom.
    private StepResult NameColor(BlockBody.NameColor n)
    {
        if (n.Color is { } from && n.Fade is { } to)
        {
            _fl.Log("FL", "gradient");
            return _fl.RunRequest(OrganizerPayload.Gradient(from, to)) switch
            {
                RequestReply.Answered => new StepResult.Ok(),
                RequestReply.Refused r => new StepResult.Fail(NameColorPayload.Message(r.Reason)),
                RequestReply.Failed f => new StepResult.Fail(f.Why),
                _ => new StepResult.Fail("?"),
            };
        }
        var payload = new NameColorPayload(n.Name, n.Color);
        if (payload.Name is not null || payload.Color is not null)
        {
            _fl.Log("FL", $"name/color ({(payload.Name is null ? "no name" : "name")} · {(payload.Color is null ? "no color" : "color")})");
            switch (_fl.RunData(Pack7.Pack(payload.Bytes)))
            {
                case DataReply.Done:
                    break;
                case DataReply.Refused r:
                    return new StepResult.Fail(NameColorPayload.Message(r.Reason));
                case DataReply.Failed f:
                    return new StepResult.Fail(f.Why);
            }
        }
        return n.Icon is null ? new StepResult.Ok() : new StepResult.Warn(Loc.T("icône pas encore posée sous Windows (pose-la dans FL avec F2)"));
    }

    // ---------- Menu de la piste, preset ----------

    /// Clic droit sur la piste visée (ou là où était le pointeur), puis les lettres soulignées de l'élément choisi (File
    /// › Open mixer track state…) dans le menu qui s'ouvre, et Entrée selon la règle du bloc.
    private StepResult TrackMenu(BlockBody.TrackMenu t)
    {
        var letters = t.Letters.ToLowerInvariant();
        if (letters.Length == 0 || letters.Any(c => LetterVk(c) is null)) return new StepResult.Fail(Loc.T("menu de piste mal décrit"));
        if (!WaitForKeyboardIdle(TimeSpan.FromSeconds(1.5))) return new StepResult.Cancel(Loc.T("relâche les touches du raccourci"));
        var before = _fl.Windows().Select(w => w.Id).ToHashSet();
        var target = t.Target == TrackTarget.Cursor ? _origin : _track;
        var clicked = ClickAt(target, true, 30);
        if (clicked is not StepResult.Ok) return clicked;
        var (opened, menu) = NewWindow(before, FlWindowRole.Menu, 1_500);
        if (opened is StepResult.Cancel)
        {
            CloseMenus();
            return opened;
        }
        if (menu is not { } m)
            return new StepResult.Fail(Loc.T("le menu de la piste ne s'est pas ouvert (clique sur le nom de ta piste dans le Mixer)"));
        _fl.Log("MENU", $"track menu {m.Width}x{m.Height}");
        // FL place souvent son menu sous le pointeur : son survol ouvrirait un sous-menu tout seul.
        HoverOutside(m);
        return MenuLetters(letters, t.FinalEnter);
    }

    /// Pointeur juste à côté du menu (à gauche, sinon à droite) : plus aucun élément survolé.
    private void HoverOutside(FlWin menu)
    {
        _cursorBefore ??= _fl.Cursor();
        var x = menu.X >= 24 ? menu.X - 24 : menu.X + menu.Width + 24;
        _fl.MoveCursor(x, menu.Y + 12);
        _fl.Sleep(40);
    }

    /// Échec si le preset n'est pas un fichier existant (nom du fichier seulement, jamais le chemin), sinon null.
    private static StepResult? MissingPreset(string path)
    {
        if (path.Length > 0 && File.Exists(path)) return null;
        return new StepResult.Fail(Loc.F("preset introuvable (%@)", Path.GetFileName(path)));
    }

    /// Preset glissé sur la piste visée, comme depuis l'Explorateur : dans une fenêtre de FL que rien ne couvre.
    private StepResult DropFile(string path)
    {
        _fl.Log("FILE", $"preset dropped on the track ({path.Length} characters)");
        if (MissingPreset(path) is { } missing) return missing;
        var (window, cover) = _fl.At(_track.X, _track.Y);
        if (window is null)
        {
            if (cover is not null) return new StepResult.Fail(Loc.F("« %@ » couvre FL à cet endroit", cover));
            _fl.Log("DROP", "refused: outside every FL window");
            return new StepResult.Fail(Loc.T("la piste visée est hors de FL : clique d'abord sur ta piste dans le Mixer"));
        }
        if (StopReason() is { } stop) return new StepResult.Cancel(stop);
        _cursorBefore ??= _fl.Cursor();
        if (_fl.DropFile(path, _track.X, _track.Y) is { } why) return new StepResult.Fail(why);
        _lastClick = _track;
        return new StepResult.Ok();
    }

    /// Chemin du preset dans la boîte « Open » ouverte par la macro (suivie par « Attendre une fenêtre »), sinon la
    /// boîte apparue depuis le départ. Le chemin n'est jamais journalisé (seulement sa longueur).
    private StepResult ChooseFile(string path)
    {
        _fl.Log("FILE", $"preset path typed ({path.Length} characters)");
        if (MissingPreset(path) is { } missing) return missing;
        if ((_dialog ?? FreshDialog()?.Id) is not { } dialog) return new StepResult.Fail(Loc.T("boîte « Open » introuvable"));
        if (StopReason() is { } stop) return new StepResult.Cancel(stop);
        if (_fl.ChooseFile(dialog, path) is { } why) return new StepResult.Fail(why);
        if (_dialog == dialog) _dialog = null;
        _fl.Log("DIALOG", "file chosen, dialog closed");
        return new StepResult.Ok();
    }

    // ---------- « Cliquer sur… » ----------

    /// Option d'une page de FL : action du lien ou touche de FL, menu Add de FL (plugin), mute/solo d'un canal, nouveau
    /// nom de la piste. Journal : l'option, jamais le nom du plugin ni celui de la piste.
    private StepResult ClickOn(BlockBody.PageOption p, RunState state)
    {
        if (p.Option is not { } id || PageOptions.Option(id) is not { } option)
            return new StepResult.Fail(Loc.T("option de FL à choisir dans la macro"));
        _fl.Log("FL", $"page option {id}");
        switch (option.Kind)
        {
            case Macros.PageOption.OptionKind.ChannelToggle t:
                return PageOptions.Channel(p.Name) is { } number ? ToggleChannel(number, t.Solo)
                    : new StepResult.Fail(Loc.T("numéro du canal à écrire dans « Cliquer sur… »"));
            case Macros.PageOption.OptionKind.Rename:
                return RenameTrack(p.Name);
        }
        if (PageOptions.Body(option, p.Name) is not { } body) return new StepResult.Fail(Loc.T("option inconnue"));
        var result = Perform(body, state);
        // Plugin pas dans le menu Add : le dire comme tel (FL peut le ranger ailleurs, ou il a été désinstallé).
        if (option.Field == PageField.Plugin && result is StepResult.Fail { Why: var why }
            && why == Loc.T("élément introuvable dans le menu de FL (renommé, ou FL dans une autre langue ?)"))
            return new StepResult.Fail(Loc.T("plugin introuvable dans le menu Add de FL : choisis-le de nouveau dans « Cliquer sur… »"));
        return result;
    }

    /// Mute ou solo d'un canal : par le lien (tous les canaux), sinon la touche 1 à 0 de FL (canaux 1 à 10).
    private StepResult ToggleChannel(int number, bool solo)
    {
        var what = solo ? "solo" : "mute";
        var key = PageOptions.ChannelKey(number, solo);
        if (key is null || _fl.LinkInstalled)
        {
            switch (_fl.RunRequest(OrganizerPayload.ToggleChannel(number - 1, solo)))
            {
                case RequestReply.Answered:
                    _fl.Log("FL", $"channel {what} by link");
                    return new StepResult.Ok();
                case RequestReply.Refused { Reason: 5 } when key is null:
                    return new StepResult.Fail(Loc.F("canal %lld absent du Channel rack (ou script de FL pas à jour : redémarre FL)", number));
                case RequestReply.Refused r when key is null:
                    return new StepResult.Fail(Loc.F("FL a refusé le %@ du canal (raison %lld)", what, r.Reason));
                case RequestReply.Failed f when key is null:
                    return new StepResult.Fail(f.Why + Loc.T(" (au-delà du canal 10, seul le lien avec FL le fait)"));
                default:
                    _fl.Log("FL", $"channel {what}: link unavailable, FL key");
                    break;
            }
        }
        if (key is null) return new StepResult.Fail(Loc.F("canal %lld : lien avec FL nécessaire", number));
        return Key(key, 1);
    }

    /// Nouveau nom de la piste sélectionnée, posé par le script de FL (opération 1 : rien n'est tapé). Le nom n'est
    /// jamais journalisé.
    private StepResult RenameTrack(string name)
    {
        var payload = new NameColorPayload(name, null);
        if (payload.Name is null) return new StepResult.Fail(Loc.T("nouveau nom de la piste à écrire dans « Cliquer sur… »"));
        switch (_fl.RunData(Pack7.Pack(payload.Bytes)))
        {
            case DataReply.Done:
                _fl.Log("FL", "track renamed by link");
                return new StepResult.Ok();
            case DataReply.Refused r:
                return new StepResult.Fail(NameColorPayload.Message(r.Reason));
            case DataReply.Failed f:
                return new StepResult.Fail(f.Why);
            default:
                return new StepResult.Fail("?");
        }
    }

    // ---------- Pages de FL ----------

    /// Déjà devant (le lien le sait) : rien à faire. Lien endormi : tout de suite la touche de FL (F5, F6, F7, F9,
    /// Alt+F8), sans attendre un lien qui ne répond pas. Sinon le lien la met devant (sans jamais la fermer).
    private StepResult OpenPage(FlPage? page, RunState state)
    {
        if (page is not { } p) return new StepResult.Fail(Loc.T("page de FL à choisir dans la macro"));
        var known = _fl.KnownPage;
        if (known == p.Window())
        {
            _fl.Log("FL", $"page {p.Raw()} already in front");
            return new StepResult.Ok();
        }
        if (known is null && p.NativeKey() is { } key && MacKeys.ToWindows(key) is { } combo)
        {
            if (StopReason() is { } stop) return new StepResult.Cancel(stop);
            if (!_fl.Send(combo)) return new StepResult.Cancel(Loc.T("FL n'est plus au premier plan"));
            _fl.Log("FL", $"open page {p.Raw()} (key)");
            return new StepResult.Ok();
        }
        _fl.Log("FL", $"open page {p.Raw()}");
        return Perform(p.OpenBody(), state);
    }
}
