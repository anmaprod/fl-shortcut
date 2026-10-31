// Pages de raccourcis comme le Mac (29/10, le propriétaire : « exactement la même interface sur win ») : chaque
// raccourci d'origine de FL et chaque action du script, rangés par page de FL, avec la touche actuelle (la tienne,
// sinon celle de FL) ; une carte par groupe (Outils, Sélection…) ; « Mes raccourcis ». Miroir de
// Sources/FLShortcut/Catalog.swift (CatalogEntry, CatalogRow, catalogRows, setTrigger, MyShortcuts) et de
// Sources/FLShortcut/CatalogGroups.swift.
namespace FLShortcut.Core;

public abstract record CatalogEntryKind
{
    /// Action du script FL Shortcuts (par le lien avec FL).
    public sealed record Action(int Id) : CatalogEntryKind;
    /// Raccourci d'origine de FL Studio, avec sa touche sur Windows.
    public sealed record Native(KeyCombo Combo) : CatalogEntryKind;
}

/// Une entrée d'une page : un raccourci d'origine de FL ou une action en plus. `DefaultTrigger` : la touche de FL,
/// ou celle du profil Recommandé pour une action.
public sealed record CatalogEntry(string Id, FlSection Section, string Title, string Detail, CatalogEntryKind Kind,
                                  KeyCombo? DefaultTrigger)
{
    public bool IsNative => Kind is CatalogEntryKind.Native;
}

/// État d'une entrée dans le profil : le raccourci qui la porte (s'il y en a un) et la touche actuelle.
public sealed record CatalogRow(CatalogEntry Entry, Shortcut? Shortcut, KeyCombo? Current)
{
    public string Id => Entry.Id;
    public bool IsDefault => Current == Entry.DefaultTrigger;
    /// Un autre de tes raccourcis utilise la touche de cette entrée (sa touche de FL, ou ta touche).
    public string? TakenBy { get; init; }
}

public static class CatalogEntries
{
    /// Page de chaque action du script (clé du protocole), comme le Mac.
    public static readonly IReadOnlyDictionary<string, FlSection> ActionSection = new Dictionary<string, FlSection>
    {
        ["pl"] = FlSection.General, ["cr"] = FlSection.General, ["pr"] = FlSection.General, ["mx"] = FlSection.General,
        ["br"] = FlSection.General, ["plmx"] = FlSection.General, ["undo"] = FlSection.General, ["redo"] = FlSection.General,
        ["save"] = FlSection.General,
        ["play"] = FlSection.Transport, ["stop"] = FlSection.Transport, ["rec"] = FlSection.Transport,
        ["recon"] = FlSection.Transport, ["metro"] = FlSection.Transport, ["count"] = FlSection.Transport,
        ["loop"] = FlSection.Transport, ["wait"] = FlSection.Transport, ["marker"] = FlSection.Transport,
        ["tap"] = FlSection.Transport,
        ["newpat"] = FlSection.Patterns, ["clone"] = FlSection.Patterns, ["pnext"] = FlSection.Patterns,
        ["pprev"] = FlSection.Patterns,
        ["snap"] = FlSection.PianoRoll, ["quant"] = FlSection.PianoRoll,
        ["chnext"] = FlSection.ChannelRack, ["chprev"] = FlSection.ChannelRack, ["presetnext"] = FlSection.ChannelRack,
        ["presetprev"] = FlSection.ChannelRack,
        ["arm"] = FlSection.Mixer, ["armon"] = FlSection.Mixer, ["mute"] = FlSection.Mixer, ["solo"] = FlSection.Mixer,
        ["unsolo"] = FlSection.Mixer, ["bypass"] = FlSection.Mixer, ["mono"] = FlSection.Mixer,
        ["trnext"] = FlSection.Mixer, ["trprev"] = FlSection.Mixer, ["volup"] = FlSection.Mixer, ["voldn"] = FlSection.Mixer,
    };

