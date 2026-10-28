# 自己调试后，怎样通过 Fork 提交代码

根据你提供的截图，你已经有原仓库的 Fork。可以在自己的 Fork 上传，再发 Pull Request 给 no-more-human/FPGA-AntiPeep-CipherLock；这个流程不要求先成为原仓库的 collaborator。截图显示该 Fork 落后原仓库四次提交，因此先同步。

## 先自己调试

本机完整工程目录：

C:\Users\sbc-2\Documents\Codex\2026-10-28\wo-m\outputs\FPGA-AntiPeep-CipherLock

进入 pc 文件夹：

1. 双击 run_demo.bat。不开摄像头、不连接硬件，先测试密码、日志和改密。
2. 关闭刚才的主窗口，再双击 run_camera_demo.bat。真实摄像头配合模拟 FPGA，测试人数、人脸和抓拍录像。
3. 保持演示主窗口开着，再双击 run_security_viewer_demo.bat。在第二个窗口查看真实 D 报警；它不另开摄像头。
4. 如果提示缺少依赖，先运行 setup_pc.bat，结束后重新启动。它使用仓库根目录独立 .venv。
5. run_camera.bat 是正式串口模式。等 FPGA 组接上 UART 后再用于实物联调。

在“模拟验收”页输入数字后，点“模拟按 # 提交”。先保持单人环境：

| 目的 | 输入示例 | 期望 |
| --- | --- | --- |
| 正常开锁 | 123456 | 显示已开锁，记录正常事件 |
| 虚位开锁 | 88912345666 | 同样正常开锁 |
| 胁迫开锁 | 9965432188 | 现场显示正常开锁，安保查看器出现报警 |
| 密码错误 | 000000 | 错误记录 |
| 暴力锁定 | 连续三次 000000 | 锁定 60 秒，普通密码暂不可用 |
| 锁定中胁迫 | 654321 | 模拟器仍允许胁迫开锁 |

先做正常/胁迫测试，再做三次错误测试，以免锁定影响后续操作。模拟器关闭重开会恢复初始密码及状态；界面里的单字节事件按钮用于注入测试事件，不能代替模拟器自己的计时和密码逻辑。

密码管理：normal 是常规密码，duress 是胁迫密码。当前常规密码初始为 123456，分别填写旧密码、新六位数字、再次确认。两类密码不能相同。修改后在模拟验收中试新旧密码；重启会恢复默认。

摄像头演示里，多人持续 1.5 秒进入防窥；恢复零人/单人持续 2 秒解除。若多人的状态下普通密码被挂起，应先恢复单人；胁迫通道仍保留。人脸开锁按钮需单张白名单人脸稳定 2 秒才可点击。没有活体检测，不能当作商业人脸门禁。

双击 run_security_viewer_demo.bat 后，再触发胁迫事件，查看器才会对新报警弹窗；启动前的报警在历史列表里标红。没有摄像头的演示只能验证事件和界面，不能产生真实抓拍。演示数据在 pc/data/demo/。

完整说明见 pc/README.md；硬件待办见 docs/PC_FPGA_Protocol.md；验证范围见 docs/PC_Test_Report.md。

## 网页上传：适合你现在的 Fork

1. 在 GitHub 打开你自己的 Fork，确认登录的是你自己的账号。
2. 点击 Sync fork → Update branch，同步原仓库的新提交。出现冲突时先解决冲突，不选择丢弃自己的改动。
3. 点击 main 分支下拉框，输入一个新分支名，例如 pc-vision，选择创建分支。
4. 解压 PC_代码提交包.zip。新版包里只有新增 pc/ 和 docs/ 文档，不含现有根目录文件。
5. 在 GitHub 仓库根目录点击 Add file → Upload files，把解压后的 pc 和 docs 文件夹拖进去。预览路径应是 pc/main.py、pc/modules/...、docs/PC_FPGA_Protocol.md 等。
6. 核对没有人脸照片、权重、录像、数据库、.venv、.git 或缓存。网页上传不会按你本机的 .gitignore 自动筛掉文件，因此只用干净的提交包。
7. 提交到 pc-vision，提交说明可写 Add PC vision and monitoring application。包中的 Python 应用有自己的 requirements 和 .gitignore，不必覆盖朋友的根目录依赖文件。
8. 到原仓库 Pull requests → New pull request → compare across forks。base 选 no-more-human/FPGA-AntiPeep-CipherLock 的 main；head 选你自己的 Fork 的 pc-vision。
9. 检查差异只有 PC 代码和文档，填写说明，点击 Create pull request，请朋友审核。朋友合并后，原团队仓库才包含你的代码。

不要把 ZIP 文件本身上传成代码；不要把整个旧工程拖到网页覆盖同步后的新工程。根 README 的 PC 入口、根 requirements 和 .gitignore 的合并可作为之后的小改动单独提交。

## 本地 Git/GitHub Desktop 的注意事项

本地完整工程目前 origin 指向朋友的原仓库，不是你的 Fork。直接点击 Push/Publish 不一定能推到你自己的仓库，也不一定有原仓库写权限。

如果使用 GitHub Desktop，较清楚的做法是先克隆你自己已同步的 Fork，在它里面建 pc-vision 分支，再复制干净提交包中的 pc/ 和 docs/，检查 Changes 后提交并推送。此时本地目录与远程 Fork 对应，操作更容易理解。

本地补全工程还有根 README、requirements.txt 和 .gitignore 的少量集成改动；这些不在新版网页提交包中。它们可以之后按差异合入，不要直接覆盖朋友继续更新的版本。

参考：[同步 Fork](https://docs.github.com/en/pull-requests/how-tos/work-with-forks/syncing-a-fork)、[网页上传文件](https://docs.github.com/en/repositories/working-with-files/managing-files/adding-a-file-to-a-repository)、[从 Fork 发起 Pull Request](https://docs.github.com/en/pull-requests/how-tos/create-pull-requests/creating-a-pull-request-from-a-fork)。
