// tb_uart
// tx 的输出直接接 rx 的输入,自己发自己收,发 16 个字节看收回来的是不是同一个
// 不用板子不用串口线,仿真跑一遍就知道波特率/采样点/位序对不对

`timescale 1ns / 1ps

module tb_uart;

    // --------------------------------------------------------------------------
    // 时钟与复位:50MHz -> 周期 20ns
    // --------------------------------------------------------------------------
    reg clk   = 1'b0;
    reg rst_n = 1'b0;

    always #10 clk = ~clk;      // 每 10ns 翻转一次 = 20ns 周期 = 50MHz

    // --------------------------------------------------------------------------
    // 被测信号
    // --------------------------------------------------------------------------
    reg        tx_start = 1'b0;
    reg  [7:0] tx_data  = 8'd0;
    wire       tx_busy;

    wire       loop_line;       // ★ 回环线:tx 的输出直接喂给 rx 的输入
    wire [7:0] rx_data;
    wire       rx_valid;

    // --------------------------------------------------------------------------
    // 例化发送器
    // --------------------------------------------------------------------------
    uart_tx #(
        .CLK_FREQ (50_000_000),
        .BAUD     (115_200)
    ) u_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx_busy  (tx_busy),
        .uart_tx  (loop_line)
    );

    // --------------------------------------------------------------------------
    // 例化接收器(输入接回环线)
    // --------------------------------------------------------------------------
    uart_rx #(
        .CLK_FREQ (50_000_000),
        .BAUD     (115_200)
    ) u_rx (
        .clk      (clk),
        .rst_n    (rst_n),
        .uart_rx  (loop_line),
        .rx_data  (rx_data),
        .rx_valid (rx_valid)
    );

    // --------------------------------------------------------------------------
    // 统计
    // --------------------------------------------------------------------------
    integer pass_cnt = 0;
    integer fail_cnt = 0;
    integer k;

    // --------------------------------------------------------------------------
    // 发一个字节(等发送器空闲了再敲)
    // --------------------------------------------------------------------------
    task automatic send_byte(input [7:0] d);
        begin
            @(posedge clk);
            while (tx_busy) @(posedge clk);   // 等空闲
            tx_start <= 1'b1;
            tx_data  <= d;
            @(posedge clk);
            tx_start <= 1'b0;
        end
    endtask

    // --------------------------------------------------------------------------
    // 等接收完成并比对
    //   一帧 10 bit × 434 拍 = 4340 拍,给足 6000 拍的耐心
    // --------------------------------------------------------------------------
    task automatic check_byte(input [7:0] expect_d);
        begin
            k = 0;
            while ((rx_valid !== 1'b1) && (k < 6000)) begin
                @(posedge clk);
                k = k + 1;
            end
            if (rx_valid !== 1'b1) begin
                $display("  [TIMEOUT] 期望 0x%02X('%c') 但一直没收到 rx_valid",
                         expect_d, expect_d);
                fail_cnt = fail_cnt + 1;
            end else if (rx_data !== expect_d) begin
                $display("  [FAIL]    期望 0x%02X('%c')  实际收到 0x%02X('%c')",
                         expect_d, expect_d, rx_data, rx_data);
                fail_cnt = fail_cnt + 1;
            end else begin
                $display("  [PASS]    0x%02X = '%c'", expect_d, expect_d);
                pass_cnt = pass_cnt + 1;
            end
            @(posedge clk);
        end
    endtask

    // --------------------------------------------------------------------------
    // 主流程
    // --------------------------------------------------------------------------
    initial begin
        $display("");
        $display("============================================================");
        $display("  UART 回环自测平台  (115200 8-N-1)");
        $display("  协议: 'S'安全 'P'偷看 'R'远程开锁 | 'U'开锁 'L'锁定 'D'挟持 'A'门");
        $display("============================================================");

        // 复位 20 拍
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n = 1'b1;
        repeat (20) @(posedge clk);

        $display("");
        $display("---- 第 1 组:协议 7 个字母 ----");
        // 'U' = 0x55 = 0101_0101,完美方波,最好调
        send_byte(8'h55);  check_byte(8'h55);   // 'U' 开锁成功
        send_byte(8'h53);  check_byte(8'h53);   // 'S' 环境安全
        send_byte(8'h50);  check_byte(8'h50);   // 'P' 窥视挂起
        send_byte(8'h52);  check_byte(8'h52);   // 'R' 远程开锁
        send_byte(8'h4C);  check_byte(8'h4C);   // 'L' 系统锁定
        send_byte(8'h44);  check_byte(8'h44);   // 'D' 反挟持
        send_byte(8'h41);  check_byte(8'h41);   // 'A' 门没关严

        $display("");
        $display("---- 第 2 组:边界图案 ----");
        send_byte(8'hAA);  check_byte(8'hAA);   // 1010_1010 反相方波
        send_byte(8'h00);  check_byte(8'h00);   // 全 0
        send_byte(8'hFF);  check_byte(8'hFF);   // 全 1
        send_byte(8'h01);  check_byte(8'h01);   // 只有最低位(考验 LSB 顺序)
        send_byte(8'h80);  check_byte(8'h80);   // 只有最高位
        send_byte(8'h5A);  check_byte(8'h5A);   // 0101_1010 混合

        $display("");
        $display("---- 第 3 组:背靠背连发(考验帧间衔接)----");
        // 连着发两个,中间不等空闲——如果状态机衔接有 bug,这组会挂
        @(posedge clk);
        while (tx_busy) @(posedge clk);
        tx_start <= 1'b1;  tx_data <= 8'h55;
        @(posedge clk);
        tx_start <= 1'b0;
        k = 0;
        while ((rx_valid !== 1'b1) && (k < 6000)) begin @(posedge clk); k = k + 1; end
        if (rx_data === 8'h55) begin $display("  [PASS]    连发第 1 字节 'U'"); pass_cnt = pass_cnt + 1; end
        else begin $display("  [FAIL]    连发第 1 字节,收到 0x%02X", rx_data); fail_cnt = fail_cnt + 1; end
        @(posedge clk);
        k = 0;
        while ((rx_valid !== 1'b1) && (k < 6000)) begin @(posedge clk); k = k + 1; end
        if (rx_data === 8'h53) begin $display("  [PASS]    连发第 2 字节 'S'"); pass_cnt = pass_cnt + 1; end
        else begin $display("  [FAIL]    连发第 2 字节,收到 0x%02X", rx_data); fail_cnt = fail_cnt + 1; end

        // 收尾
        repeat (200) @(posedge clk);
        $display("");
        $display("============================================================");
        $display("  结果: PASS = %0d    FAIL = %0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display("  ★ 全部通过,波特率/采样点/位序全对,可以上板了 ★");
        else               $display("  ✗ 有失败项,先别上板,回去查采样点和位序");
        $display("============================================================");
        $display("");
        $finish;
    end

endmodule
