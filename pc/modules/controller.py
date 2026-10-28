import time
import uuid
from collections import deque

from .policy import SafeState
from .protocol import EVENTS, validate_password
from .simulator import SimulatedFPGA
from .serial_comm import SerialLink


class Controller:
    def __init__(self, config, audit, recorder, emit, demo=False):
        self.config, self.audit, self.recorder, self.emit = config, audit, recorder, emit
        self.demo = demo
        self.sim = SimulatedFPGA() if demo else None
        self.link = None
        self.connected = demo
        self.device_seen = demo
        self.state = SafeState()
        self.peeping = False
        self.vision = None
        self.vision_paused = True
        self.needs_sync = False
        self.lines = deque(maxlen=200)
        self.alarms = deque()
        self.pending = {}
        self.last_remote = -100.0
        self.error = ""
        self.last_status = ""
        if demo:
            self.log("DEMO", "模拟演示：无物理硬件连接，密码仅存于内存")
            self.state.apply("K")

    def log(self, code, detail, sensitive=False):
        event_id = self.audit.add(code, detail, sensitive)
        if not sensitive or self.config["alarm_display"] == "security":
            self.lines.append((time.strftime("%H:%M:%S", time.localtime()), code, detail))
        return event_id

    def connect(self, port):
        self.disconnect()
        if self.demo:
            raise ValueError("演示模式不会连接物理设备，请退出后以正常模式启动")
        if not port.strip():
            raise ValueError("请先选择串口")
        self.link = SerialLink(port.strip(), self.config["baudrate"], self.emit)
        self.link.start()

    def disconnect(self):
        if self.link:
            self.link.close()
            self.link = None
        self.connected = self.demo
        self.device_seen = self.demo
        if not self.demo:
            self.state.disconnected()
        for request in self.pending.values():
            request["callback"](False, "通信中断，修改结果未知；请在实体键盘核验")
        self.pending.clear()

    def send(self, command):
        if self.demo:
            for event in self.sim.command(command):
                self.emit(event)
            success = True
        else:
            success = bool(self.link and self.link.send(command))
        if success:
            self.log("TX", f"已发送 {command}，等待下位机执行")
        return success

    def update_vision(self, result):
        self.vision = result
        if result is None:
            if not self.vision_paused and self.connected:
                self.send("P")
            self.vision_paused = True
        else:
            if self.vision_paused or self.needs_sync:
                self.peeping = result["decision"].peeping
                if self.connected:
                    self.send("P" if self.peeping else "S")
            self.vision_paused = False
            self.needs_sync = False

    def face_unlock(self, now=None):
        now = time.monotonic() if now is None else now
        v = self.vision
        if not self.connected:
            raise ValueError("尚未连接串口")
        if not v or now-v["captured_at"] > 1 or now-v["analyzed_at"] > 1:
            raise ValueError("没有新鲜的识别结果，请等待摄像头恢复")
        if not v["decision"].face_ready or v["decision"].peeping or self.peeping:
            raise ValueError("需单人白名单人脸连续稳定识别，且没有防窥告警")
        if self.state.lockout:
            raise ValueError("下位机处于试错锁定；需等待解除状态 T")
        if now-self.last_remote < 5:
            raise ValueError("开锁指令冷却中，请稍后")
        if not self.send("R"):
            raise ValueError("串口发送失败")
        self.last_remote = now

    def change_password(self, kind, old, new, confirm, callback):
        if self.pending:
            raise ValueError("已有改密请求处理中，请等待回执")
        if not (self.demo or self.config["extended_protocol"]):
            raise ValueError("当前 FPGA 未启用改密扩展协议，请通过实体键盘修改")
        if not self.connected:
            raise ValueError("串口未连接")
        if kind not in ("normal", "duress"):
            raise ValueError("未知密码类型")
        validate_password(old)
        validate_password(new)
        if new != confirm:
            raise ValueError("两次新密码不一致")
        request_id = uuid.uuid4().hex[:12]
        message = {"type": "request", "id": request_id, "op": "password_change",
                   "kind": kind, "old": old, "new": new}
        # Do not store passwords in pending state or audit logs.
        self.pending[request_id] = {"at": time.monotonic(), "kind": kind, "callback": callback}
        if self.demo:
            for event in self.sim.request(message):
                self.emit(event)
            sent = True
        else:
            sent = self.link.request(message) if self.link else False
        if not sent:
            self.pending.pop(request_id)
            raise ValueError("发送失败；请在实体键盘核验密码状态")
        self.log("CONFIG_REQUEST", f"请求修改 {kind} 密码，等待回执")

    def tick(self):
        if self.demo:
            for event in self.sim.tick():
                self.emit(event)
        now = time.monotonic()
        for request_id, request in list(self.pending.items()):
            if now-request["at"] >= 5:
                self.pending.pop(request_id)
                self.log("CONFIG_TIMEOUT", "改密超时，结果未知，需实体键盘核验")
                request["callback"](False, "未收到回执，结果未知；请在实体键盘核验后重试")

    def handle(self, msg):
        kind = msg.get("type")
        if kind == "link":
            connected = bool(msg.get("connected"))
            if self.connected != connected:
                self.connected = connected
                self.device_seen = False
                self.log("LINK", "串口已打开，等待设备回报" if connected else "串口断开，正在重连")
                if not connected:
                    self.state.disconnected()
                    for request in self.pending.values():
                        request["callback"](False, "通信中断，修改结果未知；请在实体键盘核验")
                    self.pending.clear()
                else:
                    v = self.vision
                    fresh = v and time.monotonic()-v["captured_at"] < 1
                    self.send("P" if not fresh or v["decision"].peeping else "S")
                    self.needs_sync = True
        elif kind in ("link_error", "vision_error", "evidence_error"):
            detail = msg.get("detail") or "视觉暂不可用"
            if kind == "vision_error":
                self.vision = None
            if kind != "evidence_error":
                self.error = detail
            # On-site display never exposes event-specific recorder errors.
            if kind != "evidence_error" or self.config["alarm_display"] == "security":
                self.log(kind.upper(), detail)
            else:
                self.audit.add("EVIDENCE_ERROR", detail, sensitive=True)
        elif kind == "peep":
            self.peeping = bool(msg["active"])
            self.log("PEEP" if self.peeping else "SAFE",
                     "检测到多人，请注意遮挡密码" if self.peeping else "视野恢复，防窥告警解除")
            self.send("P" if self.peeping else "S")
        elif kind == "event" and msg.get("code") in EVENTS:
            code = msg["code"]
            self.device_seen = True
            self.state.apply(code)
            sensitive = code in ("D", "C")
            event_id = self.log(code, EVENTS[code], sensitive=sensitive)
            if code == "D" and self.config["alarm_display"] == "silent":
                # Same visible behavior as U, without a sensitive audit duplicate.
                self.lines.append((time.strftime("%H:%M:%S"), "U", EVENTS["U"]))
            self.recorder.trigger(event_id, code)
            if sensitive and self.config["alarm_display"] == "security":
                self.alarms.append(EVENTS[code])
        elif kind == "ack":
            request_id = msg.get("id")
            if not isinstance(request_id, str):
                return
            request = self.pending.pop(request_id, None)
            if request:
                ok = msg.get("ok") is True
                self.log("CONFIG_OK" if ok else "CONFIG_REJECT",
                         f"{request['kind']} 密码修改" + ("已获下位机确认" if ok else "被下位机拒绝"))
                request["callback"](ok, "修改已获下位机确认" if ok else "下位机拒绝：请核对旧密码、状态及密码是否重复")
            else:
                self.log("LATE_ACK", "收到过期或未知请求回执，需实体核验")
        elif kind == "evidence":
            self.audit.attach(msg["id"], msg["paths"])
        elif kind == "record_segment":
            self.audit.add("VIDEO", msg["path"], sensitive=True)

    def close(self):
        self.disconnect()
