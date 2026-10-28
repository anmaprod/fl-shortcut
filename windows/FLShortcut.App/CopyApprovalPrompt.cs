// « Tu valides la version organisée ? », posée à la réouverture de FL Shortcuts une fois l'Organiser fermé (comme sur le
// Mac, Sources/FLShortcut/OrganizerCopyApproval.swift) : « Oui, valider » (l'original à la Corbeille, la version
// organisée prend son nom, FL la rouvre), « Retourner en arrière » (la version organisée à la Corbeille, FL rouvre le
// projet d'avant), « Plus tard ». Les règles et les fichiers sont ceux du cœur (CopyApproval, testé).
using FLShortcut.App.Services;
using FLShortcut.Core;
using FLShortcut.Core.Organizer;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

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
                var answer = await Question(root, p, approval.Pending.Count - 1).ShowAsync();
                if (answer == ContentDialogResult.None)
                {
                    approval.Snooze();
                    return;
                }
                var keep = answer == ContentDialogResult.Primary;
                var working = new ContentDialog
                {
                    XamlRoot = root,
                    Title = keep ? Loc.T("FL enregistre la version organisée…") : Loc.T("FL rouvre ton projet d'avant…"),
                    Content = new ProgressBar { IsIndeterminate = true, MinWidth = 280 },
                };
                var shown = working.ShowAsync();
                var files = approval.Files;
                var error = await Task.Run(() => keep ? Fl.Validate(p, files) : Fl.GoBack(p, files));
                working.Hide();
                await shown;
                if (error is { } e && e != CopyApprovalError.CopyMissing)
                {
                    var failed = new ContentDialog
                    {
                        XamlRoot = root,
                        Content = new TextBlock { Text = e.Message(), TextWrapping = TextWrapping.Wrap, MaxWidth = 380 },
                        PrimaryButtonText = Loc.T("Réessayer"),
                        CloseButtonText = Loc.T("Plus tard"),
                        DefaultButton = ContentDialogButton.Primary,
                    };
                    if (await failed.ShowAsync() == ContentDialogResult.Primary) continue;
                    approval.Snooze();
                    return;
                }
                // Répondu, ou la version organisée a disparu (plus rien à demander pour elle) : la suivante.
                approval.Done(p);
                approval.Prune();
                if (error is { } gone)
                {
                    await new ContentDialog
                    {
                        XamlRoot = root,
                        Content = new TextBlock { Text = gone.Message(), TextWrapping = TextWrapping.Wrap, MaxWidth = 380 },
                        CloseButtonText = Loc.T("OK"),
                    }.ShowAsync();
                }
            }
        }
        finally
        {
            _showing = false;
        }
    }

    private static ContentDialog Question(XamlRoot root, PendingCopy p, int remaining)
    {
        var body = new StackPanel { Spacing = 8, MaxWidth = 400 };
        void Line(string text, bool secondary = false) => body.Children.Add(new TextBlock
        {
            Text = text, TextWrapping = TextWrapping.Wrap, FontSize = secondary ? 12 : 13,
            Foreground = (Microsoft.UI.Xaml.Media.Brush)Application.Current.Resources[secondary ? "TextFillColorSecondaryBrush" : "TextFillColorPrimaryBrush"],
        });
        Line(Loc.F("« %@ » est ton projet « %@ » rangé par l'Organiser.", System.IO.Path.GetFileName(p.Copy), System.IO.Path.GetFileName(p.Original)));
        Line(Loc.T("Valider : ton projet d'origine part à la Corbeille et la version organisée prend son nom."), true);
        Line(Loc.T("Retourner en arrière : la version organisée part à la Corbeille et FL rouvre ton projet d'avant."), true);
        if (remaining > 0) Line(Loc.F("Encore %lld autre(s) projet(s) ensuite.", remaining), true);
        return new ContentDialog
        {
            XamlRoot = root,
            Title = Loc.T("Tu valides la version organisée ?"),
            Content = body,
            PrimaryButtonText = Loc.T("Oui, valider"),
            SecondaryButtonText = Loc.T("Retourner en arrière"),
            CloseButtonText = Loc.T("Plus tard"),
            DefaultButton = ContentDialogButton.Primary,
        };
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
