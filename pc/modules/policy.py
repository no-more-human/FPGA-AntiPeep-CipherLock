from dataclasses import dataclass


@dataclass(frozen=True)
class Decision:
    peeping: bool
    changed: bool
    face_ready: bool
    identity: str | None


class VisionPolicy:
    """Time based hysteresis. Recognition does not provide liveness detection."""

    def __init__(self, enter=1.5, exit=2.0, face_stable=2.0):
        self.enter, self.exit, self.face_stable = enter, exit, face_stable
        self.peeping = False
        self.candidate_since = None
        self.identity = None
        self.identity_since = None
        self.last_at = None

    def update(self, now, people_count, faces):
        if self.last_at is not None and now - self.last_at > 1.0:
            self.candidate_since = None
            self.identity = self.identity_since = None
        self.last_at = now
        multiple = max(people_count, len(faces)) > 1
        changed = False
        if multiple != self.peeping:
            if self.candidate_since is None:
                self.candidate_since = now
            delay = self.enter if multiple else self.exit
            if now - self.candidate_since >= delay:
                self.peeping, changed = multiple, True
                self.candidate_since = None
        else:
            self.candidate_since = None
        identity = None
        if people_count == 1 and len(faces) == 1 and faces[0]["authorized"] and not multiple and not self.peeping:
            identity = faces[0]["name"]
        if identity != self.identity:
            self.identity, self.identity_since = identity, now if identity else None
        ready = identity is not None and now - self.identity_since >= self.face_stable
        return Decision(self.peeping, changed, ready, identity)


class SafeState:
    def __init__(self):
        self.lock = "未知（等待下位机状态）"
        self.lockout = False

    def apply(self, code):
        if code in ("U", "D"):
            self.lock = "已开锁（下位机回报）"
        elif code == "L":
            self.lockout = True
            self.lock = "试错锁定（等待解除回报）"
        elif code == "K":
            self.lock = "已锁闭（下位机回报）"
        elif code == "T":
            self.lockout = False
            self.lock = "已锁闭（试错锁定解除）"
        elif code == "A":
            self.lock = "门未关严（下位机回报）"

    def disconnected(self):
        self.lock = "未知（通信中断）"
        self.lockout = False
