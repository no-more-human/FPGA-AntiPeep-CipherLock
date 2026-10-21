`timescale 1ns / 1ps

// ==============================================================================
// 模块名称: tb_door_sensor
// 功能描述: GPS-23 门磁与 SW1 双轨检测及超时未关报警仿真测试
// ==============================================================================

module tb_door_sensor;

    localparam CLK_PERIOD = 20; // 50MHz

    reg        clk;
    reg        rst_n;
    reg        tick_1k;
    reg        sensor_gpio;
    reg        unlock_en;

    wire       door_open;
    wire       door_alert;
    wire       alert_pulse;
    wire [3:0] open_sec_cnt;

    // 采用加速参数 (2秒超时, 5ms消抖)
    door_sensor #(
        .TIMEOUT_SEC  (2),
        .DEBOUNCE_TIME(5)
    ) u_door_sensor (
        .clk         (clk),
        .rst_n       (rst_n),
        .tick_1k     (tick_1k),
        .sensor_gpio (sensor_gpio),
        .unlock_en   (unlock_en),
        .door_open   (door_open),
        .door_alert  (door_alert),
        .alert_pulse (alert_pulse),
        .open_sec_cnt(open_sec_cnt)
    );

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // 产生快速 1kHz (1ms) 节拍
    initial begin
        tick_1k = 1'b0;
        forever begin
            #(CLK_PERIOD * 10) tick_1k = 1'b1;
            #(CLK_PERIOD)      tick_1k = 1'b0;
        end
    end

    initial begin
        $display("[INFO] Starting tb_door_sensor simulation...");
        rst_n       = 1'b0;
        sensor_gpio = 1'b0; // 初始门关严 (接GND)
        unlock_en   = 1'b0;
        #(CLK_PERIOD * 20);
        rst_n       = 1'b1;
        #(CLK_PERIOD * 20);

        if (door_open == 1'b0 && door_alert == 1'b0)
            $display("[PASS] Initial state: door closed, alert=0.");
        else
            $display("[FAIL] Initial state abnormal.");

        // 测试消抖: 产生 2ms 抖动干扰，不应改变 door_open
        $display("[TEST 1] Testing mechanical chatter filtering...");
        sensor_gpio = 1'b1;
        #(CLK_PERIOD * 15);
        sensor_gpio = 1'b0;
        #(CLK_PERIOD * 15);
        if (door_open == 1'b0)
            $display("[PASS] Glitch successfully rejected.");
        else
            $display("[FAIL] Glitch falsely passed.");

        // 真实门开: 保持稳定高电平
        $display("[TEST 2] Door opening & 20ms debounce stabilization...");
        sensor_gpio = 1'b1;
        #(CLK_PERIOD * 150); // 超过 5 个 tick_1k
        if (door_open == 1'b1)
            $display("[PASS] Door open state confirmed after debounce.");
        else
            $display("[FAIL] Door open not detected.");

        // 未开锁时门开不触发超时报警
        #(CLK_PERIOD * 500);
        if (door_alert == 1'b0)
            $display("[PASS] No alert when door open without unlock.");

        // 开锁并持续开门 -> 触发超时报警
        $display("[TEST 3] Unlocking and waiting for timeout alert...");
        @(posedge clk);
        unlock_en = 1'b1;
        @(posedge clk);
        unlock_en = 1'b0;

        // 等待 2 个秒边界 (约 2000 个 tick)
        #(CLK_PERIOD * 25000);
        if (door_alert == 1'b1)
            $display("[PASS] Door alert successfully triggered after timeout! door_alert=1");
        else
            $display("[FAIL] Door alert did not trigger. door_alert=%b, open_sec=%d", door_alert, open_sec_cnt);

        // 门关严 -> 立即消警
        $display("[TEST 4] Closing door & verifying immediate alert clear...");
        sensor_gpio = 1'b0; // 磁铁吸合
        #(CLK_PERIOD * 150);
        if (door_open == 1'b0 && door_alert == 1'b0)
            $display("[PASS] Door closed, alert cleared immediately to 0.");
        else
            $display("[FAIL] Alert did not clear. door_open=%b, door_alert=%b", door_open, door_alert);

        $display("[INFO] tb_door_sensor simulation finished successfully.");
        $finish;
    end

endmodule
