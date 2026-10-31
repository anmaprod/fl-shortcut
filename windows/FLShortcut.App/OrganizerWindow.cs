// La fenêtre de l'Organiser sur Windows, à l'identique du Mac (29/10 : « exactement la même interface sur win ») :
// fond noir plein, le titre seul, une carte par étape (pastille de couleur, phrase courte), boutons en capsule (bleu pour
// l'action). Mêmes étapes et mêmes textes que Sources/FLShortcut/OrganizerWindow.swift ; le contrôleur est celui du cœur
// (OrganizerController, testé). Tuto en images à la première ouverture (avant l'écoute), lien à installer, attente de
// FL (nouvel essai tout seul), écoute, aperçu (familles sur deux colonnes dès 600 points : poignée, couleur, nom,
// départ dans le Mixer, puis ses sons : ancien nom → nouveau nom ▾, case du Mixer tirée comme dans FL ; « Rangement
// automatique » et « Options » en haut), « Organiser », « Revenir comme avant », « Pas content ? ». Toujours devant FL ;
// construite en code (pas de XAML) ; la hauteur suit le contenu (l'aperçu prend la sienne).
using FLShortcut.App.Native;
using FLShortcut.App.Services;
using FLShortcut.Core;
using FLShortcut.Core.Organizer;
using Microsoft.UI;
using Microsoft.UI.Input;
using Microsoft.UI.Text;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Microsoft.UI.Xaml.Shapes;
using Windows.ApplicationModel.DataTransfer;
using Windows.System;
using Windows.UI;
using Windows.UI.Core;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal sealed class OrganizerWindow : Window
{
    private static OrganizerWindow? _open;

    /// L'Organiser est ouvert (la question de validation attend sa fermeture).
    public static bool IsOpen => _open is not null;

    /// Appelé une fois l'Organiser fermé (la question de validation de la version organisée).
    public static event Action? OrganizerClosed;

    public static void Show(AppController app)
    {
        if (_open is { } shown)
        {
            shown.Activate();
            return;
        }
        _open = new OrganizerWindow(app);
        _open.Activate();
    }

    /// Couleur de l'Organiser (l'indigo du Mac).
    private static readonly Color Tint = Indigo;
    private const string DragPrefix = "organiser-famille:";
    /// Largeur à l'ouverture (comme le Mac) et largeur à partir de laquelle les familles passent sur deux colonnes.
    private const double StartWidth = 720;
    private const double TwoColumns = 600;
    private const double PreviewHeight = 720;

    /// Les pages du tuto (comme OrganizerTutorial du Mac) : une image, un titre, une phrase.
    private static (string Title, string Text)[] TutorialPages => new[]
    {
        (Loc.T("Ouvre ton projet dans FL"), Loc.T("Puis menu de l'icône › Organiser…")),
        (Loc.T("Il écoute chaque son"), Loc.T("Ne touche pas à FL pendant l'écoute.")),
        (Loc.T("Vérifie le rangement"), Loc.T("Change une famille, un nom ou une piste si tu veux.")),
        (Loc.T("Une copie rangée"), Loc.T("Ton projet ne bouge pas : tu valides la copie, ou tu reviens en arrière.")),
    };

    private readonly AppController _app;
    private readonly OrganizerController _controller;
    private readonly IntPtr _hwnd;
    private readonly bool _demo;
    // Créés dans le constructeur, APRÈS celui de Window : un élément de XAML créé avant (initialiseur de champ) fait
    // tomber WinUI quand c'est la première fenêtre (CI, mode photos : 0xC000027B dans Microsoft.UI.Xaml.dll).
    private readonly Grid _root;
    private readonly TextBlock _title;
    private readonly StackPanel _headerTools;
    private readonly StackPanel _content;
    private readonly ScrollViewer _scroll;
    private readonly Border _footer;
    private readonly StackPanel _left;
    private readonly StackPanel _right;
    private bool _closing;
    private SoundFamily? _dragging;
    private bool _tutorial;
    private int _tutorialPage;
    private bool _startAfterTutorial;
    private bool _fitQueued;
    private int _columns = 2;

    /// Mode photos (CI) : un écran donné, avec des sons d'exemple ; rien n'est envoyé à FL.
    public static OrganizerWindow Demo(AppController app, string screen) => new(app, screen);

    private OrganizerWindow(AppController app, string? demo = null)
    {
        Photos.Note("fenêtre : constructeur");
        _app = app;
        _demo = demo is not null;
        _content = new StackPanel { Spacing = 12 };
        _left = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        _right = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Right };
        _headerTools = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Center };
        _title = Label(Loc.T("Organiser"), 20, Text, bold: true);
        _scroll = new ScrollViewer { Content = _content, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
        _footer = new Border { Padding = new Thickness(0, 12, 0, 0) };
        _root = new Grid { Padding = new Thickness(22, 34, 22, 20), RowSpacing = 16 };
        Photos.Note("fenêtre : panneaux");
        _hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        Title = Loc.T("Organiser");

        // Fond noir plein et barre de titre dans la fenêtre (comme le Mac, sans Mica ni Liquid Glass).
        ExtendsContentIntoTitleBar = true;
        if (AppWindowTitleBar.IsCustomizationSupported())
        {
            var bar = AppWindow.TitleBar;
            bar.ButtonBackgroundColor = Colors.Transparent;
            bar.ButtonInactiveBackgroundColor = Colors.Transparent;
            bar.ButtonForegroundColor = Text;
            bar.ButtonInactiveForegroundColor = Secondary;
            bar.ButtonHoverBackgroundColor = White(0.1);
            bar.ButtonHoverForegroundColor = Colors.White;
            bar.ButtonPressedBackgroundColor = White(0.18);
            bar.ButtonPressedForegroundColor = Colors.White;
        }
        var scale = Win32.GetDpiForWindow(_hwnd) / 96.0;
        AppWindow.Resize(new Windows.Graphics.SizeInt32((int)(StartWidth * scale), (int)(420 * scale)));
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsAlwaysOnTop = true;              // reste visible pendant que FL est devant
            presenter.IsMinimizable = false;
        }

        Photos.Note("fenêtre : taille");
        var page = new Grid { Background = Brush(WindowColor), RequestedTheme = ElementTheme.Dark };
        var dragBar = new Border { Height = 32, VerticalAlignment = VerticalAlignment.Top, Background = Brush(Colors.Transparent) };
        _root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        _root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        _root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var header = new Grid();
        header.Children.Add(_title);
        header.Children.Add(_headerTools);
        var footer = new Grid();
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        footer.Children.Add(_left);
        Grid.SetColumn(_right, 1);
        footer.Children.Add(_right);
        _footer.Child = footer;
        Grid.SetRow(_scroll, 1);
        Grid.SetRow(_footer, 2);
        _root.Children.Add(header);
        _root.Children.Add(_scroll);
        _root.Children.Add(_footer);
        page.Children.Add(_root);
        page.Children.Add(dragBar);
        Content = page;
        SetTitleBar(dragBar);
        _scroll.SizeChanged += (_, e) =>
        {
            var columns = e.NewSize.Width >= TwoColumns ? 2 : 1;
            if (columns == _columns) return;
            _columns = columns;
            if (_controller?.Phase is OrganizerPhase.Preview && !_tutorial) Render();
        };
        Photos.Note("fenêtre : contenu");

        _controller = new OrganizerController(OrganizerLive.Make(app, DispatcherQueue, ChooseProject, InstallElsewhere));
        _controller.Changed += Render;
        _controller.OnClose = () =>
        {
            if (!_closing) Close();
        };
        Closed += (_, _) =>
        {
            _closing = true;
            _controller.Close();
            _open = null;
            OrganizerClosed?.Invoke();
        };
        // Tuto en images la première fois, avant l'écoute (rien n'est envoyé à FL tant qu'il est là).
        _tutorial = demo == "tuto" || (demo is null && !app.Settings.OrganizerTutorialSeen);
        _startAfterTutorial = _tutorial && demo is null;
        Render();
        Photos.Note("fenêtre : premier dessin");
        if (demo is null)
        {
            if (!_tutorial) _controller.Start();
        }
        else if (demo != "tuto") _controller.ShowDemo(demo);
        Photos.Note("fenêtre : prête");
    }

    // ---------- Petits morceaux ----------

    private static SolidColorBrush Fill(RgbColor c) => new(Color.FromArgb(0xFF, c.R, c.G, c.B));

    private static Color ColorOf(RgbColor c) => Color.FromArgb(0xFF, c.R, c.G, c.B);

    /// Carte de l'Organiser : plaque claire dessinée, liseré de sa couleur ; pas de survol (une carte n'est pas une option).
    private static Border Card(UIElement child, Color? tint = null, double padding = 14) => new()
    {
        Child = child,
        Padding = new Thickness(padding),
        CornerRadius = new CornerRadius(14),
        Background = Gradient(White(0.10), White(0.045)),
        BorderBrush = Brush(WithOpacity(tint ?? Tint, 0.4)),
        BorderThickness = new Thickness(1),
    };

    /// Pastille ronde de couleur avec son dessin blanc (résultat, écoute, attente).
    private static Grid Badge(string icon, Color tint, double size = 34)
    {
        var grid = new Grid { Width = size, Height = size, VerticalAlignment = VerticalAlignment.Center };
        grid.Children.Add(new Ellipse { Fill = Gradient(Mix(tint, Colors.White, 0.18), tint) });
        var glyph = Icon(icon, size * 0.46, Colors.White, tint);
        glyph.HorizontalAlignment = HorizontalAlignment.Center;
        glyph.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(glyph);
        return grid;
    }

    /// Une ligne : une pastille (ou une icône), puis le texte qui prend la place.
    private static Grid Row(UIElement first, UIElement rest, double spacing = 12)
    {
        var grid = new Grid { ColumnSpacing = spacing };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        if (first is FrameworkElement f) f.VerticalAlignment = VerticalAlignment.Center;
        if (rest is FrameworkElement r) r.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(first);
        Grid.SetColumn((FrameworkElement)rest, 1);
        grid.Children.Add(rest);
        return grid;
    }

    private static StackPanel Stack(double spacing, params UIElement[] children)
    {
        var stack = new StackPanel { Spacing = spacing };
        foreach (var child in children) stack.Children.Add(child);
        return stack;
    }

    /// Bouton secondaire (capsule claire) ; éteint : à demi transparent.
    private static Button SoftButton(string text, Action click, string? tip = null, bool enabled = true)
    {
        var button = Soft(text, click);
        button.IsEnabled = enabled;
        if (!enabled) button.Opacity = 0.45;
        if (tip is not null) ToolTipService.SetToolTip(button, tip);
        AutomationProperties.SetName(button, text);
        return button;
    }

    private static Button BlueButton(string text, Action click)
    {
        var button = Primary(text, click);
        AutomationProperties.SetName(button, text);
        return button;
    }

    private static ProgressRing Spinner(double size = 18) => new()
    {
        IsActive = true, Width = size, Height = size, Foreground = Brush(Tint), VerticalAlignment = VerticalAlignment.Center,
    };

    private static TextBlock Note(string text, Color? color = null) => Paragraph(text, 11, color ?? Secondary);

    // ---------- Les étapes ----------

    private void Render()
    {
        if (_closing) return;
        _content.Children.Clear();
        _left.Children.Clear();
        _right.Children.Clear();
        _headerTools.Children.Clear();
        _title.Text = _controller.Title;
        var preview = _controller.Phase is OrganizerPhase.Preview && !_tutorial;
        // Aperçu : un trait fin au-dessus des boutons (comme le Mac).
        _footer.BorderThickness = new Thickness(0, preview ? 1 : 0, 0, 0);
        _footer.BorderBrush = Brush(White(0.08));
        if (_tutorial)
        {
            Tutorial();
            FitSoon();
            return;
        }
        switch (_controller.Phase)
        {
            case OrganizerPhase.Starting:
                Working(Loc.T("Préparation…"));
                break;
            case OrganizerPhase.Setup:
                Setup();
                break;
            case OrganizerPhase.Waiting w:
                Waiting(w.Reason);
                break;
            case OrganizerPhase.Listening l:
                Listening(l.Done, l.Total);
                break;
            case OrganizerPhase.Preview:
                Preview();
                break;
            case OrganizerPhase.Applying:
                Working(ApplyingText());
                break;
            case OrganizerPhase.Undoing:
                Working(Loc.T("Retour comme avant…"));
                break;
            case OrganizerPhase.Applied a:
                Ending(a.Error?.UserMessage ?? _controller.DoneText, a.Error is null, a.Error?.Is(OrganizerError.Kinds.NoResponse) == true);
                break;
            case OrganizerPhase.Undone u:
                Ending(u.Error?.UserMessage ?? (_controller.LastApply?.Copy is not null
                        ? Loc.T("Ton projet d'origine se rouvre dans FL, tel qu'il était. La copie rangée part à la Corbeille dès que FL l'a quittée.")
                        : Loc.T("FL est revenu comme avant.")),
                    u.Error is null, u.Error?.Is(OrganizerError.Kinds.NoResponse) == true);
                break;
            case OrganizerPhase.Failed f:
                Ending(f.Message, false, false);
                break;
        }
        FitSoon();
    }

    /// La hauteur de la fenêtre suit son contenu (comme le Mac) ; l'aperçu prend la sienne, la liste défile.
    private void FitSoon()
    {
        if (_fitQueued) return;
        _fitQueued = true;
        DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () =>
        {
            _fitQueued = false;
            Fit();
        });
    }

    private void Fit()
    {
        if (_closing) return;
        var scale = Win32.GetDpiForWindow(_hwnd) / 96.0;
        var width = AppWindow.ClientSize.Width / scale;
        double height;
        if (_controller.Phase is OrganizerPhase.Preview && !_tutorial) height = Math.Max(PreviewHeight, AppWindow.ClientSize.Height / scale);
        else
        {
            _root.Measure(new Windows.Foundation.Size(width, double.PositiveInfinity));
            height = Math.Clamp(_root.DesiredSize.Height, 160, 900);
        }
        var target = (int)Math.Round(height * scale);
        if (Math.Abs(target - AppWindow.ClientSize.Height) <= 2) return;
        AppWindow.ResizeClient(new Windows.Graphics.SizeInt32(AppWindow.ClientSize.Width, target));
    }

    private string ApplyingText()
    {
        var hands = Loc.T("Ne touche pas à FL.");
        if (_controller.ApplyStep is { } step) return step + " " + hands;
        return _controller.OrganizesCopy
            ? Loc.T("FL ouvre la copie rangée de ton projet, puis tout s'y range… Ne touche pas à FL.")
            : Loc.T("Application dans FL… Ne touche pas à FL.");
    }

    private void Working(string text)
    {
        _content.Children.Add(Card(Row(Spinner(), Label(text, 13, Text))));
    }

    /// Lien avec FL pas encore installé : un seul bouton, la suite se fait toute seule.
    private void Setup()
    {
        _content.Children.Add(Card(Row(Badge("link", Tint), Label(Loc.T("Un petit lien avec FL, une seule fois"), 14, Text, semibold: true), 14)));
        PortsCard();
        _right.Children.Add(SoftButton(Loc.T("Fermer"), _controller.Close));
        _right.Children.Add(BlueButton(Loc.T("Installer le lien"), _controller.InstallLink));
    }

    /// Les deux ports MIDI de loopMIDI manquent (Windows seulement) : rien ne peut passer entre FL Shortcuts et FL.
    private void PortsCard()
    {
        if (MidiLink.PortsExist()) return;
        var link = new HyperlinkButton
        {
            Content = Label(Loc.T("Télécharger loopMIDI"), 12, Link),
            NavigateUri = new Uri("https://www.tobias-erichsen.de/software/loopmidi.html"),
            Padding = new Thickness(0),
        };
        _content.Children.Add(Card(Row(Badge("exclamationmark", Orange), Stack(4,
            Label(Loc.T("Crée d'abord les deux ports MIDI"), 14, Text, semibold: true),
            Paragraph(Loc.T("Ouvre loopMIDI et crée deux ports nommés exactement « FL Shortcuts » et « FL Shortcuts Retour » (loopMIDI doit rester ouvert). FL Shortcuts les voit tout seul."), 12),
            link), 14), Orange));
    }

    private static (string Icon, string Title, string Detail) WaitText(OrganizerWait reason) => reason switch
    {
        OrganizerWait.RestartFl => ("arrow.clockwise", Loc.T("Quitte et rouvre FL Studio"),
            Loc.T("Le lien est prêt : FL le lit en démarrant. Dans FL : Options › MIDI Settings, entrée « FL Shortcuts » sur le Controller type « FL Shortcuts », et la sortie « FL Shortcuts Retour » sur le même numéro de Port.")),
        OrganizerWait.NoResponse => ("antenna.radiowaves.left.and.right", Loc.T("En attente de FL Studio"),
            Loc.T("FL ne répond pas encore. Dans FL › Options › MIDI Settings › Output, « FL Shortcuts » doit s'afficher à côté de « FL Shortcuts Retour », seul sur son Port. Sinon : « Ça ne marche toujours pas ? » ci-dessous.")),
        OrganizerWait.WrongInput => ("link", Loc.T("Le lien est sur la mauvaise entrée"),
            Loc.T("Dans FL : Options › MIDI Settings › Input, ta carte son (ou ton clavier) a le Controller type « FL Shortcuts ». Remets-la sur « (generic controller) », puis clique la ligne « FL Shortcuts » et choisis « FL Shortcuts ».")),
        OrganizerWait.OpenFl => ("macwindow", Loc.T("Ouvre FL Studio"), Loc.T("Organiser commence dès que FL est ouvert, avec ton projet.")),
        _ => ("stop.fill", Loc.T("Arrête la lecture dans FL"), Loc.T("Organiser écoute chaque son seul : FL doit être à l'arrêt.")),
    };

    /// En attente de FL : ce qu'il faut faire, en une phrase ; Organiser vérifie tout seul et continue dès que c'est
    /// bon. FL muet : l'aide détaillée, repliée.
    private void Waiting(OrganizerWait reason)
    {
        var (icon, title, detail) = WaitText(reason);
        var tint = reason == OrganizerWait.StopPlayback ? Orange : Tint;
        _content.Children.Add(Card(Row(Badge(icon, tint), Stack(4, Label(title, 14, Text, semibold: true), Paragraph(detail, 12)), 16), tint));
        _content.Children.Add(Row(Spinner(14), Note(Loc.T("Organiser continue tout seul dès que FL est prêt.")), 8));
        if (reason is OrganizerWait.NoResponse or OrganizerWait.RestartFl or OrganizerWait.WrongInput)
        {
            PortsCard();
            _content.Children.Add(LinkHelpToggle());
            if (_controller.ShowLinkHelp) LinkHelp();
        }
        _left.Children.Add(DiagnosticButton());
        _right.Children.Add(SoftButton(Loc.T("Fermer"), _controller.Close));
        _right.Children.Add(SoftButton(Loc.T("Réessayer maintenant"), _controller.Retry));
    }

    /// « Ça ne marche toujours pas ? » : les réglages de FL à vérifier, repliés tant qu'on ne les demande pas.
    private Button LinkHelpToggle()
    {
        var chevron = Icon(_controller.ShowLinkHelp ? "chevron.down" : "chevron.right", 10, Tint);
        chevron.VerticalAlignment = VerticalAlignment.Center;
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        row.Children.Add(chevron);
        row.Children.Add(Label(Loc.T("Ça ne marche toujours pas ?"), 12, Tint, semibold: true));
        var toggle = new Button { Style = PlainButton, Content = row, HorizontalAlignment = HorizontalAlignment.Left, Padding = new Thickness(0, 2, 0, 2) };
        toggle.Click += (_, _) =>
        {
            _controller.ShowLinkHelp = !_controller.ShowLinkHelp;
            Render();
        };
        AutomationProperties.SetName(toggle, Loc.T("Ça ne marche toujours pas ?"));
        return toggle;
    }

    /// Les réglages à vérifier, étape par étape, et où est le script.
    private void LinkHelp()
    {
        _content.Children.Add(Step(1, Loc.T("Dans loopMIDI : deux ports, « FL Shortcuts » et « FL Shortcuts Retour ». loopMIDI doit rester ouvert (il peut se lancer avec Windows).")));
        _content.Children.Add(Step(2, Loc.T("Dans FL : Options › MIDI Settings › Input, clique d'abord la ligne « FL Shortcuts » (le Controller type, en bas, change la ligne choisie), puis Controller type « FL Shortcuts », Enable, et un numéro de Port (7 par exemple). Ta carte son ou ton clavier MIDI restent sur « (generic controller) ».")));
        _content.Children.Add(Step(3, Loc.T("Dans Output : « FL Shortcuts Retour » sur ce même Port, et SEUL sur ce numéro. C'est bon quand « FL Shortcuts » s'affiche à côté de « FL Shortcuts Retour ». Puis quitte et rouvre FL.")));
        _content.Children.Add(Step(4, Loc.T("« FL Shortcuts » absent des Controller types : FL ne lit pas le dossier du script ci-dessous. Compare-le avec Options › File settings › User data folder dans FL ; s'il diffère, « Autre dossier de FL… » et choisis son dossier « Settings\\Hardware ».")));
        ScriptCard();
    }

    /// Une étape numérotée, dans une carte (comme OrganizerStep du Mac).
    private static Border Step(int n, string text)
    {
        var number = new Grid { Width = 22, Height = 22, VerticalAlignment = VerticalAlignment.Top };
        number.Children.Add(new Ellipse { Fill = Gradient(Mix(Tint, Colors.White, 0.18), Tint) });
        number.Children.Add(new TextBlock
        {
            Text = n.ToString(System.Globalization.CultureInfo.InvariantCulture), FontSize = 11, FontWeight = FontWeights.Bold,
            Foreground = Brush(Colors.White), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
        });
        var row = new Grid { ColumnSpacing = 10 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.Children.Add(number);
        var label = Paragraph(text, 12, Text);
        Grid.SetColumn(label, 1);
        row.Children.Add(label);
        var card = Card(row);
        card.Padding = new Thickness(12, 10, 12, 10);
        return card;
    }

    /// Où est le script du lien, avec « Afficher dans l'Explorateur » et « Autre dossier de FL… ».
    private void ScriptCard()
    {
        var place = _controller.ScriptPlace;
        var present = place?.Present == true;
        var tint = present ? Tint : Orange;
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        if (present) buttons.Children.Add(SoftButton(Loc.T("Afficher dans l'Explorateur"), _controller.RevealScript));
        buttons.Children.Add(SoftButton(Loc.T("Autre dossier de FL…"), _controller.InstallLinkElsewhere));
        var where = place is { } p ? System.IO.Path.GetDirectoryName(p.Path) ?? p.Path : Loc.T("Aucun dossier enregistré.");
        var path = Paragraph(where, 11);
        path.IsTextSelectionEnabled = true;
        var icon = Icon(present ? "doc.text.fill" : "browser", 15, tint, WindowColor);
        icon.VerticalAlignment = VerticalAlignment.Top;
        var head = Row(icon, Stack(2, Label(present ? Loc.T("Script du lien") : Loc.T("Script introuvable dans FL Studio"), 12, Text, semibold: true), path), 10);
        icon.VerticalAlignment = VerticalAlignment.Top;
        _content.Children.Add(Card(Stack(8, head, buttons), tint, 12));
    }

    private void Listening(int done, int total)
    {
        var title = total == 0 ? Loc.T("Préparation de l'analyse…") : Loc.F("Analyse du projet : %lld sur %lld", Math.Min(done + 1, total), total);
        var head = new Grid();
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        head.Children.Add(Label(title, 13, Text, semibold: true));
        if (total > 0)
        {
            var percent = Label($"{Math.Round(done * 100.0 / Math.Max(total, 1))} %", 12, Secondary);
            Grid.SetColumn(percent, 1);
            head.Children.Add(percent);
        }
        var bar = new ProgressBar
        {
            Maximum = Math.Max(total, 1), Value = done, IsIndeterminate = total == 0,
            Foreground = Brush(Tint), Background = Brush(White(0.12)), MinHeight = 6,
        };
        _content.Children.Add(Card(Row(Badge("waveform", Tint), Stack(8, head, bar))));
        // Plus d'explication (comme le Mac, 28/10) : la consigne seule.
        _content.Children.Add(Note(Loc.T("Ne touche pas à FL.")));
        _right.Children.Add(SoftButton(Loc.T("Arrêter"), _controller.Close));
    }

    /// Fin d'une étape : le message dans une carte (coche verte ou point d'exclamation orange) ; FL muet : les
    /// réglages de FL à vérifier, étape par étape.
    private void Ending(string text, bool ok, bool linkHelp)
    {
        var tint = ok ? Green : Orange;
        _content.Children.Add(Card(Row(Badge(ok ? "check" : "exclamationmark", tint), Paragraph(text, 13, Text)), tint));
        if (linkHelp) LinkHelp();
        if (_controller.CanUndo) _left.Children.Add(SoftButton(Loc.T("Revenir comme avant"), _controller.Undo));
        else if (_controller.Phase is OrganizerPhase.Failed || _controller.Phase is OrganizerPhase.Applied { Error: not null })
            _left.Children.Add(DiagnosticButton());
        if (_controller.CanGiveFeedback)
            _left.Children.Add(SoftButton(Loc.T("Pas content ?"), ShowFeedback, Loc.T("Dis ce qui n'allait pas : l'IA apprend de ses erreurs")));
        if (_controller.CanRetry && _controller.ProjectMissing)
        {
            _right.Children.Add(SoftButton(Loc.T("Fermer"), _controller.Close));
            _right.Children.Add(SoftButton(Loc.T("Réessayer"), _controller.Retry));
            _right.Children.Add(BlueButton(Loc.T("Choisir le fichier…"), _controller.ChooseProject));
        }
        else if (_controller.CanRetry)
        {
            _right.Children.Add(SoftButton(Loc.T("Fermer"), _controller.Close));
            _right.Children.Add(BlueButton(Loc.T("Réessayer"), _controller.Retry));
        }
        else
        {
            _right.Children.Add(BlueButton(Loc.T("Fermer"), _controller.Close));
        }
    }

    private Button DiagnosticButton() => SoftButton(_controller.Copied ? Loc.T("Copié") : Loc.T("Copier le diagnostic"), _controller.CopyDiagnostic,
        Loc.T("Copie un court texte technique (versions, autorisations, ce que l'écoute a reçu), sans aucun nom de son ni de piste : colle-le dans ton message pour qu'on trouve ce qui bloque."));

    // ---------- Le tuto ----------

    /// Une page du tuto : l'image en grand, son titre et sa phrase, les points de page, « Passer » et « Suivant »
    /// (« C'est parti » sur la dernière). Vu une fois : plus montré tout seul.
    private void Tutorial()
    {
        var pages = TutorialPages;
        var index = Math.Clamp(_tutorialPage, 0, pages.Length - 1);
        var last = index == pages.Length - 1;
        var picture = new Border
        {
            CornerRadius = new CornerRadius(14),
            BorderBrush = Brush(White(0.10)),
            BorderThickness = new Thickness(1),
            Background = Brush(White(0.06)),
        };
        if (TutorialImage(index + 1) is { } bitmap)
            picture.Child = new Image { Source = bitmap, Stretch = Stretch.Uniform };
        else
            picture.Height = 300;
        _content.Children.Add(picture);
        _content.Children.Add(Stack(4, Label(pages[index].Title, 17, Text, bold: true), Paragraph(pages[index].Text, 13)));

        var dots = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
        for (var i = 0; i < pages.Length; i++)
            dots.Children.Add(new Ellipse { Width = 7, Height = 7, Fill = Brush(i == index ? Accent : White(0.25)) });
        AutomationProperties.SetName(dots, Loc.F("Page %lld sur %lld", index + 1, pages.Length));
        _left.Children.Add(dots);
        if (!last) _right.Children.Add(SoftButton(Loc.T("Passer"), FinishTutorial));
        _right.Children.Add(BlueButton(last ? Loc.T("C'est parti") : Loc.T("Suivant"), () =>
        {
            if (last) FinishTutorial();
            else
            {
                _tutorialPage++;
                Render();
            }
        }));
    }

    /// L'image d'une page, dans la langue de l'app (embarquée dans l'exécutable) ; null si elle manque.
    private static BitmapImage? TutorialImage(int n)
    {
        try
        {
            var name = $"OrganiserTuto{n}-{(Loc.English ? "en" : "fr")}.png";
            using var stream = typeof(OrganizerWindow).Assembly.GetManifestResourceStream(name);
            if (stream is null) return null;
            var memory = new MemoryStream();
            stream.CopyTo(memory);
            memory.Position = 0;
            var bitmap = new BitmapImage();
            bitmap.SetSource(memory.AsRandomAccessStream());
            return bitmap;
        }
        catch (Exception)
        {
            return null;
        }
    }

    private void FinishTutorial()
    {
        _tutorial = false;
        _tutorialPage = 0;
        if (!_demo && !_app.Settings.OrganizerTutorialSeen)
        {
            _app.Settings.OrganizerTutorialSeen = true;
            _app.Settings.Save();
        }
        if (_startAfterTutorial)
        {
            _startAfterTutorial = false;
            _controller.Start();
        }
        Render();
    }

    /// « Revoir le tuto » (Options de l'aperçu) : l'aperçu revient ensuite tel quel.
    private void ShowTutorialAgain()
    {
        _tutorial = true;
        _tutorialPage = 0;
        _startAfterTutorial = false;
        Render();
    }

    // ---------- L'aperçu ----------

    private void Preview()
    {
        // En haut, à droite du titre : « Rangement automatique » et « Options » (maquette du 28/10).
        if (_controller.Options.Mixer)
            _headerTools.Children.Add(SoftButton(Loc.T("Rangement automatique"), _controller.AutoArrange,
                Loc.T("Oublie les places choisies : chaque famille à la suite, dans l'ordre du Channel rack"), _controller.PlacesChosen));
        _headerTools.Children.Add(OptionsButton());

        var colors = _controller.PlannedColors;
        var families = _controller.PresentFamilies.ToList();
        var columns = OrganizerController.FamilyColumns(families, _columns, f => _controller.Members(f).Count);
        var grid = new Grid { ColumnSpacing = 18 };
        for (var i = 0; i < columns.Count; i++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var stack = new StackPanel { Spacing = 14 };
            foreach (var family in columns[i]) stack.Children.Add(FamilySection(family, colors));
            Grid.SetColumn(stack, i);
            grid.Children.Add(stack);
        }
        _content.Children.Add(grid);
        if (_controller.PlaylistTooBig)
        {
            var warn = Icon("warning", 12, Orange, WindowColor);
            _content.Children.Add(Row(warn, Note(Loc.T("Playlist trop grande pour FL : décoche « Playlist »."), Orange), 6));
        }
        _right.Children.Add(SoftButton(Loc.T("Annuler"), _controller.Close));
        _right.Children.Add(BlueButton(Loc.T("Organiser"), _controller.Apply));
    }

    /// « Options » : les pages de FL à ranger, les noms, les bus, les sons sans note, le diagnostic et le tuto.
    private Button OptionsButton()
    {
        var options = _controller.Options;
        var menu = new MenuFlyout();
        ToggleMenuFlyoutItem Toggle(string text, bool on, Func<OrganizerOptions, bool, OrganizerOptions> set, bool enabled = true)
        {
            var item = new ToggleMenuFlyoutItem { Text = text, IsChecked = on, IsEnabled = enabled };
            item.Click += (_, _) => _controller.SetOptions(set(_controller.Options, item.IsChecked));
            return item;
        }
        menu.Items.Add(Toggle(Loc.T("Channel rack"), options.Rack, (o, on) => o with { Rack = on }));
        menu.Items.Add(Toggle(Loc.T("Patterns"), options.Patterns, (o, on) => o with { Patterns = on }));
        menu.Items.Add(Toggle(Loc.T("Mixer"), options.Mixer, (o, on) => o with { Mixer = on }));
        menu.Items.Add(Toggle(Loc.T("Playlist"), options.Playlist, (o, on) => o with { Playlist = on }));
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(Toggle(Loc.T("Renommer"), options.Rename, (o, on) => o with { Rename = on }));
        menu.Items.Add(Toggle(Loc.T("Un bus par famille"), options.Buses, (o, on) => o with { Buses = on }, options.Mixer));
        menu.Items.Add(Toggle(_controller.OrganizesCopy ? Loc.T("Supprimer les sons sans note") : Loc.T("Supprimer les sons sans note (définitif)"),
            options.DeleteUnused, (o, on) => o with { DeleteUnused = on }));
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(MenuItem(_controller.Copied ? Loc.T("Copié") : Loc.T("Copier le diagnostic"), _controller.CopyDiagnostic));
        menu.Items.Add(MenuItem(Loc.T("Revoir le tuto"), ShowTutorialAgain));
        var button = SoftButton(Loc.T("Options"), () => { }, Loc.T("Ce que l'Organiser range, et le diagnostic à copier pour l'équipe"));
        button.Flyout = menu;
        return button;
    }

    /// Une famille de l'aperçu : en-tête (poignée, couleur, nom, départ dans le Mixer), puis ses sons dans une carte.
    /// Elle se glisse au-dessus ou en dessous d'une autre par sa poignée, comme un dossier.
    private UIElement FamilySection(SoundFamily family, IReadOnlyDictionary<int, RgbColor> colors)
    {
        var style = _controller.StyleOf(family);
        var members = _controller.Members(family);

        var grip = new Border { Width = 14, Height = 24, Background = Brush(Colors.Transparent), CanDrag = true };
        grip.Child = Icon("line.3.horizontal", 12, Secondary);
        ((FrameworkElement)grip.Child).HorizontalAlignment = HorizontalAlignment.Center;
        ((FrameworkElement)grip.Child).VerticalAlignment = VerticalAlignment.Center;
        ToolTipService.SetToolTip(grip, Loc.T("Glisse la famille au-dessus ou en dessous d'une autre : le Channel rack, le Mixer et la Playlist suivent cet ordre"));
        grip.DragStarting += (_, e) =>
        {
            _dragging = family;
            e.Data.SetText(DragPrefix + family.Raw());
            e.Data.RequestedOperation = DataPackageOperation.Move;
        };
        grip.DropCompleted += (_, _) => _dragging = null;

        var head = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        head.Children.Add(grip);
        head.Children.Add(Swatch(family, style.Color, withFade: true, picked => _controller.UpdateStyle(family, s => s with { Color = picked })));
        if (style.Fade is { } fade)
            head.Children.Add(Swatch(family, fade, withFade: false, picked => _controller.UpdateStyle(family, s => s with { Fade = picked })));
        var name = Label(family.Label(), 14, Text, semibold: true);
        name.TextWrapping = TextWrapping.NoWrap;
        name.VerticalAlignment = VerticalAlignment.Center;
        head.Children.Add(name);

        var header = new Grid { MinHeight = 32, Padding = new Thickness(4, 0, 4, 0) };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.Children.Add(head);
        if (_controller.Options.Mixer && _controller.MixerRange(family) is { } range)
        {
            var mixer = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
            var label = Label(Loc.T("Mixer"), 12, Secondary);
            label.VerticalAlignment = VerticalAlignment.Center;
            mixer.Children.Add(label);
            var box = new SlotBox(style.MixerStart ?? range.First, style.MixerStart is not null, _controller.MixerLast, ColorOf(style.Color),
                start => _controller.SetMixerStart(family, start));
            ToolTipService.SetToolTip(box, Loc.T("Première piste du Mixer de la famille (son bus compris ; la 808 avec les drums) : tire vers le haut ou le bas comme dans FL, ou clique pour l'écrire"));
            mixer.Children.Add(box);
            Grid.SetColumn(mixer, 1);
            header.Children.Add(mixer);
        }

        // Ses sons, dans une carte, séparés par un trait fin.
        var list = new StackPanel();
        for (var i = 0; i < members.Count; i++)
        {
            var member = members[i];
            var cell = new Grid();
            cell.Children.Add(MemberRow(family, member, colors.TryGetValue(member.Id, out var c) ? c : style.Color));
            if (i > 0) cell.Children.Add(new Rectangle { Height = 1, Fill = Brush(White(0.08)), VerticalAlignment = VerticalAlignment.Top, IsHitTestVisible = false });
            list.Children.Add(cell);
        }
        var card = Card(list, ColorOf(style.Color), 0);
        card.Padding = new Thickness(10, 2, 10, 2);

        var section = new StackPanel { Spacing = 6, AllowDrop = true, Background = Brush(Colors.Transparent) };
        var mark = new Rectangle { Height = 3, RadiusX = 1.5, RadiusY = 1.5, Fill = Brush(Tint), Margin = new Thickness(10, 0, 10, 0), Visibility = Visibility.Collapsed };
        section.Children.Add(mark);
        section.Children.Add(header);
        section.Children.Add(card);
        section.DragOver += (_, e) =>
        {
            if (_dragging is not { } dragged || dragged == family) return;
            e.AcceptedOperation = DataPackageOperation.Move;
            mark.Visibility = Visibility.Visible;
        };
        section.DragLeave += (_, _) => mark.Visibility = Visibility.Collapsed;
        section.Drop += (_, _) =>
        {
            mark.Visibility = Visibility.Collapsed;
            if (_dragging is { } dragged && dragged != family) _controller.MoveFamily(dragged, family);
            _dragging = null;
        };
        var menu = new MenuFlyout();
        menu.Items.Add(MenuItem(Loc.T("Monter la famille"), () => _controller.ShiftFamily(family, -1)));
        menu.Items.Add(MenuItem(Loc.T("Descendre la famille"), () => _controller.ShiftFamily(family, 1)));
        section.ContextFlyout = menu;
        return section;
    }

    private static MenuFlyoutItem MenuItem(string text, Action click)
    {
        var item = new MenuFlyoutItem { Text = text };
        item.Click += (_, _) => click();
        return item;
    }

    /// Un rond de couleur : le choix de couleur s'ouvre au clic ; `withFade` : au-dessus, « Une couleur / Dégradé ».
    private Button Swatch(SoundFamily family, RgbColor color, bool withFade, Action<RgbColor> set)
    {
        var dot = new Ellipse { Width = 20, Height = 20, Fill = Fill(color), Stroke = Brush(White(0.3)), StrokeThickness = 1.5 };
        var button = new Button { Style = PlainButton, Content = dot, CornerRadius = new CornerRadius(10), VerticalAlignment = VerticalAlignment.Center };
        ToolTipService.SetToolTip(button, "#" + color.Hex);
        AutomationProperties.SetName(button, "#" + color.Hex);
        var picker = new ColorPicker
        {
            Color = ColorOf(color), IsAlphaEnabled = false, IsMoreButtonVisible = false,
            IsColorChannelTextInputVisible = false, IsHexInputVisible = true,
        };
        var body = new StackPanel { Spacing = 10 };
        if (withFade)
        {
            var fadeOn = _controller.StyleOf(family).Fade is not null;
            var choice = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
            choice.Children.Add(Segment(Loc.T("Une couleur"), !fadeOn, () => _controller.UpdateStyle(family, s => s with { Fade = null })));
            choice.Children.Add(Segment(Loc.T("Dégradé"), fadeOn, () => _controller.UpdateStyle(family, s => s with
            {
                Fade = s.Fade ?? s.Color.Lerp(new RgbColor(0, 0, 0), 0.45),
            })));
            body.Children.Add(choice);
        }
        body.Children.Add(picker);
        var flyout = new Flyout { Content = body };
        flyout.Closed += (_, _) =>
        {
            var c = picker.Color;
            var picked = new RgbColor(c.R, c.G, c.B);
            if (picked != color) set(picked);
        };
        button.Flyout = flyout;
        return button;
    }

    /// Une moitié du choix « Une couleur / Dégradé » : bleue quand elle est choisie.
    private static Button Segment(string text, bool selected, Action click)
    {
        var button = new Button
        {
            Style = PlainButton,
            Content = Label(text, 12, selected ? Colors.White : Text, semibold: selected),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(12, 5, 12, 5),
            Background = Brush(selected ? Accent : White(0.10)),
        };
        if (!selected) button.Click += (_, _) => click();
        return button;
    }

    /// Un son de l'aperçu : son nom d'origine → le nom qu'il prendra (sa case s'ouvre sur ce qu'est le son et
    /// « Écrire… »), puis sa piste du Mixer (la case de FL), tout à droite.
    private UIElement MemberRow(SoundFamily family, OrganizerController.Member member, RgbColor color)
    {
        var grid = new Grid { ColumnSpacing = 8, MinHeight = 38 };
        foreach (var width in new[] { GridLength.Auto, GridLength.Auto, GridLength.Auto, new GridLength(1, GridUnitType.Star), GridLength.Auto })
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = width });
        var name = Label(member.Name.Length == 0 ? Loc.T("(sans nom)") : member.Name, 13, Text);
        name.TextWrapping = TextWrapping.NoWrap;
        name.TextTrimming = TextTrimming.CharacterEllipsis;
        name.MaxWidth = 150;
        name.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(name);
        if (member.TestNotes)
        {
            var note = Icon("music.note", 12, Secondary);
            note.IsHitTestVisible = true;
            note.VerticalAlignment = VerticalAlignment.Center;
            ToolTipService.SetToolTip(note, Loc.T("Muet dans ses patterns : classé avec deux notes d'essai. Vérifie sa famille."));
            Grid.SetColumn(note, 1);
            grid.Children.Add(note);
        }
        var arrow = Icon("arrow.right", 10, Secondary);
        arrow.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(arrow, 2);
        grid.Children.Add(arrow);

        // Ce qu'est le son (« BEAM KICK » : Kick), sinon sa famille ; chaque famille propose ses sortes ; en bas,
        // « Écrire… » pour lui donner son propre nom.
        var text = Label(member.NewName ?? member.Kind?.Name() ?? family.Label(), 13, Text);
        text.TextWrapping = TextWrapping.NoWrap;
        text.TextTrimming = TextTrimming.CharacterEllipsis;
        text.VerticalAlignment = VerticalAlignment.Center;
        var chevron = Icon("chevron.down", 9, Secondary);
        chevron.VerticalAlignment = VerticalAlignment.Center;
        var inside = new Grid { ColumnSpacing = 4 };
        inside.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        inside.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        inside.Children.Add(text);
        Grid.SetColumn(chevron, 1);
        inside.Children.Add(chevron);
        var kind = new Button
        {
            Style = PlainButton, Content = inside, MinHeight = 26, Padding = new Thickness(8, 0, 8, 0),
            CornerRadius = new CornerRadius(7), Background = Brush(White(0.06)), VerticalAlignment = VerticalAlignment.Center,
        };
        kind.PointerEntered += (_, _) => kind.Background = Brush(White(0.12));
        kind.PointerExited += (_, _) => kind.Background = Brush(White(0.06));
        ToolTipService.SetToolTip(kind, Loc.T("Changer ce qu'est ce son (Kick, 808, Lead…), ou écrire son nom"));
        var menu = new MenuFlyout();
        foreach (var choice in SoundFamilies.Order.Where(f => f.Kinds().Length > 0))
        {
            var sub = new MenuFlyoutSubItem { Text = choice.Label() };
            foreach (var k in choice.Kinds()) sub.Items.Add(MenuItem(k.Name(), () => _controller.SetKind(member.Id, k)));
            menu.Items.Add(sub);
        }
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(MenuItem(Loc.T("Écrire…"), () => DispatcherQueue.TryEnqueue(() => WriteName(kind, member))));
        if (member.Written) menu.Items.Add(MenuItem(Loc.T("Nom automatique"), () => _controller.SetName(member.Id, null)));
        kind.Flyout = menu;
        Grid.SetColumn(kind, 3);
        grid.Children.Add(kind);

        if (_controller.Options.Mixer && (member.Slot is not null || member.Pinned))
        {
            var box = new SlotBox(member.Slot, member.Pinned, _controller.MixerLast, ColorOf(color), slot => _controller.SetSlot(member.Id, slot));
            ToolTipService.SetToolTip(box, Loc.T("Piste du Mixer de ce son : tire vers le haut ou le bas comme dans FL, ou clique pour l'écrire"));
            Grid.SetColumn(box, 4);
            grid.Children.Add(box);
        }
        return grid;
    }

    /// « Écrire… » : le nom que la personne veut, posé partout où le son a son nom.
    private void WriteName(FrameworkElement anchor, OrganizerController.Member member)
    {
        var box = new TextBox
        {
            Text = _controller.Names.TryGetValue(member.Id, out var written) ? written : "",
            PlaceholderText = Loc.T("Écris le nom que tu veux"), Width = 240, MaxLength = 64,
        };
        var flyout = new Flyout();
        void Save()
        {
            _controller.SetName(member.Id, box.Text);
            flyout.Hide();
        }
        box.KeyDown += (_, e) =>
        {
            if (e.Key != VirtualKey.Enter) return;
            e.Handled = true;
            Save();
        };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Right };
        buttons.Children.Add(SoftButton(Loc.T("Annuler"), flyout.Hide));
        buttons.Children.Add(BlueButton(Loc.T("OK"), Save));
        flyout.Content = Stack(10, Label(Loc.T("Nom du son"), 12, Text, semibold: true), box, buttons);
        flyout.Opened += (_, _) => box.Focus(FocusState.Programmatic);
        flyout.ShowAt(anchor);
    }

    private static CheckBox Check(string text, bool on, Action<bool> set)
    {
        var box = new CheckBox { Content = new TextBlock { Text = text, FontSize = 12, TextWrapping = TextWrapping.Wrap }, IsChecked = on, MinWidth = 0 };
        box.Checked += (_, _) => set(true);
        box.Unchecked += (_, _) => set(false);
        return box;
    }

    // ---------- « Pas content ? » ----------

    private async void ShowFeedback()
    {
        var feedback = new OrganizerFeedback { Share = _controller.SharingCorrections };
        var body = new StackPanel { Spacing = 8 };
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Style = MainShell.DialogStyle(),
            RequestedTheme = ElementTheme.Dark,
            Background = Brush(Rgb(0x1E, 0x1E, 0x21)),
            BorderBrush = Brush(White(0.16)),
            Title = Loc.T("Qu'est-ce qui n'allait pas ?"),
            PrimaryButtonText = Loc.T("Envoyer"),
            CloseButtonText = Loc.T("Annuler"),
            DefaultButton = ContentDialogButton.Primary,
            IsPrimaryButtonEnabled = false,
            Content = new ScrollViewer { Content = body, MaxHeight = 460 },
        };
        void Build()
        {
            body.Children.Clear();
            body.Children.Add(Paragraph(Loc.T("Coche tout ce qui ne va pas : l'IA apprend de ses erreurs."), 12));
            foreach (var reason in OrganizerFeedback.AllReasons)
            {
                body.Children.Add(Check(OrganizerFeedback.Label(reason), feedback.Reasons.Contains(reason), on =>
                {
                    if (on) feedback.Reasons.Add(reason); else feedback.Reasons.Remove(reason);
                    Build();
                }));
            }
            body.Children.Add(Check(Loc.T("Autre"), feedback.Other, on =>
            {
                feedback.Other = on;
                Build();
            }));
            if (feedback.Other)
            {
                var text = new TextBox
                {
                    Text = feedback.OtherText, PlaceholderText = Loc.T("Dis-nous ce qui ne va pas"), AcceptsReturn = true,
                    TextWrapping = TextWrapping.Wrap, MinHeight = 64, MaxLength = 1000,
                };
                text.TextChanged += (_, _) =>
                {
                    feedback.OtherText = text.Text;
                    dialog.IsPrimaryButtonEnabled = feedback.CanSend;
                };
                body.Children.Add(text);
            }
            if (feedback.AsksSounds) FeedbackSounds(body, feedback, Build);
            if (feedback.TeamMessage() is not null)
                body.Children.Add(Note(Loc.T("Sur Windows, ce message ne part pas encore tout seul : après « Envoyer », clique sur « Copier le diagnostic » et colle-le-moi avec ce qui n'allait pas.")));
            dialog.IsPrimaryButtonEnabled = feedback.CanSend;
        }
        Build();
        if (await dialog.ShowAsync() == ContentDialogResult.Primary) _controller.SubmitFeedback(feedback);
    }

    /// Les sons écoutés : pour chacun mal rangé, sa bonne famille ou sorte (mêmes choix que l'aperçu).
    private void FeedbackSounds(StackPanel body, OrganizerFeedback feedback, System.Action rebuild)
    {
        body.Children.Add(Label(Loc.T("Quels sons étaient mal rangés ?"), 13, Text, semibold: true));
        var correctable = _controller.Correctable;
        if (correctable.Count == 0)
        {
            body.Children.Add(Paragraph(Loc.T("Aucun son n'a été écouté : tous ont été rangés d'après leur nom. Change leur nom dans FL."), 12));
            return;
        }
        foreach (var item in correctable)
        {
            var chosen = feedback.Fixes.TryGetValue(item.Index, out var fix) ? fix : (OrganizerFeedback.Fix?)null;
            var family = _controller.Families.TryGetValue(item.Index, out var f) ? f : item.Family;
            var label = chosen is { } c ? c.Kind?.Name() ?? c.Family.Label() : _controller.KindOf(item.Index)?.Name() ?? family.Label();
            var menu = new MenuFlyout();
            foreach (var choice in SoundFamilies.Order)
            {
                if (choice.Kinds().Length == 0)
                {
                    menu.Items.Add(MenuItem(choice.Label(), () => { feedback.Fixes[item.Index] = new OrganizerFeedback.Fix(choice); rebuild(); }));
                    continue;
                }
                var sub = new MenuFlyoutSubItem { Text = choice.Label() };
                sub.Items.Add(MenuItem(choice.Label(), () => { feedback.Fixes[item.Index] = new OrganizerFeedback.Fix(choice); rebuild(); }));
                sub.Items.Add(new MenuFlyoutSeparator());
                foreach (var k in choice.Kinds())
                    sub.Items.Add(MenuItem(k.Name(), () => { feedback.Fixes[item.Index] = new OrganizerFeedback.Fix(choice, k); rebuild(); }));
                menu.Items.Add(sub);
            }
            var button = new DropDownButton { Content = new TextBlock { Text = label, FontSize = 11 }, Flyout = menu };
            ToolTipService.SetToolTip(button, Loc.T("Ce qu'est vraiment ce son"));
            var row = new Grid { ColumnSpacing = 8 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var name = new TextBlock { Text = item.Name.Length == 0 ? Loc.T("(sans nom)") : item.Name, FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
            var mark = chosen is null
                ? (FrameworkElement)new Ellipse { Width = 12, Height = 12, Stroke = Brush(White(0.3)), StrokeThickness = 1.2 }
                : Icon("check", 12, Green);
            mark.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(button, 1);
            Grid.SetColumn(mark, 2);
            row.Children.Add(name);
            row.Children.Add(button);
            row.Children.Add(mark);
            body.Children.Add(row);
        }
        body.Children.Add(Note(Loc.T("Les sons rangés d'après leur nom n'y sont pas : l'IA ne les a pas écoutés.")));
    }

    // ---------- Fichier et dossier montrés ----------

    /// « Choisir le fichier… » : le projet ouvert dans FL, montré par la personne.
    private bool ChooseProject()
    {
        var path = FileDialogs.PickFile(_hwnd, Loc.T("Choisis le fichier du projet ouvert dans FL Studio (.flp)."), "FL Studio (.flp)", "flp");
        if (path is null) return false;
        ProjectFileWindows.Chosen = path;
        return true;
    }

    /// « Autre dossier de FL… » : le dossier « Settings\Hardware » que FL lit.
    private bool InstallElsewhere()
    {
        var folder = FileDialogs.PickFolder(_hwnd, Loc.T("Choisis le dossier « Settings\\Hardware » de FL Studio."),
            System.IO.Path.GetDirectoryName(ScriptInstaller.DefaultHardwareFolder));
        return folder is not null && _app.InstallScript(folder) is null;
    }

    /// La case du numéro de piste du Mixer, comme celle du Channel rack de FL (et MixerSlotBox du Mac) : on la tire vers
    /// le haut ou le bas pour changer le numéro, ou on clique pour l'écrire ; Alt + clic : automatique. Un numéro choisi
    /// est clair, bordé de la couleur du son ; un numéro automatique est gris ; « --- » : aucune piste. Le numéro suit
    /// la souris, il est posé au lâcher.
    private sealed class SlotBox : Grid
    {
        public SlotBox(int? value, bool chosen, int last, Color tint, Action<int?> set)
        {
            Width = 44;
            Height = 22;
            CornerRadius = new CornerRadius(6);
            VerticalAlignment = VerticalAlignment.Center;
            Background = Brush(Color.FromArgb(0x47, 0, 0, 0));
            BorderBrush = Brush(chosen ? tint : White(0.12));
            BorderThickness = new Thickness(1);
            ProtectedCursor = InputSystemCursor.Create(InputSystemCursorShape.SizeNorthSouth);
            var label = new TextBlock
            {
                Text = value?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "---", FontSize = 12,
                HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
                FontWeight = chosen ? FontWeights.SemiBold : FontWeights.Normal, Foreground = Brush(chosen ? Text : Secondary),
            };
            Children.Add(label);
            if (!chosen)
            {
                PointerEntered += (_, _) => BorderBrush = Brush(White(0.35));
                PointerExited += (_, _) => BorderBrush = Brush(White(0.12));
            }
            double? start = null;
            var from = value ?? 1;
            var current = from;
            var moved = false;
            PointerPressed += (_, e) =>
            {
                var point = e.GetCurrentPoint(this);
                if (!point.Properties.IsLeftButtonPressed) return;
                start = point.Position.Y;
                from = value ?? 1;
                current = from;
                moved = false;
                CapturePointer(e.Pointer);
                e.Handled = true;
            };
            PointerMoved += (_, e) =>
            {
                if (start is not { } y0) return;
                var dy = e.GetCurrentPoint(this).Position.Y - y0;
                if (Math.Abs(dy) >= 2) moved = true;
                if (!moved) return;
                current = OrganizerController.DraggedSlot(from, dy, last);
                label.Text = current.ToString(System.Globalization.CultureInfo.InvariantCulture);
            };
            PointerReleased += (_, e) =>
            {
                if (start is null) return;
                start = null;
                ReleasePointerCapture(e.Pointer);
                e.Handled = true;
                if (moved) set(current);
                else if (InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Menu).HasFlag(CoreVirtualKeyStates.Down)) set(null);
                else Type(value, last, set);
            };
            PointerCaptureLost += (_, _) =>
            {
                if (start is null) return;
                start = null;
                if (moved) set(current);
            };
        }

        private void Type(int? value, int last, Action<int?> set)
        {
            var box = new TextBox { Text = value?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "", PlaceholderText = $"1…{last}", Width = 120 };
            var flyout = new Flyout();
            void Save()
            {
                if (int.TryParse(box.Text.Trim(), out var n)) set(Math.Clamp(n, 1, last));
                flyout.Hide();
            }
            box.KeyDown += (_, e) =>
            {
                if (e.Key != VirtualKey.Enter) return;
                e.Handled = true;
                Save();
            };
            var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            buttons.Children.Add(Soft(Loc.T("Automatique"), () =>
            {
                set(null);
                flyout.Hide();
            }));
            buttons.Children.Add(Primary(Loc.T("OK"), Save));
            flyout.Content = Stack(10, Label(Loc.T("Piste du Mixer"), 12, Text, semibold: true), box, buttons);
            flyout.Opened += (_, _) => box.Focus(FocusState.Programmatic);
            flyout.ShowAt(this);
        }
    }
}
