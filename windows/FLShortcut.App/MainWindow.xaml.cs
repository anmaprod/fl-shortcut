// Fenêtre principale Windows : son contenu (raccourcis, accueil, fiches, notification) est construit par MainShell, à
// l'aspect du Mac (demande du 29/10 : « exactement la même interface sur win »).
using Microsoft.UI.Xaml;

namespace FLShortcut.App;

public sealed partial class MainWindow : Window
{
    private readonly MainShell _shell;

    public MainWindow() : this(photos: false) { }

    /// `photos` : mode photos de la CI : ni hook clavier, ni port MIDI, ni question de validation.
    internal MainWindow(bool photos)
    {
        InitializeComponent();
        _shell = new MainShell(this, Root, photos);
    }

    /// Mode photos de la CI : une page donnée (« general », « playlist », « custom », « recherche »).
    internal void ShowPage(string page) => _shell.ShowPage(page);
}
