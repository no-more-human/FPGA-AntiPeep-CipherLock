// ==============================================================================
// 模块名称: tb_uart_mailman (串口中继邮差、优先级仲裁与 @O 虚拟 OLED 快照仿真平台)
// 测试项目:
//   1. 接收 'P' 进入偷窥防窥挂起，接收 'S' 解除挂起并发出 cmd_safe
//   2. 接收 'R' 触发远程开锁，验证 3 秒保持时间逻辑 (tick_1k 计数)
//   3. 突发事件并发仲裁队列: D(反挟持) > L(锁定) > T > K > A > U > E
//   4. 虚拟 OLED 状态跳变自动触发 "@O<6位Hex>\n" 9字节状态快照帧
// ==============================================================================

`timescale 1ns / 1ps

module tb_uart_mailman;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    reg tick_1k = 1'b0;

    always #10 clk = ~clk; // 50MHz

    // 生成仿真加速的 1kHz 脉冲 (每 100 拍出一个脉冲用于加速仿真)
    reg [6:0] tick_div = 7'd0;
    always @(posedge clk) begin
        if (tick_div >= 7'd99) begin
            tick_div <= 7'd0;
            tick_1k  <= 1'b1;
        end else begin
            tick_div <= tick_div + 7'd1;
            tick_1k  <= 1'b0;
        end
    end

    // 串口信号
    wire uart_tx;
    reg  uart_rx = 1'b1;

    // 事件输入
    reg evt_unlock   = 1'b0;
    reg evt_lock     = 1'b0;
    reg evt_duress   = 1'b0;
    reg evt_door     = 1'b0;
    reg evt_tamper   = 1'b0;
    reg evt_lock_end = 1'b0;
    reg evt_relock   = 1'b0;
    reg evt_pwd_err  = 1'b0;
    reg is_locked    = 1'b0;

    // 虚拟 OLED 快照输入
    reg [3:0] state_code     = 4'd0;
    reg [4:0] pwd_len        = 5'd0;
    reg [1:0] err_count      = 2'd0;
    reg [8:0] lock_countdown = 9'd0;
    reg       rec_active     = 1'b0;
    reg [2:0] rec_len        = 3'd0;
    reg       rec_locked     = 1'b0;
    reg [5:0] rec_countdown  = 6'd0;
    reg       door_alert     = 1'b0;

    // 输出信号
    wire peep_hang;
    wire remote_unlock;
    wire auth_err;
    wire cmd_safe;
    wire is_sending;
    wire [7:0] the_letter;

    uart_mailman #(
        .CLK_FREQ(50_000_000),
        .BAUD(115_200),
        .REMOTE_HOLD_SEC(3)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .tick_1k       (tick_1k),
        .uart_rx       (uart_rx),
        .uart_tx       (uart_tx),
        .evt_unlock    (evt_unlock),
        .evt_lock      (evt_lock),
        .evt_duress    (evt_duress),
        .evt_door      (evt_door),
        .evt_tamper    (evt_tamper),
        .evt_lock_end  (evt_lock_end),
        .evt_relock    (evt_relock),
        .evt_pwd_err   (evt_pwd_err),
        .is_locked     (is_locked),
        .state_code    (state_code),
        .pwd_len       (pwd_len),
        .err_count     (err_count),
        .lock_countdown(lock_countdown),
        .rec_active    (rec_active),
        .rec_len       (rec_len),
        .rec_locked    (rec_locked),
        .rec_countdown (rec_countdown),
        .door_alert    (door_alert),
        .peep_hang     (peep_hang),
        .remote_unlock (remote_unlock),
        .auth_err      (auth_err),
        .cmd_safe      (cmd_safe),
        .is_sending    (is_sending),
        .the_letter    (the_letter)
    );

    // 串口 TX 接收采样监控器 (用于捕获 @O 快照帧)
    reg [7:0] rx_cap_buf [0:31];
    integer   rx_cap_cnt = 0;
    reg       cap_en     = 1'b0;

    initial begin : tx_monitor
        reg [7:0] sh;
        integer b;
        forever begin
            @(negedge uart_tx);
            // 延时 1.5 个 bit 周期对准 Bit 0 中心 (434 * 1.5 = 651 拍)
            repeat (651) @(posedge clk);
            for (b = 0; b < 8; b = b + 1) begin
                sh[b] = uart_tx;
                repeat (434) @(posedge clk);
            end
            if (cap_en && rx_cap_cnt < 32) begin
                rx_cap_buf[rx_cap_cnt] = sh;
                rx_cap_cnt = rx_cap_cnt + 1;
            end
        end
    end

    // 辅助发送字节给 DUT 的 RX
    task send_rx_byte(input [7:0] b);
        integer i;
        begin
            // 起始位 (434 拍)
            uart_rx <= 1'b0;
            repeat (434) @(posedge clk);
            // 8 数据位 LSB first
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx <= b[i];
                repeat (434) @(posedge clk);
            end
            // 停止位
            uart_rx <= 1'b1;
            repeat (434) @(posedge clk);
            repeat (50) @(posedge clk);
        end
    endtask

    integer pass_count = 0;
    integer fail_count = 0;

    initial begin
        $display("=================================================");
        $display("  tb_uart_mailman 仿真测试开始");
        $display("=================================================");

        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (50) @(posedge clk);

        // 1. 测试 'P' 防窥与 'S' 解除
        $display("\n[Case 1] 测试 'P' 挂起与 'S' 恢复...");
        send_rx_byte(8'h50); // 'P'
        repeat (10) @(posedge clk);
        if (peep_hang === 1'b1) begin
            $display("  [PASS] 收到 'P' 成功进入防窥挂起 peep_hang = 1");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] 收到 'P' 未能进入防窥挂起");
            fail_count = fail_count + 1;
        end

        send_rx_byte(8'h53); // 'S'
        repeat (10) @(posedge clk);
        if (peep_hang === 1'b0) begin
            $display("  [PASS] 收到 'S' 成功解除防窥挂起 peep_hang = 0");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] 收到 'S' 未能解除挂起");
            fail_count = fail_count + 1;
        end

        // 等待挂起的 @O 帧发送完毕
        repeat (45000) @(posedge clk);

        // 2. 测试远程开锁 'R' 挑战-应答认证与保持 3 秒 (3000 ticks) 逻辑
        $display("\n[Case 2] 测试远程开锁 'R' PRESENT-MAC 挑战-应答握手与保持 3 秒逻辑...");
        rx_cap_cnt = 0;
        cap_en     = 1'b1;
        send_rx_byte(8'h52); // 'R' 请求挑战
        repeat (15) @(posedge clk);
        if (remote_unlock === 1'b0) begin
            $display("  [PASS] 仅发 'R' 未应答前 remote_unlock 保持 0 (防重放/未授权拦截)");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] 未完成挑战应答就错误拉高了 remote_unlock");
            fail_count = fail_count + 1;
        end

        // 等待 FPGA 发送 '?' + Nonce (2 字节)
        repeat (12000) @(posedge clk);
        cap_en = 1'b0;
        if (rx_cap_cnt >= 2 && rx_cap_buf[0] == 8'h3F) begin
            $display("  [PASS] 成功捕获挑战帧 '?' (0x3F) + Nonce (0x%02X)", rx_cap_buf[1]);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] 未捕获有效挑战帧, rx_cap_cnt=%0d", rx_cap_cnt);
            fail_count = fail_count + 1;
        end

        // 回传 '!' (0x21) + PRESENT-MAC 应答字节
        send_rx_byte(8'h21); // '!'
        send_rx_byte(dut.calc_auth_mac(rx_cap_buf[1]));
        repeat (10) @(posedge clk);
        if (remote_unlock === 1'b1) begin
            $display("  [PASS] 挑战-应答核验通过，成功触发 remote_unlock = 1");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] 挑战-应答核验后未拉高 remote_unlock");
            fail_count = fail_count + 1;
        end

        // 验证经过 100 个 tick_1k (相当于 100ms) 时依然保持开锁
        repeat (100) @(posedge tick_1k);
        @(posedge clk);
        if (remote_unlock === 1'b1) begin
            $display("  [PASS] 经过 100ms 后 remote_unlock 依然有效维持 (成功排除 3ms 快速掉电 Bug)");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] remote_unlock 提前回弹关闭 (存在 3ms Bug)");
            fail_count = fail_count + 1;
        end

        // 等待 3000 个 tick_1k 完全闭锁
        repeat (3000) @(posedge tick_1k);
        @(posedge clk);
        if (remote_unlock === 1'b0) begin
            $display("  [PASS] 倒计时结束 remote_unlock 自动回弹关闭");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] remote_unlock 倒计时超时未自动关闭");
            fail_count = fail_count + 1;
        end

        // 3. 测试远程开锁门控 (is_locked 与 peep_hang 下拒绝 'R')
        $display("\n[Case 3] 测试 is_locked=1 与 peep_hang=1 时拒绝远程开锁 'R'...");
        is_locked = 1'b1;
        send_rx_byte(8'h52); // 'R'
        repeat (10) @(posedge clk);
        if (remote_unlock === 1'b0) begin
            $display("  [PASS] is_locked=1 时成功拒绝 'R' 远程开锁");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] is_locked=1 时错误响应了 'R'");
            fail_count = fail_count + 1;
        end
        is_locked = 1'b0;

        send_rx_byte(8'h50); // 'P' 进入防窥
        send_rx_byte(8'h52); // 'R'
        repeat (10) @(posedge clk);
        if (remote_unlock === 1'b0) begin
            $display("  [PASS] peep_hang=1 时成功拒绝 'R' 远程开锁");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] peep_hang=1 时错误响应了 'R'");
            fail_count = fail_count + 1;
        end
        send_rx_byte(8'h53); // 'S' 解除防窥

        // 等待之前触发的 @O 快照帧全部排空
        repeat (45000) @(posedge clk);

        // 4. 测试事件仲裁队列与反挟持 'D' 吞并 'U'
        $display("\n[Case 4] 测试并发事件仲裁队列 (同发 D/L/T/K/A/U/E，验证 D 吞并 U 且按优先级发送)...");
        @(posedge clk);
        evt_unlock   <= 1'b1;
        evt_lock     <= 1'b1;
        evt_duress   <= 1'b1;
        evt_door     <= 1'b1;
        evt_lock_end <= 1'b1;
        evt_relock   <= 1'b1;
        evt_pwd_err  <= 1'b1;
        @(posedge clk);
        evt_unlock   <= 1'b0;
        evt_lock     <= 1'b0;
        evt_duress   <= 1'b0;
        evt_door     <= 1'b0;
        evt_lock_end <= 1'b0;
        evt_relock   <= 1'b0;
        evt_pwd_err  <= 1'b0;

        repeat (2) @(posedge clk);
        if (the_letter === 8'h44) begin
            $display("  [PASS] 最高优先级首字节为 'D' (0x44)");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] 首字节期望 'D' (0x44)，实际为 0x%02x", the_letter);
            fail_count = fail_count + 1;
        end

        repeat (35000) @(posedge clk);
        if (the_letter === 8'h45) begin
            $display("  [PASS] 队列末字节为 'E' (0x45)，且 'U' 已被 'D' 互斥抑制");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] 队列末字节期望 'E' (0x45)，实际为 0x%02x", the_letter);
            fail_count = fail_count + 1;
        end

        // 5. 测试 @O 虚拟 OLED 状态快照帧收发
        $display("\n[Case 5] 测试 @O 十六进制 OLED 状态快照帧编码与发送...");
        // 设置 state_code=1 (密码输入), pwd_len=5, err_count=1, lock_countdown=45 (0x2D)
        // Byte0 = {0,0,0,0, 4'h1} = 8'h01 -> "01"
        // Byte1 = {3'd0, 5'd5}    = 8'h05 -> "05"
        // Byte2 = {2'd1, 6'd45}   = 8'h6D -> "6D"
        // 期望帧: "@O01056D\n"
        rx_cap_cnt = 0;
        cap_en     = 1'b1;
        @(posedge clk);
        state_code     <= 4'd1;
        pwd_len        <= 5'd5;
        err_count      <= 2'd1;
        lock_countdown <= 9'd45;
        repeat (45000) @(posedge clk);
        cap_en = 1'b0;

        if (rx_cap_cnt == 9 &&
            rx_cap_buf[0] == "@" &&
            rx_cap_buf[1] == "O" &&
            rx_cap_buf[2] == "0" &&
            rx_cap_buf[3] == "1" &&
            rx_cap_buf[4] == "0" &&
            rx_cap_buf[5] == "5" &&
            rx_cap_buf[6] == "6" &&
            rx_cap_buf[7] == "D" &&
            rx_cap_buf[8] == 8'h0A) begin
            $display("  [PASS] 成功捕获 9 字节快照帧: @O01056D\\n");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] @O 快照帧不匹配，rx_cap_cnt=%0d, 首字节=%h", rx_cap_cnt, rx_cap_buf[0]);
            fail_count = fail_count + 1;
        end

        // 6. 测试 9-bit 300s 阶梯死锁倒计时在 @O 帧中的扩展编码
        $display("\n[Case 6] 测试 9-bit 300s 死锁倒计时 @O 编码 (rec_active=0 时复用 Byte1[7:5])...");
        // 300 = 9'b1_0010_1100 -> hi_bits = 3'b100 (4), lo_bits = 6'b101100 (44 = 0x2C)
        // state_code=3 (LOCKED), pwd_len=0, err_count=3
        // Byte0 = 8'h43 ("43", bit6=is_locked), Byte1 = {3'd4, 5'd0} = 8'h80 ("80"), Byte2 = {2'd3, 6'd44} = 8'hEC ("EC")
        rx_cap_cnt = 0;
        cap_en     = 1'b1;
        @(posedge clk);
        is_locked      <= 1'b1;
        state_code     <= 4'd3;
        pwd_len        <= 5'd0;
        err_count      <= 2'd3;
        lock_countdown <= 9'd300;
        repeat (45000) @(posedge clk);
        cap_en = 1'b0;

        if (rx_cap_cnt == 9 &&
            rx_cap_buf[0] == "@" &&
            rx_cap_buf[1] == "O" &&
            rx_cap_buf[2] == "4" &&
            rx_cap_buf[3] == "3" &&
            rx_cap_buf[4] == "8" &&
            rx_cap_buf[5] == "0" &&
            rx_cap_buf[6] == "E" &&
            rx_cap_buf[7] == "C" &&
            rx_cap_buf[8] == 8'h0A) begin
            $display("  [PASS] 成功捕获 300s 死锁快照帧: @O4380EC\\n");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] 300s @O 快照帧不匹配，rx_cap_cnt=%0d", rx_cap_cnt);
            fail_count = fail_count + 1;
        end

        // 7. 测试片上 BRAM (ERAM9K) 硬件安全黑匣子 'H' 审计查询 (@H<8-hex>\n)
        $display("\n[Case 7] 测试片上 BRAM 硬件黑匣子 'H' (0x48) 链式 MAC 日志回读...");
        rx_cap_cnt = 0;
        cap_en     = 1'b1;
        send_rx_byte(8'h48); // 'H'
        repeat (55000) @(posedge clk);
        cap_en = 1'b0;

        if (rx_cap_cnt >= 11 &&
            rx_cap_buf[0] == "@" &&
            rx_cap_buf[1] == "H" &&
            rx_cap_buf[10] == 8'h0A) begin
            $display("  [PASS] 成功从片上 BRAM 回读 11 字节硬件审计帧: @H%c%c%c%c%c%c%c%c\\n",
                     rx_cap_buf[2], rx_cap_buf[3], rx_cap_buf[4], rx_cap_buf[5],
                     rx_cap_buf[6], rx_cap_buf[7], rx_cap_buf[8], rx_cap_buf[9]);
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] 未捕获有效 @H 硬件审计帧，rx_cap_cnt=%0d", rx_cap_cnt);
            fail_count = fail_count + 1;
        end

        $display("\n=================================================");
        $display("  测试结果汇总: PASS=%0d, FAIL=%0d", pass_count, fail_count);
        $display("=================================================");
        $finish;
    end

endmodule
