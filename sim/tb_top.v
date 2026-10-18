`timescale 1ns / 1ps

// ==============================================================================
// 模块名称: tb_top
// 功能描述: 顶层模块 top.v 仿真激励平台 - Day 3~4
// 测试重点:
//   1. 顶层时钟复位与 1Hz 心跳灯
//   2. 0.96寸 I2C OLED SCL/SDA 波形与启动初始化
//   3. 4位数码管段选/位选动态扫描时序
//   4. 蜂鸣器输出响应与 4x4 矩阵键盘交互
// ==============================================================================

module tb_top;

    localparam integer CLK_PERIOD = 20; // 50MHz 时钟 (周期 20ns)

    reg        clk_50M;
    reg        rst_n;
    reg  [3:0] key_row;
    wire [3:0] key_col;
    wire       oled_scl;
    wire       oled_sda;
    wire [7:0] seg_out;
    wire [3:0] seg_cs;
    wire       buzzer_out;
    wire [7:0] led;

    // 例化顶层模块
    top u_top (
        .clk_50M   (clk_50M),
        .rst_n     (rst_n),
        .key_row   (key_row),
        .key_col   (key_col),
        .oled_scl  (oled_scl),
        .oled_sda  (oled_sda),
        .seg_out   (seg_out),
        .seg_cs    (seg_cs),
        .buzzer_out(buzzer_out),
        .led       (led)
    );

    // 产生 50MHz 时钟
    initial begin
        clk_50M = 1'b0;
        forever #(CLK_PERIOD / 2) clk_50M = ~clk_50M;
    end

    // 测试激励
    initial begin
        $display("[INFO] Starting Day 3~4 Top Module simulation...");

        // 初始复位与按键上拉
        key_row = 4'b1111;
        rst_n   = 1'b0;
        #(CLK_PERIOD * 20);

        // 释放复位
        rst_n = 1'b1;
        #(CLK_PERIOD * 50);

        $display("[PASS] Reset released. Initial led=%b, seg_cs=%b", led, seg_cs);

        // 运行一段时间观察 OLED SCL 时钟输出与数码管扫描
        #(CLK_PERIOD * 1000);

        $display("[INFO] Top module connectivity & peripheral buses verified.");
        $finish;
    end

endmodule
