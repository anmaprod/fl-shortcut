// Mode photos de la CI (`--photos <dossier>`) : la fenêtre principale (plusieurs pages), chaque écran de l'Organiser avec des sons
// d'exemple (OrganizerController.ShowDemo), puis la page Macros avec des macros d'exemple en mémoire (liste et créateur),
// enregistrés en PNG, puis l'appli se ferme. Rien n'est envoyé à FL, aucun hook ni port MIDI n'est ouvert, aucune macro
// n'est écrite ; seuls des « principale*.png », des « organiser-<écran>.png » et des « macros-<écran>.png » sont écrits, dans
// un dossier qui existe déjà.
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace FLShortcut.App;

internal static class Photos
{
    private static readonly string[] Screens = { "installer", "attente", "aide", "ecoute", "apercu", "fini" };

    /// Le dossier des photos donné après `--photos` (qui existe déjà), ou null : pas en mode photos.
    public static string? Folder { get; } = FolderFromCommandLine();

    private static string? FolderFromCommandLine()
    {
        var command = Environment.GetCommandLineArgs();
        var at = Array.FindIndex(command, a => string.Equals(a, "--photos", StringComparison.OrdinalIgnoreCase));
        return at >= 0 && at + 1 < command.Length && Directory.Exists(command[at + 1]) ? command[at + 1] : null;
    }

    /// Une ligne du journal « photos-journal.txt », écrite tout de suite (l'appli peut tomber juste après).
    public static void Note(string line)
    {
        if (Folder is not { } folder) return;
        try { File.AppendAllText(Path.Combine(folder, "photos-journal.txt"), $"{DateTime.UtcNow:HH:mm:ss.fff} {line}{Environment.NewLine}"); }
        catch (IOException) { }
    }

    /// `app` est créé ici (son échec est noté comme le reste).
    public static async void Take(string folder, Func<AppController> app)
    {
        try
        {
            if (!Directory.Exists(folder)) return;
            Note("début");
            // Toute exception .NET, même rattrapée : la dernière avant une chute de WinUI dit souvent pourquoi.
            AppDomain.CurrentDomain.FirstChanceException += (_, e) =>
                Note($"exception vue : {e.Exception.GetType().Name} {e.Exception.HResult:X8} {e.Exception.Message}");
            // Une fenêtre fermée avant l'ouverture de la suivante ne doit pas arrêter l'appli.
            Application.Current.DispatcherShutdownMode = DispatcherShutdownMode.OnExplicitShutdown;
            var controller = app();
            Note("appli prête");
            // Une fenêtre toute simple d'abord : si elle tombe aussi, c'est WinUI sur cette machine, pas l'Organiser.
            Note("fenêtre simple : création");
            var probe = new Window { Title = "FL Shortcuts" };
            Note("fenêtre simple : créée");
            probe.Close();
            // La fenêtre principale (raccourcis), comme au premier lancement.
            Note("principale : création");
            var main = new MainWindow(photos: true);
            main.Activate();
            Note("principale : fenêtre ouverte");
            await Task.Delay(2000);
            // Les pages comme le Mac (29/10) : Général, Playlist, Mes raccourcis, une recherche.
            foreach (var (page, name) in new[] { ("general", "principale"), ("playlist", "principale-playlist"),
                                                 ("custom", "principale-mes-raccourcis"), ("recherche", "principale-recherche") })
            {
                main.ShowPage(page);
                await Task.Delay(800);
                if (main.Content is UIElement mainContent)
                {
                    await Save(mainContent, Path.Combine(folder, name + ".png"));
                    Note($"{name} : photo");
                }
            }
            main.Close();
            foreach (var screen in Screens)
            {
                Note($"{screen} : création");
                var window = OrganizerWindow.Demo(controller, screen);
                window.Activate();
                Note($"{screen} : fenêtre ouverte");
                await Task.Delay(1500);
                if (window.Content is UIElement content)
                {
                    await Save(content, Path.Combine(folder, $"organiser-{screen}.png"));
                    Note($"{screen} : photo");
                }
                window.Close();
            }
            foreach (var screen in new[] { "liste", "createur" })
            {
                Note($"macros {screen} : création");
                var window = MacrosWindow.Demo(controller, screen);
                window.Activate();
                await Task.Delay(1500);
                if (window.Content is UIElement content)
                {
                    await Save(content, Path.Combine(folder, $"macros-{screen}.png"));
                    Note($"macros {screen} : photo");
                }
                window.Close();
            }
        }
        catch (Exception e)
        {
            Note("échec : " + e);
        }
        finally
        {
            Note("fin");
            Application.Current.Exit();
        }
    }

    private static async Task Save(UIElement element, string path)
    {
        var bitmap = new RenderTargetBitmap();
        await bitmap.RenderAsync(element);
        var pixels = (await bitmap.GetPixelsAsync()).ToArray();
        using var stream = new InMemoryRandomAccessStream();
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
        encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied, (uint)bitmap.PixelWidth, (uint)bitmap.PixelHeight,
            96, 96, pixels);
        await encoder.FlushAsync();
        var bytes = new byte[stream.Size];
        stream.Seek(0);
        await stream.ReadAsync(bytes.AsBuffer(), (uint)bytes.Length, InputStreamOptions.None);
        await File.WriteAllBytesAsync(path, bytes);
    }
}
