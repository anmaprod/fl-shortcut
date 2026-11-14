// Audit : SEC-01 (trames signées HMAC, séquence monotone, nonce de session), WIN-10 / SEC-02 (port usurpable :
//         seules les trames signées agissent, et l'appli ne fait confiance qu'au HELLO pour le statut),
//         SEC-10 (PING borné), REL-06 (statut Relié / Lien inactif / FL fermé), REL-10 (ports surveillés et
//         rouverts paresseusement). Contrat : PROTOCOL.md v2.
//
// Ports (WinMM) : l'appli écrit sur la sortie « FL Shortcuts » (lue par FL) et lit l'entrée « FL Shortcuts Retour »
// ET la boucle « FL Shortcuts » (09/11 : FL répond sur la sortie qu'il apparie au Port de l'entrée, souvent celle du
// même nom ; LinkInputs garde la première entrée qui apporte un HELLO). Ces deux ports de bouclage sont créés par loopMIDI ou par Windows MIDI Services (MidiServicesPorts :
// Windows 11 25H2 à jour, l'appli les crée elle-même). Toute la logique
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
    /// Entrées : 0 = « FL Shortcuts Retour », 1 = la boucle « FL Shortcuts » (LinkInputs).
    private readonly IntPtr[] _ins = new IntPtr[LinkInputs.Count];
    private readonly LinkInputs _inputs = new();
    private long _sent;
    private string? _openError;
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
        lock (_gate) _timer ??= new Timer(_ => Tick(), null, TimeSpan.Zero, TimeSpan.FromSeconds(1));
    }

    /// Vue pour le hook clavier (copie immuable).
    public LinkRoutingView RoutingView() => Core.RoutingView();

    /// Envoie une action signée. Faux si le lien, la clé ou le port manquent (la touche sera rendue à FL).
    public bool SendAction(int id) => Core.SendAction(id) == LinkCore.SendResult.Sent;

    /// Macro (bloquant, jamais sur le fil de l'interface) : lien ouvert le temps du bloc (mode léger), script réveillé
    /// brièvement (`brief` : il se rendort ensuite), actions dans l'ordre. null si FL les a faites, sinon la raison.
    public string? RunBriefly(IReadOnlyList<int> ids, bool brief)
    {
        if (!HasKey) return Loc.T("lien avec FL non installé");
        return Borrow(() =>
        {
            if (!(PortsPresent || PortsReady())) return Loc.T("lien avec FL non installé");
            if (MidiServicesPorts.FlOpenedBefore()) return RestartFlReason;
            OpenNow();
            return Core.RunBriefly(ids, brief);
        });
    }

    /// Commande avec données (PROTOCOL.md §7 : Nom et couleur d'une macro), bloquante : lien ouvert le temps du bloc,
    /// script réveillé si besoin (`brief` : il se rendort ensuite).
    public DataReply RunData(IReadOnlyList<byte> units, bool brief)
    {
        if (!HasKey) return new DataReply.Failed(Loc.T("lien avec FL non installé"));
        return Borrow<DataReply>(() =>
        {
            if (!(PortsPresent || PortsReady())) return new DataReply.Failed(Loc.T("lien avec FL non installé"));
            if (MidiServicesPorts.FlOpenedBefore()) return new DataReply.Failed(RestartFlReason);
            OpenNow();
            return Core.RunData(units, brief);
        });
    }

    /// Opération de l'Organiser (PROTOCOL.md §8), bloquante, seulement tant que l'Organiser tient le lien (mode léger ;
    /// comme le Mac : une demande arrivée après la fin du rangement ne le rouvre jamais).
    public RequestReply RunRequest(byte[] bytes, bool brief)
    {
        if (Light() && !Holds(LinkUser.Organizer)) return new RequestReply.Failed(Loc.T("lien avec FL fermé (Organiser fini)"));
        PortsReady();
        OpenNow();
        return Core.RunRequest(bytes, brief, TimeSpan.FromSeconds(1.5));
    }

    /// FL ouvert avant les ports de l'appli : il ne les voit qu'après un redémarrage (Windows).
    public static string RestartFlReason => Loc.T("Relance FL Studio : il voit le lien seulement à son ouverture.");

    private void OpenNow()
    {
        Start();
        lock (_gate)
        {
            if (_out == IntPtr.Zero || !AnyInput()) OpenUnlocked();
        }
    }

    // ---------- Lien seulement quand on s'en sert (mode léger), miroir de MIDILink.swift ----------
    //
    // Retour du 08/11 (« FL rame… dès qu'une touche qui a besoin du MIDI est appuyée, ça s'ouvre, et ça se ferme dès que
    // l'action est terminée, ou si elle a échoué ») : avant, une macro ou l'Organiser ouvrait le lien et il restait
    // ouvert jusqu'à la fermeture de l'appli (PING toutes les 6 à 60 s : le script de FL se réveillait sans cesse).
    // Maintenant : ouvert par l'Organiser (de « Démarrer » à la fin du rangement) ou le temps d'un bloc de macro,
    // fermé à la fin de la macro (ou 3 s après son dernier bloc), et le surveillant ferme ce que personne ne tient.
    // Les ports eux-mêmes restent jusqu'à la sortie de l'appli (08/11 au soir : FL, sous Windows, ne voit un port qu'à
    // son ouverture) ; lien fermé = plus aucun message dedans, le script de FL se rendort.

    private readonly HashSet<LinkUser> _users = new();
    private int _macroGeneration;
    private int _activeBorrows;
    private long _lastBorrowEnd = DateTime.MinValue.Ticks;
    private DateTime? _openedAt;
    private DateTime? _organizerGoneSince;
    /// FL relie le script à un appareil qui vient d'apparaître : PING jusqu'à son HELLO, ce temps au plus.
    public const double WarmUpLimit = 8;

    /// Mode léger (lu à chaque fois).
    public Func<bool> Light { get; set; } = () => true;
    /// L'Organiser tient-il encore le lien ? (fenêtre ouverte, rangement pas fini).
    public Func<bool> OrganizerHoldsLink { get; set; } = () => false;

    public bool Holds(LinkUser user)
    {
        lock (_users) return _users.Contains(user);
    }

    /// `user` a besoin du lien : ports créés par Windows s'il le faut, ouverts et surveillés. Vrai si le lien vient
    /// d'être ouvert (FL met un moment à voir l'appareil et à réveiller son script).
    public bool Use(LinkUser user) => Use(user, out _);

    private bool Use(LinkUser user, out bool portsNew)
    {
        lock (_users) _users.Add(user);
        var existed = PortsExist();
        portsNew = !existed && MidiServicesPorts.EnsureIfNeeded();
        var wasStarted = Started;
        Start();
        if (!wasStarted)
        {
            _openedAt = DateTime.UtcNow;
            AppLog.Write("MIDI", portsNew ? "link opened (ports created by Windows)" : "link opened");
        }
        return portsNew || !wasStarted;
    }

    /// `user` n'en a plus besoin ; plus personne (mode léger) : lien fermé tout de suite.
    public void Release(LinkUser user)
    {
        bool nobody;
        lock (_users)
        {
            _users.Remove(user);
            nobody = _users.Count == 0;
        }
        if (Light() && nobody) Close("nobody uses it");
    }

    /// Fin d'une macro (réussie, ratée ou arrêtée) : le lien qu'elle a ouvert est fermé tout de suite.
    public void MacroEnded()
    {
        if (!Light() || Volatile.Read(ref _activeBorrows) > 0 || !Holds(LinkUser.Macro)) return;
        Interlocked.Increment(ref _macroGeneration);       // la fermeture prévue 3 s après le dernier bloc n'a plus lieu
        Release(LinkUser.Macro);
    }

    private T Borrow<T>(Func<T> body)
    {
        if (!Light() || Holds(LinkUser.Organizer)) return body();
        var generation = Interlocked.Increment(ref _macroGeneration);
        Interlocked.Increment(ref _activeBorrows);
        try
        {
            Use(LinkUser.Macro, out var portsNew);
            if (portsNew && !MidiServicesPorts.FlOpenedBefore()) WarmUp();
            return body();
        }
        finally
        {
            Interlocked.Decrement(ref _activeBorrows);
            Interlocked.Exchange(ref _lastBorrowEnd, DateTime.UtcNow.Ticks);
            _ = Task.Delay(TimeSpan.FromSeconds(LinkWatch.MacroLinger)).ContinueWith(_ =>
            {
                if (Volatile.Read(ref _macroGeneration) == generation) Release(LinkUser.Macro);
            }, TaskScheduler.Default);
        }
    }

    /// Ports tout juste créés par Windows : FL les voit et relie son script ; PING jusqu'à son HELLO.
    private void WarmUp()
    {
        var deadline = DateTime.UtcNow.AddSeconds(WarmUpLimit);
        Thread.Sleep(500);
        OpenNow();
        while (DateTime.UtcNow < deadline)
        {
            if (Core.RunBriefly(Array.Empty<int>(), brief: true, TimeSpan.FromSeconds(0.7)) is null)
            {
                AppLog.Write("MIDI", "script ready after the ports appeared");
                return;
            }
        }
        AppLog.Write("MIDI", "no answer from FL after the ports appeared");
    }

    /// Lien fermé : plus de battement ni de PING, ports WinMM fermés, ports de Windows retirés.
    private void Close(string why)
    {
        var timer = Interlocked.Exchange(ref _timer, null);
        timer?.Dispose();
        bool had;
        lock (_gate)
        {
            had = _out != IntPtr.Zero || AnyInput() || timer is not null;
            CloseUnlocked();
        }
        Core.Reset();
        _organizerGoneSince = null;
        var since = _openedAt;
        _openedAt = null;
        // Les ports restent (MidiServicesPorts : FL ne voit un port qu'à son ouverture) ; plus rien ne passe dedans.
        if (had)
        {
            var seconds = since is { } d ? $" after {(DateTime.UtcNow - d).TotalSeconds:0.0} s" : "";
            AppLog.Write("MIDI", $"link closed{seconds} ({why})");
        }
        Changed?.Invoke();
    }

    /// Surveillant (mode léger, chaque seconde) : vrai s'il vient de fermer le lien.
    private bool Watch()
    {
        LinkUser[] holders;
        lock (_users) holders = _users.ToArray();
        var now = DateTime.UtcNow;
        var since = (now - new DateTime(Interlocked.Read(ref _lastBorrowEnd), DateTimeKind.Utc)).TotalSeconds;
        double? gone = _organizerGoneSince is { } g ? (now - g).TotalSeconds : null;
        var v = LinkWatch.Decide(holders, Volatile.Read(ref _activeBorrows), since, OrganizerHoldsLink(), gone);
        _organizerGoneSince = v.OrganizerGone ? (_organizerGoneSince ?? now) : null;
        foreach (var user in v.Release)
        {
            AppLog.Write("MIDI", $"watchdog: {(user == LinkUser.Macro ? "macro" : "organizer")} hold dropped");
            if (user == LinkUser.Macro) Interlocked.Increment(ref _macroGeneration);
            Release(user);
        }
        if (v.CloseNow) Close("watchdog: nobody uses it");
        return _timer is null;
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
            // Mode léger, lien fermé (personne ne s'en sert) : rien ne le rouvre en douce.
            if (_out == IntPtr.Zero && _timer is not null) OpenUnlocked();
            if (_out == IntPtr.Zero) return false;
            foreach (var m in messages)
            {
                if (Win32.midiOutShortMsg(_out, m.ShortMessage) == Win32.MMSYSERR_NOERROR)
                {
                    _sent++;
                    continue;
                }
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
        if (_timer is null) return;
        if (Light() && Watch()) return;                  // lien fermé par le surveillant
        var changed = false;
        lock (_gate)
        {
            if (_timer is null) return;                  // fermé entre-temps : on ne rouvre rien
            if (_out == IntPtr.Zero || !AnyInput()) changed |= OpenUnlocked();
        }
        Core.Tick(FlPresence.IsRunning());
        var alive = Alive;
        changed |= alive != _wasAlive;
        _wasAlive = alive;
        if (changed) Changed?.Invoke();
    }

    // Le rappel WinMM ne prend jamais de verrou (midiInReset/Close peuvent l'attendre) : il met en file,
    // et un seul « videur » à la fois traite la file dans l'ordre d'arrivée.
    private readonly System.Collections.Concurrent.ConcurrentQueue<(uint Raw, int Source)> _incoming = new();
    private int _draining;
    private const int MaxQueued = 4096;      // SEC-10 : un flot MIDI ne peut pas faire grossir la mémoire

    private void OnMidiIn(IntPtr hMidiIn, uint wMsg, IntPtr instance, IntPtr param1, IntPtr param2)
    {
        if (wMsg != Win32.MIM_DATA || _incoming.Count >= MaxQueued) return;
        _incoming.Enqueue(((uint)(param1.ToInt64() & 0xFFFFFFFF), (int)instance.ToInt64()));
        if (Interlocked.Exchange(ref _draining, 1) == 0) ThreadPool.UnsafeQueueUserWorkItem(_ => Drain(), null);
    }

    private void Drain()
    {
        while (true)
        {
            var notify = false;
            while (_incoming.TryDequeue(out var item))
            {
                // Les deux entrées peuvent porter les mêmes messages de FL : une seule est écoutée.
                if (!_inputs.Accept(item.Source, item.Raw, DateTime.UtcNow)) continue;
                var e = Core.ReceiveShort(item.Raw);
                if (e is not null and not IncomingEvent.Heartbeat and not IncomingEvent.Ack and not IncomingEvent.Response
                    and not IncomingEvent.Reason) notify = true;
            }
            if (notify) Changed?.Invoke();
            Volatile.Write(ref _draining, 0);
            // Un message arrivé entre la fin de la boucle et la remise à zéro : on reprend la main si personne ne l'a.
            if (_incoming.IsEmpty || Interlocked.Exchange(ref _draining, 1) != 0) return;
        }
    }

    private bool AnyInput() => _ins.Any(h => h != IntPtr.Zero);

    private bool OpenUnlocked()
    {
        var outId = FindOut(ToFlPortName) ?? FindOut(OldToFlPortName);
        var inIds = new[]
        {
            FindIn(FromFlPortName) ?? FindIn(OldFromFlPortName),
            FindIn(ToFlPortName) ?? FindIn(OldToFlPortName),        // la boucle de « FL Shortcuts »
        };
        var present = outId is not null && inIds.Any(id => id is not null);
        var changed = present != PortsPresent;
        PortsPresent = present;
        if (!present) return changed;

        string? error = null;
        if (_out == IntPtr.Zero)
        {
            var r = Win32.midiOutOpen(out var hOut, outId!.Value, IntPtr.Zero, IntPtr.Zero, Win32.CALLBACK_NULL);
            if (r == Win32.MMSYSERR_NOERROR) _out = hOut;
            else error = $"sortie {r}";
        }
        for (var i = 0; i < _ins.Length; i++)
        {
            if (_ins[i] != IntPtr.Zero || inIds[i] is not { } id) continue;
            var r = Win32.midiInOpen(out var hIn, id, _inProc, new IntPtr(i), Win32.CALLBACK_FUNCTION);
            if (r == Win32.MMSYSERR_NOERROR)
            {
                _ins[i] = hIn;
                Win32.midiInStart(hIn);
            }
            else error ??= $"entrée {i} {r}";
        }
        if (error != _openError)
        {
            _openError = error;
            if (error is not null) AppLog.Write("MIDI", "link port not opened (" + error + ")");
        }
        return true;
    }

    /// Diagnostic (nombres seulement) : messages envoyés, messages de FL reçus sur « Retour » + la boucle, entrée
    /// gardée, erreur d'ouverture.
    public string Counters
    {
        get
        {
            var active = _inputs.Active switch { 0 => "retour", 1 => "boucle", _ => "?" };
            return $"envoyés={Interlocked.Read(ref _sent)} reçus={_inputs.FromFl(0)}+{_inputs.FromFl(1)} entrée={active}"
                   + (_openError is { } e ? $" ouverture={e}" : "");
        }
    }

    private void CloseUnlocked()
    {
        // Le rappel d'entrée ne prend aucun verrou : fermer ici ne peut pas bloquer. L'appelant remet ensuite le cœur à
        // zéro (Core.Reset), hors de ce verrou.
        for (var i = 0; i < _ins.Length; i++)
        {
            if (_ins[i] == IntPtr.Zero) continue;
            Win32.midiInStop(_ins[i]);
            Win32.midiInReset(_ins[i]);
            Win32.midiInClose(_ins[i]);
            _ins[i] = IntPtr.Zero;
        }
        if (_out != IntPtr.Zero)
        {
            Win32.midiOutClose(_out);
            _out = IntPtr.Zero;
        }
        _incoming.Clear();
        _inputs.Reset();
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

    /// Les deux ports sont là, ou Windows vient de les créer (Windows MIDI Services, sans loopMIDI).
    public static bool PortsReady() => PortsExist() || MidiServicesPorts.EnsureIfNeeded();

    /// Les ports sont là, ou Windows les créera quand le lien servira (rien à installer).
    public static bool PortsUsable() => PortsExist() || MidiServicesPorts.Available;

    /// Les deux ports existent-ils ? (pour l'écran « Préparer la connexion »)
    public static bool PortsExist() => (FindOut(ToFlPortName) ?? FindOut(OldToFlPortName)) is not null
                                       && (FindIn(FromFlPortName) ?? FindIn(OldFromFlPortName)
                                           ?? FindIn(ToFlPortName) ?? FindIn(OldToFlPortName)) is not null;

    public void Dispose()
    {
        _timer?.Dispose();
        _timer = null;
        lock (_gate) CloseUnlocked();
        Core.Reset();
    }
}
