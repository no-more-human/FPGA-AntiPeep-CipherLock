// ==============================================================================
// 工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
// 模块名称: buzzer_driver (无源蜂鸣器 PWM 驱动与和弦音效生成器)
// 阶段任务: Day 4~5 - 无源蜂鸣器 PWM 驱动 (1kHz 按键音、4kHz 报警音、开锁和弦音，0 DSP 优化)
// 硬件平台: 安路 (Anlogic) EG4S20BG256 (板载无源蜂鸣器 引脚: H11)
// ==============================================================================

`timescale 1ns / 1ps

`ifndef __BUZZER_DRIVER_V__
`define __BUZZER_DRIVER_V__

module buzzer_driver #(
    parameter CLK_FREQ = 50_000_000 // 50MHz 系统主时钟
)(
    input  wire       clk,        // 50MHz 系统主时钟
    input  wire       rst_n,      // 异步复位 (低有效)
    input  wire       tick_1k,    // 1kHz (1ms) 系统节拍脉冲
    
    // 音效触发脉冲信号 (单周期有效)
    input  wire       beep_key,   // 按键提示音触发 (1kHz 短鸣 50ms)
    input  wire       beep_err,   // 密码错误警告音触发 (2.5kHz 鸣响 300ms)
    input  wire       beep_lock,  // 严重锁定报警音触发 (4kHz 快速脉冲报警 1.2s)
    input  wire       beep_succ,  // 开锁成功和弦音触发 (Do-Mi-Sol 依次鸣响 240ms)
    
    output reg        buzzer_out  // 驱动板载蜂鸣器输出 (引脚: H11)
);

// --------------------------------------------------------------------------
// 1. 各音调在 50MHz 下的半周期计数值定义 (PWM 50% 占空比方波)
// --------------------------------------------------------------------------
localparam HALF_CNT_1KHZ  = 32'd25_000; // 1000 Hz 按键音
localparam HALF_CNT_2K5HZ = 32'd10_000; // 2500 Hz 错误警告音
localparam HALF_CNT_4KHZ  = 32'd6_250;  // 4000 Hz 锁定严重警报音

// 开锁成功三音阶和弦 (C6=1046Hz, E6=1318Hz, G6=1568Hz)
localparam HALF_CNT_DO    = 32'd23_887; // C6: 1046 Hz
localparam HALF_CNT_MI    = 32'd18_968; // E6: 1318 Hz
localparam HALF_CNT_SOL   = 32'd15_943; // G6: 1568 Hz

// --------------------------------------------------------------------------
// 2. 音效工作状态定义
// --------------------------------------------------------------------------
localparam S_IDLE = 3'd0;
localparam S_KEY  = 3'd1;
localparam S_ERR  = 3'd2;
localparam S_LOCK = 3'd3;
localparam S_SUCC = 3'd4;

reg [2:0]  state;
reg [11:0] duration_cnt; // 毫秒持续时间计数器 (基于 tick_1k)
reg [7:0]  lock_phase;   // 0~199 循环相位计数器 (替代 % 200，完全消除 DSP 占用 P0-D)
reg [31:0] target_half_cnt;
reg        tone_en;      // 当前是否输出方波使能

// --------------------------------------------------------------------------
// 3. 状态机调度与持续时间控制
// --------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state           <= S_IDLE;
        duration_cnt    <= 12'd0;
        lock_phase      <= 8'd0;
        target_half_cnt <= 32'd0;
        tone_en         <= 1'b0;
    end else begin
        // 高优先级触发检测
        if (beep_lock) begin
            state           <= S_LOCK;
            duration_cnt    <= 12'd1200; // 持续 1.2 秒快速间歇报警
            lock_phase      <= 8'd0;
            target_half_cnt <= HALF_CNT_4KHZ;
            tone_en         <= 1'b1;
        end else if (beep_succ && (state != S_LOCK)) begin
            state           <= S_SUCC;
            duration_cnt    <= 12'd240;  // 3 * 80ms = 240ms 和弦
            target_half_cnt <= HALF_CNT_DO;
            tone_en         <= 1'b1;
        end else if (beep_err && (state != S_LOCK) && (state != S_SUCC)) begin
            state           <= S_ERR;
            duration_cnt    <= 12'd300;  // 持续 300ms 错误警示音
            target_half_cnt <= HALF_CNT_2K5HZ;
            tone_en         <= 1'b1;
        end else if (beep_key && (state == S_IDLE)) begin
            state           <= S_KEY;
            duration_cnt    <= 12'd50;   // 持续 50ms 清脆按键音
            target_half_cnt <= HALF_CNT_1KHZ;
            tone_en         <= 1'b1;
        end else if (tick_1k) begin
            if (duration_cnt > 12'd0) begin
                duration_cnt <= duration_cnt - 12'd1;
                
                // 状态细化控制
                case (state)
                    S_KEY: begin
                        target_half_cnt <= HALF_CNT_1KHZ;
                        tone_en         <= 1'b1;
                    end
                    
                    S_ERR: begin
                        target_half_cnt <= HALF_CNT_2K5HZ;
                        tone_en         <= 1'b1;
                    end
                    
                    S_LOCK: begin
                        // 4kHz 间歇脉冲报警: 100ms 鸣响, 100ms 静音交替 (无除法器/无DSP)
                        target_half_cnt <= HALF_CNT_4KHZ;
                        tone_en         <= (lock_phase < 8'd100);
                        if (lock_phase >= 8'd199) begin
                            lock_phase <= 8'd0;
                        end else begin
                            lock_phase <= lock_phase + 8'd1;
                        end
                    end
                    
                    S_SUCC: begin
                        // 和弦三阶跳频 (80ms Do -> 80ms Mi -> 80ms Sol)
                        if (duration_cnt > 12'd160) begin
                            target_half_cnt <= HALF_CNT_DO;
                        end else if (duration_cnt > 12'd80) begin
                            target_half_cnt <= HALF_CNT_MI;
                        end else begin
                            target_half_cnt <= HALF_CNT_SOL;
                        end
                        tone_en <= 1'b1;
                    end
                    
                    default: begin
                        tone_en <= 1'b0;
                    end
                endcase
            end else begin
                state      <= S_IDLE;
                lock_phase <= 8'd0;
                tone_en    <= 1'b0;
            end
        end
    end
end

// --------------------------------------------------------------------------
// 4. PWM 方波发生器 (50% 占空比)
// --------------------------------------------------------------------------
reg [31:0] pwm_cnt;
reg        pwm_wave;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pwm_cnt    <= 32'd0;
        pwm_wave   <= 1'b0;
        buzzer_out <= 1'b0;
    end else if (tone_en && (target_half_cnt > 32'd0)) begin
        if (pwm_cnt >= (target_half_cnt - 1)) begin
            pwm_cnt  <= 32'd0;
            pwm_wave <= ~pwm_wave;
        end else begin
            pwm_cnt <= pwm_cnt + 32'd1;
        end
        buzzer_out <= pwm_wave;
    end else begin
        pwm_cnt    <= 32'd0;
        pwm_wave   <= 1'b0;
        buzzer_out <= 1'b0; // 静音时输出低电平，避免直流功耗
    end
end

endmodule

`endif
