// Mises à jour toutes seules sur Windows (19/11, « que notre logiciel puisse être corrigé sans que les gens soient obligés
// de réinstaller l'appli »), comme AutoUpdate du Mac : au lancement puis toutes les 6 h, le manifeste signé de la
// dernière release (UpdateRules, cœur) ; une version plus récente est téléchargée, vérifiée (empreinte SHA-256), puis
// son installeur est lancé en silence quand FL Studio est fermé et que la fenêtre de l'appli est cachée ; l'installeur
// ferme l'appli et la relance (FLShortcut.iss, /UPDATE=1). Seules les versions publiées le font (métadonnée FLSUpdates
// = release, posée par la CI pour un tag) : une version d'essai ne se remplace jamais toute seule. Jamais d'exception.
using System.Diagnostics;
using System.Net.Http;
using System.Reflection;
using FLShortcut.Core;
using Microsoft.UI.Dispatching;

namespace FLShortcut.App.Services;

internal sealed class AutoUpdateWin
{
    private static readonly TimeSpan CheckEvery = TimeSpan.FromHours(6);
    private static readonly HttpClient Http = new(new HttpClientHandler { AllowAutoRedirect = true })
    {
        Timeout = TimeSpan.FromMinutes(15),
    };

    private readonly Func<bool> _flRunning;
    private readonly Func<bool> _windowOpen;
    private readonly Action _quit;
    private readonly DispatcherQueue _ui;
    private readonly DispatcherQueueTimer _timer;
    private (string Version, string Installer)? _ready;
    private bool _checking;
    private DateTime _lastCheck = DateTime.MinValue;
    private readonly DateTime _started = DateTime.UtcNow;

    public AutoUpdateWin(DispatcherQueue ui, Func<bool> flRunning, Func<bool> windowOpen, Action quit)
    {
        _flRunning = flRunning;
        _windowOpen = windowOpen;
        _quit = quit;
        _ui = ui;
        _timer = ui.CreateTimer();
        _timer.Interval = TimeSpan.FromMinutes(1);
        _timer.Tick += (_, _) => Tick();
    }

    /// Seulement une version publiée, lancée normalement (jamais les modes d'essai de la CI).
    public static bool Enabled =>
        typeof(AutoUpdateWin).Assembly.GetCustomAttributes<AssemblyMetadataAttribute>()
            .Any(m => m.Key == "FLSUpdates" && m.Value == "release")
        && !Environment.GetCommandLineArgs().Skip(1).Any(a => a.StartsWith("--", StringComparison.Ordinal) && a != "--tray");

    private static string Folder =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FL Shortcuts", "Mise à jour");

    public void Start()
    {
        if (!Enabled) return;
        try { if (Directory.Exists(Folder)) Directory.Delete(Folder, recursive: true); }   // restes d'une mise à jour posée
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        _timer.Start();
    }

    /// Chaque minute : poser la mise à jour prête si c'est le moment ; vérifier 1 min après le lancement puis toutes les 6 h.
    private void Tick()
    {
        if (_ready is { } ready) { InstallIfIdle(ready); return; }
        if (_checking || DateTime.UtcNow - _started < TimeSpan.FromMinutes(1) || DateTime.UtcNow - _lastCheck < CheckEvery) return;
        _checking = true;
        _lastCheck = DateTime.UtcNow;
        var current = HelpPage.AppVersion;
        _ = Task.Run(async () =>
        {
            var prepared = await Prepare(current).ConfigureAwait(false);
            _ui.TryEnqueue(() =>
            {
                _checking = false;
                if (prepared is { } p) { _ready = p; InstallIfIdle(p); }
            });
        });
    }

    private static async Task<byte[]?> Fetch(Uri uri, int max)
    {
        try
        {
            using var response = await Http.GetAsync(uri).ConfigureAwait(false);
            if (!response.IsSuccessStatusCode) return null;
            var data = await response.Content.ReadAsByteArrayAsync().ConfigureAwait(false);
            return data.Length <= max ? data : null;
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or IOException) { return null; }
    }

    /// Une version plus récente, signée, téléchargée et vérifiée ; null sinon (rien n'est touché).
    private static async Task<(string, string)?> Prepare(string current)
    {
        var data = await Fetch(UpdateRules.ManifestUri, 64_000).ConfigureAwait(false);
        var signature = data is null ? null : await Fetch(UpdateRules.SignatureUri, 4_000).ConfigureAwait(false);
        if (data is null || signature is null) return null;
        if (UpdateRules.Verified(data, signature) is not { } manifest)
        {
            AppLog.Write("UPDATE", "manifest refused (signature)");
            return null;
        }
        if (!UpdateRules.IsNewer(manifest.Version, current)) return null;
        if (manifest.Windows is not { } asset || UpdateRules.DownloadUri(asset.Url) is not { } uri)
        {
            AppLog.Write("UPDATE", manifest.Version + ": no Windows file");
            return null;
        }
        AppLog.Write("UPDATE", $"{current} → {manifest.Version}: downloading");
        var file = Path.Combine(Folder, "FLShortcuts-Windows-Setup-" + manifest.Version + ".exe");
        try
        {
            Directory.CreateDirectory(Folder);
            using (var response = await Http.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead).ConfigureAwait(false))
            {
                if (!response.IsSuccessStatusCode) { AppLog.Write("UPDATE", manifest.Version + ": download failed"); return null; }
                await using var output = File.Create(file);
                await response.Content.CopyToAsync(output).ConfigureAwait(false);
            }
            string sha;
            await using (var input = File.OpenRead(file)) sha = UpdateRules.Sha256Hex(input);
            if (sha != asset.Sha256.ToLowerInvariant())
            {
                AppLog.Write("UPDATE", manifest.Version + ": checksum mismatch");
                File.Delete(file);
                return null;
            }
            AppLog.Write("UPDATE", manifest.Version + ": ready");
            return (manifest.Version, file);
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or IOException or UnauthorizedAccessException)
        {
            AppLog.Write("UPDATE", manifest.Version + ": download failed (" + e.GetType().Name + ")");
            return null;
        }
    }

    /// Fil de l'interface : l'installeur en silence, puis l'appli se ferme (il la relance à la fin).
    private void InstallIfIdle((string Version, string Installer) ready)
    {
        if (!UpdateRules.CanInstall(_flRunning(), _windowOpen())) return;
        _ready = null;
        try
        {
            Process.Start(new ProcessStartInfo(ready.Installer, UpdateRules.InstallerArguments) { UseShellExecute = true });
        }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or InvalidOperationException or FileNotFoundException)
        {
            AppLog.Write("UPDATE", ready.Version + ": installer did not start (" + e.GetType().Name + ")");
            return;
        }
        AppLog.Write("UPDATE", $"{HelpPage.AppVersion} → {ready.Version}: installing, closing");
        _timer.Stop();
        _quit();
    }
}
