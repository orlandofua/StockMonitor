#!/bin/bash
# Tests for sign-app.sh. Run by ./test.sh.
#
# The release signs with a Developer ID identity, which CI and contributors do
# not have, so these tests sign with the ad-hoc identity "-". They check what
# does not depend on the identity: that every piece of code in the bundle is
# re-signed, inside out, with the Hardened Runtime, and that the result passes
# a strict verification.
set -uo pipefail
cd "$(dirname "$0")/.."

failures=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sign-app-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

FRAMEWORK=.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework
if [[ ! -d "$FRAMEWORK" ]]; then
    swift package resolve >/dev/null || { echo "FAIL sign-app.sh: cannot resolve the Sparkle package" >&2; exit 1; }
fi

fail() {
    echo "FAIL sign-app.sh: $1" >&2
    failures=$((failures + 1))
}

# flags <path>: prints the CodeDirectory flags line of the code at <path>.
flags() {
    codesign -dv "$1" 2>&1 | grep '^CodeDirectory'
}

expect_runtime() {
    local path="$1" context="$2"
    flags "$path" | grep -q 'runtime' || fail "$context: $path is not signed with the Hardened Runtime ($(flags "$path"))"
}

# make_app <dir>: builds a bundle shaped like build.sh's output, ad-hoc signed
# without the Hardened Runtime. Sparkle's nested code is re-signed the same way
# first, so a test can tell whether sign-app.sh re-signed each piece.
make_app() {
    local app="$1/StockMonitor.app" fw
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
    cp /usr/bin/true "$app/Contents/MacOS/StockMonitor"
    cat >"$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>StockMonitor</string>
    <key>CFBundleIdentifier</key><string>com.example.StockMonitorTest</string>
    <key>CFBundlePackageType</key><string>APPL</string>
</dict>
</plist>
PLIST
    ditto "$FRAMEWORK" "$app/Contents/Frameworks/Sparkle.framework"
    fw="$app/Contents/Frameworks/Sparkle.framework"
    {
        codesign --force --sign - "$fw/Versions/B/XPCServices/Installer.xpc" &&
        codesign --force --sign - --entitlements "$TMP/downloader.entitlements" \
            "$fw/Versions/B/XPCServices/Downloader.xpc" &&
        codesign --force --sign - "$fw/Versions/B/Autoupdate" &&
        codesign --force --sign - "$fw/Versions/B/Updater.app" &&
        codesign --force --sign - "$fw" &&
        codesign --force --sign - "$app"
    } 2>"$TMP/setup.log" || {
        # A broken fixture would make every later check look like a sign-app.sh bug.
        echo "sign-app-tests: cannot build the test bundle: $(cat "$TMP/setup.log")" >&2
        exit 1
    }
    echo "$app"
}

cat >"$TMP/downloader.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.network.client</key><true/>
</dict>
</plist>
PLIST

# A signed bundle: the outer app runs with the Hardened Runtime, which
# notarization requires, and still passes a strict verification.
context="sign with ad-hoc identity"
mkdir -p "$TMP/signed"
APP="$(make_app "$TMP/signed")" || exit 1
if ./scripts/sign-app.sh "$APP" - >"$TMP/out" 2>&1; then
    codesign --verify --deep --strict "$APP" 2>/dev/null || fail "$context: strict verification failed"
    expect_runtime "$APP" "$context"
    # Sparkle's helpers must carry the release identity too, or notarization
    # rejects the bundle and the updater fails to launch (Sparkle's
    # "Sandboxing and code signing" docs, comment on #12).
    fw="$APP/Contents/Frameworks/Sparkle.framework"
    for code in "$fw/Versions/B/XPCServices/Installer.xpc" \
                "$fw/Versions/B/XPCServices/Downloader.xpc" \
                "$fw/Versions/B/Autoupdate" \
                "$fw/Versions/B/Updater.app" \
                "$fw"; do
        expect_runtime "$code" "$context"
    done
    # Sparkle's docs keep the Downloader service's entitlements when re-signing.
    codesign -d --entitlements - --xml "$fw/Versions/B/XPCServices/Downloader.xpc" 2>/dev/null \
        | grep -q 'com.apple.security.network.client' \
        || fail "$context: Downloader.xpc lost its entitlements"
else
    fail "$context: exited non-zero: $(cat "$TMP/out")"
fi

# expect_error <context> <args...>: sign-app.sh must exit non-zero.
expect_error() {
    local context="$1"
    shift
    ./scripts/sign-app.sh "$@" >/dev/null 2>&1 && fail "$context: exited zero, expected an error"
}

expect_error "no arguments"
expect_error "no identity" "$APP"
expect_error "empty identity" "$APP" ""
expect_error "missing app" "$TMP/missing/StockMonitor.app" -
# A bundle without Sparkle must not be shipped as signed.
mkdir -p "$TMP/nosparkle"
NOSPARKLE="$(make_app "$TMP/nosparkle")" || exit 1
rm -rf "$NOSPARKLE/Contents/Frameworks/Sparkle.framework"
expect_error "app without Sparkle.framework" "$NOSPARKLE" -

if ((failures > 0)); then
    echo "sign-app-tests: $failures failure(s)" >&2
    exit 1
fi
echo "sign-app-tests: all passed"
