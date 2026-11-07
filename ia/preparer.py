"""Prépare le jeu d'apprentissage : chaque son reçoit une famille (voix, mélodie, basse, drums, FX) et, si on la
connaît sûrement, une sorte parmi les choix de l'aperçu de l'Organiser (Voix lead, Chœur, Adlib, Ambiance ; Lead,
Pluck, Pad, Keys, Piano, Arp, Chords, Guitare, Strings, Bell, Flûte, Brass, Orgue ; 808, Sub, Reese, Basse ; Kick,
Snare, Clap, Rim, Snap, Hi-hat, Open Hat, Perc, Tom, Shaker, Crash, Ride, Cymbal ; Riser, Downlifter, Impact,
Sweep ; et le mot général de chaque famille). Puis, pour chaque tranche de 0,975 s : l'empreinte YAMNet (1024) + 192
mesures du spectre log-mel = 1216 nombres. Sortie : TRAVAIL/jeu.npz.

Les voix sont le point faible de l'Organiser (rangées en mélodies, FX ou drums) : elles sont nombreuses et déclinées
comme en production (réverb, hauteur et formants décalés, saturation, filtre téléphone, chops très courts, stutter,
voix à l'envers, harmonies), et les pièges sont fabriqués exprès (leads de synthé au vibrato, notes à l'envers, FX).
Séparation honnête : des chanteurs, locuteurs, instruments NSynth et sons de batterie entiers sont gardés pour la
validation, jamais vus à l'apprentissage.
Usage : python ia/preparer.py   (≈ 1 h sur 4 cœurs ; chaque étape finie est gardée, une relance reprend après)"""
import json
from collections import Counter, defaultdict
import os
import random
import re
import tarfile
import zipfile

import numpy as np

from commun import (FAMILLE_DE_SORTE, FAMILLES, INCONNUE, SORTES, SORTES_42, SR, TRAVAIL, charger_yamnet, lire,
                    stats_logmel)

# FLS_IA_COUCHE13=1 : garde aussi la sortie de la couche 13 de YAMNet de chaque tranche (etape_*.c13, 3 × 2 × 1024
# nombres en 16 bits), pour réapprendre sa dernière couche (affiner.py). Demande une préparation complète.
COUCHE13 = os.environ.get("FLS_IA_COUCHE13") == "1"

rng = random.Random(7)
nrng = np.random.default_rng(7)
D = os.path.join(TRAVAIL, "donnees")


def norm(x):
    return (x / max(float(np.abs(x).max()), 1e-6) * 0.7).astype(np.float32)


# ---------- Variantes de voix (comme en production) ----------

def onepole(x, cutoff, high=False):
    from scipy.signal import lfilter
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = lfilter([1 - a], [1, -a], x).astype(np.float32)
    return (x - y) if high else y


def reverb(x, seconds=None):
    n = int((seconds or rng.uniform(0.4, 2.5)) * SR)
    ir = nrng.standard_normal(n).astype(np.float32) * np.exp(-6.9 * np.arange(n) / n).astype(np.float32)
    ir[0] = 1.0
    from scipy.signal import fftconvolve
    wet = fftconvolve(x, ir)[: len(x) + n // 2].astype(np.float32)
    dry = np.pad(x, (0, len(wet) - len(x)))
    mix = rng.uniform(0.3, 0.8)
    return norm((1 - mix) * dry + mix * norm(wet))


def pitch(x, demi_tons=None):
    """Hauteur ET formants décalés (rééchantillonnage) : voix pitchée « chipmunk » ou grave, comme en chop."""
    from scipy.signal import resample
    f = 2 ** ((demi_tons if demi_tons is not None else rng.choice([-7, -5, -3, 3, 5, 7, 12])) / 12)
    return resample(x, max(1, int(len(x) / f))).astype(np.float32)


def saturate(x):
    return norm(np.tanh(x * rng.uniform(2, 12)))


def telephone(x):
    return norm(onepole(onepole(x, rng.uniform(250, 900), high=True), rng.uniform(2500, 5000)))


def chop(x):
    n = int(rng.uniform(0.12, 1.0) * SR)
    if len(x) <= n:
        return x
    s = rng.randrange(0, len(x) - n)
    seg = x[s:s + n].copy()
    fade = min(160, n // 4)
    seg[:fade] *= np.linspace(0, 1, fade)
    seg[-fade:] *= np.linspace(1, 0, fade)
    return seg


def stutter(x):
    seg = chop(x)[: int(rng.uniform(0.06, 0.2) * SR)]
    return np.tile(seg, rng.randint(3, 8)).astype(np.float32)


def reverse(x):
    return x[::-1].copy()


def choeur(x):
    """Plusieurs voix superposées, un peu décalées et désaccordées : un chœur."""
    voix = [x] + [pitch(x, d + rng.uniform(-0.15, 0.15)) for d in rng.sample([-12, -5, -3, 0, 3, 4, 7], rng.randint(3, 5))]
    n = min(len(v) for v in voix)
    decale = [np.pad(v[:n], (int(rng.uniform(0, 0.03) * SR), 0))[:n] for v in voix]
    return norm(sum(decale))


def ambiance(x):
    """Voix noyée dans une longue réverb, adoucie : une nappe de voix."""
    return norm(onepole(reverb(x, rng.uniform(2.5, 4.5)), rng.uniform(2000, 5000)))


VARIANTES = {"reverb": reverb, "pitch": pitch, "saturate": saturate, "telephone": telephone, "chop": chop,
             "stutter": stutter, "reverse": reverse, "choeur": choeur, "ambiance": ambiance}


def variante_voix(x):
    """Variante de production ; rend aussi sa sorte quand elle change (chop → Adlib, chœur, ambiance)."""
    noms = rng.choice([["reverb"], ["pitch"], ["saturate"], ["telephone"], ["chop"], ["stutter"], ["reverse"],
                       ["choeur"], ["ambiance"], ["pitch", "reverb"], ["chop", "reverb"], ["chop", "pitch"],
                       ["reverse", "reverb"], ["choeur", "reverb"]])
    for n in noms:
        x = VARIANTES[n](x)
    sorte = "adlib" if {"chop", "stutter"} & set(noms) else "choir" if "choeur" in noms \
        else "ambiance" if "ambiance" in noms else None
    return x, "+".join(noms), sorte


# ---------- Sons fabriqués ----------

def env(n, attack=0.005, decay=None):
    t = np.arange(n) / SR
    a = np.minimum(1, t / attack)
    return (a * (np.exp(-t / decay) if decay else 1)).astype(np.float32)


def synth_808():
    n = int(rng.uniform(0.4, 2.2) * SR)
    t = np.arange(n) / SR
    f = rng.uniform(32, 75) * (1 + rng.uniform(0.5, 4) * np.exp(-t * rng.uniform(15, 70)))
    if rng.random() < 0.4:                                     # glissé
        f *= 2 ** (rng.choice([-1, 1]) * rng.uniform(2, 12) / 12 * np.clip(t / rng.uniform(0.1, 0.5), 0, 1))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.002, rng.uniform(0.25, 1.5))
    if rng.random() < 0.3:                                     # clic d'attaque
        x[:200] += nrng.standard_normal(200) * 0.3 * np.linspace(1, 0, 200)
    if rng.random() < 0.6:
        x = np.tanh(x * rng.uniform(1.5, 8))
    return norm(x)


def synth_basse():
    out = []
    for _ in range(rng.randint(1, 6)):
        f = rng.uniform(38, 120)
        n = int(rng.uniform(0.15, 0.7) * SR)
        t = np.arange(n) / SR
        onde = rng.choice(["scie", "carre", "sinus"])
        if onde == "scie":
            x = 2 * ((f * t) % 1) - 1
        elif onde == "carre":
            x = np.sign(np.sin(2 * np.pi * f * t))
        else:
            x = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t)
        out.append(onepole(x.astype(np.float32), rng.uniform(150, 1200)) * env(n, 0.005, rng.uniform(0.2, 1.5)))
    return norm(np.concatenate(out))


