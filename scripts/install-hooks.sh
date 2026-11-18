#!/bin/bash
# Points git at the versioned hooks in .githooks for this clone.
# Note: this replaces .git/hooks, so move any personal hooks into .githooks
# (or call them from there) if you rely on them.
set -euo pipefail
cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
echo "Git hooks enabled from .githooks (core.hooksPath=.githooks)."
