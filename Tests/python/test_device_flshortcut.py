"""Tests du script FL Studio Resources/device_FLShortcut.py (protocole v2).

Lancement : python3 -m unittest discover -s Tests/python -v
"""
import ast
import hashlib
import hmac
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import fl_mocks as M  # noqa: E402

ALL_IDS = list(range(1, 41))
DATA_ID = 41                     # commande avec données (PROTOCOL.md §7), hors de la table §6
EXT_ID = 42                      # opérations 2 à 8 de la commande avec données (PROTOCOL.md §8, script v5)
# Actions qui exigent une API récente (audit 04 §6) : id -> API minimale
API_MIN = {12: 25, 24: 19, 25: 12, 19: 10, 20: 10, 18: 9}
TEST_APIS = (1, 2, 5, 8, 9, 10, 12, 13, 19, 20, 25, 28, 45)


class Base(unittest.TestCase):
    API = 45
    KEY = M.TEST_KEY_HEX

    def make(self, api=None, key_hex="default", init=True, block=(), wake=True, **kw):
        api = self.API if api is None else api
        if key_hex == "default":
            key_hex = self.KEY
        self.mods, self.fl = M.build_fl(api=api, **kw)
        self.dev = M.load_script(self.mods, key_hex=key_hex, block=block)
        self.clock = M.FakeClock()
        if self.dev._time is not None:
            self.dev._time = self.clock
        self.seq = 0
        if init:
            self.dev.OnInit()
            if wake:
                # Le script démarre endormi : l'appli le réveille par un PING (1 = mode MIDI complet).
                self.send(103, 1)
                self.clock.t += 0.3          # au-delà de MIN_PING_INTERVAL pour les PING des tests
        return self.dev

    def setUp(self):
        self.make()

    # -- helpers
    def send(self, cc, value=127, chan=15, midi_id=0xB0):
        ev = M.Event(cc, value, chan, midi_id)
        self.dev.OnMidiMsg(ev)
        return ev

    def send_pairs(self, pairs):
        return [self.send(cc, v) for cc, v in pairs]

    def nonce(self):
        return list(self.dev._st.nonce)

    def command(self, action, seq=None, mac=None, nonce=None):
        if seq is None:
            self.seq += 1
            seq = self.seq
        nonce = self.nonce() if nonce is None else nonce
        evs = self.send_pairs(M.frame(nonce, seq, action, mac=mac))
        for ev in evs:
            self.assertTrue(ev.handled)
        return evs

    def acks(self):
        return [v for (s, cc, v) in self.fl.cc_out() if cc == 119]

    def last_ack(self):
        a = self.acks()
        return a[-1] if a else None

    def hellos(self):
        """Liste des trames HELLO complètes [(cc, val), ...] envoyées."""
        out, cur = [], None
        for s, cc, v in self.fl.cc_out():
            self.assertEqual(s, 0xBF)
            if cc == 120 and v == 1:
                cur = [(cc, v)]
            elif cur is not None:
                cur.append((cc, v))
                if cc == 120 and v == 127:
                    out.append(cur)
                    cur = None
        return out

    def last_hello(self):
        h = self.hellos()
        self.assertTrue(h, "aucun HELLO envoyé")
        return h[-1]

    @staticmethod
    def mask_of(hello):
        d = dict(hello[1:-1])
        mask = 0
        for k in range(6):
            mask |= d[90 + k] << (7 * k)
        return mask

    def fl_calls_excluding_reads(self):
        reads = ("Count", "Number", "getVersion", "getFocused", "isAssigned", "midiOutMsg",
                 "setHintMsg", "selectedChannel", "getLoopMode", "getName")
        return [n for n in self.fl.names() if not any(r in n for r in reads)]


# ---------------------------------------------------------------------------- Sommeil
class TestSleep(Base):
    """Le script ne fait rien tant qu'il n'est pas réveillé, et se rendort après un réveil bref."""

    def test_wrong_input_is_told_in_fl_and_to_the_app(self):
        # Controller type « FL Shortcuts » choisi sur la ligne de la carte son (vidéo de l'utilisateur).
        self.make(wake=False, device_name="SSL 2+")
        self.assertIn((120, 64), [(cc, v) for (s, cc, v) in self.fl.cc_out()])
        self.assertTrue(any("SSL 2+" in h and "FL Shortcuts Link" in h for h in self.fl.hints), self.fl.hints)
        for name in ("FL Shortcuts Link", "FL Shortcuts"):
            self.make(wake=False, device_name=name)
            self.assertNotIn((120, 64), [(cc, v) for (s, cc, v) in self.fl.cc_out()])
        self.make(wake=False, api=5, device_name="SSL 2+")             # getName absent : rien de dit
        self.assertNotIn((120, 64), [(cc, v) for (s, cc, v) in self.fl.cc_out()])

    def test_asleep_after_init_sends_nothing(self):
        self.make(wake=False)
        before = len(self.fl.out)
        calls = len(self.fl.calls)
        for _ in range(200):
            self.clock.t += 0.02
            self.dev.OnIdle()
            self.dev.OnRefresh(32)
        self.assertEqual(len(self.fl.out), before)          # ni battement, ni fenêtre, ni HELLO
        self.assertEqual(len(self.fl.calls), calls)         # aucun appel à FL

    def test_frames_ignored_while_asleep_but_refused(self):
        self.make(wake=False)
        self.command(33, nonce=[0, 0, 0, 0])
        self.assertNotIn("ui.showWindow", self.fl.names())
        self.assertEqual(self.last_ack(), 0)                # l'appli sait qu'il faut se resynchroniser
        self.assertFalse(self.dev._st.awake)

    def test_unsigned_traffic_does_not_keep_awake(self):
        self.make(wake=False)
        self.send(103, 2)
        for _ in range(20):
            self.clock.t += 1
            self.command(33, mac=[1, 2, 3, 4])               # trames non signées
            self.dev.OnIdle()
        self.assertFalse(self.dev._st.awake)

    def test_brief_wake_runs_then_sleeps(self):
        self.make(wake=False)
        self.send(103, 2)
        self.assertTrue(self.hellos())
        self.command(39)
        self.assertIn(3, self.fl.armed)
        self.command(39)                                    # déjà armée : jamais désarmée
        self.assertIn(3, self.fl.armed)
        self.command(40)
        self.assertTrue(self.fl.recording)
        self.command(40)                                    # déjà allumé : jamais éteint
        self.assertTrue(self.fl.recording)
        self.clock.t += 9
        self.dev.OnIdle()
        self.assertFalse(self.dev._st.awake)
        out = len(self.fl.out)
        for _ in range(100):
            self.clock.t += 0.02
            self.dev.OnIdle()
        self.assertEqual(len(self.fl.out), out)

    def test_durable_wake_stays_awake(self):
        self.clock.t += 60
        self.dev.OnIdle()
        self.assertTrue(self.dev._st.awake)


