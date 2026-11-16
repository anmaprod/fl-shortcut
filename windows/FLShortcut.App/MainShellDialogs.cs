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

    /// Champ de touche, comme CaptureField du Mac : la touche au milieu, ou ce qu'il faut faire ; un clic, puis les
    /// touches appuyées la remplacent (Échap annule, ⌫ efface) ; bordé de rouge pendant l'écoute.
    private static Button CaptureButton() => new()
    {
        Style = PlainButton,
        MinHeight = 52,
        HorizontalAlignment = HorizontalAlignment.Stretch,
        HorizontalContentAlignment = HorizontalAlignment.Center,
        VerticalContentAlignment = VerticalAlignment.Center,
        Padding = new Thickness(10, 6, 10, 6),
        CornerRadius = new CornerRadius(0),
        Background = Brush(MacLook.WindowColor),
        BorderBrush = Brush(LineColor),
        BorderThickness = new Thickness(1),
    };

    private static void SetCapture(Button button, KeyCombo? combo, bool recording, bool changed, string? placeholder = null)
    {
        button.BorderBrush = Brush(recording ? Red : LineColor);
        button.BorderThickness = new Thickness(recording ? 2 : 1);
        button.Content = recording ? Label(Loc.T("Appuie sur les touches…"), 13, Red)
            : combo is null ? Label(placeholder ?? Loc.T("Cliquer pour enregistrer"), 13, Secondary)
            : Keys(combo, changed);
        AutomationProperties.SetName(button, recording ? Loc.T("Appuie sur les touches…") : combo?.ToString() ?? Loc.T("Aucune"));
        if (recording) button.Focus(FocusState.Programmatic);
    }

    /// Un avertissement comme SwissWarning du Mac : un petit carré rouge devant le texte, le texte à l'encre.
    private static Grid WarningLine(string text, double size)
    {
        var grid = new Grid { ColumnSpacing = 8 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.Children.Add(new Microsoft.UI.Xaml.Shapes.Rectangle
        {
            Width = 7,
            Height = 7,
            Fill = Brush(Red),
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, size * 0.45, 0, 0),
        });
        var label = Paragraph(text, size, Text);
        Grid.SetColumn(label, 1);
        grid.Children.Add(label);
        return grid;
    }

    /// Changer la touche d'un raccourci de FL ou d'une action en plus : la même fiche que le Mac (CatalogEditSheet ;
    /// 16/11, « c'est pas du tout le même que sur mac ») : la page en petites capitales et le nom en grand, souligné ;
    /// TOUCHE (un clic, puis les touches ; ce qui l'utilise déjà dessous) ; D'ORIGINE ; puis Réinitialiser, Aucune
    /// touche, Tester … Annuler, Valider. `notice` : la touche vient d'être reprise par un autre raccourci, celui-ci en
    /// reçoit une nouvelle.
    private async void EditKey(CatalogRow row, string? notice = null)
    {
        if (_root.XamlRoot is not { } root || DialogGuard.AnyOpen(root)) return;
        KeyCombo? combo = row.Current;
        var recording = false;
        var saved = false;
        var native = row.Entry.Kind is CatalogEntryKind.Native(var n) ? n : (KeyCombo?)null;
        int? actionId = row.Entry.Kind is CatalogEntryKind.Action(var id) ? id : null;
        var dialog = SwissQuestion.SwissPanel(root);

        var body = new StackPanel { Spacing = 16, Width = 432 };
        body.Children.Add(SheetHeader(row.Entry.Section.Title(), row.Entry.Title));
        if (notice is not null) body.Children.Add(WarningLine(notice, 12));

        var capture = CaptureButton();
        var clashPanel = new StackPanel { Spacing = 2 };
        var issuePanel = new StackPanel { Spacing = 2 };
        body.Children.Add(SheetRow(Loc.T("Touche"), new StackPanel { Spacing = 6, Children = { capture, clashPanel, issuePanel } }));
        body.Children.Add(SheetRow(Loc.T("D'origine"), Label(row.Entry.DefaultTrigger?.ToString() ?? Loc.T("Aucune"), 13, Text, bold: true)));

        // Déclarés d'abord : Refresh les règle, et les boutons l'appellent.
        Button reset = null!, save = null!;
        Button? none = null;
        reset = Soft(Loc.T("Réinitialiser"), "reset", () =>
        {
            combo = row.Entry.DefaultTrigger;
            Refresh();
        });
        var left = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Children = { reset } };
        if (actionId is { } action)
        {
            none = Soft(Loc.T("Aucune touche"), () =>
            {
                combo = null;
                Refresh();
            });
            left.Children.Add(none);
            if (!_app.Light)
            {
                var test = Soft(Loc.T("Tester"), () => _app.TestAction(action));
                ToolTipService.SetToolTip(test, Loc.T("Envoie l'action à FL Studio"));
                left.Children.Add(test);
            }
        }
        save = Primary(Loc.T("Valider"), () =>
        {
            saved = true;
            dialog.Hide();
        });
        var right = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Right };
        right.Children.Add(Soft(Loc.T("Annuler"), dialog.Hide));
        right.Children.Add(save);
        if (actionId is null)
        {
            // Une seule rangée, comme le Mac : Réinitialiser à gauche, Annuler et Valider à droite.
            var buttons = new Grid();
            buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            buttons.Children.Add(left);
            Grid.SetColumn(right, 1);
            buttons.Children.Add(right);
            body.Children.Add(buttons);
        }
        else
        {
            // Une action en plus a trois boutons de plus : Annuler et Valider passent dessous, à droite.
            body.Children.Add(left);
            body.Children.Add(right);
        }
        dialog.Content = body;

        List<KeyClash> Clashes() => combo is { } c && c != row.Current ? _app.Clashes(c, row) : new List<KeyClash>();

        static void Enable(Button button, bool on)
        {
            button.IsEnabled = on;
            button.Opacity = on ? 1 : 0.35;
        }

        void Refresh()
        {
            SetCapture(capture, combo, recording, combo != row.Entry.DefaultTrigger);
            clashPanel.Children.Clear();
            var clashes = Clashes();
            if (clashes.Count > 0 && !recording)
            {
                clashPanel.Children.Add(WarningLine(Loc.T("Déjà utilisée par :"), 11));
                foreach (var c in clashes.Take(4)) clashPanel.Children.Add(Paragraph(Line(c), 11, Secondary));
                if (clashes.Count > 4) clashPanel.Children.Add(Paragraph(Loc.F("et %lld autres", clashes.Count - 4), 11, Secondary));
            }
            issuePanel.Children.Clear();
            var issues = combo is { } k && k != native
                ? _app.IssuesFor(CatalogRows.Draft(row, combo))
                      .Where(i => i is not ShortcutIssue.NoTrigger and not ShortcutIssue.NoTarget).ToList()
                : new List<ShortcutIssue>();
            if (!recording && issues.Count > 0)
                issuePanel.Children.Add(WarningLine(string.Join("\n", issues.Select(i => i.Message)), 11));
            Enable(save, !recording && combo != row.Current && !issues.Any(i => i.IsBlocking)
                         && (combo is not null || actionId is not null));
            Enable(reset, combo != row.Entry.DefaultTrigger);
            if (none is not null) Enable(none, combo is not null);
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
            if (e.Key == Windows.System.VirtualKey.Back && !pressed.HasModifiers)
            {
                combo = null;                       // ⌫ : efface, comme le Mac
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
        // Échap ferme la fiche, Entrée valide (comme le Mac) ; pendant l'écoute, les touches vont au champ.
        dialog.PreviewKeyDown += (_, e) =>
        {
            if (recording) return;
            if (e.Key == Windows.System.VirtualKey.Escape)
            {
                e.Handled = true;
                dialog.Hide();
            }
            else if (e.Key == Windows.System.VirtualKey.Enter && save.IsEnabled)
            {
                e.Handled = true;
                saved = true;
                dialog.Hide();
            }
        };

        Refresh();
        await dialog.ShowSafeAsync();
        _app.SetRecording(false);
        if (!saved) return;

        // Une touche ne sert qu'une fois (comme le Mac) : ce qui l'utilise est dit d'abord, puis repris.
        var found = Clashes();
        if (found.Count > 0 && !await ConfirmReplace(combo, found)) return;
        _app.SetKey(row, combo, found);
        ShowToast(Loc.F("« %@ » : ", row.Entry.Title) + (combo?.ToString() ?? Loc.T("aucune touche")));
        // L'entrée qui a perdu sa touche en reçoit une nouvelle tout de suite (la fiche d'avant s'est refermée).
        if (found.FirstOrDefault(c => c.Row is not null)?.Row?.Id is { } next
            && _app.Catalog.Rows.FirstOrDefault(r => r.Id == next) is { } nextRow)
        {
            await Task.Delay(400);
            EditKey(nextRow, Loc.F("Choisis une nouvelle touche pour « %@ ».", nextRow.Entry.Title));
        }
    }

    /// Ce qui utilise déjà une touche, en une ligne (comme le Mac).
    private static string Line(KeyClash c)
    {
        var place = c.Section is { } s ? $" ({s})" : "";
        return c.IsFlKey ? Loc.F("« %@ »%@, touche d'origine de FL", c.Title, place)
                         : Loc.F("« %@ »%@, ton raccourci", c.Title, place);
    }

    /// Une question (Mon compte : se déconnecter, supprimer le compte) ; vrai si l'on choisit `primary`. Question
    /// suisse comme le Mac (SwissQuestion) ; Entrée ne choisit jamais une action qui efface.
    private async Task<bool> ConfirmAsync(string title, string text, string primary, bool destructive)
    {
        if (_root.XamlRoot is not { } root) return false;
        return await SwissQuestion.AskAsync(root, title, text, new[] { primary, Loc.T("Annuler") },
                                            destructive ? 0 : null) == 0;
    }

    /// Une question à trois réponses : 0 (`first`), 1 (`second`), 2 (Annuler, le choix par défaut).
    private async Task<int> ChooseAsync(string title, string text, string first, string second)
    {
        if (_root.XamlRoot is not { } root) return 2;
        return await SwissQuestion.AskAsync(root, title, text, new[] { first, second, Loc.T("Annuler") });
    }

    /// Une touche ne sert qu'une fois : ce qui l'utilise est dit avant de la reprendre (comme le Mac : les lignes seules).
    private async Task<bool> ConfirmReplace(KeyCombo? combo, List<KeyClash> clashes)
    {
        if (_root.XamlRoot is not { } root) return false;
        return await SwissQuestion.AskAsync(root, Loc.F("%@ est déjà utilisée", combo?.ToString() ?? Loc.T("Cette touche")),
                                            string.Join("\n", clashes.Take(4).Select(Line)),
                                            new[] { Loc.T("Remplacer"), Loc.T("Annuler") }, destructive: 0) == 0;
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
        var cats = MacLook.SwissCombo(new ComboBox());
        var actions = new ListView();
        var wheres = MacLook.SwissCombo(new ComboBox());
        var keyPanel = new StackPanel { Spacing = 6 };
        var targetButton = CaptureButton();
        var macroPanel = new StackPanel();
        var macroPicker = MacLook.SwissCombo(new ComboBox());
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
            SetCapture(targetButton, draft.Target, recordingFor == "target", false, Loc.T("Cliquer, puis taper la touche de FL"));
            kinds.SelectedIndex = draft.Kind switch { ShortcutKind.FlAction => 0, ShortcutKind.Keystroke => 1, _ => 2 };
            actionPanel.Visibility = draft.Kind == ShortcutKind.FlAction ? Visibility.Visible : Visibility.Collapsed;
            keyPanel.Visibility = draft.Kind == ShortcutKind.Keystroke ? Visibility.Visible : Visibility.Collapsed;
            macroPanel.Visibility = draft.Kind == ShortcutKind.Macro ? Visibility.Visible : Visibility.Collapsed;
            macroPicker.SelectedItem = macroPicker.Items.OfType<ComboBoxItem>().FirstOrDefault(x => x.Tag is Guid g && g == draft.MacroRef);
            wheres.SelectedItem = wheres.Items.OfType<ComboBoxItem>().FirstOrDefault(x => x.Tag is ShortcutContext c && c == draft.Context);
            cats.SelectedItem = cats.Items.OfType<ComboBoxItem>().FirstOrDefault(x => x.Tag is ActionCategory c && c == category);
            actions.Items.Clear();
            foreach (var info in FlActions.Offered.Where(x => x.Category == category))
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
        var result = await dialog.ShowSafeAsync();
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
