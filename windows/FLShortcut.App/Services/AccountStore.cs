// Session du compte gardée sur ce PC (comme le Trousseau du Mac, « cet appareil seulement ») : chiffrée par Windows
// pour cet utilisateur (DPAPI), dans %LOCALAPPDATA%\FL Shortcuts\compte.bin, écrite d'un coup, jamais par un lien.
// Jamais de mot de passe ici : seulement les jetons de la session, le mail et le pseudo.
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using FLShortcut.Core;

namespace FLShortcut.App.Services;

internal static class AccountStore
{
    private static string FilePath => Path.Combine(AppPaths.Local, "compte.bin");
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("FL Shortcuts account session v1");

    public static AccountSession? Load()
    {
        try
        {
            if (!File.Exists(FilePath)) return null;
            SafeFile.EnsureNoLinks(FilePath);
            var json = ProtectedData.Unprotect(File.ReadAllBytes(FilePath), Entropy, DataProtectionScope.CurrentUser);
            return JsonSerializer.Deserialize<AccountSession>(json);
        }
        catch (Exception e)
        {
            AppLog.Write("ACCOUNT", "session illisible : " + e.GetType().Name);
            return null;
        }
    }

    /// null : déconnecté (le fichier est effacé).
    public static void Save(AccountSession? session)
    {
        try
        {
            if (session is null)
            {
                if (File.Exists(FilePath)) File.Delete(FilePath);
                return;
            }
            var json = JsonSerializer.SerializeToUtf8Bytes(session);
            SafeFile.WriteAtomic(FilePath, ProtectedData.Protect(json, Entropy, DataProtectionScope.CurrentUser));
        }
        catch (Exception e)
        {
            AppLog.Write("ACCOUNT", "session non gardée : " + e.GetType().Name);
        }
    }
}
