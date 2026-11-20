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
        _findCaption.Margin = new Thickness(0, 0, 0, 8);
        var stack = new StackPanel { Children = { _findCaption, _findBox, link, _findResults } };
        _findPage = Readable(stack, top: 18);
        UpdateFindField();
        return _findPage;
    }

    /// La grande case : en attente des touches, avec les touches appuyées (cadre rouge, ×), ou la recherche par le nom.
    private void UpdateFindField()
    {
        // Direction A : « TOUCHES », puis la grande ligne soulignée (rouge quand elle attend ou montre des touches).
        var lit = (!_findTyping && _keySearch is not null) || _keyListening || _findTyping;
        _findCaption.Text = (_findTyping ? Loc.T("Nom") : Loc.T("Touches")).ToUpper(System.Globalization.CultureInfo.CurrentCulture);
        _findBox.BorderBrush = Brush(lit ? Red : Text);
        _findBox.BorderThickness = new Thickness(0, 0, 0, 2);
        _findBox.Background = Brush(Colors.Transparent);
        _findLinkLabel.Text = _findTyping ? Loc.T("ou appuie sur le raccourci") : Loc.T("ou tape son nom");
        // La case du nom changée de place garde la main si elle l'avait (la page se redessine aussi pendant la frappe).
        var hadFocus = _search.XamlRoot is not null
                       && Microsoft.UI.Xaml.Input.FocusManager.GetFocusedElement(_search.XamlRoot) == _search;
        if (_search.Parent is Panel holder) holder.Children.Remove(_search);
        // 16/11 (« enlève toutes les fioritures ») : plus d'icône clavier ni de loupe devant.
        var grid = new Grid { ColumnSpacing = 12, Padding = new Thickness(0, 0, 0, 0) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        if (_findTyping)
        {
            _search.PlaceholderText = Loc.T("Tape son nom");
            _search.FontSize = 24;
            Grid.SetColumn(_search, 0);
            grid.Children.Add(_search);
        }
        else
        {
            var text = _keySearch is { } k
                ? Label(string.Join("+", k.Caps), 56, Text, semibold: true)
                : Label(_keyListening ? Loc.T("Appuie sur les touches…") : Loc.T("Clique ici"), 26, _keyListening ? Text : Secondary);
            if (_keySearch is not null)
            {
                text.FontFamily = TitleFont;
                text.CharacterSpacing = -30;
            }
            text.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(text, 0);
            grid.Children.Add(text);
        }
        if ((_findTyping && _query.Length > 0) || (!_findTyping && _keySearch is not null))
        {
            // × dans un carré bordé d'encre (maquette A).
            var clear = new Button
            {
                Style = PlainButton,
                Padding = new Thickness(0),
                Content = new Border
                {
                    Width = 44,
                    Height = 44,
                    BorderBrush = Brush(Text),
                    BorderThickness = new Thickness(1),
                    Child = new TextBlock { Text = "✕", FontSize = 14, Foreground = Brush(Text), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center },
                },
            };
            ToolTipService.SetToolTip(clear, Loc.T("Effacer"));
            AutomationProperties.SetName(clear, Loc.T("Effacer"));
            clear.Click += (_, _) =>
            {
                if (_findTyping) _search.Text = "";
                else _keySearch = null;
                UpdateFindField();
                RenderFindResults();
            };
            clear.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(clear, 1);
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
        UpdateFindSteps();
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
            var none = Paragraph(combo is { } c ? Loc.F("Rien n'utilise %@.", c.ToString())
                                                : Loc.F("Aucun raccourci ne correspond à « %@ ».", q), 15, Secondary);
            none.Margin = new Thickness(0, 44, 0, 0);
            _findResults.Children.Add(none);
            return;
        }
        // Direction A : un tableau numéroté (N°, Raccourci, Page, Touche).
        var head = IndexHeader(Loc.T("Raccourci"), Loc.T("Page"));
        head.Margin = new Thickness(0, 44, 0, 0);
        _findResults.Children.Add(head);
        var n = 0;
        foreach (var r in found) _findResults.Children.Add(CatalogLine(r, FindDetail(r), bold: true, number: ++n));
        foreach (var o in mine) _findResults.Children.Add(CustomLine(o, Loc.T("Mes raccourcis"), bold: true, number: ++n));
    }

    /// « GÉNÉRAL » : la page seule (16/11, plus de « · AVANT CTRL+S » : « enlève toutes les fioritures »).
    private static string FindDetail(CatalogRow r) => r.Entry.Section.Title();

    // ---------- Lignes et groupes ----------

    /// Une page de raccourcis : chaque groupe avec son nom à gauche (« OUTILS ») et ses lignes à droite.
    private void ShowGroups(List<(string Title, List<FrameworkElement> Rows)> groups)
    {
        var page = new StackPanel();
        foreach (var (title, rows) in groups)
        {
            var group = new Grid { Margin = new Thickness(0, 0, 0, 36) };
            group.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(GroupColumn) });
            group.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            // Direction A : le nom du groupe en demi-gras et son nombre en gris (« Outils 09 »).
            var label = Label(title, 13, Text, semibold: true);
            label.TextWrapping = TextWrapping.Wrap;
            var count = Label(rows.Count.ToString("00", System.Globalization.CultureInfo.InvariantCulture), 11, Secondary);
            count.FontWeight = Microsoft.UI.Text.FontWeights.Medium;
            count.Margin = new Thickness(8, 1, 0, 0);
            var head = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 16, 10, 0), VerticalAlignment = VerticalAlignment.Top, Children = { label, count } };
            AutomationProperties.SetHeadingLevel(head, Microsoft.UI.Xaml.Automation.Peers.AutomationHeadingLevel.Level3);
            AutomationProperties.SetName(head, title);
            group.Children.Add(head);
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
        var warnings = new List<string>();
        if (row.TakenBy is { } taken)
            warnings.Add(Loc.F("Touche aussi utilisée par « %@ ».", taken));
        if (row.Shortcut is { } s) warnings.AddRange(_app.IssuesOf(s.Id).Select(i => i.Message));
        var reset = row.IsDefault ? null
            : RoundIcon("reset", Loc.T("Revenir à : ") + (row.Entry.DefaultTrigger?.ToString() ?? Loc.T("aucune touche")), () => Reset(row), 32);
        var line = ReadableRow(row.Entry.Title, bold, detail, false, warnings.Count > 0 ? string.Join("\n", warnings) : null,
                               row.Current, !row.IsDefault, () => EditKey(row), reset, number);
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
    private FrameworkElement CustomLine(Shortcut s, string? detail = null, bool bold = false, int? number = null)
    {
        var issues = _app.IssuesOf(s.Id);
        var delete = RoundIcon("trash", Loc.T("Supprimer"), () => Delete(s), 32);
        var line = ReadableRow(_app.TitleOf(s), bold, detail, !s.Enabled,
                               issues.Count > 0 ? string.Join("\n", issues.Select(i => i.Message)) : null,
                               s.Trigger, false, async () => await EditCustomAsync(s), delete, number);
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
