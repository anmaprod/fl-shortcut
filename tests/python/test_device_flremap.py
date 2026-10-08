"""Tests du script FL Studio Resources/device_FLRemap.py (protocole v2).

Lancement : python3 -m unittest discover -s tests/python -v
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

ALL_IDS = list(range(1, 39))
# Actions qui exigent une API récente (audit 04 §6) : id -> API minimale
API_MIN = {12: 25, 24: 19, 25: 12, 19: 10, 20: 10, 18: 9}
TEST_APIS = (1, 2, 5, 8, 9, 10, 12, 13, 19, 20, 25, 28, 45)


class Base(unittest.TestCase):
    API = 45
    KEY = M.TEST_KEY_HEX

    def make(self, api=None, key_hex="default", init=True, block=(), **kw):
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
                 "setHintMsg", "selectedChannel", "getLoopMode")
        return [n for n in self.fl.names() if not any(r in n for r in reads)]


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
        for aid in (0, 39, 42, 127):
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
        self.fl.focused = {0}
        self.clock.t += 0.2
        self.dev.OnRefresh(32)
        self.fl.focused = {3}
        self.dev.OnRefresh(32)          # < 100 ms : différé
        self.clock.t += 0.15
        self.dev.OnIdle()
        self.dev.OnRefresh(32)
        wins = [v for s, cc, v in self.fl.cc_out() if cc == 117]
        self.assertEqual(wins[-2:], [0, 3])
        self.fl.focused = {7}
        self.clock.t += 0.6
        self.dev.OnIdle()
        self.assertEqual([v for s, cc, v in self.fl.cc_out() if cc == 117][-1], 5)
        self.fl.focused = set()
        self.clock.t += 0.6
        self.dev.OnIdle()
        self.assertEqual([v for s, cc, v in self.fl.cc_out() if cc == 117][-1], 127)

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
        self.assertEqual(self.caps_for(45), set(ALL_IDS))

    def test_api1_without_recent_actions(self):
        caps = self.caps_for(1)
        self.assertEqual(caps, set(ALL_IDS) - set(API_MIN))

    def test_thresholds(self):
        for api in TEST_APIS:
            caps = self.caps_for(api)
            expected = set(i for i in ALL_IDS if api >= API_MIN.get(i, 1))
            self.assertEqual(caps, expected, "API %d" % api)

    def test_mask_bit_layout(self):
        self.make(api=45)
        d = dict(self.last_hello()[1:-1])
        self.assertEqual(d[90], 127)        # ids 1..7
        self.assertEqual(d[95], 0b111)      # ids 36, 37, 38
        self.make(api=1)
        d = dict(self.last_hello()[1:-1])
        # id 12 (clone) = bit 11 = CC 91 bit 4 ; id 18 (quant) = CC 92 bit 3
        self.assertEqual(d[91] >> 4 & 1, 0)
        self.assertEqual(d[92] >> 3 & 1, 0)

    def test_missing_function_greys_only_that_action(self):
        self.make(api=45, missing=("patterns.clonePattern",))
        mask = self.mask_of(self.last_hello())
        self.assertEqual(mask >> 11 & 1, 0)
        self.assertEqual(bin(mask).count("1"), 37)

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
        self.dev._time = M.FakeClock()
        self.dev.OnInit()
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
        for bad in ("", "zz" * 16, "00" * 16, "0011", "__FLREMAP_KEY__"):
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
        self.assertEqual(lines[0], "# name=FL Remap")
        self.assertIn("# supportedDevices=FL Remap", lines[:5])
        self.assertNotIn("# url=", lines[:5])     # url vide inutile (audit 04 §7.1)

    def test_key_placeholder_once(self):
        self.assertEqual(self.src.count("__FLREMAP_KEY__"), 1)
        self.assertEqual(len(re.findall(r'^KEY_HEX = "__FLREMAP_KEY__"$', self.src, re.M)), 1)

    def test_action_table_matches_protocol(self):
        proto = os.path.join(M.ROOT, "PROTOCOL.md")
        with open(proto, encoding="utf-8") as fh:
            rows = re.findall(r"^\| (\d+) \| (\w+) \|", fh.read(), re.M)
        mods, _ = M.build_fl(api=45)
        dev = M.load_script(mods)
        table = dict((e[0], e[1]) for e in dev.ACTIONS)
        self.assertEqual(table, dict((int(i), k) for i, k in rows))
        self.assertTrue(all(1 <= i <= 42 for i in table))


if __name__ == "__main__":
    unittest.main(verbosity=2)
