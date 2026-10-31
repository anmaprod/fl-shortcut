// Bibliothèque des macros en blocs : le fichier macros.json, à part du profil (miroir de MacroLibraryCodec,
// Sources/FLShortcut/MacroLibraryStore.swift ; même format que le Mac : { "macros": [ … ], "version": 1 }).
// Lecture tolérante : une entrée qui n'est pas une macro est ignorée (comptée), un id en double est remplacé (deux
// macros ne partagent jamais un id) ; au-delà de 500 macros ou de 8 Mo, le fichier est refusé. C'est l'appli qui garde
// une copie avant d'écrire, et qui n'écrase jamais un fichier refusé.
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace FLShortcut.Core.Macros;

public static class MacroLibraryCodec
{
    public const int CurrentVersion = 1;
    public const int MaxBytes = 8 << 20;
    public const int MaxMacros = 500;

    /// `Dropped` : entrées illisibles ignorées.
    public sealed record Decoded(List<MacroDoc> Macros, int Version, int Dropped);

    /// Fichier refusé (le message, dans la langue de l'app, se montre tel quel).
    public sealed class Failure : Exception
    {
        private Failure(string message) : base(message) { }

        public static Failure Unreadable() => new(Loc.T("Format de bibliothèque illisible."));
        public static Failure TooMany() => new(Loc.F("Trop de macros (%lld au plus).", MaxMacros));
    }

    public static Decoded Decode(byte[] data)
    {
        if (data.Length > MaxBytes) throw Failure.Unreadable();
        JsonNode? root;
        try { root = JsonNode.Parse(data); }
        catch (JsonException) { throw Failure.Unreadable(); }
        if (J.Obj(root) is not { } o || J.Arr(o["macros"]) is not { } list) throw Failure.Unreadable();
        if (list.Count > MaxMacros) throw Failure.TooMany();
        var seen = new HashSet<Guid>();
        var macros = new List<MacroDoc>();
        foreach (var item in list)
        {
            if (J.Obj(item) is null) continue;
            var doc = MacroDoc.FromJson(item);
            if (!seen.Add(doc.Id))
            {
                doc.Id = Guid.NewGuid();
                seen.Add(doc.Id);
            }
            macros.Add(doc);
        }
        return new Decoded(macros, J.Int(o["version"]) ?? CurrentVersion, list.Count - macros.Count);
    }

    /// `pretty` : lisible dans un éditeur (le fichier) ; sans : plus court (sauvegarde en ligne).
    public static byte[] Encode(IEnumerable<MacroDoc> macros, bool pretty = true)
    {
        var o = new JsonObject
        {
            ["macros"] = new JsonArray(macros.Select(m => (JsonNode)m.ToJson()).ToArray()),
            ["version"] = CurrentVersion,
        };
        return Encoding.UTF8.GetBytes(o.ToJsonString(new JsonSerializerOptions { WriteIndented = pretty }));
    }
}
