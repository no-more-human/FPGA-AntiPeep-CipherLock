"""PC demonstration only; this is not an implementation of the FPGA RTL."""
import time
from .protocol import validate_pair, validate_password


class SimulatedFPGA:
    def __init__(self, normal="123456", duress="654321", clock=time.monotonic):
        validate_pair(normal, duress)
        self.normal, self.duress = normal, duress
        self.clock = clock
        self.failures = 0
        self.lock_until = self.open_until = 0.0
        self.peeping = False

    @staticmethod
    def event(code):
        return {"type": "event", "code": code}

    def tick(self):
        now, events = self.clock(), []
        if self.lock_until and now >= self.lock_until:
            self.lock_until = 0
            self.failures = 0
            events.append(self.event("T"))
        if self.open_until and now >= self.open_until:
            self.open_until = 0
            events.append(self.event("K"))
        return events

    def submit(self, digits):
        events = self.tick()
        if not isinstance(digits, str) or not 6 <= len(digits) <= 16 or not digits.isascii() or not digits.isdecimal():
            raise ValueError("输入应为 6~16 位数字；超长输入整串拒绝")
        if self.duress in digits:
            self.open_until = self.clock() + 3
            return events + [self.event("D")]
        if self.lock_until or self.peeping:
            return events
        if self.normal in digits:
            self.failures = 0
            self.open_until = self.clock() + 3
            return events + [self.event("U")]
        self.failures += 1
        if self.failures >= 3:
            self.lock_until = self.clock() + 60
            return events + [self.event("E"), self.event("L")]
        return events + [self.event("E")]

    def command(self, command):
        events = self.tick()
        if command == "P":
            self.peeping = True
        elif command == "S":
            self.peeping = False
        elif command == "R" and not self.lock_until and not self.peeping:
            self.open_until = self.clock() + 3
            events.append(self.event("U"))
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
                    self.lock_until = self.clock() + 60
                    return [self.event("L"), {**answer, "reason": "身份验证失败，已锁定"}]
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
            answer["ok"] = True
        except ValueError as error:
            answer["reason"] = str(error)
        return [answer]
