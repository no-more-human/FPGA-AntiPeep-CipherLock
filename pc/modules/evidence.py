import queue
import shutil
import threading
import time
import uuid
from datetime import datetime, timezone, timedelta
from pathlib import Path

import cv2

TZ = timezone(timedelta(hours=8))


class EvidenceRecorder:
    """One disk writer, bounded frame memory, segmented optional continuous recording."""

    def __init__(self, directory, config, emit):
        self.root = Path(directory)
        self.snapshots = self.root / "evidence"
        self.rolling = self.root / "recordings"
        self.snapshots.mkdir(parents=True, exist_ok=True)
        self.rolling.mkdir(parents=True, exist_ok=True)
        self.config, self.emit = config, emit
        self.jobs = queue.Queue(maxsize=64)
        self.lock = threading.Lock()
        self.frame = None
        self.frame_at = 0.0
        self.stop_event = threading.Event()
        self.writer = None
        self.clip_path = None
        self.started = 0.0
        self.record_until = 0.0
        self.record_events = {}
        self.clip_events = set()
        self.last_cleanup = 0.0
        self.last_warning = 0.0
        self.bursts = []
        self.thread = threading.Thread(target=self._run, name="evidence-writer", daemon=True)
        self.thread.start()

    def submit(self, frame, captured_at=None):
        with self.lock:
            self.frame = frame
            self.frame_at = captured_at if captured_at is not None else time.monotonic()

    def trigger(self, event_id, code):
        try:
            self.jobs.put_nowait((event_id, code))
            return True
        except queue.Full:
            self.emit({"type": "evidence_error", "detail": "取证任务队列已满，事件日志已保留"})
            return False

    @staticmethod
    def name(prefix, suffix):
        stamp = datetime.now(TZ).strftime("%Y%m%d_%H%M%S_%f")
        return f"{stamp}_{prefix}_{uuid.uuid4().hex[:6]}{suffix}"

    def _snapshot(self, frame):
        path = self.snapshots / self.name("capture", ".jpg")
        ok, buffer = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 92])
        if not ok:
            raise OSError("JPEG 编码失败")
        buffer.tofile(path)
        return str(path)

    def _close_writer(self):
        if self.writer:
            self.writer.release()
            for event_id in self.clip_events:
                self.emit({"type": "evidence", "id": event_id, "paths": [str(self.clip_path)]})
        self.writer, self.clip_path = None, None
        self.clip_events = set()

    def _clean(self):
        now = time.time()
        cutoff = now-self.config["record_retention_days"]*86400
        limit = self.config["record_max_gb"]*1024**3
        files = sorted((p for p in self.rolling.glob("*.avi") if p != self.clip_path),
                       key=lambda p: p.stat().st_mtime)
        total = sum(p.stat().st_size for p in files)
        if self.clip_path and self.clip_path.exists():
            total += self.clip_path.stat().st_size
        for path in files:
            size, modified = path.stat().st_size, path.stat().st_mtime
            if modified < cutoff or total > limit:
                path.unlink()
                total -= size
        # This quota covers rolling recordings only. Evidence is retained separately.
        if shutil.disk_usage(self.root).free < 256*1024**2:
            raise OSError("剩余磁盘空间不足 256 MiB，已暂停录像")
        if total >= limit:
            raise OSError("录像配额已满，已暂停当前分段")

    def _run(self):
        interval = 1/self.config["record_fps"]
        try:
            while not self.stop_event.is_set():
                began = time.monotonic()
                try:
                    with self.lock:
                        frame, captured_at = self.frame, self.frame_at
                    if frame is not None and began-captured_at > 2:
                        frame = None
                    while True:
                        try:
                            event_id, code = self.jobs.get_nowait()
                        except queue.Empty:
                            break
                        paths = []
                        if frame is not None:
                            paths.append(self._snapshot(frame))
                        if code in ("D", "C", "L", "A"):
                            self.record_until = max(self.record_until, began+self.config["event_record_seconds"])
                            self.record_events[event_id] = began+self.config["event_record_seconds"]
                            if self.writer:
                                self.clip_events.add(event_id)
                        if code == "L" and frame is not None:
                            self.bursts.append([event_id, paths, 4, began+.3])
                        else:
                            self.emit({"type": "evidence", "id": event_id, "paths": paths,
                                       "missing_camera": frame is None})
                        if frame is None:
                            self.emit({"type": "evidence_error", "detail": "无可用摄像头画面，事件已记录但未抓拍"})
                    for burst in self.bursts[:]:
                        if began >= burst[3]:
                            if frame is not None:
                                burst[1].append(self._snapshot(frame))
                            burst[2] -= 1
                            burst[3] = began+.3
                            if not burst[2]:
                                self.emit({"type": "evidence", "id": burst[0], "paths": burst[1]})
                                self.bursts.remove(burst)
                    self.record_events = {key: end for key, end in self.record_events.items() if end > began}
                    active = self.config["continuous_recording"] or began < self.record_until
                    if frame is None or not active:
                        self._close_writer()
                    else:
                        if began-self.last_cleanup >= 5:
                            self._clean()
                            self.last_cleanup = began
                        if self.writer and (began-self.started >= self.config["segment_seconds"] or
                                            self.writer_size != (frame.shape[1], frame.shape[0])):
                            self._close_writer()
                        if self.writer is None:
                            self.clip_path = self.rolling / self.name("segment", ".avi")
                            self.writer_size = (frame.shape[1], frame.shape[0])
                            self.writer = cv2.VideoWriter(str(self.clip_path), cv2.VideoWriter_fourcc(*"MJPG"),
                                                          self.config["record_fps"], self.writer_size)
                            if not self.writer.isOpened():
                                self._close_writer()
                                raise OSError("录像编码器无法打开 MJPG/AVI 文件")
                            self.started = began
                            self.clip_events = set(self.record_events)
                            # Do not expose event-specific file names in on-site UI.
                            self.emit({"type": "record_segment", "path": str(self.clip_path)})
                        self.writer.write(frame)
                except (OSError, cv2.error) as error:
                    self._close_writer()
                    if began-self.last_warning >= 10:
                        self.emit({"type": "evidence_error", "detail": str(error)})
                        self.last_warning = began
                self.stop_event.wait(max(.005, interval-(time.monotonic()-began)))
        finally:
            self._close_writer()

    def close(self):
        self.stop_event.set()
        self.thread.join(timeout=3)
