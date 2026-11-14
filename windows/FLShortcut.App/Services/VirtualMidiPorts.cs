// Ports du lien créés par l'appli elle-même avec le pilote de loopMIDI (08/11 : « tout ce qui est loopMIDI, ça ne
// fonctionne pas… il faut trouver une solution »). loopMIDI installe le pilote teVirtualMIDI (Tobias Erichsen) ;
// loopMIDI lui-même n'est qu'une petite fenêtre qui crée, avec ce pilote, des ports qui renvoient ce qu'ils reçoivent.
// L'appli fait la même chose : un seul port « FL Shortcuts » (09/11, MidiServicesPorts), créé au lancement de l'appli
// et gardé jusqu'à sa sortie (FL ne voit un port qu'à son ouverture), sans rien créer à la main ni garder loopMIDI
// ouvert. Il faut seulement avoir installé loopMIDI.
//
// Comme loopMIDI : un port teVirtualMIDI a deux côtés ; ce qu'un programme envoie au port arrive dans notre rappel,
// qui le renvoie aussitôt de l'autre côté (virtualMIDISendData) : FL le lit comme une entrée MIDI. MidiLink ouvre ces
// ports par WinMM, exactement comme ceux de loopMIDI. Jamais d'exception vers l'appelant ; journal MIDI (mots fixes).
using System.Runtime.InteropServices;
using FLShortcut.Core;

namespace FLShortcut.App.Services;

internal static class VirtualMidiPorts
{
    private const string Dll = "teVirtualMIDI64.dll";
    // TE_VM_FLAGS_PARSE_RX | TE_VM_FLAGS_PARSE_TX | TE_VM_FLAGS_INSTANTIATE_BOTH (réglages de loopMIDI).
    private const uint Flags = 1 | 2 | 12;
    private const uint MaxSysex = 65535;

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate void DataCallback(IntPtr port, IntPtr bytes, uint length, IntPtr instance);

    [DllImport(Dll, CharSet = CharSet.Unicode, EntryPoint = "virtualMIDICreatePortEx2", SetLastError = true)]
    private static extern IntPtr CreatePort(string name, DataCallback callback, IntPtr instance, uint maxSysex, uint flags);

    [DllImport(Dll, EntryPoint = "virtualMIDIClosePort")]
    private static extern void ClosePort(IntPtr port);

    [DllImport(Dll, EntryPoint = "virtualMIDISendData", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SendData(IntPtr port, IntPtr bytes, uint length);

    private sealed record Port(IntPtr Handle, DataCallback Callback);

    private static readonly object Gate = new();
    /// Ports ouverts et leurs rappels (gardés vivants : le pilote les appelle depuis son propre fil).
    private static readonly List<Port> Open = new();

    /// Le pilote de loopMIDI est installé (seulement pour une appli 64 bits x64 : il n'existe pas en ARM64).
    public static bool DriverInstalled
    {
        get
        {
            if (RuntimeInformation.ProcessArchitecture != Architecture.X64) return false;
            try { return File.Exists(Path.Combine(Environment.SystemDirectory, Dll)); }
            catch { return false; }
        }
    }

    public static bool Created
    {
        get { lock (Gate) return Open.Count > 0; }
    }

    /// Crée le port du lien (il renvoie ce qu'il reçoit). Vrai s'il est ouvert.
    public static bool Create(string name)
    {
        if (!DriverInstalled) return false;
        lock (Gate)
        {
            if (Open.Count == 1) return true;
            CloseUnlocked();
            try
            {
                DataCallback echo = Echo;
                var handle = CreatePort(name, echo, IntPtr.Zero, MaxSysex, Flags);
                if (handle == IntPtr.Zero)
                {
                    AppLog.Write("MIDI", $"port loopMIDI non créé ({Marshal.GetLastWin32Error()})");
                    return false;
                }
                Open.Add(new Port(handle, echo));
                AppLog.Write("MIDI", "port créé avec le pilote de loopMIDI");
                return true;
            }
            catch (Exception e)
            {
                AppLog.Write("MIDI", "pilote de loopMIDI inutilisable (" + e.GetType().Name + ")");
                CloseUnlocked();
                return false;
            }
        }
    }

    /// Ports retirés, à la sortie de l'appli seulement.
    public static void CloseAll()
    {
        lock (Gate) CloseUnlocked();
    }

    private static void CloseUnlocked()
    {
        foreach (var p in Open)
        {
            try { ClosePort(p.Handle); }
            catch (Exception e) { AppLog.Write("MIDI", "port loopMIDI non retiré (" + e.GetType().Name + ")"); }
        }
        if (Open.Count > 0) AppLog.Write("MIDI", "ports du pilote de loopMIDI retirés");
        Open.Clear();
    }

    /// Ce qui arrive sur un port repart aussitôt de l'autre côté (port « boucle », comme loopMIDI). Port fermé : rappel
    /// sans données, ignoré.
    private static void Echo(IntPtr port, IntPtr bytes, uint length, IntPtr instance)
    {
        if (port == IntPtr.Zero || bytes == IntPtr.Zero || length == 0) return;
        try { SendData(port, bytes, length); }
        catch { /* jamais d'exception dans le fil du pilote */ }
    }
}
