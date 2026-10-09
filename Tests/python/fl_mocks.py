"""Modules FL Studio simulés, paramétrables par version d'API.

Chaque fonction n'existe qu'à partir de son API minimale (stubs officiels, audit 04).
Les fonctions vérifient leurs bornes comme FL (TypeError « index out of range »).
"""
import hashlib
import hmac
import math
import os
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SCRIPT = os.environ.get("FLSHORTCUT_SCRIPT", os.path.join(ROOT, "Resources", "device_FLShortcut.py"))

FL_MODULES = ("midi", "transport", "ui", "general", "mixer", "channels", "patterns",
              "device", "plugins", "arrangement", "playlist")

TEST_KEY_HEX = "000102030405060708090a0b0c0d0e0f"
TEST_KEY = bytes(range(16))

# Constantes du module midi : (valeur, API minimale de la constante dans la simulation).
MIDI_CONSTS = {
    "MIDI_CONTROLCHANGE": (0xB0, 1), "MIDI_NOTEON": (0x90, 1), "MIDI_NOTEOFF": (0x80, 1),
    "widMixer": (0, 1), "widChannelRack": (1, 1), "widPlaylist": (2, 1), "widPianoRoll": (3, 1),
    "widBrowser": (4, 1), "widPlugin": (5, 1), "widPluginEffect": (6, 1), "widPluginGenerator": (7, 1),
    "FPT_Play": (10, 1), "FPT_Stop": (11, 1), "FPT_Record": (12, 1), "FPT_UndoUp": (21, 1),
    "FPT_AddMarker": (33, 1), "FPT_SnapMode": (49, 1), "FPT_Save": (92, 1),
    "FPT_PatternJog": (100, 1), "FPT_TrackJog": (101, 1), "FPT_ChannelJog": (102, 1),
    "FPT_TapTempo": (106, 1), "FPT_Metronome": (110, 1), "FPT_WaitForInput": (111, 1),
    # constantes « récentes » absentes des vieux midi.py simulés : le script doit avoir un repli
    "FPT_LoopRecord": (113, 9), "FPT_CountDown": (115, 9),
    "SONGLENGTH_ABSTICKS": (2, 3), "FFNEP_DontPromptName": (1, 1),
    "curfxScrollToMakeVisible": (1, 1), "HW_Dirty_FocusedWindow": (32, 1),
}


def fl_version_for_api(api):
    if api >= 45:
        return (26, 1, 7)
    if api >= 41:
        return (26, 1, 3)
    if api >= 28:
        return (21, 0, 3)
    if api >= 20:
        return (20, 9, 2)
    if api >= 15:
        return (20, 8, 4)
    return (20, 7, 0)


class FLState(object):
    def __init__(self, api, **kw):
        self.api = api
        self.calls = []
        self.out = []                    # messages device.midiOutMsg (entiers combinés)
        self.hints = []
        self.n_tracks = kw.get("n_tracks", 127)
        self.track = kw.get("track", 3)
        self.n_channels = kw.get("n_channels", 8)
        self.channel = kw.get("channel", 0)
        self.pattern = kw.get("pattern", 1)
        self.pattern_count = kw.get("pattern_count", 4)
        self.focused = set(kw.get("focused", ()))
        self.assigned = kw.get("assigned", True)
        self.fl_version = kw.get("fl_version", fl_version_for_api(api))
        self.loop_mode = kw.get("loop_mode", 1)   # 1 = Song
        self.volumes = {}
        self.solo = set(kw.get("solo", ()))
        self.ch_solo = set(kw.get("ch_solo", ()))
        self.slots_enabled = {}
        self.stereo_sep = {0: kw.get("master_sep", 0.25)}
        self.raise_on = dict(kw.get("raise_on", {}))   # "module.fn" -> exception

    def cc_out(self):
        """Liste (statut, cc, valeur) des messages envoyés."""
        return [(m & 0xFF, (m >> 8) & 0xFF, (m >> 16) & 0xFF) for m in self.out]

    def names(self):
        return [c[0] for c in self.calls]

    def called(self, name):
        return [c[1] for c in self.calls if c[0] == name]


def vol_to_db(v):
    if v <= 0:
        return float("-inf")
    return 40.0 * math.log10(v / 0.8)


