#!/bin/bash
# 构建 RemoteMate.app（Release），输出到 ./build
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="RemoteMate"
BUNDLE_ID="com.remotemate.app"
DEST="build/${APP_NAME}.app"
# 在 iCloud 同步目录之外组装和签名：文件提供程序会给 bundle 附加 FinderInfo，导致签名失败。
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/remotemate-bundle.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/${APP_NAME}.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/RemoteMate"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp -X "$BIN" "$APP/Contents/MacOS/RemoteMate"
SPARKLE=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[[ -d "$SPARKLE" ]] || { echo "缺少 Sparkle.framework，请先运行 swift package resolve" >&2; exit 1; }
ditto --norsrc --noextattr "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"
cp -X Updates/Sparkle-LICENSE.txt "$APP/Contents/Resources/Sparkle-LICENSE.txt"
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
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>用于以管理员身份切换合盖不休眠。</string>
</dict>
</plist>
PLIST

# 版本号、构建号与 Sparkle 更新配置统一来自 Updates/config.json。
python3 scripts/configure-updates.py "$APP" "$@"

# 移除编译器留下的本机源码路径和调试符号，再由内向外签名（保留 Sparkle 的符号链接结构）。
strip -S "$APP/Contents/MacOS/RemoteMate"
FW="$APP/Contents/Frameworks/Sparkle.framework"
while IFS= read -r -d '' child; do
    codesign --force --sign - "$child"
done < <(find "$FW/Versions" -type d \( -name '*.xpc' -o -name '*.app' \) -print0)
codesign --force --sign - "$FW/Versions/B/Autoupdate"
codesign --force --sign - "$FW"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --deep --strict "$APP"
rm -rf "$DEST"
mkdir -p build
ditto --norsrc --noextattr "$APP" "$DEST"
echo "✅ 已生成: $DEST"
echo "   安装: cp -R \"$DEST\" /Applications/"
