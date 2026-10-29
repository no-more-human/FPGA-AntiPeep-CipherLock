import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

wb = openpyxl.Workbook()

# Sheet 1: 核心联排引脚与接线表 (外接模块免飞线联排直插)
ws1 = wb.active
ws1.title = "外接模块联排接线表"

headers1 = [
    "外设模块", "模块引脚", "FPGA管脚", "开发板排母位置", 
    "电平标准", "联排定义与线序说明", "免飞线直插建议"
]

data1 = [
    ["SG90 舵机 (3联排)", "红线 (VCC 5V)", "板载 5V", "P4排母-Pin 2", "5V 供电", "电源正极 (VBUS)", "3联排直插 P4-2 (5V)"],
    ["SG90 舵机 (3联排)", "棕/黑线 (GND)", "板载 GND", "P4排母-Pin 4", "地 (GND)", "电源地线", "3联排直插 P4-4 (GND)"],
    ["SG90 舵机 (3联排)", "黄/橙线 (PWM)", "M11", "P4排母-Pin 6", "LVCMOS33", "50Hz PWM 控制信号 (0.5~1.5ms)", "3联排直插 P4-6 (PWM)"],
    
    ["4x4 薄膜键盘 (8联排)", "Pin 1 (Row 0)", "L12", "P4排母-Pin 8", "LVCMOS33 (PULLUP)", "矩阵键盘行0输入 (内部弱上拉)", "8联排排线 Pin 1 直插 P4-8"],
    ["4x4 薄膜键盘 (8联排)", "Pin 2 (Row 1)", "P15", "P4排母-Pin 10", "LVCMOS33 (PULLUP)", "矩阵键盘行1输入 (内部弱上拉)", "8联排排线 Pin 2 直插 P4-10"],
    ["4x4 薄膜键盘 (8联排)", "Pin 3 (Row 2)", "P16", "P4排母-Pin 12", "LVCMOS33 (PULLUP)", "矩阵键盘行2输入 (内部弱上拉)", "8联排排线 Pin 3 直插 P4-12"],
    ["4x4 薄膜键盘 (8联排)", "Pin 4 (Row 3)", "N14", "P4排母-Pin 14", "LVCMOS33 (PULLUP)", "矩阵键盘行3输入 (内部弱上拉)", "8联排排线 Pin 4 直插 P4-14"],
    ["4x4 薄膜键盘 (8联排)", "Pin 5 (Col 0)", "N16", "P4排母-Pin 16", "LVCMOS33", "矩阵键盘列0扫描输出 (低电平选通)", "8联排排线 Pin 5 直插 P4-16"],
    ["4x4 薄膜键盘 (8联排)", "Pin 6 (Col 1)", "M16", "P4排母-Pin 18", "LVCMOS33", "矩阵键盘列1扫描输出 (低电平选通)", "8联排排线 Pin 6 直插 P4-18"],
    ["4x4 薄膜键盘 (8联排)", "Pin 7 (Col 2)", "L16", "P4排母-Pin 20", "LVCMOS33", "矩阵键盘列2扫描输出 (低电平选通)", "8联排排线 Pin 7 直插 P4-20"],
    ["4x4 薄膜键盘 (8联排)", "Pin 8 (Col 3)", "P14", "P4排母-Pin 22", "LVCMOS33", "矩阵键盘列3扫描输出 (低电平选通)", "8联排排线 Pin 8 直插 P4-22"],
    
    ["0.96寸 OLED (4联排)", "SDA (数据)", "D14", "P4排母-Pin 54", "LVCMOS33 (PULLUP)", "I2C 双向数据线 (开漏三态+弱上拉)", "4联排直插 P4-54 (SDA)"],
    ["0.96寸 OLED (4联排)", "SCL (时钟)", "E15", "P4排母-Pin 56", "LVCMOS33 (PULLUP)", "I2C 时钟线 (驱动输出)", "4联排直插 P4-56 (SCL)"],
    ["0.96寸 OLED (4联排)", "GND (电源地)", "板载 GND", "P4排母-Pin 58", "地 (GND)", "模块电源负极", "4联排直插 P4-58 (GND)"],
    ["0.96寸 OLED (4联排)", "VCC (电源正)", "板载 3.3V", "P4排母-Pin 60", "3.3V 供电", "模块电源正极 (严禁接5V)", "4联排直插 P4-60 (3V3)"],

    ["JQ8900 语音 (3联排)", "BUSY (忙状态)", "G16", "P4排母-Pin 42", "LVCMOS33 (PULLUP)", "播报忙状态检测 (高阻/上拉)", "3联排直插 P4-42 (BUSY)"],
    ["JQ8900 语音 (3联排)", "GND (电源地)", "板载 GND", "P4排母-Pin 44", "地 (GND)", "模块电源负极", "3联排直插 P4-44 (GND)"],
    ["JQ8900 语音 (3联排)", "TX (单线通信)", "H16", "P4排母-Pin 46", "LVCMOS33", "One-Line 单线串口控制", "3联排直插 P4-46 (TX)"],

    ["板载 UART2USB 串口", "FPGA TX (发)", "D12", "板载 Type-C/Micro", "LVCMOS33", "FPGA 发送给板载 CH340 RXD", "免外接TTL！一根USB线直插右下角UART2USB口"],
    ["板载 UART2USB 串口", "FPGA RX (收)", "F12", "板载 Type-C/Micro", "LVCMOS33 (PULLUP)", "FPGA 接收板载 CH340 TXD", "免外接TTL！上位机打开对应COM口(115200)"]
]

