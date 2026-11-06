// La page Macros sur Windows, comme celle du Mac (maquette Macros.dc.html, 29/10 : « exactement la même interface sur
// win ») : dans la fenêtre principale, la liste des macros (maquette du 30/10 : grandes cartes Macro vide et Modèles,
// puis chaque macro en carte : icône, nom, nombre de blocs, interrupteur, touches ; clic droit pour le reste) ; une
// macro s'ouvre dans le créateur, qui prend toute la fenêtre : palette des blocs à gauche (par catégorie ; un clic
// ajoute le bloc sous la ligne choisie, on peut aussi le glisser à sa place), étapes au milieu (← rond, nom,
// raccourci, « Enregistrer » ; numéro, icône, phrase, interrupteur ; glisser une ligne pour la ranger), réglages du
// bloc choisi à droite (« Retirer ce bloc » en bas).
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
        if (_recording is not null) Services.MacroRecorder.Stop();
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

    /// Le contenu de la page Macros au style suisse (comme le Mac du 01/11) : les façons de commencer en colonnes
    /// numérotées (« 01 Enregistrer une macro », « 02 Macro vide », « 03 Modèles »), puis « MES MACROS » et une ligne
    /// par macro ; vide : « Aucune macro ». `columns` ne sert plus (une macro par ligne, comme le Mac).
    public FrameworkElement ListContent(int columns)
    {
        // Maquette du 05/11 (comme le Mac) : trois grandes cartes pour commencer (la première, principale, pleine sur
        // son ombre nette), puis « MES MACROS » et tes macros en cartes (nom, interrupteur, touches).
        if (_store.Macros.Count == 0) return EmptyList();
        var page = new StackPanel { Spacing = 0, Padding = new Thickness(26, 14, 26, 24) };
        var actions = new Grid { ColumnSpacing = 20 };
        var starts = new (string Title, string Text, Action Run)[]
        {
            (Loc.T("Enregistrer une macro"), Loc.T("Fais-le dans FL, l'app le retient."), RecordNew),
            (Loc.T("Macro vide"), Loc.T("Pose les blocs un par un."), NewMacro),
            (Loc.T("Modèles"), Loc.T("Pars d'une macro toute prête."), ShowTemplates),
        };
        for (var i = 0; i < starts.Length; i++)
        {
            actions.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var card = StartCard((i + 1).ToString("00", System.Globalization.CultureInfo.InvariantCulture),
                                 starts[i].Title, starts[i].Text, starts[i].Run, primary: i == 0);
            Grid.SetColumn(card, i);
            actions.Children.Add(card);
        }
        page.Children.Add(actions);

        var heading = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, Margin = new Thickness(0, 30, 0, 6) };
        var title = SwissLabel(Loc.T("Mes macros"), 11, Text);
        AutomationProperties.SetHeadingLevel(title, Microsoft.UI.Xaml.Automation.Peers.AutomationHeadingLevel.Level2);
        heading.Children.Add(title);
        heading.Children.Add(SwissLabel(_store.Macros.Count.ToString(System.Globalization.CultureInfo.CurrentCulture)));
        // Importer / Exporter (06/11, comme le Mac) : Documents › FL Shortcuts › Macros › Importer et › Exporter.
        var exchange = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(18, 0, 0, 0) };
        var import = Soft(Loc.T("Importer"), ImportMacros);
        ToolTipService.SetToolTip(import, Loc.T("Ajouter des macros reçues (.flsmacro) ; la boîte s'ouvre dans Documents › FL Shortcuts › Macros › Importer"));
        var export = Soft(Loc.T("Exporter"), () => ExportMacros(_store.Macros.ToList()));
        ToolTipService.SetToolTip(export, Loc.T("Toutes les macros, un fichier chacune, pour les partager, dans Documents › FL Shortcuts › Macros › Exporter"));
        exchange.Children.Add(import);
        exchange.Children.Add(export);
        heading.Children.Add(exchange);
        page.Children.Add(heading);
        page.Children.Add(Rule(Text));

        var perRow = columns >= 2 ? 3 : 2;
        var grid = new Grid { ColumnSpacing = 20, RowSpacing = 20, Margin = new Thickness(0, 14, 0, 0) };
        for (var c = 0; c < perRow; c++) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var index = 0;
        foreach (var doc in _store.Macros)
        {
            if (index % perRow == 0) grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var card = MacroCard(doc);
            Grid.SetRow(card, index / perRow);
            Grid.SetColumn(card, index % perRow);
            grid.Children.Add(card);
            index++;
        }
        page.Children.Add(grid);
        return page;
    }

    /// Une façon de commencer (maquette du 05/11, comme le Mac) : son numéro en haut, le titre en grand (minuscules)
    /// en bas, une phrase dessous. 06/11 (comme le Mac) : les trois pareilles au repos (fond de la page, numéro gris,
    /// trait fin) ; survolée, une carte se remplit (blanc sous Noir et Orange, noir sous Papier), son numéro passe à
    /// l'orange et elle se soulève sur son ombre nette (effet Gumroad). `primary` ne change plus rien.
    private static FrameworkElement StartCard(string number, string title, string text, Action click, bool primary)
    {
        Color ink = Text, paper = WindowColor, fill = PrimaryFill, onFill = PrimaryInk;
        var num = Label(number, 15, Secondary, bold: true);
        var big = Label(title.ToLower(System.Globalization.CultureInfo.CurrentCulture), 30, ink, bold: true);
        big.CharacterSpacing = -50;
        big.TextWrapping = TextWrapping.Wrap;
        big.MaxLines = 2;
        var sub = Label(text, 13, ink);
        sub.Opacity = 0.75;
        sub.TextWrapping = TextWrapping.Wrap;
        var stack = new Grid { RowSpacing = 10 };
        stack.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        stack.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        stack.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        stack.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        stack.Children.Add(num);
        Grid.SetRow(big, 2);
        stack.Children.Add(big);
        Grid.SetRow(sub, 3);
        stack.Children.Add(sub);
        var face = new Border
        {
            Padding = new Thickness(20),
            MinHeight = 176,
            BorderBrush = Brush(LineColor),
            BorderThickness = new Thickness(1),
            Child = stack,
        };
        var shadow = LiftShadow();
        void Set(bool on)
        {
            face.Background = Brush(on ? fill : paper);
            face.BorderBrush = Brush(on ? fill : LineColor);
            face.BorderThickness = new Thickness(on ? 2 : 1);
            big.Foreground = sub.Foreground = Brush(on ? onFill : ink);
            num.Foreground = Brush(on ? BrandRed : Secondary);
            SetLift(face, shadow, on, 6);
        }
        Set(false);
        var button = new Button
        {
            Style = PlainButton,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            VerticalContentAlignment = VerticalAlignment.Stretch,
            Content = new Grid { Children = { shadow, face } },
        };
        button.PointerEntered += (_, _) => Set(true);
        button.PointerExited += (_, _) => Set(false);
        button.PointerCanceled += (_, _) => Set(false);
        button.PointerCaptureLost += (_, _) => Set(false);
        button.Click += (_, _) => click();
        AutomationProperties.SetName(button, title);
        return button;
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

    private void NewMacro() => Open(_store.Add(MacroDrafts.Empty(_store)).Id);

    /// « Enregistrer une macro » (comme le Mac) : une macro neuve, puis l'enregistrement commence tout de suite.
    private void RecordNew()
    {
        NewMacro();
        StartRecording();
    }

    /// Macro en cours d'enregistrement (FL devant), sinon null.
    private Guid? _recording;

    /// « Enregistrer clics et touches » : FL passe devant ; la suite faite dans FL s'ajoute à la fin de la macro au retour
    /// ici (« Terminer », ou la fenêtre remise devant).
    private void StartRecording()
    {
        if (_demo || _editing is not { } id || _recording is not null) return;
        var problem = _app.RecordMacro((result, why) =>
        {
            _recording = null;
            if (_store.Doc(id) is { } doc && result.Blocks.Count > 0)
                Change(doc, d => d.Blocks.AddRange(result.Blocks.Select(b => new Block(b))));
            var count = result.Blocks.Count == 0 ? Loc.T("Rien d'enregistré dans FL.") : Loc.F("Étapes ajoutées : %lld.", result.Blocks.Count);
            _notice = why is null ? count : count + " " + why;
            _window.Activate();
            RenderSoon();
        });
        _notice = problem;
        if (problem is null) _recording = id;
        RenderSoon();
    }

    /// Pendant l'enregistrement : rouge, une ligne, et « Terminer » (revenir ici le termine aussi).
    private FrameworkElement RecordingBanner()
    {
        var row = new Grid { ColumnSpacing = 12, Padding = new Thickness(14, 10, 10, 10), BorderBrush = Brush(Red), BorderThickness = new Thickness(1) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var dot = new Ellipse { Width = 10, Height = 10, Fill = Brush(Red), VerticalAlignment = VerticalAlignment.Center };
        row.Children.Add(dot);
        var text = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(SwissLabel(Loc.T("Enregistrement"), 11, Red));
        text.Children.Add(Paragraph(Loc.T("Fais ta suite dans FL, puis reviens ici."), 13));
        Grid.SetColumn(text, 1);
        row.Children.Add(text);
        var stop = Primary(Loc.T("Terminer"), MacroRecorderStop);
        stop.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(stop, 2);
        row.Children.Add(stop);
        return row;
    }

    private static void MacroRecorderStop() => Services.MacroRecorder.Stop();

    /// Une macro en carte (maquette du 05/11, comme le Mac) : le nom en gras et l'interrupteur de son raccourci en haut,
    /// « À CORRIGER » en rouge, puis ses touches (ou « Choisir un raccourci… » souligné). Un clic l'ouvre dans le
    /// créateur ; clic droit : Modifier, Dupliquer, le raccourci, Supprimer. Survolée : bordée d'encre sur une encoche
    /// rouge.
    private FrameworkElement MacroCard(MacroDoc doc)
    {
        var shortcut = _demo ? null : _app.MacroShortcut(doc.Id);
        var stack = new StackPanel { Spacing = 14 };
        var top = new Grid { ColumnSpacing = 10 };
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var name = Label(DisplayText.Safe(doc.Name, MacroValidation.MaxNameLength), 17, Text, bold: true);
        name.TextWrapping = TextWrapping.Wrap;
        name.MaxLines = 2;
        top.Children.Add(name);
        if (shortcut is { } s)
        {
            var toggle = Switch(s.Enabled, on => _app.Upsert(s with { Enabled = on }),
                                s.Enabled ? Loc.T("Désactiver le raccourci") : Loc.T("Activer le raccourci"));
            Grid.SetColumn(toggle, 1);
            top.Children.Add(toggle);
        }
        stack.Children.Add(top);
        if (Issue(doc) is { } problem)
        {
            var badge = SwissLabel(Loc.T("À corriger"), 10.5, Red);
            ToolTipService.SetToolTip(badge, problem);
            stack.Children.Add(badge);
        }
        if (shortcut?.Trigger is { } trigger)
        {
            var keys = Keys(trigger);
            keys.HorizontalAlignment = HorizontalAlignment.Left;
            stack.Children.Add(keys);
        }
        else
        {
            var choose = Label(Loc.T("Choisir un raccourci…"), 12, Link, semibold: true);
            choose.TextDecorations = Windows.UI.Text.TextDecorations.Underline;
            stack.Children.Add(choose);
        }
        var face = new Border
        {
            Padding = new Thickness(18),
            Background = Brush(WindowColor),
            BorderBrush = Brush(LineColor),
            BorderThickness = new Thickness(1),
            Child = stack,
        };
        var shadow = HardShadow(BrandRed, 3);
        shadow.Visibility = Visibility.Collapsed;
        var button = new Button
        {
            Style = PlainButton,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            VerticalContentAlignment = VerticalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Stretch,
            Content = new Grid { Children = { shadow, face } },
        };
        void Set(bool on)
        {
            face.BorderBrush = Brush(on ? Text : LineColor);
            face.BorderThickness = new Thickness(on ? 2 : 1);
            shadow.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        }
        button.PointerEntered += (_, _) => Set(true);
        button.PointerExited += (_, _) => Set(false);
        button.PointerCanceled += (_, _) => Set(false);
        button.PointerCaptureLost += (_, _) => Set(false);
        button.Click += (_, _) => Open(doc.Id);
        button.ContextFlyout = MacroOptions(doc, shortcut);
        AutomationProperties.SetName(button, DisplayText.Safe(doc.Name, MacroValidation.MaxNameLength));
        return button;
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
        Add(Loc.T("Exporter…"), () => ExportMacros(new List<MacroDoc> { doc }));
        if (shortcut is { } s)
        {
            menu.Items.Add(new MenuFlyoutSeparator());
            Add(s.Enabled ? Loc.T("Désactiver le raccourci") : Loc.T("Activer le raccourci"), () => _app.Upsert(s with { Enabled = !s.Enabled }));
        }
        menu.Items.Add(new MenuFlyoutSeparator());
        Add(Loc.T("Supprimer"), () => Delete(doc));
        return menu;
    }

    // ---------- Fichiers .flsmacro (06/11, comme le Mac) ----------

    private static string Home => Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    /// Documents › FL Shortcuts › Macros › Importer (où l'on pose les macros reçues) ou › Exporter (où arrivent les
    /// macros exportées) ; les deux créés ensemble, au premier import ou export.
    private static string ExchangeFolder(bool export)
    {
        var macros = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "FL Shortcuts", "Macros");
        foreach (var name in new[] { "Importer", "Exporter" })
        {
            try { Directory.CreateDirectory(System.IO.Path.Combine(macros, name)); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
        return System.IO.Path.Combine(macros, export ? "Exporter" : "Importer");
    }

    /// Nom de fichier tiré du nom de la macro (caractères interdits remplacés), jamais un fichier existant écrasé.
    private static string FreeFile(string folder, string name)
    {
        var invalid = System.IO.Path.GetInvalidFileNameChars();
        var clean = new string(name.Select(c => invalid.Contains(c) ? '-' : c).ToArray()).Trim().TrimEnd('.');
        if (clean.Length == 0) clean = "Macro";
        if (clean.Length > 60) clean = clean[..60];
        var path = System.IO.Path.Combine(folder, clean + "." + MacroExchange.FileExtension);
        for (var n = 2; File.Exists(path); n++)
            path = System.IO.Path.Combine(folder, $"{clean} ({n}).{MacroExchange.FileExtension}");
        return path;
    }

    /// Exporte tout droit dans Macros › Exporter, sans boîte ; l'Explorateur montre le fichier, prêt à envoyer.
    private void ExportMacros(List<MacroDoc> docs)
    {
        if (_demo || docs.Count == 0) return;
        var folder = ExchangeFolder(export: true);
        string? last = null;
        var written = 0;
        foreach (var doc in docs)
        {
            try
            {
                var path = FreeFile(folder, doc.Name);
                using (var file = new FileStream(path, FileMode.CreateNew, FileAccess.Write))
                {
                    var data = MacroExchange.Export(doc, HelpPage.AppVersion, Home);
                    file.Write(data, 0, data.Length);
                }
                last = path;
                written++;
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                _notice = Loc.T("Export impossible");
                RenderSoon();
                break;
            }
        }
        if (last is null) return;
        try { System.Diagnostics.Process.Start("explorer.exe", $"/select,\"{last}\""); }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException) { }
        _toast(written == 1 ? Loc.T("Macro exportée dans Macros › Exporter")
                            : Loc.F("%lld macros exportées dans Macros › Exporter", written), null);
    }

    /// Importe un .flsmacro reçu, relu avant d'être accepté (ses blocs et ce qu'il faudra faire) : il arrive sans
    /// raccourci, sous un nom libre. La boîte s'ouvre dans Macros › Importer.
    private async void ImportMacros()
    {
        if (_demo) return;
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(_window);
        if (Native.FileDialogs.PickFile(hwnd, Loc.T("Importer"), "FL Shortcuts (.flsmacro)", MacroExchange.FileExtension,
                                        ExchangeFolder(export: false)) is not { } path)
            return;
        MacroExchange.Preview preview;
        try
        {
            if (new FileInfo(path).Length > MacroExchange.MaxBytes) throw MacroExchange.ImportFailure.TooLarge;
            preview = MacroExchange.PrepareImport(File.ReadAllBytes(path), Home);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or MacroExchange.ImportFailure or FormatException)
        {
            _notice = Loc.T("Import impossible") + " : " + e.Message;
            RenderSoon();
            return;
        }
        var notes = MacroExchange.Notes(preview);
        var text = "« " + DisplayText.Safe(preview.Doc.Name, 60) + " »"
                   + (notes.Count == 0 ? "" : "\n\n• " + string.Join("\n• ", notes))
                   + "\n\n" + Loc.T("Elle arrive sans raccourci : relis-la dans le créateur, puis choisis-lui un raccourci.");
        if (!await AskAsync(Loc.T("Importer cette macro ?"), text, Loc.T("Importer"), Loc.T("Annuler"))) return;
        var doc = preview.Doc;
        doc.Name = _store.UniqueName(doc.Name);
        var added = _store.Add(doc);
        _toast(Loc.F("« %@ » importée, sans raccourci : relis-la dans le créateur", DisplayText.Safe(added.Name, 40)), null);
        Open(added.Id);
    }

    private void Duplicate(MacroDoc doc)
    {
        var copy = MacroDrafts.Copy(doc);
        copy.Id = Guid.NewGuid();
        copy.Name = _store.UniqueName(doc.Name + Loc.T(" copie"));
        copy.Blocks = MacroTemplates.FreshIds(copy.Blocks);
        var added = _store.Add(copy);
        _toast(Loc.F("« %@ » ajoutée, sans raccourci", DisplayText.Safe(added.Name, 40)), () => _store.Remove(added.Id));
    }

    /// Supprime la macro et son raccourci après une question (06/11, comme le Mac : « c'est seulement pour supprimer
    /// que ça doit demander »), « Annuler » encore dans la notification.
    private async void Delete(MacroDoc doc)
    {
        var name = DisplayText.Safe(doc.Name, 40);
        if (_demo)
        {
            _store.Remove(doc.Id);
            return;
        }
        if (!await AskAsync(Loc.F("Supprimer « %@ » ?", name), Loc.T("La macro et son raccourci sont supprimés."),
                            Loc.T("Supprimer"), Loc.T("Annuler"), destructive: true))
            return;
        var undo = _app.DeleteMacro(doc.Id);
        _toast(Loc.F("« %@ » supprimée", name), undo);
    }

    /// « Modèles » (05/11, comme le Mac : « tout sur une page, sans scroll ») : le titre et son point carré, puis les
    /// modèles en cartes sur deux colonnes (numéro, nom, phrase, « UTILISER ») ; un clic sur une carte la prend.
    private async void ShowTemplates()
    {
        if (_window.Content?.XamlRoot is not { } root) return;
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Style = MainShell.DialogStyle(),
            RequestedTheme = MacLook.SurfaceTheme,
            Background = Brush(WindowColor),
            BorderBrush = Brush(LineColor),
            CloseButtonText = Loc.T("Fermer"),
        };
        var heading = SwissTitle(38);
        heading.Text = Loc.T("Modèles").ToLower(System.Globalization.CultureInfo.CurrentCulture);
        var head = new StackPanel { Padding = new Thickness(0, 0, 0, 12), BorderBrush = Brush(Text), BorderThickness = new Thickness(0, 0, 0, 1) };
        head.Children.Add(PageTitle(heading, 38));
        var grid = new Grid { ColumnSpacing = 16, RowSpacing = 16, Margin = new Thickness(0, 18, 0, 0), MinWidth = 600 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var index = 0;
        foreach (var template in MacroTemplates.Gallery)
        {
            var t = template;
            if (index % 2 == 0) grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var card = TemplateCard((index + 1).ToString("00", System.Globalization.CultureInfo.InvariantCulture), t.Title, t.Summary, () =>
            {
                dialog.Hide();
                Open(_store.Add(MacroDrafts.FromTemplate(t, _store)).Id);
            });
            Grid.SetRow(card, index / 2);
            Grid.SetColumn(card, index % 2);
            grid.Children.Add(card);
            index++;
        }
        dialog.Content = new StackPanel { Children = { head, grid } };
        await dialog.ShowAsync();
    }

    /// Un modèle (comme le Mac) : numéro, nom en gras, phrase, « UTILISER » ; toute la carte le prend, pleine d'encre au
    /// survol.
    private static Button TemplateCard(string number, string title, string summary, Action use)
    {
        Color ink = Text, paper = WindowColor;
        var num = Label(number, 14, Secondary, bold: true);
        var name = Label(title, 16, ink, bold: true);
        var text = Label(summary, 12, ink);
        text.Opacity = 0.7;
        text.TextWrapping = TextWrapping.Wrap;
        text.MaxLines = 2;
        var names = new StackPanel { Spacing = 4, VerticalAlignment = VerticalAlignment.Center, Children = { name, text } };
        var useLabel = SwissLabel(Loc.T("Utiliser"), 10.5, ink);
        var useBox = new Border { BorderBrush = Brush(ink), BorderThickness = new Thickness(2), Padding = new Thickness(10, 0, 10, 0), Height = 30, VerticalAlignment = VerticalAlignment.Center, Child = useLabel };
        useLabel.VerticalAlignment = VerticalAlignment.Center;
        var grid = new Grid { ColumnSpacing = 14 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(24) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        num.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(num);
        Grid.SetColumn(names, 1);
        grid.Children.Add(names);
        Grid.SetColumn(useBox, 2);
        grid.Children.Add(useBox);
        var face = new Border { Padding = new Thickness(16, 0, 16, 0), MinHeight = 76, Background = Brush(paper), BorderBrush = Brush(LineColor), BorderThickness = new Thickness(1), Child = grid };
        void Set(bool on)
        {
            face.Background = Brush(on ? ink : paper);
            name.Foreground = text.Foreground = useLabel.Foreground = Brush(on ? paper : ink);
            useBox.BorderBrush = Brush(on ? paper : ink);
            num.Foreground = Brush(on ? Red : Secondary);
        }
        var button = new Button
        {
            Style = PlainButton,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            VerticalContentAlignment = VerticalAlignment.Stretch,
            Content = face,
        };
        button.PointerEntered += (_, _) => Set(true);
        button.PointerExited += (_, _) => Set(false);
        button.PointerCanceled += (_, _) => Set(false);
        button.PointerCaptureLost += (_, _) => Set(false);
        button.Click += (_, _) => use();
        AutomationProperties.SetName(button, title);
        return button;
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
            CornerRadius = new CornerRadius(0),
            Background = Brush(Colors.Transparent),
            CanDrag = true,
        };
        void Hover(bool on)
        {
            row.Background = Brush(on ? MacLook.Text : Colors.Transparent);      // style suisse : blanc plein, texte noir
            label.Foreground = Brush(on ? MacLook.WindowColor : Text);
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
        var name = NameTitle(doc);
        Grid.SetColumn(name, 1);
        line.Children.Add(name);
        var trigger = ShortcutEditor(doc);
        Grid.SetColumn(trigger, 2);
        line.Children.Add(trigger);
        var save = SaveButton(doc);
        Grid.SetColumn(save, 3);
        line.Children.Add(save);
        // Étroit (fenêtre de 1 000 points : « Save and expor » coupé, photo du 04/11) : les touches passent sous le nom,
        // qui garde toute la ligne.
        line.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        line.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        line.SizeChanged += (_, e) =>
        {
            var narrow = e.NewSize.Width < 620;
            Grid.SetRow(trigger, narrow ? 1 : 0);
            Grid.SetColumn(trigger, narrow ? 1 : 2);
            trigger.HorizontalAlignment = narrow ? HorizontalAlignment.Left : HorizontalAlignment.Stretch;
        };
        _header.Children.Add(line);
        // 06/11 (comme le Mac, « tous ces messages-là, tu peux les enlever ») : plus le problème de la macro au-dessus
        // d'« Enregistrer clics et touches » (il est dit à « Enregistrer ») ; seulement la réponse à ce qu'on vient de
        // faire (nom refusé, clic à montrer dans FL…), en texte simple.
        if (_notice is { } notice) _header.Children.Add(Warning(notice));
    }

    private static FrameworkElement Warning(string text) => Paragraph(text, 12, Secondary);

    /// Nom de la macro au style des titres de page (06/11, comme le Mac) : en minuscules, suivi du point carré ; un clic
    /// l'ouvre en champ (le nom tel qu'il est écrit), Entrée ou un clic ailleurs le referme.
    private FrameworkElement NameTitle(MacroDoc doc)
    {
        static string Shown(string name) =>
            (string.IsNullOrWhiteSpace(name) ? Loc.T("Nom de la macro") : name).ToLower(System.Globalization.CultureInfo.CurrentCulture);
        var box = NameField(doc);
        box.FontSize = 30;
        box.Visibility = Visibility.Collapsed;
        var text = Label(Shown(doc.Name), 30, Text, bold: true);
        text.CharacterSpacing = -39;
        text.MaxLines = 1;
        text.TextTrimming = TextTrimming.CharacterEllipsis;
        var show = new Button
        {
            Style = PlainButton,
            Content = PageTitle(text, 30),
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center,
        };
        ToolTipService.SetToolTip(show, Loc.T("Clique pour renommer la macro"));
        AutomationProperties.SetName(show, Loc.T("Nom de la macro"));
        void Editing(bool on)
        {
            show.Visibility = on ? Visibility.Collapsed : Visibility.Visible;
            box.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
            if (on)
            {
                box.Focus(FocusState.Programmatic);
                box.SelectAll();
            }
            else
            {
                text.Text = Shown(box.Text);
            }
        }
        show.Click += (_, _) => Editing(true);
        box.LostFocus += (_, _) => Editing(false);
        box.KeyDown += (_, e) => { if (e.Key == VirtualKey.Enter) Editing(false); };
        return new Grid { VerticalAlignment = VerticalAlignment.Center, Children = { show, box } };
    }

    /// Question au style de l'app (comme `SwissDialog` du Mac) ; vrai si l'on choisit `primary`.
    private async Task<bool> AskAsync(string title, string text, string primary, string close, bool destructive = false)
    {
        if (_window.Content?.XamlRoot is not { } root) return false;
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Style = MainShell.DialogStyle(),
            RequestedTheme = MacLook.SurfaceTheme,
            Background = Brush(WindowColor),
            BorderBrush = Brush(LineColor),
            Title = title,
            Content = Paragraph(text, 13, Text),
            PrimaryButtonText = primary,
            CloseButtonText = close,
            DefaultButton = ContentDialogButton.Close,
        };
        if (destructive)
        {
            var red = new Style(typeof(Button));
            red.Setters.Add(new Setter(Control.ForegroundProperty, Brush(Red)));
            dialog.PrimaryButtonStyle = red;
        }
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }

    private Button BackButton()
    {
        var button = new Button
        {
            Style = PlainButton,
            Width = 36,
            Height = 36,
            CornerRadius = new CornerRadius(0),
            HorizontalContentAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Content = Icon("back", 14, Text),
            Background = Brush(MacLook.WindowColor),
            BorderBrush = Brush(LineColor),
            BorderThickness = new Thickness(1),
        };
        button.PointerEntered += (_, _) => button.Background = Brush(Accent);
        button.PointerExited += (_, _) => button.Background = Brush(MacLook.WindowColor);
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

    /// Toujours « Enregistrer » (30/10, « le bouton enregistrer ne fonctionne plus » : chaque changement s'enregistre
    /// seul juste après, le bouton restait sur « Enregistrée » sans rien faire) : enregistre et revient aux macros.
    private Button SaveButton(MacroDoc doc)
    {
        var save = Primary(Loc.T("Enregistrer"), async () =>
        {
            // Un raccourci posé sur une macro pas prête : on prévient avant de revenir (06/11, comme le Mac).
            if (!_demo && _app.MacroShortcut(doc.Id) is not null && Issue(doc) is { } problem
                && !await AskAsync(Loc.T("Ce raccourci ne marchera pas encore"), problem,
                                   Loc.T("Enregistrer quand même"), Loc.T("Corriger")))
                return;
            if (!_demo) _app.SaveMacrosNow();
            _dirty = false;
            Back();
        });
        save.VerticalAlignment = VerticalAlignment.Center;
        return save;
    }

    private FrameworkElement ShortcutEditor(MacroDoc doc)
    {
        var shortcut = _demo ? null : _app.MacroShortcut(doc.Id);
        var capture = CaptureButton(-1, shortcut?.Trigger, Loc.T("Choisir un raccourci…"), mouse: true, done: combo =>
        {
            if (_demo) return;
            if (_app.SetMacroShortcut(doc.Id, combo) is { } why) _notice = Loc.F("Ce raccourci ne peut pas lancer la macro : %@", why);
            else _notice = null;
            RenderSoon();
        });
        if (shortcut is null) return capture;
        var remove = new Button
        {
            Style = PlainButton, Width = 26, Height = 26, CornerRadius = new CornerRadius(0),
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
    /// `mouse` : un bouton de souris (molette, côtés) est accepté aussi (raccourci d'une macro, jamais une touche envoyée).
    private Button CaptureButton(int slot, KeyCombo? combo, string prompt, Action<KeyCombo> done, bool mouse = false)
    {
        var recording = _capturing == slot;
        UIElement content = recording
            ? Label(Loc.T("Appuie sur tes touches… Échap annule"), 12, Text)
            : combo is { } c ? (UIElement)Keys(c) : Label(prompt, 12, Link);
        var button = new Button
        {
            Style = PlainButton,
            Content = content,
            MinHeight = 32,
            Padding = new Thickness(8, 4, 8, 4),
            CornerRadius = new CornerRadius(0),
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center,
            Background = Brush(MacLook.WindowColor),
            BorderBrush = Brush(recording ? Accent : White(0.16)),
            BorderThickness = new Thickness(recording ? 2 : 1),
        };
        AutomationProperties.SetName(button, combo?.ToString() ?? prompt);
        if (!recording)
        {
            button.PointerEntered += (_, _) => button.Background = Brush(White(0.16));
            button.PointerExited += (_, _) => button.Background = Brush(MacLook.WindowColor);
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
        if (mouse)
            button.AddHandler(UIElement.PointerPressedEvent, new Microsoft.UI.Xaml.Input.PointerEventHandler((_, e) =>
            {
                if (_capturing != slot || PressedMouseButton(e, button) is not { } pressedButton) return;
                e.Handled = true;
                var pressed = new KeyCombo(pressedButton, IsDown(VirtualKey.Control), IsDown(VirtualKey.Menu),
                    IsDown(VirtualKey.Shift), IsDown(VirtualKey.LeftWindows) || IsDown(VirtualKey.RightWindows));
                StopCapture();
                done(pressed);
            }), true);
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
        if (_recording == doc.Id) page.Children.Add(RecordingBanner());
        if (doc.Blocks.Count > 0)
        {
            var list = new StackPanel();
            for (var i = 0; i < doc.Blocks.Count; i++) list.Children.Add(StepRow(doc, i));
            var plate = Plate(list, 14);
            plate.Padding = new Thickness(2);
            page.Children.Add(plate);
        }
        page.Children.Add(DropZone(doc));
        if (_recording is null && !_demo)
        {
            var record = Soft(Loc.T("Enregistrer clics et touches"), StartRecording);
            record.HorizontalAlignment = HorizontalAlignment.Center;
            page.Children.Add(record);
        }
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
            var note = Label(comment.Text, 13, selected ? Tertiary : Secondary);
            note.FontStyle = Windows.UI.Text.FontStyle.Italic;
            note.TextTrimming = TextTrimming.CharacterEllipsis;
            sentence.Children.Add(note);
        }
        else
        {
            var verb = Label(BlockRegistry.Label(body), 14, selected ? MacLook.WindowColor : Text);
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
            CornerRadius = new CornerRadius(0),
            Background = Brush(selected ? Accent : Colors.Transparent),
            CanDrag = true,
            AllowDrop = true,
        };
        if (!selected)
        {
            void Hover(bool on)
            {
                row.Background = Brush(on ? White(0.08) : Colors.Transparent);    // la ligne choisie, elle, est blanche
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
            CornerRadius = new CornerRadius(0),
            Background = Brush(MacLook.WindowColor),
            BorderBrush = Brush(White(0.2)),
            BorderThickness = new Thickness(1),
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    /// Interrupteur suisse (SwissSwitch du Mac) : rectangle bordé de blanc ; allumé, blanc plein et carré noir à
    /// droite ; éteint, noir et carré blanc à gauche. `help` : son aide (sinon celle d'un bloc).
    /// Case du bloc « Clic de souris » (comme le Mac) : le bouton choisi en grand ; un clic dessus, puis le bouton de la
    /// souris sur lequel on appuie (gauche, droit, molette, côtés) devient celui du bloc. Échap annule.
    private static Button MouseButtonCapture(PointerButton current, Action<PointerButton> picked)
    {
        var listening = false;
        var text = Label(current.Title(), 15, Text, bold: true);
        text.TextWrapping = TextWrapping.Wrap;
        var icon = Icon("cursorarrow.click", 14, Text);
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10, Children = { icon, text } };
        var button = new Button
        {
            Style = PlainButton,
            MinHeight = 46,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(12, 0, 12, 0),
            Background = Brush(WindowColor),
            BorderBrush = Brush(Text),
            BorderThickness = new Thickness(2),
            Content = row,
        };
        void Show()
        {
            text.Text = listening ? Loc.T("Appuie sur un bouton de ta souris…") : current.Title();
            text.FontSize = listening ? 12 : 15;
            text.Foreground = Brush(listening ? Red : Text);
            button.BorderBrush = Brush(listening ? Red : Text);
        }
        button.Click += (_, _) =>
        {
            listening = !listening;
            Show();
        };
        button.AddHandler(UIElement.PointerPressedEvent, new Microsoft.UI.Xaml.Input.PointerEventHandler((_, e) =>
        {
            if (!listening) return;
            var p = e.GetCurrentPoint(button).Properties;
            PointerButton? b = p.IsLeftButtonPressed ? PointerButton.Left
                : p.IsRightButtonPressed ? PointerButton.Right
                : p.IsMiddleButtonPressed ? PointerButton.Middle
                : p.IsXButton1Pressed ? PointerButton.Button4
                : p.IsXButton2Pressed ? PointerButton.Button5 : null;
            if (b is not { } chosen) return;
            e.Handled = true;
            listening = false;
            current = chosen;
            Show();
            picked(chosen);
        }), true);
        button.KeyDown += (_, e) =>
        {
            if (!listening || e.Key != Windows.System.VirtualKey.Escape) return;
            e.Handled = true;
            listening = false;
            Show();
        };
        AutomationProperties.SetName(button, Loc.T("Bouton de la souris : ") + current.Title());
        ToolTipService.SetToolTip(button, Loc.T("Clique ici, puis appuie sur le bouton de ta souris"));
        return button;
    }

    private static Button Switch(bool on, Action<bool> set, string? help = null)
    {
        var knob = new Rectangle { Width = 12, Height = 12, Fill = Brush(on ? MacLook.WindowColor : MacLook.Text),
                                   HorizontalAlignment = on ? HorizontalAlignment.Right : HorizontalAlignment.Left,
                                   Margin = new Thickness(3, 0, 3, 0) };
        var track = new Grid { Width = 40, Height = 20 };
        track.Children.Add(new Border { Background = Brush(on ? MacLook.Text : MacLook.WindowColor),
                                        BorderBrush = Brush(MacLook.Text), BorderThickness = new Thickness(1) });
        track.Children.Add(knob);
        var button = new Button { Style = PlainButton, Content = track, VerticalAlignment = VerticalAlignment.Center };
        help ??= on ? Loc.T("Bloc actif : coupe-le pour le sauter sans le supprimer") : Loc.T("Bloc sauté : rallume-le pour le réactiver");
        ToolTipService.SetToolTip(button, help);
        AutomationProperties.SetName(button, help);
        button.Click += (_, _) => set(!on);
        button.Tapped += (_, e) => e.Handled = true;          // la ligne (ou la carte) n'est pas choisie pour autant
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
                yield return Param(Loc.T("Durée en ms"), Number(d.Ms, 0, MacroValidation.MaxDelayMs, 50, n => set(new BlockBody.Delay(n))));
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
                yield return Param(Loc.T("Au plus, en ms"), Number(w.TimeoutMs, 100, MacroValidation.MaxWaitMs, 100, n => set(w with { TimeoutMs = n })));
                break;
            case BlockBody.WaitWindowClose wc:
                yield return Param(Loc.T("Attendre"), WaitChoice(body, set));
                yield return Param(Loc.T("Au plus, en ms"), Number(wc.TimeoutMs, 100, MacroValidation.MaxWaitMs, 100, n => set(wc with { TimeoutMs = n })));
                break;
            case BlockBody.FlAction a:
                var actions = FlActions.All;
                var at = actions.ToList().FindIndex(x => x.Key == a.ActionKey);
                yield return Param(Loc.T("Action"), Choice(actions.Select(x => Loc.T(x.Label)).ToList(), at, i =>
                {
                    var info = actions[i];
                    // Sans lien, la touche d'origine de FL quand elle existe (comme les pages).
                    var fallback = LightMode.NativeEquivalent(info.Id) is { } native && MacKeys.FromWindows(native) is { } key
                        ? ActionFallback.Key(key) : ActionFallback.None;
                    set(new BlockBody.FlAction(info.Key, fallback));
                }));
                yield return Param(Loc.T("Sans lien"), Label(a.Fallback.KeyRef is { } fk && MacKeys.ToWindows(fk) is { } fc
                    ? fc.ToString() : Loc.T("rien, le bloc échoue"), 12, Text));
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
                spot.Children.Add(Label(TargetText(c.Target), 12, Text));
                // Bouton suivi à son image : son image est reprise en le montrant de nouveau.
                spot.Children.Add(Soft(Loc.T("Montrer dans FL…"),
                    () => LearnClick(target => set(c with { Target = target }), visual: c.Target is ClickTarget.Button)));
                if (MacroDrafts.CanFollow(c.Target))
                {
                    // Comme le Mac : cochée, le bouton est retrouvé par son nom ou son image même s'il bouge (on le montre
                    // de nouveau) ; décochée, sa place seulement.
                    var follow = new CheckBox
                    {
                        Content = Loc.T("Retrouver ce bouton s'il bouge"),
                        IsChecked = c.Target is ClickTarget.Named or ClickTarget.Button,
                    };
                    follow.Click += (_, _) =>
                    {
                        if (follow.IsChecked == true) LearnClick(target => set(c with { Target = target }), visual: true);
                        else set(c with { Target = MacroDrafts.Place(c.Target) });
                    };
                    spot.Children.Add(follow);
                }
                yield return Param(Loc.T("Endroit"), spot);
                break;
            case BlockBody.MouseClick mc:
                // 05/11 (comme le Mac) : une case où l'on appuie sur le bouton de sa souris, puis Simple ou Double.
                yield return Param(Loc.T("Bouton"), MouseButtonCapture(mc.Button, b => set(mc with { Button = b })));
                yield return Param(Loc.T("Clic"), Choice(new[] { Loc.T("Simple"), Loc.T("Double") }, mc.Twice ? 1 : 0,
                    i => set(mc with { Twice = i == 1 })));
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
                        var more = new CheckBox { Content = Loc.T("Pas dans mes favoris"), IsChecked = outside is not null };
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
            if (Native.FileDialogs.PickFile(hwnd, Loc.T("Choisis un état de piste du Mixer"), Loc.T("État de piste du Mixer"), "fst", start)
                is { } chosen) set(chosen);
        }));
        return stack;
    }

    /// Où le clic est retenu, en quelques mots.
    private static string TargetText(ClickTarget target) => target switch
    {
        ClickTarget.ToLearn => Loc.T("à montrer dans FL"),
        ClickTarget.Named n => Loc.F("bouton retrouvé par son nom « %@ »",
            n.Spot.Label.Length > 30 ? n.Spot.Label[..30] + "…" : n.Spot.Label),
        ClickTarget.Button => Loc.T("bouton retrouvé à son image"),
        _ => Loc.T("retenu dans FL"),
    };

    /// « Montrer dans FL… » : la page attend le clic (FL passe devant), puis revient devant avec la position retenue :
    /// le bouton par son nom, sinon son image (`visual`), sinon sa place.
    private void LearnClick(Action<ClickTarget> set, bool visual = false)
    {
        if (_demo) return;
        var problem = _app.LearnClick((target, why) =>
        {
            _notice = why ?? Loc.T("Endroit retenu.");
            if (target is not null) set(target);
            else RenderSoon();
            _window.Activate();
        }, visual);
        _notice = problem ?? Loc.T("Clique dans FL à l'endroit voulu. Échap annule.");
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