def synth_sub():
    """Sub : sinus grave tenu, attaque douce, sans clic ni saturation."""
    n = int(rng.uniform(0.6, 2.5) * SR)
    t = np.arange(n) / SR
    f = rng.uniform(30, 65) * 2 ** (rng.randint(0, 7) / 12)
    return norm(np.sin(2 * np.pi * f * t) * env(n, rng.uniform(0.01, 0.05), rng.uniform(0.8, 3)))


def synth_reese():
    """Reese : deux ou trois scies désaccordées qui battent, filtre qui bouge."""
    n = int(rng.uniform(1.0, 3.0) * SR)
    t = np.arange(n) / SR
    f = rng.uniform(40, 90)
    x = sum(2 * ((f * (1 + d) * t + rng.random()) % 1) - 1 for d in [0, rng.uniform(0.004, 0.02), -rng.uniform(0.004, 0.02)][: rng.randint(2, 3)])
    lfo = 0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(0.2, 1.5) * t)
    x = onepole(x.astype(np.float32), 300) * (1 - lfo) + onepole(x.astype(np.float32), 1500) * lfo
    return norm(np.tanh(x * rng.uniform(1, 3)) * env(n, 0.01))


def synth_pad():
    """Pad : accord de scies désaccordées, attaque lente, long, filtré, réverb."""
    n = int(rng.uniform(2.0, 4.0) * SR)
    t = np.arange(n) / SR
    racine = rng.uniform(110, 330)
    x = np.zeros(n, np.float32)
    for k in rng.choice([[0, 4, 7], [0, 3, 7], [0, 5, 9], [0, 4, 7, 11]]):
        f = racine * 2 ** (k / 12)
        for d in (-0.006, 0, 0.006):
            x += (2 * ((f * (1 + d) * t + rng.random()) % 1) - 1).astype(np.float32)
    x = onepole(x, rng.uniform(800, 2500)) * env(n, rng.uniform(0.3, 1.0))
    return reverb(norm(x), rng.uniform(1.5, 3))


def synth_note(f, secondes):
    """Note de synthé (scie, carré ou triangle, filtrée) : matière des plucks, arpèges et accords fabriqués."""
    n = int(secondes * SR)
    t = np.arange(n) / SR
    onde = rng.choice(["scie", "carre", "triangle"])
    if onde == "scie":
        x = 2 * ((f * t) % 1) - 1
    elif onde == "carre":
        x = np.sign(np.sin(2 * np.pi * f * t))
    else:
        x = 2 * np.abs(2 * ((f * t) % 1) - 1) - 1
    return norm(onepole(x.astype(np.float32), rng.uniform(1500, 6000)))


def notes_synth(secondes):
    """Les notes d'un accord de synthé (majeur, mineur, sus, septième), d'une même onde au hasard."""
    racine = rng.uniform(130, 520)
    return [synth_note(racine * 2 ** (k / 12), secondes)
            for k in rng.choice([[0, 4, 7], [0, 3, 7], [0, 5, 7], [0, 4, 7, 11], [0, 3, 7, 10], [0, 7, 12]])]


def pluck(note):
    """Pluck : note courte qui s'éteint vite."""
    n = min(len(note), int(rng.uniform(0.15, 0.5) * SR))
    return norm(note[:n] * env(n, 0.001, rng.uniform(0.04, 0.15)))


def arpege(notes):
    """Arp : motif régulier de notes très courtes, répété."""
    motif = [rng.choice(notes) for _ in range(rng.randint(3, 5))]
    duree = int(rng.uniform(0.08, 0.16) * SR)
    pas = [m[:duree] * env(duree, 0.002, rng.uniform(0.05, 0.12)) for m in motif]
    return norm(np.concatenate(pas * rng.randint(3, 5)))


def synth_snap():
    n = int(rng.uniform(0.08, 0.3) * SR)
    x = nrng.standard_normal(n).astype(np.float32) * env(n, 0.0003, rng.uniform(0.01, 0.03))
    x = onepole(onepole(x, rng.uniform(1500, 2500), high=True), rng.uniform(4000, 8000))
    return norm(reverb(x, 0.3) if rng.random() < 0.4 else x)


def synth_shaker():
    n = int(rng.uniform(0.1, 0.4) * SR)
    t = np.arange(n) / SR
    grains = nrng.standard_normal(n).astype(np.float32) * (nrng.random(n) < 0.3)
    x = onepole(grains.astype(np.float32), rng.uniform(4000, 7000), high=True)
    return norm(x * np.sin(np.pi * np.minimum(t / t[-1], 1)) ** rng.uniform(0.5, 2))


def synth_crash():
    n = int(rng.uniform(1.0, 3.0) * SR)
    t = np.arange(n) / SR
    x = sum(np.sign(np.sin(2 * np.pi * f * t * rng.uniform(0.9, 1.4))) for f in [205.3, 304.4, 369.6, 522.7, 540, 800])
    x = x + nrng.standard_normal(n) * 2
    return norm(onepole(x.astype(np.float32), rng.uniform(3000, 6000), high=True) * env(n, 0.001, rng.uniform(0.4, 1.2)))


def synth_clap():
    n = int(rng.uniform(0.25, 0.8) * SR)
    x = np.zeros(n, np.float32)
    noise = nrng.standard_normal(n).astype(np.float32)
    for k in range(rng.randint(3, 5)):                         # plusieurs mains, quelques ms d'écart
        s = int(k * rng.uniform(0.006, 0.014) * SR)
        x[s:] += noise[: n - s] * env(n - s, 0.0005, rng.uniform(0.008, 0.02)) * (0.6 if k < 3 else 1)
    x += noise * env(n, 0.001, rng.uniform(0.08, 0.25)) * 0.5   # queue
    x = onepole(onepole(x, rng.uniform(600, 1200), high=True), rng.uniform(3000, 7000))
    return norm(reverb(x, 0.4) if rng.random() < 0.3 else x)


def synth_hihat(ouvert):
    n = int((rng.uniform(0.35, 1.0) if ouvert else rng.uniform(0.04, 0.15)) * SR)
    t = np.arange(n) / SR
    if rng.random() < 0.5:                                     # métal de 808 : six carrés
        x = sum(np.sign(np.sin(2 * np.pi * f * t)) for f in [205.3, 304.4, 369.6, 522.7, 540, 800])
    else:
        x = nrng.standard_normal(n)
    x = onepole(x.astype(np.float32), rng.uniform(5000, 9000), high=True)
    return norm(x * env(n, 0.0005, rng.uniform(0.2, 0.5) if ouvert else rng.uniform(0.01, 0.05)))


