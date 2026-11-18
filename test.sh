#!/bin/bash
# Runs the unit tests. With only the Command Line Tools installed (no Xcode),
# SwiftPM does not find the Swift Testing macro plugin on its own, so point it there.
set -euo pipefail
cd "$(dirname "$0")"

./scripts/next-version-tests.sh
./scripts/check-commit-msg-tests.sh

PLUGINS=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
if [[ -d "$PLUGINS" ]] && ! xcode-select -p | grep -q Xcode.app; then
    exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
fi
exec swift test "$@"
