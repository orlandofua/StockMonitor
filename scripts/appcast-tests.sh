#!/bin/bash
# Tests for add-appcast-item.sh and verify-ed-signature.swift. Run by ./test.sh.
set -uo pipefail
cd "$(dirname "$0")"

failures=0
TMP="$(mktemp -d "${TMPDIR:-/tmp}/appcast-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
FEED="$TMP/appcast.xml"

# A syntactically valid signature for the feed tests. The signature tests below
# use a real key.
SIG="$(printf 'A%.0s' {1..86})=="
BASE="https://github.com/orlandofua/StockMonitor/releases"

fail() {
    echo "FAIL appcast: $1" >&2
    failures=$((failures + 1))
}

# add <env assignments...>: adds an item to $FEED with a clean environment plus
# the given variables, on top of valid defaults for v1.2.3 build 10.
add() {
    env -i PATH="$PATH" TMPDIR="$TMP" \
        VERSION=1.2.3 BUILD_NUMBER=10 LENGTH=12345 ED_SIGNATURE="$SIG" \
        ZIP_URL="$BASE/download/v1.2.3/StockMonitor-v1.2.3.zip" NOTES_URL="$BASE/tag/v1.2.3" \
        PUB_DATE="Thu, 19 Nov 2026 10:00:00 +0000" \
        "$@" ./add-appcast-item.sh "$FEED" 2>/dev/null
}

# xpath <expression>: prints the expression's string value from $FEED.
xpath() {
    xmllint --xpath "$1" "$FEED" 2>/dev/null
}

expect_xpath() {
    local expression="$1" expected="$2" context="$3" actual
    actual="$(xpath "$expression")"
    [[ "$actual" == "$expected" ]] || fail "$context: $expression is '$actual', expected '$expected'"
}

# A new feed gets one item with every field Sparkle needs (ADR 0015).
context="new feed"
rm -f "$FEED"
if add; then
    xmllint --noout "$FEED" 2>/dev/null || fail "$context: not well-formed XML"
    expect_xpath "count(//channel/item)" 1 "$context"
    expect_xpath "string(//channel/title)" StockMonitor "$context"
    expect_xpath "string(//item[1]/title)" "Version 1.2.3" "$context"
    expect_xpath "string(//item[1]/pubDate)" "Thu, 19 Nov 2026 10:00:00 +0000" "$context"
    expect_xpath "string(//item[1]/*[local-name()='version'])" 10 "$context"
    expect_xpath "string(//item[1]/*[local-name()='shortVersionString'])" 1.2.3 "$context"
    expect_xpath "string(//item[1]/*[local-name()='minimumSystemVersion'])" 13.0.0 "$context"
    expect_xpath "string(//item[1]/*[local-name()='releaseNotesLink'])" "$BASE/tag/v1.2.3" "$context"
    expect_xpath "string(//item[1]/enclosure/@url)" "$BASE/download/v1.2.3/StockMonitor-v1.2.3.zip" "$context"
    expect_xpath "string(//item[1]/enclosure/@length)" 12345 "$context"
    expect_xpath "string(//item[1]/enclosure/@type)" application/octet-stream "$context"
    expect_xpath "string(//item[1]/enclosure/@*[local-name()='edSignature'])" "$SIG" "$context"
    # The sparkle prefix must be bound to Sparkle's namespace, or Sparkle ignores the fields.
    expect_xpath "namespace-uri(//item[1]/*[local-name()='version'])" \
        "http://www.andymatuschak.org/xml-namespaces/sparkle" "$context"
else
    fail "$context: exited non-zero"
fi

# A second release goes first and keeps the older one.
context="second release"
if add VERSION=1.3.0 BUILD_NUMBER=11 ZIP_URL="$BASE/download/v1.3.0/StockMonitor-v1.3.0.zip" \
    NOTES_URL="$BASE/tag/v1.3.0"; then
    xmllint --noout "$FEED" 2>/dev/null || fail "$context: not well-formed XML"
    expect_xpath "count(//channel/item)" 2 "$context"
    expect_xpath "string(//item[1]/*[local-name()='version'])" 11 "$context"
    expect_xpath "string(//item[2]/*[local-name()='version'])" 10 "$context"
else
    fail "$context: exited non-zero"
fi

# A third release still goes first.
context="third release"
if add VERSION=1.3.1 BUILD_NUMBER=12; then
    expect_xpath "count(//channel/item)" 3 "$context"
    expect_xpath "string(//item[1]/*[local-name()='shortVersionString'])" 1.3.1 "$context"
    expect_xpath "string(//item[3]/*[local-name()='shortVersionString'])" 1.2.3 "$context"
else
    fail "$context: exited non-zero"
fi

