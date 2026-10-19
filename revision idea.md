# Revision Ideas —— 代码审阅与修改建议清单

> **文档性质**：审阅建议文档。**本文件只描述"想改什么、为什么改、怎么改"，没有修改任何一行源码。**
> **审阅对象**：`F:\FPGA` 当前工作区（Day 1 ~ Day 4 交付状态）
> **审阅方式**：逐行静态审查 + 仓库内已有的安路 TD 综合/布局布线日志
> **未能执行的部分**：本次审阅环境下 sandbox 无法在 `F:\FPGA` 上取得写权限（`SetNamedSecurityInfoW failed (Win32 5): grantWrite(F:\FPGA)`），因此**没有实际跑综合、仿真或 lint**，所有结论均为静态分析 + 日志证据，未做实测验证。文中凡属"推测"处均已标注。

---

## 0. 一句话总结

骨架是对的，能综合、能出比特流（1688 LUT / 8.61%、257 FF、33 IO），后续叠加 UART / 舵机 / 语音资源毫无压力。但 Day 5 之前有 **4 个 P0 级问题**（其中 2 个会直接导致上板失败或硬件风险），以及**验证几乎空白**这一根本隐患。建议顺序：**先修 P0 + 补三条主线的 testbench，再往上叠新模块**。

---

## 1. 证据索引

审阅时引用的关键证据（都在仓库里，可复核）：

| 证据 | 位置 | 内容 |
|---|---|---|
| 综合警告 | `lock_Runs/syn_1/td_20261019_005418.log:170` | `HDL-5007 WARNING: net 'init_rom' does not have a driver in ../../rtl/oled_driver.v(499)` |
| 综合警告 | `lock_Runs/syn_1/td_20261019_005418.log:171` | `HDL-5001 WARNING: Contains anonymous inst(s) and/or net(s) that have not been renamed` |
| 无时序约束 | `lock_Runs/phy_1/td_20261019_005504.log:237 / 341 / 426` | `TMR-5001 WARNING: No sdc constraints found while initiating timer.`（出现 3 次，综合/布局/布线各一次） |
| 面积报告 | `lock_Runs/phy_1/lock_phy.area:11-27` | LUT 1688 (8.61%)、REG 257 (1.31%)、**DSP 1**、BRAM 0、PLL 0 |
| 时钟资源 | `lock_Runs/phy_1/lock_phy.area:31` | 单一 clock net `clk_50M_dup_1`，fanout 192（单时钟域，做法正确） |
| 构建路径 | `lock_Runs/syn_1/test_syn.tcl:2,5` | `open_project lock.prj` + `read_adc ../../lock.adc` |
| 构建路径 | `lock_Runs/syn_1/lock.prj:11-88` | 写死 8 个 `.v` + 1 个 `.adc` 的**副本**（非符号链接） |

---

## 2. 优先级总览

| 级别 | 编号 | 一句话 | 不改的后果 |
|---|---|---|---|
| **P0** | A | OLED 初始化表用 `initial` 块 | 屏可能永远不亮，且无报错可循 |
| **P0** | B | `oled_sda` 推挽输出 + ACK 位主动驱高 | 从机应答时双端对驱，电气风险 |
| **P0** | C | 全工程无 `.sdc` 时序约束 | P&R 不按 50MHz 收敛；报告/答辩无时序数据 |
| **P0** | D | 蜂鸣器 `% 200` 占掉唯一的 DSP | 浪费资源 + 长组合路径 |
| **P1** | E | I2C 请求只高 1 拍，靠重试对齐 `scl_tick` | 改 `SCL_DIV` 为偶数即永久卡死 |
| **P1** | F | OLED 每字节一次 Start/Stop，整屏 ~160ms | 按键后屏幕滞后 0.16s |
| **P1** | G | 位数不足按 `#` 也计一次错误 | 误触 3 次锁 60s，演示尴尬 |
| **P1** | H | 机械复位键直连异步复位，无同步器/无 POR | 复位释放沿亚稳态；不按键时无上电复位 |
| **P1** | I | `duress_alarm` 只有 3s 且无粘滞 | Day 10 接 UART 时字符抓不住 |
| **P1** | J | `tb_safe_fsm` 声称 7 项实测 3 项 | 锁定/开锁主线零覆盖 |
| **P1** | K | `tb_top` 空跑 1µs | 无集成回归，改一处崩一处 |
| **P2** | L | 两条构建路径并存，`lock.prj` 是过期副本 | Day 8 加 `uart.v` 静默漏文件 |
| **P2** | M | `lock.adc` 双份 | 改错文件 |
| **P2** | N | `timescale` 重复；`tick_100` 未使用 | 观感/警告 |
| **P2** | O | README 与 `top.v` 的 LED 定义漂移 | 评审被抓 |
| **P2** | P | `lock_ones` 依赖 4 位乘法截断 | 可读性差（功能正确，见 §5） |

---

## 3. P0 级修改建议（上板前必须处理）

### P0-A　OLED 初始化命令表改用 `case` 函数，不要用 `initial`

**位置**：`rtl/oled_driver.v:498-528`，使用点 `rtl/oled_driver.v:561`

**现状**

```verilog
// 经典初始化命令序列 (27个字节)
reg [7:0] init_rom [0:26];
initial begin
    init_rom[0]  = 8'hAE;   // 关闭显示
    ...
    init_rom[26] = 8'hAF;   // 开启显示！
end
// ...
i2c_data <= init_rom[cmd_idx];
```

**原因（为什么想改）**

1. TD 综合日志明确报了 `HDL-5007 WARNING: net 'init_rom' does not have a driver`——说明综合器把这个数组当成"没有驱动源的网络"。它有可能仍然把初值当常量折叠掉，**也有可能直接归零**。
2. 这是**不可证明**的一类写法：它没有 RTL 仿真层面的问题（仿真器一定读 `initial`），所以你的 testbench 永远测不出问题；只有上板看到"屏全黑/屏不亮"才知道，而那时你会先去怀疑接线、供电、地址、上拉，排查成本极高。这是典型"仿真过、上板死"的坑。
3. 同一文件里的 `oled_font.v` 用的是 `case` 纯组合查找表，TD 处理得干干净净。**同一个工程里没必要两种风格**，统一到 `case` 即可彻底消除该不确定性。
4. 按 Day 5~6 的排期，OLED 是你后面反复要用的调试窗口（语音状态、门磁状态都要靠屏看）。这个坑如果不除，会在你调语音/舵机的时候反复诈尸，且每次都会误导你把问题归到别处。
5. 从功耗/资源角度看两者等价（都是常量折叠成 LUT 或直接生成常数），没有性能损失。

