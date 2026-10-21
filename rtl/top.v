// ==============================================================================
// 工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
// 模块名称: top (系统顶级入口模块)
// 阶段任务: Day 5 - 底座加固 + JQ8900-16P语音播报 + GPS-23/SW1门磁防盗超时报警合流
// 硬件平台: 安路 (Anlogic) EG4S20BG256
// ==============================================================================

`timescale 1ns / 1ps

`ifndef __TOP_V__
`define __TOP_V__

module top(
    input  wire       clk_50M,     // 50MHz 系统主时钟 (引脚: R7)
    input  wire       rst_n,       // 全局异步复位，低电平有效 (引脚: E3，独立按键 KEY1)
    
    // 4x4 矩阵键盘物理接口 (兼容板载微动与外接薄膜键盘)
    input  wire [3:0] key_row,     // 4 行输入 (E10, C10, F9, D9) 内部 PULLUP
    output wire [3:0] key_col,     // 4 列扫描输出 (E11, D11, C11, F10)
    
    // 0.96寸 I2C OLED 显示屏接口 (SSD1306)
    output wire       oled_scl,    // I2C 串行时钟 (引脚: J14)
    inout  wire       oled_sda,    // I2C 串行数据开漏双向 (引脚: H13)
    
    // 板载 4 位共阴数码管接口
    output wire [7:0] seg_out,     // 段选输出 DP,G,F,E,D,C,B,A (高电平点亮: A4,A6,B8,E8,A7,B5,A8,C8)
    output wire [3:0] seg_cs,      // 位选输出 COM1~COM4 (低电平选通: C9,B6,A5,A3)
    
    // 板载无源蜂鸣器接口
    output wire       buzzer_out,  // 驱动板载蜂鸣器 (引脚: H11)
    
    // JQ8900-16P 真人语音播报模块接口 (Day 5 任务)
    output wire       voice_tx,    // 单线串口 One-Line 驱动 (引脚: H16)
    input  wire       voice_busy,  // 语音模块 BUSY 状态 (引脚: G16, 内部 PULLUP)
    
    // 门磁检测传感器接口 (板载 SW1 / 外接 GPS-23 干簧管双轨，Day 5 任务)
    input  wire       door_gpio,   // 门磁输入 (引脚: A10, 内部 PULLUP, 0:闭合, 1:敞开)
    
    // 8 位板载 LED 指示灯 (高电平点亮)
    output wire [7:0] led          // led[0]~led[7] (B14, B15, B16, C15, C16, E13, E16, F16)
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
)(
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
)(
    .clk        (clk_50M),
    .rst_n      (rst_sync_n),
    .tick_1k    (tick_1k),
    .key_row    (key_row),
    .key_col    (key_col),
    .key_val    (key_val),
    .key_valid  (key_valid),
    .key_pressed(key_pressed)
);

// --------------------------------------------------------------------------
// 3. 保险箱主业务状态机 (Day 4: 密码比对、连续输错3次锁定60秒)
// --------------------------------------------------------------------------
wire [2:0] state_code;
wire [2:0] pwd_len;
wire [1:0] err_count;
wire [6:0] lock_countdown;
wire       unlock_en;
wire       duress_alarm;
wire       beep_key;
wire       beep_err;
wire       beep_lock;
wire       beep_succ;

safe_fsm #(
    .DEFAULT_PWD       ({4'h1, 4'h2, 4'h3, 4'h4, 4'h5, 4'h6}), // 预设密码: 123456
    .DURESS_PWD        ({4'h6, 4'h5, 4'h4, 4'h3, 4'h2, 4'h1}), // 反挟持密码: 654321
    .LOCK_TIMEOUT_SEC  (60)                                   // 锁定 60 秒
)(
    .clk           (clk_50M),
    .rst_n         (rst_sync_n),
    .tick_1k       (tick_1k),
    .key_val       (key_val),
    .key_valid     (key_valid),
    .duress_clear  (1'b0), // 预留给后续串口指令清除
    .state_code    (state_code),
    .pwd_len       (pwd_len),
    .err_count     (err_count),
    .lock_countdown(lock_countdown),
    .unlock_en     (unlock_en),
    .duress_alarm  (duress_alarm),
    .beep_key      (beep_key),
    .beep_err      (beep_err),
    .beep_lock     (beep_lock),
    .beep_succ     (beep_succ)
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
)(
    .clk         (clk_50M),
    .rst_n       (rst_sync_n),
    .tick_1k     (tick_1k),
    .sensor_gpio (door_gpio),
    .unlock_en   (unlock_en),
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

// 开锁上升沿检测
reg unlock_en_d1;
always @(posedge clk_50M or negedge rst_sync_n) begin
    if (!rst_sync_n) begin
        unlock_en_d1 <= 1'b0;
    end else begin
        unlock_en_d1 <= unlock_en;
    end
end
wire unlock_rise = unlock_en && !unlock_en_d1;

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
        end else if (key_valid && (state_code == 3'd0) && (key_val <= 4'h9)) begin
            // Track 1: 敲击首位输入唤醒 ("请输入密码")
            voice_play_en   <= 1'b1;
            voice_track_num <= 8'h01;
        end
    end
end

voice_player #(
    .CLK_FREQ         (50_000_000),
    .BUSY_ACTIVE_LEVEL(1'b0)
)(
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
)(
    .clk       (clk_50M),
    .rst_n     (rst_sync_n),
    .tick_1k   (tick_1k),
    .beep_key  (beep_key),
    .beep_err  (beep_err_comb),
    .beep_lock (beep_lock),
    .beep_succ (beep_succ),
    .buzzer_out(buzzer_out)
);

// --------------------------------------------------------------------------
// 7. 板载 4 位共阴数码管底层状态代码监控 (Day 3 任务)
// --------------------------------------------------------------------------
seg_display u_seg_display (
    .clk           (clk_50M),
    .rst_n         (rst_sync_n),
    .tick_1k       (tick_1k),
    .state_code    (state_code),
    .pwd_len       (pwd_len),
    .err_count     (err_count),
    .lock_countdown(lock_countdown),
    .seg_out       (seg_out),
    .seg_cs        (seg_cs)
);

// --------------------------------------------------------------------------
// 8. 0.96寸 I2C OLED 中文与字符交互显示屏 (Day 3 任务, P0-B 开漏三态接口)
// --------------------------------------------------------------------------
oled_driver #(
    .CLK_FREQ(50_000_000)
)(
    .clk           (clk_50M),
    .rst_n         (rst_sync_n),
    .state_code    (state_code),
    .pwd_len       (pwd_len),
    .err_count     (err_count),
    .lock_countdown(lock_countdown),
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
// led[2]: 密码核验成功开锁指示灯 (高电平点亮 3 秒)
// led[3]: 系统锁定指示灯 (连续输错 3 次后在 60s 内常亮)
// led[4]: 错误报警指示灯 (处于密码错误状态时点亮)
// led[5]: 门物理状态指示 (门开点亮，门关严熄灭)
// led[6]: 输错次数累计指示 1 (输错 1 次点亮)
// led[7]: 输错次数累计指示 2 或 门未关超时警报 (报警时常亮)
// --------------------------------------------------------------------------
assign led[0] = hb_led;
assign led[1] = key_pressed;
assign led[2] = unlock_en;
assign led[3] = (state_code == 3'd4);
assign led[4] = (state_code == 3'd3);
assign led[5] = door_open;
assign led[6] = (err_count >= 2'd1);
assign led[7] = (err_count >= 2'd2) | door_alert;

endmodule

`endif
