// ==============================================================================
// 工程名称: 基于 Edge AI 视觉防窥与 FPGA 硬件安全的异构智能保险箱
// 模块名称: oled_driver (0.96寸 I2C OLED SSD1306 控制器与中文交互驱动)
// 阶段任务: Day 3~5 - I2C主机控制器(SCL 200kHz)、开漏驱动改造、消除initial块、防死锁握手
// 硬件平台: 安路 (Anlogic) EG4S20BG256 (OLED_SCL: J14, OLED_SDA: H13)
// ==============================================================================

`timescale 1ns / 1ps

`ifndef __OLED_DRIVER_V__
`define __OLED_DRIVER_V__

module oled_driver #(
    parameter CLK_FREQ = 50_000_000 // 50MHz 主频
)(
    input  wire        clk,            // 50MHz 系统主时钟
    input  wire        rst_n,          // 异步复位 (低有效)
    
    // 业务状态输入 (来自主状态机, 扩充为 4 位)
    input  wire [3:0]  state_code,     // 0:IDLE, 1:INPUT, 2:SUCCESS, 3:ERROR, 4:LOCKED, 5~10:SET/CHG
    input  wire [2:0]  pwd_len,        // 已输入密码位数 (0~6)
    input  wire [1:0]  err_count,      // 累计输错次数 (0~3)
    input  wire [6:0]  lock_countdown, // 锁定倒计时剩余秒数 (0~60)
    
    // I2C 物理引脚 (P0-B: 改为开漏三态双向口，避免从机ACK对驱短路)
    output reg         oled_scl,       // I2C 串行时钟输出 (引脚: J14)
    inout  wire        oled_sda        // I2C 串行数据开漏双向 (引脚: H13)
);

// --------------------------------------------------------------------------
// 1. I2C 底层时钟分频 (50MHz / 250 = 200kHz SCL, 半周期 125 拍 @50MHz)
// --------------------------------------------------------------------------
localparam SCL_DIV = 125; // 半周期 125 个时钟 (2.5us -> SCL = 200kHz)

reg [7:0] clk_cnt;
reg       scl_tick; // 每 2.5us 产生一个节拍，驱动 I2C 状态机半步

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        clk_cnt  <= 8'd0;
        scl_tick <= 1'b0;
    end else if (clk_cnt >= (SCL_DIV - 1)) begin
        clk_cnt  <= 8'd0;
        scl_tick <= 1'b1;
    end else begin
        clk_cnt  <= clk_cnt + 8'd1;
        scl_tick <= 1'b0;
    end
end

// --------------------------------------------------------------------------
// 2. I2C 开漏 (Open-Drain) 驱动逻辑 (P0-B)
// --------------------------------------------------------------------------
reg sda_drive_low; // 1: 主动拉低(0), 0: 释放总线为高阻(由内部/板载上拉拉高)
assign oled_sda = sda_drive_low ? 1'b0 : 1'bz;

// --------------------------------------------------------------------------
// 3. I2C 单包发送状态机 (支持 Start, 0x78从机地址, Control/Data字节, Stop)
// --------------------------------------------------------------------------
reg        i2c_req;      // 发起一次传输请求
reg        i2c_is_cmd;   // 1: 控制命令 (Control=0x00), 0: 显存数据 (Control=0x40)
reg  [7:0] i2c_data;     // 要发送的有效字节
reg        i2c_send_stop;// 发送完成后是否附带 STOP 条件
wire       i2c_busy;     // I2C 正在忙
reg        i2c_done;     // 本字节传输完成单脉冲

localparam I2C_IDLE       = 5'd0;
localparam I2C_START_1    = 5'd1;
localparam I2C_START_2    = 5'd2;
localparam I2C_ADDR_BYTE  = 5'd3;
localparam I2C_ADDR_ACK   = 5'd4;
localparam I2C_CTRL_BYTE  = 5'd5;
localparam I2C_CTRL_ACK   = 5'd6;
localparam I2C_DATA_BYTE  = 5'd7;
localparam I2C_DATA_ACK   = 5'd8;
localparam I2C_STOP_1     = 5'd9;
localparam I2C_STOP_2     = 5'd10;
localparam I2C_STOP_3     = 5'd11;

reg [4:0] i2c_state;
reg [3:0] bit_cnt;
reg [7:0] shift_reg;
reg       scl_phase; // 0: SCL=0 (数据建立), 1: SCL=1 (时钟采样)

assign i2c_busy = (i2c_state != I2C_IDLE);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        i2c_state     <= I2C_IDLE;
        oled_scl      <= 1'b1;
        sda_drive_low <= 1'b0; // 释放
        bit_cnt       <= 4'd0;
        shift_reg     <= 8'd0;
        scl_phase     <= 1'b0;
        i2c_done      <= 1'b0;
    end else begin
        i2c_done <= 1'b0;
        
        if (scl_tick) begin
            case (i2c_state)
                I2C_IDLE: begin
                    oled_scl      <= 1'b1;
                    sda_drive_low <= 1'b0; // 释放
                    if (i2c_req) begin
                        i2c_state <= I2C_START_1;
                    end
                end

                // 发送 START 条件: SCL=1 时 SDA 从 1 拉低为 0
                I2C_START_1: begin
                    oled_scl      <= 1'b1;
                    sda_drive_low <= 1'b1; // 主动拉低 SDA
                    i2c_state     <= I2C_START_2;
                end
                
                I2C_START_2: begin
                    oled_scl      <= 1'b0; // 钳住 SCL，准备发从机地址 0x78
                    shift_reg     <= 8'h78;
                    bit_cnt       <= 4'd0;
                    scl_phase     <= 1'b0;
                    i2c_state     <= I2C_ADDR_BYTE;
                end

                // 发送从机地址 0x78 (8位)
                I2C_ADDR_BYTE: begin
                    if (!scl_phase) begin
                        oled_scl      <= 1'b0;
                        sda_drive_low <= ~shift_reg[7];
                        scl_phase     <= 1'b1;
                    end else begin
                        oled_scl  <= 1'b1;
                        scl_phase <= 1'b0;
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        if (bit_cnt == 4'd7) begin
                            i2c_state <= I2C_ADDR_ACK;
                        end else begin
                            bit_cnt <= bit_cnt + 4'd1;
                        end
                    end
                end

                // 从机应答 ACK 周期
                I2C_ADDR_ACK: begin
                    if (!scl_phase) begin
                        oled_scl      <= 1'b0;
                        sda_drive_low <= 1'b0; // 释放 SDA 给从机拉低应答
                        scl_phase     <= 1'b1;
                    end else begin
                        oled_scl  <= 1'b1;
                        scl_phase <= 1'b0;
                        shift_reg <= i2c_is_cmd ? 8'h00 : 8'h40;
                        bit_cnt   <= 4'd0;
                        i2c_state <= I2C_CTRL_BYTE;
                    end
                end

                // 发送控制字节 (0x00 命令, 0x40 数据)
                I2C_CTRL_BYTE: begin
                    if (!scl_phase) begin
                        oled_scl      <= 1'b0;
                        sda_drive_low <= ~shift_reg[7];
                        scl_phase     <= 1'b1;
                    end else begin
                        oled_scl  <= 1'b1;
                        scl_phase <= 1'b0;
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        if (bit_cnt == 4'd7) begin
                            i2c_state <= I2C_CTRL_ACK;
                        end else begin
                            bit_cnt <= bit_cnt + 4'd1;
                        end
                    end
                end

                I2C_CTRL_ACK: begin
                    if (!scl_phase) begin
                        oled_scl      <= 1'b0;
                        sda_drive_low <= 1'b0; // 释放 SDA
                        scl_phase     <= 1'b1;
                    end else begin
                        oled_scl  <= 1'b1;
                        scl_phase <= 1'b0;
                        shift_reg <= i2c_data; // 准备发送真正的数据/命令
                        bit_cnt   <= 4'd0;
                        i2c_state <= I2C_DATA_BYTE;
                    end
                end

                // 发送数据 / 命令有效字节
                I2C_DATA_BYTE: begin
                    if (!scl_phase) begin
                        oled_scl      <= 1'b0;
                        sda_drive_low <= ~shift_reg[7];
                        scl_phase     <= 1'b1;
                    end else begin
                        oled_scl  <= 1'b1;
                        scl_phase <= 1'b0;
                        shift_reg <= {shift_reg[6:0], 1'b0};
                        if (bit_cnt == 4'd7) begin
                            i2c_state <= I2C_DATA_ACK;
                        end else begin
                            bit_cnt <= bit_cnt + 4'd1;
                        end
                    end
                end

                I2C_DATA_ACK: begin
                    if (!scl_phase) begin
                        oled_scl      <= 1'b0;
                        sda_drive_low <= 1'b0; // 释放 SDA
                        scl_phase     <= 1'b1;
                    end else begin
                        oled_scl  <= 1'b1;
                        scl_phase <= 1'b0;
                        if (i2c_send_stop) begin
                            i2c_state <= I2C_STOP_1;
                        end else begin
                            i2c_done  <= 1'b1;
                            i2c_state <= I2C_IDLE;
                        end
                    end
                end

                // 发送 STOP 条件: SCL=1 时 SDA 从 0 拉高为 1
                I2C_STOP_1: begin
                    oled_scl      <= 1'b0;
                    sda_drive_low <= 1'b1; // 拉低
                    i2c_state     <= I2C_STOP_2;
                end
                
                I2C_STOP_2: begin
                    oled_scl      <= 1'b1;
                    sda_drive_low <= 1'b1;
                    i2c_state     <= I2C_STOP_3;
                end
                
                I2C_STOP_3: begin
                    oled_scl      <= 1'b1;
                    sda_drive_low <= 1'b0; // 释放为高阻拉高，形成上升沿 STOP
                    i2c_done      <= 1'b1;
                    i2c_state     <= I2C_IDLE;
                end

                default: i2c_state <= I2C_IDLE;
            endcase
        end
    end
end

// --------------------------------------------------------------------------
// 4. 字模 ROM 例化与动态内容生成
// --------------------------------------------------------------------------
reg  [5:0] font_cn_code;
reg  [4:0] font_cn_byte;
wire [7:0] font_cn_pixel;

reg  [4:0] font_asc_code;
reg  [3:0] font_asc_byte;
wire [7:0] font_asc_pixel;

oled_font u_oled_font(
    .cn_code   (font_cn_code),
    .cn_byte   (font_cn_byte),
    .cn_pixel  (font_cn_pixel),
    .asc_code  (font_asc_code),
    .asc_byte  (font_asc_byte),
    .asc_pixel (font_asc_pixel)
);

// --------------------------------------------------------------------------
// 5. 显示内容渲染逻辑 (128x64 = 8 Pages x 128 Cols)
// --------------------------------------------------------------------------
reg [2:0] current_page; // 0 ~ 7
reg [6:0] current_col;  // 0 ~ 127
reg [7:0] pixel_out;

// 倒计时十位与个位 (P2-P: 宽位中间变量清晰语法)
wire [3:0] lock_tens = (lock_countdown >= 7'd60) ? 4'd6 :
                       (lock_countdown >= 7'd50) ? 4'd5 :
                       (lock_countdown >= 7'd40) ? 4'd4 :
                       (lock_countdown >= 7'd30) ? 4'd3 :
                       (lock_countdown >= 7'd20) ? 4'd2 :
                       (lock_countdown >= 7'd10) ? 4'd1 : 4'd0;

wire [6:0] lock_tens_x10 = {lock_tens, 3'b000} + {2'b00, lock_tens, 1'b0}; // 8x + 2x = 10x (完全消除DSP)
wire [6:0] lock_ones_7b  = lock_countdown - lock_tens_x10;
wire [3:0] lock_ones     = lock_ones_7b[3:0];
wire [3:0] remain_retries = (err_count <= 2'd2) ? (4'd3 - {2'd0, err_count}) : 4'd0;

// 行与字模索引译码
always @(*) begin
    font_cn_code  = 6'd0;
    font_cn_byte  = 5'd0;
    font_asc_code = 5'd16; // 空格
    font_asc_byte = 4'd0;
    pixel_out     = 8'h00;

    case (current_page)
        // ------------------------------------------------------------------
        // Row 0 (Page 0~1): 标题栏居中显示
        // ------------------------------------------------------------------
        3'd0, 3'd1: begin
            font_cn_byte = {current_page[0], current_col[3:0]};
            case (state_code)
                4'd5: begin // S_SET_NEW: "新用户录入" (24~103)
                    if (current_col >= 7'd24 && current_col < 7'd104) begin
                        case ((current_col - 7'd24) >> 4)
                            0: font_cn_code = 6'd30; // 新
                            1: font_cn_code = 6'd3;  // 用
                            2: font_cn_code = 6'd35; // 户
                            3: font_cn_code = 6'd36; // 录
                            4: font_cn_code = 6'd6;  // 入
                            default: font_cn_code = 6'd30;
                        endcase
                        pixel_out = font_cn_pixel;
                    end
                end

                4'd6, 4'd9: begin // S_SET_CFM / S_CHG_CFM: "请再次确认" (24~103)
                    if (current_col >= 7'd24 && current_col < 7'd104) begin
                        case ((current_col - 7'd24) >> 4)
                            0: font_cn_code = 6'd4;  // 请
                            1: font_cn_code = 6'd37; // 再
                            2: font_cn_code = 6'd25; // 次
                            3: font_cn_code = 6'd26; // 确
                            4: font_cn_code = 6'd27; // 认
                            default: font_cn_code = 6'd4;
                        endcase
                        pixel_out = font_cn_pixel;
                    end
                end

                4'd7: begin // S_CHG_AUTH: "修改密码" (32~95)
                    if (current_col >= 7'd32 && current_col < 7'd96) begin
                        case (current_col[5:4])
                            2'b10: font_cn_code = 6'd40; // 修
                            2'b11: font_cn_code = 6'd32; // 改
                            2'b00: font_cn_code = 6'd7;  // 密
                            2'b01: font_cn_code = 6'd8;  // 码
                        endcase
                        pixel_out = font_cn_pixel;
                    end
                end

                4'd8: begin // S_CHG_NEW: "输入新密码" (24~103)
                    if (current_col >= 7'd24 && current_col < 7'd104) begin
                        case ((current_col - 7'd24) >> 4)
                            0: font_cn_code = 6'd5;  // 输
                            1: font_cn_code = 6'd6;  // 入
                            2: font_cn_code = 6'd30; // 新
                            3: font_cn_code = 6'd7;  // 密
                            4: font_cn_code = 6'd8;  // 码
                            default: font_cn_code = 6'd5;
                        endcase
                        pixel_out = font_cn_pixel;
                    end
                end

                4'd10: begin // S_OP_DONE: "设置成功" (32~95)
                    if (current_col >= 7'd32 && current_col < 7'd96) begin
                        case (current_col[5:4])
                            2'b10: font_cn_code = 6'd33; // 设
                            2'b11: font_cn_code = 6'd34; // 置
                            2'b00: font_cn_code = 6'd11; // 成
                            2'b01: font_cn_code = 6'd12; // 功
                        endcase
                        pixel_out = font_cn_pixel;
                    end
                end

                default: begin // 常规状态: "欢迎使用" (32~95)
                    if (current_col >= 7'd32 && current_col < 7'd96) begin
                        case (current_col[5:4])
                            2'b10: font_cn_code = 6'd0; // 欢
                            2'b11: font_cn_code = 6'd1; // 迎
                            2'b00: font_cn_code = 6'd2; // 使
                            2'b01: font_cn_code = 6'd3; // 用
                        endcase
                        pixel_out = font_cn_pixel;
                    end
                end
            endcase
        end

        // ------------------------------------------------------------------
        // Row 1 (Page 2~3): 状态提示行
        // ------------------------------------------------------------------
        3'd2, 3'd3: begin
            font_cn_byte = {current_page[0], current_col[3:0]};
            case (state_code)
                4'd2: begin // 成功: "开锁成功" (32~95)
                    if (current_col >= 7'd32 && current_col < 7'd96) begin
                        case (current_col[5:4])
                            2'b10: font_cn_code = 6'd9;  // 开
                            2'b11: font_cn_code = 6'd10; // 锁
                            2'b00: font_cn_code = 6'd11; // 成
                            2'b01: font_cn_code = 6'd12; // 功
                        endcase
                        pixel_out = font_cn_pixel;
                    end
                end

                4'd3: begin // 错误: "密码错误" (32~95)
                    if (current_col >= 7'd32 && current_col < 7'd96) begin
                        case (current_col[5:4])
                            2'b10: font_cn_code = 6'd7;  // 密
                            2'b11: font_cn_code = 6'd8;  // 码
                            2'b00: font_cn_code = 6'd13; // 错
                            2'b01: font_cn_code = 6'd14; // 误
                        endcase
                        pixel_out = font_cn_pixel;
                    end
                end

                4'd4: begin // 锁定: "系统已锁定" (24~103)
                    if (current_col >= 7'd24 && current_col < 7'd104) begin
                        case ((current_col - 7'd24) >> 4)
                            0: font_cn_code = 6'd15; // 系
                            1: font_cn_code = 6'd16; // 统
                            2: font_cn_code = 6'd17; // 已
                            3: font_cn_code = 6'd10; // 锁
                            4: font_cn_code = 6'd18; // 定
                            default: font_cn_code = 6'd15;
                        endcase
                        pixel_out = font_cn_pixel;
                    end
                end

                4'd5, 4'd8: begin // S_SET_NEW / S_CHG_NEW: "输6位新密码" -> 输 入 新 密 码 (24~103)
                    if (current_col >= 7'd24 && current_col < 7'd104) begin
                        case ((current_col - 7'd24) >> 4)
                            0: font_cn_code = 6'd5;  // 输
                            1: font_cn_code = 6'd6;  // 入
                            2: font_cn_code = 6'd30; // 新
                            3: font_cn_code = 6'd7;  // 密
                            4: font_cn_code = 6'd8;  // 码
                            default: font_cn_code = 6'd5;
                        endcase
                        pixel_out = font_cn_pixel;
                    end
                end

                4'd6, 4'd9: begin // S_SET_CFM / S_CHG_CFM: "重复输入新密" (24~103)
                    if (current_col >= 7'd24 && current_col < 7'd104) begin
                        case ((current_col - 7'd24) >> 4)
                            0: font_cn_code = 6'd38; // 重
                            1: font_cn_code = 6'd39; // 复
                            2: font_cn_code = 6'd5;  // 输
                            3: font_cn_code = 6'd6;  // 入
                            4: font_cn_code = 6'd30; // 新
                            default: font_cn_code = 6'd38;
                        endcase
                        pixel_out = font_cn_pixel;
                    end
                end

                4'd7: begin // S_CHG_AUTH: "输当前旧密码" (24~103)
                    if (current_col >= 7'd24 && current_col < 7'd104) begin
                        case ((current_col - 7'd24) >> 4)
                            0: font_cn_code = 6'd41; // 当
                            1: font_cn_code = 6'd42; // 前
                            2: font_cn_code = 6'd31; // 旧
                            3: font_cn_code = 6'd7;  // 密
                            4: font_cn_code = 6'd8;  // 码
                            default: font_cn_code = 6'd41;
                        endcase
                        pixel_out = font_cn_pixel;
                    end
                end

                4'd10: begin // S_OP_DONE: "密码已更新" (24~103)
                    if (current_col >= 7'd24 && current_col < 7'd104) begin
                        case ((current_col - 7'd24) >> 4)
                            0: font_cn_code = 6'd7;  // 密
                            1: font_cn_code = 6'd8;  // 码
                            2: font_cn_code = 6'd17; // 已
                            3: font_cn_code = 6'd43; // 更
                            4: font_cn_code = 6'd30; // 新
                            default: font_cn_code = 6'd7;
                        endcase
                        pixel_out = font_cn_pixel;
                    end
                end

                default: begin // 待机/输入态: "请输入密码" (24~103)
                    if (current_col >= 7'd24 && current_col < 7'd104) begin
                        case ((current_col - 7'd24) >> 4)
                            0: font_cn_code = 6'd4; // 请
                            1: font_cn_code = 6'd5; // 输
                            2: font_cn_code = 6'd6; // 入
                            3: font_cn_code = 6'd7; // 密
                            4: font_cn_code = 6'd8; // 码
                            default: font_cn_code = 6'd4;
                        endcase
                        pixel_out = font_cn_pixel;
                    end
                end
            endcase
        end

        // ------------------------------------------------------------------
        // Row 2 (Page 4~5): 动态交互数据行
        // 锁定态: "倒计时: XX 秒"
        // 其他态: 居中显示 6 位掩码 "[ * * * - - - ]"
        // ------------------------------------------------------------------
        3'd4, 3'd5: begin
            font_cn_byte  = {current_page[0], current_col[3:0]};
            font_asc_byte = {current_page[0], current_col[2:0]};

            if (state_code == 4'd4) begin
                if (current_col >= 7'd16 && current_col < 7'd48) begin
                    case ((current_col - 7'd16) >> 4)
                        0: font_cn_code = 6'd19; // 倒
                        1: font_cn_code = 6'd20; // 计
                    endcase
                    pixel_out = font_cn_pixel;
                end else if (current_col >= 7'd48 && current_col < 7'd56) begin
                    font_asc_code = 5'd10; // ':'
                    pixel_out     = font_asc_pixel;
                end else if (current_col >= 7'd56 && current_col < 7'd64) begin
                    font_asc_code = {1'b0, lock_tens};
                    pixel_out     = font_asc_pixel;
                end else if (current_col >= 7'd64 && current_col < 7'd72) begin
                    font_asc_code = {1'b0, lock_ones};
                    pixel_out     = font_asc_pixel;
                end else if (current_col >= 7'd72 && current_col < 7'd88) begin
                    font_cn_code = 6'd22; // 秒
                    pixel_out    = font_cn_pixel;
                end
            end else begin
                // 居中显示 8 个 8x16 字符: [ 6位掩码 ]
                if (current_col >= 7'd32 && current_col < 7'd96) begin
                    case ((current_col - 7'd32) >> 3)
                        0: font_asc_code = 5'd12; // '['
                        1: font_asc_code = (pwd_len >= 3'd1) ? 5'd14 : 5'd11; // '*' 或 '-'
                        2: font_asc_code = (pwd_len >= 3'd2) ? 5'd14 : 5'd11;
                        3: font_asc_code = (pwd_len >= 3'd3) ? 5'd14 : 5'd11;
                        4: font_asc_code = (pwd_len >= 3'd4) ? 5'd14 : 5'd11;
                        5: font_asc_code = (pwd_len >= 3'd5) ? 5'd14 : 5'd11;
                        6: font_asc_code = (pwd_len >= 3'd6) ? 5'd14 : 5'd11;
                        7: font_asc_code = 5'd13; // ']'
                        default: font_asc_code = 5'd16;
                    endcase
                    pixel_out = font_asc_pixel;
                end
            end
        end

        // ------------------------------------------------------------------
        // Row 3 (Page 6~7): 底部提示行
        // ------------------------------------------------------------------
        3'd6, 3'd7: begin
            font_cn_byte  = {current_page[0], current_col[3:0]};
            font_asc_byte = {current_page[0], current_col[2:0]};

            if (state_code == 4'd5 || state_code == 4'd6 ||
                state_code == 4'd7 || state_code == 4'd8 || state_code == 4'd9) begin
                // 录入/改密流程底部提示: "# 确认   * 取消"
                if (current_col >= 7'd16 && current_col < 7'd24) begin
                    font_asc_code = 5'd15; // '#'
                    pixel_out     = font_asc_pixel;
                end else if (current_col >= 7'd24 && current_col < 7'd56) begin
                    case ((current_col - 7'd24) >> 4)
                        0: font_cn_code = 6'd26; // 确
                        1: font_cn_code = 6'd27; // 认
                    endcase
                    pixel_out = font_cn_pixel;
                end else if (current_col >= 7'd72 && current_col < 7'd80) begin
                    font_asc_code = 5'd14; // '*'
                    pixel_out     = font_asc_pixel;
                end else if (current_col >= 7'd80 && current_col < 7'd112) begin
                    case ((current_col - 7'd80) >> 4)
                        0: font_cn_code = 6'd28; // 清
                        1: font_cn_code = 6'd29; // 除
                    endcase
                    pixel_out = font_cn_pixel;
                end
            end else if (state_code == 4'd2) begin
                // 开锁成功提示: "门锁已开启" (24~103)
                if (current_col >= 7'd24 && current_col < 7'd104) begin
                    case ((current_col - 7'd24) >> 4)
                        0: font_cn_code = 6'd44; // 门
                        1: font_cn_code = 6'd10; // 锁
                        2: font_cn_code = 6'd17; // 已
                        3: font_cn_code = 6'd9;  // 开
                        4: font_cn_code = 6'd12; // 功
                        default: font_cn_code = 6'd44;
                    endcase
                    pixel_out = font_cn_pixel;
                end
            end else if (state_code == 4'd4) begin
                // 锁定提示: "键盘已锁定" (24~103)
                if (current_col >= 7'd24 && current_col < 7'd104) begin
                    case ((current_col - 7'd24) >> 4)
                        0: font_cn_code = 6'd45; // 键
                        1: font_cn_code = 6'd46; // 盘
                        2: font_cn_code = 6'd17; // 已
                        3: font_cn_code = 6'd10; // 锁
                        4: font_cn_code = 6'd18; // 定
                        default: font_cn_code = 6'd45;
                    endcase
                    pixel_out = font_cn_pixel;
                end
            end else begin
                // 待机与密码输入: "剩余: X 次"
                if (current_col >= 7'd32 && current_col < 7'd64) begin
                    case ((current_col - 7'd32) >> 4)
                        0: font_cn_code = 6'd23; // 剩
                        1: font_cn_code = 6'd24; // 余
                    endcase
                    pixel_out = font_cn_pixel;
                end else if (current_col >= 7'd64 && current_col < 7'd72) begin
                    font_asc_code = 5'd10; // ':'
                    pixel_out     = font_asc_pixel;
                end else if (current_col >= 7'd72 && current_col < 7'd80) begin
                    font_asc_code = {1'b0, remain_retries};
                    pixel_out     = font_asc_pixel;
                end else if (current_col >= 7'd80 && current_col < 7'd96) begin
                    font_cn_code = 6'd25; // 次
                    pixel_out    = font_cn_pixel;
                end
            end
        end

        default: pixel_out = 8'h00;
    endcase
end

// --------------------------------------------------------------------------
// 6. OLED 初始化命令序列查找函数 (P0-A: 纯组合 case，彻底消灭 HDL-5007 警告)
// --------------------------------------------------------------------------
function [7:0] oled_init_cmd(input [4:0] idx);
    case (idx)
        5'd0 : oled_init_cmd = 8'hAE; // 关闭显示
        5'd1 : oled_init_cmd = 8'h00; // 列低4位
        5'd2 : oled_init_cmd = 8'h10; // 列高4位
        5'd3 : oled_init_cmd = 8'h40; // 起始行
        5'd4 : oled_init_cmd = 8'hB0; // 起始页
        5'd5 : oled_init_cmd = 8'h81; // 对比度控制
        5'd6 : oled_init_cmd = 8'hCF;
        5'd7 : oled_init_cmd = 8'hA1; // 段重映射 0~127
        5'd8 : oled_init_cmd = 8'hA6; // 正常显示
        5'd9 : oled_init_cmd = 8'hA8; // 多路复用比
        5'd10: oled_init_cmd = 8'h3F; // 64 MUX
        5'd11: oled_init_cmd = 8'hC8; // COM 扫描方向
        5'd12: oled_init_cmd = 8'hD3; // 显示偏移
        5'd13: oled_init_cmd = 8'h00;
        5'd14: oled_init_cmd = 8'hD5; // 时钟分频
        5'd15: oled_init_cmd = 8'h80;
        5'd16: oled_init_cmd = 8'hD9; // 预充电周期
        5'd17: oled_init_cmd = 8'hF1;
        5'd18: oled_init_cmd = 8'hDA; // COM 引脚硬件配置
        5'd19: oled_init_cmd = 8'h12;
        5'd20: oled_init_cmd = 8'hDB; // VCOMH
        5'd21: oled_init_cmd = 8'h40;
        5'd22: oled_init_cmd = 8'h20; // 内存寻址模式
        5'd23: oled_init_cmd = 8'h02; // 页寻址模式
        5'd24: oled_init_cmd = 8'h8D; // 电荷泵启用
        5'd25: oled_init_cmd = 8'h14;
        5'd26: oled_init_cmd = 8'hAF; // 开启显示！
        default: oled_init_cmd = 8'h00;
    endcase
endfunction

// --------------------------------------------------------------------------
// 7. OLED 驱动主流程控制 (上电初始化 -> 循环刷新 8 个 Page)
// --------------------------------------------------------------------------
localparam S_PWR_ON     = 4'd0;
localparam S_INIT_CMD   = 4'd1;
localparam S_PAGE_SET   = 4'd2;
localparam S_DATA_SEND  = 4'd3;

reg [3:0]  ctrl_state;
reg [19:0] pwr_delay; // 20ms 上电延时 (1,000,000 个 50MHz 时钟)
reg [4:0]  cmd_idx;
reg [1:0]  page_step; // 0: 0xB0+Page, 1: 0x00, 2: 0x10

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ctrl_state    <= S_PWR_ON;
        pwr_delay     <= 20'd0;
        cmd_idx       <= 5'd0;
        current_page  <= 3'd0;
        current_col   <= 7'd0;
        page_step     <= 2'd0;
        i2c_req       <= 1'b0;
        i2c_is_cmd    <= 1'b1;
        i2c_data      <= 8'h00;
        i2c_send_stop <= 1'b1;
    end else begin
        // P1-E: 保持锁存握手 - 只有当 i2c 引擎真正接手 (i2c_busy) 时才撤回请求
        if (i2c_busy) begin
            i2c_req <= 1'b0;
        end

        case (ctrl_state)
            // 等待上电 20ms 电源稳定
            S_PWR_ON: begin
                if (pwr_delay >= 20'd1_000_000) begin
                    ctrl_state <= S_INIT_CMD;
                    cmd_idx    <= 5'd0;
                end else begin
                    pwr_delay <= pwr_delay + 20'd1;
                end
            end

            // 依次发送 27 个初始化命令 (使用组合函数 oled_init_cmd)
            S_INIT_CMD: begin
                if (!i2c_busy && !i2c_req) begin
                    i2c_req       <= 1'b1;
                    i2c_is_cmd    <= 1'b1;
                    i2c_data      <= oled_init_cmd(cmd_idx);
                    i2c_send_stop <= 1'b1;
                    
                    if (cmd_idx >= 5'd26) begin
                        ctrl_state   <= S_PAGE_SET;
                        current_page <= 3'd0;
                        page_step    <= 2'd0;
                    end else begin
                        cmd_idx <= cmd_idx + 5'd1;
                    end
                end
            end

            // 设置当前 Page 与列起始地址 (3个命令)
            S_PAGE_SET: begin
                if (!i2c_busy && !i2c_req) begin
                    i2c_req       <= 1'b1;
                    i2c_is_cmd    <= 1'b1;
                    i2c_send_stop <= 1'b1;
                    
                    case (page_step)
                        2'd0: begin
                            i2c_data  <= 8'hB0 | current_page;
                            page_step <= 2'd1;
                        end
                        2'd1: begin
                            i2c_data  <= 8'h00; // 列低 4 位
                            page_step <= 2'd2;
                        end
                        2'd2: begin
                            i2c_data    <= 8'h10; // 列高 4 位
                            current_col <= 7'd0;
                            ctrl_state  <= S_DATA_SEND;
                        end
                        default: page_step <= 2'd0;
                    endcase
                end
            end

            // 连续发送该 Page 的 128 个数据字节
            S_DATA_SEND: begin
                if (!i2c_busy && !i2c_req) begin
                    i2c_req       <= 1'b1;
                    i2c_is_cmd    <= 1'b0; // 数据模式
                    i2c_data      <= pixel_out;
                    i2c_send_stop <= 1'b1;
                    
                    if (current_col >= 7'd127) begin
                        current_col <= 7'd0;
                        if (current_page >= 3'd7) begin
                            current_page <= 3'd0; // 整屏刷新完毕，开始下一轮
                        end else begin
                            current_page <= current_page + 3'd1;
                        end
                        page_step  <= 2'd0;
                        ctrl_state <= S_PAGE_SET;
                    end else begin
                        current_col <= current_col + 7'd1;
                    end
                end
            end

            default: ctrl_state <= S_PWR_ON;
        endcase
    end
end

endmodule

`endif
