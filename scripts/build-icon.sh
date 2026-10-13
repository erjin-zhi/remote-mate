#!/bin/bash
# 将选定的原图转换为标准 macOS 多尺寸 ICNS。
set -euo pipefail
cd "$(dirname "$0")/.."

ICON_SOURCE="Branding/RemoteMate/app-icon-light.png"
ICON_TEMP="$(mktemp -d)"
trap 'rm -rf "$ICON_TEMP"' EXIT
ICONSET="$ICON_TEMP/AppIcon.iconset"
mkdir -p "$ICONSET" Resources

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
echo "已生成 Resources/AppIcon.icns"
