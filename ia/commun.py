"""Base commune du pipeline de l'IA intégrée (classement des sons de l'Organiser) : classes, lecture des sons,
tranches, YAMNet. Tout tourne hors-ligne une fois les données et YAMNet téléchargés (donnees.py).

Le modèle : YAMNet (Google, licence Apache 2.0) donne pour chaque tranche de 0,975 s une empreinte de 1024 nombres ;
on y ajoute 192 mesures du spectre log-mel de la même tranche (moyenne, écart-type et variation de chaque bande :
les formants et le débit syllabique d'une voix y laissent une marque nette). Deux petites têtes apprises ici donnent
la famille (voix, mélodie, basse, drums, FX) et la sorte : les 44 choix de l'aperçu de l'Organiser (Voix lead,
Chœur, Pluck, Pad, Piano, 808, Sub, Reese, Kick, Open Hat, Drum loop, Fill, Riser…)."""
import io
import os
import sys
from fractions import Fraction

import numpy as np

ICI = os.path.dirname(os.path.abspath(__file__))
TRAVAIL = os.environ.get("FLS_IA_TRAVAIL", os.path.join(os.path.expanduser("~"), ".cache", "fl-shortcuts-ia"))
MODELE = os.path.join(ICI, "modele")

SR = 16000                       # fréquence de YAMNet
TRANCHE = 15600                  # 0,975 s : une « patch » de YAMNet (96 cadres de 10 ms + fenêtre de 25 ms)
PAS = 7680                       # 0,48 s : pas entre deux tranches, comme YAMNet
MAX_TRANCHES = 16                # au-delà, les tranches les plus fortes (un son long reste rapide)

FAMILLES = ["voix", "melodie", "basse", "drums", "fx"]
# Les sortes de l'aperçu de l'Organiser (SoundKind de l'app, mêmes noms internes), par famille. Le mot général de
# chaque famille (vocal, melody, bass, drums, fx) est aussi une réponse possible. « backing » (Back) et « synth » se
# décident au nom du son, pas à l'écoute.
SORTES_PAR_FAMILLE = {
    "voix": ["vocal", "vocalLead", "choir", "adlib", "ambiance"],
    "melodie": ["lead", "pluck", "pad", "keys", "piano", "arp", "chords", "guitar", "strings", "bell", "flute",
                "brass", "organ", "melody"],
    "basse": ["bass808", "sub", "reese", "bass"],
    "drums": ["kick", "snare", "clap", "rim", "snap", "hiHat", "openHat", "perc", "tom", "shaker", "crash", "ride",
              "cymbal", "drumLoop", "fill", "drums"],
    "fx": ["riser", "downlifter", "impact", "sweep", "fx"],
}
SORTES = [s for f in FAMILLES for s in SORTES_PAR_FAMILLE[f]]
# Les sortes d'avant « Drum loop » et « Fill » (demande du propriétaire, 24/10) : celles des étapes préparées avant,
# dont les numéros de sorte sont relus dans cet ordre.
SORTES_42 = [s for s in SORTES if s not in ("drumLoop", "fill")]
FAMILLE_DE_SORTE = {s: f for f in FAMILLES for s in SORTES_PAR_FAMILLE[f]}
# Noms affichés par l'app (SoundKind.name) : dossiers de classer.py --ranger.
NOMS = {"vocal": "Voix", "vocalLead": "Voix lead", "choir": "Chœur", "adlib": "Adlib", "ambiance": "Ambiance",
        "lead": "Lead", "pluck": "Pluck", "pad": "Pad", "keys": "Keys", "piano": "Piano", "arp": "Arp",
        "chords": "Chords", "guitar": "Guitare", "strings": "Strings", "bell": "Bell", "flute": "Flûte",
        "brass": "Brass", "organ": "Orgue", "melody": "Mélodie", "bass808": "808", "sub": "Sub", "reese": "Reese",
        "bass": "Basse", "kick": "Kick", "snare": "Snare", "clap": "Clap", "rim": "Rim", "snap": "Snap",
        "hiHat": "Hi-hat", "openHat": "Open Hat", "perc": "Perc", "tom": "Tom", "shaker": "Shaker", "crash": "Crash",
        "ride": "Ride", "cymbal": "Cymbal", "drumLoop": "Drum loop", "fill": "Fill", "drums": "Drums", "riser": "Riser", "downlifter": "Downlifter",
        "impact": "Impact", "sweep": "Sweep", "fx": "FX"}
INCONNUE = -1                    # sorte inconnue (son de batterie sans nom parlant) : seule la famille apprend


def mono16k(data, sr):
    """Son mono à 16 kHz, crête ramenée à 0,7 (le niveau d'un sample ne doit pas compter)."""
    data = np.asarray(data, dtype=np.float32)
    if data.ndim > 1:
        data = data.mean(axis=1)
    if sr != SR:
        from scipy.signal import resample_poly
        f = Fraction(SR, int(round(sr))).limit_denominator(1000)
        data = resample_poly(data, f.numerator, f.denominator).astype(np.float32)
    peak = float(np.abs(data).max()) if data.size else 0.0
    return (data / peak * 0.7).astype(np.float32) if peak > 1e-4 else data


def lire(chemin_ou_octets):
    """Fichier audio (wav, aiff, flac, ogg, mp3 selon libsndfile) → mono 16 kHz."""
    import soundfile as sf
    src = io.BytesIO(chemin_ou_octets) if isinstance(chemin_ou_octets, (bytes, bytearray)) else chemin_ou_octets
    data, sr = sf.read(src, always_2d=False, dtype="float32")
    return mono16k(data, sr)


def tranches(son):
    """Tranches de TRANCHE échantillons tous les PAS (la dernière complétée de silence, comme YAMNet) ; au-delà de
    MAX_TRANCHES, les plus fortes, dans l'ordre du son. Même règle que l'app (ClasseurSons.swift)."""
    if son.size == 0:
        return np.zeros((0, TRANCHE), np.float32)
    n = 1 + max(0, int(np.ceil((son.size - TRANCHE) / PAS)))
    out = np.zeros((n, TRANCHE), np.float32)
    for i in range(n):
        part = son[i * PAS: i * PAS + TRANCHE]
        out[i, :part.size] = part
    if n > MAX_TRANCHES:
        energie = (out ** 2).sum(axis=1)
        garde = np.sort(np.argsort(-energie)[:MAX_TRANCHES])
        out = out[garde]
    return out


def yamnet_dir():
    return os.path.join(TRAVAIL, "yamnet")


def charger_yamnet():
    """Modules de YAMNet (code de tensorflow/models, Apache 2.0) téléchargés par donnees.py."""
    d = yamnet_dir()
    if not os.path.exists(os.path.join(d, "yamnet.h5")):
        sys.exit("YAMNet absent : lance d'abord  python ia/donnees.py")
    if d not in sys.path:
        sys.path.insert(0, d)
    os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")
    import params as yparams
    import yamnet as ylib
    return yparams, ylib


def stats_logmel(patch):
    """192 mesures d'une tranche de spectre log-mel [96, 64] : moyenne, écart-type et variation moyenne (|cadre −
    cadre précédent|) de chaque bande. Calcul identique dans le modèle exporté (exporter.py)."""
    patch = np.asarray(patch, np.float32)
    return np.concatenate([patch.mean(axis=0), patch.std(axis=0), np.abs(np.diff(patch, axis=0)).mean(axis=0)])
