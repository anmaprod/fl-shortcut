// Page Aide (Windows), comme HelpView du Mac au style suisse : grande recherche, questions fréquentes (réponse en
// étapes numérotées quand elle en a), « Écrire à l'équipe » à droite ; le formulaire s'ouvre dessous. Le message part
// par le serveur (support_requests, sans compte) ; sans serveur ou s'il échoue : copie du message et ticket GitHub
// (sans le mail). Le diagnostic joint (case cochée par défaut) est montré tel quel avant l'envoi : rien de personnel.
// Les champs ne redessinent jamais la page à chaque lettre (le texte tapé resterait sinon en route).
using System.Diagnostics;
using System.Reflection;
using FLShortcut.App.Services;
using FLShortcut.Core.Macros;
using FLShortcut.Core;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Windows.ApplicationModel.DataTransfer;
using Windows.UI;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal sealed class HelpPage
{
    /// Couleur de la page Aide (comme SidebarItem.help du Mac).
    public static readonly Color Tint = Rgb(0x32, 0xAD, 0xE6);
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };

    private readonly AppController _app;
    private readonly Action _render;
    private readonly Action<string, Action?> _toast;
    private string _query = "";
    private int? _open = 1;
    private bool _writing;
    private bool _sending;
    private bool _attach = true;
    private bool _showAttached;
    private string? _problem;
    private SupportMessage? _sent;
    private SupportMessage _message = new();
    private string? _lastMacro;

    /// Jeton du compte connecté (Mon compte) : le message part avec le compte, comme sur le Mac ; sinon sans.
    public Func<string?> Token { get; set; } = () => null;

    public HelpPage(AppController app, Action render, Action<string, Action?> toast)
    {
        _app = app;
        _render = render;
        _toast = toast;
        _app.MacroFinished += (ok, text) => _lastMacro = (ok ? "réussie" : "échec") + " — " + text;
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

    /// « Signaler ce problème… » (macro ratée) : le formulaire prêt avec ce message d'erreur.
    public void Report(string error)
    {
        _message = new SupportMessage { Error = error };
        _writing = true;
        _sent = null;
        _problem = null;
    }

    public FrameworkElement Content(int columns)
    {
        var page = new StackPanel { Spacing = 22, Padding = new Thickness(26, 4, 26, 24) };
        page.Children.Add(SearchField());
        var found = HelpContent.Faq.Where(e => e.Matches(_query)).ToList();
        var faq = Faq(found);
        var side = SideCards();
        if (columns >= 2)
        {
            var grid = new Grid { ColumnSpacing = 24 };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(250) });
            grid.Children.Add(faq);
            Grid.SetColumn(side, 1);
            grid.Children.Add(side);
            page.Children.Add(grid);
        }
        else
        {
            page.Children.Add(faq);
            page.Children.Add(side);
        }
        if (_sent is not null) page.Children.Add(SentCard(_sent));
        else if (_writing) page.Children.Add(Form());
        return page;
    }

    // ---------- Recherche et questions ----------

    private FrameworkElement SearchField()
    {
        var box = new TextBox
        {
            Text = _query,
            PlaceholderText = Loc.T("Cherche dans l'aide : raccourcis, macro, pause…"),
            FontSize = 20,
            FontWeight = Microsoft.UI.Text.FontWeights.Bold,
            FontFamily = SwissFont,
            Background = Brush(Colors.Black),
            BorderBrush = Brush(LineColor),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(14, 10, 14, 10),
        };
        AutomationProperties.SetName(box, Loc.T("Rechercher"));
        // Le texte cherché filtre à la touche Entrée ou à la sortie du champ (jamais un redessin par lettre).
        box.KeyDown += (_, e) => { if (e.Key == Windows.System.VirtualKey.Enter) Search(box.Text); };
        box.LostFocus += (_, _) => Search(box.Text);
        return box;
    }

    private void Search(string text)
    {
        if (text == _query) return;
        _query = text;
        _open = null;
        _render();
    }

    private FrameworkElement Faq(List<HelpEntry> entries)
    {
        var list = new StackPanel();
        list.Children.Add(Rule(LineColor));
        if (entries.Count == 0)
        {
            var none = Paragraph(Loc.F("Aucune réponse pour « %@ » : écris-nous juste en dessous, on te répond.", DisplayText.Safe(_query, 30)), 13);
            none.Margin = new Thickness(4, 14, 4, 14);
            list.Children.Add(none);
            return list;
        }
        foreach (var entry in entries) list.Children.Add(Entry(entry));
        return list;
    }

    private FrameworkElement Entry(HelpEntry entry)
    {
        var open = _open == entry.Id;
        var head = new Grid();
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var question = Label(entry.Question, 13.5, bold: true);
        question.TextWrapping = TextWrapping.Wrap;
        head.Children.Add(question);
        var chevron = Label(open ? "⌄" : "›", 15, Secondary);
        Grid.SetColumn(chevron, 1);
        head.Children.Add(chevron);
        var button = Option(head, Tint, 0, () =>
        {
            _open = open ? null : entry.Id;
            _render();
        }, minHeight: 44, padding: new Thickness(12, 8, 12, 8));
        button.HorizontalAlignment = HorizontalAlignment.Stretch;
        button.HorizontalContentAlignment = HorizontalAlignment.Stretch;
        AutomationProperties.SetName(button, entry.Question + " — " + Loc.T(open ? "ouverte" : "fermée"));
        var cell = new StackPanel();
        cell.Children.Add(button);
        if (open) cell.Children.Add(Answer(entry.Answer));
        cell.Children.Add(Rule(Faint));
        return cell;
    }

    /// La réponse : en étapes numérotées (carré rouge, comme le Mac) quand elle en a, sinon en un paragraphe.
    private static FrameworkElement Answer(string answer)
    {
        var stack = new StackPanel { Spacing = 10, Padding = new Thickness(12, 0, 12, 16) };
        var soft = Rgb(0xC8, 0xC8, 0xC8);
        if (HelpEntry.Steps(answer) is not { } parsed)
        {
            stack.Children.Add(Paragraph(answer, 12.5, soft));
            return stack;
        }
        if (parsed.Intro.Length > 0) stack.Children.Add(Paragraph(parsed.Intro, 12.5, soft));
        for (var i = 0; i < parsed.Steps.Count; i++)
        {
            var row = new Grid { ColumnSpacing = 10 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.Children.Add(new Border
            {
                Width = 20, Height = 20, Background = Brush(Red), VerticalAlignment = VerticalAlignment.Top,
                Child = new TextBlock
                {
                    Text = (i + 1).ToString(System.Globalization.CultureInfo.InvariantCulture), FontSize = 11,
                    FontWeight = Microsoft.UI.Text.FontWeights.Bold, FontFamily = SwissFont, Foreground = Brush(Colors.White),
                    HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
                },
            });
            var text = Paragraph(parsed.Steps[i], 12.5, soft);
            Grid.SetColumn(text, 1);
            row.Children.Add(text);
            stack.Children.Add(row);
        }
        return stack;
    }

    // ---------- Écrire à l'équipe ----------

    private FrameworkElement SideCards()
    {
        var card = new StackPanel { Spacing = 14, Padding = new Thickness(16, 18, 16, 18) };
        card.Children.Add(Tile("help", Tint, 40));
        card.Children.Add(Label(Loc.T("Écrire à l'équipe"), 15, bold: true));
        card.Children.Add(Primary(Loc.T("Écrire un message…"), () =>
        {
            _writing = true;
            _sent = null;
            _render();
        }));
        return new Border
        {
            Child = card,
            BorderBrush = Brush(LineColor),
            BorderThickness = new Thickness(0, 1, 0, 1),
            VerticalAlignment = VerticalAlignment.Top,
        };
    }

    private static TextBox Field(string text, string placeholder) => new()
    {
        Text = text,
        PlaceholderText = placeholder,
        FontFamily = SwissFont,
        Background = Brush(Colors.Black),
        BorderBrush = Brush(LineColor),
        BorderThickness = new Thickness(1),
    };

    private FrameworkElement Form()
    {
        var form = new StackPanel { Spacing = 12 };
        form.Children.Add(SwissLabel(Loc.T("Écrire à l'équipe"), 11, Text));
        form.Children.Add(Rule(Text));

        if (_message.Error is { Length: > 0 } error)
        {
            var reported = new StackPanel { Spacing = 6, Padding = new Thickness(12, 10, 12, 10) };
            var top = new Grid();
            top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            top.Children.Add(SwissLabel(Loc.T("Problème signalé"), 10.5, Orange));
            var remove = Soft(Loc.T("Retirer"), () =>
            {
                _message.Error = null;
                _render();
            });
            Grid.SetColumn(remove, 1);
            top.Children.Add(remove);
            reported.Children.Add(top);
            reported.Children.Add(Paragraph(error, 12.5, Text));
            reported.Children.Add(Paragraph(Loc.T("Dis en quelques mots ce que tu faisais juste avant : ça nous aide beaucoup."), 11.5));
            form.Children.Add(new Border { Child = reported, BorderBrush = Brush(Orange), BorderThickness = new Thickness(2, 0, 0, 0) });
        }

        var kinds = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var kind in Enum.GetValues<SupportKind>())
        {
            var k = kind;
            var b = Option(Label(k.Label(), 12.5, bold: true), Tint, 0, () =>
            {
                _message.Kind = k;
                _render();
            }, _message.Kind == k, minHeight: 32, padding: new Thickness(14, 0, 14, 0));
            b.BorderBrush = Brush(Colors.White);
            b.BorderThickness = new Thickness(1);
            kinds.Children.Add(b);
        }
        form.Children.Add(kinds);

        var text = Field(_message.Text, _message.Kind.Placeholder());
        text.AcceptsReturn = true;
        text.TextWrapping = TextWrapping.Wrap;
        text.MinHeight = 140;
        text.MaxLength = SupportRules.MaxMessage;
        text.TextChanged += (_, _) => _message.Text = text.Text;
        AutomationProperties.SetName(text, Loc.T("Écrire à l'équipe"));
        form.Children.Add(text);

        var mail = Field(_message.Email, Loc.T("Ton mail pour la réponse, facultatif"));
        mail.TextChanged += (_, _) => _message.Email = mail.Text;
        AutomationProperties.SetName(mail, Loc.T("Ton mail"));
        form.Children.Add(mail);

        var attach = new CheckBox { Content = Label(Loc.T("Joindre l'état de l'appli"), 12.5), IsChecked = _attach };
        attach.Checked += (_, _) => _attach = true;
        attach.Unchecked += (_, _) => _attach = false;
        var attachRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 14 };
        attachRow.Children.Add(attach);
        var see = new HyperlinkButton
        {
            Content = Label(Loc.T(_showAttached ? "Masquer" : "Voir ce qui est joint"), 12, Text),
            Padding = new Thickness(0),
            VerticalAlignment = VerticalAlignment.Center,
        };
        see.Click += (_, _) =>
        {
            _showAttached = !_showAttached;
            _render();
        };
        attachRow.Children.Add(see);
        form.Children.Add(attachRow);
        if (_showAttached)
        {
            var shown = Paragraph(Diagnostic(), 11, Secondary);
            shown.FontFamily = new Microsoft.UI.Xaml.Media.FontFamily("Consolas");
            form.Children.Add(new Border { Child = shown, Padding = new Thickness(10), BorderBrush = Brush(LineColor), BorderThickness = new Thickness(1) });
        }
        form.Children.Add(Paragraph(Loc.T("Jamais envoyé : tes touches, tes noms de pistes, tes fichiers."), 11));

        if (_problem is not null) form.Children.Add(Paragraph(_problem, 12, Red));
        var send = Primary(Loc.T("Envoyer"), Send);
        send.IsEnabled = !_sending;
        form.Children.Add(send);
        return form;
    }

    private string Diagnostic()
    {
        var fl = FlPresence.RunningInstance();
        var facts = new SupportDiagnostic.Facts(
            AppVersion, "Windows " + Environment.OSVersion.Version, fl is not null, fl?.Version?.ToString(),
            _app.Status == StatusKind.Unrecognized, _app.Status == StatusKind.Elevated, !_app.Enabled, _app.Light,
            _app.StatusTitle, _app.Shortcuts.Count, _app.Macros.Macros.Count, _lastMacro, Array.Empty<string>());
        return SupportDiagnostic.Report(facts, problems: null);
    }

    private async void Send()
    {
        _message.Diagnostic = _attach ? Diagnostic() : null;
        if (SupportRules.Problem(_message) is { } why)
        {
            _problem = why;
            _render();
            return;
        }
        _problem = null;
        if (Server is not { } server)
        {
            Fallback(Loc.T("pas de serveur."));
            return;
        }
        _sending = true;
        _render();
        try
        {
            using var request = ServerRequests.Support(server, _message, AppVersion, token: Token());
            using var response = await Http.SendAsync(request);
            if (!response.IsSuccessStatusCode) throw new HttpRequestException("status");
            AppLog.Write("SUPPORT", "sent");
            _sent = _message;
            _message = new SupportMessage();
            _writing = false;
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            AppLog.Write("SUPPORT", "send failed");
            Fallback(Loc.T("le serveur n'a pas répondu."));
        }
        finally
        {
            _sending = false;
            _render();
        }
    }

    /// Sans serveur (ou s'il échoue) : le message copié et le ticket GitHub ouvert (sans le mail : la page est publique).
    private void Fallback(string why)
    {
        var package = new DataPackage();
        package.SetText(SupportRules.PlainText(_message, AppVersion));
        Clipboard.SetContent(package);
        try { Process.Start(new ProcessStartInfo(SupportRules.IssueUri(_message, AppVersion).AbsoluteUri) { UseShellExecute = true }); }
        catch { /* pas de navigateur : le message reste copié */ }
        _toast(Loc.F("Envoi impossible : %@ Tu peux le copier ou ouvrir un ticket.", why), null);
    }

    private FrameworkElement SentCard(SupportMessage sent)
    {
        var stack = new StackPanel { Spacing = 10, Padding = new Thickness(16) };
        stack.Children.Add(Label(Loc.T("Message envoyé"), 18, bold: true));
        stack.Children.Add(Paragraph(Loc.F("Référence : %@", sent.Reference), 12.5, Text));
        if (sent.Email.Trim().Length > 0)
            stack.Children.Add(Paragraph(Loc.F("On te répond à %@ dès que possible.", sent.Email.Trim()), 12.5));
        stack.Children.Add(Soft(Loc.T("Écrire un autre message"), () =>
        {
            _sent = null;
            _writing = true;
            _render();
        }));
        return new Border { Child = stack, BorderBrush = Brush(Green), BorderThickness = new Thickness(2, 0, 0, 0) };
    }
}
