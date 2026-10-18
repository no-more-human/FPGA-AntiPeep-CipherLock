// ==============================================================================
// 工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
// 模块名称: top (系统顶级入口模块)
// 阶段任务: Day 3~4 整合 - 4x4矩阵键盘 + 0.96寸OLED中文显示 + 4位数码管 + 
//                         无源蜂鸣器音效 + 6位密码核验与3次输错锁定60s
// 硬件平台: 安路 (Anlogic) EG4S20BG256
// ==============================================================================

`timescale 1ns / 1ps

`timescale 1ns / 1ps

module top(
    input  wire       clk_50M,     // 50MHz 系统主时钟 (引脚: R7)
    input  wire       rst_n,       // 全局异步复位，低电平有效 (引脚: E3，独立按键 KEY1)
    
    // 4x4 矩阵键盘物理接口 (兼容板载微动与外接薄膜键盘)
    input  wire [3:0] key_row,     // 4 行输入 (E10, C10, F9, D9) 内部 PULLUP
    output wire [3:0] key_col,     // 4 列扫描输出 (E11, D11, C11, F10)
    
    // 0.96寸 I2C OLED 显示屏接口 (SSD1306)
    output wire       oled_scl,    // I2C 串行时钟 (引脚: J14)
    output wire       oled_sda,    // I2C 串行数据 (引脚: H13)
    
    // 板载 4 位共阴数码管接口
    output wire [7:0] seg_out,     // 段选输出 DP,G,F,E,D,C,B,A (高电平点亮: A4,A6,B8,E8,A7,B5,A8,C8)
    output wire [3:0] seg_cs,      // 位选输出 COM1~COM4 (低电平选通: C9,B6,A5,A3)
    
    // 板载无源蜂鸣器接口
    output wire       buzzer_out,  // 驱动板载蜂鸣器 (引脚: H11)
    
    // 8 位板载 LED 指示灯 (高电平点亮)
    output wire [7:0] led          // led[0]~led[7] (B14, B15, B16, C15, C16, E13, E16, F16)
);

// --------------------------------------------------------------------------
// 1. 系统基准节拍发生器 (产生 1kHz / 100Hz 同步使能脉冲)
// --------------------------------------------------------------------------
wire tick_1k;
wire tick_100;

clk_tick #(
    .CLK_FREQ(50_000_000)
) u_clk_tick (
    .clk     (clk_50M),
    .rst_n   (rst_n),
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
    .rst_n      (rst_n),
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
) u_safe_fsm (
    .clk           (clk_50M),
    .rst_n         (rst_n),
    .tick_1k       (tick_1k),
    .key_val       (key_val),
    .key_valid     (key_valid),
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
// 4. 无源蜂鸣器 PWM 驱动 (按键音、错误警告音、锁定严重警报、成功和弦)
// --------------------------------------------------------------------------
buzzer_driver #(
    .CLK_FREQ(50_000_000)
) u_buzzer_driver (
    .clk       (clk_50M),
    .rst_n     (rst_n),
    .tick_1k   (tick_1k),
    .beep_key  (beep_key),
    .beep_err  (beep_err),
    .beep_lock (beep_lock),
    .beep_succ (beep_succ),
    .buzzer_out(buzzer_out)
);

// --------------------------------------------------------------------------
// 5. 板载 4 位共阴数码管底层状态代码监控 (Day 3 任务)
// --------------------------------------------------------------------------
seg_display u_seg_display (
    .clk           (clk_50M),
    .rst_n         (rst_n),
    .tick_1k       (tick_1k),
    .state_code    (state_code),
    .pwd_len       (pwd_len),
    .err_count     (err_count),
    .lock_countdown(lock_countdown),
    .seg_out       (seg_out),
    .seg_cs        (seg_cs)
);

// --------------------------------------------------------------------------
// 6. 0.96寸 I2C OLED 中文与字符交互显示屏 (Day 3 任务)
// --------------------------------------------------------------------------
oled_driver #(
    .CLK_FREQ(50_000_000)
) u_oled_driver (
    .clk           (clk_50M),
    .rst_n         (rst_n),
    .state_code    (state_code),
    .pwd_len       (pwd_len),
    .err_count     (err_count),
    .lock_countdown(lock_countdown),
    .oled_scl      (oled_scl),
    .oled_sda      (oled_sda)
);

// --------------------------------------------------------------------------
// 7. LED0 1Hz 系统存活心跳指示
// --------------------------------------------------------------------------
reg [8:0] hb_cnt;
reg       hb_led;

always @(posedge clk_50M or negedge rst_n) begin
    if (!rst_n) begin
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
// 8. 板载 8 位 LED 状态指示映射 (声光电立体直观反馈)
// --------------------------------------------------------------------------
// led[0]: 1Hz 系统存活心跳灯 (闪烁表示 50MHz 时钟与系统存活)
// led[1]: 实时按键物理按下指示 (按住常亮，松开熄灭)
// led[2]: 密码核验成功开锁指示灯 (高电平点亮 3 秒)
// led[3]: 系统锁定指示灯 (连续输错 3 次后在 60s 内常亮)
// led[4]: 错误报警指示灯 (处于密码错误状态时点亮)
// led[5]: 密码输入有效指示 (已输入至少 1 位时点亮)
// led[6]: 输错次数累计指示 1 (输错 1 次点亮)
// led[7]: 输错次数累计指示 2 (输错 2 次点亮)
// --------------------------------------------------------------------------
assign led[0] = hb_led;
assign led[1] = key_pressed;
assign led[2] = unlock_en;
assign led[3] = (state_code == 3'd4); // 锁定状态
assign led[4] = (state_code == 3'd3); // 错误状态
assign led[5] = (pwd_len > 3'd0);     // 有输入
assign led[6] = (err_count >= 2'd1);  // 输错第1次
assign led[7] = (err_count >= 2'd2);  // 输错第2次

endmodule
