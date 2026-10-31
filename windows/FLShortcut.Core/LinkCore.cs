// Logique du lien avec le script de FL, sans WinMM : réception (HELLO, battements, accusés, raisons, réponses
// signées), envoi des trames signées, réveil du script, commandes avec données et leurs réponses (Organiser, macros).
// Miroir de LinkCore (Sources/FLShortcut/MIDILink.swift). Sûr entre fils : reçoit depuis le fil WinMM, envoie depuis
// le hook clavier, la macro ou l'Organiser, est lue depuis l'interface. Audit : SEC-01, SEC-10, REL-06.
namespace FLShortcut.Core;

/// Sortie MIDI vers FL. Injectable pour les tests.
public interface IMidiTransport
{
    bool IsReady { get; }
    bool Send(IReadOnlyList<CcMessage> messages);
}

public sealed class LinkCore
{
    public enum SendResult { Sent, NotLinked, NoKey, Unavailable, SequenceExhausted, TransportFailed }

    public sealed record Snapshot(HelloInfo? Hello, DateTimeOffset? LastAlive, FlWindow Window, bool HasKey, uint Seq,
        int? IncompatibleProtocol, bool TransportReady, double? ResponseMs, bool WrongInput);

    private readonly object _gate = new();
    private readonly IMidiTransport _transport;
    private readonly Func<DateTimeOffset> _clock;
    private readonly IncomingDecoder _decoder = new();
    private FrameSigner? _signer;
    private HelloInfo? _hello;
    private DateTimeOffset? _helloAt;
    private DateTimeOffset? _lastBeat;
    private FlWindow _window = FlWindow.Unknown;
    private uint _seq;
    private DateTimeOffset? _lastPing;
    /// Intervalle des PING sans réponse : 6 s, puis doublé jusqu'à 60 s tant que FL ne répond pas.
    private TimeSpan _pingBackoff = FlProtocol.PingInterval;
    private int _consecutiveRejects;
    /// Dernier accusé reçu (0 = refus) : la macro attend celui de sa dernière commande.
    private int? _lastAckedId;
    /// Raison du dernier refus d'une commande avec données (CC 116), remise à null à chaque envoi.
    private int? _lastReason;
    /// Seq de la dernière commande avec données : une réponse signée doit lui être liée (PROTOCOL.md §8).
    private uint? _dataSeq;
    /// Réponse vérifiée (MAC juste, liée à `_dataSeq`), octets dépaquetés ; remise à null à chaque envoi.
    private byte[]? _lastResponse;
    private int? _incompatible;
    private bool _wrongInput;
    private (int Id, long At)? _pendingSend;
    private readonly List<double> _latencies = new();

    public LinkCore(IMidiTransport transport, byte[]? key, Func<DateTimeOffset>? clock = null)
    {
        _transport = transport;
        _clock = clock ?? (() => DateTimeOffset.UtcNow);
        _signer = FrameSigner.Create(key);
    }

    /// Script de FL muet : en général le Controller type « (generic controller) » (le script n'est pas chargé), ou des
    /// numéros de Port différents pour l'entrée et la sortie.
    public static string NoResponse => Loc.T("FL ne répond pas : quitte et rouvre FL Studio. Toujours rien : dans Options › MIDI Settings, entrée « FL Shortcuts », choisis le Controller type « FL Shortcuts » (pas « generic controller »), et donne le même numéro de Port à l'entrée « FL Shortcuts » et à la sortie « FL Shortcuts Retour »");

    private DateTimeOffset? LastAlive => (_helloAt, _lastBeat) switch
    {
        ({ } a, { } b) => a > b ? a : b,
        ({ } a, null) => a,
        _ => null,                      // battement sans HELLO : nonce inconnu, pas « relié »
    };

    public void SetKey(byte[]? key)
    {
        lock (_gate) _signer = FrameSigner.Create(key);
    }

    // ---------- Réception ----------

    /// Message court reçu sur l'entrée « FL Shortcuts Retour » (WinMM : statut | data1 << 8 | data2 << 16).
    public IncomingEvent? ReceiveShort(uint msg) =>
        Receive((byte)(msg & 0xFF), (byte)((msg >> 8) & 0xFF), (byte)((msg >> 16) & 0xFF));

