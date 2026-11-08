// Port MIDI du lien créé par l'appli (08/11, « on peut bosser sur ça ? ») : sur Windows 11 25H2 à jour (Windows MIDI
// Services, arrivé avec la mise à jour de novembre 2026), un port « boucle » de MIDI 1.0 (Basic Loopback) que FL voit
// dans MIDI Settings ; sinon, le pilote installé avec loopMIDI (VirtualMidiPorts). MidiLink l'ouvre par WinMM.
// UN SEUL port, « FL Shortcuts », dans les deux sens (09/11 : avec un second port « FL Shortcuts Retour », FL répondait
// sur la sortie « FL Shortcuts » appariée à son entrée, l'appli écoutait l'autre : lien muet ; et l'entrée « Retour »
// allumée en « generic controller » passait les messages du script au son choisi). Sur ce port boucle, l'appli et le
// script entendent aussi leurs propres messages et les ignorent (numéros de CC disjoints, `FlProtocol.SentByFl`).
//
// Ports créés AU LANCEMENT de l'appli et gardés jusqu'à ce qu'elle quitte (08/11 au soir, diagnostic d'un ami :
// « ports oui · lien muet ») : sous Windows, FL ne voit un port MIDI que s'il existait à son ouverture (manuel
// d'Image-Line : « Refresh device list » pour un appareil arrivé après) et un appareil qui disparaît pendant que FL
// tourne peut le faire tomber. Créés seulement le temps du lien (comme sur le Mac, où FL les voit arriver), FL ne les
// voyait jamais. Rien ne passe dedans hors d'une action (le script de FL dort jusqu'au premier PING) : le lien, lui,
// reste ouvert seulement quand il sert (MidiLink.Use). FL ouvert AVANT les ports : il faut le relancer
// (`FlOpenedBefore`, l'Organiser le demande avec « Quitter et rouvrir FL »).
//
// Windows plus ancien, service absent, loopMIDI déjà là : rien n'est créé par Windows. Jamais d'exception vers
// l'appelant. Journal : MIDI (mots fixes, codes d'erreur).
using FLShortcut.Core;
#if MIDI_SERVICES
using Windows.Devices.Midi2;
using Windows.Devices.Midi2.Transports.BasicLoopback;
#endif

namespace FLShortcut.App.Services;

internal static class MidiServicesPorts
{
    /// Identifiant du port (unique dans le service MIDI de Windows).
    public const string ToFlId = "flshortcuts-to-fl";

    private static readonly object Gate = new();
    private static readonly List<Guid> Created = new();
    private static DateTime _lastFailure = DateTime.MinValue;
    private static bool _failedWithDriver;
    private static bool? _available;
    private static DateTime? _createdAt;
    private sealed record FlStartTime(uint Pid, DateTime? Start);
    private static FlStartTime? _flStart;          // remplacé d'un coup (lu sans verrou)

    /// L'appli sait créer les ports elle-même (Windows 25H2 à jour, ou pilote de loopMIDI installé) : créés au
    /// lancement. Faux tant que `CheckAvailable` n'a pas répondu (sauf pilote de loopMIDI).
    public static bool Available => _available == true || VirtualMidiPorts.DriverInstalled;

    /// Le service MIDI de Windows et ses ports « boucle » sont-ils là ? Bloquant (jusqu'à ~3 s) : en tâche de fond, au
    /// lancement. Rien n'est créé.
    public static bool CheckAvailable()
    {
        if (_available is { } known) return known;
#if MIDI_SERVICES
        try
        {
            _available = MidiApi.EnsureServiceAvailable() && MidiBasicLoopbackManager.IsTransportAvailable;
        }
        catch (Exception e)
        {
            AppLog.Write("MIDI", "Windows MIDI Services indisponible (" + e.GetType().Name + ")");
            _available = false;
        }
#else
        _available = false;
#endif
        return _available.Value;
    }

    /// Les ports ont été créés par Windows (pas par loopMIDI) pendant ce lancement.
    public static bool CreatedByWindows
    {
        get { lock (Gate) return Created.Count > 0 || VirtualMidiPorts.Created; }
    }

    /// Qui a fait les ports, pour le diagnostic : « app » (pilote de loopMIDI), « Windows » (MIDI Services),
    /// « loopMIDI » (déjà là : loopMIDI ouvert), « non ».
    public static string Source()
    {
        lock (Gate)
        {
            if (VirtualMidiPorts.Created) return "app";
            if (Created.Count > 0) return "Windows";
        }
        return MidiLink.PortsExist() ? "loopMIDI" : "non";
    }

    /// FL a été ouvert avant que l'appli crée les ports : il ne les voit pas tant qu'il n'est pas relancé (Windows).
    /// Faux si les ports ne sont pas de l'appli, si FL est fermé ou si son heure d'ouverture est illisible.
    public static bool FlOpenedBefore()
    {
        DateTime created;
        lock (Gate)
        {
            if (_createdAt is not { } c) return false;
            created = c;
        }
        if (FlPresence.RunningInstance() is not { } fl) return false;
        return LinkWatch.FlOpenedBeforePorts(FlStart(fl.Pid), created);
    }

