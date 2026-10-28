import json
import re

EVENTS = {
    "U": "正常开锁", "D": "紧急胁迫报警", "L": "连续试错锁定",
    "A": "门未关严报警", "E": "密码错误", "K": "锁闭",
    "T": "试错锁定解除", "C": "手动紧急报警",
}
MAX_FRAME = 1024


class StreamParser:
    """Single-byte legacy protocol and optional @JSON newline extension."""

    def __init__(self):
        self.buffer = None
        self.overflow = False

    def feed(self, data):
        result = []
        for byte in data:
            if self.buffer is not None:
                if byte == 10:
                    if not self.overflow:
                        try:
                            obj = json.loads(self.buffer.decode("utf-8"))
                            if isinstance(obj, dict):
                                result.append(obj)
                        except (ValueError, UnicodeError):
                            pass
                    self.buffer, self.overflow = None, False
                elif len(self.buffer) < MAX_FRAME:
                    self.buffer.append(byte)
                else:
                    self.overflow = True
            elif byte == ord("@"):
                self.buffer = bytearray()
            elif chr(byte) in EVENTS:
                result.append({"type": "event", "code": chr(byte)})
        return result


def encode(message):
    raw = json.dumps(message, ensure_ascii=True, separators=(",", ":")).encode("ascii")
    if len(raw) > MAX_FRAME:
        raise ValueError("协议帧过长")
    return b"@" + raw + b"\n"


def validate_password(password):
    if not isinstance(password, str) or not re.fullmatch(r"[0-9]{6}", password):
        raise ValueError("密码必须为 6 位 ASCII 数字")


def validate_pair(normal, duress):
    validate_password(normal)
    validate_password(duress)
    if normal == duress:
        raise ValueError("常规密码与胁迫密码不能相同")
