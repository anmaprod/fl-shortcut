// « Installer loopMIDI » de l'accueil (16/11, choix « Installer avec l'appli ») : comme l'installeur de FL Shortcuts,
// loopMIDI est téléchargé sur le site de son auteur, reconnu à son empreinte (LoopMidiDownload), puis son installeur
// lancé (barre de progression seule ; Windows demande l'autorisation pour le pilote). Sans réseau, fichier changé ou
// refus : faux, l'accueil ouvre alors la page de téléchargement comme avant. Jamais d'exception vers l'appelant ;
// journal STATUS (mots fixes et nombres).
using System.Diagnostics;
using System.IO.Compression;
using FLShortcut.Core;

namespace FLShortcut.App.Services;

internal static class LoopMidiInstaller
{
    private static int _running;

    /// Une installation est en cours (le bouton de l'accueil attend).
    public static bool Running => Volatile.Read(ref _running) == 1;

    /// Télécharge et installe loopMIDI. Vrai si son pilote est là à la fin.
    public static async Task<bool> InstallAsync()
    {
        if (Interlocked.Exchange(ref _running, 1) == 1) return false;
        var folder = Path.Combine(Path.GetTempPath(), "FL Shortcuts loopMIDI " + Guid.NewGuid().ToString("N"));
        try
        {
            byte[] archive;
            using (var http = new HttpClient { Timeout = TimeSpan.FromMinutes(3) })
                archive = await http.GetByteArrayAsync(LoopMidiDownload.Url).ConfigureAwait(false);
            if (!LoopMidiDownload.IsGenuine(archive))
            {
                AppLog.Write("STATUS", $"loopMIDI : fichier différent ({archive.Length} octets), pas lancé");
                return false;
            }
            Directory.CreateDirectory(folder);
            var setup = Path.Combine(folder, LoopMidiDownload.SetupName);
            using (var zip = new ZipArchive(new MemoryStream(archive), ZipArchiveMode.Read))
            {
                var entry = zip.GetEntry(LoopMidiDownload.SetupName);
                if (entry is null)
                {
                    AppLog.Write("STATUS", "loopMIDI : installeur absent de l'archive");
                    return false;
                }
                entry.ExtractToFile(setup, overwrite: true);
            }
            using var process = Process.Start(new ProcessStartInfo(setup, LoopMidiDownload.SetupArguments)
            {
                UseShellExecute = true,
                WorkingDirectory = folder,
            });
            if (process is null) return false;
            await process.WaitForExitAsync().ConfigureAwait(false);
            AppLog.Write("STATUS", $"loopMIDI : installeur terminé, code {process.ExitCode}");
            return LoopMidiDownload.Succeeded(process.ExitCode) || VirtualMidiPorts.DriverInstalled;
        }
        catch (Exception e)
        {
            AppLog.Write("STATUS", "loopMIDI non installé (" + e.GetType().Name + ")");
            return false;
        }
        finally
        {
            try { if (Directory.Exists(folder)) Directory.Delete(folder, recursive: true); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            Volatile.Write(ref _running, 0);
        }
    }
}
