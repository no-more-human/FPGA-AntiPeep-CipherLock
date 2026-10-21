// ==============================================================================
// 工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
// 模块名称: servo_driver (SG90 9g 微型舵机 50Hz PWM 控制器)
// 阶段任务: Day 6 - 50Hz PWM 发生器 (0.5ms 闭锁, 1.5ms 开锁, 0 DSP 纯计数器实现)
// 硬件平台: 安路 (Anlogic) EG4S20BG256 (PWM_Servo: F14)
// ==============================================================================

`timescale 1ns / 1ps

`ifndef __SERVO_DRIVER_V__
`define __SERVO_DRIVER_V__

module servo_driver #(
    parameter CLK_FREQ     = 50_000_000, // 50MHz 系统主时钟
    parameter PERIOD_CNT   = 1_000_000,  // 20ms 基准周期 (50Hz: 50,000,000 / 50 = 1,000,000)
    parameter PULSE_0_DEG  = 25_000,     // 0.5ms 高电平脉宽: 0° 闭锁位置 (25,000 拍)
    parameter PULSE_90_DEG = 75_000      // 1.5ms 高电平脉宽: 90° 开锁位置 (75,000 拍)
)(
    input  wire clk,        // 50MHz 主时钟
    input  wire rst_n,      // 同步复位 (低有效)
    input  wire unlock_en,  // 开锁使能 (1: 旋转至 90° 开锁; 0: 回弹至 0° 闭锁)
    output reg  servo_pwm   // SG90 舵机 PWM 控制信号输出 (引脚: F14)
);

// 20ms 周期计数器 (0 ~ 999,999)
reg [19:0] cnt_20ms;

// 目标脉宽门限选择 (纯多路器，无需复杂乘除)
wire [19:0] target_pulse = unlock_en ? PULSE_90_DEG[19:0] : PULSE_0_DEG[19:0];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt_20ms  <= 20'd0;
        servo_pwm <= 1'b0;
    end else begin
        // 周期计数
        if (cnt_20ms >= (PERIOD_CNT - 1)) begin
            cnt_20ms <= 20'd0;
        end else begin
            cnt_20ms <= cnt_20ms + 20'd1;
        end

        // PWM 方波输出打拍 (无毛刺)
        servo_pwm <= (cnt_20ms < target_pulse);
    end
end

endmodule

`endif
