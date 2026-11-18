# 10. Distribute un-notarized builds on GitHub Releases

Date: 2026-11-18

## Status

Accepted

## Context

ADR 0009 made every merged pull request publish a versioned GitHub Release. It decided how versions are numbered and when a release is made, but not how the app reaches users or what they must do to run it.

Release builds are made on GitHub's `macos-15` runner by `./build.sh`, which ad-hoc signs the bundle (`codesign --sign -`). There is no Apple Developer ID certificate or notarization credential in the repository, so the app cannot be notarized. When a browser downloads it, macOS adds the `com.apple.quarantine` attribute, and Gatekeeper blocks the first launch of a quarantined app that is not notarized. macOS 13 and 14 let the user bypass this with Control-click > Open. macOS 15 removed that shortcut, leaving System Settings > Privacy & Security > Open Anyway, or removing the attribute with `xattr`.

`swift build -c release` on the runner builds for the runner's architecture only, so the published binary is arm64.

## Decision

- Distribute the app only as GitHub Release assets: `StockMonitor-vX.Y.Z.zip`, made with `ditto -c -k --sequesterRsrc --keepParent` so the bundle's signature and metadata survive, and `StockMonitor-vX.Y.Z.zip.sha256` for checking the download. No DMG, installer package, Homebrew cask, or auto-updater for now.
- Ship the ad-hoc signed, un-notarized build, and document in the README how to open it past Gatekeeper: Open Anyway in System Settings (all supported versions), Control-click > Open (macOS 13 and 14), or `xattr -dr com.apple.quarantine` (all supported versions).
- Support macOS 13 or later on Apple silicon for downloaded builds, matching `LSMinimumSystemVersion` 13.0. Intel Macs build from source.
- Developer ID signing and notarization are deferred to issue #12. When they land, a new ADR supersedes this one and the README drops the Gatekeeper steps.

## Consequences

- Releases need no Apple Developer Program membership and no secrets, so any merged pull request can ship.
- Every user must take one extra, security-related step on first launch and again after each update, and must trust the download without Apple's malware check. The SHA-256 file only proves the zip matches what the workflow uploaded.
- Users get no update notice. They check the Releases page and replace the app by hand. Settings survive because they live in `UserDefaults` (ADR 0007).
- Intel Mac users cannot use the downloaded build until the release job builds a universal binary.
- The Gatekeeper wording and bypass steps depend on the macOS version and may change in future releases, so the README needs checking when a new macOS ships.
