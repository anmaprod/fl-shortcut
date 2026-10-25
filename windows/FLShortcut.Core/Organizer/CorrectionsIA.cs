// Organiser : ce que l'IA intégrée apprend des corrections (demande du propriétaire). Un son écouté puis corrigé (dans
// l'aperçu, ou avec « Pas content ? ») est gardé sur ce PC par son empreinte (des nombres, jamais le son ni son nom)
// avec la bonne réponse : un son presque identique est ensuite rangé pareil (règle « corrige », avant les autres).
// Avec l'accord de la personne, ses mesures partent aussi au serveur (table corrections_ia) pour le prochain
// apprentissage de l'IA de tout le monde. Miroir de Sources/FLShortcut/CorrectionsIA.swift.
using System.Text.Json.Nodes;

namespace FLShortcut.Core.Organizer;

/// Un son corrigé, gardé sur ce PC : son empreinte et la bonne réponse.
public sealed record CorrectionIA(float[] Empreinte, SoundFamily Famille, SoundKind? Sorte, DateTimeOffset Date);

public sealed class CorrectionsIA
{
    /// Ressemblance (cosinus des empreintes) à partir de laquelle c'est le même son (ou presque).
    public const float Seuil = 0.97f;
    /// Corrections gardées au plus (les plus anciennes partent).
    public const int Maximum = 500;
    /// Tranches envoyées au plus par son (≈ 26 Ko par correction).
    public const int TranchesEnvoyees = 8;

    private readonly string _path;
    private readonly Func<bool?> _getShare;
    private readonly Action<bool?> _setShare;
    private readonly Action<string, byte[]> _write;
    private readonly Func<string, byte[]?> _read;
    private readonly object _gate = new();
    private List<CorrectionIA>? _cache;

    /// `write` : écriture sûre (fichier 0600, atomique) ; `read` : lecture bornée ; `share` : l'accord gardé.
    public CorrectionsIA(string path, Func<bool?> getShare, Action<bool?> setShare, Action<string, byte[]> write, Func<string, byte[]?> read)
    {
        _path = path;
        _getShare = getShare;
        _setShare = setShare;
        _write = write;
        _read = read;
    }

    /// Accord pour envoyer les corrections au serveur (null : jamais demandé).
    public bool? Partage
    {
        get => _getShare();
        set => _setShare(value);
    }

    public int Nombre { get { lock (_gate) return Liste().Count; } }

    /// La correction d'un son presque identique (la plus proche), s'il y en a une.
    public CorrectionIA? Cherche(float[]? empreinte)
    {
        if (empreinte is null) return null;
        lock (_gate) return PlusProche(empreinte, Liste());
    }

    /// Gardée sur ce PC ; un son déjà corrigé prend la nouvelle réponse.
    public void Ajoute(CorrectionIA correction)
    {
        lock (_gate)
        {
            var toutes = Liste().Where(c => Ressemblance(c.Empreinte, correction.Empreinte) < Seuil).ToList();
            toutes.Add(correction);
            if (toutes.Count > Maximum) toutes.RemoveRange(0, toutes.Count - Maximum);
            _cache = toutes;
            try { _write(_path, System.Text.Encoding.UTF8.GetBytes(Encode(toutes))); }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
        }
    }

    private List<CorrectionIA> Liste()
    {
        if (_cache is not null) return _cache;
        List<CorrectionIA> lues;
        try { lues = _read(_path) is { } data ? Decode(System.Text.Encoding.UTF8.GetString(data)) : new List<CorrectionIA>(); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { lues = new List<CorrectionIA>(); }
        _cache = lues;
        return lues;
    }

    // ---------- Pur ----------

    /// Même forme que le fichier du Mac : [{"empreinte": […], "famille": "drums", "sorte": "kick", "date": …}].
    public static string Encode(IEnumerable<CorrectionIA> list)
    {
        var array = new JsonArray();
        foreach (var c in list)
        {
            var o = new JsonObject
            {
                ["empreinte"] = new JsonArray(c.Empreinte.Select(v => (JsonNode)JsonValue.Create(v)!).ToArray()),
                ["famille"] = c.Famille.Raw(),
                // Date comme le Mac l'écrit (secondes depuis le 1er janvier 2001).
                ["date"] = (c.Date - new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero)).TotalSeconds,
            };
            if (c.Sorte is { } s) o["sorte"] = s.Raw();
            array.Add(o);
        }
        return array.ToJsonString();
    }