    /// Toutes les entrées, page par page : les raccourcis d'origine de FL (ceux que Windows peut envoyer), puis les
    /// actions du script. En mode léger, seules les actions qui ont une touche de FL restent (comme le Mac).
    public static List<CatalogEntry> Build(bool light)
    {
        var defaults = new Dictionary<int, KeyCombo>();
        foreach (var s in ProfilePreset.Recommended.Shortcuts())
            if (s.Kind == ShortcutKind.FlAction && s.ActionId is { } id && s.Trigger is { } t) defaults.TryAdd(id, t);
        var out_ = new List<CatalogEntry>();
        foreach (var section in Enum.GetValues<FlSection>())
        {
            foreach (var n in FlCatalog.Native)
            {
                if (n.Section != section || n.Combo is not { } combo || ForbiddenTargets.IsForbidden(combo)) continue;
                out_.Add(new CatalogEntry(n.Id, section, n.Title, "", new CatalogEntryKind.Native(combo), combo));
            }
            foreach (var info in FlActions.All)
            {
                if (!ActionSection.TryGetValue(info.Key, out var s) || s != section) continue;
                if (light && LightMode.NativeEquivalent(info.Id) is null) continue;
                out_.Add(new CatalogEntry("action." + info.Key, section, Loc.T(info.Label), Loc.T(info.Detail()),
                                          new CatalogEntryKind.Action(info.Id),
                                          defaults.TryGetValue(info.Id, out var d) ? d : null));
            }
        }
        return out_;
    }
}

public static class CatalogRows
{
    /// Associe chaque entrée au raccourci du profil qui la porte ; le reste (tes raccourcis créés, les macros) va
    /// dans `Others`. Une touche reprise par un AUTRE de tes raccourcis est signalée (`TakenBy`).
    public static (List<CatalogRow> Rows, List<Shortcut> Others) Build(IReadOnlyList<CatalogEntry> entries,
                                                                        IReadOnlyList<Shortcut> shortcuts)
    {
        var claimed = new HashSet<Guid>();
        var rows = new List<CatalogRow>(entries.Count);
        foreach (var entry in entries)
        {
            switch (entry.Kind)
            {
                case CatalogEntryKind.Action(var id):
                {
                    var s = shortcuts.FirstOrDefault(x => x.Kind == ShortcutKind.FlAction && x.ActionId == id && !claimed.Contains(x.Id));
                    if (s is not null) claimed.Add(s.Id);
                    rows.Add(new CatalogRow(entry, s, s is { Enabled: true } ? s.Trigger : null));
                    break;
                }
                case CatalogEntryKind.Native(var combo):
                {
                    var context = entry.Section.Context();
                    var s = shortcuts.FirstOrDefault(x => x.Kind == ShortcutKind.Keystroke && x.Target == combo
                                                          && x.Context == context && !claimed.Contains(x.Id));
                    if (s is not null) claimed.Add(s.Id);
                    rows.Add(new CatalogRow(entry, s, s is { Enabled: true } ? s.Trigger ?? combo : combo));
                    break;
                }
            }
        }
        var others = shortcuts.Where(s => !claimed.Contains(s.Id)).ToList();
        // Touches prises : une touche d'origine de FL (ou ta touche) réutilisée par un autre de tes raccourcis. Les
        // doublons propres à FL (même touche dans deux fenêtres) ne sont pas signalés.
        var owners = new Dictionary<KeyCombo, List<string>>();
        void Own(KeyCombo k, string id)
        {
            if (!owners.TryGetValue(k, out var list)) owners[k] = list = new List<string>();
            list.Add(id);
        }
        foreach (var r in rows)
            if (r.Shortcut is { Enabled: true, Trigger: { } t }) Own(t, r.Id);
        foreach (var s in others)
            if (s is { Enabled: true, Trigger: { } t }) Own(t, s.Id.ToString());
        var titles = new Dictionary<string, string>();
        foreach (var r in rows) titles.TryAdd(r.Id, r.Entry.Title);
        for (var i = 0; i < rows.Count; i++)
        {
            var keys = new List<KeyCombo>();
            if (rows[i].Entry.Kind is CatalogEntryKind.Native(var k)) keys.Add(k);
            if (rows[i].Current is { } c && !keys.Contains(c)) keys.Add(c);
            foreach (var key in keys)
            {
                if (!owners.TryGetValue(key, out var ids) || ids.FirstOrDefault(id => id != rows[i].Id) is not { } other) continue;
                rows[i] = rows[i] with { TakenBy = titles.TryGetValue(other, out var title) ? title : Loc.T("un raccourci personnalisé") };
                break;
            }
        }
        return (rows, others);
    }

