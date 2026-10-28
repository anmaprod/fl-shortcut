// Ce que les macros lisent de FL au moment d'un clic (règle du propriétaire : jamais l'écran, sauf pour retrouver un
// bouton à son nom dans la seule fenêtre de FL, au moment du clic). D'abord sans l'écran : un menu standard de Windows
// donne ses titres, leur place et leur état grisé. Sinon (menu dessiné par FL, bouton) : l'image de la seule fenêtre
// de FL visée, lue sur place par la reconnaissance de texte de Windows, jamais enregistrée ni envoyée, et les textes
// jamais journalisés (seulement leur nombre).
using System.Runtime.InteropServices;
using System.Text;
using FLShortcut.App.Native;
using FLShortcut.Core;
using FLShortcut.Core.Macros;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Security.Cryptography;

namespace FLShortcut.App.Services;

internal static class FlScreen
{
    /// Haut de la fenêtre principale de FL où sont ses titres (FILE, EDIT, ADD…), en points à 96 ppp.
    private const int BarWidth = 1100, BarHeight = 90;

    private static readonly Lazy<OcrEngine?> Engine = new(() =>
    {
        try
        {
            // FL écrit ses menus en anglais ; sinon une langue du profil (même alphabet).
            return OcrEngine.TryCreateFromLanguage(new Windows.Globalization.Language("en-US"))
                   ?? OcrEngine.TryCreateFromUserProfileLanguages();
        }
        catch (Exception e)
        {
            AppLog.Write("MACRO", "OCR unavailable " + e.GetType().Name);
            return null;
        }
    });

    /// Titres en haut de la fenêtre principale de FL : sa barre de menus Windows si elle en a une, sinon lus dans
    /// l'image du haut de cette fenêtre.
    public static IReadOnlyList<TextItem>? MenuBar(IntPtr main)
    {
        if (main == IntPtr.Zero) return null;
        var menu = Win32.GetMenu(main);
        if (menu != IntPtr.Zero && StandardItems(menu, main) is { Count: > 0 } standard)
        {
            AppLog.Write("MACRO", $"READ menu bar: {standard.Count} standard item(s)");
            return standard;
        }
        if (!Win32.GetWindowRect(main, out var r)) return null;
        var scale = Math.Max(1.0, Win32.GetDpiForWindow(main) / 96.0);
        var width = Math.Min(r.Right - r.Left, (int)(BarWidth * scale));
        var height = Math.Min(r.Bottom - r.Top, (int)(BarHeight * scale));
        var read = Read(r.Left, r.Top, width, height);
        AppLog.Write("MACRO", $"READ menu bar: {(read is null ? "unreadable" : $"{read.Count} text(s) read")}");
        return read;
    }

    /// Éléments d'un menu ouvert de FL : menu standard de Windows (#32768) lu par Windows, sinon lu dans son image.
    public static IReadOnlyList<TextItem>? MenuItems(IntPtr window)
    {
        if (ClassOf(window) == "#32768"
            && Win32.SendMessageTimeoutW(window, Win32.MN_GETHMENU, UIntPtr.Zero, IntPtr.Zero, Win32.SMTO_ABORTIFHUNG, 300,
                out var result) != IntPtr.Zero
            && result != UIntPtr.Zero
            && StandardItems((IntPtr)(long)result.ToUInt64(), IntPtr.Zero) is { Count: > 0 } standard)
        {
            AppLog.Write("MACRO", $"READ menu: {standard.Count} standard item(s)");
            return standard;
        }
        var read = ReadWindow(window);
        AppLog.Write("MACRO", $"READ menu: {(read is null ? "unreadable" : $"{read.Count} text(s) read")}");
        return read;
    }

    /// Textes de toute une fenêtre de FL (bouton retrouvé à son nom).
    public static IReadOnlyList<TextItem>? ReadWindow(IntPtr window)
    {
        if (!Win32.GetWindowRect(window, out var r)) return null;
        return Read(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top);
    }

    private static string ClassOf(IntPtr hwnd)
    {
        var name = new StringBuilder(64);
        Win32.GetClassNameW(hwnd, name, name.Capacity);
        return name.ToString();
    }

    /// Éléments d'un menu standard : texte (« &File\tCtrl+F »), cadre à l'écran, grisé. Séparateurs à part. Vide si
    /// FL dessine lui-même ses éléments sans leur donner de texte (alors : l'image).
    private static List<TextItem> StandardItems(IntPtr menu, IntPtr owner)
    {
        var output = new List<TextItem>();
        var count = Win32.GetMenuItemCount(menu);
        if (count <= 0 || count > 400) return output;
        var text = new StringBuilder(256);
        var named = 0;
        for (var i = 0u; i < count; i++)
        {
            var state = Win32.GetMenuState(menu, i, Win32.MF_BYPOSITION);
            if (state == 0xFFFFFFFF || (state & Win32.MF_SEPARATOR) != 0) continue;
            text.Clear();
            Win32.GetMenuStringW(menu, i, text, text.Capacity, Win32.MF_BYPOSITION);
            if (!Win32.GetMenuItemRect(owner, menu, i, out var r) || r.Right <= r.Left || r.Bottom <= r.Top) continue;
            if (text.Length > 0) named++;
            output.Add(new TextItem(text.ToString(), r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top,
                (state & (Win32.MF_GRAYED | Win32.MF_DISABLED)) != 0));
        }
        return named > 0 ? output : new List<TextItem>();
    }

