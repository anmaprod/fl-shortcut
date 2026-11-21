// JSON venu d'ailleurs (macro de la Communauté ou importée, raccourcis partagés, fichier relu) : lu et vérifié EN ENTIER
// à l'ouverture (21/11, trouvé par RobustnessTests). JsonNode lit paresseusement : un texte mal encodé (UTF-8 invalide)
// ou une clé en double ne levait une erreur qu'au moment où l'on y touchait, avec une exception que l'appli n'attendait
// pas (InvalidOperationException, ArgumentException) : elle tombait sur une macro ou des raccourcis piégés.
// Ici, la seule erreur possible est FormatException (sa cause gardée dedans) ; une fois lu, tout l'arbre est sûr.
using System.Text.Json;
using System.Text.Json.Nodes;

namespace FLShortcut.Core;

public static class UntrustedJson
{
    /// Le JSON entier, vérifié ; FormatException sinon.
    public static JsonNode? Parse(byte[] utf8, JsonDocumentOptions options = default)
    {
        if (!System.Text.Unicode.Utf8.IsValid(utf8)) throw new FormatException("JSON : UTF-8 invalide");
        return Checked(() => JsonNode.Parse(utf8, documentOptions: options));
    }

    /// Le JSON entier, vérifié ; FormatException sinon.
    public static JsonNode? Parse(string text, JsonDocumentOptions options = default) =>
        Checked(() => JsonNode.Parse(text, documentOptions: options));

    private static JsonNode? Checked(Func<JsonNode?> parse)
    {
        try
        {
            var root = parse();
            Touch(root);
            return root;
        }
        catch (Exception e) when (e is JsonException or ArgumentException or InvalidOperationException)
        {
            throw new FormatException("JSON illisible", e);
        }
    }

    /// Chaque objet, liste et texte lu une fois : les clés en double et les textes mal encodés se montrent ici.
    private static void Touch(JsonNode? node)
    {
        switch (node)
        {
            case JsonObject o:
                foreach (var (_, value) in o) Touch(value);
                break;
            case JsonArray a:
                foreach (var item in a) Touch(item);
                break;
            case JsonValue v when v.TryGetValue<JsonElement>(out var element) && element.ValueKind == JsonValueKind.String:
                _ = element.GetString();
                break;
        }
    }
}
