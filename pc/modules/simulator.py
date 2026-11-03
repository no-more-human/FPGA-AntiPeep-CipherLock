"""PC demonstration only; mirrors key FPGA RTL security behaviors."""
import math
import time
from .protocol import validate_pair, validate_password


class SimulatedFPGA:
    LOCKOUT_TIERS = (60, 120, 300)

    def __init__(self, normal="123456", duress="654321", clock=time.monotonic):
        validate_pair(normal, duress)
        self.normal, self.duress = normal, duress
        self.clock = clock
        self.failures = 0
        self.lockout_tier = 0
        self.lock_until = self.open_until = 0.0
        self.err_until = self.op_done_until = 0.0
        self.peeping = False
        self.door_alert = False
        self.pwd_len = 0

    @staticmethod
    def event(code):
        return {"type": "event", "code": code}

    def set_input_len(self, length):
        if self.lock_until or self.peeping:
            self.pwd_len = 0
        else:
            self.pwd_len = max(0, min(16, int(length)))

    def oled_snapshot(self):
        now = self.clock()
        countdown = 0
        if self.lock_until and now < self.lock_until:
            state_code = 4
            countdown = max(1, min(300, int(math.ceil(self.lock_until - now))))
        elif self.open_until and now < self.open_until:
            state_code = 2
        elif self.op_done_until and now < self.op_done_until:
            state_code = 10
        elif self.err_until and now < self.err_until:
            state_code = 3
        elif self.pwd_len > 0:
            state_code = 1
        else:
            state_code = 0
        return {
            "type": "oled",
            "state_code": state_code,
            "pwd_len": self.pwd_len if state_code == 1 else 0,
            "err_count": min(3, self.failures),
            "countdown": countdown,
            "peep_hang": 1 if self.peeping else 0,
            "rec_active": 0,
            "rec_len": 0,
            "rec_locked": 0,
            "door_alert": 1 if self.door_alert else 0,
        }

    def tick(self):
        now, events = self.clock(), []
        if self.lock_until and now >= self.lock_until:
            self.lock_until = 0
            self.failures = 0
            events.append(self.event("T"))
        if self.open_until and now >= self.open_until:
            self.open_until = 0
            events.append(self.event("K"))
        if self.err_until and now >= self.err_until:
            self.err_until = 0
        if self.op_done_until and now >= self.op_done_until:
            self.op_done_until = 0
        return events

    def submit(self, digits):
        events = self.tick()
        if not isinstance(digits, str) or not 6 <= len(digits) <= 16 or not digits.isascii() or not digits.isdecimal():
            raise ValueError("输入应为 6~16 位数字；超长输入整串拒绝")
        self.pwd_len = 0
        # Duress emergency green-channel: matches rtl/safe_fsm.v where match_duress
        # overrides peep_hang and S_LOCKED to ensure life safety under coercion.
        if self.duress in digits:
            self.lock_until = 0.0
            self.failures = 0
            self.open_until = self.clock() + 3
            return events + [self.event("D"), self.event("U")]
        if self.lock_until or self.peeping:
            return events
        if self.normal in digits:
            self.failures = 0
            self.lockout_tier = 0
            self.open_until = self.clock() + 3
            return events + [self.event("U")]
        self.failures += 1
        if self.failures >= 3:
            duration = self.LOCKOUT_TIERS[min(self.lockout_tier, len(self.LOCKOUT_TIERS) - 1)]
            self.lockout_tier = min(self.lockout_tier + 1, len(self.LOCKOUT_TIERS) - 1)
            self.lock_until = self.clock() + duration
            return events + [self.event("L")]
        self.err_until = self.clock() + 1.5
        return events

    def command(self, command):
        events = self.tick()
        if command == "P":
            self.peeping = True
        elif command == "S":
            self.peeping = False
        elif command == "R" and not self.lock_until and not self.peeping:
            self.open_until = self.clock() + 3
            events.append(self.event("U"))
        elif command == "H":
            events.append({
                "type": "hw_audit",
                "raw": "001A5055",
                "timestamp_s": 1,
                "chain_mac": 0xA5,
                "state_code": 0,
                "event_code": "U",
            })
        return events

    def request(self, msg):
        answer = {"type": "ack", "id": msg.get("id"), "ok": False}
        try:
            if self.lock_until or self.peeping:
                raise ValueError("当前状态不允许修改密码")
            if msg.get("op") != "password_change":
                raise ValueError("未知操作")
            if msg.get("old") != self.normal:
                self.failures += 1
                if self.failures >= 3:
                    duration = self.LOCKOUT_TIERS[min(self.lockout_tier, len(self.LOCKOUT_TIERS) - 1)]
                    self.lockout_tier = min(self.lockout_tier + 1, len(self.LOCKOUT_TIERS) - 1)
                    self.lock_until = self.clock() + duration
                    return [self.event("L"), {**answer, "reason": "身份验证失败，已锁定"}]
                self.err_until = self.clock() + 1.5
                raise ValueError("身份验证失败")
            kind, new = msg.get("kind"), msg.get("new")
            validate_password(new)
            if kind == "normal":
                validate_pair(new, self.duress)
                self.normal = new
            elif kind == "duress":
                validate_pair(self.normal, new)
                self.duress = new
            else:
                raise ValueError("未知密码类型")
            self.failures = 0
            self.lockout_tier = 0
            self.op_done_until = self.clock() + 2.0
            answer["ok"] = True
        except ValueError as error:
            answer["reason"] = str(error)
        return [answer]
