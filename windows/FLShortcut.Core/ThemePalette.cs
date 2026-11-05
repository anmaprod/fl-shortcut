// Thèmes de l'app (demande du 04/11 : « dans mon compte la possibilité de changer de thèmes »), miroir de
// Sources/FLShortcut/AppTheme.swift du Mac : Noir (le style suisse d'origine), Papier (blanc à l'encre noire), Orange
// (le rouge de la marque en fond, la barre de gauche en noir). Mêmes couleurs que le Mac, en 0xRRGGBB. Choisi dans
// Mon compte, gardé dans settings.json (« Theme ») : rien de sensible n'en dépend.
namespace FLShortcut.Core;

public enum AppTheme { Noir, Papier, Orange }

/// Couleurs du style suisse dans un thème.
public sealed record ThemePalette(uint Background, uint Text, uint Gray, uint Soft, uint Line, uint Faint,
                                  uint KeyLine, uint Red, uint KeyFrame)
{
    /// Le rouge de la marque (#FF3B1F), le même dans tous les thèmes (logo).
    public const uint BrandRed = 0xFF3B1F;

    public static readonly ThemePalette Noir = new(0x000000, 0xFFFFFF, 0x8A8A8A, 0xA8A8A8, 0x333333, 0x222222,
                                                    0x555555, BrandRed, 0xDDDDDD);
    public static readonly ThemePalette Papier = new(0xFFFFFF, 0x000000, 0x6E6E6E, 0x555555, 0xCFCFCF, 0xE6E6E6,
                                                      0xAAAAAA, BrandRed, 0x333333);
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

    /// Thème d'après le réglage ; Noir si rien n'est choisi ou si la valeur est inconnue.
    public static AppTheme Parse(string? key) => key?.Trim().ToLowerInvariant() switch
    {
        "papier" => AppTheme.Papier,
        "orange" => AppTheme.Orange,
        _ => AppTheme.Noir,
    };
}
