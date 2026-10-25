// Organiser : « Pas content ? » (demande du propriétaire : des questions à cocher, avec « Autre » en bas, pour que l'IA
// apprenne de ses erreurs). Ce qui n'allait pas (cases), la bonne famille ou sorte des sons mal rangés (l'IA les retient
// sur ce PC et, avec l'accord de la personne, les partage : CorrectionsIA), et un message pour l'équipe (Playlist,
// Mixer, aspect, « Autre »). Les changements faits dans l'aperçu comptent aussi, sans rien demander.
// Miroir de Sources/FLShortcut/OrganizerFeedback.swift.
namespace FLShortcut.Core.Organizer;

public sealed class OrganizerFeedback
{
    public enum Reason { Voice, Family, Kind, Playlist, Mixer, Look }

    public static readonly Reason[] AllReasons = Enum.GetValues<Reason>();

    public static string Label(Reason r) => r switch
    {
        Reason.Voice => Loc.T("Une voix n'est pas rangée dans Voix"),
        Reason.Family => Loc.T("Un son est dans la mauvaise famille"),
        Reason.Kind => Loc.T("Un son a le mauvais nom (Kick, Snare, Pad…)"),
        Reason.Playlist => Loc.T("La Playlist n'est pas bien rangée"),
        Reason.Mixer => Loc.T("Le Mixer n'est pas bien rangé"),
        _ => Loc.T("Les couleurs ou les noms ne me plaisent pas"),
    };

    /// Pour l'équipe (elle lit le français), quelle que soit la langue de Windows.
    public static string TeamLabel(Reason r) => r switch
    {
        Reason.Voice => "voix mal rangée",
        Reason.Family => "mauvaise famille",
        Reason.Kind => "mauvais nom de son",
        Reason.Playlist => "Playlist",
        Reason.Mixer => "Mixer",
        _ => "couleurs ou noms",
    };

    /// Le nom envoyé (comme le Mac : « voice », « family »…).
    public static string Raw(Reason r) => SoundFamilies.Lower(r.ToString());

    /// Une réponse sur les sons : on demande lesquels, et l'IA en apprend.
    public static bool AboutSounds(Reason r) => r is Reason.Voice or Reason.Family or Reason.Kind;

    /// La bonne réponse pour un son.
    public readonly record struct Fix(SoundFamily Family, SoundKind? Kind = null);

    public HashSet<Reason> Reasons { get; } = new();
    /// « Autre », en bas : un texte libre, pour l'équipe seulement (jamais pour l'IA, ni dans le journal).
    public bool Other { get; set; }
    public string OtherText { get; set; } = "";
    /// Bonne réponse de chaque son corrigé (index du canal).
    public Dictionary<int, Fix> Fixes { get; } = new();
    /// Aider l'IA de tout le monde avec ces corrections (des nombres seulement).
    public bool Share { get; set; }

    public bool AsksSounds => Reasons.Any(AboutSounds);
    private string Text => Other ? OtherText.Trim() : "";
    public bool CanSend => Reasons.Count > 0 || Text.Length > 0;

    /// Le message pour l'équipe : ce que l'IA ne peut pas apprendre (Playlist, Mixer, aspect) et « Autre » ; null :
    /// rien à lui dire.
    public string? TeamMessage()
    {
        var others = AllReasons.Where(r => Reasons.Contains(r) && !AboutSounds(r)).ToList();
        if (others.Count == 0 && Text.Length == 0) return null;
        var all = AllReasons.Where(Reasons.Contains).Select(TeamLabel).ToList();
        var lines = new List<string> { "Organiser, pas content" + (all.Count == 0 ? "." : " : " + string.Join(", ", all) + ".") };
        if (Text.Length > 0) lines.Add(Text);
        return string.Join("\n\n", lines);
    }

    /// Changements de l'aperçu : chaque son écouté dont la famille, ou la sorte choisie, n'est plus celle trouvée.
    public static Dictionary<int, Fix> PreviewFixes(IEnumerable<OrganizerItem> items, IReadOnlyDictionary<int, SoundFamily> families,
        IReadOnlyDictionary<int, SoundKind> kinds)
    {
        var out_ = new Dictionary<int, Fix>();
        foreach (var item in items)
        {
            if (item.SoundPrint is null || !families.TryGetValue(item.Index, out var family)) continue;
            var kind = Organize.KindOf(item.Index, families, kinds);
            if (family != item.Family || (kind is not null && kind != item.Kind)) out_[item.Index] = new Fix(family, kind);
        }
        return out_;
    }
}