# ---------------------------------------------------------------------------- HMAC
class TestHmac(unittest.TestCase):
    def setUp(self):
        mods, _ = M.build_fl(api=45)
        self.dev = M.load_script(mods)

    def test_vector_hashlib(self):
        key = bytes.fromhex("000102030405060708090a0b0c0d0e0f")
        msg = bytes([17, 42, 99, 5, 0, 2, 44, 12])
        self.assertEqual(list(msg), [17, 42, 99, 5] + [(300 >> 14) & 127, (300 >> 7) & 127, 300 & 127, 12])
        d = hmac.new(key, msg, hashlib.sha256).digest()
        self.assertEqual(self.dev.mac28(d), [87, 59, 101, 12])
        self.assertEqual(self.dev.mac28(self.dev.hmac_sha256_lib(key, msg)), [87, 59, 101, 12])

    def test_vector_pure_python(self):
        key = bytes(range(16))
        msg = bytes([17, 42, 99, 5, 0, 2, 44, 12])
        self.assertEqual(self.dev.mac28(self.dev.hmac_sha256_pure(key, msg)), [87, 59, 101, 12])
        self.assertEqual(self.dev._PureHmac(key).digest(msg), hmac.new(key, msg, hashlib.sha256).digest())

    def test_pure_sha256_matches_hashlib(self):
        for n in (0, 1, 3, 55, 56, 57, 63, 64, 65, 119, 120, 128, 300):
            data = bytes((i * 7 + n) & 0xFF for i in range(n))
            self.assertEqual(self.dev.sha256_pure(data), hashlib.sha256(data).digest(), n)
        self.assertEqual(self.dev.sha256_pure(b"abc").hex(),
                         "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

    def test_pure_hmac_long_key(self):
        key = bytes(range(100))
        self.assertEqual(self.dev.hmac_sha256_pure(key, b"x" * 70),
                         hmac.new(key, b"x" * 70, hashlib.sha256).digest())

    def test_backend_is_hashlib_when_available(self):
        self.assertEqual(self.dev.MAC_BACKEND, "hashlib")

    def test_backend_falls_back_to_pure_python(self):
        mods, _ = M.build_fl(api=45)
        dev = M.load_script(mods, block=("hmac", "hashlib"))
        self.assertIsNone(dev._hmac)
        self.assertEqual(dev.MAC_BACKEND, "python")
        self.assertIsNotNone(dev._signer)


class TestPurePythonEndToEnd(Base):
    def setUp(self):
        self.make(block=("hmac", "hashlib"))

    def test_valid_frame_executes_with_pure_hmac(self):
        self.assertEqual(self.dev.MAC_BACKEND, "python")
        self.command(2)
        self.assertIn("transport.stop", self.fl.names())
        self.assertEqual(self.last_ack(), 2)

    def test_bad_mac_rejected_with_pure_hmac(self):
        self.command(2, mac=[0, 0, 0, 0])
        self.assertNotIn("transport.stop", self.fl.names())
        self.assertEqual(self.last_ack(), 0)


class TestMinimalStdlib(Base):
    def setUp(self):
        self.make(block=("hmac", "hashlib", "time", "random"))

    def test_works_without_time_random_hmac(self):
        self.assertIsNone(self.dev._time)
        self.assertIsNone(self.dev._random)
        self.assertEqual(self.dev.MAC_BACKEND, "python")
        n = self.nonce()
        self.assertTrue(all(0 <= x < 128 for x in n))
        self.command(1)
        self.assertEqual(self.last_ack(), 1)
        for _ in range(5):
            self.dev.OnIdle()


# ---------------------------------------------------------------------------- Trames
class TestFrames(Base):
    def test_valid_frame_executes_and_acks(self):
        self.command(1)
        self.assertEqual(self.fl.names().count("transport.start"), 1)
        self.assertEqual(self.last_ack(), 1)

    def test_bad_mac_rejected(self):
        good = M.mac_for(self.nonce(), 1, 38)
        bad = list(good)
        bad[3] ^= 1
        self.command(38, seq=1, mac=bad)
        self.assertEqual(self.fl.called("transport.globalTransport"), [])
        self.assertEqual(self.last_ack(), 0)
        self.assertTrue(any("non signée" in h for h in self.fl.hints))

    def test_wrong_key_rejected(self):
        self.send_pairs(M.frame(self.nonce(), 1, 36, key=b"\x01" * 16))
        self.assertNotIn("general.undoUp", self.fl.names())

    def test_wrong_nonce_rejected(self):
        n = [(x + 1) & 127 for x in self.nonce()]
        self.send_pairs(M.frame(n, 1, 36))
        self.assertNotIn("general.undoUp", self.fl.names())

    def test_replay_rejected(self):
        pairs = M.frame(self.nonce(), 5, 36)
        self.send_pairs(pairs)
        self.send_pairs(pairs)
        self.assertEqual(self.fl.names().count("general.undoUp"), 1)
        self.assertEqual(self.acks()[-2:], [36, 0])

    def test_lower_seq_rejected(self):
        self.command(36, seq=10)
        self.command(36, seq=9)
        self.command(36, seq=10)
        self.assertEqual(self.fl.names().count("general.undoUp"), 1)
        self.command(36, seq=11)
        self.assertEqual(self.fl.names().count("general.undoUp"), 2)

    def test_mixed_order_rejected(self):
        pairs = M.frame(self.nonce(), 1, 36)
        shuffled = [pairs[0], pairs[2], pairs[1]] + pairs[3:]
        self.send_pairs(shuffled)
        self.assertNotIn("general.undoUp", self.fl.names())
        # Une trame valide juste après passe toujours.
        self.command(36, seq=2)
        self.assertEqual(self.fl.names().count("general.undoUp"), 1)

    def test_interleaved_frames_rejected(self):
        a = M.frame(self.nonce(), 1, 36)
        b = M.frame(self.nonce(), 2, 37)
        mixed = []
        for x, y in zip(a, b):
            mixed += [x, y]
        self.send_pairs(mixed)
        self.assertNotIn("general.undoUp", self.fl.names())
        self.assertNotIn("general.undoDown", self.fl.names())

    def test_cc104_resets_partial_frame(self):
        a = M.frame(self.nonce(), 1, 36)
        self.send_pairs(a[:5])                 # trame tronquée
        self.send_pairs(M.frame(self.nonce(), 2, 37))
        self.assertNotIn("general.undoUp", self.fl.names())
        self.assertIn("general.undoDown", self.fl.names())

    def test_continuation_without_start_rejected(self):
        self.send_pairs(M.frame(self.nonce(), 1, 36)[1:])
        self.assertNotIn("general.undoUp", self.fl.names())

    def test_ping_inside_frame_discards_it(self):
        a = M.frame(self.nonce(), 1, 36)
        self.send_pairs(a[:4])
        self.clock.t += 1
        self.send(103, 1)
        self.send_pairs(a[4:])
        self.assertNotIn("general.undoUp", self.fl.names())

    def test_rate_limit_20_per_second(self):
        for _ in range(30):
            self.command(36)
        self.assertEqual(self.fl.names().count("general.undoUp"), 20)
        self.assertEqual(self.acks().count(0), 10)
        self.clock.t += 1.01
        self.command(36)
        self.assertEqual(self.fl.names().count("general.undoUp"), 21)

    def test_rate_limit_sliding_window(self):
        for i in range(40):
            self.clock.t += 0.025                    # 40 actions/s demandées
            self.command(36)
        # sur 1 s glissante, jamais plus de 20 exécutions
        self.assertLessEqual(self.fl.names().count("general.undoUp"), 21)
        self.assertGreaterEqual(self.fl.names().count("general.undoUp"), 19)

    def test_unknown_id_rejected_even_with_valid_mac(self):
        for aid in (0, 41, 42, 127):
            self.command(aid)
            self.assertEqual(self.last_ack(), 0)
        self.assertEqual(self.fl_calls_excluding_reads(), [])

    def test_mac_bruteforce_throttled(self):
        for i in range(10):
            self.command(36, mac=[i, 0, 0, 0])
        self.command(36)                         # valide, mais pendant la pénalité
        self.assertNotIn("general.undoUp", self.fl.names())
        self.clock.t += 1.01
        self.command(36)
        self.assertIn("general.undoUp", self.fl.names())

    def test_invalid_data_values_ignored(self):
        self.send(104, 200)
        self.send_pairs(M.frame(self.nonce(), 1, 36)[1:])
        self.assertNotIn("general.undoUp", self.fl.names())

    def test_seq_max_starts_new_session(self):
        old = self.nonce()
        self.command(36, seq=(1 << 21) - 1)
        self.assertIn("general.undoUp", self.fl.names())
        self.assertNotEqual(self.nonce(), old)
        self.assertEqual(self.dev._st.last_seq, 0)


# ---------------------------------------------------------------------------- PING / HELLO
class TestHandshake(Base):
    def assert_hello_layout(self, hello, nonce, api):
        expected_ccs = [120, 121, 122, 123, 124, 125, 126, 90, 91, 92, 93, 94, 95, 120]
        self.assertEqual([cc for cc, v in hello], expected_ccs)
        self.assertEqual(hello[0][1], 1)
        self.assertEqual(hello[-1][1], 127)
        self.assertEqual([v for cc, v in hello[1:5]], nonce)
        self.assertEqual(hello[5][1], min(api, 127))
        self.assertEqual(hello[6][1], 2)
        for cc, v in hello:
            self.assertTrue(0 <= v <= 127)

    def test_hello_on_init(self):
        self.assertEqual(len(self.hellos()), 1)
        self.assert_hello_layout(self.last_hello(), self.nonce(), 45)

    def test_ping_new_nonce_and_hello(self):
        old = self.nonce()
        self.command(36, seq=50)
        ev = self.send(103, 1)
        self.assertTrue(ev.handled)
        new = self.nonce()
        self.assertNotEqual(new, old)
        self.assertEqual(len(self.hellos()), 2)
        self.assert_hello_layout(self.last_hello(), new, 45)
        self.assertEqual(self.dev._st.last_seq, 0)
        # numérotation repartie de 1 avec le nouveau nonce
        self.command(37, seq=1)
        self.assertIn("general.undoDown", self.fl.names())
        # une trame de l'ancienne session est refusée
        self.send_pairs(M.frame(old, 51, 36))
        self.assertEqual(self.fl.names().count("general.undoUp"), 1)

    def test_ping_flood_limited(self):
        for _ in range(10):
            self.send(103, 1)
        self.assertEqual(len(self.hellos()), 2)
        self.clock.t += 0.3
        self.send(103, 1)
        self.assertEqual(len(self.hellos()), 3)

    def test_ping_zero_ignored(self):
        self.send(103, 0)
        self.assertEqual(len(self.hellos()), 1)

    def test_api_capped_at_127(self):
        self.make(api=200)
        self.assertEqual(dict(self.last_hello()[1:-1])[125], 127)

    def test_hello_retried_when_output_assigned_later(self):
        self.make(assigned=False)
        self.assertEqual(self.fl.out, [])
        self.dev.OnIdle()
        self.assertEqual(self.fl.out, [])
        self.fl.assigned = True
        self.clock.t += 2.5
        self.dev.OnIdle()
        self.assertEqual(len(self.hellos()), 1)
        self.assert_hello_layout(self.last_hello(), self.nonce(), 45)

    def test_heartbeat_alternates(self):
        for _ in range(4):
            self.clock.t += 2.0
            self.dev.OnIdle()
        beats = [v for s, cc, v in self.fl.cc_out() if cc == 118]
        self.assertEqual(beats, [1, 0, 1, 0])

    def test_window_reported_on_change(self):
        win = lambda: [v for s, cc, v in self.fl.cc_out() if cc == 117]
        self.fl.focused = {0}
        self.clock.t += 0.2
        gets = len(self.fl.called("ui.getFocused"))
        self.dev.OnRefresh(32)
        # OnRefresh ne fait aucun appel à FL : il marque, OnIdle traite.
        self.assertEqual(len(self.fl.called("ui.getFocused")), gets)
        self.dev.OnIdle()
        self.assertEqual(win()[-1], 0)
        self.fl.focused = {3}
        self.dev.OnRefresh(32)
        self.dev.OnIdle()               # < 100 ms : différé
        self.assertEqual(win()[-1], 0)
        self.clock.t += 0.15
        self.dev.OnIdle()
        self.assertEqual(win()[-1], 3)
        self.fl.focused = {7}           # aucun OnRefresh : vérification de secours au battement (2 s)
        self.clock.t += 2.1
        self.dev.OnIdle()
        self.clock.t += 0.12
        self.dev.OnIdle()
        self.assertEqual(win()[-1], 5)
        self.fl.focused = set()
        self.dev.OnRefresh(32)
        self.clock.t += 0.12
        self.dev.OnIdle()
        self.assertEqual(win()[-1], 127)

    def test_buggy_fl_never_calls_global_transport(self):
        self.make(api=43, fl_version=(26, 1, 6))
        for aid in (4, 5, 6, 7, 10, 38):
            self.command(aid)
            self.assertEqual(self.last_ack(), 0, aid)
            self.clock.t += 0.06
        self.assertEqual(self.fl.called("transport.globalTransport"), [])
        mask = self.dev.capability_mask()
        for aid in (4, 5, 6, 7, 10, 38):
            self.assertFalse(mask & (1 << (aid - 1)), aid)
        self.assertTrue(mask & (1 << 0))                     # Lecture reste disponible

    def test_volume_few_fader_writes(self):
        self.make(api=45, track=2)
        before = len(self.fl.called("mixer.setTrackVolume"))
        self.command(28)
        self.assertLessEqual(len(self.fl.called("mixer.setTrackVolume")) - before, 4)

    def test_same_hint_not_repeated(self):
        self.make(api=1)
        n = len(self.fl.hints)
        for _ in range(5):
            self.command(12)                                 # indisponible en API 1 : même message
        self.assertEqual(len(self.fl.hints) - n, 1)

    def test_window_not_resent_if_unchanged(self):
        self.fl.focused = {2}
        for _ in range(5):
            self.clock.t += 0.6
            self.dev.OnIdle()
        self.assertEqual([v for s, cc, v in self.fl.cc_out() if cc == 117], [2])

    def test_midi_out_combined_form_and_bounds(self):
        for m in self.fl.out:
            self.assertEqual(m & 0xFF, 0xBF)
            self.assertLessEqual((m >> 8) & 0xFF, 127)
            self.assertLessEqual((m >> 16) & 0xFF, 127)


# ---------------------------------------------------------------------------- Capacités
class TestCapabilities(Base):
    def caps_for(self, api):
        self.make(api=api)
        mask = self.mask_of(self.last_hello())
        self.assertEqual(mask, self.dev.capability_mask())
        return set(i for i in range(1, 43) if mask >> (i - 1) & 1)

    def test_api45_all_actions(self):
        self.assertEqual(self.caps_for(45), set(ALL_IDS) | {DATA_ID, EXT_ID})

    def test_api1_without_recent_actions(self):
        caps = self.caps_for(1)
        self.assertEqual(caps, (set(ALL_IDS) - set(API_MIN)) | {DATA_ID, EXT_ID})

    def test_thresholds(self):
        for api in TEST_APIS:
            caps = self.caps_for(api)
            expected = set(i for i in ALL_IDS if api >= API_MIN.get(i, 1)) | {DATA_ID, EXT_ID}
            self.assertEqual(caps, expected, "API %d" % api)

    def test_mask_bit_layout(self):
        self.make(api=45)
        d = dict(self.last_hello()[1:-1])
        self.assertEqual(d[90], 127)        # ids 1..7
        self.assertEqual(d[95], 0b1111111)  # ids 36 à 42 (41 = données, 42 = opérations de l'Organiser)
        self.make(api=1)
        d = dict(self.last_hello()[1:-1])
        # id 12 (clone) = bit 11 = CC 91 bit 4 ; id 18 (quant) = CC 92 bit 3
        self.assertEqual(d[91] >> 4 & 1, 0)
        self.assertEqual(d[92] >> 3 & 1, 0)

    def test_missing_function_greys_only_that_action(self):
        self.make(api=45, missing=("patterns.clonePattern",))
        mask = self.mask_of(self.last_hello())
        self.assertEqual(mask >> 11 & 1, 0)
        self.assertEqual(bin(mask).count("1"), 41)

    def test_hasattr_and_api_combined(self):
        # fonction présente mais API déclarée trop basse => indisponible
        self.make(api=20, extra={"patterns.clonePattern": lambda *a: None})
        self.assertEqual(self.dev.capability_mask() >> 11 & 1, 0)

    def test_without_globaltransport(self):
        self.make(api=1, missing=("transport.globalTransport",))
        caps = set(i for i in range(1, 43) if self.dev.capability_mask() >> (i - 1) & 1)
        for gt_only in (4, 5, 6, 7, 10, 38):
            self.assertNotIn(gt_only, caps)
        self.assertIn(1, caps)

    def test_unavailable_action_refused_with_message(self):
        self.make(api=1)
        self.command(12)
        self.assertEqual(self.last_ack(), 0)
        self.assertTrue(any("21.0.3" in h for h in self.fl.hints))


# ---------------------------------------------------------------------------- Actions
class TestEveryActionEveryApi(Base):
    def run_all(self, api, **kw):
        self.make(api=api, focused={0}, **kw)
        for aid in ALL_IDS:
            self.command(aid)
            ack = self.last_ack()
            if api >= API_MIN.get(aid, 1):
                self.assertEqual(ack, aid, "API %d, action %d, hints=%r" % (api, aid, self.fl.hints[-3:]))
            else:
                self.assertEqual(ack, 0, "API %d, action %d" % (api, aid))
            self.clock.t += 0.06
        bad = [h for h in self.fl.hints if "erreur" in h or "échoué" in h]
        self.assertEqual(bad, [], "API %d" % api)

    def test_api1(self):
        self.run_all(1)

    def test_all_apis(self):
        for api in TEST_APIS:
            self.run_all(api)

    def test_api45_plugin_focused(self):
        self.run_all(45, extra=None)
        self.fl.focused = {6}
        self.command(19)
        self.assertEqual(self.last_ack(), 19)
        self.assertIn((3, 2), self.fl.called("plugins.nextPreset"))
        self.fl.focused = {7}
        self.command(20)
        self.assertEqual(self.last_ack(), 20)

    def test_no_selection_bounds(self):
        for api in (1, 45):
            self.make(api=api, track=-1, channel=-1, focused={0})
            for aid in ALL_IDS:
                self.command(aid)
                self.clock.t += 0.06
            bad = [h for h in self.fl.hints if "erreur" in h or "échoué" in h]
            self.assertEqual(bad, [], "API %d" % api)
            for name in ("mixer.muteTrack", "mixer.soloTrack", "mixer.armTrack",
                         "channels.quickQuantize", "mixer.enableTrackSlots"):
                for args in self.fl.called(name):
                    self.assertGreaterEqual(args[0], 0, name)
            self.assertTrue(any("aucun" in h for h in self.fl.hints))

    def test_empty_project(self):
        self.make(api=45, n_channels=0, channel=-1, n_tracks=1, track=0)
        for aid in ALL_IDS:
            self.command(aid)
            self.clock.t += 0.06
        self.assertEqual([h for h in self.fl.hints if "erreur" in h or "échoué" in h], [])


class TestActionBehaviour(Base):
    def test_prev_pattern_beyond_count(self):          # REL-25
        self.make(pattern=7, pattern_count=4)
        self.command(14)
        self.assertEqual(self.fl.pattern, 6)

    def test_pattern_bounds(self):
        self.make(pattern=1)
        self.command(14)
        self.assertEqual(self.fl.pattern, 1)
        self.assertEqual(self.fl.called("patterns.jumpToPattern"), [])

    def test_channel_wraps(self):
        self.make(api=45, channel=7, n_channels=8)
        self.command(15)
        self.assertEqual(self.fl.channel, 0)
        self.command(16)
        self.assertEqual(self.fl.channel, 7)

    def test_channel_fallback_api1(self):
        self.make(api=1)
        self.command(15)
        self.assertIn((102, 1), self.fl.called("transport.globalTransport"))

    def test_track_next_bound(self):
        self.make(api=45, track=125, n_tracks=127)
        self.command(26)
        self.assertEqual(self.fl.track, 125)          # 126 = « Current » : exclue
        self.command(27)
        self.assertEqual(self.fl.track, 124)

    def test_bypass_passes_explicit_value(self):
        self.make(api=45, track=4)
        self.command(24)
        self.assertEqual(self.fl.called("mixer.enableTrackSlots")[-1], (4, False))
        self.command(24)
        self.assertEqual(self.fl.called("mixer.enableTrackSlots")[-1], (4, True))

    def test_mono_toggles_and_restores(self):
        self.make(api=45, master_sep=0.25)
        self.command(25)
        self.assertEqual(self.fl.stereo_sep[0], -1.0)
        self.command(25)
        self.assertEqual(self.fl.stereo_sep[0], 0.25)

    def test_volume_half_db(self):
        self.make(api=45, track=2)
        self.command(28)
        db = M.vol_to_db(self.fl.volumes[2])
        self.assertAlmostEqual(db, 0.5, delta=0.05)
        self.command(29)
        self.command(29)
        self.assertAlmostEqual(M.vol_to_db(self.fl.volumes[2]), -0.5, delta=0.05)

    def test_volume_fallback_api1(self):
        self.make(api=1, track=2)
        self.command(28)
        self.assertGreater(self.fl.volumes[2], 0.8)

    def test_unsolo(self):
        self.make(api=45, solo={1, 5}, ch_solo={2})
        self.command(23)
        self.assertEqual(self.fl.solo, set())
        self.assertEqual(self.fl.ch_solo, set())

    def test_mute_api1_uses_enableTrack(self):
        self.make(api=1, track=3)
        self.command(21)
        self.assertEqual(self.fl.called("mixer.enableTrack"), [(3,)])

    def test_gt_constant_fallbacks_api1(self):
        self.make(api=1)
        self.assertFalse(hasattr(self.mods["midi"], "FPT_CountDown"))
        self.command(5)
        self.command(6)
        self.command(4)
        self.assertEqual(self.fl.called("transport.globalTransport"), [(115, 1), (113, 1), (110, 1)])

    def test_save_uses_fpt_save(self):
        self.command(38)
        self.assertEqual(self.fl.called("transport.globalTransport"), [(92, 1)])

    def test_marker_song_mode_and_pattern_mode(self):
        self.make(api=45, loop_mode=1)
        self.command(8)
        self.assertEqual(self.fl.called("arrangement.addAutoTimeMarker"), [(1920, "Bonne prise")])
        self.make(api=45, loop_mode=0)
        self.command(8)
        self.assertEqual(self.fl.called("arrangement.addAutoTimeMarker"), [])
        self.assertEqual(self.last_ack(), 0)

    def test_marker_without_arrangement_module(self):
        mods, fl = M.build_fl(api=1)
        mods["arrangement"] = None
        self.mods, self.fl = mods, fl
        self.dev = M.load_script(mods)
        self.dev._time = self.clock = M.FakeClock()
        self.dev.OnInit()
        self.send(103, 1)                  # réveil
        self.command(8)
        self.assertIn((33, 1), self.fl.called("transport.globalTransport"))

    def test_window_actions(self):
        self.command(32)
        self.assertEqual(self.fl.called("ui.showWindow")[-1], (3,))
        self.assertEqual(self.fl.called("ui.setFocused")[-1], (3,))
        self.fl.focused = {0}
        self.command(35)
        self.assertEqual(self.fl.called("ui.showWindow")[-1], (2,))

    def test_api1_no_setFocused(self):
        self.make(api=1)
        self.command(33)
        self.assertEqual(self.fl.called("ui.showWindow"), [(0,)])


# ---------------------------------------------------------------------------- Clé
class TestKeyNotInstalled(Base):
    KEY = None

    def test_everything_refused(self):
        self.assertIsNone(self.dev.KEY)
        self.assertTrue(any("clé" in h for h in self.fl.hints))
        before = list(self.fl.calls)
        for aid in ALL_IDS:
            for key in (M.TEST_KEY, b"\x00" * 16):
                self.send_pairs(M.frame(self.nonce(), 1 + aid, aid, key=key))
        new = [c[0] for c in self.fl.calls[len(before):]]
        self.assertEqual([n for n in new if n not in ("ui.setHintMsg", "device.midiOutMsg",
                                                       "device.isAssigned")], [])
        self.assertTrue(all(a == 0 for a in self.acks()))

    def test_hello_mask_zero(self):
        self.assertEqual(self.mask_of(self.last_hello()), 0)

    def test_placeholder_variants_refused(self):
        for bad in ("", "zz" * 16, "00" * 16, "0011", "__FLSHORTCUT_KEY__"):
            self.make(key_hex=bad)
            self.assertIsNone(self.dev.KEY, bad)
            self.command(1)
            self.assertNotIn("transport.start", self.fl.names())

    def test_uppercase_key_accepted(self):
        self.make(key_hex=M.TEST_KEY_HEX.upper())
        self.command(1)
        self.assertIn("transport.start", self.fl.names())


# ---------------------------------------------------------------------------- Robustesse
class TestRobustness(Base):
    def test_fl_exception_swallowed(self):
        self.make(raise_on={"transport.start": RuntimeError("boom")})
        self.command(1)
        self.assertEqual(self.last_ack(), 0)
        self.assertTrue(any("échoué" in h for h in self.fl.hints))

    def test_hint_exception_inside_except(self):          # REL-27
        self.make(raise_on={"transport.start": RuntimeError("boom"),
                            "ui.setHintMsg": RuntimeError("hint")})
        self.command(1)
        self.command(999 % 128)
        self.send(103, 1)
        self.dev.OnIdle()
        self.dev.OnRefresh(32)
        self.dev.OnDeInit()

    def test_every_fl_function_raising(self):
        mods, fl = M.build_fl(api=45)
        names = []
        for mname, mod in mods.items():
            if mod is None or mname == "midi":
                continue
            for a in dir(mod):
                if not a.startswith("_"):
                    names.append("%s.%s" % (mname, a))
        self.make(api=45, raise_on=dict((n, RuntimeError(n)) for n in names), focused={0})
        for aid in ALL_IDS:
            self.command(aid)
        for _ in range(3):
            self.dev.OnIdle()
            self.dev.OnRefresh(0xFFFF)
        self.dev.OnDeInit()

    def test_midi_out_raising(self):
        self.make(raise_on={"device.midiOutMsg": ValueError("x")})
        self.command(1)
        self.assertIn("transport.start", self.fl.names())
        self.dev.OnIdle()

    def test_no_device_module_functions(self):
        self.make(missing=("device.midiOutMsg", "device.isAssigned"))
        self.command(1)
        self.assertIn("transport.start", self.fl.names())
        self.dev.OnIdle()
        self.dev.OnRefresh(32)

    def test_get_version_raising(self):
        self.make(raise_on={"general.getVersion": RuntimeError("x")})
        self.assertEqual(self.dev._api(), 1)

    def test_weird_events(self):
        class Broken(object):
            @property
            def midiId(self):
                raise RuntimeError("no")
        for ev in (object(), Broken(), M.Event(None, None), M.Event(104, -5), M.Event(104, 1000)):
            self.dev.OnMidiMsg(ev)
        self.dev.OnRefresh(None)
        self.dev.OnRefresh("x")

    def test_callbacks_before_init(self):
        self.make(init=False)
        self.dev.OnIdle()
        self.dev.OnRefresh(32)
        self.dev.OnMidiMsg(M.Event(103, 1))
        self.dev.OnDeInit()

    def test_handled_only_for_protocol_cc_on_channel_16(self):
        self.assertFalse(self.send(7, 100).handled)            # CC volume : laissé à FL
        self.assertFalse(self.send(64, 127).handled)
        self.assertFalse(self.send(20, 127).handled)           # anciens CC v1
        self.assertFalse(self.send(104, 1, chan=0).handled)    # autre canal
        self.assertFalse(self.send(104, 1, midi_id=0x90).handled)
        for cc in list(range(103, 112)) + list(range(90, 96)) + list(range(117, 127)):
            self.assertTrue(self.send(cc, 0).handled, cc)
        self.assertEqual(self.fl_calls_excluding_reads(), [])

    def test_echo_of_own_messages_ignored(self):
        for s, cc, v in list(self.fl.cc_out()):
            ev = self.send(cc, v)
            self.assertTrue(ev.handled)
        self.assertEqual(self.fl_calls_excluding_reads(), [])

    def test_buggy_fl_26_1_x_warning(self):
        self.make(api=43, fl_version=(26, 1, 3))
        self.assertTrue(self.dev._gt_buggy())
        self.assertTrue(any("26.1.7" in h for h in self.fl.hints))
        self.make(api=45, fl_version=(26, 1, 7))
        self.assertFalse(self.dev._gt_buggy())

    def test_fl_version_parsed_from_text_on_old_api(self):
        self.make(api=1)
        self.assertEqual(self.dev._fl_version(), (20, 7, 0))

    def test_load_without_optional_modules(self):
        for api in TEST_APIS:
            mods, fl = M.build_fl(api=api)
            for name in ("plugins", "arrangement", "playlist", "device"):
                mods[name] = None
            dev = M.load_script(mods)
            dev.OnInit()
            dev.OnIdle()


# ---------------------------------------------------------------------------- Source
SRC_PATH = M.SCRIPT


class TestSourceCompat(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(SRC_PATH, encoding="utf-8") as fh:
            cls.src = fh.read()
        cls.tree = ast.parse(cls.src)

    def test_parses_as_python_36(self):
        ast.parse(self.src, feature_version=(3, 6))

    def test_no_post_36_nodes(self):
        forbidden = [n for n in ("NamedExpr", "Match", "TryStar", "TypeAlias") if hasattr(ast, n)]
        for node in ast.walk(self.tree):
            name = type(node).__name__
            self.assertNotIn(name, forbidden, "ligne %s" % getattr(node, "lineno", "?"))
            if isinstance(node, ast.arguments):
                self.assertEqual(getattr(node, "posonlyargs", []), [], "paramètres positionnels seuls")
            if isinstance(node, ast.ImportFrom) and node.module == "__future__":
                self.fail("from __future__ interdit")
            if isinstance(node, (ast.AnnAssign,)):
                self.fail("annotations de variables évitées")
            if isinstance(node, ast.JoinedStr):
                self.fail("f-strings évitées (formatage %)")
            if isinstance(node, ast.Attribute) and node.attr in ("removeprefix", "removesuffix"):
                self.fail("str.%s (3.9)" % node.attr)
            if isinstance(node, ast.BinOp) and isinstance(node.op, ast.BitOr):
                if isinstance(node.left, ast.Dict) or isinstance(node.right, ast.Dict):
                    self.fail("dict | dict (3.9)")
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                self.assertIsNone(node.returns)
            if isinstance(node, ast.AsyncFunctionDef) or isinstance(node, ast.Await):
                self.fail("async interdit")
            if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id == "open":
                self.fail("aucun accès fichier")
            if isinstance(node, ast.Attribute) and node.attr in ("monotonic_ns", "time_ns", "randbytes"):
                self.fail("fonction %s postérieure à 3.6" % node.attr)

    def test_py_compile(self):
        import py_compile
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            py_compile.compile(SRC_PATH, cfile=os.path.join(d, "x.pyc"), doraise=True)

    def test_no_unprotected_imports(self):
        allowed_stdlib = {"time", "random", "hmac", "hashlib"}
        for node in self.tree.body:
            if isinstance(node, (ast.Import, ast.ImportFrom)):
                self.fail("import non protégé au niveau module : ligne %d" % node.lineno)
            if isinstance(node, ast.Try):
                for sub in ast.walk(node):
                    if isinstance(sub, ast.Import):
                        for alias in sub.names:
                            self.assertIn(alias.name, allowed_stdlib)
        for node in ast.walk(self.tree):
            if isinstance(node, ast.ImportFrom):
                self.fail("from ... import interdit")
            if isinstance(node, ast.Import):
                for alias in node.names:
                    self.assertNotIn(alias.name, M.FL_MODULES)
                    self.assertNotIn(alias.name, ("os", "json", "threading", "typing", "sys"))

    def test_metadata_header(self):
        lines = self.src.splitlines()
        self.assertEqual(lines[0], "# name=FL Shortcuts")
        # FL relie lui-même le script à l'appareil de l'appli (« FL Shortcuts Link », et l'ancien nom).
        self.assertIn("# supportedDevices=FL Shortcuts Link,FL Shortcuts", lines[:5])
        self.assertNotIn("# url=", lines[:5])     # url vide inutile (audit 04 §7.1)

    def test_key_placeholder_once(self):
        self.assertEqual(self.src.count("__FLSHORTCUT_KEY__"), 1)
        self.assertEqual(len(re.findall(r'^KEY_HEX = "__FLSHORTCUT_KEY__"$', self.src, re.M)), 1)

    def test_action_table_matches_protocol(self):
        proto = os.path.join(M.ROOT, "PROTOCOL.md")
        with open(proto, encoding="utf-8") as fh:
            rows = re.findall(r"^\| (\d+) \| (\w+) \|", fh.read(), re.M)
        mods, _ = M.build_fl(api=45)
        dev = M.load_script(mods)
        table = dict((e[0], e[1]) for e in dev.ACTIONS)
        self.assertEqual(table, dict((int(i), k) for i, k in rows))
        self.assertTrue(all(1 <= i <= 42 for i in table))

    def test_action_tables_match_mac_and_windows(self):
        """Les trois listes d'actions (script, Mac, Windows) ont les mêmes ids, clés et versions minimales."""
        mods, _ = M.build_fl(api=45)
        dev = M.load_script(mods)
        script = dict((e[0], (e[1], e[3])) for e in dev.ACTIONS)

        def read(*parts):
            with open(os.path.join(M.ROOT, *parts), encoding="utf-8") as fh:
                return fh.read()

        swift = read("Sources", "FLShortcut", "Actions.swift")
        mac = dict((int(i), (k, v)) for i, k, v in re.findall(
            r'FLActionInfo\(id: (\d+), key: "(\w+)", label: "[^"]*", category: \.\w+, minFL: "([\d.]+)"\)', swift))
        cs = read("windows", "FLShortcut.Core", "Actions.cs")
        win = dict((int(i), (k, v)) for i, k, v in re.findall(
            r'new\((\d+), "(\w+)", "[^"]*", ActionCategory\.\w+, "([\d.]+)"\)', cs))
        self.assertEqual(mac, script)
        self.assertEqual(win, script)

        # Descriptions affichées : identiques sur Mac et Windows, une par action.
        mac_detail = dict(re.findall(r'case "(\w+)": return "([^"]*)"', read("Sources", "FLShortcut", "GlassStyle.swift")))
        win_detail = dict(re.findall(r'\["(\w+)"\] = "([^"]*)"', cs))
        self.assertEqual(mac_detail, win_detail)
        self.assertEqual(set(mac_detail), set(k for k, _ in script.values()))


class TestLightweight(Base):
    """Le script ne doit jamais alourdir FL : peu de travail dans OnIdle, erreurs jamais répétées en boucle."""

    def setUp(self):
        self.make()

    def test_idle_does_little_between_ticks(self):
        calls = []
        self.dev.focused_window_code = lambda: calls.append(1) or 127
        self.clock.t += 1.0
        for _ in range(50):
            self.dev.OnIdle()                 # même instant : un seul vrai passage
        self.assertEqual(len(calls), 1)
        self.clock.t += 0.6
        self.dev.OnIdle()
        self.assertEqual(len(calls), 2)

    def test_same_error_reported_once_per_period(self):
        hints = []
        self.dev._hint = hints.append
        for _ in range(30):
            self.dev._report(RuntimeError("x"))
        self.assertEqual(len(hints), 1)
        self.clock.t += 11
        self.dev._report(RuntimeError("x"))
        self.assertEqual(len(hints), 2)




# ---------------------------------------------------------------------------- Commande avec données
class TestData(Base):
    """Action 41 précédée de données (CC 96 / 97) couvertes par le MAC : opération 1, Nom et couleur."""

    RED = (0xE0, 0x45, 0x3A)

    def data_command(self, payload=None, units=None, mac_units=None, start=True):
        if units is None:
            units = M.pack7(payload)
        ccs = M.data_ccs(units) if start else [(97, u) for u in units]
        for ev in self.send_pairs(ccs):
            self.assertTrue(ev.handled)
        self.seq += 1
        mac = M.mac_for(self.nonce(), self.seq, DATA_ID, units=units if mac_units is None else mac_units)
        return self.send_pairs(M.frame(self.nonce(), self.seq, DATA_ID, mac=mac))

    def reasons(self):
        return [v for (s, cc, v) in self.fl.cc_out() if cc == 116]

    def rgb(self, c):
        return (c[0] << 16) | (c[1] << 8) | c[2]

    def test_vector(self):
        units = M.pack7([1, 3, 0xE0, 0x45, 0x3A, 4] + list(b"Kick"))
        self.assertEqual(units, [4, 1, 3, 96, 69, 58, 4, 75, 0, 105, 99, 107])
        self.assertEqual(M.mac_for([17, 42, 99, 5], 300, 41, units=units), [116, 112, 71, 62])
        self.assertEqual(self.dev.unpack7(units), [1, 3, 0xE0, 0x45, 0x3A, 4] + list(b"Kick"))

    def test_unpack7_rejects_malformed(self):
        self.assertIsNone(self.dev.unpack7([4]))            # en-tête seul
        self.assertIsNone(self.dev.unpack7([0b100, 1, 2]))  # bit d'en-tête au-delà du groupe
        self.assertEqual(self.dev.unpack7([]), [])

    def test_name_and_color_on_selected_mixer_track(self):
        self.make(focused={0}, mx_sel={3})
        self.data_command(M.name_color("Kick", self.RED))
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertEqual(self.fl.given_names, {("mixer", 3): "Kick"})
        self.assertEqual(self.fl.given_colors, {("mixer", 3): self.rgb(self.RED)})
        self.assertEqual(self.reasons(), [])

    def test_channel_rack_and_playlist(self):
        self.make(focused={1}, ch_sel={5})
        self.data_command(M.name_color("Lead", self.RED))
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertEqual(self.fl.given_names, {("channels", 5): "Lead"})
        self.make(focused={2}, pl_sel={12})
        self.data_command(M.name_color("Voix", self.RED))
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertEqual(self.fl.given_names, {("playlist", 12): "Voix"})
        self.assertEqual(self.fl.given_colors, {("playlist", 12): self.rgb(self.RED)})

    def test_color_only_and_name_only(self):
        self.make(focused={0}, mx_sel={2})
        self.data_command(M.name_color(color=self.RED))
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertEqual(self.fl.given_names, {})
        self.assertEqual(self.fl.given_colors, {("mixer", 2): self.rgb(self.RED)})
        self.clock.t += 0.1
        self.data_command(M.name_color("Basse"))
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertEqual(self.fl.given_names, {("mixer", 2): "Basse"})

    def test_refusals(self):
        cases = (({"focused": {0}}, 2), ({"focused": {0}, "mx_sel": {1, 4}}, 3),
                 ({"focused": {3}, "mx_sel": {1}}, 1), ({"focused": {1}, "ch_sel": set()}, 2))
        for kw, reason in cases:
            self.make(**kw)
            self.data_command(M.name_color("Kick", self.RED))
            self.assertEqual(self.last_ack(), 0, kw)
            self.assertEqual(self.reasons(), [reason], kw)
            self.assertEqual(self.fl.given_names, {}, kw)
            self.assertEqual(self.fl.given_colors, {}, kw)
            # la raison part juste avant l'accusé 0
            out = [cc for (s, cc, v) in self.fl.cc_out() if cc in (116, 119)]
            self.assertEqual(out[-2:], [116, 119], kw)

    def test_name_utf8_roundtrip(self):
        self.make(focused={0}, mx_sel={7})
        self.data_command(M.name_color("Café 🎹", self.RED))
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertEqual(self.fl.given_names, {("mixer", 7): "Café 🎹"})

    def test_bad_names_refused(self):
        for name in ("", "a" * 65, "x\x07y", "\u00e9" * 64 + "!"):
            self.make(focused={0}, mx_sel={7})
            self.data_command(M.name_color(name))
            self.assertEqual(self.last_ack(), 0, repr(name))
            self.assertEqual(self.reasons(), [5], repr(name))
        self.make(focused={0}, mx_sel={7})
        self.data_command(M.name_color("é" * 64))
        self.assertEqual(self.last_ack(), DATA_ID)
        # octets UTF-8 invalides
        self.make(focused={0}, mx_sel={7})
        self.data_command([1, 1, 0, 0, 0, 2, 0xC3, 0x28])
        self.assertEqual(self.reasons(), [5])
        # drapeaux vides, longueur fausse, opération inconnue
        for payload in ([1, 0, 0, 0, 0, 0], [1, 1, 0, 0, 0, 9] + list(b"ab"), [9, 3, 0, 0, 0, 0]):
            self.make(focused={0}, mx_sel={7})
            self.data_command(payload)
            self.assertEqual(self.reasons(), [5], payload)

    def test_name_never_in_hints(self):
        self.make(focused={0}, mx_sel={1, 2})
        self.data_command(M.name_color("SecretTrack", self.RED))
        self.make(focused={0}, mx_sel={1}, raise_on={"mixer.setTrackName": RuntimeError("boom")})
        self.data_command(M.name_color("SecretTrack", self.RED))
        self.assertEqual(self.last_ack(), 0)
        self.assertFalse(any("SecretTrack" in h for h in self.fl.hints))

    def test_leftover_data_does_not_leak(self):
        self.make(focused={0}, mx_sel={3})
        self.send_pairs(M.data_ccs(M.pack7(M.name_color("Kick"))))   # données sans trame
        self.command(2)                                               # action normale : Stop
        self.assertEqual(self.last_ack(), 2)
        self.clock.t += 0.1
        # la trame 41 suivante, sans nouveau CC 96, ne reprend pas les anciennes données
        self.seq += 1
        self.send_pairs(M.frame(self.nonce(), self.seq, DATA_ID))
        self.assertEqual(self.last_ack(), 0)
        self.assertEqual(self.reasons(), [5])
        self.assertEqual(self.fl.given_names, {})

    def test_data_frame_without_or_oversized_data(self):
        self.make(focused={0}, mx_sel={3})
        self.seq += 1
        self.send_pairs(M.frame(self.nonce(), self.seq, DATA_ID))
        self.assertEqual(self.last_ack(), 0)
        self.assertEqual(self.reasons(), [5])
        self.clock.t += 0.1
        # au-delà de 600 unités, les données sont jetées : le MAC ne correspond plus, refus sans raison
        units = M.pack7(M.name_color("Kick")) + [0] * 600
        self.data_command(units=units)
        self.assertEqual(self.last_ack(), 0)
        self.assertEqual(self.reasons(), [5])
        self.assertEqual(self.fl.given_names, {})

    def test_units_without_start_ignored(self):
        self.make(focused={0}, mx_sel={3})
        self.data_command(M.name_color("Kick"), start=False)
        self.assertEqual(self.last_ack(), 0)
        self.assertEqual(self.fl.given_names, {})

    def test_bad_mac_over_data(self):
        self.make(focused={0}, mx_sel={3})
        units = M.pack7(M.name_color("Kick"))
        self.data_command(units=units, mac_units=M.pack7(M.name_color("Kack")))
        self.assertEqual(self.last_ack(), 0)
        self.assertEqual(self.fl.given_names, {})
        self.assertEqual(self.reasons(), [])          # refus du MAC : aucune raison donnée

    def test_data_ignored_while_asleep(self):
        self.make(focused={0}, mx_sel={3}, wake=False)
        self.send_pairs(M.data_ccs(M.pack7(M.name_color("Kick"))))
        self.assertIsNone(self.dev._st.data)

    def test_playlist_needs_api12(self):
        self.make(api=8, focused={2}, pl_sel={1})
        self.data_command(M.name_color("Kick"))
        self.assertEqual(self.last_ack(), 0)
        self.assertEqual(self.reasons(), [6])            # la Playlist est devant : c'est FL qui est trop ancien
        self.assertFalse([h for h in self.fl.hints if "erreur" in h])

    def test_data_unavailable_without_mixer_functions(self):
        self.make(missing=("mixer.setTrackName",))
        self.assertEqual(self.dev.capability_mask() >> (DATA_ID - 1) & 1, 0)
        self.data_command(M.name_color("Kick"))
        self.assertEqual(self.last_ack(), 0)

    def test_color_needs_fl_conversion(self):
        # sans utils.RGBToColor, aucune couleur devinée (rouge et bleu pourraient être inversés) : refus
        self.make(focused={0}, mx_sel={3}, missing=("utils.RGBToColor",))
        self.data_command(M.name_color("Kick", self.RED))
        self.assertEqual(self.reasons(), [5])
        self.assertEqual(self.fl.given_names, {})
        self.data_command(M.name_color("Kick"))           # le nom seul n'en a pas besoin
        self.assertEqual(self.fl.given_names, {("mixer", 3): "Kick"})

    def test_selection_error_answers_with_a_reason(self):
        self.make(focused={0}, mx_sel={3}, raise_on={"mixer.isTrackSelected": RuntimeError("boom")})
        self.data_command(M.name_color("Kick"))
        self.assertEqual(self.reasons(), [5])
        self.assertEqual(self.last_ack(), 0)

    def test_rate_limit_counts_data_frames(self):
        self.make(focused={0}, mx_sel={3})
        acks = []
        for _ in range(21):
            self.data_command(M.name_color("Kick"))
            acks.append(self.last_ack())
        self.assertEqual(acks[:20], [DATA_ID] * 20)
        self.assertEqual(acks[20], 0)


# ---------------------------------------------------------------------------- Organiser (script v5)
class TestDataV5(TestData):
    """Opérations 2 à 8 (PROTOCOL.md §8) et réponses signées FL -> appli (CC 112 à 115)."""

    def answer(self):
        """Dernière réponse, MAC vérifié avec le seq de la commande, données dépaquetées. Elle part avant l'accusé."""
        found = M.responses(self.fl.cc_out())
        self.assertTrue(found, "aucune réponse")
        op, units, mac = found[-1]
        self.assertEqual(mac, M.mac_for(self.nonce(), self.seq, op, units=units))
        self.assertLessEqual(len(units), 600)
        order = [cc for (s, cc, v) in self.fl.cc_out() if cc in (114, 119)]
        self.assertEqual(order[-2:], [114, 119])
        return op, M.unpack7(units)

    def test_response_mac_vector(self):
        # Vecteur commun avec ProtocolTests.swift (ResponseTests)
        units = M.pack7([1, 0, 2, 0, 0, 0, 0])
        self.assertEqual(units, [0, 1, 0, 2, 0, 0, 0, 0])
        self.assertEqual(M.mac_for([17, 42, 99, 5], 300, 2, units=units), [89, 95, 58, 61])
        self.assertEqual(self.dev.pack7([1, 0, 2, 0, 0, 0, 0]), units)
        self.assertEqual(self.dev.pack7([0xE0, 1]), [1, 0x60, 1])

    def test_list_channels_page(self):
        self.make(n_channels=3, ch_names=["Kick", "808", "Lead"], ch_colors=[0xE0453A, 0x123456, 0xABCDEF],
                  ch_types=[0, 2, 5], ch_fx=[1, 2, 300])
        self.data_command([2, 1, 0, 0])
        self.assertEqual(self.last_ack(), DATA_ID)
        op, data = self.answer()
        self.assertEqual(op, 2)
        self.assertEqual(data[:7], [1, 0, 3, 0, 0, 3, 0])
        rest = data[7:]
        self.assertEqual(rest[:7] + [bytes(rest[7:11]).decode()], [0, 0, 1, 0xE0, 0x45, 0x3A, 4, "Kick"])
        rest = rest[11:]
        self.assertEqual(rest[:7], [2, 0, 2, 0x12, 0x34, 0x56, 3])
        rest = rest[10:]
        self.assertEqual(rest, [5, 1, 44, 0xAB, 0xCD, 0xEF, 4] + list(b"Lead"))

    def test_list_pages_and_utf8_cut(self):
        self.make(n_channels=20, ch_names=["é" * 20] * 20)
        self.data_command([2, 1, 0, 0])
        _, data = self.answer()
        self.assertEqual(data[:7], [1, 0, 20, 0, 0, 16, 0])
        first_len = data[7 + 6]
        self.assertEqual(first_len, 24)                       # 12 « é » : coupé entre deux caractères
        self.assertEqual(bytes(data[14:14 + 24]).decode(), "é" * 12)
        self.clock.t += 0.1
        self.data_command([2, 1, 0, 16])
        _, data = self.answer()
        self.assertEqual(data[:7], [1, 0, 20, 0, 16, 4, 0])
        self.make(n_channels=16, ch_names=["x" * 40] * 16)     # page pleine : 600 unités au plus
        self.data_command([2, 1, 0, 0])
        _, data = self.answer()
        self.assertEqual(data[5], 16)
        cut = "\U0001F3B9" * 7                                 # 4 octets chacun : coupé à 24 → 6 caractères
        self.make(n_channels=1, ch_names=[cut])
        self.data_command([2, 1, 0, 0])
        _, data = self.answer()
        self.assertEqual(bytes(data[14:]).decode(), "\U0001F3B9" * 6)

    def test_list_filtered_group(self):
        self.make(n_channels=3, n_channels_global=5)
        self.data_command([2, 1, 0, 0])
        _, data = self.answer()
        self.assertEqual(data[6], 1)

    def test_list_mixer(self):
        self.make(n_tracks=3, mx_names={0: "Master", 2: "Kick"}, mx_colors={2: 0xE0453A})
        self.data_command([2, 2, 0, 0])
        _, data = self.answer()
        self.assertEqual(data[:7], [2, 0, 3, 0, 0, 3, 0])
        self.assertEqual(data[7:7 + 4] + [bytes(data[11:17]).decode()], [0x4B, 0x55, 0x60, 6, "Master"])
        self.assertEqual(data[-8:], [0xE0, 0x45, 0x3A, 4] + list(b"Kick"))

    def test_list_bad_kind_or_start(self):
        for payload in ([2, 4, 0, 0], [2, 1, 0, 9], [2, 1], [2, 3, 1, 245]):
            self.make(n_channels=4)
            self.data_command(payload)
            self.assertEqual(self.last_ack(), 0, payload)
            self.assertEqual(self.reasons(), [5], payload)
            self.assertEqual(M.responses(self.fl.cc_out()), [], payload)

    def test_set_colors(self):
        self.make(n_channels=4)
        self.data_command([4, 1, 2] + M.be16(1) + [0xE0, 0x45, 0x3A] + M.be16(3) + [1, 2, 3])
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertEqual(self.fl.given_colors, {("channels", 1): 0xE0453A, ("channels", 3): 0x010203})
        self.clock.t += 0.1
        self.data_command([4, 2, 1] + M.be16(5) + [9, 9, 9])
        self.assertEqual(self.fl.given_colors[("mixer", 5)], 0x090909)

    def test_set_colors_bad_index(self):
        self.make(n_channels=4)
        self.data_command([4, 1, 2] + M.be16(1) + [1, 1, 1] + M.be16(9) + [2, 2, 2])
        self.assertEqual(self.last_ack(), 0)
        self.assertEqual(self.reasons(), [5])
        self.assertEqual(self.fl.given_colors, {})             # tout vérifié avant de poser quoi que ce soit
        self.make(n_channels=4)
        self.data_command([4, 1, 65] + (M.be16(0) + [1, 1, 1]) * 65)
        self.assertEqual(self.reasons(), [5])

    def test_select_one_channel_and_mixer(self):
        self.make(n_channels=4, mx_sel={1, 2})
        self.data_command([5, 1] + M.be16(2))
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertEqual(self.fl.channel, 2)
        self.clock.t += 0.1
        self.data_command([5, 2] + M.be16(7))
        self.assertEqual(self.fl.mx_sel, {7})
        self.make(api=26, mx_sel={1, 2})                      # sans setActiveTrack
        self.data_command([5, 2] + M.be16(7))
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertEqual(self.fl.mx_sel, {7})

    def test_channel_mute_and_solo_by_number(self):
        self.make(n_channels=12, ch_muted={3})
        self.data_command([13, 0] + M.be16(11))               # canal 12, au-delà des touches 1 à 0 de FL
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertEqual(self.fl.ch_muted, {3, 11})
        self.clock.t += 0.1
        self.data_command([13, 0] + M.be16(3))                # bascule : le son revient
        self.assertEqual(self.fl.ch_muted, {11})
        self.clock.t += 0.1
        self.data_command([13, 1] + M.be16(5))
        self.assertEqual(self.fl.ch_solo, {5})
        for payload in ([13, 0] + M.be16(12), [13, 2] + M.be16(1), [13, 0, 1]):
            self.make(n_channels=12)
            self.data_command(payload)
            self.assertEqual(self.reasons(), [5], payload)

    def test_play_solo_mutes_others_and_plays(self):
        self.make(n_channels=4, ch_muted={3}, loop_mode=1, song_pos=0.5)
        self.data_command([6] + M.be16(1))
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertEqual(self.fl.ch_muted, {0, 2, 3})
        self.assertTrue(self.fl.playing)
        self.assertEqual((self.fl.loop_mode, self.fl.song_pos), (0, 0.0))
        self.clock.t += 0.1
        self.data_command([6] + M.be16(2))                    # canal suivant : arrêt, sourdines, relance
        self.assertEqual(self.fl.ch_muted, {0, 1, 3})
        self.assertTrue(self.fl.playing)
        self.clock.t += 0.1
        self.data_command([7])
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertFalse(self.fl.playing)
        self.assertEqual(self.fl.ch_muted, {3})
        self.assertEqual((self.fl.loop_mode, self.fl.song_pos), (1, 0.5))
        self.assertIsNone(self.dev._st.memo)

    def test_play_solo_in_group_mutes_whole_project(self):
        # Channel rack sur un groupe (« Unsorted ») : canal compté dans le groupe affiché, sourdines sur tout le
        # projet (API 33), canaux masqués compris.
        self.make(n_channels=2, n_channels_global=4, ch_group=[1, 3], ch_muted={0})
        self.data_command([6] + M.be16(0))
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertEqual(self.fl.ch_muted, {0, 2, 3})
        self.clock.t += 0.1
        self.data_command([6] + M.be16(1))
        self.assertEqual(self.fl.ch_muted, {0, 1, 2})
        self.clock.t += 0.1
        self.data_command([7])
        self.assertEqual(self.fl.ch_muted, {0})
        self.clock.t += 0.1
        self.data_command([6] + M.be16(2))                    # hors du groupe affiché
        self.assertEqual(self.reasons(), [5])

    def test_listening_turns_the_metronome_off_then_back_on(self):
        # Allumé, le métronome sonnerait avec chaque son écouté : éteint pendant l'écoute, rallumé à la remise.
        self.make(n_channels=2, metronome=True)
        self.data_command([6] + M.be16(0))
        self.assertFalse(self.fl.metronome)
        self.clock.t += 0.1
        self.data_command([6] + M.be16(1))
        self.assertFalse(self.fl.metronome)
        self.clock.t += 0.1
        self.data_command([7])
        self.assertTrue(self.fl.metronome)
        self.make(n_channels=2)                               # éteint : jamais allumé par l'écoute
        self.data_command([6] + M.be16(0))
        self.clock.t += 0.1
        self.data_command([7])
        self.assertFalse(self.fl.metronome)

    def test_play_solo_in_group_before_api33(self):
        self.make(api=30, n_channels=2, n_channels_global=4, ch_group=[1, 3])
        self.data_command([6] + M.be16(0))
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertEqual(self.fl.ch_muted, {3})               # les canaux affichés seulement
        self.clock.t += 0.1
        self.data_command([7])
        self.assertEqual(self.fl.ch_muted, set())

    def test_play_solo_refuses_when_playing(self):
        self.make(n_channels=4, playing=True)
        self.data_command([6] + M.be16(1))
        self.assertEqual(self.last_ack(), 0)
        self.assertEqual(self.reasons(), [4])
        self.assertEqual(self.fl.ch_muted, set())
        self.assertTrue(self.fl.playing)
        self.assertIsNone(self.dev._st.memo)

    def test_play_solo_bad_channel(self):
        self.make(n_channels=4)
        self.data_command([6] + M.be16(4))
        self.assertEqual(self.reasons(), [5])
        self.assertIsNone(self.dev._st.memo)

    def test_stop_restore_without_memo(self):
        # Sans écoute en cours (refus 4 : l'utilisateur joue), rien n'est touché : sa lecture continue.
        self.make(n_channels=4, playing=True)
        self.data_command([7])
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertTrue(self.fl.playing)

    def test_sleep_restores_memo(self):
        self.make(n_channels=4, wake=False, ch_muted={0})
        self.send(103, 2)                                     # réveil bref (macro)
        self.clock.t += 0.3
        self.data_command([6] + M.be16(2))
        self.assertEqual(self.fl.ch_muted, {0, 1, 3})
        self.clock.t += 9                                     # l'appli a disparu : le script se rendort
        self.dev.OnIdle()
        self.assertFalse(self.dev._st.awake)
        self.assertEqual(self.fl.ch_muted, {0})
        self.assertFalse(self.fl.playing)
        self.assertIsNone(self.dev._st.memo)

    def test_deinit_restores_memo(self):
        self.make(n_channels=4)
        self.data_command([6] + M.be16(2))
        self.dev.OnDeInit()
        self.assertEqual(self.fl.ch_muted, set())

    def test_audition_note_on_off(self):
        self.make(n_channels=4)
        self.data_command([3] + M.be16(2) + [48, 100])
        self.assertEqual(self.last_ack(), DATA_ID)
        self.clock.t += 0.1
        self.data_command([3] + M.be16(2) + [48, 0])
        self.assertEqual(self.fl.notes, [(2, 48, 100), (2, 48, 0)])
        self.clock.t += 0.1
        self.data_command([3] + M.be16(2) + [128, 100])       # note hors MIDI
        self.assertEqual(self.reasons(), [5])

    def test_gradient_three_tracks(self):
        self.make(focused={0}, mx_sel={2, 5, 9})
        self.data_command([8, 0xE0, 0x45, 0x3A, 0x3F, 0xA7, 0xE0])
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertEqual(self.fl.given_colors, {("mixer", 2): 0xE0453A, ("mixer", 5): 0x90768D,
                                                ("mixer", 9): 0x3FA7E0})
        self.make(focused={1}, ch_sel={0, 1}, n_channels=4)
        self.data_command([8, 0, 0, 0, 255, 255, 255])
        self.assertEqual(self.fl.given_colors, {("channels", 0): 0, ("channels", 1): 0xFFFFFF})

    def test_gradient_needs_two(self):
        for kw, reason in (({"focused": {0}, "mx_sel": {2}}, 7), ({"focused": {0}}, 2),
                           ({"focused": {1}, "ch_sel": {3}}, 7), ({"focused": {3}, "mx_sel": {1, 2}}, 1)):
            self.make(**kw)
            self.data_command([8, 1, 2, 3, 4, 5, 6])
            self.assertEqual(self.last_ack(), 0, kw)
            self.assertEqual(self.reasons(), [reason], kw)
            self.assertEqual(self.fl.given_colors, {}, kw)

    def test_caps_bit_42(self):
        self.assertEqual(self.dev.capability_mask() >> 41 & 1, 1)
        self.make(missing=("utils.ColorToRGB",))
        self.assertEqual(self.dev.capability_mask() >> 41 & 1, 0)
        self.assertEqual(self.dev.capability_mask() >> 40 & 1, 1)   # l'opération 1 reste là

    def test_missing_function_says_old_fl(self):
        self.make(n_channels=4, missing=("channels.selectOneChannel",))
        self.data_command([5, 1] + M.be16(2))
        self.assertEqual(self.reasons(), [6])
        self.make(api=8, n_channels=4)                        # getChannelType : API 19
        self.data_command([2, 1, 0, 0])
        _, data = self.answer()
        self.assertEqual(data[7], 0)                          # type inconnu : 0

    def test_ext_ops_unknown_op(self):
        for payload in ([14], [0], [8, 1, 2], [9, 0]):
            self.make(focused={0}, mx_sel={1, 2})
            self.data_command(payload)
            self.assertEqual(self.reasons(), [5], payload)

    # -- Playlist (opérations 9 à 12, genre 3)

    def test_page_code(self):
        for focused, code in (({2}, 2), ({1}, 1), ({0}, 0), ((), 127)):
            self.make(focused=focused)
            self.data_command([9])
            self.assertEqual(self.last_ack(), DATA_ID, focused)
            self.assertEqual(self.answer(), (9, [code]), focused)

    def test_list_playlist(self):
        self.make(pl_tracks=3, pl_names={1: "Kick", 3: "Voix"}, pl_colors={1: 0xE0453A}, pl_sel={3})
        self.data_command([2, 3, 0, 0])
        self.assertEqual(self.last_ack(), DATA_ID)
        op, data = self.answer()
        self.assertEqual(op, 2)
        self.assertEqual(data[:7], [3, 0, 3, 0, 0, 3, 0])
        rest = data[7:]
        self.assertEqual(rest[:5] + [bytes(rest[5:9]).decode()], [0, 0xE0, 0x45, 0x3A, 4, "Kick"])
        rest = rest[9:]
        self.assertEqual(rest[:5] + [bytes(rest[5:12]).decode()], [0, 0x56, 0x5E, 0x66, 7, "Track 2"])
        rest = rest[12:]
        self.assertEqual(rest, [1, 0x56, 0x5E, 0x66, 4] + list(b"Voix"))
        self.make(pl_tracks=40)                               # pages de 16, comme les autres genres
        self.data_command([2, 3, 0, 32])
        _, data = self.answer()
        self.assertEqual(data[:7], [3, 0, 40, 0, 32, 8, 0])
        self.make(api=11, pl_tracks=2, pl_sel={1})            # sélection : API 12
        self.data_command([2, 3, 0, 0])
        _, data = self.answer()
        self.assertEqual(data[7], 0)

    def test_set_colors_playlist(self):
        self.make(pl_tracks=4)
        self.data_command([4, 3, 2] + M.be16(0) + [0xE0, 0x45, 0x3A] + M.be16(3) + [1, 2, 3])
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertEqual(self.fl.given_colors, {("playlist", 1): 0xE0453A, ("playlist", 4): 0x010203})
        self.make(pl_tracks=4)
        self.data_command([4, 3, 1] + M.be16(4) + [1, 2, 3])
        self.assertEqual(self.reasons(), [5])
        self.assertEqual(self.fl.given_colors, {})

    def test_set_names_playlist(self):
        self.make(pl_tracks=4)
        self.data_command([10, 3, 2] + M.be16(0) + [4] + list(b"Kick") + M.be16(3) + [7] + list("Hi-hât".encode()))
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertEqual(self.fl.given_names, {("playlist", 1): "Kick", ("playlist", 4): "Hi-hât"})

    def test_set_names_checks_everything_first(self):
        good = M.be16(0) + [4] + list(b"Kick")
        for payload in ([10, 3, 2] + good + M.be16(4) + [4] + list(b"Clap"),   # piste 5 sur 4
                        [10, 2, 1] + good,                                     # pas la Playlist
                        [10, 3, 1] + good + [0],                               # octet en trop
                        [10, 3, 2] + good,                                     # un nom manquant
                        [10, 3, 1] + M.be16(1) + [0],                          # nom vide
                        [10, 3, 1] + M.be16(1) + [33] + [65] * 33,             # nom trop long
                        [10, 3, 1] + M.be16(1) + [2, 0xC3, 0x28],              # UTF-8 invalide
                        [10, 3, 0], [10, 3, 17] + good * 17):
            self.make(pl_tracks=4)
            self.data_command(payload)
            self.assertEqual(self.last_ack(), 0, payload)
            self.assertEqual(self.reasons(), [5], payload)
            self.assertEqual(self.fl.given_names, {}, payload)

    def test_play_track_seek_and_restore(self):
        self.make(pl_tracks=4, pl_muted={4}, loop_mode=0, song_pos=0.25, song_bars=48)
        self.data_command([11] + M.be16(1))
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertEqual(self.answer(), (11, [0, 48]))
        self.assertEqual(self.fl.pl_muted, {1, 3, 4})          # seule la piste 2 de FL s'entend
        self.assertTrue(self.fl.playing)
        self.assertEqual((self.fl.loop_mode, self.fl.song_pos), (1, 0.0))
        self.clock.t += 0.1
        self.data_command([12] + M.be16(500))
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertEqual(self.fl.song_pos, 0.5)
        self.clock.t += 0.1
        self.data_command([11] + M.be16(3))                   # piste suivante : arrêt, sourdines, relance
        self.assertEqual(self.fl.pl_muted, {1, 2, 3})
        self.assertTrue(self.fl.playing)
        self.clock.t += 0.1
        self.data_command([7])
        self.assertEqual(self.last_ack(), DATA_ID)
        self.assertFalse(self.fl.playing)
        self.assertEqual(self.fl.pl_muted, {4})
        self.assertEqual((self.fl.loop_mode, self.fl.song_pos), (0, 0.25))
        self.assertIsNone(self.dev._st.memo)

    def test_play_track_refuses_when_playing_or_bad(self):
        self.make(pl_tracks=4, playing=True)
        self.data_command([11] + M.be16(1))
        self.assertEqual(self.reasons(), [4])
        self.assertEqual(self.fl.pl_muted, set())
        self.assertIsNone(self.dev._st.memo)
        for payload in ([11] + M.be16(4), [11, 0], [12] + M.be16(100)):  # piste hors Playlist, court, sans écoute
            self.make(pl_tracks=4)
            self.data_command(payload)
            self.assertEqual(self.reasons(), [5], payload)
            self.assertIsNone(self.dev._st.memo, payload)
        self.make(pl_tracks=4)
        self.data_command([11] + M.be16(0))
        self.clock.t += 0.1
        self.data_command([12] + M.be16(1001))                # au-delà de la fin
        self.assertEqual(self.reasons(), [5])

    def test_play_track_old_fl(self):
        self.make(pl_tracks=4, missing=("playlist.isTrackMuted",))
        self.data_command([11] + M.be16(0))
        self.assertEqual(self.reasons(), [6])
        self.make(api=2, pl_tracks=4)                         # longueur de la chanson : API 3 → 0, l'appli devine
        self.data_command([11] + M.be16(0))
        self.assertEqual(self.answer(), (11, [0, 0]))

    def test_channel_then_playlist_listening(self):
        # Passer d'une écoute du Channel rack à la Playlist remet d'abord les canaux comme avant, et inversement.
        self.make(n_channels=4, pl_tracks=3, ch_muted={0}, pl_muted={2})
        self.data_command([6] + M.be16(1))
        self.assertEqual(self.fl.ch_muted, {0, 2, 3})
        self.clock.t += 0.1
        self.data_command([11] + M.be16(0))
        self.assertEqual(self.fl.ch_muted, {0})
        self.assertEqual(self.fl.pl_muted, {2, 3})
        self.clock.t += 0.1
        self.data_command([6] + M.be16(2))
        self.assertEqual(self.fl.pl_muted, {2})
        self.assertEqual(self.fl.ch_muted, {0, 1, 3})
        self.dev.OnDeInit()
        self.assertEqual((self.fl.ch_muted, self.fl.pl_muted), ({0}, {2}))

    def test_playlist_sleep_restores(self):
        self.make(pl_tracks=3, wake=False, pl_muted={1})
        self.send(103, 2)                                     # réveil bref
        self.clock.t += 0.3
        self.data_command([11] + M.be16(1))
        self.assertEqual(self.fl.pl_muted, {1, 3})
        self.clock.t += 9
        self.dev.OnIdle()
        self.assertEqual(self.fl.pl_muted, {1})
        self.assertFalse(self.fl.playing)

    def test_names_never_in_hints(self):
        self.make(n_channels=2, ch_names=["SecretTrack", "SecretTrack"],
                  raise_on={"channels.getChannelColor": RuntimeError("SecretTrack")})
        self.data_command([2, 1, 0, 0])
        self.assertEqual(self.last_ack(), 0)
        self.assertFalse(any("SecretTrack" in h for h in self.fl.hints))


if __name__ == "__main__":
    unittest.main(verbosity=2)
