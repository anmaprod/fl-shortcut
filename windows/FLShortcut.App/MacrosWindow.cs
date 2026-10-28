// La page Macros sur Windows, construite en code (comme l'Organiser) : la liste des macros (vide ou modèle, état, raccourci,
// modifier, supprimer) et un créateur simple : nom, raccourci, blocs (activer, monter, descendre, retirer, régler).
// La palette ne propose que les blocs faits pour Windows ; un bloc qui ne l'est pas encore (macro venue du Mac) est dit
// dans sa ligne et bloque la macro (son raccourci reste à FL). Toute modification est une copie remise au magasin
// (MacroLibraryStore.Update), enregistrée peu après par l'appli. Les champs de texte s'appliquent à la sortie du champ
// (jamais à chaque lettre : la page est redessinée après chaque changement).
using FLShortcut.App.Services;
using FLShortcut.Core;
using FLShortcut.Core.Macros;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Input;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.System;
using Windows.UI;
using Windows.UI.Core;

namespace FLShortcut.App;

internal sealed class MacrosWindow : Window
{
    private static MacrosWindow? _open;

    /// Couleur des macros (le violet des macros du Mac).
    private static readonly Color Tint = Color.FromArgb(0xFF, 0xAF, 0x52, 0xDE);

    /// Blocs réglables ici (les autres se règlent sur le Mac pour l'instant).
    private static readonly HashSet<BlockType> Editable = new()
    {
        BlockType.Key, BlockType.Delay, BlockType.MenuLetters, BlockType.MenuKey, BlockType.WaitWindow,
        BlockType.WaitWindowClose, BlockType.FlAction, BlockType.OpenPage, BlockType.Organize, BlockType.Stop, BlockType.Comment,
        BlockType.Click, BlockType.MenuBar, BlockType.NameColor, BlockType.PageOption, BlockType.TrackMenu,
        BlockType.DropFile, BlockType.ChooseFile,
    };

    public static void Show(AppController app, Guid? macro = null)
    {
        if (_open is { } shown)
        {
            if (macro is { } id) shown.Edit(id);
            shown.Activate();
            return;
        }
        _open = new MacrosWindow(app, app.Macros, demo: false);
        if (macro is { } m) _open.Edit(m);
        _open.Activate();
    }