**建议改法**（删掉 `reg [7:0] init_rom [0:26];` 与 `initial` 块，换成函数）

```verilog
// 经典初始化命令序列 (27 个字节)，用纯组合 case 实现，保证 100% 可综合
function [7:0] oled_init_cmd(input [4:0] idx);
    case (idx)
        5'd0 : oled_init_cmd = 8'hAE; // 关闭显示
        5'd1 : oled_init_cmd = 8'h00; // 列低 4 位
        5'd2 : oled_init_cmd = 8'h10; // 列高 4 位
        5'd3 : oled_init_cmd = 8'h40; // 起始行
        5'd4 : oled_init_cmd = 8'hB0; // 起始页
        5'd5 : oled_init_cmd = 8'h81; // 对比度控制
        5'd6 : oled_init_cmd = 8'hCF;
        5'd7 : oled_init_cmd = 8'hA1; // 段重映射
        5'd8 : oled_init_cmd = 8'hA6; // 正常显示
        5'd9 : oled_init_cmd = 8'hA8; // 多路复用比
        5'd10: oled_init_cmd = 8'h3F; // 64 MUX
        5'd11: oled_init_cmd = 8'hC8; // COM 扫描方向
        5'd12: oled_init_cmd = 8'hD3; // 显示偏移
        5'd13: oled_init_cmd = 8'h00;
        5'd14: oled_init_cmd = 8'hD5; // 时钟分频
        5'd15: oled_init_cmd = 8'h80;
        5'd16: oled_init_cmd = 8'hD9; // 预充电周期
        5'd17: oled_init_cmd = 8'hF1;
        5'd18: oled_init_cmd = 8'hDA; // COM 引脚硬件配置
        5'd19: oled_init_cmd = 8'h12;
        5'd20: oled_init_cmd = 8'hDB; // VCOMH
        5'd21: oled_init_cmd = 8'h40;
        5'd22: oled_init_cmd = 8'h20; // 内存寻址模式
        5'd23: oled_init_cmd = 8'h02; // 页寻址模式
        5'd24: oled_init_cmd = 8'h8D; // 电荷泵启用
        5'd25: oled_init_cmd = 8'h14;
        5'd26: oled_init_cmd = 8'hAF; // 开启显示
        default: oled_init_cmd = 8'h00;
    endcase
endfunction
```

使用点改为：

```verilog
i2c_data <= oled_init_cmd(cmd_idx);
```

**验收方法**

1. 重新综合，确认 `HDL-5007` 关于 `init_rom` 的警告消失（`HDL-5001` 匿名网络警告可能仍在，属无害）。
2. 用 Icarus 单独仿 `oled_driver`，在 SDA 上抓波形，确认前 27 个数据字节依次为
   `AE 00 10 40 B0 81 CF A1 A6 A8 3F C8 D3 00 D5 80 D9 F1 DA 12 DB 40 20 02 8D 14 AF`。

---

### P0-B　`oled_sda` 改为开漏（三态）输出

**位置**：`rtl/oled_driver.v:27`（端口）、`:96-97`（IDLE）、`:122`（发位）、`:140 / 172 / 204`（ACK 位释放）、`:220-233`（STOP）

**现状**

```verilog
output reg oled_sda,   // 推挽输出
...
oled_sda <= 1'b0;      // START
oled_sda <= 1'b1;      // ACK 位“释放总线”——实际是把线主动驱高
oled_sda <= shift_reg[7];  // 数据位，1 也是主动驱高
```

**原因（为什么想改）**

1. I2C 是**开漏总线**。ACK 那一拍从机（SSD1306）要把 SDA 拉低应答，而你的 FPGA 此刻正用 8mA 驱动强度把 SDA **主动推高**——两个器件同时在驱同一根线，形成对驱（contention）。电压上"低者胜"，所以功能看起来正常，但这一拍的电流路径是 `FPGA 输出 PMOS → 从机 NMOS → GND`。这不是"风格问题"，是会让引脚/屏长期发热、极端情况下损坏的电气隐患。
2. 你现在为了"释放"而写 `1'b1`，语义上其实是"我把线拉高"，而不是"我不驱动"。反过来，正因为是推挽，你也**没法读 ACK**，所以现在整条 I2C 是"发了就不管"的开环控制——屏没接、地址错、初始化失败，FPGA 全都不知道（见 P2 的一条附带建议）。
3. 改成开漏是**低风险高收益**：约束文件 `lock.adc:38` 已经给 `oled_sda` 配了 `PULLTYPE = PULLUP`（内部弱上拉），OLED 模块板上通常还有 4.7kΩ 上拉，所以放开高阻后线仍能可靠拉高。
4. 顺手就能把 ACK 读进来，给"屏没接好"提供一个硬件级的自检信号——这对现场答辩很重要（接线松了能一眼看出是屏的问题还是逻辑的问题）。

**建议改法（推荐：`inout` + 三态赋值）**

```verilog
// 端口
inout  wire oled_sda,      // 改为双向，开漏语义

// 内部逻辑
reg  sda_drive_low;        // 1: 主动拉低(输出 0)  0: 释放(高阻，由上拉拉高)
assign oled_sda = sda_drive_low ? 1'b0 : 1'bz;
```

然后 I2C 状态机里**所有** `oled_sda <= x` 都替换为 `sda_drive_low <= ~x`：

| 位置 | 原写法 | 新写法 |
|---|---|---|
| `:84-85` 复位 | `oled_sda <= 1'b1;` | `sda_drive_low <= 1'b0;` |
| `:96-97` IDLE | `oled_sda <= 1'b1;` | `sda_drive_low <= 1'b0;` |
| `:106` START_1 | `oled_sda <= 1'b0;` | `sda_drive_low <= 1'b1;` |
| `:122 / 155 / 187` 发位 | `oled_sda <= shift_reg[7];` | `sda_drive_low <= ~shift_reg[7];` |
| `:140 / 172 / 204` ACK | `oled_sda <= 1'b1;` | `sda_drive_low <= 1'b0;` |
| `:221` STOP_1 | `oled_sda <= 1'b0;` | `sda_drive_low <= 1'b1;` |
| `:233` STOP_3 | `oled_sda <= 1'b1;` | `sda_drive_low <= 1'b0;` |

