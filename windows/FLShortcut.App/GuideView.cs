// Fenêtre du guide, la même que le Mac (Guide.swift ; demande du 10/11 : « la page de guide après l'installation, le
// même que sur Mac ») : une carte de 640 × 540 posée sur la fenêtre. « Bienvenue » : grand titre à point carré, une
// ligne par partie (numéro, carré creux, titre, première étape en gris, flèche ; survolée : pleine d'encre, carré
// orange). Une partie : carré creux + titre, puis ses trois étapes (numéro rouge, phrase en gras) entre des traits
// fins. En bas : « Passer » (sauf à la fin), les points de pagination, « Précédent » et le bouton principal
// (« Découvrir », « Suivant », « C'est parti »). Entrée : le bouton principal ; Échap : « Passer ».
// Contenu : GuideContent (cœur, mêmes textes que le Mac sauf « Au quotidien »). Aucune animation continue : la page
// qui arrive glisse et se fond une fois (rien si Windows a coupé les animations).
using FLShortcut.Core;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal sealed class GuideView
{
    /// Taille de la carte, comme la feuille du Mac.
    public const double Width = 640, Height = 540;
    private const double Side = 56;

    private readonly Border _card;
    private readonly Grid _page = new() { VerticalAlignment = VerticalAlignment.Top };
    private readonly Grid _footer = new() { VerticalAlignment = VerticalAlignment.Bottom };
    private readonly Action _close;
    private int _current;
    /// Le bouton principal de la page montrée : il prend le clavier (Tab reste dans la carte).
    private Button? _primary;

    public FrameworkElement View => _card;

    /// `page` : 0 « Bienvenue », 1… les parties. `close` : « Passer », « C'est parti ».
    public GuideView(int page, Action close)
    {
        _close = close;
        _current = GuideContent.Clamp(page);
        var inside = new Grid { Padding = new Thickness(Side, 48, Side, 24) };
        inside.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        inside.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        inside.Children.Add(_page);
        Grid.SetRow(_footer, 1);
        inside.Children.Add(_footer);
        _card = new Border
        {
            Width = Width,
            Height = Height,
            Background = Brush(WindowColor),
            BorderBrush = Brush(LineColor),
            BorderThickness = new Thickness(1),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Child = inside,
        };
        AutomationProperties.SetName(_card, Loc.T("Bienvenue"));
        Render(forward: null);
    }

    /// Entrée : le bouton principal. Échap : « Passer » (pas à la fin, où il n'y est plus). Vrai si la touche a servi.
    public bool Key(Windows.System.VirtualKey key)
    {
        switch (key)
        {
            case Windows.System.VirtualKey.Enter:
                Next();
                return true;
            case Windows.System.VirtualKey.Escape:
                if (!GuideContent.IsLast(_current)) _close();
                return true;
            default:
                return false;
        }
    }

    /// Le clavier va au bouton principal (à l'ouverture, puis à chaque page).
    public void Focus()
    {
        var button = _primary;
        button?.DispatcherQueue.TryEnqueue(() => button.Focus(FocusState.Programmatic));
    }

    /// Mode photos de la CI : une page donnée, sans animation.
    public void Show(int page)
    {
        _current = GuideContent.Clamp(page);
        Render(forward: null);
    }

    private void Next()
    {
        if (GuideContent.IsLast(_current)) _close();
        else Go(_current + 1);
    }

    private void Go(int page)
    {
        var target = GuideContent.Clamp(page);
        if (target == _current) return;
        var forward = target > _current;
        _current = target;
        Render(forward);
        Focus();
    }

    /// `forward` : sens du changement (en avant, la page glisse depuis la droite ; en arrière, simple fondu comme le
    /// Mac) ; null : montrée d'un coup.
    private void Render(bool? forward)
    {
        _page.Children.Clear();
        var content = GuideContent.Part(_current) is { } part ? Part(part) : Welcome();
        _page.Children.Add(content);
        if (forward is { } ahead) Motion.Enter(content, fromX: ahead ? 24 : 0, fromY: 0, durationMs: Motion.Normal);
        RenderFooter();
    }

    // ---------- « Bienvenue » ----------

    private FrameworkElement Welcome()
    {
        var stack = new StackPanel();
        stack.Children.Add(Heading(Loc.T("Bienvenue"), 46, null));
        foreach (var page in GuideContent.Pages) stack.Children.Add(WelcomeRow(page));
        return stack;
    }

    /// Gros titre en minuscules avec son point carré, souligné à l'encre ; `mark` : le carré creux d'une partie, devant.
    private static FrameworkElement Heading(string text, double size, FrameworkElement? mark)
    {
        var title = SwissTitle(size);
        title.Text = text.ToLower(System.Globalization.CultureInfo.CurrentCulture);
        var line = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 14 };
        if (mark is not null)
        {
            mark.VerticalAlignment = VerticalAlignment.Bottom;
            mark.Margin = new Thickness(0, 0, 0, Math.Round(size * 0.24));
            line.Children.Add(mark);
        }
        line.Children.Add(PageTitle(title, size));
        var head = new StackPanel { Spacing = 12 };
        head.Children.Add(line);
        head.Children.Add(Rule(Text));
        return head;
    }

    /// Carré creux à l'encre (BlockSquare du Mac) ; orange sur la ligne survolée.
    private static Border Square(double side) => new()
    {
        Width = side,
        Height = side,
        BorderBrush = Brush(Text),
        BorderThickness = new Thickness(side >= 12 ? 1.5 : 1.2),
        VerticalAlignment = VerticalAlignment.Center,
    };

    /// Ligne d'une partie : numéro, carré, titre, première étape en gris, flèche ; un clic ouvre la partie.
    private FrameworkElement WelcomeRow(GuidePage page)
    {
        Color ink = Text, paper = WindowColor, gray = Secondary;
        var number = SwissLabel(page.Id.ToString("00", System.Globalization.CultureInfo.InvariantCulture), 11, gray);
        var square = Square(8);
        var title = Label(page.Title, 18, ink, bold: true);
        title.CharacterSpacing = -17;
        title.TextTrimming = TextTrimming.None;
        var first = Label(page.Steps.Count > 0 ? page.Steps[0] : "", 12.5, gray);
        var arrow = Label("→", 15, gray);

        var row = new Grid { ColumnSpacing = 10, Height = 52, Padding = new Thickness(4, 0, 4, 0) };
        foreach (var width in new[] { new GridLength(30), GridLength.Auto, GridLength.Auto, new GridLength(1, GridUnitType.Star), GridLength.Auto })
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = width });
        var column = 0;
        foreach (var piece in new FrameworkElement[] { number, square, title, first, arrow })
        {
            Grid.SetColumn(piece, column++);
            row.Children.Add(piece);
        }

        var button = Option(row, () => Go(page.Id), minHeight: 52, padding: new Thickness(0), hover: on =>
        {
            title.Foreground = Brush(on ? paper : ink);
            foreach (var soft in new[] { number, first, arrow }) soft.Foreground = Brush(on ? WithOpacity(paper, 0.7) : gray);
            square.BorderBrush = Brush(on ? BrandRed : ink);
            square.Background = Brush(on ? BrandRed : Colors.Transparent);
        });
        ToolTipService.SetToolTip(button, Loc.F("Voir « %@ »", page.Title));
        AutomationProperties.SetName(button, page.Title);
        var line = new StackPanel();
        line.Children.Add(button);
        line.Children.Add(Rule(LineColor));
        return line;
    }

    // ---------- Une partie ----------

    private static FrameworkElement Part(GuidePage page)
    {
        var stack = new StackPanel();
        // 13/11 (essai 1.3 : « il faut que les carrés deviennent orange sur chaque page ») : la partie ouverte a son
        // carré plein d'orange, comme la page ouverte dans la barre de gauche.
        var mark = Square(14);
        mark.BorderBrush = Brush(BrandRed);
        mark.Background = Brush(BrandRed);
        stack.Children.Add(Heading(page.Title, 40, mark));
        for (var i = 0; i < page.Steps.Count; i++)
        {
            var number = Label((i + 1).ToString("00", System.Globalization.CultureInfo.InvariantCulture), 11, Red, bold: true);
            var text = new TextBlock
            {
                Text = page.Steps[i],
                FontSize = 14,
                FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                FontFamily = SwissFont,
                Foreground = Brush(Text),
                TextWrapping = TextWrapping.Wrap,
                VerticalAlignment = VerticalAlignment.Center,
            };
            var row = new Grid { ColumnSpacing = 12, MinHeight = 50, Padding = new Thickness(0, 6, 0, 6) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(30) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.Children.Add(number);
            Grid.SetColumn(text, 1);
            row.Children.Add(text);
            AutomationProperties.SetName(row, $"{i + 1}. {page.Steps[i]}");
            stack.Children.Add(row);
            stack.Children.Add(Rule(LineColor));
        }
        return stack;
    }

    // ---------- Bas de la carte ----------

    /// « Passer » à gauche, les points au milieu, les boutons à droite. Les points restent au centre de la carte tant
    /// que les boutons leur laissent la place ; sinon ils se poussent juste assez pour ne jamais passer dessous.
    private void RenderFooter()
    {
        _footer.Children.Clear();
        var last = GuideContent.IsLast(_current);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, HorizontalAlignment = HorizontalAlignment.Right };
        if (_current > 0) buttons.Children.Add(Large(Soft(Loc.T("Précédent"), () => Go(_current - 1))));
        _primary = Large(Primary(GuideContent.NextTitle(_current), Next));
        buttons.Children.Add(_primary);

        var left = new Grid { HorizontalAlignment = HorizontalAlignment.Left };
        if (!last) left.Children.Add(Skip());

        var dots = Dots();
        // Une fois les tailles connues : la place qui reste à droite des points centrés, comparée aux boutons.
        void Place()
        {
            var width = _footer.ActualWidth > 0 ? _footer.ActualWidth : Width - 2 * Side - 2;
            var over = buttons.ActualWidth + 12 - (width - dots.ActualWidth) / 2;
            var margin = new Thickness(0, 0, over > 0 ? 2 * over : 0, 0);      // centré dans ce qui reste : décalé de `over`
            if (dots.Margin != margin) dots.Margin = margin;
        }
        buttons.SizeChanged += (_, _) => Place();
        dots.SizeChanged += (_, _) => Place();
        _footer.Children.Add(dots);
        _footer.Children.Add(left);
        _footer.Children.Add(buttons);
    }

    private static Button Large(Button button)
    {
        button.MinHeight = 36;
        button.MinWidth = 96;
        return button;
    }

    /// « PASSER » : petites capitales grises, à l'encre au survol.
    private Button Skip()
    {
        Color ink = Text, gray = Secondary;
        var label = SwissLabel(Loc.T("Passer"), 11, gray);
        var button = new Button
        {
            Style = PlainButton,
            Content = label,
            Padding = new Thickness(0, 8, 8, 8),
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        button.PointerEntered += (_, _) => label.Foreground = Brush(ink);
        button.PointerExited += (_, _) => label.Foreground = Brush(gray);
        button.Click += (_, _) => _close();
        ToolTipService.SetToolTip(button, Loc.T("Fermer le guide : tu le retrouves dans la page Aide."));
        AutomationProperties.SetName(button, Loc.T("Passer"));
        return button;
    }

    /// Points de pagination, cliquables : celui de la page ouverte s'allonge, à l'encre.
    private StackPanel Dots()
    {
        var dots = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        for (var i = 0; i < GuideContent.Count; i++)
        {
            var page = i;
            var on = page == _current;
            var mark = new Border { Width = on ? 22 : 8, Height = 4, Background = Brush(on ? Text : Tertiary) };
            var dot = new Button { Style = PlainButton, Content = mark, Padding = new Thickness(3, 8, 3, 8), HorizontalAlignment = HorizontalAlignment.Left };
            dot.Click += (_, _) => Go(page);
            AutomationProperties.SetName(dot, Loc.F("Page %lld sur %lld", page + 1, GuideContent.Count));
            dots.Children.Add(dot);
        }
        return dots;
    }
}
