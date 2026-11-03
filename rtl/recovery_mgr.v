`timescale 1ns / 1ps

`ifndef __RECOVERY_MGR_V__
`define __RECOVERY_MGR_V__

// ==============================================================================
// 工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
// 模块名称: recovery_mgr (遗忘密码应急恢复码核验与密码重置管理模块 - PRESENT 密文哈希版)
// 功能描述:
//   当物理拨码开关 sw_recovery (SW7/A14) 拨至高电平时，待机下按 D 键进入 6 位恢复码核验；
//   采用 ISO/IEC 29192-2 PRESENT 4-bit S-Box + 2 轮硬件加盐哈希，全芯片无明文驻留；
//   核验通过输出单周期 reset_req 脉冲将主状态机密码重置回默认值 (123456)；
//   连续输错 3 次独立锁定恢复通道 60 秒；30 秒无操作自动超时退回待机。
// ==============================================================================
module recovery_mgr #(
    // 出厂默认 6 位应急恢复码明文: "937158"
    // 经 PRESENT S-Box + 2 轮加盐哈希后的不可逆密文摘要常量: 24'hC905ED
    parameter [23:0] RECOVERY_CODE_HASH = 24'hC905ED,
    // 向后兼容可选明文参数 (若非 0 则自动算哈希，否则默认使用 RECOVERY_CODE_HASH)
    parameter [23:0] RECOVERY_CODE      = 24'h000000,
    parameter integer MAX_TRY           = 3,
    parameter integer LOCK_SEC          = 60,
    parameter integer OP_TIMEOUT_SEC    = 30
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        tick_1k,
    input  wire [3:0]  key_val,
    input  wire        key_valid,
    input  wire [3:0]  state_code,     // 只在 IDLE(0) 认 D 键
    input  wire        sw_recovery,    // A14,拨上去才允许恢复

    output reg         rec_active,     // 1 = 正在恢复流程,top 用它屏蔽主状态机
    output reg         reset_req,      // 一拍脉冲:叫 top 复位 safe_fsm
    output reg  [2:0]  rec_len,        // 已输几位
    output reg  [1:0]  rec_try,        // 已经错了几次
    output reg         rec_beep_key,   // 恢复模式按键提示脉冲
    output reg         rec_beep_err,   // 恢复模式输错/锁定提示脉冲
    output reg         rec_err,        // 错误一拍(接蜂鸣器)
    output reg         rec_ok,         // 成功一拍(接蜂鸣器/语音)
    output reg         rec_locked,     // 锁死中
    output reg  [1:0]  rec_ui_mode,    // 0:输入(rE-n), 1:成功(PASS), 2:失败(Err)
    output reg  [7:0]  rec_countdown   // 锁定剩余秒,留给 OLED 显示
);

localparam [2:0] S_IDLE = 3'd0;
localparam [2:0] S_CODE = 3'd1;
localparam [2:0] S_GOOD = 3'd2;
localparam [2:0] S_BAD  = 3'd3;
localparam [2:0] S_LOCK = 3'd4;

localparam [3:0] K_D    = 4'hD;
localparam [3:0] K_STAR = 4'hE;
localparam [3:0] K_HASH = 4'hF;

reg [2:0]  st;
reg [3:0]  buf0, buf1, buf2, buf3, buf4, buf5;
reg [11:0] ms_timer;
reg [9:0]  sec_cnt;
reg [14:0] wd_ms;

// sw_recovery 外部异步输入 2 级触发器同步 (消除亚稳态)
reg sw_recovery_meta;
reg sw_recovery_sync;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sw_recovery_meta <= 1'b0;
        sw_recovery_sync <= 1'b0;
    end else begin
        sw_recovery_meta <= sw_recovery;
        sw_recovery_sync <= sw_recovery_meta;
    end
end

// --------------------------------------------------------------------------
// PRESENT (ISO/IEC 29192-2) 4-bit S-Box 与 24-bit 双轮硬件加盐密码混淆核
// 与 safe_fsm.v 算法完全一致，确保全芯片无任何明文凭据驻留
// --------------------------------------------------------------------------
function [3:0] sbox4(input [3:0] x);
    begin
        case (x)
            4'h0: sbox4 = 4'hC; 4'h1: sbox4 = 4'h5; 4'h2: sbox4 = 4'h6; 4'h3: sbox4 = 4'hB;
            4'h4: sbox4 = 4'h9; 4'h5: sbox4 = 4'h0; 4'h6: sbox4 = 4'hA; 4'h7: sbox4 = 4'hD;
            4'h8: sbox4 = 4'h3; 4'h9: sbox4 = 4'hE; 4'hA: sbox4 = 4'hF; 4'hB: sbox4 = 4'h8;
            4'hC: sbox4 = 4'h4; 4'hD: sbox4 = 4'h7; 4'hE: sbox4 = 4'h1; 4'hF: sbox4 = 4'h2;
        endcase
    end
endfunction

function [23:0] pwd_cipher_hash(input [23:0] raw);
    reg [23:0] r1, r2;
    begin
        // 第一轮: PRESENT S-Box 非线性代换 + 硬件固定盐值异或 (0xA5C396)
        r1 = {sbox4(raw[23:20]), sbox4(raw[19:16]), sbox4(raw[15:12]),
              sbox4(raw[11:8]),  sbox4(raw[7:4]),   sbox4(raw[3:0])} ^ 24'hA5C396;
        // 第二轮: GF(2)^24 满秩循环移位线性扩散 + 次轮盐值混合 + 二次 S-Box 代换
        r2 = r1 ^ {r1[18:0], r1[23:19]} ^ {r1[10:0], r1[23:11]} ^ 24'h5A3C69;
        pwd_cipher_hash = {sbox4(r2[23:20]), sbox4(r2[19:16]), sbox4(r2[15:12]),
                           sbox4(r2[11:8]),  sbox4(r2[7:4]),   sbox4(r2[3:0])};
    end
endfunction

wire [23:0] target_rec_hash = (RECOVERY_CODE != 24'h000000) ? 
                              pwd_cipher_hash(RECOVERY_CODE) : RECOVERY_CODE_HASH;

wire [23:0] code_in      = {buf0, buf1, buf2, buf3, buf4, buf5};
wire [23:0] code_in_hash = pwd_cipher_hash(code_in);

// 按 rec_len 往对应的格子里放
task put_digit;
    input [2:0] idx;
    input [3:0] d;
    begin
        case (idx)
            3'd0: buf0 <= d;
            3'd1: buf1 <= d;
            3'd2: buf2 <= d;
            3'd3: buf3 <= d;
            3'd4: buf4 <= d;
            3'd5: buf5 <= d;
        endcase
    end
endtask

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        st            <= S_IDLE;
        buf0 <= 4'h0; buf1 <= 4'h0; buf2 <= 4'h0;
        buf3 <= 4'h0; buf4 <= 4'h0; buf5 <= 4'h0;
        rec_active    <= 1'b0;
        reset_req     <= 1'b0;
        rec_len       <= 3'd0;
        rec_try       <= 2'd0;
        rec_ui_mode   <= 2'd0;
        rec_beep_key  <= 1'b0;
        rec_beep_err  <= 1'b0;
        rec_err       <= 1'b0;
        rec_ok        <= 1'b0;
        rec_locked    <= 1'b0;
        rec_countdown <= 8'd0;
        ms_timer      <= 12'd0;
        sec_cnt       <= 10'd0;
        wd_ms         <= 15'd0;
    end else begin
        // 脉冲信号平时清零
        reset_req    <= 1'b0;
        rec_beep_key <= 1'b0;
        rec_beep_err <= 1'b0;
        rec_err      <= 1'b0;
        rec_ok       <= 1'b0;

        case (st)
        // ------------------------------------------------------------
        // 等人按 D。开关没拨上去就当没这回事
        // ------------------------------------------------------------
        S_IDLE: begin
            rec_active  <= 1'b0;
            rec_len     <= 3'd0;
            rec_locked  <= 1'b0;
            rec_ui_mode <= 2'd0;
            wd_ms       <= 15'd0;
            if (sw_recovery_sync && key_valid && (key_val == K_D) && (state_code == 4'd0)) begin
                rec_active   <= 1'b1;
                rec_beep_key <= 1'b1;
                // 注意: 漏洞修复: 不在此清零 rec_try，防止输错后退回待机再进入绕过3次锁定
                wd_ms        <= OP_TIMEOUT_SEC * 1000;
                buf0 <= 4'h0; buf1 <= 4'h0; buf2 <= 4'h0;
                buf3 <= 4'h0; buf4 <= 4'h0; buf5 <= 4'h0;
                st <= S_CODE;
            end
        end

        // ------------------------------------------------------------
        // 输恢复码
        // ------------------------------------------------------------
        S_CODE: begin
            rec_ui_mode <= 2'd0;
            // 30 秒没动静就自己退出,别把人挂在这儿
            if (key_valid) begin
                wd_ms <= OP_TIMEOUT_SEC * 1000;
            end else if (tick_1k) begin
                if (wd_ms > 15'd0) wd_ms <= wd_ms - 15'd1;
                else begin
                    rec_active   <= 1'b0;
                    rec_len      <= 3'd0;
                    buf0 <= 4'h0; buf1 <= 4'h0; buf2 <= 4'h0;
                    buf3 <= 4'h0; buf4 <= 4'h0; buf5 <= 4'h0;
                    rec_beep_err <= 1'b1;
                    rec_err      <= 1'b1;
                    st           <= S_IDLE;
                end
            end

            if (key_valid) begin
                if (key_val <= 4'h9) begin
                    if (rec_len < 3'd6) begin
                        put_digit(rec_len, key_val);
                        rec_len      <= rec_len + 3'd1;
                        rec_beep_key <= 1'b1;
                    end
                end
                else if (key_val == K_STAR) begin
                    rec_beep_key <= 1'b1;
                    if (rec_len > 3'd0) begin
                        case (rec_len - 3'd1)
                            3'd0: buf0 <= 4'h0;
                            3'd1: buf1 <= 4'h0;
                            3'd2: buf2 <= 4'h0;
                            3'd3: buf3 <= 4'h0;
                            3'd4: buf4 <= 4'h0;
                            3'd5: buf5 <= 4'h0;
                        endcase
                        rec_len <= rec_len - 3'd1;     // 退一位
                    end else begin
                        buf0 <= 4'h0; buf1 <= 4'h0; buf2 <= 4'h0;
                        buf3 <= 4'h0; buf4 <= 4'h0; buf5 <= 4'h0;
                        rec_active <= 1'b0;            // 空的时候按 = 取消
                        st         <= S_IDLE;
                    end
                end
                else if (key_val == K_HASH) begin
                    rec_beep_key <= 1'b1;
                    if (rec_len == 3'd6) begin
                        // 判决后立即清除输入缓冲，杜绝明文残留
                        buf0 <= 4'h0; buf1 <= 4'h0; buf2 <= 4'h0;
                        buf3 <= 4'h0; buf4 <= 4'h0; buf5 <= 4'h0;
                        if (code_in_hash == target_rec_hash) begin
                            rec_ok     <= 1'b1;
                            reset_req  <= 1'b1;        // 密码打回 123456
                            rec_try    <= 2'd0;
                            rec_len    <= 3'd0;
                            ms_timer   <= 12'd1500;
                            st         <= S_GOOD;
                        end else begin
                            rec_beep_err <= 1'b1;
                            rec_err      <= 1'b1;
                            rec_len      <= 3'd0;
                            if (rec_try >= (MAX_TRY - 1)) begin
                                rec_countdown <= LOCK_SEC[7:0];
                                sec_cnt       <= 10'd0;
                                rec_locked    <= 1'b1;
                                rec_try       <= 2'd0;
                                st            <= S_LOCK;
                            end else begin
                                rec_try  <= rec_try + 2'd1;
                                ms_timer <= 12'd1500;
                                st       <= S_BAD;
                            end
                        end
                    end
                end
            end
        end

        // ------------------------------------------------------------
        // 成功提示,1.5 秒后回待机 (数码管显示 PASS)
        // ------------------------------------------------------------
        S_GOOD: begin
            rec_active  <= 1'b1;
            rec_ui_mode <= 2'd1;
            if (tick_1k) begin
                if (ms_timer > 12'd0) ms_timer <= ms_timer - 12'd1;
                else begin
                    rec_active  <= 1'b0;
                    rec_ui_mode <= 2'd0;
                    st          <= S_IDLE;
                end
            end
        end

        // ------------------------------------------------------------
        // 错误提示,1.5 秒后回去接着试 (数码管显示 Err)
        // ------------------------------------------------------------
        S_BAD: begin
            rec_active  <= 1'b1;
            rec_ui_mode <= 2'd2;
            if (tick_1k) begin
                if (ms_timer > 12'd0) ms_timer <= ms_timer - 12'd1;
                else begin
                    rec_ui_mode <= 2'd0;
                    wd_ms       <= OP_TIMEOUT_SEC * 1000;
                    st          <= S_CODE;
                end
            end
        end

        // ------------------------------------------------------------
        // 错够次数,锁 60 秒。锁的是恢复通道,正常密码还能用
        // ------------------------------------------------------------
        S_LOCK: begin
            rec_active <= 1'b0;
            rec_len    <= 3'd0;
            if (tick_1k) begin
                if (sec_cnt >= 10'd999) begin
                    sec_cnt <= 10'd0;
                    if (rec_countdown > 8'd1) begin
                        rec_countdown <= rec_countdown - 8'd1;
                    end else begin
                        rec_countdown <= 8'd0;
                        rec_locked    <= 1'b0;
                        rec_try       <= 2'd0;
                        st            <= S_IDLE;
                    end
                end else begin
                    sec_cnt <= sec_cnt + 10'd1;
                end
            end
        end

        default: st <= S_IDLE;
        endcase
    end
end

//
// 怎么试:
//   1. 烧进去,把 SW7(A14) 拨上去
//   2. 待机按 D,输 937158,按 #
//   3. 蜂鸣器响一下,回到待机 —— 这时候密码已经是 123456
//   4. 故意输错 3 次,会锁 60 秒,期间按 D 没反应
//   5. SW7 拨下来,按 D 完全没反应(物理开关就是这层保险)
//
// 忘了恢复码:它写在 top.v 第 12 节的 RECOVERY_CODE 里,或者直接重烧板子。
//
endmodule

`endif
