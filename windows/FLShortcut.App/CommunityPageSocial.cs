// Communauté du 11/11 (Windows), les mêmes écrans que le Mac (CommunityShowcase.swift, CommunitySocial.swift) :
// onglets Pour toi / Abonnements / Les plus ajoutées / Les miens (point rouge), vitrine « Pour toi » (de tes abonnements,
// créateurs à suivre, les plus ajoutées), page d'une personne (← pseudo, Suivre / Abonné, photo et abonnés, son travail
// trié), « ★ 4,6 · Ajoutée 312 fois », « Ta note » dans la fiche, ajout compté une fois sur le serveur. Sans
// supabase/communaute-suivre.sql : la Communauté d'avant, sans erreur. Jamais de titre ni de nom dans le journal.
using FLShortcut.Core;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal sealed partial class CommunityPage
{
    /// Le serveur a communaute-suivre.sql (faux : la Communauté d'avant).
    private bool _social = true;
    private List<Share> _followedPreview = new();
    private List<Share> _topPreview = new();
    private List<CommunityCreator> _creators = new();
    /// Les gens que l'on suit (seulement les siens).
    private HashSet<Guid> _following = new();
    private int? _personFollowers;
    private PersonSort _personSort = PersonSort.MostAdded;
    private int _newFromFollowed;
    /// Fiche : « Ta note » seulement si je l'ai ajouté (jamais le mien), et ma note.
    private bool _canRate;
    /// Ma note en demi-étoiles (1 à 10).
    private int? _half;
    private Microsoft.UI.Dispatching.DispatcherQueueTimer? _watch;

    /// Point rouge de la barre de gauche (MainShell le redessine quand il change).
    public int NewFromFollowed => _newFromFollowed;
    public Action? BadgeChanged { get; set; }
    /// Petit message avec un bouton de plus (« Noter »), donné par la fenêtre.
    public Action<string, Action?, string, Action>? ToastAction { get; set; }

    private bool IsPersonPage => _author is { } a && a.Id != _account.Session?.UserId;

    /// 11/11 : sur la page d'une personne, son pseudo prend la place du titre « communauté. » de la fenêtre.
    public string? PersonName => IsPersonPage ? _author!.Value.Name : null;

    /// Retour de la page d'une personne à la liste (← du titre, ou « Communauté » de la barre de gauche).
    public void LeavePerson() => Choose(_tab == CommunityTab.Mine ? (_social ? CommunityTab.MostAdded : CommunityTab.ForYou) : _tab);
    private bool Searching => CommunityRules.SearchPattern(_search).Length > 0;
    private bool Showcase => _social && _tab == CommunityTab.ForYou && _author is null && !Searching;

    // ---------- Serveur ----------

    /// Partages de l'onglet, d'une recherche ou de la page d'une personne ; avec leurs nombres tant que le serveur les a.
    private async Task<List<Share>> LoadList(AccountSession session, Guid? author)
    {
        if (_social)
        {
            try
            {
                if (author is null && !Searching && _tab == CommunityTab.Following)
                {
                    var list = CommunityRequests.DecodeShares(await SocialCall(() => CommunitySocial.FollowedShares(HelpPage.Server!, session, 50)));
                    MarkFollowedSeen();
                    return list;
                }
                if (author is null && !Searching && _tab == CommunityTab.MostAdded)
                    return CommunityRequests.DecodeShares(await SocialCall(() => CommunitySocial.MostAdded(HelpPage.Server!, session, null, 50)));
                return CommunityRequests.DecodeShares(await SocialCall(() => CommunityRequests.Shares(HelpPage.Server!, session, null, _search,
                    author, social: true, order: IsPersonPage ? _personSort.Order() : "created_at.desc")));
            }
            catch (AccountPage.ServerError e) when (CommunitySocial.IsMissingSocial(e.Status, e.Message))
            {
                _social = false;
                if (_tab.NeedsSocial()) _tab = CommunityTab.ForYou;
                AppLog.Write("COMMUNITY", "serveur sans communaute-suivre.sql : Communauté d'avant");
            }
        }
        return CommunityRequests.DecodeShares(await SocialCall(() => CommunityRequests.Shares(HelpPage.Server!, session, null, _search, author)));
    }

    /// La vitrine (Pour toi) ou la page d'une personne : ce qui va avec la liste. Sans réponse : rien de plus.
    private async Task LoadSocial(AccountSession session)
    {
        if (!_social) return;
        try
        {
            if (Showcase)
            {
                _following = CommunitySocial.DecodeFollowing(await AccountPage.Call(CommunitySocial.Following(HelpPage.Server!, session)));
                _followedPreview = CommunityRequests.DecodeShares(await SocialCall(() => CommunitySocial.FollowedShares(HelpPage.Server!, session, 3)));
                _topPreview = CommunityRequests.DecodeShares(await SocialCall(() => CommunitySocial.MostAdded(HelpPage.Server!, session, null, 3)));
                _creators = CommunitySocial.DecodeCreators(await AccountPage.Call(CommunitySocial.CreatorsToFollow(HelpPage.Server!, session, 5)));
            }
            else if (IsPersonPage && _author is { } person)
            {
                var found = CommunitySocial.DecodeCreators(await AccountPage.Call(CommunitySocial.Person(HelpPage.Server!, session, person.Id)));
                _personFollowers = found.FirstOrDefault()?.FollowerCount;
                _following = CommunitySocial.DecodeFollowing(await AccountPage.Call(CommunitySocial.Following(HelpPage.Server!, session)));
            }
        }
        catch (AccountPage.ServerError e) when (CommunitySocial.IsMissingSocial(e.Status, e.Message))
        {
            _social = false;
            _followedPreview = new();
            _topPreview = new();
            _creators = new();
        }
        catch (AccountPage.ServerError) { /* la vitrine reste vide : les nouveautés suffisent */ }
    }

    /// Photos à lire : auteurs des partages, de la vitrine, créateurs, personne ouverte.
    private IEnumerable<Guid> PhotoIds() =>
        (_shares ?? new List<Share>()).Select(s => s.AuthorId)
            .Concat(_followedPreview.Select(s => s.AuthorId)).Concat(_topPreview.Select(s => s.AuthorId))
            .Concat(_creators.Select(c => c.Id)).Concat(_author is { } a ? new[] { a.Id } : Array.Empty<Guid>()).Distinct();

    /// La même liste, relue (actualiser, rechercher, réessayer).
    private void Refresh()
    {
        _notice = null;
        _shares = null;
        _ = Reload();
    }

    /// Un onglet choisi : la recherche et la personne ouverte s'effacent.
    private void Choose(CommunityTab tab)
    {
        _tab = tab;
        _author = null;
        _search = "";
        _personFollowers = null;
        if (tab == CommunityTab.Following) MarkFollowedSeen();
        if (_demo)
        {
            DemoTab();
            _render();
            return;
        }
        Refresh();
    }

    /// La page d'une personne : son travail (les plus ajoutés d'abord), son nombre d'abonnés, et si on la suit.
    private void OpenPerson(Guid id, string name)
    {
        Leave();
        RenderAbove();
        if (id == _account.Session?.UserId || (_demo && id == DemoMe))
        {
            Choose(CommunityTab.Mine);
            return;
        }
        _author = (id, name);
        _search = "";
        _personFollowers = null;
        _personSort = PersonSort.MostAdded;
        if (_demo)
        {
            _personFollowers = 1284;
            _shares = DemoShares().Where(s => s.AuthorId == id).ToList();
            _render();
            return;
        }
        Refresh();
    }

    private void SortPerson(PersonSort sort)
    {
        _personSort = sort;
        if (_demo)
        {
            _shares = sort == PersonSort.MostAdded
                ? _shares?.OrderByDescending(s => s.AddCount ?? 0).ToList()
                : _shares?.OrderByDescending(s => s.CreatedAt, StringComparer.Ordinal).ToList();
            _render();
            return;
        }
        Refresh();
    }

    private async void Follow(Guid id, bool on)
    {
        if (id == _account.Session?.UserId) return;
        void Apply()
        {
            if (on) _following.Add(id); else _following.Remove(id);
            if (_author?.Id == id) _personFollowers = Math.Max((_personFollowers ?? 0) + (on ? 1 : -1), 0);
            _render();
        }
        if (_demo)
        {
            Apply();
            return;
        }
        try
        {
            var session = await _account.FreshSession() ?? throw new AccountPage.ServerError(Loc.T("Session expirée : reconnecte-toi."), 401);
            await AccountPage.Call(on ? CommunitySocial.Follow(HelpPage.Server!, session, id) : CommunitySocial.Unfollow(HelpPage.Server!, session, id));
            Apply();
        }
        catch (AccountPage.ServerError e)
        {
            _toast(e.Message, null);
        }
    }

    /// « Ajouter » compté une fois sur le serveur (jamais le sien) ; le nombre affiché suit. Silencieux.
    private async Task RecordAdd(Share share)
    {
        if (!_social || _demo || Mine(share)) return;
        try
        {
            var session = await _account.FreshSession();
            if (session is null) return;
            if (CommunitySocial.DecodeCount(await AccountPage.Call(CommunitySocial.RecordAdd(HelpPage.Server!, session, share.Id))) is { } count)
                UpdateShare(share.Id, s => s with { AddCount = count });
        }
        catch (AccountPage.ServerError e) when (CommunitySocial.IsMissingSocial(e.Status, e.Message)) { _social = false; }
        catch (AccountPage.ServerError) { }
    }

    /// La fiche ouverte : l'ai-je ajouté, et ma note.
    private async Task LoadRating(Share share)
    {
        _canRate = false;
        _half = null;
        if (!_social || Mine(share)) return;
        if (_demo)
        {
            _canRate = true;
            return;
        }
        try
        {
            var session = await _account.FreshSession();
            if (session is null) return;
            var added = CommunitySocial.DecodeAny(await AccountPage.Call(CommunitySocial.MyAdd(HelpPage.Server!, session, share.Id)));
            var half = CommunitySocial.DecodeHalf(await SocialCall(() => CommunitySocial.MyRating(HelpPage.Server!, session, share.Id)));
            if (_opened?.Id != share.Id) return;
            _canRate = added;
            _half = half;
            RenderAbove();
        }
        catch (AccountPage.ServerError e) when (CommunitySocial.IsMissingSocial(e.Status, e.Message)) { _social = false; }
        catch (AccountPage.ServerError) { }
    }

    /// Ma note en demi-étoiles (1 à 10, 19/11) ; serveur d'avant (rate_share_half absente) : l'étoile entière la plus
    /// proche, comme le Mac.
    private async void Rate(Share share, int half)
    {
        var before = _half;
        _half = half;
        RenderAbove();
        if (_demo) return;
        try
        {
            var session = await _account.FreshSession() ?? throw new AccountPage.ServerError(Loc.T("Session expirée : reconnecte-toi."), 401);
            if (CommunityRequests.HalfStars)
            {
                try
                {
                    if (CommunitySocial.DecodeRatedHalf(await AccountPage.Call(CommunitySocial.RateHalf(HelpPage.Server!, session, share.Id, half))) is { } rated)
                        UpdateShare(share.Id, s => s with { RatingHalfSum = rated.HalfSum, RatingCount = rated.Count });
                    return;
                }
                catch (AccountPage.ServerError e) when (e.Status == 404) { CommunityRequests.HalfStars = false; }
            }
            var stars = CommunitySocial.WholeStars(half);
            if (CommunitySocial.DecodeRated(await AccountPage.Call(CommunitySocial.Rate(HelpPage.Server!, session, share.Id, stars))) is { } whole)
                UpdateShare(share.Id, s => s with { RatingSum = whole.Sum, RatingHalfSum = null, RatingCount = whole.Count });
        }
        catch (AccountPage.ServerError e)
        {
            _half = before;
            RenderAbove();
            _toast(e.Message, null);
        }
    }

    /// Requête de la Communauté : sans les demi-étoiles sur le serveur (19/11), refaite sans leurs colonnes.
    private static async Task<string> SocialCall(Func<HttpRequestMessage> make)
    {
        try { return await AccountPage.Call(make()); }
        catch (AccountPage.ServerError e) when (CommunitySocial.IsMissingHalfStars(e.Status, e.Message) && CommunityRequests.HalfStars)
        {
            CommunityRequests.HalfStars = false;
            return await AccountPage.Call(make());
        }
    }

    /// Le même partage, partout où il est affiché.
    private void UpdateShare(Guid id, Func<Share, Share> change)
    {
        foreach (var list in new[] { _shares, _followedPreview, _topPreview })
        {
            if (list is null) continue;
            for (var i = 0; i < list.Count; i++) if (list[i].Id == id) list[i] = change(list[i]);
        }
        if (_opened?.Id == id) _opened = change(_opened);
        _render();
    }

    // ---------- Point rouge ----------

    /// Au lancement (compte connecté), puis toutes les 30 min : nouveautés des gens suivis.
    public void StartWatch(Microsoft.UI.Dispatching.DispatcherQueue queue)
    {
        _watch?.Stop();
        _watch = queue.CreateTimer();
        _watch.Interval = TimeSpan.FromMinutes(30);
        _watch.Tick += (_, _) => _ = CheckFollowed();
        _watch.Start();
        _ = CheckFollowed();
    }

    private async Task CheckFollowed()
    {
        if (!_social || _demo || HelpPage.Server is null || _account.Session is null) return;
        try
        {
            var session = await _account.FreshSession();
            if (session is null) return;
            var list = CommunityRequests.DecodeShares(await SocialCall(() => CommunitySocial.FollowedShares(HelpPage.Server!, session, 20)));
            if (_app.Settings.CommunityFollowedSeen is not { } seen)
            {
                MarkFollowedSeen();                            // première fois : seuls les partages d'après comptent
                return;
            }
            SetNew(CommunityStats.NewCount(list, DateTimeOffset.FromUnixTimeMilliseconds((long)(seen * 1000))));
        }
        catch (AccountPage.ServerError e) when (CommunitySocial.IsMissingSocial(e.Status, e.Message)) { _social = false; }
        catch (AccountPage.ServerError) { }
    }

    private void MarkFollowedSeen()
    {
        if (!_demo)
        {
            _app.Settings.CommunityFollowedSeen = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0;
            _app.Settings.Save();
        }
        SetNew(0);
    }

    private void SetNew(int count)
    {
        if (_newFromFollowed == count) return;
        _newFromFollowed = count;
        BadgeChanged?.Invoke();
    }

    // ---------- Écrans ----------

    private static Rectangle RedDot() => new() { Width = 7, Height = 7, Fill = Brush(Red), VerticalAlignment = VerticalAlignment.Center };

    /// Onglets (21/11, maquette « Minimal », comme le Mac) : Les plus ajoutées, Abonnements, Les miens, en mots de 14 ;
    /// le choisi à l'encre en demi-gras et souligné ; « Pour toi » seulement sans le serveur du 11/11.
    private FrameworkElement Tabs()
    {
        var tabs = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 24, VerticalAlignment = VerticalAlignment.Bottom };
        var shown = _social
            ? new[] { CommunityTab.MostAdded, CommunityTab.Following, CommunityTab.Mine }
            : new[] { CommunityTab.ForYou, CommunityTab.Mine };
        foreach (var tab in shown)
        {
            var t = tab;
            var on = _tab == t && _author is null && !Searching;
            var content = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 7, VerticalAlignment = VerticalAlignment.Center };
            content.Children.Add(Label(t.Title(), 14, on ? Text : Secondary, semibold: on));
            if (t == CommunityTab.Following && _newFromFollowed > 0) content.Children.Add(RedDot());
            var cell = new Grid { Height = 34, Children = { content } };
            if (on)
                cell.Children.Add(new Rectangle { Height = 2, Fill = Brush(Text), VerticalAlignment = VerticalAlignment.Bottom, IsHitTestVisible = false });
            var chip = new Button { Style = PlainButton, Content = cell, Padding = new Thickness(0) };
            chip.Click += (_, _) => Choose(t);
            AutomationProperties.SetName(chip, t.Title());
            tabs.Children.Add(chip);
        }
        return tabs;
    }

    /// Suivre / Abonné ✓ (un clic sur « Abonné » arrête de suivre). Jamais pour soi-même. 19/11 : « Abonné ✓ » a la
    /// même couleur que « Suivre », au repos comme au survol (comme le Mac).
    private Button? FollowButton(Guid id)
    {
        if (id == _account.Session?.UserId || (_demo && id == DemoMe)) return null;
        var on = _following.Contains(id);
        var button = on ? Primary(Loc.T("Abonné ✓"), () => Follow(id, false)) : Primary(Loc.T("Suivre"), () => Follow(id, true));
        ToolTipService.SetToolTip(button, on ? Loc.T("Ne plus suivre") : Loc.T("Voir ses nouveaux partages dans Abonnements"));
        return button;
    }

    /// Pseudo cliquable : la page de la personne.
    private Button AuthorLink(Guid id, string name, double size = 11, Color? color = null)
    {
        var label = Label("@" + DisplayText.Safe(name, 24), size, color ?? Text, semibold: true);
        label.TextTrimming = TextTrimming.CharacterEllipsis;
        var button = new Button { Style = PlainButton, Content = label, Padding = new Thickness(0), MinHeight = 0, VerticalAlignment = VerticalAlignment.Center };
        button.Click += (_, _) => OpenPerson(id, name);
        ToolTipService.SetToolTip(button, Loc.F("Voir la page de @%@", DisplayText.Safe(name, 24)));
        return button;
    }

    /// Titre d'une rangée de la vitrine : petites capitales, « N nouvelles » en rouge, « Tout voir → » à droite.
    private static FrameworkElement SectionHeader(string title, int fresh, Action? more)
    {
        var row = new Grid { ColumnSpacing = 10 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var left = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        left.Children.Add(SwissLabel(title, 11, Text));
        if (fresh > 0)
        {
            left.Children.Add(RedDot());
            left.Children.Add(SwissLabel(fresh == 1 ? Loc.T("1 nouvelle") : Loc.F("%lld nouvelles", fresh), 11, Red));
        }
        row.Children.Add(left);
        if (more is not null)
        {
            var all = Option(SwissLabel(Loc.T("Tout voir →"), 11, Text), more, minHeight: 24, padding: new Thickness(6, 0, 6, 0));
            Grid.SetColumn(all, 2);
            row.Children.Add(all);
        }
        return new StackPanel { Spacing = 8, Children = { row, Rule(LineColor) } };
    }

    /// Vitrine « Pour toi » : de tes abonnements, créateurs à suivre, les plus ajoutées (une rangée vide n'est pas montrée).
    private FrameworkElement ShowcaseRows()
    {
        var rows = new StackPanel { Spacing = 30 };
        if (_followedPreview.Count > 0)
        {
            var grid = new Grid { ColumnSpacing = 16 };
            for (var c = 0; c < 3; c++) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            for (var i = 0; i < Math.Min(3, _followedPreview.Count); i++)
            {
                var card = FollowedCard(_followedPreview[i], i < _newFromFollowed);
                Grid.SetColumn(card, i);
                grid.Children.Add(card);
            }
            rows.Children.Add(new StackPanel
            {
                Spacing = 12,
                Children = { SectionHeader(Loc.T("De tes abonnements"), _newFromFollowed, () => Choose(CommunityTab.Following)), grid },
            });
        }
        if (_creators.Count > 0)
        {
            var grid = new Grid { ColumnSpacing = 14 };
            for (var i = 0; i < _creators.Count; i++)
            {
                grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                var tile = CreatorTile(_creators[i]);
                Grid.SetColumn(tile, i);
                grid.Children.Add(tile);
            }
            rows.Children.Add(new StackPanel { Spacing = 12, Children = { SectionHeader(Loc.T("Créateurs à suivre"), 0, null), grid } });
        }
        if (_topPreview.Count > 0)
        {
            var list = new StackPanel { Spacing = 4 };
            list.Children.Add(SectionHeader(Loc.T("Les plus ajoutées"), 0, () => Choose(CommunityTab.MostAdded)));
            for (var i = 0; i < _topPreview.Count; i++) list.Children.Add(TopRow(_topPreview[i], i + 1));
            rows.Children.Add(list);
        }
        return rows;
    }

    private FrameworkElement FollowedCard(Share share, bool fresh)
    {
        var stack = new StackPanel { Spacing = 8 };
        var top = new Grid { ColumnSpacing = 8 };
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var avatar = AccountPage.Avatar(_photos.GetValueOrDefault(share.AuthorId), share.AuthorName, 16);
        avatar.VerticalAlignment = VerticalAlignment.Center;
        top.Children.Add(avatar);
        var author = AuthorLink(share.AuthorId, share.AuthorName);
        author.HorizontalAlignment = HorizontalAlignment.Left;
        Grid.SetColumn(author, 1);
        top.Children.Add(author);
        if (fresh)
        {
            var dot = RedDot();
            Grid.SetColumn(dot, 2);
            top.Children.Add(dot);
        }
        stack.Children.Add(top);
        var title = Label(DisplayText.Safe(share.Title, 80), 19, Text, bold: true);
        title.TextWrapping = TextWrapping.Wrap;
        title.MaxLines = 2;
        title.MinHeight = 46;
        title.CharacterSpacing = -30;
        stack.Children.Add(title);
        stack.Children.Add(SwissLabel(CommunityStats.Line(share) ?? " ", 10.5));
        return ClickableCard(stack, share, new Thickness(16, 14, 16, 14));
    }

    private FrameworkElement CreatorTile(CommunityCreator creator)
    {
        var stack = new StackPanel { Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center };
        var photo = new Button { Style = PlainButton, Padding = new Thickness(0), HorizontalAlignment = HorizontalAlignment.Center,
                                 Content = AccountPage.Avatar(_photos.GetValueOrDefault(creator.Id), creator.Username, 56) };
        photo.Click += (_, _) => OpenPerson(creator.Id, creator.Username);
        AutomationProperties.SetName(photo, "@" + creator.Username);
        stack.Children.Add(photo);
        var name = AuthorLink(creator.Id, creator.Username, 13.5);
        name.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Children.Add(name);
        var followers = Label(CommunityStats.Followers(creator.FollowerCount), 12, Secondary);
        followers.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Children.Add(followers);
        if (FollowButton(creator.Id) is { } follow)
        {
            follow.HorizontalAlignment = HorizontalAlignment.Center;
            follow.MinHeight = 28;
            stack.Children.Add(follow);
        }
        return new Border
        {
            Child = stack,
            Padding = new Thickness(6, 14, 6, 14),
            Background = Brush(MacLook.WindowColor),
            BorderBrush = Brush(LineColor),
            BorderThickness = new Thickness(1),
        };
    }

    private FrameworkElement TopRow(Share share, int rank)
    {
        var row = new Grid { ColumnSpacing = 18, MinHeight = 56 };
        foreach (var width in new[] { new GridLength(44), GridLength.Auto, GridLength.Auto, new GridLength(1, GridUnitType.Star), GridLength.Auto, GridLength.Auto })
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = width });
        var number = Label(rank.ToString("00", System.Globalization.CultureInfo.InvariantCulture), 28, Secondary, bold: true);
        number.CharacterSpacing = -40;
        number.VerticalAlignment = VerticalAlignment.Center;
        row.Children.Add(number);
        var title = Label(DisplayText.Safe(share.Title, 60), 18, Text, bold: true);
        title.TextTrimming = TextTrimming.CharacterEllipsis;
        title.VerticalAlignment = VerticalAlignment.Center;
        title.MaxWidth = 360;
        Grid.SetColumn(title, 1);
        row.Children.Add(title);
        var author = AuthorLink(share.AuthorId, share.AuthorName, 13, Secondary);
        Grid.SetColumn(author, 2);
        row.Children.Add(author);
        if (CommunityStats.Line(share) is { } stats)
        {
            var label = SwissLabel(stats, 10.5);
            label.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(label, 4);
            row.Children.Add(label);
        }
        var view = Small(Soft(Loc.T("Voir"), () => Open(share)));
        Grid.SetColumn(view, 5);
        row.Children.Add(view);
        return new StackPanel { Children = { row, Rule(Faint) } };
    }

    /// Une carte de la vitrine : toute la carte ouvre la fiche (sauf ses boutons), bordée d'encre au survol.
    private Border ClickableCard(UIElement content, Share share, Thickness padding)
    {
        var border = new Border
        {
            Child = content,
            Padding = padding,
            Background = Brush(MacLook.WindowColor),
            BorderBrush = Brush(LineColor),
            BorderThickness = new Thickness(1),
        };
        Color ink = Text, line = LineColor;
        border.PointerEntered += (_, _) => border.BorderBrush = Brush(ink);
        border.PointerExited += (_, _) => border.BorderBrush = Brush(line);
        border.Tapped += (_, e) =>
        {
            for (var d = e.OriginalSource as DependencyObject; d is not null && d != border; d = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetParent(d))
                if (d is Microsoft.UI.Xaml.Controls.Primitives.ButtonBase) return;
            Open(share);
        };
        AutomationProperties.SetName(border, share.Title);
        return border;
    }

    /// Page d'une personne : son pseudo est le titre de la fenêtre (à la place de « communauté. », avec la flèche pour
    /// revenir : MainShell, 11/11) ; ici sa photo en grand, son nombre d'abonnés et Suivre / Abonné ; « Son travail »
    /// et son tri. Rien d'autre (ni bio, ni date).
    private FrameworkElement PersonHeader()
    {
        var (id, name) = _author!.Value;
        var page = new StackPanel { Spacing = 22 };

        var who = new Grid { ColumnSpacing = 22 };
        who.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        who.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        who.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        who.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        who.Children.Add(AccountPage.Avatar(_photos.GetValueOrDefault(id), name, 96));
        // 19/11 (« mieux valoriser les abonnés et les partages ») : les deux en gros chiffres, comme le Mac.
        var counts = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 32, VerticalAlignment = VerticalAlignment.Center };
        void Big(int value, string word)
        {
            var count = new StackPanel { Spacing = 4 };
            var number = Label(CommunityStats.Number(value), 34, Text, bold: true);
            number.FontFamily = TitleFont;
            number.CharacterSpacing = -40;
            count.Children.Add(number);
            count.Children.Add(SwissLabel(word, 11));
            counts.Children.Add(count);
        }
        if (_social && _personFollowers is { } followers) Big(followers, followers == 1 ? Loc.T("Abonné") : Loc.T("Abonnés"));
        var shared = _shares?.Count ?? 0;
        Big(shared, shared == 1 ? Loc.T("Partage") : Loc.T("Partages"));
        Grid.SetColumn(counts, 1);
        who.Children.Add(counts);
        if (_social && FollowButton(id) is { } follow)
        {
            follow.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(follow, 3);
            who.Children.Add(follow);
        }
        page.Children.Add(who);

        var work = new Grid { ColumnSpacing = 12 };
        work.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        work.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        work.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        work.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var label = SwissLabel(Loc.T("Son travail"), 11, Text);
        label.VerticalAlignment = VerticalAlignment.Center;
        work.Children.Add(label);
        var n = SwissLabel((_shares?.Count ?? 0).ToString(System.Globalization.CultureInfo.InvariantCulture), 11);
        n.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(n, 1);
        work.Children.Add(n);
        if (_social)
        {
            var sorts = new StackPanel { Orientation = Orientation.Horizontal };
            foreach (var sort in Enum.GetValues<PersonSort>())
            {
                var s = sort;
                var on = _personSort == s;
                var box = Option(SwissLabel(s.Title(), 10.5, on ? MacLook.WindowColor : Text), () => SortPerson(s), on,
                                 minHeight: 30, padding: new Thickness(11, 0, 11, 0));
                if (!on) box.Background = Brush(MacLook.WindowColor);
                box.BorderBrush = Brush(MacLook.Text);
                box.BorderThickness = new Thickness(2);
                box.Margin = new Thickness(sorts.Children.Count > 0 ? -2 : 0, 0, 0, 0);
                sorts.Children.Add(box);
            }
            Grid.SetColumn(sorts, 3);
            work.Children.Add(sorts);
        }
        page.Children.Add(new StackPanel { Spacing = 8, Children = { work, Rule(LineColor) } });
        return page;
    }

    /// « Ta note » : 5 étoiles en demi-étoiles comme Letterboxd (19/11) : moitié gauche = demi, droite = entière ;
    /// pleines en rouge, vides en gris ; « 4,5 sur 5 » à côté. Null : pas de note possible.
    private FrameworkElement? StarsRow(Share share)
    {
        if (!_canRate || !_social || Mine(share)) return null;
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, Padding = new Thickness(20, 12, 20, 12) };
        var label = SwissLabel(Loc.T("Ta note"), 11, Text);
        label.VerticalAlignment = VerticalAlignment.Center;
        row.Children.Add(label);
        const double size = 24;
        var stars = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 2 };
        var fills = new List<Microsoft.UI.Xaml.Media.RectangleGeometry>();
        var value = Label("", 12, Secondary);
        value.VerticalAlignment = VerticalAlignment.Center;
        void Paint(int half)
        {
            for (var i = 0; i < fills.Count; i++)
            {
                var part = Math.Clamp(half - i * 2, 0, 2);
                fills[i].Rect = new Windows.Foundation.Rect(0, 0, size * part / 2.0, size + 8);
            }
            value.Text = half > 0 ? Loc.F("%@ sur 5", (half / 2.0).ToString("0.#", System.Globalization.CultureInfo.CurrentCulture)) : "";
        }
        for (var n = 1; n <= 5; n++)
        {
            var cell = new Grid { Width = size, Height = size + 8 };
            cell.Children.Add(new TextBlock { Text = "★", FontSize = 21, Foreground = Brush(LineColor), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
            var clip = new Microsoft.UI.Xaml.Media.RectangleGeometry { Rect = new Windows.Foundation.Rect(0, 0, 0, size + 8) };
            fills.Add(clip);
            var full = new Grid { Clip = clip };
            full.Children.Add(new TextBlock { Text = "★", FontSize = 21, Foreground = Brush(MacLook.Red), HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
            cell.Children.Add(full);
            foreach (var right in new[] { false, true })
            {
                var half = n * 2 - (right ? 0 : 1);
                var hit = new Border { Background = Brush(Colors.Transparent), Width = size / 2, HorizontalAlignment = right ? HorizontalAlignment.Right : HorizontalAlignment.Left };
                hit.Tapped += (_, _) => Rate(share, half);
                hit.PointerEntered += (_, _) => Paint(half);
                hit.PointerExited += (_, _) => Paint(_half ?? 0);
                var text = Loc.F("%@ sur 5", (half / 2.0).ToString("0.#", System.Globalization.CultureInfo.CurrentCulture));
                ToolTipService.SetToolTip(hit, text);
                AutomationProperties.SetName(hit, text);
                cell.Children.Add(hit);
            }
            stars.Children.Add(cell);
        }
        Paint(_half ?? 0);
        row.Children.Add(stars);
        row.Children.Add(value);
        return row;
    }

    /// Note et ajouts en grand (19/11, maquette « Minimal », comme `CommunityBigStats` du Mac) : « ★ 4,5 sur 5 »,
    /// « 312 ajouts » ; null : rien à montrer.
    private static FrameworkElement? BigStats(Share share)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 20, VerticalAlignment = VerticalAlignment.Center };
        StackPanel Part(params TextBlock[] pieces)
        {
            var part = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 5 };
            foreach (var piece in pieces)
            {
                piece.VerticalAlignment = VerticalAlignment.Bottom;
                part.Children.Add(piece);
            }
            return part;
        }
        TextBlock Big(string text)
        {
            return Label(text, 21, Text, semibold: true);       // maquette « Minimal » : Inter demi-gras
        }
        if (share.Rating is { } value)
            row.Children.Add(Part(Label("★", 20, MacLook.Red), Big(CommunityStats.Rating(value)), Label(Loc.T("sur 5"), 13, Secondary)));
        if (CommunityStats.Adds(share) is { } adds)
            row.Children.Add(Part(Big(adds.Number), Label(adds.Word, 13, Secondary)));
        return row.Children.Count == 0 ? null : row;
    }

    /// Bas d'une carte : « ★ 4,6 · Ajoutée 312 fois » sur sa ligne, puis « Voir » et l'action (à côté des boutons, il
    /// était coupé dans une carte étroite ; comme le Mac).
    private static FrameworkElement WithStats(FrameworkElement actions, Share share)
    {
        if (CommunityStats.Line(share) is not { } stats) return actions;
        var bottom = new StackPanel { Spacing = 10, Margin = actions.Margin };
        actions.Margin = new Thickness(0);
        bottom.Children.Add(SwissLabel(stats, 10.5, Text));
        bottom.Children.Add(actions);
        return bottom;
    }

    // ---------- Mode photos (CI) ----------

    private static readonly Guid DemoMe = Guid.Parse("6f1d2c1e-0000-4000-8000-000000000001");
    private static readonly Guid DemoLeo = Guid.Parse("6f1d2c1e-0000-4000-8000-000000000002");
    private static readonly Guid DemoSarah = Guid.Parse("6f1d2c1e-0000-4000-8000-000000000003");
    private static readonly Guid DemoNina = Guid.Parse("6f1d2c1e-0000-4000-8000-000000000004");

    private static List<Share> DemoShares() => new()
    {
        new(Guid.Parse("6f1d2c1e-0000-4000-8000-000000000101"), DemoLeo, CommunityRules.MacroKind, "Export Stems",
            "Toutes les pistes de la Playlist en WAV séparés, sur la sélection de temps.", "0.2.0", "2026-11-09T09:12:00+00:00", "leo.beats",
            312, 1435, 312),
        new(Guid.Parse("6f1d2c1e-0000-4000-8000-000000000102"), DemoSarah, CommunityRules.ProfileKind, "Raccourcis du Mixer",
            "", "0.2.0", "2026-11-08T21:40:00+00:00", "sarah.mix", 88, 370, 88),
        new(Guid.Parse("6f1d2c1e-0000-4000-8000-000000000103"), DemoMe, CommunityRules.MacroKind, "Armer la piste et lancer l'enregistrement",
            "Clique sur ta piste dans le Mixer, puis lance la macro : la piste est armée et REC démarre.", "0.2.0", "2026-11-02T18:02:11+00:00",
            "flshortcuts", 1),
        new(Guid.Parse("6f1d2c1e-0000-4000-8000-000000000104"), DemoNina, CommunityRules.MacroKind, "Choisir l'interface USB",
            "Ouvre Options › Audio settings et choisit ta carte son USB.", "0.2.0", "2026-10-30T10:00:00+00:00", "prod.nina", 1204, 5538, 1204),
    };

    /// Exemples de la vitrine (abonné à leo.beats et sarah.mix, deux nouveautés).
    private void DemoSocial()
    {
        _social = true;
        _tab = CommunityTab.MostAdded;
        _following = new HashSet<Guid> { DemoLeo, DemoSarah };
        _followedPreview = DemoShares().Where(s => _following.Contains(s.AuthorId)).ToList();
        _topPreview = DemoShares().Where(s => (s.AddCount ?? 0) > 0).OrderByDescending(s => s.AddCount).Take(3).ToList();
        _creators = new List<CommunityCreator>
        {
            new(DemoNina, "prod.nina", 1284), new(Guid.NewGuid(), "kbeats", 312), new(Guid.NewGuid(), "mixdown.ana", 96),
            new(Guid.NewGuid(), "loopfactory", 41), new(Guid.NewGuid(), "sam.808", 7),
        };
        _newFromFollowed = 2;
    }

    private void DemoTab()
    {
        _shares = _tab switch
        {
            CommunityTab.Following => DemoShares().Where(s => _following.Contains(s.AuthorId)).ToList(),
            CommunityTab.MostAdded => DemoShares().Where(s => (s.AddCount ?? 0) > 0).OrderByDescending(s => s.AddCount).ToList(),
            CommunityTab.Mine => DemoShares().Where(s => s.AuthorId == DemoMe).ToList(),
            _ => DemoShares(),
        };
    }

    /// Mode photos : un écran de la nouvelle Communauté (« abonnements », « personne », « note »).
    public void DemoScreen(string screen)
    {
        Demo(detail: false);
        switch (screen)
        {
            case "abonnements":
                Choose(CommunityTab.Following);
                break;
            case "personne":
                OpenPerson(DemoNina, "prod.nina");
                break;
            case "note":
                Open(_shares![0]);
                break;
        }
    }
}
