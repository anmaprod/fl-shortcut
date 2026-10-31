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

    /// `force` : demandé par le menu de l'icône (même après « Plus tard »).
    public static async void Ask(XamlRoot? root, AppController app, bool force)
    {
        var approval = app.Approval;
        if (_showing || root is null) return;
        if (force)
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
                var p = approval.Pending[0];
                var answer = await Question(root, p, approval.Pending.Count - 1);
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
        RequestedTheme = ElementTheme.Dark,
        Background = Brush(Rgb(0x1E, 0x1E, 0x21)),
        BorderBrush = Brush(White(0.16)),
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

    /// « Tu valides la version organisée ? » : Primary = valider, Secondary = retourner en arrière, None = plus tard.
    private static async Task<ContentDialogResult> Question(XamlRoot root, PendingCopy p, int remaining)
    {
        var answer = ContentDialogResult.None;
        var dialog = Dialog(root);
        var lines = new StackPanel { Spacing = 4 };
        lines.Children.Add(Centered(Loc.T("Valider : ton projet d'origine part à la Corbeille et la version organisée prend son nom."), 11.5, Secondary));
        lines.Children.Add(Centered(Loc.T("Retourner en arrière : la version organisée part à la Corbeille et FL rouvre ton projet d'avant."), 11.5, Secondary));
        var back = Soft(Loc.T("Retourner en arrière"), () =>
        {
            answer = ContentDialogResult.Secondary;
            dialog.Hide();
        });
        var yes = Primary(Loc.T("Oui, valider"), () =>
        {
            answer = ContentDialogResult.Primary;
            dialog.Hide();
        });
        var later = new Button { Style = PlainButton, Content = Label(Loc.T("Plus tard"), 12, Link), HorizontalAlignment = HorizontalAlignment.Center };
        later.Click += (_, _) => dialog.Hide();
        AutomationProperties.SetName(later, Loc.T("Plus tard"));
        var parts = new List<UIElement>
        {
            Centered(Loc.F("« %@ » est ton projet « %@ » rangé par l'Organiser.", System.IO.Path.GetFileName(p.Copy), System.IO.Path.GetFileName(p.Original)), 12, Text),
            lines,
        };
        if (remaining > 0) parts.Add(Centered(Loc.F("Encore %lld autre(s) projet(s) ensuite.", remaining), 11.5, Secondary));
        parts.Add(Pair(back, yes));
        parts.Add(later);
        dialog.Content = Message("square.stack.3d.up", Indigo, Loc.T("Tu valides la version organisée ?"), parts.ToArray());
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
