#!/bin/bash
# Checks every non-merge commit in BASE..HEAD with check-commit-msg.sh.
# CI runs it on each pull request; commits already reachable from BASE (such
# as the history of main) are never checked.
#
# Usage: scripts/check-commits.sh <base> <head>
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <base> <head>" >&2
    exit 2
fi
base="$1" head="$2"
checker="$(cd "$(dirname "$0")" && pwd)/check-commit-msg.sh"

shas="$(git rev-list --no-merges --reverse "$base..$head")"
count=0 failures=0
for sha in $shas; do
    count=$((count + 1))
    if ! errors="$(git log -1 --format=%B "$sha" | "$checker" 2>&1)"; then
        failures=$((failures + 1))
        echo "::error::Commit $(git log -1 --format='%h %s' "$sha") does not follow Conventional Commits" >&2
        echo "Commit $sha" >&2
        echo "$errors" | sed 's/^/  /' >&2
    fi
done

if [[ $failures -gt 0 ]]; then
    echo "$failures of $count commits do not follow Conventional Commits." >&2
    echo "Reword them with 'git commit --amend' (last commit) or 'git rebase -i $base' and push again." >&2
    exit 1
fi
echo "All $count commits follow Conventional Commits."
