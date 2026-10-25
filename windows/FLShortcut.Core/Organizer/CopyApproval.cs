// Validation de la copie rangée (demande du propriétaire, 24/10). L'Organiser range toujours dans une copie
// « <nom>_2.flp » à côté du projet. Une fois l'Organiser fermé, la prochaine fois qu'on rouvre FL Shortcuts, il
// demande si l'on valide cette version : « Valider » (l'original à la Corbeille, la version organisée prend son nom),
// « Retourner en arrière » (la version organisée à la Corbeille, FL rouvre le projet d'avant), « Plus tard ». Rien
// n'est jamais supprimé pour de bon (Corbeille) ; un renommage raté remet l'original à sa place. Les chemins restent
// dans les réglages de l'appli, jamais dans le journal. Miroir de Sources/FLShortcut/OrganizerCopyApproval.swift.
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace FLShortcut.Core.Organizer;

/// Une copie rangée en attente : le projet d'origine, la version organisée, et les versions organisées d'avant du même
/// projet (rangé de nouveau sans avoir répondu), qui partent à la Corbeille quelle que soit la réponse.
public sealed record PendingCopy(string Original, string Copy, IReadOnlyList<string> Older, DateTimeOffset Date)
{
    public string Id => Copy;
}

/// Les fichiers (des faux dans les tests). `Trash` rend la place du fichier dans la Corbeille (null : inconnue).
public sealed class CopyFiles
{
    public Func<string, bool> Exists { get; init; } = File.Exists;
    public required Func<string, string?> Trash { get; init; }
    public Action<string, string> Move { get; init; } = (from, to) => File.Move(from, to);
}

public enum CopyApprovalError
{
    /// La version organisée n'est plus là : rien n'a été touché.
    CopyMissing,
    /// L'original n'a pas pu aller à la Corbeille : rien n'a été touché.
    CannotTrash,
    /// La version organisée n'a pas pu prendre le nom de l'original : l'original est revenu.
    CannotRename,
    /// FL n'a pas pu enregistrer (pas au premier plan) : rien n'a été touché.
    FlNotSaved,
    /// FL n'a pas ouvert le fichier attendu à temps : rien n'a été touché.
    FlBusy,
    /// Le projet d'avant n'est plus là : la version organisée reste.
    OriginalMissing,
}

public sealed class CopyApprovalException : Exception
{
    public CopyApprovalError Error { get; }
    public CopyApprovalException(CopyApprovalError error) : base(error.ToString()) => Error = error;
}

public static class CopyApprovalRules
{
    public static string Message(this CopyApprovalError e) => e switch
    {
        CopyApprovalError.CopyMissing => Loc.T("La version organisée n'est plus à côté de ton projet : rien n'a été touché."),
        CopyApprovalError.CannotTrash => Loc.T("Ton projet d'origine n'a pas pu aller à la Corbeille : rien n'a été touché."),
        CopyApprovalError.CannotRename => Loc.T("La version organisée n'a pas pu prendre le nom de ton projet : ton projet d'origine est revenu à sa place."),
        CopyApprovalError.FlNotSaved => Loc.T("FL Studio doit être au premier plan pour enregistrer la version organisée : clique dans sa fenêtre, puis réessaie. Rien n'a été touché."),
        CopyApprovalError.FlBusy => Loc.T("FL Studio n'a pas changé de projet à temps (une question attend peut-être dans FL) : rien n'a été touché."),
        _ => Loc.T("Ton projet d'avant n'est plus à sa place : la version organisée est gardée."),
    };

    private static string Full(string path)
    {
        try { return Path.GetFullPath(path); } catch (Exception e) when (e is ArgumentException or NotSupportedException or PathTooLongException) { return path; }
    }

    /// Même fichier (Windows ne distingue pas les majuscules dans les noms).
    public static bool Same(string a, string b) => string.Equals(Full(a), Full(b), StringComparison.OrdinalIgnoreCase);

