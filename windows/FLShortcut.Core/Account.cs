// Compte (Windows), miroir de CommunityClient.swift du Mac : règles des champs (vérifiées avant tout envoi, le serveur
// les revérifie), requêtes de l'inscription en deux temps (code du mail), de la connexion, du mot de passe oublié, du
// pseudo, et lecture de la session renvoyée par le serveur. Jamais de mot de passe ni de jeton dans le journal.
using System.Text.Json;

namespace FLShortcut.Core;

/// Session du compte (gardée chiffrée par l'app, DPAPI).
public sealed record AccountSession(string AccessToken, string RefreshToken, DateTimeOffset ExpiresAt, Guid UserId,
                                    string Email, string Username)
{
    public bool Expired(DateTimeOffset now) => now >= ExpiresAt - TimeSpan.FromSeconds(60);
}

public static class AccountRules
{
    public const int MinPassword = 8;
    public const int MaxPhotoBytes = 72_000;
    public static string PasswordRule => Loc.T("8 caractères au moins, avec une minuscule, une majuscule, un chiffre et un symbole");
    private static readonly (string Name, string Chars)[] PasswordSets =
    {
        ("une minuscule", "abcdefghijklmnopqrstuvwxyz"),
        ("une majuscule", "ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
        ("un chiffre", "0123456789"),
        ("un symbole", "!@#$%^&*()_+-=[]{};'\\:\"|<>?,./`~"),
    };

    public static string? UsernameProblem(string s)
    {
        const string allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-";
        return s.Length is >= 3 and <= 24 && s.All(allowed.Contains)
            ? null
            : Loc.T("Pseudo : 3 à 24 caractères, lettres sans accent, chiffres, « _ », « . » ou « - ».");
    }

    /// Ce qui manque au mot de passe (« 2 caractères », « un chiffre »…), dans l'ordre du Mac ; vide : bon.
    public static List<string> PasswordMissing(string s)
    {
        var missing = new List<string>();
        var shortBy = MinPassword - s.Length;
        if (shortBy > 0) missing.Add(shortBy == 1 ? Loc.T("1 caractère") : Loc.F("%lld caractères", shortBy));
        foreach (var (name, chars) in PasswordSets)
            if (!s.Any(chars.Contains)) missing.Add(Loc.T(name));
        return missing;
    }

    /// Les 5 règles du mot de passe, dans l'ordre des pastilles du Mac (8 caractères, minuscule, majuscule, chiffre,
    /// symbole) : vrai quand elle est remplie.
    public static bool[] PasswordChecks(string s) =>
        new[] { s.Length >= MinPassword }.Concat(PasswordSets.Select(set => s.Any(set.Chars.Contains))).ToArray();

    public static string? PasswordProblem(string s) =>
        PasswordMissing(s).Count == 0 ? null : Loc.F("Mot de passe : %@.", PasswordRule);

    /// Photo du profil envoyée au serveur : un JPEG (commence par FF D8 FF) de 72 Ko au plus, ≈ 96 Ko en base64, la
    /// limite du serveur (comme ProfilePhoto.isAcceptable du Mac).
    public static bool PhotoAcceptable(byte[] jpeg) =>
        jpeg.Length is > 3 and <= MaxPhotoBytes && jpeg[0] == 0xFF && jpeg[1] == 0xD8 && jpeg[2] == 0xFF;

    /// Côté de la photo envoyée (comme le Mac).
    public const int PhotoSide = 256;

    /// Le carré visible de l'image, en pixels (origine en haut à gauche) : `zoom` ≥ 1 (1 : le plus grand carré centré),
    /// `dx`, `dy` de -1 à 1 : déplacement dans la marge (comme ProfilePhoto.cropRect du Mac).
    public static (int X, int Y, int Side) CropRect(int width, int height, double zoom = 1, double dx = 0, double dy = 0)
    {
        double w = width, h = height;
        var visible = Math.Min(w, h) / Math.Clamp(zoom, 1, 8);
        dx = Math.Clamp(dx, -1, 1);
        dy = Math.Clamp(dy, -1, 1);
        return ((int)Math.Round((w - visible) / 2 * (1 + dx)), (int)Math.Round((h - visible) / 2 * (1 + dy)), (int)Math.Round(visible));
    }

    /// Sans photo : la couleur de l'initiale, tirée du pseudo (la même sur le Mac et sur Windows, ProfilePhoto.colorIndex).
    public const int InitialColorCount = 8;

    public static int InitialColorIndex(string username)
    {
        var sum = 0;
        foreach (var rune in username.ToLowerInvariant().EnumerateRunes()) sum = unchecked(sum * 31 + rune.Value) & 0x7FFF_FFFF;
        return sum % InitialColorCount;
    }

    /// La lettre affichée (« fl.shortcuts » → « F » ; vide → « ? »).
    public static string Initial(string username)
    {
        foreach (var rune in username.EnumerateRunes())
            if (System.Text.Rune.IsLetterOrDigit(rune)) return System.Text.Rune.ToUpperInvariant(rune).ToString();
        return "?";
    }

    /// Code reçu par mail : 6 à 10 chiffres, espaces ignorés.
    public static string? Code(string s)
    {
        var digits = new string(s.Where(c => !char.IsWhiteSpace(c)).ToArray());
        return digits.Length is >= 6 and <= 10 && digits.All(c => c is >= '0' and <= '9') ? digits : null;
    }
}

public enum CodeKind { Signup, Recovery }

public static class AccountRequests
{
    public static HttpRequestMessage UsernameAvailable(ServerConfig c, string name) =>
        ServerRequests.Make(c, HttpMethod.Post, "rest/v1/rpc/username_available", body: new { name });

