// Le guide dans la fenêtre, comme le Mac (10/11, « la page de guide après l'installation, le même que sur Mac ») :
// juste après l'accueil (sur le fond plein, comme dans la fenêtre d'accueil du Mac : la fenêtre des raccourcis vient
// ensuite), ou à la première ouverture de la fenêtre si l'accueil n'a pas eu à se montrer (posé sur la fenêtre
// assombrie, comme la feuille du Mac), puis à la demande depuis la page Aide (« Revoir le guide »). Vu une fois
// (réglage GuideSeen) : il ne revient plus tout seul.
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.UI;
using static FLShortcut.App.MacLook;

namespace FLShortcut.App;

internal sealed partial class MainShell
{
    /// Le calque du guide, au-dessus des pages et de l'accueil : il arrête les clics, Tab reste dans la carte.
    private readonly Grid _guideLayer = new() { Visibility = Visibility.Collapsed, TabFocusNavigation = KeyboardNavigationMode.Cycle };
    private GuideView? _guide;
    /// L'accueil s'est montré à ce lancement : le guide vient à sa suite, sur le fond plein.
    private bool _welcomeShown;

    /// `plain` : sur le fond plein de la fenêtre (suite de l'accueil) ; sinon sur la fenêtre assombrie.
    private void ShowGuide(bool plain, int page = 0)
    {
        _guide = new GuideView(page, CloseGuide);
        _guideLayer.Children.Clear();
        _guideLayer.Background = Brush(plain ? WindowColor : Color.FromArgb(0x99, 0, 0, 0));
        _guideLayer.Children.Add(_guide.View);
        _guideLayer.Visibility = Visibility.Visible;
        _guide.Focus();
    }

    /// « Passer », « C'est parti » : le guide est vu, il ne revient plus tout seul.
    private void CloseGuide()
    {
        if (_guide is null) return;
        _guide = null;
        _guideLayer.Visibility = Visibility.Collapsed;
        _guideLayer.Children.Clear();
        if (_photos || _app.Settings.GuideSeen) return;
        _app.Settings.GuideSeen = true;
        _app.Settings.Save();
    }

    /// La fenêtre des raccourcis vient de se montrer : le guide, s'il n'a jamais été vu.
    private void ShowGuideIfNeverSeen()
    {
        if (_photos || _guide is not null || _app.Settings.GuideSeen) return;
        ShowGuide(plain: _welcomeShown);
    }

    /// Le guide ouvert prend Entrée et Échap ; la recherche par une touche de la fenêtre n'écoute pas pendant ce temps.
    private bool GuideKey(KeyRoutedEventArgs e)
    {
        if (_guide is null) return false;
        if (_guide.Key(e.Key)) e.Handled = true;
        return true;
    }
}
