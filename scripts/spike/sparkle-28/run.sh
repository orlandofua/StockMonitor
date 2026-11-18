#!/bin/bash
# Spike #28: does Sparkle 2 update an ad hoc signed, SwiftPM-built app?
#
# Builds a stand-in app ("SparkleSpike") the way build.sh builds StockMonitor,
# embeds Sparkle.framework in Contents/Frameworks, makes v0.0.1 (build 1) and
# v0.0.2 (build 2), signs the v0.0.2 zip with a throwaway EdDSA key, serves an
# appcast from python3 -m http.server on 127.0.0.1, and lets v0.0.1 update itself.
# Nothing here touches build/, .build/, the real app, or any keychain.
#
# Usage: scripts/spike/sparkle-28/run.sh [all|update|negative|hardened|quarantine]
#   SPIKE_WORK  work folder (default: $TMPDIR/sparkle-spike-28). Deleted at the end
#               unless SPIKE_KEEP=1.
#   SPIKE_PORT  local HTTP port (default 8765)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${SPIKE_WORK:-${TMPDIR:-/tmp}/sparkle-spike-28}"
PORT="${SPIKE_PORT:-8765}"
MODE="${1:-all}"
BUNDLE_ID=com.local.SparkleSpike28
FEED="http://127.0.0.1:$PORT/appcast.xml"
WWW="$WORK/www"
INSTALL="$WORK/install"
APP_NAME=SparkleSpike
LOG="$WORK/spike.log"
RESULTS="$WORK/results.txt"
FAILS=0
SERVER_PID=""

say() { echo "$*" | tee -a "$RESULTS"; }
pass() { say "PASS: $*"; }
fail() { say "FAIL: $*"; FAILS=$((FAILS + 1)); }

# Matches any copy, including one macOS translocated, so `open` never reuses a stale instance.
stop_app() {
    pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    sleep 1
}

cleanup() {
    stop_app
    [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null || true
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    rm -rf "$HOME/Library/Caches/$BUNDLE_ID" "$HOME/Library/HTTPStorages/$BUNDLE_ID" \
        "$HOME/Library/Application Support/$BUNDLE_ID"
    if [[ "${SPIKE_KEEP:-0}" != 1 ]]; then
        cp "$RESULTS" "${TMPDIR:-/tmp}/sparkle-spike-28-results.txt" 2>/dev/null || true
        rm -rf "$WORK"
    fi
}
trap cleanup EXIT

# Waits up to $2 seconds for a line matching $1 in the app log.
wait_for_log() {
    local pattern="$1" timeout="$2" i
    for ((i = 0; i < timeout; i++)); do
        grep -qE "$pattern" "$LOG" 2>/dev/null && return 0
        sleep 1
    done
    return 1
}

installed_build() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INSTALL/$APP_NAME.app/Contents/Info.plist"
}

prepare() {
    rm -rf "$WORK"
    mkdir -p "$WORK" "$WWW" "$INSTALL" "$WORK/keys"
    : >"$RESULTS"
    say "== Spike #28 run $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    say "macOS: $(sw_vers -productVersion) ($(sw_vers -buildVersion)), $(uname -m)"
    say "Swift: $(swift --version 2>/dev/null | head -1)"
    rsync -a --exclude .build "$HERE/" "$WORK/pkg/"
    (cd "$WORK/pkg" && swift build -c release 2>&1 | grep -E "error|Compiling|Build complete" | tail -3)
    SPARKLE_ROOT="$WORK/pkg/.build/artifacts/sparkle/Sparkle"
    FRAMEWORK="$SPARKLE_ROOT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
    SIGN_UPDATE="$SPARKLE_ROOT/bin/sign_update"
    say "Sparkle: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$FRAMEWORK/Resources/Info.plist")"
    say "Sparkle.framework as shipped: $(codesign -dv "$FRAMEWORK" 2>&1 | grep -E '^CodeDirectory' | sed 's/.*flags=//')"
    swift "$HERE/make-test-key.swift" "$WORK/keys" 2>/dev/null
    chmod 600 "$WORK/keys/private.seed"
    PUBLIC_KEY="$(cat "$WORK/keys/public.key")"
    python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$WWW" >"$WORK/http.log" 2>&1 &
    SERVER_PID=$!
    sleep 1
}

