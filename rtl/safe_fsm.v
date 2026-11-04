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
    input  wire        peep_hang,      // 视觉防窥挂起状态 (挂起下保留反挟持求救能力)
    input  wire        pwd_reset,      // 恢复码验证成功触发的密码复位脉冲 (恢复出厂 123456)
    input  wire        remote_auth_err,// 远程开锁挑战-应答认证失败脉冲 (计入错误次数并触发阶梯锁定)
    
    // 业务状态输出 (供 OLED、数码管、LED 驱动，扩充为 4 位)
    // 0:IDLE, 1:INPUT, 2:SUCCESS, 3:ERROR, 4:LOCKED, 5:SET_NEW, 6:SET_CFM, 7:CHG_AUTH, 8:CHG_NEW, 9:CHG_CFM, 10:OP_DONE
    output reg  [3:0]  state_code,     
    output reg  [4:0]  pwd_len,        // 当前输入的密码长度 (日常开锁 0~16, 录入/改密 0~6)
    output reg  [1:0]  err_count,      // 当前累计输错次数 (0~3)
    output reg  [8:0]  lock_countdown, // 阶梯锁定倒计时剩余秒数 (0~300)
    output reg         unlock_en,      // 开锁使能 (驱动开锁与成功指示)
    output reg         duress_alarm,   // 挟持静默告警使能 (预留给 PC 串口，粘滞锁存)
    output reg         duress_trig,    // 反挟持单拍触发脉冲 (替代粘滞电平导致的二次漏发)
    output reg         pwd_err_pulse,  // 真正密码比对失败单周期脉冲 (供 UART 专属上报 'E')
    output reg         lock_timeout_pulse, // 试错锁定结束单拍脉冲 (通知 PC 解锁 'T')
    output reg         pwd_changed,    // 密码成功更新单周期脉冲
    
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

reg [3:0]  state = S_IDLE;

// --------------------------------------------------------------------------
// 1.0 PRESENT (ISO/IEC 29192-2) 4-bit S-Box 与 24-bit 双轮硬件加盐密码混淆核 (P1)
//     消除密码明文驻留，11 路滑动窗口单周期全并行计算硬件密码摘要比对
// --------------------------------------------------------------------------
function [3:0] sbox4(input [3:0] x);
    begin
        case (x)
            4'h0: sbox4 = 4'hC; 4'h1: sbox4 = 4'h5; 4'h2: sbox4 = 4'h6; 4'h3: sbox4 = 4'hB;
            4'h4: sbox4 = 4'h9; 4'h5: sbox4 = 4'h0; 4'h6: sbox4 = 4'hA; 4'h7: sbox4 = 4'hD;
            4'h8: sbox4 = 4'h3; 4'h9: sbox4 = 4'hE; 4'hA: sbox4 = 4'hF; 4'hB: sbox4 = 4'h8;
            4'hC: sbox4 = 4'h4; 4'hD: sbox4 = 4'h7; 4'hE: sbox4 = 4'h1; 4'hF: sbox4 = 4'h2;
        endcase
    end
endfunction

function [23:0] pwd_cipher_hash(input [23:0] raw);
    reg [23:0] r1, r2;
    begin
        // 第一轮: PRESENT S-Box 非线性代换 + 硬件固定盐值异或 (0xA5C396)
        r1 = {sbox4(raw[23:20]), sbox4(raw[19:16]), sbox4(raw[15:12]),
              sbox4(raw[11:8]),  sbox4(raw[7:4]),   sbox4(raw[3:0])} ^ 24'hA5C396;
        // 第二轮: GF(2)^24 满秩循环移位线性扩散 + 次轮盐值混合 + 二次 S-Box 代换
        r2 = r1 ^ {r1[18:0], r1[23:19]} ^ {r1[10:0], r1[23:11]} ^ 24'h5A3C69;
        pwd_cipher_hash = {sbox4(r2[23:20]), sbox4(r2[19:16]), sbox4(r2[15:12]),
                           sbox4(r2[11:8]),  sbox4(r2[7:4]),   sbox4(r2[3:0])};
    end
