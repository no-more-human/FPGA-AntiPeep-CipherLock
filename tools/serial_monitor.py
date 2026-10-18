#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
==============================================================================
智能保险箱 工业级串口监控与调试治具 (Serial Monitor & Diagnostic Tool)
==============================================================================
适用阶段: Day 1 - 串口通信联调与环境验证
设计规范: 符合 plan.md 1.2 工业级 UART 串口双向通信协议标准
通信参数: 115200 bps, 8-N-1 (8数据位, 无校验, 1停止位)

支持功能:
  1. 自动扫描可用 COM 端口列表，高亮识别常见 USB-TTL 芯片 (CH340/CP2102/FTDI)
  2. 毫秒级时间戳双向收发日志记录
  3. 协议语义实时解码 (FPGA -> PC: 'U', 'L', 'D', 'A')
  4. 交互式快捷按键下发 (PC -> FPGA: 'S', 'P', 'R')
  5. 内置 --mock 模拟模式，脱离物理硬件即可验证双向交互时序
==============================================================================
"""

import sys
import time
import threading
import argparse
from datetime import datetime

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    serial = None

# ANSI 颜色控制
class Colors:
    HEADER    = '\033[95m'
    OKBLUE    = '\033[94m'
    OKCYAN    = '\033[96m'
    OKGREEN   = '\033[92m'
    WARNING   = '\033[93m'
    FAIL      = '\033[91m'
    ENDC      = '\033[0m'
    BOLD      = '\033[1m'
    DIM       = '\033[2m'

# 协议字典 (依据 plan.md 1.2)
PROTO_RECV_MAP = {
    'U': ("UNLOCKED",    Colors.OKGREEN, "开锁成功: 密码匹配或虚位提取合法"),
    'L': ("LOCKED",      Colors.FAIL,    "暴力破解锁定: 连续输错3次系统锁定"),
    'D': ("DURESS",      Colors.WARNING, "反挟持静默报警: 劫持胁迫密码触发"),
    'A': ("DOOR_ALERT",  Colors.WARNING, "门未关严警报: 开锁超时未关"),
}

PROTO_SEND_MAP = {
    'S': ("SAFE",          "环境安全指令: 视野单人，恢复键盘与OLED输入"),
    'P': ("PEEP",          "窥视挂起指令: 背后探头偷窥，挂起输入并熄屏"),
    'R': ("REMOTE_UNLOCK", "远程开锁指令: 上位机授权或人脸核验通过开锁"),
}

def get_timestamp() -> str:
    """返回毫秒级格式化时间戳"""
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]

def list_available_ports():
    """扫描并列出本机所有可用串口"""
    if serial is None:
        print(f"{Colors.FAIL}[错误] 缺少 pyserial 库，请先执行: pip install pyserial{Colors.ENDC}")
        return []
    ports = list(serial.tools.list_ports.comports())
    return ports

def print_banner():
    banner = f"""
{Colors.OKCYAN}======================================================================
  異構智能保險箱 - 串口聯調與協議監控工具 (Day 1 Tooling)
  波特率: 115200 bps | 數據格式: 8-N-1 | 字符協議標準 v1.0
