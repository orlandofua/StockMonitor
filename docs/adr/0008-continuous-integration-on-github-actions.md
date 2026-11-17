# 8. Continuous integration on GitHub Actions

Date: 2026-11-17

## Status

Accepted

## Context

Until now nothing checked that a pull request builds or that its tests pass before it is merged. The build and tests already run from two scripts, `./test.sh` and `./build.sh` (ADR 0002), and the planned release workflow should only run on code that has been checked.

The tests use Swift Testing, which ships with Xcode 16 and later. The app is macOS-only (AppKit), so it cannot build on a Linux runner.

## Decision

- Add `.github/workflows/ci.yml`, a workflow named "CI" that runs on every `pull_request` and on every `push` to `main`.
- Run it on GitHub's `macos-15` runner, whose default Xcode 16 toolchain includes Swift Testing.
- Run the same scripts developers run locally, `./test.sh` and then `./build.sh`, so CI and local results agree. Tests run first so a failing test stops the job before the release build.
- Cache `.build` with `actions/cache`, keyed on `Package.swift`, `Package.resolved`, and the files under `Sources/` and `Tests/`. A prefix restore key lets a changed source tree start from the most recent cache and rebuild incrementally.
- Give the job read-only repository permissions, a 15-minute timeout, and cancel older runs for the same branch when a new commit arrives.

## Consequences

- A PR shows a "CI" check, and a failing test or build fails it.
- Every PR uses macOS runner minutes. The cache keeps warm runs short.
- CI uses Xcode's toolchain while the development machine may use only the Command Line Tools. `test.sh` already handles both.
- Linting, releases, and code signing are not part of CI. They can be added as separate jobs or workflows later.
