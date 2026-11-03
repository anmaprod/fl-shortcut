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

    public static string? PasswordProblem(string s) =>
        PasswordMissing(s).Count == 0 ? null : Loc.F("Mot de passe : %@.", PasswordRule);

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

    /// Nouveau pseudo (supabase/profil.sql : set_my_username) ; les partages déjà publiés prennent le nouveau.
    public static HttpRequestMessage SetUsername(ServerConfig c, string name, AccountSession s)
    {
        Check(AccountRules.UsernameProblem(name));
        return ServerRequests.Make(c, HttpMethod.Post, "rest/v1/rpc/set_my_username", s.AccessToken, new { name });
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

    /// Message du serveur, traduit pour les cas courants (comme le Mac).
    public static string ServerMessage(string json)
    {
        string raw = "", code = "";
        try
        {
            var root = JsonDocument.Parse(json).RootElement;
            foreach (var key in new[] { "error_description", "msg", "message", "error" })
                if (root.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String) { raw = v.GetString()!; break; }
            if (root.TryGetProperty("error_code", out var c) && c.ValueKind == JsonValueKind.String) code = c.GetString()!;
        }
        catch (JsonException) { }
        var lower = raw.ToLowerInvariant();
        if (lower.Contains("invalid login credentials")) return Loc.T("Mail ou mot de passe incorrect.");
        if (lower.Contains("email not confirmed") || code == "email_not_confirmed")
            return Loc.T("Confirme d'abord ton adresse mail avec le code reçu par mail.");
        if (lower.Contains("already registered") || lower.Contains("already exists")) return Loc.T("Un compte existe déjà avec ce mail.");
        if (code == "otp_expired" || lower.Contains("token has expired") || lower.Contains("token is invalid") || lower.Contains("otp has expired"))
            return Loc.T("Code incorrect ou expiré : vérifie-le, ou demande un nouveau code.");
        if (code == "same_password" || lower.Contains("should be different")) return Loc.T("Choisis un mot de passe différent de l'ancien.");
        if (code == "weak_password" || lower.Contains("password should")) return Loc.F("Mot de passe trop faible : %@.", AccountRules.PasswordRule);
        return raw.Length > 0 ? raw : Loc.T("Le serveur n'a pas répondu.");
    }
}
