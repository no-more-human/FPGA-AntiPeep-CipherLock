// ==============================================================================
// 工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
// 模块名称: top (系统顶级入口模块 - 纯板载外设与 PC 数字孪生 OLED 协同版)
// 硬件平台: 安路 (Anlogic) EG4S20BG256
// ==============================================================================

`timescale 1ns / 1ps

`ifndef __TOP_V__
`define __TOP_V__

module top(
    input  wire       clk_50M,     // 50MHz 系统主时钟 (引脚: R7)
    input  wire       rst_n,       // 全局异步复位，低电平有效 (引脚: E3，独立按键 KEY1)
    
    // 板载 4x4 矩阵微动键盘物理接口
    input  wire [3:0] key_row,     // 4 行输入 (E10, C10, F9, D9) 内部 PULLUP
    output wire [3:0] key_col,     // 4 列扫描输出 (E11, D11, C11, F10)
    
    // 板载 4 位共阴数码管接口
    output wire [7:0] seg_out,     // 段选输出 DP,G,F,E,D,C,B,A (高电平点亮: A4,A6,B8,E8,A7,B5,A8,C8)
    output wire [3:0] seg_cs,      // 位选输出 COM1~COM4 (低电平选通: C9,B6,A5,A3)
    
    // 板载无源蜂鸣器接口
    output wire       buzzer_out,  // 驱动板载蜂鸣器 (引脚: H11)
    
    // 门磁检测传感器模拟接口 (板载 SW1 拨动开关)
    input  wire       door_gpio,   // 门磁输入 (引脚: A10, 内部 PULLUP, 0:闭合, 1:敞开)
    
    // 8 位板载 LED 指示灯 (高电平点亮)
    output wire [7:0] led,         // led[0]~led[7] (B14, B15, B16, C15, C16, E13, E16, F16)

    // 板载 CH340 转 USB, 115200 8-N-1, 插根 USB 线就是 COM 口
    output wire       uart_tx,     // 发给 PC (D12)
    input  wire       uart_rx,     // 收 PC 的话 (F12)

    // 拨码开关 SW7, 拨上去才允许走恢复码通道 (A14, 内部下拉)
    input  wire       sw_recovery,

    // 外部机械锁舌舵机驱动接口 (标准 50Hz PWM，引脚: J14，驱动 SG90 实物锁舌)
    output wire       servo_pwm
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
// 1. 系统基准节拍发生器 (产生 1kHz 同步使能脉冲)
// --------------------------------------------------------------------------
wire tick_1k;

clk_tick #(
    .CLK_FREQ(50_000_000)
) u_clk_tick (
    .clk     (clk_50M),
    .rst_n   (rst_sync_n),
    .tick_1k (tick_1k),
    .tick_100() // 100Hz 未用悬空 (清理瑕疵 2.5)
);

// --------------------------------------------------------------------------
// 2. 板载 4x4 矩阵键盘扫描与 20ms 硬件双向消抖
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

// 邮差送过来的几根线
wire peep_hang;        // 1 就是有人在偷看
wire remote_unlock;    // PC 让远程开的
wire cmd_safe;         // 收到 'S' 那一拍
wire auth_err;         // 远程挑战-应答认证失败或超时脉冲

// 恢复码通道
wire       rec_active;
wire       reset_req;
wire [2:0] rec_len;
wire [1:0] rec_ui_mode;
wire       rec_beep_key;
wire       rec_beep_err;
wire       rec_err;
wire       rec_ok;
wire       rec_locked;
wire [7:0] rec_countdown;

// 仅在正在走恢复码流程的时候屏蔽主状态机键盘；防窥挂起 peep_hang 传入 safe_fsm 内部处理，保留反挟持能力
wire key_valid_fsm = key_valid && !rec_active;

// 本地密码开锁与 PC 远程开锁合流
wire unlock_all;

// --------------------------------------------------------------------------
// 3. 保险箱主业务状态机 (16位虚位密码、A键首次录入、B键改密、C键提前闭锁)
// --------------------------------------------------------------------------
wire [3:0] state_code;
wire [4:0] pwd_len;
wire [1:0] err_count;
wire [8:0] lock_countdown;
wire       unlock_en;
wire       duress_trig;
wire       pwd_err_pulse;
wire       lock_timeout_pulse;
wire       beep_key;
wire       beep_err;
wire       beep_lock;
wire       beep_succ;

safe_fsm #(
    .DEFAULT_PWD       ({4'h1, 4'h2, 4'h3, 4'h4, 4'h5, 4'h6}), // 预设密码: 123456
    .DURESS_PWD        ({4'h6, 4'h5, 4'h4, 4'h3, 4'h2, 4'h1}), // 反挟持密码: 654321
    .LOCK_TIMEOUT_SEC  (60),                                  // 首档锁定 60 秒
    .OP_TIMEOUT_SEC    (15)                                   // 15 秒无操作看门狗
) u_safe_fsm (
    .clk               (clk_50M),
    .rst_n             (rst_sync_n),      // 漏洞 1.1 修复: safe_fsm 复位不重置密码与锁定
    .tick_1k           (tick_1k),
    .key_val           (key_val),
    .key_valid         (key_valid_fsm),
    .duress_clear      (cmd_safe),        // 收到 'S' 清反挟持粘滞报警
    .peep_hang         (peep_hang),       // 防窥挂起输入，内部保留反挟持求救
    .pwd_reset         (reset_req),       // 恢复码验证成功触发重置出厂密码
    .remote_auth_err   (auth_err),        // P1: 远程挑战认证失败计入错误次数并触发阶梯锁定
    .state_code        (state_code),
    .pwd_len           (pwd_len),
    .err_count         (err_count),
    .lock_countdown    (lock_countdown),
    .unlock_en         (unlock_en),
    .duress_alarm      (),                // 瑕疵 2.5 清理: 未用信号悬空
    .duress_trig       (duress_trig),
    .pwd_err_pulse     (pwd_err_pulse),
    .lock_timeout_pulse(lock_timeout_pulse),
    .pwd_changed       (),                // 瑕疵 2.5 清理: 未用信号悬空
    .beep_key          (beep_key),
    .beep_err          (beep_err),
    .beep_lock         (beep_lock),
    .beep_succ         (beep_succ)
);

assign unlock_all = unlock_en | remote_unlock;

// 开锁上升沿与重新闭锁下降沿检测
reg unlock_en_d1;
always @(posedge clk_50M or negedge rst_sync_n) begin
    if (!rst_sync_n) begin
        unlock_en_d1 <= 1'b0;
    end else begin
        unlock_en_d1 <= unlock_all;
    end
end
wire unlock_rise  = unlock_all  && !unlock_en_d1;
wire relock_pulse = !unlock_all && unlock_en_d1;
wire evt_unlock   = unlock_rise && !duress_trig;

// --------------------------------------------------------------------------
// 4. 板载 SW1 门磁模拟检测及 15 秒超时报警 / 锁闭防撬报警
// --------------------------------------------------------------------------
wire       door_open;
wire       door_alert;
wire       door_alert_pulse;
wire       tamper_alert;
wire       tamper_pulse;

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
    .tamper_alert(tamper_alert),
    .tamper_pulse(tamper_pulse),
    .open_sec_cnt()             // 未用悬空 (清理瑕疵 2.5)
);

wire door_alert_comb = door_alert | tamper_alert;

// --------------------------------------------------------------------------
// 5. 板载无源蜂鸣器 PWM 驱动 (按键音、错误警告音、锁定严重警报、成功和弦，0 DSP)
// --------------------------------------------------------------------------
wire beep_key_comb = beep_key | rec_beep_key;
wire beep_err_comb = beep_err | rec_beep_err | rec_err | auth_err;

buzzer_driver #(
    .CLK_FREQ(50_000_000)
) u_buzzer_driver (
    .clk       (clk_50M),
    .rst_n     (rst_sync_n),
    .tick_1k   (tick_1k),
    .beep_key  (beep_key_comb),
    .beep_err  (beep_err_comb),
    .beep_lock (beep_lock),
    .beep_succ (beep_succ | rec_ok),
    .beep_alarm(door_alert_comb),
    .buzzer_out(buzzer_out)
);

// --------------------------------------------------------------------------
// 6. 板载 4 位共阴数码管底层状态代码监控
//    防窥挂起时整块灭掉 (段选清零、位选全关)，采用寄存器打拍输出以打包进 IOB OREG
// --------------------------------------------------------------------------
wire [7:0] seg_out_raw;
wire [3:0] seg_cs_raw;
wire [3:0] seg_state_mux = rec_locked ? 4'd4 : (rec_active ? 4'd11 : state_code);
wire [4:0] seg_len_mux   = rec_active ? ((rec_ui_mode == 2'd1) ? 5'd30 : ((rec_ui_mode == 2'd2) ? 5'd31 : {2'b00, rec_len})) : pwd_len;
wire [8:0] seg_cd_mux    = rec_locked ? {1'b0, rec_countdown} : lock_countdown;

seg_display u_seg_display (
    .clk           (clk_50M),
    .rst_n         (rst_sync_n),
    .tick_1k       (tick_1k),
    .state_code    (seg_state_mux),
    .pwd_len       (seg_len_mux),
    .err_count     (err_count),
    .lock_countdown(seg_cd_mux),
    .door_alert    (door_alert_comb),
    .seg_out       (seg_out_raw),
    .seg_cs        (seg_cs_raw)
);

reg [7:0] seg_out_r;
reg [3:0] seg_cs_r;

always @(posedge clk_50M or negedge rst_sync_n) begin
    if (!rst_sync_n) begin
        seg_out_r <= 8'h00;
        seg_cs_r  <= 4'hF;
    end else if (peep_hang && !door_alert_comb) begin
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
// 7. LED0 1Hz 系统存活心跳指示
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
// 8. 板载 8 位 LED 状态指示映射 (声光电立体直观反馈)
// --------------------------------------------------------------------------
// led[0]: 1Hz 系统存活心跳灯 (闪烁表示 50MHz 时钟与系统存活)
// led[1]: 实时按键物理按下指示 (按住常亮，松开熄灭)
// led[2]: 密码核验成功开锁指示灯 (含远程开锁，高电平点亮 3 秒)
// led[3]: 系统锁定指示灯 (连续输错 3 次后在 60s 内常亮)
// led[4]: 错误报警指示灯 (处于密码错误状态时点亮)
// led[5]: 门物理状态指示 (门开点亮，门关严熄灭)
// led[6]: 输错次数累计指示 1 (输错 1 次点亮)
// led[7]: 输错次数累计指示 2 或 门未关超时警报 (报警时常亮)
// --------------------------------------------------------------------------
assign led[0] = hb_led;
assign led[1] = key_pressed;
assign led[2] = unlock_all;
assign led[3] = (state_code == 4'd4) | rec_locked;
assign led[4] = (state_code == 4'd3);
assign led[5] = door_open;
assign led[6] = (err_count >= 2'd1);
assign led[7] = (err_count >= 2'd2) | door_alert_comb;

// --------------------------------------------------------------------------
// 9. UART 邮差与 PC 数字孪生 OLED 状态快照同步
// --------------------------------------------------------------------------
uart_mailman #(
    .CLK_FREQ(50_000_000),
    .BAUD(115_200),
    .REMOTE_HOLD_SEC(3)
) u_mailman (
    .clk           (clk_50M),
    .rst_n         (rst_sync_n),
    .tick_1k       (tick_1k),
    .uart_rx       (uart_rx),
    .uart_tx       (uart_tx),
    .evt_unlock    (evt_unlock),
    .evt_lock      (beep_lock),
    .evt_duress    (duress_trig),
    .evt_door      (door_alert_pulse),
    .evt_tamper    (tamper_pulse),
    .evt_lock_end  (lock_timeout_pulse),
    .evt_relock    (relock_pulse),
    .evt_pwd_err   (pwd_err_pulse),
    .is_locked     (state_code == 4'd4),
    .state_code    (state_code),
    .pwd_len       (pwd_len),
    .err_count     (err_count),
    .lock_countdown(lock_countdown),
    .rec_active    (rec_active),
    .rec_len       (rec_len),
    .rec_locked    (rec_locked),
    .rec_countdown (rec_countdown[5:0]),
    .door_alert    (door_alert_comb),
    .peep_hang     (peep_hang),
    .remote_unlock (remote_unlock),
    .auth_err      (auth_err),
    .cmd_safe      (cmd_safe),
    .is_sending    (), // 未用悬空 (清理瑕疵 2.5)
    .the_letter    ()  // 未用悬空 (清理瑕疵 2.5)
);

// --------------------------------------------------------------------------
// 10. 恢复码通道 (忘了密码时用)
//     待机按 D -> 输 6 位恢复码 -> 对了密码打回 123456
//     sw_recovery(A14) 不拨上去, D 键完全无效
//     默认恢复码 937158 (对应 PRESENT 密文哈希摘要 24'hC905ED, 全芯片无明文驻留)
// --------------------------------------------------------------------------
recovery_mgr #(
    .RECOVERY_CODE_HASH (24'hC905ED),
    .MAX_TRY            (3),
    .LOCK_SEC           (60),
    .OP_TIMEOUT_SEC     (30)
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
    .rec_try      (), // 未用悬空 (清理瑕疵 2.5)
    .rec_ui_mode  (rec_ui_mode),
    .rec_beep_key (rec_beep_key),
    .rec_beep_err (rec_beep_err),
    .rec_err      (rec_err),
    .rec_ok       (rec_ok),
    .rec_locked   (rec_locked),
    .rec_countdown(rec_countdown)
);

// --------------------------------------------------------------------------
// 11. P1: 外部实物机械锁舌舵机 (SG90) 50Hz PWM 发生器 (软硬件双模设计)
//     板载 LED2 (B16) 100% 保持点亮 3 秒 (零接线高可靠保底)
//     同时 servo_pwm 输出标准舵机脉冲 (驱动亚克力实物箱舵机旋转开门)
//     周期: 20ms (1,000,000 个 50MHz 时钟周期)
//     闭锁脉宽: 1.0ms (50,000 周期, 舵机 0 度, 锁舌伸出锁门)
//     开锁脉宽: 2.0ms (100,000 周期, 舵机 90度, 锁舌缩回开锁)
// --------------------------------------------------------------------------
reg [19:0] servo_cnt;
reg        servo_pwm_r;

always @(posedge clk_50M or negedge rst_sync_n) begin
    if (!rst_sync_n) begin
        servo_cnt   <= 20'd0;
        servo_pwm_r <= 1'b0;
    end else begin
        if (servo_cnt >= 20'd999_999) begin
            servo_cnt <= 20'd0;
        end else begin
            servo_cnt <= servo_cnt + 20'd1;
        end

        // 脉冲产生: 开锁 2.0ms, 闭锁 1.0ms
        if (unlock_all) begin
            servo_pwm_r <= (servo_cnt < 20'd100_000);
        end else begin
            servo_pwm_r <= (servo_cnt < 20'd50_000);
        end
    end
end

assign servo_pwm = servo_pwm_r;

endmodule

`endif
