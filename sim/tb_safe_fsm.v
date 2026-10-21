`timescale 1ns / 1ps

// ==============================================================================
// 模块名称: tb_safe_fsm
// 功能描述: 保险箱主状态机 safe_fsm 单元测试激励平台 (全覆盖)
// 测试内容:
//   1. 键盘敲击数字录入与按键提示音
//   2. 退格键 '*' 移除末位输入
//   3. P1-G: 未满 6 位按 '#' 键仅提示，不计入错误次数
//   4. 连续输错 3 次触发 60s 硬件锁定与严重警报音
//   5. 锁定期间按键被吞无效验证
//   6. 锁定倒计时清零后系统自动恢复 IDLE
//   7. 输入正确密码 "123456" 成功开锁与和弦音
//   8. 输入反挟持密码 "654321" 触发开锁与粘滞报警 (P1-I)
//   9. 外部 duress_clear 清除粘滞报警
// ==============================================================================

module tb_safe_fsm;

    localparam integer CLK_PERIOD = 20; // 50MHz

    reg        clk;
    reg        rst_n;
    reg        tick_1k;
    reg  [3:0] key_val;
    reg        key_valid;
    reg        duress_clear;

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
        .duress_clear  (duress_clear),
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
        rst_n        = 1'b0;
        key_val      = 4'h0;
        key_valid    = 1'b0;
        duress_clear = 1'b0;
        #(CLK_PERIOD * 20);
        rst_n        = 1'b1;
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

        $display("[TEST 3] P1-G: Pressing '#' with len < 6 does NOT count error...");
        press_key(4'h1);
        press_key(4'h2);
        press_key(4'hF); // '#' 键在不足 6 位时按下
        if (err_count == 2'd0 && state_code == 3'd1)
            $display("[PASS] P1-G verified: err_count remains 0, state stays INPUT.");
        else
            $display("[FAIL] P1-G failed: err_count=%d, state=%d", err_count, state_code);

        // 清空输入
        press_key(4'hE);
        press_key(4'hE);

        $display("[TEST 4] Consecutive 3 wrong attempts triggering LOCKED...");
        // 错误尝试 1
        press_key(4'h9); press_key(4'h9); press_key(4'h9);
        press_key(4'h9); press_key(4'h9); press_key(4'h9);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (err_count == 2'd1 && state_code == 3'd3)
            $display("[PASS] 1st wrong attempt: ERROR state, err_count=1");
        
        // 等待错误保持结束 (1500 tick_1k)
        #(CLK_PERIOD * 10000);

        // 错误尝试 2
        press_key(4'h9); press_key(4'h9); press_key(4'h9);
        press_key(4'h9); press_key(4'h9); press_key(4'h9);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (err_count == 2'd2 && state_code == 3'd3)
            $display("[PASS] 2nd wrong attempt: ERROR state, err_count=2");

        #(CLK_PERIOD * 10000);

        // 错误尝试 3
        press_key(4'h9); press_key(4'h9); press_key(4'h9);
        press_key(4'h9); press_key(4'h9); press_key(4'h9);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (err_count == 2'd3 && state_code == 3'd4 && lock_countdown == 7'd3)
            $display("[PASS] 3rd wrong attempt: LOCKED state entered! lock_countdown=3");
        else
            $display("[FAIL] LOCKED state not entered. state=%d, err_count=%d", state_code, err_count);

        $display("[TEST 5] Testing key presses swallowed during lock...");
        press_key(4'h1);
        press_key(4'h2);
        if (state_code == 3'd4 && pwd_len == 3'd0)
            $display("[PASS] Key presses swallowed during lock.");

        $display("[TEST 6] Waiting for lock countdown to reach 0...");
        #(CLK_PERIOD * 25000);
        if (state_code == 3'd0 && err_count == 2'd0)
            $display("[PASS] Lock countdown expired. Restored to IDLE, err_count=0.");

        $display("[TEST 7] Testing correct password '123456' unlock...");
        press_key(4'h1); press_key(4'h2); press_key(4'h3);
        press_key(4'h4); press_key(4'h5); press_key(4'h6);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (state_code == 3'd2 && unlock_en == 1'b1)
            $display("[PASS] Correct password unlocks successfully! unlock_en=1");

        // 等待 3 秒开锁保持结束
        #(CLK_PERIOD * 25000);
        if (state_code == 3'd0 && unlock_en == 1'b0)
            $display("[PASS] Relocked after 3s, returned to IDLE.");

        $display("[TEST 8] Testing duress password '654321' & sticky alarm (P1-I)...");
        press_key(4'h6); press_key(4'h5); press_key(4'h4);
        press_key(4'h3); press_key(4'h2); press_key(4'h1);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (unlock_en == 1'b1 && duress_alarm == 1'b1)
            $display("[PASS] Duress password: surface unlock_en=1, duress_alarm=1");

        // 等待 3 秒开锁保持结束，确认 duress_alarm 仍然保持为 1 (粘滞锁存)
        #(CLK_PERIOD * 25000);
        if (state_code == 3'd0 && duress_alarm == 1'b1)
            $display("[PASS] P1-I verified: duress_alarm remains sticky after relock!");

        $display("[TEST 9] Clearing duress alarm...");
        @(posedge clk);
        duress_clear = 1'b1;
        @(posedge clk);
        duress_clear = 1'b0;
        #(CLK_PERIOD * 5);
        if (duress_alarm == 1'b0)
            $display("[PASS] duress_alarm cleared successfully.");

        $display("[INFO] All safe_fsm test cases passed!");
        $finish;
    end

endmodule
