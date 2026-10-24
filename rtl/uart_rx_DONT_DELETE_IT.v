`timescale 1ns / 1ps

`ifndef __UART_RX_V__
`define __UART_RX_V__

// 串口收,115200 8-N-1
// 50M/115200 = 434.027 取 434,半个 bit 217,采样打在这俩数上
module uart_rx #(
    parameter integer CLK_FREQ = 50_000_000,
    parameter integer BAUD = 115_200
)(
    input clk, input rst_n,
    input uart_rx,          // F12
    output reg [7:0] rx_data,
    output reg rx_valid     // 收完亮一拍
);

localparam BAUD_CNT = CLK_FREQ / BAUD;   // 434
localparam HALF_CNT = BAUD_CNT / 2;      // 217

// 外面来的线不认我们的 clk,先过两级
reg rx_meta, rx_sync;
always @(posedge clk or negedge rst_n)
    if (!rst_n) begin
        rx_meta <= 1'b1;
        rx_sync <= 1'b1;      // 串口闲着是高
    end else begin
        rx_meta <= uart_rx;
        rx_sync <= rx_meta;
    end

localparam S_IDLE  = 2'd0;
localparam S_START = 2'd1;
localparam S_DATA  = 2'd2;
localparam S_STOP  = 2'd3;

reg [1:0] state;
reg [15:0] cnt;
reg [2:0] bit_idx;
reg [7:0] sh;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= S_IDLE;  cnt <= 16'd0;  bit_idx <= 3'd0;
        sh <= 8'd0;  rx_data <= 8'd0;  rx_valid <= 1'b0;
    end else begin
        rx_valid <= 1'b0;        // 脉冲,平时都清掉

        case (state)
        S_IDLE:
            if (!rx_sync)
              state <= S_START;

        S_START:
            // 蹲到半个 bit 的中点再看一眼,还是低才算真起始位,不然就是毛刺
            if (cnt == HALF_CNT - 1) begin
               cnt <= 16'd0;
               if (!rx_sync) begin
                  state   <= S_DATA;
                  bit_idx <= 3'd0;
               end else
                  state <= S_IDLE;
            end else
               cnt <= cnt + 16'd1;

        S_DATA:
            if (cnt == BAUD_CNT - 1) begin
                cnt <= 16'd0;
                sh[bit_idx] <= rx_sync;     // 中点采,LSB 先来的
                if (bit_idx == 3'd7)
                    state <= S_STOP;
                else
                    bit_idx <= bit_idx + 3'd1;
            end else
                cnt <= cnt + 16'd1;

        S_STOP:
            if (cnt == BAUD_CNT - 1) begin
                cnt <= 16'd0;
                state <= S_IDLE;
                if (rx_sync) begin        // 停止位得是高,低了就是假帧
                    rx_data  <= sh;
                    rx_valid <= 1'b1;
                end
            end else
                cnt <= cnt + 16'd1;

        default: state <= S_IDLE;
        endcase
    end
end

endmodule

`endif