ws1.append(headers1)
for r in data1:
    ws1.append(r)

# Sheet 2: 板载全部硬件资源映射表
ws2 = wb.create_sheet(title="板载全硬件引脚表")
headers2 = ["外设分类", "信号名称 (Verilog)", "FPGA管脚", "IO电平标准", "有效电平 / 属性", "硬件物理标号 / 说明"]
data2 = [
    ["全局时钟", "clk_50M", "R7", "LVCMOS33", "50MHz", "板载高精度有源晶振 Y3"],
    ["系统复位", "rst_n", "E3", "LVCMOS33", "低电平有效 (PULLUP)", "板载独立轻触按键 KEY1 / RSTn"],
    ["蜂鸣器", "buzzer_out", "H11", "LVCMOS33", "PWM 驱动", "板载无源蜂鸣器 (BUZZER1)"],
    
    ["板载LED", "led[0]", "B14", "LVCMOS33", "高电平点亮", "板载第1组 LED D0"],
    ["板载LED", "led[1]", "B15", "LVCMOS33", "高电平点亮", "板载第1组 LED D1"],
    ["板载LED", "led[2]", "B16", "LVCMOS33", "高电平点亮", "板载第1组 LED D2"],
    ["板载LED", "led[3]", "C15", "LVCMOS33", "高电平点亮", "板载第1组 LED D3"],
    ["板载LED", "led[4]", "C16", "LVCMOS33", "高电平点亮", "板载第1组 LED D4"],
    ["板载LED", "led[5]", "E13", "LVCMOS33", "高电平点亮", "板载第1组 LED D5"],
    ["板载LED", "led[6]", "E16", "LVCMOS33", "高电平点亮", "板载第1组 LED D6"],
    ["板载LED", "led[7]", "F16", "LVCMOS33", "高电平点亮", "板载第1组 LED D7"],

    ["4位数码管段选", "seg_out[0]", "A4", "LVCMOS33", "高电平有效", "共阴数码管 A 段"],
    ["4位数码管段选", "seg_out[1]", "A6", "LVCMOS33", "高电平有效", "共阴数码管 B 段"],
    ["4位数码管段选", "seg_out[2]", "B8", "LVCMOS33", "高电平有效", "共阴数码管 C 段"],
    ["4位数码管段选", "seg_out[3]", "E8", "LVCMOS33", "高电平有效", "共阴数码管 D 段"],
    ["4位数码管段选", "seg_out[4]", "A7", "LVCMOS33", "高电平有效", "共阴数码管 E 段"],
    ["4位数码管段选", "seg_out[5]", "B5", "LVCMOS33", "高电平有效", "共阴数码管 F 段"],
    ["4位数码管段选", "seg_out[6]", "A8", "LVCMOS33", "高电平有效", "共阴数码管 G 段"],
    ["4位数码管段选", "seg_out[7]", "C8", "LVCMOS33", "高电平有效", "共阴数码管 DP 小数点"],

    ["4位数码管位选", "seg_cs[0]", "C9", "LVCMOS33", "低电平选通", "共阴数码管 COM1 (千位)"],
    ["4位数码管位选", "seg_cs[1]", "B6", "LVCMOS33", "低电平选通", "共阴数码管 COM2 (百位)"],
    ["4位数码管位选", "seg_cs[2]", "A5", "LVCMOS33", "低电平选通", "共阴数码管 COM3 (十位)"],
    ["4位数码管位选", "seg_cs[3]", "A3", "LVCMOS33", "低电平选通", "共阴数码管 COM4 (个位)"],

    ["拨动开关", "door_gpio / SW0", "A9", "LVCMOS33", "高电平有效 (PULLUP)", "板载拨码开关 SW0"],
    ["拨动开关", "door_gpio / SW1", "A10", "LVCMOS33", "高电平有效 (PULLUP)", "板载拨码开关 SW1 (门磁状态模拟)"],
    ["拨动开关", "SW2", "B10", "LVCMOS33", "高电平有效", "板载拨码开关 SW2"],
    ["拨动开关", "SW3", "A11", "LVCMOS33", "高电平有效", "板载拨码开关 SW3"],
    ["拨动开关", "SW4", "A12", "LVCMOS33", "高电平有效", "板载拨码开关 SW4"],
    ["拨动开关", "SW5", "B12", "LVCMOS33", "高电平有效", "板载拨码开关 SW5"],
    ["拨动开关", "SW6", "A13", "LVCMOS33", "高电平有效", "板载拨码开关 SW6"],
    ["拨动开关", "sw_recovery / SW7", "A14", "LVCMOS33", "高电平使能 (PULLDOWN)", "板载拨码开关 SW7 (紧急恢复码使能)"],

    ["板载按键(备份)", "Key_Row[0]", "E10", "LVCMOS33", "PULLUP", "板载 4x4 矩阵白色轻触按键 行0"],
    ["板载按键(备份)", "Key_Row[1]", "C10", "LVCMOS33", "PULLUP", "板载 4x4 矩阵白色轻触按键 行1"],
    ["板载按键(备份)", "Key_Row[2]", "F9", "LVCMOS33", "PULLUP", "板载 4x4 矩阵白色轻触按键 行2"],
    ["板载按键(备份)", "Key_Row[3]", "D9", "LVCMOS33", "PULLUP", "板载 4x4 矩阵白色轻触按键 行3"],
    ["板载按键(备份)", "Key_Col[0]", "E11", "LVCMOS33", "输出", "板载 4x4 矩阵白色轻触按键 列0"],
    ["板载按键(备份)", "Key_Col[1]", "D11", "LVCMOS33", "输出", "板载 4x4 矩阵白色轻触按键 列1"],
    ["板载按键(备份)", "Key_Col[2]", "C11", "LVCMOS33", "输出", "板载 4x4 矩阵白色轻触按键 列2"],
    ["板载按键(备份)", "Key_Col[3]", "F10", "LVCMOS33", "输出", "板载 4x4 矩阵白色轻触按键 列3"]
]

