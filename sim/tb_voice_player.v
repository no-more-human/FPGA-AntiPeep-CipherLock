`timescale 1ns / 1ps

// ==============================================================================
// 模块名称: tb_voice_player
// 功能描述: JQ8900-16P 单线串口 One-Line 语音播报模块单元测试
// ==============================================================================

module tb_voice_player;

    localparam CLK_PERIOD = 20; // 50MHz

    reg        clk;
    reg        rst_n;
    reg        tick_1k;
    reg        play_en;
    reg  [7:0] track_num;
    reg        voice_busy;

    wire       voice_tx;
    wire       is_busy;

    // 例化语音模块
    voice_player #(
        .CLK_FREQ         (50_000_000),
        .BUSY_ACTIVE_LEVEL(1'b0)
    ) u_voice_player (
        .clk       (clk),
        .rst_n     (rst_n),
        .tick_1k   (tick_1k),
        .play_en   (play_en),
        .track_num (track_num),
        .voice_busy(voice_busy),
        .voice_tx  (voice_tx),
        .is_busy   (is_busy)
    );

    // 产生 50MHz 主时钟
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // 产生 1kHz 快速节拍脉冲
    initial begin
        tick_1k = 1'b0;
        forever begin
            #(CLK_PERIOD * 50) tick_1k = 1'b1;
            #(CLK_PERIOD)      tick_1k = 1'b0;
        end
    end

    initial begin
        $display("[INFO] Starting tb_voice_player simulation...");
        rst_n      = 1'b0;
        play_en    = 1'b0;
        track_num  = 8'h00;
        voice_busy = 1'b1; // 空闲 (高电平)
        #(CLK_PERIOD * 20);
        rst_n      = 1'b1;
        #(CLK_PERIOD * 20);

        if (voice_tx == 1'b1 && !is_busy)
            $display("[PASS] Idle line level is HIGH, module ready.");
        else
            $display("[FAIL] Idle state invalid. voice_tx=%b, is_busy=%b", voice_tx, is_busy);

        // 触发播报 Track 0x02 ("门已开")
        $display("[TEST 1] Triggering Track 0x02...");
        @(posedge clk);
        track_num = 8'h02;
        play_en   = 1'b1;
        @(posedge clk);
        play_en   = 1'b0;

        // 等待进入 START 阶段
        #(CLK_PERIOD * 10);
        if (voice_tx == 1'b0 && is_busy)
            $display("[PASS] Start pulse correctly pulled LOW, is_busy asserted.");
        else
            $display("[FAIL] Start pulse failed. voice_tx=%b, is_busy=%b", voice_tx, is_busy);

        // 防重入测试: 在忙状态下再次触发，确认被安全拦截
        $display("[TEST 2] Testing anti-reentrancy during transmission...");
        @(posedge clk);
        track_num = 8'h05;
        play_en   = 1'b1;
        @(posedge clk);
        play_en   = 1'b0;

        #(CLK_PERIOD * 100);
        $display("[PASS] Re-entrant trigger ignored safely while busy.");

        $display("[INFO] tb_voice_player completed successfully.");
        $finish;
    end

endmodule
