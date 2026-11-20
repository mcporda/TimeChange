#!/bin/bash
# 构建 TimeChange.app 并安装到 ~/Applications
set -euo pipefail
cd "$(dirname "$0")"

APP="build/TimeChange.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos14 \
  Sources/*.swift -o "$APP/Contents/MacOS/TimeChange"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.timechange.clock</string>
  <key>CFBundleName</key><string>TimeChange</string>
  <key>CFBundleExecutable</key><string>TimeChange</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

mkdir -p ~/Applications
rm -rf ~/Applications/TimeChange.app
cp -R "$APP" ~/Applications/
echo "已安装到 ~/Applications/TimeChange.app"
