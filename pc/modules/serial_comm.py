import threading
import time
import serial
from serial.tools import list_ports
from .protocol import StreamParser, encode


def available_ports():
    return [(port.device, port.description) for port in list_ports.comports()]


class SerialLink:
    """One reader, serialized writes, finite timeouts, no command replay."""

    def __init__(self, port, baudrate, emit, factory=serial.Serial):
        self.port, self.baudrate, self.emit = port, baudrate, emit
        self.factory = factory
        self.stop_event = threading.Event()
        self.mutex = threading.Lock()
        self.handle = None
        self.connected = False
        self.thread = threading.Thread(target=self._run, name="uart-reader", daemon=True)

    def start(self):
        self.thread.start()

    def _run(self):
        previous_error = None
        while not self.stop_event.is_set():
            handle = None
            try:
                handle = self.factory(port=self.port, baudrate=self.baudrate, bytesize=8,
                                      parity="N", stopbits=1, timeout=0.1, write_timeout=0.3)
                with self.mutex:
                    self.handle = handle
                    self.connected = True
                self.emit({"type": "link", "connected": True, "detail": self.port})
                previous_error = None
                parser = StreamParser()
                while not self.stop_event.is_set():
                    data = handle.read(min(max(handle.in_waiting, 1), 4096))
                    if data:
                        for message in parser.feed(data):
                            self.emit(message)
            except (serial.SerialException, OSError, ValueError) as error:
                if str(error) != previous_error and not self.stop_event.is_set():
                    self.emit({"type": "link_error", "detail": str(error)})
                    previous_error = str(error)
            finally:
                with self.mutex:
                    self.connected = False
                    self.handle = None
                    if handle is not None:
                        handle.close()
                self.emit({"type": "link", "connected": False, "detail": self.port})
            self.stop_event.wait(2.0)

    def send(self, command):
        if command not in ("S", "P", "R"):
            raise ValueError("不支持的单字节命令")
        return self._write(command.encode("ascii"))

    def request(self, message):
        return self._write(encode(message))

    def _write(self, data):
        with self.mutex:
            if not self.connected or self.handle is None:
                return False
            try:
                return self.handle.write(data) == len(data)
            except (serial.SerialException, OSError):
                self.connected = False
                self.handle.close()
                return False

    def close(self):
        self.stop_event.set()
        self.thread.join(timeout=2)
