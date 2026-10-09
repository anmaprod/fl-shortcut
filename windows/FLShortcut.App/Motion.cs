// Animations Windows 11 (Fluent motion) : courbe « départ rapide, arrivée douce » (≈ cubic-bezier(0,0,0,1)),
// durées 167 / 250 / 333 ms. Les animations portent sur l'opacité et les transformations : elles tournent
// sur le compositeur, sans recalcul de mise en page. Désactivées si Windows › Accessibilité › « Effets
// d'animation » est coupé.
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.UI.ViewManagement;

namespace FLShortcut.App;

internal static class Motion
{
    public const int Fast = 167;
    public const int Normal = 250;
    public const int Slow = 333;

    private static readonly UISettings Settings = new();

    /// Réglage Windows « Effets d'animation ».
    public static bool Enabled
    {
        get
        {
            try { return Settings.AnimationsEnabled; }
            catch { return true; }
        }
    }

    private static EasingFunctionBase EaseOut => new ExponentialEase { Exponent = 7, EasingMode = EasingMode.EaseOut };
    private static EasingFunctionBase EaseIn => new ExponentialEase { Exponent = 4, EasingMode = EasingMode.EaseIn };

    /// Apparition : fondu + glissement depuis (fromX, fromY) vers la position finale.
    /// `opacity` : opacité finale (par défaut l'opacité actuelle : une ligne désactivée garde 0,5).
    public static void Enter(UIElement element, double fromX = 0, double fromY = 16, int delayMs = 0, int durationMs = Slow,
                             double? opacity = null)
    {
        var finalOpacity = opacity ?? (element.Opacity <= 0 ? 1 : element.Opacity);
        if (!Enabled)
        {
            element.Opacity = finalOpacity;
            return;
        }
        var shift = new TranslateTransform { X = fromX, Y = fromY };
        element.RenderTransform = shift;
        element.Opacity = 0;

        var sb = new Storyboard();
        sb.Children.Add(Animate(element, "Opacity", 0, finalOpacity, Math.Min(durationMs, Normal), delayMs, EaseOut));
        if (fromX != 0) sb.Children.Add(Animate(shift, "X", fromX, 0, durationMs, delayMs, EaseOut));
        if (fromY != 0) sb.Children.Add(Animate(shift, "Y", fromY, 0, durationMs, delayMs, EaseOut));
        // Fin : la valeur finale devient la valeur locale et l'animation est relâchée. Sinon (HoldEnd) elle
        // masquerait toute affectation ultérieure de Opacity, par exemple si « Effets d'animation » est coupé
        // entre deux notifications (relecture 11).
        sb.Completed += (_, _) =>
        {
            element.Opacity = finalOpacity;
            shift.X = 0;
            shift.Y = 0;
            sb.Stop();
        };
        sb.Begin();
    }

    /// Disparition : fondu + léger glissement vers le bas, puis `done`.
    public static void Exit(UIElement element, Action done, double toY = 12)
    {
        if (!Enabled)
        {
            done();
            return;
        }
        var shift = element.RenderTransform as TranslateTransform ?? new TranslateTransform();
        element.RenderTransform = shift;
        var sb = new Storyboard();
        // Départ = valeur affichée (From non renseigné) : une notification fermée pendant son apparition part
        // de là où elle en est, au lieu de la valeur locale (0 pendant Enter) qui la ferait disparaître d'un coup.
        sb.Children.Add(Animate(element, "Opacity", null, 0, Fast, 0, EaseIn));
        sb.Children.Add(Animate(shift, "Y", null, toY, Fast, 0, EaseIn));
        sb.Completed += (_, _) =>
        {
            done();
            sb.Stop();       // relâche l'opacité 0 maintenue (voir Enter) ; l'élément est déjà masqué ou repris
        };
        sb.Begin();
    }

    /// Petit « pop » (0,85 → 1) pour signaler un changement d'état (statut, touche capturée).
    public static void Pop(UIElement element, int delayMs = 0, double from = 0.85)
    {
        if (!Enabled) return;
        var scale = new ScaleTransform { ScaleX = from, ScaleY = from };
        element.RenderTransformOrigin = new Windows.Foundation.Point(0.5, 0.5);
        element.RenderTransform = scale;
        var spring = new ElasticEase { Oscillations = 1, Springiness = 6, EasingMode = EasingMode.EaseOut };
        var sb = new Storyboard();
        sb.Children.Add(Animate(scale, "ScaleX", from, 1, Slow + 100, delayMs, spring));
        sb.Children.Add(Animate(scale, "ScaleY", from, 1, Slow + 100, delayMs, spring));
        sb.Completed += (_, _) =>
        {
            scale.ScaleX = 1;
            scale.ScaleY = 1;
            sb.Stop();
        };
        sb.Begin();
    }

    private static DoubleAnimation Animate(DependencyObject target, string property, double? from, double to,
                                           int durationMs, int delayMs, EasingFunctionBase ease)
    {
        var a = new DoubleAnimation
        {
            From = from,
            To = to,
            Duration = new Duration(TimeSpan.FromMilliseconds(durationMs)),
            BeginTime = TimeSpan.FromMilliseconds(delayMs),
            EasingFunction = ease,
        };
        Storyboard.SetTarget(a, target);
        Storyboard.SetTargetProperty(a, property);
        return a;
    }
}
