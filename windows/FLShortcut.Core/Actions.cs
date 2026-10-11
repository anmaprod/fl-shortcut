// Audit : SEC-05 (liste blanche d'ids), audit 04 (versions minimales, « Disponible à partir de FL X »),
//         PROTOCOL.md §6 (table des 38 actions, ids figés). Miroir de Sources/FLShortcut/Actions.swift.
namespace FLShortcut.Core;

public enum ActionCategory { Composition, Recording, Mix, Navigation }

public sealed record FlActionInfo(int Id, string Key, string Label, ActionCategory Category, string MinFl)
{
    public string CategoryLabel => Category switch
    {
        ActionCategory.Composition => "Composition",
        ActionCategory.Recording => "Enregistrement",
        ActionCategory.Mix => "Mix",
        _ => "Navigation",
    };
}

public static class FlActions
{
    /// Version minimale de FL pour le scripting Python (audit 04).
    public const string PythonMinFl = "20.7";

    public static readonly IReadOnlyList<FlActionInfo> All = new FlActionInfo[]
    {
        new(1, "play", "Lecture / Pause", ActionCategory.Recording, "20.7"),
        new(2, "stop", "Stop", ActionCategory.Recording, "20.7"),
        new(3, "rec", "Lancer le REC", ActionCategory.Recording, "20.7"),
        new(4, "metro", "Métronome", ActionCategory.Recording, "20.7"),
        new(5, "count", "Décompte", ActionCategory.Recording, "20.7"),
        new(6, "loop", "Enregistrement en boucle", ActionCategory.Recording, "20.7"),
        new(7, "wait", "Attendre une note", ActionCategory.Recording, "20.7"),
        new(8, "marker", "Poser un marqueur", ActionCategory.Recording, "20.7"),
        new(9, "arm", "Armer la piste (Mixer sélectionnée)", ActionCategory.Recording, "20.7"),
        new(10, "tap", "Tap tempo", ActionCategory.Composition, "20.7"),
        new(11, "newpat", "Nouveau pattern + Piano Roll", ActionCategory.Composition, "20.7"),
        new(12, "clone", "Cloner le pattern", ActionCategory.Composition, "21.0.3"),
        new(13, "pnext", "Pattern suivant", ActionCategory.Composition, "20.7"),
        new(14, "pprev", "Pattern précédent", ActionCategory.Composition, "20.7"),
        new(15, "chnext", "Instrument suivant", ActionCategory.Composition, "20.7"),
        new(16, "chprev", "Instrument précédent", ActionCategory.Composition, "20.7"),
        new(17, "snap", "Grille suivante", ActionCategory.Composition, "20.7"),
        new(18, "quant", "Quantize rapide", ActionCategory.Composition, "20.8"),
        new(19, "presetnext", "Preset suivant", ActionCategory.Composition, "20.8.1"),
        new(20, "presetprev", "Preset précédent", ActionCategory.Composition, "20.8.1"),
        new(21, "mute", "Mute piste Mixer sélectionnée", ActionCategory.Mix, "20.7"),
        new(22, "solo", "Solo piste Mixer sélectionnée", ActionCategory.Mix, "20.7"),
        new(23, "unsolo", "Retirer tous les solos", ActionCategory.Mix, "20.7"),
        new(24, "bypass", "Bypass des effets de la piste", ActionCategory.Mix, "20.9.1"),
        new(25, "mono", "Master en mono", ActionCategory.Mix, "20.8.2"),
        new(26, "trnext", "Piste Mixer suivante", ActionCategory.Mix, "20.7"),
        new(27, "trprev", "Piste Mixer précédente", ActionCategory.Mix, "20.7"),
        new(28, "volup", "Volume piste +0,5 dB", ActionCategory.Mix, "20.7"),
        new(29, "voldn", "Volume piste −0,5 dB", ActionCategory.Mix, "20.7"),
        new(30, "pl", "Ouvrir la Playlist", ActionCategory.Navigation, "20.7"),
        new(31, "cr", "Ouvrir le Channel Rack", ActionCategory.Navigation, "20.7"),
        new(32, "pr", "Ouvrir le Piano Roll", ActionCategory.Navigation, "20.7"),
        new(33, "mx", "Ouvrir le Mixer", ActionCategory.Navigation, "20.7"),
        new(34, "br", "Ouvrir le Browser", ActionCategory.Navigation, "20.7"),
        new(35, "plmx", "Playlist ↔ Mixer", ActionCategory.Navigation, "20.7"),
        new(36, "undo", "Annuler", ActionCategory.Navigation, "20.7"),
        new(37, "redo", "Rétablir", ActionCategory.Navigation, "20.7"),
        new(38, "save", "Sauvegarder", ActionCategory.Navigation, "20.7"),
        new(39, "armon", "Armer la piste (si éteinte)", ActionCategory.Recording, "20.7"),
        new(40, "recon", "Allumer le REC (si éteint)", ActionCategory.Recording, "20.7"),
    };

