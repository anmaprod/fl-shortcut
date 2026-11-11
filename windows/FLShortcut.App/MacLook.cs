// Aspect du Mac sur Windows, au style suisse du Mac (validé le 01/11, porté le 03/11 : « le logiciel n'est pas le même
// que la dernière version du mac ») : fond noir, texte blanc, Helvetica (Arial sous Windows), traits fins #333/#222,
// coins carrés partout, petits carrés de couleur à la place des tuiles, libellés en petites capitales espacées,
// boutons rectangulaires en capitales, survol = blanc plein et texte noir, rouge #FF3B1F seulement pour ce qui compte.
// Mêmes valeurs que `Swiss` dans Sources/FLShortcut/GlassStyle.swift. Tout est construit en code : rien ne dépend du
// thème clair ou sombre de Windows.
using System.Globalization;
using FLShortcut.Core;
using Microsoft.UI;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;

namespace FLShortcut.App;

internal static class MacLook
{
    // ---------- Couleurs (thèmes du 04/11 : Noir, Papier, Orange ; mêmes valeurs que le Mac) ----------

    /// Thème de l'app, pris au lancement (settings.json, « Theme ») : un changement relance l'app (AccountPage).
    public static AppTheme Theme { get; set; } = AppTheme.Noir;
    private static int _inverted;

    /// Partie noire sous Orange (barre de gauche) : ce qui est construit pendant ce temps prend les couleurs inversées.
    public static IDisposable Inverted()
    {
        _inverted++;
        return new Scope();
    }

    private sealed class Scope : IDisposable
    {
        private bool _done;
        public void Dispose()
        {
            if (_done) return;
            _done = true;
            _inverted--;
        }
    }

    private static ThemePalette P => ThemePalette.Of(Theme, inverse: _inverted > 0);
    private static Color C(uint rgb) => Rgb((byte)(rgb >> 16), (byte)(rgb >> 8), (byte)rgb);

    /// Partie sombre (Noir, ou barre de gauche sous Orange) : contrôles de WinUI en thème sombre, sinon clair.
    public static bool DarkSurface => P.Background == 0x000000;
    public static ElementTheme SurfaceTheme => DarkSurface ? ElementTheme.Dark : ElementTheme.Light;

    /// Fond (noir sous Noir).
    public static Color WindowColor => C(P.Background);
    /// Style suisse : plus de bleu ; ce qui était l'accent (choisi, interrupteur allumé, repère) est l'encre.
    public static Color Accent => C(P.Text);
    /// Liens : de l'encre (soulignés là où ils sont posés).
    public static Color Link => C(P.Text);
    /// Bleu des repères (Mixer, « Modifier les raccourcis ») : les petits carrés gardent leurs couleurs du Mac.
    public static readonly Color Blue = Rgb(0x0A, 0x84, 0xFF);
    public static readonly Color Orange = Rgb(0xFF, 0x9F, 0x0A);
    /// Ce qui compte : touche changée, avertissement, Désinstaller (#FF3B1F ; blanc sur le fond orange).
    public static Color Red => C(P.Red);
    /// Le rouge de la marque, le même dans tous les thèmes (logo).
    public static readonly Color BrandRed = Rgb(0xFF, 0x3B, 0x1F);
    /// Texte posé sur un fond `Red` (pastilles numérotées).
    public static Color OnRed => P.Red == ThemePalette.BrandRed ? Colors.White : C(P.Background);
    public static readonly Color Green = Rgb(0x30, 0xD1, 0x58);
    public static readonly Color Gray = Rgb(0x8E, 0x8E, 0x93);
    public static readonly Color Purple = Rgb(0xBF, 0x5A, 0xF2);
    public static readonly Color Pink = Rgb(0xFF, 0x37, 0x5F);
    public static readonly Color Teal = Rgb(0x40, 0xC8, 0xE0);
    public static readonly Color Indigo = Rgb(0x5E, 0x5C, 0xE6);
    /// Encre (blanc sous Noir).
    public static Color Text => C(P.Text);
    /// Texte secondaire (#8A8A8A) et effacé (#555555), valeurs sous Noir.
    public static Color Secondary => C(P.Gray);
    public static Color Tertiary => C(P.KeyLine);
    /// Traits : entre deux blocs (#333333), entre deux lignes (#222222), valeurs sous Noir.
    public static Color LineColor => C(P.Line);
    public static Color Faint => C(P.Faint);
    /// Cadre d'une touche (#DDDDDD sous Noir).
    public static Color KeyFrame => C(P.KeyFrame);

    private static FontFamily? _font;
    /// Helvetica comme le Mac ; Arial (même dessin) sur un PC qui ne l'a pas.
    public static FontFamily SwissFont => _font ??= new FontFamily("Helvetica Neue, Helvetica, Arial");

    public static Color Rgb(byte r, byte g, byte b) => Color.FromArgb(255, r, g, b);
    /// L'encre du thème, transparente (voiles, traits, survols discrets) : blanche sous Noir, noire sous Papier.
    public static Color White(double opacity) => WithOpacity(Text, opacity);
    public static Color WithOpacity(Color c, double opacity) => Color.FromArgb((byte)Math.Round(opacity * 255), c.R, c.G, c.B);
    public static SolidColorBrush Brush(Color c) => new(c);

    /// Couleur d'une page de FL (icône, survol), comme le Mac.
    public static Color Tint(FlSection s) => s switch
    {
        FlSection.Transport => Red,
        FlSection.Patterns => Orange,
        FlSection.Playlist => Green,
        FlSection.PianoRoll => Purple,
        FlSection.ChannelRack => Teal,
        FlSection.Mixer => Blue,
        FlSection.Browser => Indigo,
        _ => Gray,
    };

    /// Dessin de l'icône d'une page (mêmes dessins que le Mac et le tuto).
    public static string IconName(FlSection s) => s switch
    {
        FlSection.Transport => "transport",
        FlSection.Patterns => "patterns",
        FlSection.Playlist => "playlist",
        FlSection.PianoRoll => "pianoroll",
        FlSection.ChannelRack => "channelrack",
        FlSection.Mixer => "mixer",
        FlSection.Browser => "browser",
        _ => "general",
    };

    internal static Color Mix(Color a, Color b, double t) => Color.FromArgb(255,
        (byte)Math.Round(a.R + (b.R - a.R) * t), (byte)Math.Round(a.G + (b.G - a.G) * t), (byte)Math.Round(a.B + (b.B - a.B) * t));