    public IncomingEvent? Receive(byte status, byte cc, byte value)
    {
        var now = _clock();
        var needsResync = false;
        IncomingEvent? e;
        lock (_gate)
        {
            e = _decoder.Feed(status, cc, value);
            switch (e)
            {
                case IncomingEvent.Hello h:
                    // Même nonce (HELLO renvoyé) : la séquence du script n'a pas été remise à zéro.
                    if (_hello is null || !_hello.Nonce.SequenceEqual(h.Info.Nonce)) _seq = 0;
                    _hello = h.Info;
                    _helloAt = now;
                    _pingBackoff = FlProtocol.PingInterval;
                    _window = FlWindow.Unknown;        // le script renvoie la fenêtre juste après
                    _consecutiveRejects = 0;
                    _incompatible = null;
                    _wrongInput = false;
                    break;
                case IncomingEvent.WrongInput:
                    _wrongInput = true;
                    break;
                case IncomingEvent.Incompatible inc:
                    _hello = null;
                    _helloAt = null;
                    _incompatible = inc.ProtocolVersion;
                    break;
                case IncomingEvent.Heartbeat:
                    _lastBeat = now;
                    _pingBackoff = FlProtocol.PingInterval;
                    break;
                case IncomingEvent.Window w:
                    _window = w.Value;
                    break;
                case IncomingEvent.Reason r:
                    _lastReason = r.Value;
                    break;
                case IncomingEvent.Response resp:
                    // Retenue seulement si son MAC est juste pour la dernière commande avec données.
                    if (_signer is { } signer && _hello?.Nonce is { } nonce && _dataSeq is { } seq
                        && resp.Op is >= 0 and <= 127
                        && signer.Mac(nonce, seq, (byte)resp.Op, resp.Units).AsSpan().SequenceEqual(resp.Mac)
                        && Pack7.Unpack(resp.Units) is { } bytes)
                        _lastResponse = bytes;
                    break;
                case IncomingEvent.Ack ack:
                    _lastAckedId = ack.Id;
                    // Un refus expliqué (CC 116 : rien de sélectionné…) n'est pas un rejet de trame.
                    if (ack.Id == 0 && _lastReason is null)
                    {
                        _consecutiveRejects++;
                        if (_consecutiveRejects >= 2) { needsResync = true; _consecutiveRejects = 0; }
                    }
                    else
                    {
                        _consecutiveRejects = 0;
                        if (_pendingSend is { } p && p.Id == ack.Id)
                        {
                            var ms = (System.Diagnostics.Stopwatch.GetTimestamp() - p.At) * 1000.0 / System.Diagnostics.Stopwatch.Frequency;
                            if (ms is >= 0 and < 2000)
                            {
                                _latencies.Add(ms);
                                if (_latencies.Count > 15) _latencies.RemoveRange(0, _latencies.Count - 15);
                            }
                        }
                    }
                    _pendingSend = null;
                    break;
            }
        }
        if (needsResync) Ping(FlProtocol.ResyncPingInterval);
        return e;
    }

    // ---------- Envoi ----------

    /// PING (CC 103 = 1), limité à un tous les `minInterval` (le script ignore plus de 4 PING/s).
    public bool Ping(TimeSpan? minInterval = null)
    {
        var now = _clock();
        var min = minInterval ?? TimeSpan.FromSeconds(1);
        lock (_gate)
        {
            if (_lastPing is { } last && now - last < (min > TimeSpan.FromSeconds(0.3) ? min : TimeSpan.FromSeconds(0.3))) return false;
            _lastPing = now;
            return _transport.Send(new[] { CcMessage.Ping });
        }
    }

    /// Macro (bloquant) : réveille le script si besoin, puis envoie les actions dans l'ordre. `brief` (mode léger) :
    /// PING = 2, le script se rendort tout seul ensuite. Renvoie null si tout est parti, sinon la raison.
    public string? RunBriefly(IReadOnlyList<int> ids, bool brief, TimeSpan? timeout = null)
    {
        var wake = Wake(brief, timeout ?? TimeSpan.FromSeconds(4));
        if (wake.Hello is not { } hello) return wake.Why;
        if (ids.Count == 0) return null;
        var last = ids[^1];
        lock (_gate) _lastAckedId = null;
        foreach (var id in ids)
        {
            if (!hello.Capabilities.Contains(id)) return Loc.T("action indisponible dans ce FL (mets FL à jour)");
            switch (SendAction(id))
            {
                case SendResult.Sent: break;
                case SendResult.NoKey: return Loc.T("lien avec FL non installé");
                default: return Loc.T("FL n'a pas reçu la commande");
            }
        }
        // Les trames partent d'affilée et FL les exécute dans l'ordre : on attend l'accusé de la dernière.
        var deadline = DateTime.UtcNow.AddSeconds(1.5);
        while (DateTime.UtcNow < deadline)
        {
            int? acked;
            lock (_gate) acked = _lastAckedId;
            if (acked == last) return null;
            if (acked == 0) return Loc.T("FL a refusé la commande : redémarre FL (le script vient d'être mis à jour)");
            Thread.Sleep(10);
        }
        return Loc.T("FL n'a pas confirmé (armement / REC)");
    }

