// ==============================================================================
// 工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
// 模块名称: seg_display (板载 4 位共阴数码管动态扫描驱动模块)
// 阶段任务: Day 3~5 - 板载 4 位数码管底层状态代码监控 (IDLE/INPUT/OPEN/Err/L-60)
// 硬件平台: 安路 (Anlogic) EG4S20BG256 (段选: A4,A6,B8,E8,A7,B5,A8,C8; 位选: C9,B6,A5,A3)
// ==============================================================================

`timescale 1ns / 1ps

`ifndef __SEG_DISPLAY_V__
`define __SEG_DISPLAY_V__

module seg_display(
    input  wire       clk,             // 50MHz 系统主时钟
    input  wire       rst_n,           // 异步复位 (低有效)
    input  wire       tick_1k,         // 1kHz (1ms) 系统节拍，用作位选扫描时钟
    
    // 状态接口输入 (来自主状态机, 扩充为 4 位)
    input  wire [3:0] state_code,      // 0:IDLE, 1:INPUT, 2:SUCCESS, 3:ERROR, 4:LOCKED, 5~10:SET/CHG
    input  wire [4:0] pwd_len,         // 当前已输入密码长度 (日常开锁 0~16, 录入/改密 0~6)
    input  wire [1:0] err_count,       // 输错次数 (0~3)
    input  wire [6:0] lock_countdown,  // 锁定剩余倒计时秒数 (0~60)
    
    // 硬件物理引脚输出
    output reg  [7:0] seg_out,         // 段选输出 DP,G,F,E,D,C,B,A (高电平点亮)
    output reg  [3:0] seg_cs           // 位选输出 COM1~COM4 (低电平有效选通)
);

// --------------------------------------------------------------------------
// 1. 段码常数定义 (共阴极: 高电平 1 点亮对应段)
// 段位顺序: bit7=DP, bit6=G, bit5=F, bit4=E, bit3=D, bit2=C, bit1=B, bit0=A
// --------------------------------------------------------------------------
localparam SEG_0    = 8'h3F; // 0
localparam SEG_1    = 8'h06; // 1
localparam SEG_2    = 8'h5B; // 2
localparam SEG_3    = 8'h4F; // 3
localparam SEG_4    = 8'h66; // 4
localparam SEG_5    = 8'h6D; // 5
localparam SEG_6    = 8'h7D; // 6
localparam SEG_7    = 8'h07; // 7
localparam SEG_8    = 8'h7F; // 8
localparam SEG_9    = 8'h6F; // 9
localparam SEG_DASH = 8'h40; // -
localparam SEG_BLANK= 8'h00; // 空白
localparam SEG_I    = 8'h06; // I
localparam SEG_d    = 8'h5E; // d
localparam SEG_L    = 8'h38; // L
localparam SEG_E    = 8'h79; // E
localparam SEG_O    = 8'h3F; // O
localparam SEG_P    = 8'h73; // P
localparam SEG_n    = 8'h54; // n
localparam SEG_r    = 8'h50; // r
localparam SEG_S    = 8'h6D; // S
localparam SEG_t    = 8'h78; // t
localparam SEG_C    = 8'h39; // C
localparam SEG_A    = 8'h77; // A
localparam SEG_u    = 8'h1C; // u
localparam SEG_F    = 8'h71; // F

// 数字转段码函数
function [7:0] digit_to_seg(input [3:0] num);
    case (num)
        4'd0: digit_to_seg = SEG_0;
        4'd1: digit_to_seg = SEG_1;
        4'd2: digit_to_seg = SEG_2;
        4'd3: digit_to_seg = SEG_3;
        4'd4: digit_to_seg = SEG_4;
        4'd5: digit_to_seg = SEG_5;
        4'd6: digit_to_seg = SEG_6;
        4'd7: digit_to_seg = SEG_7;
        4'd8: digit_to_seg = SEG_8;
        4'd9: digit_to_seg = SEG_9;
        default: digit_to_seg = SEG_BLANK;
    endcase
endfunction

// --------------------------------------------------------------------------
// 2. 状态映射到 4 位显示缓冲区
// --------------------------------------------------------------------------
reg [7:0] seg_buf0; // 最右位 (COM4, CS[0])
reg [7:0] seg_buf1; // 第 3 位 (COM3, CS[1])
reg [7:0] seg_buf2; // 第 2 位 (COM2, CS[2])
reg [7:0] seg_buf3; // 最左位 (COM1, CS[3])

wire [3:0] lock_tens = (lock_countdown >= 7'd60) ? 4'd6 :
                       (lock_countdown >= 7'd50) ? 4'd5 :
                       (lock_countdown >= 7'd40) ? 4'd4 :
                       (lock_countdown >= 7'd30) ? 4'd3 :
                       (lock_countdown >= 7'd20) ? 4'd2 :
                       (lock_countdown >= 7'd10) ? 4'd1 : 4'd0;

wire [6:0] lock_tens_x10 = {lock_tens, 3'b000} + {2'b00, lock_tens, 1'b0}; // 8x + 2x = 10x (完全消除DSP)
wire [6:0] lock_ones_7b  = lock_countdown - lock_tens_x10;
wire [3:0] lock_ones     = lock_ones_7b[3:0];

// 输入位数十位/个位 (虚位密码最长 16 位，0~16)
wire       len_ge10  = (pwd_len >= 5'd10);
wire [4:0] len_ones5 = len_ge10 ? (pwd_len - 5'd10) : pwd_len;
wire [3:0] len_ones  = len_ones5[3:0];

always @(*) begin
    case (state_code)
        4'd0: begin // IDLE: 显示 "IdLE"
            seg_buf3 = SEG_I;
            seg_buf2 = SEG_d;
            seg_buf1 = SEG_L;
            seg_buf0 = SEG_E;
        end
        
        4'd1: begin // INPUT: 显示 "P-nn" (P, -, 已输入位数十位(不足10为空白), 个位; 0~16)
            seg_buf3 = SEG_P;
            seg_buf2 = SEG_DASH;
            seg_buf1 = len_ge10 ? SEG_1 : SEG_BLANK;
            seg_buf0 = digit_to_seg(len_ones);
        end
        
        4'd2: begin // SUCCESS: 显示 "OPEn"
            seg_buf3 = SEG_O;
            seg_buf2 = SEG_P;
            seg_buf1 = SEG_E;
            seg_buf0 = SEG_n;
        end
        
        4'd3: begin // ERROR: 显示 "Err1" / "Err2" / "Err3"
            seg_buf3 = SEG_E;
            seg_buf2 = SEG_r;
            seg_buf1 = SEG_r;
            seg_buf0 = digit_to_seg({2'b00, err_count});
        end
        
        4'd4: begin // LOCKED: 显示 "L-xx" (例如 "L-60", "L-59" ... "L-01")
            seg_buf3 = SEG_L;
            seg_buf2 = SEG_DASH;
            seg_buf1 = digit_to_seg(lock_tens);
            seg_buf0 = digit_to_seg(lock_ones);
        end
        
        4'd5: begin // S_SET_NEW: 显示 "SEt n" (A键首次录入新密码)
            seg_buf3 = SEG_S;
            seg_buf2 = SEG_E;
            seg_buf1 = SEG_t;
            seg_buf0 = digit_to_seg(pwd_len[3:0]);
        end

        4'd6: begin // S_SET_CFM: 显示 "CFn n" (A键确认新密码)
            seg_buf3 = SEG_C;
            seg_buf2 = SEG_F;
            seg_buf1 = SEG_n;
            seg_buf0 = digit_to_seg(pwd_len[3:0]);
        end

        4'd7: begin // S_CHG_AUTH: 显示 "Aut n" (B键验旧密码)
            seg_buf3 = SEG_A;
            seg_buf2 = SEG_u;
            seg_buf1 = SEG_t;
            seg_buf0 = digit_to_seg(pwd_len[3:0]);
        end

        4'd8: begin // S_CHG_NEW: 显示 "nE- n" (B键输入新密码)
            seg_buf3 = SEG_n;
            seg_buf2 = SEG_E;
            seg_buf1 = SEG_DASH;
            seg_buf0 = digit_to_seg(pwd_len[3:0]);
        end

        4'd9: begin // S_CHG_CFM: 显示 "CF- n" (B键确认新密码)
            seg_buf3 = SEG_C;
            seg_buf2 = SEG_F;
            seg_buf1 = SEG_DASH;
            seg_buf0 = digit_to_seg(pwd_len[3:0]);
        end

        4'd10: begin // S_OP_DONE: 显示 "PASS" (设置/修改完成)
            seg_buf3 = SEG_P;
            seg_buf2 = SEG_A;
            seg_buf1 = SEG_S;
            seg_buf0 = SEG_S;
        end
        
        default: begin
            seg_buf3 = SEG_DASH;
            seg_buf2 = SEG_DASH;
            seg_buf1 = SEG_DASH;
            seg_buf0 = SEG_DASH;
        end
    endcase
end

// --------------------------------------------------------------------------
// 3. 4 位动态扫描逻辑: 1ms 刷新 1 位, 整屏 250Hz, 绝对无闪烁
// CS 编码定义 (低电平选通):
//   cs_idx = 2'd0 -> seg_cs = 4'b1110 (选通 COM4, 最右位 LSB)
//   cs_idx = 2'd1 -> seg_cs = 4'b1101 (选通 COM3, 第 3 位)
//   cs_idx = 2'd2 -> seg_cs = 4'b1011 (选通 COM2, 第 2 位)
//   cs_idx = 2'd3 -> seg_cs = 4'b0111 (选通 COM1, 最左位 MSB)
// --------------------------------------------------------------------------
reg [1:0] scan_idx;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        scan_idx <= 2'd0;
        seg_cs   <= 4'b1111; // 全灭
        seg_out  <= 8'h00;
    end else if (tick_1k) begin
        scan_idx <= scan_idx + 2'd1;
        case (scan_idx)
            2'd0: begin
                seg_cs  <= 4'b1110; // 选通 COM4
                seg_out <= seg_buf0;
            end
            2'd1: begin
                seg_cs  <= 4'b1101; // 选通 COM3
                seg_out <= seg_buf1;
            end
            2'd2: begin
                seg_cs  <= 4'b1011; // 选通 COM2
                seg_out <= seg_buf2;
            end
            2'd3: begin
                seg_cs  <= 4'b0111; // 选通 COM1
                seg_out <= seg_buf3;
            end
        endcase
    end
end

endmodule

`endif