def build_fl(api=45, missing=(), extra=None, **kw):
    """Construit les 11 modules FL simulés pour la version d'API donnée."""
    st = FLState(api, **kw)
    mods = {}
    for name in FL_MODULES:
        mods[name] = types.ModuleType(name)

    def reg(modname, fname, api_min, impl):
        if api < api_min or ("%s.%s" % (modname, fname)) in missing:
            return
        full = "%s.%s" % (modname, fname)

        def f(*args):
            st.calls.append((full, args))
            exc = st.raise_on.get(full)
            if exc is not None:
                raise exc
            return impl(*args)
        f.__name__ = fname
        setattr(mods[modname], fname, f)

    def chk_track(i):
        if not isinstance(i, int) or not 0 <= i < st.n_tracks:
            raise TypeError("Track index out of range")

    def chk_chan(i):
        if not isinstance(i, int) or not 0 <= i < st.n_channels:
            raise TypeError("Channel index out of range")

    def maxargs(n, impl):
        def g(*args):
            if len(args) > n:
                raise TypeError("function takes at most %d arguments (%d given)" % (n, len(args)))
            return impl(*args)
        return g

    # midi
    for cname, (val, cmin) in MIDI_CONSTS.items():
        if api >= cmin:
            setattr(mods["midi"], cname, val)

    # transport
    for fn in ("start", "stop", "record", "setLoopMode"):
        reg("transport", fn, 1, maxargs(0, lambda: None))
    reg("transport", "globalTransport", 1, lambda cmd, value, *a: 1)
    reg("transport", "getLoopMode", 1, lambda: st.loop_mode)
    reg("transport", "getSongPos", 1,
        maxargs(1 if api >= 3 else 0, lambda *a: 1920 if a else 0.5))

    # ui
    reg("ui", "showWindow", 1, lambda w: None)
    reg("ui", "setFocused", 2, lambda w: None)
    reg("ui", "getFocused", 1, lambda w: 1 if w in st.focused else 0)
    reg("ui", "setHintMsg", 1, lambda text: st.hints.append(text))
    reg("ui", "snapMode", 1, lambda v: None)
    reg("ui", "nextWindow", 1, lambda: None)
    reg("ui", "getFocusedFormID", 13, lambda: 3 * 4194304 + 2 * 65536)

    def get_version(*a):
        if a:
            if api < 7:
                raise TypeError("getVersion() takes no arguments")
            return st.fl_version[a[0]] if a[0] < 3 else 5653
        return "FL Studio Producer Edition v%d.%d.%d [build 5653] - Mac" % tuple(st.fl_version)
    reg("ui", "getVersion", 1, get_version)

    # general
    reg("general", "getVersion", 1, lambda: api)
    reg("general", "undoUp", 1, lambda: None)
    reg("general", "undoDown", 1, lambda: None)

    # mixer
    reg("mixer", "trackNumber", 1, lambda: st.track)
    reg("mixer", "trackCount", 1, lambda: st.n_tracks)

    def set_track(i, *a):
        chk_track(i)
        st.track = i
    reg("mixer", "setTrackNumber", 1, maxargs(2, set_track))
    for fn in ("muteTrack",):
        reg("mixer", fn, 2, lambda i, *a: chk_track(i))
    reg("mixer", "enableTrack", 1, lambda i: chk_track(i))
    reg("mixer", "armTrack", 1, lambda i: chk_track(i))

    def solo_track(i, *a):
        chk_track(i)
        if len(a) > 0 and api < 30:
            raise TypeError("too many arguments")
        st.solo.symmetric_difference_update({i})
    reg("mixer", "soloTrack", 1, solo_track)
    reg("mixer", "isTrackSolo", 1, lambda i: (chk_track(i), i in st.solo)[1])

    def get_vol(i, *a):
        chk_track(i)
        v = st.volumes.get(i, 0.8)
        if a:
            if api < 13:
                raise TypeError("getTrackVolume() takes 1 argument")
            if a[0] == 1:
                return vol_to_db(v)
        return v

    def set_vol(i, v, *a):
        chk_track(i)
        st.volumes[i] = min(max(float(v), 0.0), 1.0)
    reg("mixer", "getTrackVolume", 1, get_vol)
    reg("mixer", "setTrackVolume", 1, set_vol)

    def enable_slots(i, value=None):
        chk_track(i)
        # bug documenté : sans valeur, les slots sont coupés
        st.slots_enabled[i] = False if value is None else bool(value)
    reg("mixer", "enableTrackSlots", 19, enable_slots)
    reg("mixer", "isTrackSlotsEnabled", 19, lambda i: (chk_track(i), st.slots_enabled.get(i, True))[1])

    def set_sep(i, v, *a):
        chk_track(i)
        if not -1.0 <= v <= 1.0:
            raise ValueError("sep out of range")
        st.stereo_sep[i] = v
    reg("mixer", "setTrackStereoSep", 12, set_sep)
    reg("mixer", "getTrackStereoSep", 12, lambda i: (chk_track(i), st.stereo_sep.get(i, 0.0))[1])
    reg("mixer", "getActiveEffectIndex", 25, lambda: (3, 2))

    # channels
    reg("channels", "channelCount", 1, lambda *a: st.n_channels)
    reg("channels", "channelNumber", 1, lambda *a: st.channel)
    reg("channels", "selectedChannel", 5, lambda *a: st.channel)

    def select_one(i, *a):
        chk_chan(i)
        st.channel = i
    reg("channels", "selectOneChannel", 8, select_one)
    reg("channels", "selectChannel", 1, lambda i, *a: chk_chan(i))
    reg("channels", "quickQuantize", 9, lambda i, *a: chk_chan(i))
    reg("channels", "muteChannel", 1, lambda i, *a: chk_chan(i))
    reg("channels", "isChannelSolo", 1, lambda i, *a: (chk_chan(i), i in st.ch_solo)[1])

    def solo_chan(i, *a):
        chk_chan(i)
        st.ch_solo.symmetric_difference_update({i})
    reg("channels", "soloChannel", 1, solo_chan)

    # patterns
    reg("patterns", "patternNumber", 1, lambda: st.pattern)
    reg("patterns", "patternCount", 1, lambda: st.pattern_count)
    reg("patterns", "patternMax", 1, lambda: 999)

    def jump(i):
        if not isinstance(i, int) or not 1 <= i <= 999:
            raise TypeError("Pattern index out of range")
        st.pattern = i
    reg("patterns", "jumpToPattern", 1, jump)
    reg("patterns", "findFirstNextEmptyPat", 1, lambda flags, *a: None)
    reg("patterns", "clonePattern", 25, lambda *a: None)

    # device
    def midi_out(msg, *a):
        if a:
            raise TypeError("forme séparée non supportée dans ce test")
        if not isinstance(msg, int):
            raise TypeError("message invalide")
        status = msg & 0xFF
        d1 = (msg >> 8) & 0xFF
        d2 = (msg >> 16) & 0xFF
        if not 0x80 <= status <= 0xEF or d1 > 127 or d2 > 127 or msg >> 24:
            raise ValueError("message MIDI invalide (aurait planté FL <= 20.9.2)")
        st.out.append(msg)
    reg("device", "midiOutMsg", 1, midi_out)
    reg("device", "isAssigned", 1, lambda: 1 if st.assigned else 0)
    reg("device", "getPortNumber", 1, lambda: 0)

    # plugins : module absent avant l'API 8
    if api >= 8:
        reg("plugins", "isValid", 8, lambda idx, slot=-1, g=False: True)
        reg("plugins", "nextPreset", 10, lambda idx, slot=-1, *a: None)
        reg("plugins", "prevPreset", 10, lambda idx, slot=-1, *a: None)
    else:
        mods["plugins"] = None

    # arrangement / playlist
    reg("arrangement", "addAutoTimeMarker", 1, lambda t, name: None)
    reg("playlist", "trackCount", 1, lambda: 500)

    if extra:
        for dotted, value in extra.items():
            m, a = dotted.split(".")
            setattr(mods[m], a, value)
    return mods, st


