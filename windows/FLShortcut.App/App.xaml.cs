// Audit : REL-07 (instance unique vérifiée avant toute création de hook, de port ou de profil).
using Microsoft.UI.Xaml;

namespace FLShortcut.App;

public partial class App : Application
{
    private static Mutex? _single;
    private MainWindow? _window;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
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