**可选附带改动（读 ACK，做开环闭环）**：在 ACK 状态的第二个半步（`scl_phase==1` 撤 SCL 之前那拍）采样 `oled_sda`，若为高则置 `ack_error` 标志；把这个标志引到 `top.v` 的一个 LED 上（比如 `led[7]`），现场就能一眼判断"屏没应答"。

**最小改动方案（如果暂时不想改端口方向）**：保留 `output reg oled_sda`，只把"释放/驱高"的那几处从 `1'b1` 改成 `1'bz`，数据位改成 `shift_reg[7] ? 1'bz : 1'b0`。TD 对输出端口的三态赋值会综合成带使能的输出缓冲，同样能消除对驱，只是这样**读不到 ACK**。

**验收方法**

1. 综合后检查 `lock_phy.area` 的 IO 报告里 `oled_sda` 是否变成三态/带 OE 的输出（`#IO` 统计或 pin 报告里 Direc 信息会体现）。
2. 上板后示波器/逻辑分析仪抓 SDA：ACK 位期间电平应直接被从机拉低，SDA 上升沿变缓（RC 上拉）而非硬推。
3. OLED 显示功能应与改前完全一致。

---

### P0-C　补充 `.sdc` 时序约束

**位置**：`lock.al:78-87`（当前 Constraint Set 只有 `.adc`），`constraints/` 目录下无 `.sdc`

**现状**：phy 日志中 `TMR-5001 WARNING: No sdc constraints found while initiating timer.` 出现 **3 次**（综合、布局、布线各一次）。

**原因（为什么想改）**

1. 没有任何 `create_clock`，意味着布局布线器**根本不知道有个 50MHz 时钟要收敛**。它现在"能跑"只是因为设计太松（8.61% 占用、最长路径估计也就十几级 LUT）。一旦 Day 8 接上 UART（115200 波特率下有状态机 + 采样计数），或者以后有人把时钟提到 100MHz，你会拿到一个"综合通过、上板偶发错"的工程，且没有任何报告能告诉你时序有没有收敛。
2. `plan.md` Day 16 明确写了要交付「**时序收敛报告与最大工作频率 Fmax**」。**没有 `.sdc` 就生成不了 setup/hold 报告，也就出不了 Fmax** —— 这是路线图里一条实打实的交付物，现在缺支撑。
3. 竞赛评审看"FPGA 硬件安全/高可靠"时，很可能会问"你的时序怎么收敛的、Fmax 多少"。这个问题现在答不了。
4. 成本极低：一个文件、几行约束。

**建议改法**：新建 `constraints/lock.sdc`，加入工程的 Constraint Set（TD 中 `Project → Add Source` 或在 Constraint Set 里加 SDC 文件）。

```tcl
# 50MHz 主时钟
create_clock -name clk_50M -period 20.000 -waveform {0.000 10.000} [get_ports {clk_50M}]

# 机械按键 / 复位：外部异步信号，不参与建立保持检查
set_false_path -from [get_ports {key_row[*]}]
set_false_path -from [get_ports {rst_n}]

# 输出到板载/外设器件，给宽松的输出延时即可
set_output_delay -max 10.000 -clock clk_50M [get_ports {seg_out[*] seg_cs[*] key_col[*] led[*]}]
set_output_delay -max 10.000 -clock clk_50M [get_ports {oled_scl oled_sda buzzer_out}]
```

> ⚠️ **语法待确认**：上面是标准 SDC 写法，但安路 TD 5.6 是否支持全部命令、`get_ports` 通配符的具体写法需要对照 TD 的《Timing Constraints》手册确认（这个我无法在当前环境实测）。建议做法：先在 TD 里手工跑一次 `Report Timing`，看它生成的模板，再把模板里确认可用的命令抄回来。**具体命令可以有偏差，但"必须有 `create_clock` 和时序报告"这个结论是确定的。**

**验收方法**

1. 综合/布线日志里 `TMR-5001` 警告消失。
2. 生成 `lock_Runs/phy_1/*.timing` 或时序报告，确认 setup/hold 全 pass，并记下 `Fmax`。
3. 把 `Fmax` 数值写进 README 的 Day 4 交付项和 `plan.md` Day 16 的交付物。

---

### P0-D　蜂鸣器 `% 200` 替换为自由计数器

**位置**：`rtl/buzzer_driver.v:102-106`

**现状**

```verilog
S_LOCK: begin
    // 4kHz 间歇脉冲报警: 100ms 鸣响, 100ms 静音交替
    target_half_cnt <= HALF_CNT_4KHZ;
    tone_en         <= ((duration_cnt % 200) < 100);
end
```

**原因（为什么想改）**

1. 面积报告 `lock_phy.area:17` 显示 **`#dsp 1`**。整个设计里唯一像乘除法运算的就是这一句 `duration_cnt % 200`（其余 `lock_tens * 4'd10` 是 4 位常数乘法，通常走 LUT），所以这个 DSP 基本可以确定是它吃掉的。12 位取模对综合器来说是个"常数除法器"，会展开成一串比较/减法甚至乘法器。
2. 除了占资源，更重要的是**组合路径长**：`duration_cnt % 200` 是纯组合逻辑，结果又要参与 `tone_en` 的比较，这条路径必然是你这个设计里最深的一条之一。目前因为没约束（见 P0-C）所以没人管，但一旦加了 `create_clock`，它很可能就是 critical path。
3. 这段逻辑本质上只需要一个"0~199 循环的毫秒相位"，用一个 8 位计数器即可，**逻辑量从"除法器"降到"一个加法器 + 一个比较器"**。
4. 顺带的好处：语义更清楚——现在的 `% 200` 要靠读者自己算"1200ms 里 100ms 响 100ms 停"。

**建议改法**

