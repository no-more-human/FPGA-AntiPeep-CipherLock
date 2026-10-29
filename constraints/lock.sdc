# ==============================================================================
# 工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
# 约束文件: lock.sdc (Anlogic TD 50MHz 时钟与异步路径约束)
# ==============================================================================

# 1. 50MHz 系统主时钟约束 (周期 20.000ns)
create_clock -name clk_50M -period 20.000 -waveform {0.000 10.000} [get_ports {clk_50M}]

# 2. 外部异步输入信号 False Path (消除非同步时序分析)
set_false_path -from [get_ports {rst_n}]
set_false_path -from [get_ports {key_row[*]}]
set_false_path -from [get_ports {door_gpio}]
set_false_path -from [get_ports {voice_busy}]

# 3. 静态指示灯与人眼观察输出 False Path (人眼反应数十毫秒，无需纳秒级建立保持检查)
set_false_path -to [get_ports {led[*]}]

# 4. 外设慢速总线输出延时松弛约束
set_output_delay -max 10.000 -clock clk_50M [get_ports {seg_out[*] seg_cs[*]}]
set_output_delay -max 10.000 -clock clk_50M [get_ports {key_col[*]}]
set_output_delay -max 10.000 -clock clk_50M [get_ports {buzzer_out}]
set_output_delay -max 10.000 -clock clk_50M [get_ports {voice_tx}]
# 5. Day7 新增 UART 引脚约束
set_false_path -from [get_ports {uart_rx}]
set_false_path -from [get_ports {sw_recovery}]
set_output_delay -max 10.000 -clock clk_50M [get_ports {uart_tx}]
