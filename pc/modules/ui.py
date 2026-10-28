import os
import queue
import time
import tkinter as tk
from tkinter import ttk, messagebox, filedialog

import cv2
from PIL import Image, ImageTk

from .audit import AuditStore
from .config import resolve_path
from .controller import Controller
from .evidence import EvidenceRecorder
from .serial_comm import available_ports

BG = "#101924"
PANEL = "#192635"
TEXT = "#e4edf4"
MUTED = "#a2b5c7"
GREEN = "#58d6aa"
AMBER = "#ffcf76"


class MonitorApp:
    def __init__(self, config, demo=False, no_camera=False):
        self.config, self.demo = config, demo
        self.root = tk.Tk()
        self.root.title("智能保险箱 · 视觉与联动监控" + ("【模拟演示】" if demo else ""))
        self.root.geometry("1180x880")
        self.root.minsize(1100, 850)
        self.root.configure(bg=BG)
        self.root.protocol("WM_DELETE_WINDOW", self.close)
        self.closed = False
        self.events = queue.Queue()
        self.audit = AuditStore(resolve_path(config["data_dir"]) / ("demo" if demo else "live"))
        self.recorder = EvidenceRecorder(self.audit.directory, config, self.events.put)
        self.controller = Controller(config, self.audit, self.recorder, self.events.put, demo)
        self.worker = None
        self.last_log = None
        self.last_vision_at = -1
        self.photo = None
        self._build()
        if not no_camera:
            from .vision import VisionWorker
            self.worker = VisionWorker(config, self.events.put, self.recorder)
            self.worker.start()
        else:
            self.camera_status.set("视觉未启动 · 此模式可演示日志、改密和协议")
        if config["serial_port"] and not demo:
            self.controller.connect(config["serial_port"])
        self.root.after(50, self.poll)

    def _build(self):
        style = ttk.Style(self.root)
        style.theme_use("clam")
        style.configure(".", font=("Microsoft YaHei UI", 10), background=PANEL, foreground=TEXT)
        style.configure("TFrame", background=PANEL)
        style.configure("TLabel", background=PANEL, foreground=TEXT)
        style.configure("TButton", background="#2b4257", foreground=TEXT, padding=(10, 7))
        style.map("TButton", background=[("active", "#385d79"), ("disabled", "#27323b")])
        style.configure("TNotebook", background=BG, borderwidth=0)
        style.configure("TNotebook.Tab", padding=(18, 8), background=PANEL, foreground=TEXT)
        style.map("TNotebook.Tab", background=[("selected", "#2b4257")])
        style.configure("TEntry", fieldbackground="#f5f8fa", foreground="#162436")
        style.configure("TCombobox", fieldbackground="#f5f8fa", foreground="#162436")
        style.map("TCombobox", foreground=[("readonly", "#162436")], fieldbackground=[("readonly", "#f5f8fa")])

        header = tk.Frame(self.root, bg=BG)
        header.pack(fill="x", padx=22, pady=(16, 12))
        tk.Label(header, text="SMART SAFE", bg=BG, fg=GREEN,
                 font=("Segoe UI", 21, "bold")).pack(side="left")
        tk.Label(header, text="视觉识别 / FPGA 联动", bg=BG, fg=MUTED,
                 font=("Microsoft YaHei UI", 11)).pack(side="left", padx=18)
        mode = "模拟演示 · 不控制硬件" if self.demo else (
            "安保端 · 显示报警" if self.config["alarm_display"] == "security" else "现场端")
        tk.Label(header, text=mode, bg="#293b4c", fg=AMBER, padx=12, pady=6).pack(side="right")

        conn = ttk.Frame(self.root, padding=12)
        conn.pack(fill="x", padx=22)
        ttk.Label(conn, text="串口").pack(side="left")
        self.port = tk.StringVar(value=self.config["serial_port"])
        self.ports = ttk.Combobox(conn, textvariable=self.port, width=17)
        self.ports.pack(side="left", padx=8)
        ttk.Button(conn, text="刷新", command=self.refresh_ports).pack(side="left")
        self.connect_button = ttk.Button(conn, text="连接", command=self.toggle_connection)
        self.connect_button.pack(side="left", padx=8)
        if self.demo:
            self.connect_button.configure(state="disabled")
        self.link_status = tk.StringVar(value="模拟 FPGA 已就绪" if self.demo else "未连接")
        ttk.Label(conn, textvariable=self.link_status, foreground=MUTED).pack(side="left", padx=10)
        ttk.Label(conn, text=f'{self.config["baudrate"]} / 8-N-1', foreground=MUTED).pack(side="right")
        self.refresh_ports()

        body = tk.Frame(self.root, bg=BG)
        body.pack(fill="both", expand=True, padx=22, pady=12)
        body.columnconfigure(0, weight=3)
        body.columnconfigure(1, weight=2)
        body.rowconfigure(0, weight=1)
        view = ttk.Frame(body, padding=10)
        view.grid(row=0, column=0, sticky="nsew", padx=(0, 12))
        ttk.Label(view, text="实时视觉", font=("Microsoft YaHei UI", 12, "bold")).pack(anchor="w")
        self.canvas = tk.Canvas(view, background="#0b1119", highlightthickness=0, width=640, height=390)
        self.canvas.pack(fill="both", expand=True, pady=8)
        self.canvas.create_text(320, 190, text="等待摄像头画面", fill=MUTED,
                                font=("Microsoft YaHei UI", 16), tags="placeholder")
        self.camera_status = tk.StringVar(value="视觉初始化中，请稍候")
        ttk.Label(view, textvariable=self.camera_status, foreground=MUTED, wraplength=610).pack(anchor="w")

        side = ttk.Frame(body, padding=12)
        side.grid(row=0, column=1, sticky="nsew")
        ttk.Label(side, text="锁体与环境", font=("Microsoft YaHei UI", 12, "bold")).pack(anchor="w")
        self.lock_status = tk.StringVar(value=self.controller.state.lock)
        ttk.Label(side, textvariable=self.lock_status, font=("Microsoft YaHei UI", 15, "bold"),
                  wraplength=350).pack(anchor="w", pady=(10, 4))
        self.peep_status = tk.StringVar(value="环境状态等待视觉确认")
        ttk.Label(side, textvariable=self.peep_status, foreground=AMBER, wraplength=350).pack(anchor="w", pady=4)
        self.identity = tk.StringVar(value="白名单识别：等待画面")
        ttk.Label(side, textvariable=self.identity, wraplength=350).pack(anchor="w", pady=4)
        self.face_button = ttk.Button(side, text="人脸核验后发送开锁指令", command=self.face_unlock, state="disabled")
        self.face_button.pack(fill="x", pady=(6, 3))
        ttk.Label(side, text="须单人白名单人脸稳定识别 2 秒。\n识别辅助没有活体检测，请保留密码核验。",
                  foreground=MUTED, wraplength=350).pack(anchor="w", pady=(4, 5))
        tools = ttk.Frame(side)
        tools.pack(fill="x", pady=4)
        ttk.Button(tools, text="测试 P · 防窥", command=lambda: self.test_command("P")).pack(side="left", expand=True, fill="x", padx=(0, 4))
        ttk.Button(tools, text="恢复自动判断", command=self.restore_vision).pack(side="left", expand=True, fill="x")
        ttk.Label(side, text="收到设备回报后更新锁体状态。",
                  foreground=MUTED, wraplength=350).pack(anchor="w", pady=5)
        ttk.Separator(side).pack(fill="x", pady=5)
        ttk.Label(side, text="取证存储", font=("Microsoft YaHei UI", 11, "bold")).pack(anchor="w")
        ttk.Label(side, text=("连续分段录像已开启" if self.config["continuous_recording"] else "按事件抓拍与录像") +
                  "\n本地滚动录像：1 天 / 2 GiB。",
                  foreground=MUTED, wraplength=350).pack(anchor="w", pady=6)
        ttk.Button(side, text="打开本地数据目录", command=self.open_data).pack(fill="x", pady=6)

        notebook = ttk.Notebook(self.root)
        notebook.pack(fill="x", padx=22, pady=(0, 12))
        logs = ttk.Frame(notebook, padding=10)
        notebook.add(logs, text="运行日志")
        self.log_text = tk.Text(logs, height=5, bg="#0b1119", fg=TEXT, relief="flat",
                                font=("Microsoft YaHei UI", 9), state="disabled", wrap="word")
        self.log_text.pack(side="left", fill="both", expand=True)
        log_actions = ttk.Frame(logs)
        log_actions.pack(side="right", fill="y", padx=(10, 0))
        ttk.Button(log_actions, text="导出 CSV", command=self.export_logs).pack(fill="x")
        ttk.Label(log_actions, text="最近 200 条\n完整日志存本地", foreground=MUTED).pack(pady=8)

        pwd = ttk.Frame(notebook, padding=12)
        notebook.add(pwd, text="密码管理")
        enabled = self.demo or self.config["extended_protocol"]
        ttk.Label(pwd, text="修改需验证当前常规密码；等待下位机确认后才生效。" if enabled else
                  "真实硬件改密扩展尚未启用。现阶段请使用实体键盘 B 键修改常规密码。",
                  foreground=AMBER).grid(row=0, column=0, columnspan=6, sticky="w", pady=(0, 10))
        self.password_kind = tk.StringVar(value="normal")
        ttk.Combobox(pwd, textvariable=self.password_kind, values=("normal", "duress"),
                     state="readonly", width=9).grid(row=1, column=0, padx=(0, 10))
        self.password_fields = []
        for index, label in enumerate(("当前常规密码", "新密码（6位）", "再次确认")):
            box = ttk.Frame(pwd)
            box.grid(row=1, column=index+1, padx=6)
            ttk.Label(box, text=label).pack(anchor="w")
            field = ttk.Entry(box, show="*", width=17)
            field.pack()
            self.password_fields.append(field)
        self.password_button = ttk.Button(pwd, text="提交修改", command=self.change_password,
                                          state="normal" if enabled else "disabled")
        self.password_button.grid(row=1, column=4, padx=12)
        self.password_status = tk.StringVar(value="normal 为常规密码，duress 为胁迫密码")
        ttk.Label(pwd, textvariable=self.password_status, foreground=MUTED).grid(
            row=2, column=0, columnspan=6, sticky="w", pady=(10, 0))

        if self.demo:
            demo = ttk.Frame(notebook, padding=12)
            notebook.add(demo, text="模拟验收")
            ttk.Label(demo, text="初始常规 123456 / 胁迫 654321；虚位输入 6~16 位，仅为软件模拟。",
                      foreground=AMBER).pack(anchor="w", pady=(0, 10))
            line = ttk.Frame(demo)
            line.pack(fill="x")
            self.demo_digits = ttk.Entry(line, show="*", width=30)
            self.demo_digits.pack(side="left")
            ttk.Button(line, text="模拟按 # 提交", command=self.demo_submit).pack(side="left", padx=10)
            for code, label in (("U", "正常"), ("D", "胁迫"), ("L", "锁定"), ("A", "门未关"), ("T", "解除锁定")):
                ttk.Button(line, text=label, command=lambda c=code: self.events.put({"type": "event", "code": c})).pack(side="left", padx=3)

        self.footer = tk.StringVar(value="就绪")
        tk.Label(self.root, textvariable=self.footer, bg=BG, fg=MUTED, anchor="w",
                 font=("Microsoft YaHei UI", 9)).pack(fill="x", padx=22, pady=(0, 10))

    def refresh_ports(self):
        self.ports["values"] = [p[0] for p in available_ports()]

    def toggle_connection(self):
        try:
            if self.controller.link:
                self.controller.disconnect()
                self.connect_button.configure(text="连接")
            else:
                self.controller.connect(self.port.get())
                self.connect_button.configure(text="断开")
        except ValueError as error:
            messagebox.showerror("连接", str(error), parent=self.root)

    def face_unlock(self):
        try:
            self.controller.face_unlock()
        except ValueError as error:
            messagebox.showinfo("开锁条件", str(error), parent=self.root)

    def test_command(self, command):
        self.controller.peeping = True
        if not self.controller.send(command):
            self.footer.set("未发送：请先连接串口")

    def restore_vision(self):
        v = self.controller.vision
        if not v or time.monotonic()-v["captured_at"] > 1:
            self.footer.set("画面无效，无法确认环境安全")
            return
        active = v["decision"].peeping
        self.controller.peeping = active
        self.controller.send("P" if active else "S")

    def change_password(self):
        try:
            old, new, confirm = [f.get() for f in self.password_fields]
            self.controller.change_password(self.password_kind.get(), old, new, confirm, self.password_done)
            self.password_status.set("已提交，等待下位机回执……")
            self.password_button.configure(state="disabled")
            for field in self.password_fields:
                field.delete(0, "end")
        except ValueError as error:
            self.password_status.set(str(error))

    def password_done(self, ok, detail):
        self.password_status.set(detail)
        self.password_button.configure(state="normal")
        for field in self.password_fields:
            field.delete(0, "end")

    def demo_submit(self):
        try:
            for event in self.controller.sim.submit(self.demo_digits.get()):
                self.events.put(event)
            self.demo_digits.delete(0, "end")
        except ValueError as error:
            self.footer.set(str(error))

    def open_data(self):
        os.startfile(str(self.audit.directory.resolve()))

    def export_logs(self):
        path = filedialog.asksaveasfilename(parent=self.root, defaultextension=".csv",
                                          filetypes=[("CSV", "*.csv")], initialfile="safe_logs.csv")
        if path:
            self.audit.export(path, include_sensitive=self.config["alarm_display"] == "security")
            self.footer.set("日志已导出")

    def poll(self):
        if self.closed:
            return
        self.controller.tick()
        for _ in range(300):
            try:
                self.controller.handle(self.events.get_nowait())
            except queue.Empty:
                break
        v = self.worker.latest() if self.worker else None
        now = time.monotonic()
        fresh = v is not None and now-v["captured_at"] <= 1 and now-v["analyzed_at"] <= 1
        self.controller.update_vision(v if fresh else None)
        if fresh:
            self.controller.error = ""
            if v["analyzed_at"] != self.last_vision_at:
                self.last_vision_at = v["analyzed_at"]
                width, height = max(self.canvas.winfo_width(), 100), max(self.canvas.winfo_height(), 100)
                image = Image.fromarray(cv2.cvtColor(v["frame"], cv2.COLOR_BGR2RGB))
                image.thumbnail((width, height), Image.Resampling.LANCZOS)
                self.photo = ImageTk.PhotoImage(image)
                self.canvas.delete("all")
                self.canvas.create_image(width//2, height//2, image=self.photo)
            self.camera_status.set(f'人体 {v["people"]} / 人脸 {v["faces"]} · 推理 {v["ms"]:.0f} ms · ' +
                                   ("白名单已加载" if v["trained"] else "无有效白名单照片"))
            d = v["decision"]
            self.peep_status.set("多人风险 · 已发防窥请求" if self.controller.peeping else "视野正常")
            self.identity.set("白名单识别：" + (d.identity or "未通过") +
                              (" · 已稳定，可请求开锁" if d.face_ready else ""))
        else:
            if self.worker:
                self.camera_status.set(self.controller.error or "视觉画面过期 / 等待摄像头恢复")
            self.identity.set("白名单识别：当前不可用")
            self.peep_status.set("环境状态未知，请注意遮挡密码")
        ready = fresh and v["decision"].face_ready and not self.controller.peeping
        self.face_button.configure(state="normal" if ready and self.controller.connected and
                                   not self.controller.state.lockout else "disabled")
        self.lock_status.set(self.controller.state.lock)
        self.link_status.set("模拟 FPGA 已就绪" if self.demo else (
            ("串口已打开 · 已收到设备回报" if self.controller.device_seen else "串口已打开 · 等待设备回报")
            if self.controller.connected else ("未连接 / 重连中" if self.controller.link else "未连接")))
        rows = tuple(self.controller.lines)
        if rows != self.last_log:
            self.last_log = rows
            self.log_text.configure(state="normal")
            self.log_text.delete("1.0", "end")
            self.log_text.insert("end", "\n".join(f"{t}  {code}  {text}" for t, code, text in rows))
            self.log_text.see("end")
            self.log_text.configure(state="disabled")
        if self.controller.alarms:
            alarm = self.controller.alarms.popleft()
            # Non-modal alert leaves serial processing and recording running.
            popup = tk.Toplevel(self.root)
            popup.title("安保紧急报警")
            popup.configure(bg="#551c26")
            tk.Label(popup, text=alarm, bg="#551c26", fg="white",
                     font=("Microsoft YaHei UI", 20, "bold"), padx=30, pady=30).pack()
            ttk.Button(popup, text="已查看", command=popup.destroy).pack(pady=(0, 20))
            popup.attributes("-topmost", True)
        self.root.after(60, self.poll)

    def run(self):
        self.root.mainloop()

    def close(self):
        if self.closed:
            return
        self.closed = True
        self.controller.close()
        if self.worker:
            self.worker.close()
        self.recorder.close()
        while not self.events.empty():
            event = self.events.get_nowait()
            if event.get("type") in ("evidence", "record_segment", "evidence_error"):
                self.controller.handle(event)
        self.audit.close()
        self.root.destroy()
