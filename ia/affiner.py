"""Réapprend la dernière couche de YAMNet (layer14) sur nos sons, avec une tête famille + sorte : YAMNet a appris
sur des sons du quotidien (AudioSet), pas à séparer une note grave de piano d'une basse, ni un synthé étrange d'un
FX. Lit la sortie de la couche 13 gardée par la préparation (FLS_IA_COUCHE13=1 : etape_*.c13), apprend la couche 14
(les normalisations restent celles de YAMNet), puis écrit :
  - TRAVAIL/couche14.npz : ses poids, que exporter.py met à la place de ceux de YAMNet ;
  - TRAVAIL/jeu_affine.npz : le jeu d'apprentissage avec les empreintes de la couche réapprise, pour entrainer.py.
Usage (après preparer.py avec FLS_IA_COUCHE13=1) :
  python ia/affiner.py
  FLS_IA_JEU=jeu_affine.npz python ia/entrainer.py && python ia/exporter.py && python ia/essais_app.py"""
import os

import numpy as np

import entrainer as E
from commun import FAMILLES, INCONNUE, SORTES, TRAVAIL, charger_yamnet

# Les couches de la couche 14 dans l'ordre de YAMNet ; celles qui ont des poids sont réapprises (normalisations figées).
ORDRE14 = ["layer14/depthwise_conv", "layer14/depthwise_conv/bn", "layer14/depthwise_conv/relu",
           "layer14/pointwise_conv", "layer14/pointwise_conv/bn", "layer14/pointwise_conv/relu"]
COUCHE14 = [nom for nom in ORDRE14 if not nom.endswith("/relu")]
FORME13 = (3, 2, 1024)


def parts13():
    """Sorties de la couche 13 de chaque étape (lues sur le disque au besoin), dans l'ordre du jeu."""
    import preparer
    parts = []
    for etape in preparer.ETAPES:
        base = os.path.join(TRAVAIL, f"etape_{etape.__name__}")
        n = len(np.load(base + ".npz")["famille"])
        parts.append(np.memmap(base + ".c13", dtype=np.float16, mode="r", shape=(n, *FORME13)))
    return parts


def couche13():
    """Sorties de la couche 13 de toutes les tranches, en mémoire (environ 4,5 Go)."""
    return np.concatenate(parts13())


def yamnet():
    """YAMNet de Google, avec ses poids (ses couches 14 servent de départ)."""
    yparams, ylib = charger_yamnet()
    m = ylib.yamnet_frames_model(yparams.Params())
    m.load_weights(os.path.join(os.path.dirname(ylib.__file__), "yamnet.h5"))
    return m


def poser_couche14(modele, chemin=os.path.join(TRAVAIL, "couche14.npz")):
    """Met les poids de la couche réapprise dans un modèle qui contient YAMNet (exporter.py) ; faux s'il n'y en a pas."""
    if not os.path.exists(chemin):
        return False
    poids = np.load(chemin)
    for nom in COUCHE14:
        couche = modele.get_layer(nom)
        couche.set_weights([poids[f"{nom}:{i}"] for i in range(len(couche.get_weights()))])
    return True


