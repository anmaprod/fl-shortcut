// Audit : SEC-01 (trames authentifiées HMAC-SHA256 tronqué 28 bits, nonce de session), SEC-10 (PING borné),
//         REL-06 (statut du lien), audit 04 (masque de capacités). Contrat : PROTOCOL.md v2.
// Miroir exact de Sources/FLShortcut/FLProtocol.swift. Pur : aucune dépendance MIDI ni Windows.
using System.Security.Cryptography;

namespace FLShortcut.Core;

public static class FlProtocol
{
    public const int Version = 2;
    /// Canal 16 (0-indexé : 15), statut Control Change 0xBF.
    public const byte Channel = 15;
    public const byte StatusCc = 0xB0 | Channel;

    // Appli → FL
    public const byte CcPing = 103;
    public const byte CcFrameFirst = 104;        // 104…111 : seq (3), action (1), MAC (4)
    // Commande avec données (PROTOCOL.md §7, script v4) : CC 96 début, CC 97 unités, puis la trame de l'action 41.
    public const byte CcDataStart = 96;
    public const byte CcDataUnit = 97;
    public const int DataActionId = 41;
    public const int MaxDataUnits = 600;
    /// Opérations 2 à 26 de la commande avec données (Organiser, dégradé ; script v5 et plus, PROTOCOL.md §8).
    public const int ExtActionId = 42;
    // FL → appli
    /// Réponse signée (PROTOCOL.md §8) : 112 début (valeur = opération), 113 unités, 114 fin, 4 × 115 MAC.
    public const byte CcRespStart = 112;
    public const byte CcRespUnit = 113;
    public const byte CcRespEnd = 114;
    public const byte CcRespMac = 115;
    public const int MaxRespUnits = 600;
    /// Raison d'un refus de la commande avec données, juste avant l'accusé 0.
    public const byte CcReason = 116;
    public const byte CcCapsFirst = 90;          // 90…95
    public const byte CcWindow = 117;
    public const byte CcHeartbeat = 118;
    public const byte CcAck = 119;
    public const byte CcHello = 120;             // 1 = début, 127 = fin
    public const byte CcNonceFirst = 121;        // 121…124
    public const byte CcApi = 125;
    public const byte CcProto = 126;
    public const byte HelloStart = 1;
    public const byte HelloEnd = 127;
    /// Script posé sur une autre entrée que celle de FL Shortcuts (script v8, au démarrage ; PROTOCOL.md §3).
    public const byte HelloWrongInput = 64;

    public const uint SeqMax = (1u << 21) - 1;
    public const int KeyLength = 16;
    public const int MaxActionId = 42;
    /// « Relié » : HELLO reçu et battement depuis moins de 6 s (PROTOCOL.md §5).
    public static readonly TimeSpan AliveTimeout = TimeSpan.FromSeconds(6);
    public static readonly TimeSpan PingInterval = TimeSpan.FromSeconds(6);
    /// Plafond des PING sans réponse (FL ouvert mais lien pas activé dans ses réglages MIDI).
    public static readonly TimeSpan MaxPingInterval = TimeSpan.FromSeconds(60);
    public static readonly TimeSpan ResyncPingInterval = TimeSpan.FromSeconds(2);

    public static byte[] SeqBytes(uint seq) =>
        new[] { (byte)((seq >> 14) & 0x7F), (byte)((seq >> 7) & 0x7F), (byte)(seq & 0x7F) };

    /// 4 premiers octets du HMAC en big-endian, décalés de 4 bits (28 bits), découpés en 4 × 7 bits.
    public static byte[] Mac28(ReadOnlySpan<byte> digest)
    {
        if (digest.Length < 4) throw new ArgumentException("digest trop court", nameof(digest));
        var v = ((uint)digest[0] << 24 | (uint)digest[1] << 16 | (uint)digest[2] << 8 | digest[3]) >> 4;
        return new[] { (byte)((v >> 21) & 0x7F), (byte)((v >> 14) & 0x7F), (byte)((v >> 7) & 0x7F), (byte)(v & 0x7F) };
    }

