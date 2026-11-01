# AI Context & Scope Guidelines

## Core Source Areas (AI Focus)
- `rtl/*.v`: Verilog HDL implementation for the smart safe on Anlogic EG4S20.
- `sim/tb_*.v`: Testbenches for RTL verification.
- `constraints/lock.sdc`, `lock.adc`, `lock.al`: FPGA pin and timing constraints.
- `pc/main.py`, `pc/security_monitor.py`, `pc/modules/*.py`: Python host application and YOLOv8 pipeline.
- `pc/tests/*.py`, `tools/*.py`, `tools/*.bat`, `tools/*.tcl`: Host test cases and build/download scripts.
- `plan.md`, `README.md`, `docs/EG4S20_Pinout.md`: Architecture plans and pinout references.

## Files to Never Read / Index (Ignored via .antigravityignore)
- **EDA Artifacts**: `lock_Runs/`, `*_Runs/`, `*.bit`, `*.db`, `*.gate.v`, `*.snr`, `*.log`.
- **Large Model Binaries**: `pc/yolov8n.pt`, `*.onnx`, `pc/models/*.xml`.
- **Media & Biometrics**: `pc/known_faces/*`, `pc/data/`, `docs/*.png`, `docs/*.xlsx`.
- **Caches & Waves**: `__pycache__/`, `.pytest_cache/`, `*.vcd`, `*.fsdb`.