    public static HttpRequestMessage SignUp(ServerConfig c, string email, string password, string username)
    {
        Check(SupportRules.EmailProblem(email) ?? AccountRules.PasswordProblem(password) ?? AccountRules.UsernameProblem(username));
        return ServerRequests.Make(c, HttpMethod.Post, "auth/v1/signup", body: new { email, password, data = new { username } });
    }

    public static HttpRequestMessage SignIn(ServerConfig c, string email, string password)
    {
        Check(SupportRules.EmailProblem(email));
        return ServerRequests.Make(c, HttpMethod.Post, "auth/v1/token?grant_type=password", body: new { email, password });
    }

    public static HttpRequestMessage Refresh(ServerConfig c, AccountSession s) =>
        ServerRequests.Make(c, HttpMethod.Post, "auth/v1/token?grant_type=refresh_token", body: new { refresh_token = s.RefreshToken });

    public static HttpRequestMessage SignOut(ServerConfig c, AccountSession s) =>
        ServerRequests.Make(c, HttpMethod.Post, "auth/v1/logout", s.AccessToken);

    public static HttpRequestMessage ResetPassword(ServerConfig c, string email)
    {
        Check(SupportRules.EmailProblem(email));
        return ServerRequests.Make(c, HttpMethod.Post, "auth/v1/recover", body: new { email });
    }

    public static HttpRequestMessage VerifyCode(ServerConfig c, string email, string code, CodeKind kind)
    {
        var token = AccountRules.Code(code) ?? throw new ArgumentException(Loc.T("Le code fait 6 chiffres : recopie-le depuis le mail."));
        return ServerRequests.Make(c, HttpMethod.Post, "auth/v1/verify",
            body: new { type = kind == CodeKind.Signup ? "signup" : "recovery", email, token });
    }

    public static HttpRequestMessage ResendSignupCode(ServerConfig c, string email)
    {
        Check(SupportRules.EmailProblem(email));
        return ServerRequests.Make(c, HttpMethod.Post, "auth/v1/resend", body: new { type = "signup", email });
    }

    public static HttpRequestMessage UpdatePassword(ServerConfig c, string password, AccountSession s)
    {
        Check(AccountRules.PasswordProblem(password));
        return ServerRequests.Make(c, HttpMethod.Put, "auth/v1/user", s.AccessToken, new { password });
    }

    /// Nouveau pseudo (supabase/profil.sql : set_username, comme le Mac) ; renvoie le pseudo gardé par le serveur.
    public static HttpRequestMessage SetUsername(ServerConfig c, string name, AccountSession s)
    {
        Check(AccountRules.UsernameProblem(name));
        return ServerRequests.Make(c, HttpMethod.Post, "rest/v1/rpc/set_username", s.AccessToken, new { p_name = name });
    }

    /// Pose ou remplace la photo du compte (JPEG carré déjà préparé, 256 × 256 au plus, comme ProfilePhoto du Mac).
    public static HttpRequestMessage SetAvatar(ServerConfig c, byte[] jpeg, AccountSession s)
    {
        if (!AccountRules.PhotoAcceptable(jpeg)) throw new ArgumentException(Loc.T("Photo trop grande ou illisible : choisis-en une autre."));
        return ServerRequests.Make(c, HttpMethod.Post, "rest/v1/rpc/set_avatar", s.AccessToken, new { p_image = Convert.ToBase64String(jpeg) });
    }

    public static HttpRequestMessage RemoveAvatar(ServerConfig c, AccountSession s) =>
        ServerRequests.Make(c, HttpMethod.Post, "rest/v1/rpc/remove_avatar", s.AccessToken, new { });

    /// Supprime le compte, sa sauvegarde et ses partages (supabase : delete_my_account).
    public static HttpRequestMessage DeleteAccount(ServerConfig c, AccountSession s) =>
        ServerRequests.Make(c, HttpMethod.Post, "rest/v1/rpc/delete_my_account", s.AccessToken, new { });

    /// Photos de ces membres (une requête pour toutes, 60 au plus, sans doublon ; comme CommunityClient.avatars).
    public static HttpRequestMessage Avatars(ServerConfig c, IEnumerable<Guid> ids, AccountSession s) =>
        ServerRequests.Make(c, HttpMethod.Get,
            "rest/v1/avatars?select=user_id,image,updated_at&user_id=" + Uri.EscapeDataString(AvatarFilter(ids)), s.AccessToken);

