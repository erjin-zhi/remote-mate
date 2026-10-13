#!/bin/bash
# 构建 Rmt Pilot.app（Release），输出到 ./build
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Rmt Pilot"
BUNDLE_ID="com.rmtpilot.app"
APP="build/${APP_NAME}.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/RmtPilot"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/RmtPilot"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>RmtPilot</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>用于以管理员身份切换合盖不休眠。</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "✅ 已生成: $APP"
echo "   安装: cp -R \"$APP\" /Applications/"
