// Lien avec le script de FL (PROTOCOL.md §7, §8) : commandes avec données, réponses signées liées à leur commande,
// réveil du script, refus expliqués, et la façade de l'Organiser. Vecteurs communs avec le Mac et le script
// (Tests/FLShortcutTests/ProtocolTests.swift, OrganizerLinkTests.swift).
using FLShortcut.Core.Organizer;
using Xunit;

namespace FLShortcut.Core.Tests;

/// Sortie MIDI simulée : chaque envoi est gardé ; `OnSend` imite FL qui répond.
public sealed class FakeTransport : IMidiTransport
{
    public readonly List<CcMessage[]> Sent = new();
    public Action<CcMessage[]>? OnSend;
    public bool IsReady => true;
    public int Pings => Sent.Count(m => m.Length == 1 && m[0] == CcMessage.Ping);

    public bool Send(IReadOnlyList<CcMessage> messages)
    {
        var copy = messages.ToArray();
        lock (Sent) Sent.Add(copy);
        OnSend?.Invoke(copy);
        return true;
    }

    public List<CcMessage> All()
    {
        lock (Sent) return Sent.SelectMany(m => m).ToList();
    }
}

internal static class Bytes
{
    public static (byte, byte)[] Cc(byte cc, byte value) => new[] { (cc, value) };

    public static (byte, byte)[] Hello(byte[] nonce, byte[] caps)
    {
        var out_ = new List<(byte, byte)> { (120, 1) };
        for (var i = 0; i < 4; i++) out_.Add(((byte)(121 + i), nonce[i]));
        out_.Add((125, 45));
        out_.Add((126, 2));
        for (var k = 0; k < caps.Length; k++) out_.Add(((byte)(90 + k), caps[k]));
        out_.Add((120, 127));
        return out_.ToArray();
    }

    public static void Feed(this LinkCore core, IEnumerable<(byte Cc, byte Value)> messages)
    {
        foreach (var (cc, value) in messages) core.Receive(0xBF, cc, value);
    }

    /// FL répond un peu plus tard, d'un autre fil (comme WinMM).
    public static void Later(this LinkCore core, IEnumerable<(byte Cc, byte Value)> messages)
    {
        var list = messages.ToArray();
        Task.Delay(20).ContinueWith(_ => core.Feed(list));
    }
}

public sealed class LinkCoreTests
{
    private static readonly byte[] Key = Enumerable.Range(0, 16).Select(i => (byte)i).ToArray();
    private static readonly byte[] Nonce = { 17, 42, 99, 5 };
    private static readonly byte[] KickBytes = { 1, 3, 0xE0, 0x45, 0x3A, 4, 75, 105, 99, 107 };
    private static readonly byte[] KickUnits = { 4, 1, 3, 96, 69, 58, 4, 75, 0, 105, 99, 107 };
    /// Actions 1 à 41 (41 = commande avec données) ; 1 à 42 (42 = opérations de l'Organiser).
    private static readonly byte[] CapsWithData = CapabilityMask.FromBits((1UL << 41) - 1).CcValues();
    private static readonly byte[] CapsV5 = CapabilityMask.FromBits((1UL << 42) - 1).CcValues();
    private static readonly TimeSpan Second = TimeSpan.FromSeconds(1);

    private static (LinkCore, FakeTransport) Linked(byte[] caps)
    {
        var transport = new FakeTransport();
        var core = new LinkCore(transport, Key);
        core.Feed(Bytes.Hello(Nonce, caps));
        return (core, transport);
    }

    private static void Reply(LinkCore core, FakeTransport transport, params (byte, byte)[] answer) =>
        transport.OnSend = messages =>
        {
            if (messages[^1].Cc == 111) core.Later(answer);
        };

