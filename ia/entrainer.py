"""Apprend les deux têtes (famille, sorte) sur TRAVAIL/jeu.npz, règle le seuil des voix et mesure le tout sur des
sons jamais vus. Sortie : TRAVAIL/tete.weights.h5 + TRAVAIL/tete.json (normalisation, seuil), et ia/RESULTATS.md.

Jugement d'un son (comme dans l'app) : la famille est la moyenne des tranches ; mais c'est une voix dès que sa
tranche la plus « voix » dépasse le seuil (un chop ou une phrase entourée de silence reste une voix). Le seuil est le
plus bas qui garde au plus 2 % des autres sons pris pour des voix (validation A) ; les chiffres sont donnés sur la
validation B (chanteurs, locuteurs, instruments et sons de batterie que l'apprentissage n'a jamais entendus).
Usage : python ia/entrainer.py"""
import json
import os

import numpy as np

from commun import FAMILLE_DE_SORTE, FAMILLES, ICI, INCONNUE, NOMS, SORTES, TRAVAIL

FAUX_VOIX_MAX = 0.02
COUCHES = [512, 256]             # tête : deux couches (essais : mieux qu'une seule, de 512 ou 1024)
TETES = 5                        # têtes apprises chacune de leur côté, moyennées : l'avis ne dépend plus du hasard
PART_MIN = 0.5                   # une sorte n'est donnée que si elle l'emporte nettement dans sa famille (comme l'app)


def charger(corrections=True):
    """Le jeu d'apprentissage (FLS_IA_JEU, par défaut jeu.npz ; jeu_affine.npz après affiner.py) et, si
    `corrections`, les corrections des utilisateurs."""
    d = np.load(os.path.join(TRAVAIL, os.environ.get("FLS_IA_JEU", "jeu.npz")))
    x = d["x"].astype(np.float32)
    clip = d["clip"]
    split = d["split"].astype(str)
    # Validation coupée en deux par son : A (arrêt de l'apprentissage, seuil), B (chiffres annoncés).
    split = np.where(split == "val", np.where(clip % 2 == 0, "val_a", "val_b"), split)
    famille, sorte, source, base = d["famille"], d["sorte"], d["source"].astype(str), d["base"].astype(np.float32)
    # Corrections des utilisateurs (ia/corrections.py), s'il y en a : apprises comme des sons de plus.
    chemin = os.path.join(TRAVAIL, "corrections.npz")
    if corrections and os.path.exists(chemin):
        c = np.load(chemin)
        n = len(c["famille"])
        x = np.concatenate([x, c["x"].astype(np.float32)])
        famille, sorte = np.concatenate([famille, c["famille"]]), np.concatenate([sorte, c["sorte"]])
        clip = np.concatenate([clip, c["clip"] + clip.max() + 1])
        split = np.concatenate([split, np.full(n, "train")])
        source = np.concatenate([source, np.full(n, "corrections")])
        base = np.concatenate([base, np.zeros(n, np.float32)])
        print("corrections des utilisateurs :", c["clip"].max() + 1, "sons", flush=True)
    return x, famille, sorte, split, source, clip, base


def branche(x, suffixe="", abandon=0.0):
    """Une tête : couches cachées puis probabilités de famille et de sorte (couches nommées avec `suffixe`)."""
    import tensorflow as tf
    h = x
    for k, n in enumerate(COUCHES):
        h = tf.keras.layers.Dense(n, activation="relu", name=f"cache{k + 1}{suffixe}")(h)
        if abandon:
            h = tf.keras.layers.Dropout(abandon)(h)
    return (tf.keras.layers.Dense(len(FAMILLES), activation="softmax", name=f"famille{suffixe}")(h),
            tf.keras.layers.Dense(len(SORTES), activation="softmax", name=f"sorte{suffixe}")(h))


def tetes(x):
    """Les TETES têtes et la moyenne de leurs probabilités (sorties « famille » et « sorte »)."""
    import tensorflow as tf
    sorties = [branche(x, f"_{k}") for k in range(TETES)]
    return (tf.keras.layers.Average(name="famille")([f for f, _ in sorties]),
            tf.keras.layers.Average(name="sorte")([s for _, s in sorties]))


def modele(entrees, une=False):
    """Une tête à apprendre (`une`, avec abandon), sinon toutes les têtes moyennées."""
    import tensorflow as tf
    x = tf.keras.layers.Input(shape=(entrees,), name="mesures")
    return tf.keras.Model(x, list(branche(x, abandon=0.4) if une else tetes(x)))


