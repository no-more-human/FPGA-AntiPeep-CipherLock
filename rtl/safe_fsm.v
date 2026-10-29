// ==============================================================================
// 工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
// 模块名称: safe_fsm (保险箱主业务控制状态机与密码比对/输错锁定/动态改密模块)
// 阶段任务: Day 6 - 动态密码寄存器、A键首次录入、B键验旧改密、C键提前闭锁、15s超时防呆
//           Day 9 - 日常开锁 6~16 位虚位密码: 16 级移位缓冲 + 11 组并行窗口单拍比对
//                   (胁迫密码优先匹配); A 键仅在密码仍为出厂默认值时可用
// 硬件平台: 安路 (Anlogic) EG4S20BG256
// ==============================================================================

`timescale 1ns / 1ps

`ifndef __SAFE_FSM_V__
`define __SAFE_FSM_V__

module safe_fsm #(
    // 默认初始预设 6 位核心密码: "123456" (6 个 4-bit 十进制数字)
    parameter [23:0] DEFAULT_PWD       = {4'h1, 4'h2, 4'h3, 4'h4, 4'h5, 4'h6},
    // 默认预设 6 位反挟持密码: "654321" (为后续 Day 10 创新点预留)
    parameter [23:0] DURESS_PWD        = {4'h6, 4'h5, 4'h4, 4'h3, 4'h2, 4'h1},
    // 锁定时间常量 (标准竞赛规格: 60 秒)
    parameter        LOCK_TIMEOUT_SEC  = 60,
    // 录入/改密流程无操作超时时间 (15 秒)
    parameter        OP_TIMEOUT_SEC    = 15
)(
    input  wire        clk,            // 50MHz 系统主时钟
    input  wire        rst_n,          // 全局异步复位 (低有效)
    input  wire        tick_1k,        // 1kHz (1ms) 系统节拍脉冲
    
    // 键盘扫描模块交互输入
    input  wire [3:0]  key_val,        // 按键键值 (0x0~0x9:数字, 0xA:A, 0xB:B, 0xC:C, 0xE:*, 0xF:#)
    input  wire        key_valid,      // 消抖后单周期按键有效脉冲
    input  wire        duress_clear,   // 外部清除反挟持粘滞报警 (预留给 PC 串口或复位)
    
    // 业务状态输出 (供 OLED、数码管、LED 驱动，扩充为 4 位)
    // 0:IDLE, 1:INPUT, 2:SUCCESS, 3:ERROR, 4:LOCKED, 5:SET_NEW, 6:SET_CFM, 7:CHG_AUTH, 8:CHG_NEW, 9:CHG_CFM, 10:OP_DONE
    output reg  [3:0]  state_code,     
    output reg  [4:0]  pwd_len,        // 当前输入的密码长度 (日常开锁 0~16, 录入/改密 0~6)
    output reg  [1:0]  err_count,      // 当前累计输错次数 (0~3)
    output reg  [6:0]  lock_countdown, // 锁定倒计时剩余秒数 (0~60)
    output reg         unlock_en,      // 开锁使能 (驱动舵机与成功指示)
    output reg         duress_alarm,   // 挟持静默告警使能 (预留给 PC 串口，粘滞锁存)
    output reg         pwd_changed,    // 密码成功更新单周期脉冲 (供语音播报 Track 5)
    
    // 音效触发脉冲输出 (单周期高电平，连接 buzzer_driver)
    output reg         beep_key,       // 按键音触发
    output reg         beep_err,       // 错误音触发
    output reg         beep_lock,      // 锁定严重报警音触发
    output reg         beep_succ       // 成功和弦音触发
);

// --------------------------------------------------------------------------
// 1. 状态定义
// --------------------------------------------------------------------------
localparam S_IDLE     = 4'd0;  // 空闲待机
localparam S_INPUT    = 4'd1;  // 密码敲击输入中
localparam S_CHECK    = 4'd2;  // 内部密码比对判决 (单周期瞬态)
localparam S_SUCCESS  = 4'd3;  // 密码正确，开锁成功 (保持 3 秒)
localparam S_ERROR    = 4'd4;  // 密码错误提示 (保持 1.5 秒)
localparam S_LOCKED   = 4'd5;  // 连续输错 3 次，锁定 60 秒 (键盘锁死)
localparam S_SET_NEW  = 4'd6;  // A键: 首次录入-输入6位新密码
localparam S_SET_CFM  = 4'd7;  // A键: 首次录入-再次输入确认
localparam S_CHG_AUTH = 4'd8;  // B键: 改密-输入旧密码验权
localparam S_CHG_NEW  = 4'd9;  // B键: 改密-输入6位新密码
localparam S_CHG_CFM  = 4'd10; // B键: 改密-再次输入确认
localparam S_OP_DONE  = 4'd11; // 录入/改密成功提示保持 (1.5秒)

reg [3:0]  state;

// 动态密码寄存器 (上电/复位时赋初始值 DEFAULT_PWD)
reg [23:0] current_pwd;

// 6 位输入数字暂存缓冲区 (每个 4-bit)
reg [3:0]  input_digits [0:5];

// 6 位二次确认对比暂存缓冲区 (用于 A/B 键确认新密码)
reg [3:0]  new_pwd_digits [0:5];

// 组装为 24 位总线以便单拍比对
wire [23:0] assembled_input = {
    input_digits[0], input_digits[1], input_digits[2],
    input_digits[3], input_digits[4], input_digits[5]
};

wire [23:0] assembled_new = {
    new_pwd_digits[0], new_pwd_digits[1], new_pwd_digits[2],
    new_pwd_digits[3], new_pwd_digits[4], new_pwd_digits[5]
};

// 毫秒级定时器计数器
reg [11:0] ms_timer;
reg [9:0]  sec_tick_cnt;  // 0~999 ms 用于锁定倒计时每秒减 1
reg [13:0] op_timeout_ms; // 15 秒无操作看门狗定时器 (0~15000ms)

// --------------------------------------------------------------------------
// 1.1 日常开锁 16 位虚位密码移位缓冲区 (Day 9)
//     每敲一个数字整体左移 4 bit，最新数字进入 vbuf[3:0]，最多保留最近 16 位。
//     按顺序敲入 d0 d1 d2 d3 d4 d5 后，vbuf[23:0] = {d0,d1,d2,d3,d4,d5}，
//     与 current_pwd / DURESS_PWD 的 {高位先输} 编码天然对齐。
// --------------------------------------------------------------------------
reg [63:0] vbuf;

// 11 组 6 位滑动窗口 (窗口 i = vbuf[i*4+23 : i*4])，在同一个时钟周期内并行比对
// 只有完全落在已输入范围内的窗口才有效 (i + 6 <= pwd_len)，避免缓冲区残留的 0 误匹配
wire [10:0] win_valid;
wire [10:0] win_hit_norm;
wire [10:0] win_hit_duress;

genvar g;
generate
    for (g = 0; g < 11; g = g + 1) begin : g_vwin
        assign win_valid[g]      = (pwd_len >= (g + 6));
        assign win_hit_norm[g]   = win_valid[g] && (vbuf[g*4 +: 24] == current_pwd);
        assign win_hit_duress[g] = win_valid[g] && (vbuf[g*4 +: 24] == DURESS_PWD);
    end
endgenerate

wire match_norm   = |win_hit_norm;
wire match_duress = |win_hit_duress;

// A 键开荒录入门控: 只有密码仍为出厂默认值时才允许免验旧密码直接设置
wire pwd_is_default = (current_pwd == DEFAULT_PWD);

// --------------------------------------------------------------------------
// 2. 状态映射输出 (与 seg_display / oled_driver 编码对齐)
//    改为寄存器输出 (比 state 晚 1 拍 = 20ns)，切断 safe_fsm -> oled_driver
//    字模译码之间的长组合路径，改善 50MHz 时序裕量
// --------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_code <= 4'd0;
    end else begin
        case (state)
            S_IDLE:     state_code <= 4'd0;
            S_INPUT:    state_code <= 4'd1;
            S_CHECK:    state_code <= 4'd1;
            S_SUCCESS:  state_code <= 4'd2;
            S_ERROR:    state_code <= 4'd3;
            S_LOCKED:   state_code <= 4'd4;
            S_SET_NEW:  state_code <= 4'd5;
            S_SET_CFM:  state_code <= 4'd6;
            S_CHG_AUTH: state_code <= 4'd7;
            S_CHG_NEW:  state_code <= 4'd8;
            S_CHG_CFM:  state_code <= 4'd9;
            S_OP_DONE:  state_code <= 4'd10;
            default:    state_code <= 4'd0;
        endcase
    end
end

// --------------------------------------------------------------------------
// 3. 主状态机流转控制
// --------------------------------------------------------------------------
integer i;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state          <= S_IDLE;
        current_pwd    <= DEFAULT_PWD;
        pwd_len        <= 5'd0;
        vbuf           <= 64'd0;
        err_count      <= 2'd0;
        lock_countdown <= 7'd0;
        unlock_en      <= 1'b0;
        duress_alarm   <= 1'b0;
        pwd_changed    <= 1'b0;
        beep_key       <= 1'b0;
        beep_err       <= 1'b0;
        beep_lock      <= 1'b0;
        beep_succ      <= 1'b0;
        ms_timer       <= 12'd0;
        sec_tick_cnt   <= 10'd0;
        op_timeout_ms  <= 14'd0;
        for (i = 0; i < 6; i = i + 1) begin
            input_digits[i]   <= 4'h0;
            new_pwd_digits[i] <= 4'h0;
        end
    end else begin
        // 默认清除单周期脉冲
        beep_key    <= 1'b0;
        beep_err    <= 1'b0;
        beep_lock   <= 1'b0;
        beep_succ   <= 1'b0;
        pwd_changed <= 1'b0;

        // 外部清除粘滞反挟持告警
        if (duress_clear) begin
            duress_alarm <= 1'b0;
        end

        // 录入与改密流程的 15 秒无操作看门狗计时
        if (state == S_SET_NEW || state == S_SET_CFM ||
            state == S_CHG_AUTH || state == S_CHG_NEW || state == S_CHG_CFM) begin
            if (key_valid) begin
                op_timeout_ms <= 14'd15000; // 只要有任何按键按下，重置 15s 看门狗
            end else if (tick_1k) begin
                if (op_timeout_ms > 14'd0) begin
                    op_timeout_ms <= op_timeout_ms - 14'd1;
                end else begin
                    // 15 秒超时无操作，强制放弃改密/录入流程，安全退回待机
                    pwd_len  <= 3'd0;
                    beep_err <= 1'b1;
                    state    <= S_IDLE;
                end
            end
        end

        case (state)
            // --------------------------------------------------------------
            // 空闲待机态
            // --------------------------------------------------------------
            S_IDLE: begin
                unlock_en <= 1'b0;
                pwd_len   <= 5'd0;
                ms_timer  <= 12'd0;
                
                if (key_valid) begin
                    if (key_val <= 4'h9) begin
                        // 敲击首位数字键，进入日常开锁输入态 (清空虚位缓冲，首位进入最低 nibble)
                        vbuf            <= {60'd0, key_val};
                        pwd_len         <= 5'd1;
                        beep_key        <= 1'b1;
                        state           <= S_INPUT;
                    end else if (key_val == 4'hA) begin
                        // 'A' 键: 新用户开荒录入通道 (直接输 6 位新密码)
                        // 安全门控: 仅当密码仍为出厂默认值时可用；改过密码后只能走 B 键验旧改密
                        beep_key      <= 1'b1;
                        if (pwd_is_default) begin
                            pwd_len       <= 5'd0;
                            op_timeout_ms <= 14'd15000;
                            state         <= S_SET_NEW;
                        end
                    end else if (key_val == 4'hB) begin
                        // 'B' 键: 老用户安全改密通道 (需先验旧密码)
                        pwd_len       <= 3'd0;
                        beep_key      <= 1'b1;
                        op_timeout_ms <= 14'd15000;
                        state         <= S_CHG_AUTH;
                    end else if (key_val == 4'hC) begin
                        // 'C' 键: 待机强刷清屏
                        beep_key <= 1'b1;
                    end else if (key_val == 4'hE) begin
                        // '*' 键: 提示音
                        beep_key <= 1'b1;
                    end
                end
            end

            // --------------------------------------------------------------
            // 密码输入态 (日常开锁，6~16 位虚位密码)
            // --------------------------------------------------------------
            S_INPUT: begin
                if (key_valid) begin
                    if (key_val <= 4'h9) begin
                        // 输入数字 0~9: 整体左移，新数字进入最低 nibble；
                        // 超过 16 位后最早的数字自然移出，长度饱和在 16
                        vbuf     <= {vbuf[59:0], key_val};
                        beep_key <= 1'b1;
                        if (pwd_len < 5'd16) begin
                            pwd_len <= pwd_len + 5'd1;
                        end
                    end else if (key_val == 4'hE) begin
                        // '*' 键: 退格一位 (右移撤销最新数字)，全部退完回待机
                        beep_key <= 1'b1;
                        vbuf     <= {4'h0, vbuf[63:4]};
                        if (pwd_len > 5'd1) begin
                            pwd_len <= pwd_len - 5'd1;
                        end else begin
                            pwd_len <= 5'd0;
                            state   <= S_IDLE;
                        end
                    end else if (key_val == 4'hF) begin
                        // '#' 键: 满 6 位才比对；未满 6 位仅提示音防呆 (不计错误)
                        beep_key <= 1'b1;
                        if (pwd_len >= 5'd6) begin
                            state <= S_CHECK;
                        end
                    end
                end
            end

            // --------------------------------------------------------------
            // 密码比对判决态 (单拍决策: 11 组窗口并行比对动态 current_pwd 与胁迫密码)
            // 胁迫密码优先: 只要任一窗口出现胁迫密码，一律走静默报警开锁
            // --------------------------------------------------------------
            S_CHECK: begin
                vbuf    <= 64'd0;   // 判决后立即清除缓冲区，密码不在寄存器中残留
                pwd_len <= 5'd0;
                if (match_duress) begin
                    // 反挟持密码匹配成功！(表面开门，底层静默粘滞告警)
                    err_count    <= 2'd0;
                    unlock_en    <= 1'b1;
                    duress_alarm <= 1'b1;
                    beep_succ    <= 1'b1;
                    ms_timer     <= 12'd3000;
                    state        <= S_SUCCESS;
                end else if (match_norm) begin
                    // 动态密码匹配成功！
                    err_count <= 2'd0;
                    unlock_en <= 1'b1;
                    beep_succ <= 1'b1;
                    ms_timer  <= 12'd3000; // 成功开锁保持 3 秒
                    state     <= S_SUCCESS;
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
            end

            // --------------------------------------------------------------
            // 开门成功保持态 (保持 3 秒后回弹，支持按 C 键提前闭锁)
            // --------------------------------------------------------------
            S_SUCCESS: begin
                if (key_valid && (key_val == 4'hC)) begin
                    // 按 C 键立即手动闭锁回待机，无需等待满 3 秒！
                    unlock_en <= 1'b0;
                    pwd_len   <= 3'd0;
                    beep_key  <= 1'b1;
                    state     <= S_IDLE;
                end else if (tick_1k) begin
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

            // --------------------------------------------------------------
            // 【Day 6 任务】A 键开荒录入 - 输入 6 位新密码
            // --------------------------------------------------------------
            S_SET_NEW: begin
                if (key_valid) begin
                    if (key_val <= 4'h9) begin
                        if (pwd_len < 3'd6) begin
                            input_digits[pwd_len] <= key_val;
                            pwd_len               <= pwd_len + 3'd1;
                            beep_key              <= 1'b1;
                        end
                    end else if (key_val == 4'hE) begin
                        // '*' 键: 正在输入时退格；为空时直接取消录入退回待机
                        beep_key <= 1'b1;
                        if (pwd_len > 3'd0) begin
                            pwd_len <= pwd_len - 3'd1;
                        end else begin
                            state <= S_IDLE;
                        end
                    end else if (key_val == 4'hF) begin
                        // '#' 键: 满 6 位后暂存新密码，推进入二次确认阶段
                        beep_key <= 1'b1;
                        if (pwd_len == 3'd6) begin
                            for (i = 0; i < 6; i = i + 1) begin
                                new_pwd_digits[i] <= input_digits[i];
                            end
                            pwd_len       <= 3'd0;
                            op_timeout_ms <= 14'd15000;
                            state         <= S_SET_CFM;
                        end
                    end
                end
            end

            // --------------------------------------------------------------
            // 【Day 6 任务】A 键开荒录入 - 再次输入新密码进行确认
            // --------------------------------------------------------------
            S_SET_CFM: begin
                if (key_valid) begin
                    if (key_val <= 4'h9) begin
                        if (pwd_len < 3'd6) begin
                            input_digits[pwd_len] <= key_val;
                            pwd_len               <= pwd_len + 3'd1;
                            beep_key              <= 1'b1;
                        end
                    end else if (key_val == 4'hE) begin
                        beep_key <= 1'b1;
                        if (pwd_len > 3'd0) begin
                            pwd_len <= pwd_len - 3'd1;
                        end else begin
                            state <= S_IDLE; // 取消
                        end
                    end else if (key_val == 4'hF) begin
                        beep_key <= 1'b1;
                        if (pwd_len == 3'd6) begin
                            if (assembled_input == assembled_new) begin
                                // 两次输入完全一致，写入动态密码生效！
                                current_pwd <= assembled_input;
                                pwd_changed <= 1'b1;
                                beep_succ   <= 1'b1;
                                ms_timer    <= 12'd1500;
                                pwd_len     <= 3'd0;
                                state       <= S_OP_DONE;
                            end else begin
                                // 两次输入不符，提示错误并放弃
                                beep_err <= 1'b1;
                                ms_timer <= 12'd1500;
                                pwd_len  <= 3'd0;
                                state    <= S_ERROR;
                            end
                        end
                    end
                end
            end

            // --------------------------------------------------------------
            // 【Day 6 任务】B 键安全改密 - 输入当前旧密码验权
            // --------------------------------------------------------------
            S_CHG_AUTH: begin
                if (key_valid) begin
                    if (key_val <= 4'h9) begin
                        if (pwd_len < 3'd6) begin
                            input_digits[pwd_len] <= key_val;
                            pwd_len               <= pwd_len + 3'd1;
                            beep_key              <= 1'b1;
                        end
                    end else if (key_val == 4'hE) begin
                        beep_key <= 1'b1;
                        if (pwd_len > 3'd0) begin
                            pwd_len <= pwd_len - 3'd1;
                        end else begin
                            state <= S_IDLE; // 取消
                        end
                    end else if (key_val == 4'hF) begin
                        beep_key <= 1'b1;
                        if (pwd_len == 3'd6) begin
                            if (assembled_input == current_pwd) begin
                                // 旧密码核验成功，进入新密码录入阶段！
                                pwd_len       <= 3'd0;
                                op_timeout_ms <= 14'd15000;
                                state         <= S_CHG_NEW;
                            end else begin
                                // 旧密码错误，扣罚错误次数 (达到 3 次同样锁机)
                                if (err_count >= 2'd2) begin
                                    err_count      <= 2'd3;
                                    lock_countdown <= LOCK_TIMEOUT_SEC;
                                    sec_tick_cnt   <= 10'd0;
                                    beep_lock      <= 1'b1;
                                    pwd_len        <= 3'd0;
                                    state          <= S_LOCKED;
                                end else begin
                                    err_count <= err_count + 2'd1;
                                    beep_err  <= 1'b1;
                                    ms_timer  <= 12'd1500;
                                    pwd_len   <= 3'd0;
                                    state     <= S_ERROR;
                                end
                            end
                        end
                    end
                end
            end

            // --------------------------------------------------------------
            // 【Day 6 任务】B 键安全改密 - 输入 6 位新密码
            // --------------------------------------------------------------
            S_CHG_NEW: begin
                if (key_valid) begin
                    if (key_val <= 4'h9) begin
                        if (pwd_len < 3'd6) begin
                            input_digits[pwd_len] <= key_val;
                            pwd_len               <= pwd_len + 3'd1;
                            beep_key              <= 1'b1;
                        end
                    end else if (key_val == 4'hE) begin
                        beep_key <= 1'b1;
                        if (pwd_len > 3'd0) begin
                            pwd_len <= pwd_len - 3'd1;
                        end else begin
                            state <= S_IDLE;
                        end
                    end else if (key_val == 4'hF) begin
                        beep_key <= 1'b1;
                        if (pwd_len == 3'd6) begin
                            for (i = 0; i < 6; i = i + 1) begin
                                new_pwd_digits[i] <= input_digits[i];
                            end
                            pwd_len       <= 3'd0;
                            op_timeout_ms <= 14'd15000;
                            state         <= S_CHG_CFM;
                        end
                    end
                end
            end

            // --------------------------------------------------------------
            // 【Day 6 任务】B 键安全改密 - 再次确认新密码
            // --------------------------------------------------------------
            S_CHG_CFM: begin
                if (key_valid) begin
                    if (key_val <= 4'h9) begin
                        if (pwd_len < 3'd6) begin
                            input_digits[pwd_len] <= key_val;
                            pwd_len               <= pwd_len + 3'd1;
                            beep_key              <= 1'b1;
                        end
                    end else if (key_val == 4'hE) begin
                        beep_key <= 1'b1;
                        if (pwd_len > 3'd0) begin
                            pwd_len <= pwd_len - 3'd1;
                        end else begin
                            state <= S_IDLE;
                        end
                    end else if (key_val == 4'hF) begin
                        beep_key <= 1'b1;
                        if (pwd_len == 3'd6) begin
                            if (assembled_input == assembled_new) begin
                                // 两次输入一致，更新密码成功！
                                current_pwd <= assembled_input;
                                pwd_changed <= 1'b1;
                                beep_succ   <= 1'b1;
                                ms_timer    <= 12'd1500;
                                pwd_len     <= 3'd0;
                                state       <= S_OP_DONE;
                            end else begin
                                beep_err <= 1'b1;
                                ms_timer <= 12'd1500;
                                pwd_len  <= 3'd0;
                                state    <= S_ERROR;
                            end
                        end
                    end
                end
            end

            // --------------------------------------------------------------
            // 【Day 6 任务】设置/修改成功提示态 (保持 1.5 秒后回待机)
            // --------------------------------------------------------------
            S_OP_DONE: begin
                if (tick_1k) begin
                    if (ms_timer > 12'd0) begin
                        ms_timer <= ms_timer - 12'd1;
                    end else begin
                        state <= S_IDLE;
                    end
                end
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule

`endif