```verilog
reg [7:0] lock_phase;   // 0~199 循环相位：<100 鸣响，>=100 静音

// 触发时（beep_lock 分支）
lock_phase <= 8'd0;

// 计时分支里的 S_LOCK
S_LOCK: begin
    target_half_cnt <= HALF_CNT_4KHZ;
    tone_en         <= (lock_phase < 8'd100);
    if (lock_phase >= 8'd199) lock_phase <= 8'd0;
    else                      lock_phase <= lock_phase + 8'd1;
end
```

**验收方法**

1. 重新综合后 `lock_phy.area` 里 `#dsp` 应为 **0**。
2. 上板听感：1.2 秒内应有 6 组"响 100ms / 停 100ms"的急促报警，与改前一致。
3. 补 `.sdc` 后看 `Report Timing`，确认 deepest path 不再是蜂鸣器。

---

## 4. P1 级修改建议（影响健壮性 / 演示体验，建议本周内）

### P1-E　I2C 请求改为"保持到被确认"，不要靠重试对齐（**这条最隐蔽，建议优先看**）

**位置**：`rtl/oled_driver.v:33`（`SCL_DIV`）、`:54`（`i2c_req`）、`:93-101`（采样点）、`:558 / 576 / 602`（三处发起）

**现状梳理**

- `SCL_DIV = 125`，`scl_tick` 每 125 个时钟高 **1 个时钟**（2.5µs）。
- 控制侧 `i2c_req <= 1'b1;` 之后，下一拍被顶部的 `i2c_req <= 1'b0;` 清掉——**这个请求信号只高 1 个时钟（20ns）**。
- I2C 引擎只在 `if (scl_tick)` 里、`I2C_IDLE` 状态下采样 `i2c_req`。
- 也就是说：请求是 20ns 的脉冲，采样窗口是每 2.5µs 开一次。控制侧靠 `!i2c_busy && !i2c_req` 每 **2 拍**重试一次，直到某一次恰好落在 `scl_tick` 那一拍上被吃掉。

**原因（为什么想改）**

1. **现在能跑，纯属 `SCL_DIV = 125` 是奇数的巧合。** 重试节拍固定为 2 拍一次，`scl_tick` 每 125 拍（奇数）来一次，两个相位一定会相遇，最多等 2.5µs。**如果把 `SCL_DIV` 改成任何偶数（比如 250 = 100kHz、或 62 = 400kHz），两个相位会恒定错开，`i2c_req` 永远采不到，第一次发字节就永久卡死在 `I2C_IDLE`——现象是"屏全黑"。**
2. 更危险的是：`rtl/oled_driver.v:31` 的注释写的是「`50MHz / 250 = 200kHz`」，而代码是 `SCL_DIV = 125`。**注释和代码已经漂移了**。哪天有人"顺手把注释对齐"、或者想"按注释改成 250"，就会直接踩中上面这个死锁。这是典型的"注释里埋着地雷"。
3. 这种"短脉冲 + 低频采样 + 重试"的结构，在仿真里也极难复现问题（取决于相位），属于必须从结构上消除的隐患，而不是加注释能解决的。
4. 同源问题：`i2c_done`（`:59`）声明了、赋值了，但**没有任何地方使用**——说明这里本来想做一个握手，做到一半放弃了。改成正式握手正好把这个信号用起来。

**建议改法（保持请求直到引擎接手）**

```verilog
reg i2c_req_hold;   // 请求保持位：置位后一直保持，直到引擎进入非 IDLE

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        i2c_req_hold <= 1'b0;
    end else if (!i2c_busy && !i2c_req_hold) begin
        i2c_req_hold <= 1'b1;        // 空闲时发起
    end else if (i2c_busy) begin
        i2c_req_hold <= 1'b0;        // 引擎已接管（i2c_state != IDLE）
    end
end
```

I2C 引擎侧保持原样即可（`if (i2c_req_hold) i2c_state <= I2C_START_1;`，在 `scl_tick` 那一拍采样），因为现在信号会一直保持，不存在漏采样。

同时把 `SCL_DIV` 的注释改成与代码一致：

```verilog
localparam SCL_DIV = 125;   // 半周期 125 个时钟 @50MHz → 2.5us → SCL = 200kHz
```

**验收方法**

1. 单独仿 `oled_driver`，把 `SCL_DIV` 临时改成 2（仿真加速）和 4（偶数）各跑一遍，**改前：偶数必挂；改后：两者都能完整发完 27 条初始化命令 + 1024 字节。** 这是这条改动最直接的证据。
2. 上板确认 OLED 正常显示。

---

### P1-F　OLED 每页一次事务，而不是每字节一次 Start/Stop

**位置**：`rtl/oled_driver.v:601-621`（`S_DATA_SEND`）

**现状**：每个字节都完整走 `START + 0x78 + Control + Data + STOP`。

**原因（为什么想改）**

1. I2C 事务开销占了大头：一个字节真正有价值的是 8 位数据，但每字节要额外付 2 字节（从机地址 + 控制字）+ Start + Stop。粗算每字节约 `3×9×2 + 6 ≈ 61` 个 `scl_tick`（≈152µs），一页 128 字节 ≈ 19.8ms，**8 页整帧 ≈ 160ms**。
2. 这直接体现为**交互手感**：用户按一个键，OLED 上的 `*` 最多要 0.16 秒后才出现。评审现场演示"输入密码"时，这个滞后是看得见的。
3. SSD1306 的页寻址模式**本来就支持一次写入整页**：发一次 `0x40` 控制字，后面连续灌 128 个数据字节，页内列地址自动递增。所以这是"没用上芯片能力"，不是"没优化"。
4. 改完每字节只需 `9×2 = 18` 个 tick，一页 ≈ 4.6ms，**整帧 ≈ 55ms**，快约 3 倍；如果同时把 SCL 提到 400kHz，整帧可以压到 ≈ 15ms。

**建议改法（结构改动，是本清单里最大的一处，可以评估后排期）**

1. I2C 引擎的 `I2C_DATA_ACK` 之后，不要无条件 `I2C_STOP_1` 或回 `I2C_IDLE`，而是判断"本事务是否还有后续字节"：
   - 有 → 回到 `I2C_DATA_BYTE`（`shift_reg <= next_data`，连续 SCL，中间不发 Start/Stop）；
   - 无 → 发 STOP。
