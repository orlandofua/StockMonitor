# 13. Use Conventional Commits for commit messages and PR titles

Date: 2026-11-18

## Status

Accepted

## Context

Commit messages in this repo were free-form, so the history could not be scanned by type, and ADR 0009 had to pick release labels over commit-derived versions partly for that reason (issue #18). A single, enforced format makes the history readable and keeps the door open to commit-driven changelogs or version bumps later.

The repo has no Node toolchain, and the release logic is already plain Bash with Bash tests (`scripts/next-version.sh`, `scripts/next-version-tests.sh`). The usual tool, commitlint with husky, would add Node as a dependency for every contributor and for CI only to check one line of text.

The repo allows squash merges, and GitHub then uses the pull request title as the commit message on `main`, so checking only the commits in a pull request is not enough.

## Decision

- New commits and pull request titles follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/): `<type>(<optional scope>)!: <subject>`.
  - Allowed types: `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `build`, `ci`, `chore`, `style`, `revert`, in lower case.
  - The scope is optional, a non-empty word without spaces or colons, such as `(stream)`.
  - `!` before the colon, or a `BREAKING CHANGE:` footer, marks a breaking change. The footer is not validated.
  - Exactly one space follows the colon. The subject is required and does not end with a period. The header is at most 72 characters.
  - Messages that git or GitHub generate are allowed as they are: `Merge ...`, `Revert "..."`, `fixup! `, `squash! `, and `amend! `.
- Check with a small Bash script, `scripts/check-commit-msg.sh`, instead of commitlint. It reads a message file (for the git hook) or stdin (for CI), checks only the header (the first line that is not blank or a `#` comment), and prints the expected format when it fails. `scripts/check-commit-msg-tests.sh`, run by `./test.sh`, covers valid and invalid examples, the hook, and the range check.
- Offer a versioned `commit-msg` hook in `.githooks/`, enabled once per clone with `scripts/install-hooks.sh` (`git config core.hooksPath .githooks`). The hook is a convenience; CI is the gate.
- Add `.github/workflows/commit-lint.yml`, which runs on `pull_request` `opened`, `edited`, `synchronize`, and `reopened`. It checks the pull request title, and every non-merge commit in `base.sha..head.sha` with `scripts/check-commits.sh`, which names each offending commit's SHA and header. It is a separate workflow from `ci.yml` so that editing a title re-runs only this quick Linux job, not the macOS test and build.
- Only new commits are checked. Commits already on `main` are reachable from the pull request's base, so they are outside the range, and history is not rewritten.
- Release versions stay label-driven (ADR 0009). Deriving bumps or changelogs from commit types is a possible follow-up once the convention has been in use for a while.

## Consequences

- Contributors must write commit messages and pull request titles in this format, and reword non-conforming commits (`git commit --amend`, `git rebase -i`) before a pull request can pass the check.
- Release notes are still built from pull request titles, which now carry a type prefix such as `fix:`.
- Enabling the hook sets `core.hooksPath`, which makes git ignore `.git/hooks` in that clone. Contributors with personal hooks must move them into `.githooks` or skip the hook.
- The hook also checks merge commits made with a custom `-m` message, which must then start with `Merge ` or follow the format. CI skips merge commits.
- The check only blocks merging once the owner marks it as a required status check in branch protection.
- A small custom checker can drift from the specification. It deliberately checks only the header, which keeps it short and well tested.
