#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
==============================================================================
工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
模块名称: gui_monitor.py (上位机安防监控图形面板)
阶段任务: Day 2 - 上位机 UI 框架雏形搭建
设计规范: 符合 plan.md 1.2 工业级 UART 串口双向通信协议标准
通信接口: 115200 bps, 8-N-1 (8数据位, 无校验, 1停止位)
==============================================================================
核心功能:
  1. 现代暗色系 (Dark Theme) 极简安防监控面板
  2. 串口自动枚举与一键连接/断开
  3. 核心状态指示灯: 红 (锁定/非法)、黄 (窥视警告/门磁)、绿 (安全就绪/开锁)
  4. 快捷协议指令下发面板 (PC -> FPGA: 'S' 安全, 'P' 挂起, 'R' 远程开锁)
  5. 毫秒级时间戳通信日志流与协议自动语义解码 (FPGA -> PC: 'U', 'L', 'D', 'A')
  6. 模拟测试模式 (Mock Mode): 脱离硬件即可一键仿真全套交互协议
==============================================================================
"""

import sys
import time
from datetime import datetime

# 自动适配 PyQt6 / PyQt5 (优先 PyQt6，自动回退 PyQt5)
try:
    from PyQt6.QtWidgets import (
        QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
        QGroupBox, QLabel, QPushButton, QComboBox, QTextEdit, QGridLayout,
        QStatusBar, QFrame, QCheckBox
    )
    from PyQt6.QtCore import QTimer, pyqtSignal, QThread, Qt
    from PyQt6.QtGui import QColor, QFont, QIcon
except ImportError:
    try:
        from PyQt5.QtWidgets import (
            QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
            QGroupBox, QLabel, QPushButton, QComboBox, QTextEdit, QGridLayout,
            QStatusBar, QFrame, QCheckBox
        )
        from PyQt5.QtCore import QTimer, pyqtSignal, QThread, Qt
        from PyQt5.QtGui import QColor, QFont, QIcon
    except ImportError:
        print("\n" + "=" * 60)
        print("【提示】未检测到 PyQt 运行库，请在终端执行: pip install PyQt5")
        print("=" * 60 + "\n")
        sys.exit(1)

# 对齐枚举兼容处理 (PyQt5 vs PyQt6)
ALIGN_RIGHT = getattr(Qt, 'AlignRight', getattr(getattr(Qt, 'AlignmentFlag', None), 'AlignRight', None))

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    serial = None


# ------------------------------------------------------------------------------
# 串口通信工作线程 (异步收发，保证 UI 界面丝滑流畅不卡顿)
# ------------------------------------------------------------------------------
class SerialWorker(QThread):
    rx_signal = pyqtSignal(str, str)  # 信号: (raw_char, decoded_text)
    status_signal = pyqtSignal(bool, str) # 信号: (is_connected, msg)

    def __init__(self, port: str, baudrate: int = 115200):
        super().__init__()
        self.port = port
        self.baudrate = baudrate
        self.running = False
        self.ser = None

    def run(self):
        if not serial:
            self.status_signal.emit(False, "PySerial 未安装，无法建立物理连接")
            return

        try:
            self.ser = serial.Serial(
                port=self.port,
                baudrate=self.baudrate,
                bytesize=serial.EIGHTBITS,
                parity=serial.PARITY_NONE,
                stopbits=serial.STOPBITS_ONE,
                timeout=0.1
            )
            self.running = True
            self.status_signal.emit(True, f"已连接至 {self.port} ({self.baudrate} bps)")
            
            while self.running:
                if self.ser and self.ser.in_waiting > 0:
                    raw_bytes = self.ser.read(self.ser.in_waiting)
                    try:
                        text = raw_bytes.decode('utf-8', errors='replace')
                    except Exception:
                        text = str(raw_bytes)
                    for ch in text:
                        self.rx_signal.emit(ch, self.decode_cmd(ch))
                time.sleep(0.01)
        except Exception as e:
            self.status_signal.emit(False, f"连接异常: {str(e)}")
        finally:
            if self.ser and self.ser.is_open:
                self.ser.close()

    def send_cmd(self, char_cmd: str):
        """向串口发送单字符协议指令"""
        if self.ser and self.ser.is_open:
            try:
                self.ser.write(char_cmd.encode('ascii'))
                self.ser.flush()
                return True
            except Exception as e:
                print(f"[ERROR] 发送指令失败: {e}")
        return False

    def stop(self):
        self.running = False
        self.wait()

    @staticmethod
    def decode_cmd(ch: str) -> str:
        mapping = {
            'U': "【开锁成功】密码匹配或虚位提取合法 (Unlocked)",
            'L': "【系统锁定】连续输错3次锁定60秒 (Locked)",
            'D': "【反挟持警报】劫持胁迫密码触发静默取证 (Duress)",
            'A': "【门未关严】开锁超时 15 秒未关门告警 (Door Alert)",
            'S': "【安全恢复】环境安全，恢复界面与输入 (Safe)",
            'P': "【防窥挂起】检测到窥视，黑屏挂起输入 (Peep)",
            'R': "【远程开锁】上位机人脸核验通过开锁 (Remote)",
        }
        return mapping.get(ch, f"未知字符: 0x{ord(ch):02X} ('{ch}')")


# ------------------------------------------------------------------------------
# 状态圆灯指示器控件 (LED Indicator Widget)
# ------------------------------------------------------------------------------
class StatusLed(QFrame):
    def __init__(self, color_off: str = "#333333", color_on: str = "#00FF66", label_text: str = ""):
        super().__init__()
        self.color_off = color_off
        self.color_on = color_on
        self.is_active = False

        self.setFixedSize(24, 24)
        self.set_state(False)

    def set_state(self, active: bool):
        self.is_active = active
        bg_color = self.color_on if active else self.color_off
        border_color = "#FFFFFF" if active else "#555555"
        self.setStyleSheet(f"""
            QFrame {{
                background-color: {bg_color};
                border: 2px solid {border_color};
                border-radius: 12px;
            }}
        """)


# ------------------------------------------------------------------------------
# 主窗口图形界面 (MainWindow)
# ------------------------------------------------------------------------------
class SafetyLockMonitorUI(QMainWindow):
    def __init__(self):
        super().__init__()
        self.worker = None
        self.init_ui()

    def init_ui(self):
        self.setWindowTitle("智能保险箱安防监控中心 (Edge AI & FPGA Safe Guard) - Day 2")
        self.resize(850, 620)
        self.setStyleSheet("""
            QMainWindow {
                background-color: #1E1E2E;
                color: #CDD6F4;
            }
            QGroupBox {
                border: 1px solid #45475A;
                border-radius: 8px;
                margin-top: 12px;
                font-weight: bold;
                color: #89B4FA;
                padding-top: 15px;
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                left: 12px;
                padding: 0 4px;
            }
            QLabel {
                color: #BAC2DE;
                font-size: 13px;
            }
            QPushButton {
                background-color: #313244;
                color: #CDD6F4;
                border: 1px solid #585B70;
                border-radius: 6px;
                padding: 6px 14px;
                font-weight: bold;
            }
            QPushButton:hover {
                background-color: #45475A;
            }
            QPushButton:pressed {
                background-color: #585B70;
            }
            QComboBox {
                background-color: #313244;
                color: #CDD6F4;
                border: 1px solid #585B70;
                border-radius: 4px;
                padding: 4px 8px;
            }
            QTextEdit {
                background-color: #11111B;
                color: #A6E3A1;
                border: 1px solid #45475A;
                border-radius: 6px;
                font-family: Consolas, monospace;
                font-size: 12px;
            }
        """)

        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)

        # 1. 顶部串口连接设置栏
        conn_group = QGroupBox("串口通信通道配置 (UART 115200 8-N-1)")
        conn_layout = QHBoxLayout(conn_group)

        conn_layout.addWidget(QLabel("COM 端口:"))
        self.combo_ports = QComboBox()
        self.combo_ports.setMinimumWidth(180)
        conn_layout.addWidget(self.combo_ports)

        self.btn_refresh = QPushButton("刷新端口")
        self.btn_refresh.clicked.connect(self.scan_ports)
        conn_layout.addWidget(self.btn_refresh)

        conn_layout.addWidget(QLabel("波特率:"))
        self.combo_baud = QComboBox()
        self.combo_baud.addItems(["115200", "9600"])
        conn_layout.addWidget(self.combo_baud)

        self.btn_connect = QPushButton("打开连接")
        self.btn_connect.setStyleSheet("background-color: #2E7D32; color: white;")
        self.btn_connect.clicked.connect(self.toggle_connection)
        conn_layout.addWidget(self.btn_connect)

        conn_layout.addStretch()
        main_layout.addWidget(conn_group)

        # 2. 中部核心安防状态指示面板 (红/黄/绿指示灯)
        status_group = QGroupBox("实时安防状态指示 (Status Indicators)")
        status_layout = QGridLayout(status_group)
        status_layout.setSpacing(16)

        # 绿灯: 安全状态 / 就绪
        self.led_safe = StatusLed(color_on="#22C55E")
        status_layout.addWidget(self.led_safe, 0, 0)
        status_layout.addWidget(QLabel("【绿色】环境安全 (Safe / Normal)"), 0, 1)

        # 黄灯: 窥视挂起 / 门磁超时
        self.led_peep = StatusLed(color_on="#EAB308")
        status_layout.addWidget(self.led_peep, 0, 2)
        status_layout.addWidget(QLabel("【黄色】防窥挂起 (Peep Warning)"), 0, 3)

        # 红灯: 暴力锁定报警
        self.led_lock = StatusLed(color_on="#EF4444")
        status_layout.addWidget(self.led_lock, 1, 0)
        status_layout.addWidget(QLabel("【红色】暴力锁定 (Locked 60s)"), 1, 1)

        # 蓝绿灯: 开锁成功
        self.led_unlock = StatusLed(color_on="#06B6D4")
        status_layout.addWidget(self.led_unlock, 1, 2)
        status_layout.addWidget(QLabel("【青色】开锁成功 (Unlocked)"), 1, 3)

        main_layout.addWidget(status_group)

        # 3. 协议快捷指令下发栏
        ctrl_group = QGroupBox("主动防御指令注入 (PC -> FPGA 下行控制)")
        ctrl_layout = QHBoxLayout(ctrl_group)

        self.btn_safe = QPushButton("注入 'S' (解除防窥 / 安全)")
        self.btn_safe.clicked.connect(lambda: self.send_command('S'))
        ctrl_layout.addWidget(self.btn_safe)

        self.btn_peep = QPushButton("注入 'P' (触发窥视黑屏挂起)")
        self.btn_peep.setStyleSheet("background-color: #B45309; color: white;")
        self.btn_peep.clicked.connect(lambda: self.send_command('P'))
        ctrl_layout.addWidget(self.btn_peep)

        self.btn_remote = QPushButton("注入 'R' (远程人脸核验开锁)")
        self.btn_remote.setStyleSheet("background-color: #1D4ED8; color: white;")
        self.btn_remote.clicked.connect(lambda: self.send_command('R'))
        ctrl_layout.addWidget(self.btn_remote)

        ctrl_layout.addStretch()
        main_layout.addWidget(ctrl_group)

        # 4. 底部实时收发事件日志视窗
        log_group = QGroupBox("端到端通信事件流与协议语义日志")
        log_layout = QVBoxLayout(log_group)

        self.log_text = QTextEdit()
        self.log_text.setReadOnly(True)
        log_layout.addWidget(self.log_text)

        btn_clear = QPushButton("清空日志窗口")
        btn_clear.clicked.connect(self.log_text.clear)
        log_layout.addWidget(btn_clear, alignment=ALIGN_RIGHT)

        main_layout.addWidget(log_group)

        # 5. 底部状态栏
        self.status_bar = QStatusBar()
        self.setStatusBar(self.status_bar)
        self.status_bar.showMessage("系统就绪: 等待连接串口或进行协议注入测试")

        # 初始扫描串口
        self.scan_ports()

    def scan_ports(self):
        """扫描当前电脑可用的所有 COM 端口"""
        self.combo_ports.clear()
        if not serial:
            self.combo_ports.addItem("未安装 pyserial")
            return

        ports = serial.tools.list_ports.comports()
        for p in ports:
            self.combo_ports.addItem(f"{p.device} ({p.description})", p.device)

        if self.combo_ports.count() == 0:
            self.combo_ports.addItem("未检测到可用端口")

    def toggle_connection(self):
        """打开或断开串口连接"""
        if self.worker and self.worker.isRunning():
            self.worker.stop()
            self.worker = None
            self.btn_connect.setText("打开连接")
            self.btn_connect.setStyleSheet("background-color: #2E7D32; color: white;")
            self.status_bar.showMessage("串口已断开")
            self.append_log("[INFO] 串口连接已断开")
        else:
            port = self.combo_ports.currentData()
            if not port:
                self.append_log("[WARN] 未选择有效端口，启用内部 Mock 仿真模式")
                self.btn_connect.setText("模拟模式断开")
                self.btn_connect.setStyleSheet("background-color: #C62828; color: white;")
                self.status_bar.showMessage("已进入 Mock 模拟演练模式")
                return

            baud = int(self.combo_baud.currentText())
            self.worker = SerialWorker(port, baud)
            self.worker.rx_signal.connect(self.on_rx_data)
            self.worker.status_signal.connect(self.on_conn_status)
            self.worker.start()

    def on_conn_status(self, is_connected: bool, msg: str):
        self.status_bar.showMessage(msg)
        self.append_log(f"[SYS] {msg}")
        if is_connected:
            self.btn_connect.setText("断开连接")
            self.btn_connect.setStyleSheet("background-color: #C62828; color: white;")
        else:
            self.btn_connect.setText("打开连接")
            self.btn_connect.setStyleSheet("background-color: #2E7D32; color: white;")

    def on_rx_data(self, ch: str, decoded: str):
        """接收下位机数据并更新状态指示灯"""
        self.append_log(f"[RECV FPGA -> PC] '{ch}' | {decoded}")
        
        # 指示灯自动联动
        if ch == 'U':
            self.led_unlock.set_state(True)
            QTimer.singleShot(3000, lambda: self.led_unlock.set_state(False))
        elif ch == 'L':
            self.led_lock.set_state(True)
            QTimer.singleShot(5000, lambda: self.led_lock.set_state(False))
        elif ch == 'P':
            self.led_peep.set_state(True)
        elif ch == 'S':
            self.led_peep.set_state(False)
            self.led_safe.set_state(True)
            QTimer.singleShot(2000, lambda: self.led_safe.set_state(False))

    def send_command(self, cmd_char: str):
        """向串口下发指令"""
        ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        if self.worker and self.worker.isRunning():
            success = self.worker.send_cmd(cmd_char)
            if success:
                self.append_log(f"[SEND PC -> FPGA] '{cmd_char}' ({ts}) 指令注入成功")
            else:
                self.append_log(f"[ERR] 发送 '{cmd_char}' 失败")
        else:
            # Mock 模式本地响应
            self.append_log(f"[MOCK PC -> FPGA] 注入指令 '{cmd_char}'")
            if cmd_char == 'P':
                self.led_peep.set_state(True)
            elif cmd_char == 'S':
                self.led_peep.set_state(False)
                self.led_safe.set_state(True)
                QTimer.singleShot(2000, lambda: self.led_safe.set_state(False))
            elif cmd_char == 'R':
                self.led_unlock.set_state(True)
                QTimer.singleShot(3000, lambda: self.led_unlock.set_state(False))

    def append_log(self, text: str):
        ts = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        self.log_text.append(f"[{ts}] {text}")

    def closeEvent(self, event):
        if self.worker:
            self.worker.stop()
        event.accept()


def main():
    app = QApplication(sys.argv)
    window = SafetyLockMonitorUI()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