endfunction

wire [23:0] default_pwd_hash = pwd_cipher_hash(DEFAULT_PWD);
wire [23:0] duress_pwd_hash  = pwd_cipher_hash(DURESS_PWD);

// 动态密码密文摘要寄存器 (仅上电 POR 初始化与恢复码重置，杜绝明文驻留且不受按键 RST 影响)
// 初始值为出厂默认密码 123456 经过 PRESENT S-Box + 2轮加盐混淆后的密文哈希摘要 (0xE038C9)
reg [23:0] current_pwd = 24'hE038C9;
reg        por_init_done = 1'b0;

// 阶梯锁定档位: 0: 1x(60s), 1: 2x(120s), 2: 5x(300s) (开锁成功复位为 0)
reg [1:0]  lock_tier = 2'd0;

initial begin
    state          = S_IDLE;
    state_code     = 4'd0;
    pwd_len        = 5'd0;
    err_count      = 2'd0;
    lock_countdown = 9'd0;
    unlock_en      = 1'b0;
    duress_alarm   = 1'b0;
    duress_trig    = 1'b0;
    pwd_err_pulse  = 1'b0;
    lock_timeout_pulse = 1'b0;
    pwd_changed    = 1'b0;
    beep_key       = 1'b0;
    beep_err       = 1'b0;
    beep_lock      = 1'b0;
    beep_succ      = 1'b0;
    current_pwd    = 24'hE038C9;
    por_init_done  = 1'b0;
    lock_tier      = 2'd0;
end

// 6 位输入数字暂存缓冲区 (每个 4-bit)
reg [3:0]  input_digits [0:5];

// 6 位二次确认对比暂存缓冲区 (用于 A/B 键确认新密码)
reg [3:0]  new_pwd_digits [0:5];

// 组装为 24 位总线并实时通过 PRESENT 密码学哈希核计算摘要
wire [23:0] assembled_input      = {
    input_digits[0], input_digits[1], input_digits[2],
    input_digits[3], input_digits[4], input_digits[5]
};
wire [23:0] assembled_input_hash = pwd_cipher_hash(assembled_input);

wire [23:0] assembled_new        = {
    new_pwd_digits[0], new_pwd_digits[1], new_pwd_digits[2],
    new_pwd_digits[3], new_pwd_digits[4], new_pwd_digits[5]
};
wire [23:0] assembled_new_hash   = pwd_cipher_hash(assembled_new);

// 毫秒级定时器计数器
reg [11:0] ms_timer = 12'd0;
reg [9:0]  sec_tick_cnt = 10'd0;  // 0~999 ms 用于锁定倒计时每秒减 1
reg [13:0] op_timeout_ms = 14'd0; // 15 秒无操作看门狗定时器 (0~15000ms)

// --------------------------------------------------------------------------
// 1.1 日常开锁 16 位虚位密码移位缓冲区 (Day 9) & 11 路并行硬件哈希滑窗核 (P1)
//     每敲一个数字整体左移 4 bit，最新数字进入 vbuf[3:0]，最多保留最近 16 位。
//     11 组 6 位滑动窗口在同一个时钟周期内各自经过 PRESENT 双轮混淆核并行比对摘要。
// --------------------------------------------------------------------------
reg [63:0] vbuf = 64'd0;

reg  [4:0]  lock_vlen = 5'd0; // S_LOCKED 期间用于反挟持检测的隐藏计数
wire [4:0]  eff_vlen = (state == S_LOCKED) ? lock_vlen : pwd_len;
wire [10:0] win_valid;
wire [10:0] win_hit_norm;
wire [10:0] win_hit_duress;

genvar g;
generate
    for (g = 0; g < 11; g = g + 1) begin : g_vwin
        wire [23:0] win_hash     = pwd_cipher_hash(vbuf[g*4 +: 24]);
        assign win_valid[g]      = (eff_vlen >= (g + 6));
        assign win_hit_norm[g]   = win_valid[g] && (win_hash == current_pwd);
        assign win_hit_duress[g] = win_valid[g] && (win_hash == duress_pwd_hash);
    end
