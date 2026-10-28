`timescale 1ns / 1ps

`ifndef __RECOVERY_MGR_V__
`define __RECOVERY_MGR_V__

// THE_GREAT_TASQUE_MANAGER_inpassword
//
// 忘了密码的时候用。待机按 D,输 6 位恢复码,对了就把密码打回 123456。
// 恢复码错 3 次锁 60 秒。sw_recovery(A14) 不拨上去,D 键根本不理你。
//
// 恢复码就在下面 RECOVERY_CODE 那行里。忘了就来看源码,或者直接重烧板子 ——
// 能碰到板子的人本来就有全部权限,这个模块防的是"知道密码以外的人"。
//
// 跟 safe_fsm 的关系:一个字节都没改。成功时出一拍 reset_req,top.v 拿它
// 单独复位 safe_fsm,密码寄存器就在复位分支里被打回 DEFAULT_PWD。
module THE_GREAT_TASQUE_MANAGER_inpassword #(
    parameter [23:0] RECOVERY_CODE   = {4'h9, 4'h3, 4'h7, 4'h1, 4'h5, 4'h8},
    parameter integer MAX_TRY        = 3,
    parameter integer LOCK_SEC       = 60,
    parameter integer OP_TIMEOUT_SEC = 30
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
    output reg         rec_err,        // 错误一拍(接蜂鸣器)
    output reg         rec_ok,         // 成功一拍(接蜂鸣器/语音)
    output reg         rec_locked,     // 锁死中
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

wire [23:0] code_in = {buf0, buf1, buf2, buf3, buf4, buf5};

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
        rec_err       <= 1'b0;
        rec_ok        <= 1'b0;
        rec_locked    <= 1'b0;
        rec_countdown <= 8'd0;
        ms_timer      <= 12'd0;
        sec_cnt       <= 10'd0;
        wd_ms         <= 15'd0;
    end else begin
        // 两个都是脉冲,平时清掉
        reset_req <= 1'b0;
        rec_err   <= 1'b0;
        rec_ok    <= 1'b0;

        case (st)
        // ------------------------------------------------------------
        // 等人按 D。开关没拨上去就当没这回事
        // ------------------------------------------------------------
        S_IDLE: begin
            rec_active <= 1'b0;
            rec_len    <= 3'd0;
            rec_locked <= 1'b0;
            wd_ms      <= 15'd0;
            if (sw_recovery && key_valid && (key_val == K_D) && (state_code == 4'd0)) begin
                rec_active <= 1'b1;
                rec_try    <= 2'd0;
                wd_ms      <= OP_TIMEOUT_SEC * 1000;
                buf0 <= 4'h0; buf1 <= 4'h0; buf2 <= 4'h0;
                buf3 <= 4'h0; buf4 <= 4'h0; buf5 <= 4'h0;
                st <= S_CODE;
            end
        end

        // ------------------------------------------------------------
        // 输恢复码
        // ------------------------------------------------------------
        S_CODE: begin
            // 30 秒没动静就自己退出,别把人挂在这儿
            if (key_valid) begin
                wd_ms <= OP_TIMEOUT_SEC * 1000;
            end else if (tick_1k) begin
                if (wd_ms > 15'd0) wd_ms <= wd_ms - 15'd1;
                else begin
                    rec_active <= 1'b0;
                    rec_len    <= 3'd0;
                    rec_err    <= 1'b1;
                    st         <= S_IDLE;
                end
            end

            if (key_valid) begin
                if (key_val <= 4'h9) begin
                    if (rec_len < 3'd6) begin
                        put_digit(rec_len, key_val);
                        rec_len <= rec_len + 3'd1;
                    end
                end
                else if (key_val == K_STAR) begin
                    if (rec_len > 3'd0) begin
                        rec_len <= rec_len - 3'd1;     // 退一位
                    end else begin
                        rec_active <= 1'b0;            // 空的时候按 = 取消
                        st         <= S_IDLE;
                    end
                end
                else if (key_val == K_HASH) begin
                    if (rec_len == 3'd6) begin
                        if (code_in == RECOVERY_CODE) begin
                            rec_ok     <= 1'b1;
                            reset_req  <= 1'b1;        // 密码打回 123456
                            rec_try    <= 2'd0;
                            rec_len    <= 3'd0;
                            ms_timer   <= 12'd1500;
                            st         <= S_GOOD;
                        end else begin
                            rec_err <= 1'b1;
                            rec_len <= 3'd0;
                            if (rec_try >= (MAX_TRY - 1)) begin
                                rec_countdown <= LOCK_SEC;
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
        // 成功提示,1.5 秒后回待机
        // ------------------------------------------------------------
        S_GOOD: begin
            rec_active <= 1'b1;
            if (tick_1k) begin
                if (ms_timer > 12'd0) ms_timer <= ms_timer - 12'd1;
                else begin
                    rec_active <= 1'b0;
                    st         <= S_IDLE;
                end
            end
        end

        // ------------------------------------------------------------
        // 错误提示,1.5 秒后回去接着试
        // ------------------------------------------------------------
        S_BAD: begin
            rec_active <= 1'b1;
            if (tick_1k) begin
                if (ms_timer > 12'd0) ms_timer <= ms_timer - 12'd1;
                else begin
                    wd_ms <= OP_TIMEOUT_SEC * 1000;
                    st    <= S_CODE;
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
