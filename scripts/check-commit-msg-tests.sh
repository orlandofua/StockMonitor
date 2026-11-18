#!/bin/bash
# Tests for check-commit-msg.sh, check-commits.sh, and .githooks/commit-msg.
# Run by ./test.sh.
set -uo pipefail
cd "$(dirname "$0")"
SCRIPTS="$(pwd)"
HOOKS="$(cd ../.githooks && pwd)"

failures=0
fail() {
    echo "FAIL $*" >&2
    failures=$((failures + 1))
}
accepts() {
    printf '%b' "$1" | ./check-commit-msg.sh >/dev/null 2>&1 || fail "check-commit-msg.sh rejected '$1'"
}
# rejects <message> <text the error must contain>
rejects() {
    local output
    if output="$(printf '%b' "$1" | ./check-commit-msg.sh 2>&1)"; then
        fail "check-commit-msg.sh accepted '$1'"
        return
    fi
    [[ "$output" == *"$2"* ]] || fail "check-commit-msg.sh '$1' error lacks '$2': $output"
    [[ "$output" == *"expected: <type>(<optional scope>)!: <subject>"* ]] ||
        fail "check-commit-msg.sh '$1' error does not show the expected format"
}

# Valid headers.
accepts 'feat: add launch at login'
accepts 'fix(stream): reconnect after wake'
accepts 'feat!: drop macOS 13'
accepts 'feat(api)!: drop the v7 chart endpoint'
accepts 'feat: drop macOS 13\n\nBREAKING CHANGE: macOS 14 or later is now required.'
for type in feat fix docs test refactor perf build ci chore style revert; do
    accepts "$type: change something"
done
accepts 'ci: publish a release when a PR merges to main'
# Body, trailing newline, CRLF, and trailing spaces do not matter.
accepts 'fix: handle sleep\n\nLonger explanation.\nCo-Authored-By: A <a@example.com>\n'
accepts 'fix: handle sleep\r\n'
accepts 'fix: handle sleep   '
# Git comments and leading blank lines are skipped, as in the hook's message file.
accepts '\n# Please enter the commit message\nfix: handle sleep\n# On branch main\n'
# Exactly 72 characters is allowed.
accepts "feat: $(printf 'a%.0s' {1..66})"
# Messages that git and GitHub generate.
accepts 'Merge pull request #1 from user/branch'
accepts "Merge branch 'main' into feature/x"
accepts 'Revert "feat: x"\n\nThis reverts commit abc123.'
accepts 'fixup! feat: x'
accepts 'squash! feat: x'
accepts 'amend! feat: x'

# Invalid headers.
rejects 'Add launch at login' "does not start with a type"
rejects 'bad message' "does not start with a type"
rejects 'feature: add x' "unknown type 'feature'"
rejects 'Feat: add x' "unknown type 'Feat'"
rejects 'fix:' "subject after the colon is empty"
rejects 'fix:   ' "subject after the colon is empty"
rejects 'fix(stream):' "subject after the colon is empty"
rejects 'fix: add x.' "must not end with a period"
rejects 'fix:add x' "exactly one space"
rejects 'fix:  add x' "exactly one space"
rejects 'fix(): add x' "scope must be"
rejects 'fix(my scope): add x' "scope must be"
rejects 'fix(a:b): add x' "scope must be"
rejects $'fix: \tadd x' "exactly one space"
rejects $'fix:\tadd x' "exactly one space"
rejects 'fix (stream): add x' "does not start with a type"
rejects "feat: $(printf 'a%.0s' {1..67})" "73 characters long"
rejects '' "empty"
rejects '# only a comment\n' "empty"
# The exemptions are exact prefixes.
rejects 'Merged the branch' "does not start with a type"
rejects 'fixup feat: x' "does not start with a type"

# A message file argument works like stdin (the hook passes a file).
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf 'fix: from a file\n' >"$tmp/good"
printf 'from a file\n' >"$tmp/bad"
./check-commit-msg.sh "$tmp/good" >/dev/null 2>&1 || fail "check-commit-msg.sh rejected a valid message file"
./check-commit-msg.sh "$tmp/bad" >/dev/null 2>&1 && fail "check-commit-msg.sh accepted an invalid message file"

# The hook and check-commits.sh, in a scratch repository.
repo="$tmp/repo"
git init -q -b main "$repo"
g() {
    git -C "$repo" -c user.name=Test -c user.email=test@example.com \
        -c commit.gpgsign=false -c core.hooksPath="$HOOKS" "$@"
}
g commit -q --allow-empty --no-verify -m "Old free-form commit on main"

# The hook refuses a bad message and allows a good one.
g commit -q --allow-empty -m "bad message" >/dev/null 2>&1 && fail "commit-msg hook accepted 'bad message'"
g commit -q --allow-empty -m "chore: test hook" >/dev/null 2>&1 || fail "commit-msg hook rejected 'chore: test hook'"

# Commits on main, including ones merged into the branch later, are outside
# the main..topic range, and merge commits are skipped.
g switch -q -c topic
g commit -q --allow-empty -m "feat: on topic"
g switch -q main
g commit -q --allow-empty --no-verify -m "Another old commit"
g switch -q topic
g merge -q --no-ff --no-edit main
output="$(cd "$repo" && "$SCRIPTS/check-commits.sh" main topic 2>&1)" ||
    fail "check-commits.sh failed on conforming commits: $output"

# A non-conforming commit fails, and the log names its SHA and message.
g commit -q --allow-empty --no-verify -m "Fix the thing"
bad_sha="$(g rev-parse HEAD)"
if output="$(cd "$repo" && "$SCRIPTS/check-commits.sh" main topic 2>&1)"; then
    fail "check-commits.sh passed a range with a bad commit"
fi
[[ "$output" == *"$bad_sha"* ]] || fail "check-commits.sh output lacks the bad SHA: $output"
[[ "$output" == *"Fix the thing"* ]] || fail "check-commits.sh output lacks the bad message: $output"
[[ "$output" == *"1 of 2 commits"* ]] || fail "check-commits.sh output lacks the count: $output"

if [[ $failures -gt 0 ]]; then
    echo "commit message tests: $failures failed" >&2
    exit 1
fi
echo "commit message tests: all passed"
