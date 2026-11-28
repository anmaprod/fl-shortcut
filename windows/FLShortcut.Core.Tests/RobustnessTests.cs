using System.Text;
using System.Text.Json.Nodes;
using FLShortcut.Core.Macros;
using FLShortcut.Core.Organizer;
using Xunit;
using Xunit.Abstractions;

namespace FLShortcut.Core.Tests;

/// Fichiers venus d'ailleurs (21/11, « rendre ce logiciel très sécurisé ») : une macro de la Communauté, des raccourcis
/// partagés, un projet de FL abîmé ne doivent jamais faire tomber l'appli. Des milliers de versions abîmées exprès
/// (octets changés, coupés, ajoutés ; valeurs JSON remplacées ou retirées) : seules les erreurs prévues, celles que
/// l'appli attrape et montre (MacrosPage, CommunityPage, ProjectFile), sont permises. Graine fixe : un échec se rejoue à
/// l'identique. Miroir : Tests/FLShortcutTests/RobustnessTests.swift.
public class RobustnessTests
{
    private const string Home = @"C:\Users\flshortcuts";
    private readonly ITestOutputHelper _out;

    public RobustnessTests(ITestOutputHelper output) => _out = output;

    /// Pour chercher plus loin sur un poste (jamais sur la CI) : FLS_ROBUST_SEED (autre graine) et FLS_ROBUST_SCALE
    /// (combien de fois plus de fichiers abîmés).
    private static int Seed(int fallback) =>
        int.TryParse(Environment.GetEnvironmentVariable("FLS_ROBUST_SEED"), out var s) ? s + fallback : fallback;

    private static int Scale =>
        int.TryParse(Environment.GetEnvironmentVariable("FLS_ROBUST_SCALE"), out var n) && n > 0 ? n : 1;

    [Fact]
    public void ADamagedMacroNeverCrashes()
    {
        var random = new Random(Seed(2111));
        var runs = 0;
        foreach (var template in MacroTemplates.Gallery)
        {
            var valid = MacroExchange.Export(template.Make(), "0.2.0", Home);
            for (var i = 0; i < 400 * Scale; i++, runs++) Import(Bytes(valid, random), template.Id, i);
            for (var i = 0; i < 800 * Scale; i++, runs++) Import(Json(valid, random), template.Id, i);
        }
        _out.WriteLine($"{runs} macros abîmées, aucune chute");

        static void Import(byte[] data, string template, int run)
        {
            try { MacroExchange.PrepareImport(data, Home, @"C:\Users\flshortcuts\Documents\FL Shortcuts\Presets", _ => null, _ => new[] { "Vital" }); }
            catch (Exception e) when (e is MacroExchange.ImportFailure or FormatException) { }
            catch (Exception e)
            {
                Assert.Fail($"{template} n°{run} : {e.GetType().Name} {e.Message}\n{e.StackTrace}");
            }
        }
    }

    [Fact]
    public void DamagedSharedShortcutsNeverCrash()
    {
        var random = new Random(Seed(2112));
        var runs = 0;
        foreach (var preset in Enum.GetValues<ProfilePreset>())
        {
            var shortcuts = preset.Shortcuts();
            foreach (var valid in new[] { ProfileCodec.Encode(shortcuts), MacProfile.ToMac(shortcuts, UsKeyLayout.Shared) })
            {
                var bytes = Encoding.UTF8.GetBytes(valid);
                for (var i = 0; i < 300 * Scale; i++, runs++) Prepare(Encoding.UTF8.GetString(Bytes(bytes, random)), preset, i);
                for (var i = 0; i < 600 * Scale; i++, runs++) Prepare(Encoding.UTF8.GetString(Json(bytes, random)), preset, i);
            }
        }
        _out.WriteLine($"{runs} profils abîmés, aucune chute");

        static void Prepare(string json, ProfilePreset preset, int run)
        {
            try { ProfileImporter.Prepare(json); }
            catch (FormatException) { }
            catch (Exception e)
            {
                Assert.Fail($"{preset} n°{run} : {e.GetType().Name} {e.Message}\n{e.StackTrace}");
            }
        }
    }

