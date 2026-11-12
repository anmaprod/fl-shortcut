// « Quitter et rouvrir FL » (12/11, « le bouton quitter et rouvrir… il ne rouvre pas automatiquement FL Studio ») :
// décide à chaque coup d'œil (toutes les 0,5 s) s'il faut attendre, lancer FL ou s'arrêter. Le FL d'avant est attendu
// jusqu'à son départ (le temps de répondre à « Enregistrer ? », 5 minutes au plus), puis FL est lancé une seconde après ;
// s'il n'apparaît pas, relancé (3 fois au plus, une erreur de lancement : 2 s après). Un nouveau FL, même rouvert à la
// main, finit l'attente : rien n'est lancé en plus. Mac : FLRelaunchPlan (mêmes règles, mêmes essais).
namespace FLShortcut.Core.Organizer;

public sealed class FlRelaunchPlan
{
    public enum Step { Wait, Launch, Done, GiveUp }

    public const double QuitLimit = 300;
    public const double Settle = 1;
    public const double LaunchCheck = 20;
    public const double RetryAfterError = 2;
    public const int MaxLaunches = 3;

    private readonly int _oldPid;
    private readonly double _started;
    private double? _nextLaunch;

    public int Launches { get; private set; }

    /// Quand le FL d'avant est parti (secondes depuis le début), pour le journal.
    public double? GoneAt { get; private set; }

    public FlRelaunchPlan(int oldPid, double now)
    {
        _oldPid = oldPid;
        _started = now;
    }

    /// `running` : les FL qui tournent maintenant (numéros de processus).
    public Step Next(double now, IReadOnlyCollection<int> running)
    {
        if (running.Any(pid => pid != _oldPid)) return Step.Done;
        if (running.Contains(_oldPid)) return now - _started >= QuitLimit ? Step.GiveUp : Step.Wait;
        if (GoneAt is null)
        {
            GoneAt = now;
            _nextLaunch = now + Settle;
        }
        if (_nextLaunch is not { } at || now < at) return Step.Wait;
        if (Launches >= MaxLaunches) return Step.GiveUp;
        Launches++;
        _nextLaunch = now + LaunchCheck;
        return Step.Launch;
    }

    /// Le lancement a échoué tout de suite : nouvel essai bientôt.
    public void LaunchFailed(double now) => _nextLaunch = now + RetryAfterError;
}
