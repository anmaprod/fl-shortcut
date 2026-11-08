// Accueil Windows au même aspect que le Mac (cartes claires sur fond noir, étapes d'une ligne, bouton bleu) : 1. les
// deux ports MIDI virtuels (loopMIDI), 2. relier FL Studio (lien installé, MIDI Settings). Mode léger (08/11, « quand
// tu ouvres FL Shortcuts… en plus ça demande d'installer loopMIDI avec un bouton ») : la page 1 seule, au premier
// lancement, avec « Télécharger loopMIDI » et « Continuer » toujours possible. « Réparer » (bandeau de la fenêtre) y
// ramène, avec « Retour aux raccourcis ».
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
            if (_shownPortsOk != MidiLink.PortsUsable()) ShowWelcomePorts();
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

    /// Le rond de l'accueil (05/11, « je veux que tu remettes le rond », comme le Mac) : le grand cercle décalé à
    /// l'encre, un jour, le rond rouge ; sous Orange, le rond a un trait noir et son ombre noire décalée, comme les
    /// boutons. Dessiné sur une toile de 1024 ramenée à `size`.
    private static FrameworkElement BrandRound(double size)
    {
        var canvas = new Canvas { Width = 1024, Height = 1024 };
        var orange = Theme == AppTheme.Orange;
        Microsoft.UI.Xaml.Shapes.Ellipse Circle(double cx, double cy, double r)
        {
            var e = new Microsoft.UI.Xaml.Shapes.Ellipse { Width = 2 * r, Height = 2 * r };
            Canvas.SetLeft(e, cx - r);
            Canvas.SetTop(e, cy - r);
            canvas.Children.Add(e);
            return e;
        }
        var ring = Circle(590, 440, 365);
        ring.Stroke = Brush(Text);
        ring.StrokeThickness = 70;
        Circle(470, 580, 345).Fill = Brush(WindowColor);
        if (orange) Circle(510, 620, 290).Fill = Brush(Colors.Black);
        var dot = Circle(470, 580, 290);
        dot.Fill = Brush(BrandRed);
        if (orange)
        {
            dot.Stroke = Brush(Colors.Black);
            dot.StrokeThickness = 40;
        }
        var logo = new Viewbox { Width = size, Height = size, Child = canvas, HorizontalAlignment = HorizontalAlignment.Center };
        AutomationProperties.SetAccessibilityView(logo, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        return logo;
    }

    /// Titre de l'accueil (maquette du 05/11, comme le Mac) : en minuscules, suivi de son point carré, à gauche.
    private static FrameworkElement Heading(string text, double size = 40)
    {
        var heading = SwissTitle(size);
        heading.Text = text.ToLower(System.Globalization.CultureInfo.CurrentCulture);
        var line = PageTitle(heading, size);
        line.HorizontalAlignment = HorizontalAlignment.Left;
        return line;
    }

    /// En tête de l'accueil (maquette) : le rond et « fl shortcuts » en très grand avec son point carré.
    private static FrameworkElement WelcomeHead()
    {
        var head = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 18, HorizontalAlignment = HorizontalAlignment.Left };
        var icon = BrandRound(76);
        icon.VerticalAlignment = VerticalAlignment.Bottom;
        head.Children.Add(icon);
        head.Children.Add(Heading("FL Shortcuts", 60));
        return head;
    }

    /// Carte de l'accueil (maquette) : pleine du fond, un trait fin autour.
    private static Border WelcomeCard(UIElement child) => new()
    {
        Child = child,
        Padding = new Thickness(20, 12, 20, 12),
        Background = Brush(MacLook.WindowColor),
        BorderBrush = Brush(LineColor),
        BorderThickness = new Thickness(1),
    };

    /// Pastille d'état à droite d'une carte (Prêts, En attente…).
    /// État au style suisse (maquette) : en petites capitales dans un cadre de 2 points ; fait : à l'encre ; à faire :
    /// plein de rouge.
    private static Border State(string text, Color tint)
    {
        var done = tint == Green;
        return new Border
        {
            Padding = new Thickness(12, 6, 12, 6),
            CornerRadius = new CornerRadius(0),
            Background = Brush(done ? Colors.Transparent : Red),
            BorderBrush = Brush(done ? Text : Red),
            BorderThickness = new Thickness(2),
            VerticalAlignment = VerticalAlignment.Center,
            Child = SwissLabel(text, 11, done ? Text : MacLook.OnRed),
        };
    }

    /// Numéro d'étape dans une pastille ; coche verte une fois faite (StepBadge du Mac).
    private static Border StepBadge(int number, bool done) => new()
    {
        Width = 24,
        Height = 24,
        CornerRadius = new CornerRadius(0),
        VerticalAlignment = VerticalAlignment.Top,
        Background = Brush(done ? Text : Colors.Transparent),
        BorderBrush = Brush(Text),
        BorderThickness = new Thickness(done ? 0 : 1),
        Child = done ? Icon("check", 12, MacLook.WindowColor) : new TextBlock
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

    /// Page de téléchargement de loopMIDI (gratuit, Tobias Erichsen).
    private const string LoopMidiPage = "https://www.tobias-erichsen.de/software/loopmidi.html";

    private void ShowWelcomePorts()
    {
        _onLinkStep = false;
        var exist = MidiLink.PortsExist();
        // Windows 25H2, ou loopMIDI installé (son pilote) : l'appli crée les ports quand le lien sert.
        var ok = exist || MidiServicesPorts.Available;
        var light = _app.Light;
        _shownPortsOk = ok;
        _welcomeContent.Children.Clear();
        _welcomeContent.Children.Add(WelcomeHead());

        var row = new Grid { ColumnSpacing = 12, MinHeight = 64 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var text = new StackPanel { Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(Label(Loc.T("Ports MIDI « FL Shortcuts »"), 18, Text, bold: true));
        text.Children.Add(Paragraph(ok
            ? (exist && !MidiServicesPorts.CreatedByWindows ? Loc.T("Prêts : « FL Shortcuts » et « FL Shortcuts Retour ».")
                                                             : Loc.T("Prêts : l'app crée les ports elle-même."))
            : Loc.T("Installe loopMIDI. L'app crée ensuite les ports elle-même."), 12));
        if (!ok)
        {
            // Un vrai bouton (08/11) : la page de téléchargement de loopMIDI dans le navigateur.
            var download = Soft(Loc.T("Télécharger loopMIDI"), () =>
            {
                try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(LoopMidiPage) { UseShellExecute = true }); }
                catch (Exception e) { AppLog.Write("STATUS", "page loopMIDI non ouverte (" + e.GetType().Name + ")"); }
            });
            download.HorizontalAlignment = HorizontalAlignment.Left;
            download.Margin = new Thickness(0, 4, 0, 0);
            text.Children.Add(download);
        }
        row.Children.Add(text);
        var state = State(ok ? Loc.T("Prêts") : light ? Loc.T("À installer") : Loc.T("En attente…"), ok ? Green : Orange);
        Grid.SetColumn(state, 1);
        row.Children.Add(state);
        _welcomeContent.Children.Add(WelcomeCard(row));

        _welcomeContent.Children.Add(Paragraph(Loc.T("Tes touches ne sont lues que dans FL. Rien n'est gardé."), 12));

        // Mode léger : loopMIDI ne sert qu'à l'Organiser et aux actions de FL ; on peut continuer sans lui.
        var next = Primary(ok || light ? Loc.T("Continuer") : Loc.T("Crée d'abord les deux ports MIDI"), () =>
        {
            if (light)
            {
                _app.LoopMidiSeen();
                ShowScreen();
                return;
            }
            if (!MidiLink.PortsUsable()) return;
            _linkStep = _app.Linked ? LinkStep.Linked : LinkStep.Idle;
            ShowWelcomeLink(null);
        });
        next.IsEnabled = ok || light;
        next.Opacity = ok || light ? 1 : 0.45;
        next.HorizontalAlignment = HorizontalAlignment.Right;
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
        var stepsCard = WelcomeCard(list);
        stepsCard.Padding = new Thickness(18, 16, 18, 16);
        _welcomeContent.Children.Add(stepsCard);
        _welcomeContent.Children.Add(MidiPreview());

        var (icon, tint, status) = error is not null ? ("warning", Red, error)
            : linked ? ("check", Green, Loc.T("FL Studio est relié"))
            : installed ? ("warning", Orange, Loc.T("En attente de FL Studio…"))
            : ("link", Secondary, Loc.T("FL Studio pas encore relié"));
        _welcomeContent.Children.Add(Notice(icon, tint, status, null, null));

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Right };
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
        if (!_app.Onboarded || _photos) return;
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
