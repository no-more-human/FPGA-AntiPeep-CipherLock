// ==============================================================================
// 工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
// 模块名称: safe_fsm (保险箱主业务控制状态机与密码比对/输错锁定模块)
// 阶段任务: Day 4~5 - 6位核心密码比对、连续输错3次锁定60秒、蜂鸣器音效联动、反挟持粘滞报警
// 硬件平台: 安路 (Anlogic) EG4S20BG256
// ==============================================================================

`timescale 1ns / 1ps

`ifndef __SAFE_FSM_V__
`define __SAFE_FSM_V__

module safe_fsm #(
    // 默认预设 6 位核心密码: "123456" (6 个 4-bit 十进制数字)
    parameter [23:0] DEFAULT_PWD = {4'h1, 4'h2, 4'h3, 4'h4, 4'h5, 4'h6},
    // 默认预设 6 位反挟持密码: "654321" (为后续 Day 10 创新点预留)
    parameter [23:0] DURESS_PWD  = {4'h6, 4'h5, 4'h4, 4'h3, 4'h2, 4'h1},
    // 锁定时间常量 (标准竞赛规格: 60 秒)
    parameter LOCK_TIMEOUT_SEC   = 60
)(
    input  wire        clk,            // 50MHz 系统主时钟
    input  wire        rst_n,          // 全局异步复位 (低有效)
    input  wire        tick_1k,        // 1kHz (1ms) 系统节拍脉冲
    
    // 键盘扫描模块交互输入
    input  wire [3:0]  key_val,        // 按键键值 (0x0~0x9:数字, 0xE:*, 0xF:#)
    input  wire        key_valid,      // 消抖后单周期按键有效脉冲
    input  wire        duress_clear,   // 外部清除反挟持粘滞报警 (预留给 PC 串口或复位)
    
    // 业务状态输出 (供 OLED、数码管、LED 驱动)
    output reg  [2:0]  state_code,     // 0:IDLE, 1:INPUT, 2:SUCCESS, 3:ERROR, 4:LOCKED
    output reg  [2:0]  pwd_len,        // 当前输入的密码长度 (0~6)
    output reg  [1:0]  err_count,      // 当前累计输错次数 (0~3)
    output reg  [6:0]  lock_countdown, // 锁定倒计时剩余秒数 (0~60)
    output reg         unlock_en,      // 开锁使能 (驱动舵机与成功指示)
    output reg         duress_alarm,   // 挟持静默告警使能 (预留给 PC 串口，粘滞锁存)
    
    // 音效触发脉冲输出 (单周期高电平，连接 buzzer_driver)
    output reg         beep_key,       // 按键音触发
    output reg         beep_err,       // 错误音触发
    output reg         beep_lock,      // 锁定严重报警音触发
    output reg         beep_succ       // 成功和弦音触发
);

// --------------------------------------------------------------------------
// 1. 状态定义
// --------------------------------------------------------------------------
localparam S_IDLE    = 3'd0; // 空闲待机
localparam S_INPUT   = 3'd1; // 密码敲击输入中
localparam S_CHECK   = 3'd2; // 内部密码比对判决 (单周期瞬态)
localparam S_SUCCESS = 3'd3; // 密码正确，开锁成功 (保持 3 秒)
localparam S_ERROR   = 3'd4; // 密码错误提示 (保持 1.5 秒)
localparam S_LOCKED  = 3'd5; // 连续输错 3 次，锁定 60 秒 (键盘锁死)

reg [2:0] state;

// 6 位输入数字暂存缓冲区 (每个 4-bit)
reg [3:0] input_digits [0:5];

// 组装为 24 位总线以便单拍比对
wire [23:0] assembled_input = {
    input_digits[0], input_digits[1], input_digits[2],
    input_digits[3], input_digits[4], input_digits[5]
};

// 毫秒级定时器计数器
reg [11:0] ms_timer;
reg [9:0]  sec_tick_cnt; // 0~999 ms 用于锁定倒计时每秒减 1

// --------------------------------------------------------------------------
// 2. 状态映射输出 (保持与 seg_display 编码对齐)
// --------------------------------------------------------------------------
always @(*) begin
    case (state)
        S_IDLE:    state_code = 3'd0;
        S_INPUT:   state_code = 3'd1;
        S_CHECK:   state_code = 3'd1;
        S_SUCCESS: state_code = 3'd2;
        S_ERROR:   state_code = 3'd3;
        S_LOCKED:  state_code = 3'd4;
        default:   state_code = 3'd0;
    endcase
end

// --------------------------------------------------------------------------
// 3. 主状态机流转控制
// --------------------------------------------------------------------------
integer i;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state          <= S_IDLE;
        pwd_len        <= 3'd0;
        err_count      <= 2'd0;
        lock_countdown <= 7'd0;
        unlock_en      <= 1'b0;
        duress_alarm   <= 1'b0;
        beep_key       <= 1'b0;
        beep_err       <= 1'b0;
        beep_lock      <= 1'b0;
        beep_succ      <= 1'b0;
        ms_timer       <= 12'd0;
        sec_tick_cnt   <= 10'd0;
        for (i = 0; i < 6; i = i + 1) begin
            input_digits[i] <= 4'h0;
        end
    end else begin
        // 默认清除单周期脉冲
        beep_key  <= 1'b0;
        beep_err  <= 1'b0;
        beep_lock <= 1'b0;
        beep_succ <= 1'b0;

        // 外部清除粘滞反挟持告警
        if (duress_clear) begin
            duress_alarm <= 1'b0;
        end

        case (state)
            // --------------------------------------------------------------
            // 空闲待机态
            // --------------------------------------------------------------
            S_IDLE: begin
                unlock_en <= 1'b0;
                pwd_len   <= 3'd0;
                ms_timer  <= 12'd0;
                
                if (key_valid) begin
                    if (key_val <= 4'h9) begin
                        // 敲击首位数字键，进入输入态
                        input_digits[0] <= key_val;
                        pwd_len         <= 3'd1;
                        beep_key        <= 1'b1;
                        state           <= S_INPUT;
                    end else if (key_val == 4'hE) begin // '*' 清空
                        beep_key <= 1'b1;
                    end
                end
            end

            // --------------------------------------------------------------
            // 密码输入态
            // --------------------------------------------------------------
            S_INPUT: begin
                if (key_valid) begin
                    if (key_val <= 4'h9) begin
                        // 输入数字 0~9
                        if (pwd_len < 3'd6) begin
                            input_digits[pwd_len] <= key_val;
                            pwd_len               <= pwd_len + 3'd1;
                            beep_key              <= 1'b1;
                        end else begin
                            // 已满 6 位，仍发出按键音提示
                            beep_key <= 1'b1;
                        end
                    end else if (key_val == 4'hE) begin
                        // '*' 键: 退格一位
                        beep_key <= 1'b1;
                        if (pwd_len > 3'd1) begin
                            pwd_len <= pwd_len - 3'd1;
                        end else if (pwd_len == 3'd1) begin
                            pwd_len <= 3'd0;
                            state   <= S_IDLE; // 全部退完回待机
                        end
                    end else if (key_val == 4'hF) begin
                        // '#' 键: 满 6 位才比对；未满 6 位仅响按键音，不计入错误次数 (P1-G 防呆)
                        beep_key <= 1'b1;
                        if (pwd_len == 3'd6) begin
                            state <= S_CHECK;
                        end
                    end
                end
            end

            // --------------------------------------------------------------
            // 密码比对判决态 (单拍决策)
            // --------------------------------------------------------------
            S_CHECK: begin
                if (pwd_len == 3'd6) begin
                    if (assembled_input == DEFAULT_PWD) begin
                        // 常规密码匹配成功！
                        err_count <= 2'd0;
                        unlock_en <= 1'b1;
                        beep_succ <= 1'b1;
                        ms_timer  <= 12'd3000; // 成功开锁保持 3 秒
                        state     <= S_SUCCESS;
                    end else if (assembled_input == DURESS_PWD) begin
                        // 反挟持密码匹配成功！(表面开门，底层静默粘滞告警 P1-I)
                        err_count    <= 2'd0;
                        unlock_en    <= 1'b1;
                        duress_alarm <= 1'b1;
                        beep_succ    <= 1'b1;
                        ms_timer     <= 12'd3000;
                        state        <= S_SUCCESS;
                    end else begin
                        // 密码不匹配
                        if (err_count >= 2'd2) begin
                            // 连续累计满 3 次输错 -> 触发 60s 系统锁定！
                            err_count      <= 2'd3;
                            lock_countdown <= LOCK_TIMEOUT_SEC;
                            sec_tick_cnt   <= 10'd0;
                            beep_lock      <= 1'b1;
                            state          <= S_LOCKED;
                        end else begin
                            // 输错 1 次或 2 次
                            err_count <= err_count + 2'd1;
                            beep_err  <= 1'b1;
                            ms_timer  <= 12'd1500; // 错误提示保持 1.5 秒
                            state     <= S_ERROR;
                        end
                    end
                end else begin
                    // 安全网分支 (正常流转由 S_INPUT 拦截)
                    state <= S_INPUT;
                end
            end

            // --------------------------------------------------------------
            // 开门成功保持态 (保持 3 秒后自动闭锁回待机)
            // --------------------------------------------------------------
            S_SUCCESS: begin
                if (tick_1k) begin
                    if (ms_timer > 12'd0) begin
                        ms_timer <= ms_timer - 12'd1;
                    end else begin
                        unlock_en <= 1'b0;
                        pwd_len   <= 3'd0;
                        state     <= S_IDLE;
                    end
                end
            end

            // --------------------------------------------------------------
            // 密码错误提示态 (显示 1.5 秒后回待机允许重试)
            // --------------------------------------------------------------
            S_ERROR: begin
                if (tick_1k) begin
                    if (ms_timer > 12'd0) begin
                        ms_timer <= ms_timer - 12'd1;
                    end else begin
                        pwd_len <= 3'd0;
                        state   <= S_IDLE;
                    end
                end
            end

            // --------------------------------------------------------------
            // 连续输错 3 次系统锁定态 (锁定 60s，键盘彻底屏蔽)
            // --------------------------------------------------------------
            S_LOCKED: begin
                unlock_en <= 1'b0;
                pwd_len   <= 3'd0;
                
                // 屏蔽所有 key_valid 敲击事件
                if (tick_1k) begin
                    if (sec_tick_cnt >= 10'd999) begin
                        sec_tick_cnt <= 10'd0;
                        if (lock_countdown > 7'd1) begin
                            lock_countdown <= lock_countdown - 7'd1;
                        end else begin
                            // 60 秒倒计时结束，恢复系统！
                            lock_countdown <= 7'd0;
                            err_count      <= 2'd0;
                            state          <= S_IDLE;
                        end
                    end else begin
                        sec_tick_cnt <= sec_tick_cnt + 10'd1;
                    end
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule

`endif