    [Fact]
    public void Pack7Vector()
    {
        Assert.Equal(KickUnits, Pack7.Pack(KickBytes));
        Assert.Equal(KickBytes, Pack7.Unpack(KickUnits));
        for (var n = 0; n <= 20; n++)
        {
            var bytes = Enumerable.Range(0, n).Select(i => (byte)(i * 37 + 200)).ToArray();
            var units = Pack7.Pack(bytes);
            Assert.All(units, u => Assert.True(u < 128));
            Assert.Equal(n + (n + 6) / 7, units.Length);
            Assert.Equal(bytes, Pack7.Unpack(units));
        }
        Assert.Null(Pack7.Unpack(new byte[] { 4 }));             // en-tête seul
        Assert.Null(Pack7.Unpack(new byte[] { 0b100, 1, 2 }));   // bit d'en-tête au-delà du groupe
        Assert.Null(Pack7.Unpack(new byte[] { 0, 200 }));        // unité de plus de 7 bits
    }

    /// Vecteurs de PROTOCOL.md §7 et §8, communs avec le Mac et le script.
    [Fact]
    public void DataFrameAndResponseVectors()
    {
        var signer = FrameSigner.Create(Key)!;
        Assert.Equal(new byte[] { 116, 112, 71, 62 }, signer.Mac(Nonce, 300, 41, KickUnits));
        var messages = FrameEncoder.DataFrame(300, KickUnits, Nonce, signer)!;
        Assert.Equal(1 + 12 + 8, messages.Length);
        Assert.Equal(new CcMessage(96, 0), messages[0]);
        Assert.All(messages[1..13], m => Assert.Equal(97, m.Cc));
        Assert.Equal(KickUnits, messages[1..13].Select(m => m.Value));
        Assert.Equal(new byte[] { 104, 105, 106, 107, 108, 109, 110, 111 }, messages[13..].Select(m => m.Cc));
        Assert.Equal(new byte[] { 0, 2, 44, 41, 116, 112, 71, 62 }, messages[13..].Select(m => m.Value));
        Assert.NotNull(FrameEncoder.DataFrame(1, new byte[600], Nonce, signer));
        Assert.Null(FrameEncoder.DataFrame(1, new byte[601], Nonce, signer));
        Assert.Null(FrameEncoder.DataFrame(1, new byte[] { 128 }, Nonce, signer));

        var units = Pack7.Pack(new byte[] { 1, 0, 2, 0, 0, 0, 0 });
        Assert.Equal(new byte[] { 0, 1, 0, 2, 0, 0, 0, 0 }, units);
        Assert.Equal(new byte[] { 89, 95, 58, 61 }, signer.Mac(Nonce, 300, 2, units));
    }

    [Fact]
    public void ResponsesDecodedAndBrokenOnesDropped()
    {
        static List<IncomingEvent> Decode(params (byte, byte)[] pairs)
        {
            var d = new IncomingDecoder();
            return pairs.Select(p => d.Feed(0xBF, p.Item1, p.Item2)).OfType<IncomingEvent>().ToList();
        }
        Assert.Equal(new IncomingEvent.Reason(3), new IncomingDecoder().Feed(0xBF, 116, 3));
        Assert.Empty(Decode((113, 1), (114, 0), (115, 1), (115, 2), (115, 3), (115, 4)));             // sans début
        Assert.Empty(Decode((112, 2), (113, 1), (115, 1), (115, 2), (115, 3), (115, 4)));             // sans fin
        Assert.Empty(Decode((112, 2), (114, 0), (113, 1), (115, 1), (115, 2), (115, 3), (115, 4)));
        var tooLong = new[] { ((byte)112, (byte)2) }.Concat(Enumerable.Repeat(((byte)113, (byte)0), 601))
            .Concat(new (byte, byte)[] { (114, 0), (115, 1), (115, 2), (115, 3), (115, 4) }).ToArray();
        Assert.Empty(Decode(tooLong));
        // Une nouvelle réponse repart de zéro.
        var e = Assert.IsType<IncomingEvent.Response>(Assert.Single(Decode((112, 2), (113, 9), (112, 2), (113, 1), (114, 0),
            (115, 1), (115, 2), (115, 3), (115, 4))));
        Assert.Equal(2, e.Op);
        Assert.Equal(new byte[] { 1 }, e.Units);
        Assert.Equal(new byte[] { 1, 2, 3, 4 }, e.Mac);
    }