def synth_fx():
    n = int(rng.uniform(1.0, 4.0) * SR)
    t = np.arange(n) / SR
    bruit = nrng.standard_normal(n).astype(np.float32)
    kind = rng.choice(["riser", "down", "impact", "sweep", "riser", "down", "impact", "sweep", "laser", "bruit",
                       "vinyle", "drone"])
    if kind == "riser":
        x = onepole(bruit, rng.uniform(200, 800)) * np.linspace(0.05, 1, n) \
            + 0.3 * np.sin(2 * np.pi * np.cumsum(np.linspace(rng.uniform(100, 300), rng.uniform(1000, 4000), n)) / SR)
    elif kind == "down":
        x = onepole(bruit, 1500) * np.linspace(1, 0.05, n) \
            + 0.3 * np.sin(2 * np.pi * np.cumsum(np.linspace(rng.uniform(800, 3000), 60, n)) / SR)
    elif kind == "impact":
        x = bruit * env(n, 0.001, rng.uniform(0.1, 0.5)) + np.sin(2 * np.pi * rng.uniform(35, 60) * t) * env(n, 0.001, 0.9)
        x = reverb(norm(x), rng.uniform(1.5, 3))
    elif kind == "sweep":
        x = onepole(bruit, rng.uniform(300, 2000), high=rng.random() < 0.5) * np.sin(np.pi * t / t[-1])
    elif kind == "laser":
        x = np.sin(2 * np.pi * np.cumsum(rng.uniform(1500, 5000) * np.exp(-t * rng.uniform(4, 15)) + 80) / SR) \
            * env(n, 0.001, rng.uniform(0.2, 0.8))
    elif kind == "vinyle":
        x = onepole(bruit, 3000) * 0.2
        for _ in range(int(rng.uniform(5, 40) * n / SR)):
            i = rng.randrange(0, n - 50)
            x[i:i + 50] += nrng.standard_normal(50) * rng.uniform(0.5, 2)
    elif kind == "drone":
        x = sum(np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) for f in rng.sample([55, 82.4, 110, 164.8, 220], 3))
        x = x * (0.6 + 0.4 * np.sin(2 * np.pi * rng.uniform(0.1, 0.5) * t)) + onepole(bruit, 400) * 0.3
    else:
        x = bruit * rng.uniform(0.1, 1)
    sorte = {"riser": "riser", "down": "downlifter", "impact": "impact", "sweep": "sweep"}.get(kind, "fx")
    return norm(x), sorte


def vibrato(x):
    """Lead de synthé, flûte ou cordes au vibrato : le piège de la règle « voix-vibrato » de l'Organiser."""
    t = np.arange(len(x)) / SR
    ratio = 2 ** (rng.uniform(0.15, 0.6) / 12 * np.sin(2 * np.pi * rng.uniform(4.5, 7) * t))
    pos = np.cumsum(ratio)
    pos = pos[pos < len(x) - 1]
    return np.interp(pos, np.arange(len(x)), x).astype(np.float32)


# ---------- Empreintes au fil de l'eau ----------

class Collecte:
    def __init__(self):
        yparams, ylib = charger_yamnet()
        import tensorflow as tf
        p = yparams.Params()
        model = ylib.yamnet_frames_model(p)
        model.load_weights(os.path.join(os.path.dirname(ylib.__file__), "yamnet.h5"))
        if COUCHE13:
            model = tf.keras.Model(model.inputs, model.outputs + [model.get_layer("layer13/pointwise_conv/relu").output])
        self.run = tf.function(lambda w: model(w), input_signature=[tf.TensorSpec([None], tf.float32)])
        self.c13 = None                                        # fichier de la couche 13 de l'étape en cours
        self.tf = tf
        noms = [l.split(",", 2)[2].strip().strip('"') for l in
                open(os.path.join(os.path.dirname(ylib.__file__), "yamnet_class_map.csv")).read().splitlines()[1:]]
        self.classes_voix = [i for i, n in enumerate(noms) if n in {
            "Speech", "Child speech, kid speaking", "Conversation", "Narration, monologue", "Babbling",
            "Speech synthesizer", "Shout", "Bellow", "Whoop", "Yell", "Children shouting", "Screaming", "Whispering",
            "Singing", "Choir", "Yodeling", "Chant", "Mantra", "Child singing", "Synthetic singing", "Rapping",
            "Humming", "A capella", "Vocal music"}]
        self.x, self.base, self.famille, self.sorte, self.split, self.source, self.clip = [], [], [], [], [], [], []
        self.n = 0

    def ajouter(self, source, famille, sorte, split, son):
        assert sorte is None or FAMILLE_DE_SORTE[sorte] == famille, (sorte, famille)
        if son.size < 160 or float(np.abs(son).max()) < 1e-3:
            return
        sorties = self.run(self.tf.constant(son))
        scores, emb, logmel = sorties[:3]
        emb, logmel, scores = emb.numpy()[:16], logmel.numpy(), scores.numpy()[:16]
        if self.c13 is not None:
            self.c13.write(sorties[3].numpy()[:16].astype(np.float16).tobytes())
        stats = np.stack([stats_logmel(logmel[i * 48: i * 48 + 96]) for i in range(len(emb))])
        self.x.append(np.concatenate([emb, stats], axis=1).astype(np.float16))
        self.base.append(scores[:, self.classes_voix].max(axis=1).astype(np.float16))
        k = len(emb)
        self.famille += [FAMILLES.index(famille)] * k
        self.sorte += [SORTES.index(sorte) if sorte else INCONNUE] * k
        self.split += [split] * k
        self.source += [source] * k
        self.clip += [self.n] * k
        self.n += 1
        if self.n % 500 == 0:
            print("sons", self.n, source, flush=True)

    def voix(self, source, split, son, sorte):
        """Une voix (sorte : Voix lead pour le chant, Voix pour la parole) et 1 ou 2 variantes de production."""
        self.ajouter(source, "voix", sorte, split, son)
        for _ in range(2 if rng.random() < 0.4 else 1):
            v, nom, sorte_variante = variante_voix(son)
            self.ajouter("voix-" + nom, "voix", sorte_variante or sorte, split, v)

    def marque(self):
        return len(self.x), len(self.base), len(self.famille), self.n

    def sauver_etape(self, chemin, marque):
        """Ce qu'une étape a ajouté, gardé à part : une erreur plus loin ne fait pas tout recommencer."""
        ix, ib, it, n = marque
        np.savez_compressed(chemin, x=np.concatenate(self.x[ix:]), base=np.concatenate(self.base[ib:]),
                            famille=np.array(self.famille[it:]), sorte=np.array(self.sorte[it:]),
                            split=np.array(self.split[it:]), source=np.array(self.source[it:]),
                            clip=np.array(self.clip[it:]) - n, n=self.n - n, sortes=np.array(SORTES))

    def charger_etape(self, chemin):
        """Une étape déjà faite. Ses numéros de sorte sont relus avec la liste de sortes qu'elle a gardée (avant
        « Drum loop » et « Fill » : les 42 d'avant) ; les boucles fabriquées, alors « Drums », deviennent des Drum loop."""
        d = np.load(chemin)
        noms = d["sortes"].astype(str).tolist() if "sortes" in d.files else SORTES_42
        sources = d["source"].astype(str)
        sortes = [INCONNUE if k < 0 else SORTES.index(noms[k]) for k in d["sorte"].tolist()]
        sortes = [SORTES.index("drumLoop") if src == "boucle" and k == SORTES.index("drums") else k
                  for src, k in zip(sources, sortes)]
        self.x.append(d["x"])
        self.base.append(d["base"])
        self.famille += d["famille"].tolist()
        self.sorte += sortes
        self.split += d["split"].astype(str).tolist()
        self.source += d["source"].astype(str).tolist()
        self.clip += (d["clip"] + self.n).tolist()
        self.n += int(d["n"])

    def sauver(self):
        chemin = os.path.join(TRAVAIL, "jeu.npz")
        np.savez_compressed(chemin, x=np.concatenate(self.x), base=np.concatenate(self.base),
                            famille=np.array(self.famille), sorte=np.array(self.sorte), split=np.array(self.split),
                            source=np.array(self.source), clip=np.array(self.clip))
        print("fini :", self.n, "sons,", len(self.famille), "tranches →", chemin, flush=True)