    private static readonly Regex Version = new("_[0-9]+$", RegexOptions.CultureInvariant);

    /// Le nom d'un projet sans « .flp » ni son « _N » de version (« Nuit_3.flp » → « Nuit »).
    public static string Stem(string path)
    {
        var name = Path.GetFileNameWithoutExtension(path);
        var m = Version.Match(name);
        return m.Success && m.Index > 0 ? name[..m.Index] : name;
    }

    /// Une copie en attente qu'on peut toucher : rien que des projets .flp, dans le dossier de l'original, et des
    /// versions « _N » du même projet. La liste est gardée dans les réglages de l'appli, qu'un autre programme peut
    /// écrire : sans cette vérification, il lui ferait mettre à la Corbeille, renommer ou ouvrir n'importe quel fichier.
    public static bool IsSafe(PendingCopy p)
    {
        if (!Path.IsPathFullyQualified(p.Original)) return false;
        var folder = Full(Path.GetDirectoryName(p.Original) ?? "");
        bool Ok(string path, bool version) =>
            Path.IsPathFullyQualified(path)
            && string.Equals(Path.GetExtension(path), ".flp", StringComparison.OrdinalIgnoreCase)
            && string.Equals(Full(Path.GetDirectoryName(path) ?? ""), folder, StringComparison.OrdinalIgnoreCase)
            && Stem(path) == Stem(p.Original)
            && (!version || Path.GetFileNameWithoutExtension(path) != Stem(path));
        return Ok(p.Original, false) && Ok(p.Copy, true) && !Same(p.Original, p.Copy)
               && p.Older.All(o => Ok(o, true) && !Same(o, p.Original));
    }

    /// La liste après une nouvelle copie rangée de `original`. Rangé de nouveau depuis une version organisée en attente
    /// (ou depuis son original), elle la remplace et garde l'original d'origine ; l'ancienne version organisée partira
    /// à la Corbeille avec la réponse.
    public static List<PendingCopy> Recording(IReadOnlyList<PendingCopy> list, string original, string copy, DateTimeOffset date)
    {
        var out_ = list.ToList();
        var root = original;
        var older = new List<string>();
        var i = out_.FindIndex(p => Same(p.Copy, original) || Same(p.Original, original));
        if (i >= 0)
        {
            var previous = out_[i];
            out_.RemoveAt(i);
            root = previous.Original;
            older = previous.Older.Append(previous.Copy).ToList();
        }
        older.RemoveAll(o => Same(o, copy) || Same(o, root));
        out_.RemoveAll(p => Same(p.Copy, copy));
        out_.Add(new PendingCopy(root, copy, older, date));
        return out_;
    }

    /// « Valider » : l'original à la Corbeille, la version organisée prend son nom, les versions d'avant à la
    /// Corbeille. Le fichier final (le nom de l'original).
    public static string Validate(PendingCopy p, CopyFiles files)
    {
        if (!IsSafe(p) || !files.Exists(p.Copy)) throw new CopyApprovalException(CopyApprovalError.CopyMissing);
        string? trashed = null;
        if (files.Exists(p.Original))
        {
            try { trashed = files.Trash(p.Original); }
            catch (Exception) { throw new CopyApprovalException(CopyApprovalError.CannotTrash); }
        }
        try
        {
            files.Move(p.Copy, p.Original);
        }
        catch (Exception)
        {
            if (trashed is not null)
            {
                try { files.Move(trashed, p.Original); } catch (Exception) { }
            }
            throw new CopyApprovalException(CopyApprovalError.CannotRename);
        }
        foreach (var o in p.Older)
        {
            if (!files.Exists(o)) continue;
            try { files.Trash(o); } catch (Exception) { }
        }
        return p.Original;
    }