    [Fact]
    public void RunDataDoneAndRefused()
    {
        var (core, transport) = Linked(CapsWithData);
        Reply(core, transport, (119, 41));
        Assert.Equal(new DataReply.Done(), core.RunData(KickUnits, true, Second));
        var sent = transport.All();
        Assert.Equal(new CcMessage(96, 0), sent[0]);
        Assert.Equal(111, sent[^1].Cc);

        Reply(core, transport, (116, 2), (119, 0));
        Assert.Equal(new DataReply.Refused(2), core.RunData(KickUnits, true, Second));
        // un refus expliqué n'est pas un rejet : pas de resynchronisation (PING)
        Reply(core, transport, (116, 3), (119, 0));
        Assert.Equal(new DataReply.Refused(3), core.RunData(KickUnits, true, Second));
        Assert.Equal(0, transport.Pings);
    }

    /// Script rendormi alors que son dernier battement semblait récent : la trame est ignorée (accusé 0 sans raison) ;
    /// l'appli le réveille par un PING et renvoie une seule fois.
    [Fact]
    public void SilentRefusalWakesTheScriptAndRetriesOnce()
    {
        var (core, transport) = Linked(CapsWithData);
        var frames = 0;
        transport.OnSend = messages =>
        {
            if (messages.Length == 1 && messages[0] == CcMessage.PingBrief) core.Later(Bytes.Hello(new byte[] { 9, 9, 9, 9 }, CapsWithData));
            if (messages[^1].Cc != 111) return;
            frames++;
            core.Later(Bytes.Cc(119, (byte)(frames == 1 ? 0 : 41)));
        };
        Assert.Equal(new DataReply.Done(), core.RunData(KickUnits, true, Second));
        Assert.Equal(2, frames);
        Assert.Single(transport.Sent, m => m.Length == 1 && m[0] == CcMessage.PingBrief);

        // Deux refus sans raison : un seul nouvel essai, puis un message.
        frames = 0;
        transport.OnSend = messages =>
        {
            if (messages.Length == 1 && messages[0] == CcMessage.PingBrief) core.Later(Bytes.Hello(new byte[] { 8, 8, 8, 8 }, CapsWithData));
            if (messages[^1].Cc != 111) return;
            frames++;
            core.Later(Bytes.Cc(119, 0));
        };
        Assert.IsType<DataReply.Failed>(core.RunData(KickUnits, true, Second));
        Assert.Equal(2, frames);
    }

    [Fact]
    public void RunDataNeedsCapability()
    {
        var (core, transport) = Linked(CapabilityMask.FromBits((1UL << 40) - 1).CcValues());   // pas de bit 41
        Assert.IsType<DataReply.Failed>(core.RunData(KickUnits, true, Second));
        Assert.DoesNotContain(transport.All(), m => m.Cc == 96);
    }

    [Fact]
    public void LongDataSentInSmallPackets()
    {
        var (core, transport) = Linked(CapsWithData);
        var units = Enumerable.Repeat((byte)5, 600).ToArray();
        Assert.Equal(LinkCore.SendResult.Sent, core.SendData(units));
        Assert.All(transport.Sent, m => Assert.True(m.Length * 3 <= 256));
        var all = transport.All();
        Assert.Equal(1 + 600 + 8, all.Count);
        Assert.Equal(units, all.Where(m => m.Cc == 97).Select(m => m.Value));
        Assert.Equal(1u, core.State.Seq);
    }

    /// FL répond comme le script : réponse signée (MAC sur le seq de la trame reçue, ou `seqShift` de plus pour simuler
    /// une réponse d'une autre commande), puis l'accusé 41.
    private static void Answer(LinkCore core, FakeTransport transport, byte[] data, bool badMac = false, uint seqShift = 0)
    {
        var signer = FrameSigner.Create(Key)!;
        transport.OnSend = messages =>
        {
            if (messages[^1].Cc != 111) return;
            var frame = transport.All().TakeLast(8).Select(m => m.Value).ToArray();
            var seq = ((uint)frame[0] << 14 | (uint)frame[1] << 7 | frame[2]) + seqShift;
            var units = Pack7.Pack(data);
            var mac = signer.Mac(Nonce, seq, 2, units);
            if (badMac) mac[0] ^= 1;
            var reply = new List<(byte, byte)> { (112, 2) };
            reply.AddRange(units.Select(u => ((byte)113, u)));
            reply.Add((114, 0));
            reply.AddRange(mac.Select(m => ((byte)115, m)));
            reply.Add((119, 41));
            core.Later(reply);
        };
    }

