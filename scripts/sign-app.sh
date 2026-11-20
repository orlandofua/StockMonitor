#!/bin/bash
# Usage: sign-app.sh <path/to/StockMonitor.app> <identity>
#
# Re-signs a bundle made by build.sh with <identity> and the Hardened Runtime,
# which notarization requires (ADR 0017). The release passes its
# "Developer ID Application: ..." identity. Pass "-" to sign ad hoc, for local
# checks and tests; an ad-hoc signature gets no secure timestamp.
set -euo pipefail

if (($# != 2)) || [[ -z "$1" || -z "$2" ]]; then
    echo "usage: $0 <path/to/StockMonitor.app> <identity>" >&2
    exit 2
fi
APP="$1"
IDENTITY="$2"

if [[ "$IDENTITY" == "-" ]]; then
    TIMESTAMP=--timestamp=none
else
    TIMESTAMP=--timestamp
fi

sign() {
    codesign --force --sign "$IDENTITY" --options runtime "$TIMESTAMP" "$@"
}

# Sign inside out: each piece of code before the bundle that contains it, since
# a signature seals the signatures of everything nested inside it. The order
# and paths follow Sparkle's "Sandboxing and code signing" docs.
FW="$APP/Contents/Frameworks/Sparkle.framework"
sign "$FW/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$FW/Versions/B/XPCServices/Downloader.xpc"
sign "$FW/Versions/B/Autoupdate"
sign "$FW/Versions/B/Updater.app"
sign "$FW"
sign "$APP"
codesign --verify --deep --strict "$APP"