    /// Heure d'ouverture de FL (gardée pour ce processus) ; null si Windows ne la donne pas.
    private static DateTime? FlStart(uint pid)
    {
        if (Volatile.Read(ref _flStart) is { } known && known.Pid == pid) return known.Start;
        DateTime? start = null;
        try
        {
            using var process = System.Diagnostics.Process.GetProcessById((int)pid);
            start = process.StartTime.ToUniversalTime();
        }
        catch (Exception e) when (e is ArgumentException or InvalidOperationException
                                       or System.ComponentModel.Win32Exception or NotSupportedException) { }
        Volatile.Write(ref _flStart, new FlStartTime(pid, start));
        return start;
    }

    /// Le port manque : l'appli le crée si elle sait le faire. Vrai s'il est là ensuite. Bloquant
    /// (jusqu'à ~3 s la première fois) : jamais sur le fil de l'interface. Au lancement de l'appli, puis si loopMIDI
    /// arrive après ; un essai RATÉ n'est refait qu'après 60 s.
    public static bool EnsureIfNeeded()
    {
        if (MidiLink.PortsExist()) return true;
        lock (Gate)
        {
            if (MidiLink.PortsExist()) return true;
            // loopMIDI installé depuis l'essai raté : on réessaie tout de suite.
            var driverArrived = VirtualMidiPorts.DriverInstalled && !_failedWithDriver;
            if (DateTime.UtcNow - _lastFailure < TimeSpan.FromSeconds(60) && !driverArrived) return false;
            var ok = false;
#if MIDI_SERVICES
            if (_available != false)
            {
                try
                {
                    ok = CreateLink();
                }
                catch (Exception e)
                {
                    // Classe absente de ce Windows (pas encore 25H2 à jour), service arrêté… : le pilote de loopMIDI.
                    AppLog.Write("MIDI", "Windows MIDI Services indisponible (" + e.GetType().Name + ")");
                    _available = false;
                }
            }
#endif
            // Sinon, le pilote installé avec loopMIDI (08/11) : l'appli crée elle-même les deux ports, rien à faire
            // dans loopMIDI.
            if (!ok && VirtualMidiPorts.Create(MidiLink.ToFlPortName))
            {
                for (var i = 0; i < 15 && !MidiLink.PortsExist(); i++) Thread.Sleep(200);
                ok = MidiLink.PortsExist();
                if (!ok)
                {
                    AppLog.Write("MIDI", "ports du pilote de loopMIDI pas visibles");
                    VirtualMidiPorts.CloseAll();
                }
            }
            if (!ok)
            {
                _lastFailure = DateTime.UtcNow;
                _failedWithDriver = VirtualMidiPorts.DriverInstalled;
            }
            else if (CreatedByWindows) _createdAt ??= DateTime.UtcNow;
            return ok;
        }
    }

    /// À la sortie de l'appli seulement : retire les ports créés pendant ce lancement (FL les voit partir).
    public static void RemoveCreated()
    {
        lock (Gate)
        {
#if MIDI_SERVICES
            foreach (var id in Created)
            {
                try
                {
                    var r = MidiBasicLoopbackManager.RemoveTransientLoopback(new MidiBasicLoopbackRemovalConfig(id));
                    AppLog.Write("MIDI", r.Success ? "port Windows retiré" : $"port Windows non retiré ({r.ErrorCode})");
                }
                catch (Exception e)
                {
                    AppLog.Write("MIDI", "port Windows non retiré (" + e.GetType().Name + ")");
                }
            }
#endif
            Created.Clear();
            VirtualMidiPorts.CloseAll();
            _createdAt = null;
        }
    }

#if MIDI_SERVICES
    private static bool CreateLink()
    {
        if (!MidiApi.EnsureServiceAvailable())
        {
            AppLog.Write("MIDI", "service MIDI de Windows absent");
            return false;
        }
        if (!MidiBasicLoopbackManager.IsTransportAvailable)
        {
            AppLog.Write("MIDI", "ports boucle de Windows absents");
            return false;
        }
        Create(MidiLink.ToFlPortName, ToFlId);
        // WinMM voit les nouveaux ports un instant plus tard.
        for (var i = 0; i < 15 && !MidiLink.PortsExist(); i++) Thread.Sleep(200);
        var ok = MidiLink.PortsExist();
        AppLog.Write("MIDI", ok ? "ports créés par Windows" : "ports Windows pas encore visibles");
        return ok;
    }

    private static void Create(string name, string uniqueId)
    {
        var definition = new MidiBasicLoopbackEndpointDefinition
        {
            Name = name,
            Description = "FL Shortcuts ↔ FL Studio",
            UniqueId = uniqueId,
        };
        var response = MidiBasicLoopbackManager.CreateTransientLoopback(new MidiBasicLoopbackCreationConfig(definition));
        if (response.Success)
            Created.Add(response.CreatedLoopbackEntry.AssociationId);
        else
            // Déjà là (lancement d'avant arrêté net) : le port existe toujours, rien à faire.
            AppLog.Write("MIDI", $"port {uniqueId} refusé par Windows ({response.ErrorCode})");
    }
#endif
}