    /// Mode photos (CI) : « liste » ou « createur », avec des macros d'exemple en mémoire ; rien n'est enregistré.
    public static MacrosWindow Demo(AppController app, string screen)
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
        var window = new MacrosWindow(app, store, demo: true);
        if (screen == "createur") window.Edit(sample.Id);
        return window;
    }

    private readonly AppController _app;
    private readonly MacroLibraryStore _store;
    private readonly bool _demo;
    private readonly StackPanel _content;
    private Guid? _editing;
    /// Touche en cours de capture : -1 = raccourci de la macro, sinon l'index du bloc « Touche ».
    private int? _capturing;
    private string? _notice;
    private bool _renderQueued;

    private MacrosWindow(AppController app, MacroLibraryStore store, bool demo)
    {
        _app = app;
        _store = store;
        _demo = demo;
        _content = new StackPanel { Spacing = 10 };
        Title = Loc.T("Macros");
        if (!demo && MicaController.IsSupported()) SystemBackdrop = new MicaBackdrop { Kind = MicaKind.Base };
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        var scale = Native.Win32.GetDpiForWindow(hwnd) / 96.0;
        AppWindow.Resize(new Windows.Graphics.SizeInt32((int)(640 * scale), (int)(780 * scale)));

        var root = new Grid { Padding = new Thickness(22, 18, 22, 18), RowSpacing = 14 };
        if (SystemBackdrop is null) root.Background = Res("ApplicationPageBackgroundThemeBrush");
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.Children.Add(Header());
        var scroll = new ScrollViewer { Content = _content, Padding = new Thickness(0, 0, 12, 0) };
        Grid.SetRow(scroll, 1);
        root.Children.Add(scroll);
        Content = root;

        _store.Changed += RenderSoon;
        Closed += (_, _) =>
        {
            _store.Changed -= RenderSoon;
            if (_capturing is not null && !_demo) _app.SetRecording(false);
            if (_open == this) _open = null;
        };
        Render();
    }

    private void Edit(Guid macro)
    {
        StopCapture();
        _editing = macro;
        _notice = null;
        RenderSoon();
    }

    private void Back()
    {
        StopCapture();
        _editing = null;
        _notice = null;
        RenderSoon();
    }

    /// Une copie de la macro modifiée par `change`, remise au magasin.
    private void Change(MacroDoc doc, Action<MacroDoc> change)
    {
        var copy = MacroDrafts.Copy(doc);
        change(copy);
        _store.Update(copy);
    }

    // ---------- Petits morceaux ----------

    private static Brush Res(string key)
    {
        try
        {
            if (Application.Current.Resources[key] is Brush brush) return brush;
        }
        catch (Exception) { }
        return new SolidColorBrush(Microsoft.UI.Colors.Gray);
    }

    private static TextBlock Label(string text, double size = 13, bool bold = false, bool secondary = false, Brush? color = null) => new()
    {
        Text = text,
        FontSize = size,
        TextWrapping = TextWrapping.Wrap,
        FontWeight = bold ? FontWeights.SemiBold : FontWeights.Normal,
        Foreground = color ?? Res(secondary ? "TextFillColorSecondaryBrush" : "TextFillColorPrimaryBrush"),
        VerticalAlignment = VerticalAlignment.Center,
    };

    private static Border Card(UIElement child, bool dim = false) => new()
    {
        Child = child,
        Padding = new Thickness(12),
        CornerRadius = new CornerRadius(8),
        Background = Res("CardBackgroundFillColorDefaultBrush"),
        BorderBrush = new SolidColorBrush(Color.FromArgb(0x59, Tint.R, Tint.G, Tint.B)),
        BorderThickness = new Thickness(1),
        Opacity = dim ? 0.6 : 1,
    };

    private static Button Btn(string text, Action click, bool accent = false)
    {
        var button = new Button { Content = text };
        if (accent) button.Style = (Style)Application.Current.Resources["AccentButtonStyle"];
        button.Click += (_, _) => click();
        return button;
    }

    private static Button IconButton(string glyph, string tip, Action click, bool enabled = true)
    {
        var button = new Button { Content = new FontIcon { Glyph = glyph, FontSize = 12 }, Padding = new Thickness(7, 5, 7, 5), IsEnabled = enabled };
        ToolTipService.SetToolTip(button, tip);
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(button, tip);
        button.Click += (_, _) => click();
        return button;
    }

    private static StackPanel Line(double spacing, params UIElement[] children)
    {
        var line = new StackPanel { Orientation = Orientation.Horizontal, Spacing = spacing };
        foreach (var child in children) line.Children.Add(child);
        return line;
    }

    private static Grid Columns(UIElement left, UIElement right)
    {
        var grid = new Grid { ColumnSpacing = 10 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(left);
        Grid.SetColumn((FrameworkElement)right, 1);
        grid.Children.Add(right);
        return grid;
    }

    private static Grid Badge(string glyph)
    {
        var grid = new Grid { Width = 42, Height = 42 };
        grid.Children.Add(new Ellipse { Fill = new SolidColorBrush(Color.FromArgb(0x33, Tint.R, Tint.G, Tint.B)) });
        grid.Children.Add(new FontIcon { Glyph = glyph, FontSize = 18, Foreground = new SolidColorBrush(Tint) });
        return grid;
    }

    private UIElement Header()
    {
        var text = new StackPanel { Spacing = 2, VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(Label(Loc.T("Macros"), 18, bold: true));
        text.Children.Add(Label(Loc.T("Une macro enchaîne des touches et des actions dans FL Studio, lancée par un raccourci."), 12, secondary: true));
        return Line(14, Badge(""), text);
    }

    private static InfoBar Notice(string text, InfoBarSeverity severity = InfoBarSeverity.Warning) =>
        new() { Message = text, Severity = severity, IsOpen = true, IsClosable = false };

    private static NumberBox Number(double value, double min, double max, double step, Action<int> set)
    {
        var box = new NumberBox
        {
            Value = value, Minimum = min, Maximum = max, SmallChange = step, LargeChange = step * 10, Width = 130,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact,
        };
        box.ValueChanged += (_, e) =>
        {
            if (!double.IsNaN(e.NewValue) && (int)e.NewValue != (int)e.OldValue) set((int)Math.Clamp(e.NewValue, min, max));
        };
        return box;
    }

    private static ComboBox Choice(IReadOnlyList<string> items, int selected, Action<int> set, double width = 220)
    {
        var box = new ComboBox { Width = width };
        foreach (var item in items) box.Items.Add(item);
        box.SelectedIndex = selected;
        box.SelectionChanged += (_, _) =>
        {
            if (box.SelectedIndex >= 0 && box.SelectedIndex != selected) set(box.SelectedIndex);
        };
        return box;
    }

    /// Champ de texte appliqué à sa sortie (ou à Entrée).
    private static TextBox Field(string text, int max, Action<string> commit, double width = 260)
    {
        var box = new TextBox { Text = text, MaxLength = max, Width = width };
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

    private static Grid Param(string label, UIElement editor)
    {
        var grid = new Grid { ColumnSpacing = 10 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(130) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.Children.Add(Label(label, 12, secondary: true));
        Grid.SetColumn((FrameworkElement)editor, 1);
        grid.Children.Add(editor);
        return grid;
    }

    // ---------- Dessin ----------

    /// Redessin juste après l'évènement en cours (jamais pendant celui d'un contrôle qu'il retirerait), une fois.
    private void RenderSoon()
    {
        if (_renderQueued) return;
        _renderQueued = true;
        DispatcherQueue.TryEnqueue(() =>
        {
            _renderQueued = false;
            Render();
        });
    }

    private void Render()
    {
        _content.Children.Clear();
        if (_editing is { } id && _store.Doc(id) is { } doc) Creator(doc);
        else
        {
            _editing = null;
            List();
        }
    }

    private void List()
    {
        if (!_demo && _app.MacroProblem is { } problem) _content.Children.Add(Notice(problem));
        var templates = new MenuFlyout();
        foreach (var template in MacroTemplates.Gallery)
        {
            var item = new MenuFlyoutItem { Text = template.Title };
            ToolTipService.SetToolTip(item, template.Summary);
            item.Click += (_, _) => Edit(_store.Add(MacroDrafts.FromTemplate(template, _store)).Id);
            templates.Items.Add(item);
        }
        _content.Children.Add(Line(8,
            Btn(Loc.T("Nouvelle macro"), () => Edit(_store.Add(MacroDrafts.Empty(_store)).Id), accent: true),
            new DropDownButton { Content = Loc.T("Modèles"), Flyout = templates }));
        if (_store.Macros.Count == 0)
        {
            _content.Children.Add(Label(Loc.T("Aucune macro pour l'instant : crée-en une vide ou pars d'un modèle."), secondary: true));
            return;
        }
        foreach (var doc in _store.Macros) _content.Children.Add(MacroCard(doc));
    }

    private UIElement MacroCard(MacroDoc doc)
    {
        var text = new StackPanel { Spacing = 3 };
        text.Children.Add(Label(DisplayText.Safe(doc.Name, MacroValidation.MaxNameLength), 14, bold: true));
        var shortcut = _demo ? null : _app.MacroShortcut(doc.Id);
        var details = Loc.F("%lld bloc(s)", doc.Blocks.Count) + " · "
            + (shortcut?.Trigger is { } t ? Loc.F("Raccourci : %@", t.ToString()) : Loc.T("Sans raccourci"));
        text.Children.Add(Label(details, 12, secondary: true));
        var issue = Issue(doc);
        text.Children.Add(issue is null
            ? Label(Loc.T("Prête"), 12, color: Res("SystemFillColorSuccessBrush"))
            : Label(issue, 12, color: Res("SystemFillColorCautionBrush")));

        var confirm = new Flyout();
        var sure = new StackPanel { Spacing = 10, MaxWidth = 280 };
        sure.Children.Add(Label(Loc.F("Supprimer « %@ » et son raccourci ?", DisplayText.Safe(doc.Name, 40))));
        sure.Children.Add(Btn(Loc.T("Supprimer"), () =>
        {
            confirm.Hide();
            if (_demo) _store.Remove(doc.Id);
            else _app.DeleteMacro(doc.Id);
        }, accent: true));
        confirm.Content = sure;
        var delete = new Button { Content = Loc.T("Supprimer"), Flyout = confirm };
        var buttons = Line(6, Btn(Loc.T("Modifier"), () => Edit(doc.Id)), delete);
        buttons.VerticalAlignment = VerticalAlignment.Center;
        return Card(Columns(text, buttons));
    }

    /// Problème de la macro sous Windows (compilée avec les règles de Windows), sinon null.
    private string? Issue(MacroDoc doc) => _demo
        ? MacroProgram.Compile(doc, new ValidationContext { PlatformProblem = MacroEffectsWindows.Unsupported }).Problem
        : _app.MacroIssue(doc.Id);

    // ---------- Créateur ----------

    private void Creator(MacroDoc doc)
    {
        _content.Children.Add(Line(8, IconButton("", Loc.T("Retour"), Back), Label(Loc.T("Macros"), 12, secondary: true)));
        _content.Children.Add(Param(Loc.T("Nom"), Field(doc.Name, MacroValidation.MaxNameLength, typed =>
        {
            if (MacroDrafts.CleanName(typed, doc, _store) is { } name) Change(doc, d => d.Name = name);
            else
            {
                _notice = Loc.T("Ce nom est vide ou déjà pris.");
                RenderSoon();
            }
        }, 320)));
        _content.Children.Add(Param(Loc.T("Raccourci"), ShortcutEditor(doc)));
        if (_notice is { } notice) _content.Children.Add(Notice(notice));
        if (Issue(doc) is { } issue) _content.Children.Add(Notice(issue));
        else _content.Children.Add(Notice(Loc.T("Prête"), InfoBarSeverity.Success));

        if (doc.Blocks.Count == 0)
            _content.Children.Add(Label(Loc.T("Aucun bloc : ajoute-en un avec « Ajouter un bloc »."), secondary: true));
        for (var i = 0; i < doc.Blocks.Count; i++) _content.Children.Add(BlockCard(doc, i));
        _content.Children.Add(AddBlockButton(doc));
    }

    private UIElement ShortcutEditor(MacroDoc doc)
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
        return Line(8, capture, IconButton("", Loc.T("Retirer le raccourci"), () =>
        {
            _app.RemoveMacroShortcut(doc.Id);
            RenderSoon();
        }));
    }

    /// Bouton qui capte une combinaison (raccourci de la macro ou bloc « Touche ») ; Échap seul annule.
    private Button CaptureButton(int slot, KeyCombo? combo, string prompt, Action<KeyCombo> done)
    {
        var recording = _capturing == slot;
        var button = new Button
        {
            Content = recording ? Loc.T("Appuie sur tes touches… (Échap pour annuler)") : combo?.ToString() ?? prompt,
            MinWidth = 200,
        };
        if (recording)
        {
            button.BorderBrush = Res("AccentFillColorDefaultBrush");
            button.BorderThickness = new Thickness(2);
        }
        if (!recording)
        {
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
        DispatcherQueue.TryEnqueue(() => button.Focus(FocusState.Programmatic));
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

    private UIElement BlockCard(MacroDoc doc, int index)
    {
        var block = doc.Blocks[index];
        var body = block.Body;
        var spec = body.Type is { } type ? BlockRegistry.Spec(type) : null;
        var enabled = new CheckBox { IsChecked = block.Enabled, MinWidth = 0, VerticalAlignment = VerticalAlignment.Center };
        ToolTipService.SetToolTip(enabled, Loc.T("Activé"));
        enabled.Click += (_, _) => Change(doc, d => d.Blocks[index].Enabled = enabled.IsChecked == true);
        var title = new StackPanel { Spacing = 1, VerticalAlignment = VerticalAlignment.Center };
        title.Children.Add(Label($"{index + 1}. {BlockRegistry.Label(body)}", 13, bold: true));
        if (spec?.Summary(body) is { Length: > 0 } summary) title.Children.Add(Label(summary, 12, secondary: true));
        var head = Columns(Line(8, enabled, title), Line(4,
            IconButton("", Loc.T("Monter"), () => Change(doc, d => MacroDrafts.Move(d.Blocks, index, -1)), index > 0),
            IconButton("", Loc.T("Descendre"), () => Change(doc, d => MacroDrafts.Move(d.Blocks, index, 1)), index < doc.Blocks.Count - 1),
            IconButton("", Loc.T("Retirer"), () => Change(doc, d => d.Blocks.RemoveAt(index)))));

        var stack = new StackPanel { Spacing = 8 };
        stack.Children.Add(head);
        if (MacroEffectsWindows.Unsupported(body) is { } missing)
            stack.Children.Add(Label(missing, 12, color: Res("SystemFillColorCautionBrush")));
        else if (body.Type is { } t && Editable.Contains(t))
        {
            void Set(BlockBody next) => Change(doc, d => d.Blocks[index].Body = next);
            foreach (var editor in Editors(doc, body, index, Set)) stack.Children.Add(editor);
        }
        else if (body is not BlockBody.Organize)
            stack.Children.Add(Label(Loc.T("Bloc à régler sur le Mac pour l'instant."), 12, secondary: true));
        return Card(stack, dim: !block.Enabled);
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
                yield return Param(Loc.T("Durée (ms)"), Number(d.Ms, 0, MacroValidation.MaxDelayMs, 50, n => set(new BlockBody.Delay(n))));
                break;
            case BlockBody.MenuLetters m:
                yield return Param(Loc.T("Lettres"), Field(m.Letters, 8, typed =>
                {
                    var letters = new string(typed.ToLowerInvariant().Where(c => c is >= 'a' and <= 'z').ToArray());
                    if (letters.Length > 0) set(m with { Letters = letters });
                    else RenderSoon();
                }, 120));
                yield return Param(Loc.T("Entrée à la fin"), EnterChoice(m.FinalEnter, e => set(m with { FinalEnter = e })));
                break;
            case BlockBody.MenuKeyPress mk:
                var keys = Enum.GetValues<MenuKey>();
                yield return Param(Loc.T("Touche"), Choice(keys.Select(x => x.Symbol()).ToList(), Array.IndexOf(keys, mk.MenuKey),
                    i => set(mk with { MenuKey = keys[i] }), 160));
                yield return Param(Loc.T("Nombre de fois"), Number(mk.Times, 1, 20, 1, n => set(mk with { Times = n })));
                break;
            case BlockBody.WaitWindow w:
                yield return Param(Loc.T("Attendre"), WindowChoice(w.Window, k => set(w with { Window = k })));
                yield return Param(Loc.T("Au plus (ms)"), Number(w.TimeoutMs, 100, MacroValidation.MaxWaitMs, 100, n => set(w with { TimeoutMs = n })));
                break;
            case BlockBody.WaitWindowClose wc:
                yield return Param(Loc.T("Attendre"), WindowChoice(wc.Window, k => set(wc with { Window = k })));
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
                }, 320));
                yield return Param(Loc.T("Sans lien"), Label(a.Fallback.KeyRef is { } fk && MacKeys.ToWindows(fk) is { } fc
                    ? fc.ToString() : Loc.T("rien (le bloc échoue)"), 12, secondary: true));
                break;
            case BlockBody.OpenPage p:
                var pages = Enum.GetValues<FlPage>();
                yield return Param(Loc.T("Page"), Choice(pages.Select(x => x.Title()).ToList(), p.Page is { } page ? Array.IndexOf(pages, page) : -1,
                    i => set(new BlockBody.OpenPage(pages[i])), 200));
                break;
            case BlockBody.Click c:
                yield return Param(Loc.T("Bouton"), Choice(new[] { Loc.T("Gauche"), Loc.T("Droit") }, c.Button == MouseButton.Right ? 1 : 0,
                    i => set(c with { Button = i == 1 ? MouseButton.Right : MouseButton.Left }), 160));
                yield return Param(Loc.T("Endroit"), Line(8,
                    Label(c.Target is ClickTarget.ToLearn ? Loc.T("à montrer dans FL") : Loc.T("retenu dans FL"), 12, secondary: true),
                    Btn(Loc.T("Montrer dans FL…"), () => LearnClick(target => set(c with { Target = target })))));
                break;
            case BlockBody.MenuBar mb:
                yield return Param(Loc.T("Chemin"), Field(string.Join(" › ", mb.Titles), 200, typed =>
                {
                    var titles = MacroDrafts.MenuPath(typed);
                    if (titles.Count > 0) set(new BlockBody.MenuBar(titles));
                    else RenderSoon();
                }, 360));
                yield return Label(Loc.T("Comme dans FL, séparé par › : File › Export › All playlist tracks › Time selection..."), 12, secondary: true);
                break;
            case BlockBody.NameColor nc:
                yield return Param(Loc.T("Nom"), Field(nc.Name ?? "", NameColorPayload.MaxNameScalars, typed =>
                    set(nc with { Name = typed.Trim().Length == 0 ? null : typed.Trim() }), 240));
                yield return Param(Loc.T("Couleur"), Field(nc.Color is { } color ? "#" + color.Hex : "", 7, typed =>
                {
                    if (typed.Trim().Length == 0) set(nc with { Color = null, Fade = null });
                    else if (RgbColor.FromHex(typed.Trim()) is { } parsed) set(nc with { Color = parsed });
                    else RenderSoon();
                }, 120));
                yield return Param(Loc.T("Dégradé jusqu'à"), Field(nc.Fade is { } fade ? "#" + fade.Hex : "", 7, typed =>
                {
                    if (typed.Trim().Length == 0) set(nc with { Fade = null });
                    else if (RgbColor.FromHex(typed.Trim()) is { } parsed) set(nc with { Fade = parsed });
                    else RenderSoon();
                }, 120));
                break;
            case BlockBody.PageOption po:
            {
                // Les options de la page ouverte juste au-dessus (comme sur le Mac), sauf celles pas encore faites ici.
                var above = doc.Blocks.Take(index).Select(b => b.Body).OfType<BlockBody.OpenPage>().LastOrDefault()?.Page;
                if (above is not { } shown)
                {
                    yield return Label(Loc.T("Ajoute « Ouvrir une page de FL » juste au-dessus, puis choisis l'option."), 12, secondary: true);
                    break;
                }
                var options = PageOptions.Options(shown)
                    .Where(o => MacroEffectsWindows.Unsupported(new BlockBody.PageOption(o.Id, "")) is null).ToList();
                yield return Param(Loc.T("Option"), Choice(options.Select(o => o.Label).ToList(), options.FindIndex(o => o.Id == po.Option),
                    i => set(new BlockBody.PageOption(options[i].Id, options[i].Id == po.Option ? po.Name : "")), 320));
                if (po.Option is { } id && PageOptions.FieldOf(id) is { } field)
                {
                    if (field == PageField.Plugin)
                    {
                        // Un plugin hors des favoris : pris dans « More plugins… » de FL, rien n'est ajouté à ses listes.
                        var outside = PageOptions.FromPluginList(po.Name);
                        yield return Param(Loc.T("Plugin"), Field(outside ?? po.Name, PageOptions.MaxName, typed =>
                            set(po with { Name = outside is not null && typed.Trim().Length > 0
                                ? PageOptions.MorePlugins + PageOptions.PathSeparator + typed.Trim() : typed.Trim() }), 240));
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
                        Field(po.Name, PageOptions.MaxName, typed => set(po with { Name = typed.Trim() }), 240));
                }
                break;
            }
            case BlockBody.TrackMenu tm:
            {
                var choices = MacroTemplates.TrackMenuChoices;
                var chosen = choices.ToList().FindIndex(c => c.Letters == tm.Letters);
                yield return Param(Loc.T("Élément"), Choice(choices.Select(c => c.Name).ToList(), chosen, i =>
                    set(new BlockBody.TrackMenu(choices[i].Letters, choices[i].Labels, tm.Target, choices[i].Enter)), 320));
                yield return Param(Loc.T("Piste"), Choice(new[] { Loc.T("Dernière piste cliquée dans FL"), Loc.T("Là où est le pointeur") },
                    tm.Target == TrackTarget.Cursor ? 1 : 0, i => set(tm with { Target = i == 1 ? TrackTarget.Cursor : TrackTarget.LastClicked }), 260));
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
                    set(new BlockBody.Stop(typed.Trim().Length == 0 ? null : typed.Trim())), 320));
                break;
            case BlockBody.Comment c:
                yield return Param(Loc.T("Texte"), Field(c.Text, 200, typed => set(new BlockBody.Comment(typed.Trim())), 320));
                break;
        }
    }

    /// Nom du preset choisi (jamais son chemin entier) et « Choisir… » : la boîte s'ouvre dans Image-Line › FL Studio ›
    /// Presets › Mixer presets (comme sur le Mac), sinon le dossier le plus proche qui existe.
    private UIElement PresetPicker(string path, Action<string> set)
    {
        var shown = path.Length == 0 ? Loc.T("à choisir") : System.IO.Path.GetFileName(path);
        return Line(8, Label(shown, 12, secondary: path.Length == 0), Btn(Loc.T("Choisir…"), () =>
        {
            if (_demo) return;
            var documents = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
            var start = new[] { @"Image-Line\FL Studio\Presets\Mixer presets", @"Image-Line\FL Studio\Presets", @"Image-Line\FL Studio", "Image-Line" }
                .Select(p => System.IO.Path.Combine(documents, p)).FirstOrDefault(Directory.Exists) ?? documents;
            var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
            if (Native.FileDialogs.PickFile(hwnd, Loc.T("Choisis un état de piste du Mixer (.fst)"), Loc.T("État de piste du Mixer"), "fst", start)
                is { } chosen) set(chosen);
        }));
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
            Activate();
        });
        _notice = problem ?? Loc.T("Clique dans FL à l'endroit voulu (Échap pour annuler).");
        RenderSoon();
    }

    private static ComboBox WindowChoice(WindowKind kind, Action<WindowKind> set) =>
        Choice(new[] { Loc.T("Boîte de dialogue"), Loc.T("Menu") }, kind == WindowKind.Dialog ? 0 : 1,
            i => set(i == 0 ? WindowKind.Dialog : WindowKind.Menu), 200);

    private static ComboBox EnterChoice(EnterPolicy current, Action<EnterPolicy> set)
    {
        var options = new List<(string Label, EnterPolicy Policy)>
        {
            (Loc.T("Jamais"), EnterPolicy.Never), (Loc.T("Si besoin"), EnterPolicy.IfNeeded), (Loc.T("Toujours"), EnterPolicy.Always),
        };
        if (current.Mode == "learned") options.Add((Loc.T("Apprise"), current));
        var at = options.FindIndex(o => o.Policy.Mode == current.Mode);
        return Choice(options.Select(o => o.Label).ToList(), at, i => set(options[i].Policy), 160);
    }

    private UIElement AddBlockButton(MacroDoc doc)
    {
        var menu = new MenuFlyout();
        foreach (var (category, specs) in MacroDrafts.Palette(MacroEffectsWindows.Unsupported))
        {
            var sub = new MenuFlyoutSubItem { Text = category.Label() };
            foreach (var spec in specs.Where(s => Editable.Contains(s.Type)))
            {
                var item = new MenuFlyoutItem { Text = spec.Label };
                ToolTipService.SetToolTip(item, spec.Help);
                item.Click += (_, _) => Change(doc, d => d.Blocks.Add(new Block(spec.Default())));
                sub.Items.Add(item);
            }
            if (sub.Items.Count > 0) menu.Items.Add(sub);
        }
        return new DropDownButton { Content = Loc.T("Ajouter un bloc"), Flyout = menu, HorizontalAlignment = HorizontalAlignment.Left };
    }

    /// Bibliothèque d'exemple du mode photos : en mémoire, jamais écrite.
    private sealed class DemoStorage : IMacroLibraryStorage
    {
        public byte[]? Read() => null;
        public void Write(byte[] data) { }
        public string Backup(byte[] data, string label) => label;
    }
}
