// Windows MIDI Services (21/11, « on va utiliser celui de win déjà pour essayer ») : sur Windows 11 25H2 et plus récent,
// le service MIDI de Windows et ses ports « boucle » MIDI 1.0 sont déjà dans Windows, mais pas encore son API
// (Windows.Devices.Midi2) : l'appli en porte sa propre copie, celle du paquet de Microsoft (préversion 11, licence MIT),
// à côté de son exécutable. Avant, seules les métadonnées étaient livrées : l'API n'était jamais trouvée et l'appli
// passait toujours par loopMIDI.
//
// Accord de Microsoft pour cette préversion (« Developer Go-live agreement », release inbox-preview-11) : jamais sur un
// Windows plus ancien que 11 25H2, retirée quand l'API arrivera dans Windows, et les gens prévenus qu'elle est en
// préversion. D'où : l'installeur ne copie la DLL que sur 25H2 ou plus récent (FLShortcut.iss, MidiServicesWindows) et
// l'appli ne s'en sert jamais en dessous (MidiServicesPorts.CheckAvailable).
//
// Le paquet n'est pas sur nuget.org ni dans le dépôt : la CI le télécharge à la release de Microsoft et n'en garde les
// fichiers que si son empreinte est la bonne (build.yml, essai MidiServicesSupportTests.TheBuildUsesTheSamePackage).

namespace FLShortcut.Core;

public static class MidiServicesSupport
{
    /// Windows 11 25H2 (build 26200) : la première version où Microsoft permet d'utiliser cette copie de l'API.
    public const int MinBuild = 26200;

    /// La copie de l'API de Microsoft, à côté de FLShortcut.exe (avec son .pri).
    public const string ApiFile = "Windows.Devices.Midi2.dll";

    /// Le paquet de Microsoft (release inbox-preview-11 de github.com/microsoft/MIDI) et son empreinte SHA-256
    /// (relevée le 21/11) : un autre fichier n'est jamais gardé.
    public const string PackageUrl =
        "https://github.com/microsoft/MIDI/releases/download/inbox-preview-11/Windows.Devices.Midi2.0.99.92-preview.11.nupkg";
    public const string PackageSha256 = "13afc6e6da2adac309ab8c174352f46f1c0ebe2d79e65475bd6274defb73df74";

    /// Ce Windows a le service MIDI et peut recevoir la copie de l'API.
    public static bool Supported(int build) => build >= MinBuild;
}