    /// Le raccourci qui donne `trigger` à l'entrée (brouillon : sert aussi à l'analyse des conflits).
    public static Shortcut Draft(CatalogRow row, KeyCombo? trigger) => row.Entry.Kind switch
    {
        CatalogEntryKind.Action(var id) => (row.Shortcut ?? new Shortcut { ActionId = id }) with
            { Trigger = trigger, Enabled = true, Kind = ShortcutKind.FlAction },
        CatalogEntryKind.Native(var combo) => (row.Shortcut ?? new Shortcut
            { Kind = ShortcutKind.Keystroke, Target = combo, Context = row.Entry.Section.Context() }) with
            { Trigger = trigger, Enabled = true },
        _ => throw new InvalidOperationException(),
    };

    /// Ce que devient le profil quand l'entrée prend `trigger` : la touche de FL (ou aucune pour une action) retire
    /// ton raccourci, une autre touche le crée ou le change.
    public static (Shortcut? Upsert, Guid? Delete) Change(CatalogRow row, KeyCombo? trigger)
    {
        var native = row.Entry.Kind is CatalogEntryKind.Native(var combo) ? combo : (KeyCombo?)null;
        var back = native is { } n ? trigger is null || trigger == n : trigger is null;
        if (back) return (null, row.Shortcut?.Id);
        return (Draft(row, trigger), null);
    }

    /// Revenir à la touche d'origine.
    public static (Shortcut? Upsert, Guid? Delete) Reset(CatalogRow row) => Change(row, row.Entry.DefaultTrigger);

    /// Tout ce qui utilise déjà `trigger`, hors l'entrée qu'on modifie (une touche ne sert qu'une fois ; seule
    /// exception : revenir à la touche de FL de l'entrée elle-même).
    public static List<KeyClash> Clashes(IReadOnlyList<CatalogRow> rows, IReadOnlyList<Shortcut> others, KeyCombo trigger,
                                         CatalogRow editing, Func<Shortcut, string> title)
    {
        var out_ = new List<KeyClash>();
        if (editing.Entry.Kind is CatalogEntryKind.Native(var own) && own == trigger) return out_;
        foreach (var other in rows)
        {
            if (other.Id == editing.Id) continue;
            if (other.Shortcut is { Enabled: true } s && s.Trigger == trigger)
                out_.Add(new KeyClash(other, s, other.Entry.Title, other.Entry.Section.Title()));
            else if (other.Entry.Kind is CatalogEntryKind.Native(var k) && k == trigger)
                out_.Add(new KeyClash(other, null, other.Entry.Title, other.Entry.Section.Title()));
        }
        foreach (var s in others)
            if (s.Enabled && s.Trigger == trigger && s.Id != editing.Shortcut?.Id) out_.Add(new KeyClash(null, s, title(s), null));
        return out_;
    }

    /// Libère la touche : tes raccourcis qui l'utilisaient la perdent (un raccourci de FL revient à sa seule touche
    /// de FL, un raccourci créé n'a plus de touche). Une touche d'origine de FL : rien à retirer.
    public static (List<Shortcut> Upserts, List<Guid> Deletes) Release(IEnumerable<KeyClash> clashes)
    {
        var upserts = new List<Shortcut>();
        var deletes = new List<Guid>();
        foreach (var c in clashes)
        {
            if (c.Shortcut is not { } s) continue;
            if (c.Row is not null) deletes.Add(s.Id);
            else upserts.Add(s with { Trigger = null });
        }
        return (upserts, deletes);
    }
}

/// Ce qui utilise déjà une touche : un de tes raccourcis (`Shortcut`), ou une touche d'origine de FL.
public sealed record KeyClash(CatalogRow? Row, Shortcut? Shortcut, string Title, string? Section)
{
    public bool IsFlKey => Shortcut is null;
}

/// « Mes raccourcis » : les raccourcis de FL que tu as changés, puis ceux que tu as créés. Jamais les macros (elles
/// ont leur page) ni les touches de départ.
public static class MyShortcuts
{
    public static List<CatalogRow> Changed(IEnumerable<CatalogRow> rows) => rows.Where(r => !r.IsDefault).ToList();

    public static List<Shortcut> Created(IEnumerable<Shortcut> others, IReadOnlyList<Shortcut> starters) =>
        others.Where(s => s.Kind != ShortcutKind.Macro && !starters.Any(x => Same(x, s))).ToList();

    private static bool Same(Shortcut a, Shortcut b) =>
        a.Kind == b.Kind && a.ActionId == b.ActionId && a.Trigger == b.Trigger && a.Target == b.Target && a.Context == b.Context;
}