# make_bundle <outdir> <short version> <build> <check on launch: true|false> [extra codesign args]
# Same layout, Info.plist keys and codesign call as build.sh, plus Sparkle.
make_bundle() {
    local out="$1" short="$2" build="$3" check="$4"
    shift 4
    local app="$out/$APP_NAME.app"
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
    cp "$WORK/pkg/.build/release/SparkleSpike" "$app/Contents/MacOS/$APP_NAME"
    ditto "$FRAMEWORK" "$app/Contents/Frameworks/Sparkle.framework"
    cat >"$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$short</string>
    <key>CFBundleVersion</key><string>$build</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>SUFeedURL</key><string>$FEED</string>
    <key>SUPublicEDKey</key><string>$PUBLIC_KEY</string>
    <key>SUEnableAutomaticChecks</key><false/>
    <key>SpikeCheckOnLaunch</key><$check/>
    <key>SpikeLogPath</key><string>$LOG</string>
</dict>
</plist>
PLIST
    codesign --force --sign - "$@" "$app"
    if codesign --verify --deep --strict "$app" 2>>"$RESULTS"; then
        pass "codesign --verify --deep --strict $short ($*)"
    else
        fail "codesign --verify --deep --strict $short ($*)"
    fi
}

# write_appcast <zip name> <signature attribute text> <length>
write_appcast() {
    cat >"$WWW/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>SparkleSpike</title>
    <item>
      <title>0.0.2</title>
      <sparkle:version>2</sparkle:version>
      <sparkle:shortVersionString>0.0.2</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0.0</sparkle:minimumSystemVersion>
      <pubDate>$(date -R)</pubDate>
      <enclosure url="http://127.0.0.1:$PORT/$1" $2 length="$3" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
}

