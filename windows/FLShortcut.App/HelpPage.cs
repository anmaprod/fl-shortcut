// Page Aide (Windows), comme HelpView du Mac (maquette « Minimal », 20/11) : deux onglets, Questions (recherche dans
// les questions fréquentes) et Mes messages (ce qu'on a écrit à l'équipe, sa réponse, « Répondre » ;
// supabase/mes-messages.sql) ; « Écrire à l'équipe » (en haut à droite de la page) ouvre sa page : le genre, le message
// (la case grandit avec le texte), une capture si on veut ; l'état de l'appli part tout seul (des nombres, jamais de
// nom de son ni de touche). Un compte est nécessaire pour écrire. Sans serveur ou s'il échoue : copie du message et
// ticket GitHub. Les champs ne redessinent jamais la page à chaque lettre (le texte tapé resterait sinon en route).
using System.Diagnostics;
using System.Reflection;
using FLShortcut.App.Services;
using FLShortcut.Core.Macros;
using FLShortcut.Core;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.ApplicationModel.DataTransfer;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Pickers;
using Windows.Storage.Streams;
using Windows.UI;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal sealed class HelpPage
{
    /// Couleur de la page Aide (comme SidebarItem.help du Mac).
    public static readonly Color Tint = Rgb(0x32, 0xAD, 0xE6);
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };

    private enum Screen { Questions, Messages, Write, Thread }

    private readonly AppController _app;
    private readonly Action _render;
    private readonly Action<string, Action?> _toast;
    private Screen _screen = Screen.Questions;
    private Guid? _thread;
    private string _query = "";
    private int? _open;
    private readonly HashSet<int> _tipsOpen = new();
    private bool _sending;
    private string? _problem;
    private string? _sentReference;
    private SupportMessage _message = new();
    private SupportKind? _kind;
    private BitmapImage? _captureImage;
    private string _reply = "";
    private bool _replySent;
    private string? _lastMacro;
    // Mes messages.
    private List<SupportThread> _threads = new();
    private bool? _ready;
    private bool _loading;
    private readonly Dictionary<Guid, BitmapImage> _captures = new();
    private readonly HashSet<Guid> _seen = new();

    /// Jeton du compte, rafraîchi s'il expire (09/11 : un jeton périmé faisait partir le message « non connecté ») ;
    /// null : pas de compte.
    public Func<Task<string?>> Token { get; set; } = () => Task.FromResult<string?>(null);
    /// Session du compte (rafraîchie), pour Mes messages ; null : pas de compte.
    public Func<Task<AccountSession?>> Session { get; set; } = () => Task.FromResult<AccountSession?>(null);
    /// Un compte est-il connecté (sans réseau) ?
    public Func<bool> SignedIn { get; set; } = () => false;
    /// « Se connecter » : la page Mon compte.
    public Action? SignIn { get; set; }
    /// Fenêtre de l'app, pour la boîte « Ajouter une capture ».
    public IntPtr Hwnd { get; set; }
    /// « Revoir le guide » : la fenêtre principale pose le guide sur elle (comme la feuille du Mac).
    public Action? ShowGuide { get; set; }
    /// Mode photos (CI) : des messages d'exemple, rien n'est envoyé.
    public bool Demo { get; set; }

    public HelpPage(AppController app, Action render, Action<string, Action?> toast)
    {
        _app = app;
        _render = render;
        _toast = toast;
        _app.MacroFinished += (ok, text) => _lastMacro = (ok ? "réussie" : "échec") + " — " + text;
        foreach (var id in (_app.Settings.SupportSeenReplies ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries))
            if (Guid.TryParse(id, out var g)) _seen.Add(g);
    }

    /// Adresse du serveur et clé publique écrites à la compilation (CI) ; null : pas de serveur.
    public static ServerConfig? Server
    {
        get
        {
            var meta = typeof(HelpPage).Assembly.GetCustomAttributes<AssemblyMetadataAttribute>().ToList();
            string? Value(string key) => meta.FirstOrDefault(m => m.Key == key)?.Value;
            return ServerConfig.Resolve(Value("FLSCommunityURL"), Value("FLSCommunityAnonKey"));
        }
    }

    public static string AppVersion
    {
        get
        {
            var v = typeof(HelpPage).Assembly.GetName().Version;
            return v is null ? "?" : $"{v.Major}.{v.Minor}.{v.Build}";
        }
    }

    /// « Signaler ce problème… » (macro ratée) : la page « Écrire à l'équipe », Un bug, l'erreur jointe.
    public void Report(string error)
    {
        StartWriting();
        _kind = SupportKind.Probleme;
        _message.Kind = SupportKind.Probleme;
        _message.Error = error;
    }

    /// Mode photos (CI) : « aide », « ecrire », « messages » ou « fil ».
    public void ShowScreen(string name)
    {
        Demo = true;
        _threads = DemoThreads();
        _ready = true;
        switch (name)
        {
            case "ecrire":
                Report("Macro : échec au bloc 3 (Attendre un menu) : aucun menu de FL ne s'est ouvert en 1,5 s.");
                _message.Text = "Je lançais ma macro « Armer la piste » depuis le Mixer.";
                break;
            case "messages": _screen = Screen.Messages; break;
            case "fil": _screen = Screen.Thread; _thread = _threads[0].Id; break;
            default: _screen = Screen.Questions; _open = 1; break;
        }
    }

    /// « Écrire à l'équipe » en haut de la page (comme le Mac) ; rien sur sa propre page.
    public FrameworkElement? HeaderWrite() => _screen == Screen.Write ? null : MinimalButton(Loc.T("Écrire à l'équipe"), () =>
    {
        StartWriting();
        _render();
    });

    /// Titre de la page (20/11 : un seul titre ; « Écrire à l'équipe » et un message ont le leur, comme le Mac).
    public string Title => _screen switch
    {
        Screen.Write => Loc.T("Écrire à l'équipe"),
        Screen.Thread => _threads.FirstOrDefault(t => t.Id == _thread)?.Kind.Label() ?? Loc.T("Aide"),
        _ => Loc.T("Aide"),
    };

    /// Unread : les nouvelles réponses de l'équipe (point rouge de l'onglet).
    public int Unread => SupportInbox.Unread(_threads, _seen);

    public FrameworkElement Content(int columns)
    {
        // Direction A (17/11, comme le Mac) : la colonne du titre.
        var page = new StackPanel { Spacing = 0, Padding = new Thickness(40, 4, 40, 32), MaxWidth = 1168, HorizontalAlignment = HorizontalAlignment.Left };
        switch (_screen)
        {
            case Screen.Write: page.Children.Add(WritePage(columns)); break;
            case Screen.Thread: page.Children.Add(ThreadPage()); break;
            default:
                page.Children.Add(Tabs());
                page.Children.Add(_screen == Screen.Messages ? MessagesPage() : QuestionsPage());
                break;
        }
        if (_ready is null && !_loading && SignedIn()) _ = Load();
        return page;
    }

    // ---------- Onglets ----------

    private FrameworkElement Tabs()
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 28 };
        row.Children.Add(Tab(Loc.T("Questions"), Screen.Questions, false));
        row.Children.Add(Tab(Loc.T("Mes messages"), Screen.Messages, SignedIn() && Unread > 0));
        var box = new Grid();
        box.Children.Add(new Border { BorderBrush = Brush(LineColor), BorderThickness = new Thickness(0, 0, 0, 1), IsHitTestVisible = false });
        box.Children.Add(row);
        return box;
    }

    private Button Tab(string title, Screen screen, bool dot)
    {
        var on = _screen == screen;
        var label = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 7, VerticalAlignment = VerticalAlignment.Center };
        // Maquette « Minimal » : le mot en 15 (demi-gras quand l'onglet est ouvert), plus de petites capitales.
        var text = Label(title, 15, on ? Text : Secondary, semibold: on);
        label.Children.Add(text);
        if (dot)
        {
            var mark = new Microsoft.UI.Xaml.Shapes.Rectangle { Width = 6, Height = 6, Fill = Brush(Red), VerticalAlignment = VerticalAlignment.Center };
            AutomationProperties.SetName(mark, Loc.T("Nouvelle réponse"));
            label.Children.Add(mark);
        }
        var button = new Button
        {
            Style = PlainButton,
            Padding = new Thickness(0),
            Height = 44,
            Content = new Border { Child = label, BorderBrush = Brush(Text), BorderThickness = new Thickness(0, 0, 0, on ? 2 : 0), Height = 44 },
        };
        button.Click += (_, _) =>
        {
            _screen = screen;
            if (screen == Screen.Messages) _ = Load();
            _render();
        };
        AutomationProperties.SetName(button, title);
        return button;
    }

    // ---------- Questions ----------

    private FrameworkElement QuestionsPage()
    {
        var stack = new StackPanel { Spacing = 20, Padding = new Thickness(0, 24, 0, 0) };
        stack.Children.Add(SearchField());
        var found = HelpContent.Faq.Where(e => e.Matches(_query)).ToList();
        stack.Children.Add(found.Count == 0 ? Paragraph(Loc.T("Aucune réponse."), 15, Secondary) : FaqList(found, id => _open == id, id =>
        {
            _open = _open == id ? null : id;
            _render();
        }));
        var guide = new HyperlinkButton { Content = Label(Loc.T("Revoir le guide"), 13, Text), Padding = new Thickness(0) };
        guide.Click += (_, _) => ShowGuide?.Invoke();
        stack.Children.Add(guide);
        return stack;
    }

    /// Recherche dans l'aide : une case bordée, la loupe devant (filtre à Entrée ou à la sortie du champ).
    private FrameworkElement SearchField()
    {
        var box = new TextBox
        {
            Text = _query,
            PlaceholderText = Loc.T("Rechercher dans l'aide"),
            FontSize = 15,
            FontFamily = SwissFont,
            Background = Brush(Colors.Transparent),
            BorderThickness = new Thickness(0),
            Padding = new Thickness(0, 6, 0, 6),
            VerticalAlignment = VerticalAlignment.Center,
        };
        AutomationProperties.SetName(box, Loc.T("Rechercher dans l'aide"));
        box.KeyDown += (_, e) => { if (e.Key == Windows.System.VirtualKey.Enter) Search(box.Text); };
        box.LostFocus += (_, _) => Search(box.Text);
        // Maquette « Minimal » : la case seule, sans loupe.
        var grid = new Grid();
        grid.Children.Add(box);
        return new Border
        {
            Child = grid,
            Height = 44,
            MaxWidth = 480,
            HorizontalAlignment = HorizontalAlignment.Left,
            Width = 480,
            Padding = new Thickness(14, 0, 14, 0),
            Background = Brush(MacLook.WindowColor),
            BorderBrush = Brush(Text),
            BorderThickness = new Thickness(2),
        };
    }

    private void Search(string text)
    {
        if (text == _query) return;
        _query = text;
        _open = null;
        _render();
    }

    /// Les questions en liste (▸ / ▾), un trait d'encre au-dessus, un trait fin entre elles.
    private static FrameworkElement FaqList(IEnumerable<HelpEntry> entries, Func<int, bool> isOpen, Action<int> toggle)
    {
        // Maquette « Minimal » (comme le Mac) : colonnes 1 à 8 de la grille, ▶ gris (▼ ouverte), question en 17 normal.
        var list = new StackPanel { MaxWidth = 720, HorizontalAlignment = HorizontalAlignment.Left };
        list.Children.Add(Rule2(Text));
        foreach (var entry in entries)
        {
            var open = isOpen(entry.Id);
            var head = new Grid { ColumnSpacing = 12 };
            head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
            head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var marker = Label(open ? "▼" : "▶", 10, Secondary);
            marker.VerticalAlignment = VerticalAlignment.Center;
            head.Children.Add(marker);
            var question = Label(entry.Question, 17, Text);
            question.TextWrapping = TextWrapping.Wrap;
            Grid.SetColumn(question, 1);
            head.Children.Add(question);
            var id = entry.Id;
            var button = new Button
            {
                Style = PlainButton,
                Content = head,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Stretch,
                Padding = new Thickness(12, 13, 12, 13),
            };
            button.Click += (_, _) => toggle(id);
            AutomationProperties.SetName(button, entry.Question + " — " + Loc.T(open ? "ouverte" : "fermée"));
            var cell = new StackPanel();
            cell.Children.Add(button);
            if (open) cell.Children.Add(Answer(entry.Answer));
            list.Children.Add(new Border { Child = cell, BorderBrush = Brush(LineColor), BorderThickness = new Thickness(0, 0, 0, 1) });
        }
        return list;
    }

    private static Microsoft.UI.Xaml.Shapes.Rectangle Rule2(Color color) => new() { Height = 2, Fill = Brush(color), IsHitTestVisible = false };

    /// La réponse : en étapes numérotées quand elle en a, sinon en un paragraphe.
    private static FrameworkElement Answer(string answer)
    {
        var stack = new StackPanel { Spacing = 10, Padding = new Thickness(23, 0, 0, 16) };
        var soft = Text;
        if (HelpEntry.Steps(answer) is not { } parsed)
        {
            stack.Children.Add(Paragraph(answer, 13.5, soft));
            return stack;
        }
        if (parsed.Intro.Length > 0) stack.Children.Add(Paragraph(parsed.Intro, 13.5, soft));
        for (var i = 0; i < parsed.Steps.Count; i++)
        {
            var row = new Grid { ColumnSpacing = 10 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var number = Label((i + 1).ToString(System.Globalization.CultureInfo.InvariantCulture) + ".", 13.5, Secondary);
            number.Width = 18;
            number.VerticalAlignment = VerticalAlignment.Top;
            row.Children.Add(number);
            var text = Paragraph(parsed.Steps[i], 13.5, soft);
            Grid.SetColumn(text, 1);
            row.Children.Add(text);
            stack.Children.Add(row);
        }
        return stack;
    }

    // ---------- Mes messages ----------

    private FrameworkElement MessagesPage()
    {
        var stack = new StackPanel { Spacing = 16, Padding = new Thickness(0, 24, 0, 0) };
        if (!SignedIn() && !Demo)
        {
            stack.Children.Add(SignInAsk(Loc.T("Connecte-toi pour retrouver tes messages.")));
            return stack;
        }
        if (_ready == false)
        {
            stack.Children.Add(Paragraph(Loc.T("Mes messages n'est pas encore ouvert."), 15, Secondary));
            return stack;
        }
        if (_threads.Count == 0)
        {
            stack.Children.Add(Paragraph(_loading || _ready is null ? Loc.T("Chargement…") : Loc.T("Aucun message."), 15, Secondary));
            return stack;
        }
        var list = new StackPanel();
        list.Children.Add(Rule2(Text));
        foreach (var thread in _threads) list.Children.Add(MessageRow(thread));
        stack.Children.Add(list);
        return stack;
    }

    /// Une ligne : la 1re ligne du message et son genre, la date, puis Envoyé / Réponse ✓ / Réponse ●.
    private FrameworkElement MessageRow(SupportThread thread)
    {
        var grid = new Grid { ColumnSpacing = 16 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(96) });
        var left = new StackPanel { Spacing = 3 };
        var first = Label(DisplayText.Safe(thread.FirstLine, 80), 15, Text, semibold: true);
        first.TextTrimming = TextTrimming.CharacterEllipsis;
        left.Children.Add(first);
        left.Children.Add(Label(thread.Kind.Label(), 12, Secondary));
        grid.Children.Add(left);
        var date = Label(SupportInbox.DateLabel(thread.CreatedAt), 12, Secondary);
        date.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(date, 1);
        grid.Children.Add(date);
        var state = SupportInbox.State(thread, _seen);
        FrameworkElement status = state switch
        {
            SupportState.Sent => Label(Loc.T("Envoyé"), 13, Secondary),
            SupportState.Answered => Label(Loc.T("Réponse ✓"), 13, Text, semibold: true),
            _ => new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 6,
                Children =
                {
                    Label(Loc.T("Réponse"), 13, Red, semibold: true),
                    new Microsoft.UI.Xaml.Shapes.Rectangle { Width = 6, Height = 6, Fill = Brush(Red), VerticalAlignment = VerticalAlignment.Center },
                },
            },
        };
        status.HorizontalAlignment = HorizontalAlignment.Right;
        status.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(status, 2);
        grid.Children.Add(status);
        var button = new Button
        {
            Style = PlainButton,
            Content = grid,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Padding = new Thickness(0, 14, 0, 14),
        };
        button.Click += (_, _) =>
        {
            _screen = Screen.Thread;
            _thread = thread.Id;
            _reply = "";
            _replySent = false;
            _problem = null;
            MarkSeen(thread);
            _ = LoadCapture(thread.Id);
            _render();
        };
        AutomationProperties.SetName(button, thread.FirstLine);
        return new Border { Child = button, BorderBrush = Brush(LineColor), BorderThickness = new Thickness(0, 0, 0, 1) };
    }

    // ---------- Un message ----------

    private FrameworkElement ThreadPage()
    {
        var stack = new StackPanel { Spacing = 20, Padding = new Thickness(0, 8, 0, 0) };
        stack.Children.Add(BackLink(Loc.T("Mes messages"), Screen.Messages));
        if (_threads.FirstOrDefault(t => t.Id == _thread) is not { } thread) return stack;
        var list = new StackPanel();
        list.Children.Add(Rule2(Text));
        list.Children.Add(Bubble(false, thread.Message, thread.CreatedAt, _captures.GetValueOrDefault(thread.Id)));
        foreach (var r in thread.Replies) list.Children.Add(Bubble(r.Team, r.Message, r.CreatedAt, null));
        stack.Children.Add(list);
        if (_replySent) stack.Children.Add(Label(Loc.T("Envoyé ✓"), 15, Text, semibold: true));
        var reply = new StackPanel { Spacing = 8, Padding = new Thickness(0, 12, 0, 0) };
        reply.Children.Add(SwissLabel(Loc.T("Répondre"), 11, Text));
        var field = GrowingField(_reply, "", 3);
        Button? send = null;
        field.TextChanged += (_, _) =>
        {
            _reply = field.Text;
            if (send is not null) send.IsEnabled = !_sending && _reply.Trim().Length > 0;
        };
        AutomationProperties.SetName(field, Loc.T("Répondre"));
        reply.Children.Add(field);
        if (_problem is not null) reply.Children.Add(Paragraph(_problem, 12, Red));
        send = Primary(Loc.T("Envoyer"), () => SendReply(thread));
        send.IsEnabled = !_sending && _reply.Trim().Length > 0;
        send.HorizontalAlignment = HorizontalAlignment.Left;
        reply.Children.Add(send);
        stack.Children.Add(reply);
        return stack;
    }

    private static FrameworkElement Bubble(bool team, string text, string date, BitmapImage? image)
    {
        var stack = new StackPanel { Spacing = 6, Padding = new Thickness(team ? 16 : 0, 14, 0, 14) };
        stack.Children.Add(SwissLabel((team ? Loc.T("L'équipe") : Loc.T("Toi")) + " · " + SupportInbox.DateLabel(date), 10.5, team ? Red : Secondary));
        var body = Paragraph(text, 14, Text);
        body.IsTextSelectionEnabled = true;
        stack.Children.Add(body);
        if (image is not null)
        {
            var picture = new Image { Source = image, MaxWidth = 420, MaxHeight = 280, HorizontalAlignment = HorizontalAlignment.Left, Stretch = Microsoft.UI.Xaml.Media.Stretch.Uniform };
            AutomationProperties.SetName(picture, Loc.T("Ta capture"));
            stack.Children.Add(new Border { Child = picture, BorderBrush = Brush(LineColor), BorderThickness = new Thickness(1), HorizontalAlignment = HorizontalAlignment.Left });
        }
        var mark = new Border { BorderBrush = Brush(Red), BorderThickness = new Thickness(team ? 2 : 0, 0, 0, 0), Child = stack };
        return new Border { Child = mark, BorderBrush = Brush(LineColor), BorderThickness = new Thickness(0, 0, 0, 1) };
    }

    private async void SendReply(SupportThread thread)
    {
        if (_sending || _reply.Trim().Length == 0) return;
        _sending = true;
        _problem = null;
        _render();
        try
        {
            if (Demo)
            {
                var replies = thread.Replies.Append(new SupportReply(Guid.NewGuid(), false, _reply.Trim(), DateTimeOffset.UtcNow.ToString("o"))).ToList();
                _threads = _threads.Select(t => t.Id == thread.Id ? t with { Replies = replies } : t).ToList();
            }
            else
            {
                var session = await Session() ?? throw new AccountPage.ServerError(Loc.T("Session expirée : reconnecte-toi."), 401);
                await AccountPage.Call(ServerRequests.ReplySupport(Server!, session, thread.Id, _reply));
                await Load();
            }
            _reply = "";
            _replySent = true;
        }
        catch (Exception e) when (e is AccountPage.ServerError or ArgumentException or HttpRequestException or TaskCanceledException)
        {
            _problem = e is AccountPage.ServerError or ArgumentException ? e.Message : Loc.T("le serveur n'a pas répondu.");
        }
        finally
        {
            _sending = false;
            _render();
        }
    }

    // ---------- Écrire à l'équipe ----------

    private FrameworkElement WritePage(int columns)
    {
        var stack = new StackPanel { Spacing = 20, Padding = new Thickness(0, 8, 0, 0) };
        stack.Children.Add(BackLink(Loc.T("Aide"), Screen.Questions));
        if (Server is not null && !SignedIn() && !Demo)
        {
            stack.Children.Add(SignInAsk(Loc.T("Connecte-toi pour écrire à l'équipe.")));
            return stack;
        }
        if (_sentReference is { } reference)
        {
            stack.Children.Add(Label(Loc.T("Envoyé ✓"), 17, Text, semibold: true));
            var refText = Paragraph(Loc.F("Référence : %@", reference), 12, Secondary);
            refText.IsTextSelectionEnabled = true;
            stack.Children.Add(refText);
            var again = new HyperlinkButton { Content = Label(Loc.T("Écrire un autre message"), 13, Text), Padding = new Thickness(0) };
            again.Click += (_, _) =>
            {
                StartWriting();
                _render();
            };
            stack.Children.Add(again);
            return stack;
        }
        var form = Form();
        var tips = Tips();
        if (columns >= 2 && tips is not null)
        {
            var grid = new Grid { ColumnSpacing = 40 };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(260) });
            grid.Children.Add(form);
            Grid.SetColumn(tips, 1);
            grid.Children.Add(tips);
            stack.Children.Add(grid);
        }
        else
        {
            stack.Children.Add(form);
            if (tips is not null) stack.Children.Add(tips);
        }
        return stack;
    }

    private FrameworkElement Form()
    {
        var form = new StackPanel { Spacing = 24, MaxWidth = 560, HorizontalAlignment = HorizontalAlignment.Left };

        if (_message.Error is { Length: > 0 } error)
        {
            var reported = new StackPanel { Spacing = 6 };
            var top = new Grid();
            top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            top.Children.Add(SwissLabel(Loc.T("Le problème signalé"), 10.5, Red));
            var remove = new HyperlinkButton { Content = Label(Loc.T("Retirer"), 11, Text), Padding = new Thickness(0) };
            remove.Click += (_, _) =>
            {
                _message.Error = null;
                _render();
            };
            Grid.SetColumn(remove, 1);
            top.Children.Add(remove);
            reported.Children.Add(top);
            reported.Children.Add(Paragraph(error, 12.5, Text));
            form.Children.Add(reported);
        }

        var about = new StackPanel { Spacing = 8 };
        about.Children.Add(SwissLabel(Loc.T("C'est à propos de"), 11, Text));
        var kinds = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var kind in Enum.GetValues<SupportKind>())
        {
            var k = kind;
            var chosen = _kind == k;
            var b = Option(Label(k.Label(), 13, chosen ? MacLook.WindowColor : Text), () =>
            {
                _kind = k;
                _message.Kind = k;
                _render();
            }, chosen, minHeight: 34, padding: new Thickness(14, 0, 14, 0));
            if (!chosen) b.Background = Brush(MacLook.WindowColor);
            b.BorderBrush = Brush(Text);
            b.BorderThickness = new Thickness(1);
            b.Margin = new Thickness(kinds.Children.Count > 0 ? -1 : 0, 0, 0, 0);
            kinds.Children.Add(b);
        }
        about.Children.Add(kinds);
        form.Children.Add(about);

        var write = new StackPanel { Spacing = 8 };
        write.Children.Add(SwissLabel(Loc.T("Message"), 11, Text));
        var text = GrowingField(_message.Text, (_kind ?? SupportKind.Autre).Placeholder(), 6);
        text.MaxLength = SupportRules.MaxMessage;
        Button? send = null;
        text.TextChanged += (_, _) =>
        {
            _message.Text = text.Text;
            if (send is not null) send.IsEnabled = Ready && !_sending;
        };
        // Les questions qui ressemblent au message : relues à la sortie du champ (jamais un redessin par lettre).
        text.LostFocus += (_, _) => _render();
        AutomationProperties.SetName(text, Loc.T("Message"));
        write.Children.Add(text);
        form.Children.Add(write);

        var capture = new StackPanel { Spacing = 8 };
        var capHead = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        capHead.Children.Add(SwissLabel(Loc.T("Capture"), 11, Text));
        capHead.Children.Add(Label(Loc.T("facultatif"), 12, Secondary));
        capture.Children.Add(capHead);
        capture.Children.Add(CaptureZone());
        if (_captureImage is not null)
        {
            var remove = new HyperlinkButton { Content = Label(Loc.T("Retirer la capture"), 12, Text), Padding = new Thickness(0) };
            remove.Click += (_, _) =>
            {
                _captureImage = null;
                _message.Capture = null;
                _render();
            };
            capture.Children.Add(remove);
        }
        form.Children.Add(capture);

        if (_problem is not null) form.Children.Add(Paragraph(_problem, 12, Red));
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 18 };
        send = Primary(Loc.T("Envoyer"), Send);
        send.IsEnabled = Ready && !_sending;
        buttons.Children.Add(send);
        var cancel = new HyperlinkButton { Content = Label(Loc.T("Annuler"), 13, Text), Padding = new Thickness(0), VerticalAlignment = VerticalAlignment.Center };
        cancel.Click += (_, _) =>
        {
            _screen = Screen.Questions;
            _render();
        };
        buttons.Children.Add(cancel);
        form.Children.Add(buttons);
        return form;
    }

    /// « Ajouter une capture » : un clic choisit une image (cadre en pointillés, comme le Mac).
    private FrameworkElement CaptureZone()
    {
        FrameworkElement content;
        if (_captureImage is not null)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 14, Padding = new Thickness(12) };
            row.Children.Add(new Image { Source = _captureImage, MaxWidth = 160, MaxHeight = 100, Stretch = Microsoft.UI.Xaml.Media.Stretch.Uniform });
            var change = Label(Loc.T("Changer"), 13, Text, semibold: true);
            change.TextDecorations = Windows.UI.Text.TextDecorations.Underline;
            change.VerticalAlignment = VerticalAlignment.Center;
            row.Children.Add(change);
            content = row;
        }
        else
        {
            var add = Label(Loc.T("Ajouter une capture"), 13, Text, semibold: true);
            add.HorizontalAlignment = HorizontalAlignment.Center;
            add.VerticalAlignment = VerticalAlignment.Center;
            content = new Grid { MinHeight = 64, Children = { add } };
        }
        var frame = new Grid();
        frame.Children.Add(new Microsoft.UI.Xaml.Shapes.Rectangle
        {
            Stroke = Brush(Text),
            StrokeThickness = 1,
            StrokeDashArray = new Microsoft.UI.Xaml.Media.DoubleCollection { 4, 3 },
            IsHitTestVisible = false,
        });
        frame.Children.Add(content);
        var button = new Button
        {
            Style = PlainButton,
            Content = frame,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            Padding = new Thickness(0),
            Background = Brush(MacLook.WindowColor),
        };
        button.Click += (_, _) => ChooseCapture();
        AutomationProperties.SetName(button, Loc.T("Ajouter une capture"));
        return button;
    }

    /// « Ça t'aide peut-être » : les questions qui parlent des mots du message.
    private FrameworkElement? Tips()
    {
        var tips = SupportInbox.Tips(_message.Text, _kind, HelpContent.Faq);
        if (tips.Count == 0) return null;
        var stack = new StackPanel { Spacing = 8 };
        stack.Children.Add(SwissLabel(Loc.T("Ça t'aide peut-être"), 11, Text));
        stack.Children.Add(FaqList(tips, id => _tipsOpen.Contains(id), id =>
        {
            if (!_tipsOpen.Remove(id)) _tipsOpen.Add(id);
            _render();
        }));
        return stack;
    }

    /// Une case de texte qui grandit avec le texte (20/11, comme le Mac) : jamais redimensionnable à la main, puis elle
    /// défile au-delà de 16 lignes.
    private static TextBox GrowingField(string text, string placeholder, int minLines)
    {
        var box = new TextBox
        {
            Text = text,
            PlaceholderText = placeholder,
            FontFamily = SwissFont,
            FontSize = 14,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            MinHeight = 20 + 20 * minLines,
            MaxHeight = 20 + 20 * 16,
            Padding = new Thickness(12, 10, 12, 10),
            Background = Brush(MacLook.WindowColor),
            BorderBrush = Brush(Text),
            BorderThickness = new Thickness(1),
        };
        ScrollViewer.SetVerticalScrollBarVisibility(box, ScrollBarVisibility.Auto);
        return box;
    }

    private Button BackLink(string title, Screen to)
    {
        var button = new Button { Style = PlainButton, Content = Label("← " + title, 13, Secondary), Padding = new Thickness(0), Margin = new Thickness(0, 12, 0, 0) };
        button.Click += (_, _) =>
        {
            _screen = to;
            if (to == Screen.Messages) _ = Load();
            _render();
        };
        return button;
    }

    private FrameworkElement SignInAsk(string text)
    {
        var stack = new StackPanel { Spacing = 14 };
        stack.Children.Add(Paragraph(text, 15, Text));
        var sign = Primary(Loc.T("Se connecter"), () => SignIn?.Invoke());
        sign.HorizontalAlignment = HorizontalAlignment.Left;
        stack.Children.Add(sign);
        return stack;
    }

    private bool Ready => _kind is not null && SupportRules.Problem(_message) is null;

    private void StartWriting()
    {
        _message = new SupportMessage();
        _kind = null;
        _captureImage = null;
        _problem = null;
        _sentReference = null;
        _screen = Screen.Write;
    }

    private string Diagnostic()
    {
        var fl = FlPresence.RunningInstance();
        var facts = new SupportDiagnostic.Facts(
            AppVersion, "Windows " + Environment.OSVersion.Version, fl is not null, fl?.Version?.ToString(),
            _app.Status == StatusKind.Unrecognized, _app.Status == StatusKind.Elevated, !_app.Enabled, _app.Light,
            _app.StatusTitle, _app.Shortcuts.Count, _app.Macros.Macros.Count, _lastMacro, Array.Empty<string>(),
            ScriptInstalled: _app.ScriptInstalled);
        return SupportDiagnostic.Report(facts, problems: null);
    }

    private async void ChooseCapture()
    {
        var picker = new FileOpenPicker { SuggestedStartLocation = PickerLocationId.PicturesLibrary, ViewMode = PickerViewMode.Thumbnail };
        foreach (var ext in new[] { ".png", ".jpg", ".jpeg", ".bmp", ".gif", ".webp" }) picker.FileTypeFilter.Add(ext);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, Hwnd);
        StorageFile? file;
        try { file = await picker.PickSingleFileAsync(); }
        catch (Exception e)
        {
            AppLog.Write("SUPPORT", "capture : sélecteur indisponible (" + e.GetType().Name + ")");
            return;
        }
        if (file is null) return;
        try
        {
            var props = await file.GetBasicPropertiesAsync();
            if (props.Size > 40UL << 20) throw new InvalidDataException();
            var buffer = await FileIO.ReadBufferAsync(file);
            var bytes = new byte[buffer.Length];
            using (var reader = DataReader.FromBuffer(buffer)) reader.ReadBytes(bytes);
            var base64 = await SupportCaptureWin.Base64(bytes) ?? throw new InvalidDataException();
            _message.Capture = base64;
            _captureImage = await SupportCaptureWin.Bitmap(base64);
            _problem = null;
        }
        catch (Exception e)
        {
            AppLog.Write("SUPPORT", "capture illisible (" + e.GetType().Name + ")");
            _problem = Loc.T("Image illisible ou trop lourde.");
        }
        _render();
    }

    /// Envoyé : le message dans « Mes messages » (serveur avec mes-messages.sql), sinon « Envoyé ✓ » et sa référence.
    private async void Send()
    {
        if (!Ready || _sending) return;
        _message.Diagnostic = Diagnostic();
        _problem = null;
        if (Demo)
        {
            _sentReference = _message.Reference;
            _render();
            return;
        }
        if (Server is not { } server)
        {
            Fallback(Loc.T("pas de serveur."));
            return;
        }
        _sending = true;
        _render();
        try
        {
            var session = await Session();
            _message.Email = session?.Email ?? "";
            var token = await Token();
            var (status, body) = await Post(server, _message, token);
            if (status == 400 && SupportInbox.NeedsOldForm(status, body))
                (status, body) = await Post(server, _message, token, oldForm: true);
            if (token is not null && status is 401 or 403)
            {
                AppLog.Write("SUPPORT", $"token refused ({status}), sent without the account");
                (status, body) = await Post(server, _message, null);
            }
            if (status is < 200 or >= 300)
            {
                AppLog.Write("SUPPORT", $"send failed ({status})");
                Fallback(AccountRequests.ServerMessage(body, status));
                return;
            }
            AppLog.Write("SUPPORT", "sent");
            var reference = _message.Reference;
            await Load();
            if (_ready == true && _threads.FirstOrDefault(t => t.Reference == reference) is { } thread)
            {
                _message = new SupportMessage();
                _kind = null;
                _captureImage = null;
                _screen = Screen.Thread;
                _thread = thread.Id;
                _replySent = true;
            }
            else
            {
                _sentReference = reference;
            }
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            AppLog.Write("SUPPORT", "send failed (no answer)");
            Fallback(Loc.T("le serveur n'a pas répondu."));
        }
        catch (Exception e)
        {
            // Jamais une chute de l'appli pour un message (async void) : la raison au journal, le message copié.
            AppLog.Write("SUPPORT", "send failed (" + e.GetType().Name + ")");
            Fallback(Loc.T("le serveur n'a pas répondu."));
        }
        finally
        {
            _sending = false;
            _render();
        }
    }

    private static async Task<(int Status, string Body)> Post(ServerConfig server, SupportMessage message, string? token, bool oldForm = false)
    {
        using var request = ServerRequests.Support(server, message, AppVersion, token: token, oldForm: oldForm);
        using var response = await Http.SendAsync(request);
        return ((int)response.StatusCode, await response.Content.ReadAsStringAsync());
    }

    /// Mes messages relus (rien sans compte) ; serveur sans mes-messages.sql : « pas encore ouvert ».
    private async Task Load()
    {
        if (Demo || _loading || Server is not { } server) return;
        _loading = true;                                   // avant d'attendre : jamais deux lectures à la fois
        var session = await Session();
        if (session is null)
        {
            _loading = false;
            return;
        }
        try
        {
            _threads = SupportInbox.Decode(await AccountPage.Call(ServerRequests.MyMessages(server, session)));
            _ready = true;
        }
        catch (AccountPage.ServerError e) when (SupportInbox.IsMissing(e.Status, e.Message)) { _ready = false; }
        catch (Exception e) when (e is AccountPage.ServerError or HttpRequestException or TaskCanceledException or System.Text.Json.JsonException)
        {
            AppLog.Write("SUPPORT", "inbox failed (" + e.GetType().Name + ")");
            _ready ??= true;
        }
        finally
        {
            _loading = false;
            _render();
        }
    }

    private async Task LoadCapture(Guid id)
    {
        if (Demo || _captures.ContainsKey(id) || Server is not { } server) return;
        try
        {
            var session = await Session();
            if (session is null) return;
            if (SupportInbox.DecodeCapture(await AccountPage.Call(ServerRequests.MessageCapture(server, session, id))) is { } text
                && await SupportCaptureWin.Bitmap(text) is { } image)
            {
                _captures[id] = image;
                _render();
            }
        }
        catch (Exception e) { AppLog.Write("SUPPORT", "capture not read (" + e.GetType().Name + ")"); }
    }

    private void MarkSeen(SupportThread thread)
    {
        var ids = thread.Replies.Where(r => r.Team).Select(r => r.Id).ToList();
        if (ids.All(_seen.Contains)) return;
        foreach (var id in ids) _seen.Add(id);
        _app.Settings.SupportSeenReplies = string.Join(",", _seen.TakeLast(500));
        _app.Settings.Save();
    }

    /// Déconnexion : les messages du compte ne restent pas affichés.
    public void Forget()
    {
        _threads = new();
        _ready = null;
        _captures.Clear();
    }

    /// « Pas content ? » de l'Organiser (13/11, comme le Mac) : le message part à l'équipe sans rien montrer, avec le
    /// compte s'il y en a un (jeton refusé : sans) ; un échec reste au journal, jamais une chute.
    public async Task SendQuietly(SupportMessage message)
    {
        if (Server is not { } server || SupportRules.Problem(message) is not null) return;
        try
        {
            var token = await Token();
            var (status, _) = await Post(server, message, token);
            if (token is not null && status is 401 or 403) (status, _) = await Post(server, message, null);
            AppLog.Write("SUPPORT", status is >= 200 and < 300 ? "organizer feedback sent" : $"organizer feedback failed ({status})");
        }
        catch (Exception e)
        {
            AppLog.Write("SUPPORT", "organizer feedback failed (" + e.GetType().Name + ")");
        }
    }

    /// Sans serveur (ou s'il échoue) : le message copié et le ticket GitHub ouvert (sans le mail : la page est publique).
    private void Fallback(string why)
    {
        try
        {
            var package = new DataPackage();
            package.SetText(SupportRules.PlainText(_message, AppVersion));
            Clipboard.SetContent(package);
        }
        catch (Exception e) { AppLog.Write("SUPPORT", "clipboard refused (" + e.GetType().Name + ")"); }
        try { Process.Start(new ProcessStartInfo(SupportRules.IssueUri(_message, AppVersion).AbsoluteUri) { UseShellExecute = true }); }
        catch { /* pas de navigateur : le message reste copié */ }
        _toast(Loc.F("Envoi impossible : %@", why), null);
    }

    private static List<SupportThread> DemoThreads() => new()
    {
        new SupportThread(Guid.Parse("6f1d2c1e-0000-4000-8000-0000000000a1"), SupportKind.Probleme, "FLS-3F9A2C",
            "Export Stems s'arrête au menu Export.", "2026-11-17T10:00:00+00:00",
            new[] { new SupportReply(Guid.Parse("6f1d2c1e-0000-4000-8000-0000000000b1"), true,
                                     "Merci ! C'est corrigé dans la prochaine version.", "2026-11-18T09:00:00+00:00") }),
        new SupportThread(Guid.Parse("6f1d2c1e-0000-4000-8000-0000000000a2"), SupportKind.Idee, "FLS-7B21D0",
            "Un bloc pour changer le tempo.", "2026-11-15T10:00:00+00:00", Array.Empty<SupportReply>()),
    };
}

