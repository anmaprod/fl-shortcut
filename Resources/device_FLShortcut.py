# name=FL Shortcuts
# supportedDevices=FL Shortcuts
"""
FL Shortcuts : script MIDI pour FL Studio 20.7 (API 1, Python 3.6) et plus récent.

Reçoit les commandes authentifiées de l'appli FL Shortcuts (port MIDI « FL Shortcuts »,
canal 16) et exécute l'action demandée. Contrat : PROTOCOL.md (protocole v2).

Règles de compatibilité (audit 04) :
- syntaxe Python 3.6 stricte, aucun accès disque, bibliothèque standard minimale ;
- aucun import obligatoire au niveau du module : tous les modules FL sont
  importés à la demande et peuvent manquer (plugins, arrangement, playlist...) ;
- chaque action teste la présence des fonctions (hasattr) ET la version d'API ;
  sinon repli (transport.globalTransport) ou action déclarée indisponible dans
  le masque de capacités du HELLO.

Sécurité (audit 01, SEC-01/02/10) :
- HMAC-SHA256 (hmac/hashlib, sinon SHA-256 en Python pur embarqué) sur
  nonce de session + séquence + action ; anti-rejeu ; trames de 8 CC strictes ;
  20 actions/s maximum ; liste blanche des ids ; essais de MAC limités ;
- clé non installée => toutes les commandes sont refusées.

Fiabilité (audit 02, REL-14, REL-24 à REL-27) : aucune exception ne remonte à FL,
bornes vérifiées, seuls les CC du protocole (canal 16) sont marqués « handled ».
"""

# La ligne suivante est remplacée par l'appli à l'installation (16 octets en hex).
KEY_HEX = "__FLSHORTCUT_KEY__"

SCRIPT_VERSION = 6
PROTOCOL_VERSION = 2

MIDI_CHANNEL = 15          # canal 16, 0-indexé
STATUS_CC_OUT = 0xBF       # Control Change, canal 16

# CC appli -> FL
CC_PING = 103
CC_FRAME_FIRST = 104       # 104..111 : seq (3), action (1), MAC (4)
CC_FRAME_LAST = 111
FRAME_LEN = 8
CC_DATA_START = 96         # commande avec données (PROTOCOL.md §7) : début, vide le tampon
CC_DATA_UNIT = 97          # une unité de 7 bits des données
# CC FL -> appli
CC_CAPS_FIRST = 90         # 90..95 : masque de capacités, 6 x 7 bits
CC_REASON = 116            # raison d'un refus de la commande avec données, juste avant l'accusé 0
CC_WINDOW = 117
CC_HEARTBEAT = 118
CC_ACK = 119
CC_HELLO = 120             # 1 = début, 127 = fin
CC_NONCE_FIRST = 121       # 121..124
CC_API = 125
CC_PROTO = 126

SEQ_MAX = (1 << 21) - 1
MAX_ACTION_ID = 42         # taille du masque (6 x 7 bits)
DATA_ACTION_ID = 41        # commande avec données : hors de la table des actions (PROTOCOL.md §7)
MAX_DATA_UNITS = 600
MAX_NAME_CHARS = 64
OP_NAME_COLOR = 1
REASON_PAGE = 1            # page devant non prise en charge
REASON_NONE = 2            # rien de sélectionné
REASON_MANY = 3            # plusieurs éléments sélectionnés
REASON_OLD_FL = 6          # page prise en charge, mais pas par cette version de FL (Playlist : API 12)
REASON_DATA = 5            # données invalides (ou FL a refusé)
# Organiser et dégradé (script v5, PROTOCOL.md §8)
CC_RESP_START = 112        # réponse FL -> appli : début (valeur = opération)
CC_RESP_UNIT = 113         # une unité de 7 bits de la réponse
CC_RESP_END = 114          # fin des unités, suivie de 4 CC 115 (MAC de la réponse)
CC_RESP_MAC = 115
MAX_RESP_UNITS = 600
EXT_ACTION_ID = 42         # capacité : opérations 2 à 8
OP_LIST = 2
OP_AUDITION = 3
OP_SET_COLORS = 4
OP_SELECT_ONE = 5
OP_PLAY_SOLO = 6
OP_STOP_RESTORE = 7
OP_GRADIENT = 8
OP_PAGE = 9                # page de FL devant (Organiser)
OP_SET_NAMES = 10          # noms des pistes de la Playlist
OP_PLAY_TRACK = 11         # écoute d'une piste de la Playlist seule
OP_SEEK = 12               # position de la chanson pendant cette écoute
KIND_CHANNELS = 1
KIND_MIXER = 2
KIND_PLAYLIST = 3          # pistes de la Playlist (index 0 = piste 1 de FL)
REASON_PLAYING = 4         # FL joue déjà (opération 6)
REASON_FEW = 7             # dégradé : au moins 2 éléments sélectionnés
LIST_PAGE = 16             # entrées par réponse de `list`
LIST_NAME_BYTES = 24       # noms coupés (aperçu seulement)
MAX_COLORS = 64
MAX_NAMES = 16             # noms par commande (opération 10)
NAME_MAX_BYTES = 32

MAX_ACTIONS_PER_S = 20     # PROTOCOL.md §4
MAX_MAC_CHECKS_PER_S = 25  # coût CPU borné sous inondation (SEC-10)
MAX_MAC_FAILS_PER_S = 5    # force brute du MAC 28 bits : <= 5 essais/s
MIN_PING_INTERVAL = 0.25   # s
# Sommeil : le script ne fait RIEN tant que l'appli ne l'a pas réveillé (PING). Réveil « bref » (PING = 2,
# macros) : il se rendort tout seul AWAKE_FOR secondes après le dernier message. Réveil « durable » (PING = 1,
# mode MIDI complet) : il reste éveillé. Endormi, OnIdle et OnRefresh s'arrêtent à leur première ligne.
AWAKE_FOR = 8.0            # s
PING_AWAKE = 1
PING_BRIEF = 2
MAX_REJECT_ACKS_PER_S = 20
HEARTBEAT_PERIOD = 2.0     # s
WINDOW_MIN_INTERVAL = 0.1  # s (CC 117 au plus toutes les 100 ms)
HELLO_RETRY_INTERVAL = 1.0 # s
IDLE_MIN_INTERVAL = 0.05   # s : OnIdle (appelé ~ toutes les 20 ms par FL) ne travaille qu'une fois sur 2-3
REPORT_INTERVAL = 10.0     # s : une même erreur au plus une fois par période
HINT_MIN_INTERVAL = 1.0    # s, pour les messages de refus répétés

LOG_TO_OUTPUT = False      # rien dans View > Script output (chaque ligne coûte à FL ; activer pour déboguer)

_PLACEHOLDER = "__FLSHORTCUT" + "_KEY__"   # écrit en deux morceaux : une seule occurrence à remplacer


# --------------------------------------------------------------------------
# Bibliothèque standard (toutes optionnelles)
# --------------------------------------------------------------------------
try:
    import time as _time
except Exception:  # interpréteur réduit
    _time = None

try:
    import random as _random
except Exception:
    _random = None

try:
    import hmac as _hmac
    import hashlib as _hashlib
except Exception:
    _hmac = None
    _hashlib = None

_sysrand = None
try:
    _sysrand = _random.SystemRandom()
    _sysrand.randrange(128)
except Exception:
    _sysrand = None


# --------------------------------------------------------------------------
# Accès paresseux et tolérant aux modules FL
# --------------------------------------------------------------------------
_MODS = {}


def _mod(name):
    """Module FL importé à la première utilisation ; None s'il n'existe pas."""
    if name in _MODS:
        return _MODS[name]
    try:
        m = __import__(name)
    except Exception:
        m = None
    _MODS[name] = m
    return m


def _fn(mod_name, fn_name):
    m = _mod(mod_name)
    if m is None:
        return None
    try:
        f = getattr(m, fn_name, None)
    except Exception:
        return None
    if f is None or not callable(f):
        return None
    return f


def _has(mod_name, fn_name):
    return _fn(mod_name, fn_name) is not None


def _const(name, default):
    """Constante du module midi, avec valeur de repli (anciennes versions)."""
    m = _mod("midi")
    if m is None:
        return default
    try:
        v = getattr(m, name, default)
    except Exception:
        return default
    if isinstance(v, int):
        return v
    return default


def _is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def _now():
    if _time is not None:
        try:
            return _time.monotonic()
        except Exception:
            pass
        try:
            return _time.time()
        except Exception:
            pass
    # Sans horloge : pseudo-temps avancé par OnIdle (appelé ~ toutes les 20 ms).
    return _st.ticks * 0.02


def _log(text):
    if not LOG_TO_OUTPUT:
        return
    try:
        print(text)
    except Exception:
        pass


_hint_last = [None, -1e9]


def _hint(text):
    """Barre d'aide de FL. Ne lève jamais d'exception (REL-27). Un même message n'est pas réaffiché
    avant HINT_MIN_INTERVAL : une touche maintenue ne fait pas redessiner la barre d'aide 20 fois par seconde."""
    try:
        now = _now()
        if text == _hint_last[0] and 0 <= now - _hint_last[1] < HINT_MIN_INTERVAL:
            return
        _hint_last[0] = text
        _hint_last[1] = now
    except Exception:
        pass
    try:
        f = _fn("ui", "setHintMsg")
        if f is not None:
            f(text)
    except Exception:
        pass
    _log(text)


_last_reports = {}


def _report(exc):
    """Erreur signalée au plus une fois toutes les 10 s par message : une erreur répétée dans OnIdle
    (appelé ~50 fois par seconde) ne doit jamais inonder la barre d'aide ni la sortie des scripts de FL."""
    try:
        text = "FL Shortcuts erreur : %r" % (exc,)
        now = _now()
        last = _last_reports.get(text)
        if last is not None and 0 <= now - last < REPORT_INTERVAL:
            return
        if len(_last_reports) > 32:
            _last_reports.clear()
        _last_reports[text] = now
        _hint(text)
    except Exception:
        pass


