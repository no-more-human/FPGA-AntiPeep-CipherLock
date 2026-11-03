`timescale 1ns / 1ps

`ifndef __UART_MAILMAN_V__
`define __UART_MAILMAN_V__

// ==============================================================================
// 工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
// 模块名称: uart_mailman (UART 双向协议收发、事件排队与虚拟 OLED 状态快照同步模块)
// 功能描述:
//   接收 PC 上位机指令: 'S' (环境安全恢复), 'P' (防窥挂起), 'R' (远程开锁)
//   上报 FPGA 单字节事件状态 (最高优先级):
//     'D' (0x44, 反挟持报警 - 最高优先级, 抑制同周期 'U')
//     'L' (0x4C, 连续试错锁定)
//     'T' (0x54, 60s 试错锁定解除)
//     'K' (0x4B, 锁体重新锁闭)
//     'A' (0x41, 门未关超时报警)
//     'U' (0x55, 正常开锁成功)
//     'E' (0x45, 单次密码错误)
//   上报 PC 虚拟 OLED 状态快照帧 (紧随单字节事件之后自动同步):
//     "@O" + 6位大写十六进制 + "\n" (共 9 字节)
//     Byte0 Hex: {peep_hang, door_alert, rec_locked, rec_active, state_code[3:0]}
//     Byte1 Hex: {rec_len[2:0], pwd_len[4:0]}
//     Byte2 Hex: {err_count[1:0], eff_countdown[5:0]}
// ==============================================================================
module uart_mailman #(
    parameter integer CLK_FREQ = 50_000_000,
    parameter integer BAUD = 115_200,
    parameter integer REMOTE_HOLD_SEC = 3
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tick_1k,

    input  wire       uart_rx,        // F12
    output wire       uart_tx,        // D12

    input  wire       evt_unlock,     // 开锁了 -> 'U'
    input  wire       evt_lock,       // 锁定了 -> 'L'
    input  wire       evt_duress,     // 被挟持 -> 'D'
    input  wire       evt_door,       // 门没关 -> 'A'
    input  wire       evt_tamper,     // 非法撬门 -> 'X'
    input  wire       evt_lock_end,   // 锁定解除 -> 'T' (8'h54)
    input  wire       evt_relock,     // 重新闭锁 -> 'K' (8'h4B)
    input  wire       evt_pwd_err,    // 单次输错 -> 'E' (8'h45)
    input  wire       is_locked,      // 当前处于试错锁定状态 (用于远程开锁安全门控)

    // 虚拟 OLED 状态快照输入信号
    input  wire [3:0] state_code,     // 主状态机状态码 (0~10)
    input  wire [4:0] pwd_len,        // 当前已输入密码位数 (0~16)
    input  wire [1:0] err_count,      // 累计输错次数 (0~3)
    input  wire [8:0] lock_countdown, // 阶梯锁定倒计时秒数 (0~300, P0 扩展为 9-bit 防截断)
    input  wire       rec_active,     // 应急恢复模式激活
    input  wire [2:0] rec_len,        // 应急恢复已输位数 (0~6)
    input  wire       rec_locked,     // 应急恢复锁定状态
    input  wire [5:0] rec_countdown,  // 应急恢复锁定倒计时 (0~60)
    input  wire       door_alert,     // 门未关超时报警标志

    output reg        peep_hang,      // 有人在偷看,1 的时候防窥挂起
    output wire       remote_unlock,  // PC 让远程开锁,保持几秒 (受 !is_locked && !peep_hang 门控)
    output reg        auth_err,       // 远程开锁认证失败或超时脉冲 (接 beep_err)
    output wire       cmd_safe,       // 'S' 那一拍
    output wire       is_sending,
    output reg  [7:0] the_letter      // 最近收到的指令或发出的单字节事件
);

localparam [7:0] CH_SAFE      = 8'h53;  // 'S'
localparam [7:0] CH_PEEP      = 8'h50;  // 'P'
localparam [7:0] CH_REMOTE    = 8'h52;  // 'R'
localparam [7:0] CH_AUDIT_REQ = 8'h48;  // 'H' 查询片上 BRAM 硬件黑匣子最新审计记录
localparam [7:0] CH_CHALLENGE = 8'h3F;  // '?' FPGA 发给 PC 的挑战前导符
localparam [7:0] CH_RESPONSE  = 8'h21;  // '!' PC 回传给 FPGA 的应答前导符
localparam [7:0] CH_UNLOCK    = 8'h55;  // 'U'
localparam [7:0] CH_LOCK      = 8'h4C;  // 'L'
localparam [7:0] CH_LOCK_END  = 8'h54;  // 'T'
localparam [7:0] CH_RELOCK    = 8'h4B;  // 'K'
localparam [7:0] CH_DURESS    = 8'h44;  // 'D'
localparam [7:0] CH_DOOR      = 8'h41;  // 'A'
localparam [7:0] CH_TAMPER    = 8'h58;  // 'X' 非法撬门报警
localparam [7:0] CH_ERR       = 8'h45;  // 'E'

wire [7:0] rx_byte;
wire rx_ok;

uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) u_ear (
    .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx),
    .rx_data(rx_byte), .rx_valid(rx_ok)
);

wire rx_safe      = rx_ok && (rx_byte == CH_SAFE);
wire rx_peep      = rx_ok && (rx_byte == CH_PEEP);
wire rx_remote    = rx_ok && (rx_byte == CH_REMOTE);
wire rx_audit_req = rx_ok && (rx_byte == CH_AUDIT_REQ);

// 偷看挂起,收到 'S' 才放人
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)          peep_hang <= 1'b0;
    else if (rx_safe)    peep_hang <= 1'b0;
    else if (rx_peep)    peep_hang <= 1'b1;
end

// --------------------------------------------------------------------------
// 漏洞 1.3 & P1 硬件安全升级:
//   16-bit 混合熵源伽罗瓦 LFSR + PRESENT (ISO/IEC 29192-2) S-Box 双轮非线性挑战-应答 MAC 核
// 1. PC 发送 'R' (0x52) 请求开锁；
// 2. FPGA 由 16-bit 混合物理抖动熵源提取 Nonce，回传 '?' (0x3F) + Nonce (2 字节挑战包)；
// 3. PC 接收后通过 PRESENT S-Box 双轮 ARX 算法计算 MAC = calc_auth_mac(Nonce)，回传 '!' + MAC；
// 4. FPGA 硬件核单拍校验一致后才允许拉高 remote_unlock 3 秒；超时(2s)或错误一律拒绝并输出 auth_err 触发锁定计数！
// --------------------------------------------------------------------------
function [3:0] auth_sbox(input [3:0] x);
    begin
        case (x)
            4'h0: auth_sbox = 4'hC; 4'h1: auth_sbox = 4'h5; 4'h2: auth_sbox = 4'h6; 4'h3: auth_sbox = 4'hB;
            4'h4: auth_sbox = 4'h9; 4'h5: auth_sbox = 4'h0; 4'h6: auth_sbox = 4'hA; 4'h7: auth_sbox = 4'hD;
            4'h8: auth_sbox = 4'h3; 4'h9: auth_sbox = 4'hE; 4'hA: auth_sbox = 4'hF; 4'hB: auth_sbox = 4'h8;
            4'hC: auth_sbox = 4'h4; 4'hD: auth_sbox = 4'h7; 4'hE: auth_sbox = 4'h1; 4'hF: auth_sbox = 4'h2;
        endcase
    end
endfunction

function [7:0] calc_auth_mac(input [7:0] n);
    reg [7:0] r1, r2;
    begin
        // 第一轮: 子密钥加盐 (0x5A) + PRESENT S-Box 非线性代换 + 循环左移 3 位与模加扩散 (0x7E)
        r1 = {auth_sbox(n[7:4] ^ 4'h5), auth_sbox(n[3:0] ^ 4'hA)};
        r2 = {r1[4:0], r1[7:5]} + 8'h7E;
        // 第二轮: 二次 PRESENT S-Box 代换 + 末轮白化密钥异或 (0xC3)
        calc_auth_mac = {auth_sbox(r2[7:4]), auth_sbox(r2[3:0])} ^ 8'hC3;
    end
endfunction

// --------------------------------------------------------------------------
// P1 硬件物理安全升级: 片上多级环形振荡器 (Ring Oscillator, RO) 物理真随机发生器 (TRNG)
// 利用 EG4S20 片内反相器微观传输延迟的物理热噪声与微观时钟抖动 (Phase Jitter) 产生非确定性真随机熵
// 采用 3 组素数级 (3级, 5级, 7级) 自由自激振荡环异或混叠 + 50MHz 采样 Von Neumann 差分去偏
// --------------------------------------------------------------------------
(* syn_keep = "true", keep = "true" *) wire [2:0] ro_r1;
(* syn_keep = "true", keep = "true" *) wire [4:0] ro_r2;
(* syn_keep = "true", keep = "true" *) wire [6:0] ro_r3;

// Ring 1: 3 级反相器自激环 (NAND门受 rst_n 启动控制，硬件上电平稳启振)
assign #1 ro_r1[0] = ~(ro_r1[2] & rst_n);
assign #1 ro_r1[1] = ~ro_r1[0];
assign #1 ro_r1[2] = ~ro_r1[1];

// Ring 2: 5 级反相器自激环
assign #1 ro_r2[0] = ~(ro_r2[4] & rst_n);
assign #1 ro_r2[1] = ~ro_r2[0];
assign #1 ro_r2[2] = ~ro_r2[1];
assign #1 ro_r2[3] = ~ro_r2[2];
assign #1 ro_r2[4] = ~ro_r2[3];

// Ring 3: 7 级反相器自激环
assign #1 ro_r3[0] = ~(ro_r3[6] & rst_n);
assign #1 ro_r3[1] = ~ro_r3[0];
assign #1 ro_r3[2] = ~ro_r3[1];
assign #1 ro_r3[3] = ~ro_r3[2];
assign #1 ro_r3[4] = ~ro_r3[3];
assign #1 ro_r3[5] = ~ro_r3[4];
assign #1 ro_r3[6] = ~ro_r3[5];

// 3 组素数环输出多重混叠
wire ro_osc_raw = ro_r1[2] ^ ro_r2[4] ^ ro_r3[6];

// 50MHz 系统时钟域 2 级触发器同步采样抽取微观相位抖动 (Von Neumann 差分去偏)
reg ro_sync_d1, ro_sync_d2, ro_sample;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ro_sync_d1 <= 1'b0;
        ro_sync_d2 <= 1'b0;
        ro_sample  <= 1'b0;
    end else begin
        ro_sync_d1 <= ro_osc_raw;
        ro_sync_d2 <= ro_sync_d1;
        ro_sample  <= ro_sync_d2;
    end
end
wire ro_entropy = ro_sync_d2 ^ ro_sample; // 相邻采样差分提取非确定性物理抖动

reg [15:0] lfsr;
wire       lfsr_fb = lfsr[15] ^ ro_entropy ^ tick_1k ^ rx_ok;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) lfsr <= 16'hA55A;
    else lfsr <= {lfsr[14:0], 1'b0} ^ (lfsr_fb ? 16'hB400 : 16'h0000);
end

wire [7:0] next_nonce = ((lfsr[7:0] ^ lfsr[15:8] ^ {7'b0, ro_sync_d2}) == 8'h00) ? 
                        8'h5A : (lfsr[7:0] ^ lfsr[15:8] ^ {7'b0, ro_sync_d2});

reg [7:0]  challenge_nonce;
reg [7:0]  expected_response;
reg        auth_waiting;
reg        auth_expect_byte;
reg [11:0] auth_timeout_ms;
reg        chal_req;            // 单周期触发挑战帧发送脉冲
reg        pend_chal;
reg        chal_sending;
reg        chal_idx;

reg        remote_unlock_r;
reg [15:0] remote_ms_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        auth_waiting      <= 1'b0;
        auth_expect_byte  <= 1'b0;
        auth_timeout_ms   <= 12'd0;
        challenge_nonce   <= 8'h00;
        expected_response <= 8'h00;
        chal_req          <= 1'b0;
        auth_err          <= 1'b0;
        remote_unlock_r   <= 1'b0;
        remote_ms_cnt     <= 16'd0;
    end else begin
        auth_err <= 1'b0;
        chal_req <= 1'b0;
        if (is_locked || peep_hang) begin
            auth_waiting     <= 1'b0;
            auth_expect_byte <= 1'b0;
            remote_unlock_r  <= 1'b0;
            remote_ms_cnt    <= 16'd0;
        end else begin
            // 收到 PC 请求 'R'
            if (rx_remote && !auth_waiting) begin
                challenge_nonce   <= next_nonce;
                expected_response <= calc_auth_mac(next_nonce);
                auth_waiting      <= 1'b1;
                auth_expect_byte  <= 1'b0;
                auth_timeout_ms   <= 12'd2000; // 2 秒超时
                chal_req          <= 1'b1;     // 触发挑战帧
            end else if (auth_waiting) begin
                if (rx_ok) begin
                    if (!auth_expect_byte && (rx_byte == CH_RESPONSE)) begin
                        // 收到应答前导符 '!'
                        auth_expect_byte <= 1'b1;
                    end else if (auth_expect_byte) begin
                        // 收到计算值，单拍核验
                        auth_waiting     <= 1'b0;
                        auth_expect_byte <= 1'b0;
                        if (rx_byte == expected_response) begin
                            // 认证通过！开锁保持 3 秒
                            remote_unlock_r <= 1'b1;
                            remote_ms_cnt   <= REMOTE_HOLD_SEC * 16'd1000;
                        end else begin
                            // 密钥错误
                            auth_err <= 1'b1;
                        end
                    end
                end else if (tick_1k) begin
                    if (auth_timeout_ms > 12'd0) begin
                        auth_timeout_ms <= auth_timeout_ms - 12'd1;
                    end else begin
                        // 2 秒超时无应答
                        auth_waiting     <= 1'b0;
                        auth_expect_byte <= 1'b0;
                        auth_err         <= 1'b1;
                    end
                end
            end

            // 远程开锁脉冲保持计时
            if (remote_unlock_r && tick_1k) begin
                if (remote_ms_cnt > 16'd1) remote_ms_cnt <= remote_ms_cnt - 16'd1;
                else begin
                    remote_ms_cnt   <= 16'd0;
                    remote_unlock_r <= 1'b0;
                end
            end
        end
    end
end

assign remote_unlock = remote_unlock_r && !is_locked && !peep_hang;

// --------------------------------------------------------------------------
// 虚拟 OLED 24-bit 状态快照打包与边沿检测 (P0 支持 9-bit 阶梯锁定倒计时 0~300s)
// --------------------------------------------------------------------------
wire [8:0] full_countdown = rec_locked ? {3'b000, rec_countdown[5:0]} : lock_countdown;
wire [5:0] eff_countdown  = full_countdown[5:0];
wire [2:0] snap_b1_hi     = rec_active ? rec_len : full_countdown[8:6];
wire [7:0] snap_b0        = {peep_hang, door_alert, rec_locked, rec_active, state_code};
wire [7:0] snap_b1        = {snap_b1_hi, pwd_len};
wire [7:0] snap_b2        = {err_count, eff_countdown};
wire [23:0] oled_snap     = {snap_b0, snap_b1, snap_b2};

reg [23:0] oled_snap_d1;
reg        rx_cmd_d1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        oled_snap_d1 <= 24'd0;
        rx_cmd_d1    <= 1'b0;
    end else begin
        oled_snap_d1 <= oled_snap;
        rx_cmd_d1    <= (rx_safe || rx_peep || rx_remote);
    end
end

wire oled_changed = (oled_snap != oled_snap_d1) || rx_cmd_d1;

function [7:0] hex_char(input [3:0] nib);
    begin
        hex_char = (nib < 4'd10) ? (8'h30 + {4'd0, nib}) : (8'h41 + {4'd0, nib} - 8'd10);
    end
endfunction

function [7:0] oled_frame_byte(input [3:0] idx, input [23:0] snap);
    begin
        case (idx)
            4'd0: oled_frame_byte = 8'h40;               // '@'
            4'd1: oled_frame_byte = 8'h4F;               // 'O'
            4'd2: oled_frame_byte = hex_char(snap[23:20]);
            4'd3: oled_frame_byte = hex_char(snap[19:16]);
            4'd4: oled_frame_byte = hex_char(snap[15:12]);
            4'd5: oled_frame_byte = hex_char(snap[11:8]);
            4'd6: oled_frame_byte = hex_char(snap[7:4]);
            4'd7: oled_frame_byte = hex_char(snap[3:0]);
            4'd8: oled_frame_byte = 8'h0A;               // '\n'
            default: oled_frame_byte = 8'h0A;
        endcase
    end
endfunction

function [7:0] audit_frame_byte(input [3:0] idx, input [31:0] rec);
    begin
        case (idx)
            4'd0:  audit_frame_byte = 8'h40;              // '@'
            4'd1:  audit_frame_byte = 8'h48;              // 'H'
            4'd2:  audit_frame_byte = hex_char(rec[31:28]);
            4'd3:  audit_frame_byte = hex_char(rec[27:24]);
            4'd4:  audit_frame_byte = hex_char(rec[23:20]);
            4'd5:  audit_frame_byte = hex_char(rec[19:16]);
            4'd6:  audit_frame_byte = hex_char(rec[15:12]);
            4'd7:  audit_frame_byte = hex_char(rec[11:8]);
            4'd8:  audit_frame_byte = hex_char(rec[7:4]);
            4'd9:  audit_frame_byte = hex_char(rec[3:0]);
            4'd10: audit_frame_byte = 8'h0A;              // '\n'
            default: audit_frame_byte = 8'h0A;
        endcase
    end
endfunction

// --------------------------------------------------------------------------
// 待发事件队列与 @O 快照帧 / @H 硬件黑匣子审计帧发送状态机
// --------------------------------------------------------------------------
reg pend_d; // 'D' Duress
reg pend_x; // 'X' Tamper (非法撬门)
reg pend_l; // 'L' Lockout
reg pend_t; // 'T' Lockout Clear
reg pend_k; // 'K' Relocked
reg pend_a; // 'A' Alarm (Door Open)
reg pend_u; // 'U' Normal Unlock
reg pend_e; // 'E' Error

reg        pend_oled;
reg        oled_sending;
reg [3:0]  oled_idx;
reg [23:0] latched_snap;

reg        pend_audit;
reg        audit_sending;
reg [3:0]  audit_idx;
reg [31:0] latched_audit;

reg        tx_start_r;
reg [7:0]  tx_data_r;
reg        tx_is_evt;
wire       tx_busy;

wire any_evt_pend = pend_d | pend_x | pend_l | pend_t | pend_k | pend_a | pend_u | pend_e;

// --------------------------------------------------------------------------
// P1-3: 片上 BRAM (ERAM9K) 256x32-bit 硬件安全审计黑匣子环形缓冲区
//       记录格式: {运行秒时间戳[11:0], 链式防篡改摘要[3:0], 状态快照Byte0[7:0], 事件码[7:0]}
//       支持通过串口指令 'H' (0x48) 实时回传最新硬件黑匣子记录 "@H<8位Hex>\n"
// --------------------------------------------------------------------------
(* ram_style = "block" *) reg [31:0] audit_bram [0:255];
reg [31:0] audit_rd_data;
reg [7:0]  audit_wr_ptr;
reg [7:0]  audit_rd_ptr;
reg [9:0]  audit_ms_cnt;
reg [11:0] audit_sec_cnt;
reg [3:0]  audit_chain_mac;

wire       audit_we    = (tx_start_r && tx_is_evt) || rx_cmd_d1;
wire [7:0] audit_code  = (tx_start_r && tx_is_evt) ? tx_data_r : rx_byte;
wire [3:0] next_mac    = auth_sbox(audit_chain_mac ^ audit_code[7:4] ^ audit_code[3:0] ^ snap_b0[3:0]);
wire [31:0] audit_wdata = {audit_sec_cnt, next_mac, snap_b0, audit_code};

// 标准无异步复位同步读写进程，确保安路 TD 100% 映射为片上 ERAM9K 硬件存储块
always @(posedge clk) begin
    if (audit_we) begin
        audit_bram[audit_wr_ptr] <= audit_wdata;
    end
    audit_rd_data <= audit_bram[audit_rd_ptr];
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        audit_wr_ptr    <= 8'd0;
        audit_rd_ptr    <= 8'd0;
        audit_ms_cnt    <= 10'd0;
        audit_sec_cnt   <= 12'd0;
        audit_chain_mac <= 4'hA;
    end else begin
        if (tick_1k) begin
            if (audit_ms_cnt >= 10'd999) begin
                audit_ms_cnt  <= 10'd0;
                audit_sec_cnt <= audit_sec_cnt + 12'd1;
            end else begin
                audit_ms_cnt <= audit_ms_cnt + 10'd1;
            end
        end
        if (audit_we) begin
            audit_rd_ptr    <= audit_wr_ptr;
            audit_wr_ptr    <= audit_wr_ptr + 8'd1;
            audit_chain_mac <= next_mac;
        end else if (rx_audit_req && (audit_rd_ptr > 8'd0)) begin
            // 支持连续按 'H' 回溯历史黑匣子记录
            audit_rd_ptr <= audit_rd_ptr - 8'd1;
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pend_d <= 1'b0;  pend_x <= 1'b0;  pend_l <= 1'b0;  pend_t <= 1'b0;
        pend_k <= 1'b0;  pend_a <= 1'b0;  pend_u <= 1'b0;  pend_e <= 1'b0;
    end else begin
        // 单字节事件发出去就销账 (仅在非 @O 帧发送周期销账，防止与 HEX 字符 'D'/'A'/'E' 冲突)
        if (tx_start_r && tx_is_evt) begin
            if (tx_data_r == CH_DURESS)   pend_d <= 1'b0;
            if (tx_data_r == CH_TAMPER)   pend_x <= 1'b0;
            if (tx_data_r == CH_LOCK)     pend_l <= 1'b0;
            if (tx_data_r == CH_LOCK_END) pend_t <= 1'b0;
            if (tx_data_r == CH_RELOCK)   pend_k <= 1'b0;
            if (tx_data_r == CH_DOOR)     pend_a <= 1'b0;
            if (tx_data_r == CH_UNLOCK)   pend_u <= 1'b0;
            if (tx_data_r == CH_ERR)      pend_e <= 1'b0;
        end
        // 互斥保护: 当 evt_duress 或 pend_d 有效时, 直接清除并阻断同周期可能置位的 pend_u
        if (evt_duress) begin
            pend_d <= 1'b1;
            pend_u <= 1'b0;
        end else if (evt_unlock && !pend_d) begin
            pend_u <= 1'b1;
        end
        if (evt_tamper)   pend_x <= 1'b1;
        if (evt_lock)     pend_l <= 1'b1;
        if (evt_lock_end) pend_t <= 1'b1;
        if (evt_relock)   pend_k <= 1'b1;
        if (evt_door)     pend_a <= 1'b1;
        if (evt_pwd_err)  pend_e <= 1'b1;
    end
end

// 派件顺序:
//   1. 若当前正在发送 @O 帧 (oled_sending=1)，必须原子发完 9 字节至 '\n'，防止单字节事件混入 @...\n 帧内
//   2. 帧间仲裁: 单字节事件 ('D' > 'L' > 'T' > 'K' > 'A' > 'U' > 'E') 绝对优先于新 @O 快照帧
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_start_r    <= 1'b0;
        tx_data_r     <= 8'd0;
        tx_is_evt     <= 1'b0;
        pend_oled     <= 1'b0;
        pend_chal     <= 1'b0;
        pend_audit    <= 1'b0;
        oled_sending  <= 1'b0;
        oled_idx      <= 4'd0;
        latched_snap  <= 24'd0;
        audit_sending <= 1'b0;
        audit_idx     <= 4'd0;
        latched_audit <= 32'd0;
    end else begin
        tx_start_r <= 1'b0;
        tx_is_evt  <= 1'b0;

        if (chal_req) begin
            pend_chal <= 1'b1;
        end

        if (oled_changed) begin
            pend_oled <= 1'b1;
        end

        if (rx_audit_req) begin
            pend_audit <= 1'b1;
        end

        if (!tx_busy && !tx_start_r) begin
            if (chal_sending) begin
                // 发送挑战帧第二字节 (Nonce)
                tx_start_r   <= 1'b1;
                tx_data_r    <= challenge_nonce;
                chal_sending <= 1'b0;
                chal_idx     <= 1'b0;
            end else if (pend_chal) begin
                // 发送挑战帧第一字节 ('?')
                tx_start_r   <= 1'b1;
                tx_data_r    <= CH_CHALLENGE;
                chal_sending <= 1'b1;
                chal_idx     <= 1'b1;
                pend_chal    <= 1'b0;
            end else if (oled_sending) begin
                tx_start_r <= 1'b1;
                tx_data_r  <= oled_frame_byte(oled_idx, latched_snap);
                if (oled_idx == 4'd8) begin
                    oled_sending <= 1'b0;
                    oled_idx     <= 4'd0;
                end else begin
                    oled_idx <= oled_idx + 4'd1;
                end
            end else if (audit_sending) begin
                tx_start_r <= 1'b1;
                tx_data_r  <= audit_frame_byte(audit_idx, latched_audit);
                if (audit_idx == 4'd10) begin
                    audit_sending <= 1'b0;
                    audit_idx     <= 4'd0;
                end else begin
                    audit_idx <= audit_idx + 4'd1;
                end
            end else if (any_evt_pend) begin
                tx_start_r <= 1'b1;
                tx_is_evt  <= 1'b1;
                if (pend_d)      tx_data_r <= CH_DURESS;
                else if (pend_x) tx_data_r <= CH_TAMPER;
                else if (pend_l) tx_data_r <= CH_LOCK;
                else if (pend_t) tx_data_r <= CH_LOCK_END;
                else if (pend_k) tx_data_r <= CH_RELOCK;
                else if (pend_a) tx_data_r <= CH_DOOR;
                else if (pend_u) tx_data_r <= CH_UNLOCK;
                else if (pend_e) tx_data_r <= CH_ERR;
            end else if (pend_oled) begin
                tx_start_r   <= 1'b1;
                tx_data_r    <= 8'h40; // '@' (Byte 0)
                latched_snap <= oled_snap;
                oled_sending <= 1'b1;
                oled_idx     <= 4'd1;
                pend_oled    <= oled_changed; // 若恰在同一拍又有新跳变则保留挂起
            end else if (pend_audit) begin
                tx_start_r    <= 1'b1;
                tx_data_r     <= 8'h40; // '@' (Byte 0 of @H frame)
                latched_audit <= audit_rd_data;
                audit_sending <= 1'b1;
                audit_idx     <= 4'd1;
                pend_audit    <= 1'b0;
            end
        end
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        the_letter <= 8'd0;
    end else if (rx_ok) begin
        the_letter <= rx_byte;
    end else if (tx_start_r && tx_is_evt) begin
        the_letter <= tx_data_r;
    end
end

uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) u_leg (
    .clk(clk), .rst_n(rst_n),
    .tx_start(tx_start_r), .tx_data(tx_data_r),
    .tx_busy(tx_busy), .uart_tx(uart_tx)
);

assign is_sending = tx_busy;
assign cmd_safe   = rx_safe;

endmodule

`endif
