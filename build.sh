#!/bin/bash
# Builds StockMonitor.app (release) into ./build
#
# VERSION       goes into CFBundleShortVersionString (default 1.0)
# BUILD_NUMBER  goes into CFBundleVersion (default: GITHUB_RUN_NUMBER, else 1)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    echo "error: VERSION '$VERSION' must look like 1.2 or 1.2.3" >&2
    exit 1
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "error: BUILD_NUMBER '$BUILD_NUMBER' must be a whole number" >&2
    exit 1
fi

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
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP (version $VERSION, build $BUILD_NUMBER)"
