// Mises à jour toutes seules (19/11, « que notre logiciel puisse être corrigé sans que les gens soient obligés de
// réinstaller l'appli » ; choix : « toute seule », publiée seulement quand le propriétaire dit « publie »), miroir de
// UpdateRules (AutoUpdate.swift du Mac) : manifeste `mise-a-jour.json` de la dernière release GitHub, signé ECDSA P-256
// (clé privée dans le secret UPDATE_SIGNING_KEY de la CI, clé publique ci-dessous, la même que le Mac), version plus
// récente, fichier venu des releases du dépôt, à la bonne empreinte SHA-256. Pur, testé.
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace FLShortcut.Core;

public static class UpdateRules
{
    /// Clé publique des mises à jour (la même que le Mac : essai `SameUpdateKeyAsTheMac`).
    public const string PublicKeyPem = """
        -----BEGIN PUBLIC KEY-----
        MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEXPKipXXg5IdHrF853+ZvA8rchhVc
        D/lYlcrmIHxvRARtPignnY4tUj4YCGnQwGcJKcP4UymK7KVj6gt/sr9rIg==
        -----END PUBLIC KEY-----
        """;
    public static readonly Uri ManifestUri = new("https://github.com/anmaprod/fl-shortcut/releases/latest/download/mise-a-jour.json");
    public static readonly Uri SignatureUri = new("https://github.com/anmaprod/fl-shortcut/releases/latest/download/mise-a-jour.json.sig");
    /// Seules adresses de téléchargement acceptées : les releases du dépôt.
    public const string DownloadPrefix = "https://github.com/anmaprod/fl-shortcut/releases/download/";
    /// L'installeur en silence ; `/UPDATE=1` lui fait relancer l'appli à la fin (FLShortcut.iss, IsUpdate).
    public const string InstallerArguments = "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /UPDATE=1";

    public sealed record Asset(string Url, string Sha256);
    public sealed record Manifest(string Version, Asset? Mac, Asset? Windows);

    /// Le manifeste, seulement si sa signature (base64 d'une signature DER) est celle de la clé de l'appli et qu'il a
    /// une version X.Y.Z ; null sinon.
    public static Manifest? Verified(byte[] data, byte[] signature, string? publicKeyPem = null)
    {
        try
        {
            using var key = ECDsa.Create();
            key.ImportFromPem(publicKeyPem ?? PublicKeyPem);
            var der = Convert.FromBase64String(Encoding.UTF8.GetString(signature).Trim());
            if (!key.VerifyData(data, der, HashAlgorithmName.SHA256, DSASignatureFormat.Rfc3279DerSequence)) return null;
            using var doc = JsonDocument.Parse(data);
            var root = doc.RootElement;
            var version = root.GetProperty("version").GetString() ?? "";
            if (Components(version) is null) return null;
            return new Manifest(version, AssetOf(root, "mac"), AssetOf(root, "windows"));
        }
        catch (Exception e) when (e is FormatException or CryptographicException or JsonException or ArgumentException
                                      or InvalidOperationException or KeyNotFoundException)
        {
            return null;
        }
    }

    private static Asset? AssetOf(JsonElement root, string name)
    {
        if (!root.TryGetProperty(name, out var a) || a.ValueKind != JsonValueKind.Object) return null;
        var url = a.TryGetProperty("url", out var u) ? u.GetString() : null;
        var sha = a.TryGetProperty("sha256", out var s) ? s.GetString() : null;
        return url is null || sha is null ? null : new Asset(url, sha);
    }

    /// « 1.2.3 » → [1, 2, 3] ; null pour toute autre forme.
    public static int[]? Components(string version)
    {
        var parts = version.Split('.');
        if (parts.Length != 3) return null;
        var numbers = new int[3];
        for (var i = 0; i < 3; i++)
        {
            var p = parts[i];
            if (p.Length is 0 or > 6 || !p.All(char.IsAsciiDigit)) return null;
            numbers[i] = int.Parse(p, System.Globalization.CultureInfo.InvariantCulture);
        }
        return numbers;
    }

    /// `candidate` est-elle plus récente que `current` ? Faux si l'une n'est pas de la forme X.Y.Z.
    public static bool IsNewer(string candidate, string current)
    {
        if (Components(candidate) is not { } a || Components(current) is not { } b) return false;
        for (var i = 0; i < 3; i++)
            if (a[i] != b[i]) return a[i] > b[i];
        return false;
    }

    /// L'adresse d'un fichier de la mise à jour, seulement dans les releases du dépôt (HTTPS, sans « .. »).
    public static Uri? DownloadUri(string text)
    {
        if (!text.StartsWith(DownloadPrefix, StringComparison.Ordinal) || text.Contains("..") || text.Contains('\\')) return null;
        return Uri.TryCreate(text, UriKind.Absolute, out var uri) && uri.Scheme == Uri.UriSchemeHttps && uri.Host == "github.com"
            ? uri : null;
    }

    /// Empreinte SHA-256 en hexadécimal minuscule.
    public static string Sha256Hex(Stream stream) => Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();

    /// Poser la mise à jour maintenant ? Jamais pendant que FL tourne, ni quand la fenêtre de l'appli est ouverte.
    public static bool CanInstall(bool flRunning, bool windowOpen) => !flRunning && !windowOpen;
}
