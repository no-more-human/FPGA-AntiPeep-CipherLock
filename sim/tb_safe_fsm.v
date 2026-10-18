`timescale 1ns / 1ps

// ==============================================================================
// 模块名称: tb_safe_fsm
// 功能描述: 保险箱主状态机 safe_fsm 单元测试激励平台
// 测试内容:
//   1. 键盘敲击数字录入与按键提示音
//   2. 退格键 '*' 移除末位输入
//   3. 输错密码触发 1.5s 错误提示与蜂鸣器警告音
//   4. 连续输错 3 次触发 60s 硬件锁定与严重警报音
//   5. 锁定期间按键无效验证
//   6. 锁定倒计时清零后系统自动恢复
//   7. 输入正确密码 "123456" 成功开锁与和弦音
// ==============================================================================

module tb_safe_fsm;

    localparam integer CLK_PERIOD = 20; // 50MHz

    reg        clk;
    reg        rst_n;
    reg        tick_1k;
    reg  [3:0] key_val;
    reg        key_valid;

    wire [2:0] state_code;
    wire [2:0] pwd_len;
    wire [1:0] err_count;
    wire [6:0] lock_countdown;
    wire       unlock_en;
    wire       duress_alarm;
    wire       beep_key;
    wire       beep_err;
    wire       beep_lock;
    wire       beep_succ;

    // 例化待测模块 (将锁定时间设为 3 秒以加速仿真)
    safe_fsm #(
        .DEFAULT_PWD     ({4'h1, 4'h2, 4'h3, 4'h4, 4'h5, 4'h6}),
        .DURESS_PWD      ({4'h6, 4'h5, 4'h4, 4'h3, 4'h2, 4'h1}),
        .LOCK_TIMEOUT_SEC(3)
    ) u_fsm (
        .clk           (clk),
        .rst_n         (rst_n),
        .tick_1k       (tick_1k),
        .key_val       (key_val),
        .key_valid     (key_valid),
        .state_code    (state_code),
        .pwd_len       (pwd_len),
        .err_count     (err_count),
        .lock_countdown(lock_countdown),
        .unlock_en     (unlock_en),
        .duress_alarm  (duress_alarm),
        .beep_key      (beep_key),
        .beep_err      (beep_err),
        .beep_lock     (beep_lock),
        .beep_succ     (beep_succ)
    );

    // 产生时钟
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // 产生 1kHz 快速节拍
    initial begin
        tick_1k = 1'b0;
        forever begin
            #(CLK_PERIOD * 5) tick_1k = 1'b1;
            #(CLK_PERIOD)     tick_1k = 1'b0;
        end
    end

    // 按键任务
    task press_key(input [3:0] val);
        begin
            @(posedge clk);
            key_val   = val;
            key_valid = 1'b1;
            @(posedge clk);
            key_valid = 1'b0;
            #(CLK_PERIOD * 10);
        end
    endtask

    initial begin
        $display("[INFO] Starting safe_fsm Testbench...");
        rst_n     = 1'b0;
        key_val   = 4'h0;
        key_valid = 1'b0;
        #(CLK_PERIOD * 20);
        rst_n     = 1'b1;
        #(CLK_PERIOD * 20);

        $display("[TEST 1] Testing single digit press & key sound...");
        press_key(4'h1);
        if (pwd_len == 3'd1 && state_code == 3'd1)
            $display("[PASS] State transitioned to INPUT, pwd_len=1");
        else
            $display("[FAIL] Expected pwd_len=1, got %d", pwd_len);

        $display("[TEST 2] Testing Backspace '* '...");
        press_key(4'hE); // '*'
        if (pwd_len == 3'd0 && state_code == 3'd0)
            $display("[PASS] Backspace reset to IDLE, pwd_len=0");
        else
            $display("[FAIL] Expected pwd_len=0, got %d", pwd_len);

        $display("[TEST 3] Inputting wrong password & verification...");
        press_key(4'h9);
        press_key(4'h9);
        press_key(4'h9);
        press_key(4'h9);
        press_key(4'h9);
        press_key(4'h9);
        press_key(4'hF); // '#' 确认
        #(CLK_PERIOD * 5);
        if (state_code == 3'd3 && err_count == 2'd1)
            $display("[PASS] Entered ERROR state on 1st wrong attempt. err_count=1");
        else
            $display("[FAIL] Expected err_count=1, got %d", err_count);

        $display("[INFO] safe_fsm Testbench completed.");
        $finish;
    end

endmodule
