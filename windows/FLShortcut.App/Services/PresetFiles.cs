// Preset de piste pour les macros Windows (miroir de PresetDrop.swift et PresetChooser du Mac) :
//  - dépôt : glissé comme depuis l'Explorateur (objet de données du fichier donné par le shell, le même que
//    l'Explorateur ; glisser d'OLE sur son propre fil), pointeur amené sur la piste, bougé de quelques pixels pour que
//    FL voie le fichier entrer, puis lâché. Jamais d'appui sur le bouton de la souris (FL pourrait déplacer la piste) ;
//  - boîte « Open » de FL : le chemin écrit dans son champ du nom de fichier, puis Ouvrir.
// Seulement dans FL (vérifié par l'appelant), jamais le chemin au journal (seulement sa longueur).
using System.Runtime.InteropServices;
using System.Text;
using FLShortcut.App.Native;
using FLShortcut.Core;

namespace FLShortcut.App.Services;

internal static class PresetFiles
{
    private const int DRAGDROP_S_DROP = 0x00040100;
    private const uint DROPEFFECT_COPY = 1, DROPEFFECT_MOVE = 2, DROPEFFECT_LINK = 4;
    private static readonly Guid BhidDataObject = new("B8C0BD9F-ED24-455c-83E6-D5390C4FE8C4");
    private static readonly Guid IidDataObject = new("0000010e-0000-0000-C000-000000000046");
    /// Identifiants du champ du nom de fichier des boîtes « Open » de Windows (cmb13, puis edt1 des anciennes).
    private const int FileNameCombo = 1148, FileNameEdit = 1152, IdOk = 1;

    /// Fichier glissé en (x, y) : null si FL l'a pris, sinon la raison. `inFront` : FL toujours devant.
    public static string? Drop(string path, int x, int y, Func<bool> inFront)
    {
        var source = new DropSource();
        var outcome = (Hr: 0, Effect: 0u, Failed: false);
        var thread = new Thread(() =>
        {
            OleInitialize(IntPtr.Zero);
            var data = IntPtr.Zero;
            try
            {
                if (SHCreateItemFromParsingName(path, IntPtr.Zero, typeof(IShellItem).GUID, out var item) != 0)
                {
                    outcome.Failed = true;
                    return;
                }
                var handler = BhidDataObject;
                var iid = IidDataObject;
                item.BindToHandler(IntPtr.Zero, ref handler, ref iid, out data);
                Marshal.ReleaseComObject(item);
                outcome.Hr = DoDragDrop(data, source, DROPEFFECT_COPY | DROPEFFECT_MOVE | DROPEFFECT_LINK, out var effect);
                outcome.Effect = effect;
            }
            catch (Exception e)
            {
                AppLog.Write("MACRO", "DROP error " + e.GetType().Name);
                outcome.Failed = true;
            }
            finally
            {
                if (data != IntPtr.Zero) Marshal.Release(data);
                source.Ended.Set();
                OleUninitialize();
            }
        }) { IsBackground = true, Name = "FL Shortcuts – dépôt du preset" };
        thread.SetApartmentState(ApartmentState.STA);
        var t0 = Environment.TickCount64;
        Win32.SetCursorPos(x, y);
        thread.Start();

        string? Abandon(string why)
        {
            source.Cancel = true;
            Win32.SetCursorPos(x, y);                         // le glisser relit sa demande à chaque mouvement
            source.Ended.Wait(1_000);
            return why;
        }

        if (!source.Started.Wait(800))
        {
            AppLog.Write("MACRO", $"DROP not started · {Environment.TickCount64 - t0} ms");
            return Abandon(outcome.Failed ? Loc.T("preset illisible par Windows") : Loc.T("le glisser du preset n'a pas démarré (une fenêtre couvre la piste ?)"));
        }
        // Quelques pixels à droite puis retour : FL voit le fichier entrer sur la piste, puis le reçoit au point visé.
        foreach (var dx in new[] { 4, 8, 12, 8, 4, 0 })
        {
            if (!inFront()) return Abandon(Loc.T("FL n'est plus au premier plan"));
            Win32.SetCursorPos(x + dx, y);
            Thread.Sleep(16);
        }
        Thread.Sleep(30);
        source.Release = true;
        Win32.SetCursorPos(x, y);
        if (!source.Ended.Wait(2_000))
        {
            AppLog.Write("MACRO", $"DROP not ended · {Environment.TickCount64 - t0} ms");
            return Abandon(Loc.T("FL n'a pas répondu au dépôt du preset"));
        }
        AppLog.Write("MACRO", $"DROP ended · hr 0x{outcome.Hr:X} · effect {outcome.Effect} · {Environment.TickCount64 - t0} ms");
        return !outcome.Failed && outcome.Hr == DRAGDROP_S_DROP && outcome.Effect != 0
            ? null : Loc.T("FL n'a pas pris le preset : clique d'abord au milieu de la tranche de ta piste");
    }