def par_son(valeurs, clip, mask, reduction):
    """Valeurs des tranches regroupées par son (les tranches d'un son se suivent)."""
    c = clip[mask]
    debuts = np.flatnonzero(np.r_[True, c[1:] != c[:-1]])
    return reduction(valeurs[mask], debuts), debuts


def moyenne(v, debuts):
    sommes = np.add.reduceat(v, debuts, axis=0)
    tailles = np.diff(np.r_[debuts, len(v)])
    return sommes / tailles[:, None] if v.ndim == 2 else sommes / tailles


def maximum(v, debuts):
    return np.maximum.reduceat(v, debuts, axis=0)


def decider(p_famille_moy, p_voix_max, seuil):
    """Famille d'un son : voix si sa tranche la plus « voix » passe le seuil ; sinon la meilleure des autres."""
    autres = p_famille_moy.copy()
    autres[:, 0] = -1
    return np.where(p_voix_max >= seuil, 0, autres.argmax(axis=1))


def main():
    import tensorflow as tf
    x, famille, sorte, split, source, clip, base = charger()
    tr, va, vb = split == "train", split == "val_a", split == "val_b"
    mu, sigma = x[tr].mean(axis=0), x[tr].std(axis=0) + 1e-6
    xn = (x - mu) / sigma
    # Poids : un son de 16 tranches ne compte pas 16 fois plus qu'un chop d'une tranche (1/√n par tranche) ; puis
    # chaque famille pèse autant (les voix sont nombreuses), et chaque sorte connue autant (les autres : rien).
    w_son = 1 / np.sqrt(np.bincount(clip)[clip])
    connue = sorte != INCONNUE

    def equilibre(classes, garde, nb):
        total = np.bincount(classes[tr & garde], weights=w_son[tr & garde], minlength=nb)
        return np.where(garde, w_son * (total.sum() / (nb * np.maximum(total, 1e-9)))[np.maximum(classes, 0)], 0.0)
    w_famille = equilibre(famille, np.ones_like(connue), len(FAMILLES))
    w_sorte = equilibre(sorte, connue, len(SORTES))
    w_famille /= w_famille[tr].mean()                         # poids moyen 1 : même pas d'apprentissage
    w_sorte /= w_sorte[tr & connue].mean()
    y_sorte = np.maximum(sorte, 0)

    m = modele(x.shape[1])
    for k in range(TETES):
        tf.keras.utils.set_random_seed(7 + k)
        une = modele(x.shape[1], une=True)
        une.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
                    loss={"famille": "sparse_categorical_crossentropy", "sorte": "sparse_categorical_crossentropy"})
        une.fit(xn[tr], {"famille": famille[tr], "sorte": y_sorte[tr]},
                sample_weight={"famille": w_famille[tr], "sorte": w_sorte[tr]},
                validation_data=(xn[va], {"famille": famille[va], "sorte": y_sorte[va]},
                                 {"famille": w_famille[va], "sorte": w_sorte[va]}),
                epochs=80, batch_size=512, verbose=2,
                # La famille d'abord (les voix) : arrêt quand elle ne progresse plus sur la validation A.
                callbacks=[tf.keras.callbacks.EarlyStopping(monitor="val_famille_loss", patience=8,
                                                            restore_best_weights=True),
                           tf.keras.callbacks.ReduceLROnPlateau(monitor="val_famille_loss", factor=0.5, patience=3)])
        for nom in [f"cache{j + 1}" for j in range(len(COUCHES))] + ["famille", "sorte"]:
            m.get_layer(f"{nom}_{k}").set_weights(une.get_layer(nom).get_weights())
        print(f"tête {k + 1}/{TETES} apprise", flush=True)
    p_fam, p_sorte = m.predict(xn, batch_size=4096, verbose=0)

    # Seuil des voix (validation A).
    vmax_a, deb_a = par_son(p_fam[:, 0], clip, va, maximum)
    voix_a = famille[va][deb_a] == 0
    seuil = 0.99
    for t in np.arange(0.05, 0.99, 0.01):
        if ((vmax_a >= t) & ~voix_a).sum() / max((~voix_a).sum(), 1) <= FAUX_VOIX_MAX:
            seuil = float(round(t, 2))
            break

    # Chiffres (validation B), par son.
    fam_moy, deb = par_son(p_fam, clip, vb, moyenne)
    vmax, _ = par_son(p_fam[:, 0], clip, vb, maximum)
    vrai = famille[vb][deb]
    src = source[vb][deb]
    pred = decider(fam_moy, vmax, seuil)
    bmax, _ = par_son(base, clip, vb, maximum)
    lignes = ["# Résultats de l'IA intégrée", "",
              f"Sons de validation B : {len(deb)} (jamais entendus à l'apprentissage). Seuil des voix : {seuil}.", "",
              f"- Justesse de la famille : **{(pred == vrai).mean() * 100:.1f} %**",
              f"- Voix reconnues : **{(pred[vrai == 0] == 0).mean() * 100:.1f} %** "
              f"(YAMNet seul, ses classes de voix ≥ 0,5 : {(bmax[vrai == 0] >= 0.5).mean() * 100:.1f} %)",
              f"- Autres sons pris pour des voix : **{(pred[vrai != 0] == 0).mean() * 100:.1f} %** "
              f"(YAMNet seul : {(bmax[vrai != 0] >= 0.5).mean() * 100:.1f} %)", "",
              "## Par famille (objectif : 99 %)", "", "| Famille | Sons | Bien classés |", "|---|---|---|"]
    for i, f in enumerate(FAMILLES):
        k = vrai == i
        lignes.append(f"| {f} | {k.sum()} | {(pred[k] == i).mean() * 100:.1f} % |")
    lignes += ["", "## Par source", "", "| Source | Sons | Famille attendue | Bien classés | Pris pour des voix |",
              "|---|---|---|---|---|"]
    for s in sorted(set(src)):
        k = src == s
        lignes.append(f"| {s} | {k.sum()} | {FAMILLES[vrai[k][0]]} | {(pred[k] == vrai[k]).mean() * 100:.1f} % "
                      f"| {(pred[k] == 0).mean() * 100:.1f} % |")
    lignes += ["", "## Confusion des familles (lignes : attendu ; colonnes : décidé)", "",
               "| | " + " | ".join(FAMILLES) + " |", "|---" * (len(FAMILLES) + 1) + "|"]
    for i, f in enumerate(FAMILLES):
        k = vrai == i
        lignes.append(f"| {f} | " + " | ".join(str(int(((pred == j) & k).sum())) for j in range(len(FAMILLES))) + " |")
    # Sorte, comme dans l'app : la plus probable parmi celles de la famille décidée, donnée si elle l'emporte
    # nettement (sons dont on connaît la sorte).
    s_moy, _ = par_son(p_sorte, clip, vb, moyenne)
    vrai_s = sorte[vb][deb]
    masque = np.array([[FAMILLE_DE_SORTE[n] == FAMILLES[f] for n in SORTES] for f in pred])
    dans = np.where(masque, s_moy, 0)
    pred_s = dans.argmax(axis=1)
    part = dans.max(axis=1) / np.maximum(dans.sum(axis=1), 1e-9)
    k_connue = vrai_s != INCONNUE
    donnee = k_connue & (part >= PART_MIN)
    lignes += ["", f"## Sorte (sons dont on la connaît : {k_connue.sum()})", "",
               f"- Sorte juste (parmi celles de la famille décidée) : "
               f"**{(pred_s[k_connue] == vrai_s[k_connue]).mean() * 100:.1f} %**",
               f"- Sorte donnée (nette) : {donnee.sum() / max(k_connue.sum(), 1) * 100:.1f} % des sons, "
               f"juste dans **{(pred_s[donnee] == vrai_s[donnee]).mean() * 100:.1f} %** des cas ; sinon le mot "
               "général de la famille (ou, pour des drums et des mélodies, la sorte trouvée par l'app sans l'IA)", "",
               "| Sorte | Sons | Bien nommés | Le plus souvent pris pour |", "|---|---|---|---|"]
    for i, s in enumerate(SORTES):
        k = vrai_s == i
        if k.any():
            faux = pred_s[k][pred_s[k] != i]
            erreur = NOMS[SORTES[np.bincount(faux).argmax()]] if faux.size else "—"
            lignes.append(f"| {NOMS[s]} | {k.sum()} | {(pred_s[k] == i).mean() * 100:.1f} % | {erreur} |")
    texte = "\n".join(lignes) + "\n"
    print(texte)
    open(os.path.join(ICI, "RESULTATS.md"), "w").write(texte)

    m.save_weights(os.path.join(TRAVAIL, "tete.weights.h5"))
    json.dump({"familles": FAMILLES, "sortes": SORTES, "seuil_voix": seuil, "couches": COUCHES, "tetes": TETES,
               "mu": mu.tolist(), "sigma": sigma.tolist()}, open(os.path.join(TRAVAIL, "tete.json"), "w"))
    print("tête sauvée dans", TRAVAIL)


if __name__ == "__main__":
    main()
