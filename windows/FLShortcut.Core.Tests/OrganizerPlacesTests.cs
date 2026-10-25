// Demande du propriétaire (25/10) : la place de chaque son dans le Mixer (la case de FL dans le Channel rack), le départ
// de chaque famille (« Drums de 27 à 32, la 808 comprise »), « Rangement automatique », l'ordre des familles glissées
// comme des dossiers, et « Écrire… » pour nommer un son soi-même. Miroir de Tests/FLShortcutTests/OrganizerPlacesTests.swift.
using FLShortcut.Core.Organizer;
using Xunit;

namespace FLShortcut.Core.Tests;

public sealed class OrganizerPlacesTests
{
    private static readonly RgbColor Gray = new(9, 9, 9);

    /// Lead (piste 1), Kick (2), Snare (3), 808 (4) ; un bus par famille pris sur les pistes libres (5, 6…).
    private static OrganizerResult Project()
    {
        var kinds = new[] { SoundKind.Lead, SoundKind.Kick, SoundKind.Snare, SoundKind.Bass808 };
        var channels = kinds.Select((_, i) => new ChannelInfo(i, 2, i + 1, Gray, $"Son {i}")).ToList();
        return new OrganizerResult
        {
            Channels = channels,
            Items = kinds.Select((k, i) => new OrganizerItem
            {
                Index = i, Name = $"Son {i}", Family = k.Family(), Confidence = 0.9, MixerTrack = i + 1, Color = Gray, Kind = k,
            }).ToList(),
            Mixer = Enumerable.Range(0, 42).Select(i => new MixerTrackInfo(i, Gray, i == 0 ? "Master" : $"Insert {i}")).ToList(),
        };
    }

    private static OrganizerPlan Plan(OrganizerResult result, Dictionary<SoundFamily, FamilyStyle>? styles = null,
        OrganizerOptions? options = null, Dictionary<int, string>? names = null, Dictionary<int, int>? slots = null) =>
        OrganizerPlan.Make(result, Organize.FamiliesOf(result), Organize.KindsOf(result),
            styles ?? FamilyStyles.Initial.ToDictionary(kv => kv.Key, kv => kv.Value), options ?? new OrganizerOptions(), names, slots);

    private static int SlotOf(OrganizerPlan plan, int track) => plan.Mixer.Final.IndexOf(track) + 1;

    [Fact]
    public void PinnedLayout()
    {
        // Sans place choisie : l'ordre automatique, puis les autres pistes (comme avant).
        Assert.Equal(new[] { 1, 2, 4, 9, 5, 6, 7, 10, 8, 3 },
            OrganizerPlan.Pinned(new[] { 1, 2, 4, 9, 5, 6, 7, 10, 8 }, Array.Empty<(int, int)>(), 20));
        Assert.Equal(new[] { 1, 2, 5, 3, 4 }, OrganizerPlan.Pinned(new[] { 1, 2, 3, 4, 5 }, new[] { (5, 3) }, 20));
        // Deux pistes pour la même place : la première l'emporte, l'autre prend la suivante libre.
        Assert.Equal(new[] { 1, 2, 5, 4, 3 }, OrganizerPlan.Pinned(new[] { 1, 2, 3, 4, 5 }, new[] { (5, 3), (4, 3) }, 20));
        // Plus loin que les pistes rangées : les pistes d'entre deux suivent dans leur ordre.
        Assert.Equal(new[] { 2, 3, 4, 5, 6, 7, 8, 1 }, OrganizerPlan.Pinned(new[] { 1, 2 }, new[] { (1, 8) }, 20));
        // Jamais au-delà de la dernière piste du Mixer.
        Assert.Equal(new[] { 1, 2 }, OrganizerPlan.Pinned(new[] { 1, 2 }, new[] { (1, 12) }, 10));
        Assert.Equal(new[] { 2, 1 }, OrganizerPlan.Pinned(new[] { 1, 2 }, new[] { (1, 2), (2, 2) }, 2));
    }

    /// « Toutes les drums, la 808 comprise, du 27 au 32 » : la famille commence à sa piste, son bus juste après.
    [Fact]
    public void FamilyStartsWhereItIsAsked()
    {
        var result = Project();
        var auto = Plan(result).Mixer;
        Assert.Equal(new[] { 1, 5, 4, 2, 3, 6 }, auto.Final);
        var styles = FamilyStyles.Initial.ToDictionary(kv => kv.Key, kv => kv.Value);
        styles[SoundFamily.Drums] = styles[SoundFamily.Drums] with { MixerStart = 27 };
        var plan = Plan(result, styles);
        Assert.Equal(new[] { 27, 28, 29, 30 }, new[] { 4, 2, 3, 6 }.Select(t => SlotOf(plan, t)));   // 808, Kick, Snare, bus
        Assert.Equal(new[] { 1, 2 }, new[] { 1, 5 }.Select(t => SlotOf(plan, t)));                   // les mélodies : à leur place
        Assert.Equal(30, plan.Mixer.Final.Count);
        Assert.Equal(Enumerable.Range(1, 30).OrderBy(x => x), plan.Mixer.Final.OrderBy(x => x));       // une vraie disposition

        // Le son placé à la main l'emporte ; le reste de sa famille suit, à partir du départ.
        var pinned = Plan(result, styles, slots: new Dictionary<int, int> { [2] = 40 });
        Assert.Equal(40, SlotOf(pinned, 3));
        Assert.Equal(new[] { 27, 28, 29 }, new[] { 4, 2, 6 }.Select(t => SlotOf(pinned, t)));

        // Appliqué dans FL (Alt+← sur un faux Mixer) : chaque piste arrive à sa place, ses sons avec elle.
        var link = new FakeOrganizerLink { Channels = result.Channels.ToList(), Mixer = result.Mixer.ToList() };
        var applier = new OrganizerApplier(link, link.MoveSelectedUp, link.MoveSelectedLeft, wait: _ => { });
        var outcome = applier.Apply(plan, result, styles);
        Assert.Null(outcome.Error);
        // Channel rack rangé aussi : Lead, 808, Kick, Snare.
        Assert.Equal(new[] { "Lead", "808", "Kick", "Snare" }, link.Channels.OrderBy(c => c.Index).Select(c => c.Name));
        Assert.Equal(new[] { 1, 27, 28, 29 }, link.Channels.OrderBy(c => c.Index).Select(c => c.MixerTrack));
        Assert.Equal("Drums Bus", link.Mixer[30].Name);
        Assert.Null(applier.Undo(outcome.Snapshot).Error);
        Assert.Equal(result.Mixer, link.Mixer);
    }

