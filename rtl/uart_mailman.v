`timescale 1ns / 1ps

`ifndef __UART_MAILMAN_V__
`define __UART_MAILMAN_V__

// THE_GREAT_SPAMTON_MAILMAN
//   "NOW'S YOUR CHANCE TO BE A [BIG SHOT]!!"
// 在 FPGA 和 PC 之间跑腿送信的。收 'S''P''R',发 'U''L''D''A'。
// 一次只能说一个字母,所以事件先挂旗子排队,发出去才落旗。
//
// 不碰 safe_fsm,全在外面加壳:
//   吃它吐出来的 unlock_en / beep_lock / duress_alarm / door_alert_pulse
//   吐 peep_hang / remote_unlock / cmd_safe 给 top
module THE_GREAT_SPAMTON_MAILMAN #(
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

    output reg  peep_hang,      // 有人在偷看,1 的时候 top 把键盘和数码管停掉
    output reg  remote_unlock,  // PC 让远程开锁,保持几秒
    output wire cmd_safe,       // 'S' 那一拍
    output wire is_sending,
    output reg [7:0] the_letter // 最近收到的字节,接 LED 好调机
);

localparam [7:0] CH_SAFE   = 8'h53;  // 'S'
localparam [7:0] CH_PEEP   = 8'h50;  // 'P'
localparam [7:0] CH_REMOTE = 8'h52;  // 'R'
localparam [7:0] CH_UNLOCK = 8'h55;  // 'U'
localparam [7:0] CH_LOCK   = 8'h4C;  // 'L'
localparam [7:0] CH_DURESS = 8'h44;  // 'D'
localparam [7:0] CH_DOOR   = 8'h41;  // 'A'

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
// 修复: 原代码 remote_sec 每一拍(1ms)减 1 导致 3 毫秒即闭锁，现采用 16 位毫秒倒计时
reg [15:0] remote_ms_cnt;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        remote_unlock <= 1'b0;
        remote_ms_cnt <= 16'd0;
    end else if (rx_remote) begin
        remote_unlock <= 1'b1;
        remote_ms_cnt <= REMOTE_HOLD_SEC * 16'd1000;
    end else if (remote_unlock && tick_1k) begin
        if (remote_ms_cnt > 16'd1) remote_ms_cnt <= remote_ms_cnt - 16'd1;
        else begin
            remote_ms_cnt <= 16'd0;
            remote_unlock <= 1'b0;
        end
    end
end

// 待发的信,四种事件各挂一个小旗子。串口一次一个字母,不排队就会丢信
reg pend_u, pend_l, pend_d, pend_a;
reg tx_start_r;
reg [7:0] tx_data_r;
wire tx_busy;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pend_u <= 1'b0;  pend_l <= 1'b0;  pend_d <= 1'b0;  pend_a <= 1'b0;
    end else begin
        // 发出去就销账
        if (tx_start_r) begin
            if (tx_data_r == CH_UNLOCK) pend_u <= 1'b0;
            if (tx_data_r == CH_LOCK)   pend_l <= 1'b0;
            if (tx_data_r == CH_DURESS) pend_d <= 1'b0;
            if (tx_data_r == CH_DOOR)   pend_a <= 1'b0;
        end
        // 有新事就插旗子。写在后头,所以同一拍"刚发完又来了新的"不会被吞掉
        if (evt_unlock) pend_u <= 1'b1;
        if (evt_lock)   pend_l <= 1'b1;
        if (evt_duress) pend_d <= 1'b1;
        if (evt_door)   pend_a <= 1'b1;
    end
end

// 派件顺序:挟持 > 锁定 > 门没关 > 开锁。被抢的时候当然先报挟持
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_start_r <= 1'b0;
        tx_data_r  <= 8'd0;
    end else begin
        tx_start_r <= 1'b0;
        // !tx_start_r 是防手抖的,不然刚敲完门 tx_busy 还没抬起来会连发两封
        if (!tx_busy && !tx_start_r) begin
            if (pend_d)      begin tx_start_r <= 1'b1;  tx_data_r <= CH_DURESS; end
            else if (pend_l) begin tx_start_r <= 1'b1;  tx_data_r <= CH_LOCK;   end
            else if (pend_a) begin tx_start_r <= 1'b1;  tx_data_r <= CH_DOOR;   end
            else if (pend_u) begin tx_start_r <= 1'b1;  tx_data_r <= CH_UNLOCK; end
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
