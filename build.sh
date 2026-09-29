#!/bin/bash
# Builds build/Notchless.app. Run with --open to launch it afterwards.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Notchless.app
rm -rf "$APP" build/icon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/icon.iconset

swiftc -O -swift-version 5 -target arm64-apple-macos14 Sources/main.swift -o "$APP/Contents/MacOS/Notchless"
cp Info.plist "$APP/Contents/Info.plist"

"$APP/Contents/MacOS/Notchless" --export-icon build/icon.png
for size in 16 32 128 256 512; do
  sips -z $size $size build/icon.png --out build/icon.iconset/icon_${size}x${size}.png >/dev/null
  sips -z $((size * 2)) $((size * 2)) build/icon.png --out build/icon.iconset/icon_${size}x${size}@2x.png >/dev/null
done
iconutil -c icns build/icon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--open" ]]; then open "$APP"; fi
