// Organiser : le son de FL, écouté pendant que l'Organiser fait jouer un son seul (jamais écrit sur le disque, les
// 4 dernières secondes seulement, en mémoire). Miroir de Sources/FLShortcut/FLAudioTap.swift.
//
// Windows 11 (et Windows 10 build 20348 ou plus) : la capture du seul processus de FL (« process loopback » de
// WASAPI, ActivateAudioInterfaceAsync sur « VAD\Process_Loopback ») : les autres applis (navigateur…) ne s'entendent
// pas. Plus ancien : le son de tout le PC (bouclage de la sortie par défaut). FL réglé sur un pilote ASIO de carte son
// passe à côté de Windows : rien n'est reçu (l'Organiser le dit, `NoSound`).
using System.Runtime.InteropServices;
using FLShortcut.Core;
using FLShortcut.Core.Organizer;

namespace FLShortcut.App.Services;

internal sealed class FlAudioCapture : IAudioSource, IDisposable
{
    private const int Seconds = 4;
    private readonly uint _pid;
    private CaptureBuffer? _buffer;
    private Wasapi.IAudioClient? _client;
    private Wasapi.IAudioCaptureClient? _capture;
    private Thread? _thread;
    private AutoResetEvent? _ready;
    private volatile bool _running;
    private string _mode = "aucun";
    private int _channels;
    private int _packets;
    private int _silent;

    public FlAudioCapture(uint pid) => _pid = pid;

    public double Rate { get; private set; } = 48_000;

    public string Stats
    {
        get
        {
            var (chunks, peak) = _buffer?.Received ?? (0, 0f);
            var db = 20 * Math.Log10(Math.Max(peak, 1e-9));
            return $"mode={_mode} taux={Rate:0} canaux={_channels} paquets={_packets} muets={_silent} blocs={chunks} crête={db:0}dB";
        }
    }

    public void Start()
    {
        if (_running) return;
        try
        {
            (_client, _mode) = ProcessClient() is { } own ? (own, "processus") : (SystemClient(), "système");
        }
        catch (COMException e)
        {
            throw OrganizerError.Failed(Loc.F("Impossible d'écouter le son de FL (erreur %@).", $"0x{e.HResult:X8}"));
        }
        _capture = Service<Wasapi.IAudioCaptureClient>(_client, Wasapi.IID_IAudioCaptureClient);
        _buffer = new CaptureBuffer(Rate, Seconds);
        _ready = new AutoResetEvent(false);
        _client.SetEventHandle(_ready.SafeWaitHandle.DangerousGetHandle());
        _client.Start();
        _running = true;
        _thread = new Thread(Pump) { IsBackground = true, Name = "Écoute de FL" };
        _thread.Start();
    }

    public void Reset() => _buffer?.Reset();

    public float[] Take() => _buffer?.Take() ?? Array.Empty<float>();

    public void Stop()
    {
        if (!_running) return;
        _running = false;
        _ready?.Set();
        _thread?.Join(TimeSpan.FromSeconds(1));
        try { _client?.Stop(); } catch (COMException) { }
        if (_capture is not null) Marshal.ReleaseComObject(_capture);
        if (_client is not null) Marshal.ReleaseComObject(_client);
        _capture = null;
        _client = null;
        _ready?.Dispose();
        _ready = null;
    }

    public void Dispose() => Stop();

    // ---------- Le flux ----------

    private void Pump()
    {
        while (_running)
        {
            _ready?.WaitOne(100);
            if (!_running || _capture is null) break;
            try
            {
                Drain();
            }
            catch (COMException)
            {
                break;                              // appareil retiré, FL fermé : plus rien ne vient
            }
        }
    }

    private void Drain()
    {
        var capture = _capture!;
        capture.GetNextPacketSize(out var next);
        while (next > 0)
        {
            capture.GetBuffer(out var data, out var frames, out var flags, out _, out _);
            _packets++;
            var count = (int)frames * _channels;
            var samples = new float[count];
            if ((flags & Wasapi.AUDCLNT_BUFFERFLAGS_SILENT) != 0 || data == IntPtr.Zero) _silent++;
            else Marshal.Copy(data, samples, 0, count);
            capture.ReleaseBuffer(frames);
            _buffer?.AppendInterleaved(samples, (int)frames, _channels);
            capture.GetNextPacketSize(out next);
        }
    }

    // ---------- Les deux façons d'écouter ----------

