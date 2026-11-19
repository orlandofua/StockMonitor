#!/bin/bash
# Prints the Info.plist for StockMonitor.app on standard output. Called by build.sh.
#
# VERSION                goes into CFBundleShortVersionString (default 1.0)
# BUILD_NUMBER           goes into CFBundleVersion (default 1)
# SPARKLE_FEED_URL       goes into SUFeedURL. Unset or empty: no Sparkle keys at
#                        all, so the build never checks for updates (ADR 0015).
# SPARKLE_PUBLIC_ED_KEY  goes into SUPublicEDKey. Required when SPARKLE_FEED_URL
#                        is set, because Sparkle 2 rejects updates without it.
#
# Exits 1 with a message on stderr if a value is malformed, so a bad value can
# never end up in a shipped Info.plist.
set -euo pipefail

VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"

fail() {
    echo "error: $1" >&2
    exit 1
}

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]]; then
    fail "VERSION '$VERSION' must look like 1.2 or 1.2.3"
fi
if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    fail "BUILD_NUMBER '$BUILD_NUMBER' must be a whole number"
fi

sparkle_keys=""
if [[ -n "$SPARKLE_FEED_URL" ]]; then
    # An http(s) URL with no whitespace and no characters that would need XML escaping.
    url_pattern="^https?://[^[:space:]<>&\"']+\$"
    if [[ ! "$SPARKLE_FEED_URL" =~ $url_pattern ]]; then
        fail "SPARKLE_FEED_URL '$SPARKLE_FEED_URL' must be an http or https URL"
    fi
    if [[ -z "$SPARKLE_PUBLIC_ED_KEY" ]]; then
        fail "SPARKLE_PUBLIC_ED_KEY must be set when SPARKLE_FEED_URL is set"
    fi
    # An ed25519 public key is 32 bytes, which is 44 base64 characters ending in '='.
    if [[ ! "$SPARKLE_PUBLIC_ED_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
        fail "SPARKLE_PUBLIC_ED_KEY must be a base64 ed25519 public key (44 characters)"
    fi
    sparkle_keys="
    <key>SUFeedURL</key><string>$SPARKLE_FEED_URL</string>
    <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_ED_KEY</string>"
fi

cat <<PLIST
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
    <key>LSUIElement</key><true/>$sparkle_keys
</dict>
</plist>
PLIST
