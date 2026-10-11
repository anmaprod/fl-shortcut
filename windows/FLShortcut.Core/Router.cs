// Audit : WIN-01 (aucune frappe conservée : seuls code VK + modificateurs entrent ici), REL-03 (index immuable),
//         REL-04 / SEC-11 (propriété d'un appui décidée au keyDown initial ; répétitions et keyUp suivent ;
//         état purgé et borné), REL-06 (touche « Action dans FL » avalée seulement si le lien est « Relié »),
//         REL-15 (pas d'action répétée), WIN-03 / SEC-05 (liste noire revérifiée avant chaque injection),
//         filtrage par fenêtre FL active, AltGr toujours laissé passer.
// Miroir de Sources/FLShortcut/KeyRouter.swift. Logique pure : testée par FLShortcut.Core.Tests.
namespace FLShortcut.Core;

/// Index immuable des raccourcis actifs : (déclencheur, contexte) → action.
public sealed class ShortcutIndex
{
    public sealed record Entry(Guid ShortcutId, RoutedAction Action);

    private readonly Dictionary<KeyCombo, Dictionary<ShortcutContext, Entry>> _table = new();

    public static readonly ShortcutIndex Empty = new(Array.Empty<Shortcut>(), new HashSet<Guid>());

    /// Les raccourcis doivent avoir été analysés : `blocked` contient les ids écartés (doublon, cible interdite…).
    public ShortcutIndex(IEnumerable<Shortcut> shortcuts, ISet<Guid> blocked)
    {
        foreach (var s in shortcuts)
        {
            if (!s.Enabled || blocked.Contains(s.Id) || s.Trigger is not { } trigger || s.Routed is not { } action) continue;
            if (!_table.TryGetValue(trigger, out var byCtx)) _table[trigger] = byCtx = new();
            byCtx.TryAdd(s.Context, new Entry(s.Id, action));      // le premier gagne (même règle que l'analyse)
        }
    }

    public int Count => _table.Values.Sum(d => d.Count);

    public bool ContainsTrigger(KeyCombo c) => _table.ContainsKey(c);

    /// Fenêtre précise d'abord, puis « Partout ». Fenêtre inconnue : seulement « Partout », sauf `anyContext`
    /// (mode léger : FL applique lui-même la touche envoyée à sa fenêtre active), où une entrée de n'importe
    /// quelle fenêtre convient, dans un ordre fixe.
    public Entry? Lookup(KeyCombo combo, FlWindow? window, bool anyContext = false)
    {
        if (!_table.TryGetValue(combo, out var byCtx)) return null;
        if (window is { } w && ShortcutContexts.FromWindow(w) is { } ctx && byCtx.TryGetValue(ctx, out var e)) return e;
        if (byCtx.TryGetValue(ShortcutContext.Everywhere, out var all)) return all;
        if (!anyContext) return null;
        foreach (var c in Enum.GetValues<ShortcutContext>())
            if (byCtx.TryGetValue(c, out var any)) return any;
        return null;
    }
}

/// Configuration poussée par le thread d'interface, remplacée en bloc (lecture sans verrou : référence immuable).
/// `ActionNatives` : mode léger, action → touche d'origine de FL (vide sinon) ; `AnyContext` : contexte de fenêtre ignoré.
public sealed record HookConfig(bool Enabled, ShortcutIndex Index, KeyCombo Toggle, bool Recording)
{
    public static readonly HookConfig Default = new(true, ShortcutIndex.Empty, ProfilePresets.Toggle, false);

    public IReadOnlyDictionary<int, KeyCombo> ActionNatives { get; init; } = new Dictionary<int, KeyCombo>();
    public bool AnyContext { get; init; }
}

/// Événement clavier réduit à ce qui sert à la décision.
public readonly record struct RouterInput(RouterInput.Kinds Kind, KeyCombo Combo, bool IsRepeat = false,
    bool IsOwn = false, bool TargetIsFl = false, bool AltGr = false)
{
    public enum Kinds { Down, Up, Reset }
}

public abstract record RouterEffect
{
    public sealed record SendAction(int Id) : RouterEffect;
    public sealed record Post(KeyCombo Combo) : RouterEffect;
    public sealed record ToggleEnabled : RouterEffect;
}

public sealed record RouterDecision(bool Swallow, IReadOnlyList<RouterEffect> Effects)
{
    public static readonly RouterDecision Pass = new(false, Array.Empty<RouterEffect>());
    public static readonly RouterDecision SwallowOnly = new(true, Array.Empty<RouterEffect>());
    public static RouterDecision Do(RouterEffect e) => new(true, new[] { e });
}

public sealed class KeyRouter
{
    private abstract record Owner
    {
        public sealed record Toggle : Owner;
        public sealed record Action(int Id) : Owner;
        public sealed record Keystroke(KeyCombo Target) : Owner;
    }