    /// Le seul processus de FL (et ses enfants : le pont des plugins 32 bits). null : Windows trop ancien.
    private Wasapi.IAudioClient? ProcessClient()
    {
        if (!OperatingSystem.IsWindowsVersionAtLeast(10, 0, 20348)) return null;
        var parameters = new Wasapi.AudioClientActivationParams
        {
            ActivationType = Wasapi.AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK,
            TargetProcessId = _pid,
            ProcessLoopbackMode = Wasapi.PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE,
        };
        var size = Marshal.SizeOf<Wasapi.AudioClientActivationParams>();
        var blob = Marshal.AllocHGlobal(size);
        var variant = Marshal.AllocHGlobal(Marshal.SizeOf<Wasapi.PropVariantBlob>());
        try
        {
            Marshal.StructureToPtr(parameters, blob, false);
            Marshal.StructureToPtr(new Wasapi.PropVariantBlob { vt = Wasapi.VT_BLOB, cbSize = (uint)size, pBlobData = blob }, variant, false);
            var handler = new Wasapi.ActivationHandler();
            Wasapi.ActivateAudioInterfaceAsync(Wasapi.VirtualProcessLoopback, Wasapi.IID_IAudioClient, variant, handler, out var operation);
            var done = handler.Done.Wait(TimeSpan.FromSeconds(5));
            GC.KeepAlive(operation);                    // vivante jusqu'à la réponse de Windows
            if (!done) return null;
            if (handler.Result < 0 || handler.Client is null) return null;
            var client = handler.Client;
            // Pas de format « mixé » pour ce flux : on demande le nôtre (flottants, 48 kHz, stéréo), converti par Windows.
            Rate = 48_000;
            _channels = 2;
            Initialize(client, Wasapi.WaveFormat.Float(48_000, 2));
            return client;
        }
        catch (COMException)
        {
            return null;
        }
        finally
        {
            Marshal.FreeHGlobal(variant);
            Marshal.FreeHGlobal(blob);
        }
    }

    /// Le son de tout le PC : la sortie par défaut, en bouclage, à son propre format.
    private Wasapi.IAudioClient SystemClient()
    {
        var enumerator = (Wasapi.IMMDeviceEnumerator)new Wasapi.MMDeviceEnumerator();
        try
        {
            enumerator.GetDefaultAudioEndpoint(Wasapi.ERender, Wasapi.EConsole, out var device);
            var iid = Wasapi.IID_IAudioClient;
            device.Activate(ref iid, Wasapi.CLSCTX_ALL, IntPtr.Zero, out var unknown);
            Marshal.ReleaseComObject(device);
            var client = (Wasapi.IAudioClient)unknown;
            client.GetMixFormat(out var mix);
            try
            {
                // Seuls les champs de WAVEFORMATEX (le format peut ne pas être « étendu »).
                _channels = Math.Max((int)(ushort)Marshal.ReadInt16(mix, 2), 1);
                Rate = (uint)Marshal.ReadInt32(mix, 4);
            }
            finally
            {
                Marshal.FreeCoTaskMem(mix);
            }
            // Le format mixé de Windows est en flottants ; converti au besoin, mêmes canaux et même fréquence.
            Initialize(client, Wasapi.WaveFormat.Float((int)Rate, _channels));
            return client;
        }
        finally
        {
            Marshal.ReleaseComObject(enumerator);
        }
    }

    private static void Initialize(Wasapi.IAudioClient client, Wasapi.WaveFormat format)
    {
        var pointer = Marshal.AllocHGlobal(Marshal.SizeOf<Wasapi.WaveFormat>());
        try
        {
            Marshal.StructureToPtr(format, pointer, false);
            var session = Guid.Empty;
            client.Initialize(Wasapi.AUDCLNT_SHAREMODE_SHARED,
                Wasapi.AUDCLNT_STREAMFLAGS_LOOPBACK | Wasapi.AUDCLNT_STREAMFLAGS_EVENTCALLBACK
                | Wasapi.AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | Wasapi.AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
                1_000_000, 0, pointer, ref session);
        }
        finally
        {
            Marshal.FreeHGlobal(pointer);
        }
    }

    private static T Service<T>(Wasapi.IAudioClient client, Guid iid)
    {
        client.GetService(ref iid, out var service);
        return (T)service;
    }
}

/// WASAPI : juste ce que la capture utilise (mmdeviceapi.h, audioclient.h, audioclientactivationparams.h).
internal static class Wasapi
{
    public const string VirtualProcessLoopback = @"VAD\Process_Loopback";
    public const int AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK = 1;
    public const int PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE = 0;
    public const ushort VT_BLOB = 65;
    public const int AUDCLNT_SHAREMODE_SHARED = 0;
    public const uint AUDCLNT_STREAMFLAGS_LOOPBACK = 0x00020000;
    public const uint AUDCLNT_STREAMFLAGS_EVENTCALLBACK = 0x00040000;
    public const uint AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY = 0x08000000;
    public const uint AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM = 0x80000000;
    public const uint AUDCLNT_BUFFERFLAGS_SILENT = 0x2;
    public const int ERender = 0, EConsole = 0;
    public const uint CLSCTX_ALL = 0x17;
    public static readonly Guid IID_IAudioClient = new("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2");
    public static readonly Guid IID_IAudioCaptureClient = new("C8ADBD64-E71E-48a0-A4DE-185C395CD317");

    [StructLayout(LayoutKind.Sequential)]
    public struct AudioClientActivationParams
    {
        public int ActivationType;
        public uint TargetProcessId;
        public int ProcessLoopbackMode;
    }

