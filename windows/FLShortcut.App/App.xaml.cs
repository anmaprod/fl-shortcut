// Audit : REL-07 (instance unique vérifiée avant toute création de hook, de port ou de profil),
//         WIN-06/07 (DLL jamais chargées depuis le dossier courant : SetDllDirectory("")). Pas de
//         SetDefaultDllDirectories : le Windows App SDK charge ses classes avec LOAD_WITH_ALTERED_SEARCH_PATH, refusé
//         après lui (E_INVALIDARG) : la toute première fenêtre faisait tomber l'appli (débogueur de la CI, 26/10).
using System.Runtime.InteropServices;
using Microsoft.UI.Xaml;

namespace FLShortcut.App;

public partial class App : Application
{
    private static Mutex? _single;
    private MainWindow? _window;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetDllDirectory(string lpPathName);

    public App()
    {
        SetDllDirectory("");                        // retire le dossier courant de la recherche des DLL
        Photos.Note("appli : démarrage");
        UnhandledException += (_, e) => Photos.Note("exception : " + e.Exception);
        InitializeComponent();
        Photos.Note("appli : ressources chargées");
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        // Mode photos de la CI : les écrans de l'Organiser avec des sons d'exemple, en PNG, puis l'appli se ferme.
        // Rien n'est envoyé à FL ; ni hook clavier, ni port MIDI.
        if (Photos.Folder is { } folder)
        {
            var ui = Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread();
            Photos.Take(folder, () => new AppController(ui));
            return;
        }
        _single = new Mutex(initiallyOwned: true, @"Local\FLShortcut.SingleInstance", out var created);
        if (!created)
        {
            // Une autre instance tourne déjà : on ne crée ni hook ni port en double.
            Exit();
            return;
        }
        Services.AppLogFile.Install();              // journal des macros et de l'Organiser (mots fixes et nombres)
        _window = new MainWindow();
        var startHidden = Environment.GetCommandLineArgs().Any(a => string.Equals(a, "--tray", StringComparison.OrdinalIgnoreCase));
        if (!startHidden) _window.Activate();
    }
}