endgenerate

wire match_norm   = |win_hit_norm;
wire match_duress = |win_hit_duress;

// A 键开荒录入门控: 只有密码摘要仍为出厂默认值时才允许免验旧密码直接设置
wire pwd_is_default = (current_pwd == default_pwd_hash);

// 改密黑名单比对: 严禁将日常主密码设置为反挟持密码 DURESS_PWD
wire is_duress_conflict = (assembled_input_hash == duress_pwd_hash);

// --------------------------------------------------------------------------
// 2. 状态映射输出 (与 seg_display / oled_driver 编码对齐)
//    采用同步时序与同步复位，彻底消除异步复位门控综合违例 (P0 修复)
// --------------------------------------------------------------------------
always @(posedge clk) begin
    if (!rst_n) begin
        state_code <= (state == S_LOCKED) ? 4'd4 : 4'd0;
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
// 3. 主状态机流转控制 (纯同步复位控制，合规支持按键复位防锁定逃逸与密码保持)
// --------------------------------------------------------------------------
integer i;

always @(posedge clk) begin
    if (!por_init_done) begin
        por_init_done <= 1'b1;
        current_pwd   <= default_pwd_hash;
        err_count     <= 2'd0;
        lock_tier     <= 2'd0;
    end

    if (!rst_n) begin
        // 漏洞 1.1 & P0 可综合性修复:
        // 采用同步复位判断，按键复位 (rst_n) 绝不冲刷 current_pwd、err_count、lock_tier 和 lock_countdown！
        // 若当前正处于锁定状态 (S_LOCKED)，保持锁定并继续倒计时，严防按复位键脱逃锁定！
        if (state == S_LOCKED) begin
            pwd_len            <= 5'd0;
            lock_vlen          <= 5'd0;
            vbuf               <= 64'd0;
            unlock_en          <= 1'b0;
            beep_key           <= 1'b0;
            beep_err           <= 1'b0;
            beep_lock          <= 1'b0;
            beep_succ          <= 1'b0;
            pwd_changed        <= 1'b0;
            duress_trig        <= 1'b0;
            pwd_err_pulse      <= 1'b0;
            lock_timeout_pulse <= 1'b0;
        end else begin
            state              <= S_IDLE;
            pwd_len            <= 5'd0;
            lock_vlen          <= 5'd0;
            vbuf               <= 64'd0;
            unlock_en          <= 1'b0;
            duress_alarm       <= 1'b0;
            duress_trig        <= 1'b0;
            pwd_err_pulse      <= 1'b0;
            lock_timeout_pulse <= 1'b0;
            pwd_changed        <= 1'b0;
            beep_key           <= 1'b0;
            beep_err           <= 1'b0;
            beep_lock          <= 1'b0;
            beep_succ          <= 1'b0;
            ms_timer           <= 12'd0;
            op_timeout_ms      <= 14'd0;
            for (i = 0; i < 6; i = i + 1) begin
                input_digits[i]   <= 4'h0;
                new_pwd_digits[i] <= 4'h0;
            end
        end
    end else begin
        // 默认清除单周期脉冲
        beep_key           <= 1'b0;
        beep_err           <= 1'b0;
        beep_lock          <= 1'b0;
        beep_succ          <= 1'b0;
        pwd_changed        <= 1'b0;
        duress_trig        <= 1'b0;
        pwd_err_pulse      <= 1'b0;
        lock_timeout_pulse <= 1'b0;

        // 恢复码验证成功时才将密码摘要重置回出厂默认值，并清空错误累计与锁定阶梯
        if (pwd_reset) begin
            current_pwd <= default_pwd_hash;
            err_count   <= 2'd0;
            lock_tier   <= 2'd0;
        end

        // 外部清除粘滞反挟持告警
        if (duress_clear) begin
            duress_alarm <= 1'b0;
        end

        // P0 安全加固: 远程挑战-应答认证失败或超时彻底清理所有中间状态，计入错误次数并触发阶梯锁定
        if (remote_auth_err && (state != S_LOCKED)) begin
            pwd_err_pulse <= 1'b1;
            pwd_len       <= 5'd0;
            vbuf          <= 64'd0;
            unlock_en     <= 1'b0;      // 发生远程认证失败立即拉低开锁使能，杜绝开锁逃逸
            op_timeout_ms <= 14'd0;     // 重置改密/录入看门狗
            for (i = 0; i < 6; i = i + 1) begin
                input_digits[i]   <= 4'h0;
                new_pwd_digits[i] <= 4'h0;
            end
            if (err_count >= 2'd2) begin
                err_count    <= 2'd3;
                sec_tick_cnt <= 10'd0;
                beep_lock    <= 1'b1;
                case (lock_tier)
                    2'd0: begin
                        lock_countdown <= LOCK_TIMEOUT_SEC[8:0];
                        lock_tier      <= 2'd1;
                    end
                    2'd1: begin
                        lock_countdown <= (LOCK_TIMEOUT_SEC * 9'd2);
                        lock_tier      <= 2'd2;
                    end
                    default: begin
                        lock_countdown <= (LOCK_TIMEOUT_SEC * 9'd5);
                        lock_tier      <= 2'd2;
                    end
                endcase
                state <= S_LOCKED;
            end else begin
                err_count <= err_count + 2'd1;
                beep_err  <= 1'b1;
                ms_timer  <= 12'd1500;
                state     <= S_ERROR;
            end
        end else begin

        // 瑕疵 2.1 修复:
        // S_INPUT, 录入与改密流程的 15 秒无操作看门狗计时
        if (state == S_INPUT || state == S_SET_NEW || state == S_SET_CFM ||
            state == S_CHG_AUTH || state == S_CHG_NEW || state == S_CHG_CFM) begin
            if (key_valid) begin
                op_timeout_ms <= 14'd15000; // 只要有任何按键按下，重置 15s 看门狗
            end else if (tick_1k) begin
                if (op_timeout_ms > 14'd0) begin
                    op_timeout_ms <= op_timeout_ms - 14'd1;
                end else begin
                    // 15 秒超时无操作，清空输入暂存，发出提示音，安全退回待机
                    pwd_len  <= 5'd0;
                    vbuf     <= 64'd0;
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
                lock_vlen <= 5'd0;
                ms_timer  <= 12'd0;
                
                if (key_valid) begin
                    if (key_val <= 4'h9) begin
                        // 敲击首位数字键，进入日常开锁输入态 (清空虚位缓冲，首位进入最低 nibble)
                        vbuf            <= {60'd0, key_val};
                        pwd_len         <= 5'd1;
                        beep_key        <= 1'b1;
                        op_timeout_ms   <= 14'd15000;
                        state           <= S_INPUT;
                    end else if (key_val == 4'hA && !peep_hang) begin
                        // 'A' 键: 新用户开荒录入通道 (直接输 6 位新密码)，防窥挂起时屏蔽
                        // 安全门控: 仅当密码仍为出厂默认值时可用；改过密码后只能走 B 键验旧改密
                        if (pwd_is_default) begin
                            beep_key      <= 1'b1;
                            pwd_len       <= 5'd0;
                            op_timeout_ms <= 14'd15000;
                            state         <= S_SET_NEW;
                        end else begin
                            // 瑕疵 2.7 修复: 待机态在密码已修改过时按 A 键，发出明确的错误警告音反馈
                            beep_err      <= 1'b1;
                        end
                    end else if (key_val == 4'hB && !peep_hang) begin
                        // 'B' 键: 老用户安全改密通道 (需先验旧密码)，防窥挂起时屏蔽
                        pwd_len       <= 5'd0;
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
            // 胁迫密码优先: 只要任一窗口出现胁迫密码，无条件放行并静默报警开锁
            // 防窥挂起时: 除非匹配到 match_duress，否则一律阻断开锁并提示错误
            // --------------------------------------------------------------
            S_CHECK: begin
                vbuf      <= 64'd0;   // 判决后立即清除缓冲区，密码不在寄存器中残留
                pwd_len   <= 5'd0;
                lock_vlen <= 5'd0;
                if (match_duress) begin
                    // 反挟持密码匹配成功！(无条件放行: 表面开门，底层静默粘滞告警 + 单拍脉冲)
                    err_count    <= 2'd0;
                    lock_tier    <= 2'd0; // 开锁成功，重置阶梯锁定档位
                    unlock_en    <= 1'b1;
                    duress_alarm <= 1'b1;
                    duress_trig  <= 1'b1;
                    beep_succ    <= 1'b1;
                    ms_timer     <= 12'd3000;
                    state        <= S_SUCCESS;
                end else if (match_norm && !peep_hang) begin
                    // 动态密码匹配成功！(仅在无防窥挂起时允许正常开锁)
                    err_count <= 2'd0;
                    lock_tier <= 2'd0; // 开锁成功，重置阶梯锁定档位
                    unlock_en <= 1'b1;
                    beep_succ <= 1'b1;
                    ms_timer  <= 12'd3000; // 成功开锁保持 3 秒
                    state     <= S_SUCCESS;
                end else if (peep_hang) begin
                    // 防窥挂起期间非反挟持密码尝试开锁: 阻断开锁并报警提示错误
                    beep_err  <= 1'b1;
                    ms_timer  <= 12'd1500;
                    state     <= S_ERROR;
                end else begin
                    // 瑕疵 2.3 修复: 仅在真正的密码比对失败时发出 pwd_err_pulse 单周期脉冲给 PC
                    pwd_err_pulse <= 1'b1;
                    if (err_count >= 2'd2) begin
                        // 连续累计满 3 次输错 -> 触发阶梯锁定！
                        // 漏洞 1.5 修复: 阶梯递增锁定时长 (第1次 1x=60s, 第2次 2x=120s, 第3次及以后 5x=300s)
                        err_count    <= 2'd3;
                        sec_tick_cnt <= 10'd0;
                        beep_lock    <= 1'b1;
                        case (lock_tier)
                            2'd0: begin
                                lock_countdown <= LOCK_TIMEOUT_SEC[8:0];
                                lock_tier      <= 2'd1;
                            end
                            2'd1: begin
                                lock_countdown <= (LOCK_TIMEOUT_SEC * 9'd2);
                                lock_tier      <= 2'd2;
                            end
                            default: begin
                                lock_countdown <= (LOCK_TIMEOUT_SEC * 9'd5);
                                lock_tier      <= 2'd2;
                            end
                        endcase
                        state <= S_LOCKED;
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
                        pwd_len <= 5'd0;
                        vbuf    <= 64'd0;
                        state   <= S_IDLE;
                    end
                end
            end

            // --------------------------------------------------------------
            // 连续输错 3 次系统锁定态 (锁定 60s，普通按键屏蔽，支持反挟持紧急求救开锁)
            // --------------------------------------------------------------
            S_LOCKED: begin
                unlock_en <= 1'b0;
                pwd_len   <= 5'd0;
                
                if (key_valid) begin
                    if (key_val <= 4'h9) begin
                        vbuf <= {vbuf[59:0], key_val};
                        if (lock_vlen < 5'd16) begin
                            lock_vlen <= lock_vlen + 5'd1;
                        end
                    end else if (key_val == 4'hE) begin
                        vbuf <= {4'h0, vbuf[63:4]};
                        if (lock_vlen > 5'd0) begin
                            lock_vlen <= lock_vlen - 5'd1;
                        end
                    end else if (key_val == 4'hF) begin
                        vbuf      <= 64'd0;
                        lock_vlen <= 5'd0;
                        if (lock_vlen >= 5'd6 && match_duress) begin
                            // 锁定期间输入反挟持密码求救: 立即解除锁定、开门并触发静默报警！
                            lock_countdown <= 9'd0;
                            err_count      <= 2'd0;
                            lock_tier      <= 2'd0;
                            unlock_en      <= 1'b1;
                            duress_alarm   <= 1'b1;
                            duress_trig    <= 1'b1;
                            beep_succ      <= 1'b1;
                            ms_timer       <= 12'd3000;
                            state          <= S_SUCCESS;
                        end
                    end
                end else if (tick_1k) begin
                    if (sec_tick_cnt >= 10'd999) begin
                        sec_tick_cnt <= 10'd0;
                        if (lock_countdown > 9'd1) begin
                            lock_countdown <= lock_countdown - 9'd1;
                        end else begin
                            // 锁定倒计时结束，恢复系统并发送超时解锁脉冲 'T'
                            lock_countdown     <= 9'd0;
                            err_count          <= 2'd0;
                            vbuf               <= 64'd0;
                            lock_vlen          <= 5'd0;
                            lock_timeout_pulse <= 1'b1;
                            state              <= S_IDLE;
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
                        // '#' 键: 满 6 位后暂存新密码，推进入二次确认阶段 (黑名单检查反挟持冲突)
                        beep_key <= 1'b1;
                        if (pwd_len == 3'd6) begin
                            if (is_duress_conflict) begin
                                beep_err <= 1'b1;
                                ms_timer <= 12'd1500;
                                pwd_len  <= 3'd0;
                                state    <= S_ERROR;
                            end else begin
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
                            if ((assembled_input_hash == assembled_new_hash) && !is_duress_conflict) begin
                                // 两次输入完全一致且非反挟持黑名单密码，写入动态密码密文摘要生效！
                                current_pwd <= assembled_input_hash;
                                err_count   <= 2'd0;
                                lock_tier   <= 2'd0;
                                pwd_changed <= 1'b1;
                                beep_succ   <= 1'b1;
                                ms_timer    <= 12'd1500;
                                pwd_len     <= 3'd0;
                                state       <= S_OP_DONE;
                            end else begin
                                // 两次输入不符或命中反挟持黑名单，提示错误并放弃
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
                            if (assembled_input_hash == current_pwd) begin
                                // 旧密码摘要核验成功，进入新密码录入阶段！
                                pwd_len       <= 3'd0;
                                op_timeout_ms <= 14'd15000;
                                state         <= S_CHG_NEW;
                            end else begin
                                // 旧密码错误，扣罚错误次数 (达到 3 次同样进入阶梯锁定)
                                pwd_err_pulse <= 1'b1;
                                if (err_count >= 2'd2) begin
                                    err_count    <= 2'd3;
                                    sec_tick_cnt <= 10'd0;
                                    beep_lock    <= 1'b1;
                                    pwd_len      <= 5'd0;
                                    case (lock_tier)
                                        2'd0: begin
                                            lock_countdown <= LOCK_TIMEOUT_SEC[8:0];
                                            lock_tier      <= 2'd1;
                                        end
                                        2'd1: begin
                                            lock_countdown <= (LOCK_TIMEOUT_SEC * 9'd2);
                                            lock_tier      <= 2'd2;
                                        end
                                        default: begin
                                            lock_countdown <= (LOCK_TIMEOUT_SEC * 9'd5);
                                            lock_tier      <= 2'd2;
                                        end
                                    endcase
                                    state <= S_LOCKED;
                                end else begin
                                    err_count <= err_count + 2'd1;
                                    beep_err  <= 1'b1;
                                    ms_timer  <= 12'd1500;
                                    pwd_len   <= 5'd0;
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
                            if (is_duress_conflict) begin
                                beep_err <= 1'b1;
                                ms_timer <= 12'd1500;
                                pwd_len  <= 3'd0;
                                state    <= S_ERROR;
                            end else begin
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
                            if ((assembled_input_hash == assembled_new_hash) && !is_duress_conflict) begin
                                // 两次输入一致且非反挟持黑名单密码，更新密码密文摘要成功！
                                current_pwd <= assembled_input_hash;
                                err_count   <= 2'd0;
                                lock_tier   <= 2'd0;
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
end

endmodule

`endif
