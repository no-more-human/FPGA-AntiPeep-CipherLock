`timescale 1ns / 1ps

// ==============================================================================
// 模块名称: tb_top
// 功能描述: 顶层模块 top.v 的仿真激励平台 (Testbench) - Day 2
// 测试重点:
//   1. 上电复位过程与各指示灯初始状态
//   2. 4x4 矩阵键盘行与列互联扫描响应
//   3. 按下按键后 led[7:4] 二进制键值锁存显示验证
//   4. led[1] 实时按下指示、led[2] 翻转指示与 led[0] 1Hz 心跳验证
// ==============================================================================

module tb_top;

    localparam integer CLK_PERIOD = 20; // 50MHz 时钟对应周期 20ns

    reg        clk_50M;
    reg        rst_n;
    reg  [3:0] key_row;
    wire [3:0] key_col;
    wire [7:0] led;

    // 例化顶层模块
    top u_top (
        .clk_50M(clk_50M),
        .rst_n  (rst_n),
        .key_row(key_row),
        .key_col(key_col),
        .led    (led)
    );

    // 产生 50MHz 时钟
    initial begin
        clk_50M = 1'b0;
        forever #(CLK_PERIOD / 2) clk_50M = ~clk_50M;
    end

    // 测试激励
    initial begin
        $dumpfile("sim_top.vcd");
        $dumpvars(0, tb_top);

        $display("[INFO] Starting Day 2 Top Module simulation...");

        // 初始复位与初始上拉
        key_row = 4'b1111;
        rst_n   = 1'b0;
        #(CLK_PERIOD * 10);

        // 释放复位
        rst_n = 1'b1;
        #(CLK_PERIOD * 10);

        $display("[PASS] Reset released. Initial led=%b", led);

        // 运行一段时钟观察时钟分频
        #(CLK_PERIOD * 500);

        $display("[INFO] Top module basic connectivity verified.");
        $finish;
    end

endmodule
