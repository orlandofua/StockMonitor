# 9. Release on merge with label-driven semantic versions

Date: 2026-11-17

## Status

Accepted

## Context

There was no way to ship a build. The version was hard-coded as `1.0` in `build.sh`, and nothing produced a downloadable app. Every change reaches `main` through a reviewed pull request that CI has checked (ADR 0008), so a merged pull request is a natural release point. Commit messages in this repo are free-form, so versions cannot be derived from conventional commits without adding a new commit rule and a parser.

Note (2026-11-18): ADR [0013](0013-use-conventional-commits.md) has since made Conventional Commits the rule for new commits and pull request titles. The label-driven decision below is unchanged.

## Decision

- Add `.github/workflows/release.yml`, triggered by `pull_request` `closed` on `main`, that runs only when the pull request was merged. The event carries the pull request's labels, so no API lookup is needed.
- Version with semver tags `vMAJOR.MINOR.PATCH`. The pull request's labels pick the bump: `release:major`, `release:minor`, or `release:patch`, with patch as the default. `skip-release` creates no release. When several labels are present, `skip-release` wins, then the largest bump. The first release, when no tag exists, is `v1.0.0`.
- The previous release is the highest strict `vMAJOR.MINOR.PATCH` tag reachable from the merge commit (`scripts/previous-tag.sh`). Pre-release or other hand-made tags such as `v1.1.0-beta` are ignored, so they cannot block releases. Tag parts are read as decimal even with leading zeros.
- Keep the bump logic in `scripts/next-version.sh` and the tag lookup in `scripts/previous-tag.sh`, both tested by `scripts/next-version-tests.sh`, which `./test.sh` runs.
- The job checks out the merge commit with full history, runs `./test.sh`, computes the tag, builds with `VERSION=x.y.z ./build.sh`, zips the app with `ditto` (keeping bundle metadata), writes a `.sha256` file, and publishes both with `gh release create --generate-notes`. `.github/release.yml` groups the notes by label.
- `build.sh` reads `VERSION` (default `1.0`) into `CFBundleShortVersionString` and `BUILD_NUMBER` (default the workflow run number, else `1`) into `CFBundleVersion`.
- Releases run one at a time (job-level `concurrency: release`, no cancellation) so two merges never take the same tag. The group is set on the job, not the workflow, so closes that skip the job (unmerged or `skip-release`) never enter it.

## Consequences

- Every merged pull request without `skip-release` produces a downloadable, versioned `StockMonitor.app` with release notes.
- Authors must pick a release label; forgetting one gives a patch release.
- The app is ad-hoc signed and not notarized, so users must remove the quarantine attribute before the first launch. Developer ID signing and notarization are a separate decision.
- Pull requests from forks get a read-only token and cannot create releases. If outside contributions become common, switch the trigger to `push` on `main` and look up the pull request for the commit.
- GitHub keeps at most one pending run per concurrency group. If three or more releasable pull requests are merged while one release is still running, the newer pending run replaces the older one, so the middle pull request gets no release of its own. Its changes still ship in the next release, but its version bump is lost.
- Tests run again in the release job even though CI already ran them on the pull request, because the merge commit can differ from the tested head.