    [Fact]
    public void RequestAnsweredWithVerifiedResponse()
    {
        var (core, transport) = Linked(CapsV5);
        var page = new byte[] { 1, 0, 1, 0, 0, 1, 0, 2, 0, 1, 0xE0, 0x45, 0x3A, 4 }.Concat("Kick"u8.ToArray()).ToArray();
        Answer(core, transport, page);
        var reply = Assert.IsType<RequestReply.Answered>(core.RunRequest(OrganizerPayload.List(ItemKind.Channels, 0), true, Second));
        Assert.Equal(page, reply.Bytes);
        Assert.Equal(new byte[] { 2, 1, 0, 0 }, Pack7.Unpack(transport.All().Where(m => m.Cc == 97).Select(m => m.Value).ToArray()));
    }

    [Fact]
    public void WrongMacOrOtherCommandResponseIgnored()
    {
        var (core, transport) = Linked(CapsV5);
        Answer(core, transport, new byte[] { 1, 0, 0, 0, 0, 0, 0 }, badMac: true);
        Assert.Empty(Assert.IsType<RequestReply.Answered>(core.RunRequest(new byte[] { 2, 1, 0, 0 }, true, Second)).Bytes);
        Answer(core, transport, new byte[] { 1, 0, 0, 0, 0, 0, 0 }, seqShift: 1);   // signée pour une autre commande
        Assert.Empty(Assert.IsType<RequestReply.Answered>(core.RunRequest(new byte[] { 2, 1, 0, 0 }, true, Second)).Bytes);
    }

    [Fact]
    public void RequestNeedsScriptV5()
    {
        var (core, transport) = Linked(CapsWithData);   // script v4 : pas de bit 42
        Assert.IsType<RequestReply.Failed>(core.RunRequest(new byte[] { 2, 1, 0, 0 }, true, Second));
        Assert.DoesNotContain(transport.All(), m => m.Cc == 96);
    }

    /// FL muet (script pas chargé : Controller type « generic controller », ports différents) : erreur à part, qui
    /// affiche les réglages de FL à vérifier.
    [Fact]
    public void NoResponseExplained()
    {
        var link = new RequestOrganizerLink(_ => new RequestReply.Failed(LinkCore.NoResponse), () => FlWindow.Unknown, _ => { });
        Assert.Equal(OrganizerError.NoResponse, Assert.Throws<OrganizerError>(() => link.Page()));
        Assert.Contains("generic controller", LinkCore.NoResponse);
        Assert.Contains("même numéro de Port", LinkCore.NoResponse);
        Assert.Contains("Réessayer", OrganizerError.NoResponse.UserMessage);

        // Pas de HELLO du tout : la même explication, sans rien envoyer d'autre que le réveil.
        var transport = new FakeTransport();
        var core = new LinkCore(transport, Key);
        Assert.Equal(new RequestReply.Failed(LinkCore.NoResponse), core.RunRequest(new byte[] { 9 }, true, TimeSpan.FromMilliseconds(100)));
        Assert.All(transport.Sent, m => Assert.Equal(new[] { CcMessage.PingBrief }, m));
    }

    [Fact]
    public void WrongInputNoticeUntilNextHello()
    {
        var (core, _) = Linked(CapsV5);
        Assert.False(core.State.WrongInput);
        core.Feed(Bytes.Cc(120, 64));
        Assert.True(core.State.WrongInput);
        core.Feed(Bytes.Hello(Nonce, CapsV5));
        Assert.False(core.State.WrongInput);
    }

    [Fact]
    public void RefusalsBecomeErrors()
    {
        var calls = 0;
        var link = new RequestOrganizerLink(_ =>
        {
            calls++;
            return new RequestReply.Refused(4);
        }, () => FlWindow.ChannelRack, _ => { });
        var error = Assert.Throws<OrganizerError>(() => link.PlaySolo(1));
        Assert.Equal(OrganizerError.Refused(4), error);
        Assert.Equal("FL joue : appuie sur Stop, puis relance Organiser.", error.UserMessage);
        calls = 0;
        link.StopRestore();   // jamais d'erreur ; deux essais
        Assert.Equal(2, calls);
    }

