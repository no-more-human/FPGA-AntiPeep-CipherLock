// ==============================================================================
// 工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
// 模块名称: keypad_scan (4x4 矩阵键盘扫描与硬件消抖模块)
// 阶段任务: Day 2 - 4x4 矩阵键盘扫描驱动、20ms 延时滤波硬件消抖与键值译码
// 硬件平台: 安路 (Anlogic) EG4S20BG256 (兼容板载 4x4 微动与外接薄膜键盘)
// ==============================================================================

`timescale 1ns / 1ps

`ifndef __KEYPAD_SCAN_V__
`define __KEYPAD_SCAN_V__

module keypad_scan #(
    parameter DEBOUNCE_TIME = 20 // 消抖滤波时间常数: 20ms (基于 1kHz 节拍)
)(
    input  wire       clk,         // 50MHz 系统主时钟
    input  wire       rst_n,       // 全局异步复位 (低电平有效)
    input  wire       tick_1k,     // 1kHz (1ms) 系统节拍脉冲
    
    // 物理键盘接口 (对应 FPGA 引脚)
    input  wire [3:0] key_row,     // 行输入信号 Row[3:0] (内部配置 PULLUP，按下为低电平 0)
    output reg  [3:0] key_col,     // 列扫描输出 Col[3:0] (轮流输出低电平 0 扫描)
    
    // 用户逻辑接口
    output reg  [3:0] key_val,     // 当前识别并锁存的 4 位键值 (0x0 ~ 0xF)
    output reg        key_valid,   // 单周期按键有效脉冲 (消抖后产生，按一次仅产生一个脉冲)
    output reg        key_pressed  // 按键处于被按下状态 (高电平有效，按住常高，松开变低)
);

// --------------------------------------------------------------------------
// 0. key_row 外部异步输入双级触发器同步 (2FF 同步器，消除亚稳态)
// --------------------------------------------------------------------------
reg [3:0] key_row_meta;
reg [3:0] key_row_sync;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        key_row_meta <= 4'hF;
        key_row_sync <= 4'hF;
    end else begin
        key_row_meta <= key_row;
        key_row_sync <= key_row_meta;
    end
end

// --------------------------------------------------------------------------
// 1. 列扫描逻辑: 每 1ms 切换扫描一列 (循环周期 4ms, 刷新率 250Hz)
// --------------------------------------------------------------------------
reg [1:0]  col_idx;
reg [15:0] raw_matrix; // 16 位矩阵按键采样寄存器 (1 表示有按键闭合)

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        col_idx    <= 2'd0;
        key_col    <= 4'b1110;
        raw_matrix <= 16'd0;
    end else if (tick_1k) begin
        // 采样当前列对应的 4 个行信号 (内部上拉，按下为 0，取反后 1 代表按下)
        case (col_idx)
            2'd0: raw_matrix[3:0]   <= ~key_row_sync;
            2'd1: raw_matrix[7:4]   <= ~key_row_sync;
            2'd2: raw_matrix[11:8]  <= ~key_row_sync;
            2'd3: raw_matrix[15:12] <= ~key_row_sync;
        endcase
        
        // 步进到下一列并输出低电平选通
        col_idx <= col_idx + 2'd1;
        case (col_idx + 2'd1)
            2'd0: key_col <= 4'b1110; // 选通第 0 列 (Col0 拉低)
            2'd1: key_col <= 4'b1101; // 选通第 1 列 (Col1 拉低)
            2'd2: key_col <= 4'b1011; // 选通第 2 列 (Col2 拉低)
            2'd3: key_col <= 4'b0111; // 选通第 3 列 (Col3 拉低)
        endcase
    end
end

// --------------------------------------------------------------------------
// 2. 16位按键优先级译码器 (调转 180° 旋转映射: 1<->D, 2<->#, 3<->0, A<->*, 4<->C, 5<->9, 6<->8, B<->7)
// 调转 180° 后键位映射:
//   Col 0 (E11)  Col 1 (D11)  Col 2 (C11)  Col 3 (F10)
//   -----------  -----------  -----------  -----------
// Row 0 (E10):  D (0xD)      # (0xF)      0 (0x0)      * (0xE)
// Row 1 (C10):  C (0xC)      9 (0x9)      8 (0x8)      7 (0x7)
// Row 2 (F9):   B (0xB)      6 (0x6)      5 (0x5)      4 (0x4)
// Row 3 (D9):   A (0xA)      3 (0x3)      2 (0x2)      1 (0x1)
// --------------------------------------------------------------------------
reg [3:0] decoded_val;
reg       decoded_any;

always @(*) begin
    decoded_any = 1'b1;
    case (1'b1)
        // 第 0 列 (Col 0)
        raw_matrix[0]:  decoded_val = 4'hD; // Row 0, Col 0: 'D' (原 1)
        raw_matrix[1]:  decoded_val = 4'hC; // Row 1, Col 0: 'C' (原 4)
        raw_matrix[2]:  decoded_val = 4'hB; // Row 2, Col 0: 'B' (原 7)
        raw_matrix[3]:  decoded_val = 4'hA; // Row 3, Col 0: 'A' (原 *)
        // 第 1 列 (Col 1)
        raw_matrix[4]:  decoded_val = 4'hF; // Row 0, Col 1: '#' (原 2)
        raw_matrix[5]:  decoded_val = 4'h9; // Row 1, Col 1: '9' (原 5)
        raw_matrix[6]:  decoded_val = 4'h6; // Row 2, Col 1: '6' (原 8)
        raw_matrix[7]:  decoded_val = 4'h3; // Row 3, Col 1: '3' (原 0)
        // 第 2 列 (Col 2)
        raw_matrix[8]:  decoded_val = 4'h0; // Row 0, Col 2: '0' (原 3)
        raw_matrix[9]:  decoded_val = 4'h8; // Row 1, Col 2: '8' (原 6)
        raw_matrix[10]: decoded_val = 4'h5; // Row 2, Col 2: '5' (原 9)
        raw_matrix[11]: decoded_val = 4'h2; // Row 3, Col 2: '2' (原 #)
        // 第 3 列 (Col 3)
        raw_matrix[12]: decoded_val = 4'hE; // Row 0, Col 3: '*' (原 A)
        raw_matrix[13]: decoded_val = 4'h7; // Row 1, Col 3: '7' (原 B)
        raw_matrix[14]: decoded_val = 4'h4; // Row 2, Col 3: '4' (原 C)
        raw_matrix[15]: decoded_val = 4'h1; // Row 3, Col 3: '1' (原 D)
        default: begin
            decoded_val = 4'h0;
            decoded_any = 1'b0;
        end
    endcase
end

// --------------------------------------------------------------------------
// 3. 20ms 延时滤波硬件消抖状态机 (双向消抖: 按下消抖与释放消抖)
// 保证每次敲击严格仅产生一个 key_valid 脉冲，绝无连击与毛刺
// --------------------------------------------------------------------------
localparam S_IDLE             = 2'd0; // 空闲态: 等待按键按下
localparam S_DEBOUNCE_PRESS   = 2'd1; // 按下消抖: 20ms 连续有效确认
localparam S_PRESSED          = 2'd2; // 按下保持: 等待按键释放 (防按住连击)
localparam S_DEBOUNCE_RELEASE = 2'd3; // 释放消抖: 20ms 连续释放确认

reg [1:0] state;
reg [5:0] db_cnt; // 0~20 (最大 63)
reg [3:0] debouncing_val; // 正在消抖判决的目标键值 (防止滑动按键导致误判)

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state          <= S_IDLE;
        db_cnt         <= 6'd0;
        debouncing_val <= 4'h0;
        key_val        <= 4'h0;
        key_valid      <= 1'b0;
        key_pressed    <= 1'b0;
    end else begin
        key_valid <= 1'b0; // 默认单脉冲清零
        
        case (state)
            S_IDLE: begin
                key_pressed <= 1'b0;
                if (decoded_any) begin
                    db_cnt         <= 6'd0;
                    debouncing_val <= decoded_val;
                    state          <= S_DEBOUNCE_PRESS;
                end
            end
            
            S_DEBOUNCE_PRESS: begin
                if (!decoded_any) begin
                    // 抖动毛刺，未满 20ms 就弹起，直接判定无效回退
                    state <= S_IDLE;
                end else if (decoded_val != debouncing_val) begin
                    // 消抖过程中键值发生改变，重置 20ms 计数器并重新锁定新键值
                    debouncing_val <= decoded_val;
                    db_cnt         <= 6'd0;
                end else if (tick_1k) begin
                    if (db_cnt >= (DEBOUNCE_TIME - 1)) begin
                        // 稳定且键值不变持续满 20ms，确认为真实有效按键
                        key_val     <= debouncing_val;
                        key_valid   <= 1'b1; // 发出单时钟周期有效脉冲
                        key_pressed <= 1'b1; // 置按下状态
                        state       <= S_PRESSED;
                    end else begin
                        db_cnt <= db_cnt + 6'd1;
                    end
                end
            end
            
            S_PRESSED: begin
                key_pressed <= 1'b1;
                if (!decoded_any) begin
                    // 检测到松开趋势，进入释放消抖
                    db_cnt <= 6'd0;
                    state  <= S_DEBOUNCE_RELEASE;
                end
            end
            
            S_DEBOUNCE_RELEASE: begin
                if (decoded_any) begin
                    // 释放过程中的回弹抖动，重回按下状态
                    state <= S_PRESSED;
                end else if (tick_1k) begin
                    if (db_cnt >= (DEBOUNCE_TIME - 1)) begin
                        // 稳定释放满 20ms，确认已完全松开
                        key_pressed <= 1'b0;
                        state       <= S_IDLE;
                    end else begin
                        db_cnt <= db_cnt + 6'd1;
                    end
                end
            end
            
            default: state <= S_IDLE;
        endcase
    end
end

endmodule

`endif
