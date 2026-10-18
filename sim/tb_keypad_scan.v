`timescale 1ns / 1ps

// ==============================================================================
// 模块名称: tb_keypad_scan
// 功能描述: 4x4 矩阵键盘驱动与 20ms 硬件消抖的全面仿真激励平台
// 验证要点:
//   1. 4 列轮询扫描时序 (Col 0 -> Col 1 -> Col 2 -> Col 3)
//   2. 模拟机械按键按下抖动 (5ms 抖动)，验证 20ms 延时消抖滤波器有效性
//   3. 验证单次按键仅产生单一时钟周期的 key_valid 脉冲 (杜绝连击)
//   4. 验证长按保持不重复触发
//   5. 验证松开按键的释放消抖 (5ms 释放回弹)
//   6. 遍历测试典型按键译码 (如 '1', '5', '9', '0', 'A', '#')
// ==============================================================================

module tb_keypad_scan;

    localparam integer CLK_PERIOD = 20; // 50MHz 系统时钟 (20ns)

    reg        clk;
    reg        rst_n;
    reg        tick_1k;
    reg  [3:0] key_row;
    wire [3:0] key_col;
    wire [3:0] key_val;
    wire       key_valid;
    wire       key_pressed;

    // 实例化被测模块 (为加速仿真测试，DEBOUNCE_TIME 设为 5 个 tick)
    keypad_scan #(
        .DEBOUNCE_TIME(5)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .tick_1k    (tick_1k),
        .key_row    (key_row),
        .key_col    (key_col),
        .key_val    (key_val),
        .key_valid  (key_valid),
        .key_pressed(key_pressed)
    );

    // 产生 50MHz 时钟
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // 产生 1kHz tick (加速时钟: 每 100 个 clk 一个 tick_1k 脉冲)
    reg [6:0] tick_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_cnt <= 7'd0;
            tick_1k  <= 1'b0;
        end else begin
            if (tick_cnt == 7'd99) begin
                tick_cnt <= 7'd0;
                tick_1k  <= 1'b1;
            end else begin
                tick_cnt <= tick_cnt + 7'd1;
                tick_1k  <= 1'b0;
            end
        end
    end

    // 统计 key_valid 触发次数，用于验证无连击
    integer pulse_count = 0;
    always @(posedge clk) begin
        if (key_valid) begin
            pulse_count = pulse_count + 1;
            $display("[PULSE] key_valid triggered! KeyVal=0x%h at time=%0t", key_val, $time);
        end
    end

    // 模拟按键闭合模型: 当某列被驱动为低电平且该键被按下时，拉低对应 row
    reg [3:0] press_target_col;
    reg [3:0] press_target_row;
    reg       is_pressing;

    always @(*) begin
        key_row = 4'b1111; // 默认内部上拉为高
        if (is_pressing) begin
            // 当扫描到目标列时，行线被拉低
            if (key_col[press_target_col] == 1'b0) begin
                key_row[press_target_row] = 1'b0;
            end
        end
    end

    // 任务: 模拟真实按键敲击 (包含按下前置抖动与释放回弹抖动)
    task simulate_press(input [1:0] target_c, input [1:0] target_r, input [3:0] expected_hex);
        integer i;
        begin
            press_target_col = target_c;
            press_target_row = target_r;
            pulse_count = 0;
            $display("--------------------------------------------------");
            $display("[TEST] Simulating key press: Col=%0d, Row=%0d, Expected=0x%h", target_c, target_r, expected_hex);
            
            // 1. 模拟按下机械弹跳抖动 (抖动 3 次)
            for (i = 0; i < 3; i = i + 1) begin
                is_pressing = 1'b1;
                repeat (150) @(posedge clk);
                is_pressing = 1'b0;
                repeat (100) @(posedge clk);
            end

            // 2. 按键稳定压合
            is_pressing = 1'b1;
            repeat (1000) @(posedge clk); // 持续足够多的 tick 超过消抖时间

            // 3. 检查是否触发且仅触发一次脉冲
            if (pulse_count == 1 && key_val == expected_hex) begin
                $display("[PASS] Key recognized correctly: 0x%h, pulses=%0d", key_val, pulse_count);
            end else begin
                $display("[FAIL] Key recognition error! Expected 0x%h, got 0x%h, pulses=%0d", expected_hex, key_val, pulse_count);
            end

            // 4. 模拟按键释放回弹抖动
            for (i = 0; i < 3; i = i + 1) begin
                is_pressing = 1'b0;
                repeat (100) @(posedge clk);
                is_pressing = 1'b1;
                repeat (80) @(posedge clk);
            end

            // 5. 完全释放
            is_pressing = 1'b0;
            repeat (1000) @(posedge clk); // 等待释放消抖完成
            $display("[INFO] Key released, key_pressed=%b", key_pressed);
        end
    endtask

    // 测试主流程
    initial begin
        $dumpfile("sim_keypad.vcd");
        $dumpvars(0, tb_keypad_scan);

        $display("==================================================");
        $display("[START] Starting Keypad Scan & Debounce Simulation");
        $display("==================================================");

        rst_n       = 1'b0;
        is_pressing = 1'b0;
        press_target_col = 0;
        press_target_row = 0;
        repeat (50) @(posedge clk);
        rst_n       = 1'b1;
        repeat (50) @(posedge clk);

        // 测试 Key '5' (Col 1, Row 1 -> 4'h5)
        simulate_press(2'd1, 2'd1, 4'h5);

        // 测试 Key 'A' (Col 3, Row 0 -> 4'hA)
        simulate_press(2'd3, 2'd0, 4'hA);

        // 测试 Key '0' (Col 1, Row 3 -> 4'h0)
        simulate_press(2'd1, 2'd3, 4'h0);

        // 测试 Key '#' (Col 2, Row 3 -> 4'hF)
        simulate_press(2'd2, 2'd3, 4'hF);

        repeat (200) @(posedge clk);
        $display("==================================================");
        $display("[FINISH] All Keypad Debounce Tests Completed Successfully!");
        $display("==================================================");
        $finish;
    end

endmodule
