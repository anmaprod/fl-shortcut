// Page Communauté (Windows), comme celle du Mac (CommunityView.swift) au style suisse : des macros prêtes à l'emploi,
// partagées par d'autres, avec l'explication de leur auteur. On ouvre un partage pour lire ce qu'il fait, étape par
// étape, puis on l'ajoute ; rien ne s'ajoute sans cette fiche, rien ne se lance tout seul (une macro ajoutée n'a pas de
// raccourci). Les raccourcis partagés depuis un Mac sont traduits pour le clavier de ce PC (PlatformKeys). Compte
// nécessaire : sans compte, la carte de connexion de Mon compte. Tout ajout passe par MacroExchange (même contrôle qu'un
// fichier reçu). Jamais de titre, de nom ni de texte tapé dans le journal.
using FLShortcut.App.Services;
using FLShortcut.Core;
using FLShortcut.Core.Macros;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Windows.UI;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal sealed class CommunityPage
{
    /// Couleur de la page Communauté (comme SidebarItem.community du Mac).
    public static readonly Color Tint = Rgb(0xF5, 0xAD, 0x00);

    private enum Filter { All, Macros, Profiles, Mine }

    /// Raisons d'un signalement : le texte français est la valeur envoyée (comme le Mac), affiché traduit.
    private static readonly string[] Reasons =
    {
        "Dangereux : supprime, écrase ou envoie des choses sans prévenir",
        "Ne fait pas ce que dit son explication",
        "Contenu offensant",
        "Publicité ou spam",
        "Autre",
    };

    private readonly AppController _app;
    private readonly AccountPage _account;
    private readonly Action _render;
    private readonly Action<string, Action?> _toast;
    private readonly Func<string, string, string, bool, Task<bool>> _confirm;

    // Liste.
    private Filter _filter = Filter.All;
    private string _search = "";
    private (Guid Id, string Name)? _author;
    private List<Share>? _shares;
    private bool _loading;
    private string? _error;
    private string? _notice;
    private readonly Dictionary<Guid, byte[]> _photos = new();
    private int _version;
    private bool _demo;

    // Fiche d'un partage.
    private Share? _opened;
    private MacroExchange.Preview? _preview;
    private ImportPreview? _profilePreview;
    private string? _previewError;
    private bool _reporting;
    private int _reason;
    private string _details = "";

    // Partager.
    private bool _composing;
    private bool _composeProfile;
    private Guid? _composeMacro;
    private string _composeTitle = "";
    private string _composeNotes = "";
    private string? _composeProblem;
    private bool _busy;

    public CommunityPage(AppController app, AccountPage account, Action render, Action<string, Action?> toast,
                         Func<string, string, string, bool, Task<bool>> confirm)
    {
        _app = app;
        _account = account;
        _render = render;
        _toast = toast;
        _confirm = confirm;
        // Déconnexion : la liste est oubliée (relue à la prochaine connexion).
        _account.Changed += () =>
        {
            if (_account.Session is null) Forget();
        };
    }

    private void Forget()
    {
        _shares = null;
        _opened = null;
        _composing = false;
        _author = null;
        _photos.Clear();
    }

    public FrameworkElement Content(int columns)
    {
        if (HelpPage.Server is null && !_demo)
            return Message(Loc.T("Les comptes ne sont pas encore ouverts"), Loc.T("Tes raccourcis et tes macros restent sur ce PC en attendant."), null, null);
        if (_account.Session is null && !_demo) return _account.Content(columns);
        if (_composing) return Compose();
        if (_opened is { } share) return Detail(share);
        // Premier passage : la liste est demandée, la page montre le chargement (sans se redessiner pendant sa construction).
        if (_shares is null && !_loading && _error is null)
        {
            _loading = true;
            _ = Reload(renderFirst: false);
        }
        return List(columns);
    }

    // ---------- Serveur ----------

    private async Task Reload(bool renderFirst = true)
    {
        if (_demo)
        {
            _loading = false;
            return;
        }
        var version = ++_version;
        _loading = true;
        _error = null;
        if (renderFirst) _render();
        try
        {
            var session = await _account.FreshSession() ?? throw new AccountPage.ServerError(Loc.T("Session expirée : reconnecte-toi."), 401);
            var kind = _filter switch { Filter.Macros => CommunityRules.MacroKind, Filter.Profiles => CommunityRules.ProfileKind, _ => null };
            Guid? author = _filter == Filter.Mine ? session.UserId : _author?.Id;
            var body = await AccountPage.Call(CommunityRequests.Shares(HelpPage.Server!, session, kind, _search, author));
            if (version != _version) return;
            _shares = CommunityRequests.DecodeShares(body);
            AppLog.Write("COMMUNITY", $"{_shares.Count} partages lus");
            _ = LoadPhotos(session, _shares.Select(s => s.AuthorId).Distinct().Where(id => !_photos.ContainsKey(id)).ToList());
        }
        catch (AccountPage.ServerError e)
        {
            if (version == _version) _error = e.Message;
        }
        finally
        {
            if (version == _version)
            {
                _loading = false;
                _render();
            }
        }
    }

    private async Task LoadPhotos(AccountSession session, List<Guid> ids)
    {
        if (ids.Count == 0) return;
        try
        {
            var body = await AccountPage.Call(AccountRequests.Avatars(HelpPage.Server!, ids, session));
            foreach (var (id, jpeg) in AccountRequests.DecodeAvatars(body)) _photos[id] = jpeg;
            _render();
        }
        catch (AccountPage.ServerError) { /* serveur sans photos : les initiales restent */ }
    }

    private void Choose(Filter filter)
    {
        _filter = filter;
        if (filter == Filter.Mine) _author = null;
        _notice = null;
        _shares = null;
        _ = Reload();
    }

    // ---------- Liste ----------

    private FrameworkElement List(int columns)
    {
        var page = new StackPanel { Spacing = 18, Padding = new Thickness(26, 4, 26, 24) };

        var top = new Grid { ColumnSpacing = 14 };
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        // Maquette du 05/11 (comme le Mac) : recherche bordée de 2 points, pleine du fond, texte d'aide à l'encre.
        var search = new TextBox
        {
            Text = _search,
            PlaceholderText = Loc.T("Chercher une macro, des raccourcis"),
            PlaceholderForeground = Brush(WithOpacity(Text, 0.75)),
            FontFamily = SwissFont,
            FontSize = 14,
            MinHeight = 44,
            Background = Brush(MacLook.WindowColor),
            BorderBrush = Brush(Text),
            BorderThickness = new Thickness(2),
            CornerRadius = new CornerRadius(0),
            Padding = new Thickness(12, 10, 12, 10),
        };
        AutomationProperties.SetName(search, Loc.T("Rechercher"));
        search.TextChanged += (_, _) => _search = search.Text;
        search.KeyDown += (_, e) =>
        {
            if (e.Key == Windows.System.VirtualKey.Enter) Choose(_filter);
        };
        top.Children.Add(search);
        var share = Primary(Loc.T("Partager"), StartComposing);
        ToolTipService.SetToolTip(share, Loc.T("Partager une macro…"));
        Grid.SetColumn(share, 1);
        top.Children.Add(share);
        page.Children.Add(top);

        var filters = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var (filter, label) in new[] { (Filter.All, Loc.T("Tout")), (Filter.Macros, Loc.T("Macros")),
                                                (Filter.Profiles, Loc.T("Raccourcis")), (Filter.Mine, Loc.T("Les miens")) })
        {
            // Cases collées (maquette), la choisie pleine d'encre ; les autres pleines du fond.
            var f = filter;
            var on = _filter == f && _author is null;
            var chip = Option(SwissLabel(label, 11.5, on ? MacLook.WindowColor : Text), Tint, 0, () => Choose(f), on,
                              minHeight: 44, padding: new Thickness(14, 0, 14, 0));
            if (!on) chip.Background = Brush(MacLook.WindowColor);
            chip.BorderBrush = Brush(MacLook.Text);
            chip.BorderThickness = new Thickness(2);
            chip.Margin = new Thickness(filters.Children.Count > 0 ? -2 : 0, 0, 0, 0);
            filters.Children.Add(chip);
        }
        if (_author is { } author)
        {
            var everyone = Soft(Loc.F("Tous les partages de @%@", DisplayText.Safe(author.Name, 24)) + "  ✕", () =>
            {
                _author = null;
                Choose(_filter);
            });
            everyone.Margin = new Thickness(14, 0, 0, 0);
            ToolTipService.SetToolTip(everyone, Loc.T("Voir tout le monde"));
            filters.Children.Add(everyone);
        }
        page.Children.Add(filters);
        if (_notice is not null) page.Children.Add(Paragraph(_notice, 12.5, Text));

        if (_loading && _shares is null)
        {
            page.Children.Add(new ProgressBar { IsIndeterminate = true, Foreground = Brush(Text), Background = Brush(Faint) });
            return page;
        }
        if (_error is not null)
        {
            page.Children.Add(Paragraph(_error, 12.5, Red));
            page.Children.Add(Soft(Loc.T("Réessayer"), () => Choose(_filter)));
            return page;
        }
        var shares = _shares ?? new List<Share>();
        if (shares.Count == 0)
        {
            page.Children.Add(Empty());
            return page;
        }
        var grid = new Grid { ColumnSpacing = 20, RowSpacing = 20 };
        var cols = Math.Max(1, Math.Min(columns, 2));
        for (var c = 0; c < cols; c++) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        for (var i = 0; i < shares.Count; i++)
        {
            if (i % cols == 0) grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var card = Card(shares[i]);
            Grid.SetColumn(card, i % cols);
            Grid.SetRow(card, i / cols);
            grid.Children.Add(card);
        }
        page.Children.Add(grid);
        return page;
    }

    /// Pages vides, comme le Mac : recherche sans résultat, membre sans partage, filtre vide, rien du tout.
    private FrameworkElement Empty()
    {
        var words = CommunityRules.SearchPattern(_search);
        if (words.Length > 0)
            return Message(Loc.F("Aucun partage pour « %@ »", DisplayText.Safe(words, 30)),
                Loc.T("Essaie un autre mot."),
                Loc.T("Effacer la recherche"), () =>
                {
                    _search = "";
                    Choose(_filter);
                });
        if (_author is { } author)
            return Message(Loc.F("Aucun partage de @%@", DisplayText.Safe(author.Name, 24)),
                _filter == Filter.All ? Loc.T("Ce membre n'a rien publié pour l'instant.") : Loc.T("Ce membre n'a rien publié pour l'instant de ce genre."),
                Loc.T("Voir tout le monde"), () =>
                {
                    _author = null;
                    Choose(_filter);
                });
        if (_filter is Filter.Macros or Filter.Profiles)
            return Message(Loc.T("Rien de ce genre pour l'instant"),
                _filter == Filter.Macros ? Loc.T("Personne n'a encore partagé de macro.") : Loc.T("Personne n'a encore partagé de raccourcis."),
                Loc.T("Tout afficher"), () => Choose(Filter.All));
        return Message(Loc.T("Encore aucun partage"),
            Loc.T("Partage la première macro."),
            Loc.T("Partager une macro…"), StartComposing);
    }

    /// Un partage en carte (maquette du 05/11, comme le Mac) : sa sorte en petites capitales, le titre en grand, deux
    /// lignes de l'explication, puis la photo ronde et le pseudo de l'auteur ; bordée d'encre au survol.
    private FrameworkElement Card(Share share)
    {
        var text = new StackPanel { Spacing = 10 };
        text.Children.Add(SwissLabel(share.IsMacro ? Loc.T("Macro") : Loc.T("Raccourcis"), 11));
        var title = Label(DisplayText.Safe(share.Title, 80), 24, Text, bold: true);
        title.FontFamily = SwissFont;
        title.TextWrapping = TextWrapping.Wrap;
        title.MaxLines = 2;
        title.CharacterSpacing = -30;
        text.Children.Add(title);
        if (share.Notes.Trim().Length > 0)
        {
            var notes = Paragraph(share.Notes.Trim(), 13, Secondary);
            notes.MaxLines = 2;
            notes.TextTrimming = TextTrimming.CharacterEllipsis;
            text.Children.Add(notes);
        }
        var author = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, Margin = new Thickness(0, 4, 0, 0) };
        author.Children.Add(AccountPage.Avatar(_photos.GetValueOrDefault(share.AuthorId), share.AuthorName, 26));
        var name = Label("@" + DisplayText.Safe(share.AuthorName, 24), 14, Text, bold: true);
        name.VerticalAlignment = VerticalAlignment.Center;
        author.Children.Add(name);
        text.Children.Add(author);
        var border = new Border
        {
            Child = text,
            Padding = new Thickness(20, 18, 20, 18),
            Background = Brush(MacLook.WindowColor),
            BorderBrush = Brush(LineColor),
            BorderThickness = new Thickness(1),
        };
        var button = new Button
        {
            Style = PlainButton,
            Content = border,
            Padding = new Thickness(0),
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
        };
        button.PointerEntered += (_, _) => border.BorderBrush = Brush(Text);
        button.PointerExited += (_, _) => border.BorderBrush = Brush(LineColor);
        button.Click += (_, _) => Open(share);
        AutomationProperties.SetName(button, share.Title);
        return button;
    }

    // ---------- Fiche d'un partage ----------

    private async void Open(Share share)
    {
        _opened = share;
        _preview = null;
        _profilePreview = null;
        _previewError = null;
        _reporting = false;
        _reason = 0;
        _details = "";
        _render();
        try
        {
            byte[] payload;
            if (_demo)
            {
                payload = share.IsMacro ? MacroExchange.Export(DemoMacro(), "0.2.0", Home)
                    : System.Text.Encoding.UTF8.GetBytes(MacProfile.ToMac(ProfilePreset.Recommended.Shortcuts().Take(8), UsKeyLayout.Shared));
            }
            else
            {
                var session = await _account.FreshSession() ?? throw new AccountPage.ServerError(Loc.T("Session expirée : reconnecte-toi."), 401);
                var body = await AccountPage.Call(CommunityRequests.Payload(HelpPage.Server!, session, share.Id));
                payload = CommunityRequests.DecodePayload(body) ?? throw new AccountPage.ServerError(Loc.T("Réponse inattendue du serveur."), 0);
            }
            if (share.IsMacro)
            {
                var preview = MacroExchange.PrepareImport(payload, Home);
                if (_opened?.Id == share.Id) _preview = preview;
            }
            else
            {
                // Raccourcis d'un Mac (ou d'un PC) : traduits pour le clavier de ce PC.
                var preview = _app.PrepareImport(System.Text.Encoding.UTF8.GetString(payload));
                if (_opened?.Id == share.Id) _profilePreview = preview;
            }
        }
        catch (Exception e) when (e is AccountPage.ServerError or MacroExchange.ImportFailure or FormatException)
        {
            if (_opened?.Id == share.Id) _previewError = e.Message;
        }
        _render();
    }

    private static string Home => Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    private bool Mine(Share share) => _account.Session?.UserId == share.AuthorId;

    private FrameworkElement Detail(Share share)
    {
        var page = new StackPanel { Spacing = 18, Padding = new Thickness(26, 4, 26, 24), MaxWidth = 760, HorizontalAlignment = HorizontalAlignment.Left };
        page.Children.Add(Link("← " + Loc.T("Communauté"), () =>
        {
            _opened = null;
            _render();
        }));

        var head = new StackPanel { Spacing = 4 };
        var title = SwissTitle(26);
        title.Text = DisplayText.Safe(share.Title, 80);
        title.CharacterSpacing = -20;
        title.TextWrapping = TextWrapping.Wrap;
        head.Children.Add(title);
        head.Children.Add(Paragraph(share.Byline, 12));
        if (_author?.Id != share.AuthorId)
        {
            head.Children.Add(Link(Loc.F("Tous les partages de @%@", DisplayText.Safe(share.AuthorName, 24)), () =>
            {
                _author = (share.AuthorId, share.AuthorName);
                _opened = null;
                Choose(_filter == Filter.Mine ? Filter.All : _filter);
            }));
        }
        page.Children.Add(head);

        page.Children.Add(Part(Loc.F("L'explication de @%@", DisplayText.Safe(share.AuthorName, 24)),
            Paragraph(share.Notes.Trim().Length == 0 ? Loc.T("L'auteur n'a pas écrit d'explication.") : share.Notes,
                      13, share.Notes.Trim().Length == 0 ? Secondary : Text)));

        if (!share.IsMacro)
        {
            FrameworkElement list;
            if (_profilePreview is { } shortcuts)
            {
                var lines = new StackPanel { Spacing = 5, Padding = new Thickness(12) };
                foreach (var line in ProfileLines(shortcuts)) lines.Children.Add(Paragraph(line, 12, Text));
                list = new Border { Child = lines, Background = Brush(Faint) };
            }
            else if (_previewError is { } why)
            {
                list = Paragraph(Loc.F("Ce partage ne peut pas être ajouté : %@", why), 12, Orange);
            }
            else
            {
                list = Paragraph(Loc.T("Lecture du partage…"), 12);
            }
            page.Children.Add(Part(Loc.T("Les raccourcis qu'il contient"), list));
            if (_profilePreview is { } p)
            {
                var notes = new StackPanel { Spacing = 6 };
                notes.Children.Add(Paragraph("• " + Loc.T("Tes raccourcis sont remplacés. Annulable juste après."), 12, Text));
                if (p.Disabled > 0)
                    notes.Children.Add(Paragraph("• " + Loc.F("%lld raccourcis éteints : leur touche n'existe pas sur ce PC, ou elle est déjà prise.", p.Disabled), 12, Text));
                if (p.Refused.Count > 0)
                    notes.Children.Add(Paragraph("• " + Loc.F("Refusés par sécurité : %@", string.Join(" ; ", p.Refused)), 12, Orange));
                page.Children.Add(Part(Loc.T("Bon à savoir"), notes));
            }
        }
        else
        {
            FrameworkElement steps;
            if (_preview is { } preview)
            {
                var lines = new StackPanel { Spacing = 5, Padding = new Thickness(12) };
                foreach (var line in preview.Lines) lines.Children.Add(Paragraph(line, 12, Text));
                steps = new Border { Child = lines, Background = Brush(Faint) };
            }
            else if (_previewError is { } why)
            {
                steps = Paragraph(Loc.F("Ce partage ne peut pas être ajouté : %@", why), 12, Orange);
            }
            else
            {
                var loading = new StackPanel { Spacing = 6 };
                loading.Children.Add(new ProgressBar { IsIndeterminate = true, Foreground = Brush(Text), Background = Brush(Faint) });
                loading.Children.Add(Paragraph(Loc.T("Lecture du partage…"), 12));
                steps = loading;
            }
            page.Children.Add(Part(Loc.T("Ce que fait la macro, étape par étape"), steps));
            if (_preview is { } p)
            {
                var notes = new StackPanel { Spacing = 6 };
                foreach (var note in MacroExchange.Notes(p)) notes.Children.Add(Paragraph("• " + note, 12, Text));
                page.Children.Add(Part(Loc.T("Bon à savoir"), notes));
            }
        }

        if (_reporting) page.Children.Add(ReportForm(share));

        var buttons = new Grid { ColumnSpacing = 10 };
        buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        buttons.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        if (Mine(share))
        {
            buttons.Children.Add(Soft(Loc.T("Supprimer"), () => DeleteShare(share)));
        }
        else if (!_reporting)
        {
            var report = Soft(Loc.T("Signaler…"), () =>
            {
                _reporting = true;
                _render();
            });
            ToolTipService.SetToolTip(report, Loc.T("Prévenir les administrateurs : partage dangereux, trompeur ou offensant"));
            buttons.Children.Add(report);
        }
        var close = Soft(Loc.T("Fermer"), () =>
        {
            _opened = null;
            _render();
        });
        Grid.SetColumn(close, 2);
        buttons.Children.Add(close);
        var add = share.IsMacro ? Primary(Loc.T("Ajouter à mes macros"), () => Add())
                                : Primary(Loc.T("Utiliser ces raccourcis"), () => UseShortcuts(share));
        add.IsEnabled = share.IsMacro ? _preview is not null : _profilePreview is not null;
        Grid.SetColumn(add, 3);
        buttons.Children.Add(add);
        page.Children.Add(buttons);
        return page;
    }

    private void Add()
    {
        if (_preview is not { } preview) return;
        _opened = null;
        if (_demo)
        {
            _render();
            return;
        }
        var doc = preview.Doc;
        doc.Name = _app.Macros.UniqueName(doc.Name);
        _app.Macros.Add(doc);
        AppLog.Write("COMMUNITY", "macro ajoutée depuis un partage");
        _render();
        _toast(Loc.F("« %@ » ajoutée à tes macros : choisis-lui un raccourci dans la page Macros", DisplayText.Safe(doc.Name, 40)), null);
    }

    /// Une ligne par raccourci : « Ctrl+S → Save · Mixer » (éteints marqués).
    private static IEnumerable<string> ProfileLines(ImportPreview preview) => preview.Shortcuts.Take(120).Select(s =>
        $"{s.Trigger?.ToString() ?? "—"} → {s.Label}{(s.Context == ShortcutContext.Everywhere ? "" : " · " + s.Context.Label())}"
        + (s.Enabled ? "" : Loc.T(" · éteint")));

    /// « Utiliser ces raccourcis » : ils remplacent ceux de ce PC (ceux des macros restent), annulable.
    private void UseShortcuts(Share share)
    {
        if (_profilePreview is not { } preview) return;
        _opened = null;
        if (_demo)
        {
            _render();
            return;
        }
        var before = _app.ReplaceShortcuts(preview.Shortcuts);
        AppLog.Write("COMMUNITY", $"raccourcis d'un partage en place ({preview.Shortcuts.Count})");
        _render();
        _toast(Loc.F("Raccourcis de @%@ en place", DisplayText.Safe(share.AuthorName, 24)), () => _app.RestoreShortcuts(before));
    }

    private async void DeleteShare(Share share)
    {
        if (!await _confirm(Loc.F("Supprimer « %@ » ?", DisplayText.Safe(share.Title, 40)),
                Loc.T("Le partage disparaît pour tout le monde. Tes macros et raccourcis ne changent pas."),
                Loc.T("Supprimer"), true)) return;
        try
        {
            var session = await _account.FreshSession() ?? throw new AccountPage.ServerError(Loc.T("Session expirée : reconnecte-toi."), 401);
            await AccountPage.Call(CommunityRequests.Delete(HelpPage.Server!, session, share.Id));
            _opened = null;
            _shares?.RemoveAll(s => s.Id == share.Id);
        }
        catch (AccountPage.ServerError e)
        {
            _toast(e.Message, null);
        }
        _render();
    }

    private FrameworkElement ReportForm(Share share)
    {
        var form = new StackPanel { Spacing = 10 };
        form.Children.Add(SwissLabel(Loc.F("Signaler « %@ »", DisplayText.Safe(share.Title, 40)), 11, Text));
        form.Children.Add(Rule(Text));
        form.Children.Add(Paragraph(Loc.T("Les administrateurs le relisent. L'auteur ne saura pas qui."), 12));
        var reasons = new StackPanel { Spacing = 2 };
        for (var i = 0; i < Reasons.Length; i++)
        {
            var index = i;
            var option = Option(Label(Loc.T(Reasons[i]), 12.5), Tint, 0, () =>
            {
                _reason = index;
                _render();
            }, _reason == index, minHeight: 30, padding: new Thickness(10, 0, 10, 0));
            option.HorizontalAlignment = HorizontalAlignment.Stretch;
            reasons.Children.Add(option);
        }
        form.Children.Add(reasons);
        var details = new TextBox
        {
            Text = _details,
            PlaceholderText = Loc.T("Précisions facultatives"),
            FontFamily = SwissFont,
            Background = Brush(MacLook.WindowColor),
            BorderBrush = Brush(LineColor),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(0),
            MaxLength = 400,
        };
        details.TextChanged += (_, _) => _details = details.Text;
        AutomationProperties.SetName(details, Loc.T("Précisions facultatives"));
        form.Children.Add(details);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, HorizontalAlignment = HorizontalAlignment.Right };
        buttons.Children.Add(Soft(Loc.T("Annuler"), () =>
        {
            _reporting = false;
            _render();
        }));
        var send = Primary(Loc.T("Signaler"), () => SendReport(share));
        send.IsEnabled = !_busy;
        buttons.Children.Add(send);
        form.Children.Add(buttons);
        return new Border
        {
            Child = form,
            Padding = new Thickness(16),
            BorderBrush = Brush(Orange),
            BorderThickness = new Thickness(2, 0, 0, 0),
        };
    }

    private async void SendReport(Share share)
    {
        if (_busy) return;
        var extra = _details.Trim();
        var reason = Reasons[_reason] + (extra.Length == 0 ? "" : " : " + extra);
        if (reason.Length > 500) reason = reason[..500];
        _busy = true;
        _render();
        try
        {
            if (!_demo)
            {
                var session = await _account.FreshSession() ?? throw new AccountPage.ServerError(Loc.T("Session expirée : reconnecte-toi."), 401);
                await AccountPage.Call(CommunityRequests.Report(HelpPage.Server!, session, share.Id, reason));
            }
            _reporting = false;
            _toast(Loc.T("Merci, le signalement est envoyé."), null);
        }
        catch (Exception e) when (e is AccountPage.ServerError or ArgumentException)
        {
            _toast(e.Message, null);
        }
        finally
        {
            _busy = false;
            _render();
        }
    }

    // ---------- Partager ----------

    private void StartComposing()
    {
        _composing = true;
        _composeProfile = false;
        _composeMacro = _app.Macros.Macros.FirstOrDefault()?.Id;
        _composeTitle = "";
        _composeNotes = "";
        _composeProblem = null;
        _render();
    }

    private FrameworkElement Compose()
    {
        var page = new StackPanel { Spacing = 16, Padding = new Thickness(26, 4, 26, 24), MaxWidth = 640, HorizontalAlignment = HorizontalAlignment.Left };
        var title = SwissTitle(26);
        title.Text = Loc.T("Partager avec la Communauté");
        title.CharacterSpacing = -20;
        page.Children.Add(title);
        page.Children.Add(Paragraph(Loc.T("Les autres pourront lire ton explication, voir chaque étape, puis l'ajouter chez eux."), 12.5));

        var macros = _app.Macros.Macros;
        var kinds = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var (profile, label) in new[] { (false, Loc.T("Une macro")), (true, Loc.T("Tous mes raccourcis")) })
        {
            var p = profile;
            var chip = Option(Label(label, 12.5, bold: true), Tint, 0, () =>
            {
                _composeProfile = p;
                _render();
            }, _composeProfile == p, minHeight: 32, padding: new Thickness(14, 0, 14, 0));
            chip.BorderBrush = Brush(MacLook.Text);
            chip.BorderThickness = new Thickness(1);
            kinds.Children.Add(chip);
        }
        var quoi = new StackPanel { Spacing = 6, Children = { kinds } };
        quoi.Children.Add(Paragraph(_composeProfile ? Loc.T("Ton jeu de raccourcis complet : les autres pourront le mettre à la place du leur.")
                                                    : Loc.T("La macro choisie, avec ses étapes."), 11.5));
        page.Children.Add(Field(Loc.T("Quoi"), quoi));
        if (_composeProfile)
        {
            // Rien à choisir : tous les raccourcis de ce PC (sans ceux des macros), écrits comme sur le Mac.
        }
        else if (macros.Count == 0)
        {
            page.Children.Add(Field(Loc.T("Macro"), Paragraph(Loc.T("Tu n'as pas encore de macro : crée-en une dans la page Macros."), 12.5, Orange)));
        }
        else
        {
            var picker = MacLook.SwissCombo(new ComboBox
            {
                PlaceholderText = Loc.T("Choisir…"),
                MinWidth = 320,
            });
            foreach (var m in macros) picker.Items.Add(DisplayText.Safe(m.Name, 60));
            var index = macros.ToList().FindIndex(m => m.Id == _composeMacro);
            if (index >= 0) picker.SelectedIndex = index;
            picker.SelectionChanged += (_, _) =>
            {
                if (picker.SelectedIndex >= 0) _composeMacro = macros[picker.SelectedIndex].Id;
            };
            AutomationProperties.SetName(picker, Loc.T("Macro"));
            page.Children.Add(Field(Loc.T("Macro"), picker));
        }

        var name = Input(_composeTitle, Loc.T("ex. Armer la piste et lancer l'enregistrement"));
        name.MaxLength = CommunityRules.MaxTitle;
        name.TextChanged += (_, _) => _composeTitle = name.Text;
        AutomationProperties.SetName(name, Loc.T("Titre"));
        page.Children.Add(Field(Loc.T("Titre"), name));

        var notes = Input(_composeNotes, Loc.T("À quoi elle sert et où l'utiliser."));
        notes.AcceptsReturn = true;
        notes.TextWrapping = TextWrapping.Wrap;
        notes.MinHeight = 120;
        notes.MaxLength = CommunityRules.MaxNotes;
        notes.TextChanged += (_, _) => _composeNotes = notes.Text;
        AutomationProperties.SetName(notes, Loc.T("Explication"));
        page.Children.Add(Field(Loc.T("Explication"), notes));

        page.Children.Add(Paragraph(_composeProfile ? Loc.T("Partagé : tes raccourcis, le titre, ton explication, ton nom d'utilisateur.")
                                                    : Loc.T("Partagé : la macro, le titre, ton explication, ton nom d'utilisateur."), 11.5));
        page.Children.Add(Paragraph(Loc.T("Jamais partagé : ton mail, tes positions apprises, les chemins de tes fichiers."), 11.5));
        if (_composeProblem is not null) page.Children.Add(Paragraph(_composeProblem, 12, Red));
        if (_busy) page.Children.Add(new ProgressBar { IsIndeterminate = true, Foreground = Brush(Text), Background = Brush(Faint) });

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        buttons.Children.Add(Soft(Loc.T("Annuler"), () =>
        {
            _composing = false;
            _render();
        }));
        var publish = Primary(Loc.T("Publier"), Publish);
        publish.IsEnabled = !_busy && (_composeProfile || macros.Count > 0);
        ToolTipService.SetToolTip(publish, Loc.T("Publier pour tous les membres de la Communauté"));
        buttons.Children.Add(publish);
        page.Children.Add(buttons);
        return page;
    }

    private async void Publish()
    {
        if (_busy) return;
        MacroDoc? doc = null;
        if (!_composeProfile && (_composeMacro is not { } id || (doc = _app.Macros.Doc(id)) is null))
        {
            _composeProblem = Loc.T("Choisis la macro à partager.");
            _render();
            return;
        }
        _busy = true;
        _composeProblem = null;
        _render();
        try
        {
            // Raccourcis écrits comme sur le Mac (le format des partages) : un Mac les lit tels quels, un PC les traduit.
            var payload = doc is not null ? MacroExchange.Export(doc, HelpPage.AppVersion, Home)
                                          : System.Text.Encoding.UTF8.GetBytes(_app.MacProfileJson(withMacros: false));
            var kind = doc is not null ? CommunityRules.MacroKind : CommunityRules.ProfileKind;
            if (!_demo)
            {
                var session = await _account.FreshSession() ?? throw new AccountPage.ServerError(Loc.T("Session expirée : reconnecte-toi."), 401);
                await AccountPage.Call(CommunityRequests.Publish(HelpPage.Server!, session, kind,
                                                                 _composeTitle, _composeNotes, payload, HelpPage.AppVersion));
            }
            AppLog.Write("COMMUNITY", doc is not null ? "macro partagée" : "raccourcis partagés");
            _composing = false;
            _filter = Filter.All;
            _author = null;
            _shares = null;
            _notice = Loc.T("Partage publié.");
        }
        catch (Exception e) when (e is AccountPage.ServerError or ArgumentException)
        {
            _composeProblem = e.Message;
        }
        finally
        {
            _busy = false;
            _render();
        }
    }

    // ---------- Mode photos (CI) ----------

    /// Exemples sans réseau, pour les photos de la CI (jamais envoyés).
    public void Demo(bool detail)
    {
        _demo = true;
        _composing = false;
        var author = Guid.Parse("6f1d2c1e-0000-4000-8000-000000000001");
        _shares = new List<Share>
        {
            new(Guid.NewGuid(), author, CommunityRules.MacroKind, "Armer la piste et lancer l'enregistrement",
                "Clique sur ta piste dans le Mixer, puis lance la macro : la piste est armée et REC démarre.", "0.2.0", "2026-11-02T18:02:11+00:00", "flshortcuts"),
            new(Guid.NewGuid(), Guid.NewGuid(), CommunityRules.MacroKind, "Export Stems",
                "Toutes les pistes de la Playlist en WAV séparés, sur la sélection de temps.", "0.2.0", "2026-10-30T09:12:00+00:00", "leo.beats"),
            new(Guid.NewGuid(), Guid.NewGuid(), CommunityRules.ProfileKind, "Raccourcis du Mixer",
                "", "0.2.0", "2026-10-28T21:40:00+00:00", "sarah.mix"),
        };
        _opened = null;
        if (detail) Open(_shares[0]);
    }

    private static MacroDoc DemoMacro() => new()
    {
        Name = "Armer la piste et lancer l'enregistrement",
        Blocks = MacroTemplates.ArmThroughTrackMenu(new KeyRef(new MacKey(15))),
    };

    // ---------- Pièces ----------

    private static FrameworkElement Part(string title, UIElement body)
    {
        var part = new StackPanel { Spacing = 8 };
        part.Children.Add(SwissLabel(title, 11, Text));
        part.Children.Add(Rule(LineColor));
        part.Children.Add(body);
        return part;
    }

    private static FrameworkElement Field(string title, UIElement input) =>
        new StackPanel { Spacing = 6, Children = { SwissLabel(title, 10.5), input } };

    private static TextBox Input(string text, string placeholder) => new()
    {
        Text = text,
        PlaceholderText = placeholder,
        FontFamily = SwissFont,
        FontSize = 14,
        MinHeight = 38,
        Padding = new Thickness(10, 8, 10, 8),
        CornerRadius = new CornerRadius(0),
        Background = Brush(MacLook.WindowColor),
        BorderBrush = Brush(LineColor),
        BorderThickness = new Thickness(1),
    };

    /// Lien blanc souligné (SwissLinkButtonStyle du Mac).
    private static Button Link(string text, Action click)
    {
        var label = Label(text, 12.5, Text);
        label.TextDecorations = Windows.UI.Text.TextDecorations.Underline;
        var button = new Button { Style = PlainButton, Content = label, Padding = new Thickness(0), MinHeight = 0, HorizontalAlignment = HorizontalAlignment.Left };
        button.PointerEntered += (_, _) => label.Foreground = Brush(Secondary);
        button.PointerExited += (_, _) => label.Foreground = Brush(Text);
        button.Click += (_, _) => click();
        AutomationProperties.SetName(button, text);
        return button;
    }

    private static FrameworkElement Message(string title, string text, string? button, Action? action)
    {
        var panel = new StackPanel { Spacing = 10, Padding = new Thickness(0, 20, 0, 0), MaxWidth = 520, HorizontalAlignment = HorizontalAlignment.Left };
        var t = Label(title, 20, Text, bold: true);
        t.FontFamily = SwissFont;
        t.TextWrapping = TextWrapping.Wrap;
        panel.Children.Add(t);
        panel.Children.Add(Paragraph(text, 13));
        if (button is not null && action is not null) panel.Children.Add(Soft(button, action));
        return panel;
    }
}