    /// Clé en 32 caractères hexadécimaux minuscules (format injecté dans le script).
    public static string Hex(ReadOnlySpan<byte> bytes) => Convert.ToHexString(bytes).ToLowerInvariant();
}

/// Un Control Change sur le canal 16.
public readonly record struct CcMessage(byte Cc, byte Value)
{
    public byte[] Bytes => new[] { FlProtocol.StatusCc, (byte)(Cc & 0x7F), (byte)(Value & 0x7F) };
    /// Message court WinMM : statut | data1 << 8 | data2 << 16.
    public uint ShortMessage => (uint)(FlProtocol.StatusCc | (Cc & 0x7F) << 8 | (Value & 0x7F) << 16);
    public static readonly CcMessage Ping = new(FlProtocol.CcPing, 1);
    /// Réveil bref (macros, Organiser en mode léger) : le script se rendort tout seul 8 s après le dernier message.
    public static readonly CcMessage PingBrief = new(FlProtocol.CcPing, 2);
}

/// Calcul du MAC des trames.
public sealed class FrameSigner
{
    private readonly byte[] _key;

    private FrameSigner(byte[] key) => _key = key;

    public static FrameSigner? Create(byte[]? keyBytes) =>
        keyBytes is { Length: FlProtocol.KeyLength } ? new FrameSigner((byte[])keyBytes.Clone()) : null;

    /// Message signé : nonce[4] ‖ seq_hi ‖ seq_mid ‖ seq_lo ‖ action.
    public static byte[] Message(IReadOnlyList<byte> nonce, uint seq, byte action) =>
        nonce.Concat(FlProtocol.SeqBytes(seq)).Append(action).ToArray();

    public byte[] Mac(IReadOnlyList<byte> nonce, uint seq, byte action)
    {
        var digest = HMACSHA256.HashData(_key, Message(nonce, seq, action));
        return FlProtocol.Mac28(digest);
    }

    /// Commande avec données (et réponse de FL) : le MAC couvre aussi les unités (PROTOCOL.md §7, §8).
    public byte[] Mac(IReadOnlyList<byte> nonce, uint seq, byte action, IReadOnlyList<byte> data)
    {
        var digest = HMACSHA256.HashData(_key, Message(nonce, seq, action).Concat(data).ToArray());
        return FlProtocol.Mac28(digest);
    }
}

/// Empaquetage 7 bits des données (PROTOCOL.md §7) : par groupe de 7 octets, une unité d'en-tête (bit j = bit 7 de
/// l'octet j), puis les 7 bits bas de chaque octet.
public static class Pack7
{
    public static byte[] Pack(IReadOnlyList<byte> bytes)
    {
        var out_ = new List<byte>(bytes.Count + (bytes.Count + 6) / 7);
        for (var i = 0; i < bytes.Count; i += 7)
        {
            var count = Math.Min(7, bytes.Count - i);
            byte header = 0;
            for (var j = 0; j < count; j++) if ((bytes[i + j] & 0x80) != 0) header |= (byte)(1 << j);
            out_.Add(header);
            for (var j = 0; j < count; j++) out_.Add((byte)(bytes[i + j] & 0x7F));
        }
        return out_.ToArray();
    }

    /// null si mal formé (en-tête seul, bit d'en-tête au-delà du groupe, unité de plus de 7 bits).
    public static byte[]? Unpack(IReadOnlyList<byte> units)
    {
        var out_ = new List<byte>();
        var i = 0;
        while (i < units.Count)
        {
            var header = units[i];
            var count = Math.Min(7, units.Count - i - 1);
            if (count <= 0 || header >= 128 || header >> count != 0) return null;
            for (var j = 0; j < count; j++)
            {
                var u = units[i + 1 + j];
                if (u >= 128) return null;
                out_.Add((byte)(u | (((header >> j) & 1) == 1 ? 0x80 : 0)));
            }
            i += 1 + count;
        }
        return out_.ToArray();
    }
}

