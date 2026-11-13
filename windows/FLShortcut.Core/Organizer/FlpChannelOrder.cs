// 13/11 (capture du propriétaire : « tout est génial sauf dans channel rack ça n'a pas tout rangé » ; diagnostics d'avant :
// `remise rack touche sans effet 5`, `remise rack fenêtre playlist 5`) : le Channel rack est rangé dans la copie, comme la
// Playlist et les icônes, au lieu de remonter chaque son au clavier dans FL. FL écrit ses canaux dans l'ordre du Channel
// rack, chacun numéroté par sa place (64 = 0, 1, 2…), et les notes (224) et les clips audio de la Playlist (233) les
// désignent par ce numéro (vérifié sur deux projets du propriétaire). Ranger = mettre chaque canal à sa nouvelle place, le
// renuméroter, et suivre ses notes et ses clips. Tout ce qui pourrait désigner un canal autrement (layer, clip
// d'automation, liens de contrôleurs, automations de pattern) : rien n'est touché, le Channel rack est rangé dans FL comme
// avant. Pur (testé). Miroir de Sources/FLShortcut/FLPChannelOrder.swift.
namespace FLShortcut.Core.Organizer;

public static class FlpChannelOrder
{
    /// Événements qui peuvent désigner un canal ailleurs que dans les notes et les clips : automations de pattern (223),
    /// liens de contrôleurs (227), données d'automation (234).
    public static readonly IReadOnlySet<byte> ChannelReferences = new HashSet<byte> { 223, 227, 234 };
    /// Types de canaux qui en désignent d'autres : layer (ses canaux), clip d'automation (sa cible).
    public static readonly IReadOnlySet<int> ReferencingTypes = new HashSet<int> { ChannelInfo.LayerType, ChannelInfo.AutomationType };

    /// Ce qui suit un canal dans le fichier sans être à lui : le canal suivant, les patterns (FL écrit leurs noms et
    /// couleurs après le premier canal), l'arrangement, le Mixer.
    private static bool EndsChannel(IReadOnlyList<FlpEvent> events, int i)
    {
        var id = events[i].Id;
        if (id == FlpProject.Ev.Channel && i + 1 < events.Count && events[i + 1].Id == FlpProject.Ev.ChannelType) return true;
        return id == FlpProject.Ev.Pattern || id == FlpProject.Ev.Arrangement || id == FlpIcons.InsertStart;
    }

    /// Le fichier avec les canaux dans l'ordre `order` (place → numéro d'avant, chaque canal une fois), renumérotés, leurs
    /// notes et leurs clips suivis ; ce qui n'est pas à un canal (noms des patterns…) reste à sa place. null si le fichier
    /// n'a pas la forme connue ou si un canal pourrait être désigné autrement.
    public static FlpFile? Reordering(FlpFile file, IReadOnlyList<int> order)
    {
        var events = file.Events;
        var starts = new List<int>();
        for (var i = 0; i + 1 < events.Count; i++)
            if (events[i].Id == FlpProject.Ev.Channel && events[i + 1].Id == FlpProject.Ev.ChannelType) starts.Add(i);
        var n = starts.Count;
        if (n < 2 || order.Count != n || !order.ToHashSet().SetEquals(Enumerable.Range(0, n))) return null;
        // La forme de FL : numérotés 0, 1, 2… dans l'ordre ; aucun type qui désigne un autre canal.
        for (var k = 0; k < n; k++)
        {
            var start = starts[k];
            if (events[start].Bytes.Length != 2 || events[start].Value != k
                || ReferencingTypes.Contains((int)events[start + 1].Value)) return null;
        }
        if (events.Any(e => ChannelReferences.Contains(e.Id))) return null;
        // Chaque canal : de son 64 jusqu'à ce qui n'est plus à lui ; tous finissent par le même événement (FL : 51),
        // sinon quelque chose d'autre y est collé.
        var ranges = new List<(int Start, int End)>();
        for (var k = 0; k < n; k++)
        {
            var end = starts[k] + 2;
            var limit = k + 1 < n ? starts[k + 1] : events.Count;
            while (end < limit && !EndsChannel(events, end)) end++;
            ranges.Add((starts[k], end));
        }
        if (ranges.Select(r => events[r.End - 1].Id).Distinct().Count() != 1) return null;
        if (ranges.Any(r => Enumerable.Range(r.Start, r.End - r.Start).Any(i => events[i].Id == FlpProject.Ev.Children))) return null;
        var newPlace = new int[n];
        for (var place = 0; place < n; place++) newPlace[order[place]] = place;

        var moved = new List<FlpEvent>(events);
        // Notes : 24 octets chacune, le canal sur 2 octets à la place 6.
        for (var i = 0; i < events.Count; i++)
        {
            if (events[i].Id != FlpProject.Ev.Notes) continue;
            var bytes = (byte[])events[i].Bytes.Clone();
            if (bytes.Length % FlpProject.NoteSize != 0) return null;
            for (var at = 0; at < bytes.Length; at += FlpProject.NoteSize)
            {
                var channel = (int)FlpBytes.UInt(bytes, at + 6, 2);
                if (channel >= n) return null;
                FlpBytes.Put((uint)newPlace[channel], bytes, at + 6, 2);
            }
            moved[i] = new FlpEvent(events[i].Id, bytes);
        }
        // Clips de la Playlist (chaque arrangement) : en dessous de la marque des patterns, un canal.
        for (var i = 0; i < events.Count; i++)
        {
            if (events[i].Id != FlpProject.Ev.Playlist || events[i].Bytes.Length == 0) continue;
            var bytes = (byte[])events[i].Bytes.Clone();
            if (FlpProject.ItemSizeOf(bytes) is not { } size) return null;
            for (var at = 0; at < bytes.Length; at += size)
            {
                var index = (int)FlpBytes.UInt(bytes, at + 6, 2);
                if (index > FlpProject.PatternBase) continue;
                if (index >= n) return null;
                FlpBytes.Put((uint)newPlace[index], bytes, at + 6, 2);
            }
            moved[i] = new FlpEvent(events[i].Id, bytes);
        }
        // Les canaux à leur nouvelle place ; ce qui suivait chaque place (noms des patterns après le premier) y reste.
        var rebuilt = moved.Take(starts[0]).ToList();
        for (var place = 0; place < n; place++)
        {
            var (start, end) = ranges[order[place]];
            rebuilt.Add(new FlpEvent(FlpProject.Ev.Channel, FlpBytes.Le(place, 2)));
            rebuilt.AddRange(moved.Skip(start + 1).Take(end - start - 1));
            var gapEnd = place + 1 < n ? starts[place + 1] : moved.Count;
            rebuilt.AddRange(moved.Skip(ranges[place].End).Take(gapEnd - ranges[place].End));
        }
        if (rebuilt.Count != events.Count) return null;
        var out_ = file.Clone();
        out_.Events = rebuilt;
        return out_;
    }
}