    public static LinearGradientBrush Gradient(Color top, Color bottom, double end = 1)
    {
        var brush = new LinearGradientBrush { StartPoint = new Windows.Foundation.Point(0, 0), EndPoint = new Windows.Foundation.Point(0, end) };
        brush.GradientStops.Add(new GradientStop { Color = top, Offset = 0 });
        brush.GradientStops.Add(new GradientStop { Color = bottom, Offset = 1 });
        return brush;
    }

    // ---------- Plaques et textes ----------

    /// Plaque claire des maquettes : dégradé blanc (plus clair en haut), bord fin un peu plus clair en haut.
    /// Bloc (style suisse) : noir, cadre fin #333, coins carrés (`radius` et les dégradés d'avant ne servent plus).
    public static Border Plate(UIElement? child, double radius, double top = 0.10, double bottom = 0.045, double border = 0.15) => new()
    {
        Background = Brush(WindowColor),
        BorderBrush = Brush(LineColor),
        BorderThickness = new Thickness(1),
        Child = child,
    };

    /// Libellé en petites capitales espacées (« MES MACROS », « PROJET »), gris par défaut (swissLabel du Mac).
    public static TextBlock SwissLabel(string text, double size = 11, Color? color = null)
    {
        var label = Label(text.ToUpper(CultureInfo.CurrentCulture), size, color ?? Secondary, bold: true);
        label.CharacterSpacing = 110;
        return label;
    }

    /// Gros titre de page (46, gras, serré) comme swissTitle du Mac.
    public static TextBlock SwissTitle(double size = 46)
    {
        var title = Label("", size, Text, bold: true);
        title.CharacterSpacing = -39;
        return title;
    }

