#!/bin/bash
# Tests for make-info-plist.sh. Run by ./test.sh.
set -uo pipefail
cd "$(dirname "$0")"

failures=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/make-info-plist-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PLIST="$TMP/Info.plist"

KEY="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
FEED="https://orlandofua.github.io/StockMonitor/appcast.xml"

fail() {
    echo "FAIL make-info-plist.sh: $1" >&2
    failures=$((failures + 1))
}

# generate <env assignments...>: writes $PLIST with a clean environment plus the
# given variables. Returns the script's exit status.
generate() {
    env -i PATH="$PATH" "$@" ./make-info-plist.sh >"$PLIST" 2>/dev/null
}

# value <key>: prints the key's value from $PLIST, or nothing if it is missing.
value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null
}

expect_value() {
    local key="$1" expected="$2" context="$3" actual
    actual="$(value "$key")"
    [[ "$actual" == "$expected" ]] || fail "$context: $key is '$actual', expected '$expected'"
}

expect_missing() {
    local key="$1" context="$2"
    value "$key" >/dev/null && fail "$context: $key is present, expected it to be left out"
}

expect_valid() {
    plutil -lint -s "$PLIST" >/dev/null 2>&1 || fail "$1: output is not a valid plist"
}

# Defaults: no feed URL means no Sparkle keys, so the build never checks for updates.
context="defaults"
if generate; then
    expect_valid "$context"
    expect_value CFBundleShortVersionString 1.0 "$context"
    expect_value CFBundleVersion 1 "$context"
    expect_value CFBundleExecutable StockMonitor "$context"
    expect_value LSUIElement true "$context"
    expect_missing SUFeedURL "$context"
    expect_missing SUPublicEDKey "$context"
    expect_missing SUEnableAutomaticChecks "$context"
    expect_missing SUScheduledCheckInterval "$context"
    expect_missing SUAllowsAutomaticUpdates "$context"
    expect_missing SUAutomaticallyUpdate "$context"
else
    fail "$context: exited non-zero"
fi

# VERSION and BUILD_NUMBER are stamped.
context="VERSION=1.2.3 BUILD_NUMBER=42"
if generate VERSION=1.2.3 BUILD_NUMBER=42; then
    expect_valid "$context"
    expect_value CFBundleShortVersionString 1.2.3 "$context"
    expect_value CFBundleVersion 42 "$context"
else
    fail "$context: exited non-zero"
fi

# An empty feed URL counts as unset, even with a public key.
context="empty SPARKLE_FEED_URL with a key"
if generate SPARKLE_FEED_URL= SPARKLE_PUBLIC_ED_KEY="$KEY"; then
    expect_valid "$context"
    expect_missing SUFeedURL "$context"
    expect_missing SUPublicEDKey "$context"
    expect_missing SUScheduledCheckInterval "$context"
else
    fail "$context: exited non-zero"
fi

# Both variables set: both keys are written.
context="feed URL and key set"
if generate SPARKLE_FEED_URL="$FEED" SPARKLE_PUBLIC_ED_KEY="$KEY"; then
    expect_valid "$context"
    expect_value SUFeedURL "$FEED" "$context"
    expect_value SUPublicEDKey "$KEY" "$context"
    expect_value CFBundleVersion 1 "$context"
    # ADR 0015: check once a day in the background, prompt before installing by default.
    expect_value SUEnableAutomaticChecks true "$context"
    expect_value SUScheduledCheckInterval 86400 "$context"
    expect_value SUAllowsAutomaticUpdates true "$context"
    expect_value SUAutomaticallyUpdate false "$context"
else
    fail "$context: exited non-zero"
fi

# A local http feed (as in spike #28) is allowed.
context="local http feed"
if generate SPARKLE_FEED_URL="http://127.0.0.1:8765/appcast.xml" SPARKLE_PUBLIC_ED_KEY="$KEY"; then
    expect_value SUFeedURL "http://127.0.0.1:8765/appcast.xml" "$context"
else
    fail "$context: exited non-zero"
fi

# Bad values fail the build instead of producing a broken or unverifiable plist.
expect_error() {
    local context="$1"; shift
    generate "$@" && fail "$context: succeeded, expected an error"
}
expect_error "feed URL without a key" SPARKLE_FEED_URL="$FEED"
expect_error "key too short" SPARKLE_FEED_URL="$FEED" SPARKLE_PUBLIC_ED_KEY="AAAA="
expect_error "key with bad characters" SPARKLE_FEED_URL="$FEED" SPARKLE_PUBLIC_ED_KEY="${KEY/A/<}"
expect_error "feed URL not http(s)" SPARKLE_FEED_URL="ftp://example.com/appcast.xml" SPARKLE_PUBLIC_ED_KEY="$KEY"
expect_error "feed URL with a space" SPARKLE_FEED_URL="https://example.com/app cast.xml" SPARKLE_PUBLIC_ED_KEY="$KEY"
expect_error "feed URL with an ampersand" SPARKLE_FEED_URL="https://example.com/a.xml?x=1&y=2" SPARKLE_PUBLIC_ED_KEY="$KEY"
expect_error "feed URL with markup" SPARKLE_FEED_URL="https://example.com/</string>" SPARKLE_PUBLIC_ED_KEY="$KEY"
expect_error "bad VERSION" VERSION=1
expect_error "bad BUILD_NUMBER" BUILD_NUMBER=1a

if ((failures > 0)); then
    echo "make-info-plist-tests: $failures failure(s)" >&2
    exit 1
fi
echo "make-info-plist-tests: all passed"
