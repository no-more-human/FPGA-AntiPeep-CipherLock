`timescale 1ns / 1ps

`ifndef __UART_TX_V__
`define __UART_TX_V__

// 串口发,115200 8-N-1
// 一帧 10 位:起始0 + 8个数据(LSB先) + 停止1,打成 10 位寄存器往外挤
module uart_tx #(
    parameter integer CLK_FREQ = 50_000_000,
    parameter integer BAUD = 115_200
)(
    input clk, input rst_n,
    input tx_start,        // 敲一下发一个字节
    input [7:0] tx_data,
    output reg tx_busy,    // 正在发,别插话
    output reg uart_tx     // D12
);

localparam BAUD_CNT = CLK_FREQ / BAUD;   // 434

reg [15:0] cnt;
reg [3:0] bit_idx;
reg [9:0] sh;      // {停止位, 数据[7:0], 起始位}

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        uart_tx <= 1'b1;
        tx_busy <= 1'b0;
        cnt <= 16'd0;
        bit_idx <= 4'd0;
        sh <= 10'h3FF;
    end
    else if (!tx_busy) begin
        // 在家待着,线保持高
        uart_tx <= 1'b1;
        cnt <= 16'd0;
        bit_idx <= 4'd0;
        if (tx_start) begin
            sh <= {1'b1, tx_data, 1'b0};
            tx_busy <= 1'b1;
            uart_tx <= 1'b0;      // 起始位马上下拉,不能等
        end
    end
    else begin
        // 出门送信,每位 434 拍
        if (cnt == BAUD_CNT - 1) begin
            cnt <= 16'd0;
            if (bit_idx == 4'd9) begin
                tx_busy <= 1'b0;
                uart_tx <= 1'b1;
            end else begin
                bit_idx <= bit_idx + 4'd1;
                uart_tx <= sh[bit_idx + 4'd1];
            end
        end else
            cnt <= cnt + 16'd1;
    end
end

endmodule

`endif
