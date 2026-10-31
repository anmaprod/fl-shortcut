// Validation de la version organisée : les fichiers vont à la Corbeille de Windows (jamais supprimés pour de bon).
// Windows ne dit pas où il les range : une copie de secours est gardée le temps de la validation, pour remettre
// l'original à sa place si la version organisée ne peut pas prendre son nom (CopyApprovalRules.Validate).
using System.Runtime.InteropServices;
using FLShortcut.Core.Organizer;

namespace FLShortcut.App.Services;

internal static class RecycleBin
{
    private static string Spare => Path.Combine(AppPaths.Local, "validation");

    public static CopyFiles Files()
    {
        Clean();
        return new CopyFiles
        {
            Trash = Trash,
            Move = (from, to) => File.Move(from, to),
        };
    }

    /// Le fichier à la Corbeille ; renvoie sa copie de secours (pour le remettre), ou null.
    private static string? Trash(string path)
    {
        string? spare = null;
        try
        {
            Directory.CreateDirectory(Spare);
            spare = Path.Combine(Spare, $"{Guid.NewGuid():N}.flp");
            File.Copy(path, spare);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            spare = null;
        }
        var operation = new ShFileOperation
        {
            wFunc = FO_DELETE,
            pFrom = Path.GetFullPath(path) + "\0",          // liste terminée par deux zéros
            fFlags = FOF_ALLOWUNDO | FOF_NOCONFIRMATION | FOF_SILENT | FOF_NOERRORUI,
        };
        if (SHFileOperationW(ref operation) != 0 || operation.fAnyOperationsAborted || File.Exists(path))
        {
            if (spare is not null) try { File.Delete(spare); } catch (IOException) { }
            throw new IOException("Corbeille refusée");
        }
        return spare;
    }

    private const uint FO_DELETE = 3;
    private const ushort FOF_SILENT = 0x4, FOF_NOCONFIRMATION = 0x10, FOF_ALLOWUNDO = 0x40, FOF_NOERRORUI = 0x400;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct ShFileOperation
    {
        public IntPtr hwnd;
        public uint wFunc;
        public string pFrom;
        public string? pTo;
        public ushort fFlags;
        [MarshalAs(UnmanagedType.Bool)] public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        public string? lpszProgressTitle;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHFileOperationW(ref ShFileOperation operation);

    /// Les copies de secours de plus d'un jour : la validation est finie depuis longtemps.
    private static void Clean()
    {
        try
        {
            if (!Directory.Exists(Spare)) return;
            foreach (var file in Directory.EnumerateFiles(Spare, "*.flp"))
            {
                if (DateTime.UtcNow - File.GetLastWriteTimeUtc(file) > TimeSpan.FromDays(1)) File.Delete(file);
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }
}
