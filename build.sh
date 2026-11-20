#!/bin/bash
# Builds StockMonitor.app (release) into ./build
#
# VERSION                goes into CFBundleShortVersionString (default 1.0)
# BUILD_NUMBER           goes into CFBundleVersion (default: GITHUB_RUN_NUMBER, else 1)
# SPARKLE_FEED_URL       goes into SUFeedURL. Leave it unset for a build that
#                        never checks for updates (the default).
# SPARKLE_PUBLIC_ED_KEY  goes into SUPublicEDKey. Required with SPARKLE_FEED_URL.
# ARCHS                  space-separated architectures, e.g. "arm64 x86_64" for a
#                        universal app (what releases ship). Leave it unset to
#                        build for this Mac's architecture only, which is faster.
#
# See scripts/make-info-plist.sh for the Info.plist, and ADR 0015 for Sparkle.
set -euo pipefail
cd "$(dirname "$0")"

export VERSION="${VERSION:-1.0}"
export BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
export SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
export SPARKLE_PUBLIC_ED_KEY="${SPARKLE_PUBLIC_ED_KEY:-}"
ARCHS="${ARCHS:-}"

# Check the Info.plist inputs before spending time on the build.
INFO_PLIST="$(scripts/make-info-plist.sh)"

# SwiftPM does not add an rpath for embedded frameworks, so the executable
# would not find Contents/Frameworks/Sparkle.framework without this one.
BUILD_ARGS=(-c release)
for arch in $ARCHS; do
    BUILD_ARGS+=(--arch "$arch")
done
swift build "${BUILD_ARGS[@]}" -Xlinker -rpath -Xlinker @executable_path/../Frameworks
# A multi-architecture build writes to a different directory than a
# single-architecture one, so ask SwiftPM where the executable is.
BIN_PATH="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

# Sparkle's SwiftPM artifact ships an ad-hoc signed framework. Copy it with
# ditto, which keeps the Versions/Current symlinks and the framework's own
# signature, so it does not need to be re-signed (spike #28, ADR 0015).
FRAMEWORK=.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework
if [[ ! -d "$FRAMEWORK" ]]; then
    echo "error: $FRAMEWORK not found; did SwiftPM resolve the Sparkle package?" >&2
    exit 1
fi

APP=build/StockMonitor.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
cp "$BIN_PATH/StockMonitor" "$APP/Contents/MacOS/"
ditto "$FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
printf '%s\n' "$INFO_PLIST" > "$APP/Contents/Info.plist"

# Ad-hoc signature, no Hardened Runtime: with it, Library Validation stops an
# ad-hoc app from loading the framework (ADR 0015). Releases re-sign the app
# with Developer ID and the Hardened Runtime in scripts/sign-app.sh (ADR 0017). Signing the bundle seals
# the framework inside it. A signing failure must fail the build, because a
# broken signature breaks updates.
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

# Every requested architecture must be in the executable and in Sparkle, or
# Macs of the missing architecture can neither launch the app nor update it.
for arch in $ARCHS; do
    for binary in "$APP/Contents/MacOS/StockMonitor" "$APP/Contents/Frameworks/Sparkle.framework/Sparkle"; do
        if ! lipo "$binary" -verify_arch "$arch"; then
            echo "error: $binary has no $arch slice (it has: $(lipo -archs "$binary"))" >&2
            exit 1
        fi
    done
done

echo "Built $APP (version $VERSION, build $BUILD_NUMBER, architectures: $(lipo -archs "$APP/Contents/MacOS/StockMonitor"))"
if [[ -n "$SPARKLE_FEED_URL" ]]; then
    echo "Update feed: $SPARKLE_FEED_URL"
else
    echo "No update feed set; this build never checks for updates."
fi
