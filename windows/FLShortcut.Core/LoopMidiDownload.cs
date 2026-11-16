// loopMIDI installé avec FL Shortcuts (16/11, « le loopmidi installation de lien a été oublié pour win », choix
// « Installer avec l'appli ») : loopMIDI (gratuit, Tobias Erichsen) est téléchargé sur le site de son auteur, par
// l'installeur (windows/installer/FLShortcut.iss, case cochée) et par « Installer loopMIDI » de l'accueil ; jamais
// copié dans FL Shortcuts. Seul ce fichier-là, reconnu à son empreinte, est ouvert puis lancé.
// L'installeur reprend ces valeurs telles quelles (essai LoopMidiDownloadTests.InstallerUsesTheSameFile).
using System.Security.Cryptography;

namespace FLShortcut.Core;

public static class LoopMidiDownload
{
    /// Archive officielle de loopMIDI 1.0.16.27, lien de sa page https://www.tobias-erichsen.de/software/loopmidi.html.
    public const string Url = "https://www.tobias-erichsen.de/wp-content/uploads/2020/01/loopMIDISetup_1_0_16_27.zip";

    /// Empreinte SHA-256 de cette archive (relevée le 16/11) : un autre fichier n'est jamais lancé.
    public const string Sha256 = "975399eb76e2c5a1d553ecd8975ab361261ccab8fd9412b8060b19877cb4e0d5";

    /// L'installeur dans l'archive (WiX) : il demande lui-même l'autorisation de Windows pour son pilote.
    public const string SetupName = "loopMIDISetup.exe";

    /// Barre de progression seule, rien à cliquer dedans ; jamais de redémarrage imposé.
    public const string SetupArguments = "/passive /norestart";

    /// L'archive téléchargée est bien celle de loopMIDI (même empreinte).
    public static bool IsGenuine(byte[] archive) =>
        archive.Length > 0 && Convert.ToHexString(SHA256.HashData(archive)).Equals(Sha256, StringComparison.OrdinalIgnoreCase);

    /// Code de fin de l'installeur qui veut dire « installé » (3010 : installé, redémarrage seulement conseillé).
    public static bool Succeeded(int exitCode) => exitCode is 0 or 3010;
}
