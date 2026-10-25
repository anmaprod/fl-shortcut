// La fenêtre de l'Organiser sur Windows : mêmes étapes et mêmes textes que sur le Mac (Sources/FLShortcut/OrganizerWindow.swift),
// le contrôleur est celui du cœur (OrganizerController, testé). Lien à installer, attente de FL (nouvel essai tout
// seul), écoute, aperçu par famille (couleur ou dégradé, ce qu'est chaque son, « Écrire… », la case du Mixer tirée comme
// dans FL, le départ de chaque famille, familles glissées comme des dossiers), « Organiser », « Revenir comme avant »,
// « Pas content ? ». Toujours devant FL ; construite en code (pas de XAML).
using FLShortcut.App.Native;
using FLShortcut.App.Services;
using FLShortcut.Core;
using FLShortcut.Core.Organizer;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Input;
using Microsoft.UI.Text;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.ApplicationModel.DataTransfer;
using Windows.System;
using Windows.UI;
using Windows.UI.Core;

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

    /// Couleur de l'Organiser (comme l'indigo du Mac).
    private static readonly Color Tint = Color.FromArgb(0xFF, 0x5E, 0x5C, 0xE6);
    private const string DragPrefix = "organiser-famille:";

    private readonly AppController _app;
    private readonly OrganizerController _controller;
    private readonly IntPtr _hwnd;
    private readonly StackPanel _content = new() { Spacing = 12 };
    private readonly StackPanel _left = new() { Orientation = Orientation.Horizontal, Spacing = 8 };
    private readonly StackPanel _right = new() { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Right };
    private bool _closing;
    private SoundFamily? _dragging;

    /// Mode photos (CI) : un écran donné, avec des sons d'exemple ; rien n'est envoyé à FL.
    public static OrganizerWindow Demo(AppController app, string screen) => new(app, screen);

    private OrganizerWindow(AppController app, string? demo = null)
    {
        _app = app;
        _hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        Title = Loc.T("Organiser le projet");
        // Les photos ne voient pas le fond Mica : fond uni pour elles.
        if (demo is null && MicaController.IsSupported()) SystemBackdrop = new MicaBackdrop { Kind = MicaKind.Base };
        else if (demo is null && DesktopAcrylicController.IsSupported()) SystemBackdrop = new DesktopAcrylicBackdrop();
        var scale = Win32.GetDpiForWindow(_hwnd) / 96.0;
        AppWindow.Resize(new Windows.Graphics.SizeInt32((int)(580 * scale), (int)(760 * scale)));
        if (AppWindow.Presenter is OverlappedPresenter presenter)
        {
            presenter.IsAlwaysOnTop = true;              // reste visible pendant que FL est devant
            presenter.IsMinimizable = false;
        }

        var root = new Grid { Padding = new Thickness(22, 18, 22, 18), RowSpacing = 14 };
        if (SystemBackdrop is null) root.Background = Res("ApplicationPageBackgroundThemeBrush");
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var header = Header();
        var scroll = new ScrollViewer { Content = _content, Padding = new Thickness(0, 0, 12, 0) };
        var footer = new Grid();
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        footer.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        footer.Children.Add(_left);
        Grid.SetColumn(_right, 1);
        footer.Children.Add(_right);
        Grid.SetRow(scroll, 1);
        Grid.SetRow(footer, 2);
        root.Children.Add(header);
        root.Children.Add(scroll);
        root.Children.Add(footer);
        Content = root;

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
        Render();
        if (demo is null) _controller.Start();
        else _controller.ShowDemo(demo);
    }

    // ---------- Petits morceaux ----------

    /// Pinceau du thème ; clé absente (autre version du Windows App SDK) : gris, au lieu de faire tomber la fenêtre.
    private static Brush Res(string key)
    {
        try
        {
            if (Application.Current.Resources[key] is Brush brush) return brush;
        }
        catch (Exception) { }                     // KeyNotFoundException ou COMException selon la projection
        return new SolidColorBrush(Microsoft.UI.Colors.Gray);
    }

    private static SolidColorBrush Fill(RgbColor c, byte alpha = 0xFF) => new(Color.FromArgb(alpha, c.R, c.G, c.B));

    private static TextBlock Label(string text, double size = 13, bool bold = false, bool secondary = false) => new()
    {
        Text = text,
        FontSize = size,
        TextWrapping = TextWrapping.Wrap,
        FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal,
        Foreground = Res(secondary ? "TextFillColorSecondaryBrush" : "TextFillColorPrimaryBrush"),
    };

    private static Border Card(UIElement child, Color? tint = null, double padding = 14) => new()
    {
        Child = child,
        Padding = new Thickness(padding),
        CornerRadius = new CornerRadius(8),
        Background = Res("CardBackgroundFillColorDefaultBrush"),
        BorderBrush = new SolidColorBrush(tint is { } t ? Color.FromArgb(0x80, t.R, t.G, t.B) : Color.FromArgb(0x59, Tint.R, Tint.G, Tint.B)),
        BorderThickness = new Thickness(1),
    };

    private static Button Btn(string text, Action click, bool accent = false, string? tip = null)
    {
        var button = new Button { Content = text };
        if (accent) button.Style = (Style)Application.Current.Resources["AccentButtonStyle"];
        button.Click += (_, _) => click();
        if (tip is not null) ToolTipService.SetToolTip(button, tip);
        return button;
    }

    private static FontIcon Glyph(string glyph, double size = 14, Brush? color = null) => new()
    {
        Glyph = glyph,
        FontSize = size,
        Foreground = color ?? Res("TextFillColorSecondaryBrush"),
    };

    /// Une ligne : une icône (ou un badge), puis le texte qui prend la place.
    private static Grid Row(UIElement first, UIElement rest, double spacing = 12)
    {
        var grid = new Grid { ColumnSpacing = spacing };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        if (first is FrameworkElement f) f.VerticalAlignment = VerticalAlignment.Center;
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

    private static Grid Badge(string glyph, Color tint)
    {
        var grid = new Grid { Width = 36, Height = 36 };
        grid.Children.Add(new Ellipse { Fill = new SolidColorBrush(Color.FromArgb(0x33, tint.R, tint.G, tint.B)) });
        grid.Children.Add(new FontIcon { Glyph = glyph, FontSize = 16, Foreground = new SolidColorBrush(tint) });
        return grid;
    }

    private static Grid Step(int n, string text)
    {
        var number = new Grid { Width = 22, Height = 22, VerticalAlignment = VerticalAlignment.Top };
        number.Children.Add(new Ellipse { Fill = new SolidColorBrush(Tint) });
        number.Children.Add(new TextBlock
        {
            Text = n.ToString(), FontSize = 11, FontWeight = FontWeights.Bold, Foreground = new SolidColorBrush(Microsoft.UI.Colors.White),
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
        });
        return Row(number, Label(text, 12), 10);
    }

    private UIElement Header()
    {
        var icon = Badge("\uE8FD", Tint);
        icon.Width = icon.Height = 42;
        return Row(icon, Stack(2, Label(Loc.T("Organiser le projet"), 18, bold: true),
            Label(Loc.T("Range, colore et renomme tout le projet"), 12, secondary: true)), 14);
    }

    // ---------- Les étapes ----------

    private void Render()
    {
        if (_closing) return;
        _content.Children.Clear();
        _left.Children.Clear();
        _right.Children.Clear();
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
                        ? Loc.T("Ton projet d'origine se rouvre dans FL, tel qu'il était. La copie rangée reste à côté, si tu la veux.")
                        : Loc.T("FL est revenu comme avant.")),
                    u.Error is null, u.Error?.Is(OrganizerError.Kinds.NoResponse) == true);
                break;
            case OrganizerPhase.Failed f:
                Ending(f.Message, false, false);
                break;
        }
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
        _content.Children.Add(Card(Row(new ProgressRing { IsActive = true, Width = 20, Height = 20 }, Label(text))));
    }

    private void Setup()
    {
        _content.Children.Add(Card(Row(Badge("\uE71B", Tint), Stack(4,
            Label(Loc.T("Un petit lien avec FL, une seule fois"), 14, bold: true),
            Label(Loc.T("Organiser parle à FL par un script que FL Shortcuts installe dans FL Studio. Ensuite, tout se fait seul."), 12, secondary: true)))));
        PortsCard();
        _right.Children.Add(Btn(Loc.T("Fermer"), _controller.Close));
        _right.Children.Add(Btn(Loc.T("Installer le lien"), _controller.InstallLink, accent: true));
    }

    /// Les deux ports MIDI de loopMIDI manquent : rien ne peut passer entre FL Shortcuts et FL.
    private void PortsCard()
    {
        if (MidiLink.PortsExist()) return;
        var link = new HyperlinkButton
        {
            Content = Loc.T("Télécharger loopMIDI"),
            NavigateUri = new Uri("https://www.tobias-erichsen.de/software/loopmidi.html"),
            Padding = new Thickness(0),
        };
        _content.Children.Add(Card(Row(Badge("\uE7BA", Color.FromArgb(0xFF, 0xF7, 0x93, 0x1E)), Stack(4,
            Label(Loc.T("Crée d'abord les deux ports MIDI"), 14, bold: true),
            Label(Loc.T("Ouvre loopMIDI et crée deux ports nommés exactement « FL Shortcuts » et « FL Shortcuts Retour » (loopMIDI doit rester ouvert). FL Shortcuts les voit tout seul."), 12, secondary: true),
            link)), Color.FromArgb(0xFF, 0xF7, 0x93, 0x1E)));
    }

    private static (string Glyph, string Title, string Detail) WaitText(OrganizerWait reason) => reason switch
    {
        OrganizerWait.RestartFl => ("\uE72C", Loc.T("Quitte et rouvre FL Studio"),
            Loc.T("Le lien est prêt : FL le lit en démarrant. Dans FL : Options › MIDI Settings, entrée « FL Shortcuts » sur le Controller type « FL Shortcuts », et la sortie « FL Shortcuts Retour » sur le même numéro de Port.")),
        OrganizerWait.NoResponse => ("\uE704", Loc.T("En attente de FL Studio"),
            Loc.T("FL ne répond pas encore. Dans FL › Options › MIDI Settings › Output, « FL Shortcuts » doit s'afficher à côté de « FL Shortcuts Retour », seul sur son Port. Sinon : « Ça ne marche toujours pas ? » ci-dessous.")),
        OrganizerWait.WrongInput => ("\uE839", Loc.T("Le lien est sur la mauvaise entrée"),
            Loc.T("Dans FL : Options › MIDI Settings › Input, ta carte son (ou ton clavier) a le Controller type « FL Shortcuts ». Remets-la sur « (generic controller) », puis clique la ligne « FL Shortcuts » et choisis « FL Shortcuts ».")),
        OrganizerWait.OpenFl => ("\uE737", Loc.T("Ouvre FL Studio"), Loc.T("Organiser commence dès que FL est ouvert, avec ton projet.")),
        _ => ("\uE71A", Loc.T("Arrête la lecture dans FL"), Loc.T("Organiser écoute chaque son seul : FL doit être à l'arrêt.")),
    };

    private void Waiting(OrganizerWait reason)
    {
        var (glyph, title, detail) = WaitText(reason);
        var tint = reason == OrganizerWait.StopPlayback ? Color.FromArgb(0xFF, 0xF7, 0x93, 0x1E) : Tint;
        _content.Children.Add(Card(Row(Badge(glyph, tint), Stack(4, Label(title, 14, bold: true), Label(detail, 12, secondary: true)), 16), tint));
        _content.Children.Add(Row(new ProgressRing { IsActive = true, Width = 14, Height = 14 },
            Label(Loc.T("Organiser continue tout seul dès que FL est prêt."), 11, secondary: true), 8));
        if (reason is OrganizerWait.NoResponse or OrganizerWait.RestartFl or OrganizerWait.WrongInput)
        {
            PortsCard();
            var toggle = new HyperlinkButton { Content = Loc.T("Ça ne marche toujours pas ?"), Padding = new Thickness(0) };
            toggle.Click += (_, _) =>
            {
                _controller.ShowLinkHelp = !_controller.ShowLinkHelp;
                Render();
            };
            _content.Children.Add(toggle);
            if (_controller.ShowLinkHelp) LinkHelp();
        }
        _left.Children.Add(DiagnosticButton());
        _right.Children.Add(Btn(Loc.T("Fermer"), _controller.Close));
        _right.Children.Add(Btn(Loc.T("Réessayer maintenant"), _controller.Retry));
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

    private void ScriptCard()
    {
        var place = _controller.ScriptPlace;
        var present = place?.Present == true;
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        if (present) buttons.Children.Add(Btn(Loc.T("Afficher dans l'Explorateur"), _controller.RevealScript));
        buttons.Children.Add(Btn(Loc.T("Autre dossier de FL…"), _controller.InstallLinkElsewhere));
        var where = place is { } p ? System.IO.Path.GetDirectoryName(p.Path) ?? p.Path : Loc.T("Aucun dossier enregistré.");
        var text = Label(where, 11, secondary: true);
        text.IsTextSelectionEnabled = true;
        var orange = Color.FromArgb(0xFF, 0xF7, 0x93, 0x1E);
        _content.Children.Add(Card(Stack(8,
            Row(Glyph(present ? "\uE8A5" : "\uE9CE", 15, new SolidColorBrush(present ? Tint : orange)),
                Stack(2, Label(present ? Loc.T("Script du lien") : Loc.T("Script introuvable dans FL Studio"), 12, bold: true), text), 10),
            buttons), present ? Tint : orange, 12));
    }

    private void Listening(int done, int total)
    {
        var title = total == 0 ? Loc.T("Préparation de l'analyse…") : Loc.F("Analyse du projet : %lld sur %lld", Math.Min(done + 1, total), total);
        var head = new Grid();
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        head.Children.Add(Label(title, 13, bold: true));
        if (total > 0)
        {
            var percent = Label($"{Math.Round(done * 100.0 / Math.Max(total, 1))} %", 12, secondary: true);
            Grid.SetColumn(percent, 1);
            head.Children.Add(percent);
        }
        var bar = new ProgressBar { Maximum = Math.Max(total, 1), Value = done, IsIndeterminate = total == 0 };
        _content.Children.Add(Card(Row(Badge("\uE995", Tint), Stack(8, head, bar))));
        _content.Children.Add(Label(Loc.T("FL enregistre ton projet, puis FL Shortcuts lit son fichier : ce que joue chaque pattern et où est chaque clip, exactement (rien n'est deviné). Un son dont le nom dit ce qu'il est (Kick, 808, Hat…) est classé tout de suite ; les autres jouent seuls, à ton tempo, sans que tu les entendes. Ne touche pas à FL ; Échap arrête."), 11, secondary: true));
        _right.Children.Add(Btn(Loc.T("Arrêter"), _controller.Close));
    }

    private void Ending(string text, bool ok, bool linkHelp)
    {
        var tint = ok ? Color.FromArgb(0xFF, 0x34, 0xC7, 0x59) : Color.FromArgb(0xFF, 0xF7, 0x93, 0x1E);
        _content.Children.Add(Card(Row(Badge(ok ? "\uE73E" : "\uE7BA", tint), Label(text)), tint));
        if (linkHelp) LinkHelp();
        if (_controller.CanUndo) _left.Children.Add(Btn(Loc.T("Revenir comme avant"), _controller.Undo));
        else if (_controller.Phase is OrganizerPhase.Failed || _controller.Phase is OrganizerPhase.Applied { Error: not null })
            _left.Children.Add(DiagnosticButton());
        if (_controller.CanGiveFeedback)
            _left.Children.Add(Btn(Loc.T("Pas content ?"), ShowFeedback, tip: Loc.T("Dis ce qui n'allait pas : l'IA apprend de ses erreurs")));
        if (_controller.CanRetry && _controller.ProjectMissing)
        {
            _right.Children.Add(Btn(Loc.T("Fermer"), _controller.Close));
            _right.Children.Add(Btn(Loc.T("Réessayer"), _controller.Retry));
            _right.Children.Add(Btn(Loc.T("Choisir le fichier…"), _controller.ChooseProject, accent: true));
        }
        else if (_controller.CanRetry)
        {
            _right.Children.Add(Btn(Loc.T("Fermer"), _controller.Close));
            _right.Children.Add(Btn(Loc.T("Réessayer"), _controller.Retry, accent: true));
        }
        else
        {
            _right.Children.Add(Btn(Loc.T("Fermer"), _controller.Close, accent: true));
        }
    }

    private Button DiagnosticButton() => Btn(_controller.Copied ? Loc.T("Copié") : Loc.T("Copier le diagnostic"), _controller.CopyDiagnostic,
        tip: Loc.T("Copie un court texte technique (versions, autorisations, ce que l'écoute a reçu), sans aucun nom de son ni de piste : colle-le dans ton message pour qu'on trouve ce qui bloque."));

    // ---------- L'aperçu ----------

    private void Preview()
    {
        _content.Children.Add(Label(Loc.T("Chaque son est rangé d'après son nom (« BEAM KICK » : Kick), sinon d'après son écoute. Clique sur Kick, 808… pour le changer, ou « Écrire… » pour lui donner ton nom : tout le projet suit (Channel rack, patterns, Mixer, Playlist). Glisse une famille par sa poignée pour changer leur ordre."), 12, secondary: true));
        if (_controller.Options.Mixer)
        {
            var auto = Btn(Loc.T("Rangement automatique"), _controller.AutoArrange,
                tip: Loc.T("Oublie les places choisies : chaque famille à la suite, dans l'ordre du Channel rack"));
            auto.IsEnabled = _controller.PlacesChosen;
            var row = new Grid { ColumnSpacing = 8 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var icon = Glyph("\uE9E9", 12, new SolidColorBrush(Tint));
            icon.VerticalAlignment = VerticalAlignment.Center;
            var text = Label(Loc.T("Mixer : tire le numéro d'un son ou d'une famille, comme dans FL."), 11, secondary: true);
            text.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(text, 1);
            Grid.SetColumn(auto, 2);
            row.Children.Add(icon);
            row.Children.Add(text);
            row.Children.Add(auto);
            _content.Children.Add(row);
        }
        var colors = _controller.PlannedColors;
        foreach (var family in _controller.PresentFamilies) _content.Children.Add(FamilyCard(family, colors));
        _content.Children.Add(Summary());
        _left.Children.Add(Btn(Loc.T("Annuler"), _controller.Close));
        _left.Children.Add(DiagnosticButton());
        _right.Children.Add(Btn(Loc.T("Organiser"), _controller.Apply, accent: true));
    }

    private UIElement FamilyCard(SoundFamily family, IReadOnlyDictionary<int, RgbColor> colors)
    {
        var style = _controller.StyleOf(family);
        var members = _controller.Members(family);
        var stack = new StackPanel { Spacing = 6 };

        // La poignée : la famille se glisse au-dessus ou en dessous d'une autre, comme un dossier.
        var grip = new Border { Width = 18, Height = 26, Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent), CanDrag = true };
        grip.Child = Glyph("\uE76F", 12);
        ToolTipService.SetToolTip(grip, Loc.T("Glisse la famille au-dessus ou en dessous d'une autre : le Channel rack, le Mixer et la Playlist suivent cet ordre"));
        grip.DragStarting += (_, e) =>
        {
            _dragging = family;
            e.Data.SetText(DragPrefix + family.Raw());
            e.Data.RequestedOperation = DataPackageOperation.Move;
        };
        grip.DropCompleted += (_, _) => _dragging = null;

        var dot = new Ellipse { Width = 22, Height = 22, Fill = Fill(style.Color) };
        var name = Label(family.Label(), 13, bold: true);
        name.VerticalAlignment = VerticalAlignment.Center;
        var count = new Border
        {
            CornerRadius = new CornerRadius(9), Padding = new Thickness(7, 1, 7, 1), VerticalAlignment = VerticalAlignment.Center,
            Background = Res("SubtleFillColorSecondaryBrush"), Child = Label(members.Count.ToString(), 11, bold: true, secondary: true),
        };
        var fade = new ComboBox { Items = { Loc.T("Une couleur"), Loc.T("Dégradé") }, SelectedIndex = style.Fade is null ? 0 : 1, MinWidth = 120 };
        fade.SelectionChanged += (_, _) => _controller.UpdateStyle(family, s => s with
        {
            Fade = fade.SelectedIndex == 1 ? s.Color.Lerp(new RgbColor(0, 0, 0), 0.45) : null,
        });
        var tools = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
        tools.Children.Add(fade);
        tools.Children.Add(Swatch(style.Color, picked => _controller.UpdateStyle(family, s => s with { Color = picked })));
        if (style.Fade is { } last) tools.Children.Add(Swatch(last, picked => _controller.UpdateStyle(family, s => s with { Fade = picked })));
        tools.Children.Add(SmallButton("\uE70E", Loc.T("Monter la famille"), () => _controller.ShiftFamily(family, -1)));
        tools.Children.Add(SmallButton("\uE70D", Loc.T("Descendre la famille"), () => _controller.ShiftFamily(family, 1)));

        var head = new Grid { ColumnSpacing = 8 };
        foreach (var width in new[] { GridLength.Auto, GridLength.Auto, GridLength.Auto, GridLength.Auto, new GridLength(1, GridUnitType.Star), GridLength.Auto })
            head.ColumnDefinitions.Add(new ColumnDefinition { Width = width });
        UIElement[] cells = { grip, dot, name, count, new Border(), tools };
        for (var i = 0; i < cells.Length; i++)
        {
            Grid.SetColumn((FrameworkElement)cells[i], i);
            head.Children.Add(cells[i]);
        }
        stack.Children.Add(head);

        if (_controller.Options.Mixer && _controller.MixerRange(family) is { } range)
        {
            var mixer = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, Margin = new Thickness(26, 0, 0, 0) };
            mixer.Children.Add(Label(Loc.T("Mixer"), 11, secondary: true));
            var box = new SlotBox(style.MixerStart ?? range.First, style.MixerStart is not null, _controller.MixerLast,
                start => _controller.SetMixerStart(family, start));
            ToolTipService.SetToolTip(box, Loc.T("Première piste du Mixer de la famille (son bus compris ; la 808 avec les drums) : tire vers le haut ou le bas comme dans FL, ou clique pour l'écrire"));
            mixer.Children.Add(box);
            mixer.Children.Add(Glyph("\uE72A", 10));
            mixer.Children.Add(Label(range.Last.ToString(), 11, secondary: true));
            foreach (var child in mixer.Children) ((FrameworkElement)child).VerticalAlignment = VerticalAlignment.Center;
            stack.Children.Add(mixer);
        }
        foreach (var member in members) stack.Children.Add(MemberRow(family, member, colors.TryGetValue(member.Id, out var c) ? c : style.Color));

        var card = Card(stack, Color.FromArgb(0xFF, style.Color.R, style.Color.G, style.Color.B), 12);
        card.AllowDrop = true;
        var normal = card.BorderThickness;
        card.DragOver += (_, e) =>
        {
            if (_dragging is not { } dragged || dragged == family) return;
            e.AcceptedOperation = DataPackageOperation.Move;
            card.BorderThickness = new Thickness(1, 4, 1, 1);
        };
        card.DragLeave += (_, _) => card.BorderThickness = normal;
        card.Drop += (_, _) =>
        {
            card.BorderThickness = normal;
            if (_dragging is { } dragged && dragged != family) _controller.MoveFamily(dragged, family);
            _dragging = null;
        };
        var menu = new MenuFlyout();
        menu.Items.Add(MenuItem(Loc.T("Monter la famille"), () => _controller.ShiftFamily(family, -1)));
        menu.Items.Add(MenuItem(Loc.T("Descendre la famille"), () => _controller.ShiftFamily(family, 1)));
        card.ContextFlyout = menu;
        return card;
    }

    private static MenuFlyoutItem MenuItem(string text, Action click)
    {
        var item = new MenuFlyoutItem { Text = text };
        item.Click += (_, _) => click();
        return item;
    }

    private static Button SmallButton(string glyph, string tip, Action click)
    {
        var button = new Button { Content = new FontIcon { Glyph = glyph, FontSize = 10 }, Padding = new Thickness(6, 4, 6, 4) };
        ToolTipService.SetToolTip(button, tip);
        button.Click += (_, _) => click();
        return button;
    }

    /// La pastille d'une couleur : un clic ouvre le choix de couleur de Windows.
    private static Button Swatch(RgbColor color, Action<RgbColor> set)
    {
        var button = new Button
        {
            Width = 30, Height = 22, Padding = new Thickness(0), CornerRadius = new CornerRadius(5),
            Background = Fill(color), BorderBrush = Res("ControlStrokeColorDefaultBrush"),
        };
        ToolTipService.SetToolTip(button, "#" + color.Hex);
        var picker = new ColorPicker
        {
            Color = Color.FromArgb(0xFF, color.R, color.G, color.B), IsAlphaEnabled = false, IsMoreButtonVisible = false,
            IsColorChannelTextInputVisible = false, IsHexInputVisible = true,
        };
        var flyout = new Flyout { Content = picker };
        flyout.Closed += (_, _) =>
        {
            var c = picker.Color;
            var picked = new RgbColor(c.R, c.G, c.B);
            if (picked != color) set(picked);
        };
        button.Flyout = flyout;
        return button;
    }

    private UIElement MemberRow(SoundFamily family, OrganizerController.Member member, RgbColor color)
    {
        var grid = new Grid { ColumnSpacing = 8 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var square = new Rectangle { Width = 12, Height = 12, RadiusX = 3, RadiusY = 3, Fill = Fill(color), VerticalAlignment = VerticalAlignment.Center };
        grid.Children.Add(square);

        var names = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
        names.Children.Add(new TextBlock { Text = member.Name.Length == 0 ? Loc.T("(sans nom)") : member.Name, FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis, MaxWidth = 190 });
        if (member.NewName is { } newName)
        {
            names.Children.Add(Glyph("\uE72A", 9));
            names.Children.Add(new TextBlock
            {
                Text = newName, FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis, MaxWidth = 150,
                Foreground = Res(member.Written ? "TextFillColorPrimaryBrush" : "TextFillColorSecondaryBrush"),
            });
        }
        if (member.TestNotes)
        {
            var note = Glyph("\uEC4F", 11);
            ToolTipService.SetToolTip(note, Loc.T("Muet dans ses patterns : classé avec deux notes d'essai. Vérifie sa famille."));
            names.Children.Add(note);
        }
        if (member.ByName)
        {
            var byName = Glyph("\uE8D2", 11);
            ToolTipService.SetToolTip(byName, Loc.T("Classé d'après son nom, sans l'écouter."));
            names.Children.Add(byName);
        }
        foreach (var child in names.Children) ((FrameworkElement)child).VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(names, 1);
        grid.Children.Add(names);

        if (_controller.Options.Mixer && (member.Slot is not null || member.Pinned))
        {
            var box = new SlotBox(member.Slot, member.Pinned, _controller.MixerLast, slot => _controller.SetSlot(member.Id, slot));
            ToolTipService.SetToolTip(box, Loc.T("Piste du Mixer de ce son : tire vers le haut ou le bas comme dans FL, ou clique pour l'écrire"));
            Grid.SetColumn(box, 2);
            grid.Children.Add(box);
        }

        // Ce qu'est le son (« BEAM KICK » : Kick), sinon sa famille ; chaque famille propose ses sortes ; en bas,
        // « Écrire… » pour lui donner son propre nom.
        var kind = new DropDownButton { Content = new TextBlock { Text = member.Kind?.Name() ?? family.Label(), FontSize = 11 }, Padding = new Thickness(8, 2, 6, 2) };
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
        buttons.Children.Add(Btn(Loc.T("Annuler"), flyout.Hide));
        buttons.Children.Add(Btn(Loc.T("OK"), Save, accent: true));
        flyout.Content = Stack(10, Label(Loc.T("Nom du son"), 12, bold: true), box, buttons);
        flyout.Opened += (_, _) => box.Focus(FocusState.Programmatic);
        flyout.ShowAt(anchor);
    }

    /// Ce que « Organiser » fera dans chaque page de FL, avec une case par page et une pour les noms.
    private UIElement Summary()
    {
        var stack = new StackPanel { Spacing = 7 };
        foreach (var line in _controller.Summary) stack.Children.Add(Row(Glyph("\uE73E", 10, new SolidColorBrush(Tint)), Label(line, 11, secondary: true), 8));
        var options = _controller.Options;
        var pages = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
        pages.Children.Add(Check(Loc.T("Channel rack"), options.Rack, on => _controller.SetOptions(_controller.Options with { Rack = on })));
        pages.Children.Add(Check(Loc.T("Patterns"), options.Patterns, on => _controller.SetOptions(_controller.Options with { Patterns = on })));
        pages.Children.Add(Check(Loc.T("Mixer"), options.Mixer, on => _controller.SetOptions(_controller.Options with { Mixer = on })));
        pages.Children.Add(Check(Loc.T("Playlist"), options.Playlist, on => _controller.SetOptions(_controller.Options with { Playlist = on })));
        stack.Children.Add(pages);
        stack.Children.Add(Check(Loc.T("Renommer simplement (Kick, Kick 2, 808…)"), options.Rename,
            on => _controller.SetOptions(_controller.Options with { Rename = on })));
        var buses = Check(Loc.T("Un bus par famille dans le Mixer (les 808 avec les drums), chaque son envoyé seulement à son bus"), options.Buses,
            on => _controller.SetOptions(_controller.Options with { Buses = on }));
        buses.IsEnabled = options.Mixer;
        stack.Children.Add(buses);
        stack.Children.Add(Check(_controller.OrganizesCopy
                ? Loc.T("Supprimer les sons sans aucune note de la copie rangée")
                : Loc.T("Supprimer les sons sans aucune note (on ne peut pas les remettre)"), options.DeleteUnused,
            on => _controller.SetOptions(_controller.Options with { DeleteUnused = on })));
        stack.Children.Add(Label(_controller.OrganizesCopy
            ? Loc.T("Tout se range dans une nouvelle version de ton projet (« _2 », comme « Save new version » de FL), à côté de l'original : ton projet d'origine ne bouge pas, « Revenir comme avant » le rouvre. Aucune lecture de l'écran.")
            : Loc.T("Les pistes de la Playlist sont remontées par leur menu (« Move up ») : FL Shortcuts lit alors la fenêtre de FL (autorisation « Enregistrement de l'écran »). Les patterns restent à leur place."),
            10, secondary: true));
        return Card(stack, padding: 12);
    }

    private static CheckBox Check(string text, bool on, Action<bool> set)
    {
        var box = new CheckBox { Content = new TextBlock { Text = text, FontSize = 11, TextWrapping = TextWrapping.Wrap }, IsChecked = on, MinWidth = 0 };
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
            body.Children.Add(Label(Loc.T("Coche tout ce qui ne va pas : l'IA apprend de ses erreurs."), 12, secondary: true));
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
                body.Children.Add(Label(Loc.T("Sur Windows, ce message ne part pas encore tout seul : après « Envoyer », clique sur « Copier le diagnostic » et colle-le-moi avec ce qui n'allait pas."), 11, secondary: true));
            dialog.IsPrimaryButtonEnabled = feedback.CanSend;
        }
        Build();
        if (await dialog.ShowAsync() == ContentDialogResult.Primary) _controller.SubmitFeedback(feedback);
    }

    /// Les sons écoutés : pour chacun mal rangé, sa bonne famille ou sorte (mêmes choix que l'aperçu).
    private void FeedbackSounds(StackPanel body, OrganizerFeedback feedback, System.Action rebuild)
    {
        body.Children.Add(Label(Loc.T("Quels sons étaient mal rangés ?"), 13, bold: true));
        var correctable = _controller.Correctable;
        if (correctable.Count == 0)
        {
            body.Children.Add(Label(Loc.T("Aucun son n'a été écouté : tous ont été rangés d'après leur nom. Change leur nom dans FL."), 12, secondary: true));
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
            var mark = Glyph(chosen is null ? "\uEA3A" : "\uEC61", 14,
                chosen is null ? null : new SolidColorBrush(Color.FromArgb(0xFF, 0x34, 0xC7, 0x59)));
            mark.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(button, 1);
            Grid.SetColumn(mark, 2);
            row.Children.Add(name);
            row.Children.Add(button);
            row.Children.Add(mark);
            body.Children.Add(row);
        }
        body.Children.Add(Label(Loc.T("Les sons rangés d'après leur nom n'y sont pas : l'IA ne les a pas écoutés."), 11, secondary: true));
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

    /// La case du numéro de piste du Mixer, comme celle du Channel rack de FL : on la tire vers le haut ou le bas pour
    /// changer le numéro, ou on clique pour l'écrire ; Alt + clic : automatique. Un numéro choisi est clair, un numéro
    /// automatique est gris ; « --- » : aucune piste. Le numéro suit la souris, il est posé au lâcher.
    private sealed class SlotBox : Grid
    {
        public SlotBox(int? value, bool chosen, int last, Action<int?> set)
        {
            Width = 40;
            Height = 22;
            CornerRadius = new CornerRadius(4);
            VerticalAlignment = VerticalAlignment.Center;
            Background = new SolidColorBrush(Color.FromArgb(0x47, 0, 0, 0));
            BorderBrush = chosen ? new SolidColorBrush(Tint) : Res("ControlStrokeColorDefaultBrush");
            BorderThickness = new Thickness(1);
            ProtectedCursor = InputSystemCursor.Create(InputSystemCursorShape.SizeNorthSouth);
            var label = new TextBlock
            {
                Text = value?.ToString() ?? "---", FontSize = 11, HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center, FontWeight = chosen ? FontWeights.SemiBold : FontWeights.Normal,
                Foreground = Res(chosen ? "TextFillColorPrimaryBrush" : "TextFillColorSecondaryBrush"),
            };
            Children.Add(label);
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
                label.Text = current.ToString();
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
            var box = new TextBox { Text = value?.ToString() ?? "", PlaceholderText = $"1…{last}", Width = 120 };
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
            buttons.Children.Add(Btn(Loc.T("Automatique"), () =>
            {
                set(null);
                flyout.Hide();
            }));
            buttons.Children.Add(Btn(Loc.T("OK"), Save, accent: true));
            flyout.Content = Stack(10, Label(Loc.T("Piste du Mixer"), 12, bold: true), box, buttons);
            flyout.Opened += (_, _) => box.Focus(FocusState.Programmatic);
            flyout.ShowAt(this);
        }
    }
}