    /// Page telle que le script l'écrit (`_op_list`).
    private static byte[] ChannelPage(int total, int start, string[] names, bool filtered = false)
    {
        var out_ = new List<byte> { 1, (byte)(total >> 8), (byte)total, (byte)(start >> 8), (byte)start, (byte)names.Length, (byte)(filtered ? 1 : 0) };
        for (var k = 0; k < names.Length; k++)
        {
            var raw = System.Text.Encoding.UTF8.GetBytes(names[k]);
            var track = start + k + 1;
            out_.AddRange(new byte[] { 2, (byte)(track >> 8), (byte)track, 0x10, 0x20, (byte)k, (byte)raw.Length });
            out_.AddRange(raw);
        }
        return out_.ToArray();
    }

    [Fact]
    public void ChannelListPagesDecode()
    {
        var names = Enumerable.Range(0, 20).Select(i => $"Son {i} é").ToArray();
        var requests = new List<byte[]>();
        var slept = new List<TimeSpan>();
        var link = new RequestOrganizerLink(bytes =>
        {
            requests.Add(bytes);
            var start = bytes[2] << 8 | bytes[3];
            var page = names[start..Math.Min(start + 16, names.Length)];
            return new RequestReply.Answered(ChannelPage(20, start, page, filtered: start == 16));
        }, () => FlWindow.ChannelRack, slept.Add);
        var channels = link.ListChannels();
        Assert.Equal(new[] { new byte[] { 2, 1, 0, 0 }, new byte[] { 2, 1, 0, 16 } }, requests);
        Assert.Equal(20, channels.Count);
        Assert.Equal(new ChannelInfo(17, 2, 18, new RgbColor(0x10, 0x20, 1), "Son 17 é"), channels[17]);
        Assert.Single(slept);   // 60 ms au moins entre deux commandes
        Assert.Null(OrganizerPayload.DecodeChannels(ChannelPage(20, 0, new[] { "a" }).Append((byte)0).ToArray()));   // octet de trop
        Assert.Null(OrganizerPayload.DecodeChannels(ChannelPage(20, 0, new[] { "abc" })[..^1]));
        Assert.Null(OrganizerPayload.DecodeMixer(ChannelPage(1, 0, new[] { "a" })));   // autre genre
    }

    /// Channel rack sur un groupe (« Unsorted »…) : l'analyse sur le fichier compte tous les canaux, comme « All »
    /// (script v16) ; un script plus ancien ou FL d'avant l'API 33 : le groupe affiché, comme avant.
    [Fact]
    public void AllChannelsWhateverTheGroup()
    {
        Assert.Equal(new byte[] { 2, 5, 0, 16 }, OrganizerPayload.ListAllChannels(16));
        var page = new byte[] { 1, 0, 1, 0, 0, 1, 0, 2, 0, 1, 0xE0, 0x45, 0x3A, 4 }.Concat("Kick"u8.ToArray()).ToArray();
        var sent = new List<byte[]>();
        var v16 = new RequestOrganizerLink(bytes =>
        {
            sent.Add(bytes);
            return new RequestReply.Answered(page);
        }, () => FlWindow.ChannelRack, _ => { }) { AllChannels = true };
        Assert.Equal(new[] { "Kick" }, v16.ListChannels().Select(c => c.Name));
        v16.PlaySolo(0, 1);
        v16.Audition(0, 60, 0);
        Assert.Equal(new[] { new byte[] { 2, 5, 0, 0 }, new byte[] { 6, 0, 0, 0, 1, 1 }, new byte[] { 3, 0, 0, 60, 0, 1 } }, sent);
        Assert.True(v16.AllChannels);

        foreach (var reason in new[] { 5, 6 })
        {
            sent.Clear();
            var old = new RequestOrganizerLink(bytes =>
            {
                sent.Add(bytes);
                return bytes[1] == 5 ? new RequestReply.Refused(reason) : new RequestReply.Answered(page);
            }, () => FlWindow.ChannelRack, _ => { }) { AllChannels = true };
            Assert.Equal(new[] { "Kick" }, old.ListChannels().Select(c => c.Name));
            Assert.False(old.AllChannels);   // le groupe affiché ensuite
            old.PlaySolo(0, 1);
            Assert.Equal(new[] { new byte[] { 2, 5, 0, 0 }, new byte[] { 2, 1, 0, 0 }, new byte[] { 6, 0, 0, 0, 1 } }, sent);
        }
        var refused = new RequestOrganizerLink(_ => new RequestReply.Refused(4), () => FlWindow.ChannelRack, _ => { }) { AllChannels = true };
        Assert.Equal(OrganizerError.Refused(4), Assert.Throws<OrganizerError>(() => refused.ListChannels()));
    }

