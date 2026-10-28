import csv
import json
import sqlite3
import threading
import time
from datetime import datetime, timezone, timedelta
from pathlib import Path

TZ = timezone(timedelta(hours=8))


def timestamp():
    return datetime.now(TZ).isoformat(timespec="milliseconds")


class AuditStore:
    def __init__(self, directory):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.path = self.directory / "events.sqlite3"
        self.lock = threading.Lock()
        self.db = sqlite3.connect(self.path, check_same_thread=False)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA busy_timeout=3000")
        self.db.execute("""CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY, time TEXT NOT NULL, epoch REAL NOT NULL,
            code TEXT NOT NULL, detail TEXT NOT NULL, sensitive INTEGER NOT NULL,
            evidence TEXT)""")
        self.db.commit()

    def add(self, code, detail="", sensitive=False, evidence=None):
        with self.lock:
            cursor = self.db.execute(
                "INSERT INTO events(time,epoch,code,detail,sensitive,evidence) VALUES(?,?,?,?,?,?)",
                (timestamp(), time.time(), code, detail, int(sensitive),
                 json.dumps(evidence, ensure_ascii=False) if evidence else None))
            self.db.commit()
            return cursor.lastrowid

    def attach(self, event_id, evidence):
        with self.lock:
            row = self.db.execute("SELECT evidence FROM events WHERE id=?", (event_id,)).fetchone()
            old = json.loads(row[0]) if row and row[0] else []
            combined = list(dict.fromkeys(old + evidence))
            self.db.execute("UPDATE events SET evidence=? WHERE id=?",
                            (json.dumps(combined, ensure_ascii=False), event_id))
            self.db.commit()

    def recent(self, limit=100, include_sensitive=False):
        with self.lock:
            return self.db.execute(
                "SELECT id,time,code,detail,evidence FROM events " +
                ("" if include_sensitive else "WHERE sensitive=0 ") +
                "ORDER BY id DESC LIMIT ?", (limit,)).fetchall()

    def export(self, path, include_sensitive=False):
        with self.lock:
            rows = self.db.execute(
                "SELECT id,time,code,detail,evidence FROM events " +
                ("" if include_sensitive else "WHERE sensitive=0 ") +
                "ORDER BY id").fetchall()
        with Path(path).open("w", newline="", encoding="utf-8-sig") as stream:
            writer = csv.writer(stream)
            writer.writerow(["编号", "时间(UTC+8)", "事件", "说明", "证据路径"])
            writer.writerows(rows)

    def close(self):
        with self.lock:
            self.db.close()
