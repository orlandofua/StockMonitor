#!/bin/bash
# Builds StockMonitor.app (release) into ./build
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/StockMonitor.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/StockMonitor "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>StockMonitor</string>
    <key>CFBundleIdentifier</key><string>com.local.StockMonitor</string>
    <key>CFBundleExecutable</key><string>StockMonitor</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
