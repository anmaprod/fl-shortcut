// Bibliothèque des macros : mêmes essais du magasin que Tests/FLShortcutTests/MacroLibraryTests.swift (copie gardée
// une fois, fichier abîmé ou plus récent copié, jamais écrasé sans copie, révision, cache, noms uniques).
using System.Text;
using FLShortcut.Core;
using FLShortcut.Core.Macros;
using Xunit;

namespace FLShortcut.Core.Tests;

/// Stockage en mémoire : écritures et copies comptées, erreurs choisies.
internal sealed class MemoryMacroLibraryStorage : IMacroLibraryStorage
{
    public byte[]? Data { get; set; }
    public int Writes { get; private set; }
    public Dictionary<string, byte[]> Backups { get; } = new();
    public Exception? ReadError { get; set; }
    public Exception? WriteError { get; set; }
    public Exception? BackupError { get; set; }

    public MemoryMacroLibraryStorage(byte[]? data = null) => Data = data;

    public byte[]? Read() => ReadError is { } e ? throw e : Data;

    public void Write(byte[] data)
    {
        if (WriteError is { } e) throw e;
        Writes++;
        Data = data;
    }

    public string Backup(byte[] data, string label)
    {
        if (BackupError is { } e) throw e;
        var name = $"macros.{label}.json";
        Backups[name] = data;
        return name;
    }
}

public class MacroLibraryStoreTests
{
    private static MacroDoc Sample(string name = "Ma macro") => new()
    {
        Name = name,
        Blocks = new List<Block> { new(new BlockBody.Delay(100)), new(new BlockBody.Key(new KeyRef(new MacKey(1, Command: true), "s"))) },
    };

    private static byte[] Utf8(string s) => Encoding.UTF8.GetBytes(s);

    [Fact]
    public void SavesAfterAChangeAndKeepsThePreviousFileOnce()
    {
        var storage = new MemoryMacroLibraryStorage(MacroLibraryCodec.Encode(new[] { Sample() }));
        var original = storage.Data;
        var store = new MacroLibraryStore(storage);
        Assert.Single(store.Macros);
        Assert.Null(store.LoadWarning);
        store.SaveNow();
        Assert.Equal(0, storage.Writes);                         // rien n'a changé : rien d'écrit
        store.Add(Sample("Nouvelle"));
        store.SaveNow();
        Assert.Equal(1, storage.Writes);
        Assert.Equal(original, storage.Backups["macros.precedente.json"]);
        store.Add(Sample("Encore"));
        store.SaveNow();
        Assert.Equal(2, storage.Writes);
        Assert.Single(storage.Backups);                          // une seule copie par lancement
        var reread = new MacroLibraryStore(storage);
        Assert.Equal(new[] { "Ma macro", "Nouvelle", "Encore" }, reread.Macros.Select(m => m.Name));
    }

    [Fact]
    public void CorruptFileIsBackedUpAndLibraryStartsEmpty()
    {
        var storage = new MemoryMacroLibraryStorage(Utf8("{ cassé"));
        var store = new MacroLibraryStore(storage);
        Assert.Empty(store.Macros);
        Assert.Equal(Utf8("{ cassé"), storage.Backups["macros.illisible.json"]);
        Assert.StartsWith("Le fichier des macros était illisible", store.LoadWarning);
        Assert.True(store.LoadIncomplete);
        Assert.Equal(0, storage.Writes);                         // rien d'écrit tant que rien ne change
    }

    [Fact]
    public void NewerOrPartialFileIsBackedUp()
    {
        var newer = Utf8("""{"version": 9, "macros": [{"name": "Future", "blocks": [], "format": 3}]}""");
        var storage = new MemoryMacroLibraryStorage(newer);
        var store = new MacroLibraryStore(storage);
        Assert.Single(store.Macros);
        Assert.Equal(newer, storage.Backups["macros.plus-recente.json"]);
        Assert.False(MacroProgram.Compile(store.Macros[0]).IsRunnable);   // format 3 : bloquée

        var partial = Utf8("""{"version": 1, "macros": [{"name": "A", "blocks": []}, 7]}""");
        var second = new MemoryMacroLibraryStorage(partial);
        var kept = new MacroLibraryStore(second);
        Assert.Single(kept.Macros);
        Assert.Equal(partial, second.Backups["macros.partielle.json"]);
        Assert.StartsWith("1 macro(s) illisible(s) ignorée(s)", kept.LoadWarning);
    }

    [Fact]
    public void InaccessibleFileIsNeverOverwritten()
    {
        var storage = new MemoryMacroLibraryStorage { ReadError = new UnauthorizedAccessException("refusé") };
        var store = new MacroLibraryStore(storage);
        Assert.True(store.WritesDisabled);
        store.Add(Sample());
        store.SaveNow();
        Assert.Equal(0, storage.Writes);
        Assert.StartsWith("Bibliothèque de macros inaccessible (refusé)", store.Problem);
    }

    [Fact]
    public void BackupFailureDisablesWrites()
    {
        var storage = new MemoryMacroLibraryStorage(MacroLibraryCodec.Encode(new[] { Sample() }));
        var original = storage.Data;
        storage.BackupError = new IOException("disque plein");
        var store = new MacroLibraryStore(storage);
        Assert.Null(store.Problem);
        store.Add(Sample("Nouvelle"));
        store.SaveNow();
        Assert.Equal(0, storage.Writes);                         // jamais remplacé sans copie
        Assert.Equal(original, storage.Data);
        Assert.True(store.WritesDisabled);
        Assert.StartsWith("Tes macros ne peuvent pas être enregistrées", store.Problem);
        store.Add(Sample("Encore"));
        store.SaveNow();
        Assert.Equal(0, storage.Writes);
    }

