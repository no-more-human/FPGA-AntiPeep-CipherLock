// ==============================================================================
// 工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
// 模块名称: top (系统顶级入口模块)
// 阶段任务: Day 2 - 4x4 矩阵键盘驱动挂接、20ms 消抖验证与板载 LED 键值二进制显示
// 硬件平台: 安路 (Anlogic) EG4S20BG256 (使用板载自带 4x4 矩阵键盘)
// ==============================================================================

`timescale 1ns / 1ps

`include "keypad_scan.v"

module top(
    input  wire       clk_50M, // 50MHz 系统主时钟输入 (引脚: R7)
    input  wire       rst_n,   // 全局异步复位，低电平有效 (引脚: E3，外接按键 KEY1/RST)
    
    // 4x4 矩阵键盘接口 (直接复用板载 4x4 微动与外接薄膜键盘)
    input  wire [3:0] key_row, // 4 行输入 (引脚: E10, C10, F9, D9) 内部配置 PULLUP
    output wire [3:0] key_col, // 4 列输出 (引脚: E11, D11, C11, F10) 轮流低电平扫描
    
    // 8 位板载 LED 指示灯 (高电平点亮)
    output wire [7:0] led      // led[0]~led[7] (引脚: B14, B15, B16, C15, C16, E13, E16, F16)
);

// --------------------------------------------------------------------------
// 1. 系统节拍时钟发生器
//    产生 1kHz (1ms) 与 100Hz (10ms) 单周期使能脉冲
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
// 2. 4x4 矩阵键盘扫描驱动与 20ms 硬件消抖模块
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
// 3. LED0 心跳指示逻辑: 1Hz 匀速闪烁 (亮 0.5 秒, 灭 0.5 秒)
//    指示 FPGA 内部 50MHz 时钟与主循环健康运行
// --------------------------------------------------------------------------
reg [8:0] hb_cnt; // 0 ~ 499 (共 500ms)
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
// 4. 按键行为特征指示逻辑 (消抖与无抖动验证核心)
// --------------------------------------------------------------------------
// 4.1 消抖翻转指示灯: 每次成功触发有效按键 (key_valid)，电平翻转一次
//     若有机械抖动连击，该灯会连闪；无连击时每按一次必翻转一次！
reg key_toggle;
always @(posedge clk_50M or negedge rst_n) begin
    if (!rst_n) begin
        key_toggle <= 1'b0;
    end else if (key_valid) begin
        key_toggle <= ~key_toggle;
    end
end

// 4.2 单次按键脉冲 100ms 展宽指示灯 (使用户肉眼能清晰捕捉毫秒级短按)
reg [6:0] pulse_cnt; // 0 ~ 100 (ms)
reg       pulse_led;

always @(posedge clk_50M or negedge rst_n) begin
    if (!rst_n) begin
        pulse_cnt <= 7'd0;
        pulse_led <= 1'b0;
    end else if (key_valid) begin
        pulse_cnt <= 7'd100;
        pulse_led <= 1'b1;
    end else if (tick_1k && (pulse_cnt > 7'd0)) begin
        pulse_cnt <= pulse_cnt - 7'd1;
        if (pulse_cnt == 7'd1) begin
            pulse_led <= 1'b0;
        end
    end
end

// 4.3 4 位二进制键值锁存寄存器: 松手后依然保持显示最近一次敲击的键值
reg [3:0] key_val_latched;

always @(posedge clk_50M or negedge rst_n) begin
    if (!rst_n) begin
        key_val_latched <= 4'h0;
    end else if (key_valid) begin
        key_val_latched <= key_val;
    end
end

// --------------------------------------------------------------------------
// 5. 板载 8 位 LED 信号映射 (交付标准: 准确显示键值二进制，按键无连击抖动)
// --------------------------------------------------------------------------
// led[0]: 1Hz 系统存活心跳灯 (延续 Day 1 交付特性)
// led[1]: 实时按键按下指示灯 (按住常亮，松开熄灭)
// led[2]: 消抖翻转测试灯 (每按一次翻转一次，验证无连击与无抖动)
// led[3]: 按键脉冲 100ms 展宽指示灯 (捕捉单次有效敲击)
// led[4]: 键值二进制 Bit 0 (最低位 LSB)
// led[5]: 键值二进制 Bit 1
// led[6]: 键值二进制 Bit 2
// led[7]: 键值二进制 Bit 3 (最高位 MSB)
// --------------------------------------------------------------------------
assign led[0]   = hb_led;
assign led[1]   = key_pressed;
assign led[2]   = key_toggle;
assign led[3]   = pulse_led;
assign led[7:4] = key_val_latched;

endmodule
