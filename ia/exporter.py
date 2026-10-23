"""Assemble le modèle de l'app et l'exporte : son brut (tranches de 15 600 échantillons à 16 kHz) → spectre log-mel
de YAMNet (cadres de 25 ms tous les 10 ms, FFT 512 en multiplications de matrices, 64 bandes mel 125–7500 Hz,
log(x + 0,001)) → YAMNet → empreinte + 192 mesures du spectre → têtes → « famille » [5] et « sorte » [42 : les choix
de l'aperçu de l'Organiser].
Rien de propre à une plateforme : mêmes calculs sous ONNX Runtime (Windows, macOS) et Core ML (macOS 13+).

Vérifié contre le pipeline d'apprentissage (YAMNet d'origine + mesures + tête) ; puis :
- ia/modele/classeur_sons.onnx : poids de YAMNet et des têtes en 8 bits (quantification dynamique), spectre en 32 bits ;
- ia/modele/classeur_sons.json : classes, seuil des voix, réglages des tranches, crédits ;
- Resources/ClasseurSons.mlpackage : le même modèle pour l'app Mac (8 bits, spectre en 32 bits) ;
- Tests/FLShortcutTests/Fixtures : sons d'essai jamais entendus et réponses attendues (tests de l'app sur la CI).
Usage : python ia/exporter.py"""
import json
import os
import shutil

import numpy as np

from commun import (FAMILLES, ICI, MAX_TRANCHES, MODELE, PAS, SORTES, SR, TRANCHE, TRAVAIL, charger_yamnet,
                    lire, stats_logmel, tranches)

yparams, ylib = charger_yamnet()
import tensorflow as tf  # noqa: E402

P = yparams.Params()
WIN, HOP, FFT, CADRES = 400, 160, 512, 96
REGLAGES = json.load(open(os.path.join(TRAVAIL, "tete.json")))
from entrainer import COUCHES, TETES, modele, tetes  # noqa: E402
assert (REGLAGES["couches"], REGLAGES["tetes"]) == (COUCHES, TETES), "têtes apprises avec d'autres réglages"
RACINE = os.path.dirname(ICI)

