#!/bin/bash
# 构建「上课提醒」菜单栏 App
#   用法：./build.sh [版本号]     例：./build.sh 1.13.0
# 不带版本号就用 Info.plist 里现有的版本。
# 会做四件事：写版本号 → 编译签名 → 装到 /Applications → 打包 dmg/zip + 留 5 个版本备份
set -euo pipefail
cd "$(dirname "$0")"

APP="上课提醒"
BIN="ClassReminder"
OUT="build/$APP.app"
DIST="dist"
BACKUPS="$DIST/backups"
KEEP=5                     # 保留最近几个版本

# ── 版本号
VER="${1:-}"
if [ -n "$VER" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VER" Info.plist
  BUILD_NO=$(echo "$VER" | tr -d '.')
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NO" Info.plist
fi
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
echo "==> 版本 $VER"

rm -rf build
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources" "$DIST" "$BACKUPS"

echo "==> 编译"
swiftc -O -swift-version 5 Sources/*.swift -o "$OUT/Contents/MacOS/$BIN"

cp Info.plist "$OUT/Contents/Info.plist"
cp timetable.json "$OUT/Contents/Resources/timetable.json"
cp school-timetable.json "$OUT/Contents/Resources/school-timetable.json"
[ -f 课表模板.xlsx ] && cp 课表模板.xlsx "$OUT/Contents/Resources/课表模板.xlsx"
[ -f AppIcon.icns ] && cp AppIcon.icns "$OUT/Contents/Resources/AppIcon.icns"

echo "==> 临时签名"
codesign --force --deep -s - "$OUT" >/dev/null 2>&1 || echo "（签名失败，继续）"

echo "==> 打包（文件名带版本号）"
hdiutil create -volname "$APP" -srcfolder build -ov -format UDZO \
  "$DIST/ClassReminder-$VER.dmg" >/dev/null 2>&1
ditto -c -k --sequesterRsrc --keepParent "$OUT" "$DIST/ClassReminder-$VER.zip"

echo "==> 版本备份：$BACKUPS/$APP-$VER.app"
rm -rf "$BACKUPS/$APP-$VER.app"
cp -R "$OUT" "$BACKUPS/$APP-$VER.app"

# 只留最近 $KEEP 个（按版本号从新到旧排）
prune() {
  local dir="$1" pattern="$2"
  ls -1 "$dir" 2>/dev/null | grep -E "$pattern" | sort -V -r | tail -n +$((KEEP + 1)) | while read -r old; do
    rm -rf "$dir/$old"
    echo "    清理旧版本：$old"
  done
}
prune "$BACKUPS" "^${APP}-[0-9].*\.app$"
prune "$DIST" "^ClassReminder-[0-9].*\.(dmg|zip)$"

echo "==> 安装到 /Applications"
DEST="/Applications"
if [ ! -w "$DEST" ]; then DEST="$HOME/Applications"; mkdir -p "$DEST"; fi
rm -rf "$DEST/$APP.app"
cp -R "$OUT" "$DEST/"

echo "==> 写入开机自启 LaunchAgent"
PLIST="$HOME/Library/LaunchAgents/com.mac.classreminder.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLISTEOF
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
PLISTEOF

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "==> 完成"
echo "    App:     ${DEST}/${APP}.app  version ${VER}"
echo "    安装包:  ${DIST}/ClassReminder-${VER}.dmg / .zip"
echo "    备份:    ${BACKUPS}/${APP}-${VER}.app  (keep ${KEEP})"
