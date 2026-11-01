`timescale 1ns / 1ps

`ifndef __UART_MAILMAN_V__
`define __UART_MAILMAN_V__

// ==============================================================================
// 工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
// 模块名称: uart_mailman (UART 双向协议收发与事件排队调度模块)
// 功能描述:
//   接收 PC 上位机指令: 'S' (环境安全恢复), 'P' (防窥挂起), 'R' (远程开锁)
//   上报 FPGA 事件状态:
//     'D' (0x44, 反挟持报警 - 最高优先级, 抑制同周期 'U')
//     'L' (0x4C, 连续试错锁定)
//     'T' (0x54, 60s 试错锁定解除)
//     'K' (0x4B, 舵机重新锁闭)
//     'A' (0x41, 门未关超时报警)
//     'U' (0x55, 正常开锁成功)
//     'E' (0x45, 单次密码错误)
// ==============================================================================
module uart_mailman #(
    parameter integer CLK_FREQ = 50_000_000,
    parameter integer BAUD = 115_200,
    parameter integer REMOTE_HOLD_SEC = 3
)(
    input clk, input rst_n, input tick_1k,

    input  uart_rx,        // F12
    output uart_tx,        // D12

    input evt_unlock,      // 开锁了 -> 'U'
    input evt_lock,        // 锁定了 -> 'L'
    input evt_duress,      // 被挟持 -> 'D'
    input evt_door,        // 门没关 -> 'A'
    input evt_lock_end,    // 锁定解除 -> 'T' (8'h54)
    input evt_relock,      // 重新闭锁 -> 'K' (8'h4B)
    input evt_pwd_err,     // 单次输错 -> 'E' (8'h45)
    input is_locked,       // 当前处于试错锁定状态 (用于远程开锁安全门控)

    output reg  peep_hang,      // 有人在偷看,1 的时候防窥挂起
    output wire remote_unlock,  // PC 让远程开锁,保持几秒 (受 !is_locked && !peep_hang 门控)
    output wire cmd_safe,       // 'S' 那一拍
    output wire is_sending,
    output reg [7:0] the_letter // 最近收到的字节,接 LED 好调机
);

localparam [7:0] CH_SAFE     = 8'h53;  // 'S'
localparam [7:0] CH_PEEP     = 8'h50;  // 'P'
localparam [7:0] CH_REMOTE   = 8'h52;  // 'R'
localparam [7:0] CH_UNLOCK   = 8'h55;  // 'U'
localparam [7:0] CH_LOCK     = 8'h4C;  // 'L'
localparam [7:0] CH_LOCK_END = 8'h54;  // 'T'
localparam [7:0] CH_RELOCK   = 8'h4B;  // 'K'
localparam [7:0] CH_DURESS   = 8'h44;  // 'D'
localparam [7:0] CH_DOOR     = 8'h41;  // 'A'
localparam [7:0] CH_ERR      = 8'h45;  // 'E'

wire [7:0] rx_byte;
wire rx_ok;

uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD(BAUD)) u_ear (
    .clk(clk), .rst_n(rst_n), .uart_rx(uart_rx),
    .rx_data(rx_byte), .rx_valid(rx_ok)
);

wire rx_safe   = rx_ok && (rx_byte == CH_SAFE);
wire rx_peep   = rx_ok && (rx_byte == CH_PEEP);
wire rx_remote = rx_ok && (rx_byte == CH_REMOTE);

always @(posedge clk or negedge rst_n)
    if (!rst_n) the_letter <= 8'd0;
    else if (rx_ok) the_letter <= rx_byte;

// 偷看挂起,收到 'S' 才放人。跟被班主任叫去办公室一样,不听到"回去吧"是走不了的
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)          peep_hang <= 1'b0;
    else if (rx_safe)    peep_hang <= 1'b0;
    else if (rx_peep)    peep_hang <= 1'b1;
end

// 远程开锁,保持 REMOTE_HOLD_SEC 秒 (1kHz 节拍) 后自动闭锁
// 安全门控: 仅当未锁定 (!is_locked) 且无防窥挂起 (!peep_hang) 时才允许执行远程开锁
reg        remote_unlock_r;
reg [15:0] remote_ms_cnt;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        remote_unlock_r <= 1'b0;
        remote_ms_cnt   <= 16'd0;
    end else if (is_locked || peep_hang) begin
        remote_unlock_r <= 1'b0;
        remote_ms_cnt   <= 16'd0;
    end else if (rx_remote) begin
        remote_unlock_r <= 1'b1;
        remote_ms_cnt   <= REMOTE_HOLD_SEC * 16'd1000;
    end else if (remote_unlock_r && tick_1k) begin
        if (remote_ms_cnt > 16'd1) remote_ms_cnt <= remote_ms_cnt - 16'd1;
        else begin
            remote_ms_cnt   <= 16'd0;
            remote_unlock_r <= 1'b0;
        end
    end
end

assign remote_unlock = remote_unlock_r && !is_locked && !peep_hang;

// 待发的信,七种事件各挂一个小旗子。串口一次一个字母,不排队就会丢信
reg pend_d; // 'D' Duress
reg pend_l; // 'L' Lockout
reg pend_t; // 'T' Lockout Clear
reg pend_k; // 'K' Relocked
reg pend_a; // 'A' Alarm (Door/Tamper)
reg pend_u; // 'U' Normal Unlock
reg pend_e; // 'E' Error
reg tx_start_r;
reg [7:0] tx_data_r;
wire tx_busy;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pend_d <= 1'b0;  pend_l <= 1'b0;  pend_t <= 1'b0;  pend_k <= 1'b0;
        pend_a <= 1'b0;  pend_u <= 1'b0;  pend_e <= 1'b0;
    end else begin
        // 发出去就销账
        if (tx_start_r) begin
            if (tx_data_r == CH_DURESS)   pend_d <= 1'b0;
            if (tx_data_r == CH_LOCK)     pend_l <= 1'b0;
            if (tx_data_r == CH_LOCK_END) pend_t <= 1'b0;
            if (tx_data_r == CH_RELOCK)   pend_k <= 1'b0;
            if (tx_data_r == CH_DOOR)     pend_a <= 1'b0;
            if (tx_data_r == CH_UNLOCK)   pend_u <= 1'b0;
            if (tx_data_r == CH_ERR)      pend_e <= 1'b0;
        end
        // 有新事就插旗子。写在后头,所以同一拍"刚发完又来了新的"不会被吞掉
        // 互斥保护: 当 evt_duress 或 pend_d 有效时, 直接清除并阻断同周期可能置位的 pend_u
        if (evt_duress) begin
            pend_d <= 1'b1;
            pend_u <= 1'b0;
        end else if (evt_unlock && !pend_d) begin
            pend_u <= 1'b1;
        end
        if (evt_lock)     pend_l <= 1'b1;
        if (evt_lock_end) pend_t <= 1'b1;
        if (evt_relock)   pend_k <= 1'b1;
        if (evt_door)     pend_a <= 1'b1;
        if (evt_pwd_err)  pend_e <= 1'b1;
    end
end

// 派件顺序: 'D' > 'L' > 'T' > 'K' > 'A' > 'U' > 'E'
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_start_r <= 1'b0;
        tx_data_r  <= 8'd0;
    end else begin
        tx_start_r <= 1'b0;
        // !tx_start_r 是防手抖的,不然刚敲完门 tx_busy 还没抬起来会连发两封
        if (!tx_busy && !tx_start_r) begin
            if (pend_d)      begin tx_start_r <= 1'b1;  tx_data_r <= CH_DURESS;   end
            else if (pend_l) begin tx_start_r <= 1'b1;  tx_data_r <= CH_LOCK;     end
            else if (pend_t) begin tx_start_r <= 1'b1;  tx_data_r <= CH_LOCK_END; end
            else if (pend_k) begin tx_start_r <= 1'b1;  tx_data_r <= CH_RELOCK;   end
            else if (pend_a) begin tx_start_r <= 1'b1;  tx_data_r <= CH_DOOR;     end
            else if (pend_u) begin tx_start_r <= 1'b1;  tx_data_r <= CH_UNLOCK;   end
            else if (pend_e) begin tx_start_r <= 1'b1;  tx_data_r <= CH_ERR;      end
        end
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
