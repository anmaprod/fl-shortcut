// Fenêtre de couleur copiée sur le « Color selector » de FL, comme celle du Mac (FLColorSelector.swift ; 09/11,
// « l'Organiser de Windows le même que sur Mac ») : les 10 récentes numérotées 0 à 9 en haut (un clic la pose), la
// roue à 16 secteurs et 5 anneaux, le curseur de luminosité, la couleur, son « #RRGGBB », teinte / saturation /
// luminance (échelle de FL) et rouge / vert / bleu, Reset et Accept. Style suisse, coins carrés. Construite en code.
using FLShortcut.Core;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;
using Windows.System;
using Windows.UI;
using Path = Microsoft.UI.Xaml.Shapes.Path;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal sealed class FlColorSelector
{
    private const double WheelSize = 210;
    private const double SliderHeight = 210;

    private readonly RgbColor _initial;
    private readonly Action<RgbColor> _accept;
    private readonly IReadOnlyList<RgbColor> _recent;
    private readonly Dictionary<(int Ring, int Sector), Path> _cells = new();
    private readonly Ellipse _disc = new() { Stroke = Brush(Color.FromArgb(0x59, 0, 0, 0)), StrokeThickness = 1 };
    private readonly Rectangle _swatch = new() { Width = 84, Height = 40, Stroke = Brush(LineColor), StrokeThickness = 1 };
    private readonly TextBox _hex = Field(84);
    private readonly TextBox _hue = Field(40), _sat = Field(40), _lum = Field(40), _red = Field(40), _green = Field(40), _blue = Field(40);
    private readonly Rectangle _sliderFill = new() { Stroke = Brush(LineColor), StrokeThickness = 1 };
    private readonly Rectangle _thumb = new() { Width = 14, Height = 14, StrokeThickness = 2, VerticalAlignment = VerticalAlignment.Top };
    private readonly List<Button> _slots = new();
    private RgbColor _color;
    private Path? _chosen;

    public UIElement View { get; }

    public FlColorSelector(RgbColor initial, IReadOnlyList<RgbColor> recent, Action<RgbColor> accept)
    {
        _initial = initial;
        _color = initial;
        _recent = recent;
        _accept = accept;
        var stack = new StackPanel { Spacing = 12 };
        stack.Children.Add(Slots());
        var wheelRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        wheelRow.Children.Add(Wheel());
        wheelRow.Children.Add(Slider());
        stack.Children.Add(wheelRow);
        stack.Children.Add(Fields());
        var buttons = new Grid();
        var reset = Soft(Loc.T("Reset"), () => Set(_initial));
        ToolTipService.SetToolTip(reset, Loc.T("Revenir à la couleur de départ"));
        buttons.Children.Add(reset);
        var ok = Primary(Loc.T("Accept"), () => _accept(_color));
        ok.HorizontalAlignment = HorizontalAlignment.Right;
        buttons.Children.Add(ok);
        stack.Children.Add(buttons);
        View = new Border
        {
            Child = stack, Padding = new Thickness(14), Width = 290, Background = Brush(WindowColor),
            RequestedTheme = SurfaceTheme,
        };
        Set(initial);
    }

    /// Cases 0 à 9 : les 10 dernières couleurs posées (0 = la plus récente), comme les cases de FL ; un clic la pose.
    private UIElement Slots()
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
        for (var i = 0; i < 10; i++)
        {
            RgbColor? c = i < _recent.Count ? _recent[i] : null;
            var number = new TextBlock
            {
                Text = i.ToString(System.Globalization.CultureInfo.InvariantCulture), FontSize = 8,
                Foreground = Brush(c is { } k ? (FlHsl.Of(k).Luminance > 140 ? Colors.Black : Colors.White) : Secondary),
                HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom,
                Margin = new Thickness(0, 0, 2, 0), Opacity = 0.8,
            };
            var face = new Grid { Width = 22, Height = 22, Background = Brush(c is { } f ? ColorOf(f) : WindowColor) };
            face.Children.Add(number);
            var slot = new Button
            {
                Style = PlainButton, Content = face, Padding = new Thickness(0), IsEnabled = c is not null,
                BorderBrush = Brush(LineColor), BorderThickness = new Thickness(1), CornerRadius = new CornerRadius(0),
                Tag = c,
            };
            ToolTipService.SetToolTip(slot, c is { } t ? "#" + t.Hex : Loc.T("Case vide"));
            if (c is { } picked) slot.Click += (_, _) => _accept(picked);
            _slots.Add(slot);
            row.Children.Add(slot);
        }
        var block = new StackPanel { Spacing = 6 };
        block.Children.Add(SwissLabel(Loc.T("Récentes"), 9));
        block.Children.Add(row);
        return block;
    }

    /// La roue de FL : un chemin par case ; un clic ou un glisser choisit la case sous la souris.
    private Canvas Wheel()
    {
        var canvas = new Canvas { Width = WheelSize, Height = WheelSize, Background = Brush(Colors.Transparent) };
        var radius = WheelSize / 2;
        var center = new Point(radius, radius);
        var step = 360.0 / FlColorWheel.Sectors;
        for (var ring = FlColorWheel.Edges.Length - 1; ring >= 1; ring--)
        {
            var outer = FlColorWheel.Edges[ring] * radius;
            var inner = FlColorWheel.Edges[ring - 1] * radius;
            for (var k = 0; k < FlColorWheel.Sectors; k++)
            {
                // 0° en haut, sens des aiguilles d'une montre (comme FL) ; y vers le bas à l'écran.
                var a0 = (k * step - step / 2 - 90) * Math.PI / 180;
                var a1 = (k * step + step / 2 - 90) * Math.PI / 180;
                Point At(double r, double a) => new(center.X + r * Math.Cos(a), center.Y + r * Math.Sin(a));
                var figure = new PathFigure { StartPoint = At(outer, a0), IsClosed = true };
                figure.Segments.Add(new ArcSegment { Point = At(outer, a1), Size = new Size(outer, outer), SweepDirection = SweepDirection.Clockwise });
                figure.Segments.Add(new LineSegment { Point = At(inner, a1) });
                figure.Segments.Add(new ArcSegment { Point = At(inner, a0), Size = new Size(inner, inner), SweepDirection = SweepDirection.Counterclockwise });
                var geometry = new PathGeometry();
                geometry.Figures.Add(figure);
                var path = new Path
                {
                    Data = geometry, Fill = Brush(ColorOf(FlColorWheel.Color(ring, k))),
                    Stroke = Brush(Color.FromArgb(0x59, 0, 0, 0)), StrokeThickness = 1,
                };
                _cells[(ring, k)] = path;
                canvas.Children.Add(path);
            }
        }
        var r0 = FlColorWheel.Edges[0] * radius;
        _disc.Width = _disc.Height = 2 * r0;
        Canvas.SetLeft(_disc, center.X - r0);
        Canvas.SetTop(_disc, center.Y - r0);
        canvas.Children.Add(_disc);
        void Pick(PointerRoutedEventArgs e)
        {
            var p = e.GetCurrentPoint(canvas).Position;
            if (FlColorWheel.Hit((p.X - center.X) / radius, (p.Y - center.Y) / radius) is { Ring: > 0 } cell)
                Set(FlColorWheel.Color(cell.Ring, cell.Sector));
        }
        canvas.PointerPressed += (_, e) =>
        {
            canvas.CapturePointer(e.Pointer);
            Pick(e);
        };
        canvas.PointerMoved += (_, e) =>
        {
            if (e.Pointer.IsInContact) Pick(e);
        };
        canvas.PointerReleased += (_, e) => canvas.ReleasePointerCapture(e.Pointer);
        return canvas;
    }

    /// Curseur vertical de luminosité : du blanc (en haut) au noir, en passant par la teinte choisie.
    private Grid Slider()
    {
        var grid = new Grid { Width = 18, Height = SliderHeight, Background = Brush(Colors.Transparent) };
        grid.Children.Add(_sliderFill);
        _thumb.HorizontalAlignment = HorizontalAlignment.Center;
        _thumb.Stroke = Brush(Text);
        grid.Children.Add(_thumb);
        void Pick(PointerRoutedEventArgs e)
        {
            var y = e.GetCurrentPoint(grid).Position.Y;
            var ratio = 1 - Math.Clamp(y / SliderHeight, 0, 1);
            var v = FlHsl.Of(_color);
            Set((v with { Luminance = (int)Math.Round(ratio * FlHsl.Scale) }).ToRgb());
        }
        grid.PointerPressed += (_, e) =>
        {
            grid.CapturePointer(e.Pointer);
            Pick(e);
        };
        grid.PointerMoved += (_, e) =>
        {
            if (e.Pointer.IsInContact) Pick(e);
        };
        grid.PointerReleased += (_, e) => grid.ReleasePointerCapture(e.Pointer);
        return grid;
    }

    /// La couleur, son code, teinte / saturation / luminance et rouge / vert / bleu.
    private UIElement Fields()
    {
        var left = new StackPanel { Spacing = 6 };
        left.Children.Add(_swatch);
        left.Children.Add(_hex);
        ToolTipService.SetToolTip(_hex, Loc.T("Code de la couleur (#RRGGBB), comme dans FL"));
        Commit(_hex, text => RgbColor.FromHex(text) is { } c ? c : null);
        var grid = new Grid { ColumnSpacing = 6, RowSpacing = 4 };
        foreach (var _ in Enumerable.Range(0, 4)) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        foreach (var _ in Enumerable.Range(0, 3)) grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        void Put(UIElement e, int row, int column)
        {
            Grid.SetRow((FrameworkElement)e, row);
            Grid.SetColumn((FrameworkElement)e, column);
            grid.Children.Add(e);
        }
        var rows = new (string Hsl, TextBox HslBox, Func<FlHsl, int, FlHsl> SetHsl, int Max, string Rgb, TextBox RgbBox, Func<RgbColor, byte, RgbColor> SetRgb)[]
        {
            ("Hue", _hue, (v, n) => v with { Hue = n }, 359, "Red", _red, (c, n) => c with { R = n }),
            ("Sat", _sat, (v, n) => v with { Saturation = n }, 240, "Green", _green, (c, n) => c with { G = n }),
            ("Lum", _lum, (v, n) => v with { Luminance = n }, 240, "Blue", _blue, (c, n) => c with { B = n }),
        };
        for (var i = 0; i < rows.Length; i++)
        {
            var r = rows[i];
            Put(SwissLabel(r.Hsl, 9), i, 0);
            Put(r.HslBox, i, 1);
            Put(SwissLabel(r.Rgb, 9), i, 2);
            Put(r.RgbBox, i, 3);
            Commit(r.HslBox, text => int.TryParse(text, out var n) ? r.SetHsl(FlHsl.Of(_color), Math.Clamp(n, 0, r.Max)).ToRgb() : null);
            Commit(r.RgbBox, text => int.TryParse(text, out var n) ? r.SetRgb(_color, (byte)Math.Clamp(n, 0, 255)) : null);
        }
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        row.Children.Add(left);
        row.Children.Add(grid);
        return row;
    }

    private static TextBox Field(double width) => new()
    {
        Width = width, MinWidth = width, Height = 22, MinHeight = 22, Padding = new Thickness(4, 1, 4, 1), FontSize = 11,
        FontFamily = new FontFamily("Consolas"), CornerRadius = new CornerRadius(0), BorderThickness = new Thickness(1),
        BorderBrush = Brush(LineColor), Background = Brush(WindowColor), Foreground = Brush(Text),
    };

    /// Un champ appliqué à Entrée ou à sa sortie ; illisible : la couleur d'avant revient.
    private void Commit(TextBox box, Func<string, RgbColor?> parse)
    {
        void Apply()
        {
            if (parse(box.Text.Trim()) is { } c && c != _color) Set(c);
            else Show();
        }
        box.LostFocus += (_, _) => Apply();
        box.KeyDown += (_, e) =>
        {
            if (e.Key != VirtualKey.Enter) return;
            e.Handled = true;
            Apply();
        };
    }

    private void Set(RgbColor c)
    {
        _color = c;
        Show();
    }

    private void Show()
    {
        var c = _color;
        var v = FlHsl.Of(c);
        _disc.Fill = Brush(ColorOf(c));
        _swatch.Fill = Brush(ColorOf(c));
        _hex.Text = "#" + c.Hex;
        _hue.Text = v.Hue.ToString(System.Globalization.CultureInfo.InvariantCulture);
        _sat.Text = v.Saturation.ToString(System.Globalization.CultureInfo.InvariantCulture);
        _lum.Text = v.Luminance.ToString(System.Globalization.CultureInfo.InvariantCulture);
        _red.Text = c.R.ToString(System.Globalization.CultureInfo.InvariantCulture);
        _green.Text = c.G.ToString(System.Globalization.CultureInfo.InvariantCulture);
        _blue.Text = c.B.ToString(System.Globalization.CultureInfo.InvariantCulture);
        var mid = (v with { Luminance = 120 }).ToRgb();
        var gradient = new LinearGradientBrush { StartPoint = new Point(0, 0), EndPoint = new Point(0, 1) };
        gradient.GradientStops.Add(new GradientStop { Color = Colors.White, Offset = 0 });
        gradient.GradientStops.Add(new GradientStop { Color = ColorOf(mid), Offset = 0.5 });
        gradient.GradientStops.Add(new GradientStop { Color = Colors.Black, Offset = 1 });
        _sliderFill.Fill = gradient;
        _thumb.Fill = Brush(ColorOf(c));
        var y = SliderHeight * (1 - v.Luminance / FlHsl.Scale);
        _thumb.Margin = new Thickness(0, Math.Clamp(y - 7, 0, SliderHeight - 14), 0, 0);
        // La case choisie entourée de blanc, devant ses voisines (comme le Mac : contour égal).
        if (_chosen is not null)
        {
            _chosen.Stroke = Brush(Color.FromArgb(0x59, 0, 0, 0));
            _chosen.StrokeThickness = 1;
            Canvas.SetZIndex(_chosen, 0);
        }
        _chosen = _cells.FirstOrDefault(kv => FlColorWheel.Color(kv.Key.Ring, kv.Key.Sector) == c).Value;
        if (_chosen is not null)
        {
            _chosen.Stroke = Brush(Colors.White);
            _chosen.StrokeThickness = 2;
            Canvas.SetZIndex(_chosen, 1);
        }
        foreach (var slot in _slots)
        {
            var selected = slot.Tag is RgbColor s && s == c;
            slot.BorderBrush = Brush(selected ? Text : LineColor);
            slot.BorderThickness = new Thickness(selected ? 2 : 1);
        }
    }

    private static Color ColorOf(RgbColor c) => Color.FromArgb(0xFF, c.R, c.G, c.B);
}
