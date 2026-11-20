# 16. Universal binary for releases

Date: 2026-11-20

## Status

Accepted. Supersedes the Intel part of [0010](0010-distribute-unnotarized-builds-on-github-releases.md).

## Context

ADR 0010 shipped arm64-only release builds, because `swift build -c release` on the `macos-15` runner builds only for the runner's architecture. Intel Macs could not run the downloaded app, and so could not receive in-app updates either (ADR 0015). Issue #33 asks for one download that runs on both.

SwiftPM builds a universal executable when given `--arch arm64 --arch x86_64`. A multi-architecture build uses a different build system and writes its products to a different directory than a single-architecture build (for example `.build/out/Products/Release` or `.build/apple/Products/Release`, depending on the SwiftPM version), so the path cannot be hard-coded. `swift build --show-bin-path` with the same arguments returns it.

Sparkle's SwiftPM artifact is the `macos-arm64_x86_64` slice of `Sparkle.xcframework`, so the embedded framework and its helpers are already universal. Building universal takes longer than building for one architecture.

## Decision

- `build.sh` reads an optional `ARCHS` variable, a space-separated list such as `arm64 x86_64`, and passes one `--arch` per entry to `swift build`. It copies the executable from the directory that `--show-bin-path` reports.
- When `ARCHS` is set, `build.sh` checks with `lipo -verify_arch` that the executable and `Sparkle.framework` both contain every listed architecture, and fails otherwise. A release missing a slice would not launch, or not update, on Macs of that architecture.
- When `ARCHS` is unset, `build.sh` builds for the host architecture only, as before. Local development stays fast.
- The release workflow sets `ARCHS: arm64 x86_64` and prints `lipo -archs` of the built executable in the log.
- CI builds the same universal app on every pull request, so a change that breaks the `x86_64` slice fails before merge rather than in the release job.
- Downloaded builds support macOS 13 or later on Apple silicon and Intel. `LSMinimumSystemVersion` stays 13.0, and both slices are built with a 13.0 deployment target.
- There is one download for both architectures. Separate per-architecture downloads are out of scope.

## Consequences

- Intel Macs can run the downloaded app and receive updates through the same feed and the same signed zip.
- The zip is larger, roughly twice the executable size, and CI and release builds take longer.
- The runners are Apple silicon, so the `x86_64` slice is built and checked with `lipo`, but CI never runs it. It can run under Rosetta on an Apple silicon Mac for a smoke test. Launching on a real Intel Mac with macOS 13 or later, and updating an Intel copy to the next release, are manual checks.
- Apple has deprecated `x86_64` for new deployment targets, and the build prints a warning about it. When a future toolchain drops `x86_64` for a macOS 13 deployment target, this decision needs revisiting.
