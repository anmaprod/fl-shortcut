// Fenêtre principale « plus lisible » (maquette du 16/11, « FL Shortcuts — plus lisible », 8 écrans ; miroir de
// MainReadable.swift du Mac) : barre de gauche en parties qui se déplient (Trouver un raccourci ; Raccourcis : les pages
// de FL et Mes raccourcis ; Macros ; Plus : Communauté, Mon compte, Aide), la page ouverte marquée d'un carré rouge ;
// « appuie sur un raccourci » pour trouver un raccourci par ses touches ou son nom ; les raccourcis en une seule liste
// (nom du groupe à gauche, nom, touche dans sa case, ↺).
using FLShortcut.Core;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal sealed partial class MainShell
{
    /// Mise en page des pages lisibles : le titre et la liste partent du même bord, liste de 800 points au plus.
    private const double ReadableInset = 56, ReadableMaxWidth = 800, GroupColumn = 166;

    /// Parties de la barre de gauche ouvertes (une page choisie ouvre sa partie).
    private bool _shortcutsOpen = true, _moreOpen;
    /// « ou tape son nom » : la grande case de « Trouver un raccourci » cherche par le nom.
    private bool _findTyping;
    private readonly Border _findBox = new() { Height = 66 };
    private readonly Button _findKey = new() { Style = PlainButton, HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalAlignment = VerticalAlignment.Stretch, VerticalContentAlignment = VerticalAlignment.Stretch, Padding = new Thickness(0) };
    private readonly TextBlock _findLinkLabel = Label("", 12.5, Secondary);
    private readonly StackPanel _findResults = new();
    private FrameworkElement? _findPage;
    /// « CLIQUE SUR UNE TOUCHE POUR LA CHANGER » sous le titre des pages de touches.
    private TextBlock _subtitle = null!;
    private Rectangle _titleRule = null!;

    /// Contenu d'une page lisible : 800 points au plus, collé à gauche, sous les marges de la page.
    private static Grid Readable(FrameworkElement content, double top = 10)
    {
        var grid = new Grid { Margin = new Thickness(ReadableInset, top, ReadableInset, 80) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MaxWidth = ReadableMaxWidth });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(content);
        return grid;
    }

    // ---------- Barre de gauche ----------

    /// « fl shortcuts. » : le nom en gras, son point carré rouge.
    private static FrameworkElement Brand()
    {
        var name = Label("fl shortcuts", 15, Text, bold: true);
        name.CharacterSpacing = -25;
        var dot = new Rectangle { Width = 4, Height = 4, Fill = Brush(BrandRed), VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(2, 0, 0, 4) };
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(8, 22, 0, 30), Children = { name, dot } };
        AutomationProperties.SetName(row, "FL Shortcuts");
        return row;
    }

    private void RenderSidebar()
    {
        using var inverted = Inverted();                 // noire sous Orange
        _sidebarGroups.Children.Clear();
        _sidebarGroups.Spacing = 0;
        _sidebarGroups.Children.Add(SidebarTop(Loc.T("Trouver un raccourci"), _kind == PageKind.Find ? "square" : "",
            _kind == PageKind.Find, () => Choose(PageKind.Find, _section)));
        _sidebarGroups.Children.Add(SidebarTop(Loc.T("Raccourcis"), _shortcutsOpen ? "open" : "closed", false, () =>
        {
            _shortcutsOpen = !_shortcutsOpen;
            RenderSidebar();
        }));
        if (_shortcutsOpen)
        {
            foreach (var s in Enum.GetValues<FlSection>())
            {
                var section = s;
                _sidebarGroups.Children.Add(SidebarSub(s.Title(), _kind == PageKind.Section && _section == s,
                    () => Choose(PageKind.Section, section)));
            }
            _sidebarGroups.Children.Add(new Rectangle { Height = 1, Fill = Brush(LineColor), Margin = new Thickness(34, 6, 12, 6), IsHitTestVisible = false });
            _sidebarGroups.Children.Add(SidebarSub(Loc.T("Mes raccourcis"), _kind == PageKind.Custom, () => Choose(PageKind.Custom, _section)));
            _sidebarGroups.Children.Add(new Border { Height = 8 });
        }
        _sidebarGroups.Children.Add(SidebarTop(Loc.T("Macros"), _kind == PageKind.Macros ? "square" : "",
            _kind == PageKind.Macros, () => Choose(PageKind.Macros, _section)));
        var newFromFollowed = _community.NewFromFollowed > 0;
        _sidebarGroups.Children.Add(SidebarTop(Loc.T("Plus"), _moreOpen ? "open" : "closed", false, () =>
        {
            _moreOpen = !_moreOpen;
            RenderSidebar();
        }, dot: newFromFollowed && !_moreOpen));
        if (_moreOpen)
        {
            _sidebarGroups.Children.Add(SidebarSub(Loc.T("Communauté"), _kind == PageKind.Community, () =>
            {
                // Déjà sur la page d'une personne : « Communauté » ramène à la liste.
                if (_kind == PageKind.Community && _community.PersonName is not null) _community.LeavePerson();
                else Choose(PageKind.Community, _section);
            }, dot: newFromFollowed));
            _sidebarGroups.Children.Add(SidebarSub(Loc.T("Mon compte"), _kind == PageKind.Account, () => Choose(PageKind.Account, _section)));
            _sidebarGroups.Children.Add(SidebarSub(Loc.T("Aide"), _kind == PageKind.Help, () => Choose(PageKind.Help, _section)));
        }
    }

    /// Une page choisie ouvre sa partie de la barre de gauche.
    private void OpenPart(PageKind kind)
    {
        if (kind is PageKind.Section or PageKind.Custom) _shortcutsOpen = true;
        if (kind is PageKind.Community or PageKind.Account or PageKind.Help) _moreOpen = true;
    }

    /// Ligne du haut : sa marque (carré rouge, triangle), puis le titre en gras ; `dot` : point rouge de nouveautés.
    private static Button SidebarTop(string title, string mark, bool selected, Action click, bool dot = false)
    {
        var grid = new Grid { Height = 46, Background = Brush(Colors.Transparent) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(28) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        FrameworkElement markView = mark switch
        {
            "square" => new Rectangle { Width = 6, Height = 6, Fill = Brush(BrandRed), HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 0, 0) },
            "open" or "closed" => new TextBlock
            {
                Text = mark == "open" ? "▼" : "▶",
                FontSize = 8,
                Foreground = Brush(Secondary),
                HorizontalAlignment = HorizontalAlignment.Left,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(8, 0, 0, 0),
            },
            _ => new Border(),
        };
        grid.Children.Add(markView);
        var label = Label(title, 15, Text, bold: true);
        label.VerticalAlignment = VerticalAlignment.Center;
        var line = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center, Children = { label } };
        if (dot) line.Children.Add(new Rectangle { Width = 6, Height = 6, Fill = Brush(Red), VerticalAlignment = VerticalAlignment.Center });
        Grid.SetColumn(line, 1);
        grid.Children.Add(line);
        var button = new Button
        {
            Style = PlainButton,
            Content = grid,
            Padding = new Thickness(0),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
        };
        button.PointerEntered += (_, _) => { if (!selected) grid.Opacity = 0.75; };
        button.PointerExited += (_, _) => grid.Opacity = 1;
        button.Click += (_, _) => click();
        AutomationProperties.SetName(button, title);
        if (mark is "open" or "closed")
            AutomationProperties.SetItemStatus(button, mark == "open" ? Loc.T("ouvert") : Loc.T("fermé"));
        return button;
    }

    /// Page d'une partie : en gris, blanche et en gras quand elle est ouverte, avec son carré rouge.
    private static Button SidebarSub(string title, bool selected, Action click, bool dot = false)
    {
        var grid = new Grid { Height = 29, Background = Brush(Colors.Transparent) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(42) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        if (selected)
            grid.Children.Add(new Rectangle { Width = 6, Height = 6, Fill = Brush(BrandRed), HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(28, 0, 0, 0) });
        Color rest = selected ? Text : SoftText, ink = Text;
        var label = Label(title, 14.5, rest, bold: selected);
        label.VerticalAlignment = VerticalAlignment.Center;
        label.TextTrimming = TextTrimming.CharacterEllipsis;
        var line = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center, Children = { label } };
        if (dot) line.Children.Add(new Rectangle { Width = 6, Height = 6, Fill = Brush(Red), VerticalAlignment = VerticalAlignment.Center });
        Grid.SetColumn(line, 1);
        grid.Children.Add(line);
        var button = new Button
        {
            Style = PlainButton,
            Content = grid,
            Padding = new Thickness(0),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
        };
        button.PointerEntered += (_, _) => label.Foreground = Brush(ink);
        button.PointerExited += (_, _) => label.Foreground = Brush(rest);
        button.Click += (_, _) => click();
        AutomationProperties.SetName(button, title);
        return button;
    }

    // ---------- En-tête ----------

    /// Sous le titre des pages de touches : « CLIQUE SUR UNE TOUCHE POUR LA CHANGER » ; un trait sous l'en-tête, sauf
    /// sur « appuie sur un raccourci ».
    private void SetHeaderDetails(bool keysPage, bool rule)
    {
        _subtitle.Visibility = keysPage ? Visibility.Visible : Visibility.Collapsed;
        _titleRule.Visibility = rule ? Visibility.Visible : Visibility.Collapsed;
    }

    // ---------- Trouver un raccourci ----------

    /// La page (construite une fois, la case garde la main pendant la frappe) : la grande case, « ou tape son nom »,
    /// puis les résultats.
    private FrameworkElement FindPage()
    {
        if (_findPage is not null) return _findPage;
        _findKey.Click += (_, _) => StartKeySearch();
        AutomationProperties.SetName(_findKey, Loc.T("Appuie sur un raccourci"));
        var link = new Button { Style = PlainButton, Content = _findLinkLabel, Padding = new Thickness(0, 2, 0, 2), Margin = new Thickness(0, 12, 0, 0) };
        _findLinkLabel.TextDecorations = Windows.UI.Text.TextDecorations.Underline;
        link.Click += (_, _) =>
        {
            if (_keyListening) StopKeySearch();
            _findTyping = !_findTyping;
            UpdateFindField();
            RenderFindResults();
            if (_findTyping) _search.Focus(FocusState.Programmatic);
        };
        var stack = new StackPanel { Children = { _findBox, link, _findResults } };
        _findPage = Readable(stack, top: 18);
        UpdateFindField();
        return _findPage;
    }

    /// La grande case : en attente des touches, avec les touches appuyées (cadre rouge, ×), ou la recherche par le nom.
    private void UpdateFindField()
    {
        var lit = (!_findTyping && _keySearch is not null) || _keyListening;
        _findBox.BorderBrush = Brush(lit ? Red : Text);
        _findBox.BorderThickness = new Thickness(lit ? 1.5 : 1);
        _findBox.Background = Brush(WindowColor);
        _findLinkLabel.Text = _findTyping ? Loc.T("ou appuie sur le raccourci") : Loc.T("ou tape son nom");
        // La case du nom changée de place garde la main si elle l'avait (la page se redessine aussi pendant la frappe).
        var hadFocus = _search.XamlRoot is not null
                       && Microsoft.UI.Xaml.Input.FocusManager.GetFocusedElement(_search.XamlRoot) == _search;
        if (_search.Parent is Panel holder) holder.Children.Remove(_search);
        var grid = new Grid { ColumnSpacing = 14, Padding = new Thickness(20, 0, 14, 0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var icon = Icon(_findTyping ? "search" : "keyboard", 16, Secondary);
        icon.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(icon);
        if (_findTyping)
        {
            _search.PlaceholderText = Loc.T("Tape son nom");
            _search.FontSize = 18;
            Grid.SetColumn(_search, 1);
            grid.Children.Add(_search);
        }
        else
        {
            var text = _keySearch is { } k
                ? Label(string.Join("+", k.Caps), 19, Text, bold: true)
                : Label(_keyListening ? Loc.T("Appuie sur les touches…") : Loc.T("Clique ici"), 18, _keyListening ? Text : Secondary);
            text.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(text, 1);
            grid.Children.Add(text);
        }
        if ((_findTyping && _query.Length > 0) || (!_findTyping && _keySearch is not null))
        {
            var clear = RoundIcon("xmark", Loc.T("Effacer"), () =>
            {
                if (_findTyping) _search.Text = "";
                else _keySearch = null;
                UpdateFindField();
                RenderFindResults();
            }, 28);
            clear.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(clear, 2);
            grid.Children.Add(clear);
        }
        if (_findTyping)
        {
            _findKey.Content = null;
            _findBox.Child = grid;
            if (hadFocus)
            {
                _search.Focus(FocusState.Programmatic);
                _search.SelectionStart = _search.Text.Length;
            }
        }
        else
        {
            _findKey.Content = grid;
            _findBox.Child = _findKey;
        }
    }

    /// Ce que font les touches appuyées (ou ce qui porte ce nom), dans toutes les pages : nom, page (« GÉNÉRAL · AVANT
    /// CTRL+S » si changée), touche dans sa case.
    private void RenderFindResults()
    {
        _findResults.Children.Clear();
        var (rows, others) = _app.Catalog;
        var combo = _findTyping ? null : _keySearch;
        var q = _findTyping ? _query.Trim() : "";
        if (combo is null && q.Length == 0) return;
        bool Matches(CatalogRow r) => combo is { } k
            ? r.Current == k || r.Entry.DefaultTrigger == k
            : $"{r.Entry.Title} {r.Entry.Detail} {r.Current} {r.Entry.Section.Title()}".Contains(q, StringComparison.CurrentCultureIgnoreCase);
        var found = rows.Where(Matches).ToList();
        var mine = others.Where(o => o.Kind != ShortcutKind.Macro && (combo is { } k
            ? o.Trigger == k
            : $"{_app.TitleOf(o)} {o.Trigger}".Contains(q, StringComparison.CurrentCultureIgnoreCase))).ToList();
        if (found.Count == 0 && mine.Count == 0)
        {
            var none = Paragraph(combo is { } c ? Loc.F("Rien n'utilise %@ : ces touches sont libres.", c.ToString())
                                                : Loc.F("Aucun raccourci ne correspond à « %@ ».", q), 15, Secondary);
            none.Margin = new Thickness(0, 44, 0, 0);
            _findResults.Children.Add(none);
            return;
        }
        var label = SwissLabel(Loc.T("Clique sur une touche pour la changer"), 10.5);
        label.Margin = new Thickness(0, 44, 0, 10);
        _findResults.Children.Add(label);
        _findResults.Children.Add(Rule(Faint));
        foreach (var r in found) _findResults.Children.Add(CatalogLine(r, FindDetail(r), bold: true));
        foreach (var o in mine) _findResults.Children.Add(CustomLine(o, Loc.T("Mes raccourcis"), bold: true));
    }

    /// « GÉNÉRAL » ; touche changée : « GÉNÉRAL · AVANT CTRL+S ».
    private static string FindDetail(CatalogRow r) => r.IsDefault
        ? r.Entry.Section.Title()
        : r.Entry.Section.Title() + " · " + Loc.T("avant") + " " + (r.Entry.DefaultTrigger?.ToString() ?? Loc.T("aucune touche"));

    // ---------- Lignes et groupes ----------

    /// Une page de raccourcis : chaque groupe avec son nom à gauche (« OUTILS ») et ses lignes à droite.
    private void ShowGroups(List<(string Title, List<FrameworkElement> Rows)> groups)
    {
        var page = new StackPanel();
        foreach (var (title, rows) in groups)
        {
            var group = new Grid { Margin = new Thickness(0, 0, 0, 34) };
            group.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(GroupColumn) });
            group.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var label = SwissLabel(title, 10.5);
            label.TextWrapping = TextWrapping.Wrap;
            label.Margin = new Thickness(0, 19, 10, 0);
            label.VerticalAlignment = VerticalAlignment.Top;
            AutomationProperties.SetHeadingLevel(label, Microsoft.UI.Xaml.Automation.Peers.AutomationHeadingLevel.Level3);
            group.Children.Add(label);
            var lines = new StackPanel();
            foreach (var row in rows) lines.Children.Add(row);
            Grid.SetColumn(lines, 1);
            group.Children.Add(lines);
            page.Children.Add(group);
        }
        _scroll.Content = Readable(page);
    }

    /// Une ligne lisible : le nom, un libellé en petites capitales (sa page, « avant Ctrl+S »), la touche dans sa case,
    /// puis ↺ (ou un autre bouton) ; un trait fin dessous. Toute la ligne ouvre la fiche de la touche.
    private static Grid ReadableRow(string title, bool bold, string? detail, bool dimmed, string? warning, KeyCombo? combo,
                                    bool changed, Action onKey, FrameworkElement? trailing)
    {
        var grid = new Grid { MinHeight = 51, Background = Brush(Colors.Transparent) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(50) });
        var name = Label(title, 15, dimmed ? Secondary : Text, bold: bold);
        name.TextTrimming = TextTrimming.CharacterEllipsis;
        name.VerticalAlignment = VerticalAlignment.Center;
        var left = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center, Children = { name } };
        if (warning is not null)
        {
            var mark = new Rectangle { Width = 7, Height = 7, Fill = Brush(Red), VerticalAlignment = VerticalAlignment.Center };
            ToolTipService.SetToolTip(mark, warning);
            left.Children.Add(mark);
        }
        grid.Children.Add(left);
        if (detail is not null)
        {
            var label = SwissLabel(detail, 10.5);
            label.VerticalAlignment = VerticalAlignment.Center;
            label.MaxWidth = 220;
            label.TextTrimming = TextTrimming.CharacterEllipsis;
            label.Margin = new Thickness(12, 0, 12, 0);
            Grid.SetColumn(label, 1);
            grid.Children.Add(label);
        }
        var key = new Button { Style = PlainButton, Content = KeyBox(combo, changed), Padding = new Thickness(0), VerticalAlignment = VerticalAlignment.Center };
        key.Click += (_, _) => onKey();
        ToolTipService.SetToolTip(key, Loc.T("Changer la touche"));
        AutomationProperties.SetName(key, Loc.F("Changer la touche de %@", title));
        Grid.SetColumn(key, 2);
        grid.Children.Add(key);
        if (trailing is not null)
        {
            trailing.HorizontalAlignment = HorizontalAlignment.Center;
            trailing.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(trailing, 3);
            grid.Children.Add(trailing);
        }
        var line = Rule(Faint);
        line.VerticalAlignment = VerticalAlignment.Bottom;
        Grid.SetColumnSpan(line, 4);
        grid.Children.Add(line);
        grid.Tapped += (_, e) =>
        {
            if (e.Handled) return;
            e.Handled = true;
            onKey();
        };
        AutomationProperties.SetName(grid, $"{title} : {combo?.ToString() ?? Loc.T("aucune")}");
        return grid;
    }

    /// Ligne d'un raccourci de FL : nom, touche (rouge si changée), ↺ ; clic droit : changer, réinitialiser.
    private FrameworkElement CatalogLine(CatalogRow row, string? detail = null, bool bold = false)
    {
        var warnings = new List<string>();
        if (row.TakenBy is { } taken)
            warnings.Add(Loc.F("Touche aussi utilisée par « %@ ». Clique sur la touche pour en choisir une autre.", taken));
        if (row.Shortcut is { } s) warnings.AddRange(_app.IssuesOf(s.Id).Select(i => i.Message));
        var reset = row.IsDefault ? null
            : RoundIcon("reset", Loc.T("Revenir à : ") + (row.Entry.DefaultTrigger?.ToString() ?? Loc.T("aucune touche")), () => Reset(row), 32);
        var line = ReadableRow(row.Entry.Title, bold, detail, false, warnings.Count > 0 ? string.Join("\n", warnings) : null,
                               row.Current, !row.IsDefault, () => EditKey(row), reset);
        ToolTipService.SetToolTip(line, row.Entry.IsNative ? Loc.T("Raccourci d'origine de FL Studio") : row.Entry.Detail);
        var menu = new MenuFlyout();
        var change = new MenuFlyoutItem { Text = Loc.T("Changer la touche…") };
        change.Click += (_, _) => EditKey(row);
        var resetItem = new MenuFlyoutItem { Text = Loc.T("Réinitialiser"), IsEnabled = !row.IsDefault };
        resetItem.Click += (_, _) => Reset(row);
        menu.Items.Add(change);
        menu.Items.Add(resetItem);
        line.ContextFlyout = SwissMenu(menu);
        return line;
    }

    /// Ligne d'un raccourci que tu as créé : nom (gris s'il est désactivé), touche, Supprimer.
    private FrameworkElement CustomLine(Shortcut s, string? detail = null, bool bold = false)
    {
        var issues = _app.IssuesOf(s.Id);
        var delete = RoundIcon("trash", Loc.T("Supprimer"), () => Delete(s), 32);
        var line = ReadableRow(_app.TitleOf(s), bold, detail, !s.Enabled,
                               issues.Count > 0 ? string.Join("\n", issues.Select(i => i.Message)) : null,
                               s.Trigger, false, async () => await EditCustomAsync(s), delete);
        var menu = new MenuFlyout();
        var toggle = new MenuFlyoutItem { Text = s.Enabled ? Loc.T("Désactiver") : Loc.T("Activer") };
        toggle.Click += (_, _) => _app.Upsert(s with { Enabled = !s.Enabled });
        var remove = new MenuFlyoutItem { Text = Loc.T("Supprimer") };
        remove.Click += (_, _) => Delete(s);
        menu.Items.Add(toggle);
        menu.Items.Add(remove);
        line.ContextFlyout = SwissMenu(menu);
        return line;
    }
}
