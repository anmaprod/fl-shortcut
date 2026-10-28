// La boîte « Ouvrir » de Windows (IFileOpenDialog), sans attendre : l'Organiser demande un fichier ou un dossier au
// moment du clic et continue avec la réponse (« Choisir le fichier… », « Autre dossier de FL… »).
using System.Runtime.InteropServices;

namespace FLShortcut.App.Native;

internal static class FileDialogs
{
    private const uint FOS_PICKFOLDERS = 0x20, FOS_FORCEFILESYSTEM = 0x40, FOS_PATHMUSTEXIST = 0x800, FOS_FILEMUSTEXIST = 0x1000;
    private const uint SIGDN_FILESYSPATH = 0x80058000;

    /// Un fichier `extension` (« flp ») ; null : annulé.
    public static string? PickFile(IntPtr owner, string title, string typeName, string extension, string? start = null) =>
        Pick(owner, title, FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST | FOS_FILEMUSTEXIST, (typeName, "*." + extension), start);

    /// Un dossier ; null : annulé.
    public static string? PickFolder(IntPtr owner, string title, string? start = null) =>
        Pick(owner, title, FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST, null, start);

    private static string? Pick(IntPtr owner, string title, uint options, (string Name, string Spec)? filter, string? start = null)
    {
        var dialog = (IFileDialog)new FileOpenDialogCom();
        var specs = IntPtr.Zero;
        try
        {
            dialog.GetOptions(out var current);
            dialog.SetOptions(current | options);
            dialog.SetTitle(title);
            if (filter is { } f)
            {
                specs = Marshal.AllocHGlobal(IntPtr.Size * 2);
                Marshal.WriteIntPtr(specs, 0, Marshal.StringToHGlobalUni(f.Name));
                Marshal.WriteIntPtr(specs, IntPtr.Size, Marshal.StringToHGlobalUni(f.Spec));
                dialog.SetFileTypes(1, specs);
            }
            if (start is not null && Directory.Exists(start)
                && SHCreateItemFromParsingName(start, IntPtr.Zero, typeof(IShellItem).GUID, out var folder) == 0)
                dialog.SetFolder(folder);
            if (dialog.Show(owner) != 0) return null;              // annulé (ERROR_CANCELLED) ou refusé
            dialog.GetResult(out var item);
            item.GetDisplayName(SIGDN_FILESYSPATH, out var path);
            return path;
        }
        catch (COMException)
        {
            return null;
        }
        finally
        {
            if (specs != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(Marshal.ReadIntPtr(specs, 0));
                Marshal.FreeHGlobal(Marshal.ReadIntPtr(specs, IntPtr.Size));
                Marshal.FreeHGlobal(specs);
            }
            Marshal.ReleaseComObject(dialog);
        }
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
    private static extern int SHCreateItemFromParsingName(string path, IntPtr bindContext, [MarshalAs(UnmanagedType.LPStruct)] Guid riid,
        out IShellItem item);

    [ComImport, Guid("DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7")]
    private class FileOpenDialogCom { }

    /// IModalWindow puis IFileDialog, dans l'ordre de shobjidl.h (jusqu'à GetResult).
    [ComImport, Guid("42f85136-db7e-439c-85f1-e4075d135fc8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IFileDialog
    {
        [PreserveSig] int Show(IntPtr parent);
        void SetFileTypes(uint count, IntPtr filterSpecs);
        void SetFileTypeIndex(uint index);
        void GetFileTypeIndex(out uint index);
        void Advise(IntPtr events, out uint cookie);
        void Unadvise(uint cookie);
        void SetOptions(uint options);
        void GetOptions(out uint options);
        void SetDefaultFolder(IShellItem folder);
        void SetFolder(IShellItem folder);
        void GetFolder(out IShellItem folder);
        void GetCurrentSelection(out IShellItem item);
        void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string name);
        void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string name);
        void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string title);
        void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string text);
        void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string label);
        void GetResult(out IShellItem item);
    }

    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem
    {
        void BindToHandler(IntPtr bindContext, ref Guid handler, ref Guid riid, out IntPtr result);
        void GetParent(out IShellItem parent);
        void GetDisplayName(uint sigdn, [MarshalAs(UnmanagedType.LPWStr)] out string name);
        void GetAttributes(uint mask, out uint attributes);
        void Compare(IShellItem other, uint hint, out int order);
    }
}
