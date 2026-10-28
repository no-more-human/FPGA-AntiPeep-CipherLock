import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import json
import tempfile
import time
import unittest
from pathlib import Path

from modules.audit import AuditStore
from modules.config import load_config
from modules.controller import Controller
from modules.policy import VisionPolicy, Decision
from modules.protocol import StreamParser, encode
from modules.simulator import SimulatedFPGA


TEST_TMP = Path(__file__).resolve().parents[1]/".test-tmp"
TEST_TMP.mkdir(exist_ok=True)


class Clock:
    def __init__(self):
        self.now = 100.0
    def __call__(self):
        return self.now


class Recorder:
    def __init__(self):
        self.jobs = []
    def trigger(self, event_id, code):
        self.jobs.append((event_id, code))


class ProtocolTests(unittest.TestCase):
    def test_fragmented_and_concatenated_stream(self):
        parser = StreamParser()
        frame = encode({"type": "ack", "id": "abc", "ok": True})
        self.assertEqual(parser.feed(frame[:7]), [])
        result = parser.feed(frame[7:]+b"ULD A\r\n")
        self.assertEqual(result[0]["id"], "abc")
        self.assertEqual([e["code"] for e in result[1:]], list("ULDA"))

    def test_json_text_does_not_trigger_false_alarms(self):
        parser = StreamParser()
        result = parser.feed(encode({"type": "ack", "id": "DULACE", "ok": False}))
        self.assertEqual(len(result), 1)
        self.assertNotIn("code", result[0])

    def test_malformed_oversized_frame_resynchronizes(self):
        parser = StreamParser()
        result = parser.feed(b"@"+b"D"*2000+b"\nU")
        self.assertEqual(result, [{"type": "event", "code": "U"}])
        self.assertEqual(parser.feed(b"@\xff\nL"), [{"type": "event", "code": "L"}])


class PolicyTests(unittest.TestCase):
    def test_peep_requires_continuity_and_recovery_hysteresis(self):
        p = VisionPolicy(enter=1.5, exit=2)
        for t in (0, .5, 1):
            self.assertFalse(p.update(t, 2, []).peeping)
        self.assertTrue(p.update(1.5, 2, []).changed)
        for t in (2, 2.5, 3, 3.5):
            self.assertTrue(p.update(t, 1, []).peeping)
        self.assertFalse(p.update(4, 1, []).peeping)

    def test_camera_gap_cannot_complete_face_authentication(self):
        p = VisionPolicy(face_stable=2)
        face = [{"name": "owner", "authorized": True}]
        p.update(0, 1, face)
        self.assertFalse(p.update(10, 1, face).face_ready)
        for t in (10.5, 11, 11.5):
            self.assertFalse(p.update(t, 1, face).face_ready)
        self.assertTrue(p.update(12, 1, face).face_ready)
        self.assertFalse(p.update(12.1, 2, face).face_ready)

    def test_second_face_blocks_remote_even_if_person_detection_misses_it(self):
        p = VisionPolicy(face_stable=.1)
        faces = [{"name": "owner", "authorized": True}, {"name": "UNKNOWN", "authorized": False}]
        self.assertFalse(p.update(0, 1, faces).face_ready)
        self.assertFalse(p.update(.5, 1, faces).face_ready)