    [Fact]
    public void SoundPlacedByHand()
    {
        var result = Project();
        var plan = Plan(result, slots: new Dictionary<int, int> { [0] = 10 });
        Assert.Equal(10, SlotOf(plan, 1));
        Assert.Equal(new[] { 1, 2, 3, 4 }, new[] { 5, 4, 2, 3 }.Select(t => SlotOf(plan, t)));
        // Un son classé « À vérifier » ou laissé de côté : sa case ne compte pas.
        Assert.Equal(Plan(result).Mixer.Final, Plan(result, slots: new Dictionary<int, int> { [7] = 3 }).Mixer.Final);
    }

    /// Les familles glissées dans l'aperçu : Channel rack (puis Mixer et Playlist) dans ce nouvel ordre.
    [Fact]
    public void FamilyOrderIsFollowed()
    {
        var result = Project();
        Assert.Equal(new[] { 0, 3, 1, 2 }, Plan(result).Rack.Final);
        var drumsFirst = new OrganizerOptions { FamilyOrder = new[] { SoundFamily.Drums, SoundFamily.Melody } };
        var plan = Plan(result, options: drumsFirst);
        Assert.Equal(new[] { 1, 2, 0, 3 }, plan.Rack.Final);
        Assert.Equal(new[] { 2, 3, 4, 6, 1, 5 }, plan.Mixer.Final.Take(6));   // la 808 avec les drums, devant les mélodies
        Assert.Equal(new[] { SoundFamily.Drums, SoundFamily.Vocals, SoundFamily.Melody, SoundFamily.Bass, SoundFamily.Fx, SoundFamily.Unsure },
            OrganizerOptions.CompleteOrder(new[] { SoundFamily.Drums, SoundFamily.Drums }));
        Assert.Equal(SoundFamilies.Order, OrganizerOptions.CompleteOrder(Array.Empty<SoundFamily>()));
    }

    /// « Écrire… » : le nom tapé est posé tel quel, sur le son et partout où il a son nom (piste du Mixer…) ; les
    /// autres sons sont numérotés sans le reprendre ; même « Renommer » décoché, il est posé dans le Channel rack.
    [Fact]
    public void WrittenNamesArePutEverywhere()
    {
        var result = Project();
        var plan = Plan(result, names: new Dictionary<int, string> { [1] = "  Kick Boom ", [2] = "Kick" });
        Assert.Equal("Kick Boom", plan.Rack.Names[1]);
        Assert.Equal("Kick", plan.Rack.Names[2]);
        Assert.Equal("Kick Boom", plan.Mixer.Names[2]);
        Assert.Equal("Kick", plan.Mixer.Names[3]);
        var quiet = Plan(result, options: new OrganizerOptions { Rename = false }, names: new Dictionary<int, string> { [0] = "Mon lead" });
        Assert.Equal(new Dictionary<int, string> { [0] = "Mon lead" }, quiet.Rack.Names);
        // Un nom vide : le nom automatique.
        Assert.Equal("Kick", Plan(result, names: new Dictionary<int, string> { [1] = "  " }).Rack.Names[1]);
    }

    /// Le départ de chaque famille est gardé avec ses couleurs (réglages, JSON comme sur le Mac).
    [Fact]
    public void FamilyStartIsSaved()
    {
        var styles = FamilyStyles.Initial.ToDictionary(kv => kv.Key, kv => kv.Value);
        styles[SoundFamily.Drums] = styles[SoundFamily.Drums] with { MixerStart = 27 };
        var json = FamilyStyles.Encode(styles);
        Assert.Contains("\"mixer\":27", json);
        Assert.Equal(27, FamilyStyles.Decode(json)[SoundFamily.Drums].MixerStart);
        Assert.Null(FamilyStyles.Decode(json)[SoundFamily.Bass].MixerStart);
        Assert.Null(FamilyStyles.Decode("{\"drums\":{\"color\":\"E0453A\",\"mixer\":900}}")[SoundFamily.Drums].MixerStart);
    }
}