    /// Textes d'une zone de l'écran (pixels), lignes et mots, en pixels de l'écran. L'image n'est jamais gardée.
    private static List<TextItem>? Read(int x, int y, int width, int height)
    {
        if (Engine.Value is not { } engine || width < 8 || height < 8 || width > 16_000 || height > 16_000) return null;
        if (Capture(x, y, width, height) is not { } pixels) return null;
        // Petits textes de FL : agrandis deux fois si l'image le permet (la reconnaissance a une taille maximale).
        var max = (double)OcrEngine.MaxImageDimension;
        var scale = Math.Min(2.0, Math.Min(max / width, max / height));
        var (w2, h2, scaled) = Resize(pixels, width, height, scale);
        try
        {
            using var bitmap = SoftwareBitmap.CreateCopyFromBuffer(CryptographicBuffer.CreateFromByteArray(scaled),
                BitmapPixelFormat.Bgra8, w2, h2, BitmapAlphaMode.Premultiplied);
            var task = engine.RecognizeAsync(bitmap).AsTask();
            if (!task.Wait(TimeSpan.FromSeconds(3))) return null;
            var output = new List<TextItem>();
            var sx = (double)w2 / width;
            var sy = (double)h2 / height;
            TextItem Box(string text, double left, double top, double right, double bottom) => new(text,
                x + (int)Math.Round(left / sx), y + (int)Math.Round(top / sy),
                Math.Max(1, (int)Math.Round((right - left) / sx)), Math.Max(1, (int)Math.Round((bottom - top) / sy)));
            foreach (var line in task.Result.Lines)
            {
                var words = line.Words.ToList();
                if (words.Count == 0) continue;
                output.Add(Box(line.Text, words.Min(w => w.BoundingRect.Left), words.Min(w => w.BoundingRect.Top),
                    words.Max(w => w.BoundingRect.Right), words.Max(w => w.BoundingRect.Bottom)));
                if (words.Count < 2) continue;
                foreach (var w in words)
                    output.Add(Box(w.Text, w.BoundingRect.Left, w.BoundingRect.Top, w.BoundingRect.Right, w.BoundingRect.Bottom));
            }
            return output;
        }
        catch (Exception e)
        {
            AppLog.Write("MACRO", "OCR failed " + e.GetType().Name);
            return null;
        }
    }

    /// Pixels BGRA (de haut en bas) de la zone, tels qu'affichés maintenant.
    private static byte[]? Capture(int x, int y, int width, int height)
    {
        var screen = Win32.GetDC(IntPtr.Zero);
        if (screen == IntPtr.Zero) return null;
        var memory = Win32.CreateCompatibleDC(screen);
        var bitmap = Win32.CreateCompatibleBitmap(screen, width, height);
        try
        {
            if (memory == IntPtr.Zero || bitmap == IntPtr.Zero) return null;
            var old = Win32.SelectObject(memory, bitmap);
            var copied = Win32.BitBlt(memory, 0, 0, width, height, screen, x, y, Win32.SRCCOPY | Win32.CAPTUREBLT);
            Win32.SelectObject(memory, old);
            if (!copied) return null;
            var header = new Win32.BITMAPINFOHEADER
            {
                biSize = (uint)Marshal.SizeOf<Win32.BITMAPINFOHEADER>(),
                biWidth = width,
                biHeight = -height,                          // de haut en bas
                biPlanes = 1,
                biBitCount = 32,
            };
            var pixels = new byte[width * height * 4];
            if (Win32.GetDIBits(memory, bitmap, 0, (uint)height, pixels, ref header, Win32.DIB_RGB_COLORS) != height) return null;
            for (var i = 3; i < pixels.Length; i += 4) pixels[i] = 255;    // opaque
            return pixels;
        }
        finally
        {
            if (bitmap != IntPtr.Zero) Win32.DeleteObject(bitmap);
            if (memory != IntPtr.Zero) Win32.DeleteDC(memory);
            Win32.ReleaseDC(IntPtr.Zero, screen);
        }
    }

    /// Image mise à l'échelle (moyenne des voisins : texte net agrandi, lisible réduit).
    private static (int Width, int Height, byte[] Pixels) Resize(byte[] source, int width, int height, double scale)
    {
        if (Math.Abs(scale - 1) < 0.01) return (width, height, source);
        var w2 = Math.Max(1, (int)(width * scale));
        var h2 = Math.Max(1, (int)(height * scale));
        var output = new byte[w2 * h2 * 4];
        for (var y = 0; y < h2; y++)
        {
            var fy = Math.Min(height - 1.0, (y + 0.5) / scale - 0.5);
            var y0 = Math.Max(0, (int)fy);
            var y1 = Math.Min(height - 1, y0 + 1);
            var ty = Math.Max(0, fy - y0);
            for (var x = 0; x < w2; x++)
            {
                var fx = Math.Min(width - 1.0, (x + 0.5) / scale - 0.5);
                var x0 = Math.Max(0, (int)fx);
                var x1 = Math.Min(width - 1, x0 + 1);
                var tx = Math.Max(0, fx - x0);
                for (var c = 0; c < 4; c++)
                {
                    double P(int px, int py) => source[(py * width + px) * 4 + c];
                    var top = P(x0, y0) * (1 - tx) + P(x1, y0) * tx;
                    var bottom = P(x0, y1) * (1 - tx) + P(x1, y1) * tx;
                    output[(y * w2 + x) * 4 + c] = (byte)Math.Round(top * (1 - ty) + bottom * ty);
                }
            }
        }
        return (w2, h2, output);
    }
}
