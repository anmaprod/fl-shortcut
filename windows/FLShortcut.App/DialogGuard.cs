// Boîtes de l'app (ContentDialog) ouvertes sans risque (16/11, « j'essaye de changer un raccourci ça crash ») : WinUI
// refuse une deuxième boîte tant qu'une autre est ouverte (« Only a single ContentDialog can be open at any time ») ;
// levée dans une méthode async void, l'erreur fermait l'appli. Une boîte demandée pendant qu'une autre est ouverte n'est
// pas montrée (réponse « aucune »), et une erreur de WinUI est notée au journal (son nom seulement) au lieu de tout
// fermer. Le Mac n'a pas ce problème (une seule fiche à la fois par SwiftUI).
using FLShortcut.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal static class DialogGuard
{
    /// Une boîte de l'appli est déjà ouverte dans cette fenêtre.
    public static bool AnyOpen(XamlRoot? root)
    {
        if (root is null) return false;
        try { return VisualTreeHelper.GetOpenPopupsForXamlRoot(root).Any(p => p.Child is ContentDialog); }
        catch (Exception) { return false; }
    }

    /// `ShowAsync`, mais jamais deux boîtes à la fois ni d'erreur qui ferme l'appli.
    public static async Task<ContentDialogResult> ShowSafeAsync(this ContentDialog dialog)
    {
        if (AnyOpen(dialog.XamlRoot)) return ContentDialogResult.None;
        try
        {
            return await dialog.ShowAsync();
        }
        catch (Exception e) when (e is System.Runtime.InteropServices.COMException or InvalidOperationException
                                       or ArgumentException)
        {
            AppLog.Write("DIALOG", "boîte non montrée (" + e.GetType().Name + ")");
            return ContentDialogResult.None;
        }
    }
}

/// Question au style suisse, la même que `SwissDialog` du Mac (16/11, « c'est pas du tout le même que sur mac ») : un
/// panneau aux coins carrés bordé d'un trait fin, le titre en gras souligné d'un trait d'encre, le texte en gris, les
/// boutons rectangulaires séparés à droite : le premier (principal, Entrée) tout à droite, le dernier annule (Échap) ;
/// une action qui efface est rouge et n'est jamais le choix d'Entrée. Plus de boîte de Windows à barre grise.
internal static class SwissQuestion
{
    /// L'indice du bouton choisi ; le dernier (Annuler) si la question est fermée autrement.
    public static async Task<int> AskAsync(XamlRoot root, string title, string text, IReadOnlyList<string> buttons,
                                           int? destructive = null)
    {
        IReadOnlyList<string> names = buttons.Count == 0 ? new[] { Loc.T("OK") } : buttons;
        var cancel = names.Count - 1;
        var answer = cancel;
        var dialog = SwissPanel(root);
        var body = new StackPanel { Spacing = 14, Width = 412 };
        var heading = Label(title, 22, Text, bold: true);
        heading.TextWrapping = TextWrapping.Wrap;
        heading.CharacterSpacing = -40;
        body.Children.Add(heading);
        body.Children.Add(Rule(Text));
        if (text.Length > 0) body.Children.Add(Paragraph(text, 13, Secondary));
        var row = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 10,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 8, 0, 0),
        };
        for (var i = names.Count - 1; i >= 0; i--)
        {
            var index = i;
            void Pick()
            {
                answer = index;
                dialog.Hide();
            }
            row.Children.Add(index == destructive ? Danger(names[index], Pick)
                             : index == 0 ? Primary(names[index], Pick)
                             : Soft(names[index], Pick));
        }
        body.Children.Add(row);
        dialog.Content = body;
        dialog.PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Windows.System.VirtualKey.Escape)
            {
                answer = cancel;
                dialog.Hide();
                e.Handled = true;
            }
            else if (e.Key == Windows.System.VirtualKey.Enter && destructive != 0)
            {
                answer = 0;
                dialog.Hide();
                e.Handled = true;
            }
        };
        await dialog.ShowSafeAsync();
        return answer;
    }

    /// Le panneau d'une question ou d'une fiche : fond du thème, coins carrés, trait fin tout autour, aucun bouton de
    /// Windows (les boutons suisses sont dans le contenu).
    public static ContentDialog SwissPanel(XamlRoot root) => new()
    {
        XamlRoot = root,
        Style = MainShell.DialogStyle(),
        RequestedTheme = SurfaceTheme,
        Background = Brush(WindowColor),
        BorderBrush = Brush(LineColor),
        BorderThickness = new Thickness(1),
        CornerRadius = new CornerRadius(0),
    };
}
