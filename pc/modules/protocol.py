import json
import re

EVENTS = {
    "U": "正常开锁", "D": "紧急胁迫报警", "L": "连续试错锁定",
    "A": "门未关严报警", "E": "密码错误", "K": "锁闭",
    "T": "试错锁定解除", "C": "手动紧急报警",
    "X": "非法撬门报警",
}
MAX_FRAME = 1024
HEX6_RE = re.compile(r"^[0-9A-Fa-f]{6}$")


def parse_oled_hex(hex_str):
    """Parse 6-char hex payload from @O<6-hex> frame into standard oled dict."""
    if not isinstance(hex_str, str) or not HEX6_RE.fullmatch(hex_str):
        raise ValueError("Invalid @O hex payload")
    b0 = int(hex_str[0:2], 16)
    b1 = int(hex_str[2:4], 16)
    b2 = int(hex_str[4:6], 16)
    return {
        "type": "oled",
        "state_code": b0 & 0x0F,
        "pwd_len": b1 & 0x1F,
        "err_count": (b2 >> 6) & 0x03,
        "countdown": b2 & 0x3F,
        "peep_hang": (b0 >> 7) & 0x01,
        "rec_active": (b0 >> 4) & 0x01,
        "rec_len": (b1 >> 5) & 0x07,
        "rec_locked": (b0 >> 5) & 0x01,
        "door_alert": (b0 >> 6) & 0x01,
    }


class StreamParser:
    """Single-byte legacy protocol, @O<6-hex> OLED snapshot, and @JSON newline extension."""

    def __init__(self):
        self.buffer = None
        self.overflow = False
        self.expect_challenge = False

    def feed(self, data):
        result = []
        for byte in data:
            if self.expect_challenge:
                self.expect_challenge = False
                result.append({"type": "challenge", "nonce": byte})
            elif self.buffer is not None:
                if byte == 10:
                    if not self.overflow:
                        try:
                            text = self.buffer.decode("utf-8")
                            if text.startswith("O") and len(text) == 7 and HEX6_RE.fullmatch(text[1:]):
                                result.append(parse_oled_hex(text[1:]))
                            else:
                                obj = json.loads(text)
                                if isinstance(obj, dict):
                                    result.append(obj)
                        except (ValueError, UnicodeError):
                            pass
                    self.buffer, self.overflow = None, False
                elif len(self.buffer) < MAX_FRAME:
                    self.buffer.append(byte)
                else:
                    self.overflow = True
            elif byte == ord("?"):
                self.expect_challenge = True
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
