// Icônes écrites directement dans la copie rangée (12/11, comme le Mac : FLPProject.withIcons) : plus aucun clic dans
// FL pour une icône dont le numéro de FL est connu. Forme vue dans le projet du propriétaire (FL 26.1) :
// - chaque son du Channel rack a TOUJOURS son événement 155 (l'icône, 4 octets, 0 = aucune) : rempli, jamais ajouté ;
// - chaque piste du Mixer commence par un 236 et finit par un 147 (sa sortie) ; sa couleur (149) et son nom (204) sont
//   écrits JUSTE AVANT son 236, après le 147 de la piste d'avant. L'icône (95, 2 octets) y va aussi : remplie si elle
//   y est, sinon ajoutée juste avant le 236. Un Mixer d'une autre forme : rien n'y est écrit.
namespace FLShortcut.Core.Organizer;

public static class FlpIcons
{
    public const byte ChannelIcon = 155;
    public const byte InsertStart = 236;
    public const byte InsertOutput = 147;
    public const byte InsertIcon = 95;

    /// `channels` : numéro de canal → numéro d'icône de FL ; `inserts` : piste du Mixer (Master = 0) → numéro d'icône.
    /// Renvoie la copie et ce qui y a vraiment été écrit.
    public static (FlpFile File, ISet<int> Channels, ISet<int> Inserts) WithIcons(
        FlpFile file, IReadOnlyDictionary<int, uint> channels, IReadOnlyDictionary<int, uint> inserts)
    {
        var events = file.Events;
        var outEvents = new List<FlpEvent>(events);
        var doneChannels = new HashSet<int>();
        // Channel rack : le premier 155 de chaque canal (un canal commence par 64 suivi de 21 ; il s'arrête au canal
        // suivant, à l'arrangement ou au Mixer).
        int? current = null;
        var iconOf = new Dictionary<int, int>();
        for (var i = 0; i < events.Count; i++)
        {
            var e = events[i];
            if (e.Id == 64 && i + 1 < events.Count && events[i + 1].Id == 21)
            {
                current = (int)e.Value;
                continue;
            }
            if (e.Id == 99 || e.Id == InsertStart) current = null;
            if (current is { } c && e.Id == ChannelIcon && !iconOf.ContainsKey(c) && e.Bytes.Length == 4) iconOf[c] = i;
        }
        foreach (var (channel, id) in channels)
        {
            if (!iconOf.TryGetValue(channel, out var at) || id == 0) continue;
            outEvents[at] = new FlpEvent(ChannelIcon, FlpBytes.Le(id, 4));
            doneChannels.Add(channel);
        }
        var none = new HashSet<int>();
        // Mixer : chaque 236 et le 147 qui le précède (piste d'avant) ; une forme inattendue n'écrit rien.
        var starts = Enumerable.Range(0, events.Count).Where(i => events[i].Id == InsertStart).ToList();
        if (starts.Count == 0 || events.Skip(starts[0]).Count(e => e.Id == InsertOutput) != starts.Count)
            return (Copy(file, outEvents), doneChannels, none);
        var prefix = new Dictionary<int, (int From, int To)>();
        for (var k = 1; k < starts.Count; k++)
        {
            var output = -1;
            for (var i = starts[k] - 1; i > starts[k - 1]; i--)
                if (events[i].Id == InsertOutput) { output = i; break; }
            if (output < 0) return (Copy(file, outEvents), doneChannels, none);
            prefix[k] = (output + 1, starts[k]);
        }
        var doneInserts = new HashSet<int>();
        // Du bas vers le haut : un événement ajouté ne décale pas les pistes pas encore faites.
        foreach (var (insert, id) in inserts.OrderByDescending(kv => kv.Key))
        {
            if (!prefix.TryGetValue(insert, out var range) || id == 0 || id > 0xFFFF) continue;
            var bytes = FlpBytes.Le(id, 2);
            var existing = -1;
            for (var i = range.From; i < range.To; i++)
                if (events[i].Id == InsertIcon) { existing = i; break; }
            if (existing >= 0) outEvents[existing] = new FlpEvent(InsertIcon, bytes);
            else outEvents.Insert(range.To, new FlpEvent(InsertIcon, bytes));
            doneInserts.Add(insert);
        }
        return (Copy(file, outEvents), doneChannels, doneInserts);
    }

    /// Combien de sons et de pistes du Mixer ont une icône dans ce fichier (diagnostic). Des nombres seulement.
    public static (int Channels, int Inserts) IconCounts(FlpFile file)
    {
        var events = file.Events;
        int? current = null;
        var seen = new HashSet<int>();
        var channels = 0;
        for (var i = 0; i < events.Count; i++)
        {
            var e = events[i];
            if (e.Id == 64 && i + 1 < events.Count && events[i + 1].Id == 21)
            {
                current = (int)e.Value;
                continue;
            }
            if (e.Id == 99 || e.Id == InsertStart) current = null;
            if (current is { } c && e.Id == ChannelIcon && seen.Add(c) && e.Value != 0) channels++;
        }
        var first = events.FindIndex(e => e.Id == InsertStart);
        var inserts = first < 0 ? 0 : events.Skip(first).Count(e => e.Id == InsertIcon && e.Value != 0);
        return (channels, inserts);
    }

    /// Les icônes prévues dont le numéro de FL est connu (jamais deviné), par élément.
    public static Dictionary<int, uint> KnownIcons(IReadOnlyDictionary<int, FlIcon> icons, IReadOnlyDictionary<string, uint> ids) =>
        icons.Where(kv => ids.ContainsKey(kv.Value.Code)).ToDictionary(kv => kv.Key, kv => ids[kv.Value.Code]);

    private static FlpFile Copy(FlpFile file, List<FlpEvent> events) =>
        new(file.ChannelCount, file.Ppq, events, file.Format) { HeaderExtra = file.HeaderExtra, Trailer = file.Trailer };
}
