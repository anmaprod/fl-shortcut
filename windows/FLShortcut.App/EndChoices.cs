// Pièces de la fin de l'Organiser et de la question « tu gardes la version rangée » (13/11, maquette validée, comme le
// Mac : OrganizerWindow.swift FinishStat/EndChoice/EndRow, OrganizerCopyApproval.swift KeepChoice) : grandes cases
// soulevées au survol (effet Gumroad), mini Playlist rangée aux couleurs des familles ou grise en désordre, chiffres,
// lignes à flèche.
using System.Globalization;
using FLShortcut.Core;
using FLShortcut.Core.Organizer;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using static FLShortcut.App.MacLook;
using Color = Windows.UI.Color;

namespace FLShortcut.App;

internal static class EndChoices
{
    private static SolidColorBrush Of(RgbColor c) => new(Color.FromArgb(0xFF, c.R, c.G, c.B));

    /// Grande case : GARDER pleine, REVENIR COMME AVANT bordée ; `art` au-dessus du titre (mini Playlist) ou rien
    /// (titre au milieu). Soulevée sur son ombre nette au survol.
    public static Grid Tile(string title, bool primary, Action click, double height, UIElement? art = null)
    {
        var label = Label(title.ToUpper(CultureInfo.CurrentCulture), art is null ? 13 : 15, primary ? PrimaryInk : Text, bold: true);
        label.CharacterSpacing = 100;
        label.TextWrapping = TextWrapping.Wrap;
        var inside = new Grid { Padding = new Thickness(art is null ? 12 : 16) };
        if (art is null)
        {
            label.HorizontalAlignment = HorizontalAlignment.Center;
            label.VerticalAlignment = VerticalAlignment.Center;
            label.TextAlignment = TextAlignment.Center;
            inside.Children.Add(label);
        }
        else
        {
            inside.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
            inside.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            inside.Children.Add(art);
            Grid.SetRow(label, 1);
            inside.Children.Add(label);
        }
        var face = new Border
        {
            Child = inside,
            Background = Brush(primary ? PrimaryFill : WindowColor),
            BorderBrush = Brush(primary ? Colors.Transparent : Text),
            BorderThickness = new Thickness(primary ? 0 : 2),
        };
        var button = new Button
        {
            Style = PlainButton,
            Content = face,
            Padding = new Thickness(0),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            VerticalContentAlignment = VerticalAlignment.Stretch,
        };
        button.Click += (_, _) => click();
        AutomationProperties.SetName(button, title);
        var shadow = LiftShadow(primary ? LiftColor : Text);
        var tile = new Grid { Height = height };
        tile.Children.Add(shadow);
        tile.Children.Add(button);
        button.PointerEntered += (_, _) => SetLift(button, shadow, true);
        button.PointerExited += (_, _) => SetLift(button, shadow, false);
        return tile;
    }

