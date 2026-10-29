import PIL.Image
import PIL.ImageDraw
import PIL.ImageFont
import os

base_img = PIL.Image.open('docs/DMZ_EG4S20_Official_Pinout.png').convert('RGBA')
bw, bh = base_img.size

canvas_w = bw + 200
canvas_h = bh + 630
canvas = PIL.Image.new('RGBA', (canvas_w, canvas_h), (248, 250, 252, 255))

board_x, board_y = 100, 110
canvas.paste(base_img, (board_x, board_y))

draw = PIL.ImageDraw.Draw(canvas)

font_paths = [
    r"C:\Windows\Fonts\msyhbd.ttc",
    r"C:\Windows\Fonts\msyh.ttc",
    r"C:\Windows\Fonts\simhei.ttf",
]
font_path = next((p for p in font_paths if os.path.exists(p)), None)
font_path_reg = next((p for p in [r"C:\Windows\Fonts\msyh.ttc", r"C:\Windows\Fonts\simhei.ttf"] if os.path.exists(p)), font_path)

def get_font(size, bold=False):
    p = font_path if bold else font_path_reg
    if p:
        return PIL.ImageFont.truetype(p, size)
    return PIL.ImageFont.load_default()

f_title = get_font(34, True)
f_sub = get_font(20, False)
f_box_title = get_font(21, True)
f_text = get_font(17, False)
f_text_b = get_font(17, True)
f_small = get_font(15, True)

# Title Banner
draw.rectangle([0, 0, canvas_w, 95], fill=(15, 23, 42, 255))
draw.text((40, 16), "硬木课堂 DMZ-EG4S20 密码箱全硬件直观接线图 (下方 P4 排母偶数排)", fill=(255, 255, 255), font=f_title)
draw.text((40, 60), "核心提示：所有外接模块统一插在下方排母 P4 最底下一行（偶数号 2 ~ 60） | 右下角 UART2USB 一线直连电脑（无需 USB-TTL 模块）", fill=(148, 163, 184), font=f_sub)

# Exact 31 vertical grid borders of the 30 columns (Pin 2 to Pin 60) in base_img
BORDERS = [212, 257, 298, 339, 381, 422, 463, 504, 545, 587, 628, 667, 707, 743, 779, 821, 862, 898, 933, 969, 1007, 1044, 1086, 1127, 1165, 1202, 1237, 1275, 1313, 1354, 1390]

pin_row2_y_top = board_y + 952
pin_row2_y_bot = board_y + 1047