    /// Code VK → propriétaire de l'appui en cours. Au plus 256 entrées (codes bornés).
    private readonly Dictionary<ushort, Owner> _owned = new();

    public int OwnedCount => _owned.Count;

    public void Purge() => _owned.Clear();

    /// L'effet décidé n'a pas pu être produit : l'appui est rendu (REL-06 : jamais avaler sans effet).
    public void Release(ushort vk) => _owned.Remove(vk);

    public RouterDecision Route(RouterInput e, HookConfig config, LinkRoutingView link)
    {
        if (e.Kind == RouterInput.Kinds.Reset) { Purge(); return RouterDecision.Pass; }
        if (e.IsOwn) return RouterDecision.Pass;                 // nos propres injections : jamais retraitées
        var vk = e.Combo.Vk;
        if (vk == 0 || vk >= 0xFF) return RouterDecision.Pass;

        if (e.Kind == RouterInput.Kinds.Up)
            return _owned.Remove(vk) ? RouterDecision.SwallowOnly : RouterDecision.Pass;

        if (e.IsRepeat)
        {
            if (!_owned.TryGetValue(vk, out var owner)) return RouterDecision.Pass;
            if (owner is Owner.Keystroke ks)
            {
                if (!e.TargetIsFl || !config.Enabled || ForbiddenTargets.IsForbidden(ks.Target)) return RouterDecision.SwallowOnly;
                return RouterDecision.Do(new RouterEffect.Post(ks.Target));
            }
            return RouterDecision.SwallowOnly;                   // jamais de bascule ni d'action répétées
        }

        _owned.Remove(vk);                                       // keyDown neuf : un keyUp manqué n'empoisonne plus
        if (config.Recording || e.AltGr) return RouterDecision.Pass;

        if (e.Combo == config.Toggle)
        {
            _owned[vk] = new Owner.Toggle();
            return RouterDecision.Do(new RouterEffect.ToggleEnabled());
        }

        if (!config.Enabled || !e.TargetIsFl) return RouterDecision.Pass;
        if (config.Index.Lookup(e.Combo, link.KnownWindow, config.AnyContext) is not { } entry) return RouterDecision.Pass;

        switch (entry.Action)
        {
            case RoutedAction.FlAction a:
                if (config.ActionNatives.TryGetValue(a.Id, out var native))     // mode léger : la touche de FL équivalente
                {
                    if (ForbiddenTargets.IsForbidden(native)) return RouterDecision.Pass;
                    _owned[vk] = new Owner.Keystroke(native);
                    return RouterDecision.Do(new RouterEffect.Post(native));
                }
                if (!link.CanRun(a.Id)) return RouterDecision.Pass;     // lien inactif : la touche va à FL
                _owned[vk] = new Owner.Action(a.Id);
                return RouterDecision.Do(new RouterEffect.SendAction(a.Id));
            case RoutedAction.Keystroke k:
                if (ForbiddenTargets.IsForbidden(k.Target)) return RouterDecision.Pass;
                _owned[vk] = new Owner.Keystroke(k.Target);
                return RouterDecision.Do(new RouterEffect.Post(k.Target));
            default:
                return RouterDecision.Pass;
        }
    }
}

/// Suit l'état des modificateurs et l'auto-répétition à partir des seuls événements du hook (pas de
/// GetAsyncKeyState). Détecte AltGr (Ctrl gauche + Alt droit) pour toujours laisser passer la saisie.
public sealed class ModifierTracker
{
    private readonly HashSet<ushort> _down = new();

    public bool Ctrl => _down.Contains(Vk.LControl) || _down.Contains(Vk.RControl) || _down.Contains(Vk.Control);
    public bool Alt => _down.Contains(Vk.LMenu) || _down.Contains(Vk.RMenu) || _down.Contains(Vk.Menu);
    public bool Shift => _down.Contains(Vk.LShift) || _down.Contains(Vk.RShift) || _down.Contains(Vk.Shift);
    public bool Win => _down.Contains(Vk.LWin) || _down.Contains(Vk.RWin);
    /// AltGr : Alt droit enfoncé (Windows envoie aussi un Ctrl gauche fictif).
    public bool AltGr => _down.Contains(Vk.RMenu);

    /// Met à jour l'état ; renvoie vrai si c'est une auto-répétition (touche déjà enfoncée).
    public bool Observe(ushort vk, bool isDown)
    {
        if (!isDown) { _down.Remove(vk); return false; }
        return !_down.Add(vk);
    }

    public KeyCombo Combo(ushort vk) => new(vk, Ctrl, Alt, Shift, Win);

    public void Clear() => _down.Clear();
}
