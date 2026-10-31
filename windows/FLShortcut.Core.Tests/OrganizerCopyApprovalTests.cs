// Validation de la copie rangée (demande du propriétaire, 24/10) : la copie retenue avec son original, la réponse
// sur de vrais fichiers (dossier temporaire, Corbeille imitée par un dossier), rien de perdu si quelque chose rate.
// Miroir de Tests/FLShortcutTests/OrganizerCopyApprovalTests.swift.
using FLShortcut.Core.Organizer;
using Xunit;

namespace FLShortcut.Core.Tests;

public sealed class OrganizerCopyApprovalTests : IDisposable
{
    private readonly string _folder;
    private readonly string _trashFolder;

    public OrganizerCopyApprovalTests()
    {
        _folder = Path.Combine(Path.GetTempPath(), "approbation-" + Guid.NewGuid());
        _trashFolder = Path.Combine(_folder, "Corbeille");
        Directory.CreateDirectory(_trashFolder);
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, true); } catch (IOException) { }
    }

    /// Les vrais fichiers ; la Corbeille est un dossier du test (rien ne part dans la vraie Corbeille).
    private CopyFiles Files(bool renameFails = false, bool trashFails = false)
    {
        var trash = _trashFolder;
        return new CopyFiles
        {
            Trash = path =>
            {
                if (trashFails) throw new UnauthorizedAccessException();
                var place = Path.Combine(trash, Guid.NewGuid() + "-" + Path.GetFileName(path));
                File.Move(path, place);
                return place;
            },
            Move = (from, to) =>
            {
                if (renameFails && Path.GetDirectoryName(from) != trash) throw new UnauthorizedAccessException();
                File.Move(from, to);   // l'original qui revient de la Corbeille, ou le vrai renommage
            },
        };
    }

    private string FileWith(string name, string text)
    {
        var path = Path.Combine(_folder, name);
        File.WriteAllText(path, text);
        return path;
    }

    private static string? Text(string path) => File.Exists(path) ? File.ReadAllText(path) : null;

    private static PendingCopy Pending(string original, string copy, params string[] older) =>
        new(original, copy, older, DateTimeOffset.UtcNow);

    [Fact]
    public void CopiesAreRememberedWithTheirOriginal()
    {
        var p = Path.Combine(Path.GetTempPath(), "p");
        string x = Path.Combine(p, "Nuit.flp"), x2 = Path.Combine(p, "Nuit_2.flp"), x3 = Path.Combine(p, "Nuit_3.flp");
        string y = Path.Combine(p, "Jour.flp"), y2 = Path.Combine(p, "Jour_2.flp");
        var list = CopyApprovalRules.Recording(new List<PendingCopy>(), x, x2, DateTimeOffset.UtcNow);
        Assert.Equal(new[] { x2 }, list.Select(c => c.Copy));
        list = CopyApprovalRules.Recording(list, y, y2, DateTimeOffset.UtcNow);
        Assert.Equal(2, list.Count);   // un autre projet : une autre question
        // Organiser relancé sur la version organisée, sans avoir répondu : la nouvelle la remplace, même original.
        list = CopyApprovalRules.Recording(list, x2, x3, DateTimeOffset.UtcNow);
        var nuit = list.First(c => c.Copy == x3);
        Assert.Equal(x, nuit.Original);
        Assert.Equal(new[] { x2 }, nuit.Older);   // l'ancienne version organisée partira à la Corbeille
        Assert.Equal(2, list.Count);
        // Relancé depuis l'original : pareil.
        var x4 = Path.Combine(p, "Nuit_4.flp");
        list = CopyApprovalRules.Recording(list, x, x4, DateTimeOffset.UtcNow);
        Assert.Equal(new[] { x2, x3 }, list.First(c => c.Copy == x4).Older);
        Assert.Single(list, c => c.Original == x);
    }

    /// « Valider » : l'original à la Corbeille, la version organisée prend son nom, les versions d'avant à la Corbeille.
    [Fact]
    public void ValidateReplacesTheOriginal()
    {
        var original = FileWith("Nuit.flp", "avant");
        var older = FileWith("Nuit_2.flp", "rangé 1");
        var copy = FileWith("Nuit_3.flp", "rangé 2");
        var final = CopyApprovalRules.Validate(Pending(original, copy, older), Files());
        Assert.Equal(original, final);
        Assert.Equal("rangé 2", Text(original));   // la version organisée a pris le nom du projet
        Assert.False(File.Exists(copy));
        Assert.False(File.Exists(older));
        var trashed = Directory.GetFiles(_trashFolder);
        Assert.Equal(2, trashed.Length);   // l'original et l'ancienne version : à la Corbeille, pas supprimés
        Assert.Contains(trashed, t => t.EndsWith("Nuit.flp", StringComparison.Ordinal));
    }

    /// La version organisée a disparu : rien n'est touché. Le renommage rate : l'original revient à sa place.
    [Fact]
    public void NothingIsLostWhenSomethingFails()
    {
        var original = FileWith("Nuit.flp", "avant");
        var gone = Path.Combine(_folder, "Nuit_2.flp");
        var e = Assert.Throws<CopyApprovalException>(() => CopyApprovalRules.Validate(Pending(original, gone), Files()));
        Assert.Equal(CopyApprovalError.CopyMissing, e.Error);
        Assert.Equal("avant", Text(original));

        var copy = FileWith("Nuit_2.flp", "rangé");
        e = Assert.Throws<CopyApprovalException>(() => CopyApprovalRules.Validate(Pending(original, copy), Files(renameFails: true)));
        Assert.Equal(CopyApprovalError.CannotRename, e.Error);
        Assert.Equal("avant", Text(original));   // l'original revenu de la Corbeille
        Assert.Equal("rangé", Text(copy));

        e = Assert.Throws<CopyApprovalException>(() => CopyApprovalRules.Validate(Pending(original, copy), Files(trashFails: true)));
        Assert.Equal(CopyApprovalError.CannotTrash, e.Error);
        Assert.Equal("avant", Text(original));
        Assert.Equal("rangé", Text(copy));   // rien n'a bougé
    }

    /// L'original supprimé à la main entre-temps : la version organisée prend quand même son nom.
    [Fact]
    public void ValidateWithoutTheOriginal()
    {
        var original = Path.Combine(_folder, "Nuit.flp");
        var copy = FileWith("Nuit_2.flp", "rangé");
        CopyApprovalRules.Validate(Pending(original, copy), Files());
        Assert.Equal("rangé", Text(original));
    }

    /// « Retourner en arrière » : la version organisée (et celles d'avant) à la Corbeille, l'original ne bouge pas.
    [Fact]
    public void GoBackTrashesTheCopies()
    {
        var original = FileWith("Nuit.flp", "avant");
        var older = FileWith("Nuit_2.flp", "rangé 1");
        var copy = FileWith("Nuit_3.flp", "rangé 2");
        CopyApprovalRules.GoBack(Pending(original, copy, older), Files());
        Assert.Equal("avant", Text(original));
        Assert.False(File.Exists(copy));
        Assert.False(File.Exists(older));
        Assert.Equal(2, Directory.GetFiles(_trashFolder).Length);
    }

    /// Retenu d'un lancement à l'autre ; « Revenir comme avant » l'oublie ; une version organisée disparue aussi.
    [Fact]
    public void PendingCopiesSurviveARelaunch()
    {
        string? stored = null;
        var original = FileWith("Nuit.flp", "avant");
        var copy = FileWith("Nuit_2.flp", "rangé");
        CopyApproval Make() => new(() => stored, s => stored = s, Files());
        var approval = Make();
        approval.Record(original, copy);
        var relaunched = Make();
        Assert.Equal(new[] { copy }, relaunched.Pending.Select(c => c.Copy));
        Assert.Equal(original, relaunched.Pending[0].Original);
        relaunched.Forget(copy);
        Assert.Empty(Make().Pending);   // « Revenir comme avant » : plus de question

        approval.Record(original, copy);
        File.Delete(copy);
        approval.Prune();
        Assert.Empty(approval.Pending);   // version organisée supprimée à la main : plus de question
        Assert.Null(stored);
    }

    /// Audit du 25/10 : la liste est dans les réglages de l'app, qu'un autre programme peut écrire. Seuls des projets
    /// .flp et leurs versions « _N » du même dossier sont acceptés : jamais n'importe quel fichier mis à la Corbeille,
    /// renommé ou ouvert.
    [Fact]
    public void OnlyProjectVersionsAreAccepted()
    {
        var p = Path.Combine(Path.GetTempPath(), "moi", "Projets");
        PendingCopy In(string original, string copy, params string[] older) =>
            Pending(Path.Combine(p, original), Path.Combine(p, copy), older.Select(o => Path.Combine(p, o)).ToArray());
        Assert.True(CopyApprovalRules.IsSafe(In("Nuit.flp", "Nuit_2.flp")));
        Assert.True(CopyApprovalRules.IsSafe(In("Beat_7.flp", "Beat_8.flp")));   // projet déjà numéroté
        Assert.True(CopyApprovalRules.IsSafe(In("Nuit.flp", "Nuit_3.flp", "Nuit_2.flp")));
        Assert.False(CopyApprovalRules.IsSafe(In("Rapport.docx", "Rapport_2.docx")));   // pas un projet
        Assert.False(CopyApprovalRules.IsSafe(In("Nuit.flp", "Autre_2.flp")));   // pas une version du même projet
        Assert.False(CopyApprovalRules.IsSafe(In("Nuit.flp", "Nuit.flp")));   // le même fichier
        Assert.False(CopyApprovalRules.IsSafe(In("Nuit.flp", "Nuit_2.flp", "Nuit.flp")));
        Assert.False(CopyApprovalRules.IsSafe(Pending(Path.Combine(p, "Nuit.flp"), Path.Combine(Path.GetTempPath(), "Nuit_2.flp"))));   // pas dans le dossier du projet
        Assert.False(CopyApprovalRules.IsSafe(In("Script.bat", "Script_2.bat")));   // jamais un programme
        Assert.False(CopyApprovalRules.IsSafe(Pending("Nuit.flp", "Nuit_2.flp")));   // chemin incomplet

        string? stored = CopyApprovalRules.Encode(new[] { In("Nuit.flp", "Nuit_2.flp"), In("Rapport.docx", "Rapport_2.docx") });
        var approval = new CopyApproval(() => stored, s => stored = s, Files());
        Assert.Equal(new[] { "Nuit_2.flp" }, approval.Pending.Select(c => Path.GetFileName(c.Copy)));   // une entrée écrite par un autre programme est ignorée
        Assert.Throws<CopyApprovalException>(() => CopyApprovalRules.Validate(In("Rapport.docx", "Rapport_2.docx"), Files()));
        Assert.Empty(CopyApprovalRules.Decode("{pas du json"));
    }

    /// La question n'est posée qu'Organiser fermé, et plus après « Plus tard » jusqu'au prochain lancement.
    [Fact]
    public void QuestionAskedOnlyWhenTheOrganizerIsClosed()
    {
        string? stored = null;
        var original = FileWith("Nuit.flp", "avant");
        var copy = FileWith("Nuit_2.flp", "rangé");
        var approval = new CopyApproval(() => stored, s => stored = s, Files());
        Assert.False(approval.ShouldAsk(false));
        approval.Record(original, copy);
        Assert.False(approval.ShouldAsk(true));
        Assert.True(approval.ShouldAsk(false));
        approval.Snooze();
        Assert.False(approval.ShouldAsk(false));
        Assert.True(new CopyApproval(() => stored, s => stored = s, Files()).ShouldAsk(false));
    }

    /// Avec FL : il enregistre la version organisée qu'il montre, puis rouvre le fichier sous son nom d'origine.
    [Fact]
    public void ValidateWithFlSavesThenReopens()
    {
        var original = FileWith("Nuit.flp", "avant");
        var copy = FileWith("Nuit_2.flp", "rangé");
        var shown = original;
        var steps = new List<string>();
        var fl = new CopyApprovalFl
        {
            FlRunning = () => true,
            Shows = f => CopyApprovalRules.Same(f, shown),
            Open = f => { steps.Add("ouvre " + Path.GetFileName(f)); shown = f; return true; },
            SaveShown = f => { steps.Add("enregistre " + Path.GetFileName(f)); return true; },
            Launch = _ => false,
            Sleep = _ => { },
        };
        Assert.Null(fl.Validate(Pending(original, copy), Files()));
        Assert.Equal(new[] { "ouvre Nuit_2.flp", "enregistre Nuit_2.flp", "ouvre Nuit.flp" }, steps);
        Assert.Equal("rangé", Text(original));

        // FL n'enregistre pas : rien n'a été touché.
        var copy2 = FileWith("Nuit_3.flp", "rangé 2");
        shown = copy2;
        var stuck = new CopyApprovalFl
        {
            FlRunning = () => true, Shows = f => CopyApprovalRules.Same(f, shown), Open = _ => true,
            SaveShown = _ => false, Launch = _ => false, Sleep = _ => { },
        };
        Assert.Equal(CopyApprovalError.FlNotSaved, stuck.Validate(Pending(original, copy2), Files()));
        Assert.Equal("rangé", Text(original));
        Assert.Equal("rangé 2", Text(copy2));
    }

    /// « Revenir comme avant » (28/10) : la version organisée et celles d'avant à la Corbeille une fois que FL ne la
    /// montre plus ; encore montrée au bout d'une minute : elle reste (la question reviendra).
    [Fact]
    public void UndoTrashesTheCopyOnceFlLeftIt()
    {
        var original = FileWith("Nuit.flp", "avant");
        var copy = FileWith("Nuit_2.flp", "rangé");
        var older = FileWith("Nuit_3.flp", "rangé avant");
        var shown = copy;
        var waits = 0;
        var fl = new CopyApprovalFl
        {
            FlRunning = () => true, Shows = f => CopyApprovalRules.Same(f, shown), Open = _ => true, SaveShown = _ => true,
            Launch = _ => false,
            Sleep = _ => { if (++waits == 3) shown = original; },             // FL quitte la copie au bout d'un moment
        };
        Assert.True(fl.DiscardAfterUndo(Pending(original, copy, older), Files()));
        Assert.False(File.Exists(copy));
        Assert.False(File.Exists(older));
        Assert.Equal("avant", Text(original));                                 // l'original ne bouge jamais

        var copy2 = FileWith("Nuit_4.flp", "rangé 2");
        var clock = new DateTime(2026, 1, 1, 0, 0, 0, DateTimeKind.Utc);
        var stuck = new CopyApprovalFl
        {
            FlRunning = () => true, Shows = f => CopyApprovalRules.Same(f, copy2), Open = _ => true, SaveShown = _ => true,
            Launch = _ => false, Sleep = s => clock = clock.AddSeconds(s), Now = () => clock,
        };
        Assert.False(stuck.DiscardAfterUndo(Pending(original, copy2), Files()));
        Assert.Equal("rangé 2", Text(copy2));                                  // ouverte dans FL : jamais touchée
        Assert.True(clock >= new DateTime(2026, 1, 1, 0, 1, 0, DateTimeKind.Utc));   // attendue une minute

        var approval = new CopyApproval(() => null, _ => { }, Files());
        approval.Record(original, copy2);
        Assert.NotNull(approval.Find(copy2));
        Assert.Null(approval.Find(original));
    }

    /// « Retourner en arrière » FL fermé : il est lancé sur le projet d'avant, la version organisée à la Corbeille.
    [Fact]
    public void GoBackWithFlClosedLaunchesTheOriginal()
    {
        var original = FileWith("Nuit.flp", "avant");
        var copy = FileWith("Nuit_2.flp", "rangé");
        string? launched = null;
        var fl = new CopyApprovalFl
        {
            FlRunning = () => false, Shows = _ => false, Open = _ => false, SaveShown = _ => false,
            Launch = f => { launched = f; return true; }, Sleep = _ => { },
        };
        Assert.Null(fl.GoBack(Pending(original, copy), Files()));
        Assert.Equal(original, launched);
        Assert.False(File.Exists(copy));
        Assert.Equal("avant", Text(original));
        File.Delete(original);
        Assert.Equal(CopyApprovalError.OriginalMissing, fl.GoBack(Pending(original, FileWith("Nuit_3.flp", "x")), Files()));
    }
}
