// « Pas content ? » de l'Organiser (13/11, maquette validée « parfait go », comme le Mac : OrganizerFeedbackView de
// Sources/FLShortcut/OrganizerFeedback.swift) : une liste de quatre lignes (un son mal rangé, le Mixer, la Playlist,
// les couleurs), chacune ouvre sa page où l'on corrige tout de suite ; « Autre chose ? » part à l'équipe. « C'est noté »
// garde ce qui a changé pour les prochains rangements ; « Annuler » (ou Échap sur la liste) remet tout comme avant.
using FLShortcut.Core;
using FLShortcut.Core.Organizer;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal sealed partial class OrganizerWindow
{
    private enum FeedbackPage { List, Sounds, Mixer, Playlist, Colors }

    private async void ShowFeedback()
    {
        if (Content?.XamlRoot is not { } root) return;
        var feedback = new OrganizerFeedback { Share = _controller.SharingCorrections };
        var styles = new Dictionary<SoundFamily, FamilyStyle>(_controller.Styles);
        var options = _controller.Options;
        var page = FeedbackPage.List;
        var colorFamily = SoundFamily.Drums;
        var submitted = false;
        var leaving = false;
        var body = new Grid { Width = 424, Height = 580 };
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Style = MainShell.DialogStyle(),
            RequestedTheme = MacLook.SurfaceTheme,
            Background = Brush(WindowColor),
            BorderBrush = Brush(LineColor),
            Content = body,
        };

        void Build()
        {
            body.Children.Clear();
            body.Children.Add(page switch
            {
                FeedbackPage.Sounds => SoundsPage(feedback, () => Go(FeedbackPage.List), Build),
                FeedbackPage.Mixer => MixerPage(() => feedback.Reasons.Add(OrganizerFeedback.Reason.Mixer), () => Go(FeedbackPage.List), Build),
                FeedbackPage.Playlist => PlaylistPage(() => feedback.Reasons.Add(OrganizerFeedback.Reason.Playlist), () => Go(FeedbackPage.List), Build),
                FeedbackPage.Colors => ColorsPage(colorFamily, f => { colorFamily = f; Build(); },
                    () => feedback.Reasons.Add(OrganizerFeedback.Reason.Look), () => Go(FeedbackPage.List)),
                _ => FeedbackList(feedback, Go, Close),
            });
        }
        void Go(FeedbackPage next)
        {
            page = next;
            Build();
        }
        void Close(bool send)
        {
            if (send)
            {
                submitted = true;
                _controller.SubmitFeedback(feedback);
            }
            leaving = true;
            dialog.Hide();
        }
        // Échap sur une page : retour à la liste (comme « ← Pas content ») ; sur la liste : Annuler.
        dialog.Closing += (_, e) =>
        {
            if (leaving || page == FeedbackPage.List) return;
            e.Cancel = true;
            Go(FeedbackPage.List);
        };
        Build();
        await dialog.ShowAsync();
        if (!submitted) _controller.Restore(styles, options);
        Render();
    }

    /// La liste : quatre lignes numérotées (ce qui a été corrigé en face, sur un carré rouge), « Autre chose ? »,
    /// Annuler / C'est noté.
    private static Grid FeedbackList(OrganizerFeedback feedback, Action<FeedbackPage> go, Action<bool> close)
    {
        string? Changed(OrganizerFeedback.Reason r) => feedback.Reasons.Contains(r) ? Loc.T("Changé") : null;
        var fixes = feedback.Fixes.Count;
        var sounds = fixes == 0 ? null : fixes == 1 ? Loc.T("1 son corrigé") : Loc.F("%lld sons corrigés", fixes);
        var lines = new StackPanel { BorderBrush = Brush(LineColor), BorderThickness = new Thickness(0, 1, 0, 0) };
        lines.Children.Add(FeedbackLine(1, Loc.T("Un son est mal rangé"), sounds, () => go(FeedbackPage.Sounds)));
        lines.Children.Add(FeedbackLine(2, Loc.T("Le Mixer"), Changed(OrganizerFeedback.Reason.Mixer), () => go(FeedbackPage.Mixer)));
        lines.Children.Add(FeedbackLine(3, Loc.T("La Playlist"), Changed(OrganizerFeedback.Reason.Playlist), () => go(FeedbackPage.Playlist)));
        lines.Children.Add(FeedbackLine(4, Loc.T("Les couleurs"), Changed(OrganizerFeedback.Reason.Look), () => go(FeedbackPage.Colors)));

        var other = new StackPanel { Spacing = 6 };
        other.Children.Add(SwissLabel(Loc.T("Autre chose ?"), 10.5));
        var text = new TextBox
        {
            Text = feedback.OtherText, PlaceholderText = Loc.T("Écris-le ici, ça part à l'équipe"), MaxLength = 1000,
            MinHeight = 40, CornerRadius = new CornerRadius(0), FontFamily = SwissFont,
        };
        text.TextChanged += (_, _) => feedback.OtherText = text.Text;
        other.Children.Add(text);

        var buttons = new Grid { ColumnSpacing = 12 };
        buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var cancel = Soft(Loc.T("Annuler"), () => close(false));
        cancel.HorizontalAlignment = HorizontalAlignment.Stretch;
        var send = Primary(Loc.T("C'est noté"), () => close(true));
        send.HorizontalAlignment = HorizontalAlignment.Stretch;
        Grid.SetColumn(send, 1);
        buttons.Children.Add(cancel);
        buttons.Children.Add(send);

        return FeedbackFrame(FeedbackHead(Loc.T("pas content"),
            Loc.T("Touche ce qui ne va pas et corrige-le. L'ordinateur s'en souviendra la prochaine fois."), null),
            Stack(20, lines, other), buttons);
    }

    /// Une page : le titre en haut, le contenu au milieu (il prend la place), les boutons en bas.
    private static Grid FeedbackFrame(FrameworkElement head, FrameworkElement content, FrameworkElement bottom)
    {
        var grid = new Grid { RowSpacing = 20 };
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.Children.Add(head);
        Grid.SetRow(content, 1);
        grid.Children.Add(content);
        Grid.SetRow(bottom, 2);
        grid.Children.Add(bottom);
        return grid;
    }

    /// Titre d'une page : « ← PAS CONTENT » pour revenir (pages), le titre en minuscules avec son point carré, une
    /// phrase grise, un trait d'encre dessous.
    private static Border FeedbackHead(string title, string sentence, Action? back)
    {
        var stack = new StackPanel { Spacing = 12 };
        if (back is not null)
        {
            var label = Label("← " + Loc.T("Pas content").ToUpper(System.Globalization.CultureInfo.CurrentCulture), 12, Text, bold: true);
            label.CharacterSpacing = 100;
            var button = new Button { Style = PlainButton, Content = label, MinHeight = 28, Padding = new Thickness(0) };
            button.Click += (_, _) => back();
            AutomationProperties.SetName(button, Loc.T("Pas content"));
            stack.Children.Add(button);
        }
        var heading = SwissTitle(40);
        heading.Text = title;
        stack.Children.Add(PageTitle(heading, 40));
        stack.Children.Add(Paragraph(sentence, 13.5));
        return new Border
        {
            Child = stack,
            Padding = new Thickness(0, 0, 0, 14),
            BorderBrush = Brush(Text),
            BorderThickness = new Thickness(0, 0, 0, 1),
        };
    }

    /// Une ligne de la liste : numéro gris, nom en gras, à droite ce qui a été corrigé (carré rouge) ou une flèche.
    private static Button FeedbackLine(int number, string title, string? state, Action open)
    {
        var grid = new Grid { MinHeight = 60, ColumnSpacing = 14 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(18) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var digits = Label(number.ToString("00", System.Globalization.CultureInfo.InvariantCulture), 11, Secondary);
        digits.CharacterSpacing = 110;
        grid.Children.Add(digits);
        var name = Label(title, 16, Text, bold: true);
        Grid.SetColumn(name, 1);
        grid.Children.Add(name);
        FrameworkElement end;
        TextBlock? arrow = null;
        if (state is not null)
        {
            var done = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
            done.Children.Add(new Rectangle { Width = 8, Height = 8, Fill = Brush(Red), VerticalAlignment = VerticalAlignment.Center });
            done.Children.Add(Label(state, 12, Text));
            end = done;
        }
        else
        {
            arrow = Label("→", 14, Secondary);
            end = arrow;
        }
        Grid.SetColumn(end, 2);
        grid.Children.Add(end);
        var face = new Border
        {
            Child = grid, Background = Brush(Colors.Transparent), BorderBrush = Brush(LineColor), BorderThickness = new Thickness(0, 0, 0, 1),
        };
        var button = new Button
        {
            Style = PlainButton, Content = face, Padding = new Thickness(0),
            HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch,
        };
        button.Click += (_, _) => open();
        if (arrow is not null)
        {
            button.PointerEntered += (_, _) => arrow.Foreground = Brush(Text);
            button.PointerExited += (_, _) => arrow.Foreground = Brush(Secondary);
        }
        AutomationProperties.SetName(button, state is null ? title : title + " : " + state);
        return button;
    }

    /// « C'est bon » en bas à droite d'une page : retour à la liste.
    private static Button FeedbackDone(Action done)
    {
        var button = Primary(Loc.T("C'est bon"), done);
        button.MinWidth = 120;
        button.HorizontalAlignment = HorizontalAlignment.Right;
        return button;
    }

    // ---------- Un son est mal rangé ----------

    private Grid SoundsPage(OrganizerFeedback feedback, Action done, Action refresh)
    {
        var correctable = _controller.Correctable;
        var rows = new StackPanel();
        foreach (var item in correctable) rows.Children.Add(FeedbackSoundRow(item, feedback, refresh));
        var content = new Grid { RowSpacing = 14 };
        content.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        content.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        content.Children.Add(new ScrollViewer { Content = rows, Padding = new Thickness(0, 0, 12, 0) });
        // Les sons écoutés corrigés peuvent aider l'ordinateur de tout le monde (des nombres seulement).
        var heard = feedback.Fixes.Keys.Any(index => correctable.Any(i => i.Index == index && i.SoundPrint is not null));
        if (heard)
        {
            var words = new TextBlock { FontFamily = SwissFont, FontSize = 12.5, TextWrapping = TextWrapping.Wrap };
            words.Inlines.Add(new Microsoft.UI.Xaml.Documents.Run { Text = Loc.T("Aider l'ordinateur de tout le monde"), Foreground = Brush(Text) });
            words.Inlines.Add(new Microsoft.UI.Xaml.Documents.Run { Text = " · " + Loc.T("des nombres, jamais le son"), Foreground = Brush(Secondary) });
            var share = new CheckBox { IsChecked = feedback.Share, MinWidth = 0, Content = words };
            share.Checked += (_, _) => feedback.Share = true;
            share.Unchecked += (_, _) => feedback.Share = false;
            Grid.SetRow(share, 1);
            content.Children.Add(share);
        }
        return FeedbackFrame(FeedbackHead(Loc.T("les sons"), Loc.T("Choisis la bonne famille du son qui n'est pas à sa place."), done),
            content, FeedbackDone(done));
    }

    /// Un son : la couleur de sa famille, son nom, la case de sa famille et de sa sorte (liste suisse ; pleine d'encre
    /// une fois corrigée).
    private Grid FeedbackSoundRow(OrganizerItem item, OrganizerFeedback feedback, Action refresh)
    {
        OrganizerFeedback.Fix? fixedTo = feedback.Fixes.TryGetValue(item.Index, out var fix) ? fix : null;
        var current = _controller.Families.TryGetValue(item.Index, out var f) ? f : item.Family;
        var family = fixedTo?.Family ?? current;
        string label;
        if (fixedTo is { } c) label = c.Kind is { } k ? c.Family.Label() + " · " + k.Name() : c.Family.Label();
        else label = _controller.KindOf(item.Index) is { } kind ? current.Label() + " · " + kind.Name() : current.Label();

        void Pick(SoundFamily choice, SoundKind? kind)
        {
            feedback.Fixes[item.Index] = new OrganizerFeedback.Fix(choice, kind);
            feedback.Reasons.Add(OrganizerFeedback.Reason.Family);
            refresh();
        }
        var menu = new MenuFlyout();
        foreach (var choice in SoundFamilies.Order)
        {
            var picked = choice;
            if (choice.Kinds().Length == 0)
            {
                var single = new ToggleMenuFlyoutItem { Text = choice.Label(), IsChecked = family == choice };
                single.Click += (_, _) => Pick(picked, null);
                menu.Items.Add(single);
                continue;
            }
            menu.Items.Add(new MenuFlyoutItem
            {
                Text = choice.Label().ToUpper(System.Globalization.CultureInfo.CurrentCulture), IsEnabled = false,
            });
            foreach (var k in choice.Kinds())
            {
                var kind = k;
                var entry = new ToggleMenuFlyoutItem { Text = k.Name(), IsChecked = fixedTo is { } x && x.Family == choice && x.Kind == k };
                entry.Click += (_, _) => Pick(picked, kind);
                menu.Items.Add(entry);
            }
        }

        var chosen = fixedTo is not null;
        var inside = new Grid { ColumnSpacing = 4 };
        inside.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        inside.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        inside.Children.Add(Label(label, 12.5, chosen ? WindowColor : Text, bold: chosen));
        var chevron = Label("▾", 10, chosen ? WindowColor : Text, bold: true);
        Grid.SetColumn(chevron, 1);
        inside.Children.Add(chevron);
        var box = new Button
        {
            Style = PlainButton, Content = inside, Width = 180, Height = 30, Padding = new Thickness(10, 0, 10, 0),
            HorizontalContentAlignment = HorizontalAlignment.Stretch, VerticalAlignment = VerticalAlignment.Center,
            Background = Brush(chosen ? Text : WindowColor), BorderBrush = Brush(chosen ? Text : Tertiary),
            BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(0),
            Flyout = SwissMenu(menu),
        };
        var shown = item.Name.Length == 0 ? Loc.T("(sans nom)") : item.Name;
        ToolTipService.SetToolTip(box, Loc.T("Ce qu'est vraiment ce son"));
        AutomationProperties.SetName(box, shown + " : " + label);

        var row = new Grid { MinHeight = 46, ColumnSpacing = 10, BorderBrush = Brush(Faint), BorderThickness = new Thickness(0, 0, 0, 1) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.Children.Add(new Rectangle
        {
            Width = 12, Height = 12, Fill = Brush(ColorOf(_controller.StyleOf(family).Color)), VerticalAlignment = VerticalAlignment.Center,
        });
        var name = Label(shown, 13.5, Text);
        Grid.SetColumn(name, 1);
        row.Children.Add(name);
        Grid.SetColumn(box, 2);
        row.Children.Add(box);
        return row;
    }

    // ---------- Le Mixer ----------

    private Grid MixerPage(Action changed, Action done, Action refresh)
    {
        var families = new StackPanel { BorderBrush = Brush(LineColor), BorderThickness = new Thickness(0, 1, 0, 0) };
        foreach (var family in SoundFamilies.Order.Where(f => f != SoundFamily.Unsure))
        {
            var style = _controller.StyleOf(family);
            var row = new Grid { MinHeight = 46, ColumnSpacing = 12, BorderBrush = Brush(Faint), BorderThickness = new Thickness(0, 0, 0, 1) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.Children.Add(new Rectangle { Width = 12, Height = 12, Fill = Brush(ColorOf(style.Color)), VerticalAlignment = VerticalAlignment.Center });
            var name = SwissLabel(family.Label(), 12.5, Text);
            Grid.SetColumn(name, 1);
            row.Children.Add(name);
            var track = Label(Loc.T("piste"), 11, Secondary);
            Grid.SetColumn(track, 2);
            row.Children.Add(track);
            var first = family;
            var box = new SlotBox(style.MixerStart, style.MixerStart is not null, _controller.MixerLast, ColorOf(style.Color), start =>
            {
                _controller.SetMixerStart(first, start);
                changed();
                refresh();
            })
            { VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(box, 3);
            row.Children.Add(box);
            families.Children.Add(row);
        }
        var options = _controller.Options;
        var switches = new StackPanel();
        switches.Children.Add(SwitchRow(Loc.T("Un bus par famille"), options.Buses, true, on =>
        {
            _controller.SetOptions(_controller.Options with { Buses = on });
            changed();
            refresh();
        }));
        switches.Children.Add(SwitchRow(Loc.T("Pré-master avant le Master"), options.Premaster, options.Buses, on =>
        {
            _controller.SetOptions(_controller.Options with { Premaster = on });
            changed();
            refresh();
        }));
        var hint = Paragraph(Loc.T("Tire la case vers le haut ou le bas, comme dans FL, ou clique pour écrire."), 11.5);
        return FeedbackFrame(FeedbackHead(Loc.T("le mixer"), Loc.T("Où commence chaque famille dans le Mixer ?"), done),
            Stack(20, families, switches, hint), FeedbackDone(done));
    }

    /// Une ligne à interrupteur carré (SwissSwitch du Mac) : le texte, l'interrupteur à droite ; éteinte : à demi
    /// transparente.
    private static Grid SwitchRow(string title, bool on, bool enabled, Action<bool> set)
    {
        var row = new Grid
        {
            MinHeight = 40, BorderBrush = Brush(Faint), BorderThickness = new Thickness(0, 0, 0, 1), Opacity = enabled ? 1 : 0.45,
        };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.Children.Add(Label(title, 13.5, Text));
        var knob = new Rectangle
        {
            Width = 12, Height = 12, Fill = Brush(on ? WindowColor : Text), Margin = new Thickness(3, 0, 3, 0),
            HorizontalAlignment = on ? HorizontalAlignment.Right : HorizontalAlignment.Left,
        };
        var track = new Grid { Width = 40, Height = 20 };
        track.Children.Add(new Border { Background = Brush(on ? Text : WindowColor), BorderBrush = Brush(Text), BorderThickness = new Thickness(1) });
        track.Children.Add(knob);
        var button = new Button { Style = PlainButton, Content = track, IsEnabled = enabled, VerticalAlignment = VerticalAlignment.Center };
        button.Click += (_, _) => set(!on);
        AutomationProperties.SetName(button, title);
        Grid.SetColumn(button, 1);
        row.Children.Add(button);
        return row;
    }

    // ---------- La Playlist ----------

    private const double PlaylistRow = 54;

    private Grid PlaylistPage(Action changed, Action done, Action refresh)
    {
        var order = _controller.Options.FamilyOrder.Where(f => f != SoundFamily.Unsure).ToList();
        var list = new StackPanel { Spacing = 6 };
        for (var i = 0; i < order.Count; i++)
        {
            var family = order[i];
            var face = new Grid { Height = PlaylistRow - 6, ColumnSpacing = 14, Padding = new Thickness(14, 0, 14, 0) };
            face.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            face.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(18) });
            face.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
            face.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            face.Children.Add(SixDots());
            var number = Label((i + 1).ToString("00", System.Globalization.CultureInfo.InvariantCulture), 11, Secondary);
            number.CharacterSpacing = 110;
            Grid.SetColumn(number, 1);
            face.Children.Add(number);
            var square = new Rectangle
            {
                Width = 12, Height = 12, Fill = Brush(ColorOf(_controller.StyleOf(family).Color)), VerticalAlignment = VerticalAlignment.Center,
            };
            Grid.SetColumn(square, 2);
            face.Children.Add(square);
            var name = SwissLabel(family.Label(), 12.5, Text);
            Grid.SetColumn(name, 3);
            face.Children.Add(name);
            var card = new Border
            {
                Child = face, Background = Brush(WindowColor), BorderBrush = Brush(LineColor), BorderThickness = new Thickness(1),
                RenderTransform = new TranslateTransform(),
            };
            AutomationProperties.SetName(card, family.Label());
            ToolTipService.SetToolTip(card, Loc.T("Tire vers le haut ou le bas"));
            // Tirée : pleine d'encre, devant les autres ; lâchée : posée au rang le plus proche.
            double? start = null;
            card.PointerPressed += (_, e) =>
            {
                start = e.GetCurrentPoint(list).Position.Y;
                card.CapturePointer(e.Pointer);
                card.Background = Brush(Text);
                name.Foreground = Brush(WindowColor);
                number.Foreground = Brush(WindowColor);
                Canvas.SetZIndex(card, 1);
                e.Handled = true;
            };
            card.PointerMoved += (_, e) =>
            {
                if (start is not { } y0) return;
                ((TranslateTransform)card.RenderTransform).Y = e.GetCurrentPoint(list).Position.Y - y0;
            };
            void Drop(PointerRoutedEventArgs e)
            {
                if (start is not { } y0) return;
                start = null;
                card.ReleasePointerCaptures();
                var steps = (int)Math.Round((e.GetCurrentPoint(list).Position.Y - y0) / PlaylistRow);
                var from = order.IndexOf(family);
                if (steps != 0 && from >= 0)
                {
                    var moved = order.ToList();
                    moved.RemoveAt(from);
                    moved.Insert(Math.Clamp(from + steps, 0, moved.Count), family);
                    _controller.SetFamilyOrder(moved);
                    changed();
                }
                refresh();
            }
            card.PointerReleased += (_, e) => Drop(e);
            card.PointerCaptureLost += (_, _) =>
            {
                if (start is null) return;
                start = null;
                refresh();
            };
            list.Children.Add(card);
        }
        var hint = Paragraph(Loc.T("Le Channel rack et le Mixer suivent le même ordre."), 11.5);
        return FeedbackFrame(FeedbackHead(Loc.T("la playlist"), Loc.T("Range les familles dans l'ordre que tu veux, de haut en bas."), done),
            Stack(20, list, hint), FeedbackDone(done));
    }

    // ---------- Les couleurs ----------

    private Grid ColorsPage(SoundFamily family, Action<SoundFamily> choose, Action changed, Action done)
    {
        var families = new StackPanel { Width = 120, BorderBrush = Brush(LineColor), BorderThickness = new Thickness(0, 1, 0, 0) };
        foreach (var choice in SoundFamilies.Order.Where(f => f != SoundFamily.Unsure))
        {
            var chosen = choice == family;
            var face = new Grid { Height = 46, ColumnSpacing = 10, Padding = new Thickness(10, 0, 10, 0) };
            face.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(18) });
            face.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            face.Children.Add(new Border
            {
                Width = 18, Height = 18, Background = Brush(ColorOf(_controller.StyleOf(choice).Color)),
                BorderBrush = Brush(Tertiary), BorderThickness = new Thickness(1), VerticalAlignment = VerticalAlignment.Center,
            });
            var name = SwissLabel(choice.Label(), 11.5, chosen ? WindowColor : Text);
            Grid.SetColumn(name, 1);
            face.Children.Add(name);
            var picked = choice;
            var button = new Button
            {
                Style = PlainButton, Padding = new Thickness(0), HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Stretch,
                Content = new Border
                {
                    Child = face, Background = Brush(chosen ? Text : WindowColor), BorderBrush = Brush(Faint), BorderThickness = new Thickness(0, 0, 0, 1),
                },
            };
            button.Click += (_, _) => choose(picked);
            AutomationProperties.SetName(button, choice.Label());
            families.Children.Add(button);
        }
        var wheel = ColorSelector(_controller.StyleOf(family).Color, picked =>
        {
            _app.RememberColor(picked);
            _controller.SetBaseColor(family, picked);
            changed();
            choose(family);
        });
        var content = new Grid { ColumnSpacing = 14 };
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        content.Children.Add(families);
        var right = new ScrollViewer { Content = wheel, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
        Grid.SetColumn(right, 1);
        content.Children.Add(right);
        return FeedbackFrame(FeedbackHead(Loc.T("les couleurs"), Loc.T("Choisis la couleur de chaque famille."), done),
            content, FeedbackDone(done));
    }
}