class SimulatorTests(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self.sim = SimulatedFPGA(clock=self.clock)

    def codes(self, events):
        return [e["code"] for e in events if "code" in e]

    def test_virtual_digits_and_duress_priority(self):
        self.assertEqual(self.codes(self.sim.submit("88912345666")), ["U"])
        self.assertEqual(self.codes(self.sim.submit("123456654321")), ["D"])

    def test_lockout_expires_and_duress_stays_available(self):
        for _ in range(2):
            self.assertEqual(self.codes(self.sim.submit("000000")), ["E"])
        self.assertEqual(self.codes(self.sim.submit("000000")), ["E", "L"])
        self.assertEqual(self.sim.submit("123456"), [])
        self.assertEqual(self.codes(self.sim.submit("654321")), ["D"])
        self.clock.now += 60
        self.assertIn("T", self.codes(self.sim.tick()))
        self.assertEqual(self.codes(self.sim.submit("123456")), ["U"])

    def test_peep_suspends_normal_input_without_blocking_duress(self):
        self.sim.command("P")
        self.assertEqual(self.sim.submit("123456"), [])
        self.assertEqual(self.codes(self.sim.submit("99654321")), ["D"])

    def test_change_rejects_wrong_old_duplicate_and_bad_length(self):
        base = {"id": "1", "op": "password_change", "kind": "normal", "old": "000000", "new": "112233"}
        self.assertFalse(self.sim.request(base)[0]["ok"])
        self.assertEqual(self.sim.normal, "123456")
        self.assertFalse(self.sim.request({**base, "old": "123456", "new": "654321"})[0]["ok"])
        self.assertFalse(self.sim.request({**base, "old": "123456", "new": "1234"})[0]["ok"])

    def test_valid_change_activates_only_new_password(self):
        answer = self.sim.request({"id": "1", "op": "password_change", "kind": "normal",
                                   "old": "123456", "new": "112233"})
        self.assertTrue(answer[0]["ok"])
        self.assertEqual(self.codes(self.sim.submit("123456")), ["E"])
        self.assertEqual(self.codes(self.sim.submit("8811223399")), ["U"])

    def test_input_overflow_rejects_whole_attempt(self):
        with self.assertRaises(ValueError):
            self.sim.submit("9"*16+"123456")
        with self.assertRaises(ValueError):
            self.sim.submit("１２３４５６")


class ControllerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=TEST_TMP)
        self.audit = AuditStore(self.temp.name)
        self.recorder = Recorder()
        self.events = []
        self.cfg = load_config()
        self.controller = Controller(self.cfg, self.audit, self.recorder, self.events.append, demo=True)

    def tearDown(self):
        self.controller.close()
        self.audit.close()
        self.temp.cleanup()

    def test_duress_is_visible_as_normal_on_site_and_retained_for_security(self):
        self.controller.handle({"type": "event", "code": "D"})
        self.assertEqual(self.controller.lines[-1][1:], ("U", "正常开锁"))
        self.assertFalse(self.controller.alarms)
        self.assertNotIn("D", [row[2] for row in self.audit.recent()])
        self.assertIn("D", [row[2] for row in self.audit.recent(include_sensitive=True)])
        self.assertEqual(self.recorder.jobs[-1][1], "D")

    def test_security_endpoint_gets_alarm(self):
        self.cfg["alarm_display"] = "security"
        self.controller.handle({"type": "event", "code": "D"})
        self.assertEqual(list(self.controller.alarms), ["紧急胁迫报警"])

    def test_send_does_not_claim_hardware_unlocked(self):
        self.controller.send("R")
        self.assertNotIn("已开锁", self.controller.state.lock)
        self.controller.handle(self.events.pop())
        self.assertIn("已开锁", self.controller.state.lock)

    def test_face_unlock_rejects_missing_stale_and_unstable_observations(self):
        with self.assertRaises(ValueError):
            self.controller.face_unlock()
        now = time.monotonic()
        self.controller.vision = {"captured_at": now-3, "analyzed_at": now,
                                  "decision": Decision(False, False, True, "owner")}
        with self.assertRaises(ValueError):
            self.controller.face_unlock(now)
        self.controller.vision["captured_at"] = now
        self.controller.face_unlock(now)
        with self.assertRaises(ValueError):
            self.controller.face_unlock(now+.1)

    def test_password_ack_and_logs_never_store_credentials(self):
        callbacks = []
        self.controller.change_password("normal", "123456", "112233", "112233",
                                        lambda *a: callbacks.append(a))
        self.assertEqual(callbacks, [])
        self.controller.handle(self.events.pop())
        self.assertTrue(callbacks[0][0])
        rows = str(self.audit.recent(include_sensitive=True))
        self.assertNotIn("123456", rows)
        self.assertNotIn("112233", rows)
        self.assertEqual(self.controller.pending, {})

    def test_timeout_does_not_report_password_updated(self):
        callbacks = []
        self.controller.change_password("normal", "123456", "112233", "112233",
                                        lambda *a: callbacks.append(a))
        request = next(iter(self.controller.pending.values()))
        request["at"] -= 6
        self.controller.tick()
        self.assertFalse(callbacks[0][0])
        self.assertIn("结果未知", callbacks[0][1])

    def test_evidence_attachments_merge_instead_of_overwriting_photos(self):
        event_id = self.audit.add("D", "alarm", sensitive=True)
        self.audit.attach(event_id, ["capture.jpg"])
        self.audit.attach(event_id, ["segment.avi", "capture.jpg"])
        row = self.audit.recent(include_sensitive=True)[0]
        self.assertEqual(json.loads(row[4]), ["capture.jpg", "segment.avi"])

    def test_legacy_hardware_disables_password_extension(self):
        self.controller.demo = False
        with self.assertRaises(ValueError):
            self.controller.change_password("normal", "123456", "112233", "112233", lambda *a: None)

    def test_camera_loss_and_recovery_resynchronize_protection(self):
        now = time.monotonic()
        self.controller.update_vision({"captured_at": now, "decision": Decision(False, False, False, None)})
        self.assertFalse(self.controller.sim.peeping)
        self.controller.update_vision(None)
        self.assertTrue(self.controller.sim.peeping)
        self.controller.update_vision({"captured_at": now, "decision": Decision(False, False, False, None)})
        self.assertFalse(self.controller.sim.peeping)


if __name__ == "__main__":
    unittest.main()
