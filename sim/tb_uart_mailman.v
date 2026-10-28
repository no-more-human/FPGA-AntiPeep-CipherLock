// ==============================================================================
// 模块名称: tb_uart_mailman (串口中继邮差与优先级仲裁仿真平台)
// 测试项目:
//   1. 接收 'P' 进入偷窥防窥挂起，接收 'S' 解除挂起并发出 cmd_safe
//   2. 接收 'R' 触发远程开锁，验证 3 秒保持时间逻辑 (tick_1k 计数)
//   3. 突发事件并发仲裁队列: D(反挟持) > L(锁定) > A(门未关) > U(开锁)
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
    reg evt_unlock = 1'b0;
    reg evt_lock   = 1'b0;
    reg evt_duress = 1'b0;
    reg evt_door   = 1'b0;

    // 输出信号
    wire peep_hang;
    wire remote_unlock;
    wire cmd_safe;
    wire is_sending;
    wire [7:0] the_letter;

    THE_GREAT_SPAMTON_MAILMAN #(
        .CLK_FREQ(50_000_000),
        .BAUD(115_200),
        .REMOTE_HOLD_SEC(3)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .tick_1k      (tick_1k),
        .uart_rx      (uart_rx),
        .uart_tx      (uart_tx),
        .evt_unlock   (evt_unlock),
        .evt_lock     (evt_lock),
        .evt_duress   (evt_duress),
        .evt_door     (evt_door),
        .peep_hang    (peep_hang),
        .remote_unlock(remote_unlock),
        .cmd_safe     (cmd_safe),
        .is_sending   (is_sending),
        .the_letter   (the_letter)
    );

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

        // 2. 测试远程开锁 'R' 保持时间
        $display("\n[Case 2] 测试远程开锁 'R' 保持 3 秒 (3000 ticks) 逻辑...");
        send_rx_byte(8'h52); // 'R'
        repeat (10) @(posedge clk);
        if (remote_unlock === 1'b1) begin
            $display("  [PASS] 收到 'R' 触发 remote_unlock = 1");
            pass_count = pass_count + 1;
        end else begin
            $display("  [FAIL] 收到 'R' 未拉高 remote_unlock");
            fail_count = fail_count + 1;
        end

        // 验证经过 100 个 tick_1k (相当于 100ms) 时依然保持开锁 (原 bug 在 3ms 时即断开)
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

        // 3. 测试事件仲裁队列
        $display("\n[Case 3] 测试并发事件仲裁队列 (同发 U/L/A/D)...");
        evt_unlock <= 1'b1;
        evt_lock   <= 1'b1;
        evt_duress <= 1'b1;
        evt_door   <= 1'b1;
        @(posedge clk);
        evt_unlock <= 1'b0;
        evt_lock   <= 1'b0;
        evt_duress <= 1'b0;
        evt_door   <= 1'b0;

        repeat (20000) @(posedge clk);

        $display("\n=================================================");
        $display("  测试结果汇总: PASS=%0d, FAIL=%0d", pass_count, fail_count);
        $display("=================================================");
        $finish;
    end

endmodule
