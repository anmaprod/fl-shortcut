// Effets des macros sur Windows (miroir de Sources/FLShortcut/MacroEffectsMac.swift et MacroFLBlocks.swift, sans les
// clics pour l'instant). La logique est ici, les appels à Windows dans le pilote (IFlDriver, dans l'appli) : les blocs
// sont essayés sur un faux FL (MacroEffectsWindowsTests). Garde-fous, comme sur le Mac :
//  - FL au premier plan avant chaque touche ; Échap (même un appui bref) arrête la macro ;
//  - touches à FL seul, revérifiées contre la liste noire (Alt+F4, Ctrl+Q…) avant l'envoi ;
//  - lettres et flèches d'un menu seulement tant qu'un menu ouvert par la macro est là (sinon une lettre irait à FL :
//    clavier-piano…) ;
//  - boîte de dialogue et menus suivis par leurs fenêtres (absentes au départ), jamais par leur titre ;
//  - journal : des noms de blocs et des durées, jamais une touche, un titre ou un chemin.
// Un bloc pas encore fait pour Windows bloque sa macro dès la validation (`Unsupported`) : son raccourci reste à FL.
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
}

public sealed class MacroEffectsWindows : IMacroEffects
{
    private readonly IFlDriver _fl;
    /// Fenêtres visibles au départ : ce qui n'y est pas a été ouvert par la macro.
    private HashSet<long> _start = new();
    private int _escapesAtStart;
    /// Boîte de dialogue ouverte par la macro (« Attendre une fenêtre » → « Attendre sa fermeture »).
    private long? _dialog;
    private int _dialogsAtStart;

    public MacroEffectsWindows(IFlDriver fl) => _fl = fl;

    /// Bloc pas encore fait pour Windows : la raison (la macro est bloquée à la validation), sinon null.
    public static string? Unsupported(BlockBody body) => body switch
    {
        BlockBody.Click or BlockBody.Drag or BlockBody.TrackMenu or BlockBody.ChooseFile or BlockBody.DropFile
            or BlockBody.SelectInput or BlockBody.FeedbackCheck or BlockBody.SoundCard or BlockBody.PageOption
            or BlockBody.MenuBar or BlockBody.MenuAX or BlockBody.NameColor
            => Loc.F("bloc « %@ » pas encore pris en charge sur Windows.",
                body.Type is { } type ? BlockRegistry.Spec(type).Label : "?"),
        _ => null,
    };

    // ---------- Protocole IMacroEffects ----------

    public void Log(string tag, string text) => _fl.Log(tag, text);

    public string? Begin(bool startFeedbackEarly)
    {
        var windows = _fl.Windows();
        _start = windows.Select(w => w.Id).ToHashSet();
        _dialogsAtStart = windows.Count(w => w.Role == FlWindowRole.Dialog);
        _escapesAtStart = _fl.EscapePresses;
        _dialog = null;
        _fl.Log("START", $"{windows.Count} window(s), {_dialogsAtStart} dialog(s)");
        return null;
    }

    /// Pas encore de piste visée sur Windows (les blocs qui en ont besoin sont bloqués à la validation).
    public bool TargetTrackIsInFl() => false;

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

    public void Cleanup(RunState state) { }

    public StepResult Perform(BlockBody body, RunState state)
    {
        if (Unsupported(body) is { } missing) return new StepResult.Fail(missing);
        switch (body)
        {
            case BlockBody.Delay d:
                return Pause(d.Ms);
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
