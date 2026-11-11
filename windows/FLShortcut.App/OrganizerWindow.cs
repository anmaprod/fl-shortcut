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

    /// L'Organiser tient encore le lien avec FL (lu par le surveillant du lien, n'importe quel fil).
    public static bool HoldsLink => _open?._controller is { HoldsLink: true };

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
    /// Son pris par sa poignée, glissé vers une autre famille (comme le Mac).
    private int? _draggingSound;
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
        // Titre comme le Mac (09/11, « pas identique ») : « organiser. » en minuscules, gras serré, point carré rouge,
        // un trait à l'encre dessous.
        _title = SwissTitle(36);
        _title.Text = Loc.T("Organiser").ToLower(System.Globalization.CultureInfo.CurrentCulture);
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
            bar.ButtonHoverForegroundColor = MacLook.Text;
            bar.ButtonPressedBackgroundColor = White(0.18);
            bar.ButtonPressedForegroundColor = MacLook.Text;
        }
        var scale = Win32.GetDpiForWindow(_hwnd) / 96.0;
        AppWindow.Resize(new Windows.Graphics.SizeInt32((int)(TextWidth * scale), (int)(420 * scale)));
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsAlwaysOnTop = true;              // reste visible pendant que FL est devant
            presenter.IsMinimizable = false;
        }

        Photos.Note("fenêtre : taille");
        var page = new Grid { Background = Brush(WindowColor), RequestedTheme = MacLook.SurfaceTheme };
        var dragBar = new Border { Height = 32, VerticalAlignment = VerticalAlignment.Top, Background = Brush(Colors.Transparent) };
        _root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        _root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        _root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var headerRow = new Grid();
        headerRow.Children.Add(PageTitle(_title, 36));
        headerRow.Children.Add(_headerTools);
        var header = new StackPanel { Spacing = 12 };
        header.Children.Add(headerRow);
        header.Children.Add(Rule(Text));
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
        // Plus de tuto (05/11, comme le Mac) : « Installer le lien » directement ; la photo de la CI le montre encore.
        _tutorial = demo == "tuto";
        _startAfterTutorial = _tutorial && demo is null;
        Render();
        Photos.Note("fenêtre : premier dessin");
        if (demo is null)
        {
            // Comme le Mac : l'écran « Démarrer » d'abord ; lien pas encore installé : « Installer le lien » tout de suite.
            if (!_tutorial && !app.Midi.HasKey) _controller.Start();
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
        CornerRadius = new CornerRadius(0),
        Background = Brush(MacLook.WindowColor),
        BorderBrush = Brush(WithOpacity(tint ?? Tint, 0.4)),
        BorderThickness = new Thickness(1),
    };

    /// 06/11 (comme le Mac : « une petite baguette magique… ignoble », « un petit point d'exclamation, enlève-le ») :
    /// plus aucune pastille d'icône dans l'Organiser, le texte seul.
    private static readonly bool BadgesShown = false;

    /// Pastille de couleur avec son dessin blanc (résultat, écoute, attente) ; cachée (BadgesShown).
    private static Grid Badge(string icon, Color tint, double size = 34)
    {
        if (!BadgesShown) return new Grid { Visibility = Visibility.Collapsed };
        var grid = new Grid { Width = size, Height = size, VerticalAlignment = VerticalAlignment.Center };
        grid.Children.Add(new Rectangle { Fill = Brush(tint) });
        var glyph = Icon(icon, size * 0.46, Colors.White, tint);
        glyph.HorizontalAlignment = HorizontalAlignment.Center;
        glyph.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(glyph);
        return grid;
    }

    /// Une ligne : une pastille (ou une icône), puis le texte qui prend la place.
    private static Grid Row(UIElement first, UIElement rest, double spacing = 12)
    {
        // Rien à gauche (pastille ou roue retirées) : pas d'écart non plus.
        var grid = new Grid { ColumnSpacing = first.Visibility == Visibility.Collapsed ? 0 : spacing };
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

    /// 06/11 (comme le Mac : « ça me fait tourner un petit truc à gauche… enlève-le ») : plus de roue qui tourne.
    private static ProgressRing Spinner(double size = 18) => new()
    {
        IsActive = false, Width = size, Height = size, Visibility = Visibility.Collapsed, VerticalAlignment = VerticalAlignment.Center,
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
        _right.Spacing = 8;
        _title.Text = _controller.Title.ToLower(System.Globalization.CultureInfo.CurrentCulture);
        var preview = _controller.Phase is OrganizerPhase.Preview && !_tutorial;
        // Aperçu : un trait fin au-dessus des boutons (comme le Mac).
        _footer.BorderThickness = new Thickness(0, preview ? 1 : 0, 0, 0);
        _footer.BorderBrush = Brush(LineColor);
        if (_tutorial)
        {
            Tutorial();
            FitSoon();
            return;
        }
        switch (_controller.Phase)
        {
            case OrganizerPhase.Starting:
                Ready();
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
                        ? Loc.T("Ton projet d'avant se rouvre. La copie part à la Corbeille.")
                        : Loc.T("FL est revenu comme avant.")),
                    u.Error is null, u.Error?.Is(OrganizerError.Kinds.NoResponse) == true);
                break;
            case OrganizerPhase.Failed f:
                Ending(f.Message, false, false);
                break;
        }
        FitSoon();
    }

    /// Avant « Démarrer » (comme le Mac, 09/11) : rien n'est envoyé à FL ; la consigne seule, en grand, sous le trait du
    /// titre, un carré rouge plein devant ; Fermer et Démarrer.
    private void Ready()
    {
        var text = SwissTitle(22);
        text.Text = Loc.T("Ne touche pas à FL jusqu'à la fin.");
        text.TextWrapping = TextWrapping.Wrap;
        var row = Row(new Rectangle { Width = 16, Height = 16, Fill = Brush(BrandRed) }, text, 14);
        row.Margin = new Thickness(0, 10, 0, 10);
        _content.Children.Add(row);
        _right.Children.Add(SoftButton(Loc.T("Fermer"), _controller.Close));
        _right.Children.Add(BlueButton(Loc.T("Démarrer"), _controller.Start));
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
        // Comme le Mac (07/11) : écrans de texte de 480 de large ; l'aperçu s'ouvre à 720 et se tire (440 au moins).
        var preview = _controller.Phase is OrganizerPhase.Preview && !_tutorial;
        var current = AppWindow.ClientSize.Width / scale;
        var width = preview ? (_wasPreview ? Math.Max(current, 440) : StartWidth) : TextWidth;
        _wasPreview = preview;
        double height;
        if (preview) height = Math.Max(PreviewHeight, AppWindow.ClientSize.Height / scale);
        else
        {
            _root.Measure(new Windows.Foundation.Size(width, double.PositiveInfinity));
            height = Math.Clamp(_root.DesiredSize.Height, 160, 900);
        }
        var targetHeight = (int)Math.Round(height * scale);
        var targetWidth = (int)Math.Round(width * scale);
        if (Math.Abs(targetHeight - AppWindow.ClientSize.Height) <= 2 && Math.Abs(targetWidth - AppWindow.ClientSize.Width) <= 2) return;
        // Photo de l'aperçu de la CI du 10/11 à 464 × 411 au lieu de 720 : la taille demandée et obtenue, notées.
        var before = AppWindow.ClientSize;
        AppWindow.ResizeClient(new Windows.Graphics.SizeInt32(targetWidth, targetHeight));
        Photos.Note($"taille : {before.Width}×{before.Height} → {targetWidth}×{targetHeight} demandé, {AppWindow.ClientSize.Width}×{AppWindow.ClientSize.Height} obtenu (aperçu {preview})");
    }

    /// Largeur des écrans de texte (Démarrer, lien, attente, écoute, fin), comme le Mac.
    private const double TextWidth = 480;
    private bool _wasPreview;

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
        var label = Label(text, 13, Text, bold: true);
        label.TextWrapping = TextWrapping.Wrap;
        _content.Children.Add(Ruled(label, 14));
    }

    /// Lien avec FL pas encore installé (05/11 : « un ordre à la fois ») : étape 1 sur 3, un seul bouton.
    private void Setup()
    {
        _content.Children.Add(LinkSteps(1, ""));                 // 07/11 : plus de phrase dessous
        PortsCard();
        _right.Children.Add(SoftButton(Loc.T("Fermer"), _controller.Close));
        _right.Children.Add(BlueButton(Loc.T("Installer le lien"), _controller.InstallLink));
    }

    /// Bloc entre deux traits fins (style suisse du Mac : plus de carte bordée de couleur).
    private static Border Ruled(UIElement child, double vertical = 12) => new()
    {
        Child = child,
        Padding = new Thickness(0, vertical, 0, vertical),
        BorderBrush = Brush(LineColor),
        BorderThickness = new Thickness(0, 1, 0, 1),
    };

    /// Le port MIDI du lien manque (Windows seulement) : rien ne peut passer entre FL Shortcuts et FL.
    private void PortsCard()
    {
        if (MidiLink.PortsUsable()) return;
        var link = new HyperlinkButton
        {
            Content = Label(Loc.T("Télécharger loopMIDI"), 12, Text),
            NavigateUri = new Uri("https://www.tobias-erichsen.de/software/loopmidi.html"),
            Padding = new Thickness(0),
        };
        _content.Children.Add(Ruled(Row(new Rectangle { Width = 10, Height = 10, Fill = Brush(Red) }, Stack(4,
            Label(Loc.T("Installe d'abord loopMIDI"), 14, Text, bold: true),
            Paragraph(Loc.T("Installe loopMIDI, puis ferme-le : rien à faire dedans."), 12),
            link), 12)));
    }

    private static (string Icon, string Title, string Detail) WaitText(OrganizerWait reason) => reason switch
    {
        OrganizerWait.RestartFl => ("arrow.clockwise", Loc.T("Quitte et rouvre FL"), ""),
        OrganizerWait.NoResponse => ("antenna.radiowaves.left.and.right", Loc.T("En attente de FL Studio"),
            Loc.T("FL ne répond pas encore. Vérifie MIDI Settings ci-dessous.")),
        OrganizerWait.WrongInput => ("link", Loc.T("Le lien est sur la mauvaise entrée"),
            Loc.T("Ta carte son a le Controller type « FL Shortcuts » : remets-la sur « (generic controller) ».")),
        OrganizerWait.OpenFl => ("macwindow", Loc.T("Ouvre FL Studio"), Loc.T("Organiser commence dès que FL est ouvert, avec ton projet.")),
        _ => ("stop.fill", Loc.T("Arrête la lecture dans FL"), Loc.T("Organiser écoute chaque son seul : FL doit être à l'arrêt.")),
    };

    /// En attente de FL (comme le Mac) : ce qu'il faut faire, en une phrase ; Organiser vérifie tout seul et continue
    /// dès que c'est bon. Étape 2 du lien : « Quitter et rouvrir FL » dans la page. FL muet : l'aide, repliée.
    private void Waiting(OrganizerWait reason)
    {
        var (_, title, detail) = WaitText(reason);
        if (reason == OrganizerWait.RestartFl)
            _content.Children.Add(LinkSteps(2, ""));
        else
            _content.Children.Add(Ruled(Stack(4, Label(title, 14, Text, bold: true), Paragraph(detail, 12)), 14));
        _content.Children.Add(Note(Loc.T("Organiser continue tout seul dès que FL est prêt.")));
        if (reason == OrganizerWait.RestartFl)
        {
            // 07/11 (comme le Mac) : FL quitté et rouvert d'un clic ; FL fermé : l'ouvrir.
            var restart = FlControl.Process() is not null
                ? BlueButton(Loc.T("Quitter et rouvrir FL"), _controller.RestartFl)
                : BlueButton(Loc.T("Ouvrir FL Studio"), OrganizerLive.OpenFlStudio);
            restart.HorizontalAlignment = HorizontalAlignment.Left;
            _content.Children.Add(restart);
        }
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

    /// « Ça ne marche toujours pas ? » : lien blanc souligné, chevron devant (comme le Mac) ; l'aide repliée.
    private Button LinkHelpToggle()
    {
        var chevron = Icon(_controller.ShowLinkHelp ? "chevron.down" : "chevron.right", 10, Text);
        chevron.VerticalAlignment = VerticalAlignment.Center;
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6 };
        row.Children.Add(chevron);
        var label = Label(Loc.T("Ça ne marche toujours pas ?"), 12, Text, semibold: true);
        label.TextDecorations = Windows.UI.Text.TextDecorations.Underline;
        row.Children.Add(label);
        var toggle = new Button { Style = PlainButton, Content = row, HorizontalAlignment = HorizontalAlignment.Left, Padding = new Thickness(0, 2, 0, 2) };
        toggle.Click += (_, _) =>
        {
            _controller.ShowLinkHelp = !_controller.ShowLinkHelp;
            Render();
        };
        AutomationProperties.SetName(toggle, Loc.T("Ça ne marche toujours pas ?"));
        return toggle;
    }

    /// Relier FL, comme le Mac (LinkGuide) : les quatre étapes, les 4 cases de MIDI Settings en grand (découpées dans
    /// l'image du Mac), les pièges déjà vus, puis où est le script.
    private void LinkHelp()
    {
        var steps = new[]
        {
            Loc.T("Installe le lien"), Loc.T("Quitte et rouvre FL"), Loc.T("Dans FL : Options › MIDI Settings"),
            Loc.T("Règle les 4 cases entourées"),
        };
        var list = new StackPanel();
        for (var i = 0; i < steps.Length; i++) list.Children.Add(Step(i + 1, steps[i]));
        _content.Children.Add(list);
        _content.Children.Add(MidiSettingsCrops());
        var troubles = Stack(4,
            Label(Loc.T("Toujours rien ?"), 12, Text, semibold: true),
            Paragraph(Loc.T("Ta carte son : un autre numéro de Port."), 11),
            Paragraph(Loc.T("Pas de « FL Shortcuts » dans Controller type : vérifie le dossier ci-dessous."), 11));
        _content.Children.Add(troubles);
        ScriptCard();
    }

    /// Une étape (comme OrganizerStep du Mac) : le numéro dans un carré rouge, la phrase en gras, un trait fin dessous.
    private static Border Step(int n, string text)
    {
        var row = new Grid { ColumnSpacing = 12 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.Children.Add(NumberSquare(n));
        var label = Label(text, 13, Text, bold: true);
        label.TextWrapping = TextWrapping.Wrap;
        label.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(label, 1);
        row.Children.Add(label);
        return new Border
        {
            Child = row, Padding = new Thickness(0, 10, 0, 10),
            BorderBrush = Brush(LineColor), BorderThickness = new Thickness(0, 0, 0, 1),
        };
    }

    /// Le numéro blanc (couleur du fond) dans un carré rouge de 20.
    private static Grid NumberSquare(int n)
    {
        var number = new Grid { Width = 20, Height = 20, VerticalAlignment = VerticalAlignment.Center };
        number.Children.Add(new Rectangle { Fill = Brush(Red) });
        number.Children.Add(new TextBlock
        {
            Text = n.ToString(System.Globalization.CultureInfo.InvariantCulture), FontSize = 12, FontWeight = FontWeights.Bold,
            FontFamily = SwissFont, Foreground = Brush(WindowColor),
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
        });
        return number;
    }

    /// Les 4 cases de MIDI Settings, découpées dans l'image du Mac (MIDISettingsCrops, pixels sur 1428 de large) :
    /// une ligne par case (numéro, consigne, la case elle-même), puis « Voir toute la fenêtre en grand ».
    private static readonly (int N, string Key, double X, double Y, double W, double H, bool Wide)[] Crops =
    {
        (1, "Output : un numéro de Port (ex. 7).", 1086, 468, 254, 122, false),
        (2, "Input : le même numéro de Port. N'importe lequel, du moment que les deux sont pareils.", 1096, 948, 244, 120, false),
        (3, "Input : clique « FL Shortcuts », puis allume Enable.", 80, 952, 200, 112, false),
        (4, "Controller type : FL Shortcuts.", 280, 924, 820, 142, true),
    };

    private static BitmapImage? _midiSettings;
    private static bool _midiSettingsLarge;

    private static BitmapImage? MidiSettingsImage()
    {
        if (_midiSettings is not null) return _midiSettings;
        try
        {
            using var stream = typeof(OrganizerWindow).Assembly.GetManifestResourceStream("MIDISettings.png");
            if (stream is null) return null;
            var memory = new MemoryStream();
            stream.CopyTo(memory);
            memory.Position = 0;
            var bitmap = new BitmapImage();
            bitmap.SetSource(memory.AsRandomAccessStream());
            return _midiSettings = bitmap;
        }
        catch (Exception)
        {
            return null;
        }
    }

    /// Une case de l'image, à l'échelle donnée (l'image entière décalée dans un cadre qui la coupe).
    private static FrameworkElement Piece(BitmapImage image, double x, double y, double w, double h, double scale)
    {
        var canvas = new Canvas { Width = w * scale, Height = h * scale };
        var picture = new Image { Source = image, Width = 1428 * scale, Stretch = Stretch.Uniform };
        Canvas.SetLeft(picture, -x * scale);
        Canvas.SetTop(picture, -y * scale);
        canvas.Children.Add(picture);
        canvas.Clip = new RectangleGeometry { Rect = new Windows.Foundation.Rect(0, 0, w * scale, h * scale) };
        return canvas;
    }

    private StackPanel MidiSettingsCrops()
    {
        var panel = new StackPanel();
        var image = MidiSettingsImage();
        foreach (var crop in Crops)
        {
            var row = new Grid { ColumnSpacing = 12 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.Children.Add(NumberSquare(crop.N));
            var text = Label(Loc.T(crop.Key), 13, Text, bold: true);
            text.TextWrapping = TextWrapping.Wrap;
            text.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(text, 1);
            row.Children.Add(text);
            var stack = new StackPanel { Spacing = 8 };
            stack.Children.Add(row);
            if (image is not null)
            {
                if (!crop.Wide)
                {
                    var piece = Piece(image, crop.X, crop.Y, crop.W, crop.H, 0.5);
                    piece.VerticalAlignment = VerticalAlignment.Center;
                    Grid.SetColumn(piece, 2);
                    row.Children.Add(piece);
                }
                else
                {
                    var piece = Piece(image, crop.X, crop.Y, crop.W, crop.H, 0.42);
                    piece.Margin = new Thickness(32, 0, 0, 0);
                    piece.HorizontalAlignment = HorizontalAlignment.Left;
                    stack.Children.Add(piece);
                }
            }
            panel.Children.Add(new Border
            {
                Child = stack, Padding = new Thickness(0, 10, 0, 10),
                BorderBrush = Brush(LineColor), BorderThickness = new Thickness(0, 1, 0, 0),
            });
        }
        if (image is not null)
        {
            var toggle = new Button
            {
                Style = PlainButton, HorizontalAlignment = HorizontalAlignment.Left, Padding = new Thickness(0, 8, 0, 8),
                Content = SwissLabel(_midiSettingsLarge ? Loc.T("Masquer la fenêtre en grand") : Loc.T("Voir toute la fenêtre en grand"), 10.5, Text),
            };
            toggle.Click += (_, _) =>
            {
                _midiSettingsLarge = !_midiSettingsLarge;
                Render();
            };
            panel.Children.Add(new Border { Child = toggle, BorderBrush = Brush(LineColor), BorderThickness = new Thickness(0, 1, 0, 0) });
            if (_midiSettingsLarge) panel.Children.Add(new Image { Source = image, Stretch = Stretch.Uniform, MaxWidth = 640, HorizontalAlignment = HorizontalAlignment.Left });
        }
        return panel;
    }

    /// Où est le script du lien, avec « Afficher dans l'Explorateur » et « Autre dossier de FL… ».
    private void ScriptCard()
    {
        var place = _controller.ScriptPlace;
        var present = place?.Present == true;
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        if (present) buttons.Children.Add(SoftButton(Loc.T("Afficher dans l'Explorateur"), _controller.RevealScript));
        buttons.Children.Add(SoftButton(Loc.T("Autre dossier de FL…"), _controller.InstallLinkElsewhere));
        var where = place is { } p ? System.IO.Path.GetDirectoryName(p.Path) ?? p.Path : Loc.T("Aucun dossier enregistré.");
        var path = Paragraph(where, 11);
        path.IsTextSelectionEnabled = true;
        var head = Stack(2, Row(present ? new Grid { Visibility = Visibility.Collapsed } : new Rectangle { Width = 10, Height = 10, Fill = Brush(Red) },
            Label(present ? Loc.T("Script du lien") : Loc.T("Script introuvable dans FL Studio"), 12, Text, semibold: true), 8), path);
        _content.Children.Add(Ruled(Stack(8, head, buttons)));
    }

    /// Analyse en cours (comme le Mac) : le titre et le pourcentage entre deux traits, une barre rouge, la consigne en
    /// petites capitales, « Arrêter ».
    private void Listening(int done, int total)
    {
        var title = total == 0 ? Loc.T("Préparation de l'analyse…") : Loc.F("Analyse du projet : %lld sur %lld", Math.Min(done + 1, total), total);
        var head = new Grid();
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        head.Children.Add(Label(title, 13, Text, bold: true));
        if (total > 0)
        {
            var percent = Label($"{Math.Round(done * 100.0 / Math.Max(total, 1))}%", 12, Secondary);
            Grid.SetColumn(percent, 1);
            head.Children.Add(percent);
        }
        var bar = new ProgressBar
        {
            Maximum = Math.Max(total, 1), Value = done, IsIndeterminate = total == 0,
            Foreground = Brush(Red), Background = Brush(Faint), MinHeight = 3, CornerRadius = new CornerRadius(0),
        };
        var block = Ruled(Stack(10, head, bar), 14);
        block.Padding = new Thickness(14, 14, 14, 14);
        _content.Children.Add(block);
        // Plus d'explication (comme le Mac, 28/10) : la consigne seule.
        _content.Children.Add(SwissLabel(Loc.T("Ne touche pas à FL."), 10.5));
        _right.Children.Add(SoftButton(Loc.T("Arrêter"), _controller.Close));
    }

    /// Fin d'une étape (comme le Mac) : le message entre deux traits, « Copier le diagnostic » souligné dessous ; FL
    /// muet : les réglages de FL à vérifier.
    private void Ending(string text, bool ok, bool linkHelp)
    {
        var message = Label(text, 14, Text, bold: true);
        message.TextWrapping = TextWrapping.Wrap;
        var block = Ruled(ok ? message : Row(new Rectangle { Width = 10, Height = 10, Fill = Brush(Red) }, message, 10), 14);
        block.Padding = new Thickness(14, 14, 14, 14);
        _content.Children.Add(block);
        if (linkHelp) LinkHelp();
        var copyText = Label(_controller.Copied ? Loc.T("Copié") : Loc.T("Copier le diagnostic"), 11.5, Text);
        copyText.TextDecorations = Windows.UI.Text.TextDecorations.Underline;
        var copy = new HyperlinkButton { Content = copyText, Padding = new Thickness(0) };
        copy.Click += (_, _) => _controller.CopyDiagnostic();
        _content.Children.Add(copy);
        if (_controller.CanUndo) _left.Children.Add(SoftButton(Loc.T("Revenir comme avant"), _controller.Undo));
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
        Loc.T("Copie un texte technique, sans aucun nom de son."));

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
            CornerRadius = new CornerRadius(0),
            BorderBrush = Brush(LineColor),
            BorderThickness = new Thickness(1),
            Background = Brush(MacLook.WindowColor),
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
        _content.Children.Add(FamilyBar(families));
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
            _content.Children.Add(Note(Loc.T("Playlist trop grande pour FL : décoche « Playlist »."), Red));
        }
        // Comme le Mac : « Annuler » et « Organiser » collés.
        _right.Spacing = 0;
        _right.Children.Add(SoftButton(Loc.T("Annuler"), _controller.Close));
        _right.Children.Add(BlueButton(Loc.T("Organiser"), _controller.Apply));
    }

    /// Barre des familles (OrganizerFamilyBar du Mac) : un segment de couleur par famille, à la taille de son nombre de
    /// sons, puis « VOIX 1  MÉLODIES 2… » en petites capitales.
    private UIElement FamilyBar(IReadOnlyList<SoundFamily> families)
    {
        var counts = families.Select(f => _controller.Members(f).Count).ToList();
        var bar = new Grid { ColumnSpacing = 2, Height = 6 };
        var labels = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 14 };
        for (var i = 0; i < families.Count; i++)
        {
            bar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(counts[i], 1), GridUnitType.Star) });
            var segment = new Rectangle { Fill = Fill(_controller.StyleOf(families[i]).Color) };
            Grid.SetColumn(segment, i);
            bar.Children.Add(segment);
            var label = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 5 };
            label.Children.Add(SwissLabel(families[i].Label(), 10));
            label.Children.Add(SwissLabel(counts[i].ToString(System.Globalization.CultureInfo.InvariantCulture), 10, Text));
            labels.Children.Add(label);
        }
        return Stack(6, bar, labels);
    }

    /// Les six points d'une poignée (SixDots du Mac).
    private static Canvas SixDots()
    {
        var canvas = new Canvas { Width = 8, Height = 14, VerticalAlignment = VerticalAlignment.Center };
        for (var row = 0; row < 3; row++)
        for (var column = 0; column < 2; column++)
        {
            var dot = new Ellipse { Width = 2.5, Height = 2.5, Fill = Brush(Secondary) };
            Canvas.SetLeft(dot, column * 5);
            Canvas.SetTop(dot, row * 5 + 1);
            canvas.Children.Add(dot);
        }
        return canvas;
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
        menu.Items.Add(Toggle(Loc.T("Pré-master"), options.Premaster, (o, on) => o with { Premaster = on }, options.Mixer && options.Buses));
        menu.Items.Add(Toggle(_controller.OrganizesCopy ? Loc.T("Supprimer les sons sans note") : Loc.T("Supprimer les sons sans note, pour de bon"),
            options.DeleteUnused, (o, on) => o with { DeleteUnused = on }));
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(MenuItem(_controller.Copied ? Loc.T("Copié") : Loc.T("Copier le diagnostic"), _controller.CopyDiagnostic));
        menu.Items.Add(MenuItem(Loc.T("Couleurs de base…"), ShowBaseColors));
        var button = SoftButton(Loc.T("Options"), () => { }, Loc.T("Ce que l'Organiser range, et le diagnostic à copier pour l'équipe"));
        button.Flyout = SwissMenu(menu);              // 07/11 : menu suisse, comme le Mac
        return button;
    }

    /// Une famille de l'aperçu : en-tête (poignée, couleur, nom, départ dans le Mixer), puis ses sons dans une carte.
    /// Elle se glisse au-dessus ou en dessous d'une autre par sa poignée, comme un dossier.
    private UIElement FamilySection(SoundFamily family, IReadOnlyDictionary<int, RgbColor> colors)
    {
        var style = _controller.StyleOf(family);
        var members = _controller.Members(family);

        var grip = new Border { Width = 14, Height = 24, Background = Brush(Colors.Transparent), CanDrag = true };
        grip.Child = SixDots();
        ((FrameworkElement)grip.Child).HorizontalAlignment = HorizontalAlignment.Center;
        ((FrameworkElement)grip.Child).VerticalAlignment = VerticalAlignment.Center;
        ToolTipService.SetToolTip(grip, Loc.T("Glisse pour changer l'ordre."));
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
        var name = SwissLabel(family.Label(), 12.5, Text);
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
            var label = SwissLabel(Loc.T("Mixer"), 10);
            label.VerticalAlignment = VerticalAlignment.Center;
            mixer.Children.Add(label);
            var box = new SlotBox(style.MixerStart ?? range.First, style.MixerStart is not null, _controller.MixerLast, ColorOf(style.Color),
                start => _controller.SetMixerStart(family, start));
            ToolTipService.SetToolTip(box, Loc.T("Première piste du Mixer de la famille. Tire ou clique."));
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
            if (i > 0) cell.Children.Add(new Rectangle { Height = 1, Fill = Brush(Faint), VerticalAlignment = VerticalAlignment.Top, IsHitTestVisible = false });
            list.Children.Add(cell);
        }
        var card = Card(list, ColorOf(style.Color), 0);
        card.Padding = new Thickness(0, 2, 0, 2);
        // Comme le Mac (05/11, « un petit trait en plus… à enlever pour chaque famille ») : la barre de couleur dessus,
        // plus aucun trait autour ni dessous.
        card.BorderBrush = Brush(ColorOf(style.Color));
        card.BorderThickness = new Thickness(0, 2, 0, 0);

        var section = new StackPanel { Spacing = 6, AllowDrop = true, Background = Brush(Colors.Transparent) };
        var mark = new Rectangle { Height = 3, RadiusX = 1.5, RadiusY = 1.5, Fill = Brush(Tint), Margin = new Thickness(10, 0, 10, 0), Visibility = Visibility.Collapsed };
        section.Children.Add(mark);
        section.Children.Add(header);
        section.Children.Add(card);
        section.DragOver += (_, e) =>
        {
            if (_draggingSound is { } sound)
            {
                // Un son posé sur une autre famille (comme le Mac) : la famille entourée.
                if (_controller.Families.TryGetValue(sound, out var from) && from == family) return;
                e.AcceptedOperation = DataPackageOperation.Move;
                card.BorderBrush = Brush(Text);
                card.BorderThickness = new Thickness(1, 2, 1, 1);
                return;
            }
            if (_dragging is not { } dragged || dragged == family) return;
            e.AcceptedOperation = DataPackageOperation.Move;
            mark.Visibility = Visibility.Visible;
        };
        section.DragLeave += (_, _) =>
        {
            mark.Visibility = Visibility.Collapsed;
            card.BorderBrush = Brush(ColorOf(style.Color));
            card.BorderThickness = new Thickness(0, 2, 0, 0);
        };
        section.Drop += (_, _) =>
        {
            mark.Visibility = Visibility.Collapsed;
            if (_draggingSound is { } sound) _controller.MoveSound(sound, family);
            else if (_dragging is { } dragged && dragged != family) _controller.MoveFamily(dragged, family);
            _dragging = null;
            _draggingSound = null;
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
        var dot = new Rectangle { Width = 18, Height = 18, Fill = Fill(color) };          // carré, comme le Mac
        var button = new Button { Style = PlainButton, Content = dot, CornerRadius = new CornerRadius(0), VerticalAlignment = VerticalAlignment.Center };
        ToolTipService.SetToolTip(button, "#" + color.Hex);
        AutomationProperties.SetName(button, "#" + color.Hex);
        var body = new StackPanel { Spacing = 10 };
        if (withFade)
        {
            var fadeOn = _controller.StyleOf(family).Fade is not null;
            var choice = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 0 };
            choice.Children.Add(Segment(Loc.T("Une couleur"), !fadeOn, () => _controller.UpdateStyle(family, s => s with { Fade = null })));
            choice.Children.Add(Segment(Loc.T("Dégradé"), fadeOn, () => _controller.UpdateStyle(family, s => s with
            {
                Fade = s.Fade ?? s.Color.Lerp(new RgbColor(0, 0, 0), 0.45),
            })));
            choice.Margin = new Thickness(14, 14, 14, 0);
            body.Children.Add(choice);
        }
        var flyout = new Flyout { Content = body, FlyoutPresenterStyle = FlatFlyout() };
        // La fenêtre de couleur de FL, comme le Mac (09/11) : une couleur est posée par « Accept » ou une récente.
        body.Children.Add(ColorSelector(color, picked =>
        {
            flyout.Hide();
            _app.RememberColor(picked);
            set(picked);
        }));
        button.Flyout = flyout;
        return button;
    }

    /// Une moitié du choix « Une couleur / Dégradé » : bleue quand elle est choisie.
    private static Button Segment(string text, bool selected, Action click)
    {
        var button = new Button
        {
            Style = PlainButton,
            Content = SwissLabel(text, 10.5, selected ? MacLook.WindowColor : Text),
            Padding = new Thickness(10, 5, 10, 5),
            Background = Brush(selected ? MacLook.Text : MacLook.WindowColor),
            BorderBrush = Brush(selected ? MacLook.Text : LineColor),
            BorderThickness = new Thickness(1),
        };
        if (!selected) button.Click += (_, _) => click();
        return button;
    }

    /// Un son de l'aperçu : son nom d'origine → le nom qu'il prendra (sa case s'ouvre sur ce qu'est le son et
    /// « Écrire… »), puis sa piste du Mixer (la case de FL), tout à droite.
    private UIElement MemberRow(SoundFamily family, OrganizerController.Member member, RgbColor color)
    {
        var row = new Grid { ColumnSpacing = 8, MinHeight = 38 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        // Sa poignée à six points (comme le Mac) : le son se glisse dans une autre famille.
        var handle = new Border { Width = 14, Height = 24, Background = Brush(Colors.Transparent), CanDrag = true, Child = SixDots() };
        ToolTipService.SetToolTip(handle, Loc.T("Glisse ce son dans une autre famille."));
        handle.DragStarting += (_, e) =>
        {
            _draggingSound = member.Id;
            e.Data.SetText("organiser-son:" + member.Id.ToString(System.Globalization.CultureInfo.InvariantCulture));
            e.Data.RequestedOperation = DataPackageOperation.Move;
        };
        handle.DropCompleted += (_, _) => _draggingSound = null;
        row.Children.Add(handle);
        var grid = new Grid { ColumnSpacing = 8 };
        Grid.SetColumn(grid, 1);
        row.Children.Add(grid);
        // Comme le Mac : le nom prend la place, la flèche et la case de sorte (largeur fixe) s'alignent à droite.
        foreach (var width in new[] { new GridLength(1, GridUnitType.Star), GridLength.Auto, GridLength.Auto, new GridLength(118), GridLength.Auto })
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = width });
        var name = Label(member.Name.Length == 0 ? Loc.T("Sans nom") : member.Name, 13, Text);
        name.TextWrapping = TextWrapping.NoWrap;
        name.TextTrimming = TextTrimming.CharacterEllipsis;
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
            Style = PlainButton, Content = inside, MinHeight = 26, HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Stretch, Padding = new Thickness(8, 0, 8, 0),
            CornerRadius = new CornerRadius(0), Background = Brush(MacLook.WindowColor), VerticalAlignment = VerticalAlignment.Center,
            BorderBrush = Brush(LineColor), BorderThickness = new Thickness(1),           // case bordée, comme le Mac
        };
        kind.PointerEntered += (_, _) => kind.Background = Brush(MacLook.WindowColor);
        kind.PointerExited += (_, _) => kind.Background = Brush(MacLook.WindowColor);
        ToolTipService.SetToolTip(kind, Loc.T("Changer ce son ou écrire son nom"));
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
            ToolTipService.SetToolTip(box, Loc.T("Piste du Mixer de ce son. Tire ou clique."));
            Grid.SetColumn(box, 4);
            grid.Children.Add(box);
        }
        return row;
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
            RequestedTheme = MacLook.SurfaceTheme,
            Background = Brush(Rgb(0x1E, 0x1E, 0x21)),
            BorderBrush = Brush(LineColor),
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
                body.Children.Add(Note(Loc.T("Sur Windows, copie le diagnostic et colle-le dans ton message.")));
            dialog.IsPrimaryButtonEnabled = feedback.CanSend;
        }
        Build();
        if (await dialog.ShowAsync() == ContentDialogResult.Primary) _controller.SubmitFeedback(feedback);
    }

    /// Tous les sons (comme le Mac) : pour chacun mal rangé, sa bonne famille ou sorte (mêmes choix que l'aperçu).
    private void FeedbackSounds(StackPanel body, OrganizerFeedback feedback, System.Action rebuild)
    {
        body.Children.Add(Label(Loc.T("Quels sons étaient mal rangés ?"), 13, Text, semibold: true));
        var correctable = _controller.Correctable;
        if (correctable.Count == 0) return;
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
            var name = new TextBlock { Text = item.Name.Length == 0 ? Loc.T("Sans nom") : item.Name, FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
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
        body.Children.Add(Note(Loc.T("Un son rangé d'après son nom : ta réponse est retenue pour ce nom, sur ce PC.")));
    }

    // ---------- Fichier et dossier montrés ----------

    /// « Choisir le fichier… » : le projet ouvert dans FL, montré par la personne.
    private bool ChooseProject()
    {
        var path = FileDialogs.PickFile(_hwnd, Loc.T("Choisis le fichier du projet ouvert dans FL."), "FL Studio (.flp)", "flp");
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
            CornerRadius = new CornerRadius(0);
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
                PointerExited += (_, _) => BorderBrush = Brush(LineColor);
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

    /// Relier FL en trois étapes, une consigne à la fois (comme le Mac) : « ÉTAPE n SUR 3 », la consigne en grand avec son
    /// point carré, une phrase ; dessous, les trois étapes (la faite cochée, celle en cours en rouge).
    private static StackPanel LinkSteps(int current, string detail)
    {
        var names = new[] { Loc.T("Installe le lien"), Loc.T("Quitte et rouvre FL"), Loc.T("Options › MIDI Settings") };
        var panel = new StackPanel { Spacing = 8 };
        panel.Children.Add(SwissLabel(Loc.F("Étape %lld sur 3", current), 11, Red));
        var big = SwissTitle(30);
        big.Text = names[Math.Clamp(current, 1, 3) - 1].ToLower(System.Globalization.CultureInfo.CurrentCulture);
        var title = PageTitle(big, 30);
        title.HorizontalAlignment = HorizontalAlignment.Left;
        panel.Children.Add(title);
        if (detail.Length > 0) panel.Children.Add(Paragraph(detail, 13));
        var list = new StackPanel { Margin = new Thickness(0, 10, 0, 0) };
        for (var i = 0; i < 3; i++)
        {
            var n = i + 1;
            var row = new Grid { MinHeight = 36, ColumnSpacing = 12, BorderBrush = Brush(Faint), BorderThickness = new Thickness(0, 1, 0, 0) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var number = Label("0" + n, 12, n == current ? Red : Secondary, bold: true);
            row.Children.Add(number);
            var name = Label(names[i], 14, n == current ? Text : Secondary, bold: true);
            Grid.SetColumn(name, 1);
            row.Children.Add(name);
            if (n < current)
            {
                var check = Icon("check", 11, Text);
                check.VerticalAlignment = VerticalAlignment.Center;
                Grid.SetColumn(check, 2);
                row.Children.Add(check);
            }
            list.Children.Add(row);
        }
        panel.Children.Add(list);
        return panel;
    }

    /// « Couleurs de base » (Options, 05/11, comme le Mac) : une ligne par famille, ses couleurs proposées ; la choisie
    /// entourée d'encre. Gardée tout de suite pour les prochaines fois.
    private async void ShowBaseColors()
    {
        if (Content?.XamlRoot is not { } root) return;
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Style = MainShell.DialogStyle(),
            RequestedTheme = MacLook.SurfaceTheme,
            Background = Brush(WindowColor),
            BorderBrush = Brush(LineColor),
            PrimaryButtonText = Loc.T("OK"),
            SecondaryButtonText = Loc.T("Couleurs d'origine"),
            DefaultButton = ContentDialogButton.Primary,
        };
        var rows = new StackPanel();
        void Fill()
        {
            rows.Children.Clear();
            foreach (var family in new[] { SoundFamily.Drums, SoundFamily.Bass, SoundFamily.Melody, SoundFamily.Vocals, SoundFamily.Fx })
            {
                var current = _controller.StyleOf(family).Color;
                var row = new Grid { MinHeight = 46, ColumnSpacing = 14, BorderBrush = Brush(Faint), BorderThickness = new Thickness(0, 0, 0, 1) };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(90) });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                var name = Label(family.Label(), 15, Text, bold: true);
                row.Children.Add(name);
                var swatches = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
                foreach (var color in FamilyStyles.Palette)
                {
                    var picked = color;
                    var chosen = picked == current;
                    var swatch = new Button
                    {
                        Style = PlainButton,
                        Width = 28,
                        Height = 28,
                        Padding = new Thickness(chosen ? 2 : 0),
                        BorderBrush = Brush(Text),
                        BorderThickness = new Thickness(chosen ? 1 : 0),
                        Content = new Border { Background = Brush(ColorOf(picked)), BorderBrush = Brush(Text), BorderThickness = new Thickness(chosen ? 2 : 0) },
                    };
                    swatch.Click += (_, _) =>
                    {
                        _controller.SetBaseColor(family, picked);
                        Fill();
                    };
                    AutomationProperties.SetName(swatch, family.Label() + " #" + picked.Hex);
                    swatches.Children.Add(swatch);
                }
                swatches.Children.Add(WheelButton(family, current, Fill));
                Grid.SetColumn(swatches, 1);
                row.Children.Add(swatches);
                rows.Children.Add(row);
            }
        }
        Fill();
        var heading = SwissTitle(32);
        heading.Text = Loc.T("Couleurs de base").ToLower(System.Globalization.CultureInfo.CurrentCulture);
        var head = new StackPanel { Padding = new Thickness(0, 0, 0, 10), BorderBrush = Brush(Text), BorderThickness = new Thickness(0, 0, 0, 1) };
        head.Children.Add(PageTitle(heading, 32));
        dialog.Content = new StackPanel { Spacing = 14, MinWidth = 480, Children = { head, rows } };
        dialog.SecondaryButtonClick += (_, e) =>
        {
            e.Cancel = true;
            _controller.ResetBaseColors();
            Fill();
        };
        await dialog.ShowAsync();
        Render();
    }

    /// Le « + » au bout d'une ligne des couleurs de base (05/11 : « il faut + la roue de couleur qu'il y a déjà ») :
    /// la roue des couleurs dans une bulle, comme le choix de couleur d'une famille. Une couleur prise dans la roue
    /// s'y montre, entourée comme une couleur choisie.
    private Button WheelButton(SoundFamily family, RgbColor current, Action refresh)
    {
        var custom = !FamilyStyles.Palette.Contains(current);
        var face = new Border
        {
            Background = Brush(custom ? ColorOf(current) : WindowColor),
            BorderBrush = Brush(Text),
            BorderThickness = new Thickness(custom ? 2 : 1.5),
            Child = custom ? null : new TextBlock
            {
                Text = "+", FontSize = 17, FontWeight = Microsoft.UI.Text.FontWeights.Bold, Foreground = Brush(Text),
                HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, -3, 0, 0),
            },
        };
        var button = new Button
        {
            Style = PlainButton,
            Width = 28,
            Height = 28,
            Padding = new Thickness(custom ? 2 : 0),
            BorderBrush = Brush(Text),
            BorderThickness = new Thickness(custom ? 1 : 0),
            Content = face,
        };
        var body = new StackPanel();
        var flyout = new Flyout { Content = body, FlyoutPresenterStyle = FlatFlyout() };
        body.Children.Add(ColorSelector(current, picked =>
        {
            flyout.Hide();
            _app.RememberColor(picked);
            _controller.SetBaseColor(family, picked);
            refresh();
        }));
        button.Flyout = flyout;
        ToolTipService.SetToolTip(button, Loc.T("Choisir une autre couleur"));
        AutomationProperties.SetName(button, family.Label() + " : " + Loc.T("Choisir une autre couleur"));
        return button;
    }

    /// Cadre d'une bulle au style suisse : noir plein, trait fin, coins carrés, sans marge (le contenu a la sienne).
    private static Style FlatFlyout()
    {
        var style = new Style(typeof(FlyoutPresenter));
        style.Setters.Add(new Setter(Control.PaddingProperty, new Thickness(0)));
        style.Setters.Add(new Setter(Control.BackgroundProperty, Brush(WindowColor)));
        style.Setters.Add(new Setter(Control.BorderBrushProperty, Brush(LineColor)));
        style.Setters.Add(new Setter(Control.BorderThicknessProperty, new Thickness(1)));
        style.Setters.Add(new Setter(Control.CornerRadiusProperty, new CornerRadius(0)));
        style.Setters.Add(new Setter(FrameworkElement.MaxWidthProperty, 420.0));
        return style;
    }

    /// La fenêtre de couleur de FL (FlColorSelector, comme le Mac), avec les 10 récentes de ce PC ou du compte.
    private UIElement ColorSelector(RgbColor initial, Action<RgbColor> accept)
    {
        var recent = _app.RecentColors.Select(h => RgbColor.FromHex(h)).OfType<RgbColor>().ToList();
        return new FlColorSelector(initial, recent, accept).View;
    }

}
