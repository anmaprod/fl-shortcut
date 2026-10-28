// Bibliothèque des macros (miroir de MacroLibraryStore, Sources/FLShortcut/MacroLibraryStore.swift), sans fenêtre ni
// fil : l'appli l'appelle depuis son fil principal et décide quand écrire (SaveNow, après un court délai).
// - Lecture au lancement : fichier illisible, plus récent ou en partie illisible → copie datée gardée, jamais écrasé
//   sans copie ; fichier inaccessible, ou copie impossible → plus jamais réécrit pendant ce lancement, et `Problem` le
//   dit (page Macros, créateur) : jamais de macro perdue sans prévenir.
// - Copie « macros.precedente.json » une fois par lancement, avant la première écriture ; gardée à faire tant
//   qu'elle échoue (le fichier n'est alors jamais remplacé).
// - Programmes compilés en cache par (id, révision) : un changement ne recompile que la macro modifiée.
namespace FLShortcut.Core.Macros;

/// Où vit la bibliothèque (Windows : %APPDATA%\FL Shortcuts\macros.json ; essais : en mémoire).
public interface IMacroLibraryStorage
{
    /// null : aucune macro encore. Exception : fichier présent mais inaccessible (droits, lien…).
    byte[]? Read();
    void Write(byte[] data);
    /// Copie de secours ; renvoie le nom du fichier créé.
    string Backup(byte[] data, string label);
}

public sealed class MacroLibraryStore
{
    /// Copie du fichier tel qu'il était au lancement, faite avant la première écriture.
    public const string PreviousLabel = "precedente";

    private readonly IMacroLibraryStorage _storage;
    private readonly List<MacroDoc> _macros = new();
    /// Contenu lu au lancement, copié une seule fois avant la première écriture.
    private byte[]? _previous;
    private readonly Dictionary<Guid, MacroProgram> _programs = new();

    public IReadOnlyList<MacroDoc> Macros => _macros;
    public string? LoadWarning { get; private set; }
    public string? SaveError { get; private set; }
    /// Fichier présent mais inaccessible, ou copie de secours impossible : jamais réécrit.
    public bool WritesDisabled { get; private set; }
    /// Bibliothèque illisible, inaccessible, en partie illisible ou plus récente au lancement : jamais envoyée à la
    /// place de la sauvegarde du compte tant qu'elle n'a pas été remplacée.
    public bool LoadIncomplete { get; private set; }
    /// Un changement attend d'être écrit (SaveNow).
    public bool HasUnsavedChanges { get; private set; }
    /// Après chaque changement (index des raccourcis, interface, écriture différée).
    public event Action? Changed;

    public static string WritesDisabledMessage =>
        Loc.T("Tes macros ne peuvent pas être enregistrées : le fichier n'a pas pu être copié avant d'être remplacé.");

    /// Ce que l'utilisateur doit savoir : jamais de macro perdue sans prévenir.
    public string? Problem => SaveError ?? LoadWarning ?? (WritesDisabled ? WritesDisabledMessage : null);

    public MacroLibraryStore(IMacroLibraryStorage storage)
    {
        _storage = storage;
        Load();
    }

    private void Load()
    {
        byte[]? data;
        try
        {
            data = _storage.Read();
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            WritesDisabled = true;
            LoadIncomplete = true;
            LoadWarning = Loc.F("Bibliothèque de macros inaccessible (%@) : elle n'est pas modifiée.", e.Message);
            return;
        }
        if (data is null) return;                                  // aucune macro encore
        try
        {
            var decoded = MacroLibraryCodec.Decode(data);
            _macros.AddRange(decoded.Macros);
            // « Tout organiser » s'appelle « Organiser » (retour du propriétaire) : la macro faite avec le modèle aussi.
            var renamed = Loc.T("Organiser");
            foreach (var m in _macros.Where(m => m.Origin is { Kind: "template", Template: "organize" }
                                                 && m.Name is "Tout organiser" or "Organize everything"))
                if (_macros.All(o => o.Name != renamed)) m.Name = renamed;
            _previous = data;
            var notes = new List<string>();
            LoadIncomplete = decoded.Dropped > 0 || decoded.Version > MacroLibraryCodec.CurrentVersion;
            if (decoded.Version > MacroLibraryCodec.CurrentVersion)
            {
                var name = KeepCopy(data, "plus-recente");
                notes.Add(Loc.T("Bibliothèque d'une version plus récente de FL Shortcuts")
                          + (name is null ? Loc.T(", copie impossible : elle n'est pas modifiée.") : Loc.F(" (copie : %@).", name)));
            }
            if (decoded.Dropped > 0)
            {
                var name = KeepCopy(data, "partielle");
                notes.Add(Loc.F("%lld macro(s) illisible(s) ignorée(s)", decoded.Dropped)
                          + (name is null ? Loc.T(", copie impossible : le fichier n'est pas modifié.") : Loc.F(" (copie : %@).", name)));
            }
            if (notes.Count > 0) LoadWarning = string.Join(" ", notes);
        }
        catch (MacroLibraryCodec.Failure)
        {
            LoadIncomplete = true;
            LoadWarning = KeepCopy(data, "illisible") is { } name
                ? Loc.F("Le fichier des macros était illisible : une copie datée a été gardée dans le dossier FL Shortcuts (%@).", name)
                : Loc.T("Le fichier des macros est illisible et n'a pas pu être copié : il n'est pas modifié, tes nouvelles macros ne seront pas enregistrées.");
        }
    }