# --------------------------------------------------------------------------
# SHA-256 / HMAC en Python pur (si hmac/hashlib sont absents ou défaillants)
# --------------------------------------------------------------------------
_M32 = 0xFFFFFFFF
_K256 = (
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
)
_H256 = (0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
         0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19)


def _sha256_compress(state, block):
    """Une compression SHA-256 : state = 8 mots de 32 bits, block = 64 octets."""
    M = _M32
    w = [(block[i] << 24) | (block[i + 1] << 16) | (block[i + 2] << 8) | block[i + 3]
         for i in range(0, 64, 4)]
    for i in range(16, 64):
        x = w[i - 15]
        y = w[i - 2]
        s0 = ((x >> 7) | (x << 25)) ^ ((x >> 18) | (x << 14)) ^ (x >> 3)
        s1 = ((y >> 17) | (y << 15)) ^ ((y >> 19) | (y << 13)) ^ (y >> 10)
        w.append((w[i - 16] + s0 + w[i - 7] + s1) & M)
    a, b, c, d, e, f, g, h = state
    for i in range(64):
        s1 = ((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21)) ^ ((e >> 25) | (e << 7))
        ch = (e & f) ^ ((~e) & g)
        t1 = (h + (s1 & M) + ch + _K256[i] + w[i]) & M
        s0 = ((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19)) ^ ((a >> 22) | (a << 10))
        maj = (a & b) ^ (a & c) ^ (b & c)
        t2 = ((s0 & M) + maj) & M
        h = g
        g = f
        f = e
        e = (d + t1) & M
        d = c
        c = b
        b = a
        a = (t1 + t2) & M
    return (
        (state[0] + a) & M, (state[1] + b) & M, (state[2] + c) & M, (state[3] + d) & M,
        (state[4] + e) & M, (state[5] + f) & M, (state[6] + g) & M, (state[7] + h) & M,
    )


def _sha256_finish(state, data, prefix_len):
    """Termine un hachage : `prefix_len` octets déjà absorbés dans `state`."""
    data = bytes(data)
    total_bits = (prefix_len + len(data)) * 8
    padded = data + b"\x80"
    padded += b"\x00" * ((56 - len(padded) % 64) % 64)
    padded += bytes([(total_bits >> (8 * (7 - i))) & 0xFF for i in range(8)])
    for off in range(0, len(padded), 64):
        state = _sha256_compress(state, padded[off:off + 64])
    out = []
    for word in state:
        out.extend([(word >> 24) & 0xFF, (word >> 16) & 0xFF, (word >> 8) & 0xFF, word & 0xFF])
    return bytes(out)


def sha256_pure(data):
    return _sha256_finish(_H256, data, 0)


class _PureHmac(object):
    """HMAC-SHA256 avec états ipad/opad précalculés (2 compressions par MAC)."""

    def __init__(self, key):
        key = bytes(key)
        if len(key) > 64:
            key = sha256_pure(key)
        key = key + b"\x00" * (64 - len(key))
        self._inner = _sha256_compress(_H256, bytes([b ^ 0x36 for b in key]))
        self._outer = _sha256_compress(_H256, bytes([b ^ 0x5C for b in key]))

    def digest(self, msg):
        inner = _sha256_finish(self._inner, msg, 64)
        return _sha256_finish(self._outer, inner, 64)


def hmac_sha256_pure(key, msg):
    return _PureHmac(key).digest(msg)


def hmac_sha256_lib(key, msg):
    return _hmac.new(bytes(key), bytes(msg), _hashlib.sha256).digest()


def mac28(digest):
    """4 premiers octets big-endian >> 4 => 28 bits => 4 x 7 bits (poids fort d'abord)."""
    v = ((digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3]) >> 4
    return [(v >> 21) & 0x7F, (v >> 14) & 0x7F, (v >> 7) & 0x7F, v & 0x7F]


def _ct_equal(a, b):
    if len(a) != len(b):
        return False
    acc = 0
    for x, y in zip(a, b):
        acc |= (x ^ y)
    return acc == 0


# Vecteur de test de PROTOCOL.md : sert d'autotest au chargement.
_TV_KEY = bytes(range(16))
_TV_MSG = bytes([17, 42, 99, 5, 0, 2, 44, 12])
_TV_MAC = [87, 59, 101, 12]


def _select_backend():
    if _hmac is not None and _hashlib is not None:
        try:
            if mac28(hmac_sha256_lib(_TV_KEY, _TV_MSG)) == _TV_MAC:
                return "hashlib"
        except Exception:
            pass
    try:
        if mac28(hmac_sha256_pure(_TV_KEY, _TV_MSG)) == _TV_MAC:
            return "python"
    except Exception:
        pass
    return None


def _parse_key(text):
    """16 octets en hexadécimal (32 caractères), sinon None : tout sera refusé."""
    try:
        if not isinstance(text, str) or text == _PLACEHOLDER:
            return None
        t = text.strip().lower()
        if len(t) != 32:
            return None
        for ch in t:
            if ch not in "0123456789abcdef":
                return None
        key = bytes([int(t[i:i + 2], 16) for i in range(0, 32, 2)])
        if key == b"\x00" * 16:
            return None
        return key
    except Exception:
        return None


class _Signer(object):
    def __init__(self, key, backend):
        self.key = key
        self.backend = backend
        self._pure = None
        if backend == "python":
            self._pure = _PureHmac(key)

    def mac(self, msg):
        if self.backend == "hashlib":
            return mac28(hmac_sha256_lib(self.key, msg))
        return mac28(self._pure.digest(msg))


MAC_BACKEND = None
KEY = None
_signer = None
try:
    MAC_BACKEND = _select_backend()
    KEY = _parse_key(KEY_HEX)
    if KEY is not None and MAC_BACKEND is not None:
        _signer = _Signer(KEY, MAC_BACKEND)
except Exception:
    _signer = None


# --------------------------------------------------------------------------
# État du script
# --------------------------------------------------------------------------
class _State(object):
    def __init__(self):
        self.ticks = 0
        self.api = None
        self.fl_version = None
        self.caps = None              # dict id -> bool
        self.nonce = [0, 0, 0, 0]
        self.last_seq = 0
        self.frame = None             # valeurs reçues (CC 104..)
        self.data = None              # unités reçues (CC 97) depuis le dernier CC 96, ou None
        self.data_bad = False         # plus de MAX_DATA_UNITS unités : refusées
        self.action_times = []
        self.check_times = []
        self.fail_times = []
        self.reject_ack_times = []
        self.last_ping = None
        self.last_hint = {}
        self.hello_pending = False
        self.last_idle = None
        self.last_hello_try = None
        self.last_beat = None
        self.beat = 0
        self.out_ok = None
        self.win_code = None
        self.win_dirty = True
        self.win_checked = None
        self.mono_prev = None
        self.mono_on = False
        self.awake = False            # endormi au chargement : rien n'est envoyé ni vérifié
        self.awake_until = None       # None : éveillé sans limite (mode MIDI complet)
        self.memo = None              # Organiser : sourdines, mode et position d'avant l'écoute (opération 6)


_st = _State()


def _wake(brief):
    _st.awake = True
    _st.awake_until = (_now() + AWAKE_FOR) if brief else None


def _sleep():
    _restore_memo_safely()            # l'appli a disparu pendant une écoute : FL est remis comme avant
    _st.awake = False
    _st.awake_until = None
    _st.frame = None
    _st.data = None
    _st.hello_pending = False


def _keep_awake():
    """Un message de l'appli prolonge un réveil bref."""
    if _st.awake and _st.awake_until is not None:
        _st.awake_until = _now() + AWAKE_FOR


def _rand7():
    for src in (_sysrand, _random):
        if src is None:
            continue
        try:
            v = src.randrange(128)
            if _is_int(v) and 0 <= v < 128:
                return v
        except Exception:
            pass
    # Dernier recours (aucun module random) : dérivé de SHA-256.
    _st.ticks += 1
    seed = ("%r|%r|%r" % (id(object()), _st.ticks, _now())).encode("utf-8")
    return sha256_pure(seed)[0] & 0x7F


def _new_nonce():
    old = list(_st.nonce)
    for _ in range(8):
        n = [_rand7() for _ in range(4)]
        if n != old:
            return n
    n[0] = (old[0] + 1) & 0x7F
    return n


def _new_session():
    _st.nonce = _new_nonce()
    _st.last_seq = 0
    _st.frame = None


_new_session()


def _api():
    if _st.api is None:
        v = 1
        try:
            f = _fn("general", "getVersion")
            if f is not None:
                r = f()
                if _is_int(r) and r >= 1:
                    v = r
        except Exception:
            v = 1
        _st.api = v
    return _st.api


def _api_at_least(n):
    return _api() >= n


def _parse_version_text(s):
    try:
        s = str(s)
        i = s.find("v")
        while i >= 0 and not (i + 1 < len(s) and s[i + 1].isdigit()):
            i = s.find("v", i + 1)
        if i < 0:
            i = 0
            while i < len(s) and not s[i].isdigit():
                i += 1
        else:
            i += 1
        j = i
        while j < len(s) and (s[j].isdigit() or s[j] == "."):
            j += 1
        parts = [int(p) for p in s[i:j].split(".") if p.isdigit()]
        if not parts:
            return None
        while len(parts) < 3:
            parts.append(0)
        return tuple(parts[:3])
    except Exception:
        return None


def _fl_version():
    """(majeure, mineure, révision) ou None. ui.getVersion(mode) : API 7."""
    if _st.fl_version is not None:
        return _st.fl_version
    gv = _fn("ui", "getVersion")
    v = None
    if gv is not None:
        if _api_at_least(7):
            try:
                v = (int(gv(0)), int(gv(1)), int(gv(2)))
            except Exception:
                v = None
        if v is None:
            try:
                v = _parse_version_text(gv())
            except Exception:
                v = None
    _st.fl_version = v
    return v


def _gt_buggy():
    """FL 26.1.0 à 26.1.6 : globalTransport peut geler ou planter FL (audit 04)."""
    v = _fl_version()
    return v is not None and (26, 1, 0) <= tuple(v) <= (26, 1, 6)