======================================================================{Colors.ENDC}
    """
    print(banner)

class MockSerial:
    """模拟串口类，用于无硬件情况下的本地逻辑调试"""
    def __init__(self, port="MOCK_COM", baudrate=115200):
        self.port = port
        self.baudrate = baudrate
        self.is_open = True
        self._rx_queue = []
        self._lock = threading.Lock()
        print(f"{Colors.WARNING}[MOCK] 启动模拟串口模式 ({self.port})，用于无硬件单机联调{Colors.ENDC}")

    def write(self, data: bytes):
        char = data.decode('ascii', errors='ignore')
        # 模拟根据 PC 发送的指令，回传特定状态
        if 'S' in char:
            time.sleep(0.1)
            with self._lock:
                self._rx_queue.append(b'U') # 模拟回复 U
        elif 'P' in char:
            time.sleep(0.05)
            with self._lock:
                self._rx_queue.append(b'L')
        elif 'R' in char:
            time.sleep(0.1)
            with self._lock:
                self._rx_queue.append(b'U')
        return len(data)

    def read(self, size=1):
        with self._lock:
            if self._rx_queue:
                return self._rx_queue.pop(0)
        time.sleep(0.05)
        return b''

    @property
    def in_waiting(self):
        with self._lock:
            return len(self._rx_queue)

    def close(self):
        self.is_open = False

class SerialMonitor:
    def __init__(self, port: str, baudrate: int = 115200, is_mock: bool = False):
        self.port_name = port
        self.baudrate = baudrate
        self.is_mock = is_mock
        self.ser = None
        self.running = False
        self.rx_thread = None

    def connect(self) -> bool:
        if self.is_mock:
            self.ser = MockSerial(self.port_name, self.baudrate)
            self.running = True
            return True

        if serial is None:
            print(f"{Colors.FAIL}[错误] 尚未安装 pyserial，无法开启物理串口连接{Colors.ENDC}")
            return False

        try:
            self.ser = serial.Serial(
                port=self.port_name,
                baudrate=self.baudrate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=0.2
            )
            self.running = True
            print(f"{Colors.OKGREEN}[连接成功] 成功打开端口 {self.port_name} @ {self.baudrate} bps (8-N-1){Colors.ENDC}")
            return True
        except Exception as e:
            print(f"{Colors.FAIL}[连接失败] 打开端口 {self.port_name} 异常: {e}{Colors.ENDC}")
            return False

    def start_receiver(self):
        self.rx_thread = threading.Thread(target=self._rx_worker, daemon=True)
        self.rx_thread.start()

    def _rx_worker(self):
        """后台接收线程：监听串口并带毫秒时间戳打印"""
        buffer = bytearray()
        while self.running:
            try:
                if self.is_mock:
                    byte = self.ser.read(1)
                    if byte:
                        self._handle_incoming_byte(byte[0])
                    else:
                        time.sleep(0.02)
                    continue

                if self.ser and self.ser.is_open:
                    if self.ser.in_waiting > 0:
                        raw = self.ser.read(self.ser.in_waiting)
                        for b in raw:
                            self._handle_incoming_byte(b)
                    else:
                        time.sleep(0.01)
            except Exception as e:
                if self.running:
                    print(f"\n{Colors.FAIL}[RX 异常] 读取断开: {e}{Colors.ENDC}")
                break

    def _handle_incoming_byte(self, b: int):
        ts = get_timestamp()
        char = chr(b) if 32 <= b <= 126 else f"\\x{b:02X}"
        hex_val = f"0x{b:02X}"

        # 协议解释
        c_str = chr(b) if 32 <= b <= 126 else ''
        if c_str in PROTO_RECV_MAP:
            name, color, desc = PROTO_RECV_MAP[c_str]
            proto_info = f"{color}[{name}] {desc}{Colors.ENDC}"
        else:
            proto_info = f"{Colors.DIM}普通字符 / 未定协议{Colors.ENDC}"

        print(f"{Colors.DIM}[{ts}]{Colors.ENDC} {Colors.OKBLUE}<- [RECV]{Colors.ENDC} ASCII: '{char}' | HEX: {hex_val} | {proto_info}")

    def send_char(self, char_str: str):
        if not self.ser or not self.ser.is_open:
            print(f"{Colors.FAIL}[错误] 串口尚未就绪，无法发送{Colors.ENDC}")
            return

        for ch in char_str:
            data = ch.encode('ascii')
            self.ser.write(data)
            ts = get_timestamp()
            hex_val = f"0x{ord(ch):02X}"
            desc = PROTO_SEND_MAP.get(ch, ("", "自定义指令"))[1]
            print(f"{Colors.DIM}[{ts}]{Colors.ENDC} {Colors.OKGREEN}-> [SEND]{Colors.ENDC} ASCII: '{ch}' | HEX: {hex_val} | {Colors.HEADER}{desc}{Colors.ENDC}")

    def close(self):
        self.running = False
        if self.ser and self.ser.is_open:
            self.ser.close()
        print(f"\n{Colors.OKCYAN}[退出] 串口监控已安全关闭{Colors.ENDC}")

def interactive_loop(monitor: SerialMonitor):
    """主线程命令行交互控制"""
    print(f"""
{Colors.BOLD}【交互控制菜单】{Colors.ENDC}
  输入 {Colors.OKGREEN}'S'{Colors.ENDC} -> 发送 Safe (安全状态)
  输入 {Colors.FAIL}'P'{Colors.ENDC} -> 发送 Peep (窥视挂起)
  输入 {Colors.OKBLUE}'R'{Colors.ENDC} -> 发送 Remote Unlock (远程开锁)
  输入 {Colors.WARNING}'Q'{Colors.ENDC} -> 退出程序
  输入 其它字符 -> 直接透传发送至 FPGA
----------------------------------------------------------------------
""")
    try:
        while monitor.running:
            user_input = input().strip()
            if not user_input:
                continue
            if user_input.upper() == 'Q':
                break
            monitor.send_char(user_input)
    except (KeyboardInterrupt, EOFError):
        pass
    finally:
        monitor.close()

def main():
    parser = argparse.ArgumentParser(description="智能保险箱 串口联调与协议监控治具")
    parser.add_argument("-p", "--port", type=str, default=None, help="指定串口号 (如 COM3 或 /dev/ttyUSB0)")
    parser.add_argument("-b", "--baud", type=int, default=115200, help="波特率 (默认: 115200)")
    parser.add_argument("--mock", action="store_true", help="启用模拟模式 (无须插入硬件即可联调)")
    args = parser.parse_args()

    print_banner()

    port = args.port
    is_mock = args.mock

    if not is_mock and port is None:
        ports = list_available_ports()
        if not ports:
            print(f"{Colors.WARNING}[提示] 未检测到任何物理串口设备。{Colors.ENDC}")
            print(f"       -> 若暂无硬件板卡，可输入 'M' 进入模拟模式 (--mock)")
            choice = input("是否以模拟模式 (Mock) 启动? (y/n) [默认 y]: ").strip().lower()
            if choice in ('', 'y', 'yes', 'm'):
                is_mock = True
                port = "MOCK_PORT"
            else:
                sys.exit(0)
        else:
            print("当前系统可用串口列表:")
            for idx, p in enumerate(ports):
                desc = p.description or "未知设备"
                print(f"  [{idx + 1}] {p.device} ({desc})")
            print(f"  [M] 模拟模式 (Mock Mode)")

            sel = input("\n请选择要连接的串口编号 [默认 1]: ").strip()
            if sel.upper() == 'M':
                is_mock = True
                port = "MOCK_PORT"
            elif sel.isdigit() and 1 <= int(sel) <= len(ports):
                port = ports[int(sel) - 1].device
            else:
                port = ports[0].device

    monitor = SerialMonitor(port=port, baudrate=args.baud, is_mock=is_mock)
    if monitor.connect():
        monitor.start_receiver()
        interactive_loop(monitor)

if __name__ == "__main__":
    main()
