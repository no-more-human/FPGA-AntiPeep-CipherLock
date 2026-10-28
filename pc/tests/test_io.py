import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import queue
import os
import tempfile
import time
import unittest
from pathlib import Path

import cv2
import numpy as np
import serial

from modules.config import load_config
from modules.evidence import EvidenceRecorder
from modules.serial_comm import SerialLink


TEST_TMP = Path(__file__).resolve().parents[1]/".test-tmp"
TEST_TMP.mkdir(exist_ok=True)


class SerialTests(unittest.TestCase):
    def test_pyserial_loopback_receives_batched_events(self):
        events = queue.Queue()
        def factory(port, **kwargs):
            return serial.serial_for_url(port, **kwargs)
        link = SerialLink("loop://", 115200, events.put, factory=factory)
        link.start()
        try:
            deadline = time.monotonic()+2
            while not link.connected and time.monotonic() < deadline:
                time.sleep(.01)
            self.assertTrue(link.connected)
            with link.mutex:
                link.handle.write(b"ULD")
            codes = []
            while len(codes) < 3 and time.monotonic() < deadline:
                message = events.get(timeout=1)
                if message.get("type") == "event":
                    codes.append(message["code"])
            self.assertEqual(codes, ["U", "L", "D"])
        finally:
            link.close()
        self.assertFalse(link.connected)
        self.assertFalse(link.send("R"))


class EvidenceTests(unittest.TestCase):
    def test_real_jpeg_and_video_roundtrip_in_unicode_directory(self):
        with tempfile.TemporaryDirectory(dir=TEST_TMP) as tmp:
            root = Path(tmp)/"中文取证目录"
            cfg = load_config()
            cfg.update(record_fps=8, segment_seconds=.6, event_record_seconds=1)
            messages = queue.Queue()
            recorder = EvidenceRecorder(root, cfg, messages.put)
            frame = np.full((120, 160, 3), 100, np.uint8)
            recorder.submit(frame)
            recorder.trigger(7, "D")
            paths, failures = [], []
            deadline = time.monotonic()+1.3
            while time.monotonic() < deadline:
                recorder.submit(frame)
                try:
                    message = messages.get(timeout=.1)
                except queue.Empty:
                    continue
                if message["type"] == "evidence":
                    paths.extend(p for p in message["paths"] if p.endswith(".jpg"))
                if message["type"] == "evidence_error":
                    failures.append(message)
            recorder.close()
            self.assertEqual(failures, [])
            self.assertEqual(len(paths), 1)
            raw = np.fromfile(paths[0], np.uint8)
            self.assertEqual(cv2.imdecode(raw, cv2.IMREAD_COLOR).shape, frame.shape)
            videos = list((root/"recordings").glob("*.avi"))
            self.assertGreaterEqual(len(videos), 1)
            cap = cv2.VideoCapture(str(videos[0]))
            try:
                ok, decoded = cap.read()
                self.assertTrue(ok)
                self.assertEqual(decoded.shape, frame.shape)
            finally:
                cap.release()

    def test_retention_removes_old_rolling_video_and_preserves_snapshots(self):
        with tempfile.TemporaryDirectory(dir=TEST_TMP) as tmp:
            cfg = load_config()
            recorder = EvidenceRecorder(tmp, cfg, lambda message: None)
            try:
                old = recorder.rolling/"old.avi"
                recent = recorder.rolling/"recent.avi"
                photo = recorder.snapshots/"important.jpg"
                for path in (old, recent, photo):
                    path.write_bytes(b"test artifact")
                before = time.time()-2*86400
                os.utime(old, (before, before))
                recorder._clean()
                self.assertFalse(old.exists())
                self.assertTrue(recent.exists())
                self.assertTrue(photo.exists())
            finally:
                recorder.close()

    def test_no_camera_retains_event_without_fabricating_evidence(self):
        with tempfile.TemporaryDirectory(dir=TEST_TMP) as tmp:
            messages = queue.Queue()
            recorder = EvidenceRecorder(tmp, load_config(), messages.put)
            try:
                recorder.trigger(1, "U")
                answer = messages.get(timeout=2)
                self.assertEqual(answer["type"], "evidence")
                self.assertEqual(answer["paths"], [])
                self.assertTrue(answer["missing_camera"])
            finally:
                recorder.close()


if __name__ == "__main__":
    unittest.main()