    private static readonly Dictionary<int, FlActionInfo> ById = All.ToDictionary(a => a.Id);
    private static readonly Dictionary<string, FlActionInfo> ByKey = All.ToDictionary(a => a.Key);

    public static FlActionInfo? Info(int id) => ById.TryGetValue(id, out var a) ? a : null;
    public static bool IsKnown(int id) => ById.ContainsKey(id);
    public static int? IdForKey(string key) => ByKey.TryGetValue(key, out var a) ? a.Id : null;
}

/// Ce que fait chaque action, en une phrase (tests utilisateurs : dire ce que fait l'action).
/// Miroir de FLActionInfo.detail (Sources/FLShortcut/GlassStyle.swift).
public static class FlActionDetails
{
    private static readonly Dictionary<string, string> ByKey = new()
    {
        ["play"] = "Lance ou met en pause la lecture",
        ["stop"] = "Arrête la lecture",
        ["rec"] = "Démarre ou arrête l'enregistrement",
        ["metro"] = "Active ou coupe le métronome",
        ["count"] = "Décompte avant l'enregistrement",
        ["loop"] = "Enchaîne les prises sur la boucle",
        ["wait"] = "Le REC démarre à la première note jouée",
        ["marker"] = "Repère « bonne prise » à la position de lecture",
        ["arm"] = "Prépare la piste du Mixer sélectionnée à enregistrer",
        ["tap"] = "Tape le tempo en rythme",
        ["newpat"] = "Crée un pattern vide et ouvre le Piano Roll",
        ["clone"] = "Duplique le pattern en cours pour une variation",
        ["pnext"] = "Passe au pattern suivant",
        ["pprev"] = "Revient au pattern précédent",
        ["chnext"] = "Instrument suivant, sans quitter le Piano Roll",
        ["chprev"] = "Instrument précédent, sans quitter le Piano Roll",
        ["snap"] = "Change le magnétisme : 1/4, 1/8, triolets…",
        ["quant"] = "Aligne les notes de l'instrument sélectionné",
        ["presetnext"] = "Preset suivant du plugin ouvert",
        ["presetprev"] = "Preset précédent du plugin ouvert",
        ["mute"] = "Coupe la piste du Mixer sélectionnée",
        ["solo"] = "Écoute seulement la piste sélectionnée",
        ["unsolo"] = "Réécoute tout le morceau",
        ["bypass"] = "Compare la piste avec et sans effets",
        ["mono"] = "Vérifie que le mix tient en mono",
        ["trnext"] = "Sélectionne la piste suivante du Mixer",
        ["trprev"] = "Sélectionne la piste précédente du Mixer",
        ["volup"] = "Monte la piste sélectionnée",
        ["voldn"] = "Baisse la piste sélectionnée",
        ["pl"] = "Affiche la Playlist",
        ["cr"] = "Affiche le Channel Rack",
        ["pr"] = "Affiche le Piano Roll",
        ["mx"] = "Affiche le Mixer",
        ["br"] = "Affiche le Browser",
        ["plmx"] = "Bascule entre la Playlist et le Mixer",
        ["undo"] = "Annule la dernière action",
        ["redo"] = "Rétablit l'action annulée",
        ["save"] = "Sauvegarde le projet",
        ["armon"] = "Arme la piste sélectionnée, sans jamais la désarmer",
        ["recon"] = "Allume le REC, sans jamais l'éteindre",
    };

    public static string Detail(this FlActionInfo info) => ByKey.TryGetValue(info.Key, out var d) ? d : info.Label;
}

