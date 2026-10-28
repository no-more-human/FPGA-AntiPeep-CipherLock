import importlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from modules.config import ROOT

failed = False
for name in ("cv2", "numpy", "ultralytics", "serial", "PIL", "tkinter"):
    try:
        module = importlib.import_module(name)
        print(f"OK {name}: {getattr(module, '__version__', 'available')}")
    except ImportError as error:
        failed = True
        print(f"FAIL {name}: {error}")
try:
    import cv2
    if not hasattr(cv2, "face") or not hasattr(cv2.face, "LBPHFaceRecognizer_create"):
        failed = True
        print("FAIL cv2.face: 请运行 setup_pc.bat 修复 OpenCV 依赖")
except ImportError:
    pass
for asset in (ROOT/"models"/"haarcascade_frontalface_default.xml", ROOT/"yolov8n.pt"):
    print(("OK " if asset.is_file() else "MISSING ")+str(asset))
    if not asset.is_file():
        failed = True
print("白名单照片存在:", any((ROOT/"known_faces").glob("*/*.jpg")))
print("检查完成；不自动访问摄像头、不连接串口、不联网。")
raise SystemExit(1 if failed else 0)
