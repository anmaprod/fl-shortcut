// Ports MIDI créés par Windows (08/11, « on peut bosser sur ça ? ») : sur Windows 11 25H2 à jour (Windows MIDI Services,
// arrivé avec la mise à jour de novembre 2026), l'appli crée elle-même les deux ports du lien, « FL Shortcuts » et
// « FL Shortcuts Retour », comme loopMIDI les créait : des ports « boucle » de MIDI 1.0 (Basic Loopback) que FL voit
// dans MIDI Settings. Rien d'autre à installer. MidiLink les ouvre par WinMM, comme ceux de loopMIDI.
//
// Ports « transitoires », créés seulement quand le lien sert (Organiser, bloc de macro : MidiLink.Use) et retirés dès
// qu'il ne sert plus (08/11, « FL rame ») ; l'appli les retire aussi en quittant. Si elle est tuée avant, ils restent
// jusqu'au redémarrage du service : la création suivante est refusée (même identifiant) mais les ports sont là.
//
// Windows plus ancien, service absent, loopMIDI déjà là : rien n'est créé, l'appli garde loopMIDI (écran « Télécharger
// loopMIDI » de l'Organiser). Jamais d'exception vers l'appelant. Journal : MIDI (mots fixes, codes d'erreur).
using FLShortcut.Core;
#if MIDI_SERVICES
using Windows.Devices.Midi2;
using Windows.Devices.Midi2.Transports.BasicLoopback;
#endif

namespace FLShortcut.App.Services;

internal static class MidiServicesPorts
{
    /// Identifiants des deux ports (uniques dans le service MIDI de Windows).
    public const string ToFlId = "flshortcuts-to-fl";
    public const string FromFlId = "flshortcuts-from-fl";

    private static readonly object Gate = new();
    private static readonly List<Guid> Created = new();
    private static DateTime _lastFailure = DateTime.MinValue;
    private static bool? _available;

    /// Windows sait créer les ports lui-même (25H2 à jour) : rien à installer, ils apparaissent quand le lien sert
    /// (08/11 : jamais en permanence, FL ramait). Faux tant que `CheckAvailable` n'a pas répondu.
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

    /// Les deux ports manquent : Windows les crée s'il sait le faire. Vrai si les ports sont là ensuite. Bloquant
    /// (jusqu'à ~3 s la première fois) : jamais sur le fil de l'interface. Un essai RATÉ n'est refait qu'après 60 s
    /// (créés puis retirés après une macro : recréés tout de suite à la suivante).
    public static bool EnsureIfNeeded()
    {
        if (MidiLink.PortsExist()) return true;
        lock (Gate)
        {
            if (MidiLink.PortsExist()) return true;
            if (DateTime.UtcNow - _lastFailure < TimeSpan.FromSeconds(60)) return false;
            var ok = false;
#if MIDI_SERVICES
            if (_available != false)
            {
                try
                {
                    ok = CreateBoth();
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
            if (!ok && VirtualMidiPorts.CreateBoth(MidiLink.ToFlPortName, MidiLink.FromFlPortName))
            {
                for (var i = 0; i < 15 && !MidiLink.PortsExist(); i++) Thread.Sleep(200);
                ok = MidiLink.PortsExist();
                if (!ok)
                {
                    AppLog.Write("MIDI", "ports du pilote de loopMIDI pas visibles");
                    VirtualMidiPorts.CloseAll();
                }
            }
            if (!ok) _lastFailure = DateTime.UtcNow;
            return ok;
        }
    }

    /// À la sortie de l'appli : retire les ports créés pendant ce lancement (FL les voit partir).
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
        }
    }

#if MIDI_SERVICES
    private static bool CreateBoth()
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
        Create(MidiLink.FromFlPortName, FromFlId);
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
