// ==============================================================================
// 工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
// 模块名称: voice_player (JQ8900-16P 单线串口 One-Line 语音播报驱动模块)
// 阶段任务: Day 5 - 3.3V 安全驱动、微秒级脉宽发生器、100ms防重入、BUSY状态自适应
// 硬件平台: 安路 (Anlogic) EG4S20BG256 (Voice_TX: H16, Voice_Busy: G16)
// ==============================================================================

`timescale 1ns / 1ps

`ifndef __VOICE_PLAYER_V__
`define __VOICE_PLAYER_V__

module voice_player #(
    parameter CLK_FREQ          = 50_000_000, // 50MHz 系统主时钟
    parameter BUSY_ACTIVE_LEVEL = 1'b0        // BUSY 播放有效电平 (低电平有效)
)(
    input  wire       clk,        // 50MHz 主时钟
    input  wire       rst_n,      // 异步复位 (低有效)
    input  wire       tick_1k,    // 1kHz (1ms) 系统节拍脉冲
    
    // 控制与播报指令输入
    input  wire       play_en,    // 播放使能触发脉冲 (单周期有效)
    input  wire [7:0] track_num,  // 播放曲目编号 (0x01~0x07)
    
    // 物理硬件接口 (JQ8900-16P)
    input  wire       voice_busy, // 模块 BUSY 引脚状态 (引脚: G16, 需 PULLUP)
    output reg        voice_tx,   // 单线串口 One-Line 发送端 (引脚: H16)
    
    // 模块工作状态输出
    output wire       is_busy     // 正在发送或正在播放忙指示
);

// --------------------------------------------------------------------------
// 1. 产生 1µs 基准节拍 (50MHz 下 50 个周期 = 1µs)
// --------------------------------------------------------------------------
reg [5:0] us_cnt;
wire      us_tick = (us_cnt == 6'd49);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        us_cnt <= 6'd0;
    end else if (us_tick) begin
        us_cnt <= 6'd0;
    end else begin
        us_cnt <= us_cnt + 6'd1;
    end
end

// --------------------------------------------------------------------------
// 2. 单线串口时序状态机定义
// JQ8900 One-Line 协议规范:
// - 空闲状态: 高电平
// - 起始信号: 4ms 低电平引导码
// - 数据编码 (8位 LSB 先发):
//     Bit 1: 1300µs 高 + 500µs 低
//     Bit 0: 500µs 高 + 1300µs 低
// - 停止信号: 发完拉高 2ms
// - 防重入冷却: 发送结束后至少 100ms 忽略新触发，防止撕裂爆音
// --------------------------------------------------------------------------
localparam S_IDLE      = 3'd0;
localparam S_START     = 3'd1;
localparam S_BIT_HIGH  = 3'd2;
localparam S_BIT_LOW   = 3'd3;
localparam S_STOP      = 3'd4;
localparam S_COOLDOWN  = 3'd5;

reg [2:0]  state;
reg [15:0] timer_us;     // 微秒计时器
reg [2:0]  bit_idx;      // 0~7 位索引
reg [7:0]  shift_reg;    // 移位数据寄存器
reg [7:0]  cooldown_cnt; // 100ms 防重入冷却计数器

// 外部/内部综合 busy 判定
assign is_busy = (state != S_IDLE) || (voice_busy == BUSY_ACTIVE_LEVEL);

// 计算当前 Bit 高电平与低电平持续时间
wire [15:0] high_duration = shift_reg[0] ? 16'd1300 : 16'd500;
wire [15:0] low_duration  = shift_reg[0] ? 16'd500  : 16'd1300;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state        <= S_IDLE;
        voice_tx     <= 1'b1; // 空闲保持高电平
        timer_us     <= 16'd0;
        bit_idx      <= 3'd0;
        shift_reg    <= 8'd0;
        cooldown_cnt <= 8'd0;
    end else begin
        case (state)
            // --------------------------------------------------------------
            // 空闲态: 等待播放使能 (防重入保护: is_busy 时不接受新触发)
            // --------------------------------------------------------------
            S_IDLE: begin
                voice_tx <= 1'b1;
                timer_us <= 16'd0;
                if (play_en && !is_busy) begin
                    shift_reg <= track_num;
                    bit_idx   <= 3'd0;
                    state     <= S_START;
                end
            end

            // --------------------------------------------------------------
            // 起始信号: 持续拉低 4000µs (4ms)
            // --------------------------------------------------------------
            S_START: begin
                voice_tx <= 1'b0;
                if (us_tick) begin
                    if (timer_us >= 16'd3999) begin
                        timer_us <= 16'd0;
                        state    <= S_BIT_HIGH;
                    end else begin
                        timer_us <= timer_us + 16'd1;
                    end
                end
            end

            // --------------------------------------------------------------
            // 数据位高电平阶段: '1' -> 1300µs, '0' -> 500µs
            // --------------------------------------------------------------
            S_BIT_HIGH: begin
                voice_tx <= 1'b1;
                if (us_tick) begin
                    if (timer_us >= (high_duration - 1)) begin
                        timer_us <= 16'd0;
                        state    <= S_BIT_LOW;
                    end else begin
                        timer_us <= timer_us + 16'd1;
                    end
                end
            end

            // --------------------------------------------------------------
            // 数据位低电平阶段: '1' -> 500µs, '0' -> 1300µs
            // --------------------------------------------------------------
            S_BIT_LOW: begin
                voice_tx <= 1'b0;
                if (us_tick) begin
                    if (timer_us >= (low_duration - 1)) begin
                        timer_us  <= 16'd0;
                        shift_reg <= {1'b0, shift_reg[7:1]}; // LSB 先发，右移
                        if (bit_idx >= 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                            state   <= S_BIT_HIGH;
                        end
                    end else begin
                        timer_us <= timer_us + 16'd1;
                    end
                end
            end

            // --------------------------------------------------------------
            // 停止信号: 释放拉高至少 2000µs (2ms)
            // --------------------------------------------------------------
            S_STOP: begin
                voice_tx <= 1'b1;
                if (us_tick) begin
                    if (timer_us >= 16'd1999) begin
                        timer_us     <= 16'd0;
                        cooldown_cnt <= 8'd100; // 开启 100ms 防重入冷却
                        state        <= S_COOLDOWN;
                    end else begin
                        timer_us <= timer_us + 16'd1;
                    end
                end
            end

            // --------------------------------------------------------------
            // 防重入冷却态: 维持 100ms 且等待 BUSY 信号释放
            // --------------------------------------------------------------
            S_COOLDOWN: begin
                voice_tx <= 1'b1;
                if (tick_1k) begin
                    if (cooldown_cnt > 8'd0) begin
                        cooldown_cnt <= cooldown_cnt - 8'd1;
                    end else if (voice_busy != BUSY_ACTIVE_LEVEL) begin
                        // 100ms 冷却结束且模块空闲，退出回待机
                        state <= S_IDLE;
                    end
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule

`endif