2. 引擎增加两个端口语义：`i2c_burst`（本次事务是否发送多字节）、`i2c_last_byte`（当前是否最后一个字节，由外部给）。
3. 控制侧 `S_DATA_SEND` 改为：先发 `0x78 + 0x40`（一次性），然后用 `byte_cnt[6:0]` 从 0 数到 127，每字节只驱动 `i2c_data` 和 `i2c_last_byte`。

**如果时间紧，可以只做这个廉价版**：保持结构不动，把 `SCL_DIV` 从 125 降到 62（SCL ≈ 400kHz，SSD1306 数据手册上限），整帧立刻减半到 ≈80ms；**但必须先把 P1-E 修掉**，否则改 `SCL_DIV` 会直接卡死。

**验收方法**：逻辑分析仪/示波器数一次 `S_PAGE_SET` 到 `S_PAGE_SET` 的间隔；或仿真里用 `$time` 量一页的耗时，目标 ≤5ms（单页）/ ≈55ms（整帧）。

---

### P1-G　位数不足 6 位时按 `#` 不应计入错误次数

**位置**：`rtl/safe_fsm.v:160-163`（发 `#`）、`:205-219`（`pwd_len != 6` 分支）

**现状**

```verilog
end else if (key_val == 4'hF) begin
    // '#' 键: 确认比对
    beep_key <= 1'b1;
    state    <= S_CHECK;
end
// ... S_CHECK 里：
end else begin           // 位数不足 6 位按确认，判定为输入错误
    if (err_count >= 2'd2) begin ... S_LOCKED ... end
    else begin err_count <= err_count + 2'd1; ... end
end
```

**原因（为什么想改）**

1. 现在的行为是：**误触 3 次 `#` 就锁 60 秒**。演示/答辩现场，评委或你自己手快按错一次方向、或者键盘接触不良多弹一个 `#`，就会当场锁机——这是"演示事故"的高发点，而且有 60 秒的不可恢复惩罚。
2. 从 UX 逻辑上讲，用户按 `#` 时若只输了 2 位，通常是"还没输完就想确认"或"误触"，此时**给提示、不计惩罚**才是行业惯例（银行 ATM、密码锁都是这样）。
3. 这条改动**几乎零成本**，收益是演示稳定性。

**建议改法（方案 A，推荐）**

```verilog
end else if (key_val == 4'hF) begin
    // '#' 键: 只有满 6 位才进入比对；不足 6 位给出提示但不计错误次数
    beep_key <= 1'b1;
    if (pwd_len == 3'd6) begin
        state <= S_CHECK;
    end
    // else: 保持 S_INPUT 不动，数码管/OLED 上已显示当前位数，用户自己看得出来
end
```

`S_CHECK` 里原有的 `pwd_len != 6` 分支保留作为安全网（理论上不再进入）。

**方案 B（如果竞赛规则要求"严格惩罚"）**：保留计错，但把限次从 3 次放宽，或在位数不足时只闪红灯不计数。**我推荐方案 A。**

**验收方法**：仿真里只按 3 个数字 + 连按 5 次 `#`，确认 `err_count` 仍为 0、`state_code` 仍为 1。

---

### P1-H　复位加"异步复位 + 同步释放"，并顺带获得上电复位

**位置**：`rtl/top.v:15`（端口）、`:42-49 / 58-69 / 85-105 / 110-121 / 126-136 / 141-152`（所有 `rst_n` 连接）

**现状**：机械按键 `rst_n`（E3）直接接到全部 7 个模块的异步复位端口。

**原因（为什么想改）**

1. **复位释放沿没有同步器**。机械按键松开的瞬间有毫秒级抖动，每个触发器的复位释放时刻会略有差异，理论上存在"部分寄存器先退出复位、部分还在复位"的窗口，可能产生一拍的异常状态（比如状态机跳到一个非预期编码）。目前没出问题是因为按复位键的人少；一旦 Day 5 之后加了语音/舵机，异常状态可能直接驱动舵机动一下。
2. **没有上电复位（POR）**。现在完全依赖"板子上电时 `rst_n` 为低"或用户手动按键。如果板子的复位键带上拉、上电不走低，那么所有寄存器靠 FPGA 的初始值（默认 0）——`state` 初始为 0 恰好是 `S_IDLE`，所以"碰巧"能用；但 `seg_cs` 的复位值是 `4'b1111`（全灭），而初始值 0 会让四位全亮——**这个差异说明初始值不等于复位值，只是没人上电不按键试过**。
3. 改成"异步复位、同步释放"是数字设计的标准做法，代码量极小，且**顺手就把 POR 解决了**（复位同步触发器上电为 0，两个时钟后自动释放）。
4. 对竞赛报告是加分项：可以写进"可靠性设计"章节。

**建议改法（在 `top.v` 里加，其他模块不用改）**

```verilog
// 异步复位、同步释放 + 上电复位
// 上电时两个 FF 初值为 0，2 个 clk 后 rst_sync_n 自动拉高，等效 POR；
// 按键按下时异步复位立即生效，松开时经 2 级同步后释放，消除亚稳态与抖动影响。
reg rst_meta;
reg rst_sync_n;

always @(posedge clk_50M or negedge rst_n) begin
    if (!rst_n) begin
        rst_meta   <= 1'b0;
        rst_sync_n <= 1'b0;
    end else begin
        rst_meta   <= 1'b1;
        rst_sync_n <= rst_meta;
    end
end
```

然后把 7 处例化的 `.rst_n (rst_n)` 全部换成 `.rst_n (rst_sync_n)`。

> 注意：`clk_tick` 本身也用 `rst_n`，也应换成 `rst_sync_n`；因为这些同步 FF 用的是原始 `clk_50M`，不存在循环依赖。

**验收方法**

1. 仿真：让 `rst_n` 在释放时带 5ms 抖动，确认 `rst_sync_n` 只在抖动结束后单一上升沿释放。
2. 上板：**不按复位键**直接上电，确认数码管进入 `IdLE`（而不是四个 8 或全亮）。

---

### P1-I　`duress_alarm` 改为粘滞锁存

**位置**：`rtl/safe_fsm.v:119`（S_IDLE 里清零）、`:184`（置位）、`:231`（S_SUCCESS 结束时清零）