ws2.append(headers2)
for r in data2:
    ws2.append(r)

# 美化样式
header_fill = PatternFill(start_color="1F4E79", end_color="1F4E79", fill_type="solid")
header_font = Font(name="微软雅黑", size=11, bold=True, color="FFFFFF")
cell_font = Font(name="微软雅黑", size=10)
thin_border = Border(
    left=Side(style='thin', color='D9D9D9'),
    right=Side(style='thin', color='D9D9D9'),
    top=Side(style='thin', color='D9D9D9'),
    bottom=Side(style='thin', color='D9D9D9')
)

for ws in [ws1, ws2]:
    for col_idx, col in enumerate(ws.iter_cols(min_row=1, max_row=ws.max_row, min_col=1, max_col=ws.max_column)):
        max_len = 0
        for cell in col:
            cell.border = thin_border
            if cell.row == 1:
                cell.fill = header_fill
                cell.font = header_font
                cell.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
            else:
                cell.font = cell_font
                cell.alignment = Alignment(vertical="center")
            val_str = str(cell.value or '')
            max_len = max(max_len, len(val_str.encode('gbk', 'ignore')))
        col_letter = get_column_letter(col_idx + 1)
        ws.column_dimensions[col_letter].width = max(max_len + 4, 12)
    ws.row_dimensions[1].height = 28

wb.save('docs/EG4S20_Pinout.xlsx')
print('Successfully saved docs/EG4S20_Pinout.xlsx')
