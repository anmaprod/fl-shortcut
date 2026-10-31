// Bloc « Nom et couleur » : nommer et colorer l'élément sélectionné de la page de FL qui est devant (piste du Mixer,
// canal du Channel rack, piste de la Playlist), par la commande avec données du lien (PROTOCOL.md §7, opération 1).
// Miroir de NameColorPayload (Sources/FLShortcut/NameColor.swift). Le nom n'est jamais écrit dans un journal.
using FLShortcut.Core.Organizer;

namespace FLShortcut.Core.Macros;

/// Données de l'opération 1 : `[1, drapeaux (bit 0 nom, bit 1 couleur), R, G, B, n, nom UTF-8 (n octets)]`.
public sealed record NameColorPayload
{
    /// Le script compte les points de code (Python) : même mesure ici.
    public const int MaxNameScalars = 64;
    /// La longueur du nom tient sur un octet.
    public const int MaxNameBytes = 255;

    /// Rouge de départ du bloc (un bloc neuf est valable tel quel).
    public static readonly RgbColor DefaultColor = new(0xE0, 0x45, 0x3A);

    /// Nom sans espaces de début ni de fin ; null s'il est vide.
    public string? Name { get; }
    public RgbColor? Color { get; }

    public NameColorPayload(string? name, RgbColor? color)
    {
        var trimmed = name?.Trim();
        Name = string.IsNullOrEmpty(trimmed) ? null : trimmed;
        Color = color;
    }

    /// Nom acceptable par le script : 64 caractères au plus, 255 octets au plus, aucun caractère de contrôle.
    public static string? NameProblem(string name)
    {
        if (name.EnumerateRunes().Any(r => r.Value < 32 || r.Value == 127)) return Loc.T("le nom contient un caractère invisible.");
        if (name.EnumerateRunes().Count() > MaxNameScalars || System.Text.Encoding.UTF8.GetByteCount(name) > MaxNameBytes)
            return Loc.T("nom trop long (64 caractères au plus).");
        return null;
    }

    public byte[] Bytes
    {
        get
        {
            var raw = System.Text.Encoding.UTF8.GetBytes(Name ?? "").Take(MaxNameBytes).ToArray();
            var flags = (byte)((Name is not null ? 1 : 0) | (Color is not null ? 2 : 0));
            var c = Color ?? new RgbColor(0, 0, 0);
            return new byte[] { 1, flags, c.R, c.G, c.B, (byte)raw.Length }.Concat(raw).ToArray();
        }
    }

    /// Ligne du bloc : « Kick · #E0453A », « Kick », « couleur #E0453A », « dégradé #F2A0D8 → #C02890 ».
    public static string Summary(string? name, RgbColor? color, RgbColor? fade = null, FlIcon? icon = null)
    {
        if (color is { } from && fade is { } to) return Loc.F("dégradé #%@ → #%@", from.Hex, to.Hex);
        var n = new NameColorPayload(name, color);
        var parts = new List<string>();
        if (n.Name is { } shown) parts.Add(DisplayText.Safe(shown, 40));
        if (n.Color is { } c) parts.Add(n.Name is null ? Loc.F("couleur #%@", c.Hex) : $"#{c.Hex}");
        if (icon is { } i) parts.Add(Loc.F("icône %@", i.Code));
        return parts.Count == 0 ? Loc.T("nom et couleur à choisir") : string.Join(" · ", parts);
    }

    /// Message d'un refus expliqué par FL (CC 116).
    public static string Message(int reason) => reason switch
    {
        1 => Loc.T("Ouvre le Mixer, le Channel rack ou la Playlist."),
        2 => Loc.T("Sélectionne une piste ou un canal."),
        3 => Loc.T("Sélectionne une seule piste ou un seul canal."),
        4 => Loc.T("Arrête la lecture d'abord."),
        6 => Loc.T("Ta version de FL ne le permet pas sur cette page : mets FL à jour."),
        7 => Loc.T("Sélectionne au moins 2 pistes pour un dégradé."),
        _ => Loc.T("FL a refusé le nom ou la couleur."),
    };
}
