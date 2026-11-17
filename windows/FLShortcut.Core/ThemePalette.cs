// Thèmes de l'app (demande du 04/11 : « dans mon compte la possibilité de changer de thèmes »), miroir de
// Sources/FLShortcut/AppTheme.swift du Mac : Noir (le style suisse d'origine), Papier (blanc à l'encre noire), Orange
// (le rouge de la marque en fond, la barre de gauche en noir). Mêmes couleurs que le Mac, en 0xRRGGBB. Choisi dans
// Mon compte, gardé dans settings.json (« Theme ») : rien de sensible n'en dépend. Direction A du 17/11 (« J'aime bien
// le A », « A pour tous, thèmes gardés ») : Papier = la direction A, thème de tout le monde sans compte et par défaut.
namespace FLShortcut.Core;

public enum AppTheme { Noir, Papier, Orange }

/// Couleurs du style suisse dans un thème.
public sealed record ThemePalette(uint Background, uint Text, uint Gray, uint Soft, uint Line, uint Faint,
                                  uint KeyLine, uint Red, uint KeyFrame)
{
    /// Le rouge de la marque (#FF3B1F), le même dans tous les thèmes (logo).
    public const uint BrandRed = 0xFF3B1F;
    /// Rouge de la direction A (17/11), sur le papier.
    public const uint PaperRed = 0xC62D17;

    public static readonly ThemePalette Noir = new(0x000000, 0xFFFFFF, 0x8A8A8A, 0xA8A8A8, 0x333333, 0x222222,
                                                    0x555555, BrandRed, 0xDDDDDD);
    /// Direction A (17/11) : papier clair, encre presque noire, traits gris chaud, cadre des touches à l'encre.
    public static readonly ThemePalette Papier = new(0xF3F2EE, 0x111111, 0x67655F, 0x4A4843, 0xC9C6BE, 0xD9D6CF,
                                                      0x111111, PaperRed, 0x111111);
    /// Sur le fond orange, ce qui compte (touche changée, avertissement) est blanc : le rouge ne s'y verrait pas.
    public static readonly ThemePalette Orange = new(BrandRed, 0x000000, 0x3A0B03, 0x2A0702, 0xA62614, 0xD5341B,
                                                      0x5C1508, 0xFFFFFF, 0x000000);
    /// Parties noires sous Orange (barre de gauche).
    public static readonly ThemePalette OrangeInverse = new(0x000000, 0xFFFFFF, 0xB4B4B4, 0xC8C8C8, 0x2C2C2C, 0x222222,
                                                             0x555555, BrandRed, 0xDDDDDD);

    /// Couleurs d'un thème ; `inverse` : partie noire sous Orange (rien ne change dans les autres thèmes).
    public static ThemePalette Of(AppTheme theme, bool inverse = false) => theme switch
    {
        AppTheme.Papier => Papier,
        AppTheme.Orange => inverse ? OrangeInverse : Orange,
        _ => Noir,
    };

    /// Le thème clair de Windows (contrôles, barres de défilement) sous Papier et Orange, dont le texte est noir.
    public static bool IsLight(AppTheme theme) => theme != AppTheme.Noir;

    /// Nom gardé dans les réglages, le même que sur le Mac : « noir », « papier », « orange ».
    public static string Key(AppTheme theme) => theme switch
    {
        AppTheme.Papier => "papier",
        AppTheme.Orange => "orange",
        _ => "noir",
    };

    /// Thème affiché : le choisi seulement avec un compte connecté (demande du 07/11, comme le Mac), sinon Papier.
    public static AppTheme Shown(string? key, bool signedIn) => signedIn ? Parse(key) : AppTheme.Papier;

    /// Thème d'après le réglage ; Papier (direction A) si rien n'est choisi ou si la valeur est inconnue.
    public static AppTheme Parse(string? key) => key?.Trim().ToLowerInvariant() switch
    {
        "noir" => AppTheme.Noir,
        "orange" => AppTheme.Orange,
        _ => AppTheme.Papier,
    };
}
