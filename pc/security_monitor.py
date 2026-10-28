"""Run this on a separate security screen; the default site UI stays silent."""
import argparse
import sqlite3
import tkinter as tk
from pathlib import Path
from tkinter import ttk
from modules.config import load_config, resolve_path


def main():
    parser = argparse.ArgumentParser(description="安保日志查看器（只读，不连接 FPGA）")
    parser.add_argument("--db", help="本地 events.sqlite3 文件路径")
    parser.add_argument("--demo", action="store_true", help="查看演示日志")
    args = parser.parse_args()
    cfg = load_config()
    path = Path(args.db) if args.db else resolve_path(cfg["data_dir"])/("demo" if args.demo else "live")/"events.sqlite3"
    root = tk.Tk()
    root.title("安保中心 · 报警与开锁日志（独立界面）")
    root.geometry("1050x650")
    title = tk.StringVar(value="等待日志")
    ttk.Label(root, textvariable=title, font=("Microsoft YaHei UI", 16, "bold")).pack(anchor="w", padx=16, pady=12)
    view = ttk.Treeview(root, columns=("time", "code", "detail"), show="headings")
    for column, text, width in (("time", "时间 UTC+8", 270), ("code", "事件", 150), ("detail", "内容", 530)):
        view.heading(column, text=text)
        view.column(column, width=width)
    view.tag_configure("alarm", foreground="#bb1738")
    view.pack(fill="both", expand=True, padx=16, pady=12)
    ttk.Label(root, text="此工具只读取本地数据库；跨电脑报警尚需服务端/API，不代表已联网报警。").pack(padx=16, pady=8)
    last_id = 0
    initialized = False

    def poll():
        nonlocal last_id, initialized
        try:
            with sqlite3.connect(path.resolve().as_uri()+"?mode=ro", uri=True, timeout=1) as db:
                if not initialized:
                    rows = db.execute("SELECT id,time,code,detail FROM events ORDER BY id DESC LIMIT 200").fetchall()[::-1]
                else:
                    rows = db.execute("SELECT id,time,code,detail FROM events WHERE id>? ORDER BY id LIMIT 200", (last_id,)).fetchall()
            for event_id, stamp, code, detail in rows:
                alarm = code in ("D", "C")
                view.insert("", 0, values=(stamp, code, detail), tags=("alarm",) if alarm else ())
                last_id = max(last_id, event_id)
                if alarm and initialized:
                    title.set("紧急报警：" + detail)
                    popup = tk.Toplevel(root)
                    popup.title("紧急胁迫报警")
                    tk.Label(popup, text=detail, bg="#9a243c", fg="white",
                             font=("Microsoft YaHei UI", 20), padx=30, pady=30).pack()
                    ttk.Button(popup, text="已查看", command=popup.destroy).pack(pady=10)
                    popup.attributes("-topmost", True)
            initialized = True
            if rows and title.get() == "等待日志":
                title.set("安保中心 · 正在监控新事件")
            children = view.get_children()
            for item in children[200:]:
                view.delete(item)
        except (sqlite3.Error, OSError):
            title.set("等待上位机创建日志数据库 / 数据库暂不可读")
        root.after(1000, poll)
    poll()
    root.mainloop()


if __name__ == "__main__":
    main()
