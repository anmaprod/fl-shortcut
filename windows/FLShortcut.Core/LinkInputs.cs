// Windows, 09/11 (capture de MIDI Settings d'un ami : « ça ne fonctionne toujours pas pourtant tout est connecté ») :
// les deux sorties « FL Shortcuts » et « FL Shortcuts Retour » étaient sur le même Port (236). FL envoie alors ce que
// dit le script à UNE seule de ces sorties (celle qu'il apparie à l'entrée du même nom, « FL Shortcuts ») : le HELLO
// repartait dans la boucle « FL Shortcuts » et n'arrivait jamais à l'entrée « FL Shortcuts Retour » que lisait l'appli
// (« lien muet »). L'appli lit maintenant les DEUX entrées : « FL Shortcuts Retour » et la boucle « FL Shortcuts »
// (où elle entend aussi ses propres messages, que le décodeur ignore : numéros de CC disjoints). Si FL écrit sur les
// deux, chaque message arriverait deux fois et une réponse en morceaux serait mélangée : la première entrée qui
// apporte un début de HELLO est gardée, l'autre est ignorée (elle reprend la main si la première se tait).
// Pur, testé (LinkInputsTests).
namespace FLShortcut.Core;

public sealed class LinkInputs
{
    /// Entrées lues par l'appli : 0 = « FL Shortcuts Retour », 1 = la boucle « FL Shortcuts ».
    public const int Count = 2;
    /// L'entrée gardée qui se tait depuis ce temps cède la place à l'autre au prochain HELLO.
    public static readonly TimeSpan SilenceBeforeSwitch = TimeSpan.FromSeconds(3);

    private readonly object _gate = new();
    private readonly DateTime[] _lastFromFl = new DateTime[Count];
    private readonly long[] _fromFl = new long[Count];
    private int _active = -1;

    /// L'entrée qui porte les messages de FL (-1 : pas encore de HELLO).
    public int Active
    {
        get { lock (_gate) return _active; }
    }

    /// Messages de FL reçus sur chaque entrée (diagnostic : des nombres seulement).
    public long FromFl(int source)
    {
        lock (_gate) return source is >= 0 and < Count ? _fromFl[source] : 0;
    }

    /// Ce message reçu sur `source` doit-il être donné au cœur du lien ?
    public bool Accept(int source, uint shortMessage, DateTime now)
    {
        if (source is < 0 or >= Count) return false;
        var status = (byte)(shortMessage & 0xFF);
        var cc = (byte)((shortMessage >> 8) & 0x7F);
        var value = (byte)((shortMessage >> 16) & 0x7F);
        var fromFl = status == FlProtocol.StatusCc && FlProtocol.SentByFl(cc);
        var helloStart = fromFl && cc == FlProtocol.CcHello && value == FlProtocol.HelloStart;
        lock (_gate)
        {
            if (fromFl)
            {
                _fromFl[source]++;
                _lastFromFl[source] = now;
            }
            if (_active == source) return true;
            if (_active < 0)
            {
                if (helloStart) _active = source;
                return true;                 // avant le HELLO : rien qui se mélange (battements, fenêtre)
            }
            // L'autre entrée est gardée : on passe seulement si elle se tait et qu'un HELLO commence ici.
            if (helloStart && now - _lastFromFl[_active] > SilenceBeforeSwitch)
            {
                _active = source;
                return true;
            }
            return false;
        }
    }

    /// Lien fermé ou ports rouverts : on réécoute les deux entrées.
    public void Reset()
    {
        lock (_gate) _active = -1;
    }
}
