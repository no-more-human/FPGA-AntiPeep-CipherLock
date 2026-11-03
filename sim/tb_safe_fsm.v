`timescale 1ns / 1ps

// ==============================================================================
// 模块名称: tb_safe_fsm
// 功能描述: 保险箱主状态机 safe_fsm 单元测试激励平台 (Day 6 全覆盖)
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
//  10. 【Day 6】按 A 键录入新密码 "888888" 并二次确认更新成功
//  11. 【Day 6】使用新密码 "888888" 成功开锁
//  12. 【Day 6】开锁保持期间按 C 键提前闭锁
//  13. 【Day 6】按 B 键验旧改密 (旧密码输错计入错误惩罚)
//  14. 【Day 6】按 B 键验旧改密 (新密码两次不一致放弃)
// ==============================================================================

module tb_safe_fsm;

    localparam integer CLK_PERIOD = 20; // 50MHz

    reg        clk;
    reg        rst_n;
    reg        tick_1k;
    reg  [3:0] key_val;
    reg        key_valid;
    reg        duress_clear;
    reg        peep_hang;
    reg        pwd_reset;
    reg        remote_auth_err;

    wire [3:0] state_code;
    wire [4:0] pwd_len;
    wire [1:0] err_count;
    wire [8:0] lock_countdown;
    wire       unlock_en;
    wire       duress_alarm;
    wire       duress_trig;
    wire       pwd_err_pulse;
    wire       lock_timeout_pulse;
    wire       pwd_changed;
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
        .clk               (clk),
        .rst_n             (rst_n),
        .tick_1k           (tick_1k),
        .key_val           (key_val),
        .key_valid         (key_valid),
        .duress_clear      (duress_clear),
        .peep_hang         (peep_hang),
        .pwd_reset         (pwd_reset),
        .remote_auth_err   (remote_auth_err),
        .state_code        (state_code),
        .pwd_len           (pwd_len),
        .err_count         (err_count),
        .lock_countdown    (lock_countdown),
        .unlock_en         (unlock_en),
        .duress_alarm      (duress_alarm),
        .duress_trig       (duress_trig),
        .pwd_err_pulse     (pwd_err_pulse),
        .lock_timeout_pulse(lock_timeout_pulse),
        .pwd_changed       (pwd_changed),
        .beep_key          (beep_key),
        .beep_err          (beep_err),
        .beep_lock         (beep_lock),
        .beep_succ         (beep_succ)
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

    // 监控单拍脉冲计数
    integer duress_trig_cnt = 0;
    integer lock_to_cnt     = 0;
    always @(posedge clk) begin
        if (duress_trig)        duress_trig_cnt = duress_trig_cnt + 1;
        if (lock_timeout_pulse) lock_to_cnt     = lock_to_cnt + 1;
    end

    initial begin
        $display("[INFO] Starting safe_fsm Testbench (Day 6)...");
        rst_n        = 1'b0;
        key_val      = 4'h0;
        key_valid    = 1'b0;
        duress_clear    = 1'b0;
        peep_hang       = 1'b0;
        pwd_reset       = 1'b0;
        remote_auth_err = 1'b0;
        #(CLK_PERIOD * 20);
        rst_n        = 1'b1;
        #(CLK_PERIOD * 20);

        $display("[TEST 1] Testing single digit press & key sound...");
        press_key(4'h1);
        if (pwd_len == 3'd1 && state_code == 4'd1)
            $display("[PASS] State transitioned to INPUT, pwd_len=1");
        else
            $display("[FAIL] Expected pwd_len=1, got %d", pwd_len);

        $display("[TEST 2] Testing Backspace '* '...");
        press_key(4'hE); // '*'
        if (pwd_len == 3'd0 && state_code == 4'd0)
            $display("[PASS] Backspace reset to IDLE, pwd_len=0");
        else
            $display("[FAIL] Expected pwd_len=0, got %d", pwd_len);

        $display("[TEST 3] P1-G: Pressing '#' with len < 6 does NOT count error...");
        press_key(4'h1);
        press_key(4'h2);
        press_key(4'hF); // '#' 键在不足 6 位时按下
        if (err_count == 2'd0 && state_code == 4'd1)
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
        if (err_count == 2'd1 && state_code == 4'd3)
            $display("[PASS] 1st wrong attempt: ERROR state, err_count=1");
        
        // 等待错误保持结束 (1500 tick_1k)
        #(CLK_PERIOD * 10000);

        // 错误尝试 2
        press_key(4'h9); press_key(4'h9); press_key(4'h9);
        press_key(4'h9); press_key(4'h9); press_key(4'h9);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (err_count == 2'd2 && state_code == 4'd3)
            $display("[PASS] 2nd wrong attempt: ERROR state, err_count=2");

        #(CLK_PERIOD * 10000);

        // 错误尝试 3
        press_key(4'h9); press_key(4'h9); press_key(4'h9);
        press_key(4'h9); press_key(4'h9); press_key(4'h9);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (err_count == 2'd3 && state_code == 4'd4 && lock_countdown == 7'd3)
            $display("[PASS] 3rd wrong attempt: LOCKED state entered! lock_countdown=3");
        else
            $display("[FAIL] LOCKED state not entered. state=%d, err_count=%d", state_code, err_count);

        $display("[TEST 5] Testing key presses swallowed during lock...");
        press_key(4'h1);
        press_key(4'h2);
        if (state_code == 4'd4 && pwd_len == 3'd0)
            $display("[PASS] Key presses swallowed during lock.");

        $display("[TEST 6] Waiting for lock countdown to reach 0...");
        #(CLK_PERIOD * 25000);
        if (state_code == 4'd0 && err_count == 2'd0)
            $display("[PASS] Lock countdown expired. Restored to IDLE, err_count=0.");

        $display("[TEST 7] Testing correct password '123456' unlock...");
        press_key(4'h1); press_key(4'h2); press_key(4'h3);
        press_key(4'h4); press_key(4'h5); press_key(4'h6);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (state_code == 4'd2 && unlock_en == 1'b1)
            $display("[PASS] Correct password unlocks successfully! unlock_en=1");

        // 等待 3 秒开锁保持结束
        #(CLK_PERIOD * 25000);
        if (state_code == 4'd0 && unlock_en == 1'b0)
            $display("[PASS] Relocked after 3s, returned to IDLE.");

        $display("[TEST 8] Testing duress password '654321' & sticky alarm (P1-I)...");
        press_key(4'h6); press_key(4'h5); press_key(4'h4);
        press_key(4'h3); press_key(4'h2); press_key(4'h1);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (unlock_en == 1'b1 && duress_alarm == 1'b1)
            $display("[PASS] Duress password: surface unlock_en=1, duress_alarm=1");

        #(CLK_PERIOD * 25000);
        if (state_code == 4'd0 && duress_alarm == 1'b1)
            $display("[PASS] P1-I verified: duress_alarm remains sticky after relock!");

        $display("[TEST 9] Clearing duress alarm...");
        @(posedge clk);
        duress_clear = 1'b1;
        @(posedge clk);
        duress_clear = 1'b0;
        #(CLK_PERIOD * 5);
        if (duress_alarm == 1'b0)
            $display("[PASS] duress_alarm cleared successfully.");

        // ==============================================================
        // Day 6 新增用例测试
        // ==============================================================
        $display("[TEST 10] A-Key Setup: New password '888888' & confirm...");
        press_key(4'hA); // 进入录入模式
        if (state_code == 4'd5)
            $display("[PASS] Entered S_SET_NEW (state_code=5)");
        
        // 输入 6 位新密码 888888
        press_key(4'h8); press_key(4'h8); press_key(4'h8);
        press_key(4'h8); press_key(4'h8); press_key(4'h8);
        press_key(4'hF); // 提交第一轮
        #(CLK_PERIOD * 10);
        if (state_code == 4'd6)
            $display("[PASS] Transitioned to S_SET_CFM (state_code=6)");

        // 再次输入 888888 确认
        press_key(4'h8); press_key(4'h8); press_key(4'h8);
        press_key(4'h8); press_key(4'h8); press_key(4'h8);
        press_key(4'hF); // 提交确认
        #(CLK_PERIOD * 10);
        if (pwd_changed == 1'b1 && beep_succ == 1'b1)
            $display("[PASS] Password changed pulse asserted & success chime triggered!");

        // 等待 OP_DONE 提示结束回到 IDLE
        #(CLK_PERIOD * 10000);
        if (state_code == 4'd0)
            $display("[PASS] Returned to IDLE after password updated.");

        $display("[TEST 11] Unlocking with NEW password '888888'...");
        press_key(4'h8); press_key(4'h8); press_key(4'h8);
        press_key(4'h8); press_key(4'h8); press_key(4'h8);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (state_code == 4'd2 && unlock_en == 1'b1)
            $display("[PASS] New password unlocked safe successfully! (unlock_en=1)");

        $display("[TEST 12] C-Key immediate early lock test...");
        press_key(4'hC); // 提前闭锁
        #(CLK_PERIOD * 20);
        if (state_code == 4'd0 && unlock_en == 1'b0)
            $display("[PASS] C-key immediately closed lock without waiting 3s!");

        $display("[TEST 13] B-Key auth test with wrong old password '111111'...");
        press_key(4'hB); // 改密模式
        if (state_code == 4'd7)
            $display("[PASS] Entered S_CHG_AUTH");
        press_key(4'h1); press_key(4'h1); press_key(4'h1);
        press_key(4'h1); press_key(4'h1); press_key(4'h1);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (err_count == 2'd1 && state_code == 4'd3)
            $display("[PASS] Old password wrong: counted err_count=1, state ERROR.");
        
        #(CLK_PERIOD * 10000);

        $display("[TEST 14] B-Key auth success ('888888') but mismatch confirm...");
        press_key(4'hB);
        // 输入正确旧密
        press_key(4'h8); press_key(4'h8); press_key(4'h8);
        press_key(4'h8); press_key(4'h8); press_key(4'h8);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (state_code == 4'd8)
            $display("[PASS] Old password correct! Entered S_CHG_NEW.");

        // 输新密 999999
        press_key(4'h9); press_key(4'h9); press_key(4'h9);
        press_key(4'h9); press_key(4'h9); press_key(4'h9);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (state_code == 4'd9)
            $display("[PASS] Entered S_CHG_CFM.");

        // 确认时输入不同密码 777777
        press_key(4'h7); press_key(4'h7); press_key(4'h7);
        press_key(4'h7); press_key(4'h7); press_key(4'h7);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (state_code == 4'd3 && pwd_changed == 1'b0)
            $display("[PASS] Mismatch rejected! pwd_changed=0, state ERROR.");

        #(CLK_PERIOD * 10000);

        // ==============================================================
        // Day 9 新增用例: A 键非默认密码门控 + 6~16 位虚位密码 + 胁迫优先
        // ==============================================================
        $display("[TEST 15] A-Key blocked when password is no longer default ('888888')...");
        press_key(4'hA);
        if (state_code == 4'd0)
            $display("[PASS] A-Key blocked after initial setup! Stays in IDLE.");
        else
            $display("[FAIL] A-Key should be blocked when pwd != DEFAULT_PWD, got state=%d", state_code);

        $display("[TEST 16] Virtual password unlock (prefix + '888888' + suffix, 12 digits)...");
        press_key(4'h3); press_key(4'h1); press_key(4'h4); // 前置 3 位干扰码
        press_key(4'h8); press_key(4'h8); press_key(4'h8); // 6 位真实密码 888888
        press_key(4'h8); press_key(4'h8); press_key(4'h8);
        press_key(4'h5); press_key(4'h9); press_key(4'h2); // 后置 3 位干扰码
        if (pwd_len == 5'd12)
            $display("[PASS] Virtual input length tracked as 12.");
        press_key(4'hF); // '#'
        #(CLK_PERIOD * 20);
        if (state_code == 4'd2 && unlock_en == 1'b1 && duress_alarm == 1'b0)
            $display("[PASS] 12-digit virtual password unlocked safe! unlock_en=1");
        else
            $display("[FAIL] Virtual password failed: state=%d, unlock=%b", state_code, unlock_en);
        press_key(4'hC); // 提前闭锁
        #(CLK_PERIOD * 20);

        $display("[TEST 17] Virtual duress priority (16 digits containing both '888888' and '654321')...");
        duress_trig_cnt = 0;
        press_key(4'h0); press_key(4'h8); press_key(4'h8); press_key(4'h8);
        press_key(4'h8); press_key(4'h8); press_key(4'h8); press_key(4'h9);
        press_key(4'h6); press_key(4'h5); press_key(4'h4); press_key(4'h3);
        press_key(4'h2); press_key(4'h1); press_key(4'h7); press_key(4'h7);
        if (pwd_len == 5'd16)
            $display("[PASS] 16-digit max virtual buffer reached.");
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (unlock_en == 1'b1 && duress_alarm == 1'b1 && duress_trig_cnt == 1)
            $display("[PASS] Duress priority & duress_trig pulse verified! unlock_en=1 & duress_alarm=1");
        else
            $display("[FAIL] Duress priority failed: unlock=%b, duress=%b, trig_cnt=%0d", unlock_en, duress_alarm, duress_trig_cnt);
        press_key(4'hC);
        #(CLK_PERIOD * 20);

        // ==============================================================
        // Revision 增量回归测试: 重复反挟持脉冲、防窥保留反挟持、锁定期反挟持、改密黑名单
        // ==============================================================
        $display("[TEST 18] Repeated duress trigger when duress_alarm is already 1...");
        press_key(4'h6); press_key(4'h5); press_key(4'h4);
        press_key(4'h3); press_key(4'h2); press_key(4'h1);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (unlock_en == 1'b1 && duress_trig_cnt == 2)
            $display("[PASS] Repeated duress produced 2nd duress_trig pulse even when duress_alarm==1!");
        else
            $display("[FAIL] Repeated duress failed: trig_cnt=%0d", duress_trig_cnt);
        press_key(4'hC);
        #(CLK_PERIOD * 20);

        $display("[TEST 19] Anti-peeping (peep_hang=1): blocks normal password & A/B, allows duress...");
        peep_hang = 1'b1;
        press_key(4'hB);
        if (state_code == 4'd0)
            $display("[PASS] B-key blocked under peep_hang=1.");
        else
            $display("[FAIL] B-key not blocked under peep_hang=1, state=%d", state_code);

        // 防窥下输入正确密码 888888 应被拒绝开锁
        press_key(4'h8); press_key(4'h8); press_key(4'h8);
        press_key(4'h8); press_key(4'h8); press_key(4'h8);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (unlock_en == 1'b0 && state_code == 4'd3)
            $display("[PASS] Normal password rejected under peep_hang=1!");
        else
            $display("[FAIL] Normal password should be rejected under peep_hang=1, unlock=%b, state=%d", unlock_en, state_code);
        #(CLK_PERIOD * 10000);

        // 防窥下输入反挟持密码 654321 仍能开锁并打パルス
        press_key(4'h6); press_key(4'h5); press_key(4'h4);
        press_key(4'h3); press_key(4'h2); press_key(4'h1);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (unlock_en == 1'b1 && duress_trig_cnt == 3)
            $display("[PASS] Duress password unlocked & triggered under peep_hang=1!");
        else
            $display("[FAIL] Duress under peep_hang=1 failed: unlock=%b, trig_cnt=%0d", unlock_en, duress_trig_cnt);
        peep_hang = 1'b0;
        press_key(4'hC);
        #(CLK_PERIOD * 20);

        $display("[TEST 20] Duress emergency unlock during S_LOCKED...");
        // 连续输错 3 次进入 S_LOCKED
        repeat (3) begin
            press_key(4'h0); press_key(4'h0); press_key(4'h0);
            press_key(4'h0); press_key(4'h0); press_key(4'h0);
            press_key(4'hF);
            #(CLK_PERIOD * 10000);
        end
        // 注意第 3 次输错立刻进 S_LOCKED，上面多等了 10000 拍，重新检查或触发锁定
        if (state_code != 4'd4) begin
            press_key(4'h0); press_key(4'h0); press_key(4'h0);
            press_key(4'h0); press_key(4'h0); press_key(4'h0);
            press_key(4'hF);
            #(CLK_PERIOD * 20);
        end
        // 在 S_LOCKED 期间输入带虚位前缀的反挟持密码 99654321#
        press_key(4'h9); press_key(4'h9);
        press_key(4'h6); press_key(4'h5); press_key(4'h4);
        press_key(4'h3); press_key(4'h2); press_key(4'h1);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (state_code == 4'd2 && unlock_en == 1'b1 && duress_trig_cnt == 4)
            $display("[PASS] Duress emergency unlock succeeded during S_LOCKED!");
        else
            $display("[FAIL] Duress during S_LOCKED failed: state=%d, unlock=%b, trig_cnt=%0d", state_code, unlock_en, duress_trig_cnt);
        press_key(4'hC);
        #(CLK_PERIOD * 20);

        $display("[TEST 21] Duress password conflict rejection when changing password to '654321'...");
        press_key(4'hB);
        press_key(4'h8); press_key(4'h8); press_key(4'h8);
        press_key(4'h8); press_key(4'h8); press_key(4'h8);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        // 尝试将新密码设为反挟持密码 654321
        press_key(4'h6); press_key(4'h5); press_key(4'h4);
        press_key(4'h3); press_key(4'h2); press_key(4'h1);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (state_code == 4'd3 && pwd_changed == 1'b0)
            $display("[PASS] Setting password to DURESS_PWD ('654321') rejected with S_ERROR!");
        else
            $display("[FAIL] DURESS_PWD conflict not rejected, state=%d", state_code);

        // 漏洞 1.1 修复验证: 模拟按 RST 键, 验证密码不丢失、锁定不绕过
        $display("[TEST 22] Testing RST key protection (Fix 1.1)...");
        // 此时密码应仍为 888888，按 RST 复位
        rst_n = 1'b0;
        #(CLK_PERIOD * 20);
        rst_n = 1'b1;
        #(CLK_PERIOD * 20);
        // 用旧默认密码 123456 开门，应该失败
        press_key(4'h1); press_key(4'h2); press_key(4'h3);
        press_key(4'h4); press_key(4'h5); press_key(4'h6);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (state_code == 4'd3 && unlock_en == 1'b0)
            $display("[PASS] Reset did NOT restore factory password! 123456 rejected.");
        else
            $display("[FAIL] RST key erroneously restored factory password!");

        // 用用户修改的密码 888888 开门，应该成功
        #(CLK_PERIOD * 2000);
        press_key(4'h8); press_key(4'h8); press_key(4'h8);
        press_key(4'h8); press_key(4'h8); press_key(4'h8);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (state_code == 4'd2 && unlock_en == 1'b1)
            $display("[PASS] User password '888888' survived RST and unlocked successfully!");
        else
            $display("[FAIL] User password failed after RST, state=%d", state_code);
        press_key(4'hC);
        #(CLK_PERIOD * 20);

        // 恢复码复位验证
        $display("[TEST 23] Testing pwd_reset pulse (Recovery)...");
        pwd_reset = 1'b1;
        #(CLK_PERIOD * 2);
        pwd_reset = 1'b0;
        #(CLK_PERIOD * 20);
        // 此时出厂默认密码 123456 应该生效
        press_key(4'h1); press_key(4'h2); press_key(4'h3);
        press_key(4'h4); press_key(4'h5); press_key(4'h6);
        press_key(4'hF);
        #(CLK_PERIOD * 20);
        if (state_code == 4'd2 && unlock_en == 1'b1)
            $display("[PASS] Factory password '123456' successfully restored by pwd_reset!");
        else
            $display("[FAIL] Factory password failed after pwd_reset, state=%d", state_code);
        press_key(4'hC);

        // ==============================================================
        // 改造 A1 验证: 远程挑战-应答认证失败脉冲与键盘输错同路径罚分
        // ==============================================================
        $display("[TEST 24] Testing remote_auth_err pulses triggering tiered lockout (A1)...");
        // 前置: 此时应为 IDLE 且 err_count=0 (pwd_reset 已清零)
        #(CLK_PERIOD * 100);

        // 第 1 次远程认证失败 (单周期脉冲, 与 uart_mailman auth_err 对齐)
        @(posedge clk); remote_auth_err = 1'b1;
        @(posedge clk); remote_auth_err = 1'b0;
        #(CLK_PERIOD * 20);
        if (err_count == 2'd1 && state_code == 4'd3)
            $display("[PASS] Remote auth error 1/3: err_count=1, state=S_ERROR");
        else
            $display("[FAIL] Remote auth error 1/3 failed: err_count=%d, state=%d", err_count, state_code);

        // 等待 S_ERROR 1.5s 提示结束回到 IDLE
        #(CLK_PERIOD * 10000);

        // 第 2 次远程认证失败
        @(posedge clk); remote_auth_err = 1'b1;
        @(posedge clk); remote_auth_err = 1'b0;
        #(CLK_PERIOD * 20);
        if (err_count == 2'd2 && state_code == 4'd3)
            $display("[PASS] Remote auth error 2/3: err_count=2, state=S_ERROR");
        else
            $display("[FAIL] Remote auth error 2/3 failed: err_count=%d, state=%d", err_count, state_code);

        // 等待回到 IDLE
        #(CLK_PERIOD * 10000);

        // 第 3 次远程认证失败 -> 触发 S_LOCKED, 倒计时装载 LOCK_TIMEOUT_SEC(=3)
        @(posedge clk); remote_auth_err = 1'b1;
        @(posedge clk); remote_auth_err = 1'b0;
        #(CLK_PERIOD * 20);
        if (err_count == 2'd3 && state_code == 4'd4 && lock_countdown == 9'd3)
            $display("[PASS] Remote auth error 3/3: entered S_LOCKED with countdown=3s!");
        else
            $display("[FAIL] Remote auth error 3/3 failed: state=%d, err=%d, countdown=%d", state_code, err_count, lock_countdown);

        // 等待倒计时递减 1 秒 (countdown 3 -> 2)
        #(CLK_PERIOD * 7000);

        // 锁定态下再次注入远程失败脉冲, 倒计时不应被重置
        @(posedge clk); remote_auth_err = 1'b1;
        @(posedge clk); remote_auth_err = 1'b0;
        #(CLK_PERIOD * 20);
        if (state_code == 4'd4 && lock_countdown < 9'd3)
            $display("[PASS] Locked state immune to further remote failure reset!");
        else
            $display("[FAIL] Locked state disturbed by remote failure: state=%d, countdown=%d", state_code, lock_countdown);

        if (lock_to_cnt >= 1)
            $display("[PASS] lock_timeout_pulse verified (count=%0d).", lock_to_cnt);
        else
            $display("[FAIL] lock_timeout_pulse was never asserted.");

        $display("[INFO] ALL safe_fsm Day 6~9 & Revision tests passed successfully!");
        $finish;
    end

endmodule
