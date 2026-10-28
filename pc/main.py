import argparse
import sys

from modules.config import load_config


def main():
    parser = argparse.ArgumentParser(description="FPGA 智能保险箱视觉与上位机")
    parser.add_argument("--demo", action="store_true", help="显式启用模拟 FPGA，绝不连接物理设备")
    parser.add_argument("--no-camera", action="store_true", help="不启动视觉，便于演示协议与界面")
    parser.add_argument("--config", help="配置文件路径（支持覆盖部分配置）")
    parser.add_argument("--port", help="启动时连接指定串口，例如 COM3")
    parser.add_argument("--security", action="store_true", help="安保端显示敏感报警，现场电脑勿用")
    parser.add_argument("--smoke-seconds", type=float, help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        config = load_config(args.config)
        if args.security:
            config["alarm_display"] = "security"
        if args.port:
            config["serial_port"] = args.port
        from modules.ui import MonitorApp
        app = MonitorApp(config, demo=args.demo, no_camera=args.no_camera)
        if args.smoke_seconds:
            app.root.after(int(args.smoke_seconds*1000), app.close)
        app.run()
    except (ImportError, ValueError, OSError, RuntimeError) as error:
        print(f"启动失败: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