def apprendre():
    """Apprend la couche 14 avec une tête famille + sorte, puis écrit ses poids (couche14.npz)."""
    import tensorflow as tf
    tf.keras.utils.set_random_seed(7)
    x, famille, sorte, split, source, clip, base = E.charger(corrections=False)
    c13 = couche13()
    assert len(c13) == len(x), (len(c13), len(x))
    tr, va = split == "train", split == "val_a"
    mu, sigma = x[tr].mean(axis=0), x[tr].std(axis=0) + 1e-6
    stats = ((x[:, 1024:] - mu[1024:]) / sigma[1024:]).astype(np.float32)

    # Mêmes poids que entrainer.py : chaque son compte autant qu'un chop (1/√n), chaque famille et chaque sorte connue
    # pèsent autant.
    w_son = 1 / np.sqrt(np.bincount(clip)[clip])
    connue = sorte != INCONNUE

    def equilibre(classes, garde, nb):
        total = np.bincount(classes[tr & garde], weights=w_son[tr & garde], minlength=nb)
        return np.where(garde, w_son * (total.sum() / (nb * np.maximum(total, 1e-9)))[np.maximum(classes, 0)], 0.0)
    w_famille = equilibre(famille, np.ones_like(connue), len(FAMILLES))
    w_sorte = equilibre(sorte, connue, len(SORTES))
    w_famille /= w_famille[tr].mean()
    w_sorte /= w_sorte[tr & connue].mean()
    y_sorte = np.maximum(sorte, 0)

    # La couche 14 de YAMNet (mêmes objets : ses poids s'apprennent), ses normalisations figées.
    y = yamnet()
    couches = [y.get_layer(nom) for nom in COUCHE14]
    for couche in couches:
        couche.trainable = not couche.name.endswith("/bn")
    entree = tf.keras.layers.Input(shape=FORME13, name="couche13")
    h = entree
    for nom in ORDRE14:
        h = y.get_layer(nom)(h)
    empreinte = tf.keras.layers.GlobalAveragePooling2D(name="empreinte")(h)
    norme = tf.keras.layers.Lambda(lambda e: (e - mu[:1024]) / sigma[:1024], name="norme")(empreinte)
    mesures = tf.keras.layers.Input(shape=(192,), name="spectre")
    famille_p, sorte_p = E.branche(tf.keras.layers.Concatenate()([norme, mesures]), abandon=0.4)
    m = tf.keras.Model([entree, mesures], [famille_p, sorte_p])
    m.compile(optimizer=tf.keras.optimizers.Adam(3e-4),
              loss={"famille": "sparse_categorical_crossentropy", "sorte": "sparse_categorical_crossentropy"})

    class Lots(tf.keras.utils.Sequence):
        def __init__(self, indices, melange):
            self.indices, self.melange = indices, melange

        def __len__(self):
            return int(np.ceil(len(self.indices) / 512))

        def __getitem__(self, k):
            i = np.sort(self.indices[k * 512:(k + 1) * 512])
            return ({"couche13": c13[i].astype(np.float32), "spectre": stats[i]},
                    {"famille": famille[i], "sorte": y_sorte[i]},
                    {"famille": w_famille[i], "sorte": w_sorte[i]})

        def on_epoch_end(self):
            if self.melange:
                np.random.shuffle(self.indices)

    apprentissage = Lots(np.flatnonzero(tr), True)
    np.random.shuffle(apprentissage.indices)
    m.fit(apprentissage, validation_data=Lots(np.flatnonzero(va), False), epochs=40, verbose=2,
          callbacks=[tf.keras.callbacks.EarlyStopping(monitor="val_famille_loss", patience=5,
                                                      restore_best_weights=True),
                     tf.keras.callbacks.ReduceLROnPlateau(monitor="val_famille_loss", factor=0.5, patience=2)])

    np.savez(os.path.join(TRAVAIL, "couche14.npz"),
             **{f"{c.name}:{i}": w for c in couches for i, w in enumerate(c.get_weights())})
    print("couche 14 réapprise →", os.path.join(TRAVAIL, "couche14.npz"), flush=True)


def ecrire_jeu():
    """Le jeu avec les empreintes de la couche réapprise à la place de celles de YAMNet (le reste ne change pas),
    étape par étape pour tenir en mémoire (le faire d'un coup après l'apprentissage dépassait 15 Go)."""
    import tensorflow as tf
    y = yamnet()
    assert poser_couche14(y)
    entree = tf.keras.layers.Input(shape=FORME13, name="couche13")
    h = entree
    for nom in ORDRE14:
        h = y.get_layer(nom)(h)
    vers_empreinte = tf.keras.Model(entree, tf.keras.layers.GlobalAveragePooling2D()(h))
    d = dict(np.load(os.path.join(TRAVAIL, "jeu.npz")))
    debut = 0
    for part in parts13():
        for k in range(0, len(part), 4096):
            lot = vers_empreinte.predict(np.asarray(part[k:k + 4096], dtype=np.float32), verbose=0)
            d["x"][debut + k:debut + k + len(lot), :1024] = lot.astype(np.float16)
        debut += len(part)
    assert debut == len(d["x"]), (debut, len(d["x"]))
    np.savez_compressed(os.path.join(TRAVAIL, "jeu_affine.npz"), **d)
    print("jeu →", os.path.join(TRAVAIL, "jeu_affine.npz"), flush=True)


def main():
    if os.path.exists(os.path.join(TRAVAIL, "couche14.npz")):  # déjà apprise (relance) : enlève-la pour recommencer
        print("couche 14 déjà réapprise : jeu seulement", flush=True)
    else:
        apprendre()
    ecrire_jeu()


if __name__ == "__main__":
    main()