    /// Chemin écrit dans la boîte « Open » (fenêtre de FL `pid`), puis Ouvrir : null si elle s'est refermée.
    public static string? Choose(IntPtr dialog, string path, uint pid)
    {
        Win32.GetWindowThreadProcessId(dialog, out var owner);
        if (owner != pid || !Win32.IsWindowVisible(dialog)) return Loc.T("boîte « Open » introuvable");
        if (FileNameField(dialog) is not { } field) return Loc.T("champ du nom de fichier introuvable dans la boîte « Open »");
        if (Win32.SendMessageTimeoutText(field, Win32.WM_SETTEXT, UIntPtr.Zero, path, Win32.SMTO_ABORTIFHUNG, 1_000, out _) == IntPtr.Zero)
            return Loc.T("la boîte « Open » n'a pas répondu");
        Thread.Sleep(30);
        Win32.PostMessageW(dialog, Win32.WM_COMMAND, new UIntPtr(IdOk), IntPtr.Zero);              // Ouvrir
        for (var i = 0; i < 60; i++)
        {
            Thread.Sleep(50);
            if (!Win32.IsWindow(dialog) || !Win32.IsWindowVisible(dialog)) return null;
        }
        return Loc.T("la boîte « Open » n'a pas pris le fichier");
    }

    /// Champ du nom de fichier : la liste déroulante cmb13 (son champ de texte), sinon le champ edt1 ; cherchés parmi
    /// tous les descendants (les boîtes récentes les rangent plus bas).
    private static IntPtr? FileNameField(IntPtr dialog)
    {
        IntPtr? found = null;
        var name = new StringBuilder(32);
        Win32.EnumChildWindows(dialog, (child, _) =>
        {
            var id = Win32.GetDlgCtrlID(child);
            if (id != FileNameCombo && id != FileNameEdit) return true;
            name.Clear();
            Win32.GetClassNameW(child, name, name.Capacity);
            if (name.ToString() == "Edit")
            {
                found = child;
                return false;
            }
            IntPtr? edit = null;
            Win32.EnumChildWindows(child, (inner, _) =>
            {
                name.Clear();
                Win32.GetClassNameW(inner, name, name.Capacity);
                if (name.ToString() != "Edit") return true;
                edit = inner;
                return false;
            }, IntPtr.Zero);
            if (edit is null) return true;
            found = edit;
            return false;
        }, IntPtr.Zero);
        return found;
    }

    [DllImport("ole32.dll")] private static extern int OleInitialize(IntPtr reserved);
    [DllImport("ole32.dll")] private static extern void OleUninitialize();
    [DllImport("ole32.dll")] private static extern int DoDragDrop(IntPtr dataObject, IDropSource source, uint okEffects, out uint effect);

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
    private static extern int SHCreateItemFromParsingName(string path, IntPtr bindContext, [MarshalAs(UnmanagedType.LPStruct)] Guid riid,
        out IShellItem item);

    [ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItem
    {
        void BindToHandler(IntPtr bindContext, ref Guid handler, ref Guid riid, out IntPtr result);
    }
}

[ComImport, Guid("00000121-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IDropSource
{
    [PreserveSig] int QueryContinueDrag([MarshalAs(UnmanagedType.Bool)] bool escapePressed, uint keyState);
    [PreserveSig] int GiveFeedback(uint effect);
}

/// Source du glisser : continue tant que la macro n'a pas lâché ; Échap ou l'abandon l'annulent.
[ComVisible(true)]
internal sealed class DropSource : IDropSource
{
    private const int S_OK = 0, DRAGDROP_S_DROP = 0x00040100, DRAGDROP_S_CANCEL = 0x00040101, DRAGDROP_S_USEDEFAULTCURSORS = 0x00040102;

    public readonly ManualResetEventSlim Started = new();
    public readonly ManualResetEventSlim Ended = new();
    public volatile bool Release;
    public volatile bool Cancel;

    public int QueryContinueDrag(bool escapePressed, uint keyState)
    {
        Started.Set();
        if (escapePressed || Cancel) return DRAGDROP_S_CANCEL;
        return Release ? DRAGDROP_S_DROP : S_OK;
    }

    public int GiveFeedback(uint effect)
    {
        Started.Set();
        return DRAGDROP_S_USEDEFAULTCURSORS;
    }
}
