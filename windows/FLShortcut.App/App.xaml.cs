// Audit : REL-07 (instance unique vérifiée avant toute création de hook, de port ou de profil),
//         WIN-06/07 (DLL chargées seulement depuis le dossier de l'appli et System32 : ni dossier courant, ni PATH).
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;

namespace FLShortcut.App;

public partial class App : Application
{
    private static Mutex? _single;
    private MainWindow? _window;

    private const uint LOAD_LIBRARY_SEARCH_DEFAULT_DIRS = 0x00001000;

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetDefaultDllDirectories(uint directoryFlags);

    public App()
    {
        SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        // Mode photos de la CI : les écrans de l'Organiser avec des sons d'exemple, en PNG, puis l'appli se ferme.
        // Rien n'est envoyé à FL ; ni hook clavier, ni port MIDI.
        var command = Environment.GetCommandLineArgs();
        var photos = Array.FindIndex(command, a => string.Equals(a, "--photos", StringComparison.OrdinalIgnoreCase));
        if (photos >= 0 && photos + 1 < command.Length)
        {
            Photos.Take(command[photos + 1], new AppController(Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread()));
            return;
        }
        _single = new Mutex(initiallyOwned: true, @"Local\FLShortcut.SingleInstance", out var created);
        if (!created)
        {
            // Une autre instance tourne déjà : on ne crée ni hook ni port en double.
            Exit();
            return;
        }
        _window = new MainWindow();
        var startHidden = Environment.GetCommandLineArgs().Any(a => string.Equals(a, "--tray", StringComparison.OrdinalIgnoreCase));
        if (!startHidden) _window.Activate();
    }
}