# ---------- Jeux de sons ----------

def chants():
    """Chaque chant de VocalSet (8 s au plus) et sa part : quatre chanteurs gardés pour la validation."""
    z = zipfile.ZipFile(os.path.join(D, "vocalset11.zip"))
    noms = sorted(n for n in z.namelist() if n.endswith(".wav") and n.count("/") >= 3
                  and "__MACOSX" not in n and not os.path.basename(n).startswith("._"))
    gardes = {"female2", "female7", "male3", "male9"}
    for n in noms:
        try:
            son = lire(z.read(n))[: SR * 8]
        except Exception:
            continue
        yield son, "val" if n.split("/")[1] in gardes else "train"


def paroles(archive):
    """30 phrases (8 s au plus) par locuteur de LibriSpeech et leur part : un locuteur sur cinq gardé."""
    t = tarfile.open(os.path.join(D, archive))
    par_locuteur = {}
    for m in t:
        if m.name.endswith(".flac"):
            loc = m.name.split("/")[2]
            if len(par_locuteur.setdefault(loc, [])) < 30:
                par_locuteur[loc].append(lire(t.extractfile(m).read())[: SR * 8])
    locs = sorted(par_locuteur)
    gardes = set(locs[::5])
    for loc in locs:
        for son in par_locuteur[loc]:
            yield son, "val" if loc in gardes else "train"


def vocalset(c):
    for son, split in chants():
        c.voix("vocalset", split, son, "vocalLead")


def librispeech(c, archive="librispeech-dev-clean.tar.gz"):
    for son, split in paroles(archive):
        c.voix("librispeech", split, son, "vocal")


def librispeech_test(c):
    """40 autres locuteurs (ceux de test-clean ne sont pas dans dev-clean)."""
    librispeech(c, "librispeech-test-clean.tar.gz")


def hacher(son):
    """Un chop ou un stutter, parfois traité (réverb, hauteur, saturation, téléphone)."""
    x = (chop if rng.random() < 0.5 else stutter)(son)
    return rng.choice([reverb, pitch, saturate, telephone])(x) if rng.random() < 0.4 else x


def voix_hachees(c):
    """Encore des voix hachées (chops, stutters : le plus dur à reconnaître), un chant et une phrase sur deux."""
    sources = [chants(), paroles("librispeech-dev-clean.tar.gz"), paroles("librispeech-test-clean.tar.gz")]
    for source in sources:
        for i, (son, split) in enumerate(source):
            if i % 2 == 0:
                c.ajouter("voix-hachee", "voix", "adlib", split, hacher(son))


def meta_nsynth(archive):
    t = tarfile.open(os.path.join(D, archive))
    return json.load(t.extractfile(next(m for m in t if m.name.endswith("examples.json"))))


def nsynth(c, archive="nsynth-test.tar.gz", notes_max=None):
    """Notes d'instruments NSynth (au plus `notes_max` par instrument), phrases, accords, plucks, arpèges, pads et
    pièges au vibrato faits avec elles ; un instrument sur cinq de nsynth-test gardé pour la validation (les mêmes
    dans toutes les archives : rien de vu à l'apprentissage)."""
    meta = {k: v for k, v in meta_nsynth(archive).items() if v["instrument_family_str"] != "vocal"
            and dans_sa_tessiture(v["instrument_family_str"], v["pitch"])}
    if notes_max:
        par_instrument = {}
        for k in sorted(meta):
            par_instrument.setdefault(meta[k]["instrument_str"], []).append(k)
        meta = {k: meta[k] for cles in par_instrument.values() for k in rng.sample(cles, min(notes_max, len(cles)))}
    t = tarfile.open(os.path.join(D, archive))
    audio = {}
    for m in t:
        if m.name.endswith(".wav") and os.path.basename(m.name)[:-4] in meta:
            audio[os.path.basename(m.name)[:-4]] = lire(t.extractfile(m).read())[: SR * 2]
    gardes = set(sorted({v["instrument_str"] for v in meta_nsynth("nsynth-test.tar.gz").values()})[::5])
    jouer_nsynth(c, [(v["instrument_str"], v["instrument_family_str"], v["instrument_source_str"], audio[cle],
                      "val" if v["instrument_str"] in gardes else "train") for cle, v in meta.items() if cle in audio])