/// Capture jointe (comme SupportCapture du Mac) : l'image choisie, à l'endroit, réduite à 1600 de large au plus, JPEG
/// dont la qualité baisse tant qu'il dépasse 1 Mo une fois en base64 (la règle du serveur).
internal static class SupportCaptureWin
{
    private const int MaxWidth = 1600, MaxBase64 = 1_048_576;

    public static async Task<string?> Base64(byte[] file)
    {
        using var source = await ProfilePhotoWin.Stream(file);
        var decoder = await BitmapDecoder.CreateAsync(source);
        uint w0 = decoder.PixelWidth, h0 = decoder.PixelHeight;
        if (w0 == 0 || h0 == 0) return null;
        var rotated = decoder.OrientedPixelWidth != w0;
        var shownWidth = rotated ? h0 : w0;
        var scale = shownWidth > MaxWidth ? (double)MaxWidth / shownWidth : 1;
        var transform = new BitmapTransform
        {
            ScaledWidth = (uint)Math.Max(1, Math.Round(w0 * scale)),
            ScaledHeight = (uint)Math.Max(1, Math.Round(h0 * scale)),
            InterpolationMode = BitmapInterpolationMode.Fant,
        };
        var data = await decoder.GetPixelDataAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied, transform,
            ExifOrientationMode.RespectExifOrientation, ColorManagementMode.ColorManageToSRgb);
        var pixels = data.DetachPixelData();
        uint width = rotated ? transform.ScaledHeight : transform.ScaledWidth;
        uint height = rotated ? transform.ScaledWidth : transform.ScaledHeight;
        for (var i = 0; i + 3 < pixels.Length; i += 4)
        {
            var a = pixels[i + 3];
            if (a == 255) continue;
            var white = 255 - a;                                    // transparence : fond blanc (comme le Mac)
            pixels[i] = (byte)Math.Min(255, pixels[i] + white);
            pixels[i + 1] = (byte)Math.Min(255, pixels[i + 1] + white);
            pixels[i + 2] = (byte)Math.Min(255, pixels[i + 2] + white);
            pixels[i + 3] = 255;
        }
        foreach (var quality in new[] { 0.75, 0.6, 0.45, 0.3 })
        {
            using var output = new InMemoryRandomAccessStream();
            var options = new BitmapPropertySet { { "ImageQuality", new BitmapTypedValue(quality, Windows.Foundation.PropertyType.Single) } };
            var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.JpegEncoderId, output, options);
            encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore, width, height, 96, 96, pixels);
            await encoder.FlushAsync();
            var jpeg = new byte[output.Size];
            output.Seek(0);
            using (var reader = new DataReader(output.GetInputStreamAt(0)))
            {
                await reader.LoadAsync((uint)output.Size);
                reader.ReadBytes(jpeg);
            }
            var text = Convert.ToBase64String(jpeg);
            if (text.Length <= MaxBase64) return text;
        }
        return null;
    }

    public static async Task<BitmapImage?> Bitmap(string base64)
    {
        try
        {
            using var stream = await ProfilePhotoWin.Stream(Convert.FromBase64String(base64));
            var image = new BitmapImage();
            await image.SetSourceAsync(stream);
            return image;
        }
        catch (Exception) { return null; }
    }
}