def pin_center_x(even_pin_num):
    idx = (even_pin_num // 2) - 1  # 0 to 29
    return board_x + (BORDERS[idx] + BORDERS[idx + 1]) // 2

def draw_pin_highlight(pin_start, pin_end, color_rgba, border_color):
    idx1 = (pin_start // 2) - 1
    idx2 = (pin_end // 2) - 1
    x1 = board_x + BORDERS[idx1]
    x2 = board_x + BORDERS[idx2 + 1]
    y1 = pin_row2_y_top
    y2 = pin_row2_y_bot
    
    overlay = PIL.Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    odraw = PIL.ImageDraw.Draw(overlay)
    odraw.rectangle([x1, y1, x2, y2], fill=color_rgba, outline=border_color, width=4)
    canvas.alpha_composite(overlay)
    return (x1 + x2) // 2, y2

# 1. Highlight SG90 Servo: P4-2, 4, 6 (VBUS, GND, M11)
cx_servo, by_servo = draw_pin_highlight(2, 6, (239, 68, 68, 75), (220, 38, 38, 255))

# 2. Highlight 4x4 Keypad: P4-8 to 22 (L12, P15, P16, N14, N16, M16, L16, P14)
cx_keypad, by_keypad = draw_pin_highlight(8, 22, (16, 185, 129, 75), (5, 150, 105, 255))

# 3. Highlight JQ8900 Voice: P4-42, 44, 46 (G16, GND, H16)
cx_voice, by_voice = draw_pin_highlight(42, 46, (168, 85, 247, 75), (147, 51, 234, 255))

# 4. Highlight 0.96 OLED: P4-54, 56, 58, 60 (D14, E15, GND, 3V3)
cx_oled, by_oled = draw_pin_highlight(54, 60, (59, 130, 246, 75), (37, 99, 235, 255))

# Re-acquire draw after alpha_composite
draw = PIL.ImageDraw.Draw(canvas)

# 5. Highlight Onboard UART: Bottom right box
uart_x1, uart_y1 = board_x + 1405, board_y + 755
uart_x2, uart_y2 = board_x + 1542, board_y + 885
draw.rectangle([uart_x1, uart_y1, uart_x2, uart_y2], outline=(234, 88, 12, 255), width=5)

cards_y = 1275
card_h = 375

# --- CARD 1: SG90 舵机 (3联排) ---
c1_x1, c1_x2 = 35, 410
draw.rounded_rectangle([c1_x1, cards_y, c1_x2, cards_y + card_h], radius=16, fill=(255, 255, 255), outline=(220, 38, 38), width=3)
draw.rounded_rectangle([c1_x1, cards_y, c1_x2, cards_y + 52], radius=16, fill=(220, 38, 38))
draw.rectangle([c1_x1, cards_y + 30, c1_x2, cards_y + 52], fill=(220, 38, 38))
draw.text((c1_x1 + 18, cards_y + 12), "1. SG90 舵机 (3针联排)", fill=(255, 255, 255), font=f_box_title)

c1_lines = [
    ("位置：", "P4 左下角前 3 针 (Pin 2, 4, 6)", (15, 23, 42), True),
    ("P4-2 (VBUS)", "-> 红线 (5V 电源正)", (220, 38, 38), True),
    ("P4-4 (GND)", "-> 棕/黑线 (GND 地)", (71, 85, 105), True),
    ("P4-6 (M11)", "-> 黄/橙线 (PWM 信号)", (217, 119, 6), True),
    ("注意：", "标准舵机母头中间是红线(5V)，", (100, 116, 139), False),
    ("", "请把红/棕端子挑出互换后直插！", (220, 38, 38), True),
]
yy = cards_y + 68
for k, v, col, is_b in c1_lines:
    draw.text((c1_x1 + 18, yy), k, fill=(51, 65, 85), font=f_text_b if is_b else f_text)
    draw.text((c1_x1 + 132 if k else c1_x1 + 18, yy), v, fill=col, font=f_text_b if is_b else f_text)
    yy += 42

for p_num, wire_col in [(2, (220, 38, 38)), (4, (51, 65, 85)), (6, (217, 119, 6))]:
    px = pin_center_x(p_num)
    draw.line([(px, by_servo), (px, by_servo + 45), (c1_x1 + 150 + (p_num - 2)*28, cards_y)], fill=wire_col, width=4)
    draw.ellipse([px - 5, by_servo - 5, px + 5, by_servo + 5], fill=wire_col)


# --- CARD 2: 4x4 矩阵薄膜键盘 (8联排) ---
c2_x1, c2_x2 = 430, 920
draw.rounded_rectangle([c2_x1, cards_y, c2_x2, cards_y + card_h], radius=16, fill=(255, 255, 255), outline=(5, 150, 105), width=3)
draw.rounded_rectangle([c2_x1, cards_y, c2_x2, cards_y + 52], radius=16, fill=(5, 150, 105))
draw.rectangle([c2_x1, cards_y + 30, c2_x2, cards_y + 52], fill=(5, 150, 105))
draw.text((c2_x1 + 18, cards_y + 12), "2. 4x4 薄膜键盘 (8针联排免飞线直插)", fill=(255, 255, 255), font=f_box_title)

c2_lines = [
    ("位置：", "紧挨舵机往右连续 8 针 (Pin 8 ~ 22)", (5, 150, 105), True),
    ("Pin 1~4 (行)", "-> P4-8(L12), 10(P15), 12(P16), 14(N14)", (15, 23, 42), True),
    ("Pin 5~8 (列)", "-> P4-16(N16), 18(M16), 20(L16), 22(P14)", (15, 23, 42), True),
    ("插法：", "拿一排 8P 公对公/母对公杜邦线，", (71, 85, 105), False),
    ("", "键盘扁平排线从左到右 (Pin 1~8)", (71, 85, 105), False),
    ("", "不跳线、不交叉，整排顺次插 8~22！", (5, 150, 105), True),
]
yy = cards_y + 68
for k, v, col, is_b in c2_lines:
    draw.text((c2_x1 + 16, yy), k, fill=(51, 65, 85), font=f_text_b if is_b else f_text)
    draw.text((c2_x1 + 132 if k else c2_x1 + 16, yy), v, fill=col, font=f_text_b if is_b else f_text)
    yy += 42

for idx, p_num in enumerate(range(8, 24, 2)):
    px = pin_center_x(p_num)
    col = (16, 185, 129) if idx < 4 else (5, 150, 105)
    target_x = c2_x1 + 140 + idx * 30
    draw.line([(px, by_keypad), (px, by_keypad + 35 + idx*4), (target_x, cards_y)], fill=col, width=3)
    draw.ellipse([px - 4, by_keypad - 4, px + 4, by_keypad + 4], fill=col)


# --- CARD 3: JQ8900 语音模块 (3联排) ---
c3_x1, c3_x2 = 940, 1265
draw.rounded_rectangle([c3_x1, cards_y, c3_x2, cards_y + card_h], radius=16, fill=(255, 255, 255), outline=(147, 51, 234), width=3)
draw.rounded_rectangle([c3_x1, cards_y, c3_x2, cards_y + 52], radius=16, fill=(147, 51, 234))
draw.rectangle([c3_x1, cards_y + 30, c3_x2, cards_y + 52], fill=(147, 51, 234))
draw.text((c3_x1 + 16, cards_y + 12), "3. JQ8900 语音 (3针)", fill=(255, 255, 255), font=f_box_title)

c3_lines = [
    ("位置：", "P4 中右段 (42, 44, 46)", (147, 51, 234), True),
    ("P4-42 (G16)", "-> BUSY (忙检测)", (15, 23, 42), True),
    ("P4-44 (GND)", "-> GND (共地)", (71, 85, 105), True),
    ("P4-46 (H16)", "-> IO1/RX (单线串口)", (147, 51, 234), True),
    ("供电：", "模块 V5V 接独立 5V", (100, 116, 139), False),
    ("", "或板载 5V (VBUS)", (100, 116, 139), False),
]
yy = cards_y + 68
for k, v, col, is_b in c3_lines:
    draw.text((c3_x1 + 16, yy), k, fill=(51, 65, 85), font=f_text_b if is_b else f_text)
    draw.text((c3_x1 + 125 if k else c3_x1 + 16, yy), v, fill=col, font=f_text_b if is_b else f_text)
    yy += 42

for idx, p_num in enumerate([42, 44, 46]):
    px = pin_center_x(p_num)
    draw.line([(px, by_voice), (px, by_voice + 50), (c3_x1 + 115 + idx*40, cards_y)], fill=(147, 51, 234), width=3)
    draw.ellipse([px - 4, by_voice - 4, px + 4, by_voice + 4], fill=(147, 51, 234))


# --- CARD 4: 0.96寸 OLED (GND-VCC-SCL-SDA 专属线序) ---
c4_x1, c4_x2 = 1285, 1715
draw.rounded_rectangle([c4_x1, cards_y, c4_x2, cards_y + card_h], radius=16, fill=(255, 255, 255), outline=(37, 99, 235), width=3)
draw.rounded_rectangle([c4_x1, cards_y, c4_x2, cards_y + 52], radius=16, fill=(37, 99, 235))
draw.rectangle([c4_x1, cards_y + 30, c4_x2, cards_y + 52], fill=(37, 99, 235))
draw.text((c4_x1 + 16, cards_y + 12), "4. 0.96寸 OLED (GND-VCC-SCL-SDA)", fill=(255, 255, 255), font=f_box_title)

c4_lines = [
    ("位置：", "P4 最右侧末端 4 针 (54,56,58,60)", (37, 99, 235), True),
    ("OLED [SDA]", "-> 插 P4-54 (D14 数据)", (16, 185, 129), True),
    ("OLED [SCL]", "-> 插 P4-56 (E15 时钟)", (217, 119, 6), True),
    ("OLED [VCC]", "-> 插 P4-60 (3V3 电源正)", (220, 38, 38), True),
    ("OLED [GND]", "-> 插 P4-58 (GND 电源地)", (51, 65, 85), True),
    ("要领：", "SCL/SDA 直插 56/54；仅需把", (220, 38, 38), True),
    ("", "GND 与 VCC 两根线交叉插 58/60！", (220, 38, 38), True),
]
yy = cards_y + 66
for k, v, col, is_b in c4_lines:
    draw.text((c4_x1 + 16, yy), k, fill=(51, 65, 85), font=f_text_b if is_b else f_text)
    draw.text((c4_x1 + 130 if k else c4_x1 + 16, yy), v, fill=col, font=f_text_b if is_b else f_text)
    yy += 39

oled_wires = [
    (54, c4_x1 + 85,  (16, 185, 129), "SDA"),
    (56, c4_x1 + 165, (217, 119, 6),  "SCL"),
    (58, c4_x1 + 335, (51, 65, 85),   "GND(交)"), # Crossed!
    (60, c4_x1 + 250, (220, 38, 38),  "VCC(交)"), # Crossed!
]
for p_num, target_x, col, lbl in oled_wires:
    px = pin_center_x(p_num)
    draw.line([(px, by_oled), (px, by_oled + 35), (target_x, cards_y - 28), (target_x, cards_y)], fill=col, width=4)
    draw.ellipse([px - 5, by_oled - 5, px + 5, by_oled + 5], fill=col)
    draw.text((target_x - 24, cards_y - 26), lbl, fill=col, font=f_small)

out_path = 'docs/Hardware_Wiring_Guide.png'
canvas.convert('RGB').save(out_path, quality=95)
print("Saved", out_path, canvas.size)
