// Accueil Windows au même aspect que le Mac (cartes claires sur fond noir, étapes d'une ligne, bouton bleu) : 1. les
// deux ports MIDI virtuels (loopMIDI), 2. relier FL Studio (lien installé, MIDI Settings). Seulement avec le lien :
// en mode léger, rien à configurer. « Réparer » (bandeau de la fenêtre) y ramène, avec « Retour aux raccourcis ».
using FLShortcut.App.Services;
using FLShortcut.Core;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Storage.Pickers;
using Windows.UI;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal sealed partial class MainShell
{
    private enum LinkStep { Idle, Waiting, Linked }

    private readonly Grid _welcome = new();
    private readonly StackPanel _welcomeContent = new()
    {
        MaxWidth = 560,
        Spacing = 14,
        HorizontalAlignment = HorizontalAlignment.Center,
        VerticalAlignment = VerticalAlignment.Center,
        Padding = new Thickness(40, TitleBarHeight, 40, 40),
    };
    private LinkStep _linkStep = LinkStep.Idle;
    private bool _onLinkStep;
    private bool? _shownPortsOk;

    private void BuildWelcome()
    {
        _welcome.Children.Add(new ScrollViewer { Content = _welcomeContent, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled });
    }

    private void OnPoll()
    {
        if (_welcome.Visibility != Visibility.Visible) return;
        if (!_onLinkStep)
        {
            if (_shownPortsOk != MidiLink.PortsExist()) ShowWelcomePorts();
        }
        else if (_linkStep == LinkStep.Waiting && _app.Linked)
        {
            _linkStep = LinkStep.Linked;
            ShowWelcomeLink(null);
        }
    }

    /// « Réparer » : les ports s'ils manquent, sinon le lien.
    private void Repair()
    {
        _main.Visibility = Visibility.Collapsed;
        _welcome.Visibility = Visibility.Visible;
        if (!_app.PortsPresent)
        {
            ShowWelcomePorts();
            return;
        }
        _linkStep = LinkStep.Idle;
        ShowWelcomeLink(null);
    }

    private void BackToMain()
    {
        _onLinkStep = false;
        ShowScreen();
    }

    /// Logo de l'appli (le « A » choisi le 04/11, à la place du clavier) : le grand cercle blanc au centre, le rond
    /// rouge devant en bas à gauche, sans fond, sur le noir de l'accueil ; petit, le cercle plus épais
    /// (marque/rond-A-transparent et rond-A-petit).
    private static FrameworkElement AppIcon(double size)
    {
        var k = size / 1024;
        var (cx, cy, r, w) = size < 128 ? (512.0, 512.0, 380.0, 40.0) : (512.0, 512.0, 394.0, 12.0);
        var outer = (r + w / 2) * k;                 // le trait d'une ellipse est dessiné à l'intérieur de sa taille
        var ring = new Microsoft.UI.Xaml.Shapes.Ellipse
        {
            Width = 2 * outer, Height = 2 * outer, Stroke = Brush(LogoRing), StrokeThickness = Math.Max(1, w * k),
        };
        Canvas.SetLeft(ring, cx * k - outer);
        Canvas.SetTop(ring, cy * k - outer);
        var dot = new Microsoft.UI.Xaml.Shapes.Ellipse { Width = 580 * k, Height = 580 * k, Fill = Brush(BrandRed) };
        Canvas.SetLeft(dot, 102 * k);
        Canvas.SetTop(dot, 362 * k);
        var logo = new Canvas { Width = size, Height = size, HorizontalAlignment = HorizontalAlignment.Center };
        AutomationProperties.SetAccessibilityView(logo, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        logo.Children.Add(ring);
        logo.Children.Add(dot);
        return logo;
    }

    private static TextBlock Heading(string text)
    {
        var heading = Label(text, 28, Text, bold: true);
        heading.HorizontalAlignment = HorizontalAlignment.Center;
        heading.TextAlignment = TextAlignment.Center;
        return heading;
    }

    /// Pastille d'état à droite d'une carte (Prêts, En attente…).
    private static Border State(string text, Color tint) => new()
    {
        Padding = new Thickness(10, 3, 10, 4),
        CornerRadius = new CornerRadius(0),
        Background = Brush(WithOpacity(tint, 0.18)),
        VerticalAlignment = VerticalAlignment.Center,
        Child = Label(text, 12, tint, semibold: true),
    };

    /// Numéro d'étape dans une pastille ; coche verte une fois faite (StepBadge du Mac).
    private static Border StepBadge(int number, bool done) => new()
    {
        Width = 24,
        Height = 24,
        CornerRadius = new CornerRadius(0),
        VerticalAlignment = VerticalAlignment.Top,
        Background = Brush(done ? Green : White(0.14)),
        Child = done ? Icon("check", 12, Colors.White) : new TextBlock
        {
            Text = number.ToString(),
            FontSize = 12,
            FontWeight = Microsoft.UI.Text.FontWeights.SemiBold,
            Foreground = Brush(Text),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        },
    };

    // ---------- 1. Ports MIDI ----------

    private void ShowWelcomePorts()
    {
        _onLinkStep = false;
        var ok = MidiLink.PortsExist();
        _shownPortsOk = ok;
        _welcomeContent.Children.Clear();
        _welcomeContent.Children.Add(AppIcon(76));
        _welcomeContent.Children.Add(Heading("FL Shortcuts"));

        var row = new Grid { ColumnSpacing = 12 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.Children.Add(Tile("link", Accent, 32));
        var text = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(Label(Loc.T("Ports MIDI « FL Shortcuts »"), 13, Text, semibold: true));
        text.Children.Add(Paragraph(ok
            ? Loc.T("Prêts : « FL Shortcuts » et « FL Shortcuts Retour ».")
            : Loc.T("Dans loopMIDI : crée « FL Shortcuts » et « FL Shortcuts Retour »."), 12));
        if (!ok)
        {
            var link = new HyperlinkButton
            {
                Content = Label(Loc.T("Télécharger loopMIDI"), 12, Link),
                NavigateUri = new Uri("https://www.tobias-erichsen.de/software/loopmidi.html"),
                Padding = new Thickness(0),
            };
            text.Children.Add(link);
        }
        Grid.SetColumn(text, 1);
        row.Children.Add(text);
        var state = State(ok ? Loc.T("Prêts") : Loc.T("En attente…"), ok ? Green : Orange);
        Grid.SetColumn(state, 2);
        row.Children.Add(state);
        var card = Plate(row, 16);
        card.Padding = new Thickness(14, 12, 14, 12);
        _welcomeContent.Children.Add(card);

        var privacy = Paragraph(Loc.T("Tes touches ne sont lues que dans FL. Rien n'est gardé."), 12);
        privacy.TextAlignment = TextAlignment.Center;
        _welcomeContent.Children.Add(privacy);

        var next = Primary(ok ? Loc.T("Continuer") : Loc.T("Crée d'abord les deux ports MIDI"), () =>
        {
            if (!MidiLink.PortsExist()) return;
            _linkStep = _app.Linked ? LinkStep.Linked : LinkStep.Idle;
            ShowWelcomeLink(null);
        });
        next.IsEnabled = ok;
        next.Opacity = ok ? 1 : 0.45;
        next.HorizontalAlignment = HorizontalAlignment.Center;
        _welcomeContent.Children.Add(next);
        AddBackLink();
    }

    // ---------- 2. Relier FL Studio ----------

    private void ShowWelcomeLink(string? error)
    {
        _onLinkStep = true;
        var installed = _linkStep != LinkStep.Idle;
        var linked = _linkStep == LinkStep.Linked;
        _welcomeContent.Children.Clear();
        _welcomeContent.Children.Add(Heading(Loc.T("Relier FL Studio")));

        var steps = new (string Text, bool Done)[]
        {
            (Loc.T("Installe le lien"), installed),
            (Loc.T("Dans FL : MIDI Settings, « FL Shortcuts » : Enable et Controller type « FL Shortcuts »"), linked),
            (Loc.T("Sortie « FL Shortcuts Retour » : le même numéro de Port que l'entrée"), linked),
        };
        var list = new StackPanel { Spacing = 10 };
        for (var i = 0; i < steps.Length; i++)
        {
            var line = new Grid { ColumnSpacing = 12 };
            line.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            line.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            line.Children.Add(StepBadge(i + 1, steps[i].Done));
            var label = Paragraph(steps[i].Text, 13, Text);
            label.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(label, 1);
            line.Children.Add(label);
            AutomationProperties.SetName(line, $"{i + 1}. {steps[i].Text}");
            list.Children.Add(line);
        }
        var stepsCard = Plate(list, 16);
        stepsCard.Padding = new Thickness(16, 14, 16, 14);
        _welcomeContent.Children.Add(stepsCard);
        _welcomeContent.Children.Add(MidiPreview());

        var (icon, tint, status) = error is not null ? ("warning", Red, error)
            : linked ? ("check", Green, Loc.T("FL Studio est relié"))
            : installed ? ("warning", Orange, Loc.T("En attente de FL Studio…"))
            : ("link", Secondary, Loc.T("FL Studio pas encore relié"));
        _welcomeContent.Children.Add(Notice(icon, tint, status, null, null));

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center };
        var primary = Primary(installed ? Loc.T("Terminer") : Loc.T("Installer le lien"), () =>
        {
            if (_linkStep == LinkStep.Idle) Install(null);
            else if (_linkStep == LinkStep.Linked)
            {
                _app.CompleteOnboarding();
                BackToMain();
            }
        });
        primary.IsEnabled = !installed || linked;
        primary.Opacity = primary.IsEnabled ? 1 : 0.45;
        buttons.Children.Add(primary);
        if (linked)
            buttons.Children.Add(Soft(Loc.T("Tester"), () =>
                ShowToast(_app.TestLink() ? Loc.T("Le Mixer vient de s'ouvrir dans FL Studio.") : Loc.T("FL Studio n'a pas répondu. Vérifie MIDI Settings."))));
        if (error is not null) buttons.Children.Add(Soft(Loc.T("Choisir le dossier de FL…"), ChooseFolder));
        _welcomeContent.Children.Add(buttons);
        AddBackLink();
    }

    /// Aperçu de la fenêtre MIDI Settings de FL, les deux lignes à régler entourées.
    private static Border MidiPreview()
    {
        var orange = Rgb(0xFF, 0xB3, 0x4D);
        Border Line(string text) => new()
        {
            Padding = new Thickness(8, 4, 8, 4),
            CornerRadius = new CornerRadius(0),
            BorderBrush = Brush(orange),
            BorderThickness = new Thickness(2),
            Background = Brush(WithOpacity(orange, 0.18)),
            Child = Label(text, 11, Rgb(0xFF, 0xCF, 0x8A)),
        };
        var stack = new StackPanel { Spacing = 4, Padding = new Thickness(12, 10, 12, 12) };
        stack.Children.Add(Label("Input", 11, Rgb(0x99, 0xA4, 0xAB)));
        stack.Children.Add(Line("FL Shortcuts   ①"));
        var output = Label("Output", 11, Rgb(0x99, 0xA4, 0xAB));
        output.Margin = new Thickness(0, 4, 0, 0);
        stack.Children.Add(output);
        stack.Children.Add(Line("FL Shortcuts Retour   ②"));
        var outer = new StackPanel();
        outer.Children.Add(new Border
        {
            Background = Brush(Rgb(0x3A, 0x40, 0x46)),
            Padding = new Thickness(12, 7, 12, 7),
            CornerRadius = new CornerRadius(0),
            Child = Label("Options › MIDI Settings", 11, Rgb(0xE6, 0xEB, 0xEE), semibold: true),
        });
        outer.Children.Add(stack);
        return new Border
        {
            Child = outer,
            CornerRadius = new CornerRadius(0),
            Background = Brush(Rgb(0x2B, 0x2F, 0x33)),
            BorderBrush = Brush(LineColor),
            BorderThickness = new Thickness(1),
            MaxWidth = 360,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
    }

    private void AddBackLink()
    {
        if (!_app.Onboarded) return;
        var back = Soft(Loc.T("Retour aux raccourcis"), BackToMain);
        back.HorizontalAlignment = HorizontalAlignment.Center;
        _welcomeContent.Children.Add(back);
    }

    private void Install(string? folder)
    {
        var error = _app.InstallScript(folder);
        if (error is null) _linkStep = _app.Linked ? LinkStep.Linked : LinkStep.Waiting;
        ShowWelcomeLink(error);
    }

    private async void ChooseFolder()
    {
        var picker = new FolderPicker();
        picker.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, _hwnd);
        var folder = await picker.PickSingleFolderAsync();
        if (folder is not null) Install(folder.Path);
    }
}
