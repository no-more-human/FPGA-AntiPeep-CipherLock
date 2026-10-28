import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load_config(path=None):
    with (ROOT / "config.json").open(encoding="utf-8") as stream:
        config = json.load(stream)
    if path and Path(path).resolve() != (ROOT / "config.json").resolve():
        with Path(path).open(encoding="utf-8") as stream:
            overrides = json.load(stream)
        unknown = overrides.keys() - config.keys()
        if unknown:
            raise ValueError(f"未知配置项: {sorted(unknown)}")
        config.update(overrides)
    for key in ("width", "height", "image_size", "baudrate", "record_fps", "cpu_threads"):
        if type(config[key]) is not int or config[key] <= 0:
            raise ValueError(f"{key} 必须为正整数")
    for key in ("peep_enter_seconds", "peep_exit_seconds", "face_stable_seconds",
                "face_threshold", "segment_seconds", "event_record_seconds",
                "record_max_gb", "record_retention_days"):
        if type(config[key]) not in (int, float) or not math.isfinite(config[key]) or config[key] <= 0:
            raise ValueError(f"{key} 必须为正数")
    if type(config["confidence"]) not in (int, float) or not 0 < config["confidence"] <= 1:
        raise ValueError("confidence 必须在 (0, 1] 内")
    roi = config["roi"]
    if not isinstance(roi, list) or len(roi) != 4 or any(type(v) not in (int, float) for v in roi):
        raise ValueError("roi 格式为 [左, 上, 右, 下]，范围 0~1")
    if not (0 <= roi[0] < roi[2] <= 1 and 0 <= roi[1] < roi[3] <= 1):
        raise ValueError("roi 边界无效")
    if config["alarm_display"] not in ("silent", "security"):
        raise ValueError("alarm_display 应为 silent 或 security")
    for key in ("extended_protocol", "continuous_recording"):
        if type(config[key]) is not bool:
            raise ValueError(f"{key} 必须为 true / false")
    return config


def resolve_path(value):
    path = Path(value)
    return path if path.is_absolute() else ROOT / path