    /// Réveille le script si besoin (PING) et attend son HELLO. Script déjà réveillé depuis peu : aucun PING, sauf
    /// `force` (il s'est rendormi alors que son dernier battement semblait récent).
    private (HelloInfo? Hello, string? Why) Wake(bool brief, TimeSpan timeout, bool force = false)
    {
        var start = _clock();
        bool hasKey, fresh;
        lock (_gate)
        {
            fresh = !force && _hello is not null && LastAlive is { } alive && start - alive < TimeSpan.FromSeconds(4);
            hasKey = _signer is not null;
        }
        if (!hasKey) return (null, Loc.T("lien avec FL non installé : fiche du raccourci › Installer le lien avec FL"));
        if (!fresh)
        {
            bool sent;
            lock (_gate)
            {
                _hello = null;                  // le HELLO attendu est celui de ce réveil
                _lastPing = start;
                sent = _transport.Send(new[] { brief ? CcMessage.PingBrief : CcMessage.Ping });
            }
            if (!sent) return (null, Loc.T("ports MIDI « FL Shortcuts » indisponibles"));
            var deadline = DateTime.UtcNow + timeout;
            while (DateTime.UtcNow < deadline)
            {
                lock (_gate)
                {
                    if (_hello is not null && LastAlive is { } alive && alive >= start) break;
                }
                Thread.Sleep(30);
            }
        }
        lock (_gate) return _hello is { } hello ? (hello, null) : (null, NoResponse);
    }

    /// Commande avec données (PROTOCOL.md §7, bloquant). Un refus sans raison vient en général d'un script qui s'est
    /// rendormi : il est réveillé par un PING et la commande est renvoyée une seule fois.
    public DataReply RunData(IReadOnlyList<byte> units, bool brief, TimeSpan? timeout = null, int capability = FlProtocol.DataActionId)
    {
        var t = timeout ?? TimeSpan.FromSeconds(4);
        if (AttemptData(units, brief, t, false, capability) is { } first) return first;
        return AttemptData(units, brief, t, true, capability)
               ?? new DataReply.Failed(Loc.T("FL a refusé la commande : redémarre FL si le script vient d'être mis à jour"));
    }

    /// Opération 2 à 26 (Organiser, dégradé ; PROTOCOL.md §8) : comme `RunData`, puis la réponse signée de FL s'il y
    /// en a une (vide sinon). Demande le script v5 (capacité 42).
    public RequestReply RunRequest(IReadOnlyList<byte> bytes, bool brief, TimeSpan? timeout = null)
    {
        var units = Pack7.Pack(bytes);
        if (units.Length > FlProtocol.MaxDataUnits) return new RequestReply.Failed(Loc.T("données trop longues"));
        switch (RunData(units, brief, timeout, FlProtocol.ExtActionId))
        {
            case DataReply.Done:
                lock (_gate) return new RequestReply.Answered(_lastResponse ?? Array.Empty<byte>());
            case DataReply.Refused r:
                return new RequestReply.Refused(r.Reason);
            case DataReply.Failed f:
                return new RequestReply.Failed(f.Why);
            default:
                return new RequestReply.Failed("?");
        }
    }

    /// null : refus sans raison (trame ignorée, script rendormi…).
    private DataReply? AttemptData(IReadOnlyList<byte> units, bool brief, TimeSpan timeout, bool forceWake, int capability)
    {
        var wake = Wake(brief, timeout, forceWake);
        if (wake.Hello is not { } hello) return new DataReply.Failed(wake.Why ?? NoResponse);
        if (!hello.Capabilities.Contains(capability))
            return new DataReply.Failed(Loc.T("mets à jour le lien avec FL : redémarre FL pour charger le nouveau script"));
        lock (_gate) _lastAckedId = null;
        switch (SendData(units))
        {
            case SendResult.Sent: break;
            case SendResult.NoKey: return new DataReply.Failed(Loc.T("lien avec FL non installé"));
            default: return new DataReply.Failed(Loc.T("FL n'a pas reçu la commande"));
        }
        var deadline = DateTime.UtcNow.AddSeconds(1.5);
        while (DateTime.UtcNow < deadline)
        {
            int? ack, reason;
            lock (_gate) { ack = _lastAckedId; reason = _lastReason; }
            if (ack == FlProtocol.DataActionId) return new DataReply.Done();
            if (ack == 0) return reason is { } r ? new DataReply.Refused(r) : null;
            Thread.Sleep(10);
        }
        return new DataReply.Failed(Loc.T("FL n'a pas confirmé"));
    }