/// Réponse de FL à une commande avec données.
public abstract record DataReply
{
    public sealed record Done : DataReply;
    /// Refus expliqué par le CC 116 (1 page, 2 rien de sélectionné, 3 plusieurs, 4 FL joue, 5 données, 6 FL trop
    /// ancien, 7 dégradé sur un seul élément).
    public sealed record Refused(int Reason) : DataReply;
    public sealed record Failed(string Why) : DataReply;
}

/// Réponse de FL à une opération 2 à 26 (PROTOCOL.md §8) : les octets de sa réponse signée (vide : pas de réponse).
public abstract record RequestReply
{
    public sealed record Answered(byte[] Bytes) : RequestReply;
    public sealed record Refused(int Reason) : RequestReply;
    public sealed record Failed(string Why) : RequestReply;
}

public static class FrameEncoder
{
    /// Trame de 8 CC (104…111), ou null si un paramètre sort du protocole.
    public static CcMessage[]? Frame(uint seq, int action, IReadOnlyList<byte> nonce, FrameSigner signer)
    {
        if (seq < 1 || seq > FlProtocol.SeqMax) return null;
        if (action < 1 || action > FlProtocol.MaxActionId) return null;
        if (nonce.Count != 4 || nonce.Any(b => b >= 128)) return null;
        var a = (byte)action;
        var values = FlProtocol.SeqBytes(seq).Append(a).Concat(signer.Mac(nonce, seq, a)).ToArray();
        return values.Select((v, i) => new CcMessage((byte)(FlProtocol.CcFrameFirst + i), v)).ToArray();
    }

    /// Commande avec données : CC 96, un CC 97 par unité, puis la trame de l'action 41 dont le MAC couvre les unités.
    /// null au-delà de 600 unités ou si une valeur sort du protocole.
    public static CcMessage[]? DataFrame(uint seq, IReadOnlyList<byte> units, IReadOnlyList<byte> nonce, FrameSigner signer)
    {
        if (seq < 1 || seq > FlProtocol.SeqMax || units.Count > FlProtocol.MaxDataUnits) return null;
        if (units.Any(u => u >= 128) || nonce.Count != 4 || nonce.Any(b => b >= 128)) return null;
        const byte a = FlProtocol.DataActionId;
        var values = FlProtocol.SeqBytes(seq).Append(a).Concat(signer.Mac(nonce, seq, a, units)).ToArray();
        return new[] { new CcMessage(FlProtocol.CcDataStart, 0) }
            .Concat(units.Select(u => new CcMessage(FlProtocol.CcDataUnit, u)))
            .Concat(values.Select((v, i) => new CcMessage((byte)(FlProtocol.CcFrameFirst + i), v)))
            .ToArray();
    }
}

/// Fenêtre FL active (CC 117).
public enum FlWindow { Mixer = 0, ChannelRack = 1, Playlist = 2, PianoRoll = 3, Browser = 4, Plugin = 5, Unknown = 127 }

public static class FlWindowCodes
{
    public static FlWindow FromCode(byte code) =>
        Enum.IsDefined(typeof(FlWindow), (int)code) ? (FlWindow)code : FlWindow.Unknown;
}

public sealed record HelloInfo(byte[] Nonce, int ApiVersion, int ProtocolVersion, CapabilityMask Capabilities);

public abstract record IncomingEvent
{
    public sealed record Hello(HelloInfo Info) : IncomingEvent;
    /// HELLO complet mais version de protocole différente de 2.
    public sealed record Incompatible(int ProtocolVersion) : IncomingEvent;
    public sealed record Heartbeat : IncomingEvent;
    public sealed record Window(FlWindow Value) : IncomingEvent;
    /// id de l'action exécutée, ou 0 si la trame a été rejetée / l'action a échoué.
    public sealed record Ack(int Id) : IncomingEvent;
    /// Raison du refus d'une commande avec données (CC 116), juste avant l'accusé 0.
    public sealed record Reason(int Value) : IncomingEvent;
    /// Réponse complète (CC 112 à 115), MAC pas encore vérifié : seul le lien connaît le seq de la commande.
    public sealed record Response(int Op, byte[] Units, byte[] Mac) : IncomingEvent;
    /// FL a posé le script sur une autre entrée MIDI (carte son, clavier) : il ne recevra rien de l'appli.
    public sealed record WrongInput : IncomingEvent;
}

