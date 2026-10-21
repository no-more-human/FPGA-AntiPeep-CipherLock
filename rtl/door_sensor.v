// ==============================================================================
// 工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
// 模块名称: door_sensor (GPS-23 干簧管门磁与板载SW1双轨检测及15秒未关超时报警模块)
// 阶段任务: Day 5 - 20ms 硬件消抖、开锁后15秒未关门急促声光/语音报警、关门秒级恢复
// 硬件平台: 安路 (Anlogic) EG4S20BG256 (SW_In[1] / 门磁接口 引脚: A10)
// ==============================================================================

`timescale 1ns / 1ps

`ifndef __DOOR_SENSOR_V__
`define __DOOR_SENSOR_V__

module door_sensor #(
    parameter TIMEOUT_SEC   = 15, // 开锁后门未关超时报警阈值 (15秒)
    parameter DEBOUNCE_TIME = 20  // 机械干簧管/拨码开关消抖时间 (20ms)
)(
    input  wire        clk,            // 50MHz 系统主时钟
    input  wire        rst_n,          // 异步复位 (低有效)
    input  wire        tick_1k,        // 1kHz (1ms) 系统基准节拍脉冲
    
    // 门磁物理传感器输入 (板载 SW1 或外接 GPS-23 干簧管)
    // 门关严: 磁铁吸合接 GND -> 读 0
    // 门敞开: 磁铁分离, 内部 PULLUP 拉高 -> 读 1
    input  wire        sensor_gpio,    // 物理输入引脚 (引脚: A10, 内部 PULLUP)
    
    // 业务联动输入
    input  wire        unlock_en,      // 开锁有效信号 (来自 safe_fsm)
    
    // 门磁状态与报警输出
    output reg         door_open,      // 消抖后的门当前物理状态 (0:已关严, 1:敞开)
    output reg         door_alert,     // 超时 15 秒未关门警报信号 (高电平有效)
    output reg         alert_pulse,    // 刚触发超时报警的单周期脉冲 (供语音/蜂鸣器触发)
    output reg  [3:0]  open_sec_cnt    // 门已敞开秒数统计 (0~15秒, 供数码管/OLED显示)
);

// --------------------------------------------------------------------------
// 1. 门磁物理输入 2 级同步打拍 (消除外部异步输入亚稳态)
// --------------------------------------------------------------------------
reg sync_meta;
reg sync_sensor;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sync_meta   <= 1'b0;
        sync_sensor <= 1'b0;
    end else begin
        sync_meta   <= sensor_gpio;
        sync_sensor <= sync_meta;
    end
end

// --------------------------------------------------------------------------
// 2. 20ms 双向硬件滤波消抖 (消除干簧管触点机械抖动)
// --------------------------------------------------------------------------
reg [4:0] debounce_cnt;
reg       sensor_last;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        debounce_cnt <= 5'd0;
        door_open    <= 1'b0;
        sensor_last  <= 1'b0;
    end else if (tick_1k) begin
        sensor_last <= sync_sensor;
        if (sync_sensor != sensor_last) begin
            // 检测到电平跳变，重置消抖计数器
            debounce_cnt <= 5'd0;
        end else if (debounce_cnt < DEBOUNCE_TIME) begin
            debounce_cnt <= debounce_cnt + 5'd1;
        end else begin
            // 稳定保持超过 20ms，确认门状态
            door_open <= sensor_last;
        end
    end
end

// --------------------------------------------------------------------------
// 3. 开锁后 15 秒超时未关门计时与报警逻辑 (3段状态机: 解决开锁延迟拉门失效隐患)
// --------------------------------------------------------------------------
localparam ST_DOOR_IDLE   = 2'd0; // 待机门闭，未布防
localparam ST_DOOR_WAIT   = 2'd1; // 已开锁，等待拉开门 (带 30s 未拉门超时撤防)
localparam ST_DOOR_OPENED = 2'd2; // 门已拉开，15s 未关门超时监控中

reg [1:0]  door_state;
reg [9:0]  ms_cnt;       // 0~999 毫秒计数器
reg [4:0]  wait_sec_cnt; // 0~30s 等待拉门超时

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        door_alert   <= 1'b0;
        alert_pulse  <= 1'b0;
        open_sec_cnt <= 4'd0;
        ms_cnt       <= 10'd0;
        wait_sec_cnt <= 5'd0;
        door_state   <= ST_DOOR_IDLE;
    end else begin
        alert_pulse <= 1'b0; // 默认清除单周期脉冲

        case (door_state)
            ST_DOOR_IDLE: begin
                door_alert   <= 1'b0;
                open_sec_cnt <= 4'd0;
                ms_cnt       <= 10'd0;
                wait_sec_cnt <= 5'd0;
                if (unlock_en) begin
                    // 开锁触发布防
                    if (door_open) begin
                        door_state <= ST_DOOR_OPENED;
                    end else begin
                        door_state <= ST_DOOR_WAIT;
                    end
                end
            end

            ST_DOOR_WAIT: begin
                // 开锁后等待用户拉开箱门
                if (door_open) begin
                    // 用户拉开箱门，进入敞开超时监控
                    ms_cnt       <= 10'd0;
                    open_sec_cnt <= 4'd0;
                    door_state   <= ST_DOOR_OPENED;
                end else if (tick_1k) begin
                    if (ms_cnt >= 10'd999) begin
                        ms_cnt <= 10'd0;
                        if (wait_sec_cnt >= 5'd30) begin
                            // 30秒内从未拉门且锁已回弹，平稳退回 IDLE
                            if (!unlock_en) begin
                                door_state <= ST_DOOR_IDLE;
                            end
                        end else begin
                            wait_sec_cnt <= wait_sec_cnt + 5'd1;
                        end
                    end else begin
                        ms_cnt <= ms_cnt + 10'd1;
                    end
                end
            end

            ST_DOOR_OPENED: begin
                // 门已拉开，开始进行 15 秒超时报警计时
                if (!door_open) begin
                    // 门一旦关严吸合，秒级解除警报并撤防！
                    door_alert   <= 1'b0;
                    open_sec_cnt <= 4'd0;
                    ms_cnt       <= 10'd0;
                    if (!unlock_en) begin
                        door_state <= ST_DOOR_IDLE;
                    end else begin
                        door_state <= ST_DOOR_WAIT;
                    end
                end else if (tick_1k) begin
                    if (ms_cnt >= 10'd999) begin
                        ms_cnt <= 10'd0;
                        if (open_sec_cnt < TIMEOUT_SEC) begin
                            open_sec_cnt <= open_sec_cnt + 4'd1;
                            if (open_sec_cnt + 4'd1 >= TIMEOUT_SEC) begin
                                door_alert  <= 1'b1;
                                alert_pulse <= 1'b1;
                            end
                        end
                    end else begin
                        ms_cnt <= ms_cnt + 10'd1;
                    end
                end
            end

            default: door_state <= ST_DOOR_IDLE;
        endcase
    end
end

endmodule

`endif