    /// Commande avec données : CC 96, unités, trame signée de l'action 41, envoyées dans l'ordre et sous le verrou :
    /// jamais mélangées avec une autre trame.
    public SendResult SendData(IReadOnlyList<byte> units)
    {
        var now = _clock();
        var exhausted = false;
        SendResult result;
        lock (_gate)
        {
            result = Sequence(now, FlProtocol.DataActionId, data: true, out exhausted, next =>
            {
                var messages = FrameEncoder.DataFrame(next, units, _hello!.Nonce, _signer!);
                if (messages is null) return null;
                _lastReason = null;
                _dataSeq = next;
                _lastResponse = null;
                return messages;
            });
        }
        if (exhausted) Ping(FlProtocol.ResyncPingInterval);
        return result;
    }

    /// Envoie une trame authentifiée, émise sous le verrou : jamais deux trames mélangées.
    public SendResult SendAction(int id)
    {
        var now = _clock();
        var exhausted = false;
        SendResult result;
        lock (_gate)
        {
            result = Sequence(now, id, data: false, out exhausted, next =>
            {
                if (!FlActions.IsKnown(id)) return null;
                var frame = FrameEncoder.Frame(next, id, _hello!.Nonce, _signer!);
                if (frame is not null) _lastReason = null;
                return frame;
            });
        }
        if (exhausted) Ping(FlProtocol.ResyncPingInterval);
        return result;
    }

    /// Sous le verrou : vérifications communes, trame suivante, envoi.
    private SendResult Sequence(DateTimeOffset now, int id, bool data, out bool exhausted, Func<uint, CcMessage[]?> build)
    {
        exhausted = false;
        if (_signer is null) return SendResult.NoKey;
        if (_hello is not { } hello || LastAlive is not { } alive || now - alive >= FlProtocol.AliveTimeout) return SendResult.NotLinked;
        if (!hello.Capabilities.Contains(data ? FlProtocol.DataActionId : id)) return SendResult.Unavailable;
        if (_seq >= FlProtocol.SeqMax) { exhausted = true; return SendResult.SequenceExhausted; }
        var next = _seq + 1;
        if (build(next) is not { } messages) return SendResult.Unavailable;
        _seq = next;
        _pendingSend = (id, System.Diagnostics.Stopwatch.GetTimestamp());
        // Envoi par paquets : WinMM envoie message par message, CoreMIDI par 80.
        for (var from = 0; from < messages.Length; from += 80)
        {
            if (!_transport.Send(messages.Skip(from).Take(80).ToArray())) return SendResult.TransportFailed;
        }
        return SendResult.Sent;
    }

    /// À appeler toutes les secondes : PING après 6 s sans battement (ou sans HELLO) quand FL tourne. Sans réponse,
    /// l'intervalle double (6, 12, 24, 48, 60 s) : FL Shortcuts se fait oublier.
    public void Tick(bool flRunning)
    {
        if (!flRunning) return;
        var now = _clock();
        bool stale;
        TimeSpan interval;
        lock (_gate)
        {
            interval = _pingBackoff;
            stale = _hello is null || LastAlive is not { } alive || now - alive >= FlProtocol.AliveTimeout;
        }
        if (!stale || !Ping(interval)) return;
        lock (_gate)
        {
            var doubled = _pingBackoff + _pingBackoff;
            _pingBackoff = doubled > FlProtocol.MaxPingInterval ? FlProtocol.MaxPingInterval : doubled;
        }
    }

    /// Relance immédiate de la recherche de FL (lancement de FL, bouton Tester, nouvelle clé).
    public void ResetPingBackoff()
    {
        lock (_gate) _pingBackoff = FlProtocol.PingInterval;
    }

    /// Ports fermés : plus rien de vivant (le script rouvrira une session avec un nouveau HELLO).
    public void Reset()
    {
        lock (_gate)
        {
            _hello = null;
            _helloAt = null;
            _lastBeat = null;
            _window = FlWindow.Unknown;
            _seq = 0;
        }
    }

    // ---------- Lecture ----------

    public LinkRoutingView RoutingView()
    {
        var now = _clock();
        lock (_gate)
        {
            var alive = _hello is not null && LastAlive is { } a && now - a < FlProtocol.AliveTimeout;
            return new LinkRoutingView(alive, _window, _hello?.Capabilities, _signer is not null);
        }
    }

    public Snapshot State
    {
        get
        {
            var ready = _transport.IsReady;
            lock (_gate)
            {
                double? ms = null;
                if (_latencies.Count > 0)
                {
                    var v = _latencies.OrderBy(x => x).ToArray();
                    var m = v.Length % 2 == 1 ? v[v.Length / 2] : (v[v.Length / 2 - 1] + v[v.Length / 2]) / 2;
                    ms = Math.Round(m * 10) / 10;
                }
                return new Snapshot(_hello, LastAlive, _window, _signer is not null, _seq, _incompatible, ready, ms, _wrongInput);
            }
        }
    }
}
