#!/bin/bash
# Checks that a commit message (or PR title) follows Conventional Commits 1.0.0.
# See docs/adr/0013-use-conventional-commits.md and CONTRIBUTING.md.
#
# Usage:
#   scripts/check-commit-msg.sh <message-file>   (git commit-msg hook)
#   printf '%s\n' "$TITLE" | scripts/check-commit-msg.sh   (CI, stdin)
#
# Only the header (first non-empty, non-comment line) is checked. Exits 0 when
# the message is valid, 1 with an explanation on stderr when it is not.
set -euo pipefail

TYPES="feat|fix|docs|test|refactor|perf|build|ci|chore|style|revert"
MAX_HEADER=72

if [[ $# -gt 1 ]]; then
    echo "usage: $0 [message-file]" >&2
    exit 2
fi
if [[ $# -eq 1 ]]; then
    message="$(cat -- "$1")"
else
    message="$(cat)"
fi

# The header is the first line that is neither blank nor a git comment.
header=""
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" == \#* ]] && continue
    [[ -z "${line//[[:space:]]/}" ]] && continue
    header="$line"
    break
done <<<"$message"
# Ignore trailing whitespace, as git does.
header="${header%"${header##*[![:space:]]}"}"

fail() {
    {
        echo "error: $1"
        [[ -n "$header" ]] && echo "  got:      $header"
        echo "  expected: <type>(<optional scope>)!: <subject>"
        echo "  types:    ${TYPES//|/, }"
        echo "  example:  fix(stream): reconnect after wake"
        echo "See CONTRIBUTING.md (Commit messages) for details."
    } >&2
    exit 1
}

[[ -z "$header" ]] && fail "the commit message is empty"

# Messages that git or GitHub generate are allowed as they are.
case "$header" in
    "Merge "* | "Revert \""* | "fixup! "* | "squash! "* | "amend! "*) exit 0 ;;
esac

if [[ ${#header} -gt $MAX_HEADER ]]; then
    fail "the header is ${#header} characters long; the limit is $MAX_HEADER"
fi

prefix_re="^([a-zA-Z]+)(\([^()]*\))?(!)?:"
if [[ ! "$header" =~ $prefix_re ]]; then
    fail "the header does not start with a type such as 'feat:' or 'fix(scope):'"
fi
type="${BASH_REMATCH[1]}"
scope="${BASH_REMATCH[2]}"
if [[ ! "$type" =~ ^($TYPES)$ ]]; then
    fail "unknown type '$type'"
fi
if [[ "$scope" == "()" || "$scope" =~ [[:space:]] ]]; then
    fail "the scope must be a non-empty word without spaces, such as '(stream)'"
fi

subject="${header#*:}"
if [[ -z "${subject//[[:space:]]/}" ]]; then
    fail "the subject after the colon is empty"
fi
if [[ "$subject" != " "* || "$subject" == "  "* ]]; then
    fail "put exactly one space between the colon and the subject"
fi
if [[ "$subject" == *. ]]; then
    fail "the subject must not end with a period"
fi
exit 0