    public static string AvatarFilter(IEnumerable<Guid> ids) =>
        "in.(" + string.Join(",", ids.Distinct().Take(60).Select(g => g.ToString("D").ToLowerInvariant())) + ")";

    /// Photos lues (image illisible ou trop grande ignorée).
    public static Dictionary<Guid, byte[]> DecodeAvatars(string json)
    {
        var photos = new Dictionary<Guid, byte[]>();
        try
        {
            foreach (var row in JsonDocument.Parse(json).RootElement.EnumerateArray())
            {
                if (!row.TryGetProperty("user_id", out var id) || !id.TryGetGuid(out var user)) continue;
                if (!row.TryGetProperty("image", out var image) || image.ValueKind != JsonValueKind.String) continue;
                byte[] jpeg;
                try { jpeg = Convert.FromBase64String(image.GetString()!); } catch (FormatException) { continue; }
                if (AccountRules.PhotoAcceptable(jpeg)) photos.TryAdd(user, jpeg);
            }
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException) { }
        return photos;
    }

    private static void Check(string? why)
    {
        if (why is not null) throw new ArgumentException(why);
    }

    /// La session renvoyée par le serveur (connexion, code, rafraîchissement) ; null si la réponse n'en est pas une
    /// (inscription : « confirme ton adresse avec le code »).
    public static AccountSession? DecodeSession(string json, DateTimeOffset now)
    {
        try
        {
            var root = JsonDocument.Parse(json).RootElement;
            var user = root.GetProperty("user");
            var username = user.TryGetProperty("user_metadata", out var meta) && meta.ValueKind == JsonValueKind.Object
                           && meta.TryGetProperty("username", out var u) && u.ValueKind == JsonValueKind.String ? u.GetString()! : "";
            return new AccountSession(
                root.GetProperty("access_token").GetString()!,
                root.GetProperty("refresh_token").GetString()!,
                now.AddSeconds(root.GetProperty("expires_in").GetDouble()),
                user.GetProperty("id").GetGuid(),
                user.TryGetProperty("email", out var e) && e.ValueKind == JsonValueKind.String ? e.GetString()! : "",
                username);
        }
        catch (Exception ex) when (ex is JsonException or KeyNotFoundException or InvalidOperationException or FormatException)
        {
            return null;
        }
    }

    /// Message du serveur, traduit pour les cas courants (comme CommunityClient.message du Mac).
    public static string ServerMessage(string json, int status = 0)
    {
        string raw = "", code = "";
        try
        {
            var root = JsonDocument.Parse(json).RootElement;
            foreach (var key in new[] { "error_description", "msg", "message", "error" })
                if (root.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String) { raw = v.GetString()!; break; }
            if (root.TryGetProperty("error_code", out var c) && c.ValueKind == JsonValueKind.String) code = c.GetString()!;
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException) { }
        var lower = raw.ToLowerInvariant();
        if (lower.Contains("invalid login credentials")) return Loc.T("Mail ou mot de passe incorrect.");
        if (lower.Contains("email not confirmed") || code == "email_not_confirmed") return Unconfirmed;
        if (lower.Contains("already registered") || lower.Contains("already exists")) return Loc.T("Un compte existe déjà avec ce mail.");
        if (code == "otp_expired" || lower.Contains("token has expired") || lower.Contains("token is invalid") || lower.Contains("otp has expired"))
            return Loc.T("Code incorrect ou expiré : vérifie-le, ou demande un nouveau code.");
        if (code == "same_password" || lower.Contains("should be different")) return Loc.T("Choisis un mot de passe différent de l'ancien.");
        if (code == "weak_password" || lower.Contains("password should")) return Loc.F("Mot de passe trop faible : %@.", AccountRules.PasswordRule);
        if (lower.Contains("error sending") || lower.Contains("not authorized"))
            return Loc.T("Le mail de confirmation n'a pas pu partir. Réessaie plus tard, ou écris à l'équipe depuis la page Aide.");
        if (lower.Contains("trop de partages") || lower.Contains("trop de messages") || lower.StartsWith("attends ")
            || lower.StartsWith("réservé aux administrateurs")) return raw;
        if (lower.Contains("pseudo déjà pris") || lower.Contains("profiles_username")) return Loc.T("Ce pseudo est déjà pris.");
        if (lower.Contains("pseudo invalide")) return AccountRules.UsernameProblem("")!;
        if (lower.Contains("avatars_image_check")) return Loc.T("Photo trop grande ou illisible : choisis-en une autre.");
        if (status is 401 or 403) return Loc.T("Session expirée : reconnecte-toi.");
        if (status == 429) return Loc.T("Trop de tentatives : réessaie dans quelques minutes.");
        if (raw.Length > 0) return status > 0 ? Loc.F("Erreur du serveur : %@", raw.Length > 200 ? raw[..200] : raw) : raw;
        return status > 0 ? Loc.F("Erreur du serveur (%lld).", status) : Loc.T("Le serveur n'a pas répondu.");
    }

    public static string Unconfirmed => Loc.T("Confirme d'abord ton adresse mail avec le code reçu par mail.");
}
