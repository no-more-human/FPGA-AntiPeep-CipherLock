// ==============================================================================
// 工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
// 模块名称: top (系统顶级入口模块)
// 阶段任务: Day 7 - 加了 UART,PC 那边说的话现在能听见了
// 硬件平台: 安路 (Anlogic) EG4S20BG256
// ==============================================================================

`timescale 1ns / 1ps

`ifndef __TOP_V__
`define __TOP_V__

module top(
    input  wire       clk_50M,     // 50MHz 系统主时钟 (引脚: R7)
    input  wire       rst_n,       // 全局异步复位，低电平有效 (引脚: E3，独立按键 KEY1)
    
    // 4x4 矩阵键盘物理接口 (下方排母 P4 联排直插: 8,10,12,14,16,18,20,22号针)
    input  wire [3:0] key_row,     // 4 行输入 (L12, P15, P16, N14 -> P4-8,10,12,14) 内部 PULLUP
    output wire [3:0] key_col,     // 4 列扫描输出 (N16, M16, L16, P14 -> P4-16,18,20,22)
    
    // 0.96寸 I2C OLED 显示屏接口 (SSD1306, 下方排母 P4 右端联排直插: 60,58,56,54号针)
    output wire       oled_scl,    // I2C 串行时钟 (引脚: E15 -> P4-56)
    inout  wire       oled_sda,    // I2C 串行数据开漏双向 (引脚: D14 -> P4-54)
    
    // 板载 4 位共阴数码管接口
    output wire [7:0] seg_out,     // 段选输出 DP,G,F,E,D,C,B,A (高电平点亮: A4,A6,B8,E8,A7,B5,A8,C8)
    output wire [3:0] seg_cs,      // 位选输出 COM1~COM4 (低电平选通: C9,B6,A5,A3)
    
    // 板载无源蜂鸣器接口
    output wire       buzzer_out,  // 驱动板载蜂鸣器 (引脚: H11)
    
    // SG90 舵机 50Hz PWM 控制接口 (下方排母 P4 最左侧联排直插: 2,4,6号针)
    output wire       servo_pwm,   // 驱动舵机旋转 (引脚: M11 -> P4-6)
    
    // JQ8900-16P 真人语音播报模块接口 (Day 5 任务)
    output wire       voice_tx,    // 单线串口 One-Line 驱动 (引脚: H16)
    input  wire       voice_busy,  // 语音模块 BUSY 状态 (引脚: G16, 内部 PULLUP)
    
    // 门磁检测传感器接口 (板载 SW1 / 外接 GPS-23 干簧管双轨，Day 5 任务)
    input  wire       door_gpio,   // 门磁输入 (引脚: A10, 内部 PULLUP, 0:闭合, 1:敞开)
    
    // 8 位板载 LED 指示灯 (高电平点亮)
    output wire [7:0] led,         // led[0]~led[7] (B14, B15, B16, C15, C16, E13, E16, F16)

    // 板载 CH340 转 USB,115200 8-N-1,插根 USB 线就是 COM 口
    output wire       uart_tx,     // 发给 PC (D12)
    input  wire       uart_rx,     // 收 PC 的话 (F12)

    // 拨码开关 SW7,拨上去才允许走恢复码通道 (A14,内部下拉)
    input  wire       sw_recovery
);

// --------------------------------------------------------------------------
// 0. 异步复位-双级同步释放与上电 POR (P1-H 加固)
// --------------------------------------------------------------------------
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

// --------------------------------------------------------------------------
// 1. 系统基准节拍发生器 (产生 1kHz / 100Hz 同步使能脉冲)
// --------------------------------------------------------------------------
wire tick_1k;
wire tick_100;

clk_tick #(
    .CLK_FREQ(50_000_000)
) u_clk_tick (
    .clk     (clk_50M),
    .rst_n   (rst_sync_n),
    .tick_1k (tick_1k),
    .tick_100(tick_100)
);

// --------------------------------------------------------------------------
// 2. 4x4 矩阵键盘扫描与 20ms 硬件双向消抖
// --------------------------------------------------------------------------
wire [3:0] key_val;
wire       key_valid;
wire       key_pressed;

keypad_scan #(
    .DEBOUNCE_TIME(20) // 20ms 双向滤波消抖
) u_keypad_scan (
    .clk        (clk_50M),
    .rst_n      (rst_sync_n),
    .tick_1k    (tick_1k),
    .key_row    (key_row),
    .key_col    (key_col),
    .key_val    (key_val),
    .key_valid  (key_valid),
    .key_pressed(key_pressed)
);

// 邮差送过来的几根线,例化在第 11 节
wire peep_hang;        // 1 就是有人在偷看
wire remote_unlock;    // PC 让远程开的
wire cmd_safe;         // 收到 'S' 那一拍
wire uart_is_sending;
wire [7:0] uart_last_byte;

// 恢复码通道
wire       rec_active;
wire       reset_req;
wire [2:0] rec_len;
wire [1:0] rec_try;
wire       rec_err;
wire       rec_ok;
wire       rec_locked;
wire [7:0] rec_countdown;

// 被偷看的时候、或者正在走恢复码流程的时候,主状态机都不许收键盘
wire key_valid_fsm = key_valid && !peep_hang && !rec_active;

// 恢复成功就把 safe_fsm 自己复位一下,它的 current_pwd 在复位分支里会
// 被打回 DEFAULT_PWD(123456)。这样学长那份文件一个字都不用改
reg rec_rst_n;
always @(posedge clk_50M or negedge rst_sync_n) begin
    if (!rst_sync_n)      rec_rst_n <= 1'b1;
    else if (reset_req)   rec_rst_n <= 1'b0;
    else                  rec_rst_n <= 1'b1;
end
wire safe_rst_n = rst_sync_n & rec_rst_n;

// 密码开的和远程开的都算开,舵机不关心是谁给的权利
wire unlock_all;

// --------------------------------------------------------------------------
// 3. 保险箱主业务状态机 (Day 6~9: 16位虚位密码、A键首次录入、B键改密、C键提前闭锁)
// --------------------------------------------------------------------------
wire [3:0] state_code;
wire [4:0] pwd_len;
wire [1:0] err_count;
wire [6:0] lock_countdown;
wire       unlock_en;
wire       duress_alarm;
wire       pwd_changed;
wire       beep_key;
wire       beep_err;
wire       beep_lock;
wire       beep_succ;

safe_fsm #(
    .DEFAULT_PWD       ({4'h1, 4'h2, 4'h3, 4'h4, 4'h5, 4'h6}), // 预设密码: 123456
    .DURESS_PWD        ({4'h6, 4'h5, 4'h4, 4'h3, 4'h2, 4'h1}), // 反挟持密码: 654321
    .LOCK_TIMEOUT_SEC  (60),                                  // 锁定 60 秒
    .OP_TIMEOUT_SEC    (15)                                   // 15 秒无操作看门狗
) u_safe_fsm (
    .clk           (clk_50M),
    .rst_n         (safe_rst_n),
    .tick_1k       (tick_1k),
    .key_val       (key_val),
    .key_valid     (key_valid_fsm),   // 防窥挂起时屏蔽
    .duress_clear  (cmd_safe),        // 收到 'S' 清反挟持粘滞报警(以前是死接 1'b0)
    .state_code    (state_code),
    .pwd_len       (pwd_len),
    .err_count     (err_count),
    .lock_countdown(lock_countdown),
    .unlock_en     (unlock_en),
    .duress_alarm  (duress_alarm),
    .pwd_changed   (pwd_changed),
    .beep_key      (beep_key),
    .beep_err      (beep_err),
    .beep_lock     (beep_lock),
    .beep_succ     (beep_succ)
);

// unlock_en 上面才声明,所以合流放这儿
assign unlock_all = unlock_en | remote_unlock;

// --------------------------------------------------------------------------
// 3.1 SG90 舵机 50Hz PWM 控制驱动 (Day 6 任务)
// --------------------------------------------------------------------------
servo_driver #(
    .CLK_FREQ    (50_000_000),
    .PERIOD_CNT  (1_000_000), // 20ms 基准周期
    .PULSE_0_DEG (25_000),    // 0.5ms: 0度闭锁
    .PULSE_90_DEG(75_000)     // 1.5ms: 90度开锁
) u_servo_driver (
    .clk      (clk_50M),
    .rst_n    (rst_sync_n),
    .unlock_en(unlock_all),
    .servo_pwm(servo_pwm)
);

// --------------------------------------------------------------------------
// 4. GPS-23 门磁与 SW1 双轨检测及 15 秒超时报警 (Day 5 任务)
// --------------------------------------------------------------------------
wire       door_open;
wire       door_alert;
wire       door_alert_pulse;
wire [3:0] door_open_sec;

door_sensor #(
    .TIMEOUT_SEC  (15), // 开锁后门未关 15 秒超时报警
    .DEBOUNCE_TIME(20)  // 20ms 消抖
) u_door_sensor (
    .clk         (clk_50M),
    .rst_n       (rst_sync_n),
    .tick_1k     (tick_1k),
    .sensor_gpio (door_gpio),
    .unlock_en   (unlock_all),  // 远程开的也要开始算关门时间
    .door_open   (door_open),
    .door_alert  (door_alert),
    .alert_pulse (door_alert_pulse),
    .open_sec_cnt(door_open_sec)
);

// --------------------------------------------------------------------------
// 5. JQ8900-16P 真人语音播报驱动模块与业务事件联动 (Day 5 任务)
// --------------------------------------------------------------------------
reg        voice_play_en;
reg  [7:0] voice_track_num;
wire       voice_is_busy;

// 开锁与防窥上升沿检测
reg unlock_en_d1;
reg peep_hang_d1;
always @(posedge clk_50M or negedge rst_sync_n) begin
    if (!rst_sync_n) begin
        unlock_en_d1 <= 1'b0;
        peep_hang_d1 <= 1'b0;
    end else begin
        unlock_en_d1 <= unlock_all;     // 远程开锁也要播
        peep_hang_d1 <= peep_hang;      // 防窥挂起上升沿触发语音 Track 7
    end
end
wire unlock_rise = unlock_all && !unlock_en_d1;
wire peep_rise   = peep_hang  && !peep_hang_d1;

// 语音调度逻辑 (单线串口防重入)
always @(posedge clk_50M or negedge rst_sync_n) begin
    if (!rst_sync_n) begin
        voice_play_en   <= 1'b0;
        voice_track_num <= 8'd0;
    end else begin
        voice_play_en <= 1'b0; // 默认清除脉冲
        if (unlock_rise) begin
            // Track 2: 开锁成功 ("门已开 / 欢迎使用")
            voice_play_en   <= 1'b1;
            voice_track_num <= 8'h02;
        end else if (pwd_changed) begin
            // Track 5: 密码修改/录入成功 ("修改成功")
            voice_play_en   <= 1'b1;
            voice_track_num <= 8'h05;
        end else if (peep_rise) begin
            // Track 7: 视觉防窥挂起 ("背后有人，请注意防窥")
            voice_play_en   <= 1'b1;
            voice_track_num <= 8'h07;
        end else if (door_alert_pulse) begin
            // Track 6: 门磁超时报警 ("门未关严，请关门")
            voice_play_en   <= 1'b1;
            voice_track_num <= 8'h06;
        end else if (beep_lock) begin
            // Track 4: 系统严重锁定 ("系统已锁定")
            voice_play_en   <= 1'b1;
            voice_track_num <= 8'h04;
        end else if (beep_err) begin
            // Track 3: 密码输入错误 ("密码错误")
            voice_play_en   <= 1'b1;
            voice_track_num <= 8'h03;
        end else if (key_valid_fsm && (state_code == 4'd0) && (key_val <= 4'h9)) begin
            // Track 1: 敲击首位输入唤醒 ("请输入密码")
            voice_play_en   <= 1'b1;
            voice_track_num <= 8'h01;
        end
    end
end

voice_player #(
    .CLK_FREQ         (50_000_000),
    .BUSY_ACTIVE_LEVEL(1'b0)
) u_voice_player (
    .clk       (clk_50M),
    .rst_n     (rst_sync_n),
    .tick_1k   (tick_1k),
    .play_en   (voice_play_en),
    .track_num (voice_track_num),
    .voice_busy(voice_busy),
    .voice_tx  (voice_tx),
    .is_busy   (voice_is_busy)
);

// --------------------------------------------------------------------------
// 6. 无源蜂鸣器 PWM 驱动 (按键音、错误警告音、锁定严重警报、成功和弦，0 DSP)
// --------------------------------------------------------------------------
wire beep_err_comb = beep_err | door_alert_pulse; // 门磁超时报警同步发蜂鸣警报音

buzzer_driver #(
    .CLK_FREQ(50_000_000)
) u_buzzer_driver (
    .clk       (clk_50M),
    .rst_n     (rst_sync_n),
    .tick_1k   (tick_1k),
    .beep_key  (beep_key),
    .beep_err  (beep_err_comb | rec_err),
    .beep_lock (beep_lock),
    .beep_succ (beep_succ | rec_ok),
    .buzzer_out(buzzer_out)
);

// --------------------------------------------------------------------------
// 7. 板载 4 位共阴数码管底层状态代码监控 (Day 3 任务)
//    防窥挂起时整块灭掉 (段选清零、位选全关)，采用寄存器打拍输出以打包进 IOB OREG
// --------------------------------------------------------------------------
wire [7:0] seg_out_raw;
wire [3:0] seg_cs_raw;

seg_display u_seg_display (
    .clk           (clk_50M),
    .rst_n         (rst_sync_n),
    .tick_1k       (tick_1k),
    .state_code    (state_code),
    .pwd_len       (pwd_len),
    .err_count     (err_count),
    .lock_countdown(lock_countdown),
    .seg_out       (seg_out_raw),
    .seg_cs        (seg_cs_raw)
);

reg [7:0] seg_out_r;
reg [3:0] seg_cs_r;

always @(posedge clk_50M or negedge rst_sync_n) begin
    if (!rst_sync_n) begin
        seg_out_r <= 8'h00;
        seg_cs_r  <= 4'hF;
    end else if (peep_hang) begin
        seg_out_r <= 8'h00;
        seg_cs_r  <= 4'hF;
    end else begin
        seg_out_r <= seg_out_raw;
        seg_cs_r  <= seg_cs_raw;
    end
end

assign seg_out = seg_out_r;
assign seg_cs  = seg_cs_r;

// --------------------------------------------------------------------------
// 8. 0.96寸 I2C OLED 中文与字符交互显示屏 (Day 3~8 任务, P0-B 开漏三态接口 + 防窥熄屏横杠)
// --------------------------------------------------------------------------
oled_driver #(
    .CLK_FREQ(50_000_000)
) u_oled_driver (
    .clk           (clk_50M),
    .rst_n         (rst_sync_n),
    .state_code    (state_code),
    .pwd_len       (pwd_len),
    .err_count     (err_count),
    .lock_countdown(lock_countdown),
    .peep_hang     (peep_hang),
    .oled_scl      (oled_scl),
    .oled_sda      (oled_sda)
);

// --------------------------------------------------------------------------
// 9. LED0 1Hz 系统存活心跳指示
// --------------------------------------------------------------------------
reg [8:0] hb_cnt;
reg       hb_led;

always @(posedge clk_50M or negedge rst_sync_n) begin
    if (!rst_sync_n) begin
        hb_cnt <= 9'd0;
        hb_led <= 1'b0;
    end else if (tick_1k) begin
        if (hb_cnt >= 9'd499) begin
            hb_cnt <= 9'd0;
            hb_led <= ~hb_led;
        end else begin
            hb_cnt <= hb_cnt + 9'd1;
        end
    end
end

// --------------------------------------------------------------------------
// 10. 板载 8 位 LED 状态指示映射 (声光电立体直观反馈)
// --------------------------------------------------------------------------
// led[0]: 1Hz 系统存活心跳灯 (闪烁表示 50MHz 时钟与系统存活)
// led[1]: 实时按键物理按下指示 (按住常亮，松开熄灭)
// led[2]: 密码核验成功开锁指示灯 (含远程开锁，高电平点亮 3 秒)
// led[3]: 系统锁定指示灯 (连续输错 3 次后在 60s 内常亮)
// led[4]: 错误报警指示灯 (处于密码错误状态时点亮)
// led[5]: 门物理状态指示 (门开点亮，门关严熄灭)
// led[6]: 输错次数累计指示 1 (输错 1 次点亮)
// led[7]: 输错次数累计指示 2 或 门未关超时警报 (报警时常亮)
//
// 调串口的时候可以把这一堆全换成 assign led = uart_last_byte;
// PC 发个 'S' = 0x53 = 0101_0011,看 8 个灯亮灭就知道收对不对,调通了再换回来
// --------------------------------------------------------------------------
assign led[0] = hb_led;
assign led[1] = key_pressed;
assign led[2] = unlock_all;
assign led[3] = (state_code == 4'd4);
assign led[4] = (state_code == 4'd3);
assign led[5] = door_open;
assign led[6] = (err_count >= 2'd1);
assign led[7] = (err_count >= 2'd2) | door_alert;

// --------------------------------------------------------------------------
// 11. 邮差上岗
//     事件的来源都抄现成的:
//       开锁上升沿 已经有了(unlock_rise)
//       锁定       safe_fsm 进 S_LOCKED 时自带一拍 beep_lock
//       反挟持     duress_alarm 是粘滞的,得自己取个沿
//       门没关     door_alert_pulse 已经有了
// --------------------------------------------------------------------------
reg duress_alarm_d1;
always @(posedge clk_50M or negedge rst_sync_n) begin
    if (!rst_sync_n) begin
        duress_alarm_d1 <= 1'b0;
    end else begin
        duress_alarm_d1 <= duress_alarm;
    end
end
wire duress_rise = duress_alarm && !duress_alarm_d1;

uart_mailman #(
    .CLK_FREQ(50_000_000),
    .BAUD(115_200),
    .REMOTE_HOLD_SEC(3)
) u_mailman (
    .clk          (clk_50M),
    .rst_n        (rst_sync_n),
    .tick_1k      (tick_1k),
    .uart_rx      (uart_rx),
    .uart_tx      (uart_tx),
    .evt_unlock   (unlock_rise),
    .evt_lock     (beep_lock),
    .evt_duress   (duress_rise),
    .evt_door     (door_alert_pulse),
    .peep_hang    (peep_hang),
    .remote_unlock(remote_unlock),
    .cmd_safe     (cmd_safe),
    .is_sending   (uart_is_sending),
    .the_letter   (uart_last_byte)
);

// --------------------------------------------------------------------------
// 12. 恢复码通道(忘了密码时用)
//     待机按 D -> 输 6 位恢复码 -> 对了密码打回 123456
//     sw_recovery(A14) 不拨上去,D 键完全无效
//     默认恢复码 937158,要改就改 RECOVERY_CODE 那个 parameter
// --------------------------------------------------------------------------
recovery_mgr #(
    .RECOVERY_CODE ({4'h9, 4'h3, 4'h7, 4'h1, 4'h5, 4'h8}),
    .MAX_TRY       (3),
    .LOCK_SEC      (60),
    .OP_TIMEOUT_SEC(30)
) u_recovery_mgr (
    .clk          (clk_50M),
    .rst_n        (rst_sync_n),
    .tick_1k      (tick_1k),
    .key_val      (key_val),
    .key_valid    (key_valid),
    .state_code   (state_code),
    .sw_recovery  (sw_recovery),
    .rec_active   (rec_active),
    .reset_req    (reset_req),
    .rec_len      (rec_len),
    .rec_try      (rec_try),
    .rec_err      (rec_err),
    .rec_ok       (rec_ok),
    .rec_locked   (rec_locked),
    .rec_countdown(rec_countdown)
);

endmodule

`endif