# Constantes du spectre, identiques à tf.signal.stft (Hann périodique, cadre complété à 512) et à la matrice mel.
n = np.arange(WIN)
hann = 0.5 - 0.5 * np.cos(2 * np.pi * n / WIN)
angle = 2 * np.pi * np.outer(n, np.arange(FFT // 2 + 1)) / FFT
DFT_RE = (hann[:, None] * np.cos(angle)).astype(np.float32)
DFT_IM = (-hann[:, None] * np.sin(angle)).astype(np.float32)
MEL = tf.signal.linear_to_mel_weight_matrix(64, FFT // 2 + 1, float(SR), 125.0, 7500.0).numpy().astype(np.float32)
CADRE_IDX = (np.arange(CADRES)[:, None] * HOP + np.arange(WIN)[None, :]).astype(np.int32)


class LogMel(tf.keras.layers.Layer):
    def call(self, son):                                       # [B, 15600]
        cadres = tf.gather(son, CADRE_IDX, axis=1)             # [B, 96, 400]
        re, im = tf.matmul(cadres, DFT_RE), tf.matmul(cadres, DFT_IM)
        return tf.math.log(tf.matmul(tf.sqrt(re * re + im * im), MEL) + P.log_offset)   # [B, 96, 64]


class Mesures(tf.keras.layers.Layer):
    """Empreinte + moyenne, écart-type et variation de chaque bande, puis normalisation de l'apprentissage."""
    def call(self, entrees):
        emb, logmel = entrees
        moy = tf.reduce_mean(logmel, axis=1)
        ecart = tf.sqrt(tf.reduce_mean(tf.square(logmel - moy[:, None, :]), axis=1))
        variation = tf.reduce_mean(tf.abs(logmel[:, 1:, :] - logmel[:, :-1, :]), axis=1)
        x = tf.concat([emb, moy, ecart, variation], axis=1)
        return (x - np.asarray(REGLAGES["mu"], np.float32)) / np.asarray(REGLAGES["sigma"], np.float32)


def construire():
    son = tf.keras.layers.Input(shape=(TRANCHE,), name="son")
    logmel = LogMel(name="logmel")(son)
    _, emb = ylib.yamnet(logmel, P)
    x = Mesures(name="mesures")([emb, logmel])
    m = tf.keras.Model(son, list(tetes(x)))
    m.load_weights(os.path.join(ylib.__file__.rsplit("/", 1)[0], "yamnet.h5"), by_name=True)
    # Têtes : relues dans le modèle de l'apprentissage (même forme), puis recopiées couche par couche.
    tete = modele(len(REGLAGES["mu"]))
    tete.load_weights(os.path.join(TRAVAIL, "tete.weights.h5"))
    for nom in NOMS_TETES:
        m.get_layer(nom).set_weights(tete.get_layer(nom).get_weights())
    return m


NOMS_TETES = [f"{c}_{k}" for k in range(TETES) for c in [f"cache{j + 1}" for j in range(len(COUCHES))]
              + ["famille", "sorte"]]


def reference(m, son):
    """Pipeline d'apprentissage : YAMNet d'origine (spectre de TensorFlow) + mesures numpy + têtes du modèle."""
    full = ylib.yamnet_frames_model(P)
    full.load_weights(os.path.join(ylib.__file__.rsplit("/", 1)[0], "yamnet.h5"))
    _, emb, logmel = full(son)
    x = np.concatenate([emb.numpy()[0], stats_logmel(logmel.numpy()[:96])])
    x = (x - np.asarray(REGLAGES["mu"])) / np.asarray(REGLAGES["sigma"])
    sortie = [0.0, 0.0]
    for k in range(TETES):
        h = x
        for j in range(len(COUCHES)):
            w, b = m.get_layer(f"cache{j + 1}_{k}").get_weights()
            h = np.maximum(h @ w + b, 0)
        for i, nom in enumerate(("famille", "sorte")):
            w, b = m.get_layer(f"{nom}_{k}").get_weights()
            z = h @ w + b
            sortie[i] = sortie[i] + np.exp(z - z.max()) / np.exp(z - z.max()).sum() / TETES
    return sortie


def sons_reels(n, graine):
    """Tranches de sons de chaque famille (chant, parole, batterie, fabriqués) : calibration et vérification des
    versions 8 bits."""
    import tarfile
    import zipfile
    import preparer as p
    p.rng.seed(graine)
    p.nrng = np.random.default_rng(graine)
    d = os.path.join(TRAVAIL, "donnees")
    sons = []
    for archive in ("vocalset11.zip", "oneshot.zip"):
        z = zipfile.ZipFile(os.path.join(d, archive))
        noms = [x for x in z.namelist() if x.endswith(".wav") and "/._" not in x and "__MACOSX" not in x]
        sons += [lire(z.read(x))[: SR * 3] for x in p.rng.sample(noms, n)]
    t = tarfile.open(os.path.join(d, "librispeech-dev-clean.tar.gz"))
    for m in t:
        if m.name.endswith(".flac") and p.rng.random() < 0.02:
            sons.append(lire(t.extractfile(m).read())[: SR * 3])
            if len(sons) >= 3 * n:
                break
    for _ in range(n):
        sons += [p.synth_808(), p.synth_reese(), p.synth_fx()[0], p.synth_pad(), p.arpege(p.notes_synth(0.2)),
                 p.synth_clap(), p.synth_hihat(True)]
    return np.concatenate([tranches(s) for s in sons if s.size > 400])


def poids_reduits(graphe, chemin, bits):
    """Les gros poids gardés en 16 bits (Cast) ou en 8 bits par canal (DequantizeLinear, comme Core ML) dans le
    fichier, remis en 32 bits au chargement : calculs toujours en 32 bits, seul l'arrondi des poids change. Le
    spectre (matrices de Fourier et mel) reste en 32 bits."""
    import onnx as onnx_lib
    from onnx import TensorProto, helper, numpy_helper
    g = onnx_lib.ModelProto()
    g.CopyFrom(graphe)
    axe_de = {}                                                # poids → axe de ses canaux de sortie
    for nd in g.graph.node:
        if nd.op_type == "Conv" and len(nd.input) > 1:
            axe_de[nd.input[1]] = 0
        elif nd.op_type == "MatMul":
            axe_de[nd.input[1]] = 1
    gardes, noeuds = [], []
    for init in g.graph.initializer:
        w = numpy_helper.to_array(init)
        if init.data_type != TensorProto.FLOAT or w.size < 4096 or w.shape in {(WIN, FFT // 2 + 1), (FFT // 2 + 1, 64)}:
            gardes.append(init)
        elif bits == 16:
            gardes.append(numpy_helper.from_array(w.astype(np.float16), init.name + "_r"))
            noeuds.append(helper.make_node("Cast", [init.name + "_r"], [init.name], to=TensorProto.FLOAT))
        elif init.name in axe_de:
            axe = axe_de[init.name]
            autres = tuple(i for i in range(w.ndim) if i != axe)
            echelle = (np.abs(w).max(axis=autres) / 127 + 1e-12).astype(np.float32)
            forme = [1] * w.ndim
            forme[axe] = -1
            q = np.round(w / echelle.reshape(forme)).clip(-127, 127).astype(np.int8)
            gardes += [numpy_helper.from_array(q, init.name + "_r"), numpy_helper.from_array(echelle, init.name + "_e"),
                       numpy_helper.from_array(np.zeros_like(echelle, np.int8), init.name + "_z")]
            noeuds.append(helper.make_node("DequantizeLinear", [init.name + "_r", init.name + "_e", init.name + "_z"],
                                           [init.name], axis=axe))
        else:
            gardes.append(init)
    del g.graph.initializer[:]
    g.graph.initializer.extend(gardes)
    tous = noeuds + list(g.graph.node)
    del g.graph.node[:]
    g.graph.node.extend(tous)
    onnx_lib.save(g, chemin)


def onnx(m, dossier):
    """ONNX 32 bits, puis des versions plus légères : poids en 16 ou en 8 bits (calculs en 32 bits), tout en 8 bits
    (dynamique ; statique, calibrée sur de vrais sons). La plus légère qui répond comme la 32 bits (même famille pour 99 % des tranches au moins, même
    sorte pour 97 %, probabilités à 0,02 près en moyenne) est gardée, sinon la 32 bits. Rend (chemin, précision)."""
    import onnx as onnx_lib
    import onnxruntime as ort
    import tf2onnx
    from onnxruntime.quantization import (CalibrationDataReader, QuantFormat, QuantType, quantize_dynamic,
                                          quantize_static)
    f32 = os.path.join(dossier, "classeur_sons_f32.onnx")
    tf2onnx.convert.from_keras(m, input_signature=(tf.TensorSpec((None, TRANCHE), tf.float32, name="son"),),
                               opset=13, output_path=f32)
    graphe = onnx_lib.load(f32)
    formes = {i.name: tuple(i.dims) for i in graphe.graph.initializer}
    spectre = [nd.name for nd in graphe.graph.node if nd.op_type == "MatMul"
               and any(formes.get(e) in {(WIN, FFT // 2 + 1), (FFT // 2 + 1, 64)} for e in nd.input)]
    softmax = [nd.name for nd in graphe.graph.node if nd.op_type == "Softmax"]
    dyn, sta = os.path.join(dossier, "classeur_sons_dyn.onnx"), os.path.join(dossier, "classeur_sons_sta.onnx")
    quantize_dynamic(f32, dyn, weight_type=QuantType.QUInt8, op_types_to_quantize=["Conv", "MatMul"],
                     nodes_to_exclude=spectre)
    calibration = sons_reels(12, 1)

    class Lecteur(CalibrationDataReader):
        def __init__(self):
            self.lots = iter(calibration[i:i + 8] for i in range(0, len(calibration), 8))

        def get_next(self):
            lot = next(self.lots, None)
            return None if lot is None else {"son": lot}

    # Softmax calibrés (ONNX Runtime l'exige pour une sortie) mais jamais ramenés à 8 bits.
    quantize_static(f32, sta, Lecteur(), quant_format=QuantFormat.QDQ, per_channel=True, weight_type=QuantType.QInt8,
                    activation_type=QuantType.QUInt8, op_types_to_quantize=["Conv", "Softmax"],
                    nodes_to_exclude=spectre + softmax)
    f16, p8 = os.path.join(dossier, "classeur_sons_f16.onnx"), os.path.join(dossier, "classeur_sons_p8.onnx")
    poids_reduits(graphe, f16, 16)
    poids_reduits(graphe, p8, 8)
    essai = sons_reels(10, 2)
    ref = ort.InferenceSession(f32).run(["famille", "sorte"], {"son": essai})
    choix = (f32, "float32")
    for chemin, precision in ((f16, "poids float16"), (p8, "poids int8"), (dyn, "int8 dynamique"),
                              (sta, "int8 statique")):
        q = ort.InferenceSession(chemin).run(["famille", "sorte"], {"son": essai})
        meme = float((q[0].argmax(1) == ref[0].argmax(1)).mean())
        ecart = float(np.abs(q[0] - ref[0]).mean())
        meme_sorte = float((q[1].argmax(1) == ref[1].argmax(1)).mean())
        print(f"ONNX {precision} : {os.path.getsize(chemin) / 1e6:.1f} Mo ; même famille {meme * 100:.1f} %, "
              f"écart moyen {ecart:.3f}, même sorte {meme_sorte * 100:.1f} % ({len(essai)} tranches)")
        if meme >= 0.99 and ecart <= 0.02 and meme_sorte >= 0.97 \
                and os.path.getsize(chemin) < os.path.getsize(choix[0]):
            choix = (chemin, precision)
    print(f"ONNX gardé : {choix[1]} ({os.path.getsize(f32) / 1e6:.1f} Mo en 32 bits)")
    return choix


def coreml(m, chemin):
    import coremltools as ct
    mlm = ct.convert(m, inputs=[ct.TensorType(name="son", shape=(ct.RangeDim(1, MAX_TRANCHES, default=1), TRANCHE))],
                     minimum_deployment_target=ct.target.macOS13, convert_to="mlprogram",
                     compute_precision=ct.precision.FLOAT32)
    sorties = mlm._mil_program.functions["main"].outputs
    assert [v.shape[-1] for v in sorties] == [len(FAMILLES), len(SORTES)], [v.shape for v in sorties]
    garder = {op.name for op in mlm._mil_program.functions["main"].operations
              if op.op_type == "const" and getattr(op.val.val, "shape", ()) in
              [(WIN, FFT // 2 + 1), (FFT // 2 + 1, 64)]}
    cfg = ct.optimize.coreml.OptimizationConfig(
        global_config=ct.optimize.coreml.OpLinearQuantizerConfig(mode="linear_symmetric", weight_threshold=4096),
        op_name_configs={nom: None for nom in garder})
    q = ct.optimize.coreml.linear_quantize_weights(mlm, config=cfg)
    # Sorties nommées comme dans l'ONNX (TensorFlow les appelle Identity, Identity_1, dans l'ordre du modèle).
    spec = q.get_spec()
    for ancien, nouveau in zip([o.name for o in spec.description.output], ("famille", "sorte")):
        ct.utils.rename_feature(spec, ancien, nouveau)
    q = ct.models.MLModel(spec, weights_dir=q.weights_dir)
    q.short_description = "FL Shortcuts : famille et sorte d'un son (YAMNet Apache 2.0 + têtes apprises sur des sons libres)"
    q.license = "YAMNet : Apache 2.0 (Google) ; têtes : apprises sur VocalSet, LibriSpeech, NSynth (CC BY 4.0) et " \
                "Freesound One-Shot Percussive Sounds (CC0, CC BY) — voir ia/modele/CREDITS.md"
    q.input_description["son"] = "Tranches de 15 600 échantillons, 16 kHz, mono, crête du son à 0,7"
    q.output_description["famille"] = "Probabilités : " + ", ".join(FAMILLES)
    q.output_description["sorte"] = "Probabilités : " + ", ".join(SORTES)
    if os.path.exists(chemin):
        shutil.rmtree(chemin)
    q.save(chemin)


def main():
    m = construire()
    rng = np.random.default_rng(1)
    t = np.arange(TRANCHE) / SR
    essais = {"sinus": 0.4 * np.sin(2 * np.pi * 330 * t), "bruit": 0.2 * rng.standard_normal(TRANCHE),
              "accord": 0.2 * sum(np.sin(2 * np.pi * f * t) for f in (220, 277, 330))}
    pire = 0.0
    for nom, son in essais.items():
        son = son.astype(np.float32)
        f, s = m(son[None])
        rf, rs = reference(m, son)
        pire = max(pire, float(np.abs(f.numpy()[0] - rf).max()), float(np.abs(s.numpy()[0] - rs).max()))
    print("écart avec le pipeline d'apprentissage :", pire)
    assert pire < 1e-3, "le modèle assemblé ne répond pas comme celui de l'apprentissage"

    # Core ML d'abord : la conversion ONNX transforme le modèle Keras en place (noms des sorties perdus).
    coreml(m, os.path.join(RACINE, "Resources", "ClasseurSons.mlpackage"))
    print("Core ML : Resources/ClasseurSons.mlpackage")
    os.makedirs(MODELE, exist_ok=True)
    chemin, precision = onnx(m, TRAVAIL)
    shutil.copyfile(chemin, os.path.join(MODELE, "classeur_sons.onnx"))
    json.dump({"version": 1, "entree": "son", "sorties": ["famille", "sorte"], "precision": precision,
               "familles": FAMILLES, "sortes": SORTES,
               "seuil_voix": REGLAGES["seuil_voix"], "frequence": SR, "tranche": TRANCHE, "pas": PAS,
               "max_tranches": MAX_TRANCHES, "crete": 0.7,
               "credits": ["YAMNet (Google, Apache 2.0)", "VocalSet (CC BY 4.0)", "LibriSpeech (CC BY 4.0)",
                           "NSynth (CC BY 4.0)", "Freesound One-Shot Percussive Sounds (sons CC0 et CC BY)"]},
              open(os.path.join(MODELE, "classeur_sons.json"), "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
