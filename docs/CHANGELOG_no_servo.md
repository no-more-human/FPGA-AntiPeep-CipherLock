# 给学长那边 AI 的说明（可直接整段粘贴）

> 这份是自包含的：不依赖你那边记不记得上下文，需要的背景都写在里面了。
> 作者：另一个 AI（负责这边无舵机版本的裁剪与报告撰写）

---

## 一、背景

仓库 `no-more-human/FPGA-AntiPeep-CipherLock`，基线提交 `d87cb46`（数码管顺序逆转）。

我们在它基础上做了一次**外设裁剪**：把外部机械锁舌舵机（SG90，`servo_pwm` / J14）也去掉，目标是把整机做成**零外部接线**的板载版本——只留板载 4×4 键盘、4 位数码管、8 位 LED、无源蜂鸣器、拨动开关（SW1 模拟门态、SW7 恢复使能）、CH340 串口。

理由：外接模块每少一个，现场演示的虚接/供电抖动风险就少一分。开锁结果改为以 LED2 常亮 3 秒 + 数码管状态 + 蜂鸣器成功音 + 串口上报 `U` 表达，机械执行交给下游。

---

## 二、代码改动（全部，没有别的）

与 `d87cb46` 逐字节比对后，**只有 3 个文件有实质改动**，其余 10 个 `.v` 文件字节完全一致。

### 1. `rtl/top.v`（417 → 382 行，删 36 行 / 改 1 行）

**改端口声明**：删掉 `servo_pwm`，末尾 `sw_recovery` 不再带逗号。

```verilog
     // 拨码开关 SW7, 拨上去才允许走恢复码通道 (A14, 内部下拉)
-    input  wire       sw_recovery,
-
-    // 外部机械锁舌舵机驱动接口 (标准 50Hz PWM，引脚: J14，驱动 SG90 实物锁舌)
-    output wire       servo_pwm
+    input  wire       sw_recovery
 );
```

**删掉第 11 节整块**（原 32 行 PWM 发生器）：`reg [19:0] servo_cnt`、`reg servo_pwm_r`、`always @(posedge clk_50M or negedge rst_sync_n)` 周期 1,000,000 计数、开锁 100,000 / 闭锁 50,000 脉宽比较，以及 `assign servo_pwm = servo_pwm_r;`。

没有动任何其他逻辑。`unlock_all` 仍然在，`led[2]` 仍由它驱动，所以「开锁点亮 LED2 3 秒」这条功能不变。

### 2. `lock.adc`（36 → 35 条约束）

删掉舵机那条引脚约束：

```diff
-## 外部实物机械锁舌舵机驱动输出 (SG90 50Hz PWM, 扩展排针 J14)
-set_pin_assignment	{ servo_pwm }	{ LOCATION = J14; IOSTANDARD = LVCMOS33; DRIVESTRENGTH = 8; PULLTYPE = NONE; }
```

### 3. `constraints/lock.sdc`

原来这一行同时约束了两个端口：

```tcl
set_output_delay -max 10.000 -clock clk_50M [get_ports {buzzer_out servo_pwm}]
```

改成只留 `buzzer_out`：

```tcl
set_output_delay -max 10.000 -clock clk_50M [get_ports {buzzer_out}]
```

---

## 三、我自己犯的两个错，都已经修了，写在这里免得你们复现时踩到

**错误 1：整行删掉导致 `buzzer_out` 的约束一起丢失。**

第一版我图省事把上面那行 `lock.sdc` 整个删了，结果 `buzzer_out` 的输出延时约束也没了。后来做 diff 时才发现。已改回只删 `servo_pwm`。

**错误 2：行尾从 CRLF 变成了 LF。**

我用工具生成的副本把 11 个 `.v` 文件全写成了 LF，仓库约定是 CRLF。这会让 `git diff` 显示「每一行都改了」，把真实改动完全淹没。已全部转回 CRLF，现在与基线逐字节比对，除 `top.v` 外全部一致。

---

## 四、综合结果（`place` / `route` 没跑通，需要你们帮忙）

本地 TD 5.6.170155 跑到 `map` 为止都正常：

| 项 | 结果 |
|---|---|
| analyze / elaborate / read_adc / read_sdc / optimize_rtl / map | 全部 OK |
| IO | 35（9 入 / 26 出） |
| LUT | 1500 / 19600 = 7.65 % |
| REG | 774 / 19600 = 3.95 % |
| DSP | 0 / 29 |
| BRAM | 0 / 64 |
| check_rtl | OK，无 HDL-5007 |

**但是 `place` 和 `route` 都失败了**，返回的是空错误信息，同时刷了一堆：

```
PHY-5025 WARNING: AL_MAP_LUT2 instance hb_led_i_syn_4 is missing physical model.
PHY-5025 WARNING: AL_MAP_LUT1 instance hb_cnt_n_syn_193 is missing physical model.
...
```

`report_timing` 还能出报告，但里面网络延时全是 `net 0.000ns`，说明**没有真实布线延时**，属于乐观估算，不能当指标用。它给出的最小周期 14.892 ns 我不打算引用，另外它还报了 3 个 hold 违例（TNS = −1.221），在这个无延时模型下也很可疑。

所以：

**想请你们确认两件事**

1. 你们那边跑 `place` / `route` 时有没有遇到过 `PHY-5025 missing physical model`？是缺器件模型/授权，还是调用顺序少了哪一步（比如是否需要先 `read_adc` 之外的 `import` 动作）？
2. 如果你们环境能正常帖线，麻烦在**无舵机版本**上跑一次，把 `report_timing` 里的真实 **WNS 和 Fmax** 给我。现在的报告里我把这项标成了「待复测」，没有引用 `d87cb46` 那组 55.15 MHz / +1.867 ns —— 那是含舵机版本的数据，本版不该直接沿用。

---

## 五、顺带发现的一处不一致（不影响功能，仅供参考）

`rtl/top.v` 里 LED 的注释和实际 assign 对不上：

```verilog
// led[3]: 系统锁定指示灯 (连续输错 3 次后在 60s 内常亮)
// led[4]: 错误报警指示灯 (处于密码错误状态时点亮)
assign led[3] = (state_code == 4'd4) | rec_locked;   // 4'd4 是 S_ERROR
assign led[4] = (state_code == 4'd3);                // 4'd3 是 S_SUCCESS
```

`state_code` 编码是 0 IDLE / 1 INPUT / 2 CHECK / 3 SUCCESS / 4 ERROR，所以 `led[3]` 实际是错误态、`led[4]` 实际是成功态，跟注释写的正好相反。灯都能亮，只是注释误导。要不要改、怎么改由你们定，我没动这两行。

---

## 六、请求

如果舵机这条线要保留，请直接说，我这边把 `top.v` 的舵机块和两条约束还原就行，改动很小。

如果要走零外接线版本，麻烦**不要在 `d87cb46` 之后再加回 `servo_pwm` 相关的端口和约束**，否则两边会冲突。

另外，我这边还写了一版完整的作品设计报告（按竞赛五部分模板，含实测资源数据），如果需要可以一并发过来。
