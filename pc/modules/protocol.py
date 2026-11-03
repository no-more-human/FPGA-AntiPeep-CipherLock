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
HEX8_RE = re.compile(r"^[0-9A-Fa-f]{8}$")
PRESENT_SBOX = (
    0xC, 0x5, 0x6, 0xB, 0x9, 0x0, 0xA, 0xD,
    0x3, 0xE, 0xF, 0x8, 0x4, 0x7, 0x1, 0x2,
)


def calc_auth_mac(nonce):
    """2-round PRESENT S-Box + ARX MAC matching rtl/uart_mailman.v calc_auth_mac."""
    n = int(nonce) & 0xFF
    r1 = (PRESENT_SBOX[((n >> 4) & 0xF) ^ 0x5] << 4) | PRESENT_SBOX[(n & 0xF) ^ 0xA]
    r2 = (((r1 << 3) & 0xFF) | (r1 >> 5))
    r2 = (r2 + 0x7E) & 0xFF
    mac = ((PRESENT_SBOX[(r2 >> 4) & 0xF] << 4) | PRESENT_SBOX[r2 & 0xF]) ^ 0xC3
    return mac & 0xFF


def parse_oled_hex(hex_str):
    """Parse 6-char hex payload from @O<6-hex> frame into standard oled dict."""
    if not isinstance(hex_str, str) or not HEX6_RE.fullmatch(hex_str):
        raise ValueError("Invalid @O hex payload")
    b0 = int(hex_str[0:2], 16)
    b1 = int(hex_str[2:4], 16)
    b2 = int(hex_str[4:6], 16)
    rec_active = (b0 >> 4) & 0x01
    hi_bits = (b1 >> 5) & 0x07
    rec_len = hi_bits if rec_active else 0
    countdown = (b2 & 0x3F) | (0 if rec_active else (hi_bits << 6))
    return {
        "type": "oled",
        "state_code": b0 & 0x0F,
        "pwd_len": b1 & 0x1F,
        "err_count": (b2 >> 6) & 0x03,
        "countdown": countdown,
        "peep_hang": (b0 >> 7) & 0x01,
        "rec_active": rec_active,
        "rec_len": rec_len,
        "rec_locked": (b0 >> 5) & 0x01,
        "door_alert": (b0 >> 6) & 0x01,
    }


def parse_hw_audit_hex(hex_str):
    """Parse 8-char hex payload from @H<8-hex> on-chip BRAM blackbox audit frame."""
    if not isinstance(hex_str, str) or not HEX8_RE.fullmatch(hex_str):
        raise ValueError("Invalid @H hex payload")
    word = int(hex_str, 16)
    ts_sec = (word >> 20) & 0xFFF
    chain_mac = (word >> 12) & 0xFF
    state_code = (word >> 8) & 0x0F
    event_byte = word & 0xFF
    event_char = chr(event_byte) if 32 <= event_byte <= 126 else f"0x{event_byte:02X}"
    return {
        "type": "hw_audit",
        "raw": hex_str.upper(),
        "timestamp_s": ts_sec,
        "chain_mac": chain_mac,
        "state_code": state_code,
        "event_code": event_char,
    }


class StreamParser:
    """Single-byte legacy protocol, @O<6-hex> OLED snapshot, @H<8-hex> BRAM audit, and @JSON newline extension."""

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
                            elif text.startswith("H") and len(text) == 9 and HEX8_RE.fullmatch(text[1:]):
                                result.append(parse_hw_audit_hex(text[1:]))
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