**现状**：`duress_alarm` 只在 `S_SUCCESS` 的 3 秒窗口内为高，之后回 `S_IDLE` 就被清零。

**原因（为什么想改）**

1. Day 10 要把它接到 UART 发 `'D'`。现在的窗口只有 3 秒，而且**结束时机由 3 秒定时器决定，不是由 PC 确认决定**。如果那一刻串口正好在发别的（比如 `'U'`）、或者上位机在重连、或者帧被干扰，这次挟持事件就**永久丢失**了。
2. 反挟持是"一次都不能漏"的功能。丢失一次的后果在真实场景里是致命的，在竞赛评语里是"逻辑不严密"。
3. 粘滞锁存 + 显式清除是正确做法：事件一旦发生就一直亮着，直到上位机明确回 `'S'`（或专用清除指令）才复位。

**建议改法**

```verilog
// 输出改为锁存型
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        duress_alarm <= 1'b0;
    else if (duress_hit)            // S_CHECK 里匹配到 DURESS_PWD 那一拍
        duress_alarm <= 1'b1;
    else if (duress_clear)          // 新增输入，来自 UART 收到 'S' 或专用复位指令
        duress_alarm <= 1'b0;
end
```

需要新增一个输入端口 `duress_clear`（Day 8 接 UART 时由 `'S'` 指令驱动）。在移植前，也可以先接一个"按 `*` 键清除"的临时通路，方便现在就能验证。

**验收方法**：仿真中触发挟持密码，等 3 秒后确认 `duress_alarm` **仍然为高**；给一次 `duress_clear` 脉冲后确认拉低。

---

### P1-J　`tb_safe_fsm` 补齐缺失的 4 项测试

**位置**：`sim/tb_safe_fsm.v:6-13`（声称 7 项）、`:96-124`（实际 3 项）

**现状**：头注释列了 7 项测试，实际只实现了 TEST 1（单位输入）、TEST 2（退格）、TEST 3（输错一次进 ERROR），然后 `$finish`。**"连续输错 3 次锁定 60s"、"锁定期间按键无效"、"倒计时结束恢复"、"正确密码开锁"这 4 条一条都没测。**

**原因（为什么想改）**

1. 这 4 条恰好是这个项目的**核心卖点和核心逻辑**：锁定机制是"硬件安全"的叙事基础，开锁成功是演示主线。**主线逻辑零覆盖**，等于"这个工程没有被验证过"。
2. 你现在的 `tb_safe_fsm` 之所以能"过"，是因为它只测了最简单的路径。如果 `S_LOCKED` 里的倒计时或退出条件写错了（比如 `lock_countdown > 1` 少减一次、或 `err_count` 没清零），你**不可能从现有 tb 里发现**。
3. `tick_1k` 的周期是 120ns（`#(CLK_PERIOD*5)` 高 + `#(CLK_PERIOD)` 低），而非真 1kHz。用来加速仿真是对的，但**注释里必须写清楚**，否则后人会以为 1500ms 的定时器真的跑 1.5 秒。
4. 这是投入产出比最高的一条：**写 tb 花 1 小时，能挡住后面 3 天的调试噩梦**。

**建议补的测试（顺序即执行顺序）**

| 编号 | 激励 | 断言（期望） |
|---|---|---|
| T4 | 连输 3 次错误（每次 3 个 `9` + `#`） | 第 3 次后 `state_code == 3'd4`（LOCKED）、`err_count == 2'd3`、`lock_countdown == 7'd60` |
| T5 | 在 LOCKED 中连按 `1` `2` `3` `#` | `pwd_len` 保持 0、`state_code` 保持 4（按键被吞） |
| T6 | 等待 `LOCK_TIMEOUT_SEC` 个秒边界 | `state_code == 3'd0`（IDLE）、`err_count == 0`、`lock_countdown == 0` |
| T7 | 输入 `1 2 3 4 5 6` + `#` | `unlock_en == 1`、`state_code == 3'd2`（SUCCESS）、`beep_succ` 出现过一次脉冲 |
| T8 | 等 3 秒（3000 个 tick） | `unlock_en` 回 0、回 IDLE、`pwd_len == 0` |
| T9 | 输入 `6 5 4 3 2 1` + `#` | `duress_alarm == 1` 且 `unlock_en == 1`（表面开门） |
| T10 | 输 2 次错误 → 输 1 次正确 | `err_count` 被清零为 0 |

建议在 tb 里加一个"秒边界计数"辅助变量（数 `u_fsm.sec_tick_cnt` 从 999 回 0 的次数），避免用绝对时间去等，这样 `LOCK_TIMEOUT_SEC` 换值也不用改 tb。

---

### P1-K　`tb_top` 补成真正的集成回归

**位置**：`sim/tb_top.v:49-68`

**现状**：上电、释放复位、等 1µs、打印一句、`$finish`。**没有按键模型、没有断言、没有 `$dumpfile`**——它唯一能证明的是"能编译、能例化"。

**原因（为什么想改）**

1. 这个 tb 占了"顶层集成验证"的名额，但没做集成验证。随着 Day 5+ 不断增加模块，你**每次改动都没有回归防线**，只能靠上板试——上板一轮的成本（编译 + 烧录 + 接线 + 手动敲键）至少 5 分钟，且容易漏场景。
2. `sim/tb_keypad_scan.v` 里已经写好了**很好的键盘物理模型**（`key_col` → `key_row` 联动 + 按下/释放抖动），直接搬到顶层就能做端到端回归。
3. 顶层 tb 最大的价值在于能验证**模块之间的接线**（比如 `state_code` 编码是否和 `seg_display`/`oled_driver` 对齐、`beep_*` 是否真的接到了蜂鸣器），这类问题单元 tb 测不出来。

**建议改法（把 tb_keypad_scan 的键盘模型搬过来）**

```verilog
// 4x4 物理键盘模型：扫描到目标列时拉低对应行
reg [3:0] press_col, press_row;
reg       pressing;
always @(*) begin
    key_row = 4'b1111;
    if (pressing && key_col[press_col] == 1'b0)
        key_row[press_row] = 1'b0;
end

task press(input [1:0] c, input [1:0] r);
    begin
        press_col = c; press_row = r;
        pressing = 1'b1;
        #(2_000_000);   // 2ms 稳定压合（远大于 20ms 消抖？见下）
        ...
    end
endtask
```

