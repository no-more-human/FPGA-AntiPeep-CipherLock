# ==============================================================================
# 一键下载比特流至安路 EG4S20 板卡 (JTAG 模式)
# 执行方式: D:\TD\bin\td_commands_prompt.exe tools/download.tcl
# ==============================================================================
open_project lock.al
puts "[INFO] Connecting to JTAG Cable and Programming lock.bit..."
download -bit lock_Runs/phy_1/lock.bit -mode jtag -spd 7 -sec 64 -cable 0
puts "[INFO] Programming complete!"
exit
