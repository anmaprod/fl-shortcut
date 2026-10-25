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

    public static async void Take(string folder, AppController app)
    {
        try
        {
            if (!Directory.Exists(folder)) return;
            foreach (var screen in Screens)
            {
                var window = OrganizerWindow.Demo(app, screen);
                window.Activate();
                await Task.Delay(1500);
                if (window.Content is UIElement content)
                    await Save(content, Path.Combine(folder, $"organiser-{screen}.png"));
                window.Close();
            }
        }
        catch (Exception e)
        {
            Console.Error.WriteLine("photos : " + e.GetType().Name + " " + e.Message);
        }
        finally
        {
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
