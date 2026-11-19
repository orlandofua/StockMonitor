#!/bin/bash
# Adds one release to the Sparkle update feed (appcast.xml). Called by the
# release workflow; see ADR 0015.
#
# Usage: add-appcast-item.sh <appcast.xml>
#
# The file is created if it does not exist. The new item goes first, above
# older releases. The values come from the environment:
#
# VERSION       semver without the "v", becomes sparkle:shortVersionString
# BUILD_NUMBER  the build's CFBundleVersion, becomes sparkle:version
# ZIP_URL       https URL of the release zip, the enclosure's url
# LENGTH        size of the zip in bytes
# ED_SIGNATURE  base64 EdDSA signature of the zip from sign_update
# NOTES_URL     https URL of the release notes (the GitHub release page)
# PUB_DATE      RFC 822 date of the release (default: now)
#
# Exits 1 with a message on stderr, and leaves the file unchanged, if a value
# is malformed, the build number or version is already in the feed, or the
# result is not well-formed XML. A release must never ship a broken feed entry.
set -euo pipefail

MIN_SYSTEM_VERSION="13.0.0"
FEED_URL="https://orlandofua.github.io/StockMonitor/appcast.xml"

fail() {
    echo "error: $1" >&2
    exit 1
}

[[ $# -eq 1 ]] || fail "usage: add-appcast-item.sh <appcast.xml>"
FEED="$1"

VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
ZIP_URL="${ZIP_URL:-}"
LENGTH="${LENGTH:-}"
ED_SIGNATURE="${ED_SIGNATURE:-}"
NOTES_URL="${NOTES_URL:-}"
PUB_DATE="${PUB_DATE:-$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')}"

# An https URL with no whitespace and no characters that would need XML escaping.
url_pattern="^https://[^[:space:]<>&\"']+\$"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION '$VERSION' must look like 1.2.3"
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || fail "BUILD_NUMBER '$BUILD_NUMBER' must be a whole number"
[[ "$ZIP_URL" =~ $url_pattern ]] || fail "ZIP_URL '$ZIP_URL' must be an https URL"
[[ "$NOTES_URL" =~ $url_pattern ]] || fail "NOTES_URL '$NOTES_URL' must be an https URL"
[[ "$LENGTH" =~ ^[1-9][0-9]*$ ]] || fail "LENGTH '$LENGTH' must be a positive whole number"
# An ed25519 signature is 64 bytes, which is 88 base64 characters ending in '=='.
[[ "$ED_SIGNATURE" =~ ^[A-Za-z0-9+/]{86}==$ ]] ||
    fail "ED_SIGNATURE must be a base64 ed25519 signature (88 characters)"
[[ "$PUB_DATE" =~ ^[A-Za-z0-9,:+\ -]+$ ]] || fail "PUB_DATE '$PUB_DATE' must be an RFC 822 date"

if [[ -e "$FEED" ]]; then
    xmllint --noout "$FEED" 2>/dev/null || fail "$FEED is not well-formed XML"
    current="$(cat "$FEED")"
else
    current="<?xml version=\"1.0\" encoding=\"utf-8\"?>
<rss version=\"2.0\" xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\">
    <channel>
        <title>StockMonitor</title>
        <link>$FEED_URL</link>
        <description>Updates for StockMonitor</description>
        <language>en</language>
    </channel>
</rss>"
fi

# Sparkle picks the item with the highest sparkle:version, so a repeated build
# number or version would make the feed ambiguous.
if grep -q "<sparkle:version>$BUILD_NUMBER</sparkle:version>" <<<"$current"; then
    fail "build $BUILD_NUMBER is already in $FEED"
fi
if grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" <<<"$current"; then
    fail "version $VERSION is already in $FEED"
fi
[[ "$(grep -c '</channel>' <<<"$current")" -eq 1 ]] || fail "$FEED must have exactly one </channel>"

item="        <item>
            <title>Version $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD_NUMBER</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MIN_SYSTEM_VERSION</sparkle:minimumSystemVersion>
            <sparkle:releaseNotesLink>$NOTES_URL</sparkle:releaseNotesLink>
            <enclosure url=\"$ZIP_URL\" length=\"$LENGTH\" type=\"application/octet-stream\" sparkle:edSignature=\"$ED_SIGNATURE\"/>
        </item>"

# Insert the item above the first existing item, or above </channel> if the
# feed has none yet, so the newest release comes first.
tmp="$(mktemp "${TMPDIR:-/tmp}/appcast.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
ITEM="$item" awk '
    !done && (/^[[:space:]]*<item>/ || /<\/channel>/) { print ENVIRON["ITEM"]; done = 1 }
    { print }
' <<<"$current" >"$tmp"

xmllint --noout "$tmp" 2>/dev/null || fail "the updated feed is not well-formed XML"
before="$(grep -c '<item>' <<<"$current" || true)"
after="$(grep -c '<item>' "$tmp" || true)"
[[ "$after" -eq $((before + 1)) ]] || fail "expected $((before + 1)) items after adding one, found $after"

cat "$tmp" >"$FEED"
