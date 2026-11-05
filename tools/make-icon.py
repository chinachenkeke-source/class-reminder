#!/usr/bin/env python3
"""生成上课提醒的 App 图标：蓝渐变 + 立体白表盘（10:10）+ 琥珀提醒点。

用法：make-icon.py [输出 png] [iconset 目录]

注意两个坑：
1. 图标必须铺满画布、且不能带 alpha —— 否则 macOS 26 会当旧版图标，垫一层灰底板；
2. README 用的是带圆角的 AppIcon-rounded.png，圆角只能在展示版里画。
"""
from PIL import Image, ImageDraw, ImageFilter
import math
import os
import sys

S = 1024
OUT = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png"
SETDIR = sys.argv[2] if len(sys.argv) > 2 else None

TOP, BOT = (86, 148, 255), (26, 70, 198)      # 蓝渐变
AMBER = (255, 157, 10)                        # 提醒点


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


# 1) 背景：铺满画布的渐变
img = Image.new("RGB", (S, S))
d = ImageDraw.Draw(img)
for i in range(2 * S):
    d.line([(0, i), (i, 0)], fill=lerp(TOP, BOT, i / (2 * S - 1)), width=3)
icon = img.convert("RGBA")

cx, cy = S // 2, int(S * 0.495)
R = int(S * 0.295)
ring = int(S * 0.046)

# 2) 表盘的投影，让白圈有一点厚度
sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(sh).ellipse(
    [cx - R - ring // 2, cy - R - ring // 2 + int(S * 0.012),
     cx + R + ring // 2, cy + R + ring // 2 + int(S * 0.018)],
    outline=(8, 28, 78, 110), width=ring + int(S * 0.012))
icon = Image.alpha_composite(icon, sh.filter(ImageFilter.GaussianBlur(18)))

d = ImageDraw.Draw(icon)
d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=(255, 255, 255, 255), width=ring)

# 3) 刻度
for k in range(12):
    a = math.radians(k * 30)
    long = k % 3 == 0
    r1 = R - ring
    r2 = r1 - (int(S * 0.050) if long else int(S * 0.028))
    d.line([cx + r1 * math.sin(a), cy - r1 * math.cos(a),
            cx + r2 * math.sin(a), cy - r2 * math.cos(a)],
           fill=(255, 255, 255, 190),
           width=int(S * 0.013) if long else int(S * 0.007))


# 4) 指针（10:10，带过中心的小尾巴，才看得出是钟）
def hand(deg, length, width, tail):
    a = math.radians(deg)
    x1, y1 = cx + length * math.sin(a), cy - length * math.cos(a)
    x0, y0 = cx - tail * math.sin(a), cy + tail * math.cos(a)
    d.line([x0, y0, x1, y1], fill=(255, 255, 255, 255), width=width)
    d.ellipse([x1 - width / 2, y1 - width / 2, x1 + width / 2, y1 + width / 2],
              fill=(255, 255, 255, 255))


hand((10 + 10 / 60) / 12 * 360, R * 0.50, int(S * 0.042), int(S * 0.035))
hand(10 / 60 * 360, R * 0.76, int(S * 0.028), int(S * 0.030))
d.ellipse([cx - int(S * 0.022), cy - int(S * 0.022),
           cx + int(S * 0.022), cy + int(S * 0.022)], fill=(255, 255, 255, 255))

# 5) 琥珀提醒点（蓝色描边把它和表盘分开）
ax, ay, ar = int(S * 0.735), int(S * 0.745), int(S * 0.064)
d.ellipse([ax - ar - int(S * 0.012), ay - ar - int(S * 0.012),
           ax + ar + int(S * 0.012), ay + ar + int(S * 0.012)], fill=(42, 96, 220, 255))
d.ellipse([ax - ar, ay - ar, ax + ar, ay + ar], fill=AMBER + (255,))
d.ellipse([ax - ar * 0.40, ay - ar * 0.40, ax + ar * 0.40, ay + ar * 0.40],
          fill=(255, 255, 255, 255))

# 6) 输出：真图标不带 alpha；展示版带圆角
icon.convert("RGB").resize((S, S), Image.LANCZOS).save(OUT)

disp = icon.resize((S, S), Image.LANCZOS)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * 0.2237), fill=255)
disp.putalpha(mask)
disp.save(os.path.splitext(OUT)[0] + "-rounded.png")

print("saved", OUT)

if SETDIR:
    os.makedirs(SETDIR, exist_ok=True)
    flat = Image.open(OUT).convert("RGB")
    for size in [16, 32, 128, 256, 512]:   # 64 不是合法尺寸，会让 iconutil 报 Invalid
        flat.resize((size, size), Image.LANCZOS).save(f"{SETDIR}/icon_{size}x{size}.png")
        flat.resize((size * 2, size * 2), Image.LANCZOS).save(f"{SETDIR}/icon_{size}x{size}@2x.png")
    # 1024（512@2x）是必须的，少一个 iconutil 就报 Invalid Iconset
    flat.resize((1024, 1024), Image.LANCZOS).save(f"{SETDIR}/icon_512x512@2x.png")
    print("iconset:", SETDIR)
