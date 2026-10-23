// IA intégrée (Windows) : famille et sorte d'un son avec ia/modele/classeur_sons.onnx, hors-ligne.
// Exemple de référence, pas encore compilé dans l'app Windows (en pause) : NuGet Microsoft.ML.OnnxRuntime
// (ou Microsoft.ML.OnnxRuntime.DirectML pour la carte graphique). Même règle que ia/classer.py et l'app Mac :
// son mono 16 kHz, crête à 0,7, tranches de 15 600 échantillons tous les 7 680 (16 au plus, les plus fortes) ;
// famille = moyenne des tranches, mais voix dès que la tranche la plus « voix » passe le seuil (classeur_sons.json) ;
// sorte = la plus probable parmi celles de la famille (les choix de l'aperçu de l'Organiser, mêmes noms internes que
// SoundKind de l'app Mac), donnée seulement si elle l'emporte nettement.
// La lecture et le rééchantillonnage du fichier (Media Foundation, NAudio…) sont laissés à l'app.
using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.ML.OnnxRuntime;
using Microsoft.ML.OnnxRuntime.Tensors;

namespace FLShortcut.Core;

public sealed class ClasseurSons : IDisposable
{
    public const int Frequence = 16000, Tranche = 15600, Pas = 7680, MaxTranches = 16;
    public static readonly string[] Familles = { "voix", "melodie", "basse", "drums", "fx" };
    public const float PartMin = 0.5f;
    // Sortes du modèle, dans l'ordre de sa sortie « sorte » (classeur_sons.json), groupées par famille.
    public static readonly string[][] SortesParFamille =
    {
        new[] { "vocal", "vocalLead", "choir", "adlib", "ambiance" },
        new[] { "lead", "pluck", "pad", "keys", "piano", "arp", "chords", "guitar", "strings", "bell", "flute", "brass",
                "organ", "melody" },
        new[] { "bass808", "sub", "reese", "bass" },
        new[] { "kick", "snare", "clap", "rim", "snap", "hiHat", "openHat", "perc", "tom", "shaker", "crash", "ride",
                "cymbal", "drums" },
        new[] { "riser", "downlifter", "impact", "sweep", "fx" },
    };
    public static readonly string[] Sortes = SortesParFamille.SelectMany(s => s).ToArray();
    readonly InferenceSession _session;
    readonly float _seuilVoix;

    public ClasseurSons(string cheminOnnx, float seuilVoix)
    {
        var options = new SessionOptions { GraphOptimizationLevel = GraphOptimizationLevel.ORT_ENABLE_ALL };
        try { options.AppendExecutionProvider_DML(0); } catch { /* pas de DirectML : processeur */ }
        _session = new InferenceSession(cheminOnnx, options);
        _seuilVoix = seuilVoix;
    }

    /// <summary>son : mono, 16 kHz. Rend (famille, sorte ou null si elle n'est pas nette, probabilité de voix la plus
    /// forte).</summary>
    public (string Famille, string? Sorte, float VoixMax) Classer(float[] son)
    {
        var tranches = Decouper(Normaliser(son));
        if (tranches.Count == 0) return ("fx", null, 0);
        var entree = new DenseTensor<float>(new[] { tranches.Count, Tranche });
        for (int i = 0; i < tranches.Count; i++)
            for (int j = 0; j < Tranche; j++) entree[i, j] = tranches[i][j];
        using var sorties = _session.Run(new[] { NamedOnnxValue.CreateFromTensor("son", entree) });
        var pf = sorties.First(s => s.Name == "famille").AsTensor<float>();
        var ps = sorties.First(s => s.Name == "sorte").AsTensor<float>();
        int n = tranches.Count;
        var moy = Enumerable.Range(0, Familles.Length).Select(k => Enumerable.Range(0, n).Average(i => pf[i, k])).ToArray();
        float voixMax = Enumerable.Range(0, n).Max(i => pf[i, 0]);
        int famille = voixMax >= _seuilVoix ? 0
            : Enumerable.Range(1, Familles.Length - 1).OrderByDescending(k => moy[k]).First();
        int debut = SortesParFamille.Take(famille).Sum(s => s.Length);
        var parts = SortesParFamille[famille].Select((_, j) => Enumerable.Range(0, n).Average(i => ps[i, debut + j]))
                                              .ToArray();
        int meilleure = Array.IndexOf(parts, parts.Max());
        string? sorte = parts[meilleure] / Math.Max(parts.Sum(), 1e-9f) >= PartMin
            ? SortesParFamille[famille][meilleure] : null;
        return (Familles[famille], sorte, voixMax);
    }

    static float[] Normaliser(float[] son)
    {
        float crete = son.Length == 0 ? 0 : son.Max(v => Math.Abs(v));
        return crete > 1e-4f ? son.Select(v => v / crete * 0.7f).ToArray() : son;
    }

    static List<float[]> Decouper(float[] son)
    {
        var liste = new List<float[]>();
        if (son.Length == 0) return liste;
        int n = 1 + Math.Max(0, (int)Math.Ceiling((son.Length - Tranche) / (double)Pas));
        for (int i = 0; i < n; i++)
        {
            var t = new float[Tranche];
            Array.Copy(son, i * Pas, t, 0, Math.Min(Tranche, son.Length - i * Pas));
            liste.Add(t);
        }
        if (liste.Count <= MaxTranches) return liste;
        var fortes = liste.Select((t, i) => (i, e: t.Sum(v => v * v))).OrderByDescending(x => x.e)
                          .Take(MaxTranches).Select(x => x.i).OrderBy(i => i);
        return fortes.Select(i => liste[i]).ToList();
    }

    public void Dispose() => _session.Dispose();
}
