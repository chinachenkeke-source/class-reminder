#!/usr/bin/env python3
"""生成上课提醒的 App 图标：蓝色圆角方块 + 白色时钟+ 琥珀提醒点。

用法：make-icon.py [输出 png] [iconset 目录]
"""
from PIL import Image, ImageDraw
import math, os, sys

S = 2048                      # 超采样
OUT = sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png"
SETDIR = sys.argv[2] if len(sys.argv) > 2 else None

TOP, BOT = (78, 141, 255), (26, 68, 196)


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


img = Image.new("RGB", (S, S))
d = ImageDraw.Draw(img)
for i in range(2 * S):                       # 对角渐变
    t = i / (2 * S - 1)
    d.line([(0, i), (i, 0)], fill=lerp(TOP, BOT, t), width=3)

pad = int(S * 0.052)
radius = int(S * 0.2237)
box = (pad, pad, S - pad, S - pad)
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)

icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
icon.paste(img, (0, 0), mask)
d = ImageDraw.Draw(icon)

cx, cy = S // 2, int(S * 0.485)
R = int(S * 0.285)
ring = int(S * 0.044)
d.ellipse([cx - R, cy - R, cx + R, cy + R], outline=(255, 255, 255, 255), width=ring)

for k in range(12):                          # 刻度
    a = math.radians(k * 30)
    long = k % 3 == 0
    r1 = R - ring
    r2 = r1 - (int(S * 0.052) if long else int(S * 0.030))
    w = int(S * 0.012) if long else int(S * 0.007)
    d.line([cx + r1 * math.sin(a), cy - r1 * math.cos(a),
            cx + r2 * math.sin(a), cy - r2 * math.cos(a)],
           fill=(255, 255, 255, 170), width=w)


def hand(deg, length, width, tail=0.0):
    a = math.radians(deg)
    x, y = cx + length * math.sin(a), cy - length * math.cos(a)
    tx, ty = cx - length * tail * math.sin(a), cy + length * tail * math.cos(a)
    d.line([tx, ty, x, y], fill=(255, 255, 255, 255), width=width)
    d.ellipse([x - width / 2, y - width / 2, x + width / 2, y + width / 2],
              fill=(255, 255, 255, 255))


hand((10 + 10 / 60) / 12 * 360, R * 0.50, int(S * 0.040), tail=0.10)   # 时针
hand(10 / 60 * 360, R * 0.74, int(S * 0.027), tail=0.10)               # 分针
d.ellipse([cx - S * 0.021, cy - S * 0.021, cx + S * 0.021, cy + S * 0.021],
          fill=(255, 255, 255, 255))

# 琥珀提醒点：先用底色挖一圈，再画圆点和白心
ax, ay = int(S * 0.742), int(S * 0.752)
ar = int(S * 0.062)
hole = int(ar * 1.34)
d.ellipse([ax - hole, ay - hole, ax + hole, ay + hole], fill=img.getpixel((ax, ay)))
d.ellipse([ax - ar, ay - ar, ax + ar, ay + ar], fill=(255, 157, 10, 255))
d.ellipse([ax - ar * 0.40, ay - ar * 0.40, ax + ar * 0.40, ay + ar * 0.40],
          fill=(255, 255, 255, 255))

icon = icon.resize((1024, 1024), Image.LANCZOS)
icon.save(OUT)
print("saved", OUT)

if SETDIR:
    os.makedirs(SETDIR, exist_ok=True)
    for size in [16, 32, 64, 128, 256, 512]:
        icon.resize((size, size), Image.LANCZOS).save(f"{SETDIR}/icon_{size}x{size}.png")
        icon.resize((size * 2, size * 2), Image.LANCZOS).save(f"{SETDIR}/icon_{size}x{size}@2x.png")
    icon.save(f"{SETDIR}/icon_512x512@2x.png")
    print("iconset:", SETDIR)