# Bad input fails and leaves the feed byte for byte as it was.
cp "$FEED" "$TMP/before.xml"
expect_error() {
    local context="$1"; shift
    add "$@" && fail "$context: succeeded, expected an error"
    cmp -s "$FEED" "$TMP/before.xml" || fail "$context: changed the feed"
}
expect_error "repeated build number" VERSION=9.9.9 BUILD_NUMBER=11
expect_error "repeated version" VERSION=1.3.0 BUILD_NUMBER=99
expect_error "missing signature" BUILD_NUMBER=20 VERSION=2.0.0 ED_SIGNATURE=
expect_error "short signature" BUILD_NUMBER=20 VERSION=2.0.0 ED_SIGNATURE="AAAA=="
expect_error "signature with markup" BUILD_NUMBER=20 VERSION=2.0.0 ED_SIGNATURE="${SIG/A/\"}"
expect_error "zero length" BUILD_NUMBER=20 VERSION=2.0.0 LENGTH=0
expect_error "missing length" BUILD_NUMBER=20 VERSION=2.0.0 LENGTH=
expect_error "version with a v" BUILD_NUMBER=20 VERSION=v2.0.0
expect_error "two-part version" BUILD_NUMBER=20 VERSION=2.0
expect_error "bad build number" BUILD_NUMBER=2a VERSION=2.0.0
expect_error "http zip URL" BUILD_NUMBER=20 VERSION=2.0.0 ZIP_URL="http://example.com/a.zip"
expect_error "zip URL with an ampersand" BUILD_NUMBER=20 VERSION=2.0.0 ZIP_URL="https://example.com/a.zip?x=1&y=2"
expect_error "notes URL with markup" BUILD_NUMBER=20 VERSION=2.0.0 NOTES_URL="https://example.com/</a>"
expect_error "date with markup" BUILD_NUMBER=20 VERSION=2.0.0 PUB_DATE="<x>"

context="broken existing feed"
printf '<rss><channel>\n' >"$FEED"
cp "$FEED" "$TMP/before.xml"
expect_error "$context" BUILD_NUMBER=20 VERSION=2.0.0

# PUB_DATE defaults to the current time in RFC 822 form.
context="default date"
rm -f "$FEED"
if env -i PATH="$PATH" TMPDIR="$TMP" VERSION=1.2.3 BUILD_NUMBER=10 LENGTH=1 ED_SIGNATURE="$SIG" \
    ZIP_URL="$BASE/a.zip" NOTES_URL="$BASE/n" ./add-appcast-item.sh "$FEED" 2>/dev/null; then
    date_pattern='^[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} \+0000$'
    [[ "$(xpath "string(//item[1]/pubDate)")" =~ $date_pattern ]] || fail "$context: pubDate is not RFC 822"
else
    fail "$context: exited non-zero"
fi

# verify-ed-signature.swift accepts a real signature and rejects every change.
cat >"$TMP/sign.swift" <<'SWIFT'
import CryptoKit
import Foundation
let dir = CommandLine.arguments[1]
let key = Curve25519.Signing.PrivateKey()
let other = Curve25519.Signing.PrivateKey()
let data = FileManager.default.contents(atPath: dir + "/update.zip")!
try key.publicKey.rawRepresentation.base64EncodedString().write(toFile: dir + "/public.key", atomically: true, encoding: .utf8)
try other.publicKey.rawRepresentation.base64EncodedString().write(toFile: dir + "/other.key", atomically: true, encoding: .utf8)
try key.signature(for: data).base64EncodedString().write(toFile: dir + "/signature", atomically: true, encoding: .utf8)
SWIFT
head -c 4096 /dev/urandom >"$TMP/update.zip"
if swift "$TMP/sign.swift" "$TMP" 2>/dev/null; then
    key="$(cat "$TMP/public.key")"
    sig="$(cat "$TMP/signature")"
    verify() {
        swift ./verify-ed-signature.swift "$@" >/dev/null 2>&1
    }
    verify "$key" "$sig" "$TMP/update.zip" || fail "verify: valid signature rejected"
    verify "$(cat "$TMP/other.key")" "$sig" "$TMP/update.zip" && fail "verify: signature accepted with the wrong key"
    bad_sig="$( (printf '%s' "${sig:0:10}"; [[ "${sig:10:1}" == A ]] && printf B || printf A; printf '%s' "${sig:11}") )"
    verify "$key" "$bad_sig" "$TMP/update.zip" && fail "verify: changed signature accepted"
    cp "$TMP/update.zip" "$TMP/changed.zip"
    printf 'x' >>"$TMP/changed.zip"
    verify "$key" "$sig" "$TMP/changed.zip" && fail "verify: changed file accepted"
    verify "AAAA" "$sig" "$TMP/update.zip" && fail "verify: malformed key accepted"
    verify "$key" "" "$TMP/update.zip" && fail "verify: empty signature accepted"
    verify "$key" "$sig" "$TMP/missing.zip" && fail "verify: missing file accepted"
else
    fail "could not make a test signature with CryptoKit"
fi

if ((failures > 0)); then
    echo "appcast-tests: $failures failure(s)" >&2
    exit 1
fi
echo "appcast-tests: all passed"