    /// Mini Playlist : rangée (une ligne par famille, ses clips à la couleur choisie pour elle, alignés) ou grise en
    /// désordre (la Playlist d'avant).
    public static StackPanel MiniPlaylist(bool tidy, IReadOnlyDictionary<SoundFamily, FamilyStyle> styles)
    {
        var rows = new StackPanel { Spacing = 5 };
        if (tidy)
        {
            var families = new[] { SoundFamily.Vocals, SoundFamily.Melody, SoundFamily.Bass, SoundFamily.Drums, SoundFamily.Fx };
            var clips = new[]
            {
                new[] { (0.0, 0.30), (0.50, 0.30) }, new[] { (0.0, 0.62), (0.66, 0.34) }, new[] { (0.0, 0.48), (0.50, 0.48) },
                new[] { (0.0, 1.0) }, new[] { (0.34, 0.14), (0.84, 0.14) },
            };
            for (var i = 0; i < families.Length; i++)
            {
                var style = styles.TryGetValue(families[i], out var s) ? s
                    : FamilyStyles.Initial.TryGetValue(families[i], out var first) ? first : null;
                var color = style is null ? new SolidColorBrush(Color.FromArgb(0xFF, 128, 128, 128)) : Of(style.Color);
                var line = new Grid { ColumnSpacing = 6, Height = 16 };
                line.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(10) });
                line.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                line.Children.Add(new Rectangle { Width = 10, Height = 10, Fill = color, VerticalAlignment = VerticalAlignment.Center });
                var lane = Lane(clips[i], color, Color.FromArgb(0xFF, 0xEE, 0xEE, 0xEE));
                Grid.SetColumn(lane, 1);
                line.Children.Add(lane);
                rows.Children.Add(line);
            }
            return rows;
        }
        var dark = new SolidColorBrush(Color.FromArgb(0xFF, 0x5A, 0x5A, 0x5A));
        var light = new SolidColorBrush(Color.FromArgb(0xFF, 0x8C, 0x8C, 0x8C));
        var messy = new (SolidColorBrush Color, (double, double)[] Clips)[]
        {
            (dark, new[] { (0.06, 0.22) }), (light, new[] { (0.30, 0.44) }), (dark, new[] { (0.0, 0.16), (0.40, 0.12) }),
            (dark, new[] { (0.18, 0.60) }), (light, new[] { (0.50, 0.18) }), (dark, new[] { (0.64, 0.34) }),
        };
        foreach (var (color, parts) in messy)
        {
            var lane = Lane(parts, color, null);
            lane.Height = 16;
            rows.Children.Add(lane);
        }
        return rows;
    }

    /// Une ligne de clips : colonnes proportionnelles (vide, clip, vide…), le fond `back` s'il y en a un.
    private static Grid Lane((double Start, double Width)[] clips, Brush color, Color? back)
    {
        var lane = new Grid { Height = 10, VerticalAlignment = VerticalAlignment.Center };
        if (back is { } b) lane.Background = new SolidColorBrush(b);
        var at = 0.0;
        void Column(double width, bool clip)
        {
            if (width <= 0.0001) return;
            lane.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(width, GridUnitType.Star) });
            if (!clip) return;
            var r = new Rectangle { Fill = color };
            Grid.SetColumn(r, lane.ColumnDefinitions.Count - 1);
            lane.Children.Add(r);
        }
        foreach (var (start, width) in clips.OrderBy(c => c.Start))
        {
            Column(start - at, false);
            Column(width, true);
            at = start + width;
        }
        Column(1 - at, false);
        return lane;
    }

    /// Un chiffre de la fin : grand nombre, petites capitales grises dessous, trait fin à gauche (sauf le premier).
    public static Border Stat(int value, string label, bool first)
    {
        var stack = new StackPanel { Spacing = 4 };
        stack.Children.Add(Label(value.ToString(CultureInfo.CurrentCulture), 30, Text, bold: true));
        var caption = SwissLabel(label, 10.5, Secondary);
        caption.TextWrapping = TextWrapping.Wrap;
        stack.Children.Add(caption);
        return new Border
        {
            Child = stack,
            Padding = new Thickness(first ? 0 : 14, 0, 0, 14),
            BorderBrush = Brush(LineColor),
            BorderThickness = new Thickness(first ? 0 : 1, 0, 0, 0),
        };
    }

    /// Une ligne de la fin (« Pas content ? », « Décider plus tard ») : le texte, une flèche à droite, un trait dessous.
    public static Button Row(string title, bool bold, Action click)
    {
        var grid = new Grid { MinHeight = 44 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var text = Label(title, 14, Text, bold: bold);
        text.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(text);
        var arrow = Label("→", 14, Secondary);
        arrow.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(arrow, 1);
        grid.Children.Add(arrow);
        var face = new Border { Child = grid, BorderBrush = Brush(LineColor), BorderThickness = new Thickness(0, 0, 0, 1) };
        var button = new Button
        {
            Style = PlainButton,
            Content = face,
            Padding = new Thickness(0),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
        };
        button.Click += (_, _) => click();
        button.PointerEntered += (_, _) => arrow.Foreground = Brush(Text);
        button.PointerExited += (_, _) => arrow.Foreground = Brush(Secondary);
        AutomationProperties.SetName(button, title);
        return button;
    }
}
