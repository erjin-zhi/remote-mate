#!/bin/bash
# 将 build/RemoteMate.app 打包为带拖动安装引导的 DMG：scripts/build-dmg.sh <版本号>
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?用法: scripts/build-dmg.sh <版本号>}"
APP="build/RemoteMate.app"
VOLNAME="RemoteMate"
OUT_DIR="build/releases/${VERSION}"
DMG="${OUT_DIR}/RemoteMate-${VERSION}-macOS-arm64.dmg"
[[ -d "$APP" ]] || { echo "未找到 $APP，请先运行 ./build.sh" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'hdiutil detach -quiet "/Volumes/${VOLNAME}" 2>/dev/null || true; rm -rf "$WORK"' EXIT

# 背景图：1x + 2x 合成 HiDPI TIFF，Retina 屏下保持清晰。
swift scripts/dmg-background.swift "$WORK/bg.png" 1
swift scripts/dmg-background.swift "$WORK/bg@2x.png" 2
tiffutil -cathidpicheck "$WORK/bg.png" "$WORK/bg@2x.png" -out "$WORK/background.tiff" >/dev/null

STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/RemoteMate.app"
ln -s /Applications "$STAGE/Applications"
cp "$WORK/background.tiff" "$STAGE/.background/background.tiff"

# 已挂载的同名卷会导致 Finder 布局写错位置，先卸载。
hdiutil detach -quiet "/Volumes/${VOLNAME}" 2>/dev/null || true
hdiutil create -quiet -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
# 不能带 -nobrowse，否则 Finder 不会把窗口布局写入 .DS_Store。
hdiutil attach -quiet -noautoopen "$WORK/rw.dmg"

# 内容区 660×400（bounds 高度另含约 32pt 标题栏），坐标与 dmg-background.swift 保持一致。
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "${VOLNAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set bounds of container window to {200, 120, 860, 552}
        set opts to icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "RemoteMate.app" of container window to {180, 200}
        set position of item "Applications" of container window to {480, 200}
        update without registering applications
        delay 1
        close
        -- 重新打开再关闭一次，确保布局落盘。
        open
        delay 1
        set bounds of container window to {200, 120, 860, 552}
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# 等待 Finder 写完 .DS_Store。
for _ in {1..20}; do [[ -f "/Volumes/${VOLNAME}/.DS_Store" ]] && break; sleep 0.5; done
sleep 2
chflags hidden "/Volumes/${VOLNAME}/.background"
rm -rf "/Volumes/${VOLNAME}/.fseventsd" "/Volumes/${VOLNAME}/.Trashes"
sync
hdiutil detach -quiet "/Volumes/${VOLNAME}"

mkdir -p "$OUT_DIR"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG"
(cd "$OUT_DIR" && shasum -a 256 "$(basename "$DMG")" > SHA256SUMS.txt)
echo "✅ 已生成: $DMG"
