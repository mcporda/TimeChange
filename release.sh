#!/bin/bash
# 打包发布版：通用二进制（Apple 芯片 + Intel）+ DMG
# 用法：./release.sh 1.0.0
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-1.0.0}"
OUT="build/release"
APP="$OUT/TimeChange.app"
DMG="build/TimeChange-$VERSION.dmg"

rm -rf "$OUT" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos14" Sources/main.swift -o "$OUT/TimeChange-$arch"
done
lipo -create "$OUT/TimeChange-arm64" "$OUT/TimeChange-x86_64" -output "$APP/Contents/MacOS/TimeChange"
rm "$OUT/TimeChange-arm64" "$OUT/TimeChange-x86_64"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.timechange.clock</string>
  <key>CFBundleName</key><string>TimeChange</string>
  <key>CFBundleExecutable</key><string>TimeChange</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"

# DMG：App + 指向「应用程序」的快捷方式，拖进去即可安装
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "TimeChange $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "$DMG"
