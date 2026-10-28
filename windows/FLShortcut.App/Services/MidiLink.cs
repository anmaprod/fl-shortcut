// Audit : SEC-01 (trames signées HMAC, séquence monotone, nonce de session), WIN-10 / SEC-02 (port usurpable :
//         seules les trames signées agissent, et l'appli ne fait confiance qu'au HELLO pour le statut),
//         SEC-10 (PING borné), REL-06 (statut Relié / Lien inactif / FL fermé), REL-10 (ports surveillés et
//         rouverts paresseusement). Contrat : PROTOCOL.md v2.
//
// Ports (WinMM) : l'appli écrit sur la sortie « FL Shortcuts » (lue par FL) et lit l'entrée « FL Shortcuts Retour »
// (écrite par FL). Ces deux ports de bouclage sont créés par loopMIDI ou par Windows MIDI Services. Toute la logique
// du lien (HELLO, battements, accusés, réponses signées, réveil du script, commandes de l'Organiser) est celle du cœur,
// LinkCore, la même que sur le Mac ; ici, seulement les ports WinMM.
using FLShortcut.App.Native;
using FLShortcut.Core;

namespace FLShortcut.App.Services;

internal sealed class MidiLink : IDisposable, IMidiTransport
{
    public const string ToFlPortName = "FL Shortcuts";
    public const string FromFlPortName = "FL Shortcuts Retour";
    // Ports loopMIDI créés sous l'ancien nom de l'appli (« FL Shortcut ») : toujours acceptés.
    private const string OldToFlPortName = "FL Shortcut";
    private const string OldFromFlPortName = "FL Shortcut Retour";

    private readonly object _gate = new();
    private readonly Win32.MidiInProc _inProc;        // gardé vivant pour WinMM
    private IntPtr _out = IntPtr.Zero;
    private IntPtr _in = IntPtr.Zero;
    private Timer? _timer;
    private bool _wasAlive;

    /// Appelé (hors thread d'interface) à chaque changement visible : statut, fenêtre, capacités.
    public event Action? Changed;

    /// La logique du lien, commune au Mac (PROTOCOL.md).
    public LinkCore Core { get; }

    public MidiLink()
    {
        _inProc = OnMidiIn;
        Core = new LinkCore(this, null);
    }

    public bool PortsPresent { get; private set; }
    public bool Incompatible => Core.State.IncompatibleProtocol is not null;
    public HelloInfo? Hello => Core.State.Hello;
    public bool Alive => Core.RoutingView().Linked;
    public FlWindow Window => Core.State.Window;
    public bool HasKey => Core.State.HasKey;
    /// Le script a dit être posé sur une autre entrée MIDI que « FL Shortcuts ».
    public bool WrongInput => Core.State.WrongInput;

    public void SetKey(byte[]? key)
    {
        Core.SetKey(key);
        Changed?.Invoke();
    }

    /// Ports déjà ouverts et surveillés (mode avec actions MIDI, ou Organiser déjà lancé).
    public bool Started => _timer is not null;

    /// Ports ouverts et surveillés, PING quand FL tourne (mode avec actions MIDI, ou à la demande : Organiser).
    public void Start()
    {
        _timer ??= new Timer(_ => Tick(), null, TimeSpan.Zero, TimeSpan.FromSeconds(1));
    }

    /// Vue pour le hook clavier (copie immuable).
    public LinkRoutingView RoutingView() => Core.RoutingView();

    /// Envoie une action signée. Faux si le lien, la clé ou le port manquent (la touche sera rendue à FL).
    public bool SendAction(int id) => Core.SendAction(id) == LinkCore.SendResult.Sent;

    /// Macro (bloquant, jamais sur le fil de l'interface) : ports ouverts à la demande, script réveillé brièvement
    /// (`brief` : mode léger, il se rendort ensuite), actions dans l'ordre. null si FL les a faites, sinon la raison.
    public string? RunBriefly(IReadOnlyList<int> ids, bool brief)
    {
        if (!HasKey || !(PortsPresent || PortsExist())) return Loc.T("lien avec FL non installé");
        Start();
        lock (_gate)
        {
            if (_out == IntPtr.Zero || _in == IntPtr.Zero) OpenUnlocked();
        }
        return Core.RunBriefly(ids, brief);
    }

    /// Opération de l'Organiser (PROTOCOL.md §8), bloquante : ports ouverts à la demande, script réveillé si besoin.
    public RequestReply RunRequest(byte[] bytes, bool brief)
    {
        Start();
        lock (_gate)
        {
            if (_out == IntPtr.Zero || _in == IntPtr.Zero) OpenUnlocked();
        }
        return Core.RunRequest(bytes, brief, TimeSpan.FromSeconds(1.5));
    }

    // ---------- IMidiTransport ----------

    bool IMidiTransport.IsReady
    {
        get { lock (_gate) return _out != IntPtr.Zero; }
    }

    // Appelé par le cœur sous son verrou : l'ordre est toujours « cœur puis ports », jamais l'inverse.
    bool IMidiTransport.Send(IReadOnlyList<CcMessage> messages)
    {
        var failed = false;
        lock (_gate)
        {
            if (_out == IntPtr.Zero) OpenUnlocked();
            if (_out == IntPtr.Zero) return false;
            foreach (var m in messages)
            {
                if (Win32.midiOutShortMsg(_out, m.ShortMessage) == Win32.MMSYSERR_NOERROR) continue;
                CloseUnlocked();
                failed = true;
                break;
            }
        }
        if (failed) Core.Reset();
        return !failed;
    }

