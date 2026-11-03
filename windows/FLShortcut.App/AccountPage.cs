// Page Mon compte (Windows), comme celle du Mac (AccountView.swift, AccountAuthViews.swift, EditProfileSheet.swift) au
// style suisse : une carte au centre pour se connecter, créer son compte (pseudo vérifié en direct, règles du mot de passe
// qui passent au vert) ou entrer le code reçu par mail ; connecté, la carte du profil (photo ou initiale de couleur,
// pseudo, mail, « Modifier le profil », « Se déconnecter ») et « Supprimer mon compte ». Le compte est le même que sur
// le Mac (même serveur). La sauvegarde en ligne des raccourcis n'est pas encore sur Windows : les touches du Mac et de
// Windows n'ont pas les mêmes codes, une sauvegarde faite ici abîmerait celle du Mac. Jamais de mot de passe gardé ni
// écrit dans le journal ; la session est chiffrée par Windows (AccountStore).
using System.Net.Http;
using FLShortcut.App.Services;
using FLShortcut.Core;
using Microsoft.UI;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Foundation;
using Windows.Graphics.Imaging;
using Windows.Storage;
using Windows.Storage.Pickers;
using Windows.Storage.Streams;
using Windows.UI;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal sealed class AccountPage
{
    /// Couleur de la page Mon compte (comme SidebarItem.account du Mac).
    public static readonly Color Tint = Teal;
    private static readonly Color Sky = Rgb(0x5A, 0xC8, 0xFA);
    /// Couleurs des initiales, dans l'ordre du Mac (ProfilePhoto.initialColors).
    private static readonly Color[] InitialColors = { Teal, Blue, Indigo, Purple, Pink, Orange, Green, Rgb(0xFF, 0x45, 0x3A) };
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };
    private const long MaxFileBytes = 40L << 20;

    private enum NameCheck { None, Checking, Free, Taken, Invalid }

    private readonly Action _render;
    private readonly Func<string, string, string, bool, Task<bool>> _confirm;
    private readonly IntPtr _hwnd;

    private AccountSession? _session;
    private byte[]? _myPhoto;

    // Connexion et inscription.
    private bool _creating;
    private string _email = "";
    private string _password = "";
    private string _username = "";
    private NameCheck _nameCheck;
    private string? _nameWhy;
    private int _nameVersion;
    private (CodeKind Kind, string Email)? _pending;
    private AccountSession? _recoverySession;
    private string _code = "";
    private string _newPassword = "";
    private bool _busy;
    private string? _error;
    private string? _notice;

    // Modifier le profil.
    private bool _editing;
    private string _editName = "";
    private byte[]? _editFile;
    private byte[]? _editPhoto;
    private bool _removePhoto;
    private double _zoom = 1, _dx, _dy;
    private string? _editProblem;
    private int _photoVersion;
    private string? _deleteError;

    // Contrôles mis à jour sans tout redessiner (le texte tapé garde la main).
    private Button? _submit;
    private TextBlock? _nameStatus;
    private TextBlock? _nameHint;
    private readonly List<(TextBlock Label, int Rule)> _ruleLabels = new();

    public AccountPage(Action render, Func<string, string, string, bool, Task<bool>> confirm, IntPtr hwnd)
    {
        _render = render;
        _confirm = confirm;
        _hwnd = hwnd;
        _session = AccountStore.Load();
        if (_session is not null) _ = RefreshAndLoadPhoto();
    }

    public AccountSession? Session => _session;
    public byte[]? MyPhoto => _myPhoto;

    /// Connexion, déconnexion, pseudo ou photo changés (l'en-tête suit).
    public event Action? Changed;

    /// Bouton du compte de l'en-tête sur la page Mon compte : « Modifier le profil ».
    public void EditProfile()
    {
        if (_session is null) return;
        StartEditing();
        _render();
    }

    public FrameworkElement Content(int columns)
    {
        _submit = null;
        _nameStatus = null;
        _nameHint = null;
        _ruleLabels.Clear();
        if (HelpPage.Server is null)
            return Message(Loc.T("Les comptes ne sont pas encore ouverts"), Loc.T("Tes raccourcis et tes macros restent sur ce PC en attendant."));
        if (_session is { } session) return SignedIn(session);
        var card = _pending is { } pending ? CodeCard(pending.Kind, pending.Email) : SignInCard();
        return new StackPanel { Children = { card }, Padding = new Thickness(24, 24, 24, 32) };
    }

    // ---------- Serveur ----------

    private sealed class ServerError : Exception
    {
        public ServerError(string message, int status) : base(message) => Status = status;
        public int Status { get; }
    }

    /// La réponse du serveur, ou ServerError avec son message traduit (comme CommunityClient.message du Mac).
    private static async Task<string> Call(HttpRequestMessage request)
    {
        try
        {
            using var response = await Http.SendAsync(request);
            var body = await response.Content.ReadAsStringAsync();
            var status = (int)response.StatusCode;
            if (status is >= 200 and < 300) return body;
            AppLog.Write("ACCOUNT", $"{request.Method} {request.RequestUri?.AbsolutePath} → {status}");
            throw new ServerError(AccountRequests.ServerMessage(body, status), status);
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            AppLog.Write("ACCOUNT", $"{request.Method} {request.RequestUri?.AbsolutePath} → réseau ({e.GetType().Name})");
            throw new ServerError(Loc.F("Connexion impossible : %@", Loc.T("le serveur n'a pas répondu.")), 0);
        }
    }

    private static ServerConfig Server => HelpPage.Server ?? throw new ServerError(Loc.T("Les comptes ne sont pas encore ouverts"), 0);

    /// Une action du compte : une à la fois, son erreur affichée sous le bouton.
    private async Task Run(Func<Task> work)
    {
        if (_busy) return;
        _busy = true;
        _error = null;
        _render();
        try
        {
            await work();
        }
        catch (Exception e) when (e is ServerError or ArgumentException)
        {
            _error = e.Message;
        }
        finally
        {
            _busy = false;
            _render();
        }
    }

    private void Set(AccountSession? session)
    {
        var before = _session?.UserId;
        _session = session;
        AccountStore.Save(session);
        if (session?.UserId != before) _myPhoto = null;
        AppLog.Write("ACCOUNT", session is null ? "déconnecté" : "connecté");
        Changed?.Invoke();
    }

    /// La session, rafraîchie si elle expire ; refusée par le serveur : déconnecté (« reconnecte-toi »).
    private async Task<AccountSession> Fresh()
    {
        var session = _session ?? throw new ServerError(Loc.T("Session expirée : reconnecte-toi."), 401);
        if (!session.Expired(DateTimeOffset.UtcNow)) return session;
        try
        {
            var body = await Call(AccountRequests.Refresh(Server, session));
            var fresh = AccountRequests.DecodeSession(body, DateTimeOffset.UtcNow) ?? throw new ServerError(Loc.T("Session expirée : reconnecte-toi."), 401);
            // Le pseudo changé ici reste celui de la session (le jeton peut porter l'ancien).
            if (session.Username.Length > 0) fresh = fresh with { Username = session.Username };
            Set(fresh);
            return fresh;
        }
        catch (ServerError e) when (e.Status is 400 or 401 or 403)
        {
            Set(null);
            throw new ServerError(Loc.T("Session expirée : reconnecte-toi."), 401);
        }
    }

    private async Task RefreshAndLoadPhoto()
    {
        try
        {
            var session = await Fresh();
            var body = await Call(AccountRequests.Avatars(Server, new[] { session.UserId }, session));
            _myPhoto = AccountRequests.DecodeAvatars(body).GetValueOrDefault(session.UserId);
            Changed?.Invoke();
            _render();
        }
        catch (ServerError)
        {
            // Hors ligne ou serveur sans photos (profil.sql pas encore collé) : l'initiale reste.
        }
    }

    // ---------- Connexion, inscription, code ----------

    private bool CanSubmit
    {
        get
        {
            var mail = _email.Trim();
            if (!_creating) return mail.Length > 0 && _password.Length > 0;
            return AccountRules.UsernameProblem(_username.Trim()) is null && _nameCheck != NameCheck.Taken
                   && SupportRules.EmailProblem(mail) is null && AccountRules.PasswordProblem(_password) is null;
        }
    }

    private async void Submit()
    {
        var mail = _email.Trim();
        var name = _username.Trim();
        var pass = _password;
        await Run(async () =>
        {
            if (_creating)
            {
                var free = await Call(AccountRequests.UsernameAvailable(Server, name));
                if (free.Trim() == "false") throw new ServerError(Loc.T("Ce pseudo est déjà pris."), 0);
                var body = await Call(AccountRequests.SignUp(Server, mail, pass, name));
                if (AccountRequests.DecodeSession(body, DateTimeOffset.UtcNow) is { } session)
                {
                    Set(session);
                }
                else
                {
                    _pending = (CodeKind.Signup, mail);
                    _notice = Loc.F("Un code vient de partir à %@ : entre-le ici pour confirmer ton compte.", mail);
                }
            }
            else
            {
                try
                {
                    var body = await Call(AccountRequests.SignIn(Server, mail, pass));
                    Set(AccountRequests.DecodeSession(body, DateTimeOffset.UtcNow)
                        ?? throw new ServerError(Loc.T("Réponse inattendue du serveur."), 0));
                }
                catch (ServerError e) when (e.Message == AccountRequests.Unconfirmed)
                {
                    // Compte jamais confirmé (code pas tapé, app relancée…) : un nouveau code, et l'écran pour le taper.
                    try { await Call(AccountRequests.ResendSignupCode(Server, mail)); } catch (ServerError) { }
                    _pending = (CodeKind.Signup, mail);
                    _notice = Loc.F("Ton compte n'est pas encore confirmé : un code vient de partir à %@.", mail);
                }
            }
            if (_session is not null)
            {
                _password = "";
                _notice = null;
                _ = RefreshAndLoadPhoto();
            }
        });
    }

    private async void ForgotPassword()
    {
        var mail = _email.Trim();
        await Run(async () =>
        {
            if (SupportRules.EmailProblem(mail) is { } why) throw new ArgumentException(why);
            await Call(AccountRequests.ResetPassword(Server, mail));
            _pending = (CodeKind.Recovery, mail);
            _notice = Loc.T("Si un compte existe avec ce mail, un code vient d'y partir : entre-le ici avec ton nouveau mot de passe.");
        });
    }

    private async void Validate()
    {
        if (_pending is not { } pending) return;
        var code = _code;
        var chosen = _newPassword;
        await Run(async () =>
        {
            if (pending.Kind == CodeKind.Signup)
            {
                var body = await Call(AccountRequests.VerifyCode(Server, pending.Email, code, CodeKind.Signup));
                Set(AccountRequests.DecodeSession(body, DateTimeOffset.UtcNow) ?? throw new ServerError(Loc.T("Réponse inattendue du serveur."), 0));
                _notice = null;
            }
            else
            {
                if (AccountRules.PasswordProblem(chosen) is { } why) throw new ArgumentException(why);
                var session = _recoverySession;
                if (session is null)
                {
                    var body = await Call(AccountRequests.VerifyCode(Server, pending.Email, code, CodeKind.Recovery));
                    session = AccountRequests.DecodeSession(body, DateTimeOffset.UtcNow) ?? throw new ServerError(Loc.T("Réponse inattendue du serveur."), 0);
                    _recoverySession = session;
                }
                await Call(AccountRequests.UpdatePassword(Server, chosen, session));
                Set(session);
                _notice = Loc.T("Mot de passe changé : tu es connecté.");
            }
            _pending = null;
            _recoverySession = null;
            _code = "";
            _newPassword = "";
            _ = RefreshAndLoadPhoto();
        });
    }

    private async void ResendCode()
    {
        if (_pending is not { } pending) return;
        await Run(async () =>
        {
            await Call(pending.Kind == CodeKind.Signup
                ? AccountRequests.ResendSignupCode(Server, pending.Email)
                : AccountRequests.ResetPassword(Server, pending.Email));
            _notice = Loc.F("Nouveau code envoyé à %@.", pending.Email);
        });
    }

    private void CancelCode(string? notice = null)
    {
        if (_pending is { } pending) _email = pending.Email;
        _pending = null;
        _recoverySession = null;
        _code = "";
        _newPassword = "";
        _error = null;
        _notice = notice;
        _render();
    }

    /// Pseudo tapé : vérifié 0,4 s après la dernière lettre (règles, puis libre ou déjà pris sur le serveur).
    private void CheckName(string name, string? mine = null)
    {
        var version = ++_nameVersion;
        name = name.Trim();
        if (name.Length == 0) SetNameCheck(NameCheck.None, null);
        else if (AccountRules.UsernameProblem(name) is { } why) SetNameCheck(NameCheck.Invalid, why);
        else if (mine is not null && string.Equals(name, mine, StringComparison.OrdinalIgnoreCase)) SetNameCheck(NameCheck.Free, null);
        else
        {
            SetNameCheck(NameCheck.Checking, null);
            _ = Later();
        }

        async Task Later()
        {
            await Task.Delay(400);
            if (version != _nameVersion || HelpPage.Server is not { } server) return;
            try
            {
                var free = (await Call(AccountRequests.UsernameAvailable(server, name))).Trim();
                if (version == _nameVersion) SetNameCheck(free == "false" ? NameCheck.Taken : NameCheck.Free, null);
            }
            catch (ServerError)
            {
                if (version == _nameVersion) SetNameCheck(NameCheck.None, null);
            }
        }
    }

    private void SetNameCheck(NameCheck check, string? why)
    {
        _nameCheck = check;
        _nameWhy = why;
        if (_nameStatus is not null)
        {
            (_nameStatus.Text, _nameStatus.Foreground) = check switch
            {
                NameCheck.Free => ("✓ " + Loc.T("Libre"), Brush(Green)),
                NameCheck.Taken => (Loc.T("Déjà pris"), Brush(Red)),
                NameCheck.Checking => ("…", Brush(Secondary)),
                _ => ("", Brush(Secondary)),
            };
        }
        if (_nameHint is not null)
        {
            _nameHint.Text = why ?? "";
            _nameHint.Visibility = why is null ? Visibility.Collapsed : Visibility.Visible;
        }
        UpdateSubmit();
    }

    private void UpdateSubmit()
    {
        if (_submit is null) return;
        _submit.IsEnabled = !_busy && (_editing && _session is not null ? CanSaveProfile
            : _pending is { } p ? AccountRules.Code(_code) is not null && (p.Kind == CodeKind.Signup || AccountRules.PasswordProblem(_newPassword) is null)
            : CanSubmit);
    }

    private void UpdateRules(string password)
    {
        var checks = AccountRules.PasswordChecks(password);
        foreach (var (label, rule) in _ruleLabels) label.Foreground = Brush(checks[rule] ? Green : Secondary);
    }

    // ---------- Écrans de connexion ----------

    private FrameworkElement SignInCard()
    {
        var card = new StackPanel { Spacing = 18 };
        var head = new StackPanel { Spacing = 12, HorizontalAlignment = HorizontalAlignment.Center };
        head.Children.Add(Badge("", Tint));
        var title = SwissTitle(25);
        title.Text = Loc.T("Ton compte FL Shortcuts");
        title.TextAlignment = TextAlignment.Center;
        title.CharacterSpacing = -20;
        head.Children.Add(title);
        card.Children.Add(head);
        card.Children.Add(Tabs());

        var fields = new StackPanel { Spacing = 16 };
        if (_creating)
        {
            var name = Input(_username, Loc.T("ton.pseudo"));
            name.MaxLength = 24;
            name.TextChanged += (_, _) =>
            {
                _username = name.Text;
                CheckName(name.Text);
            };
            AutomationProperties.SetName(name, Loc.T("Pseudo"));
            _nameStatus = Label("", 11.5, Secondary, bold: true);
            fields.Children.Add(Field(Loc.T("Pseudo"), name, _nameStatus));
            _nameHint = Paragraph("", 11, Orange);
            fields.Children.Add(_nameHint);
        }
        var mail = Input(_email, Loc.T("toi@exemple.com"));
        mail.InputScope = new InputScope { Names = { new InputScopeName(InputScopeNameValue.EmailSmtpAddress) } };
        mail.TextChanged += (_, _) =>
        {
            _email = mail.Text;
            UpdateSubmit();
        };
        AutomationProperties.SetName(mail, Loc.T("E-mail"));
        fields.Children.Add(Field(Loc.T("E-mail"), mail));
        var pass = Secret(_password, _creating ? Loc.T("8 caractères au moins") : Loc.T("Ton mot de passe"));
        pass.PasswordChanged += (_, _) =>
        {
            _password = pass.Password;
            UpdateRules(pass.Password);
            UpdateSubmit();
        };
        pass.KeyDown += (_, e) =>
        {
            if (e.Key == Windows.System.VirtualKey.Enter && CanSubmit && !_busy) Submit();
        };
        AutomationProperties.SetName(pass, Loc.T("Mot de passe"));
        fields.Children.Add(Field(Loc.T("Mot de passe"), pass, _creating ? null : LinkButton(Loc.T("Mot de passe oublié ?"), ForgotPassword)));
        if (_creating) fields.Children.Add(Rules(_password));
        card.Children.Add(fields);

        _submit = Primary(_creating ? Loc.T("Créer mon compte") : Loc.T("Se connecter"), Submit);
        _submit.HorizontalAlignment = HorizontalAlignment.Stretch;
        _submit.MinHeight = 40;
        card.Children.Add(_submit);
        card.Children.Add(Status());
        if (_creating)
        {
            var note = Paragraph(Loc.T("Les autres voient ton pseudo et ta photo, jamais ton e-mail."), 11.5);
            note.TextAlignment = TextAlignment.Center;
            card.Children.Add(note);
        }
        if (_creating) SetNameCheck(_nameCheck, _nameWhy); else UpdateSubmit();
        return Card(card);
    }

    private FrameworkElement Tabs()
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var rule = Rule(LineColor);
        rule.VerticalAlignment = VerticalAlignment.Bottom;
        Grid.SetColumnSpan(rule, 2);
        grid.Children.Add(rule);
        void Tab(string title, bool creating, int column)
        {
            var selected = _creating == creating;
            var label = SwissLabel(title, 11, selected ? Text : Secondary);
            var button = new Button
            {
                Style = PlainButton,
                Content = label,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Center,
                MinHeight = 34,
                BorderBrush = Brush(selected ? Text : Colors.Transparent),
                BorderThickness = new Thickness(0, 0, 0, 2),
            };
            button.PointerEntered += (_, _) => label.Foreground = Brush(Text);
            button.PointerExited += (_, _) => label.Foreground = Brush(selected ? Text : Secondary);
            button.Click += (_, _) =>
            {
                if (_creating == creating) return;
                _creating = creating;
                _error = null;
                _notice = null;
                _render();
            };
            AutomationProperties.SetName(button, title);
            Grid.SetColumn(button, column);
            grid.Children.Add(button);
        }
        Tab(Loc.T("Se connecter"), false, 0);
        Tab(Loc.T("Créer un compte"), true, 1);
        return grid;
    }

    private FrameworkElement CodeCard(CodeKind kind, string email)
    {
        var recovery = kind == CodeKind.Recovery;
        var card = new StackPanel { Spacing = 18 };
        var head = new StackPanel { Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center };
        head.Children.Add(Badge("", Sky));
        var title = SwissTitle(25);
        title.Text = recovery ? Loc.T("Nouveau mot de passe") : Loc.T("Vérifie tes mails");
        title.TextAlignment = TextAlignment.Center;
        title.CharacterSpacing = -20;
        head.Children.Add(title);
        var sent = Paragraph(Loc.F("Code envoyé à %@", email.Length > 60 ? email[..60] + "…" : email), 13);
        sent.TextAlignment = TextAlignment.Center;
        head.Children.Add(sent);
        card.Children.Add(head);

        var code = Input(_code, "000000");
        code.MaxLength = 12;
        code.FontSize = 26;
        code.FontFamily = new FontFamily("Consolas");
        code.CharacterSpacing = 300;
        code.TextAlignment = TextAlignment.Center;
        code.InputScope = new InputScope { Names = { new InputScopeName(InputScopeNameValue.Number) } };
        code.TextChanged += (_, _) =>
        {
            _code = code.Text;
            UpdateSubmit();
        };
        code.KeyDown += (_, e) =>
        {
            if (e.Key == Windows.System.VirtualKey.Enter && _submit?.IsEnabled == true) Validate();
        };
        AutomationProperties.SetName(code, Loc.T("Code reçu par mail"));
        card.Children.Add(Field(Loc.T("Code reçu par mail"), code));
        if (recovery)
        {
            var pass = Secret(_newPassword, Loc.T("8 caractères au moins"));
            pass.PasswordChanged += (_, _) =>
            {
                _newPassword = pass.Password;
                UpdateRules(pass.Password);
                UpdateSubmit();
            };
            AutomationProperties.SetName(pass, Loc.T("Nouveau mot de passe"));
            card.Children.Add(Field(Loc.T("Nouveau mot de passe"), pass));
            card.Children.Add(Rules(_newPassword));
        }
        _submit = Primary(recovery ? Loc.T("Changer le mot de passe") : Loc.T("Valider"), Validate);
        _submit.HorizontalAlignment = HorizontalAlignment.Stretch;
        _submit.MinHeight = 40;
        card.Children.Add(_submit);
        var links = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 18, HorizontalAlignment = HorizontalAlignment.Center };
        links.Children.Add(LinkButton(Loc.T("Renvoyer le code"), ResendCode));
        links.Children.Add(LinkButton(Loc.T("Changer d'adresse"), () => CancelCode()));
        card.Children.Add(links);
        card.Children.Add(Status());
        var spam = Paragraph(Loc.T("Rien reçu ? Regarde dans les spams."), 11.5);
        spam.TextAlignment = TextAlignment.Center;
        card.Children.Add(spam);
        if (!recovery)
        {
            // Mail avec un lien au lieu d'un code : le lien confirme l'adresse, il ne reste qu'à se connecter.
            var link = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4, HorizontalAlignment = HorizontalAlignment.Center };
            link.Children.Add(Paragraph(Loc.T("Reçu un lien au lieu d'un code ?"), 11));
            link.Children.Add(LinkButton(Loc.T("J'ai cliqué sur le lien"), () =>
            {
                _creating = false;
                CancelCode(Loc.T("Si tu as cliqué sur le lien du mail, ton adresse est confirmée : connecte-toi avec ton mot de passe."));
            }, 11));
            card.Children.Add(link);
        }
        UpdateSubmit();
        return Card(card);
    }

    private FrameworkElement Status()
    {
        var panel = new StackPanel { Spacing = 4 };
        if (_busy) panel.Children.Add(new ProgressBar { IsIndeterminate = true, Foreground = Brush(Text), Background = Brush(Faint) });
        if (_error is not null) panel.Children.Add(Paragraph(_error, 12, Red));
        if (_notice is not null) panel.Children.Add(Paragraph(_notice, 12, Text));
        return panel;
    }

    /// Les 5 règles du mot de passe (pastilles du Mac), vertes une fois remplies.
    private FrameworkElement Rules(string password)
    {
        var names = new[] { Loc.T("8 caractères"), Loc.T("Minuscule"), Loc.T("Majuscule"), Loc.T("Chiffre"), Loc.T("Symbole") };
        var grid = new Grid { ColumnSpacing = 10, RowSpacing = 4 };
        for (var c = 0; c < 3; c++) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition());
        grid.RowDefinitions.Add(new RowDefinition());
        for (var i = 0; i < names.Length; i++)
        {
            var label = Label("✓ " + names[i], 11.5, Secondary, semibold: true);
            Grid.SetColumn(label, i % 3);
            Grid.SetRow(label, i / 3);
            grid.Children.Add(label);
            _ruleLabels.Add((label, i));
        }
        UpdateRules(password);
        return grid;
    }

    // ---------- Connecté ----------

    private FrameworkElement SignedIn(AccountSession session)
    {
        var page = new StackPanel { Spacing = 14, Padding = new Thickness(26, 10, 26, 24) };
        page.Children.Add(_editing ? EditCard(session) : ProfileCard(session));
        if (_notice is not null) page.Children.Add(Paragraph(_notice, 12, Text));

        var backup = new StackPanel { Spacing = 8 };
        backup.Children.Add(SwissLabel(Loc.T("Sauvegarde"), 11, Text));
        backup.Children.Add(Rule(LineColor));
        backup.Children.Add(Paragraph(Loc.T("Bientôt sur Windows : pour l'instant, tes raccourcis et tes macros restent sur ce PC."), 12.5));
        page.Children.Add(Boxed(backup, new Thickness(20, 16, 20, 16)));

        var delete = new Grid { ColumnSpacing = 12 };
        delete.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        delete.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        delete.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var trash = Icon("trash", 15, Red);
        trash.VerticalAlignment = VerticalAlignment.Center;
        delete.Children.Add(trash);
        var label = Label(Loc.T("Supprimer mon compte"), 13);
        label.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(label, 1);
        delete.Children.Add(label);
        var button = DangerButton(Loc.T("Supprimer…"), DeleteAccount);
        ToolTipService.SetToolTip(button, Loc.T("Efface ton compte et tes partages. Tes raccourcis et tes macros restent sur ce PC."));
        Grid.SetColumn(button, 2);
        delete.Children.Add(button);
        var deleteBox = new StackPanel { Spacing = 8, Children = { delete } };
        if (_deleteError is not null) deleteBox.Children.Add(Paragraph(_deleteError, 12, Orange));
        var deleteCard = Boxed(deleteBox, new Thickness(20, 14, 20, 14));
        deleteCard.Margin = new Thickness(0, 10, 0, 0);
        page.Children.Add(deleteCard);
        return page;
    }

    private FrameworkElement ProfileCard(AccountSession session)
    {
        var grid = new Grid { ColumnSpacing = 18 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var avatar = new Button
        {
            Style = PlainButton,
            Content = Avatar(_myPhoto, session.Username, 72),
            Padding = new Thickness(0),
            BorderBrush = Brush(Text),
            BorderThickness = new Thickness(1),
            VerticalAlignment = VerticalAlignment.Center,
        };
        avatar.Click += (_, _) => EditProfile();
        ToolTipService.SetToolTip(avatar, Loc.T("Changer ta photo"));
        AutomationProperties.SetName(avatar, Loc.T("Changer ta photo"));
        grid.Children.Add(avatar);
        var who = new StackPanel { Spacing = 4, VerticalAlignment = VerticalAlignment.Center };
        var name = Label(session.Username.Length > 0 ? session.Username : session.Email, 22, Text, bold: true);
        name.FontFamily = SwissFont;
        name.TextTrimming = TextTrimming.CharacterEllipsis;
        who.Children.Add(name);
        var mail = Paragraph(session.Email, 12.5);
        mail.TextTrimming = TextTrimming.CharacterEllipsis;
        who.Children.Add(mail);
        Grid.SetColumn(who, 1);
        grid.Children.Add(who);
        var actions = new StackPanel { Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        var edit = Soft(Loc.T("Modifier le profil"), EditProfile);
        edit.HorizontalAlignment = HorizontalAlignment.Stretch;
        actions.Children.Add(edit);
        var signOut = Soft(Loc.T("Se déconnecter"), SignOut);
        signOut.HorizontalAlignment = HorizontalAlignment.Stretch;
        actions.Children.Add(signOut);
        Grid.SetColumn(actions, 2);
        grid.Children.Add(actions);
        return Boxed(grid, new Thickness(20));
    }

    private async void SignOut()
    {
        if (_session is not { } session) return;
        if (!await _confirm(Loc.T("Se déconnecter ?"),
                Loc.T("Tu pourras te reconnecter quand tu veux. Tes raccourcis et tes macros restent sur ce PC."),
                Loc.T("Se déconnecter"), false)) return;
        try { await Call(AccountRequests.SignOut(Server, session)); }
        catch (ServerError) { /* hors ligne ou session déjà finie : déconnecté ici quand même */ }
        _editing = false;
        _notice = null;
        Set(null);
        _render();
    }

    private async void DeleteAccount()
    {
        if (_session is null) return;
        if (!await _confirm(Loc.T("Supprimer ton compte ?"),
                Loc.T("Ton compte, ta sauvegarde en ligne et tes partages dans la Communauté seront effacés pour toujours. Tes raccourcis et tes macros restent sur ce PC."),
                Loc.T("Supprimer définitivement"), true)) return;
        _deleteError = null;
        try
        {
            var session = await Fresh();
            await Call(AccountRequests.DeleteAccount(Server, session));
            _editing = false;
            Set(null);
            _notice = Loc.T("Ton compte est supprimé. Tes raccourcis et tes macros restent sur ce PC.");
        }
        catch (ServerError e)
        {
            _deleteError = e.Message;
        }
        _render();
    }

    // ---------- Modifier le profil ----------

    private void StartEditing()
    {
        _editing = true;
        _editName = _session?.Username ?? "";
        _editFile = null;
        _editPhoto = null;
        _removePhoto = false;
        _zoom = 1;
        _dx = _dy = 0;
        _editProblem = null;
        _nameCheck = NameCheck.None;
        _nameWhy = null;
    }

    private bool CanSaveProfile =>
        AccountRules.UsernameProblem(_editName.Trim()) is null && _nameCheck is not (NameCheck.Taken or NameCheck.Checking)
        && (_editFile is null || _editPhoto is not null);

    private FrameworkElement EditCard(AccountSession session)
    {
        var card = new StackPanel { Spacing = 14 };
        card.Children.Add(SwissLabel(Loc.T("Modifier le profil"), 11, Text));
        card.Children.Add(Rule(Text));

        var row = new Grid { ColumnSpacing = 18 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var shown = _removePhoto ? null : _editPhoto ?? (_editFile is null ? _myPhoto : null);
        var preview = new Border
        {
            Child = Avatar(shown, _editName.Trim().Length > 0 ? _editName : session.Username, 128),
            BorderBrush = Brush(Text),
            BorderThickness = new Thickness(1),
            VerticalAlignment = VerticalAlignment.Top,
        };
        AutomationProperties.SetName(preview, Loc.T("Ta photo"));
        if (_editFile is not null) DragToPlace(preview);
        row.Children.Add(preview);

        var right = new StackPanel { Spacing = 10 };
        var photoButtons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        photoButtons.Children.Add(Soft(Loc.T("Choisir une photo…"), ChoosePhoto));
        if (!_removePhoto && (_editFile is not null || _myPhoto is not null))
        {
            var remove = Soft(Loc.T("Retirer"), () =>
            {
                _removePhoto = true;
                _editFile = null;
                _editPhoto = null;
                _render();
            });
            ToolTipService.SetToolTip(remove, Loc.T("Retirer ta photo : ton initiale de couleur la remplace"));
            photoButtons.Children.Add(remove);
        }
        right.Children.Add(photoButtons);
        if (_editFile is not null)
        {
            right.Children.Add(SwissLabel(Loc.T("Zoom de la photo"), 10.5));
            var zoom = new Slider { Minimum = 1, Maximum = 4, StepFrequency = 0.05, Value = _zoom, MaxWidth = 260, HorizontalAlignment = HorizontalAlignment.Left };
            AutomationProperties.SetName(zoom, Loc.T("Zoom de la photo"));
            zoom.ValueChanged += (_, e) =>
            {
                _zoom = e.NewValue;
                PreparePhoto();
            };
            right.Children.Add(zoom);
            right.Children.Add(Paragraph(Loc.T("Glisse la photo pour la placer"), 11.5));
        }
        Grid.SetColumn(right, 1);
        row.Children.Add(right);
        card.Children.Add(row);

        var name = Input(_editName, Loc.T("ton.pseudo"));
        name.MaxLength = 24;
        name.TextChanged += (_, _) =>
        {
            _editName = name.Text;
            CheckName(name.Text, session.Username);
        };
        AutomationProperties.SetName(name, Loc.T("Pseudo"));
        _nameStatus = Label("", 11.5, Secondary, bold: true);
        card.Children.Add(Field(Loc.T("Pseudo"), name, _nameStatus));
        _nameHint = Paragraph("", 11, Orange);
        card.Children.Add(_nameHint);
        if (_editProblem is not null) card.Children.Add(Paragraph(_editProblem, 12, Red));
        if (_busy) card.Children.Add(new ProgressBar { IsIndeterminate = true, Foreground = Brush(Text), Background = Brush(Faint) });

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, HorizontalAlignment = HorizontalAlignment.Right };
        buttons.Children.Add(Soft(Loc.T("Annuler"), () =>
        {
            _editing = false;
            _render();
        }));
        _submit = Primary(Loc.T("Enregistrer"), SaveProfile);
        buttons.Children.Add(_submit);
        card.Children.Add(buttons);
        SetNameCheck(_nameCheck, _nameWhy);
        return Boxed(card, new Thickness(20));
    }

    /// Glisser la photo dans son carré la déplace (comme la feuille du Mac) ; l'image est refaite au lâcher.
    private void DragToPlace(Border preview)
    {
        Point? last = null;
        preview.PointerPressed += (_, e) =>
        {
            last = e.GetCurrentPoint(preview).Position;
            preview.CapturePointer(e.Pointer);
        };
        preview.PointerMoved += (_, e) =>
        {
            if (last is not { } from) return;
            var to = e.GetCurrentPoint(preview).Position;
            // Glisser vers la droite montre la gauche de l'image (la marge se déplace à l'opposé).
            _dx = Math.Clamp(_dx - (to.X - from.X) / 64, -1, 1);
            _dy = Math.Clamp(_dy - (to.Y - from.Y) / 64, -1, 1);
            last = to;
        };
        void Release()
        {
            if (last is null) return;
            last = null;
            PreparePhoto();
        }
        preview.PointerReleased += (_, _) => Release();
        preview.PointerCaptureLost += (_, _) => Release();
    }

    private async void ChoosePhoto()
    {
        var picker = new FileOpenPicker { SuggestedStartLocation = PickerLocationId.PicturesLibrary, ViewMode = PickerViewMode.Thumbnail };
        foreach (var ext in new[] { ".jpg", ".jpeg", ".png", ".bmp", ".gif", ".tif", ".tiff", ".heic", ".webp" }) picker.FileTypeFilter.Add(ext);
        WinRT.Interop.InitializeWithWindow.Initialize(picker, _hwnd);
        StorageFile? file;
        try { file = await picker.PickSingleFileAsync(); }
        catch (Exception e)
        {
            AppLog.Write("ACCOUNT", "photo : sélecteur indisponible (" + e.GetType().Name + ")");
            return;
        }
        if (file is null) return;
        _editProblem = null;
        try
        {
            var size = (await file.GetBasicPropertiesAsync()).Size;
            if (size > MaxFileBytes) throw new InvalidDataException();
            var buffer = await FileIO.ReadBufferAsync(file);
            var bytes = new byte[buffer.Length];
            using (var reader = DataReader.FromBuffer(buffer)) reader.ReadBytes(bytes);
            _editFile = bytes;
            _removePhoto = false;
            _zoom = 1;
            _dx = _dy = 0;
            _editPhoto = null;
        }
        catch (Exception)
        {
            _editProblem = Loc.T("Cette image ne se lit pas (ou elle est trop lourde) : choisis-en une autre.");
            _render();
            return;
        }
        PreparePhoto();
    }

    /// La photo à envoyer, refaite depuis l'image choisie (zoom, place) ; la dernière demande gagne.
    private async void PreparePhoto()
    {
        if (_editFile is not { } file) return;
        var version = ++_photoVersion;
        var jpeg = await ProfilePhotoWin.Jpeg(file, _zoom, _dx, _dy);
        if (version != _photoVersion) return;
        _editPhoto = jpeg;
        _editProblem = jpeg is null ? Loc.T("Cette image ne se lit pas (ou elle est trop lourde) : choisis-en une autre.") : null;
        _render();
    }

    private async void SaveProfile()
    {
        if (_busy) return;
        var name = _editName.Trim();
        _busy = true;
        _editProblem = null;
        _render();
        try
        {
            var session = await Fresh();
            if (name != session.Username)
            {
                var body = await Call(AccountRequests.SetUsername(Server, name, session));
                var kept = body.Trim().Trim('"');
                session = session with { Username = kept.Length > 0 ? kept : name };
                Set(session);
            }
            if (_editPhoto is { } jpeg)
            {
                await Call(AccountRequests.SetAvatar(Server, jpeg, session));
                _myPhoto = jpeg;
            }
            else if (_removePhoto)
            {
                await Call(AccountRequests.RemoveAvatar(Server, session));
                _myPhoto = null;
            }
            _editing = false;
            Changed?.Invoke();
        }
        catch (Exception e) when (e is ServerError or ArgumentException)
        {
            _editProblem = e.Message;
        }
        finally
        {
            _busy = false;
            _render();
        }
    }

    // ---------- Pièces ----------

    /// Photo d'un membre dans un carré ; sans photo, l'initiale de son pseudo sur sa couleur (AvatarView du Mac).
    public static FrameworkElement Avatar(byte[]? jpeg, string username, double size)
    {
        var grid = new Grid { Width = size, Height = size, Background = Brush(InitialColors[AccountRules.InitialColorIndex(username)]) };
        var initial = Label(AccountRules.Initial(username), size * 0.46, Colors.Black, bold: true);
        initial.FontFamily = SwissFont;
        initial.HorizontalAlignment = HorizontalAlignment.Center;
        initial.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(initial);
        if (jpeg is not null)
        {
            var image = new Image { Stretch = Stretch.UniformToFill, Width = size, Height = size };
            grid.Children.Add(image);
            _ = Show(image, jpeg);
        }
        AutomationProperties.SetAccessibilityView(grid, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        return grid;

        static async Task Show(Image image, byte[] jpeg)
        {
            try
            {
                using var stream = await ProfilePhotoWin.Stream(jpeg);
                var bitmap = new BitmapImage();
                await bitmap.SetSourceAsync(stream);
                image.Source = bitmap;
            }
            catch (Exception) { /* image illisible : l'initiale reste */ }
        }
    }

    private static Border Badge(string glyph, Color color) => new()
    {
        Width = 64,
        Height = 64,
        Background = Brush(color),
        HorizontalAlignment = HorizontalAlignment.Center,
        Child = new FontIcon
        {
            Glyph = glyph,
            FontFamily = new FontFamily("Segoe Fluent Icons, Segoe MDL2 Assets"),
            FontSize = 27,
            Foreground = Brush(Colors.Black),
        },
    };

    private static Border Card(UIElement content) => new()
    {
        Child = content,
        Width = 420,
        Padding = new Thickness(30, 28, 30, 28),
        HorizontalAlignment = HorizontalAlignment.Center,
        Background = Brush(Colors.Black),
        BorderBrush = Brush(LineColor),
        BorderThickness = new Thickness(1),
    };

    private static Border Boxed(UIElement content, Thickness padding) => new()
    {
        Child = content,
        Padding = padding,
        Background = Brush(Colors.Black),
        BorderBrush = Brush(LineColor),
        BorderThickness = new Thickness(1),
    };

    private static FrameworkElement Message(string title, string text)
    {
        var panel = new StackPanel { Spacing = 10, Padding = new Thickness(26, 30, 26, 24), MaxWidth = 520, HorizontalAlignment = HorizontalAlignment.Left };
        var t = Label(title, 20, Text, bold: true);
        t.FontFamily = SwissFont;
        panel.Children.Add(t);
        panel.Children.Add(Paragraph(text, 13));
        return panel;
    }

    /// Un champ : son nom en petites capitales (et, à droite, un lien ou l'état du pseudo), puis la case.
    private static FrameworkElement Field(string title, UIElement input, FrameworkElement? trailing = null)
    {
        var top = new Grid();
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var label = SwissLabel(title, 10.5);
        label.VerticalAlignment = VerticalAlignment.Bottom;
        top.Children.Add(label);
        if (trailing is not null)
        {
            trailing.VerticalAlignment = VerticalAlignment.Bottom;
            Grid.SetColumn(trailing, 1);
            top.Children.Add(trailing);
        }
        return new StackPanel { Spacing = 6, Children = { top, input } };
    }

    private static TextBox Input(string text, string placeholder) => new()
    {
        Text = text,
        PlaceholderText = placeholder,
        FontFamily = SwissFont,
        FontSize = 14,
        MinHeight = 38,
        Padding = new Thickness(10, 8, 10, 8),
        CornerRadius = new CornerRadius(0),
        Background = Brush(Colors.Black),
        BorderBrush = Brush(LineColor),
        BorderThickness = new Thickness(1),
        IsSpellCheckEnabled = false,
    };

    /// Mot de passe : l'œil de Windows montre ce qu'on tape tant qu'on appuie dessus.
    private static PasswordBox Secret(string password, string placeholder) => new()
    {
        Password = password,
        PlaceholderText = placeholder,
        FontSize = 14,
        MinHeight = 38,
        Padding = new Thickness(10, 8, 10, 8),
        CornerRadius = new CornerRadius(0),
        Background = Brush(Colors.Black),
        BorderBrush = Brush(LineColor),
        BorderThickness = new Thickness(1),
        PasswordRevealMode = PasswordRevealMode.Peek,
    };

    /// Lien blanc souligné (SwissLinkButtonStyle du Mac).
    private static Button LinkButton(string text, Action click, double size = 12)
    {
        var label = Label(text, size, Text);
        label.TextDecorations = Windows.UI.Text.TextDecorations.Underline;
        var button = new Button { Style = PlainButton, Content = label, Padding = new Thickness(0), MinHeight = 0 };
        button.PointerEntered += (_, _) => label.Foreground = Brush(Secondary);
        button.PointerExited += (_, _) => label.Foreground = Brush(Text);
        button.Click += (_, _) => click();
        AutomationProperties.SetName(button, text);
        return button;
    }

    /// Bouton rouge bordé (danger du Mac) ; au survol, rouge plein, texte noir.
    private static Button DangerButton(string text, Action click)
    {
        var label = Label(text.ToUpper(System.Globalization.CultureInfo.CurrentCulture), 12, Red, bold: true);
        label.CharacterSpacing = 80;
        var button = new Button
        {
            Style = PlainButton,
            Content = label,
            MinHeight = 32,
            Padding = new Thickness(16, 0, 16, 0),
            Background = Brush(Colors.Transparent),
            BorderBrush = Brush(Red),
            BorderThickness = new Thickness(1),
            VerticalAlignment = VerticalAlignment.Center,
        };
        void Set(bool on)
        {
            button.Background = Brush(on ? Red : Colors.Transparent);
            label.Foreground = Brush(on ? Colors.Black : Red);
        }
        button.PointerEntered += (_, _) => Set(true);
        button.PointerExited += (_, _) => Set(false);
        button.PointerCanceled += (_, _) => Set(false);
        button.Click += (_, _) => click();
        AutomationProperties.SetName(button, text);
        return button;
    }
}

/// Photo du profil préparée sur ce PC avant l'envoi (comme ProfilePhoto du Mac) : l'image choisie, à l'endroit, le carré
/// visible (zoom, place) réduit à 256 × 256, transparence sur fond blanc, JPEG dont la qualité baisse tant qu'il dépasse
/// la limite du serveur (72 Ko).
internal static class ProfilePhotoWin
{
    public static async Task<byte[]?> Jpeg(byte[] file, double zoom, double dx, double dy)
    {
        try
        {
            using var source = await Stream(file);
            var decoder = await BitmapDecoder.CreateAsync(source);
            int w0 = (int)decoder.PixelWidth, h0 = (int)decoder.PixelHeight;
            int w = (int)decoder.OrientedPixelWidth, h = (int)decoder.OrientedPixelHeight;
            var (x, y, visible) = AccountRules.CropRect(w, h, zoom, dx, dy);
            if (visible <= 0) return null;
            const int side = AccountRules.PhotoSide;
            var scale = (double)side / visible;
            // Ordre de Windows : mise à l'échelle (image non tournée), rotation EXIF, puis découpe (image tournée).
            uint sw = (uint)Math.Max(1, Math.Round(w0 * scale)), sh = (uint)Math.Max(1, Math.Round(h0 * scale));
            var rotated = w != w0;
            uint ow = rotated ? sh : sw, oh = rotated ? sw : sh;
            if (ow < side || oh < side) return null;
            var transform = new BitmapTransform
            {
                ScaledWidth = sw,
                ScaledHeight = sh,
                InterpolationMode = BitmapInterpolationMode.Fant,
                Bounds = new BitmapBounds
                {
                    X = (uint)Math.Clamp(Math.Round(x * scale), 0, ow - side),
                    Y = (uint)Math.Clamp(Math.Round(y * scale), 0, oh - side),
                    Width = side,
                    Height = side,
                },
            };
            var data = await decoder.GetPixelDataAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied, transform,
                ExifOrientationMode.RespectExifOrientation, ColorManagementMode.ColorManageToSRgb);
            var pixels = data.DetachPixelData();
            for (var i = 0; i + 3 < pixels.Length; i += 4)
            {
                var a = pixels[i + 3];
                if (a == 255) continue;
                var white = 255 - a;                                // transparence d'un PNG : fond blanc (comme le Mac)
                pixels[i] = (byte)Math.Min(255, pixels[i] + white);
                pixels[i + 1] = (byte)Math.Min(255, pixels[i + 1] + white);
                pixels[i + 2] = (byte)Math.Min(255, pixels[i + 2] + white);
                pixels[i + 3] = 255;
            }
            foreach (var quality in new[] { 0.82, 0.7, 0.55, 0.4, 0.25 })
            {
                using var output = new InMemoryRandomAccessStream();
                var options = new BitmapPropertySet { { "ImageQuality", new BitmapTypedValue(quality, PropertyType.Single) } };
                var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.JpegEncoderId, output, options);
                encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore, side, side, 96, 96, pixels);
                await encoder.FlushAsync();
                var jpeg = await Bytes(output);
                if (AccountRules.PhotoAcceptable(jpeg)) return jpeg;
            }
        }
        catch (Exception e)
        {
            AppLog.Write("ACCOUNT", "photo illisible (" + e.GetType().Name + ")");
        }
        return null;
    }

    public static async Task<InMemoryRandomAccessStream> Stream(byte[] bytes)
    {
        var stream = new InMemoryRandomAccessStream();
        using (var writer = new DataWriter(stream.GetOutputStreamAt(0)))
        {
            writer.WriteBytes(bytes);
            await writer.StoreAsync();
            await writer.FlushAsync();
            writer.DetachStream();
        }
        stream.Seek(0);
        return stream;
    }

    private static async Task<byte[]> Bytes(IRandomAccessStream stream)
    {
        var size = (uint)stream.Size;
        var bytes = new byte[size];
        using var reader = new DataReader(stream.GetInputStreamAt(0));
        await reader.LoadAsync(size);
        reader.ReadBytes(bytes);
        return bytes;
    }
}
