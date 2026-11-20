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
        BlockType.DropFile, BlockType.ChooseFile, BlockType.MouseClick, BlockType.Drag,
    };

    /// Carré creux d'un bloc, comme `BlockSquare` du Mac (08/11, « le créateur n'est pas le même ») : creux à l'encre ;
    /// orange au survol ; plein d'orange sur la ligne choisie.
    private static Border BlockSquare(bool selected = false)
    {
        var square = new Border
        {
            Width = 9,
            Height = 9,
            BorderThickness = new Thickness(1.2),
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
        };
        SetBlockSquare(square, selected, hovered: false);
        return square;
    }

    private static void SetBlockSquare(Border square, bool selected, bool hovered)
    {
        square.BorderBrush = Brush(selected || hovered ? BrandRed : Text);
        square.Background = Brush(selected ? BrandRed : Colors.Transparent);
    }

    /// Carré d'un bloc : orange pour tous (08/11, « carré violet, carré bleu… carré orange pour tous », comme le
    /// créateur du Mac depuis le 05/11 : plus de couleur par catégorie).
    private static Color CategoryTint => MacLook.BrandRed;

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

    private readonly ScrollViewer _stepsScroll = new() { HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
    /// Colonne de gauche du créateur (nom, touche, étapes, « Supprimer la macro »), redessinée à chaque changement.
    private readonly StackPanel _left = new();
    /// « Supprimer la macro » demandé dans la page (maquette « Minimal »).
    private bool _confirmMacroDelete;
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
    /// La bibliothèque a des macros (sous le titre : « CLIQUE SUR UNE TOUCHE POUR LA CHANGER »).
    public bool HasMacros => _store.Macros.Count > 0;

    /// Clic sur la touche d'une macro qui a déjà un raccourci : sa fiche (la fenêtre principale l'ouvre).
    public Func<Shortcut, Task>? EditShortcut { get; set; }

    /// En-tête de la page (maquette « Minimal » du 20/11, comme le Mac) : « + Nouvelle macro » seul, plein d'encre.
    public FrameworkElement HeaderActions() => MinimalButton("+ " + Loc.T("Nouvelle macro"), NewMacro);

    /// « Supprimer » demandé dans la ligne (maquette « Minimal ») : la macro concernée.
    private Guid? _confirmDelete;

    public FrameworkElement ListContent(int columns)
    {
        // Maquette « Minimal » (20/11, comme le Mac) : un tableau sous un trait d'encre ; une macro par ligne, ses
        // étapes en gris ; « Importer » et « Tout exporter » en petits liens dessous. `columns` ne sert plus.
        var list = new StackPanel();
        if (_store.Macros.Count == 0)
        {
            var empty = Label(Loc.T("Aucune macro."), 16, Secondary);
            empty.Margin = new Thickness(0, 24, 0, 0);
            list.Children.Add(empty);
        }
        else
        {
            list.Children.Add(new Rectangle { Height = 2, Fill = Brush(Text) });
            foreach (var doc in _store.Macros) list.Children.Add(MacroLine(doc));
        }
        var links = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 20, Margin = new Thickness(0, 24, 0, 0) };
        links.Children.Add(LinkButton(Loc.T("Importer"), Secondary, ImportMacros));
        if (_store.Macros.Count > 0) links.Children.Add(LinkButton(Loc.T("Tout exporter"), Secondary, () => ExportMacros(_store.Macros.ToList())));
        list.Children.Add(links);
        // Même bord et même largeur que le titre de la page (MainShell.ReadableInset / ReadableMaxWidth).
        var host = new Grid { Margin = new Thickness(56, 4, 56, 80) };
        host.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MaxWidth = 800 });
        host.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        host.Children.Add(list);
        return host;
    }

    /// Les étapes en une ligne (« Menu de FL File › Export · Attendre 1 s · Touche Entrée »), comme le Mac.
    private static string StepsSummary(MacroDoc doc)
    {
        if (doc.Blocks.Count == 0) return Loc.T("Aucune étape");
        var parts = new List<string>();
        foreach (var block in doc.Blocks.Take(6))
        {
            if (block.Body.Type is not { } type) continue;
            var label = BlockRegistry.Label(block.Body);
            var value = BlockRegistry.Spec(type)?.Summary(block.Body) ?? "";
            parts.Add(value.Length == 0 ? label : label + " " + value);
        }
        return string.Join(" · ", parts.Where(p => p.Length > 0));
    }

    /// Une macro (maquette) : son nom en demi-gras et ses étapes en une ligne grise (« À apprendre » / « À corriger »
    /// en rouge devant), sa touche en texte, l'interrupteur et « Supprimer » ; survolée, pleine d'encre ; un clic
    /// l'ouvre ; la touche ouvre la fiche de son raccourci (sans raccourci : le créateur, où il se choisit).
    private FrameworkElement MacroLine(MacroDoc doc)
    {
        var shortcut = _demo ? null : _app.MacroShortcut(doc.Id);
        var title = DisplayText.Safe(doc.Name, MacroValidation.MaxNameLength);
        var grid = new Grid { ColumnSpacing = 24, MinHeight = 58, Padding = new Thickness(12, 8, 12, 8), Background = Brush(Colors.Transparent) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(120) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var name = Label(title, 16, Text, semibold: true);
        name.TextTrimming = TextTrimming.CharacterEllipsis;
        name.TextWrapping = TextWrapping.NoWrap;
        string? alert = MacroDrafts.ToLearn(doc.Blocks) ? Loc.T("À apprendre") : Issue(doc) is not null ? Loc.T("À corriger") : null;
        // Une grille (pas une pile horizontale, de largeur infinie) : la ligne des étapes se coupe avec « … ».
        var steps = new Grid { ColumnSpacing = alert is null ? 0 : 6 };
        steps.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        steps.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        if (alert is not null)
        {
            var warn = Label(alert, 13, Red);
            if (Issue(doc) is { } problem) ToolTipService.SetToolTip(warn, problem);
            steps.Children.Add(warn);
        }
        var summary = Label(StepsSummary(doc), 13, Secondary);
        summary.TextTrimming = TextTrimming.CharacterEllipsis;
        summary.TextWrapping = TextWrapping.NoWrap;
        Grid.SetColumn(summary, 1);
        steps.Children.Add(summary);
        grid.Children.Add(new StackPanel { Spacing = 3, VerticalAlignment = VerticalAlignment.Center, Children = { name, steps } });

        var keyText = shortcut?.Trigger?.ToString();
        var keyLabel = Label(keyText ?? "—", 20, keyText is null ? Secondary : Text, semibold: true);
        keyLabel.FontFamily = TitleFont;
        keyLabel.TextTrimming = TextTrimming.CharacterEllipsis;
        keyLabel.TextWrapping = TextWrapping.NoWrap;
        var key = new Button { Style = PlainButton, Content = keyLabel, Padding = new Thickness(0), HorizontalAlignment = HorizontalAlignment.Stretch, HorizontalContentAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center };
        key.Click += async (_, _) =>
        {
            if (shortcut is { } s && EditShortcut is { } edit) await edit(s);
            else Open(doc.Id);
        };
        ToolTipService.SetToolTip(key, Loc.T("Changer la touche"));
        AutomationProperties.SetName(key, Loc.F("Changer la touche de %@", title));
        Grid.SetColumn(key, 1);
        grid.Children.Add(key);

        var right = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 24, VerticalAlignment = VerticalAlignment.Center };
        Action<bool>? paintSwitch = null;
        if (shortcut is { } sc)
        {
            var (toggle, paint) = MinimalSwitch(sc.Enabled, () => _app.Upsert(sc with { Enabled = !sc.Enabled }));
            paintSwitch = paint;
            right.Children.Add(toggle);
        }
        else
        {
            right.Children.Add(new Border { Width = 106, Height = 22 });
        }
        var deleteLabel = Label(Loc.T("Supprimer"), 13, Secondary);
        deleteLabel.TextDecorations = Windows.UI.Text.TextDecorations.Underline;
        var delete = new Button { Style = PlainButton, Content = deleteLabel, Padding = new Thickness(0), VerticalAlignment = VerticalAlignment.Center };
        delete.Click += (_, _) => AskDelete(doc.Id);
        AutomationProperties.SetName(delete, Loc.T("Supprimer"));
        right.Children.Add(delete);
        Grid.SetColumn(right, 2);
        grid.Children.Add(right);

        var box = new Border { Child = grid, BorderBrush = Brush(LineColor), BorderThickness = new Thickness(0, 0, 0, 1) };
        void Paint(bool on)
        {
            grid.Background = Brush(on ? Text : Colors.Transparent);
            box.BorderBrush = Brush(on ? Text : LineColor);
            name.Foreground = Brush(on ? WindowColor : Text);
            summary.Foreground = Brush(on ? WithOpacity(WindowColor, 0.7) : Secondary);
            keyLabel.Foreground = Brush(keyText is null ? (on ? WithOpacity(WindowColor, 0.6) : Secondary) : on ? WindowColor : Text);
            deleteLabel.Foreground = Brush(on ? WindowColor : Secondary);
            paintSwitch?.Invoke(on);
        }
        grid.PointerEntered += (_, _) => Paint(true);
        grid.PointerExited += (_, _) => Paint(false);
        grid.Tapped += (_, e) =>
        {
            // La touche, l'interrupteur et « Supprimer » font le leur : la ligne n'ouvre pas le créateur en plus.
            if (e.Handled || OnButton(e, grid)) return;
            e.Handled = true;
            Open(doc.Id);
        };
        grid.ContextFlyout = MacroOptions(doc, shortcut);
        AutomationProperties.SetName(grid, title);

        var stack = new StackPanel { Children = { box } };
        if (_confirmDelete == doc.Id)
        {
            var band = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16, Padding = new Thickness(12, 10, 12, 10) };
            var question = Label(Loc.F("Supprimer « %@ » ?", DisplayText.Safe(doc.Name, 40)), 14, Text);
            question.VerticalAlignment = VerticalAlignment.Center;
            band.Children.Add(question);
            band.Children.Add(MinimalButton(Loc.T("Supprimer"), () => { _confirmDelete = null; Delete(doc); }));
            var cancel = LinkButton(Loc.T("Annuler"), Text, () => { _confirmDelete = null; _window.DispatcherQueue.TryEnqueue(() => _listChanged()); });
            cancel.VerticalAlignment = VerticalAlignment.Center;
            band.Children.Add(cancel);
            stack.Children.Add(new Border { Child = band, BorderBrush = Brush(LineColor), BorderThickness = new Thickness(0, 0, 0, 1) });
        }
        return stack;
    }

    /// « Supprimer » d'une ligne ou du clic droit : la question vient dans la ligne même (maquette « Minimal »).
    private void AskDelete(Guid id)
    {
        _confirmDelete = id;
        _window.DispatcherQueue.TryEnqueue(() => _listChanged());
    }

    private void NewMacro() => Open(_store.Add(MacroDrafts.Empty(_store)).Id);

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
            RecordingBar.Hide();
            if (_store.Doc(id) is { } doc && result.Blocks.Count > 0)
                Change(doc, d => d.Blocks.AddRange(result.Blocks.Select(b => new Block(b))));
            var count = result.Blocks.Count == 0 ? Loc.T("Rien d'enregistré dans FL.") : Loc.F("Étapes ajoutées : %lld.", result.Blocks.Count);
            _notice = why is null ? count : count + " " + why;
            _window.Activate();
            RenderSoon();
        });
        _notice = problem;
        if (problem is null)
        {
            _recording = id;
            RecordingBar.Show();                     // devant FL, comme le panneau du Mac
        }
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
        Add(Loc.T("Supprimer"), () => AskDelete(doc.Id));
        return SwissMenu(menu);
    }

    // ---------- Fichiers .flsmacro (06/11, comme le Mac) ----------

    private static string Home => Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

    /// Presets joints aux macros importées ou ajoutées depuis la Communauté (comme le Mac : Documents › FL Shortcuts › Presets).
    public static string PresetsFolder =>
        System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments), "FL Shortcuts", "Presets");

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
            preview = MacroExchange.PrepareImport(File.ReadAllBytes(path), Home, PresetsFolder,
                installed: effect => PluginDatabase.Installed(_app.PluginRoots, effect).Select(p => p.Name).ToList());
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or MacroExchange.ImportFailure or FormatException)
        {
            _notice = Loc.T("Import impossible") + " : " + e.Message;
            RenderSoon();
            return;
        }
        var notes = MacroExchange.Notes(preview);
        var text = "« " + DisplayText.Safe(preview.Doc.Name, 60) + " »"
                   + (notes.Count == 0 ? "" : "\n\n• " + string.Join("\n• ", notes));
        if (!await AskAsync(Loc.T("Importer cette macro ?"), text, Loc.T("Importer"), Loc.T("Annuler"))) return;
        var doc = preview.Doc;
        // Presets joints : rangés dans Documents › FL Shortcuts › Presets (jamais par-dessus un autre fichier).
        if (MacroExchange.WriteAttached(preview.Files ?? Array.Empty<MacroExchange.AttachedFile>()) is { } why) _notice = why;
        doc.Name = _store.UniqueName(doc.Name);
        var added = _store.Add(doc);
        _toast(Loc.F("« %@ » importée", DisplayText.Safe(added.Name, 40)), null);
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

    /// Supprime la macro et son raccourci (la question a été posée dans la ligne, maquette « Minimal » ; 06/11 : « c'est
    /// seulement pour supprimer que ça doit demander »), « Annuler » encore dans la notification.
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

    /// Problème de la macro sous Windows (compilée avec les règles de Windows), sinon null.
    private string? Issue(MacroDoc doc) => _demo
        ? MacroProgram.Compile(doc, new ValidationContext { PlatformProblem = MacroEffectsWindows.Unsupported }).Problem
        : _app.MacroIssue(doc.Id);

    // ---------- Créateur ----------

    /// Maquette « Minimal » (20/11, comme le Mac) : une seule colonne. En haut « ← Macros » et « Terminé » ; à gauche le
    /// nom, la touche, les étapes en phrases ; à droite la boîte « Ajouter une étape » ; tout défile ensemble.
    private void BuildCreator()
    {
        Creator.Background = Brush(WindowColor);
        Creator.Padding = new Thickness(0);
        var top = new Grid { Margin = new Thickness(0, 24, 0, 0) };
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        top.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var back = LinkButton("← " + Loc.T("Macros"), Secondary, Done);
        back.VerticalAlignment = VerticalAlignment.Center;
        top.Children.Add(back);
        var done = MinimalButton(Loc.T("Terminé"), Done);
        ToolTipService.SetToolTip(done, Loc.T("Enregistrer et revenir aux macros"));
        Grid.SetColumn(done, 1);
        top.Children.Add(done);
        var body = new Grid { ColumnSpacing = 32 };
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MinWidth = 360 });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(300) });
        body.Children.Add(_left);
        var box = AddStepBox();
        box.Margin = new Thickness(0, 60, 0, 0);
        box.VerticalAlignment = VerticalAlignment.Top;
        Grid.SetColumn(box, 1);
        body.Children.Add(box);
        // Toute la largeur jusqu'à 1 088, collée à gauche (photo de la CI : la page prenait la largeur de son contenu).
        var page = new StackPanel { Children = { top, body } };
        var host = new Grid { Margin = new Thickness(56, TitleBarHeight - 8, 56, 32) };
        host.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star), MaxWidth = 1088 });
        host.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        host.Children.Add(page);
        _stepsScroll.Content = host;
        Creator.Children.Add(_stepsScroll);
    }

    /// « Ajouter une étape » (maquette) : une boîte bordée d'encre, les blocs par catégorie (Clavier, FL Studio, Souris,
    /// Temps) ; un clic ajoute le bloc sous l'étape choisie, on peut aussi le glisser. En tête, « Enregistrer clics et
    /// touches ».
    private Border AddStepBox()
    {
        var stack = new StackPanel { Padding = new Thickness(0, 0, 0, 8) };
        var title = SwissLabel(Loc.T("Ajouter une étape"), 12, Secondary);
        title.Margin = new Thickness(16, 10, 16, 4);
        AutomationProperties.SetHeadingLevel(title, Microsoft.UI.Xaml.Automation.Peers.AutomationHeadingLevel.Level2);
        stack.Children.Add(title);
        stack.Children.Add(AddStepLine(Loc.T("Enregistrer clics et touches"), StartRecording, red: true,
                                       help: Loc.T("FL passe devant : clique et tape ta suite, puis reviens ici.")));
        foreach (var (category, entries) in StepSentence.Groups(_palette))
        {
            var label = Label(category, 12, Secondary);
            label.Margin = new Thickness(16, 10, 16, 2);
            stack.Children.Add(label);
            foreach (var entry in entries) stack.Children.Add(AddStepLine(StepSentence.AddLabel(entry), () => Insert(entry, before: null), entry: entry, help: entry.Help));
        }
        return new Border { Child = stack, BorderBrush = Brush(Text), BorderThickness = new Thickness(2) };
    }

    /// Une ligne de la boîte : pas un bouton (le glisser ne démarrerait pas) ; pleine d'encre au survol.
    private Border AddStepLine(string text, Action action, bool red = false, PaletteEntry? entry = null, string? help = null)
    {
        var label = Label(text, 16, red ? Red : Text);
        label.TextWrapping = TextWrapping.Wrap;
        var row = new Border
        {
            Child = label,
            Padding = new Thickness(16, 6, 16, 6),
            Margin = new Thickness(2, 0, 2, 0),
            Background = Brush(Colors.Transparent),
            CanDrag = entry is not null,
        };
        void Hover(bool on)
        {
            row.Background = Brush(on ? MacLook.Text : Colors.Transparent);
            label.Foreground = Brush(on ? MacLook.WindowColor : red ? Red : Text);
        }
        row.PointerEntered += (_, _) => Hover(true);
        row.PointerExited += (_, _) => Hover(false);
        row.PointerCanceled += (_, _) => Hover(false);
        row.Tapped += (_, _) => action();
        if (entry is not null)
            row.DragStarting += (_, e) =>
            {
                e.Data.SetText(BlockDrag + entry.Type);
                e.Data.RequestedOperation = DataPackageOperation.Copy;
            };
        if (help is not null) ToolTipService.SetToolTip(row, help);
        AutomationProperties.SetName(row, text);
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
        _left.Children.Clear();
        _left.Children.Add(Head(doc));
        if (_notice is { } notice)
        {
            var warn = Paragraph(notice, 13, Red);
            warn.Margin = new Thickness(0, 8, 0, 0);
            _left.Children.Add(warn);
        }
        if (_recording == doc.Id)
        {
            var banner = RecordingBanner();
            banner.Margin = new Thickness(0, 24, 0, 0);
            _left.Children.Add(banner);
        }
        var steps = Steps(doc);
        steps.Margin = new Thickness(0, 32, 0, 0);
        _left.Children.Add(steps);
        var delete = DeleteArea(doc);
        delete.Margin = new Thickness(0, 48, 0, 0);
        _left.Children.Add(delete);
    }

    /// Le nom en grand, souligné (maquette), puis « Touche » et la touche de la macro.
    private FrameworkElement Head(MacroDoc doc)
    {
        var head = new Grid { ColumnSpacing = 32, Margin = new Thickness(0, 16, 0, 0) };
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        // La touche prend sa place, le nom garde le reste (fenêtre étroite : le nom était coupé sur le Mac).
        head.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var name = NameField(doc);
        name.FontSize = 32;
        name.FontFamily = SwissFont;
        name.FontWeight = FontWeights.SemiBold;
        name.CharacterSpacing = -20;
        name.Padding = new Thickness(0, 0, 0, 4);
        name.PlaceholderText = Loc.T("Nouvelle macro");
        name.VerticalAlignment = VerticalAlignment.Bottom;
        name.BorderThickness = new Thickness(0, 0, 0, 2);
        foreach (var key in new[] { "TextControlBorderThemeThickness", "TextControlBorderThemeThicknessFocused" })
            name.Resources[key] = new Thickness(0, 0, 0, 2);
        name.Resources["TextControlBorderBrush"] = Brush(Faint);
        name.Resources["TextControlBorderBrushPointerOver"] = Brush(Secondary);
        name.Resources["TextControlBorderBrushFocused"] = Brush(Text);
        foreach (var key in new[] { "TextControlPlaceholderForeground", "TextControlPlaceholderForegroundPointerOver",
                                    "TextControlPlaceholderForegroundFocused" })
            name.Resources[key] = Brush(Secondary);
        head.Children.Add(name);
        var trigger = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12, VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, 6) };
        var keyLabel = Label(Loc.T("Touche"), 15, Secondary);
        keyLabel.VerticalAlignment = VerticalAlignment.Bottom;
        keyLabel.Margin = new Thickness(0, 0, 0, 6);
        trigger.Children.Add(keyLabel);
        trigger.Children.Add(ShortcutEditor(doc));
        Grid.SetColumn(trigger, 1);
        head.Children.Add(trigger);
        return head;
    }

    /// « Terminé » / « ← Macros » : un raccourci posé sur une macro pas prête est dit d'abord (06/11), puis retour.
    private async void Done()
    {
        if (_editing is not { } id || _store.Doc(id) is not { } doc)
        {
            Back();
            return;
        }
        if (!_demo && _app.MacroShortcut(doc.Id) is not null && Issue(doc) is { } problem
            && !await AskAsync(Loc.T("Ce raccourci ne marchera pas encore"), problem,
                               Loc.T("Enregistrer quand même"), Loc.T("Corriger")))
            return;
        if (!_demo) _app.SaveMacrosNow();
        _dirty = false;
        _confirmMacroDelete = false;
        Back();
    }

    /// « Supprimer la macro » en rouge, qui demande dans la page (maquette).
    private FrameworkElement DeleteArea(MacroDoc doc)
    {
        if (!_confirmMacroDelete)
            return LinkButton(Loc.T("Supprimer la macro"), Red, () =>
            {
                _confirmMacroDelete = true;
                RenderSoon();
            });
        var ask = new StackPanel { Spacing = 8 };
        ask.Children.Add(Label(Loc.T("Supprimer cette macro ?"), 14, Text));
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16 };
        row.Children.Add(MinimalButton(Loc.T("Supprimer"), () =>
        {
            _confirmMacroDelete = false;
            var name = DisplayText.Safe(doc.Name, 40);
            _dirty = false;
            if (_demo)
            {
                _store.Remove(doc.Id);
                return;
            }
            var undo = _app.DeleteMacro(doc.Id);
            Back();
            _toast(Loc.F("« %@ » supprimée", name), undo);
        }));
        var cancel = LinkButton(Loc.T("Annuler"), Text, () =>
        {
            _confirmMacroDelete = false;
            RenderSoon();
        });
        cancel.VerticalAlignment = VerticalAlignment.Center;
        row.Children.Add(cancel);
        ask.Children.Add(row);
        return ask;
    }

    private static FrameworkElement Warning(string text) => Paragraph(text, 12, Secondary);

    /// Question au style de l'app (comme `SwissDialog` du Mac) ; vrai si l'on choisit `primary`.
    private async Task<bool> AskAsync(string title, string text, string primary, string close, bool destructive = false)
    {
        if (_window.Content?.XamlRoot is not { } root) return false;
        return await SwissQuestion.AskAsync(root, title, text, new[] { primary, close }, destructive ? 0 : null) == 0;
    }

    /// Le nom de la macro, en grand, sans cadre : appliqué à la sortie du champ ou à Entrée.
    private TextBox NameField(MacroDoc doc, bool lower = false)
    {
        var box = new TextBox
        {
            Text = lower ? doc.Name.ToLower(System.Globalization.CultureInfo.CurrentCulture) : doc.Name,
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
        var committed = box.Text;                    // en minuscules au titre : rien à renommer tant qu'on n'écrit pas
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

    /// La touche de la macro (maquette) : en 24 demi-gras soulignée ; « Choisir » en rouge pointillé sans touche ; un
    /// clic, puis la touche (Retour arrière seul : plus de touche ; Échap : rien ne change).
    private FrameworkElement ShortcutEditor(MacroDoc doc)
    {
        var shortcut = _demo ? null : _app.MacroShortcut(doc.Id);
        return CaptureButton(-1, shortcut?.Trigger, Loc.T("Choisir"), mouse: true, minimal: true, done: combo =>
        {
            if (_demo) return;
            if (combo.Vk == 0x08 && !combo.HasModifiers)
            {
                _app.RemoveMacroShortcut(doc.Id);
                _notice = null;
            }
            else if (_app.SetMacroShortcut(doc.Id, combo) is { } why) _notice = Loc.F("Ce raccourci ne peut pas lancer la macro : %@", why);
            else _notice = null;
            RenderSoon();
        });
    }

    /// Champ d'une combinaison (raccourci de la macro ou bloc « Touche ») : ses touches en petites plaques ; un clic,
    /// puis les touches appuyées la remplacent (Échap seul annule).
    /// `mouse` : un bouton de souris (molette, côtés) est accepté aussi (raccourci d'une macro, jamais une touche envoyée).
    private Button CaptureButton(int slot, KeyCombo? combo, string prompt, Action<KeyCombo> done, bool mouse = false, bool minimal = false)
    {
        var recording = _capturing == slot;
        UIElement content = minimal
            ? MinimalKey(recording, combo, prompt)
            : recording
            ? Label(Loc.T("Appuie sur tes touches…"), 12, Text)
            : combo is { } c ? (UIElement)Keys(c) : Label(prompt, 12, Link);
        var button = new Button
        {
            Style = PlainButton,
            Content = content,
            MinHeight = minimal ? 0 : 32,
            Padding = minimal ? new Thickness(0) : new Thickness(8, 4, 8, 4),
            CornerRadius = new CornerRadius(0),
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = minimal ? VerticalAlignment.Bottom : VerticalAlignment.Center,
            Background = Brush(minimal ? Colors.Transparent : MacLook.WindowColor),
            BorderBrush = Brush(minimal ? Colors.Transparent : recording ? Accent : White(0.16)),
            BorderThickness = new Thickness(minimal ? 0 : recording ? 2 : 1),
        };
        AutomationProperties.SetName(button, combo?.ToString() ?? prompt);
        if (!recording)
        {
            if (!minimal)
            {
                button.PointerEntered += (_, _) => button.Background = Brush(White(0.16));
                button.PointerExited += (_, _) => button.Background = Brush(MacLook.WindowColor);
            }
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

    /// La touche de la maquette : 24 demi-gras soulignée d'encre ; « Choisir » rouge pointillé ; pendant l'écoute,
    /// « Appuie sur une touche » en rouge, souligné de rouge.
    private static FrameworkElement MinimalKey(bool recording, KeyCombo? combo, string prompt)
    {
        var text = recording ? Loc.T("Appuie sur une touche") : combo?.ToString() ?? prompt;
        var label = Label(text, recording || combo is null ? 17 : 24, recording || combo is null ? Red : Text, semibold: !recording && combo is not null);
        label.TextWrapping = TextWrapping.NoWrap;
        var line = new Rectangle { Height = 2, Fill = Brush(recording ? Red : Text), VerticalAlignment = VerticalAlignment.Bottom };
        if (!recording && combo is null)
        {
            line.Fill = null;
            line.Stroke = Brush(Red);
            line.StrokeThickness = 2;
            line.StrokeDashArray = new DoubleCollection { 1, 1.5 };
            line.Height = 2;
        }
        return new StackPanel { Spacing = 4, Children = { label, line } };
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

    /// Les étapes (maquette « Minimal ») sous un trait d'encre : une phrase numérotée par bloc ; sans étape, « Choisis
    /// une étape à droite. » (on peut y lâcher un bloc).
    private StackPanel Steps(MacroDoc doc)
    {
        var list = new StackPanel();
        list.Children.Add(new Rectangle { Height = 2, Fill = Brush(Text) });
        if (doc.Blocks.Count == 0)
        {
            var empty = new Border { Background = Brush(Colors.Transparent), AllowDrop = true, Padding = new Thickness(12, 16, 12, 16) };
            empty.Child = Label(Loc.T("Choisis une étape à droite."), 16, Secondary);
            AcceptDrops(empty, 0, null);
            list.Children.Add(empty);
            return list;
        }
        for (var i = 0; i < doc.Blocks.Count; i++) list.Children.Add(StepRow(doc, i));
        return list;
    }

    /// Une étape : son numéro (« 01 »), sa phrase avec la valeur soulignée (rouge tant qu'elle manque) ; un clic ouvre
    /// ses réglages juste dessous ; au survol, « Monter », « Descendre », « Retirer » ; clic droit : activer /
    /// désactiver ; on la glisse pour la ranger.
    private FrameworkElement StepRow(MacroDoc doc, int index)
    {
        var block = doc.Blocks[index];
        var body = block.Body;
        var spec = body.Type is { } type ? BlockRegistry.Spec(type) : null;
        var open = block.Id == _selected;

        var grid = new Grid { ColumnSpacing = 16, MinHeight = 52, Padding = new Thickness(12, 8, 12, 8), Background = Brush(Colors.Transparent) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(32) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var number = Label((index + 1).ToString("00", System.Globalization.CultureInfo.InvariantCulture), 13, Secondary);
        number.VerticalAlignment = VerticalAlignment.Center;
        grid.Children.Add(number);

        var sentence = new TextBlock { FontFamily = SwissFont, FontSize = 17, Foreground = Brush(Text), TextWrapping = TextWrapping.Wrap, VerticalAlignment = VerticalAlignment.Center };
        if (body is BlockBody.Comment comment)
        {
            sentence.Text = comment.Text;
            sentence.Foreground = Brush(Secondary);
            sentence.FontStyle = Windows.UI.Text.FontStyle.Italic;
        }
        else
        {
            var parts = StepSentence.For(body.Type, BlockRegistry.Label(body));
            var value = spec?.Summary(body) is { Length: > 0 } summary ? summary : null;
            // « Poser un marqueur » avec un nom (08/11) : le nom suit l'action.
            if (value is not null && MarkerPayload.Of(block) is { } marker) value += " · " + DisplayText.Safe(marker, 40);
            if (parts.Pre.Length > 0) sentence.Inlines.Add(new Microsoft.UI.Xaml.Documents.Run { Text = parts.Pre + " " });
            if (value is not null || parts.Placeholder.Length > 0)
                sentence.Inlines.Add(new Microsoft.UI.Xaml.Documents.Run
                {
                    Text = (value ?? parts.Placeholder) + " ▾",
                    FontWeight = value is null ? FontWeights.Normal : FontWeights.SemiBold,
                    Foreground = Brush(value is null ? Red : Text),
                    TextDecorations = Windows.UI.Text.TextDecorations.Underline,
                });
            if (parts.Post.Length > 0) sentence.Inlines.Add(new Microsoft.UI.Xaml.Documents.Run { Text = " " + parts.Post });
            if (!block.Enabled) sentence.Inlines.Add(new Microsoft.UI.Xaml.Documents.Run { Text = "  " + Loc.T("désactivée"), FontSize = 13, Foreground = Brush(Secondary) });
        }
        var middle = new StackPanel { Spacing = 4, VerticalAlignment = VerticalAlignment.Center, Children = { sentence } };
        if (MacroEffectsWindows.Unsupported(body) is { } missing) middle.Children.Add(Paragraph(missing, 13, Red));
        Grid.SetColumn(middle, 1);
        grid.Children.Add(middle);

        // Comme le Mac (photo de la CI du 20/11) : par-dessus la fin de la ligne, au survol seulement ; cachés, ils ne
        // prennent plus de place à la phrase.
        var toolRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16, VerticalAlignment = VerticalAlignment.Center };
        if (index > 0) toolRow.Children.Add(LinkButton(Loc.T("Monter"), Secondary, () => MoveStep(doc, index, -1)));
        if (index < doc.Blocks.Count - 1) toolRow.Children.Add(LinkButton(Loc.T("Descendre"), Secondary, () => MoveStep(doc, index, 1)));
        toolRow.Children.Add(LinkButton(Loc.T("Retirer"), Secondary, () => Remove(doc, index)));
        var hoverFill = Color.FromArgb(255, (byte)(WindowColor.R + (Text.R - WindowColor.R) * 0.06), (byte)(WindowColor.G + (Text.G - WindowColor.G) * 0.06),
                                       (byte)(WindowColor.B + (Text.B - WindowColor.B) * 0.06));
        var tools = new Border
        {
            Child = toolRow,
            Background = Brush(hoverFill),
            Padding = new Thickness(16, 0, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Stretch,
            Visibility = open ? Visibility.Visible : Visibility.Collapsed,
        };
        Grid.SetColumn(tools, 1);
        grid.Children.Add(tools);
        foreach (var child in new UIElement[] { number, middle }) child.Opacity = block.Enabled ? 1 : 0.45;

        // Trait d'insertion pendant un dépôt sur cette ligne : rouge (comme le Mac).
        var mark = new Rectangle { Height = 3, Fill = Brush(BrandRed), VerticalAlignment = VerticalAlignment.Top, Visibility = Visibility.Collapsed, IsHitTestVisible = false };
        var row = new Border
        {
            Child = grid,
            BorderBrush = Brush(Faint),
            BorderThickness = new Thickness(0, 0, 0, 1),
            Background = Brush(open ? WithOpacity(Text, 0.06) : Colors.Transparent),
            CanDrag = true,
            AllowDrop = true,
        };
        void Hover(bool on)
        {
            row.Background = Brush(on || open ? WithOpacity(Text, 0.06) : Colors.Transparent);
            tools.Visibility = on || open ? Visibility.Visible : Visibility.Collapsed;
        }
        row.PointerEntered += (_, _) => Hover(true);
        row.PointerExited += (_, _) => Hover(false);
        row.PointerCanceled += (_, _) => Hover(false);
        row.Tapped += (_, e) =>
        {
            // « Monter », « Descendre », « Retirer » font le leur.
            if (OnButton(e, row)) return;
            _selected = _selected == block.Id ? null : block.Id;
            RenderSoon();
        };
        var menu = new MenuFlyout();
        var enable = new MenuFlyoutItem { Text = block.Enabled ? Loc.T("Désactiver") : Loc.T("Activer") };
        enable.Click += (_, _) => Change(doc, d => d.Blocks[index].Enabled = !block.Enabled);
        menu.Items.Add(enable);
        menu.Items.Add(new MenuFlyoutSeparator());
        var delete = new MenuFlyoutItem { Text = Loc.T("Retirer") };
        delete.Click += (_, _) => Remove(doc, index);
        menu.Items.Add(delete);
        row.ContextFlyout = SwissMenu(menu);
        row.DragStarting += (_, e) =>
        {
            e.Data.SetText(StepDrag + index.ToString(System.Globalization.CultureInfo.InvariantCulture));
            e.Data.RequestedOperation = DataPackageOperation.Copy;
        };
        AcceptDrops(row, index, mark, split: true, moving: grid);
        AutomationProperties.SetName(row, $"{index + 1}. {BlockRegistry.Label(body)}");

        var cell = new Grid();
        cell.Children.Add(row);
        cell.Children.Add(mark);
        if (!open) return cell;
        // Réglages du bloc ouverts juste sous sa ligne, dans un cadre d'encre (comme le Mac).
        var settings = new Border
        {
            Child = BlockSettings(doc, index),
            BorderBrush = Brush(Text),
            BorderThickness = new Thickness(2),
            Margin = new Thickness(60, 8, 0, 8),
            Padding = new Thickness(16),
        };
        return new StackPanel { Children = { cell, settings } };
    }

    private void MoveStep(MacroDoc doc, int index, int delta)
    {
        var block = doc.Blocks[index];
        Change(doc, d => MacroDrafts.Move(d.Blocks, index, delta));
        _selected = _selected == block.Id ? block.Id : _selected;
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

    /// Dépôt d'un bloc de la palette ou d'une ligne glissée, à la place `before`. `split` (une ligne, comme le Mac
    /// le 07/11) : moitié haute, au-dessus ; moitié basse, dessous ; le trait suit.
    /// `moving` : le contenu de la ligne, qui s'écarte en douceur du trait (08/11, « refais une animation… pour que les
    /// gens comprennent qu'ils peuvent glisser », comme le Mac) ; la zone de dépôt, elle, ne bouge pas.
    private void AcceptDrops(UIElement target, int before, Rectangle? mark, bool split = false, UIElement? moving = null)
    {
        var place = before;
        if (moving is not null) moving.TranslationTransition = new Vector3Transition { Duration = TimeSpan.FromMilliseconds(160) };
        void Settle()
        {
            if (moving is not null) moving.Translation = System.Numerics.Vector3.Zero;
        }
        target.DragOver += (_, e) =>
        {
            e.AcceptedOperation = e.DataView.Contains(StandardDataFormats.Text) ? DataPackageOperation.Copy : DataPackageOperation.None;
            e.DragUIOverride.IsCaptionVisible = false;
            e.DragUIOverride.IsGlyphVisible = false;
            if (split && target is FrameworkElement area && area.ActualHeight > 0)
            {
                var lower = e.GetPosition(area).Y > area.ActualHeight / 2;
                place = lower ? before + 1 : before;
                if (mark is not null) mark.VerticalAlignment = lower ? VerticalAlignment.Bottom : VerticalAlignment.Top;
                if (moving is not null) moving.Translation = new System.Numerics.Vector3(0, lower ? -6 : 6, 0);
            }
        };
        target.DragLeave += (_, _) => Settle();
        if (mark is not null)
        {
            target.DragEnter += (_, _) => mark.Visibility = Visibility.Visible;
            target.DragLeave += (_, _) => mark.Visibility = Visibility.Collapsed;
        }
        target.Drop += async (_, e) =>
        {
            Settle();
            if (mark is not null) mark.Visibility = Visibility.Collapsed;
            if (!e.DataView.Contains(StandardDataFormats.Text)) return;
            var at = place;
            var deferral = e.GetDeferral();
            string text;
            try { text = await e.DataView.GetTextAsync(); }
            catch (Exception) { return; }
            finally { deferral.Complete(); }
            Dropped(text, at);
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

    /// Réglages d'un bloc, ouverts sous sa ligne (maquette « Minimal ») : son aide, puis ses réglages.
    private FrameworkElement BlockSettings(MacroDoc doc, int index)
    {
        var block = doc.Blocks[index];
        var body = block.Body;
        var spec = body.Type is { } type ? BlockRegistry.Spec(type) : null;
        var stack = new StackPanel { Spacing = 14 };

        var titles = new StackPanel { Spacing = 3 };
        titles.Children.Add(Label(spec?.Label ?? Loc.T("Bloc inconnu"), 15, Text, semibold: true));
        if (spec?.Help is { Length: > 0 } help) titles.Children.Add(Paragraph(help, 12));
        stack.Children.Add(titles);

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
                // Comme le Mac : « RÉGLAGES » en petites capitales sur un trait fin, les réglages dessous sans cadre.
                var title = SwissLabel(Loc.T("Réglages"), 10.5, Secondary);
                title.Margin = new Thickness(0, 4, 0, 0);
                stack.Children.Add(title);
                stack.Children.Add(Rule(LineColor));
                stack.Children.Add(settings);
            }
        }
        else if (body is not BlockBody.Organize)
            stack.Children.Add(Paragraph(Loc.T("Bloc à régler sur le Mac pour l'instant."), 12));

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
            CornerRadius = new CornerRadius(0),
        };
        box.ValueChanged += (_, e) =>
        {
            if (!double.IsNaN(e.NewValue) && (int)e.NewValue != (int)e.OldValue) set((int)Math.Clamp(e.NewValue, min, max));
        };
        return box;
    }

    /// « Écrire le nom moi-même » choisi pour le plugin (sinon la liste).
    private bool _typingPlugin;
    /// Plugins installés lus dans la Plugin database de FL (instruments, effets), relus avec « Relire la liste ».
    private readonly Dictionary<bool, IReadOnlyList<PluginDatabase.Plugin>> _pluginLists = new();

    private IReadOnlyList<PluginDatabase.Plugin> InstalledPlugins(bool effect)
    {
        if (_demo) return Array.Empty<PluginDatabase.Plugin>();
        if (!_pluginLists.TryGetValue(effect, out var list))
            _pluginLists[effect] = list = PluginDatabase.Installed(_app.PluginRoots, effect);
        return list;
    }

    /// Liste des plugins comme celle du Mac : « À choisir », puis une rubrique par format (« Tous les plugins · VST3 »).
    private static ComboBox PluginChoice(IReadOnlyList<PluginDatabase.Plugin> installed, string value, Action<string> choose)
    {
        var box = MacLook.SwissCombo(new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch, MaxDropDownHeight = 420 });
        var current = PageOptions.PluginPath(value).LastOrDefault(p => p.Length > 0 && p != PageOptions.MorePlugins) ?? "";
        var names = new List<string?>();
        void Add(object content, string? name, bool enabled = true)
        {
            box.Items.Add(new ComboBoxItem { Content = content, IsEnabled = enabled });
            names.Add(name);
        }
        if (current.Length == 0) Add(Loc.T("À choisir"), null, enabled: false);
        else if (!installed.Any(p => p.Name == current)) Add(current, current);
        foreach (var (format, list) in PluginDatabase.ByFormat(installed))
        {
            Add(SwissLabel(Loc.F("Tous les plugins · %@", format), 10, Secondary), null, enabled: false);
            foreach (var name in list) Add(name, name);
        }
        var selected = current.Length == 0 ? 0 : names.IndexOf(current);
        box.SelectedIndex = selected;
        box.SelectionChanged += (_, _) =>
        {
            if (box.SelectedIndex < 0 || box.SelectedIndex == selected || names[box.SelectedIndex] is not { } name) return;
            choose(name);
        };
        return box;
    }

    /// Petit lien souligné sous un réglage (comme les SwissLinkButtonStyle du Mac).
    private static HyperlinkButton SmallLink(string text, Action click)
    {
        var link = new HyperlinkButton { Content = Label(text, 11, Text), Padding = new Thickness(0) };
        link.Click += (_, _) => click();
        return link;
    }

    private static ComboBox Choice(IReadOnlyList<string> items, int selected, Action<int> set)
    {
        var box = MacLook.SwissCombo(new ComboBox { HorizontalAlignment = HorizontalAlignment.Stretch });
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
                // Les actions retirées des listes (08/11) restent montrées pour un bloc qui en a déjà une.
                // Puis les actions faites dans la fenêtre de FL, sans le script (« Consolider la piste dans la Playlist »).
                var actions = FlActions.All.Where(x => !FlActions.Retired.Contains(x.Key) || x.Key == a.ActionKey)
                    .Select(x => (x.Key, Label: Loc.T(x.Label), Detail: Loc.T(x.Detail()), Id: (int?)x.Id))
                    .Concat(LocalFlAction.All.Select(x => (x.Key, Label: Loc.T(x.Label), Detail: Loc.T(x.Detail), Id: (int?)null)))
                    .ToList();
                var at = actions.FindIndex(x => x.Key == a.ActionKey);
                yield return Param(Loc.T("Action"), Choice(actions.Select(x => x.Label).ToList(), at, i =>
                {
                    var info = actions[i];
                    // Sans lien, la touche d'origine de FL quand elle existe (comme les pages).
                    var fallback = info.Id is { } id && LightMode.NativeEquivalent(id) is { } native && MacKeys.FromWindows(native) is { } key
                        ? ActionFallback.Key(key) : ActionFallback.None;
                    Change(doc, d =>
                    {
                        // Le nom du marqueur part avec l'action (gardé dans la note du bloc, comme le Mac).
                        if (MarkerPayload.Of(d.Blocks[index]) is not null && info.Key != "marker") d.Blocks[index].Note = null;
                        d.Blocks[index].Body = new BlockBody.FlAction(info.Key, fallback);
                    });
                }));
                // Sa phrase courte dessous, comme le Mac (« Bascule entre la Playlist et le Mixer ») ; le repli sans lien
                // est choisi tout seul et plus montré (08/11 : « tous ces petits détails-là, tu les enlèves »).
                if (at >= 0)
                {
                    var detail = Paragraph(actions[at].Detail, 11);
                    detail.Margin = new Thickness(0, -6, 0, 0);
                    yield return detail;
                }
                // « Poser un marqueur » (08/11, « mettre un bouton en dessous, nommer le marqueur ») : vide = comme avant.
                if (a.ActionKey == "marker")
                {
                    var markerName = Field(doc.Blocks[index].Note ?? "", NameColorPayload.MaxNameScalars, typed =>
                        Change(doc, d => d.Blocks[index].Note = string.IsNullOrWhiteSpace(typed) ? null : typed));
                    markerName.PlaceholderText = Loc.T("Facultatif");
                    yield return Param(Loc.T("Nom du marqueur"), markerName);
                }
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
            case BlockBody.Drag d:
                // 10/11 (comme le Mac) : où il attrape et où il lâche, puis « Montrer dans FL… » : on le fait une fois.
                if (d.From is ClickTarget.ToLearn || d.To is ClickTarget.ToLearn)
                    yield return Paragraph(Loc.T("Pas encore montré."), 12, Text);
                else
                {
                    yield return Param(Loc.T("Attraper"), Label(TargetText(d.From), 12, Text));
                    yield return Param(Loc.T("Lâcher"), Label(TargetText(d.To), 12, Text));
                }
                var teach = Soft(Loc.T("Montrer dans FL…"), () => LearnDrag(shown => set(new BlockBody.Drag(shown.From, shown.To))));
                teach.HorizontalAlignment = HorizontalAlignment.Left;
                ToolTipService.SetToolTip(teach, Loc.T("Glisse et lâche dans FL."));
                yield return teach;
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
                        // Comme le Mac (09/11) : la liste de tous les plugins installés (Plugin database de FL), par
                        // format ; un plugin choisi est pris par la macro (son .fst déposé, sinon « More plugins… » de
                        // FL), rien n'est ajouté aux listes de FL. « Écrire le nom moi-même » garde le champ d'avant.
                        var effect = PageOptions.Option(id)?.Kind is PageOption.OptionKind.AddMenu { Item: "Effect" };
                        var installed = InstalledPlugins(effect);
                        if (installed.Count > 0 && !_typingPlugin)
                        {
                            yield return Param(Loc.T("Plugin"), PluginChoice(installed, po.Name, name =>
                                set(po with { Name = PageOptions.MorePlugins + PageOptions.PathSeparator + name })));
                            yield return SmallLink(Loc.T("Écrire le nom moi-même"), () => { _typingPlugin = true; RenderSoon(); });
                            yield return SmallLink(Loc.T("Relire la liste"), () => { _pluginLists.Clear(); RenderSoon(); });
                            break;
                        }
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
                        if (installed.Count > 0)
                            yield return SmallLink(Loc.T("Choisir dans la liste de FL"), () => { _typingPlugin = false; RenderSoon(); });
                        else
                            yield return Paragraph(Loc.T("Liste introuvable dans FL : écris le nom."), 11, Secondary);
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
        _notice = problem ?? Loc.T("Clique dans FL.");
        RenderSoon();
    }

    /// « Montrer dans FL… » d'un glisser-déposer : la page attend l'appui puis le relâché dans FL, puis revient devant.
    private void LearnDrag(Action<(ClickTarget From, ClickTarget To)> set)
    {
        if (_demo) return;
        var problem = _app.LearnDrag((shown, why) =>
        {
            _notice = why ?? Loc.T("Glisser-déposer retenu.");
            if (shown is { } both) set(both);
            else RenderSoon();
            _window.Activate();
        });
        _notice = problem ?? Loc.T("Glisse et lâche dans FL.");
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