    private void Tick()
    {
        var changed = false;
        lock (_gate)
        {
            if (_out == IntPtr.Zero || _in == IntPtr.Zero) changed |= OpenUnlocked();
        }
        Core.Tick(FlPresence.IsRunning());
        var alive = Alive;
        changed |= alive != _wasAlive;
        _wasAlive = alive;
        if (changed) Changed?.Invoke();
    }

    // Le rappel WinMM ne prend jamais de verrou (midiInReset/Close peuvent l'attendre) : il met en file,
    // et un seul « videur » à la fois traite la file dans l'ordre d'arrivée.
    private readonly System.Collections.Concurrent.ConcurrentQueue<uint> _incoming = new();
    private int _draining;
    private const int MaxQueued = 4096;      // SEC-10 : un flot MIDI ne peut pas faire grossir la mémoire

    private void OnMidiIn(IntPtr hMidiIn, uint wMsg, IntPtr instance, IntPtr param1, IntPtr param2)
    {
        if (wMsg != Win32.MIM_DATA || _incoming.Count >= MaxQueued) return;
        _incoming.Enqueue((uint)(param1.ToInt64() & 0xFFFFFFFF));
        if (Interlocked.Exchange(ref _draining, 1) == 0) ThreadPool.UnsafeQueueUserWorkItem(_ => Drain(), null);
    }

    private void Drain()
    {
        while (true)
        {
            var notify = false;
            while (_incoming.TryDequeue(out var raw))
            {
                var e = Core.ReceiveShort(raw);
                if (e is not null and not IncomingEvent.Heartbeat and not IncomingEvent.Ack and not IncomingEvent.Response
                    and not IncomingEvent.Reason) notify = true;
            }
            if (notify) Changed?.Invoke();
            Volatile.Write(ref _draining, 0);
            // Un message arrivé entre la fin de la boucle et la remise à zéro : on reprend la main si personne ne l'a.
            if (_incoming.IsEmpty || Interlocked.Exchange(ref _draining, 1) != 0) return;
        }
    }

    private bool OpenUnlocked()
    {
        var outId = FindOut(ToFlPortName) ?? FindOut(OldToFlPortName);
        var inId = FindIn(FromFlPortName) ?? FindIn(OldFromFlPortName);
        var present = outId is not null && inId is not null;
        var changed = present != PortsPresent;
        PortsPresent = present;
        if (!present) return changed;

        if (_out == IntPtr.Zero && Win32.midiOutOpen(out var hOut, outId!.Value, IntPtr.Zero, IntPtr.Zero, Win32.CALLBACK_NULL) == Win32.MMSYSERR_NOERROR)
            _out = hOut;
        if (_in == IntPtr.Zero && Win32.midiInOpen(out var hIn, inId!.Value, _inProc, IntPtr.Zero, Win32.CALLBACK_FUNCTION) == Win32.MMSYSERR_NOERROR)
        {
            _in = hIn;
            Win32.midiInStart(_in);
        }
        return true;
    }

    private void CloseUnlocked()
    {
        // Le rappel d'entrée ne prend aucun verrou : fermer ici ne peut pas bloquer. L'appelant remet ensuite le cœur à
        // zéro (Core.Reset), hors de ce verrou.
        if (_in != IntPtr.Zero)
        {
            Win32.midiInStop(_in);
            Win32.midiInReset(_in);
            Win32.midiInClose(_in);
            _in = IntPtr.Zero;
        }
        if (_out != IntPtr.Zero)
        {
            Win32.midiOutClose(_out);
            _out = IntPtr.Zero;
        }
        _incoming.Clear();
    }

    private static bool NameMatches(string? actual, string wanted)
    {
        if (string.IsNullOrEmpty(actual)) return false;
        actual = actual.Trim();
        if (string.Equals(actual, wanted, StringComparison.OrdinalIgnoreCase)) return true;
        // loopMIDI / Windows MIDI Services peuvent ajouter un suffixe numérique : « FL Shortcuts 1 ».
        if (!actual.StartsWith(wanted + " ", StringComparison.OrdinalIgnoreCase)) return false;
        var rest = actual[(wanted.Length + 1)..];
        return rest.All(char.IsDigit);
    }

    private static uint? FindOut(string name)
    {
        var n = Win32.midiOutGetNumDevs();
        for (uint i = 0; i < n; i++)
        {
            var caps = new Win32.MIDIOUTCAPSW();
            if (Win32.midiOutGetDevCapsW(new UIntPtr(i), ref caps, (uint)System.Runtime.InteropServices.Marshal.SizeOf<Win32.MIDIOUTCAPSW>()) == 0
                && NameMatches(caps.szPname, name)) return i;
        }
        return null;
    }

    private static uint? FindIn(string name)
    {
        var n = Win32.midiInGetNumDevs();
        for (uint i = 0; i < n; i++)
        {
            var caps = new Win32.MIDIINCAPSW();
            if (Win32.midiInGetDevCapsW(new UIntPtr(i), ref caps, (uint)System.Runtime.InteropServices.Marshal.SizeOf<Win32.MIDIINCAPSW>()) == 0
                && NameMatches(caps.szPname, name)) return i;
        }
        return null;
    }

    /// Les deux ports existent-ils ? (pour l'écran « Préparer la connexion »)
    public static bool PortsExist() => (FindOut(ToFlPortName) ?? FindOut(OldToFlPortName)) is not null
                                       && (FindIn(FromFlPortName) ?? FindIn(OldFromFlPortName)) is not null;

    public void Dispose()
    {
        _timer?.Dispose();
        _timer = null;
        lock (_gate) CloseUnlocked();
        Core.Reset();
    }
}
