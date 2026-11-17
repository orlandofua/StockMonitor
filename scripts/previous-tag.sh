#!/bin/bash
# Reads tag names on stdin (one per line) and prints the highest strict
# vMAJOR.MINOR.PATCH tag, or nothing when there is none. Pre-release and other
# non-semver tags such as v1.1.0-beta or v1.0.0.1 are ignored, so a hand-made
# tag cannot block releases.
#
# Usage: git tag --merged HEAD | previous-tag.sh
set -euo pipefail

grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sed 's/^v//' \
    | sort -t. -k1,1n -k2,2n -k3,3n \
    | tail -n 1 \
    | sed 's/^/v/' \
    || true