# --------------------------------------------------------------------------
# Sortie MIDI (device.midiOutMsg, forme combinée API 1)
# --------------------------------------------------------------------------
def _output_ready():
    if _fn("device", "midiOutMsg") is None:
        return False
    assigned = _fn("device", "isAssigned")
    if assigned is None:
        return True
    try:
        return bool(assigned())
    except Exception:
        return False


def _out_raw(cc, value):
    """Un CC canal 16. Octets bornés à 0..127 (midiOutMsg plantait FL <= 20.9.2)."""
    f = _fn("device", "midiOutMsg")
    if f is None:
        return False
    cc = int(cc) & 0x7F
    value = int(value) & 0x7F
    f(STATUS_CC_OUT | (cc << 8) | (value << 16))
    return True


def _send_cc(cc, value):
    """Sortie connue prête (vérifiée par le battement toutes les 2 s et par HELLO) : pas d'appel à
    device.isAssigned à chaque message."""
    if not _st.out_ok:
        return False
    try:
        return _out_raw(cc, value)
    except Exception:
        return False


def _send_many(pairs):
    try:
        if not _output_ready():
            return False
        for cc, value in pairs:
            _out_raw(cc, value)
        return True
    except Exception:
        return False


# --------------------------------------------------------------------------
# Outils pour les actions
# --------------------------------------------------------------------------
def _gt(name, default, value=1):
    """Repli : transport.globalTransport(midi.FPT_xxx, value) (API 1). Jamais sur FL 26.1.0-26.1.6, où
    globalTransport peut geler ou planter FL : l'action est alors annoncée indisponible et la touche va à FL."""
    if _gt_buggy():
        return False
    f = _fn("transport", "globalTransport")
    if f is None:
        return False
    f(_const(name, default), value)
    return True


def _has_gt():
    return _has("transport", "globalTransport") and not _gt_buggy()


def _call_compat(f, *variants):
    """Paramètres ajoutés tardivement : essaie la forme longue puis les plus courtes."""
    last = None
    for args in variants:
        try:
            return f(*args)
        except TypeError as exc:
            last = exc
    if last is not None:
        raise last
    return None


def _selected_track():
    """Piste Mixer sélectionnée, ou None (REL-24)."""
    tn = _fn("mixer", "trackNumber")
    if tn is None:
        return None
    t = tn()
    if not _is_int(t) or t < 0:
        return None
    tc = _fn("mixer", "trackCount")
    if tc is not None:
        n = tc()
        if _is_int(n) and t >= n:
            return None
    return t


def _channel_count():
    cc = _fn("channels", "channelCount")
    if cc is None:
        return 0
    n = cc()
    return n if _is_int(n) and n > 0 else 0


def _selected_channel_raw():
    f = None
    if _api_at_least(5):
        f = _fn("channels", "selectedChannel")
    if f is None:
        f = _fn("channels", "channelNumber")
    if f is None:
        return None
    c = f()
    return c if _is_int(c) else None


def _selected_channel():
    """Canal sélectionné, ou None si aucun (-1) ou hors bornes (REL-24)."""
    c = _selected_channel_raw()
    n = _channel_count()
    if c is None or c < 0 or c >= n:
        return None
    return c


def _no_track():
    _hint("FL Shortcuts : aucune piste Mixer sélectionnée")
    return False


def _no_channel():
    _hint("FL Shortcuts : aucun canal sélectionné")
    return False


def _show(wid):
    f = _fn("ui", "showWindow")
    if f is None:
        return False
    f(wid)
    if _api_at_least(2) and not _focused(wid):     # showWindow a souvent déjà donné le focus
        sf = _fn("ui", "setFocused")
        if sf is not None:
            sf(wid)
    return True


def _focused(wid):
    f = _fn("ui", "getFocused")
    if f is None:
        return False
    try:
        return bool(f(wid))
    except Exception:
        return False


W_MIXER = ("widMixer", 0)
W_CHANNELRACK = ("widChannelRack", 1)
W_PLAYLIST = ("widPlaylist", 2)
W_PIANOROLL = ("widPianoRoll", 3)
W_BROWSER = ("widBrowser", 4)
W_PLUGIN = ("widPlugin", 5)
W_PLUGIN_EFFECT = ("widPluginEffect", 6)
W_PLUGIN_GENERATOR = ("widPluginGenerator", 7)


def _wid(w):
    return _const(w[0], w[1])


# --------------------------------------------------------------------------
# Actions (chaque fonction renvoie True si exécutée, False sinon)
# --------------------------------------------------------------------------
def _a_play():
    f = _fn("transport", "start")
    if f is not None:
        f()
        return True
    return _gt("FPT_Play", 10)


def _a_stop():
    f = _fn("transport", "stop")
    if f is not None:
        f()
        return True
    return _gt("FPT_Stop", 11)


def _a_rec():
    f = _fn("transport", "record")
    if f is not None:
        f()
        return True
    return _gt("FPT_Record", 12)


def _a_marker():
    lm = _fn("transport", "getLoopMode")
    if lm is not None:
        try:
            if lm() == 0:   # mode Pattern : getSongPos donne la position dans le pattern
                _hint("FL Shortcuts : marqueur posé seulement en mode Song")
                return False
        except Exception:
            pass
    add = None
    arr = _mod("arrangement")
    if arr is not None:
        add = getattr(arr, "addAutoTimeMarker", None)
    gsp = _fn("transport", "getSongPos")
    if add is not None and gsp is not None and _api_at_least(3):
        pos = None
        try:
            pos = gsp(_const("SONGLENGTH_ABSTICKS", 2))
        except TypeError:
            pos = None
        if isinstance(pos, (int, float)) and not isinstance(pos, bool) and pos >= 0:
            add(int(pos), "Bonne prise")
            return True
    return _gt("FPT_AddMarker", 33)


def _av_marker():
    arr = _mod("arrangement")
    direct = (arr is not None and callable(getattr(arr, "addAutoTimeMarker", None))
              and _has("transport", "getSongPos") and _api_at_least(3))
    return direct or _has_gt()


def _a_arm():
    t = _selected_track()
    if t is None:
        return _no_track()
    _fn("mixer", "armTrack")(t)
    return True


def _a_armon():
    """Arme la piste sélectionnée seulement si elle ne l'est pas (ne jamais désarmer)."""
    t = _selected_track()
    if t is None:
        return _no_track()
    if not _fn("mixer", "isTrackArmed")(t):
        _fn("mixer", "armTrack")(t)
    return True


def _a_recon():
    """Allume le REC seulement s'il est éteint (ne jamais l'éteindre)."""
    if _fn("transport", "isRecording")():
        return True
    _fn("transport", "record")()
    return True


def _a_newpat():
    _fn("patterns", "findFirstNextEmptyPat")(_const("FFNEP_DontPromptName", 1))
    _show(_wid(W_PIANOROLL))
    return True


def _a_clone():
    _fn("patterns", "clonePattern")()
    return True


def _a_pattern(delta):
    jump = _fn("patterns", "jumpToPattern")
    pn = _fn("patterns", "patternNumber")
    if jump is None or pn is None:
        return _gt("FPT_PatternJog", 100, delta)
    cur = pn()
    if not _is_int(cur) or cur < 1:
        cur = 1
    pmax = 999
    pm = _fn("patterns", "patternMax")
    if pm is not None:
        try:
            v = pm()
            if _is_int(v) and v >= 1:
                pmax = v
        except Exception:
            pmax = 999
    target = min(max(1, cur + delta), pmax)   # REL-25 : borne patternMax, pas patternCount
    if target != cur:
        jump(target)
    return True


def _av_pattern():
    return (_has("patterns", "jumpToPattern") and _has("patterns", "patternNumber")) or _has_gt()


def _a_channel(delta):
    n = _channel_count()
    if n <= 0:
        return _no_channel()
    c = _selected_channel_raw()
    if c is None or c < 0 or c >= n:
        target = 0 if delta > 0 else n - 1
    else:
        target = (c + delta) % n
    sel = _fn("channels", "selectOneChannel") if _api_at_least(8) else None
    if sel is not None:
        sel(target)
        return True
    return _gt("FPT_ChannelJog", 102, delta)


def _av_channel():
    return ((_api_at_least(8) and _has("channels", "selectOneChannel")
             and _has("channels", "channelCount")) or _has_gt())


def _a_snap():
    f = _fn("ui", "snapMode")
    if f is not None:
        f(1)
        return True
    return _gt("FPT_SnapMode", 49, 1)


def _a_quant():
    c = _selected_channel()
    if c is None:
        return _no_channel()
    _fn("channels", "quickQuantize")(c)
    return True