    [Fact]
    public void ADamagedProjectNeverCrashes()
    {
        var random = new Random(Seed(2113));
        var valid = FlpSample.Sample().Encoded();
        for (var i = 0; i < 4000 * Scale; i++)
        {
            var data = Bytes(valid, random);
            try
            {
                var file = FlpFile.Parse(data);
                var project = new FlpProject(file);
                project.SplitByChannel(file);
            }
            catch (FlpException) { }
            catch (Exception e)
            {
                Assert.Fail($"projet n°{i} : {e.GetType().Name} {e.Message}\n{e.StackTrace}");
            }
        }
        _out.WriteLine($"{4000 * Scale} projets abîmés, aucune chute");
    }

    // MARK: fichiers abîmés

    /// Des octets changés, coupés, ajoutés, retirés ou doublés.
    private static byte[] Bytes(byte[] source, Random random)
    {
        var b = source.ToList();
        switch (random.Next(5))
        {
            case 0:
                for (var k = random.Next(1, 9); k > 0 && b.Count > 0; k--) b[random.Next(b.Count)] = (byte)random.Next(256);
                break;
            case 1:
                b = b.Take(random.Next(b.Count + 1)).ToList();
                break;
            case 2:
            {
                var extra = new byte[random.Next(1, 64)];
                random.NextBytes(extra);
                b.InsertRange(random.Next(b.Count + 1), extra);
                break;
            }
            case 3:
                if (b.Count > 1)
                {
                    var start = random.Next(b.Count);
                    b.RemoveRange(start, random.Next(1, Math.Min(64, b.Count - start) + 1));
                }
                break;
            default:
                if (b.Count > 1)
                {
                    var start = random.Next(b.Count);
                    b.InsertRange(start, b.Skip(start).Take(random.Next(1, 128)).ToList());
                }
                break;
        }
        return b.ToArray();
    }

    /// Une valeur du JSON remplacée par une autre d'un autre genre, ou retirée (le fichier reste du JSON).
    private static byte[] Json(byte[] source, Random random)
    {
        var root = JsonNode.Parse(source)!;
        for (var k = random.Next(1, 4); k > 0; k--)
        {
            var spots = new List<(JsonNode Parent, string? Key, int Index)>();
            Collect(root, spots);
            if (spots.Count == 0) break;
            var (parent, key, index) = spots[random.Next(spots.Count)];
            var remove = random.Next(5) == 0;
            if (parent is JsonObject o && key is not null)
            {
                if (remove) o.Remove(key); else o[key] = Value(random);
            }
            else if (parent is JsonArray a)
            {
                if (remove) a.RemoveAt(index); else a[index] = Value(random);
            }
        }
        return Encoding.UTF8.GetBytes(root.ToJsonString());

        static void Collect(JsonNode node, List<(JsonNode, string?, int)> spots)
        {
            if (node is JsonObject o)
                foreach (var (k, v) in o.ToList())
                {
                    spots.Add((o, k, -1));
                    if (v is not null) Collect(v, spots);
                }
            else if (node is JsonArray a)
                for (var i = 0; i < a.Count; i++)
                {
                    spots.Add((a, null, i));
                    if (a[i] is { } v) Collect(v, spots);
                }
        }
    }

    private static JsonNode? Value(Random random) => random.Next(13) switch
    {
        0 => null,
        1 => JsonValue.Create(true),
        2 => JsonValue.Create(-1),
        3 => JsonValue.Create(0),
        4 => JsonValue.Create(1e308),
        5 => JsonValue.Create(long.MaxValue),
        6 => JsonValue.Create(""),
        7 => JsonValue.Create("x"),
        8 => JsonValue.Create(new string('é', 20_000)),
        9 => new JsonArray(),
        10 => new JsonObject(),
        11 => JsonValue.Create(int.MinValue),
        _ => Deep(random.Next(1, 200)),
    };

    private static JsonNode Deep(int depth)
    {
        JsonNode node = new JsonArray();
        for (var i = 0; i < depth; i++) node = new JsonArray(node);
        return node;
    }
}