    /// PROPVARIANT de type VT_BLOB (24 octets en 64 bits).
    [StructLayout(LayoutKind.Sequential)]
    public struct PropVariantBlob
    {
        public ushort vt;
        public ushort r1, r2, r3;
        public uint cbSize;
        public IntPtr pBlobData;
    }

    /// WAVEFORMATEXTENSIBLE en flottants 32 bits.
    [StructLayout(LayoutKind.Sequential, Pack = 2)]
    public struct WaveFormat
    {
        public ushort wFormatTag;
        public ushort nChannels;
        public uint nSamplesPerSec;
        public uint nAvgBytesPerSec;
        public ushort nBlockAlign;
        public ushort wBitsPerSample;
        public ushort cbSize;
        public ushort wValidBitsPerSample;
        public uint dwChannelMask;
        public Guid SubFormat;

        private static readonly Guid IeeeFloat = new("00000003-0000-0010-8000-00aa00389b71");

        public static WaveFormat Float(int rate, int channels) => new()
        {
            wFormatTag = 0xFFFE,                // WAVE_FORMAT_EXTENSIBLE
            nChannels = (ushort)channels,
            nSamplesPerSec = (uint)rate,
            nAvgBytesPerSec = (uint)(rate * channels * 4),
            nBlockAlign = (ushort)(channels * 4),
            wBitsPerSample = 32,
            cbSize = 22,
            wValidBitsPerSample = 32,
            dwChannelMask = channels == 2 ? 0x3u : 0u,
            SubFormat = IeeeFloat,
        };
    }

    [DllImport("Mmdevapi.dll", ExactSpelling = true, PreserveSig = false)]
    public static extern void ActivateAudioInterfaceAsync([MarshalAs(UnmanagedType.LPWStr)] string deviceInterfacePath,
        [MarshalAs(UnmanagedType.LPStruct)] Guid riid, IntPtr activationParams,
        IActivateAudioInterfaceCompletionHandler completionHandler, out IActivateAudioInterfaceAsyncOperation operation);

    [ComImport, Guid("41D949AB-9862-444A-80F6-C261334DA5EB"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IActivateAudioInterfaceCompletionHandler
    {
        void ActivateCompleted(IActivateAudioInterfaceAsyncOperation operation);
    }

    [ComImport, Guid("72A22D78-CDE4-431D-B8CC-843A71199B6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IActivateAudioInterfaceAsyncOperation
    {
        void GetActivateResult(out int activateResult, [MarshalAs(UnmanagedType.IUnknown)] out object activatedInterface);
    }

    /// Windows appelle la fin de l'activation depuis un autre fil : l'objet doit être « agile ».
    [ComImport, Guid("94ea2b94-e9cc-49e0-c0ff-ee64ca8f5b90"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAgileObject { }

    [ComVisible(true)]
    public sealed class ActivationHandler : IActivateAudioInterfaceCompletionHandler, IAgileObject
    {
        public ManualResetEventSlim Done { get; } = new(false);
        public int Result { get; private set; } = -1;
        public IAudioClient? Client { get; private set; }

        public void ActivateCompleted(IActivateAudioInterfaceAsyncOperation operation)
        {
            try
            {
                operation.GetActivateResult(out var result, out var unknown);
                Result = result;
                if (result >= 0) Client = unknown as IAudioClient;
            }
            catch (COMException e)
            {
                Result = e.HResult;
            }
            finally
            {
                Done.Set();
            }
        }
    }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    public class MMDeviceEnumerator { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDeviceEnumerator
    {
        void EnumAudioEndpoints(int dataFlow, uint stateMask, out IntPtr devices);
        void GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IMMDevice
    {
        void Activate(ref Guid iid, uint clsCtx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object instance);
    }

    [ComImport, Guid("1CB9AD4C-DBFA-4c32-B178-C2F568A703B2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioClient
    {
        void Initialize(int shareMode, uint streamFlags, long bufferDuration, long periodicity, IntPtr format, ref Guid audioSessionGuid);
        void GetBufferSize(out uint frames);
        void GetStreamLatency(out long latency);
        void GetCurrentPadding(out uint padding);
        [PreserveSig] int IsFormatSupported(int shareMode, IntPtr format, out IntPtr closestMatch);
        void GetMixFormat(out IntPtr format);
        void GetDevicePeriod(out long defaultPeriod, out long minimumPeriod);
        void Start();
        void Stop();
        void Reset();
        void SetEventHandle(IntPtr eventHandle);
        void GetService(ref Guid iid, [MarshalAs(UnmanagedType.IUnknown)] out object service);
    }

    [ComImport, Guid("C8ADBD64-E71E-48a0-A4DE-185C395CD317"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    public interface IAudioCaptureClient
    {
        void GetBuffer(out IntPtr data, out uint frames, out uint flags, out ulong devicePosition, out ulong qpcPosition);
        void ReleaseBuffer(uint frames);
        void GetNextPacketSize(out uint frames);
    }
}
