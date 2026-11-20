// Page Mon compte (Windows), comme celle du Mac (AccountView.swift, AccountAuthViews.swift, EditProfileSheet.swift) au
// style suisse : une carte au centre pour se connecter, créer son compte (pseudo vérifié en direct, règles du mot de passe
// qui passent au vert) ou entrer le code reçu par mail ; connecté, la carte du profil (photo ou initiale de couleur,
// pseudo, mail, « Modifier le profil », « Se déconnecter »), la sauvegarde en ligne (la même que celle du Mac, raccourcis
// traduits : AccountBackupWin) avec le choix quand ce PC et le compte ont chacun leurs changements, et « Supprimer mon
// compte ». Le compte est le même que sur le Mac (même serveur). Jamais de mot de passe gardé ni écrit dans le journal ;
// la session est chiffrée par Windows (AccountStore).
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
    /// La photo réglée est celle du compte (vidéo du 04/11 : « je ne peux pas zoomer dans la photo de mon profil ») :
    /// pas touchée, elle n'est pas renvoyée.
    private bool _editFromAccount;
    /// Le carré de la photo et le nom montré dessous : refaits seuls pendant un réglage (zoom, place), sans redessiner
    /// la carte (le curseur du zoom lâchait la souris à chaque pas).
    private Border? _previewHost;
    private string _previewName = "";
    private Slider? _zoomSlider;
    private bool _removePhoto;
    private double _zoom = 1, _dx, _dy;
    private string? _editProblem;
    private int _photoVersion;
    private string? _deleteError;

    // Contrôles mis à jour sans tout redessiner (le texte tapé garde la main).
    private Button? _submit;
    private TextBlock? _nameStatus;
    private TextBlock? _nameHint;

    public AccountPage(Action render, Func<string, string, string, bool, Task<bool>> confirm, IntPtr hwnd)
    {
        _render = render;
        _confirm = confirm;
        _hwnd = hwnd;
        _session = AccountStore.Load();
        if (_session is not null) _ = RefreshAndLoadPhoto();
    }

    public AccountSession? Session => _session;

    private AccountBackupWin? _backup;

    /// Sauvegarde en ligne (créée après la page, par la fenêtre) : la page suit son état.
    public AccountBackupWin? Backup
    {
        get => _backup;
        set
        {
            _backup = value;
            if (value is not null) value.Changed += _render;
        }
    }

    /// Question à trois réponses (0 : premier bouton, 1 : second, 2 : Annuler), fournie par la fenêtre.
    public Func<string, string, string, string, Task<int>>? Choose { get; set; }
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

    /// Carte « Thème » (MainShell), posée sous le profil quand on est connecté.
    public Func<FrameworkElement>? ThemeCard { get; set; }

    /// Thème (maquette « Minimal », comme le Mac) : Papier, Noir, Orange en onglets soulignés ; un clic le prend
    /// (MainShell.ChooseTheme relance l'app dans ce thème).
    public static FrameworkElement ThemeTabs(AppTheme current, Action<AppTheme> choose)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 24 };
        foreach (var theme in new[] { AppTheme.Papier, AppTheme.Noir, AppTheme.Orange })
        {
            var on = theme == current;
            var label = Label(ThemeTitle(theme), 14, on ? Text : MacLook.Secondary, semibold: on);
            var tab = new Border
            {
                Child = label,
                Padding = new Thickness(0, 0, 0, 6),
                BorderBrush = Brush(Text),
                BorderThickness = new Thickness(0, 0, 0, on ? 2 : 0),
            };
            var button = new Button { Style = PlainButton, Content = tab, Padding = new Thickness(0) };
            button.Click += (_, _) => choose(theme);
            AutomationProperties.SetName(button, ThemeTitle(theme));
            row.Children.Add(button);
        }
        return row;
    }

    public static string ThemeTitle(AppTheme theme) => theme switch
    {
        AppTheme.Papier => Loc.T("Papier"),
        AppTheme.Orange => Loc.T("Orange"),
        _ => Loc.T("Noir"),
    };

    public FrameworkElement Content(int columns)
    {
        _submit = null;
        _nameStatus = null;
        _nameHint = null;
        if (HelpPage.Server is null)
            return Message(Loc.T("Les comptes ne sont pas encore ouverts"), "");
        if (_session is { } session) return SignedIn(session, columns);
        // Maquette « Minimal » (20/11, comme le Mac) : la connexion seule, sans titre de page ni présentation.
        var card = _pending is { } pending ? CodeCard(pending.Kind, pending.Email) : SignInCard();
        return new StackPanel { Children = { card }, Padding = new Thickness(56, 40, 56, 32), MaxWidth = 592, HorizontalAlignment = HorizontalAlignment.Left };
    }

    // ---------- Serveur ----------

    internal sealed class ServerError : Exception
    {
        public ServerError(string message, int status) : base(message) => Status = status;
        public int Status { get; }
    }

    /// La réponse du serveur, ou ServerError avec son message traduit (comme CommunityClient.message du Mac).
    internal static async Task<string> Call(HttpRequestMessage request)
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

    /// La réponse brute du serveur (code et texte) ; seule une panne du réseau lève ServerError (code 0).
    internal static async Task<(int Status, string Body)> Send(HttpRequestMessage request)
    {
        try
        {
            using var response = await Http.SendAsync(request);
            return ((int)response.StatusCode, await response.Content.ReadAsStringAsync());
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

    /// La session pour une requête de la Communauté (rafraîchie si besoin) ; null : déconnecté ou hors ligne.
    public async Task<AccountSession?> FreshSession()
    {
        try { return await Fresh(); }
        catch (ServerError) { return null; }
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
            if (_forgot) return SupportRules.EmailProblem(mail) is null;
            if (!_creating) return mail.Length > 0 && _password.Length > 0;
            return AccountRules.UsernameProblem(_username.Trim()) is null && _nameCheck != NameCheck.Taken
                   && SupportRules.EmailProblem(mail) is null && AccountRules.PasswordProblem(_password) is null;
        }
    }

    private async void Submit()
    {
        if (_forgot)
        {
            ForgotPassword();
            return;
        }
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
            _notice = Loc.T("Code envoyé si ce mail a un compte.");
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
        // Maquette « Minimal » (comme le Mac) : seulement ce qui ne va pas, en orange sous la case.
        ShowHint(_nameHint, why ?? (check == NameCheck.Taken ? Loc.T("Ce pseudo est déjà pris.") : null));
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
        UpdateSubmit();
    }

    private void UpdateSubmit()
    {
        if (_submit is null) return;
        _submit.IsEnabled = !_busy && (_editing && _session is not null ? CanSaveProfile
            : _pending is { } p ? AccountRules.Code(_code) is not null && (p.Kind == CodeKind.Signup || AccountRules.PasswordProblem(_newPassword) is null)
            : CanSubmit);
        // Le bouton plein d'encre de la maquette ne pâlit pas tout seul : à demi effacé tant qu'il attend.
        if (!(_editing && _session is not null)) _submit.Opacity = _submit.IsEnabled ? 1 : 0.4;
    }

    // ---------- Écrans de connexion ----------

    /// « Mot de passe oublié ? » : l'adresse seule, puis le code reçu par mail (maquette « Minimal »).
    private bool _forgot;
    /// Ce qui manque au mot de passe choisi (en orange sous la case, comme le Mac).
    private TextBlock? _passHint;

    /// Titre d'un écran du compte (maquette « Minimal ») : « Connexion », « Créer un compte »… en 48 demi-gras.
    private static TextBlock BigTitle(string text)
    {
        var title = Label(text, 48, Text, semibold: true);
        title.CharacterSpacing = -30;
        title.TextWrapping = TextWrapping.Wrap;
        AutomationProperties.SetHeadingLevel(title, Microsoft.UI.Xaml.Automation.Peers.AutomationHeadingLevel.Level1);
        return title;
    }

    /// Champ de la maquette : son nom en gris au-dessus, la case bordée d'encre (2 points), 48 de haut.
    private static FrameworkElement MinimalField(string title, Control input)
    {
        input.MinHeight = 48;
        input.FontSize = 16;
        input.BorderThickness = new Thickness(2);
        input.BorderBrush = Brush(Text);
        AutomationProperties.SetName(input, title);
        return new StackPanel { Spacing = 8, Margin = new Thickness(0, 24, 0, 0), Children = { Label(title, 13, Secondary), input } };
    }

    private static TextBlock Hint() => new()
    {
        FontFamily = SwissFont, FontSize = 11, Foreground = Brush(Orange), TextWrapping = TextWrapping.Wrap,
        Margin = new Thickness(0, 6, 0, 0), Visibility = Visibility.Collapsed,
    };

    private static void ShowHint(TextBlock? hint, string? text)
    {
        if (hint is null) return;
        hint.Text = text ?? "";
        hint.Visibility = string.IsNullOrEmpty(text) ? Visibility.Collapsed : Visibility.Visible;
    }

    /// Connexion (maquette « Minimal », comme le Mac) : « Connexion » en grand, Adresse mail, Mot de passe,
    /// « Se connecter » plein d'encre ; dessous « Créer un compte » et « Mot de passe oublié ? ». Créer un compte : le
    /// pseudo en plus, « Recevoir le code » ; oublié : l'adresse seule ; « J'ai déjà un compte » y ramène.
    private FrameworkElement SignInCard()
    {
        var card = new StackPanel { MaxWidth = 480, HorizontalAlignment = HorizontalAlignment.Left };
        card.Children.Add(BigTitle(_forgot ? Loc.T("Mot de passe oublié") : _creating ? Loc.T("Créer un compte") : Loc.T("Connexion")));
        var mail = Input(_email, "");
        mail.InputScope = new InputScope { Names = { new InputScopeName(InputScopeNameValue.EmailSmtpAddress) } };
        mail.TextChanged += (_, _) =>
        {
            _email = mail.Text;
            UpdateSubmit();
        };
        mail.KeyDown += (_, e) => { if (e.Key == Windows.System.VirtualKey.Enter && CanSubmit && !_busy) Submit(); };
        card.Children.Add(MinimalField(Loc.T("Adresse mail"), mail));
        if (_creating && !_forgot)
        {
            var name = Input(_username, "");
            name.MaxLength = 24;
            name.TextChanged += (_, _) =>
            {
                _username = name.Text;
                CheckName(name.Text);
            };
            card.Children.Add(MinimalField(Loc.T("Pseudo"), name));
            _nameHint = Hint();
            card.Children.Add(_nameHint);
        }
        if (!_forgot)
        {
            var pass = Secret(_password, "");
            pass.PasswordChanged += (_, _) =>
            {
                _password = pass.Password;
                if (_creating) ShowHint(_passHint, pass.Password.Length == 0 ? null : AccountRules.PasswordProblem(pass.Password));
                UpdateSubmit();
            };
            pass.KeyDown += (_, e) => { if (e.Key == Windows.System.VirtualKey.Enter && CanSubmit && !_busy) Submit(); };
            card.Children.Add(MinimalField(Loc.T("Mot de passe"), pass));
            if (_creating)
            {
                _passHint = Hint();
                ShowHint(_passHint, _password.Length == 0 ? null : AccountRules.PasswordProblem(_password));
                card.Children.Add(_passHint);
            }
        }
        _submit = MinimalButton(_forgot || _creating ? Loc.T("Recevoir le code") : Loc.T("Se connecter"), Submit);
        _submit.HorizontalAlignment = HorizontalAlignment.Left;
        _submit.Margin = new Thickness(0, 32, 0, 0);
        card.Children.Add(_submit);
        var status = Status();
        status.Margin = new Thickness(0, 12, 0, 0);
        card.Children.Add(status);
        var links = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 20, Margin = new Thickness(0, 24, 0, 0) };
        if (_creating || _forgot)
        {
            links.Children.Add(MacLook.LinkButton(Loc.T("J'ai déjà un compte"), Text, () => ShowSignIn(creating: false, forgot: false)));
        }
        else
        {
            links.Children.Add(MacLook.LinkButton(Loc.T("Créer un compte"), Text, () => ShowSignIn(creating: true, forgot: false)));
            links.Children.Add(MacLook.LinkButton(Loc.T("Mot de passe oublié ?"), Secondary, () => ShowSignIn(creating: false, forgot: true)));
        }
        card.Children.Add(links);
        if (_creating && !_forgot) SetNameCheck(_nameCheck, _nameWhy); else UpdateSubmit();
        return card;
    }

    /// Passe d'un écran de connexion à l'autre (Connexion, Créer un compte, Mot de passe oublié).
    private void ShowSignIn(bool creating, bool forgot)
    {
        _creating = creating;
        _forgot = forgot;
        _error = null;
        _notice = null;
        _render();
    }

    /// Code reçu par mail en 6 cases (19/11, comme le Mac, CodeBoxes) : un clic n'importe où, chaque chiffre va dans la
    /// case suivante, ⌫ revient, un code collé remplit tout. Une seule zone de saisie invisible posée sur les cases.
    private FrameworkElement CodeBoxes(Action onEnter)
    {
        var boxes = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        var digits = new List<TextBlock>();
        var frames = new List<Border>();
        for (var i = 0; i < 6; i++)
        {
            var digit = new TextBlock
            {
                FontFamily = SwissFont, FontSize = 26, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Foreground = Brush(Text),
                HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            };
            var frame = new Border { Width = 48, Height = 60, BorderThickness = new Thickness(2), BorderBrush = Brush(Faint), Child = digit };
            digits.Add(digit);
            frames.Add(frame);
            boxes.Children.Add(frame);
        }
        var input = new TextBox
        {
            MaxLength = 6, Opacity = 0, HorizontalAlignment = HorizontalAlignment.Stretch, VerticalAlignment = VerticalAlignment.Stretch,
            InputScope = new InputScope { Names = { new InputScopeName(InputScopeNameValue.Number) } },
        };
        AutomationProperties.SetName(input, Loc.T("Code reçu par mail"));
        var focused = false;
        void Paint()
        {
            for (var i = 0; i < 6; i++)
            {
                digits[i].Text = i < _code.Length ? _code[i].ToString() : "";
                var current = focused && i == Math.Min(_code.Length, 5);
                frames[i].BorderBrush = Brush(i < _code.Length || current ? Text : Faint);
                frames[i].BorderThickness = new Thickness(current ? 3 : 2);
            }
        }
        input.TextChanged += (_, _) =>
        {
            var clean = new string(input.Text.Where(char.IsAsciiDigit).Take(6).ToArray());
            if (clean != input.Text)
            {
                input.Text = clean;
                input.SelectionStart = clean.Length;
                return;
            }
            _code = clean;
            Paint();
            UpdateSubmit();
        };
        input.GotFocus += (_, _) =>
        {
            focused = true;
            input.SelectionStart = input.Text.Length;
            Paint();
        };
        input.LostFocus += (_, _) =>
        {
            focused = false;
            Paint();
        };
        input.KeyDown += (_, e) => { if (e.Key == Windows.System.VirtualKey.Enter) onEnter(); };
        input.Text = new string(_code.Where(char.IsAsciiDigit).Take(6).ToArray());
        Paint();
        var grid = new Grid { HorizontalAlignment = HorizontalAlignment.Left };
        grid.Children.Add(boxes);
        grid.Children.Add(input);
        return grid;
    }

    /// Code reçu par mail (maquette « Minimal », comme le Mac) : le titre de l'écran, « Code envoyé à … », les 6 cases ;
    /// nouveau mot de passe s'il est oublié ; « Valider » et « Renvoyer le code » ; « J'ai déjà un compte ».
    private FrameworkElement CodeCard(CodeKind kind, string email)
    {
        var recovery = kind == CodeKind.Recovery;
        var card = new StackPanel { MaxWidth = 480, HorizontalAlignment = HorizontalAlignment.Left };
        card.Children.Add(BigTitle(recovery ? Loc.T("Mot de passe oublié") : Loc.T("Créer un compte")));
        var sent = Label(Loc.F("Code envoyé à %@.", email.Length > 60 ? email[..60] + "…" : email), 14, Text);
        sent.TextWrapping = TextWrapping.Wrap;
        sent.Margin = new Thickness(0, 16, 0, 0);
        card.Children.Add(sent);
        var boxes = CodeBoxes(() => { if (_submit?.IsEnabled == true) Validate(); });
        boxes.Margin = new Thickness(0, 24, 0, 0);
        card.Children.Add(boxes);
        if (recovery)
        {
            var pass = Secret(_newPassword, "");
            _passHint = Hint();
            pass.PasswordChanged += (_, _) =>
            {
                _newPassword = pass.Password;
                ShowHint(_passHint, pass.Password.Length == 0 ? null : AccountRules.PasswordProblem(pass.Password));
                UpdateSubmit();
            };
            card.Children.Add(MinimalField(Loc.T("Nouveau mot de passe"), pass));
            ShowHint(_passHint, _newPassword.Length == 0 ? null : AccountRules.PasswordProblem(_newPassword));
            card.Children.Add(_passHint);
        }
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16, Margin = new Thickness(0, 32, 0, 0) };
        _submit = MinimalButton(Loc.T("Valider"), Validate);
        row.Children.Add(_submit);
        var resend = MacLook.LinkButton(Loc.T("Renvoyer le code"), Text, ResendCode);
        resend.VerticalAlignment = VerticalAlignment.Center;
        row.Children.Add(resend);
        card.Children.Add(row);
        var status = Status();
        status.Margin = new Thickness(0, 12, 0, 0);
        card.Children.Add(status);
        var back = MacLook.LinkButton(Loc.T("J'ai déjà un compte"), Text, () =>
        {
            _creating = false;
            _forgot = false;
            CancelCode();
        });
        back.Margin = new Thickness(0, 24, 0, 0);
        card.Children.Add(back);
        UpdateSubmit();
        return card;
    }

    private FrameworkElement Status()
    {
        var panel = new StackPanel { Spacing = 4 };
        if (_busy) panel.Children.Add(new ProgressBar { IsIndeterminate = true, Foreground = Brush(Text), Background = Brush(Faint) });
        if (_error is not null) panel.Children.Add(Paragraph(_error, 12, Red));
        if (_notice is not null) panel.Children.Add(Paragraph(_notice, 12, Text));
        return panel;
    }

    // ---------- Connecté ----------

    /// « Supprimer mon compte » demandé dans la page (maquette « Minimal »).
    private bool _confirmingDelete;

    /// Maquette « Minimal » (20/11, comme le Mac) : la photo ronde et le pseudo en très grand avec son point rouge, le
    /// mail ; « Ajouter une photo » ; « Thème » : Papier, Noir, Orange soulignés ; « Se déconnecter » bordé ;
    /// « Supprimer mon compte » en rouge, qui demande dans la page. La sauvegarde ne se montre que s'il faut choisir.
    private FrameworkElement SignedIn(AccountSession session, int columns)
    {
        var page = new StackPanel { Padding = new Thickness(56, 40, 56, 24), MaxWidth = 912, HorizontalAlignment = HorizontalAlignment.Left };
        var head = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 20 };
        var avatar = new Button { Style = PlainButton, Content = Avatar(_myPhoto, session.Username, 96), Padding = new Thickness(0), VerticalAlignment = VerticalAlignment.Center };
        avatar.Click += (_, _) => EditProfile();
        ToolTipService.SetToolTip(avatar, Loc.T("Changer ta photo"));
        AutomationProperties.SetName(avatar, Loc.T("Changer ta photo"));
        head.Children.Add(avatar);
        var who = new StackPanel { Spacing = 8, VerticalAlignment = VerticalAlignment.Center };
        var nameRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 3 };
        var name = Label(DisplayText.Safe(session.Username.Length > 0 ? session.Username : session.Email, 24), 48, Text, semibold: true);
        name.CharacterSpacing = -30;
        name.TextTrimming = TextTrimming.CharacterEllipsis;
        nameRow.Children.Add(new Viewbox { Child = name, StretchDirection = StretchDirection.DownOnly, MaxWidth = 560, HorizontalAlignment = HorizontalAlignment.Left });
        nameRow.Children.Add(new Microsoft.UI.Xaml.Shapes.Rectangle { Width = 8, Height = 8, Fill = Brush(Red), VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, 12) });
        who.Children.Add(nameRow);
        var mail = Label(DisplayText.Safe(session.Email, 60), 13, Secondary);
        mail.TextTrimming = TextTrimming.CharacterEllipsis;
        who.Children.Add(mail);
        head.Children.Add(who);
        page.Children.Add(head);
        var photo = MacLook.LinkButton(_myPhoto is null ? Loc.T("Ajouter une photo") : Loc.T("Changer la photo"), Text, EditProfile);
        photo.Margin = new Thickness(0, 16, 0, 0);
        photo.HorizontalAlignment = HorizontalAlignment.Left;
        page.Children.Add(photo);
        if (_editing)
        {
            var edit = EditCard(session);
            edit.Margin = new Thickness(0, 24, 0, 0);
            page.Children.Add(edit);
        }
        if (_notice is not null) page.Children.Add(Spaced(Paragraph(_notice, 12, Text), 24));
        var themeLabel = Label(Loc.T("Thème"), 13, Secondary);
        themeLabel.Margin = new Thickness(0, 48, 0, 0);
        page.Children.Add(themeLabel);
        if (ThemeCard is { } theme) page.Children.Add(Spaced(theme(), 16));
        if (_backup is { } backup)
        {
            if (backup.Notice is { } notice) page.Children.Add(Spaced(Paragraph(notice, 12, Text), 24));
            if (backup.Choice is { } choice) page.Children.Add(Spaced(ConflictCard(backup, choice), 32));
            // Page ouverte : le compte est relu s'il n'a pas été vu depuis 2 minutes (après ce dessin).
            Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread()?.TryEnqueue(() => _ = backup.RefreshIfStale());
        }
        var signOut = MinimalButton(Loc.T("Se déconnecter"), () => SignOut(ask: false), outlined: true);
        signOut.HorizontalAlignment = HorizontalAlignment.Left;
        ToolTipService.SetToolTip(signOut, Loc.T("Tes raccourcis et tes macros quittent ce PC et restent dans ton compte."));
        page.Children.Add(Spaced(signOut, 48));
        if (_confirmingDelete)
        {
            var ask = new StackPanel { Spacing = 8 };
            ask.Children.Add(Label(Loc.T("Supprimer le compte et sa sauvegarde ?"), 14, Text));
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16 };
            row.Children.Add(MinimalButton(Loc.T("Supprimer"), () =>
            {
                _confirmingDelete = false;
                DeleteAccount();
            }));
            var cancel = MacLook.LinkButton(Loc.T("Annuler"), Text, () =>
            {
                _confirmingDelete = false;
                _render();
            });
            cancel.VerticalAlignment = VerticalAlignment.Center;
            row.Children.Add(cancel);
            ask.Children.Add(row);
            page.Children.Add(Spaced(ask, 32));
        }
        else
        {
            var delete = MacLook.LinkButton(Loc.T("Supprimer mon compte"), Red, () =>
            {
                _confirmingDelete = true;
                _deleteError = null;
                _render();
            });
            delete.HorizontalAlignment = HorizontalAlignment.Left;
            page.Children.Add(Spaced(delete, 32));
        }
        if (_deleteError is not null) page.Children.Add(Spaced(Paragraph(_deleteError, 12, Red), 12));
        return page;
    }

    private static FrameworkElement Spaced(FrameworkElement element, double top)
    {
        element.Margin = new Thickness(0, top, 0, 0);
        return element;
    }

    /// « Se déconnecter » : comme le Mac, tout part d'abord en ligne, puis raccourcis et macros quittent ce PC (ils
    /// restent dans le compte) ; si quelque chose n'a pas pu partir, la question le dit.
    /// `ask` : « Se déconnecter ? » d'abord ; la page Mon compte se déconnecte tout de suite (maquette « Minimal »), la
    /// question revient seulement si des changements ne sont pas en ligne.
    private async void SignOut(bool ask = true)
    {
        if (_session is null) return;
        if (ask && !await _confirm(Loc.T("Se déconnecter ?"),
                Loc.T("Tes raccourcis et tes macros restent dans ton compte."),
                Loc.T("Se déconnecter"), false)) return;
        if (_backup is null)
        {
            await SignOutNow();
            return;
        }
        var outcome = await _backup.SignOut(evenIfNotSaved: false);
        while (outcome is AccountBackupWin.SignOutOutcome.NotSaved notSaved && Choose is not null)
        {
            var answer = await Choose(Loc.T("Tes derniers changements ne sont pas en ligne"),
                Loc.F("%@ Si tu te déconnectes maintenant, ils seront perdus.", notSaved.Why),
                Loc.T("Réessayer"), Loc.T("Se déconnecter quand même"));
            if (answer == 0) outcome = await _backup.SignOut(evenIfNotSaved: false);
            else if (answer == 1) outcome = await _backup.SignOut(evenIfNotSaved: true);
            else return;
        }
    }

    /// La session se ferme sur le serveur (hors ligne : ici quand même) et sur ce PC.
    internal async Task SignOutNow()
    {
        if (_session is { } session && HelpPage.Server is { } server)
        {
            try { await Call(AccountRequests.SignOut(server, session)); }
            catch (ServerError) { /* hors ligne ou session déjà finie : déconnecté ici quand même */ }
        }
        _editing = false;
        _notice = null;
        Set(null);
        _render();
    }

    /// Le compte effacé (la question a été posée dans la page, maquette « Minimal »).
    private async void DeleteAccount()
    {
        if (_session is null) return;
        _deleteError = null;
        try
        {
            var session = await Fresh();
            await Call(AccountRequests.DeleteAccount(Server, session));
            _editing = false;
            Set(null);
            _backup?.ForgetSync();
            _notice = Loc.T("Ton compte est supprimé. Tes raccourcis et tes macros restent sur ce PC.");
        }
        catch (ServerError e)
        {
            _deleteError = e.Message;
        }
        _render();
    }

    // ---------- Sauvegarde ----------

    /// Ce PC et le compte ont chacun leurs changements : laquelle garder (comme AccountConflictCard du Mac).
    private FrameworkElement ConflictCard(AccountBackupWin backup, AccountBackupWin.Conflict choice)
    {
        var card = new StackPanel { Spacing = 10 };
        card.Children.Add(Label(Loc.T("Deux versions différentes"), 15, Text, bold: true));
        var sides = new Grid { ColumnSpacing = 12 };
        sides.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        sides.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        sides.Children.Add(Side(Loc.T("Ce PC"), choice.Here, Loc.T("La sauvegarde de ton compte est remplacée par ce qu'il y a ici."),
                                Primary(Loc.T("Garder ce PC"), () => _ = backup.Resolve(keepAccount: false))));
        var account = Side(Loc.T("Mon compte"), choice.Account + (When(choice.Remote.UpdatedAt) is { } w ? " · " + w : ""),
                           Loc.T("Ce PC reprend ta sauvegarde."),
                           Soft(Loc.T("Garder mon compte"), () => _ = backup.Resolve(keepAccount: true)));
        Grid.SetColumn(account, 1);
        sides.Children.Add(account);
        card.Children.Add(sides);
        return new Border
        {
            Child = card,
            Padding = new Thickness(20, 16, 20, 16),
            Background = Brush(MacLook.WindowColor),
            BorderBrush = Brush(Orange),
            BorderThickness = new Thickness(2, 1, 1, 1),
        };

        static FrameworkElement Side(string title, string summary, string effect, Button button)
        {
            var side = new StackPanel { Spacing = 6, Padding = new Thickness(12), Background = Brush(Faint) };
            side.Children.Add(SwissLabel(title, 10));
            side.Children.Add(Label(summary, 13.5, Text, semibold: true));
            side.Children.Add(Paragraph(effect, 11.5));
            ToolTipService.SetToolTip(button, effect);
            side.Children.Add(button);
            return side;
        }
    }

    /// « 04/11/2026 10:12 » (heure de ce PC) d'une date du serveur ; null si elle ne se lit pas.
    private static string? When(string? iso) =>
        DateTimeOffset.TryParse(iso, System.Globalization.CultureInfo.InvariantCulture, System.Globalization.DateTimeStyles.None, out var d)
            ? d.ToLocalTime().ToString("g", System.Globalization.CultureInfo.CurrentCulture) : null;

    // ---------- Modifier le profil ----------

    private void StartEditing()
    {
        _editing = true;
        _editName = _session?.Username ?? "";
        // La photo du compte se règle tout de suite (zoom, place), comme une photo qu'on vient de choisir.
        _editFile = _myPhoto;
        _editPhoto = _myPhoto;
        _editFromAccount = _myPhoto is not null;
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
        _zoomSlider = null;
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
        _previewHost = preview;
        _previewName = _editName.Trim().Length > 0 ? _editName : session.Username;
        if (_editFile is not null)
        {
            DragToPlace(preview);
            // Molette (ou pincement du pavé tactile) sur la photo : zoom.
            preview.PointerWheelChanged += (_, e) =>
            {
                var delta = e.GetCurrentPoint(preview).Properties.MouseWheelDelta;
                _zoom = Math.Clamp(_zoom + delta / 1200.0, 1, 4);
                if (_zoomSlider is { } slider) slider.Value = _zoom;
                else PreparePhoto();
                e.Handled = true;
            };
        }
        row.Children.Add(preview);

        var right = new StackPanel { Spacing = 10 };
        var photoButtons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        var choosePhoto = Soft(Loc.T("Choisir une photo…"), ChoosePhoto);
        photoButtons.Children.Add(choosePhoto);
        if (!_removePhoto && (_editFile is not null || _myPhoto is not null))
        {
            var remove = Soft(Loc.T("Retirer"), () =>
            {
                _removePhoto = true;
                _editFile = null;
                _editPhoto = null;
                _editFromAccount = false;
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
            _zoomSlider = zoom;
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
        // Comme le Mac (07/11, « ça clique automatiquement sur le pseudo ») : la main posée toute seule sur le pseudo
        // à l'ouverture (le bouton « Modifier le profil » disparu) repart ; seul un clic dessus le fait écrire.
        var opened = DateTime.UtcNow;
        name.GotFocus += (_, _) =>
        {
            if (name.FocusState != FocusState.Pointer && DateTime.UtcNow - opened < TimeSpan.FromSeconds(0.6) && choosePhoto is Control photo)
                photo.Focus(FocusState.Programmatic);
        };
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
            _editFromAccount = false;
            _removePhoto = false;
            _zoom = 1;
            _dx = _dy = 0;
            _editPhoto = null;
        }
        catch (Exception)
        {
            _editProblem = Loc.T("Image illisible : choisis-en une autre.");
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
        var hadPhoto = _editPhoto is not null;
        _editPhoto = jpeg;
        _editProblem = jpeg is null ? Loc.T("Image illisible : choisis-en une autre.") : null;
        // Pendant un réglage, seul le carré de la photo change : le curseur du zoom garde la souris.
        if (jpeg is not null && hadPhoto && _previewHost is { } host)
        {
            host.Child = Avatar(jpeg, _previewName, 128);
            return;
        }
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
            if (_editPhoto is { } jpeg && !(_editFromAccount && _zoom == 1 && _dx == 0 && _dy == 0))
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
        // Rond, comme le Mac et les maquettes du 05/11 : l'initiale sur sa couleur, la photo dans un cercle par-dessus.
        var grid = new Grid
        {
            Width = size,
            Height = size,
            CornerRadius = new CornerRadius(size / 2),
            Background = Brush(InitialColors[AccountRules.InitialColorIndex(username)]),
        };
        var initial = Label(AccountRules.Initial(username), size * 0.46, Colors.Black, bold: true);
        initial.FontFamily = SwissFont;
        initial.HorizontalAlignment = HorizontalAlignment.Center;
        initial.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(initial);
        if (jpeg is not null)
        {
            var brush = new ImageBrush { Stretch = Stretch.UniformToFill };
            grid.Children.Add(new Microsoft.UI.Xaml.Shapes.Ellipse { Width = size, Height = size, Fill = brush });
            _ = Show(brush, jpeg);
        }
        AutomationProperties.SetAccessibilityView(grid, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        return grid;

        static async Task Show(ImageBrush brush, byte[] jpeg)
        {
            try
            {
                using var stream = await ProfilePhotoWin.Stream(jpeg);
                var bitmap = new BitmapImage();
                await bitmap.SetSourceAsync(stream);
                brush.ImageSource = bitmap;
            }
            catch (Exception) { /* image illisible : l'initiale reste */ }
        }
    }

    /// Carte des pages du compte (05/11, comme le Mac) : pleine du fond, trait de 2 points à l'encre, sur l'ombre nette du
    /// thème.
    private static FrameworkElement Card(UIElement content)
    {
        var face = new Border
        {
            Child = content,
            Padding = new Thickness(28, 26, 28, 26),
            Background = Brush(MacLook.WindowColor),
            BorderBrush = Brush(Text),
            BorderThickness = new Thickness(2),
        };
        return new Grid { Width = 400, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Top, Children = { HardShadow(PrimaryShadow, 6), face } };
    }

    private static Border Boxed(UIElement content, Thickness padding) => new()
    {
        Child = content,
        Padding = padding,
        Background = Brush(MacLook.WindowColor),
        BorderBrush = Brush(LineColor),
        BorderThickness = new Thickness(1),
    };

    private static FrameworkElement Message(string title, string text)
    {
        var panel = new StackPanel { Spacing = 10, Padding = new Thickness(26, 30, 26, 24), MaxWidth = 520, HorizontalAlignment = HorizontalAlignment.Left };
        var t = Label(title, 20, Text, bold: true);
        t.FontFamily = SwissFont;
        panel.Children.Add(t);
        if (text.Length > 0) panel.Children.Add(Paragraph(text, 13));
        return panel;
    }

    /// Un champ : son nom en petites capitales (et, à droite, un lien ou l'état du pseudo), puis la case.
    private static FrameworkElement Field(string title, UIElement input, FrameworkElement? trailing = null)
    {
        var top = new Grid();
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var label = SwissLabel(title, 11);
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
        MinHeight = 44,
        Padding = new Thickness(12, 10, 12, 10),
        CornerRadius = new CornerRadius(0),
        Background = Brush(MacLook.WindowColor),
        BorderBrush = Brush(Text),
        BorderThickness = new Thickness(1.5),
        IsSpellCheckEnabled = false,
    };

    /// Mot de passe : l'œil de Windows montre ce qu'on tape tant qu'on appuie dessus.
    private static PasswordBox Secret(string password, string placeholder) => new()
    {
        Password = password,
        PlaceholderText = placeholder,
        FontSize = 14,
        MinHeight = 44,
        Padding = new Thickness(12, 10, 12, 10),
        CornerRadius = new CornerRadius(0),
        Background = Brush(MacLook.WindowColor),
        BorderBrush = Brush(Text),
        BorderThickness = new Thickness(1.5),
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
