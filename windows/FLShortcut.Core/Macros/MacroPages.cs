// Blocs « Ouvrir une page de FL » et « Cliquer sur… » : on choisit d'abord la page (Playlist, Channel Rack, Mixer…),
// puis une option de cette page dans une liste (armer la piste, ajouter un instrument, un raccourci de FL…). Miroir de
// Sources/FLShortcut/MacroPages.swift : mêmes identifiants (« mixer.armon », « channelRack.fl.channelRack.c »), pour
// qu'une macro passe d'un Mac à un PC.
// - La page n'est ouverte que si elle n'est pas déjà devant (lien avec FL), sinon par sa touche de FL (F5, F6, F7, F9,
//   Alt+F8).
// - Une option qui demande une valeur (plugin, numéro du canal, nouveau nom) la garde dans le texte « name » du bloc.
namespace FLShortcut.Core.Macros;

/// Une option d'une page de FL (« Cliquer sur… »).
public sealed record PageOption(string Id, FlPage Page, string Label, PageOption.OptionKind Kind)
{
    public abstract record OptionKind
    {
        /// Action du script de FL (le lien), avec sa touche de FL en repli.
        public sealed record Action(string Key) : OptionKind;
        /// Raccourci d'origine de FL dans cette page.
        public sealed record Shortcut(KeyRef Key) : OptionKind;
        /// Élément du menu Add de FL, suivi du nom choisi (plugin).
        public sealed record AddMenu(string Item) : OptionKind;
        /// Mute ou solo d'un canal du Channel rack, par son numéro.
        public sealed record ChannelToggle(bool Solo) : OptionKind;
        /// Nouveau nom de la piste sélectionnée.
        public sealed record Rename : OptionKind;
        /// Bouton « Arrangement » de la Playlist, puis cette ligne de son menu ; null : l'arrangement écrit dans le bloc.
        public sealed record Arrangement(string? Item) : OptionKind;
    }

    /// Ce que l'option demande en plus, écrit dans le bloc (son texte « name »).
    public PageField? Field => Kind switch
    {
        OptionKind.AddMenu => PageField.Plugin,
        OptionKind.ChannelToggle => PageField.Channel,
        OptionKind.Rename => PageField.Name,
        OptionKind.Arrangement { Item: null } => PageField.Arrangement,
        _ => null,
    };
}

public enum PageField { Plugin, Channel, Name, Arrangement }

public static class PageOptions
{
    /// Longueur maximale du nom d'un plugin.
    public const int MaxName = 80;
    /// Numéro de canal le plus grand accepté (« Mute d'un canal »).
    public const int MaxChannel = 999;
    /// Sous-menus du menu Add dans le nom d'un plugin : « Fruity › Fruity Limiter ».
    public const string PathSeparator = " › ";
    /// Profondeur d'un chemin de menu de FL (titre du menu compris), comme MenuBarAX.maxDepth du Mac.
    public const int MaxMenuDepth = 5;

    /// Raccourcis remplacés par une option qui demande sa valeur : les touches 1 à 0 (⌘ pour le solo) par « Mute
    /// d'un canal », F2 par « Renommer la piste ». Plus proposés, toujours compris (macros déjà faites).
    public static readonly IReadOnlySet<string> Replaced = BuildReplaced();