    /// Grand titre suivi de son point carré, rouge (blanc sous Orange), posé sur la ligne du texte (SwissPageTitle du
    /// Mac, maquette du 05/11). Le texte se met en minuscules à l'appelant.
    public static StackPanel PageTitle(TextBlock title, double size)
    {
        var side = Math.Round(size * 0.19);
        var dot = new Rectangle
        {
            Width = side,
            Height = side,
            Fill = Brush(Red),
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(size * 0.09, 0, 0, Math.Round(size * 0.24)),
        };
        AutomationProperties.SetAccessibilityView(dot, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        title.VerticalAlignment = VerticalAlignment.Bottom;
        return new StackPanel
        {
            Orientation = Orientation.Horizontal,
            VerticalAlignment = VerticalAlignment.Bottom,
            Children = { title, dot },
        };
    }

    /// Trait d'un point : blanc sous un titre, #333 entre deux blocs, #222 entre deux lignes (swissRule du Mac).
    public static Rectangle Rule(Color color) => new() { Height = 1, Fill = Brush(color), IsHitTestVisible = false };

    public static TextBlock Label(string text, double size = 13, Color? color = null, bool bold = false, bool semibold = false)
    {
        var label = new TextBlock
        {
            Text = text,
            FontSize = size,
            FontWeight = bold ? FontWeights.Bold : semibold ? FontWeights.SemiBold : FontWeights.Normal,
            FontFamily = SwissFont,
            TextTrimming = TextTrimming.CharacterEllipsis,
            VerticalAlignment = VerticalAlignment.Center,
        };
        if (color is { } c) label.Foreground = Brush(c);
        return label;
    }

    /// Texte qui revient à la ligne (phrases, avertissements).
    public static TextBlock Paragraph(string text, double size = 12, Color? color = null) => new()
    {
        Text = text,
        FontSize = size,
        FontFamily = SwissFont,
        Foreground = Brush(color ?? Secondary),
        TextWrapping = TextWrapping.Wrap,
    };

    // ---------- Icônes dessinées (16 × 16) ----------

    private sealed record Part(string Data, bool Fill = true, double Stroke = 0, bool Hole = false);

    private static string N(double v) => v.ToString("0.###", CultureInfo.InvariantCulture);

    private static string Circle(double cx, double cy, double r) =>
        $"M{N(cx - r)},{N(cy)} A{N(r)},{N(r)} 0 1 0 {N(cx + r)},{N(cy)} A{N(r)},{N(r)} 0 1 0 {N(cx - r)},{N(cy)} Z";

    private static string Rect(double x, double y, double w, double h, double r) =>
        $"M{N(x + r)},{N(y)} H{N(x + w - r)} A{N(r)},{N(r)} 0 0 1 {N(x + w)},{N(y + r)} V{N(y + h - r)} " +
        $"A{N(r)},{N(r)} 0 0 1 {N(x + w - r)},{N(y + h)} H{N(x + r)} A{N(r)},{N(r)} 0 0 1 {N(x)},{N(y + h - r)} " +
        $"V{N(y + r)} A{N(r)},{N(r)} 0 0 1 {N(x + r)},{N(y)} Z";

    /// Étincelle à quatre branches (baguette des macros).
    private static string Sparkle(double cx, double cy, double r)
    {
        var k = r * 0.28;
        return $"M{N(cx)},{N(cy - r)} L{N(cx + k)},{N(cy - k)} L{N(cx + r)},{N(cy)} L{N(cx + k)},{N(cy + k)} " +
               $"L{N(cx)},{N(cy + r)} L{N(cx - k)},{N(cy + k)} L{N(cx - r)},{N(cy)} L{N(cx - k)},{N(cy - k)} Z";
    }

    private static Part[] Parts(string icon) => icon switch
    {
        "general" => new[] { new Part(Rect(2, 2, 5.2, 5.2, 1.3)), new Part(Rect(8.8, 2, 5.2, 5.2, 1.3)),
                             new Part(Rect(2, 8.8, 5.2, 5.2, 1.3)), new Part(Rect(8.8, 8.8, 5.2, 5.2, 1.3)) },
        "transport" => new[] { new Part(Circle(8, 8, 6.2)), new Part(Circle(8, 8, 3), Hole: true) },
        "patterns" => new[] { new Part(Rect(2.5, 6, 11, 8.5, 1.6)), new Part(Rect(4, 3.6, 8, 1.5, 0.75)),
                              new Part(Rect(5.5, 1.4, 5, 1.4, 0.7)) },
        "playlist" => new[] { new Part(Rect(1.8, 3, 3.6, 10, 1)), new Part(Rect(6.2, 3, 3.6, 10, 1)),
                              new Part(Rect(10.6, 3, 3.6, 10, 1)) },
        "pianoroll" => new[] { new Part(Rect(1.8, 2.5, 12.4, 11, 1.6)), new Part("M5.9,9 V13.5 M10.1,9 V13.5", false, 1, true),
                               new Part("M4.7,2.5 H7.1 V9 H4.7 Z", Hole: true), new Part("M8.9,2.5 H11.3 V9 H8.9 Z", Hole: true) },
        "channelrack" => new[] { new Part("M8,1.6 L14.2,4.9 L8,8.2 L1.8,4.9 Z"),
                                 new Part("M1.8,8 L8,11.3 L14.2,8", false, 1.6), new Part("M1.8,11.1 L8,14.4 L14.2,11.1", false, 1.6) },
        "mixer" => new[] { new Part("M4,2 V14 M8,2 V14 M12,2 V14", false, 1.3), new Part(Rect(2.4, 8.5, 3.2, 2.4, 1)),
                           new Part(Rect(6.4, 4, 3.2, 2.4, 1)), new Part(Rect(10.4, 9.6, 3.2, 2.4, 1)) },
        "browser" => new[] { new Part("M1.6,4.4 C1.6,3.7 2.1,3.2 2.8,3.2 H6.2 L7.7,4.8 H13.2 C13.9,4.8 14.4,5.3 14.4,6 V12.2 " +
                                      "C14.4,12.9 13.9,13.4 13.2,13.4 H2.8 C2.1,13.4 1.6,12.9 1.6,12.2 Z") },
        "macros" => new[] { new Part("M2.3,13.7 L9.7,6.3", false, 2), new Part(Sparkle(11.5, 4, 2.5)),
                            new Part(Sparkle(5.2, 3.3, 1.55)), new Part(Sparkle(12.8, 10.2, 1.55)) },
        "custom" => new[] { new Part("M8,1.6 L9.95,5.6 L14.35,6.2 L11.15,9.3 L11.95,13.7 L8,11.6 L4.05,13.7 L4.85,9.3 " +
                                     "L1.65,6.2 L6.05,5.6 Z") },
        // Étoile creuse (« star » du Mac) : la page vide de « Mes raccourcis ».
        "star" => new[] { new Part("M8,1.6 L9.95,5.6 L14.35,6.2 L11.15,9.3 L11.95,13.7 L8,11.6 L4.05,13.7 L4.85,9.3 " +
                                   "L1.65,6.2 L6.05,5.6 Z", false, 0.9) },
        "community" => new[] { new Part(Circle(5.6, 5, 2.4)), new Part(Circle(11, 5.6, 2)),
                               new Part("M1.2,13.2 C1.2,10.6 3.2,9 5.6,9 C8,9 10,10.6 10,13.2 Z"),
                               new Part("M10.6,13.2 C10.6,11.7 10.1,10.5 9.2,9.6 C9.7,9.4 10.3,9.3 11,9.3 C13.1,9.3 14.8,10.7 14.8,13.2 Z") },
        "organize" => new[] { new Part(Rect(2, 2.5, 12, 3, 1)), new Part(Rect(2, 6.5, 12, 3, 1)), new Part(Rect(2, 10.5, 12, 3, 1)) },
        "link" => new[] { new Part("M6.6,9.4 L9.4,6.6", false, 1.6),
                          new Part("M7.4,4.6 L8.6,3.4 C9.9,2.1 12,2.1 13.3,3.4 C14.6,4.7 14.6,6.8 13.3,8.1 L12.1,9.3", false, 1.6),
                          new Part("M8.6,11.4 L7.4,12.6 C6.1,13.9 4,13.9 2.7,12.6 C1.4,11.3 1.4,9.2 2.7,7.9 L3.9,6.7", false, 1.6) },
        "search" => new[] { new Part(Circle(6.8, 6.8, 4.6), false, 1.6), new Part("M10.3,10.3 L14.2,14.2", false, 1.6) },
        "keyboard" => new[] { new Part(Rect(0.8, 3.2, 14.4, 9.6, 2), false, 1.1),
                              new Part("M3.6,6.2 H4.4 M6.6,6.2 H7.4 M9.6,6.2 H10.4 M12.4,6.2 H12.6 M3.6,8.4 H4.4 M6.6,8.4 H7.4 " +
                                       "M9.6,8.4 H10.4 M12.4,8.4 H12.6 M5,10.6 H11", false, 1.2) },
        "plus" => new[] { new Part("M8,3 V13 M3,8 H13", false, 1.8) },
        "back" => new[] { new Part("M10,3 L5,8 L10,13", false, 2) },
        "reset" => new[] { new Part("M4,4.6 A5,5 0 1 1 3,9.2", false, 1.6), new Part("M4.6,1.8 L4,4.6 L6.8,5.2", false, 1.6) },
        // Avertissement suisse (08/11 : « pas un logo, un emoji d'attention… un point orange ») : un carré plein.
        "warning" => new[] { new Part(Rect(4.5, 4.5, 7, 7, 0)) },
        "trash" => new[] { new Part("M2.5,4.2 H13.5 M6,4.2 V2.6 H10 V4.2", false, 1.3),
                           new Part("M3.8,4.2 L4.6,14 H11.4 L12.2,4.2", false, 1.3) },
        "check" => new[] { new Part("M3,8.4 L6.6,12 L13,4.4", false, 2) },
        // Blocs des macros et modèles (noms des symboles du Mac, BlockSpec.Symbol / MacroTemplate.Symbol).
        "character.cursor.ibeam" => new[] { new Part("M1.8,13 L5.3,3 L8.8,13 M3.1,9.4 H7.5", false, 1.5),
                                            new Part("M12.2,3 V13 M10.6,3 H13.8 M10.6,13 H13.8", false, 1.2) },
        "arrow.up.arrow.down" => new[] { new Part("M5,13 V3 M2.5,5.5 L5,3 L7.5,5.5", false, 1.6),
                                         new Part("M11,3 V13 M8.5,10.5 L11,13 L13.5,10.5", false, 1.6) },
        "cursorarrow.click" => new[] { new Part("M5.6,5.6 V14.6 L7.9,12.4 L9.5,15.4 L11,14.7 L9.5,11.7 H12.6 Z"),
                                       new Part("M3,3 L4.2,4.2 M5.8,1.2 V2.8 M1.2,5.8 H2.8", false, 1.2) },
        "cursorarrow.click.2" => new[] { new Part("M5.6,5.6 V14.6 L7.9,12.4 L9.5,15.4 L11,14.7 L9.5,11.7 H12.6 Z"),
                                         new Part("M3,3 L4.2,4.2 M5.8,1.2 V2.8 M1.2,5.8 H2.8 M8.6,2.4 L7.6,3.4 M2.4,8.6 L3.4,7.6", false, 1.2) },
        "hand.draw" => new[] { new Part(Circle(3, 12.6, 1.6)), new Part("M4.4,11.4 C6.5,5 9.5,12.5 13.4,4", false, 1.5),
                               new Part("M10.8,3.6 L13.4,4 L13.8,6.6", false, 1.5) },
        "clock" or "clock.badge.checkmark" => new[] { new Part(Circle(8, 8, 6.2), false, 1.5),
                                                      new Part("M8,4.4 V8 L10.6,9.6", false, 1.5) },
        "hourglass" => new[] { new Part("M3.5,1.8 H12.5 M3.5,14.2 H12.5", false, 1.5),
                               new Part("M4.6,1.8 C4.6,6 8,6.4 8,8 C8,9.6 4.6,10 4.6,14.2 M11.4,1.8 C11.4,6 8,6.4 8,8 C8,9.6 11.4,10 11.4,14.2", false, 1.3),
                               new Part("M5.6,13.4 C6,11.6 7.5,10.9 8,10.4 C8.5,10.9 10,11.6 10.4,13.4 Z") },
        "macwindow" => new[] { new Part(Rect(1.5, 2.5, 13, 11, 2), false, 1.4), new Part("M1.5,5.8 H14.5", false, 1.4) },
        "macwindow.badge.plus" => new[] { new Part(Rect(1.2, 2.2, 11, 9.4, 2), false, 1.4), new Part("M1.2,5.2 H12.2", false, 1.4),
                                          new Part("M12.4,9.4 V15 M9.6,12.2 H15.2", false, 1.7) },
        "menubar.rectangle" => new[] { new Part(Rect(1.5, 2.5, 13, 11, 2), false, 1.4),
                                       new Part("M4,5.8 H5.8 M7.6,5.8 H9.4 M11.2,5.8 H12", false, 1.5) },
        "filemenu.and.selection" => new[] { new Part(Rect(2, 1.8, 12, 12.4, 2), false, 1.3), new Part("M4.6,4.8 H11.4 M4.6,11.6 H9.6", false, 1.3),
                                            new Part(Rect(3.4, 6.9, 9.2, 2.6, 1)) },
        "list.bullet.rectangle" => new[] { new Part(Rect(1.5, 2.5, 13, 11, 2), false, 1.3), new Part(Circle(4.7, 6, 0.9)),
                                           new Part(Circle(4.7, 10, 0.9)), new Part("M6.8,6 H11.8 M6.8,10 H11.8", false, 1.3) },
        "bolt.horizontal" => new[] { new Part("M9.2,1.2 L3.2,9.2 H7.6 L6.6,14.8 L12.8,6.6 H8.4 Z") },
        "doc.badge.arrow.up" => new[] { new Part("M3.5,1.5 H9 L12.5,5 V14.5 H3.5 Z", false, 1.3), new Part("M9,1.5 V5 H12.5", false, 1.1),
                                        new Part("M8,12.6 V7.6 M5.9,9.7 L8,7.6 L10.1,9.7", false, 1.4) },
        "square.and.arrow.down.on.square" => new[] { new Part("M5,6.5 H3 V14 H13 V6.5 H11", false, 1.4),
                                                     new Part("M8,1.5 V10 M5.5,7.5 L8,10 L10.5,7.5", false, 1.5) },
        "square.stack.3d.up" or "square.stack.3d.down.right" => Parts("channelrack"),
        "paintpalette" => new[] { new Part("M8,1.5 C4.2,1.5 1.5,4.3 1.5,7.8 C1.5,11.4 4.3,14.5 7.6,14.5 C8.8,14.5 9.3,13.8 9,12.9 " +
                                           "C8.6,11.8 9.3,10.8 10.5,10.8 H12 C13.5,10.8 14.5,9.6 14.5,8 C14.5,4.4 11.6,1.5 8,1.5 Z"),
                                  new Part(Circle(4.5, 8, 1.1), Hole: true), new Part(Circle(6, 4.7, 1.1), Hole: true),
                                  new Part(Circle(9.7, 4.4, 1.1), Hole: true), new Part(Circle(12, 7.3, 1.1), Hole: true) },
        "speaker.wave.2" => new[] { new Part("M1.8,6 H4.4 L8,3 V13 L4.4,10 H1.8 Z"),
                                    new Part("M10.2,5.6 C11,6.4 11,9.6 10.2,10.4 M12.2,3.8 C14,5.6 14,10.4 12.2,12.2", false, 1.3) },
        "hifispeaker.and.homepod" => new[] { new Part(Rect(3, 1.5, 10, 13, 2), false, 1.3), new Part(Circle(8, 10, 2.4), false, 1.3),
                                             new Part(Circle(8, 4.8, 1)) },
        "mic" => new[] { new Part(Rect(5.5, 1.5, 5, 8.2, 2.5)),
                         new Part("M3.5,7.6 C3.5,10.3 5.5,12 8,12 C10.5,12 12.5,10.3 12.5,7.6 M8,12 V14.5 M5.6,14.5 H10.4", false, 1.3) },
        "slider.horizontal.3" => new[] { new Part("M2,4 H14 M2,8 H14 M2,12 H14", false, 1.2), new Part(Circle(5, 4, 1.7)),
                                         new Part(Circle(10.6, 8, 1.7)), new Part(Circle(7, 12, 1.7)) },
        "number" => new[] { new Part("M6.2,2 L5,14 M11.2,2 L10,14 M2.6,5.8 H13.8 M2.2,10.2 H13.4", false, 1.4) },
        "repeat" => new[] { new Part("M2.5,8 V6.5 C2.5,5.1 3.6,4 5,4 H13 M11,2 L13,4 L11,6", false, 1.4),
                            new Part("M13.5,8 V9.5 C13.5,10.9 12.4,12 11,12 H3 M5,10 L3,12 L5,14", false, 1.4) },
        "arrow.clockwise" => new[] { new Part("M12.6,9.2 A5,5 0 1 1 12,4.6", false, 1.6), new Part("M12.4,1.8 L12,4.6 L9.2,4", false, 1.6) },
        "arrow.triangle.branch" => new[] { new Part("M8,14.5 V8.5 L3.6,4.1 M8,8.5 L12.4,4.1", false, 1.5),
                                           new Part("M3.2,6.8 V3.7 H6.3 M9.7,3.7 H12.8 V6.8", false, 1.5) },
        "stop.circle" => new[] { new Part(Circle(8, 8, 6.4)), new Part(Rect(5.6, 5.6, 4.8, 4.8, 0.8), Hole: true) },
        "text.bubble" => new[] { new Part("M3,2.5 H13 C13.8,2.5 14.5,3.2 14.5,4 V10 C14.5,10.8 13.8,11.5 13,11.5 H7 L4,14 V11.5 H3 " +
                                          "C2.2,11.5 1.5,10.8 1.5,10 V4 C1.5,3.2 2.2,2.5 3,2.5 Z"),
                                 new Part("M4.5,5.6 H11.5 M4.5,8.4 H9.5", false, 1.2, true) },
        "metronome" => new[] { new Part("M5.6,1.8 H10.4 L13,14.4 H3 Z", false, 1.3), new Part("M8,11.4 L11.6,3.6", false, 1.3),
                               new Part(Circle(8, 11.4, 1)) },
        "record.circle" => new[] { new Part(Circle(8, 8, 6.2), false, 1.4), new Part(Circle(8, 8, 3.4)) },
        "pianokeys" => Parts("pianoroll"),
        "square.grid.2x2" => Parts("general"),
        "wand.and.stars" => Parts("macros"),
        "ellipsis" => new[] { new Part(Circle(3.4, 8, 1.4)), new Part(Circle(8, 8, 1.4)), new Part(Circle(12.6, 8, 1.4)) },
        // Organiser (symboles du Mac : pastilles, poignée, flèches).
        "waveform" => new[] { new Part("M2,6.5 V9.5 M4.8,4 V12 M7.6,2 V14 M10.4,4.5 V11.5 M13.2,6 V10", false, 1.6) },
        "exclamationmark" => new[] { new Part(Rect(4.5, 4.5, 7, 7, 0)) },
        "antenna.radiowaves.left.and.right" => new[] { new Part(Circle(8, 8, 1.6)),
            new Part("M5.2,5.2 C3.7,6.7 3.7,9.3 5.2,10.8 M10.8,5.2 C12.3,6.7 12.3,9.3 10.8,10.8 " +
                     "M3,3 C0.4,5.6 0.4,10.4 3,13 M13,3 C15.6,5.6 15.6,10.4 13,13", false, 1.4) },
        "stop.fill" => new[] { new Part(Rect(3.5, 3.5, 9, 9, 1.6)) },
        "doc.text.fill" => new[] { new Part("M3.5,1.5 H9 L12.5,5 V14.5 H3.5 Z"), new Part("M5.6,8 H10.4 M5.6,10.6 H10.4", false, 1.1, true) },
        "line.3.horizontal" => new[] { new Part("M2.5,4.5 H13.5 M2.5,8 H13.5 M2.5,11.5 H13.5", false, 1.6) },
        "arrow.right" => new[] { new Part("M2.5,8 H13 M9,4 L13,8 L9,12", false, 1.6) },
        "arrow.left" => new[] { new Part("M13.5,8 H3 M7,4 L3,8 L7,12", false, 1.6) },
        "chevron.down" => new[] { new Part("M3.5,6 L8,10.5 L12.5,6", false, 1.8) },
        "chevron.right" => new[] { new Part("M6,3.5 L10.5,8 L6,12.5", false, 1.8) },
        "music.note" => new[] { new Part("M6.5,12 V2.6 L13,1.6 V10.4", false, 1.4), new Part(Circle(4.6, 12.2, 2)), new Part(Circle(11.1, 10.6, 2)) },
        _ => Array.Empty<Part>(),
    };

    /// Une icône dessinée à la taille voulue ; `hole` : la couleur des parties « percées » (celle de la tuile).
    public static FrameworkElement Icon(string name, double size, Color color, Color? hole = null)
    {
        // L'avertissement suisse porte toujours le rouge-orange du thème (#FF3B1F, blanc sous Orange), comme le Mac.
        if (name is "warning" or "exclamationmark") color = Red;
        var canvas = new Canvas { Width = 16, Height = 16 };
        foreach (var p in Parts(name))
        {
            var c = p.Hole ? hole ?? Colors.Transparent : color;
            var path = (Microsoft.UI.Xaml.Shapes.Path)XamlReader.Load(
                $"<Path xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" Data=\"{p.Data}\"/>");
            if (p.Stroke > 0)
            {
                path.Stroke = Brush(c);
                path.StrokeThickness = p.Stroke;
                path.StrokeStartLineCap = PenLineCap.Round;
                path.StrokeEndLineCap = PenLineCap.Round;
                path.StrokeLineJoin = PenLineJoin.Round;
            }
            else
            {
                path.Fill = Brush(c);
            }
            canvas.Children.Add(path);
        }
        return new Viewbox { Width = size, Height = size, Child = canvas, IsHitTestVisible = false };
    }

    /// Repère d'une page ou d'une rubrique (style suisse) : un petit carré plein de sa couleur, centré dans la place
    /// de l'ancienne tuile (`size`), comme la barre de gauche du Mac.
    public static Border Tile(string icon, Color tint, double size = 22)
    {
        var tile = new Border { Width = size, Height = size, IsHitTestVisible = false };
        SetTileHover(tile, icon, tint, hovered: false);
        return tile;
    }

    /// Le carré garde sa couleur au survol (la ligne devient blanche, le carré reste lisible dessus).
    public static void SetTileHover(Border tile, string icon, Color tint, bool hovered)
    {
        var side = Math.Max(8, Math.Round(tile.Width * 0.38));
        tile.Child = new Rectangle
        {
            Width = side,
            Height = side,
            Fill = Brush(tint),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    // ---------- Touches ----------

    /// Une touche (style suisse) : petit carré au cadre clair, lettre en gras ; changée : en rouge.
    public static Border Cap(string text, bool changed = false, bool muted = false) => new()
    {
        MinWidth = 20,
        Height = 20,
        Padding = new Thickness(5, 0, 5, 0),
        Background = Brush(WindowColor),
        BorderBrush = Brush(changed ? Red : muted ? Tertiary : KeyFrame),
        BorderThickness = new Thickness(1),
        Child = new TextBlock
        {
            Text = text,
            FontSize = 11.5,
            FontWeight = FontWeights.Bold,
            FontFamily = SwissFont,
            Foreground = Brush(changed ? Red : muted ? Secondary : Text),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        },
    };

    /// Les touches d'un raccourci, une plaque par touche (« Ctrl » « Maj » « 4 ») ; aucune : « Aucune ».
    public static StackPanel Keys(KeyCombo? combo, bool changed = false)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 3, VerticalAlignment = VerticalAlignment.Center };
        if (combo is not { } c)
        {
            row.Children.Add(Cap(Loc.T("Aucune"), muted: true));
            return row;
        }
        foreach (var name in c.Caps) row.Children.Add(changed ? ChangedCap(Loc.T(name)) : Cap(Loc.T(name)));
        return row;
    }

    /// Touche changée (06/11, comme le Mac : « si on change une touche, il y a un relief ») : pleine de rouge, bordée
    /// d'encre, soulevée sur son ombre nette d'encre (effet Gumroad), dans les trois thèmes.
    public static Grid ChangedCap(string text)
    {
        var face = Cap(text);
        face.Background = Brush(Red);
        face.BorderBrush = Brush(Text);
        face.BorderThickness = new Thickness(1.5);
        if (face.Child is TextBlock label) label.Foreground = Brush(Text);
        var shadow = new Rectangle { Fill = Brush(Text), IsHitTestVisible = false };
        var host = new Grid { Margin = new Thickness(2, 2, 0, 0), Children = { shadow, face } };
        SetLift(face, shadow, true, 2);
        return host;
    }

    // ---------- Boutons et survol ----------

    private static Style? _plain;

    /// Bouton sans dessin du système : son contenu seul, avec son fond et ses coins (focus clavier gardé).
    public static Style PlainButton => _plain ??= MakePlain();

    private static Style MakePlain()
    {
        var style = new Style(typeof(Button));
        style.Setters.Add(new Setter(Control.BackgroundProperty, Brush(Colors.Transparent)));
        style.Setters.Add(new Setter(Control.ForegroundProperty, Brush(Text)));
        style.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(0)));
        style.Setters.Add(new Setter(Control.BorderThicknessProperty, new Thickness(0)));
        style.Setters.Add(new Setter(FrameworkElement.HorizontalAlignmentProperty, HorizontalAlignment.Stretch));
        style.Setters.Add(new Setter(Control.HorizontalContentAlignmentProperty, HorizontalAlignment.Stretch));
        style.Setters.Add(new Setter(Control.VerticalContentAlignmentProperty, VerticalAlignment.Center));
        style.Setters.Add(new Setter(Control.UseSystemFocusVisualsProperty, true));
        style.Setters.Add(new Setter(Control.TemplateProperty, XamlReader.Load(
            "<ControlTemplate xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\" TargetType=\"Button\">" +
            "<ContentPresenter Background=\"{TemplateBinding Background}\" BorderBrush=\"{TemplateBinding BorderBrush}\" " +
            "BorderThickness=\"{TemplateBinding BorderThickness}\" CornerRadius=\"{TemplateBinding CornerRadius}\" " +
            "Padding=\"{TemplateBinding Padding}\" Content=\"{TemplateBinding Content}\" " +
            "Foreground=\"{TemplateBinding Foreground}\" " +
            "HorizontalContentAlignment=\"{TemplateBinding HorizontalContentAlignment}\" " +
            "VerticalContentAlignment=\"{TemplateBinding VerticalContentAlignment}\"/></ControlTemplate>")));
        return style;
    }

    /// Une option cliquable (style suisse) : au survol comme choisie, blanc plein et texte noir, coins carrés (`tint` et
    /// `radius` ne servent plus). `hover` : ce qui change en plus (texte de couleur fixe à noircir).
    public static Button Option(UIElement content, Color tint, double radius, Action? click, bool selected = false,
                                Action<bool>? hover = null, double minHeight = 32, Thickness? padding = null)
    {
        Color ink = Text, paper = WindowColor;          // pris maintenant : une partie inversée garde les siens
        var button = new Button
        {
            Style = PlainButton,
            Content = content,
            MinHeight = minHeight,
            Padding = padding ?? new Thickness(10, 0, 10, 0),
            Background = Brush(selected ? ink : Colors.Transparent),
            Foreground = Brush(selected ? paper : ink),
            FontWeight = selected ? FontWeights.Bold : FontWeights.Normal,
        };
        if (!selected)
        {
            void Set(bool on)
            {
                button.Background = Brush(on ? ink : Colors.Transparent);
                button.Foreground = Brush(on ? paper : ink);
                hover?.Invoke(on);
            }
            button.PointerEntered += (_, _) => Set(true);
            button.PointerExited += (_, _) => Set(false);
            button.PointerCanceled += (_, _) => Set(false);
            button.PointerCaptureLost += (_, _) => Set(false);
        }
        if (click is not null) button.Click += (_, _) => click();
        return button;
    }

    /// Champ de raccourci : la molette cliquée ou un bouton du côté de la souris (05/11), en « touche » (Vk.MButton…) ;
    /// null pour un autre bouton. Le champ l'écoute même si le bouton a déjà traité l'appui (handledEventsToo).
    public static ushort? PressedMouseButton(Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e, UIElement element)
    {
        var p = e.GetCurrentPoint(element).Properties;
        return p.IsMiddleButtonPressed ? global::FLShortcut.Core.Vk.MButton
             : p.IsXButton1Pressed ? global::FLShortcut.Core.Vk.XButton1
             : p.IsXButton2Pressed ? global::FLShortcut.Core.Vk.XButton2
             : null;
    }

    /// Bouton principal (Valider, Organiser…) au style suisse : rectangle blanc plein, texte noir en capitales ; au
    /// survol, noir bordé de blanc (SwissButtonBody du Mac).
    public static Button Primary(string text, Action click) => SwissButton(text, click, primary: true);
    /// Principal avec une icône devant (« ⊙ ENREGISTRER UNE MACRO », comme le Mac).
    public static Button Primary(string text, string icon, Action click) => SwissButton(text, click, primary: true, icon: icon);

    /// Bouton secondaire (Annuler, Réparer…) : rectangle bordé de blanc, capitales ; au survol, blanc plein.
    public static Button Soft(string text, Action click) => SwissButton(text, click, primary: false);

    /// Menu du clic droit au style suisse (07/11, comme le Mac : « le bouton supprimer ou dupliquer dans le style
    /// suisse ») : fond plein, trait fin, coins carrés, ligne pleine d'encre au survol, « Supprimer » en rouge ; noir
    /// sous Orange, comme les autres petites fenêtres.
    public static MenuFlyout SwissMenu(MenuFlyout menu)
    {
        using var surface = Theme == AppTheme.Orange ? Inverted() : null;
        var presenter = new Style(typeof(MenuFlyoutPresenter));
        presenter.Setters.Add(new Setter(Control.BackgroundProperty, Brush(WindowColor)));
        presenter.Setters.Add(new Setter(Control.BorderBrushProperty, Brush(Text)));
        presenter.Setters.Add(new Setter(Control.BorderThicknessProperty, new Thickness(1)));
        presenter.Setters.Add(new Setter(Control.CornerRadiusProperty, new CornerRadius(0)));
        presenter.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(4)));
        menu.MenuFlyoutPresenterStyle = presenter;
        foreach (var entry in menu.Items)
        {
            if (entry is MenuFlyoutSeparator separator)
            {
                separator.Background = Brush(LineColor);
                continue;
            }
            if (entry is not MenuFlyoutItem item) continue;
            var ink = item.Text.StartsWith(Loc.T("Supprimer"), StringComparison.CurrentCulture) ? Red : Text;
            item.FontFamily = SwissFont;
            item.FontWeight = FontWeights.Bold;
            item.FontSize = 13;
            item.CornerRadius = new CornerRadius(0);
            item.Foreground = Brush(ink);
            item.Resources["MenuFlyoutItemForeground"] = Brush(ink);
            item.Resources["MenuFlyoutItemBackgroundPointerOver"] = Brush(ink);
            item.Resources["MenuFlyoutItemForegroundPointerOver"] = Brush(WindowColor);
            item.Resources["MenuFlyoutItemBackgroundPressed"] = Brush(ink);
            item.Resources["MenuFlyoutItemForegroundPressed"] = Brush(WindowColor);
            // Choix à cocher (Options de l'Organiser) : mêmes couleurs, coche à l'encre.
            item.Resources["ToggleMenuFlyoutItemForeground"] = Brush(ink);
            item.Resources["ToggleMenuFlyoutItemBackgroundPointerOver"] = Brush(ink);
            item.Resources["ToggleMenuFlyoutItemForegroundPointerOver"] = Brush(WindowColor);
            item.Resources["ToggleMenuFlyoutItemBackgroundPressed"] = Brush(ink);
            item.Resources["ToggleMenuFlyoutItemForegroundPressed"] = Brush(WindowColor);
            item.Resources["ToggleMenuFlyoutItemCheckGlyphForeground"] = Brush(ink);
            item.Resources["ToggleMenuFlyoutItemCheckGlyphForegroundPointerOver"] = Brush(WindowColor);
        }
        return menu;
    }

    /// Liste déroulante au style suisse (08/11, comme le Mac : « ces listes, mets-les dans le même style que le
    /// logiciel ») : case carrée bordée d'un trait fin ; liste au fond plein, bordée d'encre, coins carrés, ligne
    /// pleine d'encre au survol, le choix en cours marqué d'un trait rouge (plus de bleu ni d'arrondi de Windows).
    public static ComboBox SwissCombo(ComboBox box)
    {
        box.CornerRadius = new CornerRadius(0);
        box.FontFamily = SwissFont;
        box.FontSize = 12.5;
        box.Background = Brush(WindowColor);
        box.Foreground = Brush(Text);
        box.BorderBrush = Brush(Tertiary);
        box.BorderThickness = new Thickness(1);
        var r = box.Resources;
        r["OverlayCornerRadius"] = new CornerRadius(0);
        r["ControlCornerRadius"] = new CornerRadius(0);
        r["ComboBoxBackground"] = Brush(WindowColor);
        r["ComboBoxBackgroundPointerOver"] = Brush(Text);
        r["ComboBoxBackgroundPressed"] = Brush(Text);
        r["ComboBoxBackgroundFocused"] = Brush(WindowColor);
        r["ComboBoxForeground"] = Brush(Text);
        r["ComboBoxForegroundPointerOver"] = Brush(WindowColor);
        r["ComboBoxForegroundPressed"] = Brush(WindowColor);
        r["ComboBoxForegroundFocused"] = Brush(Text);
        r["ComboBoxBorderBrush"] = Brush(Tertiary);
        r["ComboBoxBorderBrushPointerOver"] = Brush(Text);
        r["ComboBoxBorderBrushPressed"] = Brush(Text);
        r["ComboBoxBorderBrushFocused"] = Brush(Text);
        r["ComboBoxDropDownGlyphForeground"] = Brush(Text);
        r["ComboBoxDropDownGlyphForegroundFocused"] = Brush(Text);
        r["ComboBoxDropDownBackground"] = Brush(WindowColor);
        r["ComboBoxDropDownBorderBrush"] = Brush(Text);
        r["ComboBoxDropdownBorderThickness"] = new Thickness(1);
        r["ComboBoxItemForeground"] = Brush(Text);
        r["ComboBoxItemBackgroundPointerOver"] = Brush(Text);
        r["ComboBoxItemForegroundPointerOver"] = Brush(WindowColor);
        r["ComboBoxItemBackgroundPressed"] = Brush(Text);
        r["ComboBoxItemForegroundPressed"] = Brush(WindowColor);
        r["ComboBoxItemBackgroundSelected"] = Brush(Colors.Transparent);
        r["ComboBoxItemForegroundSelected"] = Brush(Text);
        r["ComboBoxItemBackgroundSelectedPointerOver"] = Brush(Text);
        r["ComboBoxItemForegroundSelectedPointerOver"] = Brush(WindowColor);
        r["ComboBoxItemBackgroundSelectedPressed"] = Brush(Text);
        r["ComboBoxItemForegroundSelectedPressed"] = Brush(WindowColor);
        r["ComboBoxItemPillFillBrush"] = Brush(BrandRed);
        r["ComboBoxItemCornerRadius"] = new CornerRadius(0);
        r["ComboBoxItemPillCornerRadius"] = new CornerRadius(0);
        return box;
    }

    /// Curseur et sélection de TOUS les champs comme la recherche (07/11, comme le Mac : « la barre qui clignote
    /// identique à la barre de recherche, en rapport avec le thème ») : texte et curseur à l'encre du thème, sélection
    /// grise, jamais de bleu quand le champ a la main. Posé une fois dans les ressources de l'app, avant les fenêtres.
    public static void ApplyTextFieldLook(ResourceDictionary resources)
    {
        resources["TextControlForegroundFocused"] = Brush(Text);
        resources["TextControlSelectionHighlightColor"] = Brush(Tertiary);
        resources["TextControlBorderBrushFocused"] = Brush(Text);
    }

    /// Bouton principal et carte principale (maquettes du 05/11, comme le Mac) : plein blanc sous Noir et Orange, noir
    /// sous Papier ; ombre nette rouge sous Papier, noire sous Orange, aucune sous Noir (et dans les parties sombres).
    public static Color PrimaryFill => Theme == AppTheme.Papier && !DarkSurface ? Colors.Black : Colors.White;
    public static Color PrimaryInk => Theme == AppTheme.Papier && !DarkSurface ? Colors.White : Colors.Black;
    public static Color? PrimaryShadow => DarkSurface ? null : Theme == AppTheme.Papier ? BrandRed : Colors.Black;

    /// Ombre de l'effet Gumroad au survol (06/11, comme le Mac `Swiss.primaryLift`) : noire sur le fond orange, rouge
    /// partout ailleurs (sous Noir aussi).
    public static Color LiftColor => Theme == AppTheme.Orange && !DarkSurface ? Colors.Black : BrandRed;

    /// Ombre de l'effet Gumroad, cachée au repos (voir SetLift).
    public static Rectangle LiftShadow(Color? color = null) => new()
    {
        Fill = Brush(color ?? LiftColor),
        IsHitTestVisible = false,
        Visibility = Visibility.Collapsed,
    };

    /// Effet Gumroad (06/11, « qu'il ne soit pas là quand on ne met pas la souris dessus ; quand on met la souris
    /// dessus, il apparaît ») : soulevée, la face monte en haut à gauche de `distance` et laisse voir son ombre nette
    /// à sa place ; au repos, rien ne dépasse. La face et l'ombre sont dans la même grille.
    public static void SetLift(FrameworkElement face, Rectangle shadow, bool on, double distance = 4)
    {
        face.RenderTransform = new TranslateTransform { X = on ? -distance : 0, Y = on ? -distance : 0 };
        shadow.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
    }

    /// Ombre nette décalée de `offset` points sous un élément (comme celle des maquettes) ; null : rien.
    public static Rectangle HardShadow(Color? color, double offset) => new()
    {
        Fill = Brush(color ?? Colors.Transparent),
        RenderTransform = new TranslateTransform { X = offset, Y = offset },
        IsHitTestVisible = false,
        Visibility = color is null ? Visibility.Collapsed : Visibility.Visible,
    };

    private static Button SwissButton(string text, Action click, bool primary, string? icon = null)
    {
        // Maquettes du 05/11 (comme le Mac) : le principal est plein. 06/11 : sans ombre au repos ; au survol, il garde
        // ses couleurs et se soulève sur son ombre nette (effet Gumroad). Le bordé (trait de 2 points, plein du fond :
        // la grille de Papier ne passe pas dedans) se remplit d'encre au survol.
        Color ink = Text, paper = WindowColor, fill = PrimaryFill, onFill = PrimaryInk;
        var label = Label(text.ToUpper(CultureInfo.CurrentCulture), 12, primary ? onFill : ink, bold: true);
        label.CharacterSpacing = 80;
        label.HorizontalAlignment = HorizontalAlignment.Center;
        UIElement content = label;
        if (icon is not null)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center };
            var mark = Icon(icon, 13, primary ? onFill : ink);
            mark.VerticalAlignment = VerticalAlignment.Center;
            row.Children.Add(mark);
            label.VerticalAlignment = VerticalAlignment.Center;
            row.Children.Add(label);
            content = row;
        }
        var face = new Border
        {
            Background = Brush(primary ? fill : paper),
            BorderBrush = Brush(ink),
            BorderThickness = new Thickness(2),
            Padding = new Thickness(16, 0, 16, 0),
            MinHeight = 32,
            Child = content,
        };
        var shadow = LiftShadow();
        var button = new Button
        {
            Style = PlainButton,
            HorizontalAlignment = HorizontalAlignment.Left,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            VerticalContentAlignment = VerticalAlignment.Stretch,
            Content = new Grid { Children = { shadow, face } },
            MinHeight = 32,
        };
        void Set(bool on)
        {
            if (primary)
            {
                SetLift(face, shadow, on);
            }
            else
            {
                face.Background = Brush(on ? ink : paper);
                label.Foreground = Brush(on ? paper : ink);
            }
        }
        button.PointerEntered += (_, _) => Set(true);
        button.PointerExited += (_, _) => Set(false);
        button.PointerCanceled += (_, _) => Set(false);
        button.PointerCaptureLost += (_, _) => Set(false);
        button.Click += (_, _) => click();
        return button;
    }

    /// Bouton carré de l'en-tête (44 points), une icône seule, bordé de blanc ; au survol, blanc plein.
    public static Button RoundIcon(string icon, string help, Action click, double size = 44)
    {
        Color ink = Text, paper = WindowColor;
        var button = new Button
        {
            Style = PlainButton,
            Width = size,
            Height = size,
            HorizontalAlignment = HorizontalAlignment.Center,
            HorizontalContentAlignment = HorizontalAlignment.Center,
            Content = Icon(icon, size * 0.4, ink),
            BorderBrush = Brush(ink),
            BorderThickness = new Thickness(1),
        };
        button.PointerEntered += (_, _) =>
        {
            button.Background = Brush(ink);
            button.Content = Icon(icon, size * 0.4, paper);
        };
        button.PointerExited += (_, _) =>
        {
            button.Background = Brush(Colors.Transparent);
            button.Content = Icon(icon, size * 0.4, ink);
        };
        button.Click += (_, _) => click();
        ToolTipService.SetToolTip(button, help);
        AutomationProperties.SetName(button, help);
        return button;
    }
}