def _focused_plugin():
    """(index, slot, global) du plugin qui a le focus, ou None."""
    gff = _fn("ui", "getFocusedFormID") if _api_at_least(13) else None
    if _focused(_wid(W_PLUGIN_EFFECT)):
        gae = _fn("mixer", "getActiveEffectIndex") if _api_at_least(25) else None
        if gae is not None:
            try:
                r = gae()
                if r is not None and len(r) == 2 and _is_int(r[0]) and _is_int(r[1]) and r[0] >= 0 and r[1] >= 0:
                    return (r[0], r[1], False)
            except Exception:
                pass
        if gff is not None:
            fid = gff()
            if _is_int(fid) and fid >= 0:
                return (fid // 4194304, (fid % 4194304) // 65536, False)
        return None
    # Générateur : getFocusedFormID donne l'index global du canal, utilisable
    # seulement avec useGlobalIndex (API 26). Avant : canal sélectionné (appelant).
    if _focused(_wid(W_PLUGIN_GENERATOR)) and gff is not None and _api_at_least(26):
        fid = gff()
        if _is_int(fid) and fid >= 0:
            return (fid, -1, True)
    return None


def _a_preset(forward):
    pl = _mod("plugins")
    f = getattr(pl, "nextPreset" if forward else "prevPreset", None)
    target = _focused_plugin()
    if target is None:
        c = _selected_channel()
        if c is None:
            return _no_channel()
        target = (c, -1, False)
    idx, slot, glob = target
    valid = getattr(pl, "isValid", None)
    if valid is not None:
        if glob:
            ok = _call_compat(valid, (idx, slot, True), (idx, slot), (idx,))
        else:
            ok = _call_compat(valid, (idx, slot), (idx,))
        if not ok:
            _hint("FL Shortcuts : aucun plugin à cet emplacement")
            return False
    if glob:
        _call_compat(f, (idx, slot, True), (idx, slot), (idx,))
    elif slot >= 0:
        f(idx, slot)
    else:
        _call_compat(f, (idx,), (idx, -1))
    return True


def _av_preset(forward):
    if not _api_at_least(10):
        return False
    pl = _mod("plugins")
    if pl is None:
        return False
    return callable(getattr(pl, "nextPreset" if forward else "prevPreset", None))


def _a_mute():
    t = _selected_track()
    if t is None:
        return _no_track()
    f = _fn("mixer", "muteTrack") if _api_at_least(2) else None
    if f is not None:
        f(t)
    else:
        _fn("mixer", "enableTrack")(t)   # API 1 : même bascule
    return True


def _av_mute():
    return _has("mixer", "trackNumber") and (
        (_api_at_least(2) and _has("mixer", "muteTrack")) or _has("mixer", "enableTrack"))


def _a_solo():
    t = _selected_track()
    if t is None:
        return _no_track()
    _fn("mixer", "soloTrack")(t)    # index seul : value/mode sont arrivés plus tard
    return True


def _a_unsolo():
    count = _fn("mixer", "trackCount")
    is_solo = _fn("mixer", "isTrackSolo")
    solo = _fn("mixer", "soloTrack")
    n = count()
    if _is_int(n):
        for i in range(min(max(n, 0), 1000)):
            if is_solo(i):
                solo(i)
    cc = _fn("channels", "channelCount")
    ics = _fn("channels", "isChannelSolo")
    sc = _fn("channels", "soloChannel")
    if cc is not None and ics is not None and sc is not None:
        try:
            m = cc()
            if _is_int(m):
                for i in range(min(max(m, 0), 1000)):
                    if ics(i):
                        sc(i)
        except Exception as exc:
            _report(exc)
    return True


def _a_bypass():
    t = _selected_track()
    if t is None:
        return _no_track()
    enabled = bool(_fn("mixer", "isTrackSlotsEnabled")(t))
    # Toujours passer la valeur : sans elle, les slots sont coupés (bug < 25.1.99).
    _fn("mixer", "enableTrackSlots")(t, not enabled)
    _hint("FL Shortcuts : effets de la piste %s" % ("coupés" if enabled else "actifs"))
    return True


def _a_mono():
    setsep = _fn("mixer", "setTrackStereoSep")
    getsep = _fn("mixer", "getTrackStereoSep")
    cur = None
    if getsep is not None:
        try:
            cur = float(getsep(0))
        except Exception:
            cur = None
    if cur is not None:
        is_mono = cur <= -0.999
    else:
        is_mono = _st.mono_on
    if is_mono:
        restore = _st.mono_prev if _st.mono_prev is not None else 0.0
        setsep(0, restore)
        _st.mono_on = False
        _st.mono_prev = None
        _hint("FL Shortcuts : Master en stéréo")
    else:
        _st.mono_prev = cur if cur is not None else 0.0
        setsep(0, -1.0)
        _st.mono_on = True
        _hint("FL Shortcuts : Master en mono (réglage du projet, ré-appuie pour revenir)")
    return True


def _a_track(delta):
    sel = _fn("mixer", "setTrackNumber")
    if sel is None:
        return _gt("FPT_TrackJog", 101, delta)
    n = _fn("mixer", "trackCount")()
    if not _is_int(n) or n < 1:
        return _no_track()
    last = max(0, n - 2)      # la dernière piste est la « Current » (bug corrigé en 26.1.4)
    t = _fn("mixer", "trackNumber")()
    if not _is_int(t) or t < 0:
        t = 0
    target = min(max(0, t + delta), last)
    if target != t:
        _call_compat(sel, (target, _const("curfxScrollToMakeVisible", 1)), (target,))
    return True


def _av_track():
    return ((_has("mixer", "setTrackNumber") and _has("mixer", "trackCount")
             and _has("mixer", "trackNumber")) or _has_gt())


_INF = float("inf")


def _finite(x):
    return x == x and x != _INF and x != -_INF


def _a_volume(delta_db):
    t = _selected_track()
    if t is None:
        return _no_track()
    get = _fn("mixer", "getTrackVolume")
    setv = _fn("mixer", "setTrackVolume")
    cur = float(get(t))
    cur = min(max(cur, 0.0), 1.0)
    db = None
    try:
        db = float(get(t, 1))      # mode 1 = dB
    except TypeError:
        db = None
    if db is None or not _finite(db) or db < -200.0:
        step = 0.0125 if delta_db > 0 else -0.0125     # repli : pas normalisé (~)
        new = min(max(cur + step, 0.0), 1.0)
        if new != cur:
            setv(t, new)
        return True
    target = db + delta_db
    if (delta_db > 0 and cur >= 1.0) or (delta_db < 0 and cur <= 0.0):
        return True                 # déjà en butée
    # La courbe du fader n'est pas documentée : petit pas d'essai puis méthode de la sécante.
    # 4 écritures au plus, toutes proches de la cible (pas de saut audible, Mixer redessiné 4 fois au plus).
    x0, d0 = cur, db
    x1 = min(max(cur + (0.004 if delta_db > 0 else -0.004), 0.0), 1.0)
    setv(t, x1)
    d1 = float(get(t, 1))
    for _ in range(3):
        if not _finite(d1) or not _finite(d0) or d1 == d0 or abs(d1 - target) < 0.02:
            break
        x2 = min(max(x1 + (target - d1) * (x1 - x0) / (d1 - d0), 0.0), 1.0)
        if x2 == x1:
            break
        setv(t, x2)
        x0, d0, x1, d1 = x1, d1, x2, float(get(t, 1))
    return True


def _a_window(w):
    return _show(_wid(w))


def _a_plmx():
    if _focused(_wid(W_MIXER)):
        return _show(_wid(W_PLAYLIST))
    return _show(_wid(W_MIXER))


def _a_undo():
    f = _fn("general", "undoUp")
    if f is not None:
        f()
        return True
    return _gt("FPT_UndoUp", 21)


def _a_redo():
    _fn("general", "undoDown")()
    return True


def _av(*pairs, **kw):
    """Disponible si l'API minimale est atteinte et toutes les fonctions existent."""
    api_min = kw.get("api", 1)

    def check():
        if not _api_at_least(api_min):
            return False
        for p in pairs:
            if not _has(p[0], p[1]):
                return False
        return True
    return check


def _av_or_gt(mod_name, fn_name):
    return lambda: _has(mod_name, fn_name) or _has_gt()


_GT_ONLY = lambda: _has_gt()

# (id, clé, libellé, version FL minimale, disponible(), exécuter())
# Ids figés : PROTOCOL.md §6. Fonctions et API minimales : audit 04 §6.
ACTIONS = (
    (1, "play", "Lecture / Pause", "20.7", _av_or_gt("transport", "start"), _a_play),
    (2, "stop", "Stop", "20.7", _av_or_gt("transport", "stop"), _a_stop),
    (3, "rec", "Lancer le REC", "20.7", _av_or_gt("transport", "record"), _a_rec),
    (4, "metro", "Métronome", "20.7", _GT_ONLY, lambda: _gt("FPT_Metronome", 110)),
    (5, "count", "Décompte", "20.7", _GT_ONLY, lambda: _gt("FPT_CountDown", 115)),
    (6, "loop", "Enregistrement en boucle", "20.7", _GT_ONLY, lambda: _gt("FPT_LoopRecord", 113)),
    (7, "wait", "Attendre une note", "20.7", _GT_ONLY, lambda: _gt("FPT_WaitForInput", 111)),
    (8, "marker", "Poser un marqueur", "20.7", _av_marker, _a_marker),
    (9, "arm", "Armer la piste", "20.7",
     _av(("mixer", "trackNumber"), ("mixer", "armTrack")), _a_arm),
    (10, "tap", "Tap tempo", "20.7", _GT_ONLY, lambda: _gt("FPT_TapTempo", 106)),
    (11, "newpat", "Nouveau pattern", "20.7",
     _av(("patterns", "findFirstNextEmptyPat"), ("ui", "showWindow")), _a_newpat),
    (12, "clone", "Cloner le pattern", "21.0.3",
     _av(("patterns", "clonePattern"), api=25), _a_clone),
    (13, "pnext", "Pattern suivant", "20.7", _av_pattern, lambda: _a_pattern(1)),
    (14, "pprev", "Pattern précédent", "20.7", _av_pattern, lambda: _a_pattern(-1)),
    (15, "chnext", "Instrument suivant", "20.7", _av_channel, lambda: _a_channel(1)),
    (16, "chprev", "Instrument précédent", "20.7", _av_channel, lambda: _a_channel(-1)),
    (17, "snap", "Grille suivante", "20.7", _av_or_gt("ui", "snapMode"), _a_snap),
    (18, "quant", "Quantize rapide", "20.8",
     _av(("channels", "quickQuantize"), ("channels", "channelCount"), api=9), _a_quant),
    (19, "presetnext", "Preset suivant", "20.8.1", lambda: _av_preset(True), lambda: _a_preset(True)),
    (20, "presetprev", "Preset précédent", "20.8.1", lambda: _av_preset(False), lambda: _a_preset(False)),
    (21, "mute", "Mute piste Mixer", "20.7", _av_mute, _a_mute),
    (22, "solo", "Solo piste Mixer", "20.7",
     _av(("mixer", "trackNumber"), ("mixer", "soloTrack")), _a_solo),
    (23, "unsolo", "Retirer tous les solos", "20.7",
     _av(("mixer", "trackCount"), ("mixer", "isTrackSolo"), ("mixer", "soloTrack")), _a_unsolo),
    (24, "bypass", "Bypass des effets", "20.9.1",
     _av(("mixer", "trackNumber"), ("mixer", "enableTrackSlots"), ("mixer", "isTrackSlotsEnabled"),
         api=19), _a_bypass),
    (25, "mono", "Master en mono", "20.8.2", _av(("mixer", "setTrackStereoSep"), api=12), _a_mono),
    (26, "trnext", "Piste Mixer suivante", "20.7", _av_track, lambda: _a_track(1)),
    (27, "trprev", "Piste Mixer précédente", "20.7", _av_track, lambda: _a_track(-1)),
    (28, "volup", "Volume +0,5 dB", "20.7",
     _av(("mixer", "trackNumber"), ("mixer", "getTrackVolume"), ("mixer", "setTrackVolume")),
     lambda: _a_volume(0.5)),
    (29, "voldn", "Volume -0,5 dB", "20.7",
     _av(("mixer", "trackNumber"), ("mixer", "getTrackVolume"), ("mixer", "setTrackVolume")),
     lambda: _a_volume(-0.5)),
    (30, "pl", "Ouvrir la Playlist", "20.7", _av(("ui", "showWindow")), lambda: _a_window(W_PLAYLIST)),
    (31, "cr", "Ouvrir le Channel Rack", "20.7", _av(("ui", "showWindow")),
     lambda: _a_window(W_CHANNELRACK)),
    (32, "pr", "Ouvrir le Piano Roll", "20.7", _av(("ui", "showWindow")),
     lambda: _a_window(W_PIANOROLL)),
    (33, "mx", "Ouvrir le Mixer", "20.7", _av(("ui", "showWindow")), lambda: _a_window(W_MIXER)),
    (34, "br", "Ouvrir le Browser", "20.7", _av(("ui", "showWindow")), lambda: _a_window(W_BROWSER)),
    (35, "plmx", "Playlist / Mixer", "20.7", _av(("ui", "showWindow"), ("ui", "getFocused")), _a_plmx),
    (36, "undo", "Annuler", "20.7", _av_or_gt("general", "undoUp"), _a_undo),
    (37, "redo", "Rétablir", "20.7", _av(("general", "undoDown")), _a_redo),
    (38, "save", "Sauvegarder", "20.7", _GT_ONLY, lambda: _gt("FPT_Save", 92)),
    (39, "armon", "Armer la piste (si éteinte)", "20.7",
     _av(("mixer", "trackNumber"), ("mixer", "isTrackArmed"), ("mixer", "armTrack")), _a_armon),
    (40, "recon", "Allumer le REC (si éteint)", "20.7",
     _av(("transport", "isRecording"), ("transport", "record")), _a_recon),
)

ACTION_BY_ID = {}
for _entry in ACTIONS:
    ACTION_BY_ID[_entry[0]] = _entry
del _entry


def _compute_caps():
    caps = {}
    for entry in ACTIONS:
        ok = False
        try:
            ok = bool(entry[4]())
        except Exception:
            ok = False
        caps[entry[0]] = ok
    return caps


def _caps():
    if _st.caps is None:
        _st.caps = _compute_caps()
    return _st.caps


def capability_mask():
    """42 bits : bit (id-1) = action id disponible. 0 si la clé n'est pas installée."""
    if _signer is None:
        return 0
    mask = 0
    for aid, ok in _caps().items():
        if ok and 1 <= aid <= MAX_ACTION_ID:
            mask |= 1 << (aid - 1)
    if _data_available():
        mask |= 1 << (DATA_ACTION_ID - 1)
        if _ext_available():
            mask |= 1 << (EXT_ACTION_ID - 1)
    return mask


# --------------------------------------------------------------------------
# Commande avec données (action 41, PROTOCOL.md §7)
# --------------------------------------------------------------------------
def unpack7(units):
    """Inverse de l'empaquetage 7 bits : par groupe, une unité d'en-tête (bit j = bit 7 de l'octet j) puis
    jusqu'à 7 unités. None si mal formé."""
    out = []
    i = 0
    n = len(units)
    while i < n:
        hdr = units[i]
        body = units[i + 1:i + 8]
        if not body or hdr >> len(body):
            return None
        for j, u in enumerate(body):
            out.append(u | (0x80 if (hdr >> j) & 1 else 0))
        i += 1 + len(body)
    return out


def _data_available():
    return (_has("ui", "getFocused") and _has("mixer", "isTrackSelected")
            and _has("mixer", "setTrackName") and _has("mixer", "setTrackColor"))


def pack7(data):
    """Empaquetage 7 bits (PROTOCOL.md §7) : par groupe de 7 octets, une unité d'en-tête puis les 7 bits bas."""
    out = []
    for i in range(0, len(data), 7):
        group = data[i:i + 7]
        hdr = 0
        for j, b in enumerate(group):
            if b & 0x80:
                hdr |= 1 << j
        out.append(hdr)
        for b in group:
            out.append(b & 0x7F)
    return out


def _ext_available():
    return _has("utils", "ColorToRGB") and _has("utils", "RGBToColor")


def _run_data(units, seq3=(0, 0, 0)):
    """0 si exécutée, sinon la raison du refus (CC 116). Une opération qui répond envoie sa réponse signée
    (CC 112 à 115) avant l'accusé."""
    if not units or not _data_available():
        return REASON_DATA
    raw = unpack7(units)
    if not raw:
        return REASON_DATA
    op = raw[0]
    if op == OP_NAME_COLOR:
        return _op_name_color(raw)
    handler = _EXT_OPS.get(op)
    if handler is None:
        return REASON_DATA
    if not _ext_available():
        return REASON_OLD_FL
    try:
        return handler(raw, list(seq3))
    except Exception as exc:
        # Jamais de nom de son ni de piste dans le message : seulement le type de l'erreur.
        _hint("FL Shortcuts : « Organiser » a échoué (%s)" % type(exc).__name__)
        return REASON_DATA


# Page devant -> (module, nombre, est sélectionné, nom, couleur, premier index, API minimale de la sélection)
_NAME_COLOR_PAGES = {
    0: ("mixer", "trackCount", "isTrackSelected", "setTrackName", "setTrackColor", 0, 1),
    1: ("channels", "channelCount", "isChannelSelected", "setChannelName", "setChannelColor", 0, 1),
    2: ("playlist", "trackCount", "isTrackSelected", "setTrackName", "setTrackColor", 1, 12),
}


def _rgb_to_color(r, g, b):
    """Couleur au format de FL par sa propre fonction (la doc de FL hésite entre 0xRRGGBB et 0x--BBGGRR : pas de
    calcul de repli qui risquerait d'inverser rouge et bleu). None si indisponible."""
    f = _fn("utils", "RGBToColor")
    if f is None:
        return None
    try:
        c = f(r, g, b)
    except Exception:
        return None
    return c if _is_int(c) else None


def _name_color_target():
    """(fonctions, index) de l'unique élément sélectionné de la page devant, sinon la raison du refus."""
    page = _NAME_COLOR_PAGES.get(focused_window_code())
    if page is None:
        return REASON_PAGE
    mod, count_fn, sel_fn, name_fn, color_fn, first, api_min = page
    count, is_sel = _fn(mod, count_fn), _fn(mod, sel_fn)
    set_name, set_color = _fn(mod, name_fn), _fn(mod, color_fn)
    if None in (count, set_name, set_color):
        return REASON_PAGE
    if is_sel is None or not _api_at_least(api_min):
        return REASON_OLD_FL               # page connue, sélection lisible seulement dans un FL plus récent
    n = count()
    if not _is_int(n) or n < 0:
        return REASON_DATA
    found = []
    for i in range(first, n + first):
        if is_sel(i):
            found.append(i)
            if len(found) > 1:
                return REASON_MANY
    if not found:
        return REASON_NONE
    return (set_name, set_color), found[0]


def _op_name_color(raw):
    """[1, drapeaux (bit 0 nom, bit 1 couleur), R, G, B, n, nom UTF-8 (n octets)]. Le nom n'est jamais écrit
    dans un message de FL."""
    if len(raw) < 6:
        return REASON_DATA
    flags, r, g, b, n = raw[1], raw[2], raw[3], raw[4], raw[5]
    if flags & ~3 or not flags & 3 or len(raw) != 6 + n or (n and not flags & 1):
        return REASON_DATA
    name = None
    if flags & 1:
        try:
            name = bytes(raw[6:]).decode("utf-8")
        except Exception:
            return REASON_DATA
        if not name or len(name) > MAX_NAME_CHARS or any(ord(c) < 32 or ord(c) == 127 for c in name):
            return REASON_DATA
    color = None
    if flags & 2:
        color = _rgb_to_color(r, g, b)
        if color is None:
            return REASON_DATA
    try:
        target = _name_color_target()
    except Exception as exc:
        _hint("FL Shortcuts : sélection illisible (%s)" % type(exc).__name__)
        return REASON_DATA
    if _is_int(target):
        return target
    (set_name, set_color), index = target
    try:
        if name is not None:
            set_name(index, name)
        if color is not None:
            set_color(index, color)
    except Exception as exc:
        _hint("FL Shortcuts : « Nom et couleur » a échoué (%s)" % type(exc).__name__)
        return REASON_DATA
    return 0


# --------------------------------------------------------------------------
# Organiser et dégradé : opérations 2 à 8 (PROTOCOL.md §8)
# --------------------------------------------------------------------------
def _respond(op, data, seq3):
    """Réponse FL -> appli : CC 112 = op, CC 113 = unités, CC 114, puis 4 CC 115 =
    MAC(nonce || seq de la commande || op || unités). Liée à la commande : jamais rejouable ailleurs."""
    units = pack7(data)
    if len(units) > MAX_RESP_UNITS or _signer is None:
        return False
    mac = _signer.mac(bytes(list(_st.nonce) + list(seq3) + [op] + units))
    pairs = [(CC_RESP_START, op)] + [(CC_RESP_UNIT, u) for u in units] + [(CC_RESP_END, 0)]
    pairs += [(CC_RESP_MAC, m) for m in mac]
    return _send_many(pairs)


def _be16(hi, lo):
    return (hi << 8) | lo


def _u16(n):
    n = n if _is_int(n) and 0 <= n <= 0xFFFF else 0
    return [(n >> 8) & 0xFF, n & 0xFF]


def _fns(mod, *names):
    """Fonctions du module dans l'ordre, ou None si l'une manque."""
    out = []
    for n in names:
        f = _fn(mod, n)
        if f is None:
            return None
        out.append(f)
    return out


def _rgb_of(color):
    """Couleur de FL -> [R, G, B] par utils.ColorToRGB (la fonction de FL, donc son ordre)."""
    rgb = [int(v) for v in _fn("utils", "ColorToRGB")(color)][:3]
    if len(rgb) != 3 or any(not 0 <= v <= 255 for v in rgb):
        raise ValueError("couleur")
    return rgb


def _name_bytes(name):
    """Nom en UTF-8, coupé à LIST_NAME_BYTES octets sans couper un caractère."""
    try:
        raw = str(name).encode("utf-8")
    except Exception:
        return []
    return list(raw[:LIST_NAME_BYTES].decode("utf-8", "ignore").encode("utf-8"))


def _channel_count():
    f = _fn("channels", "channelCount")
    return f() if f is not None else 0


def _op_list(raw, seq3):
    """[2, genre, début (2)] -> [genre, total (2), début (2), n, filtré] + entrées (16 au plus). Playlist : entrée
    [sélectionnée, R, G, B, longueur, nom], index 0 = piste 1 de FL."""
    if len(raw) != 4 or raw[1] not in (KIND_CHANNELS, KIND_MIXER, KIND_PLAYLIST):
        return REASON_DATA
    kind, start = raw[1], _be16(raw[2], raw[3])
    get_type = None
    if kind == KIND_PLAYLIST:
        return _list_playlist(start, seq3)
    if kind == KIND_CHANNELS:
        fns = _fns("channels", "channelCount", "getChannelName", "getChannelColor", "getTargetFxTrack")
        if fns is None:
            return REASON_OLD_FL
        count, get_name, get_color, get_fx = fns
        if _api_at_least(19):
            get_type = _fn("channels", "getChannelType")
        total = count()
        try:
            filtered = 1 if count(True) != total else 0
        except Exception:
            filtered = 0                   # FL ancien : pas de nombre global
    else:
        fns = _fns("mixer", "trackCount", "getTrackName", "getTrackColor")
        if fns is None:
            return REASON_OLD_FL
        count, get_name, get_color = fns
        total = count()
        filtered = 0
    if not _is_int(total) or not 0 <= start <= total:
        return REASON_DATA
    n = min(LIST_PAGE, total - start)
    data = [kind] + _u16(total) + _u16(start) + [n, filtered]
    for i in range(start, start + n):
        name = _name_bytes(get_name(i))
        rgb = _rgb_of(get_color(i))
        if kind == KIND_CHANNELS:
            t = get_type(i) if get_type is not None else 0
            t = t if _is_int(t) and 0 <= t <= 255 else 0
            data += [t] + _u16(get_fx(i)) + rgb + [len(name)] + name
        else:
            data += rgb + [len(name)] + name
    return 0 if _respond(OP_LIST, data, seq3) else REASON_DATA


def _list_playlist(start, seq3):
    fns = _fns("playlist", "trackCount", "getTrackName", "getTrackColor")
    if fns is None:
        return REASON_OLD_FL
    count, get_name, get_color = fns
    selected = _fn("playlist", "isTrackSelected") if _api_at_least(12) else None
    total = count()
    if not _is_int(total) or not 0 <= start <= total:
        return REASON_DATA
    n = min(LIST_PAGE, total - start)
    data = [KIND_PLAYLIST] + _u16(total) + _u16(start) + [n, 0]
    for i in range(start, start + n):
        name = _name_bytes(get_name(i + 1))
        sel = 1 if selected is not None and selected(i + 1) else 0
        data += [sel] + _rgb_of(get_color(i + 1)) + [len(name)] + name
    return 0 if _respond(OP_LIST, data, seq3) else REASON_DATA


def _kind_fns(kind):
    """(nombre, poser la couleur) du genre, ou une raison de refus."""
    if kind == KIND_CHANNELS:
        fns = _fns("channels", "channelCount", "setChannelColor")
    elif kind == KIND_MIXER:
        fns = _fns("mixer", "trackCount", "setTrackColor")
    elif kind == KIND_PLAYLIST:
        fns = _fns("playlist", "trackCount", "setTrackColor")
        if fns is not None:                  # index 0 = piste 1 de FL
            count, set_color = fns
            fns = (count, lambda i, c: set_color(i + 1, c))
    else:
        return REASON_DATA
    return fns if fns is not None else REASON_OLD_FL


def _op_set_colors(raw, seq3):
    """[4, genre, n, (index (2), R, G, B) x n], n <= 64 : tout est vérifié avant de poser la première couleur."""
    if len(raw) < 3:
        return REASON_DATA
    kind, n = raw[1], raw[2]
    if not 1 <= n <= MAX_COLORS or len(raw) != 3 + 5 * n:
        return REASON_DATA
    fns = _kind_fns(kind)
    if _is_int(fns):
        return fns
    count, set_color = fns
    total = count()
    todo = []
    for k in range(n):
        o = 3 + 5 * k
        index = _be16(raw[o], raw[o + 1])
        color = _rgb_to_color(raw[o + 2], raw[o + 3], raw[o + 4])
        if not _is_int(total) or not 0 <= index < total or color is None:
            return REASON_DATA
        todo.append((index, color))
    for index, color in todo:
        set_color(index, color)
    return 0


def _op_select_one(raw, seq3):
    """[5, genre, index (2)] : cet élément seul sélectionné."""
    if len(raw) != 4:
        return REASON_DATA
    kind, index = raw[1], _be16(raw[2], raw[3])
    if kind == KIND_CHANNELS:
        fns = _fns("channels", "channelCount", "selectOneChannel")
        if fns is None or not _api_at_least(8):
            return REASON_OLD_FL
        total = fns[0]()
        if not _is_int(total) or not 0 <= index < total:
            return REASON_DATA
        fns[1](index)
        return 0
    if kind == KIND_MIXER:
        count = _fn("mixer", "trackCount")
        active = _fn("mixer", "setActiveTrack") if _api_at_least(27) else None
        pair = _fns("mixer", "deselectAll", "selectTrack")
        if count is None or (active is None and pair is None):
            return REASON_OLD_FL
        total = count()
        if not _is_int(total) or not 0 <= index < total:
            return REASON_DATA
        if active is not None:
            active(index)
        else:
            pair[0]()
            pair[1](index)
        return 0
    return REASON_DATA


_PLAY_FNS = (("channels", "channelCount"), ("channels", "isChannelMuted"), ("channels", "muteChannel"),
             ("transport", "start"), ("transport", "stop"), ("transport", "isPlaying"),
             ("transport", "getLoopMode"), ("transport", "setLoopMode"), ("transport", "getSongPos"),
             ("transport", "setSongPos"))


def _op_play_solo(raw, seq3):
    """[6, canal (2)] : au premier appel, mémo des sourdines, du mode et de la position ; puis ce canal seul
    audible (les autres en sourdine, en ne basculant que ceux qui doivent changer), mode pattern, début, lecture."""
    if len(raw) != 3:
        return REASON_DATA
    if any(_fn(m, n) is None for m, n in _PLAY_FNS):
        return REASON_OLD_FL
    index = _be16(raw[1], raw[2])
    total = _channel_count()
    if not _is_int(total) or not 0 <= index < total:
        return REASON_DATA
    is_muted, mute = _fn("channels", "isChannelMuted"), _fn("channels", "muteChannel")
    if _st.memo is not None and _st.memo.get("kind", "ch") != "ch":
        _restore_memo()                    # une écoute de la Playlist était en cours
    playing = _fn("transport", "isPlaying")()
    if _st.memo is None:
        if playing:
            return REASON_PLAYING          # l'utilisateur joue : on ne coupe rien
        _st.memo = {"kind": "ch", "n": total, "muted": [bool(is_muted(i)) for i in range(total)],
                    "mode": _fn("transport", "getLoopMode")(), "pos": _fn("transport", "getSongPos")()}
    elif playing:
        _fn("transport", "stop")()
    for i in range(total):
        want = i != index
        if bool(is_muted(i)) != want:
            mute(i)
    if _fn("transport", "getLoopMode")() != 0:
        _fn("transport", "setLoopMode")()
    _fn("transport", "setSongPos")(0.0)
    _fn("transport", "start")()
    return 0


_PL_PLAY_FNS = (("playlist", "trackCount"), ("playlist", "isTrackMuted"), ("playlist", "muteTrack"),
                ("transport", "start"), ("transport", "stop"), ("transport", "isPlaying"),
                ("transport", "getLoopMode"), ("transport", "setLoopMode"), ("transport", "getSongPos"),
                ("transport", "setSongPos"))


def _op_play_track(raw, seq3):
    """[11, piste (2)] -> [longueur de la chanson en mesures (2)] : comme l'opération 6, pour une piste de la
    Playlist : au premier appel, mémo des sourdines des pistes, du mode et de la position ; puis cette piste seule
    audible, mode chanson, début, lecture."""
    if len(raw) != 3:
        return REASON_DATA
    if any(_fn(m, n) is None for m, n in _PL_PLAY_FNS):
        return REASON_OLD_FL
    index = _be16(raw[1], raw[2])
    total = _fn("playlist", "trackCount")()
    if not _is_int(total) or not 0 <= index < total:
        return REASON_DATA
    is_muted, mute = _fn("playlist", "isTrackMuted"), _fn("playlist", "muteTrack")
    if _st.memo is not None and _st.memo.get("kind", "ch") != "pl":
        _restore_memo()                    # une écoute du Channel rack était en cours
    playing = _fn("transport", "isPlaying")()
    if _st.memo is None:
        if playing:
            return REASON_PLAYING
        _st.memo = {"kind": "pl", "n": total, "muted": [bool(is_muted(i + 1)) for i in range(total)],
                    "mode": _fn("transport", "getLoopMode")(), "pos": _fn("transport", "getSongPos")()}
    elif playing:
        _fn("transport", "stop")()
    for i in range(total):
        want = i != index
        if bool(is_muted(i + 1)) != want:
            mute(i + 1)
    if _fn("transport", "getLoopMode")() != 1:
        _fn("transport", "setLoopMode")()
    _fn("transport", "setSongPos")(0.0)
    _fn("transport", "start")()
    length = _fn("transport", "getSongLength")
    bars = 0
    if length is not None and _api_at_least(3):
        try:
            bars = int(length(_const("SONGLENGTH_BARS", 3)))
        except Exception:
            bars = 0
    return 0 if _respond(OP_PLAY_TRACK, _u16(max(0, bars)), seq3) else REASON_DATA


def _op_seek(raw, seq3):
    """[12, pour mille (2)] : position de la chanson, seulement pendant une écoute de la Playlist."""
    if len(raw) != 3:
        return REASON_DATA
    permille = _be16(raw[1], raw[2])
    if _st.memo is None or _st.memo.get("kind") != "pl" or permille > 1000:
        return REASON_DATA
    _fn("transport", "setSongPos")(permille / 1000.0)
    return 0


def _op_page(raw, seq3):
    """[9] -> [code de la page devant] (0 Mixer, 1 Channel rack, 2 Playlist…, 127 aucune)."""
    if len(raw) != 1:
        return REASON_DATA
    return 0 if _respond(OP_PAGE, [focused_window_code()], seq3) else REASON_DATA


def _op_set_names(raw, seq3):
    """[10, genre, n, (index (2), longueur, nom UTF-8) x n] : noms des pistes de la Playlist (genre 3), tout vérifié
    avant d'en poser un."""
    if len(raw) < 3 or raw[1] != KIND_PLAYLIST:
        return REASON_DATA
    n = raw[2]
    fns = _fns("playlist", "trackCount", "setTrackName")
    if fns is None:
        return REASON_OLD_FL
    count, set_name = fns
    total = count()
    if not 1 <= n <= MAX_NAMES or not _is_int(total):
        return REASON_DATA
    todo, at = [], 3
    for _ in range(n):
        if at + 3 > len(raw):
            return REASON_DATA
        index, size = _be16(raw[at], raw[at + 1]), raw[at + 2]
        at += 3
        if not 0 <= index < total or not 1 <= size <= NAME_MAX_BYTES or at + size > len(raw):
            return REASON_DATA
        try:
            name = bytes(raw[at:at + size]).decode("utf-8")
        except Exception:
            return REASON_DATA
        at += size
        todo.append((index, name))
    if at != len(raw):
        return REASON_DATA
    for index, name in todo:
        set_name(index + 1, name)
    return 0


def _restore_memo():
    """Arrêt de la lecture, sourdines, mode et position remis comme au mémo, mémo vidé. Rien sans mémo."""
    memo = _st.memo
    _st.memo = None
    if memo is None:
        return

    def stop():
        _fn("transport", "stop")()

    def mutes():
        if memo.get("kind", "ch") == "pl":
            is_muted, mute = _fn("playlist", "isTrackMuted"), _fn("playlist", "muteTrack")
            count = _fn("playlist", "trackCount")()
            for i in range(min(memo["n"], count if _is_int(count) else 0)):
                if bool(is_muted(i + 1)) != memo["muted"][i]:
                    mute(i + 1)
            return
        is_muted, mute = _fn("channels", "isChannelMuted"), _fn("channels", "muteChannel")
        for i in range(min(memo["n"], _channel_count())):
            if bool(is_muted(i)) != memo["muted"][i]:
                mute(i)

    def mode():
        if _fn("transport", "getLoopMode")() != memo["mode"]:
            _fn("transport", "setLoopMode")()

    def pos():
        _fn("transport", "setSongPos")(memo["pos"])

    for step in (stop, mutes, mode, pos):
        try:                               # une étape qui échoue n'empêche pas les suivantes
            step()
        except Exception as exc:
            _hint("FL Shortcuts : remise après l'écoute incomplète (%s)" % type(exc).__name__)


def _restore_memo_safely():
    try:
        _restore_memo()
    except Exception:
        _st.memo = None


def _op_stop_restore(raw, seq3):
    """[7] : remet FL comme avant l'écoute (sans effet s'il n'y a pas eu d'écoute)."""
    if len(raw) != 1:
        return REASON_DATA
    _restore_memo()
    return 0


def _op_audition(raw, seq3):
    """[3, canal (2), note, vélocité] : note jouée sur le canal (vélocité 0 = arrêt)."""
    if len(raw) != 5 or raw[3] > 127 or raw[4] > 127:
        return REASON_DATA
    note_on = _fn("channels", "midiNoteOn")
    if note_on is None:
        return REASON_OLD_FL
    index = _be16(raw[1], raw[2])
    total = _channel_count()
    if not _is_int(total) or not 0 <= index < total:
        return REASON_DATA
    to_global = _fn("channels", "getChannelIndex")
    note_on(to_global(index) if to_global is not None else index, raw[3], raw[4])
    return 0


def _selected_targets():
    """(poser la couleur, [index sélectionnés]) sur la page devant, sinon la raison du refus."""
    page = _NAME_COLOR_PAGES.get(focused_window_code())
    if page is None:
        return REASON_PAGE
    mod, count_fn, sel_fn, _name_fn, color_fn, first, api_min = page
    count, is_sel, set_color = _fn(mod, count_fn), _fn(mod, sel_fn), _fn(mod, color_fn)
    if count is None or set_color is None:
        return REASON_PAGE
    if is_sel is None or not _api_at_least(api_min):
        return REASON_OLD_FL
    n = count()
    if not _is_int(n) or n < 0:
        return REASON_DATA
    return set_color, [i for i in range(first, n + first) if is_sel(i)]


def _op_gradient(raw, seq3):
    """[8, R1, G1, B1, R2, G2, B2] : dégradé de First (premier sélectionné) à Last (dernier), comme
    « Gradient color… » de FL : chaque composante en ligne droite, arrondie au plus proche."""
    if len(raw) != 7:
        return REASON_DATA
    target = _selected_targets()
    if _is_int(target):
        return target
    set_color, picked = target
    if not picked:
        return REASON_NONE
    if len(picked) < 2:
        return REASON_FEW
    a, b = raw[1:4], raw[4:7]
    last = len(picked) - 1
    colors = []
    for k in range(len(picked)):
        rgb = [int(a[c] + (b[c] - a[c]) * k / float(last) + 0.5) for c in range(3)]
        color = _rgb_to_color(rgb[0], rgb[1], rgb[2])
        if color is None:
            return REASON_DATA
        colors.append(color)
    for index, color in zip(picked, colors):
        set_color(index, color)
    return 0


_EXT_OPS = {
    OP_LIST: _op_list,
    OP_AUDITION: _op_audition,
    OP_SET_COLORS: _op_set_colors,
    OP_SELECT_ONE: _op_select_one,
    OP_PLAY_SOLO: _op_play_solo,
    OP_STOP_RESTORE: _op_stop_restore,
    OP_GRADIENT: _op_gradient,
    OP_PAGE: _op_page,
    OP_SET_NAMES: _op_set_names,
    OP_PLAY_TRACK: _op_play_track,
    OP_SEEK: _op_seek,
}


# --------------------------------------------------------------------------
# Handshake
# --------------------------------------------------------------------------
def hello_messages():
    mask = capability_mask()
    pairs = [(CC_HELLO, 1)]
    for i in range(4):
        pairs.append((CC_NONCE_FIRST + i, _st.nonce[i]))
    pairs.append((CC_API, min(max(_api(), 0), 127)))
    pairs.append((CC_PROTO, PROTOCOL_VERSION))
    for k in range(6):
        pairs.append((CC_CAPS_FIRST + k, (mask >> (7 * k)) & 0x7F))
    pairs.append((CC_HELLO, 127))
    return pairs


def _send_hello():
    _st.last_hello_try = _now()
    if _send_many(hello_messages()):
        _st.hello_pending = False
        _st.out_ok = True
        _st.win_code = None        # renvoyer la fenêtre active juste après
        _st.win_dirty = True
        return True
    _st.hello_pending = True
    return False


def _on_ping(value):
    if value not in (PING_AWAKE, PING_BRIEF):
        return
    now = _now()
    if _st.last_ping is not None and now - _st.last_ping < MIN_PING_INTERVAL:
        return
    _st.last_ping = now
    _st.data = None
    _wake(brief=value == PING_BRIEF)
    _new_session()
    _st.caps = None
    _send_hello()


# --------------------------------------------------------------------------
# Trames authentifiées
# --------------------------------------------------------------------------
def _prune(times, now, window=1.0):
    while times and now - times[0] >= window:
        times.pop(0)


def _throttled_hint(key, text):
    now = _now()
    last = _st.last_hint.get(key)
    if last is None or now - last >= HINT_MIN_INTERVAL:
        _st.last_hint[key] = now
        _hint(text)


def _reject(reason_key, text):
    now = _now()
    _prune(_st.reject_ack_times, now)
    if len(_st.reject_ack_times) < MAX_REJECT_ACKS_PER_S:
        _st.reject_ack_times.append(now)
        _send_cc(CC_ACK, 0)
    _throttled_hint(reason_key, text)
    return False


def _asleep_reject():
    now = _now()
    _prune(_st.reject_ack_times, now)
    if len(_st.reject_ack_times) < MAX_REJECT_ACKS_PER_S and _output_ready():
        _st.reject_ack_times.append(now)
        try:
            _out_raw(CC_ACK, 0)
        except Exception:
            pass


def _on_data_cc(cc, value):
    """Données de la prochaine trame (action 41). Une unité sans CC 96 est ignorée."""
    if cc == CC_DATA_START:
        _st.data = []
        _st.data_bad = False
        return
    if _st.data is None:
        return
    if len(_st.data) >= MAX_DATA_UNITS:
        _st.data_bad = True
        return
    _st.data.append(value)


def _on_frame_cc(cc, value):
    if cc == CC_FRAME_FIRST:
        if _st.frame is not None:
            _reject("partial", "FL Shortcuts : trame incomplète ignorée")
        _st.frame = [value]
        return
    frame = _st.frame
    if frame is None or cc != CC_FRAME_FIRST + len(frame):
        _st.frame = None
        _reject("mixed", "FL Shortcuts : trame mélangée ignorée")
        return
    frame.append(value)
    if len(frame) == FRAME_LEN:
        _st.frame = None
        units = None if _st.data_bad else _st.data
        _st.data = None                # les données ne servent qu'à la trame qui les suit
        _st.data_bad = False
        _process_frame(frame, units)


def _process_frame(f, units=None):
    if _signer is None:
        if KEY is None:
            return _reject("nokey", "FL Shortcuts : clé absente, réinstalle le script depuis l'appli FL Shortcuts")
        return _reject("nomac", "FL Shortcuts : HMAC indisponible dans ce Python, commandes refusées")
    seq = (f[0] << 14) | (f[1] << 7) | f[2]
    aid = f[3]
    if aid not in ACTION_BY_ID and aid != DATA_ACTION_ID:
        return _reject("id", "FL Shortcuts : action %d inconnue (mets à jour le script)" % aid)
    if seq <= _st.last_seq:
        return _reject("replay", "FL Shortcuts : commande rejouée refusée")
    now = _now()
    _prune(_st.fail_times, now)
    _prune(_st.check_times, now)
    if len(_st.fail_times) >= MAX_MAC_FAILS_PER_S or len(_st.check_times) >= MAX_MAC_CHECKS_PER_S:
        return _reject("flood", "FL Shortcuts : trop de commandes invalides, pause")
    _st.check_times.append(now)
    signed = list(_st.nonce) + list(f[0:4])
    if aid == DATA_ACTION_ID and units:
        signed += units                # le MAC couvre les données
    expected = _signer.mac(bytes(signed))
    if not _ct_equal(expected, f[4:8]):
        _st.fail_times.append(now)
        return _reject("mac", "FL Shortcuts : commande non signée refusée")
    _st.last_seq = seq                 # trame authentique : consommée même si non exécutée
    _keep_awake()                      # seule une trame signée prolonge un réveil bref
    try:
        _prune(_st.action_times, now)
        if len(_st.action_times) >= MAX_ACTIONS_PER_S:
            return _reject("rate", "FL Shortcuts : trop d'actions par seconde")
        _st.action_times.append(now)
        if aid == DATA_ACTION_ID:
            reason = _run_data(units, f[0:3])
            if reason:
                _send_cc(CC_REASON, reason)
            ok = not reason
        else:
            ok = _run_action(aid)
        _send_cc(CC_ACK, aid if ok else 0)
        return ok
    finally:
        if seq >= SEQ_MAX:             # séquence épuisée : nouvelle session annoncée
            _new_session()
            _send_hello()


def _run_action(aid):
    entry = ACTION_BY_ID.get(aid)
    if entry is None:
        return False
    if not _caps().get(aid, False):
        _hint("FL Shortcuts : « %s » demande FL Studio %s ou plus récent" % (entry[2], entry[3]))
        return False
    try:
        r = entry[5]()
    except Exception as exc:
        _hint("FL Shortcuts : « %s » a échoué (%r)" % (entry[2], exc))
        return False
    return r is not False


# --------------------------------------------------------------------------
# Fenêtre active (CC 117) et battement (CC 118)
# --------------------------------------------------------------------------
_WINDOW_CODES = (
    (W_MIXER, 0), (W_CHANNELRACK, 1), (W_PLAYLIST, 2), (W_PIANOROLL, 3), (W_BROWSER, 4),
    (W_PLUGIN, 5), (W_PLUGIN_EFFECT, 5), (W_PLUGIN_GENERATOR, 5),
)


def focused_window_code():
    if _fn("ui", "getFocused") is None:
        return 127
    for w, code in _WINDOW_CODES:
        if _focused(_wid(w)):
            return code
    return 127


def _check_window(now):
    _st.win_checked = now
    _st.win_dirty = False
    code = focused_window_code()
    if code != _st.win_code:
        if _send_cc(CC_WINDOW, code):
            _st.win_code = code


def _idle():
    st = _st
    if not st.awake:
        return                       # endormi : aucun travail dans la boucle de FL
    now = _now()
    if st.awake_until is not None and now >= st.awake_until:
        _sleep()
        return
    st.ticks += 1
    # Changement de fenêtre signalé par OnRefresh : traité au passage suivant (~20 ms), au plus toutes les
    # 100 ms, et seulement si l'appli peut le recevoir.
    if st.win_dirty and st.out_ok and (st.win_checked is None
                                       or not 0 <= now - st.win_checked < WINDOW_MIN_INTERVAL):
        _check_window(now)
    # Le moins de travail possible dans la boucle de FL : rien n'a besoin d'être vérifié plus de 20 fois
    # par seconde (sans horloge, le pseudo-temps avance de 20 ms par appel : pas de limitation).
    if _time is not None and _st.last_idle is not None and 0 <= now - _st.last_idle < IDLE_MIN_INTERVAL:
        return
    _st.last_idle = now
    if _st.hello_pending and (_st.last_hello_try is None
                              or now - _st.last_hello_try >= HELLO_RETRY_INTERVAL):
        _send_hello()
    if _st.last_beat is None or now - _st.last_beat >= HEARTBEAT_PERIOD:
        _st.last_beat = now
        ready = _output_ready()
        if ready and _st.out_ok is False:
            _st.hello_pending = True    # la sortie vient d'être reliée : se réannoncer
        _st.out_ok = ready
        if ready:
            _st.beat ^= 1
            _send_cc(CC_HEARTBEAT, _st.beat)
            _st.win_dirty = True        # vérification de secours de la fenêtre, toutes les 2 s


# --------------------------------------------------------------------------
# Callbacks FL Studio (aucune exception ne doit en sortir)
# --------------------------------------------------------------------------
_COMMAND_CCS = frozenset(list(range(CC_PING, CC_FRAME_LAST + 1))    # 103..111 et 96, 97 : traités
                         + [CC_DATA_START, CC_DATA_UNIT])
# Tous les CC du protocole (y compris FL -> appli, si le port les renvoie en boucle) :
# marqués « handled » sur le canal 16 ; les autres CC sont laissés à FL.
_PROTOCOL_CCS = frozenset(list(range(CC_CAPS_FIRST, CC_CAPS_FIRST + 6)) + list(_COMMAND_CCS)
                          + list(range(CC_RESP_START, CC_PROTO + 1)))


def _cc_of(event):
    """(cc, valeur) si l'événement est un CC sur le canal 16, sinon (None, None)."""
    mid = getattr(event, "midiId", None)
    chan = getattr(event, "midiChan", None)
    if not _is_int(mid) or not _is_int(chan):
        status = getattr(event, "status", None)
        if not _is_int(status):
            return None, None
        mid = status & 0xF0
        chan = status & 0x0F
    if mid != _const("MIDI_CONTROLCHANGE", 0xB0) or chan != MIDI_CHANNEL:
        return None, None
    d1 = getattr(event, "data1", None)
    d2 = getattr(event, "data2", None)
    if not _is_int(d1) or not _is_int(d2):
        return None, None
    return d1, d2


def _midi_msg(event):
    cc, value = _cc_of(event)
    if cc is None or cc not in _PROTOCOL_CCS:
        return                       # pas à nous : FL le traite normalement
    event.handled = True
    if cc not in _COMMAND_CCS:
        return                       # écho de nos propres messages : ignoré
    if not 0 <= value <= 127:
        _st.frame = None
        return
    if cc == CC_PING:
        _on_ping(value)
    elif cc in (CC_DATA_START, CC_DATA_UNIT):
        if _st.awake:
            _on_data_cc(cc, value)
    elif _st.awake:
        _on_frame_cc(cc, value)
    elif cc == CC_FRAME_LAST:
        # Endormi (FL vient de recharger le script…) : une trame complète n'est pas exécutée, mais un refus
        # (accusé 0, borné) dit à l'appli de se resynchroniser par un PING. Seuls les PING réveillent.
        _asleep_reject()


def _init():
    _st.api = None
    _st.fl_version = None
    _st.caps = None
    _new_session()
    _api()
    _fl_version()
    _caps()
    if KEY is None:
        msg = "FL Shortcuts : clé absente, réinstalle le script depuis l'appli. Commandes refusées."
    elif _signer is None:
        msg = "FL Shortcuts : HMAC indisponible, commandes refusées."
    else:
        n = len([1 for v in _caps().values() if v])
        msg = "FL Shortcuts prêt (script v%d, API %d, %d/%d actions)" % (
            SCRIPT_VERSION, _api(), n, len(ACTIONS))
    if _gt_buggy():
        msg += " - FL 26.1.0-26.1.6 : mets à jour vers 26.1.7 (bugs du scripting MIDI)"
    _hint(msg)
    # Endormi jusqu'au premier PING de l'appli : rien n'est envoyé tant qu'on n'en a pas besoin.
    _sleep()


def OnInit():
    try:
        _init()
    except Exception as exc:
        _report(exc)


def OnDeInit():
    try:
        _restore_memo_safely()        # script déchargé pendant une écoute : FL remis comme avant
        _st.frame = None
        _st.hello_pending = False
        _st.out_ok = None
        _st.win_code = None
    except Exception as exc:
        _report(exc)


def OnMidiMsg(event):
    try:
        _midi_msg(event)
    except Exception as exc:
        _report(exc)


def OnIdle():
    try:
        _idle()
    except Exception as exc:
        _report(exc)


_FOCUS_BIT = 32                  # midi.HW_Dirty_FocusedWindow (valeur fixe depuis l'API 1)


def OnRefresh(flags):
    try:
        # Aucun appel à FL pendant sa diffusion de rafraîchissement : on marque, OnIdle s'en charge.
        if _st.awake and _is_int(flags) and flags & _FOCUS_BIT:
            _st.win_dirty = True
    except Exception as exc:
        _report(exc)
