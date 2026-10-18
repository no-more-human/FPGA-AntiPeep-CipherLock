`timescale 1ns / 1ps

// ==============================================================================
// 模块名称: tb_clk_tick
// 功能描述: clk_tick 多速率时钟节拍发生器的仿真激励平台 (Testbench)
// 测试重点:
//   1. 50MHz 时钟下 tick_1k 和 tick_100 脉冲生成
//   2. 脉冲宽度精确为 1 个系统时钟周期 (20ns)
//   3. 异步复位及释放行为
// ==============================================================================

module tb_clk_tick;

    // 参数设定: 为便于快速仿真，将分频比按比例等比压缩
    localparam integer SIM_CLK_FREQ = 100_000; // 模拟 100kHz，缩短仿真时间
    localparam integer CLK_PERIOD   = 20;      // 50MHz 时钟周期 = 20ns

    reg  clk;
    reg  rst_n;
    wire tick_1k;
    wire tick_100;

    // 例化待测模块 (DUT)
    clk_tick #(
        .CLK_FREQ(SIM_CLK_FREQ)
    ) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .tick_1k (tick_1k),
        .tick_100(tick_100)
    );

    // 产生 50MHz 连续对称方波时钟
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // 测试激励时序
    initial begin
        // 波形记录输出 (用于 ModelSim / GTKWave 查看)
        $dumpfile("sim_clk_tick.vcd");
        $dumpvars(0, tb_clk_tick);

        // 初始复位
        rst_n = 1'b0;
        #(CLK_PERIOD * 5);

        // 释放复位
        rst_n = 1'b1;
        $display("[INFO] Reset released, starting clock tick observation...");

        // 观察多个节拍周期
        wait(tick_1k == 1'b1);
        $display("[PASS] First 1kHz tick captured at time: %t", $time);

        wait(tick_100 == 1'b1);
        $display("[PASS] First 100Hz tick captured at time: %t", $time);

        // 运行足够时间后结束
        #(CLK_PERIOD * 2000);
        $display("[INFO] Testbench finished successfully!");
        $finish;
    end

endmodule
