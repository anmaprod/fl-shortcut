using FLShortcut.Core;
using Xunit;

namespace FLShortcut.Core.Tests;

/// Pages de raccourcis comme le Mac (CatalogRows.cs) : entrées par page, touche changée puis remise, cartes.
public class CatalogRowsTests
{
    private static readonly List<CatalogEntry> Entries = CatalogEntries.Build(light: false);

    private static CatalogRow Row(List<CatalogRow> rows, string id) => rows.Single(r => r.Id == id);

    [Fact]
    public void EveryPage_HasItsNativeShortcuts_ThenItsActions()
    {
        foreach (var section in Enum.GetValues<FlSection>())
        {
            var mine = Entries.Where(e => e.Section == section).ToList();
            Assert.NotEmpty(mine);
            var firstAction = mine.FindIndex(e => !e.IsNative);
            if (firstAction >= 0) Assert.All(mine.Skip(firstAction), e => Assert.False(e.IsNative));
        }
        Assert.Contains(Entries, e => e.Id == "fl.playlist.p" && e.DefaultTrigger == new KeyCombo(Vk.Letter('P')));
        Assert.All(Entries.Where(e => e.IsNative), e => Assert.False(ForbiddenTargets.IsForbidden(e.DefaultTrigger!.Value)));
        Assert.Equal(Entries.Count, Entries.Select(e => e.Id).Distinct().Count());
    }

    [Fact]
    public void LightMode_KeepsOnlyActionsWithAFlKey()
    {
        var light = CatalogEntries.Build(light: true);
        Assert.All(light.Where(e => e.Kind is CatalogEntryKind.Action),
                   e => Assert.NotNull(LightMode.NativeEquivalent(((CatalogEntryKind.Action)e.Kind).Id)));
        Assert.Equal(Entries.Count(e => e.IsNative), light.Count(e => e.IsNative));
    }

    /// Changer la touche d'un raccourci de FL crée « ta touche → la touche de FL » dans sa fenêtre ; remettre la
    /// touche de FL (↺) le retire.
    [Fact]
    public void ChangingThenResettingANativeKey()
    {
        var (rows, others) = CatalogRows.Build(Entries, new List<Shortcut>());
        Assert.Empty(others);
        var pencil = Row(rows, "fl.playlist.p");
        Assert.True(pencil.IsDefault);
        var x = new KeyCombo(Vk.Letter('X'));
        var (upsert, delete) = CatalogRows.Change(pencil, x);
        Assert.Null(delete);
        Assert.NotNull(upsert);
        Assert.Equal(ShortcutKind.Keystroke, upsert!.Kind);
        Assert.Equal(new KeyCombo(Vk.Letter('P')), upsert.Target);
        Assert.Equal(ShortcutContext.Playlist, upsert.Context);

        (rows, others) = CatalogRows.Build(Entries, new List<Shortcut> { upsert });
        Assert.Empty(others);
        pencil = Row(rows, "fl.playlist.p");
        Assert.False(pencil.IsDefault);
        Assert.Equal(x, pencil.Current);
        Assert.Equal((null, upsert.Id), CatalogRows.Reset(pencil));
        Assert.Equal((null, upsert.Id), CatalogRows.Change(pencil, new KeyCombo(Vk.Letter('P'))));
    }

    /// Une touche prise par un autre de tes raccourcis est signalée sur la ligne (pas les doublons propres à FL).
    [Fact]
    public void TakenKey_IsShown()
    {
        var mine = Shortcut.Sends(new KeyCombo(Vk.Letter('B')), new KeyCombo(Vk.Letter('P')), ShortcutContext.Playlist);
        var (rows, _) = CatalogRows.Build(Entries, new List<Shortcut> { mine });
        Assert.Equal("Outil crayon", Row(rows, "fl.playlist.b").TakenBy);
        Assert.Null(Row(rows, "fl.pianoRoll.p").TakenBy);
    }

    [Fact]
    public void ActionRows_UseTheirShortcut_OthersStayApart()
    {
        var mute = Shortcut.Action(new KeyCombo(Vk.Letter('T'), Ctrl: true, Shift: true), 21);
        var macro = Shortcut.RunsMacro(new KeyCombo(Vk.Letter('M'), Ctrl: true, Shift: true), Guid.NewGuid());
        var created = Shortcut.Sends(new KeyCombo(Vk.F(2), Ctrl: true), new KeyCombo(Vk.Letter('Q')));
        var (rows, others) = CatalogRows.Build(Entries, new List<Shortcut> { mute, macro, created });
        Assert.Equal(mute.Trigger, Row(rows, "action.mute").Current);
        Assert.Equal(new[] { macro.Id, created.Id }, others.Select(s => s.Id));
        Assert.Equal(new[] { created.Id }, MyShortcuts.Created(others, new List<Shortcut>()).Select(s => s.Id));
        Assert.Empty(MyShortcuts.Created(new[] { mute with { Id = Guid.NewGuid() } }, new[] { mute }));
    }

