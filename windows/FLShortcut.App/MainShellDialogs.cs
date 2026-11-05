// Fiches de la fenêtre principale : « Changer la touche » d'un raccourci de FL (comme CatalogEditSheet du Mac : la
// touche, ce qui l'utilise déjà, la touche d'origine ; une touche ne sert qu'une fois, « Remplacer » la reprend) et la
// fiche d'un raccourci que tu as créé (action dans FL, touche de FL ou macro).
using FLShortcut.Core;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal sealed partial class MainShell
{
    internal static Style? DialogStyle()
    {
        try { return Application.Current.Resources["DefaultContentDialogStyle"] as Style; }
        catch (Exception) { return null; }
    }

    private ContentDialog NewDialog() => new()
    {
        XamlRoot = _root.XamlRoot,
        Style = DialogStyle(),                // créé en code, le dialogue garderait sinon l'ancien style
        RequestedTheme = MacLook.SurfaceTheme,
        Background = Brush(Rgb(0x1E, 0x1E, 0x21)),
        BorderBrush = Brush(LineColor),
    };

    /// En-tête d'une fiche (comme le Mac, 05/11) : la rubrique en petites capitales grises, puis le titre en minuscules
    /// suivi de son point carré, souligné d'un trait.
    private static StackPanel SheetHeader(string label, string title)
    {
        var big = SwissTitle(30);
        big.Text = title.ToLower(System.Globalization.CultureInfo.CurrentCulture);
        var panel = new StackPanel { Spacing = 6, Padding = new Thickness(0, 0, 0, 12), BorderBrush = Brush(Text), BorderThickness = new Thickness(0, 0, 0, 1) };
        panel.Children.Add(SwissLabel(label, 11, Secondary));
        panel.Children.Add(PageTitle(big, 30));
        return panel;
    }

    /// Ligne d'une fiche : le nom en petites capitales à gauche, le champ à droite, un trait fin dessous.
    private static Grid SheetRow(string title, FrameworkElement content)
    {
        var grid = new Grid { ColumnSpacing = 16, Padding = new Thickness(0, 0, 0, 14), BorderBrush = Brush(Faint), BorderThickness = new Thickness(0, 0, 0, 1) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(110) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var label = SwissLabel(title, 11, Secondary);
        label.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(label);
        Grid.SetColumn(content, 1);
        grid.Children.Add(content);
        return grid;
    }

    /// « Ouvrir dans le créateur » (comme le Mac) : grande ligne bordée, carré creux, nom de la macro, flèche ; au survol,
    /// pleine d'encre.
    private static Button OpenCreatorRow(string name, Action open)
    {
        StackPanel Face(bool hovered)
        {
            var ink = hovered ? MacLook.WindowColor : Text;
            var square = new Border { Width = 8, Height = 8, BorderBrush = Brush(ink), BorderThickness = new Thickness(1), VerticalAlignment = VerticalAlignment.Center };
            var names = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
            names.Children.Add(SwissLabel(Loc.T("Ouvrir dans le créateur"), 13, ink));
            names.Children.Add(Label(name, 12, hovered ? ink : Secondary));
            var grid = new Grid { ColumnSpacing = 12 };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            grid.Children.Add(square);
            Grid.SetColumn(names, 1);
            grid.Children.Add(names);
            var arrow = Label("→", 16, ink, bold: true);
            Grid.SetColumn(arrow, 2);
            grid.Children.Add(arrow);
            return new StackPanel { Children = { grid } };
        }
        var button = new Button
        {
            Style = PlainButton,
            MinHeight = 54,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Padding = new Thickness(14, 0, 14, 0),
            Background = Brush(MacLook.WindowColor),
            BorderBrush = Brush(Text),
            BorderThickness = new Thickness(1.5),
            Content = Face(false),
        };
        button.PointerEntered += (_, _) => { button.Background = Brush(Text); button.Content = Face(true); };
        button.PointerExited += (_, _) => { button.Background = Brush(MacLook.WindowColor); button.Content = Face(false); };
        button.Click += (_, _) => open();
        AutomationProperties.SetName(button, Loc.T("Ouvrir dans le créateur"));
        return button;
    }

    /// Champ de touche : la touche (ou « Aucune ») ; un clic, puis les touches appuyées la remplacent (Échap annule).
    private static Button CaptureButton() => new()
    {
        Style = PlainButton,
        MinHeight = 40,
        HorizontalAlignment = HorizontalAlignment.Stretch,
        HorizontalContentAlignment = HorizontalAlignment.Left,
        Padding = new Thickness(10, 6, 10, 6),
        CornerRadius = new CornerRadius(0),
        Background = Brush(MacLook.WindowColor),
        BorderBrush = Brush(LineColor),
        BorderThickness = new Thickness(1),
    };

    private static void SetCapture(Button button, KeyCombo? combo, bool recording, bool changed)
    {
        button.BorderBrush = Brush(recording ? Accent : White(0.16));
        button.BorderThickness = new Thickness(recording ? 2 : 1);
        button.Content = recording ? Label(Loc.T("Appuie sur les touches…"), 13, Link) : Keys(combo, changed);
        AutomationProperties.SetName(button, recording ? Loc.T("Appuie sur les touches…") : combo?.ToString() ?? Loc.T("Aucune"));
        if (recording) button.Focus(FocusState.Programmatic);
    }

    /// Changer la touche d'un raccourci de FL ou d'une action en plus.
    private async void EditKey(CatalogRow row)
    {
        if (_root.XamlRoot is null) return;
        KeyCombo? combo = row.Current;
        var recording = false;
        var native = row.Entry.Kind is CatalogEntryKind.Native(var n) ? n : (KeyCombo?)null;
        var isAction = row.Entry.Kind is CatalogEntryKind.Action;
        var dialog = NewDialog();
        dialog.PrimaryButtonText = Loc.T("Valider");
        dialog.CloseButtonText = Loc.T("Annuler");
        dialog.SecondaryButtonText = Loc.T("Réinitialiser");
        dialog.DefaultButton = ContentDialogButton.Primary;

        var body = new StackPanel { Spacing = 14, MinWidth = 420 };
        body.Children.Add(SheetHeader(row.Entry.Section.Title(), row.Entry.Title));

        var capture = CaptureButton();
        var clashPanel = new StackPanel { Spacing = 2 };
        var issuePanel = new StackPanel { Spacing = 2 };
        var keyBlock = new StackPanel { Spacing = 6 };
        keyBlock.Children.Add(Label(Loc.T("Touche"), 12, Secondary, semibold: true));
        keyBlock.Children.Add(capture);
        keyBlock.Children.Add(clashPanel);
        keyBlock.Children.Add(issuePanel);
        body.Children.Add(keyBlock);

        var origin = new StackPanel { Spacing = 2 };
        origin.Children.Add(Label(Loc.T("D'origine"), 12, Secondary, semibold: true));
        origin.Children.Add(Keys(row.Entry.DefaultTrigger));
        if (native is not null) origin.Children.Add(Paragraph(Loc.T("Elle continue de marcher dans FL : ta touche s'ajoute."), 11));
        body.Children.Add(origin);

        var extra = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        if (isAction)
        {
            extra.Children.Add(Soft(Loc.T("Aucune touche"), () =>
            {
                combo = null;
                Refresh();
            }));
            if (!_app.Light && row.Entry.Kind is CatalogEntryKind.Action(var id))
                extra.Children.Add(Soft(Loc.T("Tester"), () => _app.TestAction(id)));
        }
        if (extra.Children.Count > 0) body.Children.Add(extra);
        dialog.Content = body;

        List<KeyClash> Clashes() => combo is { } c && c != row.Current ? _app.Clashes(c, row) : new List<KeyClash>();

        void Refresh()
        {
            SetCapture(capture, combo, recording, combo != row.Entry.DefaultTrigger);
            clashPanel.Children.Clear();
            var clashes = Clashes();
            if (clashes.Count > 0 && !recording)
            {
                var title = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
                title.Children.Add(Icon("warning", 12, Orange, Rgb(0x1E, 0x1E, 0x21)));
                title.Children.Add(Label(Loc.T("Déjà utilisée par :"), 11, Text));
                clashPanel.Children.Add(title);
                foreach (var c in clashes.Take(4)) clashPanel.Children.Add(Paragraph(Line(c), 11));
                if (clashes.Count > 4) clashPanel.Children.Add(Paragraph(Loc.F("et %lld autres", clashes.Count - 4), 11));
            }
            issuePanel.Children.Clear();
            var issues = combo is { } k && k != native
                ? _app.IssuesFor(CatalogRows.Draft(row, combo))
                      .Where(i => i is not ShortcutIssue.NoTrigger and not ShortcutIssue.NoTarget).ToList()
                : new List<ShortcutIssue>();
            if (!recording)
                foreach (var i in issues) issuePanel.Children.Add(Paragraph(i.Message, 11, i.IsBlocking ? Red : Orange));
            dialog.IsPrimaryButtonEnabled = !recording && combo != row.Current && !issues.Any(i => i.IsBlocking)
                                            && (combo is not null || isAction);
            dialog.IsSecondaryButtonEnabled = combo != row.Entry.DefaultTrigger;
        }

        void Stop()
        {
            recording = false;
            _app.SetRecording(false);
            Refresh();
        }

        capture.Click += (_, _) =>
        {
            recording = true;
            _app.SetRecording(true);
            Refresh();
        };
        capture.PreviewKeyDown += (_, e) =>
        {
            if (!recording) return;
            e.Handled = true;
            var vk = (ushort)e.Key;
            if (Vk.IsModifier(vk)) return;
            var pressed = CurrentCombo(vk);
            if (e.Key == Windows.System.VirtualKey.Escape && !pressed.HasModifiers)
            {
                Stop();
                return;
            }
            if (!pressed.IsValidKey) return;
            combo = pressed;
            Stop();
        };
        // Un bouton de souris (molette, côtés) peut aussi lancer ce raccourci (05/11).
        capture.AddHandler(UIElement.PointerPressedEvent, new Microsoft.UI.Xaml.Input.PointerEventHandler((_, e) =>
        {
            if (!recording || PressedMouseButton(e, capture) is not { } mouse) return;
            e.Handled = true;
            combo = CurrentCombo(mouse);
            Stop();
        }), true);
        capture.LostFocus += (_, _) => { if (recording) Stop(); };
        dialog.SecondaryButtonClick += (_, args) =>
        {
            args.Cancel = true;                 // « Réinitialiser » remet la touche d'origine dans le champ
            combo = row.Entry.DefaultTrigger;
            Refresh();
        };

        Refresh();
        var result = await dialog.ShowAsync();
        _app.SetRecording(false);
        if (result != ContentDialogResult.Primary) return;

        var found = Clashes();
        var mine = found.Where(c => !c.IsFlKey).ToList();
        if (mine.Count > 0 && !await ConfirmReplace(combo, found)) return;
        _app.SetKey(row, combo, found);
        ShowToast(Loc.F("« %@ » : ", row.Entry.Title) + (combo?.ToString() ?? Loc.T("aucune touche")));
        // Touche reprise à un autre raccourci de FL : une nouvelle touche lui est proposée tout de suite.
        if (mine.FirstOrDefault(c => c.Row is not null)?.Row?.Id is { } next
            && _app.Catalog.Rows.FirstOrDefault(r => r.Id == next) is { } nextRow)
            EditKey(nextRow);
    }

    /// Ce qui utilise déjà une touche, en une ligne (comme le Mac).
    private static string Line(KeyClash c)
    {
        var place = c.Section is { } s ? $" ({s})" : "";
        return c.IsFlKey ? Loc.F("« %@ »%@, touche d'origine de FL", c.Title, place)
                         : Loc.F("« %@ »%@, ton raccourci", c.Title, place);
    }

    /// Une question (Mon compte : se déconnecter, supprimer le compte) ; vrai si l'on choisit `primary`. « Annuler »
    /// est le choix par défaut.
    private async Task<bool> ConfirmAsync(string title, string text, string primary, bool destructive)
    {
        if (_root.XamlRoot is null) return false;
        var dialog = NewDialog();
        dialog.Title = title;
        dialog.Content = Paragraph(text, 13, Text);
        dialog.PrimaryButtonText = primary;
        dialog.CloseButtonText = Loc.T("Annuler");
        dialog.DefaultButton = ContentDialogButton.Close;
        if (destructive)
        {
            var red = new Style(typeof(Button));
            red.Setters.Add(new Setter(Control.ForegroundProperty, Brush(Red)));
            dialog.PrimaryButtonStyle = red;
        }
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    /// Une question à trois réponses : 0 (`first`), 1 (`second`), 2 (Annuler, le choix par défaut).
    private async Task<int> ChooseAsync(string title, string text, string first, string second)
    {
        if (_root.XamlRoot is null) return 2;
        var dialog = NewDialog();
        dialog.Title = title;
        dialog.Content = Paragraph(text, 13, Text);
        dialog.PrimaryButtonText = first;
        dialog.SecondaryButtonText = second;
        dialog.CloseButtonText = Loc.T("Annuler");
        dialog.DefaultButton = ContentDialogButton.Close;
        return await dialog.ShowAsync() switch
        {
            ContentDialogResult.Primary => 0,
            ContentDialogResult.Secondary => 1,
            _ => 2,
        };
    }

    /// Une touche ne sert qu'une fois : ce qui l'utilise est annoncé avant de la reprendre.
    private async Task<bool> ConfirmReplace(KeyCombo? combo, List<KeyClash> clashes)
    {
        var dialog = NewDialog();
        dialog.Title = Loc.F("%@ est déjà utilisée", combo?.ToString() ?? Loc.T("Cette touche"));
        dialog.Content = Paragraph(string.Join("\n", clashes.Take(4).Select(Line))
            + "\n\n" + Loc.F("Une touche ne sert qu'une fois : « %@ » en prendra une autre.", clashes.FirstOrDefault()?.Title ?? Loc.T("l'autre raccourci")), 13, Text);
        dialog.PrimaryButtonText = Loc.T("Remplacer");
        dialog.CloseButtonText = Loc.T("Annuler");
        dialog.DefaultButton = ContentDialogButton.Close;
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    /// Fiche d'un raccourci que tu as créé : sa touche, ce qu'il fait (action dans FL, touche de FL, macro), où.
    private async Task EditCustomAsync(Shortcut existing)
    {
        if (_root.XamlRoot is null) return;
        var draft = existing;
        var category = draft.ActionId is { } a0 && FlActions.Info(a0) is { } i0 ? i0.Category : ActionCategory.Composition;
        string? recordingFor = null;              // "trigger" ou "target"

        var dialog = NewDialog();
        dialog.PrimaryButtonText = Loc.T("Valider");
        dialog.CloseButtonText = Loc.T("Annuler");
        dialog.SecondaryButtonText = Loc.T("Supprimer");
        dialog.DefaultButton = ContentDialogButton.Primary;

        // 05/11 (« on s'y perd… juste le bouton raccourci et puis c'est fini ») : comme le Mac, la touche seule ; la
        // touche de FL pour un raccourci « Touche de FL » ; « Ouvrir dans le créateur » pour une macro. Plus de type, ni
        // de liste d'actions, ni de « Où ? » ici.
        var body = new StackPanel { Spacing = 14, MinWidth = 480 };
        var triggerButton = CaptureButton();
        var warning = new StackPanel { Spacing = 2 };
        var kinds = new RadioButtons { MaxColumns = 3 };
        var actionPanel = new StackPanel();
        var cats = new ComboBox();
        var actions = new ListView();
        var wheres = new ComboBox();
        var keyPanel = new StackPanel { Spacing = 6 };
        var targetButton = CaptureButton();
        var macroPanel = new StackPanel();
        var macroPicker = new ComboBox();
        var kindLabel = draft.Kind switch
        {
            ShortcutKind.FlAction => Loc.T("Action dans FL"),
            ShortcutKind.Keystroke => Loc.T("Touche de FL"),
            _ => Loc.T("Macro"),
        };
        var macroDoc = draft.MacroRef is { } refId ? _app.Macros.Macros.FirstOrDefault(m => m.Id == refId) : null;
        var headerTitle = macroDoc is not null ? DisplayText.Safe(macroDoc.Name, 40) : _app.TitleOf(draft);
        body.Children.Add(SheetHeader(kindLabel, headerTitle));
        body.Children.Add(SheetRow(Loc.T("Raccourci"), new StackPanel { Spacing = 6, Children = { triggerButton, warning } }));
        if (draft.Kind == ShortcutKind.Keystroke)
        {
            keyPanel.Children.Add(targetButton);
            body.Children.Add(SheetRow(Loc.T("Touche de FL"), keyPanel));
        }
        else if (draft.Kind == ShortcutKind.Macro && macroDoc is not null)
        {
            var id = macroDoc.Id;
            body.Children.Add(OpenCreatorRow(DisplayText.Safe(macroDoc.Name, 60), () =>
            {
                dialog.Hide();
                Choose(PageKind.Macros, _section);
                _macros.Open(id);
            }));
        }
        dialog.Content = new ScrollViewer { Content = body, MaxHeight = 600 };

        var refreshing = false;
        void Refresh()
        {
            refreshing = true;
            SetCapture(triggerButton, draft.Trigger, recordingFor == "trigger", false);
            SetCapture(targetButton, draft.Target, recordingFor == "target", false);
            kinds.SelectedIndex = draft.Kind switch { ShortcutKind.FlAction => 0, ShortcutKind.Keystroke => 1, _ => 2 };
            actionPanel.Visibility = draft.Kind == ShortcutKind.FlAction ? Visibility.Visible : Visibility.Collapsed;
            keyPanel.Visibility = draft.Kind == ShortcutKind.Keystroke ? Visibility.Visible : Visibility.Collapsed;
            macroPanel.Visibility = draft.Kind == ShortcutKind.Macro ? Visibility.Visible : Visibility.Collapsed;
            macroPicker.SelectedItem = macroPicker.Items.OfType<ComboBoxItem>().FirstOrDefault(x => x.Tag is Guid g && g == draft.MacroRef);
            wheres.SelectedItem = wheres.Items.OfType<ComboBoxItem>().FirstOrDefault(x => x.Tag is ShortcutContext c && c == draft.Context);
            cats.SelectedItem = cats.Items.OfType<ComboBoxItem>().FirstOrDefault(x => x.Tag is ActionCategory c && c == category);
            actions.Items.Clear();
            foreach (var info in FlActions.All.Where(x => x.Category == category))
            {
                var availability = _app.Availability(info.Id);
                var item = new ListViewItem { Tag = info.Id, IsEnabled = availability.IsUsable };
                var stack = new StackPanel { Padding = new Thickness(0, 6, 0, 6), Spacing = 1 };
                stack.Children.Add(Label(Loc.T(info.Label), 13));
                stack.Children.Add(Paragraph(availability is ActionAvailability.Unavailable u ? u.Reason : Loc.T(info.Detail()), 11));
                item.Content = stack;
                actions.Items.Add(item);
                if (draft.ActionId == info.Id) actions.SelectedItem = item;
            }
            var issues = draft.Trigger is null && draft.Target is null ? new List<ShortcutIssue>() : _app.IssuesFor(draft).ToList();
            var blocking = issues.Where(x => x.IsBlocking && x is not ShortcutIssue.NoTrigger and not ShortcutIssue.NoTarget).ToList();
            var shown = blocking.Count > 0 ? blocking : issues.Where(x => !x.IsBlocking).ToList();
            warning.Children.Clear();
            if (recordingFor is null)
                foreach (var i in shown) warning.Children.Add(Paragraph(i.Message, 11, blocking.Count > 0 ? Red : Orange));
            // Une macro pas encore prête garde son raccourci (bloqué jusque-là, comme depuis la page Macros).
            dialog.IsPrimaryButtonEnabled = recordingFor is null && issues.All(x => !x.IsBlocking || x is ShortcutIssue.MacroInvalid)
                && draft.Trigger is not null && draft.Kind switch
                {
                    ShortcutKind.FlAction => draft.ActionId is not null,
                    ShortcutKind.Keystroke => draft.Target is not null,
                    _ => draft.MacroRef is not null,
                };
            refreshing = false;
        }

        void StartRecording(string which)
        {
            recordingFor = which;
            _app.SetRecording(true);
            Refresh();
        }

        void StopRecording()
        {
            recordingFor = null;
            _app.SetRecording(false);
            Refresh();
        }

        void OnCaptureKey(object s, KeyRoutedEventArgs e)
        {
            if (recordingFor is null) return;
            e.Handled = true;
            var vk = (ushort)e.Key;
            if (Vk.IsModifier(vk)) return;
            var combo = CurrentCombo(vk);
            if (e.Key == Windows.System.VirtualKey.Escape && !combo.HasModifiers) { StopRecording(); return; }
            draft = recordingFor == "trigger" ? draft with { Trigger = combo } : draft with { Target = combo };
            StopRecording();
        }

        triggerButton.Click += (_, _) => StartRecording("trigger");
        targetButton.Click += (_, _) => StartRecording("target");
        triggerButton.PreviewKeyDown += OnCaptureKey;
        // Le déclencheur peut être un bouton de souris (molette, côtés) ; la touche envoyée à FL, jamais.
        triggerButton.AddHandler(UIElement.PointerPressedEvent, new Microsoft.UI.Xaml.Input.PointerEventHandler((_, e) =>
        {
            if (recordingFor != "trigger" || PressedMouseButton(e, triggerButton) is not { } mouse) return;
            e.Handled = true;
            draft = draft with { Trigger = CurrentCombo(mouse) };
            StopRecording();
        }), true);
        targetButton.PreviewKeyDown += OnCaptureKey;
        triggerButton.LostFocus += (_, _) => { if (recordingFor == "trigger") StopRecording(); };
        targetButton.LostFocus += (_, _) => { if (recordingFor == "target") StopRecording(); };
        kinds.SelectionChanged += (_, _) =>
        {
            if (refreshing || kinds.SelectedIndex < 0) return;
            var kind = kinds.SelectedIndex switch { 1 => ShortcutKind.Keystroke, 2 => ShortcutKind.Macro, _ => ShortcutKind.FlAction };
            if (kind != draft.Kind) { draft = draft with { Kind = kind, MacroRef = null }; Refresh(); }
        };
        macroPicker.SelectionChanged += (_, _) =>
        {
            if (refreshing) return;
            if (macroPicker.SelectedItem is ComboBoxItem { Tag: Guid id } && draft.MacroRef != id)
            {
                draft = draft with { MacroRef = id, UnknownAction = null };
                _window.DispatcherQueue.TryEnqueue(Refresh);
            }
        };
        cats.SelectionChanged += (_, _) =>
        {
            if (refreshing || cats.SelectedItem is not ComboBoxItem { Tag: ActionCategory picked } || picked == category) return;
            category = picked;
            _window.DispatcherQueue.TryEnqueue(Refresh);
        };
        actions.SelectionChanged += (_, _) =>
        {
            if (refreshing) return;
            if (actions.SelectedItem is ListViewItem { Tag: int id } && draft.ActionId != id)
            {
                draft = draft with { ActionId = id, UnknownAction = null };
                // Refresh vide et remplit la liste : jamais pendant son propre SelectionChanged.
                _window.DispatcherQueue.TryEnqueue(Refresh);
            }
        };
        wheres.SelectionChanged += (_, _) =>
        {
            if (refreshing) return;
            if (wheres.SelectedItem is ComboBoxItem { Tag: ShortcutContext c } && c != draft.Context)
            {
                draft = draft with { Context = c };
                _window.DispatcherQueue.TryEnqueue(Refresh);
            }
        };

        Refresh();
        var result = await dialog.ShowAsync();
        _app.SetRecording(false);
        if (result == ContentDialogResult.Primary)
        {
            var final = draft.Kind switch
            {
                ShortcutKind.FlAction => draft with { Target = null },
                ShortcutKind.Keystroke => draft with { ActionId = null },
                _ => draft with { ActionId = null, Target = null },
            };
            _app.Upsert(final with { Enabled = true });
            ShowToast(Loc.T("Raccourci modifié"));
        }
        else if (result == ContentDialogResult.Secondary)
        {
            Delete(existing);
        }
    }
}
