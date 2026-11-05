#!/bin/bash
# 构建「上课提醒」macOS 菜单栏 App 并安装到 ~/Applications
set -euo pipefail
cd "$(dirname "$0")"

APP="上课提醒"
BIN="ClassReminder"
OUT="build/$APP.app"

rm -rf build
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"

echo "==> 编译"
swiftc -O -swift-version 5 Sources/main.swift -o "$OUT/Contents/MacOS/$BIN"

cp Info.plist "$OUT/Contents/Info.plist"
cp timetable.json "$OUT/Contents/Resources/timetable.json"
[ -f 课表模板.xlsx ] && cp 课表模板.xlsx "$OUT/Contents/Resources/课表模板.xlsx"
[ -f AppIcon.icns ] && cp AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"

echo "==> 临时签名"
codesign --force --deep -s - "$OUT" >/dev/null 2>&1 || echo "（签名失败，继续）"

echo "==> 安装到 /Applications"
DEST="/Applications"
if [ ! -w "$DEST" ]; then DEST="$HOME/Applications"; mkdir -p "$DEST"; fi
rm -rf "$DEST/$APP.app"
cp -R "$OUT" "$DEST/"

echo "==> 写入开机自启 LaunchAgent"
PLIST="$HOME/Library/LaunchAgents/com.mac.classreminder.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.mac.classreminder</string>
    <key>ProgramArguments</key>
    <array><string>$DEST/$APP.app/Contents/MacOS/$BIN</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "==> 完成：$DEST/$APP.app"