    [Fact]
    public void ProblemVisibleWhenLibraryEmpty()
    {
        var storage = new MemoryMacroLibraryStorage(Utf8("{ cassé")) { BackupError = new UnauthorizedAccessException("non") };
        var store = new MacroLibraryStore(storage);
        Assert.Empty(store.Macros);
        Assert.True(store.WritesDisabled);                       // illisible et pas copié : jamais écrasé
        Assert.StartsWith("Le fichier des macros est illisible", store.Problem);
        store.Add(Sample());
        store.SaveNow();
        Assert.Equal(0, storage.Writes);
        Assert.Equal(Utf8("{ cassé"), storage.Data);
    }

    /// Une écriture ratée est dite, et refaite à la prochaine sauvegarde.
    [Fact]
    public void FailedWriteIsReportedAndRetried()
    {
        var storage = new MemoryMacroLibraryStorage { WriteError = new IOException("occupé") };
        var store = new MacroLibraryStore(storage);
        store.Add(Sample());
        store.SaveNow();
        Assert.Equal("Tes macros ne peuvent pas être enregistrées : occupé", store.SaveError);
        Assert.True(store.HasUnsavedChanges);
        storage.WriteError = null;
        store.SaveNow();
        Assert.Equal(1, storage.Writes);
        Assert.Null(store.SaveError);
    }

    [Fact]
    public void UpdateBumpsTheRevisionOnlyWhenContentChanges()
    {
        var store = new MacroLibraryStore(new MemoryMacroLibraryStorage());
        var doc = store.Add(Sample());
        Assert.Equal(0, store.Update(MacroDoc.FromJson(doc.ToJson()))?.Revision);
        var changed = MacroDoc.FromJson(doc.ToJson());
        changed.Name = "Renommée";
        Assert.Equal(1, store.Update(changed)?.Revision);
        Assert.Null(store.Update(new MacroDoc { Name = "Absente" }));
    }

    [Fact]
    public void ProgramsAreCachedByRevision()
    {
        var store = new MacroLibraryStore(new MemoryMacroLibraryStorage());
        var doc = store.Add(new MacroDoc { Name = "A", Blocks = new List<Block> { new(new BlockBody.Delay(100)) } });
        var first = store.Programs()[doc.Id];
        Assert.Same(first, store.Programs()[doc.Id]);
        var changed = MacroDoc.FromJson(doc.ToJson());
        changed.Blocks.Add(new Block(new BlockBody.Delay(200)));
        store.Update(changed);
        var second = store.Programs()[doc.Id];
        Assert.NotSame(first, second);
        Assert.Equal(2, second.Blocks.Count);
        Assert.Null(second.Problem);
    }

    [Fact]
    public void UniqueNames()
    {
        var store = new MacroLibraryStore(new MemoryMacroLibraryStorage());
        Assert.Equal("Nouvelle macro", store.UniqueName("Nouvelle macro"));
        store.Add(new MacroDoc { Name = "Nouvelle macro" });
        store.Add(new MacroDoc { Name = "Nouvelle macro 2" });
        Assert.Equal("Nouvelle macro 3", store.UniqueName("Nouvelle macro"));
    }

    [Fact]
    public void RemoveAndUndoKeepThePlace()
    {
        var store = new MacroLibraryStore(new MemoryMacroLibraryStorage());
        var a = store.Add(Sample("A"));
        store.Add(Sample("B"));
        var changes = 0;
        store.Changed += () => changes++;
        var removed = store.Remove(a.Id);
        Assert.Equal(0, removed?.Index);
        store.Add(removed!.Value.Doc, removed.Value.Index);
        Assert.Equal(new[] { "A", "B" }, store.Macros.Select(m => m.Name));
        Assert.Equal(2, changes);
    }

    [Fact]
    public void MessagesHaveTheirEnglish()
    {
        foreach (var key in new[]
                 {
                     "Bibliothèque de macros inaccessible (%@) : elle n'est pas modifiée.",
                     "Bibliothèque d'une version plus récente de FL Shortcuts", " (copie : %@).",
                     ", copie impossible : elle n'est pas modifiée.", ", copie impossible : le fichier n'est pas modifié.",
                     "%lld macro(s) illisible(s) ignorée(s)",
                     "Le fichier des macros était illisible : une copie datée a été gardée dans le dossier FL Shortcuts (%@).",
                     "Le fichier des macros est illisible et n'a pas pu être copié : il n'est pas modifié, tes nouvelles macros ne seront pas enregistrées.",
                     "Tes macros ne peuvent pas être enregistrées : %@",
                     "Tes macros ne peuvent pas être enregistrées : la copie de secours du fichier a échoué (%@). Le fichier n'est pas remplacé.",
                     "Tes macros ne peuvent pas être enregistrées : le fichier n'a pas pu être copié avant d'être remplacé.",
                     "Organiser", "Macro",
                 })
            Assert.True(Loc.Has(key), $"« {key} » sans anglais");
    }
}
