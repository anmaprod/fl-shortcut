// « Tu valides la version organisée ? », posée à la réouverture de FL Shortcuts une fois l'Organiser fermé (comme sur le
// Mac, Sources/FLShortcut/OrganizerCopyApproval.swift) : « Oui, valider » (l'original à la Corbeille, la version
// organisée prend son nom, FL la rouvre), « Retourner en arrière » (la version organisée à la Corbeille, FL rouvre le
// projet d'avant), « Plus tard ». Les règles et les fichiers sont ceux du cœur (CopyApproval, testé). Aspect du Mac
// (29/10) : boîte sombre, l'icône des versions, la question en gras, « Retourner en arrière » et « Oui, valider » (bleu)
// côte à côte, « Plus tard » en lien dessous.
using FLShortcut.App.Services;
using FLShortcut.Core;
using FLShortcut.Core.Organizer;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal static class CopyApprovalPrompt
{
    private static bool _showing;

    /// `force` : demandé par le menu de l'icône (même après « Plus tard »). `keepCopy` (13/11) : « Garder » de l'écran de
    /// fin de l'Organiser, cette version rangée gardée tout de suite, sans la question.
    public static async void Ask(XamlRoot? root, AppController app, bool force, string? keepCopy = null)
    {
        var approval = app.Approval;
        if (_showing || root is null) return;
        PendingCopy? kept = null;
        if (keepCopy is not null)
        {
            approval.Prune();
            kept = approval.Pending.FirstOrDefault(p => string.Equals(System.IO.Path.GetFullPath(p.Copy),
                System.IO.Path.GetFullPath(keepCopy), StringComparison.OrdinalIgnoreCase));
            if (kept is null) return;
        }
        else if (force)
        {
            approval.Prune();
            if (approval.Pending.Count == 0 || OrganizerWindow.IsOpen) return;
        }
        else if (!approval.ShouldAsk(OrganizerWindow.IsOpen))
        {
            return;
        }
        _showing = true;
        try
        {
            while (approval.Pending.Count > 0)
            {
                var p = kept ?? approval.Pending[0];
                var answer = kept is not null ? ContentDialogResult.Primary
                    : await Question(root, app, p, approval.Pending.Count - 1);
                kept = null;
                if (answer == ContentDialogResult.None)
                {
                    approval.Snooze();
                    return;
                }
                var keep = answer == ContentDialogResult.Primary;
                var working = Dialog(root);
                working.Content = Message("square.stack.3d.up", Indigo, keep ? Loc.T("FL enregistre la version organisée…") : Loc.T("FL rouvre ton projet d'avant…"),
                    new ProgressRing { IsActive = true, Width = 20, Height = 20, Foreground = Brush(Indigo) });
                var shown = working.ShowAsync();
                var files = approval.Files;
                var error = await Task.Run(() => keep ? Fl.Validate(p, files) : Fl.GoBack(p, files));
                working.Hide();
                await shown;
                if (error is { } e && e != CopyApprovalError.CopyMissing)
                {
                    if (await Failed(root, e.Message(), retry: true) == ContentDialogResult.Primary) continue;
                    approval.Snooze();
                    return;
                }
                // Répondu, ou la version organisée a disparu (plus rien à demander pour elle) : la suivante.
                approval.Done(p);
                approval.Prune();
                if (error is { } gone) await Failed(root, gone.Message(), retry: false);
            }
        }
        finally
        {
            _showing = false;
        }
    }

    /// Boîte sombre, sans boutons du système (ceux du Mac sont dans son contenu) ; Échap = « Plus tard ».
    private static ContentDialog Dialog(XamlRoot root) => new()
    {
        XamlRoot = root,
        Style = MainShell.DialogStyle(),
        RequestedTheme = MacLook.SurfaceTheme,
        Background = Brush(Rgb(0x1E, 0x1E, 0x21)),
        BorderBrush = Brush(LineColor),
    };

    /// Le contenu centré : une icône de couleur, un texte en gras, puis ce qui suit (attente, boutons).
    private static StackPanel Message(string icon, Windows.UI.Color tint, string title, params UIElement[] then)
    {
        var body = new StackPanel { Spacing = 10, Width = 340, Padding = new Thickness(0, 6, 0, 0) };
        var tile = Tile(icon, tint, 44);
        tile.HorizontalAlignment = HorizontalAlignment.Center;
        body.Children.Add(tile);
        var heading = Label(title, 13.5, Text, bold: true);
        heading.HorizontalAlignment = HorizontalAlignment.Center;
        heading.TextAlignment = TextAlignment.Center;
        body.Children.Add(heading);
        foreach (var element in then)
        {
            if (element is FrameworkElement f && f.HorizontalAlignment == HorizontalAlignment.Left) f.HorizontalAlignment = HorizontalAlignment.Center;
            body.Children.Add(element);
        }
        return body;
    }

    private static TextBlock Centered(string text, double size, Windows.UI.Color color)
    {
        var label = Paragraph(text, size, color);
        label.TextAlignment = TextAlignment.Center;
        label.HorizontalAlignment = HorizontalAlignment.Center;
        return label;
    }

    /// Deux boutons côte à côte, de même largeur.
    private static Grid Pair(Button left, Button right)
    {
        var grid = new Grid { ColumnSpacing = 8, Margin = new Thickness(0, 8, 0, 0), HorizontalAlignment = HorizontalAlignment.Stretch };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        left.HorizontalAlignment = right.HorizontalAlignment = HorizontalAlignment.Stretch;
        grid.Children.Add(left);
        Grid.SetColumn(right, 1);
        grid.Children.Add(right);
        return grid;
    }

    /// « tu gardes la version rangée » (13/11, maquette validée, comme le Mac) : deux grandes cases, GARDER (une mini
    /// Playlist rangée aux couleurs choisies pour les familles) et REVENIR COMME AVANT (la même en désordre), soulevées
    /// au survol ; « Plus tard » en bas à droite. Primary = garder, Secondary = revenir, None = plus tard.
    private static async Task<ContentDialogResult> Question(XamlRoot root, AppController app, PendingCopy p, int remaining)
    {
        var answer = ContentDialogResult.None;
        var dialog = Dialog(root);
        var body = new StackPanel { Spacing = 22, Width = 424, Padding = new Thickness(0, 6, 0, 0) };
        var title = new TextBlock();
        title.Text = Loc.T("tu gardes la version rangée");
        var head = PageTitle(title, 34);
        head.Padding = new Thickness(0, 0, 0, 14);
        body.Children.Add(new Border { Child = head, BorderBrush = Brush(Text), BorderThickness = new Thickness(0, 0, 0, 1) });
        var styles = FamilyStyles.Decode(app.Settings.OrganizerStyles);
        var tiles = new Grid { ColumnSpacing = 16 };
        tiles.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        tiles.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        tiles.Children.Add(EndChoices.Tile(Loc.T("Garder"), true, () =>
        {
            answer = ContentDialogResult.Primary;
            dialog.Hide();
        }, 250, EndChoices.MiniPlaylist(true, styles)));
        var back = EndChoices.Tile(Loc.T("Revenir comme avant"), false, () =>
        {
            answer = ContentDialogResult.Secondary;
            dialog.Hide();
        }, 250, EndChoices.MiniPlaylist(false, styles));
        Grid.SetColumn(back, 1);
        tiles.Children.Add(back);
        body.Children.Add(tiles);
        var bottom = new Grid();
        if (remaining > 0) bottom.Children.Add(SwissLabel(Loc.F("Encore %lld projets ensuite.", remaining), 10.5, Secondary));
        var laterText = Label(Loc.T("Plus tard").ToUpper(System.Globalization.CultureInfo.CurrentCulture), 12, Text, bold: true);
        laterText.CharacterSpacing = 100;
        var later = new Button { Style = PlainButton, Content = laterText, MinHeight = 44, HorizontalAlignment = HorizontalAlignment.Right };
        later.Click += (_, _) => dialog.Hide();
        AutomationProperties.SetName(later, Loc.T("Plus tard"));
        bottom.Children.Add(later);
        body.Children.Add(bottom);
        dialog.Content = body;
        await dialog.ShowAsync();
        return answer;
    }

    /// Un échec (ou la version organisée disparue) : le message, puis « Plus tard » / « Réessayer », ou « OK ».
    private static async Task<ContentDialogResult> Failed(XamlRoot root, string text, bool retry)
    {
        var answer = ContentDialogResult.None;
        var dialog = Dialog(root);
        var message = Centered(text, 12, Text);
        UIElement buttons = retry
            ? Pair(Soft(Loc.T("Plus tard"), dialog.Hide), Primary(Loc.T("Réessayer"), () =>
              {
                  answer = ContentDialogResult.Primary;
                  dialog.Hide();
              }))
            : Primary(Loc.T("OK"), dialog.Hide);
        var body = Message("warning", Orange, "", message, buttons);
        body.Children.RemoveAt(1);                    // pas de titre : le message suffit
        dialog.Content = body;
        await dialog.ShowAsync();
        return answer;
    }

    /// Ce que FL fait autour des fichiers (FL devant pour enregistrer ; un double-clic pour ouvrir).
    internal static CopyApprovalFl Fl => new()
    {
        FlRunning = FlPresence.IsRunning,
        Shows = ProjectFileWindows.IsOpen,
        Open = ProjectFileWindows.Open,
        SaveShown = ProjectFileWindows.SaveShown,
        Launch = ProjectFileWindows.Open,
    };
}
