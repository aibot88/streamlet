#!/usr/bin/env bash
# Builds a universal Streamlet.app (ad-hoc signed) and zips it into build/.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --arch arm64 --arch x86_64
BIN=.build/apple/Products/Release/Streamlet
APP=build/Streamlet.app
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Streamlet"
ICONSET=build/AppIcon.iconset && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  "$BIN" --render-icon "$ICONSET/icon_${s}x${s}.png" $s
  "$BIN" --render-icon "$ICONSET/icon_${s}x${s}@2x.png" $((s*2))
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Streamlet</string>
  <key>CFBundleDisplayName</key><string>Streamlet</string>
  <key>CFBundleIdentifier</key><string>com.aibot88.streamlet</string>
  <key>CFBundleExecutable</key><string>Streamlet</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
(cd build && ditto -c -k --keepParent Streamlet.app Streamlet.zip)
echo "Built $APP and build/Streamlet.zip"
