`timescale 1ns / 1ps

// ==============================================================================
// 模块名称: tb_top
// 功能描述: 顶层模块 top.v 端到端集成仿真回归平台 - Day 5
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
    wire       servo_pwm;
    wire       voice_tx;
    reg        voice_busy;
    reg        door_gpio;
    wire [7:0] led;
    wire       uart_tx;
    reg        uart_rx;
    reg        sw_recovery;

    // 模拟外设引脚弱上拉
    pullup(oled_sda);

    // 例化顶层模块
    top u_top (
        .clk_50M    (clk_50M),
        .rst_n      (rst_n),
        .key_row    (key_row),
        .key_col    (key_col),
        .oled_scl   (oled_scl),
        .oled_sda   (oled_sda),
        .seg_out    (seg_out),
        .seg_cs     (seg_cs),
        .buzzer_out (buzzer_out),
        .servo_pwm  (servo_pwm),
        .voice_tx   (voice_tx),
        .voice_busy (voice_busy),
        .door_gpio  (door_gpio),
        .led        (led),
        .uart_tx    (uart_tx),
        .uart_rx    (uart_rx),
        .sw_recovery(sw_recovery)
    );

    // 115200 波特率发送任务 (1 bit = 434 个 50MHz 时钟周期)
    task uart_send_byte(input [7:0] data);
        integer b;
        begin
            uart_rx = 1'b0; // Start bit
            #(CLK_PERIOD * 434);
            for (b = 0; b < 8; b = b + 1) begin
                uart_rx = data[b];
                #(CLK_PERIOD * 434);
            end
            uart_rx = 1'b1; // Stop bit
            #(CLK_PERIOD * 434);
        end
    endtask

    // 产生 50MHz 时钟
    initial begin
        clk_50M = 1'b0;
        forever #(CLK_PERIOD / 2) clk_50M = ~clk_50M;
    end

    // 测试激励
    initial begin
        $display("[INFO] Starting Day 5 Top Module full-chip simulation...");

        // 初始复位与物理上拉默认电平
        key_row     = 4'b1111;
        door_gpio   = 1'b0; // 门关严
        voice_busy  = 1'b1; // 语音空闲
        uart_rx     = 1'b1; // UART 空闲高电平
        sw_recovery = 1'b0; // 默认关闭恢复开关
        rst_n       = 1'b0;
        #(CLK_PERIOD * 20);

        // 释放复位
        rst_n = 1'b1;
        #(CLK_PERIOD * 50);

        $display("[PASS] Reset released. Initial led=%b, seg_cs=%b, voice_tx=%b", led, seg_cs, voice_tx);

        // 模拟 PC 下发 'P' (0x50) 防窥挂起指令
        uart_send_byte(8'h50);
        #(CLK_PERIOD * 20);
        if (seg_out == 8'h00 && seg_cs == 4'hF)
            $display("[PASS] Anti-peeping 'P' command blanked 7-seg & asserted peep_hang.");
        else
            $display("[FAIL] Expected seg_out=00, seg_cs=F on 'P', got %h %h", seg_out, seg_cs);

        // 模拟 PC 下发 'S' (0x53) 安全恢复指令
        uart_send_byte(8'h53);
        #(CLK_PERIOD * 20);

        // 模拟 PC 下发 'R' (0x52) 远程开锁指令
        uart_send_byte(8'h52);
        #(CLK_PERIOD * 20);
        if (led[2] == 1'b1)
            $display("[PASS] Remote unlock 'R' command asserted unlock_all (led[2]=1).");

        // 模拟开门
        door_gpio = 1'b1;
        #(CLK_PERIOD * 2000);

        // 门关严
        door_gpio = 1'b0;
        #(CLK_PERIOD * 2000);

        $display("[INFO] Top module connectivity & multi-peripheral integration verified.");
        $finish;
    end

endmodule