    [Fact]
    public void OldScriptsAskForARestart()
    {
        var old = new RequestOrganizerLink(_ => new RequestReply.Refused(5), () => FlWindow.ChannelRack, _ => { });
        Assert.Equal(OrganizerError.OutdatedScript, Assert.Throws<OrganizerError>(() => old.PatternLengths()));
        Assert.Equal(OrganizerError.OutdatedScript, Assert.Throws<OrganizerError>(() => old.HeardTracks()));
        Assert.Equal(OrganizerError.OutdatedScript, Assert.Throws<OrganizerError>(() => old.ListPatterns()));
        Assert.Equal(OrganizerError.OutdatedScript, Assert.Throws<OrganizerError>(() => old.PlaySolo(1, 2)));
        Assert.Equal(OrganizerError.Refused(5), Assert.Throws<OrganizerError>(() => old.PlaySolo(1)));
        Assert.Contains("redémarre FL Studio", OrganizerError.OutdatedScript.UserMessage);
    }

    [Fact]
    public void PayloadSizes()
    {
        var colors = Enumerable.Range(0, 65).Select(i => (i, new RgbColor(255, 128, (byte)i))).ToList();
        var chunks = OrganizerPayload.SetColors(ItemKind.Channels, colors);
        Assert.Equal(2, chunks.Count);
        Assert.Equal(3 + 5 * 64, chunks[0].Length);
        Assert.Equal(new byte[] { 4, 1, 1 }, chunks[1][..3]);
        Assert.True(Pack7.Pack(chunks[0]).Length <= FlProtocol.MaxDataUnits);
        Assert.Equal(new byte[] { 5, 2, 1, 44 }, OrganizerPayload.SelectOne(ItemKind.Mixer, 300));
        Assert.Equal(new byte[] { 6, 0, 3 }, OrganizerPayload.PlaySolo(3));
        Assert.Equal(new byte[] { 6, 0, 3, 0, 12 }, OrganizerPayload.PlaySolo(3, 12));
        Assert.Equal(new byte[] { 3, 0, 2, 48, 0 }, OrganizerPayload.Audition(2, 48, 0));
        Assert.Equal(new byte[] { 24, 0, 2, 1, 44 }, OrganizerPayload.LinkChannel(2, 300));
        Assert.Equal(new byte[] { 23, 0, 10, 0b10010, 0b10 }, OrganizerPayload.SelectChannels(new[] { 1, 4, 9 }, 10));
        // Noms : 16 par commande, 64 octets au plus sans couper un caractère, vides jamais envoyés (sauf Mixer).
        Assert.Equal("Kick"u8.ToArray(), OrganizerPayload.NameUtf8("  Kick "));
        Assert.Equal(new string('é', 32), System.Text.Encoding.UTF8.GetString(OrganizerPayload.NameUtf8(new string('é', 40))!));
        Assert.Null(OrganizerPayload.NameUtf8("   "));
        Assert.Equal(new[] { new byte[] { 10, 2, 1, 0, 5, 0 } }, OrganizerPayload.SetNames(ItemKind.Mixer, new[] { (5, "") }));
        Assert.Empty(OrganizerPayload.SetNames(ItemKind.Channels, new[] { (5, "") }));
    }
}