    /// « Retourner en arrière » : la version organisée et celles d'avant à la Corbeille ; l'original ne bouge pas.
    public static void GoBack(PendingCopy p, CopyFiles files)
    {
        if (!IsSafe(p)) return;
        foreach (var path in p.Older.Prepend(p.Copy))
        {
            if (!files.Exists(path)) continue;
            try { files.Trash(path); } catch (Exception) { }
        }
    }

    public static string Encode(IEnumerable<PendingCopy> list)
    {
        var array = new JsonArray();
        foreach (var p in list)
            array.Add(new JsonObject
            {
                ["original"] = p.Original,
                ["copy"] = p.Copy,
                ["older"] = new JsonArray(p.Older.Select(o => (JsonNode)JsonValue.Create(o)!).ToArray()),
                ["date"] = p.Date.ToUnixTimeSeconds(),
            });
        return array.ToJsonString();
    }

    /// La liste gardée ; seules les copies sûres (`IsSafe`), 20 au plus.
    public static List<PendingCopy> Decode(string? json)
    {
        var out_ = new List<PendingCopy>();
        if (string.IsNullOrEmpty(json)) return out_;
        try
        {
            if (JsonNode.Parse(json) is not JsonArray array) return out_;
            foreach (var node in array)
            {
                if (node is not JsonObject o || o["original"]?.GetValue<string>() is not { } original
                    || o["copy"]?.GetValue<string>() is not { } copy) continue;
                var older = (o["older"] as JsonArray)?.Select(x => x?.GetValue<string>()).OfType<string>().ToList() ?? new List<string>();
                var date = DateTimeOffset.FromUnixTimeSeconds(o["date"]?.GetValue<long>() ?? 0);
                out_.Add(new PendingCopy(original, copy, older, date));
            }
        }
        catch (Exception e) when (e is System.Text.Json.JsonException or InvalidOperationException or FormatException) { }
        return out_.Where(IsSafe).Take(20).ToList();
    }
}

/// Les copies en attente (réglages de l'appli) et la question, posée à la réouverture de FL Shortcuts.
public sealed class CopyApproval
{
    private readonly Func<string?> _load;
    private readonly Action<string?> _save;
    public CopyFiles Files { get; set; }
    public List<PendingCopy> Pending { get; private set; }
    /// « Plus tard » : plus demandé tout seul avant le prochain lancement (la ligne du menu reste).
    public bool Snoozed { get; private set; }
    public event Action? Changed;

    public CopyApproval(Func<string?> load, Action<string?> save, CopyFiles files)
    {
        _load = load;
        _save = save;
        Files = files;
        Pending = CopyApprovalRules.Decode(load());
    }

    private void Save()
    {
        _save(Pending.Count == 0 ? null : CopyApprovalRules.Encode(Pending));
        Changed?.Invoke();
    }

    /// Une copie rangée vient d'être faite (et ouverte dans FL).
    public void Record(string original, string copy)
    {
        Pending = CopyApprovalRules.Recording(Pending, original, copy, DateTimeOffset.UtcNow).Where(CopyApprovalRules.IsSafe).ToList();
        Save();
    }

    /// « Revenir comme avant » : l'utilisateur a déjà choisi l'original, plus rien à demander pour cette copie.
    public void Forget(string copy)
    {
        Pending.RemoveAll(p => CopyApprovalRules.Same(p.Copy, copy));
        Save();
    }

    /// Les versions organisées qui ne sont plus là sont oubliées.
    public void Prune()
    {
        var before = Pending.Count;
        Pending.RemoveAll(p => !Files.Exists(p.Copy) || !CopyApprovalRules.IsSafe(p));
        if (Pending.Count != before) Save();
    }

    /// Réponse donnée (ou rien à faire) : la copie sort de la liste.
    public void Done(PendingCopy p)
    {
        Pending.RemoveAll(x => x.Id == p.Id);
        Save();
    }

    public void Snooze() => Snoozed = true;

