# 视觉与上位机：运行说明

本目录将原来的 main.py、vision.py 和 FaceAuth 接入团队仓库。FPGA 的矩阵键盘、密码匹配、舵机和板上声光由队友维护；PC 提供视觉判断、串口请求、状态展示和取证。原 tools/gui_monitor.py、rtl/ 和 sim/ 保留。

## 1. 先运行演示

本机已复制原有 YOLO 模型、Haar 模型和三张 owner 照片，放在此目录中；人脸照片和 YOLO 权重均被 Git 排除。分享用的代码 ZIP 不包含照片、权重或运行日志。

- Windows 双击 run_demo.bat：不打开摄像头、不连接硬件。
- 双击 run_camera_demo.bat：真实摄像头 + 模拟 FPGA，适合你先自己调试。
- 保持演示主窗口开启，再双击 run_security_viewer_demo.bat：独立查看演示日志和新胁迫报警，不占用第二路摄像头。
- 双击 run_camera.bat：打开视觉，串口需在界面手动选择并连接。
- 环境缺少依赖时，先双击 setup_pc.bat。它只安装到仓库根目录的 .venv。
- 从分享用 ZIP 安装后，执行 tools/download_model.py 下载权重，再录入本地照片。
- 推荐 Python 3.10–3.12。不要同时维护多个提供 cv2 的 OpenCV 安装包；安装脚本会在独立环境中保留 contrib 版本以支持 LBPH。

在仓库根目录执行：

~~~powershell
.\.venv\Scripts\python.exe -X utf8 pc\main.py --demo --no-camera
.\.venv\Scripts\python.exe -X utf8 pc\main.py --demo
.\.venv\Scripts\python.exe -X utf8 pc\main.py --port COM3
~~~

--demo 才会启动软件模拟器。普通模式不会在串口连接失败时自动切换模拟，更不会假报开锁。

## 2. 视觉功能

- YOLOv8n 检测 ROI 内人体；Haar 独立检测真实人脸，LBPH 识别白名单。
- 两人及以上持续 1.5 秒进入防窥风险；恢复零人/单人持续 2 秒解除。采用时间防抖，切换时发送 P 或 S。
- 判定是“多人风险”，不能据此证明旁人正在偷窥；没有实现注视方向、遮挡恢复或动作意图识别。
- 人脸稳定识别 2 秒后，允许点击核验开锁按钮发送 R；不会看到人脸就自动开门。第二个人体或人脸出现时立即撤销开锁资格。
- 只有收到 U/D 才显示开锁确认。没有 K 闭锁回报时不会按 3 秒计时擅自显示已关门。
- 摄像头/推理结果过期会关闭人脸开锁入口，并在已连接时发送 P；画面恢复后重新同步 S/P。
- 摄像头、推理和录像分别运行；画面仅保留最新一帧，防止队列堆积。CPU 线程数默认 4，可在 config.json 调整。
- LBPH 没有活体检测；阈值 65 是初始参数，需用未参与训练的真人样本调试，不能把训练照自测当成准确率。

录入自己的脸：

~~~powershell
cd pc
..\.venv\Scripts\python.exe -X utf8 tools\enroll_face.py --name owner --camera 0
~~~

S 保存、Q 退出，每次只允许一张正脸。建议每人 10–20 张清晰照片，目录 known_faces/人员名称/*.jpg。重启主程序训练。原 konwn_faces 拼写已规范为 known_faces；原照片没有上传。

## 3. 胁迫报警与取证

默认 alarm_display = "silent"，适用于现场电脑可能被歹徒看到的情况。D 在现场表现与 U 一样；C 不显示；真实事件写入本地审计库并触发取证，不播放报警声音、不弹窗。

如果电脑仅由安保人员查看：

~~~powershell
python main.py --security
~~~

或在同一台电脑的另一个安保屏幕运行只读查看器：

~~~powershell
python security_monitor.py
python security_monitor.py --demo
~~~

查看器会标红 D/C，对启动后新收到的敏感事件弹出非模态窗口；历史事件保留在列表。这个工具只读本地数据库，没有实现跨电脑推送、短信、拨号或固定手机号通知。不要把 SQLite WAL 数据库直接当成网络服务使用；后续手机/远程报警需要单独的服务端与消息通道。

U 抓拍一张；L 计划抓拍五张，并启动事件录像；D/C/A 启动事件录像。没有画面仍保留报警日志，绝不生成虚假照片。事件录像从触发时刻开始，默认 15 秒，没有事前回溯录像。

continuous_recording 设 true 后开启持续分段录像，可作为滚动监控。默认 60 秒一个 MJPG/AVI 文件，按 UTC+8 命名。滚动录像达到一天或 2 GiB 限额时优先删除最旧的已关闭分段；单个正在写入的分段可能暂时超出配额。事件视频也位于此滚动池，会被同样清理，重要视频应及时另存。日志记录视频路径，但清理后路径可能已失效。

照片和数据库单独保留，不受上述 2 GiB 限额约束，需人工归档。磁盘不足 256 MiB 时暂停录像并保留已有日志。离线、断电或摄像头异常时不承诺完整 24 小时取证。

## 4. 密码管理与 FPGA 边界

演示模式初始常规密码 123456、胁迫密码 654321，支持 6–16 位输入，包含连续真密码即可开锁；两种都包含时胁迫优先。三次错误锁 60 秒。演示密码仅存内存，重启恢复默认。

界面可分别修改 normal / duress，需输入当前常规密码，并二次确认新密码。密码固定六位，不能相同。只有匹配请求编号的成功回执才显示修改完成；超时/掉线显示“结果未知”，请用实体键盘核验。密码不会写入审计日志。

真实模式默认禁用远程改密，因为已有单字节协议不能携带密码。队友完成扩展后，才将 extended_protocol 设 true。扩展设计见 ../docs/PC_FPGA_Protocol.md；当前 PC 的模拟通过不代表现有 RTL 已支持。

## 5. 配置与数据

config.json 包含摄像头编号、ROI、阈值、防抖、串口、报警显示、录像和路径设置。roi = [左, 上, 右, 下]，使用 0–1 相对坐标。也可建立被 Git 忽略的 config.local.json，仅覆盖部分配置：

~~~json
{"camera": 1, "serial_port": "COM5", "continuous_recording": true}
~~~

~~~powershell
python main.py --config config.local.json
~~~

相对文件路径始终相对此 pc 目录解析，不依赖终端当前目录。运行数据：

~~~text
data/
  live/              真实连接日志
  demo/              软件演示日志
    events.sqlite3   本地审计库
    evidence/        JPEG 照片
    recordings/      循环录像分段
~~~

现场导出 CSV 会排除敏感事件；安保模式导出包含敏感事件。数据库是本机普通文件，没有访问身份验证或加密，需用操作系统账户控制可见性。

## 6. 验证

~~~powershell
cd pc
python -X utf8 -m unittest discover -s tests -v
python -X utf8 tools/check_environment.py
~~~

测试覆盖防窥防抖、人脸时效、串口分包、胁迫静默、锁定、改密确认与超时、真实 JPEG/AVI 读写、串口回环。实测与未验证项目见 ../docs/PC_Test_Report.md。

接口资料：[Ultralytics 预测接口](https://docs.ultralytics.com/modes/predict/)、[OpenCV LBPH](https://docs.opencv.org/4.x/df/d25/classcv_1_1face_1_1LBPHFaceRecognizer.html)、[PySerial](https://pyserial.readthedocs.io/en/latest/pyserial_api.html)。外部依赖与预训练权重遵循各自许可。
