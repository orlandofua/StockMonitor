#!/bin/bash
# Tests for next-version.sh. Run by ./test.sh.
set -uo pipefail
cd "$(dirname "$0")"

failures=0
check() {
    local expected="$1"; shift
    local actual
    actual="$(./next-version.sh "$@" 2>/dev/null)"
    if [[ "$actual" != "$expected" ]]; then
        echo "FAIL next-version.sh $* -> '$actual', expected '$expected'" >&2
        failures=$((failures + 1))
    fi
}
check_fails() {
    if ./next-version.sh "$@" >/dev/null 2>&1; then
        echo "FAIL next-version.sh $* succeeded, expected an error" >&2
        failures=$((failures + 1))
    fi
}

# No release label defaults to a patch bump.
check v1.0.1 v1.0.0
check v1.0.1 v1.0.0 enhancement bug
check v1.0.1 v1.0.0 release:patch
# Minor and major bumps reset the lower parts.
check v1.3.0 v1.2.7 release:minor
check v2.0.0 v1.2.7 release:major
# The largest bump wins regardless of label order.
check v2.0.0 v1.2.7 release:minor release:major
check v2.0.0 v1.2.7 release:major release:minor release:patch
check v1.3.0 v1.2.7 release:patch release:minor
# skip-release creates no release, even with other release labels.
check "" v1.2.7 skip-release
check "" v1.2.7 release:major skip-release
check "" "" skip-release
# The first release is v1.0.0.
check v1.0.0 ""
check v1.0.0 "" release:minor
# Multi-digit parts.
check v1.10.0 v1.9.12 release:minor
check v10.0.1 v10.0.0
# Bad input.
check_fails
check_fails 1.0.0
check_fails v1.0
check_fails v1.0.0-beta

if [[ $failures -gt 0 ]]; then
    echo "next-version tests: $failures failed" >&2
    exit 1
fi
echo "next-version tests: all passed"