/// Les cartes d'une page (maquette du 28/10) : un groupe de raccourcis d'origine de FL par carte (Outils, Sélection,
/// Zoom…), chacun dans l'ordre du catalogue ; sans groupe : « Autres », à la fin.
public static class CatalogGroups
{
    public sealed record Group(string Title, IReadOnlyList<string> Keys);

    private static IEnumerable<string> Range(string prefix, int from, int to) =>
        Enumerable.Range(from, to - from + 1).Select(i => prefix + i);

    public static IReadOnlyList<Group> For(FlSection section) => section switch
    {
        FlSection.General => new[]
        {
            new Group(Loc.T("Projet"), new[] { "cmd-z", "cmd-opt-z", "cmd-s", "cmd-shift-s", "cmd-n", "cmd-o" }),
            new Group(Loc.T("Export"), new[] { "cmd-r", "cmd-shift-r", "cmd-shift-m" }),
            new Group(Loc.T("Fenêtres"), new[] { "cmd-shift-h", "f5", "f6", "f7", "f8", "f9", "opt-f8", "f10", "f11", "f12",
                                                 "f1", "f3", "tab", "esc", "return" }),
            new Group(Loc.T("Projets récents"), Range("opt-", 0, 9).ToArray()),
        },
        FlSection.Transport => new[]
        {
            new Group(Loc.T("Lecture"), new[] { "space", "cmd-space", "l", "np0", "npmul", "npdiv", "bksp", "cmd-h" }),
            new Group(Loc.T("Enregistrement"), new[] { "r", "cmd-m", "cmd-p", "cmd-i", "cmd-b", "cmd-e" }),
            new Group(Loc.T("Clavier-piano"), new[] { "cmd-t" }.Concat(Range("opt-np", 2, 6)).ToArray()),
        },
        FlSection.Patterns => new[]
        {
            new Group(Loc.T("Choisir"), Range("np", 1, 9).Concat(new[] { "npplus", "npminus" }).ToArray()),
            new Group(Loc.T("Créer et renommer"), new[] { "cmd-f4", "f4", "f2" }),
        },
        FlSection.Playlist => new[]
        {
            new Group(Loc.T("Outils"), new[] { "p", "b", "d", "t", "s", "c", "e", "y", "z" }),
            new Group(Loc.T("Sélection"), new[] { "cmd-a", "cmd-d", "shift-i", "shift-c", "shift-g", "opt-g", "cmd-left",
                                                  "cmd-right", "cmd-return" }),
            new Group(Loc.T("Édition"), new[] { "cmd-c", "cmd-x", "cmd-v", "cmd-b", "del", "7", "8", "9", "opt-m",
                                                "opt-shift-m", "shift-left", "shift-right", "shift-up", "shift-down",
                                                "cmd-opt-c", "cmd-opt-shift-c", "cmd-opt-home", "shift-m", "shift-q" }),
            new Group(Loc.T("Zoom"), new[] { "pgup", "pgdn", "5", "6", "home" }.Concat(Range("shift-", 0, 6)).ToArray()),
            new Group(Loc.T("Marqueurs"), new[] { "opt-t", "opt-npmul", "opt-npdiv", "cmd-t", "shift-opt-t" }),
            new Group(Loc.T("Affichage"), new[] { "bksp", "opt-p", "cmd-opt-g", "cmd-f8", "cmd-p" }),
        },
        FlSection.PianoRoll => new[]
        {
            new Group(Loc.T("Outils"), new[] { "p", "b", "d", "t", "c", "e", "y", "z" }),
            new Group(Loc.T("Outils de notes"), new[] { "opt-a", "opt-e", "opt-f", "opt-k", "opt-l", "opt-o", "opt-q",
                                                        "opt-r", "opt-s", "opt-u", "opt-w", "opt-x", "opt-y", "cmd-opt-q",
                                                        "cmd-l", "cmd-u", "cmd-g" }),
            new Group(Loc.T("Sélection"), new[] { "cmd-a", "cmd-d", "shift-i", "shift-c", "shift-g", "opt-g", "shift-m",
                                                  "shift-r", "cmd-left", "cmd-right", "cmd-return" }),
            new Group(Loc.T("Édition"), new[] { "cmd-c", "cmd-x", "cmd-v", "shift-cmd-v", "cmd-b", "del", "opt-left",
                                                "opt-right", "opt-up", "opt-down", "shift-left", "shift-right", "shift-up",
                                                "shift-down", "cmd-up", "cmd-down", "opt-m", "opt-shift-m", "shift-d", "s",
                                                "o", "cmd-i", "cmd-m", "cmd-opt-home", "opt-c", "shift-n" }),
            new Group(Loc.T("Zoom"), new[] { "pgup", "pgdn" }.Concat(Range("shift-", 0, 5)).ToArray()),
            new Group(Loc.T("Instruments"), new[] { "g", "h", "j", "k", "shift-h", "shift-k", "opt-v" }),
            new Group(Loc.T("Affichage"), new[] { "m", "f", "shift-f", "opt-b", "opt-n", "cmd-opt-g", "shift-opt-t", "bksp" }),
        },
        FlSection.ChannelRack => new[]
        {
            new Group(Loc.T("Mute"), Range("", 1, 9).Concat(new[] { "0" }).ToArray()),
            new Group(Loc.T("Solo"), Range("cmd-", 1, 9).Concat(new[] { "cmd-0" }).ToArray()),
            new Group(Loc.T("Canaux"), new[] { "down", "up", "pgup", "pgdn", "opt-c", "opt-del", "opt-down", "opt-up",
                                               "opt-g", "opt-m", "opt-u", "opt-z", "cmd-l", "cmd-opt-r", "shift-down",
                                               "shift-up", "cmd-return" }),
            new Group(Loc.T("Pas"), new[] { "cmd-c", "cmd-v", "cmd-x", "shift-cmd-left", "shift-cmd-right" }),
        },
        FlSection.Mixer => new[]
        {
            new Group(Loc.T("Pistes"), new[] { "s", "opt-left", "opt-right", "opt-r", "opt-s", "opt-w", "cmd-a",
                                               "cmd-shift-s", "ctrl-return", "f2" }),
            new Group(Loc.T("Liens"), new[] { "opt-l", "cmd-l", "shift-cmd-l" }),
        },
        FlSection.Browser => new[] { new Group(Loc.T("Navigation"), new[] { "return", "shift-up", "shift-down" }) },
        _ => Array.Empty<Group>(),
    };

