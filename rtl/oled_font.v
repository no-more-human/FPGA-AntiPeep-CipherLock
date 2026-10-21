// ==============================================================================
// OLED 16x16 汉字与 8x16 ASCII 字模 ROM
// ==============================================================================
`timescale 1ns / 1ps

module oled_font(
    input  wire [5:0] cn_code,   // 汉字索引 0~29
    input  wire [4:0] cn_byte,   // 汉字字节索引 0~31 (0~15上部, 16~31下部)
    output reg  [7:0] cn_pixel,  // 8点垂直像素数据
    
    input  wire [4:0] asc_code,  // ASCII索引 0~16
    input  wire [3:0] asc_byte,  // ASCII字节索引 0~15 (0~7上部, 8~15下部)
    output reg  [7:0] asc_pixel  // 8点垂直像素数据
);

// 16x16 汉字字模查找表
always @(*) begin
    case (cn_code)
        6'd0: begin // 欢
            case (cn_byte)
                5'd0: cn_pixel = 8'h04;
                5'd1: cn_pixel = 8'h24;
                5'd2: cn_pixel = 8'h44;
                5'd3: cn_pixel = 8'h84;
                5'd4: cn_pixel = 8'h64;
                5'd5: cn_pixel = 8'h9C;
                5'd6: cn_pixel = 8'h40;
                5'd7: cn_pixel = 8'h30;
                5'd8: cn_pixel = 8'h0F;
                5'd9: cn_pixel = 8'hC8;
                5'd10: cn_pixel = 8'h08;
                5'd11: cn_pixel = 8'h08;
                5'd12: cn_pixel = 8'h28;
                5'd13: cn_pixel = 8'h18;
                5'd14: cn_pixel = 8'h00;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h10;
                5'd17: cn_pixel = 8'h08;
                5'd18: cn_pixel = 8'h06;
                5'd19: cn_pixel = 8'h01;
                5'd20: cn_pixel = 8'h82;
                5'd21: cn_pixel = 8'h4C;
                5'd22: cn_pixel = 8'h20;
                5'd23: cn_pixel = 8'h18;
                5'd24: cn_pixel = 8'h06;
                5'd25: cn_pixel = 8'h01;
                5'd26: cn_pixel = 8'h06;
                5'd27: cn_pixel = 8'h18;
                5'd28: cn_pixel = 8'h20;
                5'd29: cn_pixel = 8'h40;
                5'd30: cn_pixel = 8'h80;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd1: begin // 迎
            case (cn_byte)
                5'd0: cn_pixel = 8'h40;
                5'd1: cn_pixel = 8'h40;
                5'd2: cn_pixel = 8'h42;
                5'd3: cn_pixel = 8'hCC;
                5'd4: cn_pixel = 8'h00;
                5'd5: cn_pixel = 8'h00;
                5'd6: cn_pixel = 8'hFC;
                5'd7: cn_pixel = 8'h04;
                5'd8: cn_pixel = 8'h02;
                5'd9: cn_pixel = 8'h00;
                5'd10: cn_pixel = 8'hFC;
                5'd11: cn_pixel = 8'h04;
                5'd12: cn_pixel = 8'h04;
                5'd13: cn_pixel = 8'hFC;
                5'd14: cn_pixel = 8'h00;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h40;
                5'd18: cn_pixel = 8'h20;
                5'd19: cn_pixel = 8'h1F;
                5'd20: cn_pixel = 8'h20;
                5'd21: cn_pixel = 8'h40;
                5'd22: cn_pixel = 8'h4F;
                5'd23: cn_pixel = 8'h44;
                5'd24: cn_pixel = 8'h42;
                5'd25: cn_pixel = 8'h40;
                5'd26: cn_pixel = 8'h7F;
                5'd27: cn_pixel = 8'h42;
                5'd28: cn_pixel = 8'h44;
                5'd29: cn_pixel = 8'h43;
                5'd30: cn_pixel = 8'h40;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd2: begin // 使
            case (cn_byte)
                5'd0: cn_pixel = 8'h80;
                5'd1: cn_pixel = 8'h60;
                5'd2: cn_pixel = 8'hF8;
                5'd3: cn_pixel = 8'h07;
                5'd4: cn_pixel = 8'h04;
                5'd5: cn_pixel = 8'hE4;
                5'd6: cn_pixel = 8'h24;
                5'd7: cn_pixel = 8'h24;
                5'd8: cn_pixel = 8'h24;
                5'd9: cn_pixel = 8'hFF;
                5'd10: cn_pixel = 8'h24;
                5'd11: cn_pixel = 8'h24;
                5'd12: cn_pixel = 8'h24;
                5'd13: cn_pixel = 8'hE4;
                5'd14: cn_pixel = 8'h04;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h00;
                5'd18: cn_pixel = 8'hFF;
                5'd19: cn_pixel = 8'h00;
                5'd20: cn_pixel = 8'h80;
                5'd21: cn_pixel = 8'h81;
                5'd22: cn_pixel = 8'h45;
                5'd23: cn_pixel = 8'h29;
                5'd24: cn_pixel = 8'h11;
                5'd25: cn_pixel = 8'h2F;
                5'd26: cn_pixel = 8'h41;
                5'd27: cn_pixel = 8'h41;
                5'd28: cn_pixel = 8'h81;
                5'd29: cn_pixel = 8'h81;
                5'd30: cn_pixel = 8'h80;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd3: begin // 用
            case (cn_byte)
                5'd0: cn_pixel = 8'h00;
                5'd1: cn_pixel = 8'h00;
                5'd2: cn_pixel = 8'hFE;
                5'd3: cn_pixel = 8'h22;
                5'd4: cn_pixel = 8'h22;
                5'd5: cn_pixel = 8'h22;
                5'd6: cn_pixel = 8'h22;
                5'd7: cn_pixel = 8'hFE;
                5'd8: cn_pixel = 8'h22;
                5'd9: cn_pixel = 8'h22;
                5'd10: cn_pixel = 8'h22;
                5'd11: cn_pixel = 8'h22;
                5'd12: cn_pixel = 8'hFE;
                5'd13: cn_pixel = 8'h00;
                5'd14: cn_pixel = 8'h00;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h80;
                5'd17: cn_pixel = 8'h60;
                5'd18: cn_pixel = 8'h1F;
                5'd19: cn_pixel = 8'h02;
                5'd20: cn_pixel = 8'h02;
                5'd21: cn_pixel = 8'h02;
                5'd22: cn_pixel = 8'h02;
                5'd23: cn_pixel = 8'h7F;
                5'd24: cn_pixel = 8'h02;
                5'd25: cn_pixel = 8'h02;
                5'd26: cn_pixel = 8'h42;
                5'd27: cn_pixel = 8'h82;
                5'd28: cn_pixel = 8'h7F;
                5'd29: cn_pixel = 8'h00;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd4: begin // 请
            case (cn_byte)
                5'd0: cn_pixel = 8'h40;
                5'd1: cn_pixel = 8'h42;
                5'd2: cn_pixel = 8'hCC;
                5'd3: cn_pixel = 8'h00;
                5'd4: cn_pixel = 8'h00;
                5'd5: cn_pixel = 8'h44;
                5'd6: cn_pixel = 8'h54;
                5'd7: cn_pixel = 8'h54;
                5'd8: cn_pixel = 8'h54;
                5'd9: cn_pixel = 8'h7F;
                5'd10: cn_pixel = 8'h54;
                5'd11: cn_pixel = 8'h54;
                5'd12: cn_pixel = 8'h54;
                5'd13: cn_pixel = 8'h44;
                5'd14: cn_pixel = 8'h40;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h00;
                5'd18: cn_pixel = 8'h7F;
                5'd19: cn_pixel = 8'h20;
                5'd20: cn_pixel = 8'h10;
                5'd21: cn_pixel = 8'h00;
                5'd22: cn_pixel = 8'hFF;
                5'd23: cn_pixel = 8'h15;
                5'd24: cn_pixel = 8'h15;
                5'd25: cn_pixel = 8'h15;
                5'd26: cn_pixel = 8'h55;
                5'd27: cn_pixel = 8'h95;
                5'd28: cn_pixel = 8'h7F;
                5'd29: cn_pixel = 8'h00;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd5: begin // 输
            case (cn_byte)
                5'd0: cn_pixel = 8'h88;
                5'd1: cn_pixel = 8'h68;
                5'd2: cn_pixel = 8'h1F;
                5'd3: cn_pixel = 8'hC8;
                5'd4: cn_pixel = 8'h08;
                5'd5: cn_pixel = 8'h10;
                5'd6: cn_pixel = 8'hC8;
                5'd7: cn_pixel = 8'h54;
                5'd8: cn_pixel = 8'h52;
                5'd9: cn_pixel = 8'hD1;
                5'd10: cn_pixel = 8'h12;
                5'd11: cn_pixel = 8'h94;
                5'd12: cn_pixel = 8'h08;
                5'd13: cn_pixel = 8'hD0;
                5'd14: cn_pixel = 8'h10;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h09;
                5'd17: cn_pixel = 8'h19;
                5'd18: cn_pixel = 8'h09;
                5'd19: cn_pixel = 8'hFF;
                5'd20: cn_pixel = 8'h05;
                5'd21: cn_pixel = 8'h00;
                5'd22: cn_pixel = 8'hFF;
                5'd23: cn_pixel = 8'h12;
                5'd24: cn_pixel = 8'h92;
                5'd25: cn_pixel = 8'hFF;
                5'd26: cn_pixel = 8'h00;
                5'd27: cn_pixel = 8'h5F;
                5'd28: cn_pixel = 8'h80;
                5'd29: cn_pixel = 8'h7F;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd6: begin // 入
            case (cn_byte)
                5'd0: cn_pixel = 8'h00;
                5'd1: cn_pixel = 8'h00;
                5'd2: cn_pixel = 8'h00;
                5'd3: cn_pixel = 8'h00;
                5'd4: cn_pixel = 8'h00;
                5'd5: cn_pixel = 8'h01;
                5'd6: cn_pixel = 8'hE2;
                5'd7: cn_pixel = 8'h1C;
                5'd8: cn_pixel = 8'hE0;
                5'd9: cn_pixel = 8'h00;
                5'd10: cn_pixel = 8'h00;
                5'd11: cn_pixel = 8'h00;
                5'd12: cn_pixel = 8'h00;
                5'd13: cn_pixel = 8'h00;
                5'd14: cn_pixel = 8'h00;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h80;
                5'd17: cn_pixel = 8'h40;
                5'd18: cn_pixel = 8'h20;
                5'd19: cn_pixel = 8'h10;
                5'd20: cn_pixel = 8'h0C;
                5'd21: cn_pixel = 8'h03;
                5'd22: cn_pixel = 8'h00;
                5'd23: cn_pixel = 8'h00;
                5'd24: cn_pixel = 8'h00;
                5'd25: cn_pixel = 8'h03;
                5'd26: cn_pixel = 8'h0C;
                5'd27: cn_pixel = 8'h30;
                5'd28: cn_pixel = 8'h40;
                5'd29: cn_pixel = 8'h80;
                5'd30: cn_pixel = 8'h80;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd7: begin // 密
            case (cn_byte)
                5'd0: cn_pixel = 8'h10;
                5'd1: cn_pixel = 8'h8C;
                5'd2: cn_pixel = 8'h44;
                5'd3: cn_pixel = 8'h04;
                5'd4: cn_pixel = 8'hE4;
                5'd5: cn_pixel = 8'h04;
                5'd6: cn_pixel = 8'h95;
                5'd7: cn_pixel = 8'hA6;
                5'd8: cn_pixel = 8'h44;
                5'd9: cn_pixel = 8'h24;
                5'd10: cn_pixel = 8'h14;
                5'd11: cn_pixel = 8'h84;
                5'd12: cn_pixel = 8'h44;
                5'd13: cn_pixel = 8'h94;
                5'd14: cn_pixel = 8'h0C;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h02;
                5'd17: cn_pixel = 8'h02;
                5'd18: cn_pixel = 8'h7A;
                5'd19: cn_pixel = 8'h41;
                5'd20: cn_pixel = 8'h41;
                5'd21: cn_pixel = 8'h43;
                5'd22: cn_pixel = 8'h42;
                5'd23: cn_pixel = 8'h7E;
                5'd24: cn_pixel = 8'h42;
                5'd25: cn_pixel = 8'h42;
                5'd26: cn_pixel = 8'h42;
                5'd27: cn_pixel = 8'h43;
                5'd28: cn_pixel = 8'hF8;
                5'd29: cn_pixel = 8'h00;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd8: begin // 码
            case (cn_byte)
                5'd0: cn_pixel = 8'h04;
                5'd1: cn_pixel = 8'h84;
                5'd2: cn_pixel = 8'hE4;
                5'd3: cn_pixel = 8'h5C;
                5'd4: cn_pixel = 8'h44;
                5'd5: cn_pixel = 8'hC4;
                5'd6: cn_pixel = 8'h00;
                5'd7: cn_pixel = 8'h02;
                5'd8: cn_pixel = 8'hF2;
                5'd9: cn_pixel = 8'h82;
                5'd10: cn_pixel = 8'h82;
                5'd11: cn_pixel = 8'h82;
                5'd12: cn_pixel = 8'hFE;
                5'd13: cn_pixel = 8'h80;
                5'd14: cn_pixel = 8'h80;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h02;
                5'd17: cn_pixel = 8'h01;
                5'd18: cn_pixel = 8'h7F;
                5'd19: cn_pixel = 8'h10;
                5'd20: cn_pixel = 8'h10;
                5'd21: cn_pixel = 8'h3F;
                5'd22: cn_pixel = 8'h00;
                5'd23: cn_pixel = 8'h08;
                5'd24: cn_pixel = 8'h08;
                5'd25: cn_pixel = 8'h08;
                5'd26: cn_pixel = 8'h08;
                5'd27: cn_pixel = 8'h48;
                5'd28: cn_pixel = 8'h88;
                5'd29: cn_pixel = 8'h40;
                5'd30: cn_pixel = 8'h3F;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd9: begin // 开
            case (cn_byte)
                5'd0: cn_pixel = 8'h80;
                5'd1: cn_pixel = 8'h82;
                5'd2: cn_pixel = 8'h82;
                5'd3: cn_pixel = 8'h82;
                5'd4: cn_pixel = 8'hFE;
                5'd5: cn_pixel = 8'h82;
                5'd6: cn_pixel = 8'h82;
                5'd7: cn_pixel = 8'h82;
                5'd8: cn_pixel = 8'h82;
                5'd9: cn_pixel = 8'h82;
                5'd10: cn_pixel = 8'hFE;
                5'd11: cn_pixel = 8'h82;
                5'd12: cn_pixel = 8'h82;
                5'd13: cn_pixel = 8'h82;
                5'd14: cn_pixel = 8'h80;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h80;
                5'd18: cn_pixel = 8'h40;
                5'd19: cn_pixel = 8'h30;
                5'd20: cn_pixel = 8'h0F;
                5'd21: cn_pixel = 8'h00;
                5'd22: cn_pixel = 8'h00;
                5'd23: cn_pixel = 8'h00;
                5'd24: cn_pixel = 8'h00;
                5'd25: cn_pixel = 8'h00;
                5'd26: cn_pixel = 8'hFF;
                5'd27: cn_pixel = 8'h00;
                5'd28: cn_pixel = 8'h00;
                5'd29: cn_pixel = 8'h00;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd10: begin // 锁
            case (cn_byte)
                5'd0: cn_pixel = 8'h20;
                5'd1: cn_pixel = 8'h10;
                5'd2: cn_pixel = 8'h2C;
                5'd3: cn_pixel = 8'hE7;
                5'd4: cn_pixel = 8'h24;
                5'd5: cn_pixel = 8'h24;
                5'd6: cn_pixel = 8'h00;
                5'd7: cn_pixel = 8'hE2;
                5'd8: cn_pixel = 8'h2C;
                5'd9: cn_pixel = 8'h20;
                5'd10: cn_pixel = 8'hBF;
                5'd11: cn_pixel = 8'h20;
                5'd12: cn_pixel = 8'h28;
                5'd13: cn_pixel = 8'hE6;
                5'd14: cn_pixel = 8'h00;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h01;
                5'd17: cn_pixel = 8'h01;
                5'd18: cn_pixel = 8'h01;
                5'd19: cn_pixel = 8'h7F;
                5'd20: cn_pixel = 8'h21;
                5'd21: cn_pixel = 8'h11;
                5'd22: cn_pixel = 8'h80;
                5'd23: cn_pixel = 8'h4F;
                5'd24: cn_pixel = 8'h20;
                5'd25: cn_pixel = 8'h10;
                5'd26: cn_pixel = 8'h0F;
                5'd27: cn_pixel = 8'h10;
                5'd28: cn_pixel = 8'h20;
                5'd29: cn_pixel = 8'h4F;
                5'd30: cn_pixel = 8'h80;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd11: begin // 成
            case (cn_byte)
                5'd0: cn_pixel = 8'h00;
                5'd1: cn_pixel = 8'h00;
                5'd2: cn_pixel = 8'hF8;
                5'd3: cn_pixel = 8'h88;
                5'd4: cn_pixel = 8'h88;
                5'd5: cn_pixel = 8'h88;
                5'd6: cn_pixel = 8'h88;
                5'd7: cn_pixel = 8'h08;
                5'd8: cn_pixel = 8'h08;
                5'd9: cn_pixel = 8'hFF;
                5'd10: cn_pixel = 8'h08;
                5'd11: cn_pixel = 8'h09;
                5'd12: cn_pixel = 8'h0A;
                5'd13: cn_pixel = 8'hC8;
                5'd14: cn_pixel = 8'h08;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h80;
                5'd17: cn_pixel = 8'h60;
                5'd18: cn_pixel = 8'h1F;
                5'd19: cn_pixel = 8'h00;
                5'd20: cn_pixel = 8'h10;
                5'd21: cn_pixel = 8'h20;
                5'd22: cn_pixel = 8'h1F;
                5'd23: cn_pixel = 8'h80;
                5'd24: cn_pixel = 8'h40;
                5'd25: cn_pixel = 8'h21;
                5'd26: cn_pixel = 8'h16;
                5'd27: cn_pixel = 8'h18;
                5'd28: cn_pixel = 8'h26;
                5'd29: cn_pixel = 8'h41;
                5'd30: cn_pixel = 8'hF8;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd12: begin // 功
            case (cn_byte)
                5'd0: cn_pixel = 8'h08;
                5'd1: cn_pixel = 8'h08;
                5'd2: cn_pixel = 8'h08;
                5'd3: cn_pixel = 8'hF8;
                5'd4: cn_pixel = 8'h08;
                5'd5: cn_pixel = 8'h08;
                5'd6: cn_pixel = 8'h08;
                5'd7: cn_pixel = 8'h10;
                5'd8: cn_pixel = 8'h10;
                5'd9: cn_pixel = 8'hFF;
                5'd10: cn_pixel = 8'h10;
                5'd11: cn_pixel = 8'h10;
                5'd12: cn_pixel = 8'h10;
                5'd13: cn_pixel = 8'hF0;
                5'd14: cn_pixel = 8'h00;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h10;
                5'd17: cn_pixel = 8'h30;
                5'd18: cn_pixel = 8'h10;
                5'd19: cn_pixel = 8'h1F;
                5'd20: cn_pixel = 8'h08;
                5'd21: cn_pixel = 8'h88;
                5'd22: cn_pixel = 8'h48;
                5'd23: cn_pixel = 8'h30;
                5'd24: cn_pixel = 8'h0E;
                5'd25: cn_pixel = 8'h01;
                5'd26: cn_pixel = 8'h40;
                5'd27: cn_pixel = 8'h80;
                5'd28: cn_pixel = 8'h40;
                5'd29: cn_pixel = 8'h3F;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd13: begin // 错
            case (cn_byte)
                5'd0: cn_pixel = 8'h40;
                5'd1: cn_pixel = 8'h30;
                5'd2: cn_pixel = 8'hEF;
                5'd3: cn_pixel = 8'h24;
                5'd4: cn_pixel = 8'h64;
                5'd5: cn_pixel = 8'h48;
                5'd6: cn_pixel = 8'h48;
                5'd7: cn_pixel = 8'h7F;
                5'd8: cn_pixel = 8'h48;
                5'd9: cn_pixel = 8'h48;
                5'd10: cn_pixel = 8'h48;
                5'd11: cn_pixel = 8'h7F;
                5'd12: cn_pixel = 8'h48;
                5'd13: cn_pixel = 8'h48;
                5'd14: cn_pixel = 8'h40;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h01;
                5'd17: cn_pixel = 8'h01;
                5'd18: cn_pixel = 8'h7F;
                5'd19: cn_pixel = 8'h21;
                5'd20: cn_pixel = 8'h11;
                5'd21: cn_pixel = 8'h00;
                5'd22: cn_pixel = 8'hFF;
                5'd23: cn_pixel = 8'h49;
                5'd24: cn_pixel = 8'h49;
                5'd25: cn_pixel = 8'h49;
                5'd26: cn_pixel = 8'h49;
                5'd27: cn_pixel = 8'h49;
                5'd28: cn_pixel = 8'hFF;
                5'd29: cn_pixel = 8'h00;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd14: begin // 误
            case (cn_byte)
                5'd0: cn_pixel = 8'h40;
                5'd1: cn_pixel = 8'h42;
                5'd2: cn_pixel = 8'hCC;
                5'd3: cn_pixel = 8'h00;
                5'd4: cn_pixel = 8'h00;
                5'd5: cn_pixel = 8'h80;
                5'd6: cn_pixel = 8'h9E;
                5'd7: cn_pixel = 8'h92;
                5'd8: cn_pixel = 8'h92;
                5'd9: cn_pixel = 8'h92;
                5'd10: cn_pixel = 8'h92;
                5'd11: cn_pixel = 8'h92;
                5'd12: cn_pixel = 8'h9E;
                5'd13: cn_pixel = 8'h80;
                5'd14: cn_pixel = 8'h00;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h00;
                5'd18: cn_pixel = 8'h7F;
                5'd19: cn_pixel = 8'h20;
                5'd20: cn_pixel = 8'h94;
                5'd21: cn_pixel = 8'h84;
                5'd22: cn_pixel = 8'h44;
                5'd23: cn_pixel = 8'h24;
                5'd24: cn_pixel = 8'h14;
                5'd25: cn_pixel = 8'h0F;
                5'd26: cn_pixel = 8'h14;
                5'd27: cn_pixel = 8'h24;
                5'd28: cn_pixel = 8'h44;
                5'd29: cn_pixel = 8'h84;
                5'd30: cn_pixel = 8'h84;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd15: begin // 系
            case (cn_byte)
                5'd0: cn_pixel = 8'h00;
                5'd1: cn_pixel = 8'h00;
                5'd2: cn_pixel = 8'h22;
                5'd3: cn_pixel = 8'h32;
                5'd4: cn_pixel = 8'h2A;
                5'd5: cn_pixel = 8'hA6;
                5'd6: cn_pixel = 8'hA2;
                5'd7: cn_pixel = 8'h62;
                5'd8: cn_pixel = 8'h21;
                5'd9: cn_pixel = 8'h11;
                5'd10: cn_pixel = 8'h09;
                5'd11: cn_pixel = 8'h81;
                5'd12: cn_pixel = 8'h01;
                5'd13: cn_pixel = 8'h00;
                5'd14: cn_pixel = 8'h00;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h42;
                5'd18: cn_pixel = 8'h22;
                5'd19: cn_pixel = 8'h13;
                5'd20: cn_pixel = 8'h0B;
                5'd21: cn_pixel = 8'h42;
                5'd22: cn_pixel = 8'h82;
                5'd23: cn_pixel = 8'h7E;
                5'd24: cn_pixel = 8'h02;
                5'd25: cn_pixel = 8'h02;
                5'd26: cn_pixel = 8'h0A;
                5'd27: cn_pixel = 8'h12;
                5'd28: cn_pixel = 8'h23;
                5'd29: cn_pixel = 8'h46;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd16: begin // 统
            case (cn_byte)
                5'd0: cn_pixel = 8'h20;
                5'd1: cn_pixel = 8'h30;
                5'd2: cn_pixel = 8'hAC;
                5'd3: cn_pixel = 8'h63;
                5'd4: cn_pixel = 8'h30;
                5'd5: cn_pixel = 8'h00;
                5'd6: cn_pixel = 8'h88;
                5'd7: cn_pixel = 8'hC8;
                5'd8: cn_pixel = 8'hA8;
                5'd9: cn_pixel = 8'h99;
                5'd10: cn_pixel = 8'h8E;
                5'd11: cn_pixel = 8'h88;
                5'd12: cn_pixel = 8'hA8;
                5'd13: cn_pixel = 8'hC8;
                5'd14: cn_pixel = 8'h88;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h22;
                5'd17: cn_pixel = 8'h67;
                5'd18: cn_pixel = 8'h22;
                5'd19: cn_pixel = 8'h12;
                5'd20: cn_pixel = 8'h12;
                5'd21: cn_pixel = 8'h80;
                5'd22: cn_pixel = 8'h40;
                5'd23: cn_pixel = 8'h30;
                5'd24: cn_pixel = 8'h0F;
                5'd25: cn_pixel = 8'h00;
                5'd26: cn_pixel = 8'h00;
                5'd27: cn_pixel = 8'h3F;
                5'd28: cn_pixel = 8'h40;
                5'd29: cn_pixel = 8'h40;
                5'd30: cn_pixel = 8'h71;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd17: begin // 已
            case (cn_byte)
                5'd0: cn_pixel = 8'h00;
                5'd1: cn_pixel = 8'h00;
                5'd2: cn_pixel = 8'hE2;
                5'd3: cn_pixel = 8'h82;
                5'd4: cn_pixel = 8'h82;
                5'd5: cn_pixel = 8'h82;
                5'd6: cn_pixel = 8'h82;
                5'd7: cn_pixel = 8'h82;
                5'd8: cn_pixel = 8'h82;
                5'd9: cn_pixel = 8'h82;
                5'd10: cn_pixel = 8'h82;
                5'd11: cn_pixel = 8'hFE;
                5'd12: cn_pixel = 8'h00;
                5'd13: cn_pixel = 8'h00;
                5'd14: cn_pixel = 8'h00;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h00;
                5'd18: cn_pixel = 8'h3F;
                5'd19: cn_pixel = 8'h40;
                5'd20: cn_pixel = 8'h40;
                5'd21: cn_pixel = 8'h40;
                5'd22: cn_pixel = 8'h40;
                5'd23: cn_pixel = 8'h40;
                5'd24: cn_pixel = 8'h40;
                5'd25: cn_pixel = 8'h40;
                5'd26: cn_pixel = 8'h40;
                5'd27: cn_pixel = 8'h40;
                5'd28: cn_pixel = 8'h40;
                5'd29: cn_pixel = 8'h78;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd18: begin // 定
            case (cn_byte)
                5'd0: cn_pixel = 8'h10;
                5'd1: cn_pixel = 8'h0C;
                5'd2: cn_pixel = 8'h44;
                5'd3: cn_pixel = 8'h44;
                5'd4: cn_pixel = 8'h44;
                5'd5: cn_pixel = 8'h44;
                5'd6: cn_pixel = 8'h45;
                5'd7: cn_pixel = 8'hC6;
                5'd8: cn_pixel = 8'h44;
                5'd9: cn_pixel = 8'h44;
                5'd10: cn_pixel = 8'h44;
                5'd11: cn_pixel = 8'h44;
                5'd12: cn_pixel = 8'h44;
                5'd13: cn_pixel = 8'h14;
                5'd14: cn_pixel = 8'h0C;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h80;
                5'd17: cn_pixel = 8'h40;
                5'd18: cn_pixel = 8'h20;
                5'd19: cn_pixel = 8'h1E;
                5'd20: cn_pixel = 8'h20;
                5'd21: cn_pixel = 8'h40;
                5'd22: cn_pixel = 8'h40;
                5'd23: cn_pixel = 8'h7F;
                5'd24: cn_pixel = 8'h44;
                5'd25: cn_pixel = 8'h44;
                5'd26: cn_pixel = 8'h44;
                5'd27: cn_pixel = 8'h44;
                5'd28: cn_pixel = 8'h44;
                5'd29: cn_pixel = 8'h40;
                5'd30: cn_pixel = 8'h40;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd19: begin // 倒
            case (cn_byte)
                5'd0: cn_pixel = 8'h80;
                5'd1: cn_pixel = 8'h60;
                5'd2: cn_pixel = 8'hF8;
                5'd3: cn_pixel = 8'h07;
                5'd4: cn_pixel = 8'h04;
                5'd5: cn_pixel = 8'h64;
                5'd6: cn_pixel = 8'h5C;
                5'd7: cn_pixel = 8'hC4;
                5'd8: cn_pixel = 8'h64;
                5'd9: cn_pixel = 8'h44;
                5'd10: cn_pixel = 8'h00;
                5'd11: cn_pixel = 8'hF8;
                5'd12: cn_pixel = 8'h00;
                5'd13: cn_pixel = 8'hFF;
                5'd14: cn_pixel = 8'h00;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h00;
                5'd18: cn_pixel = 8'hFF;
                5'd19: cn_pixel = 8'h00;
                5'd20: cn_pixel = 8'h20;
                5'd21: cn_pixel = 8'h62;
                5'd22: cn_pixel = 8'h22;
                5'd23: cn_pixel = 8'h1F;
                5'd24: cn_pixel = 8'h12;
                5'd25: cn_pixel = 8'h12;
                5'd26: cn_pixel = 8'h00;
                5'd27: cn_pixel = 8'h4F;
                5'd28: cn_pixel = 8'h80;
                5'd29: cn_pixel = 8'h7F;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd20: begin // 计
            case (cn_byte)
                5'd0: cn_pixel = 8'h40;
                5'd1: cn_pixel = 8'h40;
                5'd2: cn_pixel = 8'h42;
                5'd3: cn_pixel = 8'hCC;
                5'd4: cn_pixel = 8'h00;
                5'd5: cn_pixel = 8'h40;
                5'd6: cn_pixel = 8'h40;
                5'd7: cn_pixel = 8'h40;
                5'd8: cn_pixel = 8'h40;
                5'd9: cn_pixel = 8'hFF;
                5'd10: cn_pixel = 8'h40;
                5'd11: cn_pixel = 8'h40;
                5'd12: cn_pixel = 8'h40;
                5'd13: cn_pixel = 8'h40;
                5'd14: cn_pixel = 8'h40;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h00;
                5'd18: cn_pixel = 8'h00;
                5'd19: cn_pixel = 8'h7F;
                5'd20: cn_pixel = 8'h20;
                5'd21: cn_pixel = 8'h10;
                5'd22: cn_pixel = 8'h00;
                5'd23: cn_pixel = 8'h00;
                5'd24: cn_pixel = 8'h00;
                5'd25: cn_pixel = 8'hFF;
                5'd26: cn_pixel = 8'h00;
                5'd27: cn_pixel = 8'h00;
                5'd28: cn_pixel = 8'h00;
                5'd29: cn_pixel = 8'h00;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd21: begin // 时
            case (cn_byte)
                5'd0: cn_pixel = 8'h00;
                5'd1: cn_pixel = 8'hFC;
                5'd2: cn_pixel = 8'h84;
                5'd3: cn_pixel = 8'h84;
                5'd4: cn_pixel = 8'h84;
                5'd5: cn_pixel = 8'hFC;
                5'd6: cn_pixel = 8'h00;
                5'd7: cn_pixel = 8'h10;
                5'd8: cn_pixel = 8'h10;
                5'd9: cn_pixel = 8'h10;
                5'd10: cn_pixel = 8'h10;
                5'd11: cn_pixel = 8'h10;
                5'd12: cn_pixel = 8'hFF;
                5'd13: cn_pixel = 8'h10;
                5'd14: cn_pixel = 8'h10;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h3F;
                5'd18: cn_pixel = 8'h10;
                5'd19: cn_pixel = 8'h10;
                5'd20: cn_pixel = 8'h10;
                5'd21: cn_pixel = 8'h3F;
                5'd22: cn_pixel = 8'h00;
                5'd23: cn_pixel = 8'h00;
                5'd24: cn_pixel = 8'h01;
                5'd25: cn_pixel = 8'h06;
                5'd26: cn_pixel = 8'h40;
                5'd27: cn_pixel = 8'h80;
                5'd28: cn_pixel = 8'h7F;
                5'd29: cn_pixel = 8'h00;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd22: begin // 秒
            case (cn_byte)
                5'd0: cn_pixel = 8'h24;
                5'd1: cn_pixel = 8'h24;
                5'd2: cn_pixel = 8'hA4;
                5'd3: cn_pixel = 8'hFE;
                5'd4: cn_pixel = 8'h23;
                5'd5: cn_pixel = 8'h22;
                5'd6: cn_pixel = 8'h00;
                5'd7: cn_pixel = 8'hC0;
                5'd8: cn_pixel = 8'h38;
                5'd9: cn_pixel = 8'h00;
                5'd10: cn_pixel = 8'hFF;
                5'd11: cn_pixel = 8'h00;
                5'd12: cn_pixel = 8'h08;
                5'd13: cn_pixel = 8'h10;
                5'd14: cn_pixel = 8'h60;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h08;
                5'd17: cn_pixel = 8'h06;
                5'd18: cn_pixel = 8'h01;
                5'd19: cn_pixel = 8'hFF;
                5'd20: cn_pixel = 8'h01;
                5'd21: cn_pixel = 8'h06;
                5'd22: cn_pixel = 8'h81;
                5'd23: cn_pixel = 8'h80;
                5'd24: cn_pixel = 8'h40;
                5'd25: cn_pixel = 8'h40;
                5'd26: cn_pixel = 8'h27;
                5'd27: cn_pixel = 8'h10;
                5'd28: cn_pixel = 8'h0C;
                5'd29: cn_pixel = 8'h03;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd23: begin // 剩
            case (cn_byte)
                5'd0: cn_pixel = 8'h48;
                5'd1: cn_pixel = 8'h4A;
                5'd2: cn_pixel = 8'hFA;
                5'd3: cn_pixel = 8'h0A;
                5'd4: cn_pixel = 8'hFE;
                5'd5: cn_pixel = 8'h09;
                5'd6: cn_pixel = 8'hF9;
                5'd7: cn_pixel = 8'h49;
                5'd8: cn_pixel = 8'hA8;
                5'd9: cn_pixel = 8'h00;
                5'd10: cn_pixel = 8'h00;
                5'd11: cn_pixel = 8'hF0;
                5'd12: cn_pixel = 8'h00;
                5'd13: cn_pixel = 8'h00;
                5'd14: cn_pixel = 8'hFF;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h22;
                5'd17: cn_pixel = 8'h11;
                5'd18: cn_pixel = 8'h0B;
                5'd19: cn_pixel = 8'h04;
                5'd20: cn_pixel = 8'hFF;
                5'd21: cn_pixel = 8'h04;
                5'd22: cn_pixel = 8'h09;
                5'd23: cn_pixel = 8'h12;
                5'd24: cn_pixel = 8'h23;
                5'd25: cn_pixel = 8'h00;
                5'd26: cn_pixel = 8'h00;
                5'd27: cn_pixel = 8'h0F;
                5'd28: cn_pixel = 8'h40;
                5'd29: cn_pixel = 8'h80;
                5'd30: cn_pixel = 8'h7F;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd24: begin // 余
            case (cn_byte)
                5'd0: cn_pixel = 8'h80;
                5'd1: cn_pixel = 8'h80;
                5'd2: cn_pixel = 8'h40;
                5'd3: cn_pixel = 8'h20;
                5'd4: cn_pixel = 8'h50;
                5'd5: cn_pixel = 8'h48;
                5'd6: cn_pixel = 8'h44;
                5'd7: cn_pixel = 8'hC3;
                5'd8: cn_pixel = 8'h44;
                5'd9: cn_pixel = 8'h48;
                5'd10: cn_pixel = 8'h50;
                5'd11: cn_pixel = 8'h20;
                5'd12: cn_pixel = 8'h40;
                5'd13: cn_pixel = 8'h80;
                5'd14: cn_pixel = 8'h80;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h40;
                5'd18: cn_pixel = 8'h22;
                5'd19: cn_pixel = 8'h1A;
                5'd20: cn_pixel = 8'h02;
                5'd21: cn_pixel = 8'h42;
                5'd22: cn_pixel = 8'h82;
                5'd23: cn_pixel = 8'h7F;
                5'd24: cn_pixel = 8'h02;
                5'd25: cn_pixel = 8'h02;
                5'd26: cn_pixel = 8'h02;
                5'd27: cn_pixel = 8'h0A;
                5'd28: cn_pixel = 8'h12;
                5'd29: cn_pixel = 8'h60;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd25: begin // 次
            case (cn_byte)
                5'd0: cn_pixel = 8'h00;
                5'd1: cn_pixel = 8'h02;
                5'd2: cn_pixel = 8'h0C;
                5'd3: cn_pixel = 8'h80;
                5'd4: cn_pixel = 8'h60;
                5'd5: cn_pixel = 8'h80;
                5'd6: cn_pixel = 8'h40;
                5'd7: cn_pixel = 8'h30;
                5'd8: cn_pixel = 8'h0F;
                5'd9: cn_pixel = 8'hC8;
                5'd10: cn_pixel = 8'h08;
                5'd11: cn_pixel = 8'h08;
                5'd12: cn_pixel = 8'h28;
                5'd13: cn_pixel = 8'h18;
                5'd14: cn_pixel = 8'h00;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h02;
                5'd17: cn_pixel = 8'h02;
                5'd18: cn_pixel = 8'h7E;
                5'd19: cn_pixel = 8'h01;
                5'd20: cn_pixel = 8'h80;
                5'd21: cn_pixel = 8'h40;
                5'd22: cn_pixel = 8'h20;
                5'd23: cn_pixel = 8'h18;
                5'd24: cn_pixel = 8'h06;
                5'd25: cn_pixel = 8'h01;
                5'd26: cn_pixel = 8'h06;
                5'd27: cn_pixel = 8'h18;
                5'd28: cn_pixel = 8'h20;
                5'd29: cn_pixel = 8'h40;
                5'd30: cn_pixel = 8'h80;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd26: begin // 确
            case (cn_byte)
                5'd0: cn_pixel = 8'h04;
                5'd1: cn_pixel = 8'h84;
                5'd2: cn_pixel = 8'hE4;
                5'd3: cn_pixel = 8'h5C;
                5'd4: cn_pixel = 8'h44;
                5'd5: cn_pixel = 8'hC4;
                5'd6: cn_pixel = 8'h20;
                5'd7: cn_pixel = 8'h10;
                5'd8: cn_pixel = 8'hE8;
                5'd9: cn_pixel = 8'h27;
                5'd10: cn_pixel = 8'h24;
                5'd11: cn_pixel = 8'hE4;
                5'd12: cn_pixel = 8'h34;
                5'd13: cn_pixel = 8'h2C;
                5'd14: cn_pixel = 8'hE0;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h02;
                5'd17: cn_pixel = 8'h01;
                5'd18: cn_pixel = 8'h7F;
                5'd19: cn_pixel = 8'h10;
                5'd20: cn_pixel = 8'h10;
                5'd21: cn_pixel = 8'h3F;
                5'd22: cn_pixel = 8'h80;
                5'd23: cn_pixel = 8'h60;
                5'd24: cn_pixel = 8'h1F;
                5'd25: cn_pixel = 8'h09;
                5'd26: cn_pixel = 8'h09;
                5'd27: cn_pixel = 8'h3F;
                5'd28: cn_pixel = 8'h49;
                5'd29: cn_pixel = 8'h89;
                5'd30: cn_pixel = 8'h7F;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd27: begin // 认
            case (cn_byte)
                5'd0: cn_pixel = 8'h40;
                5'd1: cn_pixel = 8'h40;
                5'd2: cn_pixel = 8'h42;
                5'd3: cn_pixel = 8'hCC;
                5'd4: cn_pixel = 8'h00;
                5'd5: cn_pixel = 8'h00;
                5'd6: cn_pixel = 8'h00;
                5'd7: cn_pixel = 8'h00;
                5'd8: cn_pixel = 8'h00;
                5'd9: cn_pixel = 8'hFF;
                5'd10: cn_pixel = 8'h00;
                5'd11: cn_pixel = 8'h00;
                5'd12: cn_pixel = 8'h00;
                5'd13: cn_pixel = 8'h00;
                5'd14: cn_pixel = 8'h00;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h00;
                5'd18: cn_pixel = 8'h00;
                5'd19: cn_pixel = 8'h3F;
                5'd20: cn_pixel = 8'h90;
                5'd21: cn_pixel = 8'h48;
                5'd22: cn_pixel = 8'h20;
                5'd23: cn_pixel = 8'h18;
                5'd24: cn_pixel = 8'h07;
                5'd25: cn_pixel = 8'h00;
                5'd26: cn_pixel = 8'h07;
                5'd27: cn_pixel = 8'h18;
                5'd28: cn_pixel = 8'h20;
                5'd29: cn_pixel = 8'h40;
                5'd30: cn_pixel = 8'h80;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd28: begin // 清
            case (cn_byte)
                5'd0: cn_pixel = 8'h10;
                5'd1: cn_pixel = 8'h60;
                5'd2: cn_pixel = 8'h02;
                5'd3: cn_pixel = 8'h8C;
                5'd4: cn_pixel = 8'h00;
                5'd5: cn_pixel = 8'h44;
                5'd6: cn_pixel = 8'h54;
                5'd7: cn_pixel = 8'h54;
                5'd8: cn_pixel = 8'h54;
                5'd9: cn_pixel = 8'h7F;
                5'd10: cn_pixel = 8'h54;
                5'd11: cn_pixel = 8'h54;
                5'd12: cn_pixel = 8'h54;
                5'd13: cn_pixel = 8'h44;
                5'd14: cn_pixel = 8'h40;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h04;
                5'd17: cn_pixel = 8'h04;
                5'd18: cn_pixel = 8'h7E;
                5'd19: cn_pixel = 8'h01;
                5'd20: cn_pixel = 8'h00;
                5'd21: cn_pixel = 8'h00;
                5'd22: cn_pixel = 8'hFF;
                5'd23: cn_pixel = 8'h15;
                5'd24: cn_pixel = 8'h15;
                5'd25: cn_pixel = 8'h15;
                5'd26: cn_pixel = 8'h55;
                5'd27: cn_pixel = 8'h95;
                5'd28: cn_pixel = 8'h7F;
                5'd29: cn_pixel = 8'h00;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd29: begin // 除
            case (cn_byte)
                5'd0: cn_pixel = 8'h00;
                5'd1: cn_pixel = 8'hFE;
                5'd2: cn_pixel = 8'h22;
                5'd3: cn_pixel = 8'h5A;
                5'd4: cn_pixel = 8'h86;
                5'd5: cn_pixel = 8'h20;
                5'd6: cn_pixel = 8'h10;
                5'd7: cn_pixel = 8'h28;
                5'd8: cn_pixel = 8'h24;
                5'd9: cn_pixel = 8'hE3;
                5'd10: cn_pixel = 8'h24;
                5'd11: cn_pixel = 8'h28;
                5'd12: cn_pixel = 8'h10;
                5'd13: cn_pixel = 8'h20;
                5'd14: cn_pixel = 8'h20;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'hFF;
                5'd18: cn_pixel = 8'h04;
                5'd19: cn_pixel = 8'h08;
                5'd20: cn_pixel = 8'h27;
                5'd21: cn_pixel = 8'h11;
                5'd22: cn_pixel = 8'h0D;
                5'd23: cn_pixel = 8'h41;
                5'd24: cn_pixel = 8'h81;
                5'd25: cn_pixel = 8'h7F;
                5'd26: cn_pixel = 8'h01;
                5'd27: cn_pixel = 8'h05;
                5'd28: cn_pixel = 8'h09;
                5'd29: cn_pixel = 8'h31;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd30: begin // 新
            case (cn_byte)
                5'd0: cn_pixel = 8'h40;
                5'd1: cn_pixel = 8'h44;
                5'd2: cn_pixel = 8'h54;
                5'd3: cn_pixel = 8'h65;
                5'd4: cn_pixel = 8'hC6;
                5'd5: cn_pixel = 8'h64;
                5'd6: cn_pixel = 8'h54;
                5'd7: cn_pixel = 8'h44;
                5'd8: cn_pixel = 8'h00;
                5'd9: cn_pixel = 8'hFC;
                5'd10: cn_pixel = 8'h44;
                5'd11: cn_pixel = 8'h44;
                5'd12: cn_pixel = 8'hC4;
                5'd13: cn_pixel = 8'h42;
                5'd14: cn_pixel = 8'h40;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h20;
                5'd17: cn_pixel = 8'h12;
                5'd18: cn_pixel = 8'h4A;
                5'd19: cn_pixel = 8'h82;
                5'd20: cn_pixel = 8'h7F;
                5'd21: cn_pixel = 8'h02;
                5'd22: cn_pixel = 8'h0A;
                5'd23: cn_pixel = 8'h92;
                5'd24: cn_pixel = 8'h60;
                5'd25: cn_pixel = 8'h1F;
                5'd26: cn_pixel = 8'h00;
                5'd27: cn_pixel = 8'h00;
                5'd28: cn_pixel = 8'hFF;
                5'd29: cn_pixel = 8'h00;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd31: begin // 旧
            case (cn_byte)
                5'd0: cn_pixel = 8'h00;
                5'd1: cn_pixel = 8'h00;
                5'd2: cn_pixel = 8'hFF;
                5'd3: cn_pixel = 8'h00;
                5'd4: cn_pixel = 8'h00;
                5'd5: cn_pixel = 8'h00;
                5'd6: cn_pixel = 8'hFE;
                5'd7: cn_pixel = 8'h82;
                5'd8: cn_pixel = 8'h82;
                5'd9: cn_pixel = 8'h82;
                5'd10: cn_pixel = 8'h82;
                5'd11: cn_pixel = 8'h82;
                5'd12: cn_pixel = 8'h82;
                5'd13: cn_pixel = 8'hFE;
                5'd14: cn_pixel = 8'h00;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h00;
                5'd18: cn_pixel = 8'hFF;
                5'd19: cn_pixel = 8'h00;
                5'd20: cn_pixel = 8'h00;
                5'd21: cn_pixel = 8'h00;
                5'd22: cn_pixel = 8'h7F;
                5'd23: cn_pixel = 8'h20;
                5'd24: cn_pixel = 8'h20;
                5'd25: cn_pixel = 8'h20;
                5'd26: cn_pixel = 8'h20;
                5'd27: cn_pixel = 8'h20;
                5'd28: cn_pixel = 8'h20;
                5'd29: cn_pixel = 8'h7F;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd32: begin // 改
            case (cn_byte)
                5'd0: cn_pixel = 8'h04;
                5'd1: cn_pixel = 8'h84;
                5'd2: cn_pixel = 8'h84;
                5'd3: cn_pixel = 8'h84;
                5'd4: cn_pixel = 8'h84;
                5'd5: cn_pixel = 8'hFC;
                5'd6: cn_pixel = 8'h40;
                5'd7: cn_pixel = 8'h30;
                5'd8: cn_pixel = 8'hCC;
                5'd9: cn_pixel = 8'h0B;
                5'd10: cn_pixel = 8'h08;
                5'd11: cn_pixel = 8'h08;
                5'd12: cn_pixel = 8'hF8;
                5'd13: cn_pixel = 8'h08;
                5'd14: cn_pixel = 8'h08;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h7F;
                5'd18: cn_pixel = 8'h20;
                5'd19: cn_pixel = 8'h10;
                5'd20: cn_pixel = 8'h10;
                5'd21: cn_pixel = 8'h08;
                5'd22: cn_pixel = 8'h80;
                5'd23: cn_pixel = 8'h40;
                5'd24: cn_pixel = 8'h21;
                5'd25: cn_pixel = 8'h16;
                5'd26: cn_pixel = 8'h08;
                5'd27: cn_pixel = 8'h16;
                5'd28: cn_pixel = 8'h21;
                5'd29: cn_pixel = 8'h40;
                5'd30: cn_pixel = 8'h80;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd33: begin // 设
            case (cn_byte)
                5'd0: cn_pixel = 8'h40;
                5'd1: cn_pixel = 8'h40;
                5'd2: cn_pixel = 8'h42;
                5'd3: cn_pixel = 8'hCC;
                5'd4: cn_pixel = 8'h00;
                5'd5: cn_pixel = 8'h40;
                5'd6: cn_pixel = 8'hA0;
                5'd7: cn_pixel = 8'h9E;
                5'd8: cn_pixel = 8'h82;
                5'd9: cn_pixel = 8'h82;
                5'd10: cn_pixel = 8'h82;
                5'd11: cn_pixel = 8'h9E;
                5'd12: cn_pixel = 8'hA0;
                5'd13: cn_pixel = 8'h20;
                5'd14: cn_pixel = 8'h20;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h00;
                5'd18: cn_pixel = 8'h00;
                5'd19: cn_pixel = 8'h3F;
                5'd20: cn_pixel = 8'h90;
                5'd21: cn_pixel = 8'h88;
                5'd22: cn_pixel = 8'h40;
                5'd23: cn_pixel = 8'h43;
                5'd24: cn_pixel = 8'h2C;
                5'd25: cn_pixel = 8'h10;
                5'd26: cn_pixel = 8'h28;
                5'd27: cn_pixel = 8'h46;
                5'd28: cn_pixel = 8'h41;
                5'd29: cn_pixel = 8'h80;
                5'd30: cn_pixel = 8'h80;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd34: begin // 置
            case (cn_byte)
                5'd0: cn_pixel = 8'h00;
                5'd1: cn_pixel = 8'h17;
                5'd2: cn_pixel = 8'h15;
                5'd3: cn_pixel = 8'hD5;
                5'd4: cn_pixel = 8'h55;
                5'd5: cn_pixel = 8'h57;
                5'd6: cn_pixel = 8'h55;
                5'd7: cn_pixel = 8'h7D;
                5'd8: cn_pixel = 8'h55;
                5'd9: cn_pixel = 8'h57;
                5'd10: cn_pixel = 8'h55;
                5'd11: cn_pixel = 8'hD5;
                5'd12: cn_pixel = 8'h15;
                5'd13: cn_pixel = 8'h17;
                5'd14: cn_pixel = 8'h00;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h40;
                5'd17: cn_pixel = 8'h40;
                5'd18: cn_pixel = 8'h40;
                5'd19: cn_pixel = 8'h7F;
                5'd20: cn_pixel = 8'h55;
                5'd21: cn_pixel = 8'h55;
                5'd22: cn_pixel = 8'h55;
                5'd23: cn_pixel = 8'h55;
                5'd24: cn_pixel = 8'h55;
                5'd25: cn_pixel = 8'h55;
                5'd26: cn_pixel = 8'h55;
                5'd27: cn_pixel = 8'h7F;
                5'd28: cn_pixel = 8'h40;
                5'd29: cn_pixel = 8'h40;
                5'd30: cn_pixel = 8'h40;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd35: begin // 户
            case (cn_byte)
                5'd0: cn_pixel = 8'h00;
                5'd1: cn_pixel = 8'h00;
                5'd2: cn_pixel = 8'h00;
                5'd3: cn_pixel = 8'hF8;
                5'd4: cn_pixel = 8'h08;
                5'd5: cn_pixel = 8'h08;
                5'd6: cn_pixel = 8'h09;
                5'd7: cn_pixel = 8'h0E;
                5'd8: cn_pixel = 8'h08;
                5'd9: cn_pixel = 8'h08;
                5'd10: cn_pixel = 8'h08;
                5'd11: cn_pixel = 8'h08;
                5'd12: cn_pixel = 8'hF8;
                5'd13: cn_pixel = 8'h00;
                5'd14: cn_pixel = 8'h00;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h80;
                5'd18: cn_pixel = 8'h60;
                5'd19: cn_pixel = 8'h1F;
                5'd20: cn_pixel = 8'h01;
                5'd21: cn_pixel = 8'h01;
                5'd22: cn_pixel = 8'h01;
                5'd23: cn_pixel = 8'h01;
                5'd24: cn_pixel = 8'h01;
                5'd25: cn_pixel = 8'h01;
                5'd26: cn_pixel = 8'h01;
                5'd27: cn_pixel = 8'h01;
                5'd28: cn_pixel = 8'h03;
                5'd29: cn_pixel = 8'h00;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd36: begin // 录
            case (cn_byte)
                5'd0: cn_pixel = 8'h80;
                5'd1: cn_pixel = 8'h80;
                5'd2: cn_pixel = 8'h82;
                5'd3: cn_pixel = 8'h92;
                5'd4: cn_pixel = 8'h92;
                5'd5: cn_pixel = 8'h92;
                5'd6: cn_pixel = 8'h92;
                5'd7: cn_pixel = 8'h92;
                5'd8: cn_pixel = 8'h92;
                5'd9: cn_pixel = 8'h92;
                5'd10: cn_pixel = 8'h92;
                5'd11: cn_pixel = 8'hFE;
                5'd12: cn_pixel = 8'h80;
                5'd13: cn_pixel = 8'h80;
                5'd14: cn_pixel = 8'h80;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h40;
                5'd17: cn_pixel = 8'h40;
                5'd18: cn_pixel = 8'h22;
                5'd19: cn_pixel = 8'h24;
                5'd20: cn_pixel = 8'h10;
                5'd21: cn_pixel = 8'h48;
                5'd22: cn_pixel = 8'h80;
                5'd23: cn_pixel = 8'h7F;
                5'd24: cn_pixel = 8'h04;
                5'd25: cn_pixel = 8'h08;
                5'd26: cn_pixel = 8'h18;
                5'd27: cn_pixel = 8'h24;
                5'd28: cn_pixel = 8'h22;
                5'd29: cn_pixel = 8'h40;
                5'd30: cn_pixel = 8'h40;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd37: begin // 再
            case (cn_byte)
                5'd0: cn_pixel = 8'h02;
                5'd1: cn_pixel = 8'h02;
                5'd2: cn_pixel = 8'hF2;
                5'd3: cn_pixel = 8'h92;
                5'd4: cn_pixel = 8'h92;
                5'd5: cn_pixel = 8'h92;
                5'd6: cn_pixel = 8'h92;
                5'd7: cn_pixel = 8'hFE;
                5'd8: cn_pixel = 8'h92;
                5'd9: cn_pixel = 8'h92;
                5'd10: cn_pixel = 8'h92;
                5'd11: cn_pixel = 8'h92;
                5'd12: cn_pixel = 8'hF2;
                5'd13: cn_pixel = 8'h02;
                5'd14: cn_pixel = 8'h02;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h04;
                5'd17: cn_pixel = 8'h04;
                5'd18: cn_pixel = 8'hFF;
                5'd19: cn_pixel = 8'h04;
                5'd20: cn_pixel = 8'h04;
                5'd21: cn_pixel = 8'h04;
                5'd22: cn_pixel = 8'h04;
                5'd23: cn_pixel = 8'h07;
                5'd24: cn_pixel = 8'h04;
                5'd25: cn_pixel = 8'h04;
                5'd26: cn_pixel = 8'h44;
                5'd27: cn_pixel = 8'h84;
                5'd28: cn_pixel = 8'h7F;
                5'd29: cn_pixel = 8'h04;
                5'd30: cn_pixel = 8'h04;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd38: begin // 重
            case (cn_byte)
                5'd0: cn_pixel = 8'h10;
                5'd1: cn_pixel = 8'h10;
                5'd2: cn_pixel = 8'h14;
                5'd3: cn_pixel = 8'hD4;
                5'd4: cn_pixel = 8'h54;
                5'd5: cn_pixel = 8'h54;
                5'd6: cn_pixel = 8'h54;
                5'd7: cn_pixel = 8'hFC;
                5'd8: cn_pixel = 8'h52;
                5'd9: cn_pixel = 8'h52;
                5'd10: cn_pixel = 8'h52;
                5'd11: cn_pixel = 8'hD3;
                5'd12: cn_pixel = 8'h12;
                5'd13: cn_pixel = 8'h10;
                5'd14: cn_pixel = 8'h10;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h40;
                5'd17: cn_pixel = 8'h40;
                5'd18: cn_pixel = 8'h50;
                5'd19: cn_pixel = 8'h57;
                5'd20: cn_pixel = 8'h55;
                5'd21: cn_pixel = 8'h55;
                5'd22: cn_pixel = 8'h55;
                5'd23: cn_pixel = 8'h7F;
                5'd24: cn_pixel = 8'h55;
                5'd25: cn_pixel = 8'h55;
                5'd26: cn_pixel = 8'h55;
                5'd27: cn_pixel = 8'h57;
                5'd28: cn_pixel = 8'h50;
                5'd29: cn_pixel = 8'h40;
                5'd30: cn_pixel = 8'h40;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd39: begin // 复
            case (cn_byte)
                5'd0: cn_pixel = 8'h20;
                5'd1: cn_pixel = 8'h10;
                5'd2: cn_pixel = 8'h08;
                5'd3: cn_pixel = 8'hF7;
                5'd4: cn_pixel = 8'h54;
                5'd5: cn_pixel = 8'h54;
                5'd6: cn_pixel = 8'h54;
                5'd7: cn_pixel = 8'h54;
                5'd8: cn_pixel = 8'h54;
                5'd9: cn_pixel = 8'h54;
                5'd10: cn_pixel = 8'h54;
                5'd11: cn_pixel = 8'hF4;
                5'd12: cn_pixel = 8'h04;
                5'd13: cn_pixel = 8'h04;
                5'd14: cn_pixel = 8'h00;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h80;
                5'd17: cn_pixel = 8'h90;
                5'd18: cn_pixel = 8'h90;
                5'd19: cn_pixel = 8'h49;
                5'd20: cn_pixel = 8'h4D;
                5'd21: cn_pixel = 8'h57;
                5'd22: cn_pixel = 8'h25;
                5'd23: cn_pixel = 8'h25;
                5'd24: cn_pixel = 8'h25;
                5'd25: cn_pixel = 8'h55;
                5'd26: cn_pixel = 8'h4D;
                5'd27: cn_pixel = 8'h45;
                5'd28: cn_pixel = 8'h80;
                5'd29: cn_pixel = 8'h80;
                5'd30: cn_pixel = 8'h80;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd40: begin // 修
            case (cn_byte)
                5'd0: cn_pixel = 8'h40;
                5'd1: cn_pixel = 8'h20;
                5'd2: cn_pixel = 8'hF8;
                5'd3: cn_pixel = 8'h07;
                5'd4: cn_pixel = 8'hF0;
                5'd5: cn_pixel = 8'hA0;
                5'd6: cn_pixel = 8'h90;
                5'd7: cn_pixel = 8'h4C;
                5'd8: cn_pixel = 8'h57;
                5'd9: cn_pixel = 8'h24;
                5'd10: cn_pixel = 8'hA4;
                5'd11: cn_pixel = 8'h54;
                5'd12: cn_pixel = 8'h4C;
                5'd13: cn_pixel = 8'h80;
                5'd14: cn_pixel = 8'h80;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h00;
                5'd18: cn_pixel = 8'hFF;
                5'd19: cn_pixel = 8'h00;
                5'd20: cn_pixel = 8'h1F;
                5'd21: cn_pixel = 8'h80;
                5'd22: cn_pixel = 8'h92;
                5'd23: cn_pixel = 8'h52;
                5'd24: cn_pixel = 8'h49;
                5'd25: cn_pixel = 8'h29;
                5'd26: cn_pixel = 8'h24;
                5'd27: cn_pixel = 8'h12;
                5'd28: cn_pixel = 8'h08;
                5'd29: cn_pixel = 8'h00;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd41: begin // 当
            case (cn_byte)
                5'd0: cn_pixel = 8'h00;
                5'd1: cn_pixel = 8'h40;
                5'd2: cn_pixel = 8'h42;
                5'd3: cn_pixel = 8'h44;
                5'd4: cn_pixel = 8'h58;
                5'd5: cn_pixel = 8'h40;
                5'd6: cn_pixel = 8'h40;
                5'd7: cn_pixel = 8'h7F;
                5'd8: cn_pixel = 8'h40;
                5'd9: cn_pixel = 8'h40;
                5'd10: cn_pixel = 8'h50;
                5'd11: cn_pixel = 8'h48;
                5'd12: cn_pixel = 8'hC6;
                5'd13: cn_pixel = 8'h00;
                5'd14: cn_pixel = 8'h00;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h40;
                5'd18: cn_pixel = 8'h44;
                5'd19: cn_pixel = 8'h44;
                5'd20: cn_pixel = 8'h44;
                5'd21: cn_pixel = 8'h44;
                5'd22: cn_pixel = 8'h44;
                5'd23: cn_pixel = 8'h44;
                5'd24: cn_pixel = 8'h44;
                5'd25: cn_pixel = 8'h44;
                5'd26: cn_pixel = 8'h44;
                5'd27: cn_pixel = 8'h44;
                5'd28: cn_pixel = 8'hFF;
                5'd29: cn_pixel = 8'h00;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd42: begin // 前
            case (cn_byte)
                5'd0: cn_pixel = 8'h08;
                5'd1: cn_pixel = 8'h08;
                5'd2: cn_pixel = 8'hE8;
                5'd3: cn_pixel = 8'h29;
                5'd4: cn_pixel = 8'h2E;
                5'd5: cn_pixel = 8'h28;
                5'd6: cn_pixel = 8'hE8;
                5'd7: cn_pixel = 8'h08;
                5'd8: cn_pixel = 8'h08;
                5'd9: cn_pixel = 8'hC8;
                5'd10: cn_pixel = 8'h0C;
                5'd11: cn_pixel = 8'h0B;
                5'd12: cn_pixel = 8'hE8;
                5'd13: cn_pixel = 8'h08;
                5'd14: cn_pixel = 8'h08;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'h00;
                5'd18: cn_pixel = 8'hFF;
                5'd19: cn_pixel = 8'h09;
                5'd20: cn_pixel = 8'h49;
                5'd21: cn_pixel = 8'h89;
                5'd22: cn_pixel = 8'h7F;
                5'd23: cn_pixel = 8'h00;
                5'd24: cn_pixel = 8'h00;
                5'd25: cn_pixel = 8'h0F;
                5'd26: cn_pixel = 8'h40;
                5'd27: cn_pixel = 8'h80;
                5'd28: cn_pixel = 8'h7F;
                5'd29: cn_pixel = 8'h00;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd43: begin // 更
            case (cn_byte)
                5'd0: cn_pixel = 8'h02;
                5'd1: cn_pixel = 8'h02;
                5'd2: cn_pixel = 8'hF2;
                5'd3: cn_pixel = 8'h92;
                5'd4: cn_pixel = 8'h92;
                5'd5: cn_pixel = 8'h92;
                5'd6: cn_pixel = 8'h92;
                5'd7: cn_pixel = 8'hFE;
                5'd8: cn_pixel = 8'h92;
                5'd9: cn_pixel = 8'h92;
                5'd10: cn_pixel = 8'h92;
                5'd11: cn_pixel = 8'h92;
                5'd12: cn_pixel = 8'hF2;
                5'd13: cn_pixel = 8'h02;
                5'd14: cn_pixel = 8'h02;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h80;
                5'd17: cn_pixel = 8'h80;
                5'd18: cn_pixel = 8'h87;
                5'd19: cn_pixel = 8'h4C;
                5'd20: cn_pixel = 8'h54;
                5'd21: cn_pixel = 8'h24;
                5'd22: cn_pixel = 8'h34;
                5'd23: cn_pixel = 8'h4F;
                5'd24: cn_pixel = 8'h44;
                5'd25: cn_pixel = 8'h44;
                5'd26: cn_pixel = 8'h84;
                5'd27: cn_pixel = 8'h84;
                5'd28: cn_pixel = 8'h87;
                5'd29: cn_pixel = 8'h80;
                5'd30: cn_pixel = 8'h80;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd44: begin // 门
            case (cn_byte)
                5'd0: cn_pixel = 8'h00;
                5'd1: cn_pixel = 8'hF8;
                5'd2: cn_pixel = 8'h01;
                5'd3: cn_pixel = 8'h06;
                5'd4: cn_pixel = 8'h00;
                5'd5: cn_pixel = 8'h00;
                5'd6: cn_pixel = 8'h02;
                5'd7: cn_pixel = 8'h02;
                5'd8: cn_pixel = 8'h02;
                5'd9: cn_pixel = 8'h02;
                5'd10: cn_pixel = 8'h02;
                5'd11: cn_pixel = 8'h02;
                5'd12: cn_pixel = 8'h02;
                5'd13: cn_pixel = 8'hFE;
                5'd14: cn_pixel = 8'h00;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h00;
                5'd17: cn_pixel = 8'hFF;
                5'd18: cn_pixel = 8'h00;
                5'd19: cn_pixel = 8'h00;
                5'd20: cn_pixel = 8'h00;
                5'd21: cn_pixel = 8'h00;
                5'd22: cn_pixel = 8'h00;
                5'd23: cn_pixel = 8'h00;
                5'd24: cn_pixel = 8'h00;
                5'd25: cn_pixel = 8'h00;
                5'd26: cn_pixel = 8'h00;
                5'd27: cn_pixel = 8'h40;
                5'd28: cn_pixel = 8'h80;
                5'd29: cn_pixel = 8'h7F;
                5'd30: cn_pixel = 8'h00;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd45: begin // 键
            case (cn_byte)
                5'd0: cn_pixel = 8'h40;
                5'd1: cn_pixel = 8'h30;
                5'd2: cn_pixel = 8'hEF;
                5'd3: cn_pixel = 8'h24;
                5'd4: cn_pixel = 8'h24;
                5'd5: cn_pixel = 8'h80;
                5'd6: cn_pixel = 8'hE4;
                5'd7: cn_pixel = 8'h9C;
                5'd8: cn_pixel = 8'h10;
                5'd9: cn_pixel = 8'h54;
                5'd10: cn_pixel = 8'h54;
                5'd11: cn_pixel = 8'hFF;
                5'd12: cn_pixel = 8'h54;
                5'd13: cn_pixel = 8'h7C;
                5'd14: cn_pixel = 8'h10;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h01;
                5'd17: cn_pixel = 8'h01;
                5'd18: cn_pixel = 8'h7F;
                5'd19: cn_pixel = 8'h21;
                5'd20: cn_pixel = 8'h51;
                5'd21: cn_pixel = 8'h26;
                5'd22: cn_pixel = 8'h18;
                5'd23: cn_pixel = 8'h27;
                5'd24: cn_pixel = 8'h44;
                5'd25: cn_pixel = 8'h45;
                5'd26: cn_pixel = 8'h45;
                5'd27: cn_pixel = 8'h5F;
                5'd28: cn_pixel = 8'h45;
                5'd29: cn_pixel = 8'h45;
                5'd30: cn_pixel = 8'h44;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        6'd46: begin // 盘
            case (cn_byte)
                5'd0: cn_pixel = 8'h20;
                5'd1: cn_pixel = 8'h20;
                5'd2: cn_pixel = 8'h20;
                5'd3: cn_pixel = 8'hFC;
                5'd4: cn_pixel = 8'h24;
                5'd5: cn_pixel = 8'h26;
                5'd6: cn_pixel = 8'hA5;
                5'd7: cn_pixel = 8'h2C;
                5'd8: cn_pixel = 8'h34;
                5'd9: cn_pixel = 8'h24;
                5'd10: cn_pixel = 8'h24;
                5'd11: cn_pixel = 8'hFC;
                5'd12: cn_pixel = 8'h20;
                5'd13: cn_pixel = 8'h20;
                5'd14: cn_pixel = 8'h20;
                5'd15: cn_pixel = 8'h00;
                5'd16: cn_pixel = 8'h40;
                5'd17: cn_pixel = 8'h42;
                5'd18: cn_pixel = 8'h7D;
                5'd19: cn_pixel = 8'h44;
                5'd20: cn_pixel = 8'h44;
                5'd21: cn_pixel = 8'h7C;
                5'd22: cn_pixel = 8'h44;
                5'd23: cn_pixel = 8'h45;
                5'd24: cn_pixel = 8'h44;
                5'd25: cn_pixel = 8'h7D;
                5'd26: cn_pixel = 8'h46;
                5'd27: cn_pixel = 8'h45;
                5'd28: cn_pixel = 8'h7C;
                5'd29: cn_pixel = 8'h40;
                5'd30: cn_pixel = 8'h40;
                5'd31: cn_pixel = 8'h00;
                default: cn_pixel = 8'h00;
            endcase
        end
        default: cn_pixel = 8'h00;
    endcase
end

// 8x16 ASCII 字模查找表
always @(*) begin
    case (asc_code)
        5'd0: begin // '0'
            case (asc_byte)
                4'd0: asc_pixel = 8'h00;
                4'd1: asc_pixel = 8'hF0;
                4'd2: asc_pixel = 8'h08;
                4'd3: asc_pixel = 8'h84;
                4'd4: asc_pixel = 8'hC4;
                4'd5: asc_pixel = 8'h44;
                4'd6: asc_pixel = 8'h28;
                4'd7: asc_pixel = 8'hF0;
                4'd8: asc_pixel = 8'h00;
                4'd9: asc_pixel = 8'h03;
                4'd10: asc_pixel = 8'h05;
                4'd11: asc_pixel = 8'h08;
                4'd12: asc_pixel = 8'h08;
                4'd13: asc_pixel = 8'h08;
                4'd14: asc_pixel = 8'h04;
                4'd15: asc_pixel = 8'h03;
                default: asc_pixel = 8'h00;
            endcase
        end
        5'd1: begin // '1'
            case (asc_byte)
                4'd0: asc_pixel = 8'h00;
                4'd1: asc_pixel = 8'h10;
                4'd2: asc_pixel = 8'h08;
                4'd3: asc_pixel = 8'h04;
                4'd4: asc_pixel = 8'hFC;
                4'd5: asc_pixel = 8'h00;
                4'd6: asc_pixel = 8'h00;
                4'd7: asc_pixel = 8'h00;
                4'd8: asc_pixel = 8'h00;
                4'd9: asc_pixel = 8'h08;
                4'd10: asc_pixel = 8'h08;
                4'd11: asc_pixel = 8'h08;
                4'd12: asc_pixel = 8'h0F;
                4'd13: asc_pixel = 8'h08;
                4'd14: asc_pixel = 8'h08;
                4'd15: asc_pixel = 8'h08;
                default: asc_pixel = 8'h00;
            endcase
        end
        5'd2: begin // '2'
            case (asc_byte)
                4'd0: asc_pixel = 8'h00;
                4'd1: asc_pixel = 8'h08;
                4'd2: asc_pixel = 8'h04;
                4'd3: asc_pixel = 8'h04;
                4'd4: asc_pixel = 8'h04;
                4'd5: asc_pixel = 8'h8C;
                4'd6: asc_pixel = 8'h78;
                4'd7: asc_pixel = 8'h00;
                4'd8: asc_pixel = 8'h00;
                4'd9: asc_pixel = 8'h08;
                4'd10: asc_pixel = 8'h0C;
                4'd11: asc_pixel = 8'h0A;
                4'd12: asc_pixel = 8'h09;
                4'd13: asc_pixel = 8'h08;
                4'd14: asc_pixel = 8'h08;
                4'd15: asc_pixel = 8'h08;
                default: asc_pixel = 8'h00;
            endcase
        end
        5'd3: begin // '3'
            case (asc_byte)
                4'd0: asc_pixel = 8'h00;
                4'd1: asc_pixel = 8'h04;
                4'd2: asc_pixel = 8'h44;
                4'd3: asc_pixel = 8'h44;
                4'd4: asc_pixel = 8'h44;
                4'd5: asc_pixel = 8'hE4;
                4'd6: asc_pixel = 8'hB8;
                4'd7: asc_pixel = 8'h00;
                4'd8: asc_pixel = 8'h00;
                4'd9: asc_pixel = 8'h08;
                4'd10: asc_pixel = 8'h08;
                4'd11: asc_pixel = 8'h08;
                4'd12: asc_pixel = 8'h08;
                4'd13: asc_pixel = 8'h04;
                4'd14: asc_pixel = 8'h03;
                4'd15: asc_pixel = 8'h00;
                default: asc_pixel = 8'h00;
            endcase
        end
        5'd4: begin // '4'
            case (asc_byte)
                4'd0: asc_pixel = 8'h00;
                4'd1: asc_pixel = 8'h80;
                4'd2: asc_pixel = 8'h60;
                4'd3: asc_pixel = 8'h38;
                4'd4: asc_pixel = 8'h0C;
                4'd5: asc_pixel = 8'hFC;
                4'd6: asc_pixel = 8'h00;
                4'd7: asc_pixel = 8'h00;
                4'd8: asc_pixel = 8'h03;
                4'd9: asc_pixel = 8'h03;
                4'd10: asc_pixel = 8'h02;
                4'd11: asc_pixel = 8'h02;
                4'd12: asc_pixel = 8'h02;
                4'd13: asc_pixel = 8'h0F;
                4'd14: asc_pixel = 8'h02;
                4'd15: asc_pixel = 8'h02;
                default: asc_pixel = 8'h00;
            endcase
        end
        5'd5: begin // '5'
            case (asc_byte)
                4'd0: asc_pixel = 8'h00;
                4'd1: asc_pixel = 8'h7C;
                4'd2: asc_pixel = 8'h44;
                4'd3: asc_pixel = 8'h44;
                4'd4: asc_pixel = 8'h44;
                4'd5: asc_pixel = 8'hC4;
                4'd6: asc_pixel = 8'h80;
                4'd7: asc_pixel = 8'h00;
                4'd8: asc_pixel = 8'h00;
                4'd9: asc_pixel = 8'h08;
                4'd10: asc_pixel = 8'h08;
                4'd11: asc_pixel = 8'h08;
                4'd12: asc_pixel = 8'h08;
                4'd13: asc_pixel = 8'h04;
                4'd14: asc_pixel = 8'h03;
                4'd15: asc_pixel = 8'h00;
                default: asc_pixel = 8'h00;
            endcase
        end
        5'd6: begin // '6'
            case (asc_byte)
                4'd0: asc_pixel = 8'h00;
                4'd1: asc_pixel = 8'hE0;
                4'd2: asc_pixel = 8'h98;
                4'd3: asc_pixel = 8'h4C;
                4'd4: asc_pixel = 8'h44;
                4'd5: asc_pixel = 8'h44;
                4'd6: asc_pixel = 8'hC4;
                4'd7: asc_pixel = 8'h80;
                4'd8: asc_pixel = 8'h00;
                4'd9: asc_pixel = 8'h03;
                4'd10: asc_pixel = 8'h04;
                4'd11: asc_pixel = 8'h08;
                4'd12: asc_pixel = 8'h08;
                4'd13: asc_pixel = 8'h08;
                4'd14: asc_pixel = 8'h04;
                4'd15: asc_pixel = 8'h07;
                default: asc_pixel = 8'h00;
            endcase
        end
        5'd7: begin // '7'
            case (asc_byte)
                4'd0: asc_pixel = 8'h00;
                4'd1: asc_pixel = 8'h04;
                4'd2: asc_pixel = 8'h04;
                4'd3: asc_pixel = 8'h04;
                4'd4: asc_pixel = 8'h84;
                4'd5: asc_pixel = 8'hE4;
                4'd6: asc_pixel = 8'h3C;
                4'd7: asc_pixel = 8'h0C;
                4'd8: asc_pixel = 8'h00;
                4'd9: asc_pixel = 8'h00;
                4'd10: asc_pixel = 8'h08;
                4'd11: asc_pixel = 8'h0E;
                4'd12: asc_pixel = 8'h03;
                4'd13: asc_pixel = 8'h00;
                4'd14: asc_pixel = 8'h00;
                4'd15: asc_pixel = 8'h00;
                default: asc_pixel = 8'h00;
            endcase
        end
        5'd8: begin // '8'
            case (asc_byte)
                4'd0: asc_pixel = 8'h00;
                4'd1: asc_pixel = 8'h38;
                4'd2: asc_pixel = 8'hA4;
                4'd3: asc_pixel = 8'h44;
                4'd4: asc_pixel = 8'h44;
                4'd5: asc_pixel = 8'hA4;
                4'd6: asc_pixel = 8'h38;
                4'd7: asc_pixel = 8'h00;
                4'd8: asc_pixel = 8'h00;
                4'd9: asc_pixel = 8'h07;
                4'd10: asc_pixel = 8'h08;
                4'd11: asc_pixel = 8'h08;
                4'd12: asc_pixel = 8'h08;
                4'd13: asc_pixel = 8'h08;
                4'd14: asc_pixel = 8'h07;
                4'd15: asc_pixel = 8'h00;
                default: asc_pixel = 8'h00;
            endcase
        end
        5'd9: begin // '9'
            case (asc_byte)
                4'd0: asc_pixel = 8'h00;
                4'd1: asc_pixel = 8'h78;
                4'd2: asc_pixel = 8'hC8;
                4'd3: asc_pixel = 8'h84;
                4'd4: asc_pixel = 8'h84;
                4'd5: asc_pixel = 8'h84;
                4'd6: asc_pixel = 8'h48;
                4'd7: asc_pixel = 8'hF0;
                4'd8: asc_pixel = 8'h00;
                4'd9: asc_pixel = 8'h00;
                4'd10: asc_pixel = 8'h08;
                4'd11: asc_pixel = 8'h08;
                4'd12: asc_pixel = 8'h08;
                4'd13: asc_pixel = 8'h0C;
                4'd14: asc_pixel = 8'h06;
                4'd15: asc_pixel = 8'h01;
                default: asc_pixel = 8'h00;
            endcase
        end
        5'd10: begin // ':'
            case (asc_byte)
                4'd0: asc_pixel = 8'h00;
                4'd1: asc_pixel = 8'h00;
                4'd2: asc_pixel = 8'h00;
                4'd3: asc_pixel = 8'h60;
                4'd4: asc_pixel = 8'h60;
                4'd5: asc_pixel = 8'h00;
                4'd6: asc_pixel = 8'h00;
                4'd7: asc_pixel = 8'h00;
                4'd8: asc_pixel = 8'h00;
                4'd9: asc_pixel = 8'h00;
                4'd10: asc_pixel = 8'h00;
                4'd11: asc_pixel = 8'h0C;
                4'd12: asc_pixel = 8'h0C;
                4'd13: asc_pixel = 8'h00;
                4'd14: asc_pixel = 8'h00;
                4'd15: asc_pixel = 8'h00;
                default: asc_pixel = 8'h00;
            endcase
        end
        5'd11: begin // '-'
            case (asc_byte)
                4'd0: asc_pixel = 8'h00;
                4'd1: asc_pixel = 8'h00;
                4'd2: asc_pixel = 8'h80;
                4'd3: asc_pixel = 8'h80;
                4'd4: asc_pixel = 8'h80;
                4'd5: asc_pixel = 8'h80;
                4'd6: asc_pixel = 8'h80;
                4'd7: asc_pixel = 8'h00;
                4'd8: asc_pixel = 8'h00;
                4'd9: asc_pixel = 8'h00;
                4'd10: asc_pixel = 8'h00;
                4'd11: asc_pixel = 8'h00;
                4'd12: asc_pixel = 8'h00;
                4'd13: asc_pixel = 8'h00;
                4'd14: asc_pixel = 8'h00;
                4'd15: asc_pixel = 8'h00;
                default: asc_pixel = 8'h00;
            endcase
        end
        5'd12: begin // '['
            case (asc_byte)
                4'd0: asc_pixel = 8'h00;
                4'd1: asc_pixel = 8'h00;
                4'd2: asc_pixel = 8'h00;
                4'd3: asc_pixel = 8'hFE;
                4'd4: asc_pixel = 8'h02;
                4'd5: asc_pixel = 8'h02;
                4'd6: asc_pixel = 8'h02;
                4'd7: asc_pixel = 8'h00;
                4'd8: asc_pixel = 8'h00;
                4'd9: asc_pixel = 8'h00;
                4'd10: asc_pixel = 8'h00;
                4'd11: asc_pixel = 8'h7F;
                4'd12: asc_pixel = 8'h40;
                4'd13: asc_pixel = 8'h40;
                4'd14: asc_pixel = 8'h40;
                4'd15: asc_pixel = 8'h00;
                default: asc_pixel = 8'h00;
            endcase
        end
        5'd13: begin // ']'
            case (asc_byte)
                4'd0: asc_pixel = 8'h00;
                4'd1: asc_pixel = 8'h00;
                4'd2: asc_pixel = 8'h02;
                4'd3: asc_pixel = 8'h02;
                4'd4: asc_pixel = 8'h02;
                4'd5: asc_pixel = 8'hFE;
                4'd6: asc_pixel = 8'h00;
                4'd7: asc_pixel = 8'h00;
                4'd8: asc_pixel = 8'h00;
                4'd9: asc_pixel = 8'h00;
                4'd10: asc_pixel = 8'h40;
                4'd11: asc_pixel = 8'h40;
                4'd12: asc_pixel = 8'h40;
                4'd13: asc_pixel = 8'h7F;
                4'd14: asc_pixel = 8'h00;
                4'd15: asc_pixel = 8'h00;
                default: asc_pixel = 8'h00;
            endcase
        end
        5'd14: begin // '*'
            case (asc_byte)
                4'd0: asc_pixel = 8'h00;
                4'd1: asc_pixel = 8'h44;
                4'd2: asc_pixel = 8'h28;
                4'd3: asc_pixel = 8'h28;
                4'd4: asc_pixel = 8'hFE;
                4'd5: asc_pixel = 8'h28;
                4'd6: asc_pixel = 8'h28;
                4'd7: asc_pixel = 8'h44;
                4'd8: asc_pixel = 8'h00;
                4'd9: asc_pixel = 8'h00;
                4'd10: asc_pixel = 8'h00;
                4'd11: asc_pixel = 8'h00;
                4'd12: asc_pixel = 8'h00;
                4'd13: asc_pixel = 8'h00;
                4'd14: asc_pixel = 8'h00;
                4'd15: asc_pixel = 8'h00;
                default: asc_pixel = 8'h00;
            endcase
        end
        5'd15: begin // '#'
            case (asc_byte)
                4'd0: asc_pixel = 8'h20;
                4'd1: asc_pixel = 8'hA0;
                4'd2: asc_pixel = 8'h7C;
                4'd3: asc_pixel = 8'h20;
                4'd4: asc_pixel = 8'h20;
                4'd5: asc_pixel = 8'hA0;
                4'd6: asc_pixel = 8'h7C;
                4'd7: asc_pixel = 8'h20;
                4'd8: asc_pixel = 8'h01;
                4'd9: asc_pixel = 8'h0F;
                4'd10: asc_pixel = 8'h01;
                4'd11: asc_pixel = 8'h01;
                4'd12: asc_pixel = 8'h01;
                4'd13: asc_pixel = 8'h0F;
                4'd14: asc_pixel = 8'h01;
                4'd15: asc_pixel = 8'h01;
                default: asc_pixel = 8'h00;
            endcase
        end
        5'd16: begin // 'space'
            case (asc_byte)
                4'd0: asc_pixel = 8'h00;
                4'd1: asc_pixel = 8'h00;
                4'd2: asc_pixel = 8'h00;
                4'd3: asc_pixel = 8'h00;
                4'd4: asc_pixel = 8'h00;
                4'd5: asc_pixel = 8'h00;
                4'd6: asc_pixel = 8'h00;
                4'd7: asc_pixel = 8'h00;
                4'd8: asc_pixel = 8'h00;
                4'd9: asc_pixel = 8'h00;
                4'd10: asc_pixel = 8'h00;
                4'd11: asc_pixel = 8'h00;
                4'd12: asc_pixel = 8'h00;
                4'd13: asc_pixel = 8'h00;
                4'd14: asc_pixel = 8'h00;
                4'd15: asc_pixel = 8'h00;
                default: asc_pixel = 8'h00;
            endcase
        end
        default: asc_pixel = 8'h00;
    endcase
end

endmodule