    private static HashSet<string> BuildReplaced()
    {
        var digits = new[] { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" };
        var rack = digits.SelectMany(d => new[] { $"channelRack.fl.channelRack.{d}", $"channelRack.fl.channelRack.cmd-{d}" });
        return rack.Append("mixer.fl.mixer.f2").ToHashSet();
    }

    /// Rubrique du catalogue des raccourcis de la page.
    public static FlSection Section(this FlPage page) => page switch
    {
        FlPage.Playlist => FlSection.Playlist,
        FlPage.ChannelRack => FlSection.ChannelRack,
        FlPage.PianoRoll => FlSection.PianoRoll,
        FlPage.Mixer => FlSection.Mixer,
        _ => FlSection.Browser,
    };

    /// Touche de FL qui affiche la page (F5, F6, F7, F9, Alt+F8), en notation du Mac.
    public static KeyRef? NativeKey(this FlPage page) =>
        FlActions.IdForKey(page.ActionKey()) is { } id && LightMode.NativeEquivalent(id) is { } combo ? MacKeys.FromWindows(combo) : null;

    /// Bloc qui la met devant : le lien avec FL, sinon sa touche de FL.
    public static BlockBody OpenBody(this FlPage page) =>
        new BlockBody.FlAction(page.ActionKey(), page.NativeKey() is { } key ? ActionFallback.Key(key) : ActionFallback.None);

    /// Options de la page : les plus utiles d'abord (ajouter un plugin, armer…), puis les raccourcis de FL de la page.
    /// `all` : avec les raccourcis remplacés (validation, macros déjà faites).
    public static List<PageOption> Options(FlPage page, bool all = false)
    {
        var output = new List<PageOption>();
        void Add(string id, string label, PageOption.OptionKind kind) => output.Add(new PageOption($"{page.Raw()}.{id}", page, label, kind));
        switch (page)
        {
            case FlPage.ChannelRack:
                Add("addInstrument", Loc.T("Ajouter un instrument (VST, plugin…)"), new PageOption.OptionKind.AddMenu("Channel"));
                Add("chMute", Loc.T("Mute d'un canal (son numéro)"), new PageOption.OptionKind.ChannelToggle(false));
                Add("chSolo", Loc.T("Solo d'un canal (son numéro)"), new PageOption.OptionKind.ChannelToggle(true));
                Add("chnext", Loc.T("Instrument suivant"), new PageOption.OptionKind.Action("chnext"));
                Add("chprev", Loc.T("Instrument précédent"), new PageOption.OptionKind.Action("chprev"));
                Add("presetnext", Loc.T("Preset suivant"), new PageOption.OptionKind.Action("presetnext"));
                Add("presetprev", Loc.T("Preset précédent"), new PageOption.OptionKind.Action("presetprev"));
                break;
            case FlPage.Mixer:
                Add("addEffect", Loc.T("Ajouter un effet sur la piste (plugin)"), new PageOption.OptionKind.AddMenu("Effect"));
                Add("rename", Loc.T("Renommer la piste"), new PageOption.OptionKind.Rename());
                Add("armon", Loc.T("Armer la piste"), new PageOption.OptionKind.Action("armon"));
                Add("arm", Loc.T("Armer ou désarmer la piste"), new PageOption.OptionKind.Action("arm"));
                Add("mute", Loc.T("Mute de la piste (coupe ou remet le son)"), new PageOption.OptionKind.Action("mute"));
                Add("solo", Loc.T("Solo de la piste (met ou retire le solo)"), new PageOption.OptionKind.Action("solo"));
                Add("unsolo", Loc.T("Retirer tous les solos"), new PageOption.OptionKind.Action("unsolo"));
                Add("bypass", Loc.T("Couper les effets de la piste (bypass)"), new PageOption.OptionKind.Action("bypass"));
                Add("trnext", Loc.T("Piste suivante"), new PageOption.OptionKind.Action("trnext"));
                Add("trprev", Loc.T("Piste précédente"), new PageOption.OptionKind.Action("trprev"));
                Add("volup", Loc.T("Monter le volume de la piste"), new PageOption.OptionKind.Action("volup"));
                Add("voldn", Loc.T("Baisser le volume de la piste"), new PageOption.OptionKind.Action("voldn"));
                Add("mono", Loc.T("Master en mono"), new PageOption.OptionKind.Action("mono"));
                break;
            case FlPage.Playlist:
                Add("marker", Loc.T("Poser un marqueur"), new PageOption.OptionKind.Action("marker"));
                Add("snap", Loc.T("Grille suivante"), new PageOption.OptionKind.Action("snap"));
                // Le menu « Arrangement » de la Playlist.
                Add("arrangementGo", Loc.T("Arrangement : ouvrir un arrangement (son nom)"), new PageOption.OptionKind.Arrangement(null));
                Add("arrangementAdd", Loc.T("Arrangement : en ajouter un (Add one)"), new PageOption.OptionKind.Arrangement("Add one"));
                Add("arrangementClone", Loc.T("Arrangement : le dupliquer (Clone)"), new PageOption.OptionKind.Arrangement("Clone"));
                Add("arrangementRename", Loc.T("Arrangement : le renommer (Rename)"), new PageOption.OptionKind.Arrangement("Rename"));
                Add("arrangementDelete", Loc.T("Arrangement : le supprimer (Delete)"), new PageOption.OptionKind.Arrangement("Delete"));
                Add("arrangementMerge", Loc.T("Arrangement : fusionner avec… (Merge with, sous-menu ouvert)"),
                    new PageOption.OptionKind.Arrangement("Merge with"));
                break;
            case FlPage.PianoRoll:
                Add("quant", Loc.T("Quantize rapide"), new PageOption.OptionKind.Action("quant"));
                Add("snap", Loc.T("Grille suivante"), new PageOption.OptionKind.Action("snap"));
                break;
        }
        // Raccourcis d'origine de FL dans cette page (touche de FL, toujours la même).
        var section = page.Section();
        foreach (var entry in FlCatalog.Native)
        {
            if (entry.Section != section) continue;
            var id = $"{page.Raw()}.{entry.Id}";
            if (!all && Replaced.Contains(id)) continue;
            output.Add(new PageOption(id, page, entry.Title, new PageOption.OptionKind.Shortcut(entry.Key)));
        }
        return output;
    }

    private static readonly Lazy<(HashSet<string> All, HashSet<string> Link, Dictionary<string, PageField> Fields)> Known = new(() =>
    {
        var all = Enum.GetValues<FlPage>().SelectMany(p => Options(p, all: true)).ToList();
        var link = all.Where(o => o.Kind is PageOption.OptionKind.Action or PageOption.OptionKind.ChannelToggle or PageOption.OptionKind.Rename);
        return (all.Select(o => o.Id).ToHashSet(), link.Select(o => o.Id).ToHashSet(),
                all.Where(o => o.Field is not null).ToDictionary(o => o.Id, o => o.Field!.Value));
    });

    public static bool IsKnown(string id) => Known.Value.All.Contains(id);
    public static bool UsesLink(string id) => Known.Value.Link.Contains(id);
    /// Option qui clique dans FL (le menu « Arrangement » de la Playlist).
    public static bool Clicks(string id) => id.StartsWith("playlist.arrangement", StringComparison.Ordinal);
    public static PageField? FieldOf(string id) => Known.Value.Fields.TryGetValue(id, out var f) ? f : null;

    /// Page d'une option, d'après son identifiant.
    public static FlPage? PageOf(string id) => FlPages.FromRaw(id.Split('.', 2)[0]);

    public static PageOption? Option(string id) => PageOf(id) is { } page ? Options(page, all: true).FirstOrDefault(o => o.Id == id) : null;

    /// Numéro de canal écrit dans le bloc (1 à `MaxChannel`), sinon null.
    public static int? Channel(string text) =>
        int.TryParse(text.Trim(), System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var n)
        && n is >= 1 and <= MaxChannel ? n : null;

    /// Touche 1 à 0 de FL (Ctrl pour le solo) du canal `number`, jusqu'au canal 10.
    public static KeyRef? ChannelKey(int number, bool solo)
    {
        if (number is < 1 or > 10) return null;
        var digit = number == 10 ? "0" : number.ToString(System.Globalization.CultureInfo.InvariantCulture);
        return Option($"channelRack.fl.channelRack.{(solo ? "cmd-" : "")}{digit}")?.Kind is PageOption.OptionKind.Shortcut s ? s.Key : null;
    }

    /// Élément du menu Add de FL qui ouvre la liste de tous ses plugins (fenêtre « Select plugin ») ; aussi le premier
    /// élément du nom d'un plugin choisi hors des favoris (« More plugins... › Serum 2 »), comme sur le Mac.
    public const string MorePlugins = "More plugins...";

    /// Nom du plugin à prendre dans « More plugins… », null pour un favori du menu Add.
    public static string? FromPluginList(string name) =>
        PluginPath(name) is [MorePlugins, { Length: > 0 } plugin] ? plugin : null;

    /// Chemin dans le menu Add › Channel ou Effect : « Fruity › Fruity Limiter » → [Fruity, Fruity Limiter].
    public static List<string> PluginPath(string name) => name.Split('›').Select(p => p.Trim()).ToList();

    /// Ce que joue l'option : une action du lien, la touche de FL, ou le menu Add de FL avec le nom choisi. null : jouée
    /// par l'effet lui-même (canal par son numéro, nom de la piste, menu Arrangement).
    public static BlockBody? Body(PageOption option, string name)
    {
        switch (option.Kind)
        {
            case PageOption.OptionKind.Action a:
            {
                // Armer sans le lien : le menu de la piste (n'éteint jamais) ; sinon la touche de FL, si elle existe.
                var native = FlActions.IdForKey(a.Key) is { } id && LightMode.NativeEquivalent(id) is { } combo ? MacKeys.FromWindows(combo) : null;
                var fallback = a.Key == "armon" ? ActionFallback.TrackMenuArm
                    : native is not null ? ActionFallback.Key(native) : ActionFallback.None;
                return new BlockBody.FlAction(a.Key, fallback);
            }
            case PageOption.OptionKind.Shortcut s:
                return new BlockBody.Key(s.Key, 1);
            case PageOption.OptionKind.AddMenu m:
            {
                // Choix d'une ancienne version du Mac (« FL Shortcuts › Serum 2 ») : ce dossier de favoris n'existe plus
                // (FL Shortcuts ne touche plus aux listes de FL), le plugin seul.
                var path = PluginPath(name);
                if (path.Count > 1 && path[0] == "FL Shortcuts") path.RemoveAt(0);
                return new BlockBody.MenuBar(new[] { "Add", m.Item }.Concat(path).ToList());
            }
            default:
                return null;
        }
    }

    /// Valeur du bloc pour son option : null si elle convient, sinon ce qu'il faut écrire.
    public static string? ValueProblem(PageField field, string text)
    {
        var trimmed = text.Trim();
        switch (field)
        {
            case PageField.Plugin:
            {
                var path = PluginPath(trimmed);
                if (trimmed.Length == 0 || trimmed.Length > MaxName || path.Any(p => p.Length == 0) || path.Count > MaxMenuDepth - 2)
                    return Loc.T("choisis le plugin à ajouter (comme dans le menu Add de FL).");
                break;
            }
            case PageField.Channel:
                if (Channel(trimmed) is null) return Loc.F("écris le numéro du canal (1 à %lld).", MaxChannel);
                break;
            case PageField.Name:
                if (trimmed.Length == 0) return Loc.T("écris le nouveau nom de la piste.");
                if (NameColorPayload.NameProblem(trimmed) is { } problem) return problem;
                break;
            case PageField.Arrangement:
                if (trimmed.Length == 0 || trimmed.Length > MaxName)
                    return Loc.T("écris le nom de l'arrangement, comme dans FL (Arrangement 2…).");
                break;
        }
        return null;
    }

    /// Pur (testé) : première option dont la page n'est pas celle ouverte au-dessus (chemin du bloc « 3.2 », numéroté
    /// comme la validation : « sinon » poursuit après « alors »), avec la page ouverte au-dessus.
    public static (string Path, FlPage? Page)? Misplaced(IReadOnlyList<Block> blocks, string prefix = "", int offset = 0, FlPage? inherited = null)
    {
        var page = inherited;
        for (var i = 0; i < blocks.Count; i++)
        {
            var block = blocks[i];
            var path = MacroValidation.Path(prefix, offset + i + 1);
            if (block.Body is BlockBody.PageOption { Option: { } id } && PageOf(id) is { } own && own != page) return (path, page);
            foreach (var (start, child) in MacroValidation.ChildLists(block.Body))
                if (Misplaced(child, path, start, page) is { } found) return found;
            if (block.Body is BlockBody.OpenPage open) page = open.Page;
        }
        return null;
    }

    /// Message de la validation pour une option hors de sa page.
    public static string MisplacedMessage((string Path, FlPage? Page) wrong) => wrong.Page is { } page
        ? Loc.F("Étape %@ : cette option n'est pas dans %@, la page ouverte au-dessus : choisis-en une de cette page.", wrong.Path, page.Title())
        : Loc.F("Étape %@ : ajoute « Ouvrir une page de FL » juste au-dessus et choisis la page de cette option.", wrong.Path);
}