/// Machine à états des messages FL → appli. WinMM livre déjà des messages courts (statut, data1, data2).
public sealed class IncomingDecoder
{
    private sealed class Partial
    {
        public readonly byte?[] Nonce = new byte?[4];
        public byte? Api;
        public byte? Proto;
        public readonly byte?[] Caps = new byte?[CapabilityMask.CcCount];
    }

    private sealed class PartialResponse
    {
        public byte Op;
        public readonly List<byte> Units = new();
        /// null tant que le CC 114 (fin des unités) n'est pas arrivé.
        public List<byte>? Mac;
    }

    private Partial? _partial;
    private PartialResponse? _response;

    public IncomingEvent? Feed(byte status, byte cc, byte value)
    {
        if (status != FlProtocol.StatusCc || cc >= 128 || value >= 128) return null;
        switch (cc)
        {
            case FlProtocol.CcRespStart:
                _response = new PartialResponse { Op = value };
                return null;
            case FlProtocol.CcRespUnit:
                // Unité hors réponse, après la fin, ou au-delà de 600 : la réponse est jetée.
                if (_response is null || _response.Mac is not null || _response.Units.Count >= FlProtocol.MaxRespUnits)
                {
                    _response = null;
                    return null;
                }
                _response.Units.Add(value);
                return null;
            case FlProtocol.CcRespEnd:
                if (_response is null || _response.Mac is not null) { _response = null; return null; }
                _response.Mac = new List<byte>();
                return null;
            case FlProtocol.CcRespMac:
                if (_response?.Mac is not { } mac) { _response = null; return null; }
                mac.Add(value);
                if (mac.Count < 4) return null;
                var done = _response;
                _response = null;
                return new IncomingEvent.Response(done.Op, done.Units.ToArray(), mac.ToArray());
            case FlProtocol.CcHello:
                if (value == FlProtocol.HelloStart) { _partial = new Partial(); return null; }
                if (value == FlProtocol.HelloEnd) { var r = Finish(); _partial = null; return r; }
                _partial = null;
                return value == FlProtocol.HelloWrongInput ? new IncomingEvent.WrongInput() : null;
            case >= FlProtocol.CcNonceFirst and < FlProtocol.CcNonceFirst + 4:
                if (_partial is not null) _partial.Nonce[cc - FlProtocol.CcNonceFirst] = value;
                return null;
            case FlProtocol.CcApi:
                if (_partial is not null) _partial.Api = value;
                return null;
            case FlProtocol.CcProto:
                if (_partial is not null) _partial.Proto = value;
                return null;
            case >= FlProtocol.CcCapsFirst and < FlProtocol.CcCapsFirst + CapabilityMask.CcCount:
                if (_partial is not null) _partial.Caps[cc - FlProtocol.CcCapsFirst] = value;
                return null;
            case FlProtocol.CcWindow:
                return new IncomingEvent.Window(FlWindowCodes.FromCode(value));
            case FlProtocol.CcHeartbeat:
                return new IncomingEvent.Heartbeat();
            case FlProtocol.CcAck:
                return new IncomingEvent.Ack(value);
            case FlProtocol.CcReason:
                return new IncomingEvent.Reason(value);
            default:
                return null;
        }
    }

    /// Message court WinMM (MIM_DATA) : statut | data1 << 8 | data2 << 16.
    public IncomingEvent? FeedShortMessage(uint msg) =>
        Feed((byte)(msg & 0xFF), (byte)((msg >> 8) & 0xFF), (byte)((msg >> 16) & 0xFF));

    private IncomingEvent? Finish()
    {
        var p = _partial;
        if (p?.Api is not { } api || p.Proto is not { } proto) return null;
        if (p.Nonce.Any(b => b is null) || p.Caps.Any(b => b is null)) return null;
        if (proto != FlProtocol.Version) return new IncomingEvent.Incompatible(proto);
        var nonce = p.Nonce.Select(b => b!.Value).ToArray();
        var caps = CapabilityMask.FromCcValues(p.Caps.Select(b => b!.Value).ToArray());
        return new IncomingEvent.Hello(new HelloInfo(nonce, api, proto, caps));
    }
}