def jouer_nsynth(c, notes, plus=4):
    """Les notes [(instrument, famille NSynth, source, son, part)] telles quelles (parfois à l'envers : un FX), puis,
    par instrument, `plus` phrases, accords, plucks et arpèges (sons de synthé), un pad et des pièges au vibrato."""
    par_inst = {}
    for inst, fam, source, son, split in notes:
        sorte = sorte_nsynth(fam, source)
        famille = FAMILLE_DE_SORTE[sorte]
        par_inst.setdefault((inst, sorte, source, split), []).append(son)
        c.ajouter("nsynth", famille, sorte, split, son)
        if famille == "melodie" and rng.random() < 0.15:       # note à l'envers + réverb : un FX
            c.ajouter("note-envers", "fx", "fx", split, reverb(son[::-1].copy(), rng.uniform(1, 2.5)))
    for (inst, sorte, source, split), notes in par_inst.items():
        famille = FAMILLE_DE_SORTE[sorte]
        for _ in range(plus):                                  # phrases de cet instrument
            parts = [rng.choice(notes)[: int(rng.uniform(0.1, 0.6) * SR)] for _ in range(rng.randint(4, 10))]
            c.ajouter("phrase", famille, sorte, split, norm(np.concatenate(parts)))
        if famille != "melodie":
            continue
        if len(notes) >= 3:                                    # accords (au piano ou à la guitare : leur sorte)
            for _ in range(plus):
                duree = int(rng.uniform(0.4, 1.0) * SR)
                suite = [sum(n[:duree] for n in rng.sample(notes, 3)) for _ in range(rng.randint(1, 3))]
                c.ajouter("accord", "melodie", sorte if sorte in ("piano", "guitar") else "chords", split,
                          norm(np.concatenate(suite)))
        if source != "acoustic":                               # sons de synthé : pluck, arp, pad
            for _ in range(plus):
                c.ajouter("pluck", "melodie", "pluck", split, pluck(rng.choice(notes)))
                c.ajouter("arp", "melodie", "arp", split, arpege(notes))
            if sorte in ("strings", "organ", "lead", "keys", "brass", "flute"):
                note = rng.choice(notes)
                c.ajouter("pad-note", "melodie", "pad", split,
                          reverb(norm(onepole(note * env(len(note), rng.uniform(0.3, 0.8)), 2000)), rng.uniform(1.5, 3)))
        if sorte in ("lead", "flute", "strings", "melody", "brass", "organ", "keys"):
            for _ in range(max(1, plus * 3 // 4)):             # le piège des voix : vibrato
                c.ajouter("vibrato", "melodie", sorte, split, vibrato(rng.choice(notes)))


def nsynth_valid(c):
    """D'autres notes des mêmes instruments (autres hauteurs et forces de jeu), 80 par instrument."""
    nsynth(c, "nsynth-valid.tar.gz", notes_max=80)


URL_NSYNTH_TRAIN = "http://download.magenta.tensorflow.org/datasets/nsynth/nsynth-train.jsonwav.tar.gz"
NOTES_PAR_INSTRUMENT = 16


def flux_tar(url, coupures=None):
    """Les fichiers d'une archive .tar.gz lue au fil du téléchargement (rien n'est gardé sur le disque) :
    (nom, lecture des octets). Une coupure du réseau arrête la lecture, ce qui a été lu sert (notée dans
    `coupures`)."""
    import urllib.request
    try:
        with urllib.request.urlopen(url, timeout=120) as r:
            t = tarfile.open(fileobj=r, mode="r|gz")
            for m in t:
                if m.isfile():
                    yield os.path.basename(m.name), lambda m=m: t.extractfile(m).read()
    except (OSError, EOFError, tarfile.ReadError) as e:
        print("lecture arrêtée :", type(e).__name__, flush=True)
        if coupures is not None:
            coupures.append(e)


def nsynth_train(c):
    """Les ~1000 instruments de nsynth-train (24 Go lus au fil du téléchargement), 16 notes chacun dans sa
    tessiture ; un instrument sur cinq (tiré une fois pour toutes) gardé pour la validation. Les notes arrivent dans
    le désordre : les premières de chaque instrument sont prises au hasard."""
    import zlib
    gardees, vues = {}, set()
    for _ in range(3):                                         # coupure en route : relue, en sautant ce qui est lu
        coupures = []
        for nom, lire_octets in flux_tar(URL_NSYNTH_TRAIN, coupures):
            if not nom.endswith(".wav") or nom in vues:
                continue
            vues.add(nom)
            inst, note, _ = nom[:-4].rsplit("-", 2)           # famille_source_NNN-hauteur-force
            parts = inst.split("_")
            fam, source = "_".join(parts[:-2]), parts[-2]
            liste = gardees.setdefault(inst, [])
            if fam == "vocal" or len(liste) >= NOTES_PAR_INSTRUMENT or not dans_sa_tessiture(fam, int(note)):
                continue
            liste.append((fam, source, lire(lire_octets())[: SR * 2].astype(np.float16)))
        if not coupures:
            break
    print("nsynth-train :", len(gardees), "instruments", flush=True)
    jouer_nsynth(c, [(inst, fam, source, son.astype(np.float32), "val" if zlib.crc32(inst.encode()) % 5 == 0
                      else "train") for inst, liste in gardees.items() for fam, source, son in liste], plus=2)


URL_MEDLEY = "https://zenodo.org/api/records/3464194/files/Medley-solos-DB.tar.gz/content"
URL_MEDLEY_META = "https://zenodo.org/api/records/3464194/files/Medley-solos-DB_metadata.csv/content"
SORTES_MEDLEY = {"clarinet": "melody", "distorted electric guitar": "guitar", "flute": "flute", "piano": "piano",
                 "tenor saxophone": "melody", "trumpet": "brass", "violin": "strings"}
EXTRAITS_MEDLEY = 1200


def medley(c):
    """Medley-solos-DB (Lostanlen et al., 2019, CC BY 4.0) : extraits de 3 s de vrais morceaux, une chanteuse ou un
    instrument seul (7,9 Go lus au fil du téléchargement). Toutes les chanteuses (et une voix hachée sur deux),
    1200 extraits au plus par instrument, tirés dans les deux collections ; un morceau sur cinq gardé pour la
    validation."""
    import csv
    import io
    import urllib.request
    meta = {m["uuid4"]: m for m in csv.DictReader(io.StringIO(
        urllib.request.urlopen(URL_MEDLEY_META, timeout=120).read().decode()))}
    total = {}
    for m in meta.values():
        total[m["instrument"]] = total.get(m["instrument"], 0) + 1
    vus = set()
    for _ in range(3):                                         # coupure en route : relue, en sautant ce qui est lu
        coupures = []
        for nom, lire_octets in flux_tar(URL_MEDLEY, coupures):
            v = meta.get(nom[:-4].split("_")[-1]) if nom.endswith(".wav") and not nom.startswith("._") else None
            if v is None or v["uuid4"] in vus:
                continue
            vus.add(v["uuid4"])
            medley_extrait(c, v, total, lire_octets)
        if not coupures:
            break


def medley_extrait(c, v, total, lire_octets):
    """Un extrait de Medley-solos-DB : une chanteuse (et parfois sa voix hachée), ou un instrument tiré au sort."""
    import zlib
    chanteuse = v["instrument"] == "female singer"
    tirage = zlib.crc32(v["uuid4"].encode()) % 10000 / 10000
    if not chanteuse and tirage >= EXTRAITS_MEDLEY / total[v["instrument"]]:
        return
    split = "val" if zlib.crc32(f"{v['subset']}-{v['song_id']}".encode()) % 5 == 0 else "train"
    son = lire(lire_octets())
    if chanteuse:
        c.voix("medley-voix", split, son, "vocalLead")
        if tirage < 0.5:
            c.ajouter("voix-hachee", "voix", "adlib", split, hacher(son))
    else:
        c.ajouter("medley-instrument", "melodie", SORTES_MEDLEY[v["instrument"]], split, son)


def dans_sa_tessiture(famille, note):
    """Note NSynth gardée si elle sonne comme sa famille en production : une basse jusqu'au sol 3 (MIDI 55), une
    mélodie du sol 2 au do 7 (MIDI 43 à 96) ; plus grave, une note de piano sonne comme une basse, plus aiguë comme un
    sifflement (essai : des mélodies trop graves prises pour des basses)."""
    return 24 <= note <= 55 if famille == "bass" else 43 <= note <= 96


def sorte_nsynth(famille, source):
    """Sorte de l'aperçu pour un instrument NSynth (famille et source de NSynth)."""
    if famille == "keyboard":
        return "piano" if source == "acoustic" else "keys"
    return {"bass": "bass", "brass": "brass", "flute": "flute", "guitar": "guitar", "mallet": "bell",
            "organ": "organ", "reed": "melody", "string": "strings", "synth_lead": "lead"}[famille]


MOTIFS = {"kick": r"kick|\bbd\b|bassdrum|bass drum|\bkik\b|kck", "snare": r"snare|\bsd\b|snr",
          "clap": r"clap|clp", "rim": r"\brim|side ?stick|cross ?stick", "snap": r"snap",
          "openHat": r"open ?(hi ?)?hat|open ?hh|\bohh?\b", "hiHat": r"hi ?hat|\bc?hh\b|hats?\b",
          "perc": r"perc|conga|bongo|cowbell|clave|block|djembe|timbale|cajon|triangle|agogo|guiro",
          "tom": r"\btoms?\b|floor ?tom", "shaker": r"shaker|tamb|maraca|cabasa", "crash": r"crash",
          "ride": r"\bride\b", "cymbal": r"cymbal|splash|china|\bcym\b"}
# Un mot plus précis l'emporte : « open hi-hat » est un Open Hat, « crash cymbal » un Crash, « snare rim » un Rim.
CACHES = {"openHat": "hiHat", "crash": "cymbal", "ride": "cymbal", "rim": "snare"}


def sorte_du_nom(nom):
    """Sorte d'un son de batterie d'après son nom Freesound ; None s'il n'en dit rien ou en dit deux."""
    nom = nom.lower().replace("_", " ").replace("-", " ")
    trouvees = {s for s, m in MOTIFS.items() if re.search(m, nom)}
    trouvees -= {CACHES[s] for s in trouvees if s in CACHES}
    return trouvees.pop() if len(trouvees) == 1 else None


def batterie(c):
    lic = json.load(open(os.path.join(D, "oneshot-licenses.txt")))
    libres = {k: v for k, v in lic.items()
              if "publicdomain/zero" in v["license"] or "/licenses/by/" in v["license"]}
    z = zipfile.ZipFile(os.path.join(D, "oneshot.zip"))
    noms = [n for n in z.namelist() if n.endswith(".wav") and os.path.basename(n)[:-4] in libres]
    rng.shuffle(noms)
    sans_nom = 0
    pool = {"train": [], "val": []}
    for i, n in enumerate(noms):
        cle = os.path.basename(n)[:-4]
        sorte = sorte_du_nom(libres[cle]["name"])
        if sorte is None:
            sans_nom += 1
            if sans_nom > 2500:                                # assez de sons « drums » sans sorte
                continue
        split = "val" if i % 5 == 0 else "train"
        try:
            son = lire(z.read(n))[: SR * 3]
        except Exception:
            continue
        pool[split].append(son[:SR])
        c.ajouter("batterie", "drums", sorte, split, son)
        if sorte in ("openHat", "crash", "ride", "cymbal") and rng.random() < 0.4:   # cymbale à l'envers : un Riser
            c.ajouter("cymbale-envers", "fx", "riser", split, reverb(son[::-1].copy(), rng.uniform(1, 2.5)))
    for split, nb in (("train", 400), ("val", 100)):           # boucles de batterie
        for _ in range(nb):
            step = int(SR * 60 / rng.uniform(80, 160) / 4)
            boucle = np.zeros(step * 32, np.float32)
            for k in range(32):
                if rng.random() < 0.45:
                    s = rng.choice(pool[split])[: step * 2]
                    fin = min(len(boucle), k * step + len(s))
                    boucle[k * step: fin] += s[: fin - k * step]
            c.ajouter("boucle", "drums", "drumLoop", split, norm(boucle))


def fabriques(c):
    for split, nb in (("train", 700), ("val", 200)):
        for _ in range(nb):
            c.ajouter("808", "basse", "bass808", split, synth_808())
            c.ajouter("basse-synth", "basse", "bass", split, synth_basse())
            fx, sorte = synth_fx()
            c.ajouter("fx", "fx", sorte, split, fx)
        for _ in range(nb // 2):
            c.ajouter("sub", "basse", "sub", split, synth_sub())
            c.ajouter("reese", "basse", "reese", split, synth_reese())
            c.ajouter("pad", "melodie", "pad", split, synth_pad())
            c.ajouter("clap-synth", "drums", "clap", split, synth_clap())
            c.ajouter("hihat-synth", "drums", "hiHat", split, synth_hihat(False))
            c.ajouter("openhat-synth", "drums", "openHat", split, synth_hihat(True))
        for _ in range(nb // 4):
            c.ajouter("pluck-synth", "melodie", "pluck", split, pluck(rng.choice(notes_synth(0.5))))
            c.ajouter("arp-synth", "melodie", "arp", split, arpege(notes_synth(0.2)))
            accords = [sum(notes_synth(rng.uniform(0.3, 0.9))) for _ in range(rng.randint(1, 4))]
            n = min(len(a) for a in accords)
            c.ajouter("accords-synth", "melodie", "chords", split, norm(np.concatenate([a[:n] for a in accords])))
            c.ajouter("snap-synth", "drums", "snap", split, synth_snap())
            c.ajouter("shaker-synth", "drums", "shaker", split, synth_shaker())
            c.ajouter("crash-synth", "drums", "crash", split, synth_crash())



# Groove MIDI Dataset (Magenta, CC BY 4.0) : 13,6 h de vrais batteurs sur une batterie électronique, chaque
# enregistrement noté « beat » (une boucle) ou « fill ». Demande du propriétaire (24/10) : les sortes « Drum loop » et
# « Fill ».
GROOVE = "groove-v1.0.0.zip"


def saturer(x):
    """Variante de production d'un son de batterie : saturation douce, parfois une réverbération courte."""
    y = np.tanh(x * rng.uniform(1.5, 4.0)).astype(np.float32)
    if rng.random() < 0.4:
        y = reverb(y, rng.uniform(0.3, 1.2))
    return norm(y)


def groove(c):
    """Boucles (2 à 3 extraits d'une, 1, 2 ou 4 mesures) et fills des batteurs du Groove MIDI Dataset."""
    import csv
    import io as _io
    chemin = os.path.join(D, GROOVE)
    if not os.path.exists(chemin):
        print("groove : archive absente, étape sautée", flush=True)
        return
    z = zipfile.ZipFile(chemin)
    lignes = list(csv.DictReader(_io.StringIO(z.read("groove/info.csv").decode())))
    for ligne in lignes:
        if not ligne["audio_filename"]:
            continue
        split = "train" if ligne["split"] == "train" else "val"
        try:
            son = lire(z.read("groove/" + ligne["audio_filename"]))
        except Exception:
            continue
        num, den = (int(v) for v in ligne["time_signature"].split("-"))
        temps = num if den == 4 else num / 2
        mesure = int(SR * 60 / float(ligne["bpm"]) * temps)
        if ligne["beat_type"] == "fill":
            sons = [son[: SR * 8]]
            source = "groove-fill"
            sorte = "fill"
        else:
            sons = []
            for k, mesures in enumerate(rng.sample([1, 2, 4], 3 if len(son) > mesure * 8 else 2)):
                debut = int((len(son) - mesure * mesures) * (k + 0.5) / 3)
                if debut >= 0:
                    sons.append(son[debut: debut + mesure * mesures])
            source = "groove-boucle"
            sorte = "drumLoop"
        for x in sons:
            c.ajouter(source, "drums", sorte, split, norm(x))
            if split == "train" and rng.random() < 0.5:
                c.ajouter(source + "+prod", "drums", sorte, split, saturer(x))


# Kits du propriétaire (FLS_IA_KITS : dossier de ses packs ; demande du 24/10 : « tu lui montres les sons du drive et
# tu lui expliques que là ça s'appelle comme ça »). La sorte vient des noms des dossiers et du fichier. Des packs entiers
# sont gardés pour la vérification, jamais appris : l'IA est notée sur des packs qu'elle n'a jamais entendus.
MOTS_NON_DRUMS = r"melod|melody|piano|guitar|keys|synth|vocal|\bvox\b|\b808|bass|pluck|\bpad|chord|string|\bbell"
MOTS_FX = {"riser": r"\briser|uplifter", "downlifter": r"downlifter|\bdowner", "impact": r"\bimpact|\bboom\b",
           "sweep": r"\bsweep"}


def sorte_du_texte(texte, type_du_son=False):
    """(famille, sorte) d'après un texte (chemin, nom, ou type du son avant « -- ») ; None si rien de sûr."""
    texte = texte.replace("_", " ").replace("-", " ")
    nom = os.path.basename(texte)
    if re.search(r"\bfills?\b|drumfill|drum fill", texte):
        return "drums", "fill"
    if re.search(r"\bs?fx\b|\btextures?\b", nom):
        return "fx", next((s for s, m in MOTS_FX.items() if re.search(m, nom)), "fx")
    if re.search(r"loops?\b|drumloop|break ?beat", texte):
        return None if re.search(MOTS_NON_DRUMS, texte) else ("drums", "drumLoop")
    if re.search(r"\b808", nom):
        return "basse", "bass808"
    if type_du_son and re.search(r"\b(low|sub)\b", nom):     # « LOW -- NOM (C) » : un son grave, pas forcément une 808
        return "basse", None
    sorte = sorte_du_nom(nom) or sorte_du_nom(texte)
    return ("drums", sorte) if sorte else None


def sorte_du_kit(chemin):
    """(famille, sorte) d'un son de kit d'après son chemin. Le nom du son d'abord : « © KICK -- NOM », son type avant
    « -- » (« TEXTURE -- NOMLOOP » est une texture, pas une boucle ; « LOW -- NOM (C) », un son grave), puis le nom
    entier ; ses dossiers seulement s'il ne dit rien, du plus proche au plus loin, et jamais un dossier mélangé
    (« fill + chop » : des fills ET des chops, 24/10 : « il n'y a pas que des fills et drumloops dans le drive »)."""
    nom = os.path.basename(chemin).lower()
    if " -- " in nom:
        quoi = sorte_du_texte(nom.split(" -- ")[0], type_du_son=True)
        if quoi:
            return quoi
    quoi = sorte_du_texte(nom)
    if quoi:
        return quoi
    dossier = os.path.dirname(chemin.lower())
    while dossier and dossier != ".":
        dernier = os.path.basename(dossier)
        if re.search(r"\+|&|\band\b|\bet\b", dernier):
            return None
        quoi = sorte_du_texte(dernier)
        if quoi:
            return quoi
        dossier = os.path.dirname(dossier)
    return None


def grave(son):
    """Part de l'énergie sous 150 Hz."""
    spectre = np.abs(np.fft.rfft(son)) ** 2
    f = np.fft.rfftfreq(len(son), 1 / SR)
    return float(spectre[f < 150].sum() / max(spectre.sum(), 1e-12))


def packs_des_kits(fichiers):
    """Pack de chaque son : son dossier du premier niveau ; un son posé seul à la racine va avec ceux qui partagent
    les mêmes mots (« Drum Loop - Nom 140BPM @Marque » : drum loop marque)."""
    mots = {f: set(re.findall(r"[a-z]+", f.lower())) for r, f in fichiers if r == "."}
    frequence = Counter(m for ms in mots.values() for m in ms)
    packs = []
    for relatif, f in fichiers:
        if relatif != ".":
            packs.append(relatif.split(os.sep)[0])
        else:
            communs = sorted(m for m in mots[f] if frequence[m] >= 3)
            packs.append(" ".join(communs) or f)
    return packs


def packs_de_verification(sortes_par_pack):
    """Packs gardés pour la vérification : pour chaque sorte principale, un pack sur quatre (le 2e, le 6e…) dans un
    ordre fixe ; une sorte d'un seul pack est toute apprise."""
    import zlib
    par_sorte = defaultdict(list)
    for pack, sortes in sortes_par_pack.items():
        par_sorte[sortes.most_common(1)[0][0]].append(pack)
    verification = set()
    for packs in par_sorte.values():
        packs.sort(key=lambda p: zlib.crc32(p.encode()))
        verification.update(p for i, p in enumerate(packs) if i % 4 == 1)
    return verification


def sons_des_kits():
    """Sons des packs du propriétaire : (chemin, pack, (famille, sorte) ou None, split). [] sans FLS_IA_KITS.
    FLS_IA_KITS_VERIF=0 : tous les packs appris (version livrée, chiffres mesurés avant avec des packs gardés)."""
    import hashlib
    racine = os.environ.get("FLS_IA_KITS")
    if not racine or not os.path.isdir(racine):
        return []
    fichiers, empreintes = [], set()
    for dossier, sous, noms in os.walk(racine):
        sous.sort()
        relatif = os.path.relpath(dossier, racine)
        for f in sorted(noms):
            if not f.lower().endswith((".wav", ".aif", ".aiff", ".flac", ".mp3", ".ogg")):
                continue
            with open(os.path.join(dossier, f), "rb") as fh:
                empreinte = hashlib.md5(fh.read()).hexdigest()
            if empreinte in empreintes:                    # le même son dans deux dossiers : appris une fois
                continue
            empreintes.add(empreinte)
            fichiers.append((relatif, f))
    packs = packs_des_kits(fichiers)
    sortes = [sorte_du_kit(os.path.join(r, f)) for r, f in fichiers]
    sortes_par_pack = defaultdict(Counter)
    for pack, quoi in zip(packs, sortes):
        if quoi:
            sortes_par_pack[pack][quoi[1]] += 1
    verification = set() if os.environ.get("FLS_IA_KITS_VERIF") == "0" else packs_de_verification(sortes_par_pack)
    print("kits du propriétaire :", len(sortes_par_pack), "packs,", len(verification), "gardés pour la vérification",
          flush=True)
    return [(os.path.join(racine, r, f), pack, quoi, "val" if pack in verification else "train")
            for (r, f), pack, quoi in zip(fichiers, packs, sortes)]


def kits_proprietaire(c):
    sons = sons_des_kits()
    if not sons:
        print("kits du propriétaire : FLS_IA_KITS absent, étape sautée", flush=True)
        return
    vus = Counter()
    for chemin, _, quoi, split in sons:
        if quoi is None:
            continue
        try:
            son = lire(chemin)[: SR * 8]
        except Exception:
            continue
        famille, sorte = quoi
        if famille == "basse" and grave(son) < 0.6:                # « basse » d'après le nom mais pas grave : écarté
            vus[("pas grave", split)] += 1
            continue
        source = "kit-" + {"fill": "fill", "drumLoop": "boucle"}.get(sorte, "oneshot")
        c.ajouter(source, famille, sorte, split, son)
        vus[(sorte or famille, split)] += 1
        if split == "train" and sorte in ("fill", "drumLoop") and rng.random() < 0.5:
            c.ajouter(source + "+prod", famille, sorte, split, saturer(son))
    print("kits du propriétaire :", sum(vus.values()), "sons", dict(sorted(vus.items())), flush=True)


# Boucles et fills de style trap (24/10 : les boucles trap du propriétaire passaient pour des voix hachées — rolls de
# hats rapides —, ses fills courts pour des boucles). Faits avec les sons seuls des packs appris (ou fabriqués), pour
# l'apprentissage seulement : la vérification reste sur les packs gardés.
def synth_kick():
    n = int(rng.uniform(0.15, 0.5) * SR)
    t = np.arange(n) / SR
    f = rng.uniform(45, 70) * (1 + rng.uniform(2, 6) * np.exp(-t * rng.uniform(25, 60)))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.001, rng.uniform(0.06, 0.25))
    return norm(np.tanh(x * rng.uniform(1, 4)))


def coups_trap(sons):
    """Sons seuls par sorte (kick, snare, clap, hiHat, openHat, perc, tom) : ceux des packs appris, sinon fabriqués."""
    coups = defaultdict(list)
    for chemin, _, quoi, split in sons:
        if split == "train" and quoi and quoi[1] in ("kick", "snare", "clap", "hiHat", "openHat", "perc", "tom"):
            try:
                coups[quoi[1]].append(lire(chemin)[:SR])
            except Exception:
                pass
    fabriques = {"kick": synth_kick, "snare": synth_clap, "clap": synth_clap, "hiHat": lambda: synth_hihat(False),
                 "openHat": lambda: synth_hihat(True), "perc": synth_snap, "tom": synth_kick}
    for sorte, fabrique in fabriques.items():
        while len(coups[sorte]) < 8:
            coups[sorte].append(fabrique())
    return coups


def poser(piste, son, debut, gain=1.0):
    if debut >= len(piste):
        return
    fin = min(len(piste), debut + len(son))
    piste[debut:fin] += son[: fin - debut] * gain


def boucle_trap(coups):
    """2 mesures à 130–185 BPM (snare au 3e temps), hats en croches ou doubles avec des rolls (1/32, triolets),
    808 sur les kicks parfois ; répétées jusqu'à ≈ 8 s."""
    temps = 60 / rng.uniform(130, 185) * SR
    double = temps / 4
    n = int(temps * 8)
    x = np.zeros(n, np.float32)
    kick, snare, hat = rng.choice(coups["kick"]), rng.choice(coups["snare"] + coups["clap"]), rng.choice(coups["hiHat"])
    kicks = [0] + sorted(rng.sample([2, 3, 6, 7, 10, 11, 14, 15], rng.randint(1, 4)))
    avec_808 = rng.random() < 0.4
    for mesure in range(2):
        base = mesure * 16
        for k in kicks:
            poser(x, kick, int((base + k) * double))
            if avec_808:
                poser(x, synth_808()[: int(double * 3)], int((base + k) * double), 0.7)
        poser(x, snare, int((base + 8) * double))
        if rng.random() < 0.3:
            poser(x, rng.choice(coups["clap"]), int((base + 8) * double), 0.6)
        pas_hat = rng.choice([1, 2])                           # doubles ou croches
        k = 0
        while k < 16:
            if rng.random() < 0.18:                            # roll : un temps coupé en 6, 8 ou 12
                parts = rng.choice([6, 8, 12])
                for j in range(parts):
                    poser(x, hat[: int(temps / parts)], int((base + k) * double + j * temps / parts),
                          rng.uniform(0.4, 1.0))
                k += 4
                continue
            poser(x, hat, int((base + k) * double), rng.uniform(0.5, 1.0))
            k += pas_hat
        if rng.random() < 0.4:
            poser(x, rng.choice(coups["openHat"]), int((base + rng.choice([6, 14])) * double), 0.6)
        if rng.random() < 0.4:
            poser(x, rng.choice(coups["perc"]), int((base + rng.choice([3, 5, 11, 13])) * double), 0.6)
    boucle = np.tile(x, int(np.ceil(8 * SR / n)))[: 8 * SR]
    return norm(saturer(boucle) if rng.random() < 0.4 else boucle)


def fill_trap(coups):
    """1 à 4 temps : roll de snare, de hats ou de toms qui accélère (et monte), souvent de plus en plus fort."""
    temps = 60 / rng.uniform(130, 185) * SR
    n = int(temps * rng.choice([1, 2, 2, 3, 4]))
    x = np.zeros(n, np.float32)
    sorte = rng.choice(["snare", "snare", "tom", "hiHat", "clap", "perc"])
    son = rng.choice(coups[sorte])
    pos, ecart = 0.0, temps / rng.choice([2, 4])
    fin_ecart = temps / rng.choice([8, 12, 16])
    melange = rng.random() < 0.3                               # kick et snare mêlés
    while pos < n:
        avance = pos / n
        coup = rng.choice(coups["kick"]) if melange and rng.random() < 0.3 else son
        if sorte == "tom":
            coup = pitch(coup, rng.uniform(-7, 7) * (1 - 2 * avance))
        poser(x, coup[: int(ecart * 1.5)], int(pos), 0.3 + 0.7 * avance if rng.random() < 0.7 else 1.0)
        pos += ecart
        ecart = max(fin_ecart, ecart * rng.uniform(0.8, 0.95))
    if rng.random() < 0.3:
        x = reverb(x, rng.uniform(0.3, 1.0))
    return norm(saturer(x) if rng.random() < 0.3 else x)


def trap(c):
    sons = sons_des_kits()
    coups = coups_trap(sons)
    for _ in range(600):
        c.ajouter("trap-boucle", "drums", "drumLoop", "train", boucle_trap(coups))
    for _ in range(600):
        c.ajouter("trap-fill", "drums", "fill", "train", fill_trap(coups))
    print("trap : 600 boucles, 600 fills (", ", ".join(f"{k} {len(v)}" for k, v in coups.items()), ")", flush=True)


ETAPES = (vocalset, librispeech, librispeech_test, voix_hachees, nsynth, nsynth_valid, nsynth_train, medley, batterie,
          fabriques, groove, kits_proprietaire, trap)


def main():
    c = Collecte()
    for etape in ETAPES:
        chemin = os.path.join(TRAVAIL, f"etape_{etape.__name__}.npz")
        c13 = chemin[:-4] + ".c13"
        if os.path.exists(chemin):                             # déjà faite (relance après une erreur)
            if COUCHE13 and not os.path.exists(c13):
                raise SystemExit(f"{chemin} n'a pas la couche 13 : enlève les etape_*.npz et recommence")
            c.charger_etape(chemin)
        else:
            marque = c.marque()
            if COUCHE13:
                c.c13 = open(c13 + ".part", "wb")
            etape(c)
            if COUCHE13:
                c.c13.close()
                c.c13 = None
                os.replace(c13 + ".part", c13)
            if c.marque() == marque:                            # rien d'ajouté (données absentes) : refaite plus tard
                print("·", etape.__name__, "rien à ajouter", flush=True)
                continue
            c.sauver_etape(chemin, marque)
        print("✓", etape.__name__, c.n, "sons", flush=True)
    c.sauver()


if __name__ == "__main__":
    main()
