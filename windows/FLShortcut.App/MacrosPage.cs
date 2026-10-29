// La page Macros sur Windows, comme celle du Mac (maquette Macros.dc.html, 29/10 : « exactement la même interface sur
// win ») : dans la fenêtre principale, la liste des macros (Macro vide, Modèles…, puis chaque macro : icône, nom, nombre
// de blocs, badge, raccourci, Modifier…, options) ; une macro s'ouvre dans le créateur, qui prend toute la fenêtre :
// palette des blocs à gauche (par catégorie ; un clic ajoute le bloc sous la ligne choisie, on peut aussi le glisser
// à sa place), étapes au milieu (← rond, nom, raccourci, « Enregistrer » ; numéro, icône, phrase, interrupteur ; glisser
// une ligne pour la ranger), réglages du bloc choisi à droite (« Retirer ce bloc » en bas).
// La palette ne propose que les blocs faits pour Windows ; un bloc qui ne l'est pas encore (macro venue du Mac) le dit
// dans ses réglages et bloque la macro (son raccourci reste à FL). Toute modification est une copie remise au magasin
// (MacroLibraryStore.Update), enregistrée peu après par l'appli. Les champs de texte s'appliquent à la sortie du champ
// (jamais à chaque lettre : le créateur est redessiné après chaque changement).
using FLShortcut.Core;
using FLShortcut.Core.Macros;
using Microsoft.UI;
using Microsoft.UI.Input;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.ApplicationModel.DataTransfer;
using Windows.System;
using Windows.UI;
using Windows.UI.Core;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal sealed class MacrosPage
{
    private const double SidebarWidth = 252;
    private const double InspectorWidth = 270;
    private const double TitleBarHeight = 48;
    /// Glisser-déposer interne : un bloc de la palette, ou une ligne déplacée.
    private const string BlockDrag = "fls-block:";
    private const string StepDrag = "fls-step:";

    /// Blocs réglables ici (les autres se règlent sur le Mac pour l'instant).
    private static readonly HashSet<BlockType> Editable = new()
    {
        BlockType.Key, BlockType.Delay, BlockType.MenuLetters, BlockType.MenuKey, BlockType.WaitWindow,
        BlockType.WaitWindowClose, BlockType.FlAction, BlockType.OpenPage, BlockType.Organize, BlockType.Stop, BlockType.Comment,
        BlockType.Click, BlockType.MenuBar, BlockType.NameColor, BlockType.PageOption, BlockType.TrackMenu,
        BlockType.DropFile, BlockType.ChooseFile,
    };

    /// Couleur d'une catégorie de blocs (comme BlockCategory.tint du Mac).
    private static Color CategoryTint(BlockCategory c) => c switch
    {
        BlockCategory.Keyboard => Accent,
        BlockCategory.Mouse => Orange,
        BlockCategory.Windows => Green,
        BlockCategory.Fl => Purple,
        _ => Gray,
    };

    /// Bibliothèque d'exemple du mode photos (CI) : en mémoire, jamais écrite ; `Sample` s'ouvre dans le créateur.
    public static (MacroLibraryStore Store, Guid Sample) DemoStore()
    {
        var store = new MacroLibraryStore(new DemoStorage());
        foreach (var template in MacroTemplates.Gallery.Take(3)) store.Add(MacroDrafts.FromTemplate(template, store));
        var sample = store.Add(new MacroDoc
        {
            Name = Loc.T("Enregistrer et exporter"),
            Blocks = new List<Block>
            {
                new(new BlockBody.Key(new KeyRef(new MacKey(1, Command: true), "s"))),
                new(new BlockBody.WaitWindow(WindowKind.Dialog, 3000)),
                new(new BlockBody.MenuLetters("fe", EnterPolicy.IfNeeded)),
                new(new BlockBody.Delay(300), enabled: false),
                new(new BlockBody.FlAction("recon", ActionFallback.Key(new KeyRef(new MacKey(15), "r")))),
                new(new BlockBody.OpenPage(FlPage.Mixer)),
                new(new BlockBody.MenuBar(new[] { "File", "Export" })),
            },
        });
        return (store, sample.Id);
    }

    private readonly AppController _app;
    private readonly MacroLibraryStore _store;
    private readonly bool _demo;
    private readonly Window _window;
    private readonly Action _listChanged;
    private readonly Action<bool> _creatorShown;
    private readonly Action<string, Action?> _toast;
    private readonly IReadOnlyList<(BlockCategory Category, IReadOnlyList<PaletteEntry> Entries)> _palette;

    private readonly Grid _stepsPane = new();
    private readonly StackPanel _header = new() { Spacing = 10, Margin = new Thickness(22, TitleBarHeight, 22, 10) };
    private readonly ScrollViewer _stepsScroll = new() { HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
    private readonly ScrollViewer _inspector = new() { HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
    private Guid? _editing;
    private Guid? _selected;
    /// Touche en cours de capture : -1 = raccourci de la macro, sinon l'index du bloc « Touche ».
    private int? _capturing;
    private string? _notice;
    private bool _renderQueued;
    private bool _dirty;
    private Microsoft.UI.Dispatching.DispatcherQueueTimer? _savedTimer;

    /// Le créateur : posé par la fenêtre au-dessus de ses raccourcis, visible pendant qu'une macro est ouverte.
    public Grid Creator { get; } = new() { Padding = new Thickness(8), ColumnSpacing = 8, Visibility = Visibility.Collapsed };

    public bool Editing => _editing is not null;

    public MacrosPage(AppController app, MacroLibraryStore store, bool demo, Window window, Action listChanged,
                      Action<bool> creatorShown, Action<string, Action?> toast)
    {
        _app = app;
        _store = store;
        _demo = demo;
        _window = window;
        _listChanged = listChanged;
        _creatorShown = creatorShown;
        _toast = toast;
        _palette = MacroDrafts.CreatorPalette(MacroEffectsWindows.Unsupported, Editable.Contains);
        BuildCreator();
        _store.Changed += () =>
        {
            if (_editing is not null) RenderSoon();
            else _listChanged();
        };
    }

    // ---------- Ouvrir, revenir ----------

    public void Open(Guid macro)
    {
        StopCapture();
        _editing = macro;
        _selected = null;
        _notice = null;
        _dirty = false;
        Creator.Visibility = Visibility.Visible;
        _creatorShown(true);
        Render();
        _stepsScroll.ChangeView(null, 0, null, disableAnimation: true);
    }

    /// Mode photos : la macro d'exemple ouverte, son premier bloc choisi (ses réglages à droite).
    public void OpenDemo(Guid macro)
    {
        Open(macro);
        _selected = _store.Doc(macro)?.Blocks.FirstOrDefault()?.Id;
        Render();
    }

    public void Back()
    {
        if (_editing is null) return;
        StopCapture();
        if (!_demo && _dirty) _app.SaveMacrosNow();
        _editing = null;
        _selected = null;
        _notice = null;
        Creator.Visibility = Visibility.Collapsed;
        _creatorShown(false);
        _listChanged();
    }

    /// Une copie de la macro modifiée par `change`, remise au magasin.
    private void Change(MacroDoc doc, Action<MacroDoc> change)
    {
        var copy = MacroDrafts.Copy(doc);
        change(copy);
        if (_store.Update(copy) is null) return;
        _dirty = true;
        if (_demo) return;
        // L'appli enregistre 0,5 s après : « Enregistrer » redevient « Enregistrée » juste après.
        _savedTimer ??= CreateSavedTimer();
        _savedTimer.Stop();
        _savedTimer.Start();
    }

    private Microsoft.UI.Dispatching.DispatcherQueueTimer CreateSavedTimer()
    {
        var timer = _window.DispatcherQueue.CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(800);
        timer.IsRepeating = false;
        timer.Tick += (_, _) =>
        {
            _dirty = false;
            if (_editing is not null) RenderSoon();
        };
        return timer;
    }

    // ---------- Liste des macros (page de la fenêtre principale) ----------

    /// Le contenu de la page Macros : vide (« Aucune macro ») ou les actions et la carte « Mes macros ».
    public FrameworkElement ListContent()
    {
        if (_store.Macros.Count == 0) return EmptyList();
        var page = new StackPanel { Spacing = 20, Padding = new Thickness(26, 10, 26, 24) };
        var actions = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4 };
        actions.Children.Add(ActionButton("plus", Loc.T("Macro vide"), NewMacro));
        actions.Children.Add(ActionButton("square.grid.2x2", Loc.T("Modèles…"), ShowTemplates));
        var actionsPlate = Plate(actions, 14);
        actionsPlate.Padding = new Thickness(4);
        page.Children.Add(actionsPlate);
        page.Children.Add(MainShell.TitledCard(Loc.T("Mes macros"), _store.Macros.Select(MacroRow).ToList()));
        return page;
    }

    private FrameworkElement EmptyList()
    {
        var stack = new StackPanel { Spacing = 12, HorizontalAlignment = HorizontalAlignment.Center, Padding = new Thickness(24, 90, 24, 24) };
        var tile = Tile("macros", Purple, 52);
        tile.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Children.Add(tile);
        var title = Label(Loc.T("Aucune macro"), 20, Text, bold: true);
        title.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Children.Add(title);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 4, 0, 0) };
        buttons.Children.Add(Primary(Loc.T("Macro vide"), NewMacro));
        buttons.Children.Add(Soft(Loc.T("Partir d'un modèle…"), ShowTemplates));
        stack.Children.Add(buttons);
        return stack;
    }

    /// Bouton de la plaque d'actions : icône et texte ; au survol, plein de violet.
    private static Button ActionButton(string icon, string text, Action click)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 7 };
        var glyph = Icon(icon, 13, Text);
        glyph.VerticalAlignment = VerticalAlignment.Center;
        row.Children.Add(glyph);
        row.Children.Add(Label(text, 13));
        var button = Option(row, Purple, 10, click, minHeight: 32, padding: new Thickness(12, 0, 14, 0));
        button.HorizontalAlignment = HorizontalAlignment.Left;
        AutomationProperties.SetName(button, text);
        return button;
    }

    private void NewMacro() => Open(_store.Add(MacroDrafts.Empty(_store)).Id);

    /// Une macro : icône, nom et résumé (« 3 blocs · Touche, Attendre… »), badges, raccourci, « Modifier… », options.
    /// Un clic sur la ligne l'ouvre ; au survol, toute la ligne est violette (comme le Mac).
    private FrameworkElement MacroRow(MacroDoc doc)
    {
        var shortcut = _demo ? null : _app.MacroShortcut(doc.Id);
        var grid = new Grid { ColumnSpacing = 10 };
        foreach (var width in new[] { GridLength.Auto, new GridLength(1, GridUnitType.Star), GridLength.Auto, GridLength.Auto, GridLength.Auto, GridLength.Auto })
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = width });
        var tile = Tile("macros", Purple, 26);
        grid.Children.Add(tile);

        var text = new StackPanel { Spacing = 1, VerticalAlignment = VerticalAlignment.Center };
        var name = Label(DisplayText.Safe(doc.Name, MacroValidation.MaxNameLength), 13);
        name.TextWrapping = TextWrapping.NoWrap;
        name.TextTrimming = TextTrimming.CharacterEllipsis;
        text.Children.Add(name);
        var caption = Label(Caption(doc), 11, Secondary);
        caption.TextWrapping = TextWrapping.NoWrap;
        caption.TextTrimming = TextTrimming.CharacterEllipsis;
        text.Children.Add(caption);
        Grid.SetColumn(text, 1);
        grid.Children.Add(text);

        var badges = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4, VerticalAlignment = VerticalAlignment.Center };
        if (Issue(doc) is { } problem) badges.Children.Add(Badge(Loc.T("À corriger"), Red, problem));
        if (shortcut is { Enabled: false }) badges.Children.Add(Badge(Loc.T("Désactivée"), Secondary, Loc.T("Le raccourci de cette macro est désactivé.")));
        Grid.SetColumn(badges, 2);
        grid.Children.Add(badges);

        FrameworkElement keys = shortcut?.Trigger is { } trigger ? (FrameworkElement)Keys(trigger) : Label(Loc.T("Sans raccourci"), 12, Secondary);
        keys.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(keys, 3);
        grid.Children.Add(keys);

        var edit = new Button { Style = PlainButton, Content = Label(Loc.T("Modifier…"), 12, Link), Padding = new Thickness(4, 2, 4, 2) };
        edit.Click += (_, _) => Open(doc.Id);
        Grid.SetColumn(edit, 4);
        grid.Children.Add(edit);

        var more = new Button
        {
            Style = PlainButton, Width = 26, Height = 26, CornerRadius = new CornerRadius(13),
            HorizontalContentAlignment = HorizontalAlignment.Center, Content = Icon("ellipsis", 14, Secondary),
            Flyout = MacroOptions(doc, shortcut),
        };
        ToolTipService.SetToolTip(more, Loc.T("Options de la macro"));
        AutomationProperties.SetName(more, Loc.T("Options de la macro"));
        Grid.SetColumn(more, 5);
        grid.Children.Add(more);

        var row = Option(grid, Purple, 10, () => Open(doc.Id), minHeight: 46, padding: new Thickness(10, 4, 8, 4),
                         hover: on => SetTileHover(tile, "macros", Purple, on));
        AutomationProperties.SetName(row, DisplayText.Safe(doc.Name, MacroValidation.MaxNameLength));
        return row;
    }

    private static string Caption(MacroDoc doc)
    {
        var count = MacroValidation.Count(doc.Blocks);
        var blocks = count == 1 ? Loc.T("1 bloc") : Loc.F("%lld blocs", count);
        var first = doc.Blocks.Where(b => b.Enabled && b.Body is not BlockBody.Comment).Take(3).Select(b => BlockRegistry.Label(b.Body)).ToList();
        return first.Count == 0 ? blocks : blocks + " · " + string.Join(", ", first);
    }

    private static Border Badge(string text, Color tint, string help)
    {
        var badge = new Border
        {
            Padding = new Thickness(7, 1, 7, 2),
            CornerRadius = new CornerRadius(9),
            Background = Brush(WithOpacity(tint, 0.16)),
            VerticalAlignment = VerticalAlignment.Center,
            Child = Label(text, 10.5, tint, semibold: true),
        };
        ToolTipService.SetToolTip(badge, help);
        return badge;
    }

    private MenuFlyout MacroOptions(MacroDoc doc, Shortcut? shortcut)
    {
        var menu = new MenuFlyout();
        void Add(string text, Action click)
        {
            var item = new MenuFlyoutItem { Text = text };
            item.Click += (_, _) => click();
            menu.Items.Add(item);
        }
        Add(Loc.T("Modifier…"), () => Open(doc.Id));
        Add(Loc.T("Dupliquer"), () => Duplicate(doc));
        if (shortcut is { } s)
        {
            menu.Items.Add(new MenuFlyoutSeparator());
            Add(s.Enabled ? Loc.T("Désactiver le raccourci") : Loc.T("Activer le raccourci"), () => _app.Upsert(s with { Enabled = !s.Enabled }));
        }
        menu.Items.Add(new MenuFlyoutSeparator());
        Add(Loc.T("Supprimer"), () => Delete(doc));
        return menu;
    }

    private void Duplicate(MacroDoc doc)
    {
        var copy = MacroDrafts.Copy(doc);
        copy.Id = Guid.NewGuid();
        copy.Name = _store.UniqueName(doc.Name + Loc.T(" (copie)"));
        copy.Blocks = MacroTemplates.FreshIds(copy.Blocks);
        var added = _store.Add(copy);
        _toast(Loc.F("« %@ » ajoutée, sans raccourci", DisplayText.Safe(added.Name, 40)), () => _store.Remove(added.Id));
    }

    /// Supprime la macro et son raccourci, « Annuler » dans la notification (comme le Mac).
    private void Delete(MacroDoc doc)
    {
        var name = DisplayText.Safe(doc.Name, 40);
        if (_demo)
        {
            _store.Remove(doc.Id);
            return;
        }
        var undo = _app.DeleteMacro(doc.Id);
        _toast(Loc.F("« %@ » supprimée", name), undo);
    }

    /// « Modèles… » : chaque modèle (icône, nom, résumé) et « Utiliser » (comme MacroTemplatesSheet du Mac).
    private async void ShowTemplates()
    {
        if (_window.Content?.XamlRoot is not { } root) return;
        var list = new StackPanel { Spacing = 8 };
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Style = MainShell.DialogStyle(),
            RequestedTheme = ElementTheme.Dark,
            Background = Brush(Rgb(0x1E, 0x1E, 0x21)),
            BorderBrush = Brush(White(0.16)),
            CloseButtonText = Loc.T("Annuler"),
        };
        var title = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        title.Children.Add(Tile("square.grid.2x2", Purple, 34));
        var heading = Label(Loc.T("Modèles de macros"), 17, Text, bold: true);
        heading.VerticalAlignment = VerticalAlignment.Center;
        title.Children.Add(heading);
        dialog.Title = title;
        foreach (var template in MacroTemplates.Gallery)
        {
            var t = template;
            var row = new Grid { ColumnSpacing = 12 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var tile = Tile(t.Symbol, Purple, 28);
            tile.VerticalAlignment = VerticalAlignment.Top;
            row.Children.Add(tile);
            var text = new StackPanel { Spacing = 2 };
            text.Children.Add(Label(t.Title, 13, Text, semibold: true));
            text.Children.Add(Paragraph(t.Summary, 11));
            Grid.SetColumn(text, 1);
            row.Children.Add(text);
            var use = Soft(Loc.T("Utiliser"), () =>
            {
                dialog.Hide();
                Open(_store.Add(MacroDrafts.FromTemplate(t, _store)).Id);
            });
            use.VerticalAlignment = VerticalAlignment.Center;
            Grid.SetColumn(use, 2);
            row.Children.Add(use);
            var plate = Plate(row, 12);
            plate.Padding = new Thickness(12, 10, 12, 10);
            list.Children.Add(plate);
        }
        dialog.Content = new ScrollViewer { Content = list, MaxHeight = 460, Padding = new Thickness(0, 0, 10, 0) };
        await dialog.ShowAsync();
    }

    /// Problème de la macro sous Windows (compilée avec les règles de Windows), sinon null.
    private string? Issue(MacroDoc doc) => _demo
        ? MacroProgram.Compile(doc, new ValidationContext { PlatformProblem = MacroEffectsWindows.Unsupported }).Problem
        : _app.MacroIssue(doc.Id);

    // ---------- Créateur ----------

    private void BuildCreator()
    {
        Creator.Background = Brush(WindowColor);
        Creator.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(SidebarWidth) });
        Creator.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MinWidth = 280 });
        Creator.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(InspectorWidth) });

        var palette = Plate(new ScrollViewer
        {
            Content = PaletteView(),
            VerticalScrollBarVisibility = ScrollBarVisibility.Hidden,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        }, 19, 0.10, 0.04, 0.16);
        palette.Padding = new Thickness(10, 14, 10, 16);
        Creator.Children.Add(palette);

        _stepsPane.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        _stepsPane.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        _stepsPane.Children.Add(_header);
        Grid.SetRow(_stepsScroll, 1);
        _stepsPane.Children.Add(_stepsScroll);
        Grid.SetColumn(_stepsPane, 1);
        Creator.Children.Add(_stepsPane);

        var inspector = Plate(_inspector, 19, 0.10, 0.04, 0.16);
        Grid.SetColumn(inspector, 2);
        Creator.Children.Add(inspector);
    }

    /// La palette : par catégorie, sous son titre gris ; un clic ajoute le bloc, on peut aussi le glisser.
    private StackPanel PaletteView()
    {
        var stack = new StackPanel { Spacing = 12 };
        foreach (var (category, entries) in _palette)
        {
            var group = new StackPanel { Spacing = 1 };
            var title = Label(category.Label(), 11, Secondary, semibold: true);
            title.Margin = new Thickness(10, 0, 10, 4);
            AutomationProperties.SetHeadingLevel(title, Microsoft.UI.Xaml.Automation.Peers.AutomationHeadingLevel.Level2);
            group.Children.Add(title);
            foreach (var entry in entries) group.Children.Add(PaletteRow(entry));
            stack.Children.Add(group);
        }
        return stack;
    }

    /// Une ligne de la palette : pas un bouton (un bouton garde l'appui de la souris et le glisser ne démarrerait
    /// pas, comme sur le Mac) ; au survol, pleine de la couleur de sa catégorie.
    private Border PaletteRow(PaletteEntry entry)
    {
        var tint = CategoryTint(entry.Category);
        var tile = Tile(entry.Symbol, tint, 22);
        var label = Label(entry.Label, 13);
        label.TextWrapping = TextWrapping.NoWrap;
        label.TextTrimming = TextTrimming.CharacterEllipsis;
        label.VerticalAlignment = VerticalAlignment.Center;
        var content = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        content.Children.Add(tile);
        content.Children.Add(label);
        var row = new Border
        {
            Child = content,
            MinHeight = 32,
            Padding = new Thickness(10, 5, 10, 5),
            CornerRadius = new CornerRadius(8),
            Background = Brush(Colors.Transparent),
            CanDrag = true,
        };
        void Hover(bool on)
        {
            row.Background = Brush(on ? tint : Colors.Transparent);
            label.Foreground = Brush(on ? Colors.White : Text);
            SetTileHover(tile, entry.Symbol, tint, on);
        }
        row.PointerEntered += (_, _) => Hover(true);
        row.PointerExited += (_, _) => Hover(false);
        row.PointerCanceled += (_, _) => Hover(false);
        row.Tapped += (_, _) => Insert(entry, before: null);
        row.DragStarting += (_, e) =>
        {
            e.Data.SetText(BlockDrag + entry.Type);
            e.Data.RequestedOperation = DataPackageOperation.Copy;
        };
        ToolTipService.SetToolTip(row, entry.Help);
        AutomationProperties.SetName(row, entry.Label);
        return row;
    }

    /// Bloc de la palette ajouté sous la ligne choisie (sinon à la fin), ou à la place `before` d'un dépôt ; il est choisi.
    private void Insert(PaletteEntry entry, int? before)
    {
        if (_editing is not { } id || _store.Doc(id) is not { } doc) return;
        var block = new Block(entry.Make());
        var at = before ?? (SelectedIndex(doc) is { } i ? i + 1 : doc.Blocks.Count);
        at = Math.Clamp(at, 0, doc.Blocks.Count);
        _selected = block.Id;
        Change(doc, d => d.Blocks.Insert(at, block));
    }

    private int? SelectedIndex(MacroDoc doc)
    {
        var i = doc.Blocks.FindIndex(b => b.Id == _selected);
        return i >= 0 ? i : null;
    }

    /// Redessin juste après l'évènement en cours (jamais pendant celui d'un contrôle qu'il retirerait), une fois.
    private void RenderSoon()
    {
        if (_renderQueued) return;
        _renderQueued = true;
        _window.DispatcherQueue.TryEnqueue(() =>
        {
            _renderQueued = false;
            Render();
        });
    }

    private void Render()
    {
        if (_editing is not { } id) return;
        if (_store.Doc(id) is not { } doc)
        {
            Back();
            return;
        }
        if (SelectedIndex(doc) is null) _selected = null;
        RenderHeader(doc);
        _stepsScroll.Content = Steps(doc);
        _inspector.Content = Inspector(doc);
    }

    /// ← rond, le nom en grand (champ), les touches du raccourci (clic : en taper d'autres), « Enregistrer » en bleu ;
    /// dessous, seulement ce qui demande d'agir (problème, raccourci refusé).
    private void RenderHeader(MacroDoc doc)
    {
        _header.Children.Clear();
        var line = new Grid { ColumnSpacing = 10, MinHeight = 52 };
        line.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        line.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        line.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        line.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        line.Children.Add(BackButton());
        var name = NameField(doc);
        Grid.SetColumn(name, 1);
        line.Children.Add(name);
        var trigger = ShortcutEditor(doc);
        Grid.SetColumn(trigger, 2);
        line.Children.Add(trigger);
        var save = SaveButton();
        Grid.SetColumn(save, 3);
        line.Children.Add(save);
        _header.Children.Add(line);
        foreach (var text in new[] { _notice, Issue(doc) })
            if (text is not null) _header.Children.Add(Warning(text));
    }

    private static FrameworkElement Warning(string text)
    {
        var row = new Grid { ColumnSpacing = 8 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var icon = Icon("warning", 13, Orange, WindowColor);
        icon.VerticalAlignment = VerticalAlignment.Top;
        icon.Margin = new Thickness(0, 2, 0, 0);
        row.Children.Add(icon);
        var label = Paragraph(text, 12);
        Grid.SetColumn(label, 1);
        row.Children.Add(label);
        return row;
    }

    private Button BackButton()
    {
        var button = new Button
        {
            Style = PlainButton,
            Width = 36,
            Height = 36,
            CornerRadius = new CornerRadius(18),
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Content = Icon("back", 14, Text),
            Background = Brush(White(0.10)),
            BorderBrush = Brush(White(0.16)),
            BorderThickness = new Thickness(1),
        };
        button.PointerEntered += (_, _) => button.Background = Brush(Accent);
        button.PointerExited += (_, _) => button.Background = Brush(White(0.10));
        button.Click += (_, _) => Back();
        ToolTipService.SetToolTip(button, Loc.T("Retour"));
        AutomationProperties.SetName(button, Loc.T("Retour"));
        return button;
    }

    /// Le nom de la macro, en grand, sans cadre : appliqué à la sortie du champ ou à Entrée.
    private TextBox NameField(MacroDoc doc)
    {
        var box = new TextBox
        {
            Text = doc.Name,
            MaxLength = MacroValidation.MaxNameLength,
            FontSize = 22,
            FontWeight = FontWeights.Bold,
            BorderThickness = new Thickness(0),
            Background = Brush(Colors.Transparent),
            VerticalAlignment = VerticalAlignment.Center,
            Padding = new Thickness(2, 4, 2, 4),
            PlaceholderText = Loc.T("Nom de la macro"),
        };
        foreach (var key in new[] { "TextControlBackground", "TextControlBackgroundPointerOver", "TextControlBackgroundFocused",
                                    "TextControlBorderBrush", "TextControlBorderBrushPointerOver", "TextControlBorderBrushFocused" })
            box.Resources[key] = Brush(Colors.Transparent);
        foreach (var key in new[] { "TextControlForeground", "TextControlForegroundFocused", "TextControlForegroundPointerOver" })
            box.Resources[key] = Brush(Text);
        AutomationProperties.SetName(box, Loc.T("Nom de la macro"));
        var committed = doc.Name;
        void Commit()
        {
            if (box.Text == committed) return;
            committed = box.Text;
            if (MacroDrafts.CleanName(box.Text, doc, _store) is { } clean) Change(doc, d => d.Name = clean);
            else
            {
                _notice = Loc.T("Ce nom est vide ou déjà pris.");
                RenderSoon();
            }
        }
        box.LostFocus += (_, _) => Commit();
        box.KeyDown += (_, e) => { if (e.Key == VirtualKey.Enter) Commit(); };
        return box;
    }

    /// « Enregistrer » en bleu tant qu'un changement attend (sinon fait tout seul dans un instant), puis « Enregistrée ».
    private Button SaveButton()
    {
        if (_dirty)
        {
            var save = Primary(Loc.T("Enregistrer"), () =>
            {
                if (!_demo) _app.SaveMacrosNow();
                _dirty = false;
                RenderSoon();
            });
            save.VerticalAlignment = VerticalAlignment.Center;
            return save;
        }
        var saved = new Button
        {
            Style = PlainButton,
            IsHitTestVisible = false,
            IsTabStop = false,
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalContentAlignment = HorizontalAlignment.Center,
            Content = Label(Loc.T("Enregistrée"), 13.5, Secondary, semibold: true),
            CornerRadius = new CornerRadius(17),
            MinHeight = 34,
            Padding = new Thickness(20, 0, 20, 0),
            Background = Brush(White(0.08)),
        };
        AutomationProperties.SetName(saved, Loc.T("Enregistrée"));
        return saved;
    }

    private FrameworkElement ShortcutEditor(MacroDoc doc)
    {
        var shortcut = _demo ? null : _app.MacroShortcut(doc.Id);
        var capture = CaptureButton(-1, shortcut?.Trigger, Loc.T("Choisir un raccourci…"), combo =>
        {
            if (_demo) return;
            if (_app.SetMacroShortcut(doc.Id, combo) is { } why) _notice = Loc.F("Ce raccourci ne peut pas lancer la macro : %@", why);
            else _notice = null;
            RenderSoon();
        });
        if (shortcut is null) return capture;
        var remove = new Button
        {
            Style = PlainButton, Width = 26, Height = 26, CornerRadius = new CornerRadius(13),
            HorizontalContentAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            Content = Icon("trash", 12, Secondary),
        };
        remove.Click += (_, _) =>
        {
            _app.RemoveMacroShortcut(doc.Id);
            RenderSoon();
        };
        ToolTipService.SetToolTip(remove, Loc.T("Retirer le raccourci"));
        AutomationProperties.SetName(remove, Loc.T("Retirer le raccourci"));
        var line = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4, VerticalAlignment = VerticalAlignment.Center };
        line.Children.Add(capture);
        line.Children.Add(remove);
        return line;
    }

    /// Champ d'une combinaison (raccourci de la macro ou bloc « Touche ») : ses touches en petites plaques ; un clic,
    /// puis les touches appuyées la remplacent (Échap seul annule).
    private Button CaptureButton(int slot, KeyCombo? combo, string prompt, Action<KeyCombo> done)
    {
        var recording = _capturing == slot;
        UIElement content = recording
            ? Label(Loc.T("Appuie sur tes touches… (Échap pour annuler)"), 12, Text)
            : combo is { } c ? (UIElement)Keys(c) : Label(prompt, 12, Link);
        var button = new Button
        {
            Style = PlainButton,
            Content = content,
            MinHeight = 32,
            Padding = new Thickness(8, 4, 8, 4),
            CornerRadius = new CornerRadius(9),
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center,
            Background = Brush(White(0.08)),
            BorderBrush = Brush(recording ? Accent : White(0.16)),
            BorderThickness = new Thickness(recording ? 2 : 1),
        };
        AutomationProperties.SetName(button, combo?.ToString() ?? prompt);
        if (!recording)
        {
            button.PointerEntered += (_, _) => button.Background = Brush(White(0.16));
            button.PointerExited += (_, _) => button.Background = Brush(White(0.08));
            button.Click += (_, _) =>
            {
                StopCapture();
                _capturing = slot;
                if (!_demo) _app.SetRecording(true);
                RenderSoon();
            };
            return button;
        }
        // Seul le bouton dessiné pendant la capture écoute le clavier et la perte du focus (l'ancien bouton, retiré
        // au redessin, perdrait le focus et annulerait la capture tout de suite).
        button.PreviewKeyDown += (_, e) =>
        {
            if (_capturing != slot) return;
            e.Handled = true;
            var vk = (ushort)e.Key;
            if (Vk.IsModifier(vk)) return;
            var pressed = new KeyCombo(vk, IsDown(VirtualKey.Control), IsDown(VirtualKey.Menu), IsDown(VirtualKey.Shift),
                IsDown(VirtualKey.LeftWindows) || IsDown(VirtualKey.RightWindows));
            StopCapture();
            if (e.Key == VirtualKey.Escape && !pressed.HasModifiers) RenderSoon();
            else done(pressed);
        };
        button.LostFocus += (_, _) =>
        {
            if (_capturing != slot) return;
            StopCapture();
            RenderSoon();
        };
        _window.DispatcherQueue.TryEnqueue(() => button.Focus(FocusState.Programmatic));
        return button;
    }

    private void StopCapture()
    {
        if (_capturing is null) return;
        _capturing = null;
        if (!_demo) _app.SetRecording(false);
    }

    private static bool IsDown(VirtualKey key) =>
        InputKeyboardSource.GetKeyStateForCurrentThread(key).HasFlag(CoreVirtualKeyStates.Down);

    // ---------- Étapes ----------

    /// Les étapes dans une plaque (un trait fin entre deux lignes), puis la zone en pointillés où lâcher un bloc.
    private StackPanel Steps(MacroDoc doc)
    {
        var page = new StackPanel { Spacing = 12, Padding = new Thickness(22, 4, 22, 24) };
        if (doc.Blocks.Count > 0)
        {
            var list = new StackPanel();
            for (var i = 0; i < doc.Blocks.Count; i++) list.Children.Add(StepRow(doc, i));
            var plate = Plate(list, 14);
            plate.Padding = new Thickness(2);
            page.Children.Add(plate);
        }
        page.Children.Add(DropZone(doc));
        return page;
    }

    /// Une ligne : numéro, icône de couleur, la phrase (nom du bloc et sa valeur en pastille), l'interrupteur.
    /// Un clic la choisit (réglages à droite) ; clic droit : activer / désactiver, supprimer ; on la glisse pour la ranger.
    private FrameworkElement StepRow(MacroDoc doc, int index)
    {
        var block = doc.Blocks[index];
        var body = block.Body;
        var spec = body.Type is { } type ? BlockRegistry.Spec(type) : null;
        var tint = spec is null ? Gray : CategoryTint(spec.Category);
        var symbol = spec?.Symbol ?? "warning";
        var selected = block.Id == _selected;

        var grid = new Grid { ColumnSpacing = 8 };
        foreach (var width in new[] { GridLength.Auto, GridLength.Auto, new GridLength(1, GridUnitType.Star), GridLength.Auto, GridLength.Auto })
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = width });
        var number = Label((index + 1).ToString(System.Globalization.CultureInfo.InvariantCulture), 11, selected ? White(0.8) : Secondary);
        number.MinWidth = 24;
        number.TextAlignment = TextAlignment.Right;
        number.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(number);
        var tile = Tile(symbol, tint, 24);
        Grid.SetColumn(tile, 1);
        grid.Children.Add(tile);

        var sentence = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
        if (body is BlockBody.Comment comment)
        {
            var note = Label(comment.Text, 13, selected ? Colors.White : Secondary);
            note.FontStyle = Windows.UI.Text.FontStyle.Italic;
            note.TextTrimming = TextTrimming.CharacterEllipsis;
            sentence.Children.Add(note);
        }
        else
        {
            var verb = Label(BlockRegistry.Label(body), 14, selected ? Colors.White : Text);
            verb.TextWrapping = TextWrapping.NoWrap;
            verb.VerticalAlignment = VerticalAlignment.Center;
            sentence.Children.Add(verb);
            if (spec?.Summary(body) is { Length: > 0 } summary) sentence.Children.Add(ValuePill(summary));
        }
        Grid.SetColumn(sentence, 2);
        grid.Children.Add(sentence);
        if (MacroEffectsWindows.Unsupported(body) is { } missing)
        {
            var warn = Icon("warning", 13, Orange, WindowColor);
            ToolTipService.SetToolTip(warn, missing);
            warn.IsHitTestVisible = true;
            Grid.SetColumn(warn, 3);
            grid.Children.Add(warn);
        }
        var toggle = Switch(block.Enabled, on => Change(doc, d => d.Blocks[index].Enabled = on));
        Grid.SetColumn(toggle, 4);
        grid.Children.Add(toggle);
        foreach (var child in new UIElement[] { number, tile, sentence }) child.Opacity = block.Enabled ? 1 : 0.45;

        // Trait d'insertion pendant un dépôt sur cette ligne.
        var mark = new Rectangle { Height = 2, Fill = Brush(Accent), VerticalAlignment = VerticalAlignment.Top, Visibility = Visibility.Collapsed,
                                   Margin = new Thickness(8, 0, 8, 0), IsHitTestVisible = false };
        var row = new Border
        {
            Child = grid,
            MinHeight = 40,
            Padding = new Thickness(6, 4, 10, 4),
            CornerRadius = new CornerRadius(11),
            Background = Brush(selected ? Accent : Colors.Transparent),
            CanDrag = true,
            AllowDrop = true,
        };
        if (!selected)
        {
            void Hover(bool on)
            {
                row.Background = Brush(on ? tint : Colors.Transparent);
                SetTileHover(tile, symbol, tint, on);
            }
            row.PointerEntered += (_, _) => Hover(true);
            row.PointerExited += (_, _) => Hover(false);
            row.PointerCanceled += (_, _) => Hover(false);
        }
        row.Tapped += (_, _) =>
        {
            if (_selected == block.Id) return;
            _selected = block.Id;
            RenderSoon();
        };
        var menu = new MenuFlyout();
        var enable = new MenuFlyoutItem { Text = block.Enabled ? Loc.T("Désactiver") : Loc.T("Activer") };
        enable.Click += (_, _) => Change(doc, d => d.Blocks[index].Enabled = !block.Enabled);
        menu.Items.Add(enable);
        menu.Items.Add(new MenuFlyoutSeparator());
        var delete = new MenuFlyoutItem { Text = Loc.T("Supprimer") };
        delete.Click += (_, _) => Remove(doc, index);
        menu.Items.Add(delete);
        row.ContextFlyout = menu;
        row.DragStarting += (_, e) =>
        {
            e.Data.SetText(StepDrag + index.ToString(System.Globalization.CultureInfo.InvariantCulture));
            e.Data.RequestedOperation = DataPackageOperation.Copy;
        };
        AcceptDrops(row, index, mark);
        AutomationProperties.SetName(row, $"{index + 1}. {BlockRegistry.Label(body)}");

        var cell = new Grid();
        cell.Children.Add(row);
        cell.Children.Add(mark);
        if (index > 0)
            cell.Children.Add(new Rectangle { Height = 1, Fill = Brush(White(0.06)), VerticalAlignment = VerticalAlignment.Top,
                                              Margin = new Thickness(10, 0, 10, 0), IsHitTestVisible = false });
        return cell;
    }

    private static Border ValuePill(string text)
    {
        var label = Label(text, 13, Text, semibold: true);
        label.TextWrapping = TextWrapping.NoWrap;
        label.TextTrimming = TextTrimming.CharacterEllipsis;
        return new Border
        {
            Child = label,
            Padding = new Thickness(9, 3, 9, 3),
            CornerRadius = new CornerRadius(7),
            Background = Brush(White(0.12)),
            BorderBrush = Brush(White(0.2)),
            BorderThickness = new Thickness(1),
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    /// Interrupteur (comme celui du Mac) : bleu allumé, gris éteint.
    private static Button Switch(bool on, Action<bool> set)
    {
        var knob = new Ellipse { Width = 14, Height = 14, Fill = Brush(Colors.White), HorizontalAlignment = on ? HorizontalAlignment.Right : HorizontalAlignment.Left,
                                 Margin = new Thickness(2, 0, 2, 0) };
        var track = new Grid { Width = 32, Height = 18 };
        track.Children.Add(new Border { CornerRadius = new CornerRadius(9), Background = Brush(on ? Accent : White(0.22)),
                                        BorderBrush = Brush(White(on ? 0.3 : 0.12)), BorderThickness = new Thickness(1) });
        track.Children.Add(knob);
        var button = new Button { Style = PlainButton, Content = track, CornerRadius = new CornerRadius(9), VerticalAlignment = VerticalAlignment.Center };
        var help = on ? Loc.T("Bloc actif : coupe-le pour le sauter sans le supprimer") : Loc.T("Bloc sauté : rallume-le pour le réactiver");
        ToolTipService.SetToolTip(button, help);
        AutomationProperties.SetName(button, help);
        button.Click += (_, _) => set(!on);
        button.Tapped += (_, e) => e.Handled = true;          // la ligne n'est pas choisie pour autant
        return button;
    }

    /// Zone en pointillés sous les étapes : un bloc de la palette lâché ici va à la fin.
    private FrameworkElement DropZone(MacroDoc doc)
    {
        var zone = new Grid { MinHeight = 52, AllowDrop = true, Background = Brush(Colors.Transparent) };
        var border = new Rectangle
        {
            RadiusX = 14,
            RadiusY = 14,
            Stroke = Brush(White(0.25)),
            StrokeThickness = 1,
            StrokeDashArray = new DoubleCollection { 5, 4 },
        };
        zone.Children.Add(border);
        var text = Paragraph(Loc.T("Glisse un bloc ici, ou clique-le dans la liste à gauche"), 13);
        text.TextAlignment = TextAlignment.Center;
        text.HorizontalAlignment = HorizontalAlignment.Center;
        text.VerticalAlignment = VerticalAlignment.Center;
        text.Margin = new Thickness(16, 10, 16, 10);
        zone.Children.Add(text);
        zone.DragEnter += (_, _) => border.Stroke = Brush(Accent);
        zone.DragLeave += (_, _) => border.Stroke = Brush(White(0.25));
        AcceptDrops(zone, doc.Blocks.Count, null);
        return zone;
    }

    /// Dépôt d'un bloc de la palette ou d'une ligne glissée, à la place `before`.
    private void AcceptDrops(UIElement target, int before, Rectangle? mark)
    {
        target.DragOver += (_, e) =>
        {
            e.AcceptedOperation = e.DataView.Contains(StandardDataFormats.Text) ? DataPackageOperation.Copy : DataPackageOperation.None;
            e.DragUIOverride.IsCaptionVisible = false;
            e.DragUIOverride.IsGlyphVisible = false;
        };
        if (mark is not null)
        {
            target.DragEnter += (_, _) => mark.Visibility = Visibility.Visible;
            target.DragLeave += (_, _) => mark.Visibility = Visibility.Collapsed;
        }
        target.Drop += async (_, e) =>
        {
            if (mark is not null) mark.Visibility = Visibility.Collapsed;
            if (!e.DataView.Contains(StandardDataFormats.Text)) return;
            var deferral = e.GetDeferral();
            string text;
            try { text = await e.DataView.GetTextAsync(); }
            catch (Exception) { return; }
            finally { deferral.Complete(); }
            Dropped(text, before);
        };
    }

    private void Dropped(string text, int before)
    {
        if (_editing is not { } id || _store.Doc(id) is not { } doc) return;
        if (text.StartsWith(BlockDrag, StringComparison.Ordinal))
        {
            var raw = text[BlockDrag.Length..];
            var entry = _palette.SelectMany(p => p.Entries).FirstOrDefault(e => e.Type.ToString() == raw);
            if (entry is not null) Insert(entry, before);
            return;
        }
        if (!text.StartsWith(StepDrag, StringComparison.Ordinal)
            || !int.TryParse(text[StepDrag.Length..], System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var from)
            || from < 0 || from >= doc.Blocks.Count) return;
        var to = before > from ? before - 1 : before;
        if (to == from) return;
        _selected = doc.Blocks[from].Id;
        Change(doc, d =>
        {
            var moved = d.Blocks[from];
            d.Blocks.RemoveAt(from);
            d.Blocks.Insert(Math.Clamp(to, 0, d.Blocks.Count), moved);
        });
    }

    private void Remove(MacroDoc doc, int index)
    {
        if (index < 0 || index >= doc.Blocks.Count) return;
        if (doc.Blocks[index].Id == _selected) _selected = null;
        Change(doc, d => d.Blocks.RemoveAt(index));
    }

    // ---------- Réglages du bloc choisi ----------

    private FrameworkElement Inspector(MacroDoc doc)
    {
        if (SelectedIndex(doc) is not { } index) return Hint();
        var block = doc.Blocks[index];
        var body = block.Body;
        var spec = body.Type is { } type ? BlockRegistry.Spec(type) : null;
        var stack = new StackPanel { Spacing = 14, Padding = new Thickness(16, TitleBarHeight, 16, 18) };

        var header = new Grid { ColumnSpacing = 10 };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var tile = Tile(spec?.Symbol ?? "warning", spec is null ? Gray : CategoryTint(spec.Category), 28);
        tile.VerticalAlignment = VerticalAlignment.Top;
        header.Children.Add(tile);
        var titles = new StackPanel { Spacing = 3 };
        titles.Children.Add(Label(spec?.Label ?? Loc.T("Bloc inconnu"), 15, Text, semibold: true));
        if (spec?.Help is { Length: > 0 } help) titles.Children.Add(Paragraph(help, 11));
        Grid.SetColumn(titles, 1);
        header.Children.Add(titles);
        stack.Children.Add(header);

        if (spec is null)
            stack.Children.Add(Paragraph(Loc.T("Bloc d'une version plus récente : mets l'app à jour, ou supprime-le."), 12, Text));
        else if (MacroEffectsWindows.Unsupported(body) is { } missing)
            stack.Children.Add(Warning(missing));
        else if (body.Type is { } t && Editable.Contains(t) && body is not BlockBody.Organize)
        {
            void Set(BlockBody next) => Change(doc, d => d.Blocks[index].Body = next);
            var settings = new StackPanel { Spacing = 12 };
            foreach (var editor in Editors(doc, body, index, Set)) settings.Children.Add(editor);
            if (settings.Children.Count > 0)
            {
                var title = Label(Loc.T("Réglages"), 11, Secondary, semibold: true);
                title.Margin = new Thickness(4, 4, 0, -6);
                stack.Children.Add(title);
                var plate = Plate(settings, 12);
                plate.Padding = new Thickness(12);
                stack.Children.Add(plate);
            }
        }
        else if (body is not BlockBody.Organize)
            stack.Children.Add(Paragraph(Loc.T("Bloc à régler sur le Mac pour l'instant."), 12));

        var remove = new Button
        {
            Style = PlainButton,
            HorizontalAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(4, 4, 4, 4),
            Content = Label(Loc.T("Retirer ce bloc"), 13, Rgb(0xFF, 0x69, 0x61)),
        };
        remove.Click += (_, _) => Remove(doc, index);
        AutomationProperties.SetName(remove, Loc.T("Retirer ce bloc"));
        stack.Children.Add(remove);
        return stack;
    }

    private static FrameworkElement Hint()
    {
        var stack = new StackPanel { Spacing = 8, Padding = new Thickness(24), Margin = new Thickness(0, 160, 0, 0) };
        var icon = Icon("slider.horizontal.3", 26, Secondary);
        icon.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Children.Add(icon);
        var title = Label(Loc.T("Aucun bloc choisi"), 14, Text, semibold: true);
        title.HorizontalAlignment = HorizontalAlignment.Center;
        stack.Children.Add(title);
        var text = Paragraph(Loc.T("Choisis une ligne pour la régler."), 12);
        text.TextAlignment = TextAlignment.Center;
        stack.Children.Add(text);
        return stack;
    }

    // Petits morceaux des réglages (colonne étroite : le nom au-dessus du champ).

    private static StackPanel Param(string label, UIElement editor)
    {
        var stack = new StackPanel { Spacing = 5 };
        stack.Children.Add(Label(label, 12, Secondary));
        stack.Children.Add(editor);
        return stack;
    }

    private static NumberBox Number(double value, double min, double max, double step, Action<int> set)
    {
        var box = new NumberBox
        {
            Value = value, Minimum = min, Maximum = max, SmallChange = step, LargeChange = step * 10, Width = 140,
            HorizontalAlignment = HorizontalAlignment.Left,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact,
        };
        box.ValueChanged += (_, e) =>
        {
            if (!double.IsNaN(e.NewValue) && (int)e.NewValue != (int)e.OldValue) set((int)Math.Clamp(e.NewValue, min, max));
        };
        return box;
    }

    private static ComboBox Choice(IReadOnlyList<string> items, int selected, Action<int> set)
    {
        var box = new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch };
        foreach (var item in items) box.Items.Add(item);
        box.SelectedIndex = selected;
        box.SelectionChanged += (_, _) =>
        {
            if (box.SelectedIndex >= 0 && box.SelectedIndex != selected) set(box.SelectedIndex);
        };
        return box;
    }

    /// Champ de texte appliqué à sa sortie (ou à Entrée).
    private static TextBox Field(string text, int max, Action<string> commit)
    {
        var box = new TextBox { Text = text, MaxLength = max, HorizontalAlignment = HorizontalAlignment.Stretch };
        var committed = text;
        void Commit()
        {
            if (box.Text == committed) return;
            committed = box.Text;
            commit(box.Text);
        }
        box.LostFocus += (_, _) => Commit();
        box.KeyDown += (_, e) => { if (e.Key == VirtualKey.Enter) Commit(); };
        return box;
    }

    /// Réglages d'un bloc (seulement ceux qui marchent sous Windows).
    private IEnumerable<UIElement> Editors(MacroDoc doc, BlockBody body, int index, Action<BlockBody> set)
    {
        switch (body)
        {
            case BlockBody.Key k:
                yield return Param(Loc.T("Touche"), CaptureButton(index, MacKeys.ToWindows(k.Ref), Loc.T("Touche"), combo =>
                {
                    if (ForbiddenTargets.Reason(combo) is { } why) _notice = Loc.F("Cible interdite : %@.", why);
                    else if (MacKeys.FromWindows(combo) is not { } key) _notice = Loc.T("touche non prise en charge");
                    else
                    {
                        _notice = null;
                        set(k with { Ref = key });
                        return;
                    }
                    RenderSoon();
                }));
                yield return Param(Loc.T("Nombre de fois"), Number(k.Times, 1, 20, 1, n => set(k with { Times = n })));
                break;
            case BlockBody.Delay d:
                yield return Param(Loc.T("Attendre"), WaitChoice(body, set));
                yield return Param(Loc.T("Durée (ms)"), Number(d.Ms, 0, MacroValidation.MaxDelayMs, 50, n => set(new BlockBody.Delay(n))));
                break;
            case BlockBody.MenuLetters m:
                yield return Param(Loc.T("Lettres"), Field(m.Letters, 8, typed =>
                {
                    var letters = new string(typed.ToLowerInvariant().Where(c => c is >= 'a' and <= 'z').ToArray());
                    if (letters.Length > 0) set(m with { Letters = letters });
                    else RenderSoon();
                }));
                yield return Param(Loc.T("Entrée à la fin"), EnterChoice(m.FinalEnter, e => set(m with { FinalEnter = e })));
                break;
            case BlockBody.MenuKeyPress mk:
                var keys = Enum.GetValues<MenuKey>();
                yield return Param(Loc.T("Touche"), Choice(keys.Select(x => x.Symbol()).ToList(), Array.IndexOf(keys, mk.MenuKey),
                    i => set(mk with { MenuKey = keys[i] })));
                yield return Param(Loc.T("Nombre de fois"), Number(mk.Times, 1, 20, 1, n => set(mk with { Times = n })));
                break;
            case BlockBody.WaitWindow w:
                yield return Param(Loc.T("Attendre"), WaitChoice(body, set));
                yield return Param(Loc.T("Au plus (ms)"), Number(w.TimeoutMs, 100, MacroValidation.MaxWaitMs, 100, n => set(w with { TimeoutMs = n })));
                break;
            case BlockBody.WaitWindowClose wc:
                yield return Param(Loc.T("Attendre"), WaitChoice(body, set));
                yield return Param(Loc.T("Au plus (ms)"), Number(wc.TimeoutMs, 100, MacroValidation.MaxWaitMs, 100, n => set(wc with { TimeoutMs = n })));
                break;
            case BlockBody.FlAction a:
                var actions = FlActions.All;
                var at = actions.ToList().FindIndex(x => x.Key == a.ActionKey);
                yield return Param(Loc.T("Action"), Choice(actions.Select(x => x.Label).ToList(), at, i =>
                {
                    var info = actions[i];
                    // Sans lien, la touche d'origine de FL quand elle existe (comme les pages).
                    var fallback = LightMode.NativeEquivalent(info.Id) is { } native && MacKeys.FromWindows(native) is { } key
                        ? ActionFallback.Key(key) : ActionFallback.None;
                    set(new BlockBody.FlAction(info.Key, fallback));
                }));
                yield return Param(Loc.T("Sans lien"), Label(a.Fallback.KeyRef is { } fk && MacKeys.ToWindows(fk) is { } fc
                    ? fc.ToString() : Loc.T("rien (le bloc échoue)"), 12, Text));
                break;
            case BlockBody.OpenPage p:
                var pages = Enum.GetValues<FlPage>();
                yield return Param(Loc.T("Page"), Choice(pages.Select(x => x.Title()).ToList(), p.Page is { } page ? Array.IndexOf(pages, page) : -1,
                    i => set(new BlockBody.OpenPage(pages[i]))));
                break;
            case BlockBody.Click c:
                yield return Param(Loc.T("Bouton"), Choice(new[] { Loc.T("Gauche"), Loc.T("Droit") }, c.Button == MouseButton.Right ? 1 : 0,
                    i => set(c with { Button = i == 1 ? MouseButton.Right : MouseButton.Left })));
                var spot = new StackPanel { Spacing = 6 };
                spot.Children.Add(Label(c.Target is ClickTarget.ToLearn ? Loc.T("à montrer dans FL") : Loc.T("retenu dans FL"), 12, Text));
                spot.Children.Add(Soft(Loc.T("Montrer dans FL…"), () => LearnClick(target => set(c with { Target = target }))));
                yield return Param(Loc.T("Endroit"), spot);
                break;
            case BlockBody.MenuBar mb:
                yield return Param(Loc.T("Chemin"), Field(string.Join(" › ", mb.Titles), 200, typed =>
                {
                    var titles = MacroDrafts.MenuPath(typed);
                    if (titles.Count > 0) set(new BlockBody.MenuBar(titles));
                    else RenderSoon();
                }));
                yield return Paragraph(Loc.T("Comme dans FL, séparé par › : File › Export › All playlist tracks › Time selection..."), 11);
                break;
            case BlockBody.NameColor nc:
                yield return Param(Loc.T("Nom"), Field(nc.Name ?? "", NameColorPayload.MaxNameScalars, typed =>
                    set(nc with { Name = typed.Trim().Length == 0 ? null : typed.Trim() })));
                yield return Param(Loc.T("Couleur"), Field(nc.Color is { } color ? "#" + color.Hex : "", 7, typed =>
                {
                    if (typed.Trim().Length == 0) set(nc with { Color = null, Fade = null });
                    else if (RgbColor.FromHex(typed.Trim()) is { } parsed) set(nc with { Color = parsed });
                    else RenderSoon();
                }));
                yield return Param(Loc.T("Dégradé jusqu'à"), Field(nc.Fade is { } fade ? "#" + fade.Hex : "", 7, typed =>
                {
                    if (typed.Trim().Length == 0) set(nc with { Fade = null });
                    else if (RgbColor.FromHex(typed.Trim()) is { } parsed) set(nc with { Fade = parsed });
                    else RenderSoon();
                }));
                break;
            case BlockBody.PageOption po:
            {
                // Les options de la page ouverte juste au-dessus (comme sur le Mac), sauf celles pas encore faites ici.
                var above = doc.Blocks.Take(index).Select(b => b.Body).OfType<BlockBody.OpenPage>().LastOrDefault()?.Page;
                if (above is not { } shown)
                {
                    yield return Paragraph(Loc.T("Ajoute « Ouvrir une page de FL » juste au-dessus, puis choisis l'option."), 12, Text);
                    break;
                }
                var options = PageOptions.Options(shown)
                    .Where(o => MacroEffectsWindows.Unsupported(new BlockBody.PageOption(o.Id, "")) is null).ToList();
                yield return Param(Loc.T("Option"), Choice(options.Select(o => o.Label).ToList(), options.FindIndex(o => o.Id == po.Option),
                    i => set(new BlockBody.PageOption(options[i].Id, options[i].Id == po.Option ? po.Name : ""))));
                if (po.Option is { } id && PageOptions.FieldOf(id) is { } field)
                {
                    if (field == PageField.Plugin)
                    {
                        // Un plugin hors des favoris : pris dans « More plugins… » de FL, rien n'est ajouté à ses listes.
                        var outside = PageOptions.FromPluginList(po.Name);
                        yield return Param(Loc.T("Plugin"), Field(outside ?? po.Name, PageOptions.MaxName, typed =>
                            set(po with { Name = outside is not null && typed.Trim().Length > 0
                                ? PageOptions.MorePlugins + PageOptions.PathSeparator + typed.Trim() : typed.Trim() })));
                        var more = new CheckBox { Content = Loc.T("Pas dans mes favoris (pris dans « More plugins… » de FL)"), IsChecked = outside is not null };
                        more.Click += (_, _) =>
                        {
                            var name = outside ?? po.Name;
                            set(po with { Name = more.IsChecked == true && name.Length > 0 ? PageOptions.MorePlugins + PageOptions.PathSeparator + name : name });
                        };
                        yield return more;
                        break;
                    }
                    yield return Param(field == PageField.Channel ? Loc.T("Canal") : Loc.T("Nom"),
                        Field(po.Name, PageOptions.MaxName, typed => set(po with { Name = typed.Trim() })));
                }
                break;
            }
            case BlockBody.TrackMenu tm:
            {
                var choices = MacroTemplates.TrackMenuChoices;
                var chosen = choices.ToList().FindIndex(c => c.Letters == tm.Letters);
                yield return Param(Loc.T("Élément"), Choice(choices.Select(c => c.Name).ToList(), chosen, i =>
                    set(new BlockBody.TrackMenu(choices[i].Letters, choices[i].Labels, tm.Target, choices[i].Enter))));
                yield return Param(Loc.T("Piste"), Choice(new[] { Loc.T("Dernière piste cliquée dans FL"), Loc.T("Là où est le pointeur") },
                    tm.Target == TrackTarget.Cursor ? 1 : 0, i => set(tm with { Target = i == 1 ? TrackTarget.Cursor : TrackTarget.LastClicked })));
                break;
            }
            case BlockBody.DropFile df:
                yield return Param(Loc.T("Preset"), PresetPicker(df.Path, path => set(new BlockBody.DropFile(path))));
                break;
            case BlockBody.ChooseFile cf:
                yield return Param(Loc.T("Preset"), PresetPicker(cf.Path, path => set(new BlockBody.ChooseFile(path))));
                break;
            case BlockBody.Stop s:
                yield return Param(Loc.T("Message"), Field(s.Message ?? "", 120, typed =>
                    set(new BlockBody.Stop(typed.Trim().Length == 0 ? null : typed.Trim()))));
                break;
            case BlockBody.Comment c:
                yield return Param(Loc.T("Texte"), Field(c.Text, 200, typed => set(new BlockBody.Comment(typed.Trim()))));
                break;
        }
    }

    /// Ce qu'attend le bloc « Attendre » (comme le Mac) : un seul bloc pour toutes les attentes, le choix change son
    /// genre (boîte ou menu qui s'ouvre ou se ferme, ou temps fixe) ; le délai est gardé quand il a un sens.
    private static ComboBox WaitChoice(BlockBody body, Action<BlockBody> set)
    {
        var current = body switch
        {
            BlockBody.WaitWindow { Window: WindowKind.Dialog } => 0,
            BlockBody.WaitWindowClose { Window: WindowKind.Dialog } => 1,
            BlockBody.WaitWindow => 2,
            BlockBody.WaitWindowClose => 3,
            _ => 4,
        };
        var timeout = body switch
        {
            BlockBody.WaitWindow w => w.TimeoutMs,
            BlockBody.WaitWindowClose wc => wc.TimeoutMs,
            _ => 4000,
        };
        return Choice(new[]
        {
            Loc.T("qu'une boîte de FL s'ouvre"), Loc.T("que la boîte se ferme"), Loc.T("qu'un menu de FL s'ouvre"),
            Loc.T("que le menu se ferme"), Loc.T("un temps fixe"),
        }, current, i => set(i switch
        {
            0 => new BlockBody.WaitWindow(WindowKind.Dialog, timeout),
            1 => new BlockBody.WaitWindowClose(WindowKind.Dialog, Math.Max(timeout, 8000)),
            2 => new BlockBody.WaitWindow(WindowKind.Menu, timeout),
            3 => new BlockBody.WaitWindowClose(WindowKind.Menu, timeout),
            _ => new BlockBody.Delay(300),
        }));
    }

    /// Nom du preset choisi (jamais son chemin entier) et « Choisir… » : la boîte s'ouvre dans Image-Line › FL Studio ›
    /// Presets › Mixer presets (comme sur le Mac), sinon le dossier le plus proche qui existe.
    private UIElement PresetPicker(string path, Action<string> set)
    {
        var shown = path.Length == 0 ? Loc.T("à choisir") : System.IO.Path.GetFileName(path);
        var stack = new StackPanel { Spacing = 6 };
        stack.Children.Add(Label(shown, 12, path.Length == 0 ? Secondary : Text));
        stack.Children.Add(Soft(Loc.T("Choisir…"), () =>
        {
            if (_demo) return;
            var documents = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
            var start = new[] { @"Image-Line\FL Studio\Presets\Mixer presets", @"Image-Line\FL Studio\Presets", @"Image-Line\FL Studio", "Image-Line" }
                .Select(p => System.IO.Path.Combine(documents, p)).FirstOrDefault(Directory.Exists) ?? documents;
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(_window);
            if (Native.FileDialogs.PickFile(hwnd, Loc.T("Choisis un état de piste du Mixer (.fst)"), Loc.T("État de piste du Mixer"), "fst", start)
                is { } chosen) set(chosen);
        }));
        return stack;
    }

    /// « Montrer dans FL… » : la page attend le clic (FL passe devant), puis revient devant avec la position retenue.
    private void LearnClick(Action<ClickTarget> set)
    {
        if (_demo) return;
        var problem = _app.LearnClick((target, why) =>
        {
            _notice = why ?? Loc.T("Endroit retenu.");
            if (target is not null) set(target);
            else RenderSoon();
            _window.Activate();
        });
        _notice = problem ?? Loc.T("Clique dans FL à l'endroit voulu (Échap pour annuler).");
        RenderSoon();
    }

    private static ComboBox EnterChoice(EnterPolicy current, Action<EnterPolicy> set)
    {
        var options = new List<(string Label, EnterPolicy Policy)>
        {
            (Loc.T("Jamais"), EnterPolicy.Never), (Loc.T("Si besoin"), EnterPolicy.IfNeeded), (Loc.T("Toujours"), EnterPolicy.Always),
        };
        if (current.Mode == "learned") options.Add((Loc.T("Apprise"), current));
        var at = options.FindIndex(o => o.Policy.Mode == current.Mode);
        return Choice(options.Select(o => o.Label).ToList(), at, i => set(options[i].Policy));
    }

    /// Bibliothèque d'exemple du mode photos : en mémoire, jamais écrite.
    private sealed class DemoStorage : IMacroLibraryStorage
    {
        public byte[]? Read() => null;
        public void Write(byte[] data) { }
        public string Backup(byte[] data, string label) => label;
    }
}
