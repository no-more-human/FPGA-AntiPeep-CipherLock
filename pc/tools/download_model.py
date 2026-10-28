"""Run explicitly to download the YOLOv8n weight; main never downloads silently."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from modules.config import ROOT


def main():
    from ultralytics import YOLO
    target = ROOT / "yolov8n.pt"
    if target.is_file():
        print("本地模型已存在:", target)
        return
    YOLO(str(target))
    if not target.is_file():
        raise RuntimeError("模型下载后未出现在预期路径，请手动放入 pc/yolov8n.pt")
    print("模型已下载:", target)


if __name__ == "__main__":
    main()