    [Fact]
    public void PlaylistCards_InOrder_AndTwoColumns()
    {
        var (rows, _) = CatalogRows.Build(Entries, new List<Shortcut>());
        var page = rows.Where(r => r.Entry.Section == FlSection.Playlist && r.Entry.IsNative).ToList();
        var cards = CatalogGroups.Cards(FlSection.Playlist, page, r => r.Entry);
        Assert.Equal(new[] { "Outils", "Sélection", "Édition", "Zoom", "Marqueurs", "Affichage" },
                     cards.Select(c => c.Title));
        Assert.Equal(page.Count, cards.Sum(c => c.Rows.Count));
        var columns = CatalogGroups.Columns(cards, 2, c => c.Rows.Count);
        Assert.Equal(2, columns.Count);
        Assert.Equal("Outils", columns[0][0].Title);
        Assert.Single(CatalogGroups.Columns(cards.Take(1).ToList(), 2, c => c.Rows.Count));
    }

    /// Chaque raccourci d'origine de FL est dans un groupe de sa page (pas de carte « Autres »).
    [Fact]
    public void EveryNativeShortcut_HasItsGroup()
    {
        foreach (var e in Entries.Where(e => e.IsNative))
            Assert.Contains(CatalogGroups.For(e.Section), g => g.Keys.Contains(CatalogGroups.Key(e)));
    }

    /// Choisir une touche déjà prise : la touche de FL d'une autre entrée est dite, ton raccourci qui l'avait la perd.
    [Fact]
    public void Clashes_ThenRelease()
    {
        var mine = Shortcut.Sends(new KeyCombo(Vk.Letter('X')), new KeyCombo(Vk.Letter('P')), ShortcutContext.Playlist);
        var created = Shortcut.Sends(new KeyCombo(Vk.Letter('X')), new KeyCombo(Vk.Letter('Q')));
        var (rows, others) = CatalogRows.Build(Entries, new List<Shortcut> { mine, created });
        var brush = Row(rows, "fl.playlist.b");
        var clashes = CatalogRows.Clashes(rows, others, new KeyCombo(Vk.Letter('X')), brush, s => "créé");
        Assert.Contains(clashes, c => c.Row?.Id == "fl.playlist.p" && c.Shortcut?.Id == mine.Id);
        Assert.Contains(clashes, c => c.Row is null && c.Title == "créé");
        Assert.DoesNotContain(clashes, c => c.Row?.Id == brush.Id);
        Assert.Contains(CatalogRows.Clashes(rows, others, new KeyCombo(Vk.Letter('D')), brush, s => ""),
                        c => c.IsFlKey && c.Row?.Id == "fl.playlist.d");
        var (upserts, deletes) = CatalogRows.Release(clashes);
        Assert.Equal(new[] { mine.Id }, deletes);
        Assert.Single(upserts);
        Assert.Null(upserts[0].Trigger);
        Assert.Empty(CatalogRows.Clashes(rows, others, new KeyCombo(Vk.Letter('B')), brush, s => ""));
    }

    [Fact]
    public void NewContexts_RoundTripInTheProfile()
    {
        var s = Shortcut.Sends(new KeyCombo(Vk.Letter('K')), new KeyCombo(Vk.Down), ShortcutContext.ChannelRack);
        var back = ProfileCodec.Decode(ProfileCodec.Encode(new[] { s })).Shortcuts.Single();
        Assert.Equal(ShortcutContext.ChannelRack, back.Context);
        Assert.Equal(ShortcutContext.Browser, ShortcutContexts.FromWindow(FlWindow.Browser));
        Assert.Equal(ShortcutContext.ChannelRack, FlSection.ChannelRack.Context());
    }

    [Fact]
    public void KeyNames_InTheAppLanguage()
    {
        var zoom = new KeyCombo(Vk.Prior, Shift: true);
        Assert.Equal(new[] { "Maj", "Pg préc." }, zoom.CapsIn(english: false));
        Assert.Equal(new[] { "Shift", "Page Up" }, zoom.CapsIn(english: true));
        Assert.Equal("Enter", Vk.Name(Vk.Return, english: true));
        Assert.Equal("Entrée", Vk.Name(Vk.Return, english: false));
        Assert.Equal("Key 255", Vk.Name(0xFF, english: true));
        Assert.Equal("A", Vk.Name(Vk.A, english: true));
    }
}
