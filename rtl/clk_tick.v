// ==============================================================================
// 模块名称: clk_tick (多速率时钟节拍使能生成器)
// 功能描述: 将 50MHz 系统主时钟分频，产生单周期宽度的使能脉冲(Tick Strobe):
//           - tick_1k  : 1kHz  (1ms  节拍)，适用于按键消抖采样、快速轮询
//           - tick_100 : 100Hz (10ms 节拍)，适用于数码管刷新、动态定时调度
// 设计哲学: 全系统仅使用 50MHz 单一时钟域，避免产生门控时钟或纹波时钟，确保静态时序收敛
// ==============================================================================

module clk_tick #(
    parameter integer CLK_FREQ = 50_000_000 // 系统主时钟频率: 50MHz
)(
    input  wire clk,        // 50MHz 主时钟输入 (引脚 R7)
    input  wire rst_n,      // 全局异步复位信号，低电平有效 (引脚 E3)
    output reg  tick_1k,    // 1kHz 单周期使能脉冲 (每 1ms 产生 1 个高脉冲)
    output reg  tick_100    // 100Hz 单周期使能脉冲 (每 10ms 产生 1 个高脉冲)
);

// --------------------------------------------------------------------------
// 常量计算:
// 50MHz / 1kHz = 50,000 个主时钟周期
// --------------------------------------------------------------------------
localparam integer CNT_1K_MAX = CLK_FREQ / 1_000;

reg [15:0] cnt_1k;  // 50,000 需要 16 位宽 (0 ~ 65535)
reg [3:0]  cnt_100; // 0 ~ 9，4 位宽足够

// 1kHz 节拍脉冲生成逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt_1k  <= 16'd0;
        tick_1k <= 1'b0;
    end else if (cnt_1k >= (CNT_1K_MAX - 1)) begin
        cnt_1k  <= 16'd0;
        tick_1k <= 1'b1; // 到达 1ms，输出 1 个时钟周期的脉冲
    end else begin
        cnt_1k  <= cnt_1k + 16'd1;
        tick_1k <= 1'b0;
    end
end

// 100Hz 节拍脉冲生成逻辑 (基于 1kHz 级联分频，节省逻辑资源)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cnt_100  <= 4'd0;
        tick_100 <= 1'b0;
    end else if (tick_1k) begin
        if (cnt_100 >= 4'd9) begin
            cnt_100  <= 4'd0;
            tick_100 <= 1'b1; // 累积 10 次 1ms，输出 100Hz (10ms) 脉冲
        end else begin
            cnt_100  <= cnt_100 + 4'd1;
            tick_100 <= 1'b0;
        end
    end else begin
        tick_100 <= 1'b0;
    end
end

endmodule
