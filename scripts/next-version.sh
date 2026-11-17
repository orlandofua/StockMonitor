#!/bin/bash
# Prints the next release tag (vMAJOR.MINOR.PATCH) for a merged pull request,
# or nothing when the pull request is labeled skip-release.
#
# Usage: next-version.sh <previous-tag> [label ...]
#   <previous-tag>  latest vX.Y.Z tag, or "" when no release exists yet
#   [label ...]     the pull request's label names
#
# The bump comes from the labels: skip-release wins over release:major, which
# wins over release:minor, which wins over release:patch. With no release
# label the bump is a patch. With no previous tag the first release is v1.0.0.
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <previous-tag> [label ...]" >&2
    exit 2
fi

previous="$1"
shift

bump=patch
for label in "$@"; do
    case "$label" in
        skip-release) exit 0 ;;
        release:major) bump=major ;;
        release:minor) [[ "$bump" == major ]] || bump=minor ;;
    esac
done

if [[ -z "$previous" ]]; then
    echo "v1.0.0"
    exit 0
fi

if [[ ! "$previous" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "error: previous tag '$previous' is not vMAJOR.MINOR.PATCH" >&2
    exit 1
fi
major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

case "$bump" in
    major) echo "v$((major + 1)).0.0" ;;
    minor) echo "v${major}.$((minor + 1)).0" ;;
    patch) echo "v${major}.${minor}.$((patch + 1))" ;;
esac