# build_pair [extra codesign args]: v0.0.1 into $INSTALL (via a zip, like a download),
# v0.0.2 zipped into $WWW and signed. Sets SIG and LEN.
build_pair() {
    rm -rf "$WORK/v1" "$WORK/v2" "$INSTALL"/* "$WWW"/*.zip "$WORK/v1.zip"
    make_bundle "$WORK/v1" 0.0.1 1 true "$@"
    make_bundle "$WORK/v2" 0.0.2 2 false "$@"
    (cd "$WORK/v1" && ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$WORK/v1.zip")
    (cd "$WORK/v2" && ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$WWW/$APP_NAME-v0.0.2.zip")
    ditto -x -k "$WORK/v1.zip" "$INSTALL"
    SIG="$("$SIGN_UPDATE" --ed-key-file "$WORK/keys/private.seed" -p "$WWW/$APP_NAME-v0.0.2.zip")"
    LEN="$(stat -f %z "$WWW/$APP_NAME-v0.0.2.zip")"
}

launch_v1() {
    stop_app
    : >"$LOG"
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    # Never launch a quarantined ad hoc app here: Gatekeeper would block it with a dialog.
    if xattr -r "$INSTALL/$APP_NAME.app" | grep -q com.apple.quarantine; then
        fail "refusing to launch: v0.0.1 still carries com.apple.quarantine"
        return
    fi
    open "$INSTALL/$APP_NAME.app" || fail "open v0.0.1 failed"
}

check_updated() {
    local label="$1"
    if wait_for_log "v=2 launched" 90; then
        pass "$label: v0.0.1 found, downloaded, installed and relaunched as v0.0.2"
    else
        fail "$label: no relaunch as v0.0.2 within 90 s"
    fi
    [[ "$(installed_build)" == 2 ]] && pass "$label: installed CFBundleVersion is 2" \
        || fail "$label: installed CFBundleVersion is $(installed_build)"
    pgrep -f "$INSTALL/$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null && pass "$label: updated app is running" \
        || fail "$label: updated app is not running"
    local xattrs
    xattrs="$(xattr -r "$INSTALL/$APP_NAME.app" | grep -c com.apple.quarantine || true)"
    [[ "$xattrs" == 0 ]] && pass "$label: no com.apple.quarantine on the updated bundle" \
        || fail "$label: $xattrs files with com.apple.quarantine on the updated bundle"
    codesign --verify --deep --strict "$INSTALL/$APP_NAME.app" 2>>"$RESULTS" \
        && pass "$label: updated bundle passes codesign --verify --deep --strict" \
        || fail "$label: updated bundle fails codesign --verify"
    say "$label: spctl --assess says: $(spctl --assess --type execute "$INSTALL/$APP_NAME.app" 2>&1 | tr '\n' ' ')"
    say "--- app log ($label)"
    sed 's/^/    /' "$LOG" | tee -a "$RESULTS" >/dev/null
    stop_app
}

# A rejected update must leave v0.0.1 installed and running.
check_rejected() {
    local label="$1"
    if wait_for_log "UPDATER ERROR" 60; then
        pass "$label: Sparkle reported an error"
    else
        fail "$label: no updater error within 60 s"
    fi
    sleep 3
    [[ "$(installed_build)" == 1 ]] && pass "$label: installed CFBundleVersion is still 1" \
        || fail "$label: installed CFBundleVersion is $(installed_build)"
    grep -q "v=2 launched" "$LOG" && fail "$label: v0.0.2 launched" || pass "$label: v0.0.2 never launched"
    pgrep -f "$INSTALL/$APP_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null && grep -q "v=1 launched" "$LOG" \
        && pass "$label: v0.0.1 keeps running" \
        || fail "$label: v0.0.1 is not running"
    say "--- app log ($label)"
    sed 's/^/    /' "$LOG" | tee -a "$RESULTS" >/dev/null
    stop_app
}

run_update() {
    say "== Update, signed exactly like build.sh (codesign --force --sign -)"
    build_pair
    write_appcast "$APP_NAME-v0.0.2.zip" "sparkle:edSignature=\"$SIG\"" "$LEN"
    launch_v1
    check_updated "adhoc"
}

run_quarantine() {
    say "== Update after a quarantined download (v0.0.1 zip carries com.apple.quarantine)"
    build_pair
    write_appcast "$APP_NAME-v0.0.2.zip" "sparkle:edSignature=\"$SIG\"" "$LEN"
    rm -rf "$INSTALL/$APP_NAME.app"
    cp "$WORK/v1.zip" "$WORK/v1-downloaded.zip"
    xattr -w com.apple.quarantine "0083;$(printf %x "$(date +%s)");Safari;" "$WORK/v1-downloaded.zip"
    ditto -x -k "$WORK/v1-downloaded.zip" "$INSTALL"
    local n
    n="$(xattr -r "$INSTALL/$APP_NAME.app" | grep -c com.apple.quarantine || true)"
    say "quarantine: $n files in the extracted v0.0.1 carry com.apple.quarantine"
    say "quarantine: spctl --assess on v0.0.1: $(spctl --assess --type execute "$INSTALL/$APP_NAME.app" 2>&1 | tr '\n' ' ')"
    # First launch bypass documented in the README (ADR 0010): remove the attribute.
    xattr -dr com.apple.quarantine "$INSTALL/$APP_NAME.app"
    launch_v1
    check_updated "quarantine"
}

run_negative() {
    local zip="$APP_NAME-v0.0.2.zip"
    say "== Negative: bad EdDSA signature"
    build_pair
    local bad
    bad="$(printf %s "$SIG" | cut -c1-10)$(printf %s "$SIG" | cut -c11 | tr 'A-Za-z0-9+/' 'B-Za-z0-9+/A')$(printf %s "$SIG" | cut -c12-)"
    write_appcast "$zip" "sparkle:edSignature=\"$bad\"" "$LEN"
    launch_v1
    check_rejected "bad-signature"

    say "== Negative: missing EdDSA signature"
    write_appcast "$zip" "" "$LEN"
    launch_v1
    check_rejected "missing-signature"

    say "== Negative: zip replaced after signing (valid signature of the original zip)"
    rm -rf "$WORK/evil"
    mkdir -p "$WORK/evil"
    ditto "$WORK/v2/$APP_NAME.app" "$WORK/evil/$APP_NAME.app"
    echo "tampered" >"$WORK/evil/$APP_NAME.app/Contents/Resources-tampered.txt"
    (cd "$WORK/evil" && ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$WWW/evil.zip")
    write_appcast "evil.zip" "sparkle:edSignature=\"$SIG\"" "$(stat -f %z "$WWW/evil.zip")"
    launch_v1
    check_rejected "tampered-zip"

    say "== Negative: one byte of the signed zip flipped"
    cp "$WWW/$zip" "$WWW/flipped.zip"
    local off=$((LEN / 2)) byte
    byte="$(dd if="$WWW/flipped.zip" bs=1 skip=$off count=1 2>/dev/null | xxd -p)"
    printf "\\x$(printf %02x $((0x$byte ^ 0xff)))" | dd of="$WWW/flipped.zip" bs=1 seek=$off count=1 conv=notrunc 2>/dev/null
    write_appcast "flipped.zip" "sparkle:edSignature=\"$SIG\"" "$LEN"
    launch_v1
    check_rejected "flipped-byte"
}

run_hardened() {
    say "== Hardened Runtime on: codesign --force --sign - --options runtime"
    build_pair --options runtime
    say "hardened: v0.0.1 flags: $(codesign -dv "$INSTALL/$APP_NAME.app" 2>&1 | grep -E '^CodeDirectory' | sed 's/.*flags=//')"
    write_appcast "$APP_NAME-v0.0.2.zip" "sparkle:edSignature=\"$SIG\"" "$LEN"
    # Expected to fail: Library Validation refuses an ad hoc framework (no Team ID).
    local dyld
    : >"$LOG"
    dyld="$( ("$INSTALL/$APP_NAME.app/Contents/MacOS/$APP_NAME" & sleep 3; kill $! 2>/dev/null) 2>&1 || true)"
    if grep -q "launched" "$LOG" 2>/dev/null; then
        say "hardened: UNEXPECTED: v0.0.1 started and loaded Sparkle.framework"
        stop_app
    else
        say "hardened: as expected, v0.0.1 cannot load Sparkle.framework:"
        printf '%s\n' "$dyld" | grep -oE "not valid for use in process: [^']*" | head -1 | sed 's/^/    /' | tee -a "$RESULTS"
    fi
    : >"$LOG"

    say "== Hardened Runtime + com.apple.security.cs.disable-library-validation"
    cat >"$WORK/dlv.entitlements" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>com.apple.security.cs.disable-library-validation</key><true/></dict></plist>
ENT
    build_pair --options runtime --entitlements "$WORK/dlv.entitlements"
    write_appcast "$APP_NAME-v0.0.2.zip" "sparkle:edSignature=\"$SIG\"" "$LEN"
    launch_v1
    check_updated "hardened+dlv"
}

prepare
case "$MODE" in
    all) run_update; run_quarantine; run_negative; run_hardened ;;
    update) run_update ;;
    quarantine) run_quarantine ;;
    negative) run_negative ;;
    hardened) run_hardened ;;
    *) echo "unknown mode $MODE" >&2; exit 2 ;;
esac
say "== Done: $FAILS failure(s)"
exit $((FAILS > 0))