    /// Fin de l'identifiant d'un raccourci d'origine de FL (« fl.playlist.cmd-a » → « cmd-a »).
    public static string Key(CatalogEntry entry)
    {
        var prefix = $"fl.{entry.Section.Raw()}.";
        return entry.Id.StartsWith(prefix, StringComparison.Ordinal) ? entry.Id[prefix.Length..] : entry.Id;
    }

    /// Les raccourcis d'origine d'une page, carte par carte ; les cartes vides ne sont pas gardées.
    public static List<(string Title, List<T> Rows)> Cards<T>(FlSection section, IEnumerable<T> rows, Func<T, CatalogEntry> entry)
    {
        var groups = For(section);
        var index = new Dictionary<string, int>();
        for (var i = 0; i < groups.Count; i++)
            foreach (var key in groups[i].Keys) index.TryAdd(key, i);
        var filled = groups.Select(_ => new List<T>()).ToList();
        var others = new List<T>();
        foreach (var row in rows)
        {
            if (index.TryGetValue(Key(entry(row)), out var i)) filled[i].Add(row);
            else others.Add(row);
        }
        var out_ = groups.Zip(filled).Where(p => p.Second.Count > 0).Select(p => (p.First.Title, p.Second)).ToList();
        if (others.Count > 0) out_.Add((Loc.T("Autres"), others));
        return out_;
    }

    /// Cartes sur deux colonnes, comme le Mac : la première de haut en bas, puis la suivante, coupées là où les
    /// colonnes ont la hauteur la plus proche (un en-tête compte pour deux lignes).
    public static List<List<T>> Columns<T>(IReadOnlyList<T> cards, int count, Func<T, int> size)
    {
        if (count < 2 || cards.Count < 2) return new List<List<T>> { cards.ToList() };
        var heights = cards.Select(c => size(c) + 2).ToList();
        var total = heights.Sum();
        int best = 1, bestGap = int.MaxValue, running = 0;
        for (var cut = 1; cut < cards.Count; cut++)
        {
            running += heights[cut - 1];
            var gap = Math.Abs(total - 2 * running);
            if (gap < bestGap) { best = cut; bestGap = gap; }
        }
        return new List<List<T>> { cards.Take(best).ToList(), cards.Skip(best).ToList() };
    }
}
