from pathlib import Path
import shutil
import tempfile

import cv2
import numpy as np


class FaceAuth:
    VERSION = "FACE_AUTH_V3"

    def __init__(self, dataset_dir=None, threshold=65.0):
        print("[FACE_AUTH_V3] 正在初始化人脸识别...")

        root = Path(__file__).resolve().parent.parent

        self.dataset_dir = (
            Path(dataset_dir) if dataset_dir is not None
            else root / "known_faces"
        )

        self.threshold = float(threshold)
        self.label_to_name = {}
        self.trained = False

        # 1. 获取项目中的 XML 模型文件
        source = (
            root
            / "models"
            / "haarcascade_frontalface_default.xml"
        )

        if not source.is_file():
            raise FileNotFoundError(
                f"缺少人脸模型文件: {source}"
            )

        # 2. 复制模型到英文路径，解决中文路径问题
        cache = (
            Path(tempfile.gettempdir())
            / "smart_safe_cv_models"
        )

        cache.mkdir(parents=True, exist_ok=True)

        target = (
            cache
            / "haarcascade_frontalface_default.xml"
        )

        shutil.copyfile(source, target)

        if not str(target).isascii():
            raise RuntimeError(
                f"临时路径含中文字符，无法直接交给 OpenCV: {target}"
            )

        # 3. 加载人脸检测模型
        self.face_cascade = cv2.CascadeClassifier(
            str(target)
        )

        if self.face_cascade.empty():
            raise RuntimeError(
                f"模型复制完成，但 OpenCV 仍无法读取: {target}"
            )

        print("[FACE_AUTH_V3] 人脸检测模型加载成功")

        # 4. 检查 LBPH 人脸识别模块
        if (
            not hasattr(cv2, "face")
            or not hasattr(
                cv2.face, "LBPHFaceRecognizer_create"
            )
        ):
            raise RuntimeError(
                "找不到 LBPH 人脸识别功能，"
                "请检查 opencv-contrib-python"
            )

        self.recognizer = (
            cv2.face.LBPHFaceRecognizer_create()
        )

        # 5. 加载授权人员照片并训练
        self.train_faces()

    def _detect(self, gray):
        return self.face_cascade.detectMultiScale(
            gray,
            scaleFactor=1.1,
            minNeighbors=5,
            minSize=(60, 60)
        )

    @staticmethod
    def _prepare(gray, box):
        x, y, w, h = [int(v) for v in box]

        crop = gray[y:y + h, x:x + w]

        if crop.size == 0:
            return None

        crop = cv2.equalizeHist(crop)

        return cv2.resize(crop, (200, 200))

    # 加载授权人员照片
    def train_faces(self):
        self.label_to_name = {}
        self.trained = False
        if not self.dataset_dir.is_dir():
            print(
                f"[FACE_AUTH_V3] 找不到照片目录: "
                f"{self.dataset_dir}"
            )
            return

        samples = []
        labels = []

        extensions = {
            ".jpg", ".jpeg", ".png", ".bmp"
        }

        people_dirs = sorted(
            p for p in self.dataset_dir.iterdir()
            if p.is_dir()
        )

        for person_dir in people_dirs:
            current_samples = []

            for path in sorted(person_dir.iterdir()):
                if (
                    not path.is_file()
                    or path.suffix.lower() not in extensions
                ):
                    continue

                # 支持中文路径中的图片
                try:
                    raw = np.fromfile(
                        str(path),
                        dtype=np.uint8
                    )
                    img = cv2.imdecode(
                        raw,
                        cv2.IMREAD_COLOR
                    )
                except (OSError, cv2.error, ValueError):
                    img = None

                if img is None:
                    print(
                        f"[FACE_AUTH_V3] 图片读取失败: "
                        f"{path.name}"
                    )
                    continue

                gray = cv2.cvtColor(
                    img,
                    cv2.COLOR_BGR2GRAY
                )

                boxes = self._detect(gray)

                if len(boxes) == 0:
                    print(
                        f"[FACE_AUTH_V3] 图片没有检测到正脸: "
                        f"{path.name}"
                    )
                    continue

                # 选择图片中最大的人脸
                box = max(
                    boxes,
                    key=lambda b: int(b[2]) * int(b[3])
                )

                crop = self._prepare(gray, box)

                if crop is not None:
                    current_samples.append(crop)

            if not current_samples:
                print(
                    f"[FACE_AUTH_V3] 跳过没有有效照片的文件夹: "
                    f"{person_dir.name}"
                )
                continue

            label = len(self.label_to_name)

            self.label_to_name[label] = (
                person_dir.name
            )

            samples.extend(current_samples)

            labels.extend(
                [label] * len(current_samples)
            )

            print(
                f"[FACE_AUTH_V3] 已加载 "
                f"{person_dir.name}: "
                f"{len(current_samples)} 张"
            )

        if not samples:
            print(
                "[FACE_AUTH_V3] 没有可训练的照片，"
                "摄像头仍可检测人脸，但会显示 UNKNOWN"
            )
            return

        self.recognizer.train(
            samples,
            np.asarray(labels, dtype=np.int32)
        )

        self.trained = True

        print("[FACE_AUTH_V3] 白名单训练成功")

    # 对摄像头画面进行人脸识别
    def analyze_faces(self, frame):
        if frame is None:
            return []

        gray = cv2.cvtColor(
            frame,
            cv2.COLOR_BGR2GRAY
        )

        found = []

        for box in self._detect(gray):
            x, y, w, h = [
                int(v) for v in box
            ]

            crop = self._prepare(
                gray,
                box
            )

            if crop is None:
                continue

            name = "UNKNOWN"
            authorized = False
            confidence = None

            if self.trained:
                label, distance = (
                    self.recognizer.predict(crop)
                )

                confidence = float(distance)

                candidate = (
                    self.label_to_name.get(int(label))
                )

                if (
                    candidate is not None
                    and confidence <= self.threshold
                ):
                    name = candidate
                    authorized = True

            found.append({
                "bbox": (x, y, w, h),
                "name": name,
                "authorized": authorized,
                "confidence": confidence
            })

        return found