    public static List<CorrectionIA> Decode(string json)
    {
        var out_ = new List<CorrectionIA>();
        try
        {
            if (JsonNode.Parse(json) is not JsonArray array) return out_;
            foreach (var node in array)
            {
                if (node is not JsonObject o || o["empreinte"] is not JsonArray e) continue;
                if (o["famille"]?.GetValue<string>() is not { } f || SoundFamilies.FamilyFromRaw(f) is not { } famille) continue;
                var sorte = o["sorte"]?.GetValue<string>() is { } s ? SoundKinds.KindFromRaw(s) : null;
                var seconds = o["date"]?.GetValue<double>() ?? 0;
                out_.Add(new CorrectionIA(e.Select(v => v?.GetValue<float>() ?? 0).ToArray(), famille, sorte,
                    new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero).AddSeconds(seconds)));
            }
        }
        catch (Exception x) when (x is System.Text.Json.JsonException or InvalidOperationException or FormatException) { }
        return out_;
    }

    public static CorrectionIA? PlusProche(float[] empreinte, IEnumerable<CorrectionIA> liste)
    {
        (CorrectionIA C, float R)? meilleure = null;
        foreach (var c in liste)
        {
            var r = Ressemblance(empreinte, c.Empreinte);
            if (r >= Seuil && r > (meilleure?.R ?? -1)) meilleure = (c, r);
        }
        return meilleure?.C;
    }

    /// Cosinus de deux empreintes de longueur 1 (produit scalaire) ; 0 si leurs tailles diffèrent.
    public static float Ressemblance(float[] a, float[] b)
    {
        if (a.Length != b.Length || a.Length == 0) return 0;
        float r = 0;
        for (var i = 0; i < a.Length; i++) r += a[i] * b[i];
        return r;
    }

    /// Famille de l'IA intégrée (ia/commun.py) pour une famille de l'Organiser ; null pour « À vérifier ».
    public static string? NomIA(SoundFamily famille) => famille switch
    {
        SoundFamily.Vocals => "voix",
        SoundFamily.Melody => "melodie",
        SoundFamily.Bass => "basse",
        SoundFamily.Drums => "drums",
        SoundFamily.Fx => "fx",
        _ => null,
    };

    /// Une correction à envoyer au serveur (table corrections_ia) : des nombres et des noms de familles et de sortes,
    /// jamais le son, son nom ni un texte tapé. null si la bonne réponse n'apprend rien à l'IA (« À vérifier »).
    public static JsonObject? Envoi(SoundPrint print, (SoundFamily Famille, SoundKind? Sorte) avant,
        (SoundFamily Famille, SoundKind? Sorte) apres, IReadOnlyList<string> raisons, string appVersion)
    {
        if (NomIA(apres.Famille) is not { } famille || NomIA(print.FamilleIA) is not { } familleIA || print.Mesures.Length == 0) return null;
        var tranches = print.Mesures.Take(TranchesEnvoyees).ToArray();
        if (!tranches.All(t => t.Length == ClasseurSons.TailleMesures)) return null;
        string? Apprise(SoundKind? k) => k is { } kind && ClasseurSons.SortesModele.Contains(kind) ? kind.Raw() : null;
        var corps = new JsonObject
        {
            ["famille_ia"] = familleIA,
            ["famille_avant"] = NomIA(avant.Famille) ?? "",
            ["famille"] = famille,
            ["mesures"] = Convert.ToBase64String(Demi(tranches.SelectMany(t => t).ToArray())),
            ["tranches"] = tranches.Length,
            ["raisons"] = string.Join(",", raisons),
            ["modele"] = ClasseurSons.VersionModele,
            ["app_version"] = appVersion.Length > 20 ? appVersion[..20] : appVersion,
        };
        if (Apprise(print.SorteIA) is { } a) corps["sorte_ia"] = a;
        if (Apprise(avant.Sorte) is { } b) corps["sorte_avant"] = b;
        if (Apprise(apres.Sorte) is { } c) corps["sorte"] = c;
        return corps;
    }

    /// Nombres en 16 bits (IEEE 754, petit-boutiste) : deux fois moins lourds, assez précis pour apprendre.
    public static byte[] Demi(float[] valeurs)
    {
        var out_ = new byte[valeurs.Length * 2];
        for (var i = 0; i < valeurs.Length; i++)
        {
            var h = BitConverter.HalfToUInt16Bits((Half)valeurs[i]);
            out_[2 * i] = (byte)(h & 0xFF);
            out_[2 * i + 1] = (byte)(h >> 8);
        }
        return out_;
    }
}