def install(mods):
    for name in FL_MODULES:
        m = mods.get(name)
        sys.modules[name] = m          # None => ImportError à l'import
    return mods


def load_script(mods, key_hex=TEST_KEY_HEX, block=(), path=SCRIPT):
    """Charge le script comme FL : modules FL dans sys.modules, clé « installée »."""
    install(mods)
    saved = {}
    for name in block:                 # simule une bibliothèque standard tronquée
        saved[name] = sys.modules.get(name, False)
        sys.modules[name] = None
    try:
        with open(path, encoding="utf-8") as fh:
            src = fh.read()
        if key_hex is not None:
            src = src.replace('KEY_HEX = "__FLSHORTCUT_KEY__"', 'KEY_HEX = "%s"' % key_hex, 1)
        module = types.ModuleType("device_FLShortcut_under_test")
        module.__file__ = path
        code = compile(src, path, "exec")
        exec(code, module.__dict__)
    finally:
        for name, prev in saved.items():
            if prev is False:
                sys.modules.pop(name, None)
            else:
                sys.modules[name] = prev
    return module


class FakeClock(object):
    def __init__(self, t=1000.0):
        self.t = t

    def monotonic(self):
        return self.t

    def time(self):
        return self.t


class Event(object):
    def __init__(self, data1, data2=127, chan=15, midi_id=0xB0):
        self.midiId = midi_id
        self.midiChan = chan
        self.data1 = data1
        self.data2 = data2
        self.status = midi_id | chan
        self.handled = False


def mac_for(nonce, seq, action, key=TEST_KEY):
    msg = bytes(list(nonce) + [(seq >> 14) & 0x7F, (seq >> 7) & 0x7F, seq & 0x7F, action])
    d = hmac.new(key, msg, hashlib.sha256).digest()
    v = int.from_bytes(d[:4], "big") >> 4
    return [(v >> 21) & 0x7F, (v >> 14) & 0x7F, (v >> 7) & 0x7F, v & 0x7F]


def frame(nonce, seq, action, key=TEST_KEY, mac=None):
    """Les 8 CC (cc, valeur) d'une commande authentifiée."""
    if mac is None:
        mac = mac_for(nonce, seq, action, key)
    vals = [(seq >> 14) & 0x7F, (seq >> 7) & 0x7F, seq & 0x7F, action] + list(mac)
    return [(104 + i, v) for i, v in enumerate(vals)]
