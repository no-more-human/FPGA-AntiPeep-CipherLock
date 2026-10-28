import threading
import time
from pathlib import Path

import cv2

from .face_auth import FaceAuth
from .policy import VisionPolicy
from .config import resolve_path


class LatestCamera:
    """Capture independently and retain one latest frame, avoiding queued latency."""

    def __init__(self, source, width, height):
        self.source, self.width, self.height = source, width, height
        self.lock = threading.Lock()
        self.frame = None
        self.captured_at = 0.0
        self.sequence = 0
        self.error = "摄像头初始化中"
        self.stop_event = threading.Event()
        self.thread = threading.Thread(target=self._run, name="camera", daemon=True)
        self.thread.start()

    def _run(self):
        while not self.stop_event.is_set():
            cap = cv2.VideoCapture(self.source)
            try:
                if not cap.isOpened():
                    raise RuntimeError(f"无法打开摄像头 {self.source}")
                cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.width)
                cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.height)
                cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
                while not self.stop_event.is_set():
                    ok, frame = cap.read()
                    if not ok:
                        raise RuntimeError("摄像头读取失败，正在重试")
                    with self.lock:
                        self.frame = frame
                        self.captured_at = time.monotonic()
                        self.sequence += 1
                        self.error = None
            except (RuntimeError, cv2.error) as error:
                with self.lock:
                    self.frame = None
                    self.error = str(error)
            finally:
                cap.release()
            self.stop_event.wait(2)

    def latest(self):
        with self.lock:
            return self.frame, self.captured_at, self.sequence, self.error

    def close(self):
        self.stop_event.set()
        self.thread.join(timeout=2)


class VisionEngine:
    def __init__(self, config):
        model = resolve_path(config["model"])
        if not model.is_file():
            raise FileNotFoundError(f"缺少本地 YOLO 模型: {model}，请先运行 tools/download_model.py")
        import torch
        from ultralytics import YOLO
        torch.set_num_threads(config["cpu_threads"])
        self.model = YOLO(str(model))
        self.face_auth = FaceAuth(threshold=config["face_threshold"])
        self.config = config
        self.policy = VisionPolicy(config["peep_enter_seconds"], config["peep_exit_seconds"],
                                   config["face_stable_seconds"])

    def analyze(self, frame, captured_at=None):
        start = time.monotonic()
        height, width = frame.shape[:2]
        left, top, right, bottom = self.config["roi"]
        x1, y1, x2, y2 = int(left * width), int(top * height), int(right * width), int(bottom * height)
        crop = frame[y1:y2, x1:x2]
        if not crop.size:
            raise ValueError("ROI 在当前画面内为空")
        results = self.model.predict(crop, classes=[0], conf=self.config["confidence"],
                                     imgsz=self.config["image_size"], verbose=False)
        people_count = len(results[0].boxes)
        # Recognition always uses the original image, before any detection annotation.
        faces = self.face_auth.analyze_faces(crop)
        decision = self.policy.update(start, people_count, faces)
        annotated = frame.copy()
        for box in results[0].boxes.xyxy.cpu().numpy():
            a, b, c, d = [int(v) for v in box]
            cv2.rectangle(annotated, (a+x1, b+y1), (c+x1, d+y1), (220, 160, 70), 2)
        for face in faces:
            x, y, w, h = face["bbox"]
            color = (80, 210, 100) if face["authorized"] else (80, 90, 240)
            cv2.rectangle(annotated, (x+x1, y+y1), (x+w+x1, y+h+y1), color, 2)
            label = face["name"] if str(face["name"]).isascii() else "AUTHORIZED"
            if face["confidence"] is not None:
                label += f" d={face['confidence']:.1f}"
            cv2.putText(annotated, label, (x+x1, max(24, y+y1-8)),
                        cv2.FONT_HERSHEY_SIMPLEX, .6, color, 2)
        cv2.rectangle(annotated, (x1, y1), (x2-1, y2-1), (140, 140, 140), 1)
        elapsed = time.monotonic()-start
        return {
            "type": "vision", "frame": annotated, "raw": frame,
            "people": people_count, "faces": len(faces), "decision": decision,
            "captured_at": captured_at if captured_at is not None else start,
            "analyzed_at": time.monotonic(), "ms": elapsed*1000,
            "trained": self.face_auth.trained,
        }


class VisionWorker:
    def __init__(self, config, emit, recorder):
        self.config, self.emit, self.recorder = config, emit, recorder
        self.lock = threading.Lock()
        self.result = None
        self.stop_event = threading.Event()
        self.camera = None
        self.thread = threading.Thread(target=self._run, name="vision", daemon=True)

    def start(self):
        self.thread.start()

    def _run(self):
        try:
            engine = VisionEngine(self.config)
            if self.stop_event.is_set():
                return
            self.camera = LatestCamera(self.config["camera"], self.config["width"], self.config["height"])
            previous_seq, previous_error = -1, None
            while not self.stop_event.is_set():
                frame, captured_at, sequence, error = self.camera.latest()
                if frame is None or time.monotonic()-captured_at > 1.0:
                    with self.lock:
                        self.result = None
                    if error != previous_error:
                        self.emit({"type": "vision_error", "detail": error or "摄像头画面超时"})
                        previous_error = error
                    self.stop_event.wait(.05)
                    continue
                previous_error = None
                if sequence == previous_seq:
                    self.stop_event.wait(.01)
                    continue
                previous_seq = sequence
                result = engine.analyze(frame, captured_at)
                # Only observed transitions enter the event queue; frames use a latest slot.
                if result["decision"].changed:
                    self.emit({"type": "peep", "active": result["decision"].peeping})
                self.recorder.submit(frame, captured_at)
                with self.lock:
                    self.result = result
        except Exception as error:
            self.emit({"type": "vision_error", "detail": f"{type(error).__name__}: {error}"})
        finally:
            if self.camera:
                self.camera.close()

    def latest(self):
        with self.lock:
            return self.result

    def close(self):
        self.stop_event.set()
        self.thread.join(timeout=3)
