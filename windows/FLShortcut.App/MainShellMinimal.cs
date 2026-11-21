// Pages de la maquette « Minimal » (20/11, comme MinimalPages.swift du Mac ; docs/maquettes/fl-shortcuts-minimal.html) :
// Raccourcis (groupe en capitales sur un trait d'encre, lignes nom | touche | Remettre, la ligne survolée pleine
// d'encre, un clic = « Appuie sur une touche » dans la ligne) et Trouver (la grande case de 200, la touche en très grand,
// ce qu'elle fait à droite, le changement dans la page : Nouvelle touche, C'est changé.). La touche se change sans
// fiche à part (ChangeKeyAsync : mêmes règles que la fiche).
using FLShortcut.Core;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal sealed partial class MainShell
{
    private string? _captureRowId;
    private (string Id, string Text)? _captureError;
    private CatalogRow? _findEditing;
    private (string Section, string Title, KeyCombo? Old, KeyCombo? New, List<Shortcut> Before)? _findDone;

    private enum KeyChangeResult { Done, Cancelled, Refused }

    /// Mêmes règles que la fiche (19/11) : touche refusée, une touche ne fait qu'une seule chose (petite page avant →
    /// après), puis « Changer aussi dans … ? ».
    private async Task<(KeyChangeResult Result, string? Why, KeyCombo? Old, List<Shortcut> Before)> ChangeKeyAsync(CatalogRow row, KeyCombo? combo)
    {
        var before = _app.Shortcuts.ToList();
        var old = row.Current;
        if (combo == old) return (KeyChangeResult.Cancelled, null, old, before);
        var isAction = row.Entry.Kind is CatalogEntryKind.Action;
        if (combo is null && !isAction) return (KeyChangeResult.Refused, Loc.T("Ce raccourci de FL garde une touche."), old, before);
        if (combo is { } c)
        {
            if (!c.IsValidKey) return (KeyChangeResult.Refused, Loc.T("Cette touche ne peut pas servir de raccourci."), old, before);
            var blocking = _app.IssuesFor(CatalogRows.Draft(row, c))
                .Where(i => i is not ShortcutIssue.NoTrigger and not ShortcutIssue.NoTarget)
                .FirstOrDefault(i => i.IsBlocking);
            if (blocking is not null) return (KeyChangeResult.Refused, blocking.Message, old, before);
        }
        var clashes = combo is { } k ? _app.Clashes(k, row) : new List<KeyClash>();
        if (clashes.Count > 0 && !await ConfirmReplace(row, combo, clashes)) return (KeyChangeResult.Cancelled, null, old, before);
        _app.SetKey(row, combo, clashes);
        var twins = _app.Twins(row, old, combo);
        if (twins.Count > 0 && _root.XamlRoot is { } xamlRoot)
        {
            await Task.Delay(300);
            var place = twins.Count == 1 ? twins[0].Entry.Section.Title() : Loc.T("les autres pages");
            var lines = string.Join("\n", twins.Select(t => KeyChangeLine.Text(t.Entry.Title, t.Entry.Section.Title(), old, combo)));
            if (await SwissQuestion.AskAsync(xamlRoot, Loc.F("Changer aussi dans %@ ?", place), lines,
                                             new[] { Loc.T("Changer aussi"), Loc.T("Seulement ici") }) == 0)
                foreach (var twin in twins)
                    if (_app.Catalog.Rows.FirstOrDefault(r => r.Id == twin.Id) is { } now) _app.SetKey(now, combo, Array.Empty<KeyClash>());
        }
        return (KeyChangeResult.Done, null, old, before);
    }

    // ---------- Lignes de « Raccourcis » ----------

    /// Nom d'un groupe (« PROJET ») : petites capitales sur un trait d'encre de 2.
    private static FrameworkElement MinimalGroupHeader(string title)
    {
        var label = SwissLabel(title, 12, Text);
        label.Margin = new Thickness(12, 0, 12, 8);
        var box = new Border { Child = label, BorderBrush = Brush(Text), BorderThickness = new Thickness(0, 0, 0, 2), Margin = new Thickness(0, 32, 0, 0) };
        AutomationProperties.SetHeadingLevel(box, Microsoft.UI.Xaml.Automation.Peers.AutomationHeadingLevel.Level3);
        AutomationProperties.SetName(box, title);
        return box;
    }

    /// Une ligne : nom (la page dessous dans « Mes raccourcis »), touche en texte (rouge si changée), « Remettre » ;
    /// survolée ou en écoute : pleine d'encre ; en écoute : « Appuie sur une touche » en rouge et « Annuler ».
    private FrameworkElement MinimalRow(string title, string? page, string? key, bool changed, bool dimmed, bool capturing,
                                        string? error, Action onTap, string? trailing, Action? onTrailing)
    {
        var stack = new StackPanel();
        var grid = new Grid { ColumnSpacing = 24, MinHeight = 44, Padding = new Thickness(12, 6, 12, 6), Background = Brush(Colors.Transparent) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(160) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(96) });
        var name = Label(title, 16, dimmed ? Secondary : Text);
        name.TextWrapping = TextWrapping.Wrap;
        var left = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center, Children = { name } };
        TextBlock? pageLabel = null;
        if (page is not null)
        {
            pageLabel = Label(page, 13, Secondary);
            left.Children.Add(pageLabel);
        }
        grid.Children.Add(left);
        FrameworkElement keyCell;
        TextBlock? keyLabel = null;
        if (capturing)
        {
            keyCell = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 8,
                VerticalAlignment = VerticalAlignment.Center,
                Children =
                {
                    Blink(new Rectangle { Width = 2, Height = 18, Fill = Brush(Red) }),
                    Label(Loc.T("Appuie sur une touche"), 15, Red),
                },
            };
        }
        else
        {
            keyLabel = Label(key ?? "—", 20, key is null ? Secondary : changed ? Red : Text, semibold: true);
            keyLabel.FontFamily = TitleFont;
            keyLabel.VerticalAlignment = VerticalAlignment.Center;
            keyLabel.TextTrimming = TextTrimming.CharacterEllipsis;
            keyCell = keyLabel;
        }
        Grid.SetColumn(keyCell, 1);
        grid.Children.Add(keyCell);
        TextBlock? linkLabel = null;
        var linkText = capturing ? Loc.T("Annuler") : trailing;
        var linkAction = capturing ? StopRowCapture : onTrailing;
        if (linkText is not null && linkAction is not null)
        {
            linkLabel = Label(linkText, 13, Secondary);
            linkLabel.TextDecorations = Windows.UI.Text.TextDecorations.Underline;
            var link = new Button { Style = PlainButton, Content = linkLabel, Padding = new Thickness(0), HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
            link.Click += (_, _) => linkAction();
            Grid.SetColumn(link, 2);
            grid.Children.Add(link);
        }
        var box = new Border { Child = grid, BorderBrush = Brush(LineColor), BorderThickness = new Thickness(0, 0, 0, 1) };
        void Paint(bool on)
        {
            grid.Background = Brush(on ? Text : Colors.Transparent);
            box.BorderBrush = Brush(on ? Text : LineColor);
            name.Foreground = Brush(on ? WindowColor : dimmed ? Secondary : Text);
            if (pageLabel is not null) pageLabel.Foreground = Brush(on ? Tertiary : Secondary);
            if (keyLabel is not null) keyLabel.Foreground = Brush(key is null ? Secondary : changed ? Red : on ? WindowColor : Text);
            if (linkLabel is not null) linkLabel.Foreground = Brush(on ? WindowColor : Secondary);
        }
        Paint(capturing);
        grid.PointerEntered += (_, _) => Paint(true);
        grid.PointerExited += (_, _) => Paint(capturing);
        grid.Tapped += (_, e) =>
        {
            for (var d = e.OriginalSource as DependencyObject; d is not null && d != grid; d = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetParent(d))
                if (d is Microsoft.UI.Xaml.Controls.Primitives.ButtonBase) return;
            if (!capturing) onTap();
        };
        AutomationProperties.SetName(box, Loc.F("Changer la touche de %@", title));
        stack.Children.Add(box);
        if (error is not null)
        {
            var band = Paragraph(error, 13, Red);
            band.Margin = new Thickness(12, 8, 12, 8);
            stack.Children.Add(band);
        }
        return stack;
    }

    /// Un clic sur une ligne : elle attend la nouvelle touche (Échap annule ; Retour arrière seul : aucune touche).
    private void StartRowCapture(CatalogRow row)
    {
        if (_keyListening) StopKeySearch();
        _captureError = null;
        _captureRowId = row.Id;
        _app.SetRecording(true);
        RenderPage();
        _root.Focus(FocusState.Programmatic);
    }

    private void StopRowCapture()
    {
        _captureRowId = null;
        _captureError = null;
        _app.SetRecording(false);
        RenderPage();
    }

    /// Touche appuyée pendant l'écoute d'une ligne.
    private async void RowKey(KeyCombo combo)
    {
        if (_captureRowId is not { } id || _app.Catalog.Rows.FirstOrDefault(r => r.Id == id) is not { } row) { StopRowCapture(); return; }
        KeyCombo? wanted = combo.Vk == 0x08 && !combo.HasModifiers ? null : combo;
        _app.SetRecording(false);
        var (result, why, _, before) = await ChangeKeyAsync(row, wanted);
        switch (result)
        {
            case KeyChangeResult.Done:
                _captureRowId = null;
                _captureError = null;
                RenderPage();
                ShowToast(Loc.F("« %@ » : ", row.Entry.Title) + (wanted?.ToString() ?? Loc.T("aucune touche")), () => _app.Restore(before));
                break;
            case KeyChangeResult.Cancelled:
                StopRowCapture();
                break;
            default:
                _captureError = (id, why ?? "");
                _app.SetRecording(true);
                RenderPage();
                break;
        }
    }

    // ---------- Trouver ----------

    /// La touche en très grand (taille d'après sa longueur, comme la maquette).
    private static TextBlock KeyImage(string text, bool red = false)
    {
        var n = text.Length;
        var size = n <= 3 ? 200 : n <= 5 ? 150 : n <= 8 ? 96 : 64;
        var label = Label(text, size, red ? Red : Text, semibold: true);
        label.FontFamily = TitleFont;
        label.CharacterSpacing = -50;
        label.LineHeight = size * 0.84;
        label.LineStackingStrategy = LineStackingStrategy.BlockLineHeight;
        label.TextWrapping = TextWrapping.NoWrap;
        return label;
    }

    /// « Appuie sur une touche » / « Nouvelle touche » : la barre rouge qui attend, puis le mot en très grand gris.
    private static FrameworkElement WaitingKey(string placeholder)
    {
        var word = Label(placeholder, 48, FaintText);
        word.VerticalAlignment = VerticalAlignment.Bottom;
        word.TextWrapping = TextWrapping.NoWrap;
        return new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 24,
            VerticalAlignment = VerticalAlignment.Bottom,
            Children = { Blink(new Rectangle { Width = 20, Height = 168, Fill = Brush(Red) }), word },
        };
    }

    /// Une ligne de résultat : « Playlist · Ctrl+S » en gris et « Changer » à droite, puis le nom en 24.
    private FrameworkElement ResultRow(string section, string? key, bool changed, string title, Action change, Action? reset)
    {
        var meta = new Grid { ColumnSpacing = 8 };
        meta.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        meta.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var place = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4, Children = { Label(section, 13, Secondary) } };
        if (key is not null)
        {
            place.Children.Add(Label("·", 13, Secondary));
            place.Children.Add(Label(key, 13, changed ? Red : Text, semibold: true));
        }
        meta.Children.Add(place);
        var links = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16 };
        links.Children.Add(LinkButton(Loc.T("Changer"), Secondary, change));
        if (reset is not null) links.Children.Add(LinkButton(Loc.T("Remettre"), Secondary, reset));
        Grid.SetColumn(links, 1);
        meta.Children.Add(links);
        var name = new Button { Style = PlainButton, Padding = new Thickness(0), HorizontalAlignment = HorizontalAlignment.Left, Content = Label(title, 24, Text) };
        name.Click += (_, _) => change();
        return new StackPanel { Spacing = 8, Margin = new Thickness(0, 0, 0, 32), Children = { meta, name } };
    }

    /// « Changer » d'un résultat : étape 3, la grande case attend la nouvelle touche.
    private void BeginFindChange(CatalogRow row)
    {
        if (_keyListening) StopKeySearch();
        _captureError = null;
        _findEditing = row;
        _app.SetRecording(true);
        RenderPage();
        _root.Focus(FocusState.Programmatic);
    }

    private async void FinishFindChange(CatalogRow row, KeyCombo? combo)
    {
        _app.SetRecording(false);
        if (_app.Catalog.Rows.FirstOrDefault(r => r.Id == row.Id) is not { } fresh) { CancelFindChange(); return; }
        var (result, why, old, before) = await ChangeKeyAsync(fresh, combo);
        if (result == KeyChangeResult.Done)
        {
            _findEditing = null;
            _captureError = null;
            _findDone = (fresh.Entry.Section.Title(), fresh.Entry.Title, old, combo, before);
        }
        else
        {
            _captureError = result == KeyChangeResult.Refused ? (fresh.Id, why ?? "") : null;
            _app.SetRecording(true);
        }
        RenderPage();
    }

    private void CancelFindChange()
    {
        _findEditing = null;
        _captureError = null;
        _app.SetRecording(false);
        RenderPage();
        if (!_findTyping) StartKeySearch();
    }

    /// « Chercher un autre raccourci » : la case vide, qui écoute.
    private void ResetFind()
    {
        _findDone = null;
        _findEditing = null;
        _captureError = null;
        _keySearch = null;
        _search.Text = "";
        _findTyping = false;
        RenderPage();
        StartKeySearch();
    }

    /// Une touche pendant une écoute de la maquette (ligne ou étape 3 de « Trouver ») ; vrai si elle a été prise.
    private bool MinimalKey(KeyRoutedEventArgs e, KeyCombo combo)
    {
        if (_captureRowId is null && _findEditing is null) return false;
        e.Handled = true;
        var escape = e.Key == Windows.System.VirtualKey.Escape && !combo.HasModifiers;
        if (_captureRowId is not null)
        {
            if (escape) StopRowCapture(); else RowKey(combo);
        }
        else if (_findEditing is { } row)
        {
            if (escape) CancelFindChange();
            else FinishFindChange(row, combo.Vk == 0x08 && !combo.HasModifiers ? null : combo);
        }
        return true;
    }
}
