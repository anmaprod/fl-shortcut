// Icônes de FL dans l'Organiser (14/11, « fais les icones pour win », comme FLIconPicker.swift du Mac) : la case de
// l'en-tête d'une famille et la grille pour la choisir, à la même place que dans la fenêtre « Change icon… » de FL.
// Les images sont celles du Mac (Resources/FLIcons.png embarquée, cases de 88 pixels), blanches : chacune est posée sur
// une case noire, lisible dans les trois thèmes, comme dans FL. L'icône choisie est écrite dans la copie rangée
// (FlIconIds, FlpIcons) : sur les sons, les pistes du Mixer et de la Playlist de la famille.
using FLShortcut.Core;
using FLShortcut.Core.Organizer;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Shapes;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal static class FlIconPicker
{
    private const double Side = 26;
    private const double Gap = 2;
    private static BitmapImage? _sheet;
    private static bool _sheetTried;

    /// La planche des icônes de FL, lue une seule fois ; null si elle manque.
    private static BitmapImage? Sheet()
    {
        if (_sheetTried) return _sheet;
        _sheetTried = true;
        try
        {
            using var stream = typeof(FlIconPicker).Assembly.GetManifestResourceStream("FLIcons.png");
            if (stream is null) return null;
            var memory = new MemoryStream();
            stream.CopyTo(memory);
            memory.Position = 0;
            var bitmap = new BitmapImage();
            bitmap.SetSource(memory.AsRandomAccessStream());
            return _sheet = bitmap;
        }
        catch (Exception)
        {
            return null;
        }
    }

    /// L'icône de cette case à `size` points : la planche entière, décalée dans un cadre qui ne montre que la case.
    private static FrameworkElement Glyph(FlIcon icon, double size)
    {
        var canvas = new Canvas { Width = size, Height = size, IsHitTestVisible = false };
        if (Sheet() is { } sheet)
        {
            var picture = new Image { Source = sheet, Width = FlIconGrid.Columns * size, Stretch = Stretch.Uniform };
            Canvas.SetLeft(picture, -icon.Column * size);
            Canvas.SetTop(picture, -icon.Row * size);
            canvas.Children.Add(picture);
        }
        canvas.Clip = new RectangleGeometry { Rect = new Windows.Foundation.Rect(0, 0, size, size) };
        return canvas;
    }

    /// La case de l'en-tête d'une famille : son icône sur fond noir, ou un carré pointillé (aucune icône).
    public static Border Badge(FlIcon? icon, double size)
    {
        var badge = new Border
        {
            Width = size, Height = size, Background = Brush(Colors.Black), BorderBrush = Brush(LineColor),
            BorderThickness = new Thickness(1), VerticalAlignment = VerticalAlignment.Center,
        };
        if (icon is { } i && FlIconGrid.IsPickable(i))
        {
            var glyph = Glyph(i, Math.Round(size * 0.72));
            glyph.HorizontalAlignment = HorizontalAlignment.Center;
            glyph.VerticalAlignment = VerticalAlignment.Center;
            badge.Child = glyph;
        }
        else
        {
            badge.Background = Brush(WindowColor);
            badge.BorderThickness = new Thickness(0);
            badge.Child = new Rectangle
            {
                Stroke = Brush(Secondary), StrokeThickness = 1, StrokeDashArray = new DoubleCollection { 2, 2 },
                Margin = new Thickness(size * 0.18),
            };
        }
        return badge;
    }

    /// La grille : « Icône de FL » et « Aucune » en haut, les titres de FL, puis les cases (ni Reset ni Channel), la
    /// choisie bordée de rouge, son nom anglais de FL en bulle.
    public static StackPanel Picker(FlIcon? selected, Action<FlIcon?> pick)
    {
        var panel = new StackPanel { Spacing = 8, Padding = new Thickness(12) };
        var top = new Grid();
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        top.Children.Add(Label(Loc.T("Icône de FL"), 13, Text, bold: true));
        var none = Soft(Loc.T("Aucune"), () => pick(null));
        ToolTipService.SetToolTip(none, Loc.T("Pas d'icône"));
        Grid.SetColumn(none, 1);
        top.Children.Add(none);
        panel.Children.Add(top);

        var titles = new StackPanel { Orientation = Orientation.Horizontal, Spacing = Gap };
        foreach (var (_, title, span) in FlIconGrid.Headers())
        {
            var label = Label(title, 9, Secondary);
            label.Width = span * Side + (span - 1) * Gap;
            label.TextAlignment = TextAlignment.Center;
            titles.Children.Add(label);
        }
        panel.Children.Add(titles);

        var columns = new StackPanel { Orientation = Orientation.Horizontal, Spacing = Gap };
        for (var column = 1; column < FlIconGrid.ChannelColumn; column++)
        {
            var cells = new StackPanel { Spacing = Gap };
            for (var row = 0; row < FlIconGrid.Rows; row++)
            {
                if (FlIcon.Make(column, row) is not { } icon || FlIconGrid.Name(icon) is not { } name)
                {
                    // Case vide dans FL : rien à choisir.
                    cells.Children.Add(new Rectangle { Width = Side, Height = Side, Fill = Brush(White(0.02)) });
                    continue;
                }
                var chosen = icon == selected;
                var glyph = Glyph(icon, 18);
                glyph.HorizontalAlignment = HorizontalAlignment.Center;
                glyph.VerticalAlignment = VerticalAlignment.Center;
                var face = new Border
                {
                    Width = Side, Height = Side, Child = glyph,
                    Background = Brush(chosen ? BrandRed : Colors.Black),
                    BorderBrush = Brush(chosen ? BrandRed : Colors.Transparent), BorderThickness = new Thickness(1.5),
                };
                var button = new Button { Style = PlainButton, Content = face, Padding = new Thickness(0) };
                var picked = icon;
                button.Click += (_, _) => pick(picked);
                button.PointerEntered += (_, _) => { if (!chosen) face.BorderBrush = Brush(Text); };
                button.PointerExited += (_, _) => { if (!chosen) face.BorderBrush = Brush(Colors.Transparent); };
                ToolTipService.SetToolTip(button, name);
                AutomationProperties.SetName(button, name);
                cells.Children.Add(button);
            }
            columns.Children.Add(cells);
        }
        panel.Children.Add(columns);
        var note = Paragraph(Loc.T("Même place que dans la grille « Change icon… » de FL."), 11);
        note.MaxWidth = (FlIconGrid.ChannelColumn - 1) * (Side + Gap);
        panel.Children.Add(note);
        return panel;
    }
}
