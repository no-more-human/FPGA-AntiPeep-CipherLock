"""Explicit interactive local enrollment. Existing photos are never overwritten."""
import argparse
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import cv2
from modules.face_auth import FaceAuth
from modules.config import ROOT


def main():
    parser = argparse.ArgumentParser(description="采集白名单照片，S 保存、Q 退出")
    parser.add_argument("--name", required=True, help="授权用户名称，只允许字母数字、下划线或汉字")
    parser.add_argument("--camera", type=int, default=0)
    args = parser.parse_args()
    if not re.fullmatch(r"[\w\u4e00-\u9fff]{1,32}", args.name) or args.name in (".", ".."):
        parser.error("名称不合法")
    directory = ROOT/"known_faces"/args.name
    directory.mkdir(parents=True, exist_ok=True)
    auth = FaceAuth()
    camera = cv2.VideoCapture(args.camera)
    if not camera.isOpened():
        raise RuntimeError("摄像头打开失败")
    count = 0
    try:
        while True:
            ok, frame = camera.read()
            if not ok:
                raise RuntimeError("摄像头读取失败")
            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            boxes = auth._detect(gray)
            annotated = frame.copy()
            for x, y, w, h in boxes:
                cv2.rectangle(annotated, (x, y), (x+w, y+h), (0, 220, 120), 2)
            cv2.putText(annotated, f"S: save one face | Q: quit | saved {count}",
                        (12, 30), cv2.FONT_HERSHEY_SIMPLEX, .65, (100, 240, 160), 2)
            cv2.imshow("Local face enrollment", annotated)
            key = cv2.waitKey(1) & 0xff
            if key == ord("q"):
                break
            if key == ord("s"):
                if len(boxes) != 1:
                    print("请确保画面中只有一张正脸")
                    continue
                path = directory / f"{time.time_ns()}.jpg"
                encoded, buffer = cv2.imencode(".jpg", frame)
                if encoded:
                    buffer.tofile(path)
                    count += 1
                    print(f"已保存第 {count} 张；建议采集 10~20 张不同光照和角度的正脸")
    finally:
        camera.release()
        cv2.destroyAllWindows()
    print("重启主程序后重新训练生效。照片仅保存在本地，不要上传 GitHub。")


if __name__ == "__main__":
    main()