> ⚠️ 注意：顶层例化的消抖是 **20ms**（`DEBOUNCE_TIME(20)`），比 `tb_keypad_scan` 里的 5 快很多，所以顶层 tb 必须按键**保持 ≥25ms** 才能被识别。仿真时间会拉长，建议先用 `TB_DEBOUNCE` 参数化，或者干脆给顶层加一个 `SIM` 宏把消抖调短——**这一点在写 tb 前必须先决定，否则你会以为是"按键没反应"。**

建议的顶层回归剧本（一条跑完）：

```
上电 → LED0 心跳 2 次跳变（验证 clk_tick + 心跳逻辑）
→ 数码管出现 "IdLE"（验证 seg_display 编码）
→ 敲 1 2 3 4 5 6 # → 数码管 "OPEn"、led[2] 亮、蜂鸣器有输出、OLED 继续刷新不卡死
→ 等 3 秒 → 回 "IdLE"
→ 敲 3 组错误 → 数码管 "L-60"、led[3] 亮
→ 敲任意键 → 数码管仍 "L-60"（键盘被吞）
→ 等到倒计时归零 → 回 "IdLE"
```

同时加上 `$dumpfile("sim_top.vcd")`。

---

## 5. 我确认"没问题、不要白改"的部分

写在这里，避免后人（或未来的你）在这些地方浪费时间去"修"：

| 项 | 位置 | 结论 |
|---|---|---|
| **锁定时长是准的 60 秒** | `rtl/safe_fsm.v:261-270` | 我按秒边界逐拍推演过：`lock_countdown` 从 60 递减到 1，每个值持续 1 秒，共 60 个秒边界，第 60 秒末退出。**不是 off-by-one**。它只是"永远显示不到 0"，这是显示习惯，不是 bug。 |
| **`lock_ones` 的 4 位乘法截断结果是正确的** | `rtl/seg_display.v:86`、`rtl/oled_driver.v:279` | `lock_countdown - (lock_tens * 4'd10)` 中 `lock_tens*10` 会截断成 4 位（模 16），但 `(N - 10t) mod 16 = N - 10t`（因为个位数 < 10 < 16），所以**结果在 0~60 范围内恒等于个位，功能完全正确**。只是可读性差，见 P2-P。 |
| **I2C 位时序（数据在 SCL 低电平期间变化）是对的** | `rtl/oled_driver.v:119-134` | `oled_sda` 只在 `scl_phase==0`（SCL=0）那一拍更新，SCL 上升沿时数据已经稳定了半个周期。**不需要改。** |
| **键盘 4ms 扫描 / 20ms 消抖的组合够用** | `rtl/keypad_scan.v:36-59, 116-179` | 扫描 4 列 4ms 一轮、消抖 20ms，人的按键最短也有 50ms 以上，**余量充足**。跨列陈旧数据的窗口只有 3ms，用户不可能在 3ms 内释放一个键再按另一个（物理上被 20ms 消抖挡住），所以不会误判。 |
| **单时钟域 + tick 使能的分频写法是对的** | `rtl/clk_tick.v` | 面积报告显示只有一个 clock net（fanout 192），没有门控时钟、没有衍生时钟。**这个设计哲学要保留**，后面加 UART/舵机也必须沿用 tick 使能，不要引入第二个时钟。 |
| **`tick_100` 虽然当前没用，但保留是合理的** | `rtl/clk_tick.v:42-57` | 后面数码管扫描/DMA 类逻辑会用上，且它只占 4 个 FF。**不用删**（但可以在 `top.v` 里加一句注释说明"预留给 Day 5+"）。 |
| **`S_CHECK` 作为单拍瞬态状态、`state_code` 复用 `S_INPUT` 的编码** | `rtl/safe_fsm.v:72-82` | 写法清晰，没有引入额外的显示状态，**不要改**。 |
| **密码 `123456` / 反挟持 `654321` 的 24 位拼接方向和比较方向一致** | `rtl/safe_fsm.v:60-63, 15-17` | `input_digits[0]` 在 MSB，`DEFAULT_PWD` 的 `4'h1` 也在 MSB，**两边对齐正确**。 |

---

## 6. P2 级（工程治理 / 文档，可随手做）

### P2-L　两条构建路径并存，且 `lock.prj` 是过期副本

**位置**：`tools/build.bat:12-20`、`tools/build.tcl:10-15`、`lock_Runs/syn_1/test_syn.tcl:2`、`lock_Runs/syn_1/lock.prj:11-88`

**现状**

- `tools/build.bat` 走的是 **run 级 tcl**：`cd lock_Runs\syn_1` → `test_syn.tcl` → `open_project lock.prj`。
- `lock.prj` 是 TD 从 `lock.al` **生成的一份副本**，里面**写死了 8 个 `.v` 文件的相对路径**（`../../rtl/xxx.v`）。
- `tools/build.tcl` 走的是**工程级流程**：`open_project lock.al` + `launch_runs syn_1 phy_1`。

**原因**：Day 8 加 `uart.v` 时，如果你只改了 `lock.al`（GUI 里点 Add Source），`lock.prj` 这份副本**不会自动更新**，`build.bat` 会：
- 要么报"找不到模块 uart"；
- 要么更糟——静默地按旧文件列表综合，生成的 bit 里没有 UART，你烧上去发现串口不通，然后开始怀疑 UART 代码。

**建议**：**只保留一条构建路径**。

- 推荐：以 `tools/build.tcl` 为唯一入口，`build.bat` 里那几行改成
  `"D:\TD\bin\td_commands_prompt.exe" tools\build.tcl`（在项目根目录执行，不要在 `lock_Runs` 里执行）。
- 如果必须保留 run 级路径（比如只有它能跑通 `wait_run`），就在 `build.bat` 里加一步"从 `.al` 重新生成 prj"，或者在 README 里用醒目方式写死"**加文件时必须同步改 `lock.al` 和 `lock.prj` 两处**"。
- 建议顺手在 README 的 Quick Start 里写明"改 RTL 后建议先 `git status` 看有没有新增文件漏进约束/工程"。

### P2-M　`lock.adc` 有两份完全相同的副本

**位置**：`lock.adc`（根目录，**实际生效**）与 `constraints/lock.adc`（备份）

