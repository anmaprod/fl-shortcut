// Fenêtre principale « plus lisible » (maquette du 16/11 ; miroir de MainReadable.swift du Mac), à la direction A
// depuis le 17/11 (« J'aime bien le A ») : barre de gauche en index numéroté (01 Trouver un raccourci, 02 Raccourcis et
// ses pages, 03 Macros, 04 Communauté, 05 Mon compte, 06 Aide), chaque page sous un surtitre (« 02 — RACCOURCIS ») et
// un très grand titre ; « appuie sur un raccourci » pour trouver un raccourci par ses touches ou son nom ; les
// raccourcis en une seule liste (nom du groupe et son nombre à gauche, nom, touche dans son cadre, rouge si changée, ↺).
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
    private const double ReadableInset = 56, ReadableMaxWidth = 800, GroupColumn = 170;

    /// Partie « Raccourcis » de la barre de gauche ouverte (une page de raccourcis choisie l'ouvre).
    private bool _shortcutsOpen = true;
    /// « ou tape son nom » : la grande case de « Trouver un raccourci » cherche par le nom.
    private bool _findTyping;
    private readonly Border _findBox = new() { Height = 80 };
    private readonly TextBlock _findCaption = SwissLabel("", 11);
    private readonly Button _findKey = new() { Style = PlainButton, HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalAlignment = VerticalAlignment.Stretch, VerticalContentAlignment = VerticalAlignment.Stretch, Padding = new Thickness(0) };
    private readonly TextBlock _findLinkLabel = Label("", 13, SoftText);
    private readonly StackPanel _findResults = new();
    private FrameworkElement? _findPage;
    /// « CLIQUE SUR UNE TOUCHE POUR LA CHANGER » sous le titre des pages de touches.
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

    /// « fl shortcuts. » : le nom en Inter Display gras, son point carré rouge.
    private static FrameworkElement Brand()
    {
        var name = Label("fl shortcuts", 18, Text, bold: true);
        name.FontFamily = TitleFont;
        name.CharacterSpacing = -33;
        var dot = new Rectangle { Width = 5, Height = 5, Fill = Brush(Red), VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(2, 0, 0, 5) };
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(4, 26, 0, 36), Children = { name, dot } };
        AutomationProperties.SetName(row, "FL Shortcuts");
        return row;
    }

    /// Numéro d'une page dans l'index de la barre de gauche (« 02 » pour Playlist), le même que son surtitre.
    private static int PageNumber(PageKind kind) => kind switch
    {
        PageKind.Find => 1,
        PageKind.Section or PageKind.Custom => 2,
        PageKind.Macros => 3,
        PageKind.Community => 4,
        PageKind.Account => 5,
        PageKind.Help => 6,
        _ => 2,
    };

    /// Surtitre d'une page (direction A) : son numéro et le nom de sa partie (« 02 — RACCOURCIS »).
    private static string Eyebrow(PageKind kind)
    {
        var part = kind switch
        {
            PageKind.Find => Loc.T("Trouver"),
            PageKind.Macros => Loc.T("Macros"),
            PageKind.Community => Loc.T("Communauté"),
            PageKind.Account => Loc.T("Mon compte"),
            PageKind.Help => Loc.T("Aide"),
            _ => Loc.T("Raccourcis"),
        };
        return $"{PageNumber(kind):00} — {part}";
    }

    /// Maquette « Minimal » (20/11, comme le Mac) : les menus en haut (Trouver, Raccourcis, Macros, Communauté, Compte,
    /// Aide ; la partie ouverte à l'encre en demi-gras ; un point rouge de nouveautés), et à gauche de « Raccourcis » ses
    /// pages de FL et « Mes raccourcis » (la page ouverte à l'encre avec son carré rouge).
    private void RenderSidebar()
    {
        var inShortcuts = _kind is PageKind.Section or PageKind.Custom;
        _navBar.Children.Clear();
        _navBar.Children.Add(NavItem(Loc.T("Trouver"), _kind == PageKind.Find, () => Choose(PageKind.Find, _section)));
        _navBar.Children.Add(NavItem(Loc.T("Raccourcis"), inShortcuts, () =>
        {
            if (!inShortcuts) Choose(_lastShortcutsCustom ? PageKind.Custom : PageKind.Section, _section);
        }));
        _navBar.Children.Add(NavItem(Loc.T("Macros"), _kind == PageKind.Macros, () => Choose(PageKind.Macros, _section)));
        _navBar.Children.Add(NavItem(Loc.T("Communauté"), _kind == PageKind.Community, () =>
        {
            // Déjà sur la page d'une personne : « Communauté » ramène à la liste.
            if (_kind == PageKind.Community && _community.PersonName is not null) _community.LeavePerson();
            else Choose(PageKind.Community, _section);
        }, dot: _community.NewFromFollowed > 0));
        _navBar.Children.Add(NavItem(Loc.T("Compte"), _kind == PageKind.Account, () => Choose(PageKind.Account, _section)));
        _navBar.Children.Add(NavItem(Loc.T("Aide"), _kind == PageKind.Help, () => Choose(PageKind.Help, _section), dot: _help.Unread > 0));

        if (_subnav is not null) _subnav.Visibility = inShortcuts ? Visibility.Visible : Visibility.Collapsed;
        if (_kind == PageKind.Custom) _lastShortcutsCustom = true;
        else if (_kind == PageKind.Section) _lastShortcutsCustom = false;
        _sidebarGroups.Children.Clear();
        _sidebarGroups.Spacing = 0;
        foreach (var s in Enum.GetValues<FlSection>())
        {
            var section = s;
            _sidebarGroups.Children.Add(SubnavItem(s.Title(), _kind == PageKind.Section && _section == s, () => Choose(PageKind.Section, section)));
        }
        _sidebarGroups.Children.Add(SubnavItem(Loc.T("Mes raccourcis"), _kind == PageKind.Custom, () => Choose(PageKind.Custom, _section)));
    }

    /// « Raccourcis » des menus du haut : la dernière page de raccourcis ouverte (« Mes raccourcis » ou une page de FL).
    private bool _lastShortcutsCustom;

    private static Button NavItem(string title, bool selected, Action click, bool dot = false)
    {
        var label = Label(title, 14, selected ? Text : Secondary, semibold: selected);
        label.VerticalAlignment = VerticalAlignment.Center;
        var line = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, Height = 40, Background = Brush(Colors.Transparent), Children = { label } };
        if (dot) line.Children.Add(new Rectangle { Width = 6, Height = 6, Fill = Brush(Red), VerticalAlignment = VerticalAlignment.Center });
        var button = new Button { Style = PlainButton, Content = line, Padding = new Thickness(0) };
        button.PointerEntered += (_, _) => label.Foreground = Brush(Text);
        button.PointerExited += (_, _) => label.Foreground = Brush(selected ? Text : Secondary);
        button.Click += (_, _) => click();
        AutomationProperties.SetName(button, title);
        return button;
    }

    private static Button SubnavItem(string title, bool selected, Action click)
    {
        var grid = new Grid { ColumnSpacing = 10, Padding = new Thickness(0, 7, 0, 7), Background = Brush(Colors.Transparent) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.Children.Add(new Rectangle { Width = 8, Height = 8, Fill = Brush(selected ? Red : Colors.Transparent), VerticalAlignment = VerticalAlignment.Center });
        var label = Label(title, 15, selected ? Text : Secondary, semibold: selected);
        label.VerticalAlignment = VerticalAlignment.Center;
        label.TextTrimming = TextTrimming.CharacterEllipsis;
        Grid.SetColumn(label, 1);
        grid.Children.Add(label);
        var button = new Button
        {
            Style = PlainButton,
            Content = grid,
            Padding = new Thickness(0),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
        };
        button.PointerEntered += (_, _) => label.Foreground = Brush(Text);
        button.PointerExited += (_, _) => label.Foreground = Brush(selected ? Text : Secondary);
        button.Click += (_, _) => click();
        AutomationProperties.SetName(button, title);
        return button;
    }

    /// Une page de raccourcis choisie ouvre sa partie de la barre de gauche.
    private void OpenPart(PageKind kind)
    {
        if (kind is PageKind.Section or PageKind.Custom) _shortcutsOpen = true;
    }

    /// Ligne de l'index : « 03 » en petit (rouge si la partie est ouverte), puis le titre en demi-gras ; `dot` : point
    /// rouge de nouveautés.
    private static Button IndexTop(int number, string title, bool selected, Action click, bool dot = false)
    {
        var grid = new Grid { Height = 34, Background = Brush(Colors.Transparent) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(34) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var digits = Label(number.ToString("00", System.Globalization.CultureInfo.InvariantCulture), 11, selected ? Red : Secondary);
        digits.FontWeight = Microsoft.UI.Text.FontWeights.Medium;
        digits.VerticalAlignment = VerticalAlignment.Center;
        digits.Margin = new Thickness(4, 1, 0, 0);
        grid.Children.Add(digits);
        var label = Label(title, 14, Text, semibold: true);
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
        button.PointerEntered += (_, _) => { if (!selected) grid.Opacity = 0.7; };
        button.PointerExited += (_, _) => grid.Opacity = 1;
        button.Click += (_, _) => click();
        AutomationProperties.SetName(button, title);
        return button;
    }

    /// Page de « Raccourcis » (« Playlist ») : gris foncé sous le titre ; ouverte, à l'encre, en demi-gras, avec son
    /// carré rouge.
    private static Button IndexSub(string title, bool selected, Action click)
    {
        var grid = new Grid { Height = 27, Background = Brush(Colors.Transparent) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(38) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        if (selected)
            grid.Children.Add(new Rectangle { Width = 5, Height = 5, Fill = Brush(Red), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 10, 0) });
        Color rest = selected ? Text : SoftText, ink = Text;
        var label = Label(title, 14, rest, semibold: selected);
        label.VerticalAlignment = VerticalAlignment.Center;
        label.TextTrimming = TextTrimming.CharacterEllipsis;
        Grid.SetColumn(label, 1);
        grid.Children.Add(label);
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

    /// Un trait sous l'en-tête, sauf sur « appuie sur un raccourci ».
    /// Maquette « Minimal » (20/11) : plus de trait sous le titre (les tableaux ont le leur).
    private void SetTitleRule(bool rule) => _titleRule.Visibility = Visibility.Collapsed;

    // ---------- Trouver un raccourci ----------

    /// « Trouver » (maquette « Minimal », construite une fois : la case du nom garde la main pendant la frappe) : à gauche
    /// la grande case de 200 (elle écoute dès l'ouverture ; « ou tape un nom »), à droite ce que la touche fait.
    private FrameworkElement FindPage()
    {
        if (_findPage is not null) return _findPage;
        AutomationProperties.SetName(_findKey, Loc.T("Appuie sur une touche"));
        _findKey.Click += (_, _) => { if (!_findTyping && _findEditing is null && _findDone is null) StartKeySearch(); };
        _findBox.Height = 200;
        _findBox.BorderBrush = Brush(Text);
        _findBox.BorderThickness = new Thickness(0, 0, 0, 2);
        _findBox.Padding = new Thickness(0, 0, 0, 16);
        var link = new Button { Style = PlainButton, Content = _findLinkLabel, Padding = new Thickness(0, 2, 0, 2), Margin = new Thickness(0, 16, 0, 0) };
        link.Click += (_, _) =>
        {
            if (_keyListening) StopKeySearch();
            _findTyping = !_findTyping;
            UpdateFindField();
            RenderFindResults();
            if (_findTyping) _search.Focus(FocusState.Programmatic); else StartKeySearch();
        };
        _findErrorLabel.Margin = new Thickness(0, 16, 0, 0);
        var left = new StackPanel { Children = { _findBox, link, _findErrorLabel } };
        var grid = new Grid { ColumnSpacing = 24, MaxWidth = 1088, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(ReadableInset, 24, ReadableInset, 80) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(440) });
        grid.Children.Add(left);
        _findResults.Margin = new Thickness(0, 8, 0, 0);
        Grid.SetColumn(_findResults, 1);
        grid.Children.Add(_findResults);
        _findPage = grid;
        UpdateFindField();
        return _findPage;
    }

    private readonly TextBlock _findErrorLabel = Label("", 13, Red);

    /// La grande case : en attente (barre rouge et « Appuie sur une touche »), la touche en très grand, le nom tapé, ou
    /// l'étape 3 (« Nouvelle touche ») et la nouvelle touche une fois changée.
    private void UpdateFindField()
    {
        var hadFocus = _search.XamlRoot is not null
                       && Microsoft.UI.Xaml.Input.FocusManager.GetFocusedElement(_search.XamlRoot) == _search;
        if (_search.Parent is Panel holder) holder.Children.Remove(_search);
        if (_search.Parent is Border b) b.Child = null;
        _findLinkLabel.Text = _findTyping ? Loc.T("ou appuie sur une touche") : Loc.T("ou tape un nom");
        _findLinkLabel.Foreground = Brush(Secondary);
        _findLinkLabel.TextDecorations = Windows.UI.Text.TextDecorations.None;
        var showLink = _findEditing is null && _findDone is null && (_findTyping || _keySearch is null);
        if (_findLinkLabel.Parent is Button linkButton) linkButton.Visibility = showLink ? Visibility.Visible : Visibility.Collapsed;
        _findErrorLabel.Text = _findEditing is not null && _captureError is { } err ? err.Text : "";
        _findErrorLabel.Visibility = _findErrorLabel.Text.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        if (_findTyping && _findEditing is null && _findDone is null)
        {
            _search.PlaceholderText = Loc.T("Nom de l'action");
            _search.FontSize = 48;
            _search.VerticalAlignment = VerticalAlignment.Bottom;
            _findKey.Content = null;
            _findBox.Child = _search;
            if (hadFocus)
            {
                _search.Focus(FocusState.Programmatic);
                _search.SelectionStart = _search.Text.Length;
            }
            return;
        }
        FrameworkElement content = _findDone is { } done ? KeyImage(done.New?.ToString() ?? Loc.T("Aucune"))
            : _findEditing is not null ? WaitingKey(Loc.T("Nouvelle touche"))
            : _keySearch is { } k ? KeyImage(k.ToString())
            : WaitingKey(Loc.T("Appuie sur une touche"));
        content.VerticalAlignment = VerticalAlignment.Bottom;
        content.HorizontalAlignment = HorizontalAlignment.Left;
        _findKey.VerticalContentAlignment = VerticalAlignment.Bottom;
        _findKey.HorizontalContentAlignment = HorizontalAlignment.Left;
        _findKey.Content = content;
        _findBox.Child = _findKey;
    }

    /// À droite : ce que fait la touche (ou ce qui porte ce nom), l'étape 3, ou « C'est changé. ».
    private void RenderFindResults()
    {
        UpdateFindSteps();
        _findResults.Children.Clear();
        if (_findDone is { } done)
        {
            _findResults.Children.Add(Label(Loc.T("C'est changé."), 24, Text, semibold: true));
            var section = Label(done.Section, 13, Secondary);
            section.Margin = new Thickness(0, 24, 0, 0);
            _findResults.Children.Add(section);
            var title = Label(done.Title, 24, Text);
            title.Margin = new Thickness(0, 8, 0, 0);
            title.TextWrapping = TextWrapping.Wrap;
            _findResults.Children.Add(title);
            var change = Label(Loc.F("Avant : %@ · Maintenant : %@", done.Old?.ToString() ?? Loc.T("aucune"), done.New?.ToString() ?? Loc.T("aucune")), 13, Secondary);
            change.Margin = new Thickness(0, 8, 0, 0);
            _findResults.Children.Add(change);
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16, Margin = new Thickness(0, 32, 0, 0) };
            buttons.Children.Add(MinimalButton(Loc.T("Chercher un autre raccourci"), ResetFind));
            var undo = LinkButton(Loc.T("Annuler le changement"), Text, () => { _app.Restore(done.Before); ResetFind(); });
            undo.VerticalAlignment = VerticalAlignment.Center;
            buttons.Children.Add(undo);
            _findResults.Children.Add(buttons);
            return;
        }
        if (_findEditing is { } row)
        {
            _findResults.Children.Add(Label(row.Entry.Section.Title(), 13, Secondary));
            var title = Label(row.Entry.Title, 24, Text);
            title.Margin = new Thickness(0, 8, 0, 0);
            title.TextWrapping = TextWrapping.Wrap;
            _findResults.Children.Add(title);
            var before = Label(Loc.F("Avant : %@", row.Current?.ToString() ?? Loc.T("sans touche")), 13, Secondary);
            before.Margin = new Thickness(0, 8, 0, 0);
            _findResults.Children.Add(before);
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16, Margin = new Thickness(0, 32, 0, 0) };
            if (row.Entry.Kind is CatalogEntryKind.Action)
                buttons.Children.Add(MinimalButton(Loc.T("Aucune touche"), () => FinishFindChange(row, null), outlined: true));
            var cancel = LinkButton(Loc.T("Annuler"), Text, CancelFindChange);
            cancel.VerticalAlignment = VerticalAlignment.Center;
            buttons.Children.Add(cancel);
            _findResults.Children.Add(buttons);
            return;
        }
        var (rows, others) = _app.Catalog;
        var combo = _findTyping ? null : _keySearch;
        var q = _findTyping ? _query.Trim() : "";
        if (combo is null && q.Length == 0) return;
        bool Matches(CatalogRow r) => combo is { } k
            ? r.Current == k || r.Entry.DefaultTrigger == k
            : $"{r.Entry.Title} {r.Entry.Detail} {r.Entry.Section.Title()}".Contains(q, StringComparison.CurrentCultureIgnoreCase);
        var found = rows.Where(Matches).Take(40).ToList();
        var mine = others.Where(o => o.Kind != ShortcutKind.Macro && (combo is { } k
            ? o.Trigger == k
            : _app.TitleOf(o).Contains(q, StringComparison.CurrentCultureIgnoreCase))).Take(20).ToList();
        if (found.Count == 0 && mine.Count == 0)
        {
            _findResults.Children.Add(Label(combo is { } c ? Loc.F("Rien sur %@.", c.ToString()) : Loc.T("Aucun résultat."), 24, combo is null ? Secondary : Text));
            return;
        }
        foreach (var r in found)
        {
            var current = r;
            _findResults.Children.Add(ResultRow(r.Entry.Section.Title(), _findTyping ? (r.Current?.ToString() ?? Loc.T("Sans touche")) : null,
                                                !r.IsDefault, r.Entry.Title, () => BeginFindChange(current),
                                                r.IsDefault ? null : () => Reset(current)));
        }
        foreach (var o in mine)
        {
            var current = o;
            _findResults.Children.Add(ResultRow(Loc.T("Mes raccourcis"), _findTyping ? o.Trigger?.ToString() : null, false,
                                                _app.TitleOf(o), async () => await EditCustomAsync(current), null));
        }
    }

    /// « GÉNÉRAL » : la page seule (16/11, plus de « · AVANT CTRL+S » : « enlève toutes les fioritures »).
    private static string FindDetail(CatalogRow r) => r.Entry.Section.Title();

    // ---------- Lignes et groupes ----------

    /// Une page de raccourcis (maquette « Minimal ») : chaque groupe en capitales sur son trait d'encre, puis ses lignes.
    private void ShowGroups(List<(string Title, List<FrameworkElement> Rows)> groups)
    {
        var page = new StackPanel { Margin = new Thickness(0, -24, 0, 0) };
        foreach (var (title, rows) in groups)
        {
            page.Children.Add(MinimalGroupHeader(title));
            foreach (var row in rows) page.Children.Add(row);
        }
        _scroll.Content = Readable(page);
    }

    /// Une ligne lisible : le nom, un libellé en petites capitales (sa page, « avant Ctrl+S »), la touche dans sa case,
    /// puis ↺ (ou un autre bouton) ; un trait fin dessous. Toute la ligne ouvre la fiche de la touche.
    private static Grid ReadableRow(string title, bool bold, string? detail, bool dimmed, string? warning, KeyCombo? combo,
                                    bool changed, Action onKey, FrameworkElement? trailing, int? number = null)
    {
        // Direction A : numéro (listes de résultats), nom, page en petites capitales, touche dans son cadre, ↺.
        var grid = new Grid { MinHeight = number is null ? 50 : 62, Background = Brush(Colors.Transparent) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = number is null ? new GridLength(0) : new GridLength(NumberColumn) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(50) });
        if (number is { } index) grid.Children.Add(RowNumber(index));
        var name = Label(title, 15, dimmed ? Secondary : Text);
        if (bold) name.FontWeight = Microsoft.UI.Text.FontWeights.Medium;
        name.TextTrimming = TextTrimming.CharacterEllipsis;
        name.VerticalAlignment = VerticalAlignment.Center;
        var left = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center, Children = { name } };
        if (warning is not null)
        {
            var mark = new Rectangle { Width = 7, Height = 7, Fill = Brush(Red), VerticalAlignment = VerticalAlignment.Center };
            ToolTipService.SetToolTip(mark, warning);
            left.Children.Add(mark);
        }
        Grid.SetColumn(left, 1);
        grid.Children.Add(left);
        if (detail is not null)
        {
            var label = SwissLabel(detail, 10.5);
            label.VerticalAlignment = VerticalAlignment.Center;
            label.Width = PageColumn;
            label.TextTrimming = TextTrimming.CharacterEllipsis;
            label.Margin = new Thickness(12, 0, 12, 0);
            Grid.SetColumn(label, 2);
            grid.Children.Add(label);
        }
        var key = new Button { Style = PlainButton, Content = KeyBox(combo, changed), Padding = new Thickness(0), VerticalAlignment = VerticalAlignment.Center };
        key.Click += (_, _) => onKey();
        ToolTipService.SetToolTip(key, Loc.T("Changer la touche"));
        AutomationProperties.SetName(key, Loc.F("Changer la touche de %@", title));
        Grid.SetColumn(key, 3);
        grid.Children.Add(key);
        if (trailing is not null)
        {
            trailing.HorizontalAlignment = HorizontalAlignment.Right;
            trailing.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(trailing, 4);
            grid.Children.Add(trailing);
        }
        var line = Rule(Faint);
        line.VerticalAlignment = VerticalAlignment.Bottom;
        Grid.SetColumnSpan(line, 5);
        grid.Children.Add(line);
        grid.Tapped += (_, e) =>
        {
            // La touche, ↺ et la corbeille font le leur : la ligne n'ouvre pas une deuxième fiche (16/11, plantage).
            if (e.Handled || OnButton(e, grid)) return;
            e.Handled = true;
            onKey();
        };
        AutomationProperties.SetName(grid, $"{title} : {combo?.ToString() ?? Loc.T("aucune")}");
        return grid;
    }

    /// Ligne d'un raccourci de FL : nom, touche (rouge si changée), ↺ ; clic droit : changer, réinitialiser.
    private FrameworkElement CatalogLine(CatalogRow row, string? detail = null, bool bold = false, int? number = null)
    {
        // Maquette « Minimal » : un clic, puis la nouvelle touche dans la ligne ; « Remettre » s'il a changé.
        var line = MinimalRow(row.Entry.Title, detail, row.Current?.ToString(), !row.IsDefault, false, _captureRowId == row.Id,
                              _captureError is { } err && err.Id == row.Id ? err.Text : null,
                              () => StartRowCapture(row), row.IsDefault ? null : Loc.T("Remettre"), () => Reset(row));
        ToolTipService.SetToolTip(line, row.Entry.IsNative ? Loc.T("Raccourci d'origine de FL Studio") : row.Entry.Detail);
        var menu = new MenuFlyout();
        var change = new MenuFlyoutItem { Text = Loc.T("Changer la touche…") };
        change.Click += (_, _) => StartRowCapture(row);
        var resetItem = new MenuFlyoutItem { Text = Loc.T("Remettre"), IsEnabled = !row.IsDefault };
        resetItem.Click += (_, _) => Reset(row);
        menu.Items.Add(change);
        menu.Items.Add(resetItem);
        line.ContextFlyout = SwissMenu(menu);
        return line;
    }

    private FrameworkElement CustomLine(Shortcut s, string? detail = null, bool bold = false, int? number = null)
    {
        // Maquette « Minimal » : un clic ouvre sa fiche ; « Supprimer ».
        var line = MinimalRow(_app.TitleOf(s), detail, s.Trigger?.ToString(), false, !s.Enabled, false, null,
                              async () => await EditCustomAsync(s), Loc.T("Supprimer"), () => Delete(s));
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
