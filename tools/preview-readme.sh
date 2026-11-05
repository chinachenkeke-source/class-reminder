#!/bin/bash
# 把 README.md 按 GitHub 样式渲染成图片，用来检查排版。
# 需要：gh 已登录、本机装了 Google Chrome、有 python3。
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-docs/readme-preview.png}"
mkdir -p "$(dirname "$OUT")"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

python3 - "$TMP" <<'PY'
import json, subprocess, sys, os
tmp = sys.argv[1]
text = open("README.md", encoding="utf-8").read()
req = os.path.join(tmp, "req.json")
json.dump({"text": text, "mode": "gfm"}, open(req, "w"))
out = subprocess.run(["gh", "api", "-X", "POST", "/markdown", "--input", req],
                     capture_output=True, text=True, check=True).stdout
base = os.getcwd()
for n in ["statusbar.png", "preview.png", "preview-alert.png"]:
    out = out.replace('src="%s"' % n, 'src="file://%s/%s"' % (base, n))
css = """
<style>
  body{font-family:-apple-system,"PingFang SC","Helvetica Neue",Arial,sans-serif;font-size:16px;
       line-height:1.65;color:#1f2328;background:#fff;max-width:880px;margin:0 auto;padding:34px 40px 60px}
  h1{font-size:2em;border-bottom:1px solid #d1d9e0;padding-bottom:.3em;margin-top:0}
  h2{font-size:1.5em;border-bottom:1px solid #d1d9e0;padding-bottom:.3em;margin-top:1.7em}
  p{margin:10px 0} img{max-width:100%;vertical-align:middle}
  a{color:#0969da;text-decoration:none}
  blockquote{margin:14px 0;padding:4px 16px;color:#59636e;border-left:4px solid #d1d9e0}
  code{background:rgba(129,139,152,.12);padding:.2em .4em;border-radius:6px;
       font-family:ui-monospace,Menlo,monospace;font-size:85%}
  pre{background:#f6f8fa;padding:14px 16px;border-radius:8px;overflow:auto}
  pre code{background:transparent;padding:0}
  table{border-collapse:collapse;margin:14px 0}
  th,td{border:1px solid #d1d9e0;padding:7px 13px}
  th{background:#f6f8fa;font-weight:600}
  sub{color:#59636e;font-size:13px}
  ul{padding-left:1.6em} li{margin:5px 0}
</style>
"""
open(os.path.join(tmp, "readme.html"), "w").write(out.replace("<h1>", css + "<h1>", 1))
PY

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "没找到 Google Chrome"; exit 1; }

"$CHROME" --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=2 --window-size=980,8000 \
  --screenshot="$TMP/shot.png" "file://$TMP/readme.html" >/dev/null 2>&1

# 裁掉底部空白（需要 Pillow；没有就直接整张）
PYBIN=""
for cand in python3 /Users/mac/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3; do
  if "$cand" -c "import PIL" >/dev/null 2>&1; then PYBIN="$cand"; break; fi
done

if [ -n "$PYBIN" ]; then
  "$PYBIN" - "$TMP/shot.png" "$OUT" <<'PY2'
import sys
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
im = Image.open(src).convert("RGB")
w, h = im.size
px = im.load()
bottom = h
for y in range(h - 1, -1, -4):
    if not all(px[x, y] == (255, 255, 255) for x in range(0, w, 8)):
        bottom = min(h, y + 80)
        break
im.crop((0, 0, w, bottom)).save(dst)
print("已渲染：%s  (%dx%d)" % (dst, w, bottom))
PY2
else
  cp "$TMP/shot.png" "$OUT"
  echo "已渲染：$OUT（没装 Pillow，底部空白未裁）"
fi