**证据**：`lock_Runs/syn_1/test_syn.tcl:5` 是 `read_adc ../../lock.adc`；`lock.al:79` 也指向根目录那份。

**原因**：两份内容现在完全一致，但没有任何机制保证以后一致。将来改引脚（Day 5 加语音/门磁、Day 6 加舵机几乎必然要改）时，很容易改到 `constraints/` 那份，然后发现"改了没生效"，白白浪费半小时。

**建议**：删掉 `constraints/lock.adc`，`constraints/` 目录只保留 `.sdc`（配合 P0-C）；或在两份文件头部加醒目注释说明"根目录那份才生效，本文件仅为备份，不要改这里"。

### P2-N　`timescale` 重复、`tick_100` 未使用

- `rtl/top.v:9` 和 `:11` 两行 `` `timescale 1ns / 1ps ``，删一行即可（无害，但会被 lint 报）。
- `top.v` 里 `tick_100` 产生后没有使用，建议保留但加注释"预留 Day 5+ 数码管/舵机时序"（见 §5）。

### P2-O　README 与实际 LED 定义漂移

**位置**：`README.md:150-151` vs `rtl/top.v:186-193`

| 文档说法 | 代码实际 |
|---|---|
| `led[1]` = 复位释放/运行就绪 | `led[1] = key_pressed`（按住按键才亮） |
| `led[2]~7` = 系统安全等级能量条 | `led[2]=unlock_en`、`led[3]=LOCKED`、`led[4]=ERROR`、`led[5]=有输入`、`led[6]=错 1 次`、`led[7]=错 2 次` |

**原因**：这类漂移在评审时会被直接指出"文档与实现不符"，而修改成本只有几分钟。**建议以 `top.v` 的注释为准更新 README**（`top.v:177-184` 那 8 行注释写得很清楚，直接搬过去即可）。

### P2-P　`lock_ones` 建议写成宽位中间信号（功能不变，只为可读）

**位置**：`rtl/seg_display.v:79-86`、`rtl/oled_driver.v:272-279`

**现状**：`wire [3:0] lock_ones = lock_countdown - (lock_tens * 4'd10);`

**原因**：功能正确（见 §5），但读者和 lint 工具都会怀疑这里有 4 位截断。综合器也可能给出 width 相关的 warning，混在一堆 warning 里污染视线。

**建议**：

```verilog
wire [6:0] lock_tens_x10 = {3'd0, lock_tens} * 7'd10;   // 7 位，最大 60，无截断
wire [6:0] lock_ones_7b  = lock_countdown - lock_tens_x10;
wire [3:0] lock_ones     = lock_ones_7b[3:0];           // 个位必然 < 10，取低 4 位无损
```

**验收**：`lock_countdown` 从 60 遍历到 0，`lock_ones` 每一位都和 `N % 10` 一致。

---

## 7. 建议的执行顺序

```
第 1 步（半天）：P0-A（init_rom 改 case）+ P0-D（去 DSP）
                —— 都是单文件局部改动，风险最低，先拿到"警告清零 + DSP=0"的正反馈

第 2 步（半天）：P0-C（加 .sdc）
                —— 加了约束后立刻能跑出第一条时序报告，同时暴露真正的 critical path
                   （很可能是 OLED 的 I2C 状态机或蜂鸣器的取模，此时 P0-D 已修掉后者）

第 3 步（半天）：P0-B（SDA 改开漏）+ P1-E（请求握手）
                —— 同一个文件，一起改、一起仿真；改完顺手把 SCL_DIV 注释对齐

第 4 步（1 天）：P1-J / P1-K 补 testbench
                —— 这是 Day 5 的"保险"：先把 Day1~4 的行为钉死成可回归的，再动新模块

第 5 步（半天）：P1-G / P1-H / P1-I
                —— 演示稳定性（误触不锁机、上电可靠复位、挟持事件不丢）

第 6 步（半天）：P2 全清（构建路径统一、删重复 adc、README 对齐）
                —— 为 Day 8 加 UART / Day 5-6 加语音舵机清路

可选（有富余时间）：P1-F（OLED 单页事务）—— 收益是 3 倍刷新率，但不是阻塞项
```

**如果只有一天时间，只做这三件**：P0-A（否则屏可能不亮且查不出原因）、P0-C（否则时序没法证明）、P1-J（否则核心逻辑等于没测）。

---

## 8. 给 Day 5+ 的顺带提醒（不属于本次修改，但会踩到）

1. **UART 接收必须做两级同步 + 起始位中点采样**。`key_row` 现在也是异步输入，只是被 20ms 消抖掩盖了；UART 的 RX 是 115200（8.68µs/位），没有余量，必须先过 2 级 FF。
2. **舵机 PWM 务必用 tick 使能 + 计数器生成**（20ms 周期 / 0.5~2.5ms 脉宽），不要用第二个时钟，否则会破坏"单时钟域"这个来之不易的优点。
3. **语音模块（JQ8900 单线）要有防重入**：`plan.md` Day 5 已经写了"内部定时器防重入"，请在代码里落成"发一帧后 100ms 内忽略新请求"，否则状态切换时会发出撕裂音。
4. **门磁/GPS-23 是机械开关**，接进来同样需要 20ms 消抖，建议复用 `keypad_scan` 里的消抖状态机写成通用 `debounce` 模块，不要复制粘贴第三份。
5. **面积窗口还很宽**（LUT 8.61%、BRAM 0/64）：字模库现在全部落在 LUT 里（1688 里估计 1300+ 是字模），未来若时序紧张可以把 `oled_font` 改成 `(* ram_style = "block" *)` 或 TD 的 ROM 推断属性搬进 BRAM。**现在不要动**——它没占满，动了反而可能引入初始化问题。

---

## 9. 附：一句话备忘

> **这个工程最大的风险不是"哪里写错了"，而是"错了也不会有人告诉你"** ——
> 仿真器能过（`initial` 在仿真里一定生效）、综合能过（只会给 warning）、布局能过（没有时序约束）、
> 上板可能不亮（没有人会怀疑是初始化表）。
> 所以本清单里 P0-A / P0-C / P1-J 三件的共同本质是：**把"沉默的失败"变成"会喊出来的失败"。**