    /// À la réouverture de FL Shortcuts : faut-il poser la question ? (une version organisée attend, l'Organiser est
    /// fermé et « Plus tard » n'a pas été choisi depuis le lancement)
    public bool ShouldAsk(bool organizerOpen)
    {
        if (Snoozed || organizerOpen) return false;
        Prune();
        return Pending.Count > 0;
    }
}

/// Ce que FL doit faire autour des fichiers : jamais un nom dans le journal.
public sealed class CopyApprovalFl
{
    /// FL est ouvert ; il montre ce fichier ; il ouvre ce fichier ; il enregistre ce fichier montré ; il est lancé sur
    /// ce fichier (FL fermé).
    public required Func<bool> FlRunning { get; init; }
    public required Func<string, bool> Shows { get; init; }
    public required Func<string, bool> Open { get; init; }
    public required Func<string, bool> SaveShown { get; init; }
    public required Func<string, bool> Launch { get; init; }
    public Action<double> Sleep { get; init; } = s => Thread.Sleep(TimeSpan.FromSeconds(s));

    private bool WaitUntil(double seconds, Func<bool> condition)
    {
        var deadline = DateTime.UtcNow.AddSeconds(seconds);
        while (DateTime.UtcNow < deadline)
        {
            if (condition()) return true;
            Sleep(0.5);
        }
        return condition();
    }

    /// « Valider », avec FL. Si FL montre l'original, il ouvre d'abord la version organisée ; s'il la montre, il
    /// l'enregistre (Ctrl+S) ; les fichiers changent ; FL rouvre le fichier sous son nom d'origine. FL fermé ou sur un
    /// autre projet : les fichiers seulement.
    public CopyApprovalError? Validate(PendingCopy p, CopyFiles files)
    {
        if (!files.Exists(p.Copy)) return CopyApprovalError.CopyMissing;
        var flHad = false;
        if (FlRunning())
        {
            var showsCopy = Shows(p.Copy);
            if (!showsCopy && Shows(p.Original))
            {
                if (!Open(p.Copy) || !WaitUntil(60, () => Shows(p.Copy))) return CopyApprovalError.FlBusy;
            }
            if (showsCopy || Shows(p.Copy))
            {
                flHad = true;
                if (!SaveShown(p.Copy)) return CopyApprovalError.FlNotSaved;
            }
        }
        try
        {
            var final = CopyApprovalRules.Validate(p, files);
            if (flHad) Open(final);
            AppLog.Write("ORGANIZE", $"organized copy approved (fl {(flHad ? "reopened" : "untouched")}, {p.Older.Count} older)");
            return null;
        }
        catch (CopyApprovalException e)
        {
            AppLog.Write("ORGANIZE", $"organized copy not approved ({e.Error})");
            return e.Error;
        }
    }

    /// « Retourner en arrière », avec FL : il rouvre le projet d'avant (sauf s'il le montre déjà), puis la version
    /// organisée part à la Corbeille une fois quittée. FL fermé : il est lancé sur le projet d'avant.
    public CopyApprovalError? GoBack(PendingCopy p, CopyFiles files)
    {
        if (!CopyApprovalRules.IsSafe(p)) return CopyApprovalError.CopyMissing;
        if (!files.Exists(p.Original)) return CopyApprovalError.OriginalMissing;
        if (FlRunning())
        {
            var showsCopy = Shows(p.Copy);
            if (showsCopy || !Shows(p.Original))
            {
                if (!Open(p.Original)) return CopyApprovalError.FlBusy;
                if (showsCopy && !WaitUntil(60, () => !Shows(p.Copy))) return CopyApprovalError.FlBusy;
            }
        }
        else if (!Launch(p.Original))
        {
            return CopyApprovalError.FlBusy;
        }
        CopyApprovalRules.GoBack(p, files);
        AppLog.Write("ORGANIZE", $"organized copy discarded, previous project reopened ({p.Older.Count} older)");
        return null;
    }
}
