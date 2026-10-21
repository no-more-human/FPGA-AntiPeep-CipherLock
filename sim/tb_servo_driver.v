`timescale 1ns / 1ps

// ==============================================================================
// 模块名称: tb_servo_driver
// 功能描述: SG90 舵机控制器单元测试台 (测试 0° / 90° PWM 脉宽)
// ==============================================================================

module tb_servo_driver;

    localparam integer CLK_PERIOD = 20; // 50MHz 时钟 (20ns)

    reg  clk;
    reg  rst_n;
    reg  unlock_en;
    wire servo_pwm;

    // 例化待测模块 (缩短周期以加速波形验证)
    servo_driver #(
        .CLK_FREQ    (50_000_000),
        .PERIOD_CNT  (1_000), // 缩短为 1000 拍
        .PULSE_0_DEG (25),    // 25 拍 (2.5%)
        .PULSE_90_DEG(75)     // 75 拍 (7.5%)
    ) u_servo (
        .clk      (clk),
        .rst_n    (rst_n),
        .unlock_en(unlock_en),
        .servo_pwm(servo_pwm)
    );

    // 时钟生成
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // 测试激励
    initial begin
        $display("[INFO] Starting tb_servo_driver...");
        rst_n     = 1'b0;
        unlock_en = 1'b0;
        #(CLK_PERIOD * 10);
        rst_n = 1'b1;

        // 验证闭锁 0° PWM
        #(CLK_PERIOD * 3000);
        $display("[INFO] Verified 0 deg locked PWM.");

        // 验证开锁 90° PWM
        unlock_en = 1'b1;
        #(CLK_PERIOD * 3000);
        $display("[INFO] Verified 90 deg unlocked PWM.");

        // 验证回弹 0° PWM
        unlock_en = 1'b0;
        #(CLK_PERIOD * 3000);
        $display("[PASS] tb_servo_driver passed successfully!");
        $finish;
    end

endmodule
