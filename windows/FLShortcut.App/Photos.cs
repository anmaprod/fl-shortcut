// Mode photos de la CI (`--photos <dossier>`) : chaque écran de l'Organiser, avec des sons d'exemple
// (OrganizerController.ShowDemo), enregistré en PNG, puis l'appli se ferme. Rien n'est envoyé à FL, aucun hook ni port
// MIDI n'est ouvert ; seuls des fichiers « organiser-<écran>.png » sont écrits, dans un dossier qui existe déjà.
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace FLShortcut.App;

internal static class Photos
{
    private static readonly string[] Screens = { "installer", "attente", "aide", "ecoute", "apercu", "fini" };

    /// `app` est créé ici (son échec est noté comme le reste) ; le journal « photos-journal.txt » dit chaque étape.
    public static async void Take(string folder, Func<AppController> app)
    {
        var journal = new List<string>();
        void Note(string line) => journal.Add($"{DateTime.UtcNow:HH:mm:ss.fff} {line}");
        try
        {
            if (!Directory.Exists(folder)) return;
            Note("début");
            // Une fenêtre fermée avant l'ouverture de la suivante ne doit pas arrêter l'appli.
            Application.Current.DispatcherShutdownMode = DispatcherShutdownMode.OnExplicitShutdown;
            Application.Current.UnhandledException += (_, e) =>
            {
                Note("exception : " + e.Exception);
                try { File.WriteAllLines(Path.Combine(folder, "photos-journal.txt"), journal); } catch (IOException) { }
            };
            var controller = app();
            Note("appli prête");
            foreach (var screen in Screens)
            {
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
        }
        catch (Exception e)
        {
            Note("échec : " + e);
        }
        finally
        {
            try { if (Directory.Exists(folder)) File.WriteAllLines(Path.Combine(folder, "photos-journal.txt"), journal); }
            catch (IOException) { }
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
