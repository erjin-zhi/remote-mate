#!/bin/bash
# 构建 RemoteMate.app（Release），输出到 ./build
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="RemoteMate"
BUNDLE_ID="com.remotemate.app"
APP="build/${APP_NAME}.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/RemoteMate"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -X "$BIN" "$APP/Contents/MacOS/RemoteMate"
cp -X "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -X -R Resources/en.lproj Resources/zh-Hans.lproj "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>RemoteMate</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.1</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>用于以管理员身份切换合盖不休眠。</string>
</dict>
</plist>
PLIST

# 移除编译器留下的本机源码路径和调试符号，再对最终二进制签名。
strip -S "$APP/Contents/MacOS/RemoteMate"
codesign --force --deep --sign - "$APP"
echo "✅ 已生成: $APP"
echo "   安装: cp -R \"$APP\" /Applications/"
