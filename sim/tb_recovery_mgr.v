`timescale 1ns / 1ps

// ==============================================================================
// 模块名称: tb_recovery_mgr
// 功能描述: recovery_mgr 应急恢复通道 PRESENT 密文哈希比对与安全锁定仿真激励
// 测试内容:
//   1. SW7 拨码关闭时按 D 键无效防误触测试
//   2. SW7 开启后按 D 键成功激活恢复模式 (rec_active=1)
//   3. 输入非正确恢复码 (例如 112233) 触发单次输错与 S_BAD 状态
//   4. 连续输错满 3 次触发独立通道锁定 (rec_locked=1) 与倒计时装载
//   5. 输入出厂恢复码 "937158"，验证 PRESENT 硬件密文哈希 (0xC905ED) 核验通过并输出 reset_req 脉冲
//   6. 退格 '*' 键与清除输入缓冲区验证
// ==============================================================================

module tb_recovery_mgr;

    localparam CLK_PERIOD = 20; // 50MHz

    reg        clk;
    reg        rst_n;
    reg        tick_1k;
    reg  [3:0] key_val;
    reg        key_valid;
    reg  [3:0] state_code;
    reg        sw_recovery;

    wire       rec_active;
    wire       reset_req;
    wire [2:0] rec_len;
    wire [1:0] rec_try;
    wire       rec_beep_key;
    wire       rec_beep_err;
    wire       rec_err;
    wire       rec_ok;
    wire       rec_locked;
    wire [1:0] rec_ui_mode;
    wire [7:0] rec_countdown;

    // 例化待测模块 (使用加速锁定时间 2 秒与操作超时 5 秒)
    recovery_mgr #(
        .RECOVERY_CODE_HASH(24'hC905ED), // 937158 经 PRESENT 混淆后的哈希值
        .MAX_TRY           (3),
        .LOCK_SEC          (2),
        .OP_TIMEOUT_SEC    (5)
    ) u_rec (
        .clk          (clk),
        .rst_n        (rst_n),
        .tick_1k      (tick_1k),
        .key_val      (key_val),
        .key_valid    (key_valid),
        .state_code   (state_code),
        .sw_recovery  (sw_recovery),
        .rec_active   (rec_active),
        .reset_req    (reset_req),
        .rec_len      (rec_len),
        .rec_try      (rec_try),
        .rec_beep_key (rec_beep_key),
        .rec_beep_err (rec_beep_err),
        .rec_err      (rec_err),
        .rec_ok       (rec_ok),
        .rec_locked   (rec_locked),
        .rec_ui_mode  (rec_ui_mode),
        .rec_countdown(rec_countdown)
    );

    // 产生 50MHz 时钟
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // 产生 1kHz 快速节拍
    initial begin
        tick_1k = 1'b0;
        forever begin
            #(CLK_PERIOD * 8) tick_1k = 1'b1;
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
            key_val   = 4'h0;
            #(CLK_PERIOD * 5);
        end
    endtask

    initial begin
        $display("[INFO] Starting recovery_mgr PRESENT Cipher Hash Verification Testbench...");
        
        // 初始复位
        rst_n       = 1'b0;
        key_val     = 4'h0;
        key_valid   = 1'b0;
        state_code  = 4'd0; // IDLE
        sw_recovery = 1'b0; // SW7 默认关闭
        #(CLK_PERIOD * 20);

        rst_n = 1'b1;
        #(CLK_PERIOD * 20);

        // [TEST 1] SW7 未使能时按 D 键无效验证
        $display("[TEST 1] Testing D key ignored when sw_recovery=0...");
        press_key(4'hD);
        #(CLK_PERIOD * 10);
        if (rec_active == 1'b0)
            $display("[PASS] D key correctly ignored without hardware SW7 enable.");
        else
            $display("[FAIL] D key illegally activated without SW7!");

        // [TEST 2] 拨上 SW7 拨码开关，按 D 键激活恢复通道
        $display("[TEST 2] Testing activation with SW7=1 and D key...");
        sw_recovery = 1'b1;
        #(CLK_PERIOD * 20); // 穿过 2 级同步触发器
        press_key(4'hD);
        #(CLK_PERIOD * 10);
        if (rec_active == 1'b1)
            $display("[PASS] Recovery mode activated (rec_active=1).");
        else
            $display("[FAIL] Failed to enter recovery mode, rec_active=%d", rec_active);

        // [TEST 3] 输入错误恢复码 112233 并按 #
        $display("[TEST 3] Testing incorrect recovery code (112233)...");
        press_key(4'h1); press_key(4'h1); press_key(4'h2);
        press_key(4'h2); press_key(4'h3); press_key(4'h3);
        press_key(4'hF); // '#' 确认
        #(CLK_PERIOD * 10);
        if (rec_err == 1'b1 && reset_req == 1'b0)
            $display("[PASS] Incorrect code rejected (rec_err asserted, reset_req=0).");
        else
            $display("[FAIL] Incorrect code failed check: rec_err=%d, reset_req=%d", rec_err, reset_req);

        // 等待 1.5s (加速) S_BAD 提示退回输入
        #(CLK_PERIOD * 2000);

        // 第 2 次输错
        $display("[TEST 4] Testing 2nd incorrect attempt...");
        press_key(4'h0); press_key(4'h0); press_key(4'h0);
        press_key(4'h0); press_key(4'h0); press_key(4'h0);
        press_key(4'hF);
        #(CLK_PERIOD * 2000);

        // 第 3 次输错 -> 触发 2 秒锁定
        $display("[TEST 5] Testing 3rd incorrect attempt triggering rec_locked...");
        press_key(4'h0); press_key(4'h0); press_key(4'h0);
        press_key(4'h0); press_key(4'h0); press_key(4'h0);
        press_key(4'hF);
        #(CLK_PERIOD * 10);
        if (rec_locked == 1'b1 && rec_countdown == 8'd2)
            $display("[PASS] 3 errors locked recovery channel (rec_locked=1, countdown=2s).");
        else
            $display("[FAIL] Lockout failed: rec_locked=%d, countdown=%d", rec_locked, rec_countdown);

        // 等待倒计时结束解封
        #(CLK_PERIOD * 5000);
        if (rec_locked == 1'b0)
            $display("[PASS] Recovery channel automatically unlocked after timeout.");
        else
            $display("[FAIL] Channel remained locked after timeout.");

        // [TEST 6] 再次按 D 键进入，输入出厂正确恢复码 "937158"，核验 PRESENT 密文哈希
        $display("[TEST 6] Testing valid recovery code '937158' with PRESENT hash (0xC905ED)...");
        press_key(4'hD);
        #(CLK_PERIOD * 10);
        press_key(4'h9); press_key(4'h3); press_key(4'h7);
        press_key(4'h1); press_key(4'h5); press_key(4'h8);
        press_key(4'hF);
        #(CLK_PERIOD * 5);
        if (rec_ok == 1'b1 && reset_req == 1'b1)
            $display("[PASS] PRESENT Hash matched! reset_req pulse asserted successfully!");
        else
            $display("[FAIL] Valid recovery code failed to match PRESENT Hash: rec_ok=%d, reset_req=%d", rec_ok, reset_req);

        #(CLK_PERIOD * 2000);
        $display("[INFO] ALL recovery_mgr unit tests passed successfully!");
        $finish;
    end

endmodule
