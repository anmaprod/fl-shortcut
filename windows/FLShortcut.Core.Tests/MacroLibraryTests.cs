// Bibliothèque des macros (macros.json) : mêmes essais du format que Tests/FLShortcutTests/MacroLibraryTests.swift,
// plus un fichier écrit par le Mac (clés triées) relu tel quel.
using System.Text;
using System.Text.Json.Nodes;
using FLShortcut.Core;
using FLShortcut.Core.Macros;
using Xunit;

namespace FLShortcut.Core.Tests;

public class MacroLibraryTests
{
    private static MacroDoc Sample(string name = "Ma macro") => new()
    {
        Name = name,
        Blocks = new List<Block>
        {
            new(new BlockBody.Key(new KeyRef(new MacKey(1, Command: true), "s")), note: "Enregistrer"),
            new(new BlockBody.RepeatCount(2, new List<Block>
            {
                new(new BlockBody.MenuKeyPress(MenuKey.Down)),
                new(new BlockBody.Delay(100), enabled: false),
            })),
            new(new BlockBody.Click(new ClickTarget.FlWindowPoint(Corner.TopRight, -40, 12, new Size2(900, 600)))),
            new(new BlockBody.ChooseFile(@"C:\Users\moi\Documents\Voix.fst")),
            new(new BlockBody.Unknown("teleport", new JsonObject { ["where"] = "Mars" })),
        },
    };

    private static string Text(MacroDoc d) => d.ToJson().ToJsonString();

    [Fact]
    public void RoundTripKeepsEveryMacroAndUnknownBlocks()
    {
        var docs = new[] { Sample(), Sample("Deuxième") };
        var decoded = MacroLibraryCodec.Decode(MacroLibraryCodec.Encode(docs));
        Assert.Equal(docs.Select(Text), decoded.Macros.Select(Text));
        Assert.Equal(0, decoded.Dropped);
        Assert.Equal(MacroLibraryCodec.CurrentVersion, decoded.Version);
        // Le bloc inconnu est gardé tel quel, et bloque sa macro.
        Assert.NotNull(MacroProgram.Compile(decoded.Macros[0]).Problem);
    }

    [Fact]
    public void UnreadableEntryIsDroppedAndDuplicateIdsRegenerated()
    {
        var id = Guid.NewGuid().ToString().ToUpperInvariant();
        var json = $$"""
            {"version": 1, "macros": [
              {"id": "{{id}}", "name": "A", "blocks": [{"type": "delay", "ms": 100}]},
              42,
              {"id": "{{id}}", "name": "B", "blocks": []}
            ]}
            """;
        var decoded = MacroLibraryCodec.Decode(Encoding.UTF8.GetBytes(json));
        Assert.Equal(new[] { "A", "B" }, decoded.Macros.Select(m => m.Name));
        Assert.Equal(1, decoded.Dropped);
        Assert.NotEqual(decoded.Macros[0].Id, decoded.Macros[1].Id);
    }

    /// Fichier écrit par le Mac (clés triées, révision) : relu tel quel, sa macro prête à tourner.
    [Fact]
    public void MacFileIsReadAsIs()
    {
        const string mac = """
            {
              "macros" : [
                {
                  "blocks" : [ { "enabled" : true, "id" : "6F1C2A43-8B0E-4E4B-9D3A-1B2C3D4E5F60", "ms" : 100, "onFailure" : "stop", "type" : "delay" } ],
                  "format" : 2,
                  "id" : "0A1B2C3D-4E5F-4061-8273-8495A6B7C8D9",
                  "name" : "Pause",
                  "revision" : 3
                }
              ],
              "version" : 1
            }
            """;
        var decoded = MacroLibraryCodec.Decode(Encoding.UTF8.GetBytes(mac));
        var doc = Assert.Single(decoded.Macros);
        Assert.Equal("Pause", doc.Name);
        Assert.Equal(3, doc.Revision);
        Assert.Equal(Guid.Parse("0A1B2C3D-4E5F-4061-8273-8495A6B7C8D9"), doc.Id);
        Assert.Equal(new BlockBody.Delay(100), doc.Blocks[0].Body);
        Assert.True(MacroProgram.Compile(doc).IsRunnable);
    }

    [Fact]
    public void BrokenOrOversizedFilesAreRefused()
    {
        var broken = Assert.Throws<MacroLibraryCodec.Failure>(() => MacroLibraryCodec.Decode(Encoding.UTF8.GetBytes("{ cassé")));
        Assert.Equal("Format de bibliothèque illisible.", broken.Message);
        Assert.Throws<MacroLibraryCodec.Failure>(() => MacroLibraryCodec.Decode(Encoding.UTF8.GetBytes("""{"version": 1}""")));
        Assert.Throws<MacroLibraryCodec.Failure>(() => MacroLibraryCodec.Decode(new byte[MacroLibraryCodec.MaxBytes + 1]));

        var many = MacroLibraryCodec.Encode(Enumerable.Range(0, MacroLibraryCodec.MaxMacros + 1).Select(i => new MacroDoc { Name = $"M{i}" }));
        var tooMany = Assert.Throws<MacroLibraryCodec.Failure>(() => MacroLibraryCodec.Decode(many));
        Assert.Equal("Trop de macros (500 au plus).", tooMany.Message);
    }

    /// Fichier d'une version plus récente : lu, sa version gardée (l'appli en garde une copie et prévient).
    [Fact]
    public void NewerVersionIsReported()
    {
        var newer = MacroLibraryCodec.Decode(Encoding.UTF8.GetBytes("""{"version": 9, "macros": [{"name": "Future", "blocks": [], "format": 3}]}"""));
        Assert.Equal(9, newer.Version);
        Assert.False(MacroProgram.Compile(newer.Macros[0]).IsRunnable);    // format 3 : bloquée
    }

    [Fact]
    public void MessagesHaveTheirEnglish()
    {
        Assert.True(Loc.Has("Format de bibliothèque illisible."));
        Assert.True(Loc.Has("Trop de macros (%lld au plus)."));
    }
}