/// Statut affiché (PROTOCOL.md §5).
public enum LinkStatus { Linked, Inactive, FlClosed }

public static class LinkStatusExtensions
{
    public static string Label(this LinkStatus s) => s switch
    {
        LinkStatus.Linked => "Relié",
        LinkStatus.Inactive => "Lien inactif",
        _ => "FL fermé",
    };

    public static LinkStatus Resolve(bool flRunning, bool alive) =>
        !flRunning ? LinkStatus.FlClosed : alive ? LinkStatus.Linked : LinkStatus.Inactive;
}

/// Ce que le hook clavier a besoin de savoir du lien, au moment d'une frappe.
public sealed record LinkRoutingView(bool Linked, FlWindow Window, CapabilityMask? Capabilities, bool CanSign)
{
    public static readonly LinkRoutingView Offline = new(false, FlWindow.Unknown, null, false);

    /// Fenêtre connue seulement si le lien est vivant (sinon on ne filtre pas par fenêtre).
    public FlWindow? KnownWindow => Linked && Window != FlWindow.Unknown ? Window : null;

    public bool CanRun(int id) =>
        Linked && CanSign && FlActions.IsKnown(id) && (Capabilities?.Contains(id) ?? false);
}

/// État du lien côté appli : nonce, séquence, vivacité. Pur et testable (horloge injectée).
public sealed class LinkSession
{
    private readonly Func<DateTimeOffset> _now;
    private DateTimeOffset _lastAlive = DateTimeOffset.MinValue;
    private DateTimeOffset _lastPing = DateTimeOffset.MinValue;
    private uint _seq;

    public LinkSession(Func<DateTimeOffset>? now = null) => _now = now ?? (() => DateTimeOffset.UtcNow);

    public HelloInfo? Hello { get; private set; }
    public FlWindow Window { get; private set; } = FlWindow.Unknown;
    public bool Incompatible { get; private set; }

    public bool Alive => Hello is not null && _now() - _lastAlive < FlProtocol.AliveTimeout;

    public void Apply(IncomingEvent e)
    {
        switch (e)
        {
            case IncomingEvent.Hello h:
                Hello = h.Info;
                Incompatible = false;
                _seq = 0;                           // le script remet sa séquence à 0 avec un nouveau nonce
                _lastAlive = _now();
                break;
            case IncomingEvent.Incompatible:
                Hello = null;
                Incompatible = true;
                break;
            case IncomingEvent.Heartbeat:
                if (Hello is not null) _lastAlive = _now();
                break;
            case IncomingEvent.Window w:
                Window = w.Value;
                if (Hello is not null) _lastAlive = _now();
                break;
            case IncomingEvent.Ack:
                if (Hello is not null) _lastAlive = _now();
                break;
        }
    }

    /// Faut-il envoyer un PING maintenant ? (au lancement, puis après 6 s sans signe de vie ; 2 s en resynchro)
    public bool ShouldPing(bool resync = false)
    {
        var now = _now();
        var interval = resync ? FlProtocol.ResyncPingInterval : FlProtocol.PingInterval;
        if (Alive && !resync) return false;
        if (now - _lastPing < interval) return false;
        _lastPing = now;
        return true;
    }

    /// Trame signée pour l'action, ou null (pas de HELLO, séquence épuisée, action hors protocole).
    public CcMessage[]? NextFrame(int action, FrameSigner signer)
    {
        if (Hello is null || _seq >= FlProtocol.SeqMax) return null;
        var frame = FrameEncoder.Frame(_seq + 1, action, Hello.Nonce, signer);
        if (frame is not null) _seq++;
        return frame;
    }

    public void Reset()
    {
        Hello = null;
        Window = FlWindow.Unknown;
        _seq = 0;
        _lastAlive = DateTimeOffset.MinValue;
    }
}