    /// Copie de secours avant tout remplacement ; impossible : plus aucune écriture (jamais écrasé sans copie).
    private string? KeepCopy(byte[] data, string label)
    {
        try { return _storage.Backup(data, label); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            WritesDisabled = true;
            return null;
        }
    }

    // ---------- Lecture ----------

    public MacroDoc? Doc(Guid id) => _macros.FirstOrDefault(m => m.Id == id);

    /// « Nouvelle macro », puis « Nouvelle macro 2 »… (noms uniques, 60 caractères au plus).
    public string UniqueName(string @base)
    {
        var root = new string(@base.Take(MacroValidation.MaxNameLength - 4).ToArray()).Trim();
        var taken = _macros.Select(m => m.Name).ToHashSet();
        if (!taken.Contains(root)) return root.Length == 0 ? Loc.T("Macro") : root;
        var n = 2;
        while (taken.Contains($"{root} {n}")) n++;
        return $"{root} {n}";
    }

    /// Programmes compilés (validés), en cache par (id, révision). `context` : dossier personnel des essais.
    public IReadOnlyDictionary<Guid, MacroProgram> Programs(ValidationContext? context = null)
    {
        var fresh = new Dictionary<Guid, MacroProgram>();
        foreach (var doc in _macros)
            fresh[doc.Id] = _programs.TryGetValue(doc.Id, out var hit) && hit.Revision == doc.Revision
                ? hit
                : MacroProgram.Compile(doc, context);
        _programs.Clear();
        foreach (var kv in fresh) _programs[kv.Key] = kv.Value;
        return fresh;
    }

    // ---------- Modifications ----------

    /// Ajoute une macro (id déjà pris : un neuf). `index` : place dans la liste (annulation d'une suppression).
    public MacroDoc Add(MacroDoc doc, int? index = null)
    {
        if (_macros.Any(m => m.Id == doc.Id)) doc.Id = Guid.NewGuid();
        if (index is { } i && i >= 0 && i <= _macros.Count) _macros.Insert(i, doc);
        else _macros.Add(doc);
        OnChanged();
        return doc;
    }

    /// Enregistre une version modifiée : révision + 1 si le contenu a changé (clé du cache). null si elle n'existe plus.
    public MacroDoc? Update(MacroDoc doc)
    {
        var i = _macros.FindIndex(m => m.Id == doc.Id);
        if (i < 0) return null;
        var old = _macros[i];
        if (SameContent(old, doc)) return old;
        doc.Revision = old.Revision + 1;
        _macros[i] = doc;
        OnChanged();
        return doc;
    }

    /// Retire une macro ; renvoie ce qu'il faut pour l'annuler.
    public (MacroDoc Doc, int Index)? Remove(Guid id)
    {
        var i = _macros.FindIndex(m => m.Id == id);
        if (i < 0) return null;
        var doc = _macros[i];
        _macros.RemoveAt(i);
        OnChanged();
        return (doc, i);
    }

    /// Remplace toute la bibliothèque (sauvegarde du compte reprise, déconnexion).
    public void ReplaceAll(IEnumerable<MacroDoc> docs)
    {
        LoadIncomplete = false;
        _macros.Clear();
        _macros.AddRange(docs);
        OnChanged();
    }

    /// Copie datée de la bibliothèque (avant de la remplacer par la sauvegarde du compte).
    public string? KeepCurrentCopy(string label)
    {
        try { return _storage.Backup(MacroLibraryCodec.Encode(_macros), label); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return null; }
    }

    /// Même contenu (nom, blocs, variables, origine, format) : rien à enregistrer.
    public static bool SameContent(MacroDoc a, MacroDoc b)
    {
        var ja = a.ToJson();
        var jb = b.ToJson();
        foreach (var key in new[] { "id", "revision" })
        {
            ja.Remove(key);
            jb.Remove(key);
        }
        return ja.ToJsonString() == jb.ToJsonString();
    }

    private void OnChanged()
    {
        if (!WritesDisabled) HasUnsavedChanges = true;
        Changed?.Invoke();
    }

    // ---------- Sauvegarde ----------

    /// Écrit maintenant ce qui a changé (après un court délai, à la fermeture de l'appli, essais).
    public void SaveNow()
    {
        if (WritesDisabled || !HasUnsavedChanges) return;
        if (_previous is { } old)
        {
            try
            {
                _storage.Backup(old, PreviousLabel);
                _previous = null;
            }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException)
            {
                WritesDisabled = true;
                HasUnsavedChanges = false;
                SaveError = Loc.F("Tes macros ne peuvent pas être enregistrées : la copie de secours du fichier a échoué (%@). Le fichier n'est pas remplacé.", e.Message);
                return;
            }
        }
        try
        {
            _storage.Write(MacroLibraryCodec.Encode(_macros));
            HasUnsavedChanges = false;
            SaveError = null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            SaveError = Loc.F("Tes macros ne peuvent pas être enregistrées : %@", e.Message);
        }
    }
}