/// Version de FL Studio (lue dans les informations de version de FL64.exe).
public sealed class FlVersion : IComparable<FlVersion>, IEquatable<FlVersion>
{
    public IReadOnlyList<int> Parts { get; }

    private FlVersion(List<int> parts) => Parts = parts;

    /// Accepte « 21.0.3 », « 2024.1.0 », « 24.1.1.4234 »… Les années (2024) deviennent 24.
    public static FlVersion? Parse(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var parts = new List<int>();
        foreach (var piece in text.Split('.').Take(4))
        {
            var digits = new string(piece.TakeWhile(char.IsDigit).ToArray());
            if (digits.Length == 0 || !int.TryParse(digits, out var n)) break;
            parts.Add(n);
        }
        if (parts.Count == 0) return null;
        if (parts[0] >= 2000) parts[0] -= 2000;
        return new FlVersion(parts);
    }

    private int Component(int i) => i < Parts.Count ? Parts[i] : 0;

    public int CompareTo(FlVersion? other)
    {
        if (other is null) return 1;
        var n = Math.Max(Parts.Count, other.Parts.Count);
        for (var i = 0; i < n; i++)
        {
            var c = Component(i).CompareTo(other.Component(i));
            if (c != 0) return c;
        }
        return 0;
    }

    public bool Equals(FlVersion? other) => other is not null && CompareTo(other) == 0;
    public override bool Equals(object? obj) => obj is FlVersion v && Equals(v);
    public override int GetHashCode()
    {
        var trimmed = Parts.ToList();
        while (trimmed.Count > 1 && trimmed[^1] == 0) trimmed.RemoveAt(trimmed.Count - 1);
        return trimmed.Aggregate(17, (h, p) => h * 31 + p);
    }
    public override string ToString() => string.Join('.', Parts);

    public bool SupportsPython => CompareTo(Parse(FlActions.PythonMinFl)) >= 0;
}

/// Masque de capacités du HELLO (PROTOCOL.md §3) : CC 90+k porte les bits 7k…7k+6 ; bit j = action 7k+j+1.
public readonly record struct CapabilityMask(ulong Bits)
{
    public const int CcCount = 6;
    private const ulong AllBits = (1UL << 42) - 1;

    public static CapabilityMask FromBits(ulong bits) => new(bits & AllBits);

    public static CapabilityMask FromCcValues(IReadOnlyList<byte> values)
    {
        ulong b = 0;
        for (var k = 0; k < Math.Min(CcCount, values.Count); k++)
            b |= (ulong)(values[k] & 0x7F) << (7 * k);
        return FromBits(b);
    }

    public bool Contains(int id) => id is >= 1 and <= 42 && (Bits & (1UL << (id - 1))) != 0;

    public byte[] CcValues()
    {
        var bits = Bits;
        return Enumerable.Range(0, CcCount).Select(k => (byte)((bits >> (7 * k)) & 0x7F)).ToArray();
    }
}

public abstract record ActionAvailability
{
    public sealed record Available : ActionAvailability;
    /// Ni handshake ni version connue.
    public sealed record Unverified : ActionAvailability;
    public sealed record Unavailable(string Reason) : ActionAvailability;

    public bool IsUsable => this is not Unavailable;
}

public static class AvailabilityResolver
{
    /// Le masque du script fait foi ; à défaut, la version lue dans FL64.exe.
    public static ActionAvailability Resolve(int id, CapabilityMask? caps, FlVersion? flVersion)
    {
        var info = FlActions.Info(id);
        if (info is null) return new ActionAvailability.Unavailable("Action inconnue");
        var message = $"Disponible à partir de FL {info.MinFl}";
        if (caps is { } mask)
        {
            if (mask.Contains(id)) return new ActionAvailability.Available();
            if (mask.Bits == 0) return new ActionAvailability.Unavailable("Le script FL n'a pas de clé : réinstalle-le");
            return new ActionAvailability.Unavailable(message);
        }
        if (flVersion is null) return new ActionAvailability.Unverified();
        if (!flVersion.SupportsPython)
            return new ActionAvailability.Unavailable($"Les actions FL demandent FL Studio {FlActions.PythonMinFl} ou plus récent");
        var min = FlVersion.Parse(info.MinFl);
        if (min is not null && flVersion.CompareTo(min) < 0) return new ActionAvailability.Unavailable(message);
        return new ActionAvailability.Available();
    }
}
