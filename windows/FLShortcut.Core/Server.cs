// Serveur du compte, de la Communauté et de l'Aide (Supabase, le même que le Mac : supabase/*.sql). Adresse et clé
// publique (anon) écrites dans l'app à la compilation (CI : FLS_SUPABASE_URL, FLS_SUPABASE_ANON_KEY → métadonnées de
// l'assembly, comme l'Info.plist du Mac) ; HTTPS seulement ; jamais de clé secrète. Requêtes construites ici (testées),
// envoyées par l'app.
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace FLShortcut.Core;

public sealed record ServerConfig(Uri Url, string AnonKey)
{
    /// Comme CommunityConfig.resolve du Mac : https, une adresse sans nom d'utilisateur, une clé ; sinon pas de serveur.
    public static ServerConfig? Resolve(string? url, string? anonKey)
    {
        if (string.IsNullOrWhiteSpace(url) || string.IsNullOrWhiteSpace(anonKey)) return null;
        if (!Uri.TryCreate(url.Trim(), UriKind.Absolute, out var uri)) return null;
        if (uri.Scheme != Uri.UriSchemeHttps || string.IsNullOrEmpty(uri.Host) || uri.UserInfo.Length > 0) return null;
        return new ServerConfig(uri, anonKey.Trim());
    }
}

public static class ServerRequests
{
    /// Requête REST : « apikey » toujours ; « Authorization » seulement avec un jeton de session (sans compte, la clé
    /// publique seule, comme le Mac).
    public static HttpRequestMessage Make(ServerConfig config, HttpMethod method, string path, string? token = null,
                                          object? body = null)
    {
        var request = new HttpRequestMessage(method, new Uri(config.Url, path));
        request.Headers.Add("apikey", config.AnonKey);
        if (token is not null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        if (body is not null)
            request.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");
        return request;
    }

    /// Message à l'équipe (table support_requests, avec ou sans compte) ; refusé avant l'envoi s'il ne suit pas les
    /// règles (le serveur les revérifie).
    /// `oldForm` : pour un serveur sans supabase/mes-messages.sql (20/11), sans capture et « Autre » comme une question.
    public static HttpRequestMessage Support(ServerConfig config, SupportMessage message, string appVersion, string? token,
                                             bool oldForm = false)
    {
        if (SupportRules.Problem(message) is { } why) throw new ArgumentException(why);
        var body = new Dictionary<string, string>
        {
            ["kind"] = oldForm && message.Kind == SupportKind.Autre ? SupportKind.Question.Raw() : message.Kind.Raw(),
            ["reference"] = message.Reference,
            ["message"] = message.Text.Trim(),
            ["error"] = Cut(message.Error ?? "", 2000),
            ["diagnostic"] = Cut(message.Diagnostic ?? "", SupportRules.MaxDiagnostic),
            ["app_version"] = Cut(appVersion, 20),
        };
        var mail = message.Email.Trim();
        if (mail.Length > 0) body["email"] = mail;
        if (!oldForm && message.Capture is { Length: > 0 } capture) body["capture"] = capture;
        return Make(config, HttpMethod.Post, "rest/v1/support_requests", token, body);
    }

    /// Aide › Mes messages (20/11) : mes messages, les plus récents d'abord, avec leurs réponses.
    public static HttpRequestMessage MyMessages(ServerConfig config, AccountSession session) =>
        Make(config, HttpMethod.Get, "rest/v1/support_requests?select=id,kind,reference,message,created_at,"
            + "support_replies(id,team,message,created_at)&user_id=eq." + session.UserId.ToString().ToLowerInvariant()
            + "&order=created_at.desc&limit=100", session.AccessToken);

    /// La capture d'un de mes messages.
    public static HttpRequestMessage MessageCapture(ServerConfig config, AccountSession session, Guid id) =>
        Make(config, HttpMethod.Get, "rest/v1/support_requests?select=capture&id=eq." + id.ToString().ToLowerInvariant(),
             session.AccessToken);

    /// Répondre à l'équipe dans un de mes messages.
    public static HttpRequestMessage ReplySupport(ServerConfig config, AccountSession session, Guid id, string text)
    {
        var clean = text.Trim();
        if (clean.Length == 0) throw new ArgumentException(Loc.T("Ta réponse est vide."));
        return Make(config, HttpMethod.Post, "rest/v1/support_replies", session.AccessToken,
                    new Dictionary<string, string> { ["request_id"] = id.ToString().ToLowerInvariant(), ["message"] = Cut(clean, 4000) });
    }

    private static string Cut(string s, int max) => s.Length > max ? s[..max] : s;
}
